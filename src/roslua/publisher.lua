
----------------------------------------------------------------------------
--  publisher.lua - Topic publisher
--
--  Created: Mon Jul 27 17:04:24 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010       Intel Research Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Topic publisher.
-- This module contains the Publisher class to publish to a ROS topic. The
-- class is used to publish messages to a specified topic. It is created using
-- the function <code>roslua.publisher()</code>.
-- <br /><br />
-- The main interaction for applications is using the <code>publish()</code>
-- method to send new messages. The publisher spins automatically when created
-- using <code>roslua.publisher()</code>.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Labs Pittsburgh,
-- SRI International
-- @release Released under BSD license
module("roslua.publisher", package.seeall)

require("roslua")
require("roslua.msg_spec")

Publisher = {DEBUG = false,
	     SUBSTATE_CONNECTED = 1,
	     SUBSTATE_HEADER_SENT = 2,
	     SUBSTATE_HEADER_RECEIVED = 3,
	     SUBSTATE_COMMUNICATING = 4,
	     SUBSTATE_FAILED = 5,
	     
	     SUBSTATE_TO_STR = { "SUBSTATE_CONNECTED",
				 "SUBSTATE_HEADER_SENT",
				 "SUBSTATE_HEADER_RECEIVED",
				 "SUBSTATE_COMMUNICATING",
				 "SUBSTATE_FAILED" }
}

--- Constructor.
-- Create a new publisher instance.
-- @param topic topic to publish to
-- @param type type of the topic
-- @param latching true to create latching publisher,
-- false or nil to create regular publisher. A latching publisher keeps
-- the last sent message in a buffer and sends it to connecting nodes.
function Publisher:new(topic, type, latching)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = roslua.resolve(topic)
   o.latching    = latching or false
   if roslua.msg_spec.is_msgspec(type) then
      o.type    = type.type
      o.msgspec = type
   elseif _G.type(type) == "string" then
      o.type    = type
      o.msgspec = roslua.get_msgspec(type)
   else
      error("Publisher: topic type must be a string or message spec")
   end
   assert(o.type, "Publisher: topic type is missing")
   assert(o.topic, "Publisher: topic name is missing")
   assert(_G.type(o.topic) == "string", "Publisher: topic name must be a string")

   o.subscribers = {}
   o.waiting_subscribers = 0
   o.failed_subscribers = 0

   -- connect to all publishers
   o:start_server()

   return o
end

--- Finalize instance.
function Publisher:finalize()
   for _, s in ipairs(self.subscribers) do
      if s.connection then
	 s.connection:close()
      end
   end
   self.subscribers = {}
   self.waiting_subscribers = 0
end

--- Start the internal TCP server to accept ROS subscriber connections.
function Publisher:start_server()
   self.server = roslua.tcpros.TcpRosPubSubConnection:new()
   self.server.name = string.format("Publisher[%s:%s]", self.type, self.topic)
   self.server:bind()
   self.address, self.port = self.server:get_ip_port()
end


--- Wait for a subscriber to connect.
function Publisher:wait_for_subscriber()
   local have_subscriber = false
   repeat
      assert(not roslua.quit, "Aborted while waiting for subscriber for topic "
	     .. self.topic)
      for _, _ in ipairs(self.subscribers) do
	 have_subscriber = true
	 break
      end
      roslua.spin()
   until have_subscriber
end

-- (internal) Called by spin() to accept new connections.
function Publisher:accept_connections()
   local conns = self.server:accept()
   for _, c in ipairs(conns) do
      table.insert(self.subscribers, {state=self.SUBSTATE_CONNECTED, connection=c})
   end
   self.waiting_subscribers = self.waiting_subscribers + #conns
end

-- (internal) Called by spin to process waiting subscribers.
function Publisher:process_subscribers()
   for _, s in ipairs(self.subscribers) do
      if s.state < self.SUBSTATE_COMMUNICATING then
	 local old_state = s.state
	 if s.state == self.SUBSTATE_CONNECTED then
            if self.DEBUG then
               print_debug("Publisher[%s]: accepting connection from %s:%s",
                           self.topic, self.server:get_ip_port())
            end

	    s.md5sum = self.msgspec:md5()
	    s.connection:send_header{callerid=roslua.node_name,
				     topic=self.topic,
				     type=self.type,
				     md5sum=s.md5sum}

	    s.header_receive_coroutine =
	       coroutine.create(function ()
				   return s.connection:receive_header(true)
				end)
	    s.state = self.SUBSTATE_HEADER_SENT

	 elseif s.state == self.SUBSTATE_HEADER_SENT then
	    local ok, data_err =
               coroutine.resume(s.header_receive_coroutine)
	    if not ok or not data_err then
	       print_warn("Publisher[%s]: failed to receive header: %s",
			  self.topic, data_err)
	       s.state = self.SUBSTATE_FAILED
	    elseif coroutine.status(s.header_receive_coroutine) == "dead" then
	       -- finished
	       s.header_receive_coroutine = nil
	       s.state = self.SUBSTATE_HEADER_RECEIVED
	    end

	 elseif s.state == self.SUBSTATE_HEADER_RECEIVED then
	    if self.DEBUG then
	       print_debug("Publisher[%s::%s]: subscriber connection from %s "..
			   "(%s:%d)", self.topic, self.type,
			s.connection.header.callerid,
			s.connection.socket:getpeername())
	    end

	    if s.connection.header.md5sum ~= "*" and
	       s.connection.header.md5sum ~= s.md5sum
	    then
	       print_warn("Publisher[%s::%s]: received non-matching MD5 "..
			  "(here: %s there: %s) sum from %s, disconnecting and "..
			  "ignoring", self.topic, self.type, s.md5sum,
		       s.connection.header.md5sum, s.connection.header.callerid)
	       s.state = self.SUBSTATE_FAILED
	    elseif self.latching and self.latched_message then
	       if self.DEBUG then
		  print_warn("Publisher[%s::%s]: sending latched message",
			     self.type, self.topic)
	       end
	       local ok, error = s.connection:send(self.latched_message.serialized)
	       if not ok then
		  local ip, port = s.connection:get_ip_port()
		  print_warn("Publisher[%s::%s]: failed sending to %s:%s "..
			     "for latched message (%s)",
			  self.type, self.topic, ip, port, error)
		  s.state = self.SUBSTATE_FAILED
	       end
	    end
	    if s.state ~= self.SUBSTATE_FAILED then
	       if self.DEBUG then
		  printf("Publisher[%s::%s]: accepted connection from %s",
			 self.type, self.topic, s.connection.header.callerid)
	       end
	       s.callerid = s.connection.header.callerid
	       s.connection.name = string.format("Publisher[%s:%s]/%s", self.type,
						 self.topic, s.callerid)
	       s.state = self.SUBSTATE_COMMUNICATING
	       self.waiting_subscribers = self.waiting_subscribers - 1
	    end
	 end

	 if s.state == self.SUBSTATE_FAILED then
	    self.waiting_subscribers = self.waiting_subscribers - 1
	    self.failed_subscribers = self.failed_subscribers + 1
	    print_warn("Publisher[%s::%s]: accepting connection failed",
		       self.topic, self.type)
	    s.connection:close()
	    s.connection = nil
	 end

	 --[[
	 if old_state ~= s.state then
	    local remote = "?"
	    if s.connection and s.connection.header then
	       remote = s.connection.header.callerid
	    elseif s.connection then
	       local rip, rport = s.connection.socket:getpeername()
	       remote = tostring(rip) .. ":" .. tostring(rport)
	    end
	    printf("Publisher[%s:%s] %s: %s -> %s", self.type, self.topic,
		   remote, self.SUBSTATE_TO_STR[old_state],
		   self.SUBSTATE_TO_STR[s.state])
	 end
	 --]]
      end
   end
end


-- (internal) Called by spin() to cleanup failed subscribers.
function Publisher:cleanup_subscribers()
   for i=#self.subscribers, 1, -1 do
      if self.subscribers[i].state == self.SUBSTATE_FAILED then
	 if self.DEBUG then
	    printf("Publisher[%s:%s]: removing failed subscriber %s",
		   self.type, self.topic, self.subscribers[i].callerid)
	 end
	 table.remove(self.subscribers, i)
      end
   end
   self.failed_subscribers = 0
end

--- Get statistics about this publisher.
-- @return an array containing the topic name as the first entry, and another array
-- as the second entry. This array contains itself tables with four fields each:
-- the remote caller ID of the connection, the number of bytes sent, number of
-- messages sent and connection aliveness (always true). Suitable for
-- getBusStats of slave API.
function Publisher:get_stats()
   local conns = {}
   for callerid, s in pairs(self.subscribers) do
      local bytes_rcvd, bytes_sent, age, msgs_rcvd, msgs_sent = s.connection:get_stats()
      local stats = {callerid, bytes_sent, msgs_sent, true}
      table.insert(conns, stats)
   end
   return {self.topic, conns}
end

--- Publish message to topic.
-- The messages are sent immediately. Busy or bad network connections
-- or a large number of subscribers can slow down this method.
-- @param message message to publish
function Publisher:publish(message)
   --assert(message.spec.type == self.type,
   --       "Message of invalid type cannot be published (topic " ..
   --       self.topic .. ", " .. self.type .. " vs. " .. message.spec.type)

   local sm = message:serialize()
   if self.latching  then
      self.latched_message = {message=message, serialized=sm}
   end
   if not next(self.subscribers) and self.topic ~= "/rosout" then
      --if self.DEBUG then
      -- print_warn("Publisher[%s::%s]: cannot send message, no subscribers",
      --	    self.type, self.topic)
      --end
   else
      for _, s in ipairs(self.subscribers) do
	 if s.state == self.SUBSTATE_COMMUNICATING then
	    local ok, error = s.connection:send(sm)

	    if not ok then
	       if self.DEBUG and self.topic ~= "/rosout" then
		  print_warn("Publisher[%s::%s]: failed to send to %s",
			     self.type, self.topic, s.connection.header.callerid)
	       end
	       s.connection:close()
	       s.connection = nil
	       s.state = self.SUBSTATE_FAILED
	       self.failed_subscribers = self.failed_subscribers + 1
	    end
	 end
      end
   end
end

--- Spin function.
-- While spinning the publisher accepts new connections.
function Publisher:spin()
   self:accept_connections()
   if self.waiting_subscribers > 0 then
      self:process_subscribers()
   end
   if self.failed_subscribers > 0 then
      self:cleanup_subscribers()
   end
end

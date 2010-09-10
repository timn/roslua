
----------------------------------------------------------------------------
--  publisher.lua - Topic publisher
--
--  Created: Mon Jul 27 17:04:24 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Topic publisher.
-- This module contains the Publisher class to publish to a ROS topic. The
-- class is used to publish messages to a specified topic. It is created using
-- the function <code>roslua.publisher()</code>.
-- <br /><br />
-- The main interaction for applications is using the <code>publish()</code>
-- method to send new messages. The publisher spins automatically when created
-- using <code>roslua.publisher()</code>.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.publisher", package.seeall)

require("roslua")
require("roslua.msg_spec")

Publisher = {}

--- Constructor.
-- Create a new publisher instance.
-- @param topic topic to publish to
-- @param type type of the topic
function Publisher:new(topic, type)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = topic
   o.latching    = o.latching or false
   if roslua.msg_spec.is_msgspec(type) then
      o.type    = type.type
      o.msgspec = type
   else
      o.type    = type
      o.msgspec = roslua.get_msgspec(type)
   end
   assert(o.topic, "Topic name is missing")
   assert(o.type, "Topic type is missing")

   o.subscribers = {}

   -- connect to all publishers
   o:start_server()

   return o
end

--- Finalize instance.
function Publisher:finalize()
   for uri, s in pairs(self.subscribers) do
      s.connection:close()
   end
   self.subscribers = {}
end

--- Start the internal TCP server to accept ROS subscriber connections.
function Publisher:start_server()
   self.server = roslua.tcpros.TcpRosPubSubConnection:new()
   self.server:bind()
   self.address, self.port = self.server:get_ip_port()
end


--- Wait for a subscriber to connect.
function Publisher:wait_for_subscriber()
   local have_subscriber = false
   repeat
      assert(not roslua.quit, "Aborted while waiting for subscriber for topic "
	     .. self.topic)
      for _, _ in pairs(self.subscribers) do
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
      c:send_header{callerid=roslua.node_name,
		    topic=self.topic,
		    type=self.type,
		    md5sum=self.msgspec:md5()}
      c:receive_header()

      if self.latched and self.latched_message then
	 local ok, error = pcall(c.send, c, self.latched_message.serialized)
	 if not ok then
	    local ip, port = c:get_ip_port()
	    print_warn("Publisher[%s::%s]: failed sending to %s:%s for latched message (%s)",
		       self.type, self.name, ip, port, error)
	    self.subscribers[uri].connection:close() 
	    self.subscribers[uri] = nil
	 end
      end

      --print("Accepted connection from " .. c.header.callerid)
      self.subscribers[c.header.callerid] = {uri=c.header.callerid, connection=c}
   end
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
-- The messages are sent immediately. Busy or bad network connections or a large number
-- of subscribers can slow down this method.
-- @param message message to publish
function Publisher:publish(message)
   --assert(message.spec.type == self.type, "Message of invalid type cannot be published "
	--  .. " (topic " .. self.topic .. ", " .. self.type .. " vs. " .. message.spec.type)

   local sm = message:serialize()
   if self.latching  then
      self.latched_message = {message=message, serialized=sm}
   end
   local uri, s
   for uri, s in pairs(self.subscribers) do
      local ok, error = pcall(s.connection.send, s.connection, sm)
      if not ok then
	 self.subscribers[uri].connection:close()
	 self.subscribers[uri] = nil
      end
   end
end

--- Spin function.
-- While spinning the publisher accepts new connections.
function Publisher:spin()
   self:accept_connections()
end

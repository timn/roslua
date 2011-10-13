
----------------------------------------------------------------------------
--  subscriber.lua - Topic subscriber
--
--  Created: Mon Jul 27 14:11:07 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010       Intel Research Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Topic subscriber.
-- This module contains the Subscriber class to subscribe to a ROS topic. The
-- class is used to connect to all publishers for a certain topic and receive
-- messages published by and of these.
-- <br /><br />
-- During spinning the messages are received and registered listeners are
-- called to process the messages.
--
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Labs Pittsburgh,
-- SRI International
-- @release Released under BSD license
module("roslua.subscriber", package.seeall)

require("roslua")
require("roslua.msg_spec")
require("roslua.tcpros")

CONNECTION_MAX_TRIES = 10

Subscriber = {DEBUG = false,
              MAX_MSGS_PER_LOOP = 10,
	      PUBSTATE_DISCONNECTED = 1,
	      PUBSTATE_TOPIC_REQUESTED = 2,
	      PUBSTATE_TOPIC_NEGOTIATED = 3,
	      PUBSTATE_CONNECTING = 4,
	      PUBSTATE_CONNECTED = 5,
	      PUBSTATE_HEADER_SENT = 6,
	      PUBSTATE_HEADER_RECEIVED = 7,
	      PUBSTATE_COMMUNICATING = 8,
	      PUBSTATE_MAYRETRY = 9,
	      PUBSTATE_FAILED = 10,

	      PUBSTATE_TO_STR = { "PUBSTATE_DISCONNECTED",
				  "PUBSTATE_TOPIC_REQUESTED",
				  "PUBSTATE_TOPIC_NEGOTIATED",
				  "PUBSTATE_CONNECTING",
				  "PUBSTATE_CONNECTED",
				  "PUBSTATE_HEADER_SENT",
				  "PUBSTATE_HEADER_RECEIVED",
				  "PUBSTATE_COMMUNICATING",
                                  "PUBSTATE_MAYRETRY",
				  "PUBSTATE_FAILED" }
	   }

--- Constructor.
-- Create a new subscriber instance.
-- @param topic topic to subscribe to
-- @param type type of the topic
function Subscriber:new(topic, type)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = roslua.resolve(topic)
   if roslua.msg_spec.is_msgspec(type) then
      o.type    = type.type
      o.msgspec = type
   elseif _G.type(type) == "string" then
      o.type    = type
      o.msgspec = roslua.get_msgspec(type)
   else
      error("Subscriber: topic type must be a string or message spec")
   end
   assert(o.type, "Subscriber: topic type is missing")
   assert(o.topic, "Subscriber: topic name is missing")
   assert(_G.type(o.topic) == "string", "Subscriber: topic name must be a string")

   o.publishers = {}
   o.listeners  = {}
   o.messages   = {}
   o.latching   = o.latching or false

   return o
end

--- Finalize instance.
function Subscriber:finalize()
   for uri, p in pairs(self.publishers) do
      if p.connection then
	 p.connection:close()
	 p.connection = nil
      end
   end
end

--- Add a listener to this subscriber.
-- @param listener A listener is either a function or a class which provides a
-- message_received() method. The function or method is called for any
-- successively received message. Note that your listener blocks all other
-- listeners from receiving any further messages. For lengthy task you might
-- consider storing the message and interleaving processing and node spinning.
function Subscriber:add_listener(listener)
   assert(type(listener) == "function" or
         (type(listener) == "table" and listener.message_received),
    "Handle message method is neither function nor class")
   assert(not self.listeners[listener], "Handler already registered")

   self.listeners[listener] = listener
end

--- remove the given listener.
-- The listener will no longer be notified of incoming messages.
-- @param listener listener to remove
function Subscriber:remove_listener(listener)
   self.listeners[listeners] = nil
end

function Subscriber:dispatch()
   for _, m in ipairs(self.messages) do
      for listener, _ in pairs(self.listeners) do
	 local t = type(listener)
	 if t == "table" then
	    listener:message_received(m)
	 elseif t == "function" then
	    listener(m)
	 end
      end
   end
end


--- Update the publishers.
-- This method is called by the slave API handler when the
-- <code>publisherUpdate()</code> XML-RPC method is called. The
-- subscriber instance will connect to any new publishers that it had
-- not connected to before (during the next call to
-- <code>spin()</code> and will (immediately) disconnect from any
-- publishers that are no longer available.
-- @param publishers an array of currently available and slave URIs that were
-- registered at the core
-- @param connect_now if set to true will immediately try to connect to unconnected
-- publishers instead of only marking enqueuing a try for the next spin
function Subscriber:update_publishers(publishers, connect_now)
   self.connect_on_spin = false
   local pub_rev = {}
   for _, uri in ipairs(publishers) do
      pub_rev[uri] = true
      if not self.publishers[uri] then
	 --if roslua.slave_uri == uri then
	 --   print_warn("Subscriber[%s:%s]: removing ourselves from list of "..
         --              "publishers", self.type, self.topic)
	 --else
         self.publishers[uri] = { uri = uri, num_tries = 0,
                                  state = self.PUBSTATE_DISCONNECTED }
         self.connect_on_spin = true
         --end
      end
   end
   local remove_pubs = {}
   for uri, p in pairs(self.publishers) do
      if not pub_rev[uri] then
	 -- publisher dead, remove
	 table.insert(remove_pubs, uri)
      end
   end
   for _, uri in ipairs(remove_pubs) do
      if self.publishers[uri].connection then
	 self.publishers[uri].connection:close()
      end
      self.publishers[uri] = nil
   end
   if connect_now then
      self:connect()
   end
end

--- Get statistics about this subscriber.
-- @return an array containing the topic name as the first entry, and
-- another array as the second entry. This array contains itself
-- tables with five fields each: the remote caller ID of the
-- connection, the number of bytes received, number of messages
-- received, the drop estimate (always -1) and connection aliveness
-- (always true). Suitable for getBusStats of slave API.
function Subscriber:get_stats()
   local conns = {}
   for uri, p in pairs(self.publishers) do
      local bytes_rcvd, bytes_sent, age, msgs_rcvd, msgs_sent = p.connection:get_stats()
      local stats = {uri, bytes_rcvd, msgs_rcvd, -1, true}
      table.insert(conns, stats)
   end
   return {self.topic, conns}
end


--- Connect to all available publishers to which no connection has yet been
-- established.
function Subscriber:connect()
   for uri, p in pairs(self.publishers) do
      local old_state = p.state
      local slave = roslua.get_slave_proxy(uri)

      if p.state ~= self.PUBSTATE_COMMUNICATING and
	 p.state ~= self.PUBSTATE_FAILED
      then
	 if p.state == self.PUBSTATE_DISCONNECTED then
            if self.DEBUG then
               print_debug("Subscriber[%s]: Request topic from %s",
                           self.topic, uri)
            end
            local ok, handle_err = pcall(slave.requestTopic_conc, slave, self.topic)
            if not ok then
               p.state = self.PUBSTATE_MAYRETRY
               print_warn("Subscriber[%s]: parameter negotiation to "..
			     "%s failed (%s)", self.topic, uri, handle_err)
            else
               p.req_handle = handle_err
               p.state = self.PUBSTATE_TOPIC_REQUESTED
            end
	 end

	 if p.state == self.PUBSTATE_TOPIC_REQUESTED then
	    if p.req_handle:failed() then
	       --print_warn("Subscriber[%s]: Parameter negotiation "..
               --           "failed. %s", self.topic, p.req_handle:error())
	       p.state = self.PUBSTATE_MAYRETRY
	       p.req_handle:finalize()
	       p.req_handle = nil
	    elseif p.req_handle:succeeded() then
	       local proto = p.req_handle:result()
	       p.req_handle:finalize()
	       p.req_handle = nil

	       if proto[1] ~= "TCPROS" then
		  print_warn("Subscriber[%s]: TCPROS not supported "..
			     " by remote %s, ignoring peer", 
                             self.topic, uri)
		  p.state = self.PUBSTATE_FAILED
	       else
		  p.proto = proto
		  p.state = self.PUBSTATE_TOPIC_NEGOTIATED
	       end
	    end

	 elseif p.state == self.PUBSTATE_TOPIC_NEGOTIATED then
	    if self.DEBUG then
	       print_debug("Subscriber[%s]: Connecting to %s:%d",
			   self.topic, p.proto[2], p.proto[3])
	    end
	    p.connection = roslua.tcpros.TcpRosPubSubConnection:new()
	    p.connection.name = string.format("Subscriber[%s]", self.topic)
	    local ok, err = pcall(p.connection.connect_start, p.connection,
				  p.proto[2], p.proto[3])
	    if ok then
	       p.state = self.PUBSTATE_CONNECTING
	    else
	       --print_warn("Subscriber[%s] -> %s:%d: Connection start "..
               --	  "failed (%s)", self.topic, p.proto[2],
               --         p.proto[3], err)
	       p.state = self.PUBSTATE_DISCONNECTED
	       p.num_tries = p.num_tries + 1
	    end

	 elseif p.state == self.PUBSTATE_CONNECTING then
	    if p.connection:connect_done() then
	       p.state = self.PUBSTATE_CONNECTED
	    end

	 elseif p.state == self.PUBSTATE_CONNECTED then
	    if self.DEBUG then
	       print_debug("Subscriber[%s]: Connected to %s:%d, sending header",
			   self.topic, p.proto[2], p.proto[3])
	    end
	    p.md5sum = self.msgspec:md5()
	    p.connection:send_header{callerid=roslua.node_name,
				topic=self.topic,
				type=self.type,
				md5sum=p.md5sum}
	    p.state = self.PUBSTATE_HEADER_SENT

	    p.header_receive_coroutine =
	       coroutine.create(function ()
				   return p.connection:receive_header(true)
				end)
	    
	 elseif p.state == self.PUBSTATE_HEADER_SENT then
	    local ok, data_err =
               coroutine.resume(p.header_receive_coroutine)
	    if not ok or not data_err then
	       --print_warn("Subscriber[%s] -> %s:%d: Failed to receive "..
               --           "header (%s)", self.topic, p.proto[2],
               --           p.proto[3], tostring(data_err))
	       p.state = self.PUBSTATE_MAYRETRY
	    elseif coroutine.status(p.header_receive_coroutine) == "dead" then
	       -- finished
	       p.header_receive_coroutine = nil
	       p.state = self.PUBSTATE_HEADER_RECEIVED
	    end

	 elseif p.state == self.PUBSTATE_HEADER_RECEIVED then
	    if p.connection.header.md5sum ~= p.md5sum then
	       print_warn("Subscriber[%s]: received non-matching MD5 "..
			  "(here: %s there: %s) from %s, "..
			  "disconnecting and ignoring",
		       self.topic, p.md5sum, p.connection.header.md5sum,
		       p.connection.header.callerid)
	       p.state = self.PUBSTATE_FAILED
	    else
	       if self.DEBUG then
		  printf("Subscriber[%s]: established connection to %s",
			 self.topic, p.connection.header.callerid)
	       end
	       p.callerid   = p.connection.header.callerid
	       p.state = self.PUBSTATE_COMMUNICATING
	    end
	 end

	 if (p.state == self.PUBSTATE_FAILED or
             p.state == self.PUBSTATE_MAYRETRY) and p.connection
         then
	    p.connection:close()
	    p.connection = nil
            if p.state == self.PUBSTATE_MAYRETRY then
               p.num_tries = p.num_tries + 1
               if p.num_tries < CONNECTION_MAX_TRIES then
                  p.state = self.PUBSTATE_DISCONNECTED
               else
                  p.state = self.PUBSTATE_FAILED
                  print_warn("Subscriber[%s] -> %s:%d: Failed to connect "..
                             "%d times, ignoring peer", self.topic,
                             p.proto[2], p.proto[3], p.num_tries)
               end
            end
	 end

	 if p.state ~= self.PUBSTATE_COMMUNICATING and
	    p.state ~= self.PUBSTATE_FAILED
	 then
	    self.connect_on_spin = true
	 end

	 if self.DEBUG and p.state ~= old_state then
	    printf("Subscriber[%s] pub %s: %s[%s] -> %s[%s]",
                   self.topic, p.uri,
                   self.PUBSTATE_TO_STR[old_state], tostring(old_state),
                   tostring(self.PUBSTATE_TO_STR[p.state]), tostring(p.state))
	 end
      end
   end

   local remove_uris = {}
   for uri, p in pairs(self.publishers) do
      if not p.connection and p.num_tries >= CONNECTION_MAX_TRIES then
	 print_warn("Subscriber[%s]: publisher %s connection failed %d times"..
                    ", dropping publisher", self.topic, uri, p.num_tries)
	 table.insert(remove_uris, uri)
      end
   end
   for _, uri in ipairs(remove_uris) do
      self.publishers[uri] = nil
   end
end


--- Reset messages.
-- You can use this for a latching subscriber to erase the messages at a
-- certain point manually.
function Subscriber:reset_messages()
   self.messages = {}
end

--- Spin all connections to subscribers and dispatch incoming messages.
-- Connections which are found dead are removed.
function Subscriber:spin()
   if self.connect_on_spin then
      self.connect_on_spin = false
      self:connect()
   end

   local erased = false
   if not self.latching then
      self.messages = {}
      erased = true
   end
   for uri, p in pairs(self.publishers) do
      if p.state == self.PUBSTATE_COMMUNICATING and p.connection then
	 p.connection.messages = {}
         local num_msgs = 0
         while num_msgs < self.MAX_MSGS_PER_LOOP
               and p.connection and p.connection:data_available()
         do
            num_msgs = num_msgs + 1
	    local ok, err = pcall(p.connection.receive, p.connection)
	    if not ok then
	       if err == "closed" then
		  -- remote closed the connection, remove this publisher connection
		  p.connection:close()
		  p.connection = nil
		  -- we do not try to reconnect, we rely on proper publisher updates
	       else
                  --if self.DEBUG then
                     print_warn("Subscriber[%s]: receiving failed: %s",
                                self.topic, err)
                  --end
		  p.state = self.PUBSTATE_FAILED
	       end
	    elseif p.connection:data_received() then
	       if self.latching and not erased then
		  self.messages = {}
		  erased = true
	       end
	       for _, m in ipairs(p.connection.messages) do
		  table.insert(self.messages, m)
	       end
	    end
	 end
      end
   end
   self:dispatch()
end


----------------------------------------------------------------------------
--  subscriber.lua - Topic subscriber
--
--  Created: Mon Jul 27 14:11:07 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Topic subscriber.
-- This module contains the Subscriber class to subscribe to a ROS topic. The
-- class is used to connect to all publishers for a certain topic and receive
-- messages published by and of these.
-- <br /><br />
-- During spinning the messages are received and registered listeners are
-- called to process the messages.
--
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.subscriber", package.seeall)

require("roslua")
require("roslua.msg_spec")
require("roslua.tcpros")

CONNECTION_MAX_TRIES = 10

Subscriber = {}

--- Constructor.
-- Create a new subscriber instance.
-- @param topic topic to subscribe to
-- @param type type of the topic
function Subscriber:new(topic, type)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = topic
   if roslua.msg_spec.is_msgspec(type) then
      o.type    = type.type
      o.msgspec = type
   else
      o.type    = type
      o.msgspec = roslua.get_msgspec(type)
   end
   assert(o.topic, "Topic name is missing")
   assert(o.type, "Topic type is missing")

   o.publishers = {}
   o.listeners  = {}

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

function Subscriber:dispatch(messages)
   for _, m in ipairs(messages) do
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
-- This method is called by the slave API handler when the <code>publisherUpdate()</code>
-- XML-RPC method is called. The subscriber instance will connect to any new publishers
-- that it had not connected to before (during the next call to <code>spin()</code> and
-- will (immediately) disconnect from any publishers that are no longer available.
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
	 self.publishers[uri] = { uri = uri, num_tries = 0 }
	 self.connect_on_spin = true
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
-- @return an array containing the topic name as the first entry, and another array
-- as the second entry. This array contains itself tables with five fields each:
-- the remote caller ID of the connection, the number of bytes received, number of
-- messages received, the drop estimate (always -1) and connection aliveness (always
-- true). Suitable for getBusStats of slave API.
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
      p.num_tries = p.num_tries + 1
      local slave = roslua.get_slave_proxy(uri)

      if not p.connection then
	 --print_debug("Subscriber[%s]: Request topic", self.topic)
	 local ok, proto = pcall(slave.requestTopic, slave, self.topic)
	 if ok and proto then
	    assert(proto[1] == "TCPROS", "TCPROS not supported by remote")

	    --print_debug("Subscriber[%s]: Connect", self.topic)
	    local c = roslua.tcpros.TcpRosPubSubConnection:new()
	    local ok, err = pcall(c.connect, c, proto[2], proto[3])
	    if ok then
	       --print_debug("Subscriber[%s]: Send header", self.topic)
	       c:send_header{callerid=roslua.node_name,
			     topic=self.topic,
			     type=self.type,
			     md5sum=self.msgspec:md5()}
	       local ok, err = pcall(c.receive_header, c)
	       if not ok then
		  print_warn("Subscriber[%s] -> %s:%d: Failed to received header (%s)", self.topic,
			     proto[2], proto[3], err)
	       else
		  --print_debug("Subscriber[%s]: Received header", self.topic)
		  p.connection = c
	       end
	    else
	       -- Connection failed, retry in next spin
	       print_warn("Subscriber[%s]: connection failed (%s)", self.topic, err)
	       self.connect_on_spin = true
	    end
	 else
	    -- Connection parameter negotiation failed, retry in next spin
	    --print_warn("Subscriber[%s]: parameter negotiation failed", self.topic)
	    self.connect_on_spin = true
	 end
      end
   end

   local remove_uris = {}
   for uri, p in pairs(self.publishers) do
      if not p.connection and p.num_tries >= CONNECTION_MAX_TRIES then
	 print_warn("Subscriber[%s]: publisher %s connection failed %d times, dropping publisher",
		    self.topic, uri, p.num_tries)
	 table.insert(remove_uris, uri)
      end
   end
   for _, uri in ipairs(remove_uris) do
      self.publishers[uri] = nil
   end
end

--- Spin all connections to subscribers and dispatch incoming messages.
-- Connections which are found dead are removed.
function Subscriber:spin()
   if self.connect_on_spin then
      self.connect_on_spin = false
      self:connect()
   end

   for uri, p in pairs(self.publishers) do
      if p.connection then
	 local ok, err = pcall(p.connection.spin, p.connection)
	 if not ok then
	    if err == "closed" then
	       -- remote closed the connection, we remove this publisher connection
	       p.connection:close()
	       p.connection = nil
	       -- we do not try to reconnect, we rely on proper publisher updates
	    else
	       error(err)
	    end
	 elseif p.connection:data_received() then
	    self:dispatch(p.connection.messages)
	 end
      end
   end
end

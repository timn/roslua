
----------------------------------------------------------------------------
--  subscriber.lua - Topic subscriber
--
--  Created: Mon Jul 27 14:11:07 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")
require("roslua.tcpros")

Subscriber = {}

function Subscriber:new(topic, type)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = topic
   o.type        = type
   o.listeners   = {}
   assert(o.topic, "Topic name is missing")
   assert(o.type, "Topic type is missing")

   -- get message specification
   o.msgspec = roslua.get_msgspec(type)
   o.publishers = {}

   return o
end

function Subscriber:finalize()
   for uri, p in pairs(self.publishers) do
      if p.connection then
	 p.connection:close()
	 p.connection = nil
      end
   end
end

function Subscriber:add_listener(listener)
   assert(type(listener) == "function" or
         (type(listener) == "table" and listener.message_received),
    "Handle message method is neither function nor class")
   assert(not self.listeners[listener], "Handler already registered")

   self.listeners[listener] = listener
end

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

function Subscriber:update_publishers(publishers)
   self.connect_on_spin = false
   local pub_rev = {}
   for _, uri in ipairs(publishers) do
      pub_rev[uri] = true
      if not self.publishers[uri] then
	 self.publishers[uri] = { uri = uri }
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
      self.publishers[uri] = nil
   end
end

function Subscriber:connect()
   for uri, p in pairs(self.publishers) do
      local slave = roslua.get_slave_proxy(uri)

      if not p.connection then
	 local proto = slave:requestTopic(self.topic)
	 if proto then
	    assert(proto[1] == "TCPROS", "TCPROS not supported by remote")

	    local c = roslua.tcpros.TcpRosPubSubConnection:new()
	    local ok, err = pcall(c.connect, c, proto[2], proto[3])
	    if ok then
	       c:send_header{callerid=roslua.node_name,
			     topic=self.topic,
			     type=self.type,
			     md5sum=self.msgspec:md5()}
	       c:receive_header()

	       p.connection = c
	    end
	 end
      end
   end
end

function Subscriber:spin()
   if self.connect_on_spin then
      self:connect()
      self.connect_on_spin = false
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

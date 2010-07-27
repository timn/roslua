
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

Subscriber = { }

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

   -- register as subscriber, this will give us a list of existing publishers
   -- and will get us notified if a publishers comes or goes
   roslua.register_subscriber(topic, type, o)
   o.publishers  = roslua.master:registerSubscriber(topic, type)
   o.connections = {}

   -- connect to all publishers
   o:connect()

   return o
end

function Subscriber:add_listener(listener)
   assert(listener.handle_message, "Handler does not have a handle message method")
   assert(type(handler.handle_message) == "function", "Handle message method is not a function")
   assert(not self.handlers[handler], "Handler already registered")

   self.handlers[handler] = handler
end

function Subscriber:remove_handler(handler)
   self.handlers[handler] = nil
end

function Subscriber:connect()
   for _,p in ipairs(self.publishers) do
      local slave = roslua.get_slave_proxy(p)

      if not self.connections[p] then
	 local proto = slave:requestTopic(self.topic)
	 assert(proto[1] == "TCPROS", "TCPROS not supported by remote")

	 local c = roslua.tcpros.TcpRosConnection:new()
	 c:connect(proto[2], proto[3])

	 c:send_header{callerid=roslua.node_name,
		       topic=self.topic,
		       type=self.type,
		       md5sum=self.msgspec:md5()}
	 c:receive_header()

	 self.connections[p] = c
      end
   end
end

function Subscriber:spin()
   for _,c in pairs(self.connections) do
      c:spin()
      if c:data_received() then
	 c.message:print()
      end
   end
end

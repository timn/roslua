
----------------------------------------------------------------------------
--  publisher.lua - Topic publisher
--
--  Created: Mon Jul 27 17:04:24 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")

Publisher = {}

function Publisher:new(topic, type)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.topic       = topic
   o.type        = type
   assert(o.topic, "Topic name is missing")
   assert(o.type, "Topic type is missing")

   -- get message specification
   o.msgspec = roslua.get_msgspec(type)

   o.subscribers = {}

   -- connect to all publishers
   o:start_server()

   return o
end

function Publisher:finalize()
   for uri, s in pairs(self.subscribers) do
      s.connection:close()
   end
   self.subscribers = {}
end

function Publisher:start_server()
   self.server = roslua.tcpros.TcpRosConnection:new()
   self.server:bind()
   self.address, self.port = self.server:get_ip_port()
end


function Publisher:accept_connections()
   local conns = self.server:accept()
   for _, c in ipairs(conns) do
      c:send_header{callerid=roslua.node_name,
		    topic=self.topic,
		    type=self.type,
		    md5sum=self.msgspec:md5()}
      c:receive_header()

      self.subscribers[c.header.callerid] = { uri = c.header.callerid, connection = c }
   end
end


function Publisher:publish(message)
   assert(message.spec.type == self.type, "Message of invalid type cannot be published "
	  .. " (topic " .. self.topic .. ", " .. self.type .. " vs. " .. message.spec.type)

   local sm = message:serialize()
   local uri, s
   for uri, s in pairs(self.subscribers) do
      local ok, error = pcall(s.connection.send, s.connection, sm)
      if not ok then
	 self.subscribers[uri].connection:close()
	 self.subscribers[uri] = nil
      end
   end
end

function Publisher:spin()
   self:accept_connections()
end

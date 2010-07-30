
----------------------------------------------------------------------------
--  service.lua - Service provider
--
--  Created: Thu Jul 29 14:43:45 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")
require("struct")
require("socket")

Service = {}

function Service:new(service, srvtype, handler)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.service     = service
   o.type        = srvtype
   o.handler     = handler
   assert(o.service, "Service name is missing")
   assert(o.type, "Service type is missing")
   assert(o.handler, "No service handler given")
   assert(type(handler) == "function" or
       (type(handler) == "table" and handler.service_call),
    "Service handler must be function or class")

   -- get message specification
   o.srvspec = roslua.get_srvspec(srvtype)

   o.clients = {}

   -- connect to all publishers
   o:start_server()

   return o
end


function Service:finalize()
   for uri, c in pairs(self.clients) do
      c.connection:close()
   end
   self.subscribers = {}
end

function Service:start_server()
   self.server = roslua.tcpros.TcpRosServiceProviderConnection:new()
   self.server.srvspec = self.srvspec
   self.server:bind()
   _, self.port = self.server:get_ip_port()
   self.address = socket.dns.gethostname()
end


function Service:accept_connections()
   local conns = self.server:accept()
   for _, c in ipairs(conns) do
      c.srvspec = self.srvspec
      c:send_header{callerid=roslua.node_name,
		    service=self.service,
		    type=self.type,
		    md5sum=self.srvspec:md5()}
      c:receive_header()

      self.clients[c.header.callerid] = { uri = c.header.callerid, connection = c }
   end
end


function Service:send_response(connection, msg_or_vals)
   local m
   if getmetatable(msg_or_vals) == roslua.Message then
      m = message
   else
      -- value array, pack it first
      m = self.srvspec.respspec:instantiate()
      m:set_from_array(msg_or_vals)
   end
   local s = struct.pack("<!1I1", 1)

   connection:send(s .. m:serialize())
end

function Service:send_error(message)
   local s = struct.pack("<!1I1I4c0", 0, #message, message)
end


function Service:uri()
   return "rosrpc://" .. self.address .. ":" .. self.port
end


function Service:dispatch(client)
   for _, m in ipairs(client.connection.messages) do
      local format, args = m:generate_value_array(false)
      local t = type(self.handler)
      local rv
      if t == "function" then
	 rv = self.handler(unpack(args))
      elseif t == "table" then
	 rv = self.handler:service_call(unpack(args))
      else
	 self:send_error("Could not handle request")
      end

      self:send_response(client.connection, rv)
      if not client.connection.header.persistent == 1 then
	 client.connection:close()
	 self.clients[client.uri] = nil
      end
   end
end

function Service:spin()
   self:accept_connections()

   -- handle service calls
   for uri, c in pairs(self.clients) do
      local ok, err = pcall(c.connection.spin, c.connection)
      if not ok then
	 if err == "closed" then
	    -- remote closed the connection, we remove this service
	    c.connection:close()
	    self.clients[uri] = nil
	 else
	    error(err)
	 end
      elseif c.connection:data_received() then
	 self:dispatch(c)
      end
   end
end

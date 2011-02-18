
----------------------------------------------------------------------------
--  service.lua - Service provider
--
--  Created: Thu Jul 29 14:43:45 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Service provider.
-- This module contains the Service class to provide services to other ROS
-- nodes. It is created using the function <code>roslua.service()</code>.
-- <br /><br />
-- The service needs a handler to which incoming requests are dispatched.
-- A handler is either a function or a class instance with a service_call()
-- method. On a connection, the request message is called with the fields
-- of the message passed as positional arguments. Sub-messages (i.e.
-- non-builtin complex types) are themselves passed as arrays with the
-- entries being the sub-message fields. This is done recursively for
-- larger hierarchies of parameters.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.service", package.seeall)

require("roslua")
require("roslua.srv_spec")

require("struct")
require("socket")

Service = {}

--- Constructor.
-- Create a new service provider instance.
-- @param service name of the provided service
-- @param type type of the service
-- @param handler handler function or class instance
function Service:new(service, srvtype, handler)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.service     = service
   o.handler     = handler
   if roslua.srv_spec.is_srvspec(srvtype) then
      o.type    = srvtype.type
      o.srvspec = srvtype
   else
      o.type    = srvtype
      o.srvspec = roslua.get_srvspec(srvtype)
   end
   assert(o.service, "Service name is missing")
   assert(o.type, "Service type is missing")
   assert(o.handler, "No service handler given")
   assert(type(handler) == "function" or
       (type(handler) == "table" and handler.service_call),
    "Service handler must be function or class")

   o.clients = {}
   o.num_calls = 0

   o.is_complex = false
   for _, f in ipairs(o.srvspec.reqspec.fields) do
      if f.is_array or not f.is_builtin then
	 o.is_complex = true
      end
   end

   -- connect to all publishers
   o:start_server()

   return o
end


--- Finalize instance.
function Service:finalize()
   for uri, c in pairs(self.clients) do
      c.connection:close()
   end
   self.subscribers = {}
end

--- Start the internal TCP server to accept ROS RPC connections.
function Service:start_server()
   self.server = roslua.tcpros.TcpRosServiceProviderConnection:new()
   self.server.srvspec = self.srvspec
   self.server:bind()
   _, self.port = self.server:get_ip_port()
   self.address = socket.dns.gethostname()
end


-- (internal) Called by spin() to accept new connections.
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


-- (internal) Send response to the given connection
-- @param connection connection to send response with
-- @param msg_or_vals Either message object or value array to send
-- as response. A value array must be given in the same format as the parameters
-- that are passed to the handler.
function Service:send_response(connection, msg_or_vals)
   local m
   if getmetatable(msg_or_vals) == roslua.Message then
      m = message
   else
      -- value array or nil, pack it first
      m = self.srvspec.respspec:instantiate()
      if msg_or_vals then m:set_from_array(msg_or_vals) end
   end
   local s = struct.pack("<!1I1", 1)

   connection:send(s .. m:serialize())
end

-- (internal) send error message.
-- @param connection connection to send error response with
-- @param message error message to send
function Service:send_error(connection, message)
   local s = struct.pack("<!1I1I4c0", 0, #message, message)
   connection:send(s)
end


--- Get the URI for this service.
-- @return rosrpc URI
function Service:uri()
   return "rosrpc://" .. self.address .. ":" .. self.port
end


--- Get stats.
-- @return currently empty array until this is fixed in the XML-RPC
-- specification.
function Service:get_stats()
   return {}
end

--- Dispatch incoming service requests from client.
-- @param client client whose requests to process
function Service:dispatch(client)
   for _, m in ipairs(client.connection.messages) do
      local t = type(self.handler)
      local rv
      local ok

      if self.is_complex then
	 if t == "function" then
	    ok, rv = pcall(self.handler, m.values)
	 elseif t == "table" then
	    ok, rv = pcall(self.handler.service_call, self.handler, unpack(args))
	 else
            ok = false
            rv = "Could not handle request"
	 end
      else
	 local format, args = m:generate_value_array(false)
	 if t == "function" then
	    ok, rv = pcall(self.handler, unpack(args))
	 elseif t == "table" then
	    ok, rv = pcall(self.handler.service_call, self.handler, unpack(args))
	 else
            ok = false
            rv = "Could not handle request"
	 end
      end
      if ok then
         self:send_response(client.connection, rv)
      else
         self:send_error(client.connection, rv)
      end
      if not client.connection.header.persistent == 1 then
	 client.connection:close()
	 self.clients[client.uri] = nil
      end

      self.num_calls = self.num_calls + 1
   end
end

--- Spin service provider.
-- This will accept new connections to the service and dispatch incoming
-- service requests.
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

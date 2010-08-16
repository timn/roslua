
----------------------------------------------------------------------------
--  service_client.lua - Service client
--
--  Created: Fri Jul 30 10:34:47 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Service client.
-- This module contains the ServiceClient class to access services provided
-- by other ROS nodes. It is created using the function
-- <code>roslua.service_client()</code>.
-- <br /><br />
-- The service client employs the <code>__call()</code> meta method, such that
-- the service can be called just as <code>service_client(...)</code>. As arguments
-- you must pass the exact number of fields required for the request message in
-- the exact order and of the proper type as they are defined in the service
-- description file.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.service_client", package.seeall)

require("roslua")
require("roslua.srv_spec")

ServiceClient = { persistent = true }

--- Constructor.
-- The constructor can be called in two ways, either with positional or
-- named arguments. The latter form allows to set additional parameters.
-- In the positional form the ctor takes two arguments, the name and the type
-- of the service. For named parameters the parameter names are service (for
-- the name), type (service type) and persistent. If the latter is set to true
-- the connection to the service provider ROS node will not be closed after
-- one service call. This is beneficial when issuing many service calls in
-- a row, but no guarantee is made that the connection is re-opened if it
-- fails.<br /><br />
-- Examples:<br />
-- Positional: <code>ServiceClient:new("/myservice", "myservice/MyType")</code>
-- Named: <code>ServiceClient:new{service="/myservice", type="myservice/MyType",persistent=true}</code> (mind the curly braces instead of round brackets!)
-- @param args_or_service argument table or service name, see above
-- @param srvtype service type, only used in positional case
function ServiceClient:new(args_or_service, srvtype)
   local o = {}
   setmetatable(o, self)
   self.__index = self
   self.__call  = self.execute

   local type
   if type(args_or_service) == "table" then
      o.service    = args_or_service[1] or args_or_service.service
      type         = args_or_service[2] or args_or_service.type
      o.persistent = args_or_service.persistent
   else
      o.service    = args_or_service
      type         = srvtype
   end
   if roslua.srv_spec.is_srvspec(type) then
      o.type    = type.type
      o.srvspec = type
   else
      o.type    = type
      o.srvspec = roslua.get_msgspec(type)
   end

   assert(o.service, "Service name is missing")
   assert(o.type, "Service type is missing")

   if o.persistent then
      o:connect()
   end

   return o
end


--- Finalize instance.
function ServiceClient:finalize()
   if self.persistent and self.connection then
      -- disconnect
      self.connection:close()
      self.connection = nil
   end
end


--- Connect to service provider.
function ServiceClient:connect()
   assert(not self.connection, "Already connected")

   self.connection = roslua.tcpros.TcpRosServiceClientConnection:new()
   self.connection.srvspec = self.srvspec

   local uri = roslua.master:lookupService(self.service)
   assert(uri ~= "", "No provider found for service")

   -- parse uri
   local host, port = uri:match("rosrpc://([^:]+):(%d+)$")
   assert(host and port, "Parsing ROSRCP uri " .. uri .. " failed")

   self.connection:connect(host, port)
   self.connection:send_header{callerid=roslua.node_name,
			       service=self.service,
			       type=self.type,
			       md5sum=self.srvspec:md5(),
			       persistent=self.persistent and 1 or 0}
   self.connection:receive_header()
end

--- Execute service.
-- This method is set as __call entry in the meta table. See the module documentation
-- on the passed arguments. The method will return only after it has received a reply
-- from the service provider!
-- @param args argument array
function ServiceClient:execute(args)
   if not self.connection then
      self:connect()
   end

   local m = self.srvspec.reqspec:instantiate()
   m:set_from_array(args)
   self.connection:send(m)
   self.connection:wait_for_message()

   local _, rv = self.connection.message:generate_value_array(false)
   if #rv == 1 then
      rv = rv[1]
   end

   if not self.persistent then
      self.connection:close()
      self.connection = nil
   end

   return rv
end

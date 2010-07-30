
----------------------------------------------------------------------------
--  service_client.lua - Service client
--
--  Created: Fri Jul 30 10:34:47 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")

ServiceClient = { persistent = true }

function ServiceClient:new(args_or_service, srvtype)
   local o = {}
   setmetatable(o, self)
   self.__index = self
   self.__call  = self.execute

   if type(args_or_service) == "table" then
      o.service    = args_or_service[1] or args_or_service.service
      o.type       = args_or_service[2] or args_or_service.type
      o.persistent = args_or_service.persistent
   else
      o.service     = args_or_service
      o.type        = srvtype
   end
   assert(o.service, "Service name is missing")
   assert(o.type, "Service type is missing")

   -- get message specification
   o.srvspec = roslua.get_srvspec(o.type)

   if o.persistent then
      o:connect()
   end

   return o
end


function ServiceClient:finalize()
   if self.persistent and self.connection then
      -- disconnect
      self.connection:close()
      self.connection = nil
   end
end


function ServiceClient:connect()
   assert(not self.connection, "Already connected")

   self.connection = roslua.tcpros.TcpRosServiceClientConnection:new()
   self.connection.srvspec = self.srvspec

   local uri = roslua.master:lookupService(self.service)
   assert(uri ~= "", "No provider found for service")

   -- parse uri
   local host, port = uri:match("rosrpc://([^:]+):(%d+)$")
   assert(host and port, "Parsing ROSRCP uri " .. uri .. " failed")
   print(uri, host, port)

   self.connection:connect(host, port)
   self.connection:send_header{callerid=roslua.node_name,
			       service=self.service,
			       type=self.type,
			       md5sum=self.srvspec:md5(),
			       persistent=self.persistent and 1 or 0}
   self.connection:receive_header()
end

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


----------------------------------------------------------------------------
--  slave_proxy.lua - Slave XML-RPC proxy
--
--  Created: Mon Jul 26 11:58:27 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("xmlrpc.http")

__DEBUG = false

SlaveProxy = { slave_uri = nil, node_name = nil }

function SlaveProxy:new(slave_uri, node_name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.slave_uri = slave_uri
   o.node_name = node_name

   return o
end

function SlaveProxy:do_call(method_name, ...)
   local ok, res = xmlrpc.http.call(self.slave_uri,
				    method_name, self.node_name, ...)
   assert(ok, string.format("XML-RPC call %s failed on client: %s", method_name, tostring(res)))
   assert(res[1] == 1, string.format("XML-RPC call %s failed on server: %s",
				     method_name, tostring(res[2])))

   if __DEBUG then
      print(string.format("Ok: %s  Code: %d  Error: %s", tostring(ok), res[1], res[2]))
   end

   return res
end

function SlaveProxy:getBusStats()
   local res = self:do_call("getBusStats")


end

function SlaveProxy:getMasterUri()
   local res = self:do_call("getMasterUri")

   return res[3]
end

function SlaveProxy:shutdown(msg)
   local res = self:do_call("shutdown", msg or "")
end

function SlaveProxy:getPid()
   local res = self:do_call("getPid")

   return res[2]
end

function SlaveProxy:getSubscriptions()
   local res = self:do_call("getSubscriptions")

   return res[3]
end


function SlaveProxy:getPublications()
   local res = self:do_call("getPublications")

   return res[3]
end

function SlaveProxy:requestTopic(topic)
   local protocols = {}
   local tcpros = {"TCPROS"}
   table.insert(protocols, xmlrpc.newTypedValue(tcpros, xmlrpc.newArray()))
   local protocols_x = xmlrpc.newTypedValue(protocols, xmlrpc.newArray("array"))

   local res = self:do_call("requestTopic", topic, protocols_x)

   return res[3]
end

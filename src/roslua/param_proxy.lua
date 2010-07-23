
----------------------------------------------------------------------------
--  param_proxy.lua - Parameter server XML-RPC proxy
--
--  Created: Thu Jul 22 14:37:22 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("xmlrpc.http")

__DEBUG = true

ParamProxy = { ros_master_uri = nil, node_name = nil }

function ParamProxy:new(ros_master_uri, node_name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.ros_master_uri = ros_master_uri
   o.node_name      = node_name

   return o
end

function ParamProxy:do_call(method_name, ...)
   local ok, res = xmlrpc.http.call(self.ros_master_uri,
				    method_name, self.node_name, ...)
   assert(ok, string.format("XML-RPC call %s failed on client: %s", method_name, tostring(res)))
   assert(res[1] == 1, string.format("XML-RPC call %s failed on server: %s",
				     method_name, tostring(res[2])))

   if __DEBUG then
      print(string.format("Ok: %s  Code: %d  Error: %s", tostring(ok), res[1], res[2]))
   end

   return res
end

function ParamProxy:getParamNames()
   local res = self:do_call("getParamNames")

   return res[3]
end


function ParamProxy:hasParam(key)
   local res = self:do_call("hasParam", key)

   return res[3]
end

function ParamProxy:getParam(key)
   local res = self:do_call("getParam", key)

   return res[3]
end

function ParamProxy:setParam(key, value)
   self:do_call("setParam", key, value)
end

function ParamProxy:deleteParam(key)
   self:do_call("deleteParam", key)
end

function ParamProxy:searchParam(key)
   local res = self:do_call("searchParam", key)

   return res[3]
end


function ParamProxy:subscribeParam(caller_api, key)
   local res = self:do_call("subscribeParam", caller_api, key)

   return res[3]
end

function ParamProxy:unsubscribeParam(caller_api, key)
   self:do_call("subscribeParam", caller_api, key)
end


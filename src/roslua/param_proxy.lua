
----------------------------------------------------------------------------
--  param_proxy.lua - Parameter server XML-RPC proxy
--
--  Created: Thu Jul 22 14:37:22 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Parameter XML-RPC API proxy.
-- This module contains the ParamProxy class to call methods provided via
-- XML-RPC by the parameter server.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.param_proxy", package.seeall)

require("xmlrpc")
require("xmlrpc.http")
assert(xmlrpc._VERSION_MAJOR and (xmlrpc._VERSION_MAJOR > 1 or xmlrpc._VERSION_MAJOR == 1 and xmlrpc._VERSION_MINOR >= 2),
       "You must use version 1.2 or newer of lua-xmlrpc")

require("roslua")
require("roslua.names")

__DEBUG = false


--- Initialize parameters.
-- This reads the remappings and stores parameters (remapping left hand
-- sides that start with a single underscore) in the parameter server.
function init()
   for k, v in pairs(roslua.names.remappings) do
      local param = k:match("^_([%w][%w/_]*)$")
      if param then
         roslua.set_param("~" .. param, v)
      end
   end
end


ParamProxy = { ros_master_uri = nil, node_name = nil }

--- Constructor.
-- @param ros_master_uri XML-RPC HTTP URI of ROS master
-- @param node_name name of this node
function ParamProxy:new()
   local o = {}
   setmetatable(o, self)
   self.__index = self

   return o
end


-- (internal) execute XML-RPC call
-- Will always prefix the arguments with the caller ID.
-- @param method_name name of the method to execute
-- @param ... Arguments depending on the method call
function ParamProxy:do_call(method_name, ...)
   local ok, res = xmlrpc.http.call(roslua.master_uri,
				    method_name, roslua.node_name, ...)
   assert(ok, string.format("XML-RPC call %s failed on client: %s",
                            method_name, tostring(res)))
   assert(res[1] == 1, string.format("XML-RPC call %s failed on server: %s",
				     method_name, tostring(res[2])))

   if __DEBUG then
      print(string.format("Ok: %s  Code: %d  Error: %s",
                          tostring(ok), res[1], res[2]))
   end

   return res
end

--- Get names of all available parameters.
-- @return array with names of all parameters
function ParamProxy:get_param_names()
   local res = self:do_call("getParamNames")

   return res[3]
end

--- Check if parameter exists.
-- @param key key of the parameter to query
-- @return true if the parameter exists, false otherwise
function ParamProxy:has_param(key)
   local res = self:do_call("hasParam", roslua.resolve(key))

   return res[3]
end

--- Get parameter.
-- @param key key of the parameter to query
-- @return value of the parameter
function ParamProxy:get_param(key)
   local res = self:do_call("getParam", roslua.resolve(key))

   return res[3]
end

--- Set parameter.
-- @param key key of the parameter to set
-- @param value value of the parameter to set
function ParamProxy:set_param(key, value)
   self:do_call("setParam", roslua.resolve(key), tonumber(value) or value)
end

--- Delete parameter.
-- @param key key of the parameter to delete
function ParamProxy:delete_param(key)
   self:do_call("deleteParam", roslua.resolve(key))
end

--- Search for parameter.
-- @param key substring of the key to look for
-- @return first key that matched
function ParamProxy:search_param(key)
   local res = self:do_call("searchParam", roslua.resolve(key))

   return res[3]
end

--- Subscribe to parameter.
-- @param key key to subscribe to
function ParamProxy:subscribe_param(key)
   local res = self:do_call("subscribeParam", roslua.slave_uri,
                            roslua.resolve(key))

   return res[3]
end

--- Unsubscribe from parameter.
-- @param key key to unsubscribe from
function ParamProxy:unsubscribe_param(key)
   self:do_call("subscribeParam", roslua.slave_uri, roslua.resolve(key))
end


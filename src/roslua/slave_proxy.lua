
----------------------------------------------------------------------------
--  slave_proxy.lua - Slave XML-RPC proxy
--
--  Created: Mon Jul 26 11:58:27 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Slave XML-RPC API proxy.
-- This module contains the SlaveProxy class to call methods provided via
-- XML-RPC by ROS slaves.
-- <br /><br />
-- The user should not have to directly interact with the slave. It is used
-- to initiate topic connections and get information about the slave.
-- It can also be used to remotely shutdown a slave.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.slave_proxy", package.seeall)

require("xmlrpc.http")

__DEBUG = false

SlaveProxy = { slave_uri = nil, node_name = nil }

--- Constructor.
-- @param slave_uri XML-RPC HTTP slave URI
-- @param node_name name of this node
function SlaveProxy:new(slave_uri, node_name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.slave_uri = slave_uri
   o.node_name = node_name

   return o
end

-- (internal) execute XML-RPC call
-- Will always prefix the arguments with the caller ID.
-- @param method_name name of the method to execute
-- @param ... Arguments depending on the method call
function SlaveProxy:do_call(method_name, ...)
   local ok, res = xmlrpc.http.call(self.slave_uri,
				    method_name, self.node_name, ...)
   assert(ok, string.format("XML-RPC call %s failed on client: %s", method_name, tostring(res)))
   assert(res[1] == 1, string.format("XML-RPC call %s failed on server: %s",
				     method_name, tostring(res[2])))

   if __DEBUG then
      print(string.format("Ok: %s  Code: %d  Error: %s  arrlen: %i", tostring(ok), tostring(res[1]),
			  tostring(res[2]), #res))
   end

   return res
end

--- Get bus stats.
-- @return bus stats
function SlaveProxy:getBusStats()
   local res = self:do_call("getBusStats")

   return res[3]
end


--- Get slaves master URI.
-- @return slaves master URI
function SlaveProxy:getMasterUri()
   local res = self:do_call("getMasterUri")

   return res[3]
end

--- Shutdown remote node.
-- @param msg shutdown message
function SlaveProxy:shutdown(msg)
   local res = self:do_call("shutdown", msg or "")
end

--- Get PID of remote slave.
-- Can be used to "ping" the remote node.
function SlaveProxy:getPid()
   local res = self:do_call("getPid")

   return res[3]
end

--- Get all subscriptions of remote node.
-- @return list of subscriptions
function SlaveProxy:getSubscriptions()
   local res = self:do_call("getSubscriptions")

   return res[3]
end

--- Get all publications of remote node.
-- @return list of publications
function SlaveProxy:getPublications()
   local res = self:do_call("getPublications")

   return res[3]
end

--- Request a TCPROS connection for a specific topic.
-- @param topic name of topic
-- @return TCPROS communication parameters
function SlaveProxy:requestTopic(topic)
   local protocols = {}
   local tcpros = {"TCPROS"}
   table.insert(protocols, xmlrpc.newTypedValue(tcpros, xmlrpc.newArray()))
   local protocols_x = xmlrpc.newTypedValue(protocols, xmlrpc.newArray("array"))

   local res = self:do_call("requestTopic", topic, protocols_x)

   return res[3]
end

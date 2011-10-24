
----------------------------------------------------------------------------
--  master_proxy.lua - Master XML-RPC proxy
--
--  Created: Thu Jul 22 11:31:05 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Master XML-RPC API proxy.
-- This module contains the MasterProxy class to call methods provided via
-- XML-RPC by the ROS master.
-- <br /><br />
-- The user should not have to directly interact with the master. It is used
-- register and unregister topic publishers/subscribers and services, to
-- lookup nodes and services, and to gather information about the master.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.master_proxy", package.seeall)

require("roslua")
require("xmlrpc")
require("xmlrpc.http")
assert(xmlrpc._VERSION_MAJOR and (xmlrpc._VERSION_MAJOR > 1 or xmlrpc._VERSION_MAJOR == 1 and xmlrpc._VERSION_MINOR >= 2),
       "You must use version 1.2 or newer of lua-xmlrpc")
require("roslua.xmlrpc_post")

__DEBUG = false

MasterProxy = { ros_master_uri = nil, node_name = nil }

--- Constructor.
-- @param ros_master_uri XML-RPC HTTP URI of ROS master
-- @param node_name name of this node
function MasterProxy:new()
   local o = {}
   setmetatable(o, self)
   self.__index = self

   return o
end

-- (internal) execute XML-RPC call
-- Will always prefix the arguments with the caller ID.
-- @param method_name name of the method to execute
-- @param ... Arguments depending on the method call
function MasterProxy:do_call(method_name, ...)
   local ok, res = xmlrpc.http.call(roslua.master_uri,
				    method_name, roslua.node_name, ...)
   assert(ok, string.format("XML-RPC call %s failed on client: %s",
                            method_name, tostring(res)))
   if res[1] ~= 1 then
      error(string.format("XML-RPC call %s failed on server: %s",
                          method_name, tostring(res[2])), 0)
   end

   if __DEBUG then
      print(string.format("Ok: %s  Code: %d  Error: %s",
                          tostring(ok), res[1], res[2]))
   end

   return res
end

--- Get master system state.
-- @return three array of registered publishers, subscribers, and services
function MasterProxy:getSystemState()
   local res = self:do_call("getSystemState")

   local publishers  = {}
   local subscribers = {}
   local services    = {}

   for i, v in ipairs(res[3][1]) do
      publishers[v[1]] = v[2]
   end

   for i, v in ipairs(res[3][2]) do
      subscribers[v[1]] = v[2]
   end

   for i, v in ipairs(res[3][3]) do
      services[v[1]] = v[2]
   end

   return publishers, subscribers, services
end

--- Lookup node by name.
-- @param name of node to lookup
-- @return Slave API XML-RPC HTTP URI
function MasterProxy:lookupNode(node_name)
   local res = self:do_call("lookupNode", node_name)

   return tostring(res[3])
end

--- Get published topics.
-- @param subgraph subgraph to query from master
-- @return graph of topics
function MasterProxy:getPublishedTopics(subgraph)
   local subgraph = subgraph or ""
   local res = self:do_call("getPublishedTopics", subgraph)

   return res[3]
end

--- Get master URI.
-- Considering that you need to know the URI to call this method is's quite
-- useless.
-- @return ROS master URI
function MasterProxy:getUri()
   local res = self:do_call("getUri")

   return res[3]
end

--- Lookup service by name.
-- @param service name of service to lookup
-- @return ROS RPC URI of service provider
function MasterProxy:lookupService(service)
   local res = self:do_call("lookupService", roslua.resolve(service))

   return res[3]
end

--- Start a lookup request.
-- This starts a concurrent execution of lookupService().
-- @param service service to lookup
-- @return XmlRpcRequest handle for the started request
function MasterProxy:lookupService_conc(service)
   return roslua.xmlrpc_post.XmlRpcRequest:new(roslua.master_uri, "lookupService",
                                               roslua.node_name,
                                               roslua.resolve(service))
end

--- Register a service with the master.
-- @param service name of service to register
-- @param service_api ROS RPC URI of service
function MasterProxy:registerService(service, service_api)
   self:do_call("registerService", roslua.resolve(service),
                service_api, roslua.slave_uri)
end

--- Unregister a service from master.
-- @param service name of service to register
-- @param service_api ROS RPC URI of service
function MasterProxy:unregisterService(service, service_api)
   self:do_call("unregisterService", roslua.resolve(service), service_api)
end


--- Register subscriber with the master.
-- @param topic topic to register for
-- @param topic_type type of the topic
function MasterProxy:registerSubscriber(topic, topic_type)
   local res = self:do_call("registerSubscriber", roslua.resolve(topic),
                            topic_type, roslua.slave_uri)

   return res[3]
end

--- Unregister subscriber from master.
-- @param topic topic to register for
function MasterProxy:unregisterSubscriber(topic)
   self:do_call("unregisterSubscriber", roslua.resolve(topic), roslua.slave_uri)
end


--- Register Publisher with the master.
-- @param topic topic to register for
-- @param topic_type type of the topic
function MasterProxy:registerPublisher(topic, topic_type)
   local res = self:do_call("registerPublisher",
                            roslua.resolve(topic), topic_type, roslua.slave_uri)

   return res[3]
end

--- Unregister publisher from master.
-- @param topic topic to register for
function MasterProxy:unregisterPublisher(topic)
   self:do_call("unregisterPublisher", roslua.resolve(topic), roslua.slave_uri)
end

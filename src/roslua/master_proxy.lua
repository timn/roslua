
----------------------------------------------------------------------------
--  master_proxy.lua - Master XML-RPC proxy
--
--  Created: Thu Jul 22 11:31:05 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")
require("xmlrpc.http")

__DEBUG = false

MasterProxy = { ros_master_uri = nil, node_name = nil }

function MasterProxy:new(ros_master_uri, node_name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.ros_master_uri = ros_master_uri
   o.node_name      = node_name

   return o
end

function MasterProxy:do_call(method_name, ...)
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

function MasterProxy:lookupNode(node_name)
   local res = self:do_call("lookupNode", node_name)

   return tostring(res[3])
end

function MasterProxy:getPublishedTopics(subgraph)
   local subgraph = subgraph or ""
   local res = self:do_call("getPublishedTopics", subgraph)

   return res[3]
end

function MasterProxy:getUri()
   local res = self:do_call("getUri")

   -- That should be index 3, but master sends buggy response
   return res[2]
end

function MasterProxy:lookupService(service)
   local res = self:do_call("lookupService", service)

   return res[3]
end


function MasterProxy:registerService(service, service_api)
   self:do_call("registerService", service, service_api, roslua.slave_uri)
end

function MasterProxy:unregisterService(service, service_api)
   self:do_call("unregisterService", service, service_api)
end


function MasterProxy:registerSubscriber(topic, topic_type)
   local res = self:do_call("registerSubscriber", topic, topic_type, roslua.slave_uri)

   return res[3]
end

function MasterProxy:unregisterSubscriber(topic)
   self:do_call("unregisterSubscriber", topic, roslua.slave_uri)
end


function MasterProxy:registerPublisher(topic, topic_type)
   local res = self:do_call("registerPublisher", topic, topic_type, roslua.slave_uri)

   return res[3]
end

function MasterProxy:unregisterPublisher(topic)
   self:do_call("unregisterPublisher", topic, roslua.slave_uri)
end


----------------------------------------------------------------------------
--  init.lua - base file for roslua library
--
--  Created: Fri Jul 16 17:29:03 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module("roslua", package.seeall)

require("xmlrpc.http")

master = nil

MasterProxy = { ros_master_uri = nil, node_name = nil }

function MasterProxy:new(ros_master_uri, node_name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.ros_master_uri = ros_master_uri
   o.node_name      = node_name

   return o
end

function MasterProxy:getSystemState()
   local ok, res = xmlrpc.http.call(self.ros_master_uri, "getSystemState", self.node_name)
   assert(ok, "XML-RPC call getSystemState failed on client: " .. tostring(res))
   assert(res[1] == 1, "XML-RPC call getSystemState failed on server: " .. tostring(res[2]))

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


function init_node(ros_master_uri, node_name)
   master = MasterProxy:new(ros_master_uri, node_name)
end

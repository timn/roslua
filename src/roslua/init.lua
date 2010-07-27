
----------------------------------------------------------------------------
--  init.lua - base file for roslua library
--
--  Created: Fri Jul 16 17:29:03 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

local master_proxy = require("roslua.master_proxy")
local param_proxy  = require("roslua.param_proxy")

-- just to describe variables we provide
master = nil
parameter_server = nil

function init_node(ros_master_uri, node_name)
   assert(ros_master_uri, "ROS Master URI not set")
   assert(node_name, "Node name not set")

   master = master_proxy.MasterProxy:new(ros_master_uri, node_name)
   parameter_server = param_proxy.ParamProxy:new(ros_master_uri, node_name)
end


----------------------------------------------------------------------------
--  service_client.lua - service client example
--
--  Created: Fri Jul 30 10:58:59 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"),
		 node_name="/serviceclient"}

local service = "/add_two_ints"
local srvtype = "rospy_tutorials/AddTwoInts"

math.randomseed(os.time())
local a, b = math.random(1000), math.random(1000)

local s = roslua.service_client(service, srvtype)
local res = s{a, b}

print(a .. " + " .. b .. " = " .. res)

roslua.finalize()


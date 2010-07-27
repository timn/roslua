
----------------------------------------------------------------------------
--  serializetest.lua - serialization test
--
--  Created: Mon Jul 27 19:16:35 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

package.path  = ";;/homes/timn/ros/local/roslua/src/?/init.lua;/homes/timn/ros/local/roslua/src/?.lua;/usr/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua"
package.cpath = package.cpath .. ";/homes/timn/ros/local/roslua/src/roslua/?.luaso;something?;/usr/lib/lua/5.1/?.so"

require("roslua")

roslua.init_node{master_uri = os.getenv("ROS_MASTER_URI"),
		 node_name  = "/serializetest"}

local ms = roslua.get_msgspec("roslib/Log")
ms:print()
local m = ms:instantiate()

local hms = roslua.get_msgspec("roslib/Header")
local hm = hms:instantiate()

hm.values.seq = 1024
hm.values.stamp = {1, 2}
hm.values.frame_id = "my_frameid"

m.values.header = hm
m.values.level  = 2
m.values.topics = {"/topic1", "/topic2", "/topic3"}

local s = m:serialize()

local f = io.open("serializetest.dat", "w")
f:write(s)
f:close()



----------------------------------------------------------------------------
--  subscriber.lua - subscriber implementation test
--
--  Created: Mon Jul 27 15:37:01 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--package.path  = ";;/homes/timn/ros/local/roslua/src/?/init.lua;/homes/timn/ros/local/roslua/src/?.lua;/usr/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua"
--package.cpath = package.cpath .. ";/homes/timn/ros/local/roslua/src/roslua/?.luaso;something?;/usr/lib/lua/5.1/?.so"

require("roslua")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"),
		 node_name="/talkersub"}

--local topic = "/rosout"
--local msgtype = "roslib/Log"
local topic = "/chatter"
local msgtype = "std_msgs/String"

local s = roslua.subscriber(topic, msgtype)
s:add_listener(function (message)
		  message:print()
	       end)

while not roslua.quit do
   roslua.spin()
end
roslua.finalize()

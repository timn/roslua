
----------------------------------------------------------------------------
--  publisher.lua - publisher implementation test
--
--  Created: Tue Jul 28 10:40:33 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"),
		 node_name="/talkerpub"}

local topic = "/chatter"
local msgtype = "std_msgs/String"
local msgspec = roslua.get_msgspec(msgtype)

local p = roslua.publisher(topic, msgtype)

while not roslua.quit do
   roslua.spin()

   local m = msgspec:instantiate()
   m.values.data = "hello world " .. os.date()
   p:publish(m)
end
roslua.finalize()

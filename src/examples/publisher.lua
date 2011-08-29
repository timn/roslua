
----------------------------------------------------------------------------
--  publisher.lua - publisher implementation test
--
--  Created: Tue Jul 28 10:40:33 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{node_name="talkerpub"}

local topic = "chatter"
local msgtype = "std_msgs/String"

local p = roslua.publisher(topic, msgtype)

while not roslua.quit do
   roslua.spin()

   local m = p.msgspec:instantiate()
   m.values.data = "hello world " .. tostring(roslua.Time.now())
   p:publish(m)
   roslua.sleep(0.1)
end
roslua.finalize()


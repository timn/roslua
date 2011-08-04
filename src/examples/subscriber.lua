
----------------------------------------------------------------------------
--  subscriber.lua - subscriber example
--
--  Created: Mon Jul 27 15:37:01 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")
require("roslua.names")

roslua.init_node{node_name="talkersub"}

local topic = "chatter"
local msgtype = "std_msgs/String"

local s = roslua.subscriber(topic, msgtype)
s:add_listener(function (message)
		  message:print()
	       end)

roslua.run()


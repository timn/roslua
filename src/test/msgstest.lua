
----------------------------------------------------------------------------
--  msgstest.lua - Message specification parser test
--
--  Created: Mon Jul 26 15:48:49 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")
require("roslua.utils")

print("std_msgs path: ", roslua.utils.find_rospack("std_msgs"))

print()
print("Message spec tests")

print()
local msgspec = roslua.msg_spec.get_msgspec("std_msgs/String")
msgspec:print()

print()
local msgspec = roslua.msg_spec.get_msgspec("roslib/Log")
msgspec:print()

print()
local msgspec = roslua.msg_spec.get_msgspec("gazebo_plugins/ModelJointsState")
msgspec:print()

print()
local msgspec = roslua.msg_spec.get_msgspec("geometry_msgs/Pose")
msgspec:print()

print()
local msgspec = roslua.msg_spec.get_msgspec("geometry_msgs/Point")
msgspec:print()

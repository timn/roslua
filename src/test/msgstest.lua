
----------------------------------------------------------------------------
--  talkertest.lua - Initial test of opening a connection
--
--  Created: Mon Jul 26 15:48:49 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

package.path  = ";;/homes/timn/ros/local/roslua/src/?/init.lua;/homes/timn/ros/local/roslua/src/?.lua;/usr/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua"
package.cpath = ";;/homes/timn/ros/local/roslua/src/roslua/?.so;/usr/lib/lua/5.1/?.so"

require("roslua")

print("std_msgs path: ", roslua.msg_spec.find_rospack("std_msgs"))

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

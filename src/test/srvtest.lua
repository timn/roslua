
----------------------------------------------------------------------------
--  srvspec.lua - Service specification parser test
--
--  Created: Thu Jul 29 11:47:56 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

package.path  = ";;/homes/timn/ros/local/roslua/src/?/init.lua;/homes/timn/ros/local/roslua/src/?.lua;/usr/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua"
package.cpath = ";;/homes/timn/ros/local/roslua/src/roslua/?.luaso;/usr/lib/lua/5.1/?.so"

require("roslua")

print()
print("Service spec tests")

print()
local srvspec = roslua.srv_spec.get_srvspec("std_srvs/Empty")
srvspec:print()

print()
local srvspec = roslua.srv_spec.get_srvspec("roscpp/SetLoggerLevel")
srvspec:print()

print()
local srvspec = roslua.srv_spec.get_srvspec("roscpp/GetLoggers")
srvspec:print()


print()
local srvspec = roslua.srv_spec.get_srvspec("rospy_tutorials/AddTwoInts")
srvspec:print()

--[[
print()
local srvspec = roslua.srv_spec.get_srvspec("geometry_srvs/Point")
srvspec:print()
--]]


----------------------------------------------------------------------------
--  srvspec.lua - Service specification parser test
--
--  Created: Thu Jul 29 11:47:56 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

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

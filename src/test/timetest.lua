
----------------------------------------------------------------------------
--  timetest.lua - time test
--
--  Created: Mon Aug 09 14:29:06 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license
require("roslua")
require("roslua.time")

local Time = roslua.time.Time

local t = Time:new()
print(tostring(t))

t:stamp()
print(tostring(t))


local t1 = Time:new(1, 0)
local t2 = Time:new(3, 0)
local t3 = t1 + t2
local t4 = t2 - t1

print("t1", t1)
print("t2", t2)
print("t3 = t1 + t2", t3)
print("t4 = t2 - t1", t4)

print("t1 < t2?", tostring(t1 < t2))
print("t1 > t2?", tostring(t1 > t2))
print("t1 == t2?", tostring(t1 == t2))
local t5 = t1:clone()
print("t1 == t5?", tostring(t1 == t5))


----------------------------------------------------------------------------
--  serializetest.lua - serialization test
--
--  Created: Mon Jul 27 19:16:35 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

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

local s, format, arr = m:serialize()

local function print_table_rec(t, indent)
   local indent = indent or ""
   for k,v in pairs(t) do
      if type(v) == "table" then
	 print(indent .. "Recursing into table " .. k)
	 print_table_rec(v, indent .. "   ")
      else
	 print(indent .. k .. "=" .. tostring(v) .. " (" .. type(v) .. ")")
      end
   end
end
print("Format", format)
print_table_rec(arr)

print("Writing serialized string to serializetest.dat")
local f = io.open("serializetest.dat", "w")
f:write(s)
f:close()


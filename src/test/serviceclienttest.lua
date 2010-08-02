
----------------------------------------------------------------------------
--  serviceclienttest.lua - service client implementation test
--
--  Created: Fri Jul 30 10:58:59 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"),
		 node_name="/serviceclient"}

local service = "/add_two_ints"
local srvtype = "rospy_tutorials/AddTwoInts"
local srvspec = roslua.get_srvspec(srvtype)

local function run_test(s)
   math.randomseed(os.time())
   local a, b = math.random(1000), math.random(1000)
   local res = s{a, b}

   local result_ok = (a + b) == res
   print(a .. " + " .. b .. " = " .. res .. "  (result ok: " .. tostring(result_ok) .. ")")
end


print("Running NON-persistent tests")
local s = roslua.service_client(service, srvtype, false)
run_test(s)
run_test(s)
run_test(s)

print("Running persistent test")
local s = roslua.service_client(service, srvtype, true)
run_test(s)
run_test(s)
run_test(s)

roslua.finalize()

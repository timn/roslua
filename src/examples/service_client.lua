
----------------------------------------------------------------------------
--  service_client.lua - service client example
--
--  Created: Fri Jul 30 10:58:59 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{node_name="serviceclient"}

local service = "add_two_ints"
local srvtype = "rospy_tutorials/AddTwoInts"

local s = roslua.service_client(service, srvtype, {simplified_return=true})

--for i = 1, 2 do
math.randomseed(os.time())
local a, b = math.random(1000), math.random(1000)

local ok, res = pcall(s, {a, b})

if ok then
   print(a .. " + " .. b .. " = " .. res)
else
   printf("Service execution failed: %s", res)
end

--   roslua.sleep(5.0)
--end

roslua.finalize()


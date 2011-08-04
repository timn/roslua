
----------------------------------------------------------------------------
--  service_provider.lua - service provider example
--
--  Created: Thu Jul 29 15:55:38 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{node_name="serviceprovider"}

local service = "add_two_ints"
local srvtype = "rospy_tutorials/AddTwoInts"

function add_two_ints(a, b)
   -- Randomly fail to show and test error handling
   if math.random() < 0.3 then error("Failed on purpose") end
   print(a .. " + " .. b .. " = " .. a+b)
   return { a + b }
end

local p = roslua.service(service, srvtype, add_two_ints)

roslua.run()


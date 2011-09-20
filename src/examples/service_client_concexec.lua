
----------------------------------------------------------------------------
--  service_client_concexec.lua - concurrent service client example
--
--  Created: Tue Sep 20 18:27:22 2011 (Papas 65.!)
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{node_name="serviceclient"}

-- Number of iterations to call the service
local LOOPS = 3
-- Sleep 5 seconds after each iteration but the last?
local SLEEP_PER_LOOP = false

local service = "add_two_ints"
local srvtype = "rospy_tutorials/AddTwoInts"

local s = roslua.service_client(service, srvtype, {simplified_return=true})
math.randomseed(os.time())

for i = 1, LOOPS do
   local a, b = math.random(1000), math.random(1000)

   -- Use more complex but also more powerful form of execution
   -- which can be run concurrent to other tasks

   s:concexec_start{a, b}

   local running = true
   while running do
      if s:concexec_succeeded() then
         print(a .. " + " .. b .. " = " .. s:concexec_result())
         running = false
      elseif s:concexec_failed() then
         printf("%s", s.concexec_error)
         running = false
      end
      roslua.sleep(0.1)
   end

   -- Sleep after loop, for example to restart provider in between loops
   if i ~= LOOPS and SLEEP_PER_LOOP then roslua.sleep(5.0) end
end

roslua.finalize()

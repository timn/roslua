
----------------------------------------------------------------------------
--  timer.lua - timer example
--
--  Created: Fri Apr 15 12:53:22 2011
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010-2011  Intel Labs Pittsburgh
--             2011       SRI International
--  Licensed under BSD license, cf. LICENSE file of roslua
----------------------------------------------------------------------------

require("roslua")

roslua.init_node{node_name="timertest"}

function callback(event)
   local offset = (event.current_real - event.current_expected):to_sec()

   printf("Timer CB, Last Exp: %s  Last Real: %s  Cur Exp: %s  Cur Real: %s "
	  .. " Last Dur: %f  Offset: %f", tostring(event.last_expected),
       tostring(event.last_real), tostring(event.current_expected),
       tostring(event.current_real), event.last_duration, offset)
end

local t = roslua.timer(1.0, callback)

roslua.run(10)
--[[
while not roslua.quit do
   roslua.spin()
   roslua.sleep(0.1)
end
roslua.finalize()
--]]

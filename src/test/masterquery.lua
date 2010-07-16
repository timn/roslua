
----------------------------------------------------------------------------
--  masterquery.lua - little test program to query data from master
--
--  Created: Fri Jul 16 18:12:18 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")

roslua.init_node(os.getenv("ROS_MASTER_URI"), "/roslua_masterquery")

local publishers, subscribers, services = roslua.master:getSystemState()

print("Publishers")
for topic, pubs in pairs(publishers) do
   print("  " .. topic)
   for _, p in ipairs(pubs) do
      print("    " .. p)
   end
end

print("Subscribers")
for topic, subs in pairs(subscribers) do
   print("  " .. topic)
   for _, s in ipairs(subs) do
      print("    " .. s)
   end
end

print("Services")
for service, prvs in pairs(services) do
   print("  " .. service)
   for _, p in ipairs(prvs) do
      print("    " .. p)
   end
end


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

local master = roslua.master
local parmserv = roslua.parameter_server

print("Getting system state...")
local publishers, subscribers, services = master:getSystemState()

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


print()
print("Looking up node /talker...")

local uri = master:lookupNode("/talker")
print(string.format("URI for /talker is %s", uri))


print()
print("Listing topics")
local topics = master:getPublishedTopics()
for i,t in ipairs(topics) do
   print(i, t[1], t[2])
end


print()
print("Getting master URI")
local master_uri = master:getUri()
print("Master Uri", master_uri)


print()
print("Looking up service /rosout/get_loggers")
local service_uri = master:lookupService("/rosout/get_loggers")
print("Service URI", service_uri)


print()
print("Registering dummy service /masterquery")
master:registerService("/masterquery", "rosrpc://localhost:12345", "http://localhost:12346")

print()
print("UNregistering dummy service /masterquery")
master:unregisterService("/masterquery", "rosrpc://localhost:12345", "http://localhost:12346")

--print()
--print("Registering as subscriber for /chatter")
--master:registerSubscriber("/chatter", "rosrpc://localhost:12345", "http://localhost:12346")

print()
print("Listing parameter names")
local param_names = parmserv:get_param_names()
for _,n in ipairs(param_names) do
   local param_value = parmserv:get_param(n)
   print("", n,"=", param_value)
end

print()
print("Checking for parameter /run_id")
local has_param = parmserv:has_param("/run_id")
if has_param then
   print("", "YES")
else
   print("", "NO")
end


print()
print("Custom value test with /masterquery")
parmserv:set_param("/masterquery", 1234)
local set_ok = parmserv:has_param("/masterquery")
if set_ok then
   print("setting worked, fetching")
   local val = parmserv:get_param("/masterquery")
   print("Value", val)

   print("Deleting value")
   parmserv:delete_param("/masterquery")
   local del_ok = parmserv:has_param("/masterquery")
   if del_ok then
      print("Failed to delete value")
   else
      print("Delete succeeded")
   end
else
   print("Setting parameter failed")
end

print()
print("Searching bogus key")
local ok, fkey = pcall(parmserv.search_param, parmserv, "/bogus")
if ok then
   print("WTF, our bogus search found something!?", fkey)
else
   print("Nothing, as expected")
end


print()
print("Searching run_id key")
local fkey = parmserv:search_param("run_id")
print("Found", fkey)



----------------------------------------------------------------------------
--  registry.lua - Registry for topic/service registration
--
--  Created: Fri Jul 30 14:52:10 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")

subscribers = {}
publishers  = {}
services    = {}

function register_subscriber(topic, type, subscriber)
   assert(not roslua.subscribers[topic], "Subscriber has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   roslua.subscribers[topic] = { type=type, subscriber=subscriber }

   local ok, pubs_err = pcall(roslua.master.registerSubscriber, roslua.master, topic, type)
   if not ok then
      error("Cannot connect to ROS master: " .. pubs_err)
   end
   subscriber:update_publishers(pubs_err)
end

function register_publisher(topic, type, publisher)
   assert(not roslua.publishers[topic], "Publisher has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   local ok, subs_err  = pcall(roslua.master.registerPublisher, roslua.master, topic, type)
   if not ok then
      error("Cannot connect to ROS master: " .. subs_err)
   end
   roslua.publishers[topic] = { type=type, publisher=publisher }
end

function register_service(service, type, provider)
   assert(not roslua.services[service], "Service already provided")

   local ok = pcall(roslua.master.registerService, roslua.master, service, provider:uri())
   if not ok then
      error("Cannot connect to ROS master: " .. subs_err)
   end
   roslua.services[service] = { type=type, provider=provider }
end

function unregister_subscriber(topic, type, subscriber)
   assert(roslua.subscribers[topic], "Topic " .. topic .. " has not been subscribed")
   assert(roslua.subscribers[topic].type == type, "Conflicting type for topic " .. topic
	  .. " while unregistering subscriber (" .. roslua.subscribers[topic].type
	  .. " vs. " .. type .. ")")
   assert(roslua.subscribers[topic].subscriber == subscriber,
	  "Different subscribers for topic " .. topic .. " on unregistering subscriber")

   roslua.master:unregisterSubscriber(topic)
   roslua.subscribers[topic] = nil
end

function unregister_publisher(topic, type, publisher)
   assert(roslua.publishers[topic], "Topic " .. topic .. " is not published")
   assert(roslua.publishers[topic].type == type, "Conflicting type for topic " .. topic
	  .. " while unregistering publisher (" .. roslua.publishers[topic].type
	  .. " vs. " .. type .. ")")
   assert(roslua.publishers[topic].publisher == publisher,
	  "Different publishers for topic " .. topic .. " on unregistering publisher")

   roslua.master:unregisterPublisher(topic)
   roslua.publishers[topic] = nil
end

function unregister_service(service, type, provider)
   assert(roslua.services[service], "Service " .. service .. " is not provided")
   assert(roslua.services[service].type == type, "Conflicting type for service " .. service
	  .. " while unregistering provider (" .. roslua.services[service].type
	  .. " vs. " .. type .. ")")
   assert(roslua.services[service].provider == provider,
	  "Different providers for service " .. service .. " on unregistering provider")

   roslua.master:unregisterService(service, roslua.services[service].provider:uri())
   roslua.services[service] = nil
end

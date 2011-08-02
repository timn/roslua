
----------------------------------------------------------------------------
--  registry.lua - Registry for topic/service registration
--
--  Created: Fri Jul 30 14:52:10 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Registry housekeeping.
-- This module contains functions used for housekeeping of subscriptions,
-- publishers, and services. They should not be used directly.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.registry", package.seeall)

require("roslua")

subscribers = {}
publishers  = {}
services    = {}
timers      = {}

--- Register subscriber.
-- As a side effect registers the subscriber with the master.
-- @param topic topic to register subscriber for
-- @param type type of topic
-- @param subscriber Subscriber instance to register
-- @see Subscriber
function register_subscriber(topic, type, subscriber)
   assert(not roslua.subscribers[topic], "Subscriber has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   roslua.subscribers[topic] = { type=type, subscriber=subscriber }

   local ok, pubs_err = pcall(roslua.master.registerSubscriber, roslua.master, topic, type)
   if not ok then
      error("Cannot connect to ROS master: " .. pubs_err)
   end
   subscriber:update_publishers(pubs_err, true)
end

--- Register publisher.
-- As a side effect registers the publisher with the master.
-- @param topic topic to register publisher for
-- @param type type of topic
-- @param publisher Publisher instance to register
-- @see Publisher
function register_publisher(topic, type, publisher)
   assert(not roslua.publishers[topic], "Publisher has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   local ok, subs_err  = pcall(roslua.master.registerPublisher, roslua.master, topic, type)
   if not ok then
      error("Cannot connect to ROS master: " .. subs_err)
   end
   roslua.publishers[topic] = { type=type, publisher=publisher }
end

--- Register service provider.
-- As a side effect registers the service provider with the master.
-- @param topic topic to register service provider for
-- @param type type of topic
-- @param provider Service instance to register
-- @see Service
function register_service(service, type, provider)
   assert(not roslua.services[service], "Service already provided")

   local ok = pcall(roslua.master.registerService, roslua.master, service, provider:uri())
   if not ok then
      error("Cannot connect to ROS master: " .. subs_err)
   end
   roslua.services[service] = { type=type, provider=provider }
end

--- Unregister subscriber.
-- As a side effect unregisters the subscriber with the master.
-- @param topic topic to register subscriber for
-- @param type type of topic
-- @param subscriber Subscriber instance to unregister
-- @see Subscriber
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

--- Unregister publisher.
-- As a side effect unregisters the publisher with the master.
-- @param topic topic to unregister publisher for
-- @param type type of topic
-- @param publisher Publisher instance to unregister
-- @see Publisher
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

--- Unregister service provider.
-- As a side effect unregisters the service provider with the master.
-- @param topic topic to unregister service provider for
-- @param type type of topic
-- @param provider Service instance to unregister
-- @see Service
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


--- Register timer.
-- @param timer timer to register
-- @see Timer
function register_timer(timer)
   assert(not roslua.timers[timer], "Timer has already been registered")

   roslua.timers[timer] = timer
end


--- Unregister timer
-- @param timer timer to unregister
-- @see Timer
function unregister_timer(timer)
   assert(roslua.timers[timer], "Timer has not been registered")

   roslua.timers[timer] = nil
end

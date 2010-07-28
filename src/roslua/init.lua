
----------------------------------------------------------------------------
--  init.lua - base file for roslua library
--
--  Created: Fri Jul 16 17:29:03 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua.master_proxy")
require("roslua.param_proxy")
require("roslua.slave_api")
require("roslua.slave_proxy")

require("roslua.msg_spec")
require("roslua.message")
require("roslua.subscriber")
require("roslua.publisher")

require("signal")

-- Imports from other libs to have a unified entry point
MsgSpec = roslua.msg_spec.MsgSpec
Message = roslua.message.RosMessage
Subscriber = roslua.subscriber.Subscriber
Publisher  = roslua.publisher.Publisher

get_msgspec = roslua.msg_spec.get_msgspec

quit = false

function init_node(args)
   roslua.master_uri = args.master_uri
   roslua.node_name  = args.node_name

   assert(roslua.master_uri, "ROS Master URI not set")
   assert(roslua.node_name, "Node name not set")
   roslua.anonymous = args.anonymous or false

   if anonymous then
      -- make up random name
      local posix = require("posix")
      roslua.node_name = string.format("%s_%s_%s", node_name,
				       posix.getpid("pid"), os.time() * 1000)
   end

   roslua.master = roslua.master_proxy.MasterProxy:new(roslua.master_uri, node_name)
   roslua.parameter_server = roslua.param_proxy.ParamProxy:new(roslua.master_uri, node_name)
   roslua.slave_api.init()
   roslua.slave_uri = roslua.slave_api.slave_uri()

   roslua.msg_spec.init()


   roslua.subscribers   = {}
   roslua.publishers    = {}
   roslua.slave_proxies = {}

   signal.signal(signal.SIGINT, roslua.exit)
end

function finalize()
   -- shutdown all connections
   for topic,s in pairs(roslua.subscribers) do
      s.subscriber:finalize()
      roslua.unregister_subscriber(topic, s.type, s.subscriber)
   end
   for topic,p in pairs(roslua.publishers) do
      p.publisher:finalize()
      roslua.unregister_publisher(topic, p.type, p.publisher)
   end
end


function exit()
   roslua.quit = true
end

function spin()
   roslua.slave_api.spin()

   -- spin subscribers for receiving
   local s
   for _,s in pairs(roslua.subscribers) do
      s.subscriber:spin()
   end
   -- spin publishers for accepting
   local p
   for _,p in pairs(roslua.publishers) do
      p.publisher:spin()
   end
end

function get_slave_proxy(uri)
   assert(uri, "No slave URI given")

   if not roslua.slave_proxies[uri] then
      roslua.slave_proxies[uri] = roslua.slave_proxy.SlaveProxy:new(uri, roslua.node_name)
   end
   return roslua.slave_proxies[uri]
end

function subscriber(topic, type)
   if not roslua.subscribers[topic] then
      local s = Subscriber:new(topic, type)
      roslua.register_subscriber(topic, type, s) -- this sets the subscribers table entry
   end
   return roslua.subscribers[topic].subscriber
end

function publisher(topic, type)
   if not roslua.publishers[topic] then
      local s = Publisher:new(topic, type)
      roslua.register_publisher(topic, type, s) -- this sets the publishers table entry
   end
   return roslua.publishers[topic].publisher
end

function register_subscriber(topic, type, subscriber)
   assert(not roslua.subscribers[topic], "Subscriber has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   roslua.subscribers[topic] = { type=type, subscriber=subscriber }

   local pubs  = roslua.master:registerSubscriber(topic, type)
   subscriber:update_publishers(pubs)
end

function register_publisher(topic, type, publisher)
   assert(not roslua.publishers[topic], "Publisher has already been registerd for "
	  .. topic .. " (" .. type .. ")")

   local subs  = roslua.master:registerPublisher(topic, type)
   roslua.publishers[topic] = { type=type, publisher=publisher }
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

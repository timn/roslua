
----------------------------------------------------------------------------
--  init.lua - base file for roslua library
--
--  Created: Fri Jul 16 17:29:03 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- ROS language binding for Lua.
-- This module and its sub-modules provides the necessary tools to write
-- ROS nodes in the Lua programming language. It supports subscribing to
-- and publishing topics, providing and calling services, and interacts with
-- the standard ROS tools to provide introspection information.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua", package.seeall)

require("roslua.master_proxy")
require("roslua.param_proxy")
require("roslua.slave_api")
require("roslua.slave_proxy")

require("roslua.msg_spec")
require("roslua.srv_spec")
require("roslua.message")
require("roslua.subscriber")
require("roslua.publisher")
require("roslua.service")
require("roslua.service_client")
require("roslua.registry")

require("signal")

-- Imports from other libs to have a unified entry point
MsgSpec = roslua.msg_spec.MsgSpec
Message = roslua.message.Message
Subscriber = roslua.subscriber.Subscriber
Publisher  = roslua.publisher.Publisher
Service = roslua.service.Service
ServiceClient = roslua.service_client.ServiceClient

--- Get message specification.
-- @name get_msgspec
-- @class function
-- @param msg_type message type (e.g. std_msgs/String). The name must include
-- the package.

--- Get service specification.
-- @name get_srvspec
-- @class function
-- @param srv_type service type (e.g. std_msgs/String). The name must include
-- the package.

get_msgspec = roslua.msg_spec.get_msgspec
get_srvspec = roslua.srv_spec.get_srvspec

subscribers   = roslua.registry.subscribers
publishers    = roslua.registry.publishers
services      = roslua.registry.services
slave_proxies = {}

--- Query this flag in your main loop and exit the application when it is set to
-- true.
quit = false


--- Initialize ROS node.
-- This function must be called before any other interaction with ROS or roslua
-- is possible. Note that the library can always accomodate only one ROS node per
-- interpreter instance!
-- A signal handler is set for SIGINT (e.g. after pressing Ctrl-C) to set the quit
-- flag to true if the signal is received.
-- @param args a table with argument entries. The following fields are mandatory:
-- master_uri The ROS master URI
-- node_name the name of the node using the library
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

   signal.signal(signal.SIGINT, roslua.exit)
end

--- Finalize this node.
-- Call this function when existing the program to allow for proper unregistering
-- of topic and services and to perform other cleanup tasks.
function finalize()
   -- shutdown all connections
   for topic,s in pairs(roslua.subscribers) do
      s.subscriber:finalize()
      roslua.registry.unregister_subscriber(topic, s.type, s.subscriber)
   end
   for topic,p in pairs(roslua.publishers) do
      p.publisher:finalize()
      roslua.registry.unregister_publisher(topic, p.type, p.publisher)
   end
   for service,s in pairs(roslua.services) do
      s.provider:finalize()
      roslua.registry.unregister_service(service, s.type, s.provider)
   end
end

--- Exit the program.
-- This sets the quit flag to true and will cause (proper) programs to exit.
function exit()
   roslua.quit = true
end


--- Spin the roslua main loop.
-- This will spin all registered subscribers, publishers and services, execute
-- callbacks and accpet new connections. Call this at the desired frequency. It is
-- recommended to call it as fast as possible, as the call frequency influences
-- the overall latency e.g. for processing service calls or delivering messages.
function spin()
   roslua.slave_api.spin()

   -- spin subscribers for receiving
   for _,s in pairs(roslua.subscribers) do
      s.subscriber:spin()
   end
   -- spin publishers for accepting
   for _,p in pairs(roslua.publishers) do
      p.publisher:spin()
   end
   -- spin service providers for accepting and processing
   for _,s in pairs(roslua.services) do
      s.provider:spin()
   end
end

--- Get a slave proxy.
-- Slave proxies are XML-RPC client-side wrappers to communicate with another
-- ROS node via the XML-RPC protocol, e.g. for requesting information or
-- topics. The proxies are maintained in a cache and there is always only one
-- instance of a slave for a specific remote node.
-- @param uri URI of remote slave
-- @return SlaveProxy instance
-- @see SlaveProxy
function get_slave_proxy(uri)
   assert(uri, "No slave URI given")

   if not roslua.slave_proxies[uri] then
      roslua.slave_proxies[uri] = roslua.slave_proxy.SlaveProxy:new(uri, roslua.node_name)
   end
   return roslua.slave_proxies[uri]
end

--- Get a new subscriber for a topic.
-- Request the creation of a subscriber for a specific topic. Subscribers are
-- maintained in a cache, and for any one topic there is always at most one
-- subscriber which is shared.
-- @param topic name of topic to request subscriber for
-- @param type type of topic
-- @return Subscriber instance for the requested topic
-- @see Publisher
function subscriber(topic, type)
   if not roslua.subscribers[topic] then
      local s = Subscriber:new(topic, type)
      roslua.registry.register_subscriber(topic, type, s) -- this sets the subscribers table entry
   end
   return roslua.subscribers[topic].subscriber
end

--- Get a new publisher for a topic.
-- Request the creation of a publisher for a specific topic. Publishers are
-- maintained in a cache, and for any one topic there is always at most one
-- publisher which is shared.
-- @param topic name of topic to request publisher for
-- @param type type of topic
-- @return Publisher instance for the requested topic
-- @see Publisher
function publisher(topic, type)
   if not roslua.publishers[topic] then
      local s = Publisher:new(topic, type)
      roslua.registry.register_publisher(topic, type, s) -- this sets the publishers table entry
   end
   return roslua.publishers[topic].publisher
end


--- Get a new service handler.
-- Request the creation of a new service, i.e. the server side or provider of
-- the service. An error is thrown if the service has already been registered.
-- @param service name of the provided service
-- @param type type of the provided service
-- @param handler the service handler, this is either a function or a class
-- instance which provides a service_call() method.
-- @see Service
-- @return Service instance for the requested service
function service(service, type, handler)
   assert(not roslua.services[service], "Service already provided")
   local s = Service:new(service, type, handler)
   roslua.registry.register_service(service, type, s)

   return roslua.services[service].provider
end

--- Get a service client.
-- Request the creation of a new service client to access a ROS service.
-- Service clients are not cached and a new client is created for every
-- new creation request.
-- @param service name of the requested service
-- @param type type of service
-- @param persistent true to request a persistent connection to the service
-- @see ServiceClient
function service_client(service, type, persistent)
   return ServiceClient:new{service, type, persistent=persistent}
end


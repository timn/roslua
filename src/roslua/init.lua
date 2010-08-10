
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
require("roslua.time")
require("roslua.logging")
require("roslua.logging.stdout")
require("roslua.logging.rosout")

require("signal")

local utils = require("roslua.utils")

-- Imports from other libs to have a unified entry point
MsgSpec = roslua.msg_spec.MsgSpec
Message = roslua.message.Message
Subscriber = roslua.subscriber.Subscriber
Publisher  = roslua.publisher.Publisher
Service = roslua.service.Service
ServiceClient = roslua.service_client.ServiceClient
Time = roslua.time.Time

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

local slave_proxies = {}
local spinners = {}

--- Query this flag in your main loop and exit the application when it is set to
-- true. We default to true, it is set to false in init_node(). This way we ensure
-- that init_node() was called.
quit = true

-- Add our custom loader, we do this outside of init to avoid having to call
-- init before loading required modules
table.insert(package.loaders, 4, utils.package_loader)

--- Initialize ROS node.
-- This function must be called before any other interaction with ROS or roslua
-- is possible. Note that the library can always accomodate only one ROS node per
-- interpreter instance!
-- A signal handler is set for SIGINT (e.g. after pressing Ctrl-C) to set the quit
-- flag to true if the signal is received.
-- @param args a table with argument entries. The following fields are mandatory:
-- <dl>
--  <dt>master_uri</dt><dd>The ROS master URI</dd>
--  <dt>node_name</dt><dd>the name of the node using the library</dd>
-- </dl>
-- The following fields are optional.
-- <dl>
--  <dt>no_rosout</dt><dd>Do not log to /rosout.</dd>
--  <dt>no_signal_handler</dt><dd>Do not register default signal handler.</dd>
-- </dl>

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

   roslua.logging.register_print_funcs(_G)
   roslua.logging.add_logger(roslua.logging.stdout.get_logger())
   if not args.no_rosout then
      roslua.logging.add_logger(roslua.logging.rosout.get_logger())
   end

   quit = false;
   if not args.no_signal_handler then
      signal.signal(signal.SIGINT, roslua.exit)
   end
end

--- Add a spinner.
-- The spinner will be called in every loop after the other events have been
-- processed.
-- @param spinner spinner to add, must be a function that is called without
-- any arguments in each spin.
function add_spinner(spinner)
   assert(type(spinner) == "function", "Spinner must be a function")
   for _, s in ipairs(spinners) do
      if s == spinner then
	 error("Spinner has already been registered", 0)
      end
   end
   table.insert(spinners, spinner);
end

--- Remove spinner.
-- @param spinner spinner to remove
function remove_spinner(spinner)
   for i, s in ipairs(spinners) do
      if s == spinner then
	 table.remove(spinners, i)
	 break;
      end
   end
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


--- Spin until program is stopped.
-- This will spin infinitely until roslua.quit is set to true, e.g. by
-- a interrupt signal after pressing Ctrl-C.
function run()
   while not roslua.quit do
      roslua.spin()
   end
   roslua.finalize()
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

   -- Spin all registered spinners
   -- work on a copy of the list as the list might change while we run the
   -- spinners if one of the removes itself
   local tmpspinners = {}
   for i, s in ipairs(spinners) do
      tmpspinners[i] = s
   end
   for _, s in ipairs(spinners) do
      s()
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

   if not slave_proxies[uri] then
      slave_proxies[uri] = roslua.slave_proxy.SlaveProxy:new(uri, roslua.node_name)
   end
   return slave_proxies[uri]
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
      roslua.registry.register_subscriber(topic, s.type, s) -- this sets subscribers table entry
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
      local p = Publisher:new(topic, type)
      roslua.registry.register_publisher(topic, p.type, p) -- this sets publishers table entry
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
   roslua.registry.register_service(service, s.type, s)

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

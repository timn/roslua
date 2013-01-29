
----------------------------------------------------------------------------
--  init.lua - base file for roslua library
--
--  Created: Fri Jul 16 17:29:03 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010-2011  Intel Labs Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- ROS language binding for Lua.
-- This module and its sub-modules provides the necessary tools to write
-- ROS nodes in the Lua programming language. It supports subscribing to
-- and publishing topics, providing and calling services, and interacts with
-- the standard ROS tools to provide introspection information.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Labs Pittsburgh,
-- SRI International
-- @release Released under BSD license
module("roslua", package.seeall)

local utils = require("roslua.utils")

-- Add our custom loader, we do this outside of init to avoid having to call
-- init before loading required modules
table.insert(package.loaders, 2, utils.package_loader)
table.insert(package.loaders, 4, utils.c_package_loader)

require("roslua.slave_api")
require("roslua.master_proxy")
require("roslua.param_proxy")
require("roslua.slave_proxy")

require("roslua.names")
require("roslua.msg_spec")
require("roslua.srv_spec")
require("roslua.message")
require("roslua.subscriber")
require("roslua.publisher")
require("roslua.service")
require("roslua.service_client")
require("roslua.registry")
require("roslua.time")
require("roslua.timer")
require("roslua.logging")
require("roslua.logging.rosout")

local signal = require("roslua.signal")
local socket = require("socket")

VERSION_MAJOR = 0
VERSION_MINOR = 6
VERSION_MICRO = 0
VERSION = VERSION_MAJOR .. "." .. VERSION_MINOR .. "." .. VERSION_MICRO

-- Imports from other libs to have a unified entry point
MsgSpec = roslua.msg_spec.MsgSpec
Message = roslua.message.Message
Subscriber = roslua.subscriber.Subscriber
Publisher  = roslua.publisher.Publisher
Service = roslua.service.Service
ServiceClient = roslua.service_client.ServiceClient
Time = roslua.time.Time
Duration = roslua.time.Duration
Timer = roslua.timer.Timer

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
resolve     = roslua.names.resolve

subscribers   = roslua.registry.subscribers
publishers    = roslua.registry.publishers
services      = roslua.registry.services
timers        = roslua.registry.timers

local slave_proxies = {}
local spinners = {}
local finalizers = {}

--- Query this flag in your main loop and exit the application when it is set to
-- true. We default to true, it is set to false in init_node(). This way we ensure
-- that init_node() was called.
quit = true

--- Assert a specific roslua version.
-- Throws an error if minimum version requirements are not met.
-- @param major minimum required major version
-- @param minor minimum required minor version (if major version is equal)
-- @param micro minimum required micro version (if major and minor versions are equal)
function assert_version(major, minor, micro)
   assert(major and minor and micro, "All version parts must be passed, use zero to ignore")
   if major >  VERSION_MAJOR
   or major == VERSION_MAJOR and minor >  VERSION_MINOR
   or major == VERSION_MAJOR and minor == VERSION_MINOR and micro > VERSION_MICRO
   then
      local reqv = string.format("%d.%d.%d", major, minor, micro)
      error("Insufficient roslua version, requested " ..reqv.. " vs. installed " .. VERSION)
   end
end

--- Initialize ROS node.
-- This function must be called before any other interaction with ROS or roslua
-- is possible. Note that the library can always accomodate only one ROS node per
-- interpreter instance!
-- A signal handler is set for SIGINT (e.g. after pressing Ctrl-C) to set the quit
-- flag to true if the signal is received.
-- @param args a table with argument entries. The following fields are mandatory:
-- <dl>
--  <dt>node_name</dt><dd>the name of the node using the library</dd>
-- </dl>
-- The following fields are optional.
-- <dl>
--  <dt>master_uri</dt><dd>The ROS master URI</dd>
--  <dt>namespace</dt><dd>Namespace to push node down to</dd>
--  <dt>no_rosout</dt><dd>Do not log to /rosout.</dd>
--  <dt>no_signal_handler</dt><dd>Do not register default signal handler.</dd>
-- </dl>
function init_node(args)
   roslua.master_uri = args.master_uri
   roslua.node_name  = args.node_name
   roslua.namespace  = args.namespace

   if not roslua.master_uri then
      roslua.master_uri = os.getenv("ROS_MASTER_URI")
   end
   if not roslua.namespace then
      roslua.namespace = os.getenv("ROS_NAMESPACE") or "/"
   end

   roslua.names.read_remappings()

   -- Overrides from remappings
   if roslua.names.remappings["__master"] then
      roslua.master_uri = roslua.names.remappings["__master"]
   end
   if roslua.names.remappings["__ns"] then
      roslua.namespace = roslua.names.remappings["__ns"]
   end
   if roslua.names.remappings["__name"] then
      roslua.node_name = roslua.names.remappings["__name"]
   end

   roslua.names.init_remappings()

   assert(roslua.master_uri, "ROS Master URI not set")
   assert(roslua.node_name, "Node name not set")
   assert(not roslua.node_name:match("^/"), "Node names may not begin with /")
   roslua.anonymous = args.anonymous or false

   roslua.msg_spec.init()

   if anonymous then
      -- make up random name
      local posix = require("posix")
      roslua.node_name = string.format("%s_%s_%s", roslua.node_name,
				       posix.getpid("pid"), os.time() * 1000)
   end

   roslua.node_name = resolve(roslua.node_name)

   roslua.master = roslua.master_proxy.MasterProxy:new()
   roslua.parameter_server = roslua.param_proxy.ParamProxy:new()
   roslua.slave_api.init()
   roslua.slave_uri = roslua.slave_api.slave_uri()

   roslua.logging.register_print_funcs(_G)
   if not args.no_rosout then
      roslua.logging.add_logger(roslua.logging.rosout.get_logger())
   end

   roslua.param_proxy.init()

   if roslua.parameter_server:has_param("/use_sim_time") then
      local use_sim_time = roslua.parameter_server:get_param("/use_sim_time")
      if use_sim_time then
	 roslua.time.init_simtime()
      end
   end

   math.randomseed(roslua.Time.now():to_sec())

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

--- Add a finalizer.
-- The finalizer will be called when roslua.finalize() is executed.
-- @param finalizer function which is called without arguments on finalization
function add_finalizer(finalizer)
   if type(finalizer) == "function" or
      (type(finalizer) == "table" and type(finalizer.finalize) == "function")
   then

      for _, f in ipairs(finalizers) do
         if f == finalizer then
            error("Finalizer has already been registered", 0)
         end
      end
      table.insert(finalizers, finalizer);

   else
      error("Finalizer must be a function, or table with finalize function entry",
            0)
   end
end

--- Remove finalizer.
-- @param finalizer finalizer to remove
function remove_finalizer(finalizer)
   for i, s in ipairs(finalizer) do
      if f == finalizer then
	 table.remove(finalizer, i)
	 break;
      end
   end
end

--- Finalize this node.
-- Call this function when existing the program to allow for proper unregistering
-- of topic and services and to perform other cleanup tasks.
function finalize()
   print("ROS node " .. roslua.node_name .. " is finalizing")

   -- Run custom finalizers
   local fcopy = {}
   for i, f in ipairs(finalizers) do fcopy[i] = f end
   for _, f in ipairs(fcopy) do
      if type(f) == "function" then
         f()
      else
         f:finalize()
      end
   end

   for _,t in pairs(roslua.timers) do
      t:finalize()
      roslua.registry.unregister_timer(t)
   end

   -- shutdown all connections
   for service,s in pairs(roslua.services) do
      s.provider:finalize()
      roslua.registry.unregister_service(service, s.type, s.provider)
   end
   for topic,s in pairs(roslua.subscribers) do
      s.subscriber:finalize()
      roslua.registry.unregister_subscriber(topic, s.type, s.subscriber)
   end
   for topic,p in pairs(roslua.publishers) do
      p.publisher:finalize()
      roslua.registry.unregister_publisher(topic, p.type, p.publisher)
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
-- @param desired loop frequency in Hz. If set to anything less or equal to zero
-- will run as fast as possible Warning, may cause high CPU load. Defaults to 25 Hz.
-- You should increase the loop frequency if you need small communication latencies.
function run(loop_frequency)
   if loop_frequency == nil then
      spin_time = 1. / 25
   elseif loop_frequency <= 0 then
      spin_time = 0
   else -- if loop_frequency > 0 then
      spin_time = 1. / loop_frequency
   end
   local last_spin_start = nil
   while not roslua.quit do
      local spin_start = roslua.Time.now()
      roslua.spin()
      local spin_end   = roslua.Time.now()
      local spin_runtime   = (spin_end - spin_start):to_sec()

      -- take overlong loop times into account
      local adjustment = 0
      if last_spin_start ~= nil then
	 adjustment = (spin_start - last_spin_start - spin_time):to_sec()
	 -- We only want positive adjustments. For one to guarantee that the
	 -- loop time is the minimum loop time and for another because negative
	 -- times have shown a more negative impact in experiments
	 if adjustment < 0 then adjustment = 0 end
      end

      local time_remaining = spin_time - spin_runtime - adjustment
      last_spin_start = spin_start

      if time_remaining > 0 then sleep(time_remaining) end
   end
   roslua.finalize()
end

--- Sleep the given number of seconds.
-- During the sleep time events will be processed if the sleep time is at least
-- 0.05 sec.
-- @param sec time in seconds or duration to sleep
function sleep(sec_or_duration)
   local duration
   if Duration.is_instance(sec_or_duration) then
      duration = sec_or_duration
   else
      local sec_full = math.floor(sec_or_duration)
      local sec_frac = math.floor((sec_or_duration - sec_full) * 1000000000)
      duration = Duration:new(sec_full, sec_frac)
   end
   local end_time = Time.now() + duration
   local now = Time.now()
   while not roslua.quit and now < end_time do
      spin()
      local diff = (end_time - now):to_sec()
      if diff > 0.05 then
	 socket.sleep(0.05)
      else
	 socket.sleep(diff)
      end
      now = Time.now()
   end
end

--- Spin the roslua main loop.
-- This will spin all registered subscribers, publishers and services, execute
-- callbacks and accpet new connections. Call this at the desired frequency. It is
-- recommended to call it as fast as possible, as the call frequency influences
-- the overall latency e.g. for processing service calls or delivering messages.
local spin_count = 0
local last_loop  = roslua.Time.now()
function spin()
   --local tracked_times = {}
   --tracked_times.total = {start = roslua.Time.now()}

   --*** Spin XML-RPC API Slave
   --tracked_times.api_slave = {start = roslua.Time.now()}
   roslua.slave_api.spin()
   --tracked_times.api_slave.endtime = roslua.Time.now()

   --*** spin subscribers for receiving
   --printf("*** Running subscribers")
   --tracked_times.subscribers = {start = roslua.Time.now()}
   for _,s in pairs(roslua.subscribers) do
      s.subscriber:spin()
   end
   --tracked_times.subscribers.endtime = roslua.Time.now()

   --*** spin publishers for accepting
   --printf("*** Running publishers")
   --tracked_times.publishers = {start = roslua.Time.now()}
   for _,p in pairs(roslua.publishers) do
      p.publisher:spin()
   end
   --tracked_times.publishers.endtime = roslua.Time.now()

   --*** spin service providers for accepting and processing
   --printf("*** Running service providers")
   --tracked_times.providers = {start = roslua.Time.now()}
   for _,s in pairs(roslua.services) do
      s.provider:spin()
   end
   --tracked_times.providers.endtime = roslua.Time.now()

   --printf("*** Running timers")
   --tracked_times.timers = {start = roslua.Time.now()}
   for _,t in pairs(roslua.timers) do
      t:spin()
   end
   --tracked_times.timers.endtime = roslua.Time.now()

   --*** Spin all registered spinners
   -- work on a copy of the list as the list might change while we run the
   -- spinners if one of the removes itself
   --printf("*** Running spinners")
   --tracked_times.spinners = {start = roslua.Time.now()}
   local tmpspinners = {}
   for i, s in ipairs(spinners) do
      tmpspinners[i] = s
   end
   for _, s in ipairs(spinners) do
      s()
   end

   --printf("*** DONE")

   --tracked_times.spinners.endtime = roslua.Time.now()
   --tracked_times.total.endtime = roslua.Time.now()

   --[[
   spin_count = spin_count + 1
   local now = roslua.Time.now()
   if (now - last_loop):to_sec() > 1 then
      printf("Currently making %d spins/sec", spin_count)
      last_loop = now
      spin_count = 0

      for k, t in pairs(tracked_times) do
	 local difftime = t.endtime - t.start
	 printf("%s spin time: %f sec", k, difftime:to_sec())
      end
   end
   --]]
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

--- Get node name.
-- @return node name
function get_name()
   return roslua.node_name
end

--- Get value from parameter server.
-- @param key of value
-- @return value, throws an error if not found
function get_param(key)
   return roslua.parameter_server:get_param(key)
end

--- Check if value exists in parameter server.
-- @param key of value
-- @return true if parameter exists, false otherwise
function has_param(key)
   return roslua.parameter_server:has_param(key)
end


--- Set value from parameter server.
-- @param key of value
-- @param value value to set
function set_param(key, value)
   return roslua.parameter_server:set_param(key, value)
end

--- Get a new subscriber for a topic.
-- Request the creation of a subscriber for a specific topic. Subscribers are
-- maintained in a cache, and for any one topic there is always at most one
-- subscriber which is shared.
-- @param topic name of topic to request subscriber for
-- @param type type of topic
-- @return Subscriber instance for the requested topic
-- @see Subscriber
function subscriber(topic, type)
   local resolved_topic = resolve(topic)
   if not roslua.subscribers[resolved_topic] then
      local s = Subscriber:new(resolved_topic, type)
      -- the following sets subscribers table entry
      roslua.registry.register_subscriber(resolved_topic, s.type, s)
   end
   return roslua.subscribers[resolved_topic].subscriber
end

--- Get a new publisher for a topic.
-- Request the creation of a publisher for a specific topic. Publishers are
-- maintained in a cache, and for any one topic there is always at most one
-- publisher which is shared.
-- @param topic name of topic to request publisher for
-- @param type type of topic
-- @param latching true to create latching publisher,
-- false or nil to create regular publisher
-- @return Publisher instance for the requested topic
-- @see Publisher
function publisher(topic, type, latching)
   local resolved_topic = resolve(topic)
   if not roslua.publishers[resolved_topic] then
      local p = Publisher:new(resolved_topic, type, latching)
      -- the following sets publishers table entry
      roslua.registry.register_publisher(resolved_topic, p.type, p)
   end
   return roslua.publishers[resolved_topic].publisher
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
   local resolved_service = resolve(service)
   assert(not roslua.services[resolved_service], "Service already provided")
   local s = Service:new(resolved_service, type, handler)
   roslua.registry.register_service(resolved_service, s.type, s)

   return roslua.services[resolved_service].provider
end

--- Get a service client.
-- Request the creation of a new service client to access a ROS service.
-- Service clients are not cached and a new client is created for every
-- new creation request.
-- @param service name of the requested service
-- @param type type of service
-- @param options a table defining additional for the service. The possible
-- valid fields are:
-- persistent: true to request a persistent connection to the service
-- simplified_return: true, to make the return value the unpacked array of the
-- returned message. This is useful for services which have a small return
-- value, e.g. just a boolean success flag or a few simple values. Note that
-- complex types will be flattened in the return value.
-- @see ServiceClient
function service_client(service, type, options)
   local resolved_service = resolve(service)
   local o = {resolved_service, type}
   if options and _G.type(options) == "table" then
      o.persistent=options.persistent
      o.simplified_return=options.simplified_return
   end
   return ServiceClient:new(o)
end


--- Create timer.
-- Creates a timer and registers it for execution.
-- @param interval minimum time between invocations, i.e. the desired
-- time interval between invocations. Either a number, which is
-- considered as time in seconds, or an instance of Duration.
-- @param callback_or_timer either callback function to execute when
-- the timer is due, or an instance of a Timer sub-class. In the
-- latter case finalization is invoked on roslua finalization.
function timer(interval, callback_or_timer)
   local t
   if Timer.is_instance(callback_or_timer) then
      t = callback_or_timer
   else
      t = Timer:new(interval, callback_or_timer)
   end
   roslua.registry.register_timer(t)
   return t
end


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

-- Imports from other libs to have a unified entry point
MsgSpec = roslua.msg_spec.MsgSpec
Message = roslua.message.RosMessage
Subscriber = roslua.subscriber.Subscriber

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

end

function finalize()
   -- shutdown all connections
end


function exit()
   roslua.quit = true
end

function spin()
   roslua.slave_api.spin()

   -- spin subscribers for receiving
   for _,subs in pairs(roslua.subscribers) do
      for _,s in ipairs(subs) do
	 s:spin()
      end
   end
end

function get_node_slave_proxy(node_name)
   local uri = roslua.master:lookupNode(remote_node)
   return get_slave_proxy(uri)
end

function get_slave_proxy(uri)
   assert(uri, "No slave URI given")

   if not roslua.slave_proxies[uri] then
      roslua.slave_proxies[uri] = roslua.slave_proxy.SlaveProxy:new(uri, roslua.node_name)
   end
   return roslua.slave_proxies[uri]
end

function register_subscriber(topic, type, subscriber)
   if roslua.subscribers[topic] then
      assert(roslua.subscribers[topic].type == type,
	     "Topic has already been registered with conflicting type " ..
		"(" .. roslua.subscribers[topic].type .. " vs. " .. type .. ")")
      table.insert(roslua.subscribers[topic], subscriber)
   else
      roslua.subscribers[topic] = { type=type, subscriber }
   end
end

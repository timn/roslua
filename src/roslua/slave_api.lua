
----------------------------------------------------------------------------
--  slave_api.lua - Slave XML-RPC API
--
--  Created: Thu Jul 22 19:06:06 2010 (at Intel Labs Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010       Intel Labs Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Slave API implementation.
-- This module provides the slave API to be called by other nodes. It uses
-- the Xavante HTTP server with the WSAPI interface to process XML-RPC
-- requests. The server is bound to a random port on startup.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.slave_api", package.seeall)

require("roslua")
require("xavante")
require("xavante.httpd")
require("wsapi.xavante")
require("wsapi.request")
require("xmlrpc")
require("posix")
require("socket")
assert(xmlrpc._VERSION_MAJOR and (xmlrpc._VERSION_MAJOR > 1 or xmlrpc._VERSION_MAJOR == 1 and xmlrpc._VERSION_MINOR >= 2),
       "You must use version 1.2 or newer of lua-xmlrpc")

__DEBUG = false

--- XML-RPC WSAPI handler
-- @param wsapi_env WSAPI environment
function wsapi_handler(wsapi_env)
  local headers = { ["Content-type"] = "text/xml" }

  local req = wsapi.request.new(wsapi_env)

  local method, arg_table = xmlrpc.srvDecode(req.POST.post_data)

  if __DEBUG then print("XML-RPC Slave API: " .. method .. " called") end

  local func = xmlrpc.dispatch(method)
  local result = { pcall(func, unpack(arg_table or {})) }
  local ok = result[1]
  if not ok then
     print_error("Slave API call '%s' failed: %s", method, result[2])
     result = { code = 3, message = result[2] }
  else
     table.remove(result, 1)
     if table.getn(result) == 1 then
	result = result[1]
     end
  end

  local r = xmlrpc.srvEncode(result, not ok)
  headers["Content-length"] = tostring(#r)

  local function xmlrpc_reply(wsapienv)
     coroutine.yield(r)
  end

  return 200, headers, coroutine.wrap(xmlrpc_reply)
end



-- XML-RPC exported functions
xmlrpc_exports = {}
xmlrpc_exports.system = {}

local ROS_CODE_ERROR   = -1
local ROS_CODE_FAILURE =  0
local ROS_CODE_SUCCESS =  1

-- (internal) encapsulate reply in ROS format
function rosreply_encaps(status, msg, reply)
   local rv = {status, msg, reply}
   return xmlrpc.newTypedValue(rv, xmlrpc.newArray())
end

--- List available methods.
-- @return list of available methods
function xmlrpc_exports.system.listMethods()
   local rv = {}
   for k,v in pairs(xmlrpc_exports) do
      if type(v) == "table" then
	 -- we recurse down at most one level
	 for k2,v2 in pairs(v) do
	    if type(v2) == "function" then
	       table.insert(rv, tostring(k) .. "." .. tostring(k2))
	    end
	 end
      elseif type(v) == "function" then
	 table.insert(rv, tostring(k))
      end
   end

   table.sort(rv)
   local arrtype = xmlrpc.newArray("string")
   return xmlrpc.newTypedValue(rv, arrtype)
end

--- Get bus stats.
-- @param caller_id ID of the calling node
-- @return bus stats
function xmlrpc_exports.getBusStats(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local publish_stats   = {}
   local subscribe_stats = {}
   local service_stats   = {}

   for topic, p in pairs(roslua.publishers) do
      local stats = p.publisher:get_stats()
      local conns = {}
      for _, c in ipairs(stats[2]) do
	 table.insert(conns, xmlrpc.newTypedValue(c, xmlrpc.newArray()))
      end
      local ct = {stats[1], conns}
      table.insert(publish_stats, xmlrpc.newTypedValue(ct, xmlrpc.newArray()))
   end

   for topic, s in pairs(roslua.subscribers) do
      print(topic)
      local stats = s.subscriber:get_stats()
      local conns = {}
      for _, c in ipairs(stats[2]) do
	 table.insert(conns, xmlrpc.newTypedValue(c, xmlrpc.newArray()))
      end
      local ct = {stats[1], conns}
      table.insert(publish_stats, xmlrpc.newTypedValue(ct, xmlrpc.newArray()))
   end

   local x_publish_stats   = xmlrpc.newTypedValue(publish_stats, xmlrpc.newArray())
   local x_subscribe_stats = xmlrpc.newTypedValue(subscribe_stats, xmlrpc.newArray())
   local x_service_stats   = xmlrpc.newTypedValue(service_stats, xmlrpc.newArray())

   local rv = {x_publish_stats, x_subscribe_stats, x_service_stats}
   local xrv = xmlrpc.newTypedValue(rv, xmlrpc.newArray("array"))

   return rosreply_encaps(ROS_CODE_SUCCESS, "", xrv)
end


--- Get bus info.
-- @param caller_id ID of the calling node
-- @return bus info
function xmlrpc_exports.getBusInfo(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local businfo = {}
   local topic, p, s

   for topic, s in pairs(roslua.subscribers) do
      for uri, p in pairs(s.subscriber.publishers) do
	 local conn = {p.uri, uri, "i", "TCPROS", topic,
		       p.state == roslua.Subscriber.PUBSTATE_COMMUNICATING}
	 local xconn = xmlrpc.newTypedValue(conn, xmlrpc.newArray())
	 table.insert(businfo, xconn)
      end
   end

   for topic, p in pairs(roslua.publishers) do
      for i, s in pairs(p.publisher.subscribers) do
	 local conn = {tostring(i), s.callerid, "o", "TCPROS", topic,
		       (s.state == roslua.Publisher.SUBSTATE_COMMUNICATING)}
	 local xconn = xmlrpc.newTypedValue(conn, xmlrpc.newArray())
	 table.insert(businfo, xconn)
      end
   end

   local xrv = xmlrpc.newTypedValue(businfo, xmlrpc.newArray("array"))
   return rosreply_encaps(ROS_CODE_SUCCESS, "", xrv)
end

--- Get master URI.
-- @param caller_id ID of the calling node
-- @return Master URI this node is connected to
function xmlrpc_exports.getMasterUri(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   return rosreply_encaps(ROS_CODE_SUCCESS, "", roslua.master_uri)
end


--- Shutdown this node
-- @param caller_id ID of the calling node
-- @param msg shutdown message
-- @return bus stats
function xmlrpc_exports.shutdown(caller_id, msg)
   assert(caller_id, "Caller ID argument is missing")

   roslua.quit = true

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)
end


--- Get process ID of node.
-- @param caller_id ID of the calling node
-- @return PID
function xmlrpc_exports.getPid(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local pid = posix.getpid("pid")
   return rosreply_encaps(ROS_CODE_SUCCESS, "", pid)
end

--- Get subscriptions of node.
-- @param caller_id ID of the calling node
-- @return list of subscriptions
function xmlrpc_exports.getSubscriptions(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local rv = {}

   for topic, s in pairs(roslua.subscribers) do
      table.insert(rv, xmlrpc.newTypedValue({topic, s.type}, xmlrpc.newArray("string")))
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", xmlrpc.newTypedValue(rv, xmlrpc.newArray("array")))
end

--- Get publications of node.
-- @param caller_id ID of the calling node
-- @return list of publications
function xmlrpc_exports.getPublications(caller_id)
   assert(caller_id, "Caller ID argument is missing")
   local rv = {}
   
   for topic, p in pairs(roslua.publishers) do
      table.insert(rv, xmlrpc.newTypedValue({topic, p.type}, xmlrpc.newArray("string")))
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", xmlrpc.newTypedValue(rv, xmlrpc.newArray("array")))
end

--- Parameter update notification.
-- Called by the parameter server if a subscribed value has changed.
-- @param caller_id ID of the calling node
-- @param param_key key of parameter
-- @param param_value value of parameter
function xmlrpc_exports.paramUpdate(caller_id, param_key, param_value)
   assert(caller_id, "Caller ID argument is missing")
   assert(param_key, "Parameter key is missing")
   assert(param_value, "Parameter value is missing")

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)
end


--- Publisher update.
-- Called when the list of available publishers for a topic changes.
-- @param caller_id ID of the calling node
-- @param topic topic for which the list changed
-- @param publishers array of currently available slave URIs
function xmlrpc_exports.publisherUpdate(caller_id, topic, publishers)
   assert(caller_id, "Caller ID argument is missing")
   assert(topic, "Topic name is missing")
   assert(publishers, "Publishers are missing")

   if roslua.subscribers[topic] then
      roslua.subscribers[topic].subscriber:update_publishers(publishers)
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)   
end


--- Topic connection request.
-- @param caller_id ID of the calling node
-- @param topic requested topic
-- @param protocols list of supported protocols
-- @return TCPROS connection configuration if topic is published
function xmlrpc_exports.requestTopic(caller_id, topic, protocols)
   assert(caller_id, "Caller ID argument is missing")
   assert(topic, "Topic name is missing")
   assert(protocols, "Protocols are missing")

   if not roslua.publishers[topic] then
      return rosreply_encaps(ROS_CODE_ERROR,
			     "Topic "..topic.." is not published on this node", 0)
   end

   if __DEBUG then print(caller_id .. " requests topic " .. topic) end

   for _,p in ipairs(protocols) do
      if p[1] == "TCPROS" then
	 -- ok, that we can handle
	 local protodef = {"TCPROS", socket.dns.gethostname(),
			   roslua.publishers[topic].publisher.port}
	 local xprotodef = xmlrpc.newTypedValue(protodef, xmlrpc.newArray())
	 if __DEBUG then
	    print_debug("Negotiated TCPROS for topic %s with caller %s: %s:%d",
			topic, caller_id, socket.dns.gethostname(),
			roslua.publishers[topic].publisher.port)
	 end
	 if __DEBUG then print_warn("TCP ROS for topic %s", topic) end
	 return rosreply_encaps(ROS_CODE_SUCCESS, "", xprotodef)
      end
   end

   if __DEBUG then print_error("No suitable protocol for topic %s", topic) end
   return rosreply_encaps(ROS_CODE_FAILURE, "No suitable protocol found", 0)   
end


-- Webserver Setup
local rules = {{ match = ".", with = wsapi.xavante.makeHandler(wsapi_handler) }}
local config = { server = {host = "*", port = 0}, defaultHost = { rules = rules} }


--- Init slave API.
-- This configures and starts the HTTP server and XML-RPC API.
function init()
   xmlrpc.srvMethods(xmlrpc_exports)
   xavante.HTTP(config)
end

--- Get slave URI.
-- @return URI for this slave
function slave_uri()
   local port = xavante.httpd.get_ports()[1]
   assert(port and port ~= "0", "Xavante patch for ephemeral port not applied. ".. 
	  "You need at least version 2.2.1 or later of Xavante, cf. README.")
   return "http://" .. socket.dns.gethostname() .. ":" .. port .. "/"
end

--- Process requests.
-- This processes XML-RPC API calls.
function spin()
   copas.step(0)
end


----------------------------------------------------------------------------
--  slave_api.lua - Slave XML-RPC API
--
--  Created: Thu Jul 22 19:06:06 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")
require("xavante")
require("xavante.httpd")
require("wsapi.xavante")
require("wsapi.request")
require("xmlrpc")
require("posix")
require("socket")


-- XML-RPC WSAPI handler
function wsapi_handler(wsapi_env)
  local headers = { ["Content-type"] = "text/html" }

  local req = wsapi.request.new(wsapi_env)

  local function xmlrpc_reply(wsapienv)
     local method, arg_table = xmlrpc.srvDecode(req.POST.post_data)

     local func = xmlrpc.dispatch(method)
     local result = { pcall(func, unpack(arg_table or {})) }
     local ok = result[1]
     if not ok then
	result = { code = 3, message = result[2] }
     else
	table.remove(result, 1)
	if table.getn(result) == 1 then
	   result = result[1]
	end
     end

     local r = xmlrpc.srvEncode(result, not ok)
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

function rosreply_encaps(status, msg, reply)
   local rv = {status, msg, reply}
   return xmlrpc.newTypedValue(rv, xmlrpc.newArray())
end

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


function xmlrpc_exports.getBusInfo(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local businfo = {}
   local topic, p, s

   for topic, s in pairs(roslua.subscribers) do
      for uri, p in pairs(s.subscriber.publishers) do
	 local conn = {p.uri, uri, "i", "TCPROS", topic, (p.connection ~= nil)}
	 local xconn = xmlrpc.newTypedValue(conn, xmlrpc.newArray())
	 table.insert(businfo, xconn)
      end
   end

   for topic, p in pairs(roslua.publishers) do
      for _, s in pairs(p.publisher.subscribers) do
	 local conn = {s.uri, "", "o", "TCPROS", topic, (s.connection ~= nil)}
	 local xconn = xmlrpc.newTypedValue(conn, xmlrpc.newArray())
	 table.insert(businfo, xconn)
      end
   end

   local xrv = xmlrpc.newTypedValue(businfo, xmlrpc.newArray("array"))
   return rosreply_encaps(ROS_CODE_SUCCESS, "", xrv)
end

function xmlrpc_exports.getMasterUri(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   return rosreply_encaps(ROS_CODE_SUCCESS, "", roslua.master_uri)
end


function xmlrpc_exports.shutdown(caller_id, msg)
   assert(caller_id, "Caller ID argument is missing")

   roslua.quit = true

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)
end


function xmlrpc_exports.getPid(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local pid = posix.getpid("pid")
   return rosreply_encaps(ROS_CODE_SUCCESS, "", pid)
end

function xmlrpc_exports.getSubscriptions(caller_id)
   assert(caller_id, "Caller ID argument is missing")

   local rv = {}

   for topic, s in pairs(roslua.subscribers) do
      table.insert(rv, xmlrpc.newTypedValue({topic, s.type}, xmlrpc.newArray("string")))
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", xmlrpc.newTypedValue(rv, xmlrpc.newArray("array")))
end

function xmlrpc_exports.getPublications(caller_id)
   assert(caller_id, "Caller ID argument is missing")
   local rv = {}
   
   for topic, p in pairs(roslua.publishers) do
      table.insert(rv, xmlrpc.newTypedValue({topic, p.type}, xmlrpc.newArray("string")))
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", xmlrpc.newTypedValue(rv, xmlrpc.newArray("array")))
end


function xmlrpc_exports.paramUpdate(caller_id, param_key, param_value)
   assert(caller_id, "Caller ID argument is missing")
   assert(param_key, "Parameter key is missing")
   assert(param_value, "Parameter value is missing")

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)
end


function xmlrpc_exports.publisherUpdate(caller_id, topic, publishers)
   assert(caller_id, "Caller ID argument is missing")
   assert(topic, "Topic name is missing")
   assert(publishers, "Publishers are missing")

   if roslua.subscribers[topic] then
      roslua.subscribers[topic].subscriber:update_publishers(publishers)
   end

   return rosreply_encaps(ROS_CODE_SUCCESS, "", 0)   
end


function xmlrpc_exports.requestTopic(caller_id, topic, protocols)
   assert(caller_id, "Caller ID argument is missing")
   assert(topic, "Topic name is missing")
   assert(protocols, "Protocols are missing")

   if not roslua.publishers[topic] then
      return rosreply_encaps(ROS_CODE_ERROR, "Topic us not published on this node", 0)
   end

   for _,p in ipairs(protocols) do
      if p[1] == "TCPROS" then
	 -- ok, that we can handle
	 local protodef = {"TCPROS", socket.dns.gethostname(),
			   roslua.publishers[topic].publisher.port}
	 local xprotodef = xmlrpc.newTypedValue(protodef, xmlrpc.newArray())
	 return rosreply_encaps(ROS_CODE_SUCCESS, "", xprotodef)
      end
   end

   return rosreply_encaps(ROS_CODE_FAILURE, "No suitable protocol found", 0)   
end


-- Webserver Setup
local rules = {{ match = ".", with = wsapi.xavante.makeHandler(wsapi_handler) }}
local config = { server = {host = "*", port = 0}, defaultHost = { rules = rules} }


function init()
   xmlrpc.srvMethods(xmlrpc_exports)
   xavante.HTTP(config)
end

function slave_uri()
   local port = xavante.httpd.get_ports()[1]
   return "http://" .. socket.dns.gethostname() .. ":" .. port
end

function spin()
   copas.step(0.1)
end

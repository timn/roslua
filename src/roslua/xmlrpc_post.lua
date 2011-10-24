
----------------------------------------------------------------------------
--  xmlrpc_post.lua - Concurrent execution of XML-RPC calls
--
--  Created: Wed Jul 13 14:43:00 2011 (at SRI International, Menlo Park, CA)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2011  Tim Niemueller [www.niemueller.de]
--             2011  SRI International
--             2011  Carnegie Mellon University
----------------------------------------------------------------------------

--- Concurrent XML-RPC client.
-- This module contains the XmlRpcPost class which can execute XML-RPC calls
-- concurrently. A method call is split up into multiple stages. A request
-- is started and on spinning required actions are taken (sending call,
-- waiting, reading and parsing the reply) with a minimum time overhead.
-- <br /><br />
-- The user should not have to directly interact with this class. It is used
-- by the SlaveProxy class to provide a way to concurrently call
-- requestTopic, an operation that can harm the overall performance (and
-- actually lead to deadlocks) when called blocking.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Labs Pittsburgh,
-- SRI International
-- @release Released under BSD license
module("roslua.xmlrpc_post", package.seeall)

require("socket")
require("socket.url")
require("xmlrpc")
assert(xmlrpc._VERSION_MAJOR and (xmlrpc._VERSION_MAJOR > 1 or xmlrpc._VERSION_MAJOR == 1 and xmlrpc._VERSION_MINOR >= 2),
       "You must use version 1.2 or newer of lua-xmlrpc")

require("roslua.utils")
local socket_send = roslua.utils.socket_send
local socket_recv = roslua.utils.socket_recv
local socket_recvline = roslua.utils.socket_recvline

local STATE_IDLE      = 1
local STATE_INITIATED = 2
local STATE_CONNECTED = 3
local STATE_POSTED    = 4
local STATE_RECEIVED  = 5
local STATE_FAILED    = 6

local num_to_state = { "IDLE", "INITIATED", "CONNECTED",
		       "POSTED", "RECEIVED", "FAILED"}

XmlRpcPost = {}

--- Constructor.
-- Setup a new concurrent XML-RPC call.
-- @param uri URI to use for method calls
-- @param method method name to pass. This parameter is optional, if passed
-- the call is started in the contructor.
-- @param ... any parameter required for the method call (only used if
-- method is passed)
function XmlRpcPost:new(uri, method, ...)
   assert(uri, "XmlRpcPost: uri must not be nil")

   local o = { uri=uri }
   setmetatable(o, self)
   self.__index = self

   o.state = STATE_IDLE

   if method then
      o:start_call(method, ...)
      self.args = { ... }
   end

   return o
end


--- Setup the request.
-- @param method name of method to call
-- @param ... any parameter required for the method call
function XmlRpcPost:setup_request(method, ...)
   local request_body = xmlrpc.clEncode(method, ...)
   self.args = { ... }

   local u = socket.url.parse(self.uri, {path="/"})

   self.request = {
      url = u,
      uri=socket.url.build({path=u.path}),
      method = method,
      http_method = "POST",
      request_body = request_body,
      headers = {
	 ["user-agent"] = xmlrpc._PKGNAME .. " " .. xmlrpc._VERSION,
	 ["host"] = u.host,
	 ["connection"] = "close",
	 ["content-type"] = "text/xml",
	 ["content-length"] = tostring(string.len(request_body)),
      },
   }

   for k,v in pairs(u) do
      --printf("U: %s: %s", k, tostring(v))
      self.request[k] = v
   end

   --for k,v in pairs(self.request) do
   --  printf("R: %s: %s", k, tostring(v))
   --end
end

--- Start a method call.
-- @param method name of method to call
-- @param ... any parameter required for the method call
function XmlRpcPost:start_call(method, ...)
   assert(self.state == STATE_IDLE, "A request is already running")

   self:setup_request(method, ...)

   self.c = socket.tcp()
   assert(self.c,
          string.format("XmlRpcPost: Failed to create TCP socket "..
                        "(host: %s, port %d, method: %s)",
                     self.request.host, self.request.port, method))
   self.c:settimeout(0)
   local ok, err = self.c:connect(self.request.host, self.request.port)
   if not ok then
      if err == "timeout" then
	 -- it might still complete at some point
	 self.state = STATE_INITIATED
      else
         self.c = nil
	 self.state = STATE_FAILED
	 error(err)
      end
   else
      -- Wow, that was fast
      self.state = STATE_CONNECTED
   end

   self.spinner = function () self:spin() end
   roslua.add_spinner(self.spinner)
end


--- Send the request to the server.
function XmlRpcPost:post_request()
   assert(self:writable(), "Socket is not ready for writing")
   if self.state >= STATE_POSTED then
      error("Request has already been sent")
   elseif self.state < STATE_CONNECTED then
      error("Socket is not connected, yet")
   end


   local reqline = string.format("%s %s HTTP/1.1\r\n",
				 self.request.http_method, self.request.uri)

   local bytes, err = socket_send(self.c, reqline)
   if bytes ~= #reqline then
      error("Failed to send XML-RPC request line to " ..
            self.uri .. " ("..tostring(err) .. ")", 0)
   end

   local h = "\r\n"
   for i, v in pairs(self.request.headers) do
      h = i .. ": " .. v .. "\r\n" .. h
   end
   local bytes, err = socket_send(self.c, h)
   if bytes ~= #h then
      error("Failed to send XML-RPC headers to " ..
            self.uri .. " ("..tostring(err) .. ")", 0)
   end
   
   local bytes, err = socket_send(self.c, self.request.request_body)

   if bytes ~= #self.request.request_body then
      error("Failed to send XML-RPC request to " ..
            self.uri .. " ("..tostring(err) .. ")", 0)
   end
end


--- Receive the HTTP status line.
-- @param yield_on_timeout if true the method will yield if the data
-- cannot be read immediately or completely.
function XmlRpcPost:receive_status_line(yield_on_timeout)
   local status = socket_recv(self.c, 5, yield_on_timeout)
   -- identify HTTP/0.9 responses, which do not contain a status line
   -- this is just a heuristic, but is what the RFC recommends
   if status ~= "HTTP/" then return nil, status end
   -- otherwise proceed reading a status line
   local remainder, err = socket_recvline(self.c, yield_on_timeout)
   if not remainder then return nil, err end

   status = status .. remainder
   
   local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
   return tonumber(code), status
end

--- Receive HTTP headers.
-- @param yield_on_timeout if true the method will yield if the data
-- cannot be read immediately or completely.
function XmlRpcPost:receive_headers(yield_on_timeout)
   local line, name, value, err
   local headers = {}
   -- get first line
   line, err = socket_recvline(self.c, yield_on_timeout)
   if err then return nil, err end
   -- headers go until a blank line is found
   while line ~= "" do
      -- get field-name and value
      name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
      if not (name and value) then return nil, "malformed reponse headers" end
      name = string.lower(name)
      -- get next line (value might be folded)
      line, err  = socket_recvline(self.c, yield_on_timeout)
      if err then return nil, err end
      -- unfold any folded values
      while string.find(line, "^%s") do
	 value = value .. line
	 line = socket_recvline(self.c, yield_on_timeout)
	 if err then return nil, err end
      end
      -- save pair in table
      if headers[name] then headers[name] = headers[name] .. ", " .. value
      else headers[name] = value end
   end
   return headers
end


--- Receive HTTP body.
-- @param headers headers that have been read before
-- @param yield_on_timeout if true the method will yield if the data
-- cannot be read immediately or completely.
function XmlRpcPost:receive_body(headers, yield_on_timeout)
   assert(headers["content-length"], "Server did not supply content length")

   local body = socket_recv(self.c, tonumber(headers["content-length"]),
			    yield_on_timeout)
   return body
end


--- Read the reply.
-- @param yield_on_timeout if true the method will yield if the data
-- cannot be read immediately or completely.
function XmlRpcPost:read_reply(yield_on_timeout)
   local code, status = self:receive_status_line(yield_on_timeout)
   assert(code, "Failed to receive status line, too old HTTP server?")

   local headers, err, body
   -- ignore any 100-continue messages
   while code == 100 do 
      headers, err = self:receive_headers(yield_on_timeout)
      code, status = self:receive_status_line(yield_on_timeout)
   end
   headers, err = self:receive_headers(yield_on_timeout)
   if not headers then
      self.state = STATE_FAILED
      self.error = "Receiving headers failed: " .. err
   else
      body = self:receive_body(headers, yield_on_timeout)
   end
   self.c:close()

   if self.state ~= STATE_FAILED and code == 200 then
      --printf("Received Body\n  -----\n%s\n  -----", body)
      local t = {xmlrpc.clDecode(body)}
      if not t[1] then
	 self.state = STATE_FAILED
	 self.error = "Call failed: " .. t[2]
      else
	 table.remove(t, 1)
	 self.result = t
	 self.state = STATE_RECEIVED
      end
   else
      self.state = STATE_FAILED
      self.error = "Failed with code " .. tostring(code)
   end

   return self.state == STATE_RECEIVED
end


--- Check if the connection is currently writable.
-- @return true if data can be written without blocking, false otherwise
function XmlRpcPost:writable()
   assert(self.state ~= STATE_IDLE, "writable(): no request running")
   local ready_r, ready_w = socket.select({}, {self.c}, 0)
   return (ready_w[self.c] ~= nil)
end

--- Check if the connection is currently readable.
-- @return true if data can be read without blocking, false otherwise
function XmlRpcPost:readable()
   assert(self.state ~= STATE_IDLE, "readable(): no request running")
   local ready_r, ready_w = socket.select({self.c}, {}, 0)
   return (ready_r[self.c] ~= nil)
end

--- Reset the currently running call.
-- The connection is closed and if a call was running the result is
-- ignored. New calls can be started after this method completes.
function XmlRpcPost:reset()
   self.state = STATE_IDLE
   roslua.remove_spinner(self.spinner)
   self.spinner = nil
   if self.request_running then
      self.c:close()
      self.c = nil
      self.request_running = false
   end
end


--- Check if a call is currently running.
-- Note that the call might be done or have failed, but reset() has not
-- been called.
-- @return true if currently not idle, false otherwise
function XmlRpcPost:running()
   return self.state ~= STATE_IDLE
end


--- Check if the call was successfully completed.
-- @return true if the call was succesfully completed
function XmlRpcPost:done()
   return self.state == STATE_RECEIVED
end


--- Check if the call has failed.
-- @return true if the call has failed
function XmlRpcPost:failed()
   return self.state == STATE_FAILED
end


--- Spin the call.
-- This method usually does not need to be called manually, rather it automtically
-- registers with roslua to be called on roslua.spin().
function XmlRpcPost:spin()
   --local old_state = self.state

   if self.state == STATE_INITIATED then
      -- check if we already connected
      if self:writable() then
	 self.state = STATE_CONNECTED
      end

   elseif self.state == STATE_CONNECTED then
      -- Send the request
      local ok, err = pcall(self.post_request, self)
      if not ok then
	 self.state = STATE_FAILED
	 self.error = err
      else
	 self.state = STATE_POSTED

	 self.read_coroutine =
	    coroutine.create(function ()
				return self:read_reply(true)
			     end)
      end

   elseif self.state == STATE_POSTED then
      -- check if reply can be read and do so if it is
      local data, err = coroutine.resume(self.read_coroutine)
      if not data then
	 print_warn("XMLRPC Post: failed to receive reply")
	 self.state = STATE_FAILED
	 self.error = "Failed to receive reply: " .. tostring(err)

      elseif coroutine.status(self.read_coroutine) == "dead" then
	 -- finished
	 self.read_coroutine = nil
      end

   elseif self.state == STATE_FAILED then
      -- We failed, remove spinner
      --printf("Call failed with '%s'", self.error)
      roslua.remove_spinner(self.spinner)
   end

   --if old_state  ~= self.state then
   --   printf("%s -> %s", num_to_state[old_state], num_to_state[self.state])
   --end
end


XmlRpcRequest = { uri = nil, method = nil, args = {} }

--- Constructor.
-- @param slave_uri XML-RPC HTTP slave URI
-- @param node_name name of this node
function XmlRpcRequest:new(uri, method, ...)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.uri         = uri
   o.method      = method
   o.args        = { ... }
   o.xmlrpc_post = XmlRpcPost:new(uri)

   o.xmlrpc_post:start_call(method, ...)

   return o
end

--- Destructor.
function XmlRpcRequest:finalize()
   self.xmlrpc_post:reset()
end


--- Check if concurrent execution is still busy.
-- @return true if execution is still busy, false otherwise
function XmlRpcRequest:busy()
   return self.xmlrpc_post.request and
      self.xmlrpc_post.request.method == self.method and
      self.xmlrpc_post:running()
end

--- Check if concurrent execution has successfully completed.
-- @return true if execution has succeeded, false otherwise
function XmlRpcRequest:succeeded()
   return self.xmlrpc_post:done()
end

--- Check if concurrent execution has failed.
-- @return true if execution has failed, false otherwise
function XmlRpcRequest:failed()
   return self.xmlrpc_post:failed()
end

--- Get error message if any.
-- @return error message if any, empty string otherwise
function XmlRpcRequest:error()
   return self.xmlrpc_post.error or ""
end

--- Result from completed concurrent call.
-- @return result of completed concurrent call
function XmlRpcRequest:result()
   assert(self.xmlrpc_post:done(), self.method .. " not done")
   if self.xmlrpc_post.result[1][1] ~= 1 then
      error(string.format("XML-RPC call %s failed on server: %s",
                          self.xmlrpc_post.request.method,
                          tostring(self.xmlrpc_post.result[1][2])), 0)
   end
   return self.xmlrpc_post.result[1][3]
end

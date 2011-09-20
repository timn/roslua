
----------------------------------------------------------------------------
--  tcpros.lua - Lua implementation of TCPROS protocol
--
--  Created: Sat Jul 24 14:02:06 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010-2011  Intel Research Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- TCPROS communication implementation.
-- This module contains classes that implement the TCPROS communication
-- protocol for topic as well as service communication. The user should not
-- have to use these directly, rather they are encapsulated by the
-- Publisher, Subscriber, Service, and ServiceClient classes.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.tcpros", package.seeall)

require("socket")
require("roslua.struct")
require("roslua.msg_spec")

TcpRosConnection = { payload = nil, received = false, max_receives_per_spin = 10 }

--- Constructor.
-- @param socket optionally a socket to use for communication
function TcpRosConnection:new(socket, name)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.socket    = socket
   o.msg_stats = {total = 0, received = 0, sent = 0}
   o.is_client = false

   if self.socket then
      self.socket:settimeout(0)
   end

   return o
end

--- Connect to given host and port.
-- @param host hostname or IP address of remote side
-- @param port port of remote side
-- @param timeout timeout to set on the socket after connecting. Note that
-- the connection itself is done with the system default timeout! Defaults
-- to 0 if omitted. Timeout is provided in seconds.
function TcpRosConnection:connect(host, port, timeout)
   assert(not self.socket, "Socket has already been created")
   self.socket = socket.tcp()
   local ok, err = pcall(self.socket.connect, self.socket, host, port)
   if not ok then error(err, 0) end
   self.socket:settimeout(timeout or 0)
   self.is_client = true
end

--- Connect non-blocking to given host and port.
-- @param host hostname or IP address of remote side
-- @param port port of remote side
function TcpRosConnection:connect_start(host, port)
   assert(not self.socket, "Socket has already been created")
   self.socket = socket.tcp()
   self.socket:settimeout(0)
   local ok, err = self.socket:connect(host, port)
   if not ok and err ~= "timeout" then
      error("Failed to connect to %s:%d: %s", host, port, err)
   end
   self.is_client = true
end

function TcpRosConnection:connect_done()
   assert(self.socket, "Connect has not been initiated")
   if self:writable() then
      return true
   else
      return false
   end
end

--- Close connection.
function TcpRosConnection:close()
   if self.socket then
      self.socket:close()
      self.socket = nil
   end
end

--- Bind to random port as server.
-- This will transform the socket into a server socket allowing to
-- accept connections. The socket will bind to a ephemeral port assigned
-- by the operating system. It will set the timeout of the socket to
-- zero to avoid locks on accepting new connections.
-- @see TcpRosConnection:get_ip_port()
-- @see TcpRosConnection:accept()
function TcpRosConnection:bind()
   assert(not self.socket, "Socket has already been created")
   self.socket = assert(socket.bind("*", 0))
   self.socket:settimeout(0)
end

--- Accept new connections.
-- @return array of new connections, possibly empty
function TcpRosConnection:accept()
   local conns = {}
   while true do
      local c = self.socket:accept()
      if not c then
	 break
      else
	 table.insert(conns, getmetatable(self):new(c))
      end
   end
   return conns
end

function TcpRosConnection:send_data(data)
   return roslua.utils.socket_send(self.socket, data)
end

function TcpRosConnection:receive_data(num_bytes, yield_on_timeout)
   return roslua.utils.socket_recv(self.socket, num_bytes, yield_on_timeout)
end

--- Get IP and port of socket.
-- @return two values, IP and port of socket
function TcpRosConnection:get_ip_port()
   return self.socket:getsockname()
end

--- Send out header.
-- @param header table with header fields to send
function TcpRosConnection:send_header(fields)
   local s = ""

   for k,v in pairs(fields) do
      local f  = k .. "=" .. v
      local fp = struct.pack("<!1i4", #f) .. f
      s = s .. fp
   end

   self:send_data(struct.pack("<!1i4", #s) .. s)
end

--- Receive header.
-- This will read the header from the network connection and store
-- it in the header field as well as return it.
-- @return table of header fields
function TcpRosConnection:receive_header(yield_on_timeout)
   self.header = {}

   local rd, err = self:receive_data(4, yield_on_timeout)
   if not rd then error("Connection " .. tostring(err), 0) end
   local packet_size = struct.unpack("<!1i4", rd)
   local packet, err = self:receive_data(packet_size, yield_on_timeout)
   if not packet then error("Connection " .. tostring(err), 0) end

   local i = 1

   while i <= packet_size do
      local field_size
      field_size, i = struct.unpack("<!1i4", packet, i)

      local sub = string.sub(packet, i, i+field_size)
      local eqpos = string.find(sub, "=")
      local k = string.sub(sub, 1, eqpos - 1)
      local v = string.sub(sub, eqpos + 1, field_size)

      self.header[k] = v

      i = i + field_size
   end

   return self.header
end


function TcpRosConnection:writable()
   local _, ready_w = socket.select({}, {self.socket}, 0)
   return (ready_w[self.socket] ~= nil)
end

function TcpRosConnection:readable()
   local ready_r, _ = socket.select({self.socket}, {}, 0)
   return (ready_r[self.socket] ~= nil)
end


--- Wait for a message to arrive.
-- This message blocks until a message has been received or the
-- timeout has been reached.
-- @param timeout optional timeout in seconds after which the waiting
-- should be aborted. An error is thrown if the timeout happens with
-- only the string "timeout". A missing timeout or if set to -1 will
-- cause it to wait indefinitely.
function TcpRosConnection:wait_for_message(timeout)
   local timeout = timeout or -1
   local start, now = roslua.Time.now()

   local selres
   repeat
      selres = socket.select({self.socket}, {}, timeout)
      now = roslua.Time.now()
   until selres[self.socket] or
      (timeout >= 0 and (now - start):to_sec() > timeout)

   -- Timeout, throw an error.
   if not selres[self.socket] then error("timeout", 0) end

   self:receive()
end

--- Check if data is available.
-- @return true if data can be read, false otherwise
function TcpRosConnection:data_available()
   local selres = socket.select({self.socket}, {}, 0)

   return selres[self.socket] ~= nil
end

--- Receive data from the network.
-- Upon return contains the new data in the payload field.
function TcpRosConnection:receive()
   local packet_size_d, err = self:receive_data(4)
   if not packet_size_d then return nil, err end
   local packet_size = struct.unpack("<!1i4", packet_size_d)

   if packet_size > 0 then
      self.payload, err = self:receive_data(packet_size)
      if not self.payload then return nil, err end
   else
      self.payload = ""
   end
   self.received = true
   self.msg_stats.received = self.msg_stats.received + 1
   self.msg_stats.total    = self.msg_stats.total    + 1

   return true
end

--- Check if data has been received.
-- @return true if data has been received, false otherwise. This method will
-- return true only once if data has been received, consecutive calls will
-- return false unless more data has been read with receive().
function TcpRosConnection:data_received()
   local rv = self.received
   self.received = false
   return rv
end

--- Get connection statistics.
-- @return six values: bytes received, bytes send, socket age in seconds,
-- messages received, messages sent, total messages processed (sent + received)
function TcpRosConnection:get_stats()
   local bytes_recv, bytes_sent, age = self.socket:getstats()
   return bytes_recv, bytes_sent, age,
          self.msg_stats.received, self.msg_stats.sent, self.msg_stats.total
end

--- Send message.
-- @param message either a serialized message string or a Message
-- class instance.
function TcpRosConnection:send(message)
   local bytes, error
   if type(message) == "string" then
      bytes, error = self:send_data(message)
   else
      local s = message:serialize()
      bytes, error = self:send_data(s)
   end
   self.msg_stats.sent  = self.msg_stats.sent  + 1
   self.msg_stats.total = self.msg_stats.total + 1
   return bytes, error
end

--- Spin ros connection.
-- This will read messages from the wire when they become available. The
-- field max_receives_per_spin is used to determine the maximum number
-- of messages read per spin.
function TcpRosConnection:spin()
   self.messages = {}
   local i = 1
   while self:data_available() and i <= self.max_receives_per_spin do
      local ok, err = pcall(self.receive, self)
      if not ok then error(err, 0) end
      i = i + 1
   end
end


TcpRosPubSubConnection = {}

--- Publisher/Subscriber connection constructor.
-- @param socket optionally a socket to use for communication
function TcpRosPubSubConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

function TcpRosPubSubConnection:send_header(fields)
   assert(fields.type, "You must specify a type name")
   TcpRosConnection.send_header(self, fields)
  
   self.msgspec = roslua.msg_spec.get_msgspec(fields.type)
end

--- Receive data from the network.
-- Upon return contains the new messages in the messages array field.
function TcpRosPubSubConnection:receive()
   local ok, err = TcpRosConnection.receive(self)
   if ok then
      local message = self.msgspec:instantiate()
      if not self.payload then
         error("payload is nil", 0)
      end
      local ok, err = xpcall(function() message:deserialize(self.payload) end, debug.traceback)
      if not ok then error(err, 0) end
      table.insert(self.messages, message)
   else
      if err == "closed" then
         error(err, 0)
      else
         error("Failed to receive (connection " .. err .. ")", 0)
      end
   end
end

--- Receive header.
-- This receives the header, asserts the type and loads the message
-- specification into the msgspec field.
-- @return table of headers
function TcpRosPubSubConnection:receive_header(yield_on_timeout)
   TcpRosConnection.receive_header(self, yield_on_timeout)

   if self.header.error ~= nil then
      error("Remote reported error: " .. tostring(self.header.error), 0)
   elseif self.header.type ~= "*" and self.header.type ~= self.msgspec.type then
      error("Type mismatched, got " .. tostring(self.header.type) ..
            ", but expected: " .. tostring(self.msgspec.type), 0)
   end

   return self.header
end


TcpRosServiceProviderConnection = {}

--- Service provider connection constructor.
-- @param socket optionally a socket to use for communication
function TcpRosServiceProviderConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

--- Receive data from the network.
-- Upon return contains the new messages in the messages array field.
function TcpRosServiceProviderConnection:receive()
   local ok, err = TcpRosConnection.receive(self)
   if ok then
      local message = self.srvspec.reqspec:instantiate()
      message:deserialize(self.payload)
      table.insert(self.messages, message)
   else
      error(err, 0)
   end
end


TcpRosServiceClientConnection = {}

--- Service client connection constructor.
-- @param socket optionally a socket to use for communication
function TcpRosServiceClientConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

--- Receive data from the network.
-- Upon return contains the new message in the message field.
function TcpRosServiceClientConnection:receive()
   -- get OK-byte
   local ok_byte_d, err = roslua.utils.socket_recv(self.socket, 1)
   if ok_byte_d == nil then
      if err == "closed" then
         error("closed", 0)
      else
         error("Reading OK byte failed: " .. err)
      end
   end
   local ok_byte = struct.unpack("<!1I1", ok_byte_d)

   if not TcpRosConnection.receive(self) then
      error("Service execution failed: failed to receive message")
   end

   if ok_byte == 1 then
      local message = self.srvspec.respspec:instantiate()
      message:deserialize(self.payload)
      self.message = message
   else
      if #self.payload > 0 then
         error("Service execution failed: " .. self.payload, 0)
      else
         error("Service execution failed (no error message received)")
      end
   end
end

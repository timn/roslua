
----------------------------------------------------------------------------
--  tcpros.lua - Lua implementation of TCPROS protocol
--
--  Created: Sat Jul 24 14:02:06 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("socket")
require("struct")
require("roslua.msg_spec")

TcpRosConnection = { payload = nil, received = false, max_receives_per_spin = 10 }

function TcpRosConnection:new(socket)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.socket = socket
   o.msg_stats = {total = 0, received = 0, sent = 0}

   return o
end


function TcpRosConnection:connect(host, port)
   assert(not self.socket, "Socket has already been created")
   self.socket = assert(socket.connect(host, port))
end

function TcpRosConnection:close()
   self.socket:close()
   self.socket = nil
end

function TcpRosConnection:bind()
   assert(not self.socket, "Socket has already been created")
   self.socket = assert(socket.bind("*", 0))
   self.socket:settimeout(0)
end

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

function TcpRosConnection:get_ip_port()
   return self.socket:getsockname()
end

function TcpRosConnection:send_header(fields)
   local s = ""

   for k,v in pairs(fields) do
      local f  = k .. "=" .. v
      local fp = struct.pack("<!1i4", #f) .. f
      s = s .. fp
   end

   self.socket:send(struct.pack("<!1i4", #s) .. s)
end

function TcpRosConnection:receive_header()
   self.header = {}

   local rd = self.socket:receive(4)
   local packet_size = struct.unpack("<!1i4", rd)

   local packet = self.socket:receive(packet_size)
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

function TcpRosConnection:wait_for_message()
   repeat
      local selres = socket.select({self.socket}, {}, -1)
   until selres[self.socket]
   self:receive()
end

function TcpRosConnection:data_available()
   local selres = socket.select({self.socket}, {}, 0)

   return selres[self.socket] ~= nil
end

function TcpRosConnection:receive()
   local ok, packet_size_d, err = pcall(self.socket.receive, self.socket, 4)
   if not ok or packet_size_d == nil then
      error(err, (err == "closed") and 0)
   end
   local packet_size = struct.unpack("<!1i4", packet_size_d)

   self.payload = assert(self.socket:receive(packet_size))
   self.received = true
   self.msg_stats.received = self.msg_stats.received + 1
   self.msg_stats.total    = self.msg_stats.total    + 1
end

function TcpRosConnection:data_received()
   local rv = self.received
   self.received = false
   return rv
end

function TcpRosConnection:get_stats()
   local bytes_recv, bytes_sent, age = self.socket:getstats()
   return bytes_recv, bytes_sent, age,
          self.msg_stats.received, self.msg_stats.sent, self.msg_stats.total
end

function TcpRosConnection:send(message)
   if type(message) == "string" then
      assert(self.socket:send(message))
   else
      local s = message:serialize()
      assert(self.socket:send(s))
   end
   self.msg_stats.sent  = self.msg_stats.sent  + 1
   self.msg_stats.total = self.msg_stats.total + 1
end

function TcpRosConnection:spin()
   self.messages = {}
   local i = 1
   while self:data_available() and i <= self.max_receives_per_spin do
      self:receive()
   end
end


--- @class TcpRosPubSubConnection
-- Connection implementation for publishers and subscribers.
TcpRosPubSubConnection = {}

function TcpRosPubSubConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

function TcpRosPubSubConnection:receive()
   TcpRosConnection.receive(self)

   local message = self.msgspec:instantiate()
   message:deserialize(self.payload)
   table.insert(self.messages, message)
end

function TcpRosPubSubConnection:receive_header()
   TcpRosConnection.receive_header(self)

   assert(self.header.type, "Opposite site did not set type")
   self.msgspec = roslua.msg_spec.get_msgspec(self.header.type)

   return self.header
end


--- @class TcpRosServiceProviderConnection
-- Connection implementation for service providers
TcpRosServiceProviderConnection = {}

function TcpRosServiceProviderConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

function TcpRosServiceProviderConnection:receive()
   TcpRosConnection.receive(self)

   local message = self.srvspec.reqspec:instantiate()
   message:deserialize(self.payload)
   table.insert(self.messages, message)
end


--- @class TcpRosServiceClientConnection
-- Connection implementation for service clients
TcpRosServiceClientConnection = {}

function TcpRosServiceClientConnection:new(socket)
   local o = TcpRosConnection:new(socket)

   setmetatable(o, self)
   setmetatable(self, TcpRosConnection)
   self.__index = self

   return o
end

function TcpRosServiceClientConnection:receive()
   -- get OK-byte
   local ok, ok_byte_d, err = pcall(self.socket.receive, self.socket, 1)
   if not ok or ok_byte_d == nil then
      error(err, (err == "closed") and 0)
   end
   local ok_byte = struct.unpack("<!1I1", ok_byte_d)

   TcpRosConnection.receive(self)

   if ok_byte then
      local message = self.srvspec.respspec:instantiate()
      message:deserialize(self.payload)
      self.message = message
   else
      error(self.payload, 0)
   end
end


----------------------------------------------------------------------------
--  talkertest.lua - Initial test of opening a connection
--
--  Created: Mon Jul 26 11:05:22 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

package.path  = ";;/homes/timn/ros/local/roslua/src/?/init.lua;/homes/timn/ros/local/roslua/src/?.lua;/usr/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua"
package.cpath = ";;/homes/timn/ros/local/roslua/src/roslua/?.so;/usr/lib/lua/5.1/?.so"

require("struct")

require("roslua")
require("roslua.slave_proxy")
require("roslua.tcpros")

StringMessage = { md5sum = "992ce8a1687cec8c8bd883ec73ca41d1" }

function StringMessage:new()
   local o = {}
   setmetatable(o, self)
   self.__index = self

   return o
end


--[[
1 Subscriber starts.
  It reads its command-line remapping arguments to resolve which topic name
  it will use. (Remapping Arguments)
2 Publisher starts.
  It reads its command-line remapping arguments to resolve which topic name
  it will use. (Remapping Arguments)
3 Subscriber registers with the Master. (XMLRPC)
4 Publisher registers with the Master. (XMLRPC)
5 Master informs Subscriber of new Publisher. (XMLRPC)
6 Subscriber contacts Publisher to request a topic connection and negotiate
  the transport protocol. (XMLRPC)
7 Publish sends Subscriber the settings for the selected transport
  protocol. (XMLRPC)
8 Subscriber connects to Publisher using the selected transport protocol.
  (TCPROS, etc...) 
--]]

roslua.init_node("http://irpwkst00-l:13476/", "/talkertest")
local uri = roslua.master:lookupNode("/talker")
print("Slave URI", uri)
local slave = roslua.slave_proxy.SlaveProxy:new(uri, "/talkertest")

local pid = slave:getPid()
print("PID", pid)

print("Requesting topic")
local proto = slave:requestTopic("/chatter")
local function print_table_rec(t, indent)
   local indent = indent or ""
   for k,v in pairs(t) do
      if type(v) == "table" then
	 print(indent .. "Recursing into table " .. k)
	 print_table_rec(v, indent .. "   ")
      else
	 print(indent .. k .. "=" .. tostring(v))
      end
   end
end
print_table_rec(proto)

function sleep(n)
  os.execute("sleep " .. tonumber(n))
end

print("Sleeping, fire up your wireshark")
--sleep(15)

local tcpconn = roslua.tcpros.TcpRosConnection:new()
tcpconn:connect(proto[2], proto[3])

tcpconn:send_header{callerid="/talkertest",
		    topic="/chatter",
		    type="std_msgs/String",
		    md5sum="992ce8a1687cec8c8bd883ec73ca41d1"}
local header = tcpconn:receive_header()
print_table_rec(header, "HEADER ")

while true do
   tcpconn:spin()
   if tcpconn:data_received() then
      print("Received:", tcpconn.payload)
   end
end

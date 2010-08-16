
----------------------------------------------------------------------------
--  srv_spec.lua - Service specification wrapper
--
--  Created: Thu Jul 29 11:04:13 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Service specification.
-- This module contains the SrvSpec class to read and represent ROS service
-- specification (YAML files). Service specifications should be obtained by
-- using the <code>get_srvspec()</code> function, which is aliased for
-- convenience as <code>roslua.get_srvspec()</code>.
-- <br /><br />
-- The service files are read on the fly, no offline code generation is
-- necessary. This avoids the need to write yet another code generator. After
-- reading the service specifications contains two fields, the reqspec field
-- contains the request message specification, the respspec field contains the
-- response message specification.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.srv_spec", package.seeall)

require("roslua.msg_spec")
require("md5")

local MsgSpec = roslua.msg_spec.MsgSpec

local srvspec_cache = {}

--- Get service specification.
-- It is recommended to use the aliased version <code>roslua.get_srvspec()</code>.
-- @param srv_type service type (e.g. std_msgs/String). The name must include
-- the package.
function get_srvspec(srv_type)
   roslua.utils.assert_rospack()

   if not srvspec_cache[srv_type] then
      srvspec_cache[srv_type] = SrvSpec:new{type=srv_type}
   end

   return srvspec_cache[srv_type]
end

--- Check if the given object is a message spec.
-- @param testobj object to test
-- @return true if testobj is a message spec, false otherwise
function is_srvspec(testobj)
   if type(testobj) == "table" then
      if getmetatable(testobj) == SrvSpec then
	 return true
      end
   end
   return false
end


SrvSpec = { request = nil, response = nil }

--- Constructor.
-- @param o Object initializer, must contain a field type with the string
-- representation of the type name.
function SrvSpec:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.type, "Service type is missing")

   o.package    = "roslib"
   o.short_type = o.type

   local slashpos = o.type:find("/")
   if slashpos then
      o.package    = o.type:sub(1, slashpos - 1)
      o.short_type = o.type:sub(slashpos + 1)
   end

   o:load()

   return o
end

-- (internal) load from iterator
-- @param iterator iterator that returns one line of the specification at a time
function SrvSpec:load_from_iterator(iterator)
   self.fields = {}
   self.constants = {}

   local request  = ""
   local response = ""

   local is_request = true

   -- extract the request and response message descriptions
   for line in iterator do
      if line == "---" then
	 is_request = false
      elseif is_request then
	 request = request .. line .. "\n"
      else
	 response = response .. line .. "\n"
      end
   end

   self.reqspec  = MsgSpec:new{type=self.type .. "_Request",
			       specstr = request}
   self.respspec = MsgSpec:new{type=self.type .. "_Response",
			       specstr = response}
end

--- Load specification from string.
-- @param s string containing the service specification
function SrvSpec:load_from_string(s)
   return self:load_from_iterator(s:gmatch("(.-)\n"))
end

--- Load service specification from file.
-- Will search for the appropriate service specification file (using rospack)
-- and will then read and parse the file.
function SrvSpec:load()
   local package_path = roslua.utils.find_rospack(self.package)
   self.file = package_path .. "/srv/" .. self.short_type .. ".srv"

   return self:load_from_iterator(io.lines(self.file))
end

-- (internal) Calculate MD5 sum.
-- Generates the MD5 sum for this message type.
-- @return MD5 sum as text
function SrvSpec:calc_md5()
   local s =
      self.reqspec:generate_hashtext() .. self.respspec:generate_hashtext()

   self.md5sum = md5.sumhexa(s)
   return self.md5sum
end

--- Get MD5 sum of type specification.
-- This will create a text representation of the service specification and
-- generate the MD5 sum for it. The value is cached so concurrent calls will
-- cause the cached value to be returned
-- @return MD5 sum of message specification
function SrvSpec:md5()
   return self.md5sum or self:calc_md5()
end

--- Print specification.
-- @param indent string (normally spaces) to put before every line of output
function SrvSpec:print()
   print("Service " .. self.type)
   print("MD5: " .. self:md5())
   print("Messages:")
   self.reqspec:print("  ")
   print()
   self.respspec:print("  ")
end


----------------------------------------------------------------------------
--  srv_spec.lua - Service specification wrapper
--
--  Created: Thu Jul 29 11:04:13 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua.msg_spec")
require("md5")

local MsgSpec = roslua.msg_spec.MsgSpec

local srvspec_cache = {}

function get_srvspec(srv_type)
   roslua.utils.assert_rospack()

   if not srvspec_cache[srv_type] then
      srvspec_cache[srv_type] = SrvSpec:new{type=srv_type}
   end

   return srvspec_cache[srv_type]
end


SrvSpec = { request = nil, response = nil }

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

function SrvSpec:load_from_string(s)
   return self:load_from_iterator(s:gmatch("(.-)\n"))
end

function SrvSpec:load()
   local package_path = roslua.utils.find_rospack(self.package)
   self.file = package_path .. "/srv/" .. self.short_type .. ".srv"

   return self:load_from_iterator(io.lines(self.file))
end

function SrvSpec:calc_md5()
   local s =
      self.reqspec:generate_hashtext() .. self.respspec:generate_hashtext()

   self.md5sum = md5.sumhexa(s)
   return self.md5sum
end

function SrvSpec:md5()
   return self.md5sum or self:calc_md5()
end

function SrvSpec:print()
   print("Service " .. self.type)
   print("MD5: " .. self:md5())
   print("Messages:")
   self.reqspec:print("  ")
   print()
   self.respspec:print("  ")
end

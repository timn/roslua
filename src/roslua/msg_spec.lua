
----------------------------------------------------------------------------
--  msg_spec.lua - Message specification wrapper
--
--  Created: Mon Jul 26 16:59:59 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("md5")
require("roslua.message")
require("roslua.utils")

BUILTIN_TYPES = { "int8","uint8","int16","uint16","int32","uint32",
		  "int64","uint64","float32","float64","string","bool",
		  "byte", "char"}
for _,v in ipairs(BUILTIN_TYPES) do
   BUILTIN_TYPES[v] = v
end
EXTENDED_TYPES = { time={"uint32", "uint32"}, duration={"int32", "int32"} }

local msgspec_cache = {}

function base_type(type)
   return type:match("^([^%[]+)") or type
end

function is_array_type(type)
   return type:find("%[") ~= nil
end

function is_builtin_type(type)
   local t = base_type(type)
   return BUILTIN_TYPES[t] ~= nil or  EXTENDED_TYPES[t] ~= nil
end

function resolve_type(type, package)
   if is_builtin_type(type) or type:find("/") then
      return type
   else
      return string.format("%s/%s", package, type)
   end
end

function get_msgspec(msg_type)
   roslua.utils.assert_rospack()

   if not msgspec_cache[msg_type] then
      msgspec_cache[msg_type] = MsgSpec:new{type=msg_type}
   end

   return msgspec_cache[msg_type]
end


MsgSpec = { md5sum = nil }

function MsgSpec:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.type, "Message type is missing")

   local slashpos = o.type:find("/")
   o.package    = "roslib"
   o.short_type = o.type
   if slashpos then
      o.package    = o.type:sub(1, slashpos - 1)
      o.short_type = o.type:sub(slashpos + 1)
   end

   if o.specstr then
      o:load_from_string(o.specstr)
   else
      o:load()
   end

   return o
end


function MsgSpec:load_from_iterator(iterator)
   self.fields = {}
   self.constants = {}

   for line in iterator do
      line = line:match("^([^#]*)") or ""   -- strip comment
      line = line:match("(.-)%s+$") or line -- strip trailing whitespace

      if line ~= "" then -- else comment or empty
	 local ftype, fname = string.match(line, "^([%w_/%[%]]+) ([%w_%[%]]+)$")
	 if ftype and fname then
	    if ftype == "Header" then ftype = "roslib/Header" end
	    self.fields[fname] = ftype
	    table.insert(self.fields, {ftype, fname, type=ftype, name=fname,
				       base_type=base_type(ftype)})
	 else -- check for constant
	    local ctype, cname, cvalue = line:match("^([%w_]+) ([%w_]+)=([%w]+)$")
	    if ctype and cname and cvalue then
	       self.constants[cname] = { ctype, cvalue }
	       table.insert(self.constants, {ctype, cname, cvalue})
	    else
	       error("Unparsable line: " .. line)
	    end
	 end
      end
   end
end

function MsgSpec:load_from_string(s)
   return self:load_from_iterator(s:gmatch("(.-)\n"))
end

function MsgSpec:load()
   local package_path = roslua.utils.find_rospack(self.package)
   self.file = package_path .. "/msg/" .. self.short_type .. ".msg"

   return self:load_from_iterator(io.lines(self.file))
end

function MsgSpec:generate_hashtext()
   local s = ""
   for _, spec in ipairs(self.constants) do
      s = s .. string.format("%s %s=%s\n", spec[1], spec[2], spec[3])
   end

   for _, spec in ipairs(self.fields) do
      if is_builtin_type(spec[1]) then
	 s = s .. string.format("%s %s\n", spec[1], spec[2])
      else
	 local msgspec = get_msgspec(base_type(resolve_type(spec[1], self.package)))
	 s = s .. msgspec:md5() .. " " .. spec[2] .. "\n"
      end
   end
   s = string.gsub(s, "^(.+)\n$", "%1") -- strip trailing newline

   return s
end

function MsgSpec:calc_md5()
   self.md5sum = md5.sumhexa(self:generate_hashtext())
   return self.md5sum
end


function MsgSpec:md5()
   return self.md5sum or self:calc_md5()
end


function MsgSpec:print(indent)
   local indent = indent or ""
   print(indent .. "Message " .. self.type)
   print(indent .. "Fields:")
   for _,s in ipairs(self.fields) do
      print(indent .. "  " .. s[1] .. " " .. s[2])
      if not is_builtin_type(s[1]) then
	 local msgspec = get_msgspec(base_type(resolve_type(s[1], self.package)))
	 msgspec:print(indent .. "    ")
      end
   end

   print(indent .. "MD5: " .. self:md5())
end


function MsgSpec:instantiate()
   return roslua.message.RosMessage:new(self)
end

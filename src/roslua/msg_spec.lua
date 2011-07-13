
----------------------------------------------------------------------------
--  msg_spec.lua - Message specification wrapper
--
--  Created: Mon Jul 26 16:59:59 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010-2011  Intel Research Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Message specification.
-- This module contains the MsgSpec class to read and represent ROS message
-- specification (YAML files). Message specifications should be obtained by
-- using the <code>get_msgspec()</code> function, which is aliased for
-- convenience as <code>roslua.get_msgspec()</code>.
-- <br /><br />
-- The message files are read on the fly, no offline code generation is
-- necessary. This avoids the need to write yet another code generator. After
-- reading the table field <code>fields</code> contains key value pairs, where
-- the keys are the names of the data fields and the value is the type of the
-- data field.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.msg_spec", package.seeall)

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

DEFAULT_PACKAGE = "std_msgs"

--- Initialize message sub-system.
function init()
   local ros_ver_codename, ros_ver_major, ros_ver_minor, ros_ver_micro =
      roslua.utils.rosversion()
   if ros_ver_major < 1 or (ros_ver_major == 1 and ros_ver_minor < 4) then
      DEFAULT_PACKAGE = "roslib"
   end
end

local msgspec_cache = {}

--- Get the base version of type, i.e. the non-array type.
-- @param type type to get base type for
-- @return base type, for array types returns the non-array type, for non-array
-- type returns the given value.
function base_type(type)
   return type:match("^([^%[]+)") or type
end

--- Check if type is an array type.
-- @param type type to check
-- @return true if given type is an array type, false otherwise
function is_array_type(type)
   return type:find("%[") ~= nil
end

--- Check if given type is a built-in type.
-- @param type type to check
-- @return true if type is a built-in type, false otherwise
function is_builtin_type(type)
   local t = base_type(type)
   return BUILTIN_TYPES[t] ~= nil or  EXTENDED_TYPES[t] ~= nil
end

--- Resolve the given type.
-- @param type to resolve
-- @param package to which the type should be resolve relatively
-- @return the given value if it is either a base type or contains a slash,
-- otherwise returns package/type.
function resolve_type(type, package)
   if is_builtin_type(type) or type:find("/") then
      return type
   else
      return string.format("%s/%s", package, type)
   end
end

--- Get message specification.
-- It is recommended to use the aliased version <code>roslua.get_msgspec()</code>.
-- @param msg_type message type (e.g. std_msgs/String). The name must include
-- the package.
function get_msgspec(msg_type, specstr)
   roslua.utils.assert_rospack()

   if not msgspec_cache[msg_type] then
      msgspec_cache[msg_type] = MsgSpec:new{type=msg_type, specstr=specstr}
   end

   return msgspec_cache[msg_type]
end

--- Check if the given object is a message spec.
-- @param testobj object to test
-- @return true if testobj is a message spec, false otherwise
function is_msgspec(testobj)
   if type(testobj) == "table" then
      if getmetatable(testobj) == MsgSpec then
	 return true
      end
   end
   return false
end




MsgSpec = { md5sum = nil }


--- Contstructor.
-- @param o Object initializer, must contain a field type with the string
-- representation of the type name. Optionally can contain a specstr field,
-- in which case the string will be parsed as message specification and no
-- attempt will be made to read the message specification file.
function MsgSpec:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.type, "Message type is missing")

   local slashpos = o.type:find("/")
   o.package    = DEFAULT_PACKAGE
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

   o.base_format, o.base_farray = o:generate_base_format()

   return o
end


--- Resolve a type relative to this message spec.
-- This is similar to the global resolve_type function, but the package parameter
-- can be omitted as it is taken from the message spec instance.
-- @param type type to resolve
-- @return resolved type
-- @see resolve_type()
function MsgSpec:resolve_type(type)
   return resolve_type(type, self.package)
end

-- (internal) load from iterator
-- @param iterator iterator that returns one line of the specification at a time
function MsgSpec:load_from_iterator(iterator)
   self.fields = {}
   self.constants = {}

   local field_i = 1

   for line in iterator do
      line = line:match("^([^#]*)") or ""   -- strip comment
      line = line:match("(.-)%s+$") or line -- strip trailing whitespace

      if line ~= "" then -- else comment or empty
	 local ftype, fname = string.match(line, "^([%w_/%[%]]+)[%s]+([%w_%[%]]+)$")
	 if ftype and fname then
	    if ftype == "Header" then ftype = DEFAULT_PACKAGE .. "/Header" end
	    ftype = self:resolve_type(ftype)
	    local msgspec = nil
	    if not is_builtin_type(ftype) then
	       -- load sub-spec
	       msgspec = get_msgspec(base_type(ftype))
	    end
	    local typeinfo = {ftype, fname, msgspec, type=ftype, name=fname,
			      base_type=base_type(ftype), spec=msgspec,
			      is_array=is_array_type(ftype),
			      is_builtin=is_builtin_type(ftype),
			      value_index=field_i}
	    self.fields[fname] = typeinfo
	    table.insert(self.fields, typeinfo)
	    field_i = field_i + 1
	 else -- check for constant
	    local ctype, cname, cvalue =
	       line:match("^([%w_]+)[%s]+([%w_]+)[%s]*=[%s]*([%w%s\"._-]+)$")
	    if ctype and cname and cvalue then
	       local nv = tonumber(cvalue)
	       if nv ~= nil then cvalue = nv end
	       self.constants[cname] = { ctype, cvalue, type=ctype, value=cvalue }
	       table.insert(self.constants, {ctype, cname, cvalue})
	    else
	       error(self.type .. " unparsable line: " .. line)
	    end
	 end
      end
   end
end

--- Load specification from string.
-- @param s string containing the message specification
function MsgSpec:load_from_string(s)
   return self:load_from_iterator(s:gmatch("(.-)\n"))
end

--- Load message specification from file.
-- Will search for the appropriate message specification file (using rospack)
-- and will then read and parse the file.
function MsgSpec:load()
   local package_path = roslua.utils.find_rospack(self.package)
   self.file = package_path .. "/msg/" .. self.short_type .. ".msg"

   return self:load_from_iterator(io.lines(self.file))
end


function MsgSpec:generate_base_format(prefix)
   local format = prefix or "<!1"
   local farray = {}
   local curfor = ""
   for _, f in ipairs(self.fields) do
      local fname = f.name
      local ftype = f.type
      local is_array   = f.is_array
      local is_builtin = f.is_builtin

      if is_array then
	 format = format .. "I4("
	 if curfor ~= "" then
	    table.insert(farray, curfor)
	    curfor = ""
	 end
	 if is_builtin then
	    format = format .. roslua.message.Message.builtin_formats[f.base_type]
	    table.insert(farray, {roslua.message.Message.builtin_formats[f.base_type]})
	 else
	    local subformat, subfarray = f.spec:generate_base_format("")
	    format = format .. subformat
	    table.insert(farray, subfarray)
	 end
	 format = format .. ")"
      else
	 if is_builtin then
	    format = format .. roslua.message.Message.builtin_formats[ftype]
	    curfor = curfor .. roslua.message.Message.builtin_formats[ftype]
	 else
	    local subformat, subfarray = f.spec:generate_base_format("")
	    format = format .. subformat
	    if curfor ~= "" then
	       table.insert(farray, curfor)
	       curfor = ""
	    end
	    for _, sa in ipairs(subfarray) do
	       table.insert(farray, sa)
	    end
	 end
      end
   end
   if curfor ~= "" then
      table.insert(farray, curfor)
   end
   
   return format, farray
end

-- (internal) create string representation appropriate to generate the hash
-- @return string representation
function MsgSpec:generate_hashtext()
   local s = ""
   for _, spec in ipairs(self.constants) do
      s = s .. string.format("%s %s=%s\n", spec[1], spec[2], spec[3])
   end

   for _, spec in ipairs(self.fields) do
      if is_builtin_type(spec[1]) then
	 s = s .. string.format("%s %s\n", spec[1], spec[2])
      else
	 local msgspec = get_msgspec(base_type(spec[1]))
	 s = s .. msgspec:md5() .. " " .. spec[2] .. "\n"
      end
   end
   s = string.gsub(s, "^(.+)\n$", "%1") -- strip trailing newline

   return s
end

-- (internal) Calculate MD5 sum.
-- Generates the MD5 sum for this message type.
-- @return MD5 sum as text
function MsgSpec:calc_md5()
   self.md5sum = md5.sumhexa(self:generate_hashtext())
   return self.md5sum
end


--- Get MD5 sum of type specification.
-- This will create a text representation of the message specification and
-- generate the MD5 sum for it. The value is cached so concurrent calls will
-- cause the cached value to be returned
-- @return MD5 sum of message specification
function MsgSpec:md5()
   return self.md5sum or self:calc_md5()
end


--- Print specification.
-- @param indent string (normally spaces) to put before every line of output
function MsgSpec:print(indent)
   local indent = indent or ""
   print(indent .. "Message " .. self.type)
   print(indent .. "Fields:")
   for _,s in ipairs(self.fields) do
      print(indent .. "  " .. s[1] .. " " .. s[2])
      if not is_builtin_type(s[1]) then
	 local msgspec = get_msgspec(base_type(s[1]))
	 msgspec:print(indent .. "    ")
      end
   end

   print(indent .. "MD5:    " .. self:md5())
   print(indent .. "Format: " .. self.base_format)
end


--- Check if given message is an instance of this spec.
-- @param message message instance to check
-- @return true if the message is an instantiation of this spec, false otherwise
function MsgSpec:is_instance(message)
   return type(message) == "table"
          and getmetatable(message) == roslua.Message
          and message.spec == self
end

--- Instantiate this message.
-- @return a Message instance of the specified message type.
-- @see roslua.message
function MsgSpec:instantiate(no_prefill)
   return roslua.Message:new(self, no_prefill)
end

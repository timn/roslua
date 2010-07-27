
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

BUILTIN_TYPES = { "int8","uint8","int16","uint16","int32","uint32",
		  "int64","uint64","float32","float64","string","bool",
		  "byte", "char"}
for _,v in ipairs(BUILTIN_TYPES) do
   BUILTIN_TYPES[v] = v
end
EXTENDED_TYPES = { time={"uint32", "uint32"}, duration={"int32", "int32"} }

local rospack_path_cache = {}
local msgdef_cache = {}

function base_type(type)
   return type:match("^([^%[]+)") or type
end

function is_builtin(type)
   local t = base_type(type)
   return BUILTIN_TYPES[t] ~= nil or  EXTENDED_TYPES[t] ~= nil
end

function resolve_type(type, package)
   if is_builtin(type) or type:find("/") then
      return type
   else
      return string.format("%s/%s", package, type)
   end
end

function init()
   local rv = os.execute("rospack 2>/dev/null")
   assert(rv == 0, "Cannot find rospack command, must be in PATH")

   -- so common that we resolve it right away
   get_msgspec("roslib/Header")
end


function find_rospack(package)
   if not rospack_path_cache[package] then
      local p = io.popen("rospack find " .. package)
      local path = p:read("*a")
      -- strip trailing newline
      rospack_path_cache[package] = string.gsub(path, "^(.+)\n$", "%1")
      p:close()
   end

   assert(rospack_path_cache[package], "Package path could not be found")
   return rospack_path_cache[package]
end


function get_msgspec(msg_type)

   local spec = MsgSpec:new(msg_type)

   msgdef_cache[msg_type] = spec
   return spec
end


MsgSpec = { md5sum = nil }

function MsgSpec:new(msgtype, file)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.msgtype = msgtype
   assert(o.msgtype, "Message type is missing")

   local slashpos = o.msgtype:find("/")
   o.package    = "roslib"
   o.short_type = o.msgtype
   if slashpos then
      o.package    = o.msgtype:sub(1, slashpos - 1)
      o.short_type = o.msgtype:sub(slashpos + 1)
   end

   o:load()

   return o
end


function MsgSpec:load()
   local package_path = find_rospack(self.package)
   self.file = package_path .. "/msg/" .. self.short_type .. ".msg"

   local line
   self.fields = {}
   self.constants = {}

   for line in io.lines(self.file) do
      line = line:match("^([^#]*)") or "" -- strip comment
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
   local line
   self.fields = {}

   for line in string.gmatch("^(.+)\n") do
      if not string.match(line, "^#.*$") then -- else comment
	 local ftype, fname = string.match(line, "^(%w+) (%w+)$")
	 self.fields[fname] = ftype
	 table.insert(self.fields, {ftype, fname})
      end
   end
end


function MsgSpec:calc_md5()
   local s = ""
   for _, spec in ipairs(self.constants) do
      s = s .. string.format("%s %s=%s\n", spec[1], spec[2], spec[3])
   end

   for _, spec in ipairs(self.fields) do
      if is_builtin(spec[1]) then
	 s = s .. string.format("%s %s\n", spec[1], spec[2])
      else
	 local msgspec = get_msgspec(base_type(resolve_type(spec[1], self.package)))
	 s = s .. msgspec:md5() .. " " .. spec[2] .. "\n"
      end
   end
   s = string.gsub(s, "^(.+)\n$", "%1") -- strip trailing newline

   self.md5sum = md5.sumhexa(s)
   return self.md5sum
end


function MsgSpec:md5()
   return self.md5sum or self:calc_md5()
end


function MsgSpec:print(indent)
   local indent = indent or ""
   print(indent .. self.msgtype)
   print(indent .. "Fields:")
   for _,s in ipairs(self.fields) do
      print(indent .. "  " .. s[1] .. " " .. s[2])
   end

   print(indent .. "MD5: " .. self:md5())
end


function MsgSpec:instantiate()

end


----------------------------------------------------------------------------
--  message.lua - Message base class
--
--  Created: Mon Jul 26 19:50:16 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("roslua")
require("struct")

RosMessage = { spec=nil }

function RosMessage:new(spec)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.spec   = spec
   o.values = {}
   assert(o.spec, "Message specification instance missing")

   return o
end

RosMessage.read_methods = {
   int8     = "<!1i1",   uint8   = "<!1I1",
   int16    = "<!1i2",   uint16  = "<!1I2",
   int32    = "<!1i4",   uint32  = "<!1I4",
   int64    = "<!1i8",   uint64  = "<!1I8",
   float32  = "<!1f",    float64 = "<!1d",
   char     = "<!1i1",   byte    = "<!1I1",
   duration = function (buffer, i)
		 local s, u
		 s, u, i = struct.unpack("<!1i4i4", buffer, i)
		 return {s, u}, i
	      end,
   time     = function (buffer, i)
		 local s, u
		 s, u, i = struct.unpack("<!1I4I4", buffer, i)
		 return {s, u}, i
	      end,
   string   = function (buffer, i)
		 local l
		 l, i = struct.unpack("<!1I4", buffer, i)
		 --print("String", i, l)
		 return buffer:sub(i,i+l-1), i+l
	      end,

   array    = function (buffer, i, typefunc)
		 local l, v, rv = {}
		 l, i = struct.unpack("<!1I4", buffer, i)
		 for li = 1, l do
		    local v
		    v, i = typefunc(buffer, i)
		    table.insert(rv, v)
		 end
		 
		 return rv, i
	      end
}

function RosMessage.simple_read(buffer, i, format)
   local s, v
   v, i = struct.unpack(format, buffer, i)
   return v, i
end
   


function RosMessage:deserialize(buffer, i)
   local i = i or 1

   for _, f in ipairs(self.spec.fields) do
      assert(i <= #buffer, self.spec.type .. ": buffer too short for message type (" ..
	     i .. " <= " .. #buffer .. ")")

      local fname = f.name
      local ftype = f.type
      local is_array = roslua.msg_spec.is_array_type(ftype)
      local num_values = 1

      if is_array then
	 ftype = roslua.msg_spec.base_type(ftype)
	 num_values, i = self.simple_read(buffer, i, self.read_methods["uint32"])
      end

      local rm = self.read_methods[ftype]

      for n = 1, num_values do
	 assert(i <= #buffer, self.spec.type .. ": buffer too short for message type (" ..
		i .. " <= " .. #buffer .. ")")
	 if rm then -- standard type
	    if type(rm) == "function" then
	       self.values[fname], i = rm(buffer, i)
	    else
	       self.values[fname], i = self.simple_read(buffer, i, rm)
	    end
	 else -- must be complex type, try to instantiate and deserialize
	    if not self.values[fname] then
	       local msgspec = roslua.msg_spec.get_msgspec(ftype)
	       self.values[fname] = msgspec:instantiate()
	    end
	    assert(self.values[fname], "Could not instantiate message of type " .. ftype)

	    i = self.values[fname]:deserialize(buffer, i)
	 end
      end
   end

   return i
end


function RosMessage:print(indent)
   local indent = indent or ""

   print(indent .. self.spec.type)
   for k, v in pairs(self.values) do
      if type(v) == "table" then
	 if self.spec.fields[k] == "time" or self.spec.fields[k] == "duration" then
	    print(indent .. "  " .. "k" .. "=" .. v[1] .. "." .. v[2])
	 elseif v.print then
	    v:print(indent .. "  ")
	 else
	    print(indent .. "  " .. k .. " [cannot print]")
	 end
      else
	 print(indent .. "  " .. k .. "=" .. tostring(v))
      end
   end
end

function RosMessage:serialize()
   local rv = ""

   return rv
end

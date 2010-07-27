
----------------------------------------------------------------------------
--  message.lua - Message base class
--
--  Created: Mon Jul 26 19:50:16 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

module(..., package.seeall)

require("struct")

--require("roslua.msg_spec")

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
   "int8"     = "<!1i1",   "uint8"   = "<!1I1",
   "int16"    = "<!1i2",   "uint16"  = "<!1I2",
   "int32"    = "<!1i4",   "uint32"  = "<!1I4",
   "int64"    = "<!1i8",   "uint64"  = "<!1I8",
   "float32"  = "<!1f",    "float64" = "<!1d",
   "char"     = "<!1i1",   "byte"    = "<!1I1",
   "duration" = function (buffer, i)
		   local s, u
		   s, u, i = struct.unpack("<!1i4i4", buffer)
		   return {s, u}, i
		end
   "time"     = function (buffer, i)
		   local s, u
		   s, u, i = struct.unpack("<!1I4I4", buffer)
		   return {s, u}, i
		end
   "string"   = function (buffer, i)
		   local l
		   l, i = struct.unpack("<!1I4", buffer)
		   return buffer:sub(i,i+l), i+l+1
		end

   "array"    = function (buffer, i, typefunc)
		   local l, v, rv = {}
		   l, i = struct.unpack("<!1I4", buffer)
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
   v, i = struct.unpack(format, buffer)
   return v, i
end
   


function RosMessage:deserialize(buffer)
   local i = 1
   
   for _, f in ipairs(self.spec.fields) do
      local rm = self.read_methods[f.type]
      if type(rm) == "function" then
	 self.values[f.name], i = rm(buffer, i)
      else
	 self.values[f.name], i = self.simple_read(buffer, i, rm)
      end
   end
end


function RosMessage:serialize()
   local rv = ""

   return rv
end

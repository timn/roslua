
----------------------------------------------------------------------------
--  message.lua - Message base class
--
--  Created: Mon Jul 26 19:50:16 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- ROS message representation.
-- This class incorporates a ROS message that can be sent and received over
-- a TCPROS connection. A message is created via the MsgSpec:instantiate()
-- method.
-- <br /><br />
-- A message has two important fields. One is the spec field. It contains a
-- reference a a MsgSpec instance describing this message. Further there is a
-- field values which is a dict table. It contains entries for the names of
-- the message fields storing the appropriate.
-- The values array has to be filled appropriately before sending a message,
-- and on deserializing a received message it will contain the received values.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.message", package.seeall)

require("roslua")
require("struct")

Message = { spec=nil }

--- Constructor.
-- @param spec message specification
function Message:new(spec)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.spec   = spec
   o.values = {}
   assert(o.spec, "Message specification instance missing")

   return o
end

-- simple read function
local function srf(format)
   return function (buffer, i)
	     local s, v
	     v, i = struct.unpack(format, buffer, i)
	     return v, i
	  end
end

-- (internal) table of read methods for built-in types
Message.read_methods = {
   int8     = srf("<!1i1"),   uint8   = srf("<!1I1"),
   int16    = srf("<!1i2"),   uint16  = srf("<!1I2"),
   int32    = srf("<!1i4"),   uint32  = srf("<!1I4"),
   int64    = srf("<!1i8"),   uint64  = srf("<!1I8"),
   float32  = srf("<!1f"),    float64 = srf("<!1d"),
   char     = srf("<!1i1"),   byte    = srf("<!1I1"),
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

-- (internal) table of default values for built-in types
Message.default_values = {
   int8     = 0,       uint8   = 0,
   int16    = 0,       uint16  = 0,
   int32    = 0,       uint32  = 0,
   int64    = 0,       uint64  = 0,
   float32  = 0,       float64 = 0,
   char     = 0,       byte    = 0,
   duration = {0, 0},  time    = {0, 0},
   string   = "",      array   = {}
}

-- (internal) table of formats for built-in types
Message.builtin_formats = {
   int8     = "i1",    uint8   = "I1",
   int16    = "i2",    uint16  = "I2",
   int32    = "i4",    uint32  = "I4",
   int64    = "i8",    uint64  = "I8",
   float32  = "f",     float64 = "d",
   char     = "i1",    byte    = "I1",
   duration = "i4i4",  time    = "I4I4",
   string   = "i4c0",  array   = "I4"
}

--- Deserialize received message.
-- This will deserialize the message according to the message specification.
-- Not that it is the users obligation to make sure that the buffer is correctly
-- typed for the message, especially that the buffer has the appropriate size.
-- @param buffer buffer that contains the message as read from the TCPROS connection
-- @param i Index from where to start parsing in the buffer, optional argument
-- that defaults to 1
function Message:deserialize(buffer, i)
   local i = i or 1

   self.values = {}

   for _, f in ipairs(self.spec.fields) do
      assert(i <= #buffer, self.spec.type .. ": buffer too short for message type (" ..
	     i .. " <= " .. #buffer .. ")")

      local fname = f.name
      local ftype = f.type
      local is_array = roslua.msg_spec.is_array_type(ftype)
      local num_values = 1

      if is_array then
	 ftype = roslua.msg_spec.base_type(ftype)
	 num_values, i = self.read_methods["uint32"](buffer, i)
      end

      local rm = self.read_methods[ftype]

      for n = 1, num_values do
	 assert(i <= #buffer, self.spec.type .. ": buffer too short for message type (" ..
		i .. " <= " .. #buffer .. ")")
	 if rm then -- standard type
	    self.values[fname], i = rm(buffer, i)
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


--- Print message.
-- @param indent string (normally spaces) to put before every line of output
function Message:print(indent)
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


--- Generate a value array from the stored values.
-- This is used for serialization, but also during execution of service calls.
-- @param flat_array if set to true (the default) will generate a flat array, which
-- means that the resulting value array from complex sub-messages are folded into
-- the array at the place where the field is defined. If set to false the value arrays
-- for the sub-messages are integrated verbatim as array at the appropriate
-- position.
-- @return positional array of values, output depends on flat_array param, see above.
function Message:generate_value_array(flat_array)
   local rv = {}
   local format = ""

   if flat_array == nil then flat_array = true end

   for _, f in ipairs(self.spec.fields) do

      local fname = f.name
      local ftype = f.type
      local is_builtin_type = roslua.msg_spec.is_builtin_type(ftype)
      local is_array = roslua.msg_spec.is_array_type(ftype)

      if is_array then
	 ftype = roslua.msg_spec.base_type(ftype)
      end

      -- if no value has been set, set default value
      if not self.values[fname] then
	 if is_array then -- just assume empty array
	    self.values[fname] = {}
	 elseif is_builtin_type then -- set default builtin value from table
	    self.values[fname] = self.default_values[ftype]
	 else -- generate new complex message with no values set to trigger defaults
	    self.values[fname] = roslua.get_msgspec(ftype):instantiate()
	 end
      end


      local v, j
      if is_builtin_type and is_array then
	 format = format .. "I4" .. string.rep(self.builtin_formats[ftype], #self.values[fname])
	 table.insert(rv, #self.values[fname])
	 for _,v in ipairs(self.values[fname]) do
	    if ftype == "duration" or ftype == "time" then
	       table.insert(rv, v[1])
	       table.insert(rv, v[2])
	    elseif ftype == "string" then
	       table.insert(rv, #v)
	       table.insert(rv, v)
	    else
	       table.insert(rv, v)
	    end
	 end
	    
      elseif is_builtin_type then
	 format = format .. self.builtin_formats[ftype]
	 if ftype == "duration" or ftype == "time" then
	    table.insert(rv, self.values[fname][1])
	    table.insert(rv, self.values[fname][2])
	 elseif ftype == "string" then
	    table.insert(rv, #self.values[fname])
	    table.insert(rv, self.values[fname])
	 else
	    table.insert(rv, self.values[fname])
	 end

      elseif is_array then -- it is a complex type and an array
	 for _,v in ipairs(self.values[fname]) do
	    local f, va = v:generate_value_array()
	    format = format .. f
	    if flat_array then
	       for _, j in ipairs(va) do
		  table.insert(rv, j)
	       end
	    else
	       table.insert(rv, va)
	    end
	 end

      else -- complex type, but *not* an array
	 local f, va = self.values[fname]:generate_value_array()
	 format = format .. f
	 if flat_array then
	    for _, j in ipairs(va) do
	       table.insert(rv, j)
	    end
	 else
	    table.insert(rv, va)
	 end
      end
   end

   return format, rv
end

--- Serialize message.
-- @return three values, the serialized string appropriate for sending over a
-- TCPROS connection, the used struct format, and the array of values
function Message:serialize()
   local rv = ""

   -- pack values into array in proper order
   for _, f in ipairs(self.spec.fields) do

      local fname = f.name
      local ftype = f.type
      local is_array = roslua.msg_spec.is_array_type(ftype)
      local num_values = 1

      if is_array then
	 ftype = roslua.msg_spec.base_type(ftype)
      end

      -- generate format string
      local format, arr = self:generate_value_array(true)

      format = "<!1" .. format

      -- pack it!
      local tmp = struct.pack(format, unpack(arr))
      rv = struct.pack("<!1I4c0", #tmp, tmp)

      return rv, format, arr
   end
end


--- Set message values from array.
-- Set the values field from the given array. Assumes a non-flat array layout
-- where positions of complex sub-messages contain an appropriate array of
-- values for the message (possibly recursively having arrays again).
-- @param arr array of values
function Message:set_from_array(arr)
   local i = 1
   for _, f in ipairs(self.spec.fields) do
      local ftype, fname = f.type, f.name
      if roslua.msg_spec.is_builtin_type(ftype) then
	 self.values[fname] = arr[i]
      else
	 local ms = roslua.get_msgspec(ftype)
	 local m = ms:instantiate()
	 m:set_from_array(arr[i])
	 self.values[fname] = m
      end
      i = i + 1
   end
end

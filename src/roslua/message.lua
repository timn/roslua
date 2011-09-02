
----------------------------------------------------------------------------
--  message.lua - Message base class
--
--  Created: Mon Jul 26 19:50:16 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010       Carnegie Mellon University
--             2010       Intel Research Pittsburgh
----------------------------------------------------------------------------

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
require("roslua.struct")

Message = { spec=nil }

--- Constructor.
-- @param spec message specification
function Message:new(spec, no_prefill)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.spec   = spec
   assert(o.spec, "Message specification instance missing")

   o.values = {}

   if not no_prefill then o:prefill() end

   return o
end


--- Clone this message.
-- This creates a new message and copies the values array to it. The method
-- recursively clones complex sub-type values.
function Message:clone()
   local m = Message:new(self.spec, true)
   for _, f in ipairs(self.spec.fields) do
      if f.is_array then
	 local t = {}
	 if f.is_builtin then
	    -- simply copy array
	    for i, v in ipairs(self.values[f.name]) do
	       t[i] = v
	    end
	 else
	    for i, v in ipairs(self.values[f.name]) do
	       t[i] = v:clone()
	    end
	 end
	 m.values[f.name] = t
      else
	 if f.is_builtin then
	    m.values[f.name] = self.values[f.name]
	 else
	    m.values[f.name] = self.values[f.name]:clone()
	 end
      end
   end

   return m
end


--- Copy values from message.
-- This method takes another message of the same type and copies all values
-- from that message to this message. An error is raised if the message types
-- do not match. This method checks values on the other message and only copies
-- non-nil values. It might be a good idea to prefill or erase all values
-- if you want to detect unset values.
function Message:copy(message)
   for _, f in ipairs(self.spec.fields) do
      if message.values[f.name] ~= nil then
	 if f.is_array then
	    local t = {}
	    if f.is_builtin then
	       -- simply copy array
	       for i, v in ipairs(self.values[f.name]) do
		  t[i] = v
	       end
	    else
	       for i, v in ipairs(self.values[f.name]) do
		  t[i] = v:clone()
	       end
	    end
	    m.values[f.name] = t
	 else
	    if f.is_builtin then
	       m.values[f.name] = self.values[f.name]
	    else
	       m.values[f.name] = self.values[f.name]:clone()
	    end
	 end
      end
   end
end


--- Prefill message with default values.
function Message:prefill()
   for _, f in ipairs(self.spec.fields) do
      if not self.values[f.name] then
	 if f.is_array then -- just assume empty array
	    self.values[f.name] = {}
	 elseif f.is_builtin then -- set default builtin value
	    self.values[f.name] = self.default_values[f.type]
	 else -- generate new complex msg with no values set to trigger defaults
	    self.values[f.name] = f.spec:instantiate()
	 end
      end
   end
end

-- (internal) table of default values for built-in types
Message.default_values = {
   bool     = 0,
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
   bool     = "I1",
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
-- @param buffer buffer that contains the message as read from the
-- TCPROS connection
-- @param i Index from where to start parsing in the buffer, optional
-- argument that defaults to 1
function Message:deserialize(buffer)
   local format = self:format_string(buffer, 1, self.farray, "")

   local values = {}
   local l = 0
   local i = 1
   for s in self:split_format(format) do
      l = l + #s
      local tmpval = struct.unpack_table("<!1" .. s, buffer, i)
      i = tmpval[#tmpval]
      table.remove(tmpval)
      for _, v in ipairs(tmpval) do
	 table.insert(values, v)
      end
   end
   self:read_values(values)
end

--- Format splitting iterator.
-- Splits the struct format after 200 characters (up to 202 if a string
-- definition would otherwise be illegal, e.g. a 'c' not followed by a 0, or
-- an i/I without the number of bytes).
-- @param format format to split
-- @return iterator function
function Message:split_format(format)
   local lenformat = #format
   local l = 1
   return function()
	     if l < lenformat then
		local lread = 200
		if lenformat - l < lread then
		   lread = lenformat - l + 1
		end
		local f = format:sub(l, l+lread-1)
		l = l + lread
                
                local last = format:sub(l-1,l-1)
                if last == "i" or last == "I" or last == "c" then
                   f = f .. format:sub(l,l)
                   l = l + 1
                end
		if format:sub(l, l+1) == "c0" then
		   f = f .. format:sub(l, l+1)
		   l = l + 2
                end

		return f
	     end
	  end
end


--- Generate format string.
-- The format string is based on the base format of the message specification,
-- but takes into account actual array sizes, replicating array parts as
-- necessary.
-- @param buffer incoming buffer to be deserialized
-- @param i index from where to start reading buffer
-- @param farray base format array from message spec, if nil the one from
-- internal spec is used (recursion parameter)
-- @param format prefix if nil set to little endian and 1 byte alignment
-- (recursion parameter)
function Message:format_string(buffer, i, farray, prefix)
   local rv = prefix or "<!1"
   local farray = farray or self.spec.base_farray
   for j, f in ipairs(farray) do
      if type(f) == "string" then
	 rv = rv .. f
	 local s = struct.size(f, buffer, i)
	 i = i + s
      else
	 local num
	 num, i = struct.unpack("I4", buffer, i)
	 rv = rv .. "I4"
	 local tmp
	 if #f == 1 and type(f[1]) == "string" and not f[1]:find("c") then
	    -- we have an array which only has one constant length pattern string
	    local format = ""
	    for n=1, num do
	       format = format .. f[1]
	    end
	    local s = struct.size(f[1])
	    i = i + (s * num)
	    rv = rv .. format
	 else
	    for n=1,num do
	       tmp, i = self:format_string(buffer, i, f, "")
	       rv = rv .. tmp
	    end
	 end
      end
   end
   return rv, i
end

--- Read values into values field.
-- This iterates over the given array and copies the values to the internal
-- values field, instantiating sub-classes as necessary.
-- @param values array, flat array with all values of the message
-- @param start index from where to start reading the values array
function Message:read_values(values, start)
   local fi = start or 1
   for _, f in ipairs(self.spec.fields) do
      if f.is_array then
	 local num = values[fi]
 	 fi = fi + 1
	 local array = {}
	 self.values[f.name] = array
	 if f.is_builtin then
	    if f.base_type == "time" or f.base_type == "duration" then
	       local class = roslua.Time
	       if f.base_type == "duration" then class = roslua.Duration end
	       for i = 1, num do
		  array[i] = class:new(values[fi], values[fi+1])
		  fi = fi + 2
	       end
	    elseif f.base_type == "bool" then
	       for i = 1, num do
		  if values[fi] == 1 then
		     array[i] = true
		  else
		     array[i] = false
		  end
	       end
	    else
	       for i = 1, num do
		  array[i] = values[fi]
		  fi = fi + 1
	       end
	    end
	 else
	    for i = 1, num do
	       array[i] = f.spec:instantiate(false)
	       fi = array[i]:read_values(values, fi)
	    end
	 end
      else
	 if f.is_builtin then
	    if f.base_type == "time" then
	       self.values[f.name] = roslua.Time:new(values[fi], values[fi+1])
	       fi = fi + 2
	    elseif f.base_type == "duration" then
	       self.values[f.name] = roslua.Duration:new(values[fi], values[fi+1])
	       fi = fi + 2
	    elseif f.base_type == "bool" then
	       if values[fi] == 1 then
		  self.values[f.name] = true
	       else
		  self.values[f.name] = false
	       end
	       fi = fi + 1
	    else
	       self.values[f.name] = values[fi]
	       fi = fi + 1
	    end
	 else
	    self.values[f.name] = f.spec:instantiate(false)
	    fi = self.values[f.name]:read_values(values, fi)
	 end
      end
   end
   return fi
end

function Message:print_value(indent, ftype, fname, fvalue)
   if type(fvalue) == "table" then
      if ftype == "time" or ftype == "duration" then
	 print(indent .. "  " .. "k" .. "=" .. fvalue[1] .. "." .. fvalue[2])
      elseif roslua.msg_spec.is_array_type(ftype) then
	 if #fvalue == 0 then
	    print(indent .. "  " .. fname .. " = []")
	 else
	    for i, a in ipairs(fvalue) do
	       self:print_value(indent .. "  ", roslua.msg_spec.base_type(ftype),
				fname .. "[" .. tostring(i) .. "]", a)
	    end
	 end
      elseif fvalue.print then
	 fvalue:print(indent .. "  ")
      else
	 print(indent .. "  " .. fname .. " [cannot print]")
      end
   else
      print(indent .. "  " .. fname .. "=" .. tostring(fvalue))
   end
end

--- Print message.
-- @param indent string (normally spaces) to put before every line of output
function Message:print(indent)
   local indent = indent or ""

   print(indent .. self.spec.type)
   for k, f in pairs(self.spec.fields) do
      self:print_value(indent, f.type, k, self.values[k])
   end
end


--- Generate a value array from the stored values.
-- This is used for serialization, but also during execution of
-- service calls.
-- @param flat_array if set to true (the default) will generate a flat
-- array, which means that the resulting value array from complex
-- sub-messages are folded into the array at the place where the field
-- is defined. If set to false the value arrays for the sub-messages
-- are integrated verbatim as array at the appropriate position.
-- @return positional array of values, output depends on flat_array
-- param, see above.
function Message:generate_value_array(flat_array, array)
   local rv = array or {}
   local format = ""

   if flat_array == nil then flat_array = true end

   for _, f in ipairs(self.spec.fields) do

      local fname = f.name
      local ftype = f.type

      if f.is_array then
	 ftype = f.base_type
      end

      -- if no value has been set, set default value
      if self.values[fname] == nil then
	 if f.is_array then -- just assume empty array
	    self.values[fname] = {}
	 elseif f.is_builtin then -- set default builtin value from table
	    self.values[fname] = self.default_values[ftype]
	 else -- generate new complex msg with no values set to trigger defaults
	    self.values[fname] = roslua.get_msgspec(ftype):instantiate()
	 end
      end


      local v, j
      if f.is_builtin and f.is_array then
	 format = format .. "I4"
	    .. string.rep(self.builtin_formats[ftype], #self.values[fname])
	 table.insert(rv, #self.values[fname])
	 for _,v in ipairs(self.values[fname]) do
	    if ftype == "duration" or ftype == "time" then
	       if roslua.Time.is_instance(v) then
		  table.insert(rv, v.sec)
		  table.insert(rv, v.nsec)
	       else
		  table.insert(rv, v[1])
		  table.insert(rv, v[2])
	       end
	    elseif ftype == "string" then
	       table.insert(rv, #v)
	       table.insert(rv, v)
	    elseif ftype == "bool" then
	       local bv = 0
	       if v then bv = 1 end
	       table.insert(rv, bv)
	    else
	       table.insert(rv, v)
	    end
	 end
	 
      elseif f.is_builtin then
	 format = format .. self.builtin_formats[ftype]
	 if ftype == "duration" or ftype == "time" then
	    if roslua.Time.is_instance(self.values[fname]) then
	       table.insert(rv, self.values[fname].sec)
	       table.insert(rv, self.values[fname].nsec)
	    else
	       table.insert(rv, self.values[fname][1])
	       table.insert(rv, self.values[fname][2])
	    end
	 elseif ftype == "string" then
	    table.insert(rv, #self.values[fname])
	    table.insert(rv, self.values[fname])
	 elseif ftype == "bool" then
	    local bv = 0
	    if self.values[fname] then bv = 1 end
	    table.insert(rv, bv)
	 else
	    table.insert(rv, self.values[fname])
	 end

      elseif f.is_array then -- it is a complex type and an array
	 format = format .. "I4"
	 table.insert(rv, #self.values[fname])
	 for _,v in ipairs(self.values[fname]) do
	    if f.spec then
	       assert(f.spec:is_instance(v),
		      "Expected message type is " .. f.spec.type
			 .. " but got type " .. tostring(v.type))
	    end
	    local f = v:generate_value_array(flat_array, rv)
	    format = format .. f
	 end

      else -- complex type, but *not* an array
	 if f.spec then
	    if not self.values[fname] then
	       self.values[fname] = f.spec:instantiate()
	    end
	    assert(f.spec:is_instance(self.values[fname]),
		   "Expected message type is " .. f.spec.type
		      .. " but got type " .. tostring(self.values[fname].type))
	 end
	 local f, va = self.values[fname]:generate_value_array(flat_array, rv)
	 format = format .. f
      end
   end

   return format, rv
end


--- Get plain value table.
-- This creates a new table which contains all the values from the values
-- field. The major difference is that this will be done recursively for
-- sub-message types.
-- @return value table
function Message:plain_value_table()
   local rv = {}
   for _, f in ipairs(self.spec.fields) do
      if f.is_builtin and f.is_array then
	 local arr = {}
	 for _, v in ipairs(self.values[f.name]) do
	    if f.type == "duration" or f.type == "time" then
	       if roslua.Time.is_instance(v) then
		  table.insert(arr, {v.sec, v.nsec})
	       else
		  table.insert(arr, {v[1], v[2]})
	       end
	    else
	       table.insert(arr, v)
	    end
	 end
	 rv[f.name] = arr
      elseif f.is_builtin then
	 if f.type == "duration" or f.type == "time" then
	    rv[f.name] = {self.values[f.name].sec, self.values[f.name].nsec}
	 else
	    rv[f.name] = self.values[f.name]
	 end
      elseif f.is_array then -- complex type array
	 local arr = {}
	 for _, v in ipairs(self.values[f.name]) do
	    table.insert(arr, v:plain_value_table())
	 end
	 rv[f.name] = arr
      else -- single complex type
	 rv[f.name] = self.values[f.name]:plain_value_table()
      end
   end
   return rv
end

--- Serialize message.
-- @return three values, the serialized string appropriate for sending over a
-- TCPROS connection, the used struct format, and the array of values
function Message:serialize()
   local rv = ""

   -- generate format string
   local format, arr = self:generate_value_array(true)

   format = "<!1" .. format

   -- pack it!
   local tmp = struct.pack(format, unpack(arr))
   rv = struct.pack("<!1I4c0", #tmp, tmp)

   return rv, format, arr
end


--- Set message values from array.
-- Set the values field from the given array. Assumes a non-flat array
-- layout.  Positions of complex sub-messages contain either contain
-- an instance of the appropriate message type or an appropriate array
-- of values for the message (possibly recursively having arrays
-- again).
-- @param arr array of values
function Message:set_from_array(arr)
   for i, f in ipairs(self.spec.fields) do
      local ftype, fname = f.type, f.name
      if f.is_builtin then
         if arr[fname] ~= nil then
            self.values[fname] = arr[fname]
         else
            self.values[fname] = arr[i]
         end
      elseif f.is_array then
	 -- complex type and array
	 local ma = {}
         if not arr[fname] and not arr[i] then
            self.values[fname] = {}
         else
	    local a = arr[fname] or arr[i] or {}
	    if a then
               local ms = roslua.get_msgspec(f.base_type)
	       for _,va in ipairs(a) do
                  if ms:is_instance(va) then
                     table.insert(ma, va:clone())
                  else
                     local m = ms:instantiate(false)
                     m:set_from_array(va)
                     table.insert(ma, m)
                  end
	       end
	       self.values[fname] = ma
	    end
         end
      else
	 -- complex, but not an array
	 local ms = roslua.get_msgspec(ftype)
         if arr[fname] and ms:is_instance(arr[fname]) then
            self.values[fname] = arr[fname]:clone()
         else
            local m = ms:instantiate(false)
            m:set_from_array(arr[fname] or arr[i] or {})
            self.values[fname] = m
         end
      end
   end
end

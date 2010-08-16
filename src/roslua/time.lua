
----------------------------------------------------------------------------
--  time.lua - time related classes and functions
--
--  Created: Mon Aug 09 14:11:59 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--             2010  Carnegie Mellon University
--             2010  Intel Research Pittsburgh
----------------------------------------------------------------------------

--- Time utility class for roslua.
-- This module provides the Time class. It uses the local clock or the
-- /clock topic depending whether simulation time has been initialized or
-- not.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.time", package.seeall)

require("roslua.posix")

local sub_clock
local sim_time

--- Local function called on simtime updates, i.e. new messages
-- for /clock.
-- @param message new Clock message
local function simtime_update(message)
   -- Have to actually test with a simulator, until then just give warning
   assert(sim_time < message.values.clock, "The time received from the simulator is smaller "..
	  "than the curerntly set time. This happened because of small increments to the "..
	  "nsec part of the last sim time update. It indicates that the simulator is "..
	  "producing updates too slow for too small increments of time. Check with roslua "..
	  "authors on what to do")
   sim_time = message.values.clock
end

--- Initialize simulation time.
-- This initializes the simulation time by subscribing to the /clock topic.
-- This function is called automatically from roslua.init_node() if required,
-- so you should not call this function directly.
function init_simtime()
   sub_clock = roslua.subscriber("/clock", "roslib/Clock")
   sub_clock.add_listener(simtime_update)
end


Time = { sec = 0, nsec = 0 }

--- Contructor.
-- @param sec seconds, 0 if not supplied
-- @param nsec nano seconds, 0 if not supploed
-- @return new Time instance
function Time:new(sec, nsec)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.sec  = sec  or 0
   o.nsec = nsec or 0

   -- for deserialization compatibility
   o[1]   = o.sec
   o[2]   = o.nsec

   return o
end

--- Check if given table is an instance of Time.
-- @param t instance to check
-- @return true if given object t is an instance of Time
function Time.is_instance(t)
   return getmetatable(t) == Time
end

--- Clone an instance (copy constructor).
-- @param time Time instance to clone
-- @return new instances for the same time as the given one
function Time:clone()
   return Time:new(self.sec, self.nsec)
end

--- Get current time.
-- @return new Time instance set to the current time
function Time.now()
   local t = Time:new()
   t:stamp()
   return t
end


--- Set to current time.
function Time:stamp()
   if sim_time then
      -- Add 1 to the nsec value to ensure that two consecutive calls to stamp will
      -- never return the same time, they wouldn't on a real system as well
      sim_time.nsec = sim_time.nsec + 1
      if sim_time.nsec >= 1000000000 then
	 sim_time.sec  = sim_time.sec + 1
	 sim_time.nsec = 0
      end
      self.sec, self.nsec = sim_time.sec, sim_time.nsec
   else
      self.sec, self.nsec = posix.clock_gettime("realtime")
   end
end

--- Create Time from seconds.
-- @param sec seconds since the epoch as a floating point number,
-- the fraction is converted internally to nanoseconds
-- @return new instance for the given time
function Time.from_sec(sec)
   local t = Time:new()
   t.sec  = math.floor(sec)
   t.nsec = (sec - t.sec) * 1000000000
   return t
end


--- Create Time from message array.
-- @param a array that contains two entries, index 1 must be seconds, index 2 must
-- be nano seconds.
-- @return new instance for the given time
function Time.from_message_array(a)
   local t = Time:new()
   t.sec  = a[1]
   t.nsec = math.floor(a[2] / 1000.)
   return t
end

--- Check if time is zero.
-- @return true if sec and nsec fields are zero, false otherwise
function Time:is_zero()
   return self.sec == 0 and self.nsec == 0
end


--- Set sec and nsec values.
-- @param sec new seconds value
-- @param nsec new nano seconds value
function Time:set(sec, nsec)
   self.sec  = sec or 0
   self.nsec = nsec or 0
end


--- Convert time to seconds.
-- @return floating point number in seconds.
function Time:to_sec()
   return self.sec + self.nsec / 1000000000
end


--- Add the given times t1 and t2.
-- @param t1 first time to add
-- @param t2 second time or duration to add
-- @return new time instance with the sum of t1 and t2
function Time.__add(t1, t2)
   local t = Time:new()
   t.sec  = t1.sec + t2.sec
   t.nsec = t1.nsec + t2.nsec
   if t.nsec > 1000000000 then
      local n = math.floor(t.nsec / 1000000000)
      t.sec  = t.sec  + n
      t.nsec = t.nsec - n * 1000000000
   end
   return t
end


--- Subtract t2 from t1.
-- @param t1 time to subtract from
-- @param t2 time or duration to subtract
-- @return new time instance for the result of t1 - t2
function Time.__sub(t1, t2)
   local t = Time:new()
   t.sec = t1.sec - t2.sec
   t.nsec = t1.nsec - t2.nsec
   if t.nsec < 0 then
      local n = math.floor(-t.nsec / 1000000000)
      t.sec  = t.sec  - n
      t.nsec = t.nsec + n * 1000000000
   end
   return t
end


--- Check if times equal.
-- @param t1 first time to compare
-- @param t2 second time to compare
-- @return true if t1 == t2, false otherwise
function Time.__eq(t1, t2)
   return t1.sec == t2.sec and t1.nsec == t2.nsec
end

--- Check if t1 is less than t2.
-- @param t1 first time to compare
-- @param t2 second time to compare
-- @return true if t1 < t2, false otherwise
function Time.__lt(t1, t2)
   return t1.sec < t2.sec or (t1.sec == t2.sec and t1.nsec < t2.nsec)
end

--- Check if t1 is greater than t2.
-- @param t1 first time to compare
-- @param t2 second time to compare
-- @return true if t1 > t2, false otherwise
function Time.__gt(t1, t2)
   return t1.sec > t2.sec or (t1.sec == t2.sec and t1.nsec > t2.nsec)
end


--- Convert time to string.
-- @param t time to convert
-- @return string representing this time
function Time.__tostring(t)
   if t.sec < 1000000000 then
      return tostring(t.sec) .. "." .. tostring(t.nsec)
   else
      local tm = posix.localtime(t.sec)
      return posix.strftime("%H:%M:%S", tm) .. "." ..tostring(t.nsec)
   end
end

--- Format time as string.
-- @param format format string, cf. documentation of your system's strftime
-- @return string representation of this time given the supplied format
function Time:format(format)
   local format = format or "%H:%M:%S"
   local tm = posix.localtime(t.sec)
   return posix.strftime(format, tm) .. "." ..tostring(t.nsec)
end



Duration = { sec = 0, nsec = 0 }

--- Contructor.
-- @param sec seconds, 0 if not supplied
-- @param nsec nano seconds, 0 if not supploed
-- @return new Time instance
function Duration:new(sec, nsec)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   o.sec  = sec  or 0
   o.nsec = nsec or 0

   -- for deserialization compatibility
   o[1]   = o.sec
   o[2]   = o.nsec

   return o
end

--- Check if given table is an instance of Time.
-- @param t instance to check
-- @return true if given object t is an instance of Time
function Duration.is_instance(t)
   return getmetatable(t) == Duration
end

--- Clone an instance (copy constructor).
-- @param time Time instance to clone
-- @return new instances for the same time as the given one
function Duration:clone()
   return Duration:new(self.sec, self.nsec)
end

--- Create Time from seconds.
-- @param sec seconds since the epoch as a floating point number,
-- the fraction is converted internally to nanoseconds
-- @return new instance for the given time
function Duration.from_sec(sec)
   local d = Duration:new()
   d.sec  = math.floor(sec)
   d.nsec = (sec - d.sec) * 1000000000
   return d
end


--- Create Time from message array.
-- @param a array that contains two entries, index 1 must be seconds, index 2 must
-- be nano seconds.
-- @return new instance for the given time
function Duration.from_message_array(a)
   local d = Duration:new()
   d.sec  = a[1]
   d.nsec = math.floor(a[2] / 1000.)
   return t
end

--- Check if time is zero.
-- @return true if sec and nsec fields are zero, false otherwise
function Duration:is_zero()
   return self.sec == 0 and self.nsec == 0
end


--- Set sec and nsec values.
-- @param sec new seconds value
-- @param nsec new nano seconds value
function Duration:set(sec, nsec)
   self.sec  = sec or 0
   self.nsec = nsec or 0
end


--- Convert duration to seconds.
-- @return floating point number in seconds.
function Duration:to_sec()
   return self.sec + self.nsec / 1000000000
end


--- Add the given durations d1 and d2.
-- @param d1 first duration to add
-- @param d2 second duration to add
-- @return new duration instance with the sum of d1 and d2
function Duration.__add(d1, d2)
   local d = Duration:new()
   d.sec  = d1.sec + d2.sec
   d.nsec = d1.nsec + d2.nsec
   if d.nsec > 1000000000 then
      local n = math.floor(d.nsec / 1000000000)
      d.sec  = d.sec  + n
      d.nsec = d.nsec - n * 1000000000
   end
   return d
end


--- Subtract d2 from d1.
-- @param d1 duration to subtract from
-- @param d2 duration to subtract
-- @return new duration instance for the result of d1 - d2
function Duration.__sub(d1, d2)
   local t = Duration:new()
   t.sec = d1.sec - d2.sec
   t.nsec = d1.nsec - d2.nsec
   if t.nsec < 0 then
      local n = math.floor(-t.nsec / 1000000000)
      t.sec  = t.sec  - n
      t.nsec = t.nsec + n * 1000000000
   end
   return t
end


--- Check if durations equal.
-- @param d1 first duration to compare
-- @param d2 second duration to compare
-- @return true if d1 == d2, false otherwise
function Duration.__eq(d1, d2)
   return d1.sec == d2.sec and d1.nsec == d2.nsec
end

--- Check if d1 is less than d2.
-- @param d1 first duration to compare
-- @param d2 second duration to compare
-- @return true if d1 < d2, false otherwise
function Duration.__lt(d1, d2)
   return d1.sec < d2.sec or (d1.sec == d2.sec and d1.nsec < d2.nsec)
end

--- Check if d1 is greater than d2.
-- @param d1 first duration to compare
-- @param d2 second duration to compare
-- @return true if d1 > d2, false otherwise
function Duration.__gt(d1, d2)
   return d1.sec > d2.sec or (d1.sec == d2.sec and d1.nsec > d2.nsec)
end


--- Convert duration to string.
-- @param t duration to convert
-- @return string representing this duration
function Duration.__tostring(t)
   return tostring(t.sec) .. "." .. tostring(t.nsec)
end

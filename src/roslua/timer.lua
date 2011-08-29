
----------------------------------------------------------------------------
--  timer.lua - Timer
--
--  Created: Fri Apr 15 12:07:33 2011
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010-2011  Intel Labs Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Timer.
-- This module contains the Timer class for periodical execution of a
-- function. A time period is given, in which the function should be
-- executed. Due to the nature of Lua, especially because it is inherently
-- single-threaded, the times cannot be guaranteed, rather, a minimum time
-- between calls to the function is defined.
-- <br /><br />
-- During spinning the all timers are evaluated and executed if the minimum
-- time has gone by. Make sure that timer callbacks are functions that run
-- quickly and have a very short duration as not to influence the overall
-- system performance negatively.
-- <br /><br />
-- The rate at which the spinning function is called defines the minimum
-- period for which timers can be called somewhat accurately. For
-- example, if the roslua.spin() function is called once every 30ms, then
-- these 30ms are the very minimum duration of a timer, a shorter time is
-- not possible. You will see increasing offsets between the
-- current_expected and current_real times which will periodically get
-- small once the offset approaches half the spinning time.
-- <br /><br />
-- The callback is invoked with a table as parameter of the following
-- entries:
--  * last_expected     Time when the last callback should have happened
--  * last_real         Time when the last callback actually happened
--  * current_expected  Time when the current callback should have happened
--  * current_real      Time at the start of the current execution
--  * last_duration     Time in seconds the last callback ran
--
-- @copyright Tim Niemueller, SRI International, Carnegie Mellon University,
-- Intel Labs Pittsburgh
-- @release Released under BSD license
module("roslua.timer", package.seeall)

require("roslua")

Timer = {DEBUG = false}


--- Constructor.
-- Create a new Timer instance.
-- @param period minimum time between invocations, i.e. the desired
-- time interval between invocations. Either a number, which is considered
-- as time in seconds, or an instance of Duration.
-- @param callback function to execute when the timer is due
function Timer:new(period, callback)
   local o = {}
   setmetatable(o, self)
   self.__index = self

   if roslua.Duration.is_instance(inverval) then
      o.period = period:to_sec()
   elseif type(period) == "number" then
      o.period = period
   else
      error("Period must be a number (time in seconds) or Duration")
   end
   o.callback = callback
   assert(o.callback, "Callback is missing")
   assert(type(o.callback) == "function", "Callback must be a function")

   local now = roslua.Time.now()
   o.event = { last_expected = now,
	       last_real = now,
	       current_expected = now + period,
	       current_real = nil,
	       last_duration = 0
	     }

   return o
end

--- Finalize instance.
function Timer:finalize()
   -- Subs, pubs etc. also do not auto-unregister, maybe later
   -- if roslua.registry.timers[self] then
   --   roslua.registry.unregister_timer(self)
   --end
end

--- Check if given table is an instance of Timer.
-- @param t instance to check
-- @return true if given object t is an instance of Timer, false otherwise
function Timer.is_instance(t)
   return getmetatable(t) == Timer
end

--- Default run function.
-- This function calls a registered callback function with the event
-- table as the only parameter.
function Timer:run()
   self.callback(self.event)
end

--- Check time and execute callback if due.
function Timer:spin()
   local now = roslua.Time.now()
   if now >= self.event.current_expected then
      self.event.current_real = now
      self:run()
      local after = roslua.Time.now()
      self.event.last_expected    = self.event.current_expected
      self.event.last_real        = self.event.current_real
      self.event.last_duration    = (after - now):to_sec()
      self.event.current_expected = self.event.last_expected + self.period
   end
end

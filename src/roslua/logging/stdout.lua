
----------------------------------------------------------------------------
--  stdout.lua - stdout logger
--
--  Created: Tue Aug 10 10:05:49 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

-- Save this so that it is not overwritten once the logger is initialized
-- and has overridden print
local print = print

--- Logging facilities for roslua.
-- This module provides a logger that logs to stdout.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.logging.stdout", package.seeall)

require("roslua.logging")

COLOR_GRAY     = "\27[2;37m"
COLOR_RED      = "\27[0;31m"
COLOR_BROWN    = "\27[0;33m"
COLOR_CYAN     = "\27[0;36m"
COLOR_PURPLE   = "\27[0;35m"
COLOR_NONE     = "\27[0;39m"

local overhang = {}
overhang[roslua.logging.DEBUG]= ""
overhang[roslua.logging.INFO] = " "
overhang[roslua.logging.WARN] = " "
overhang[roslua.logging.ERROR]= ""

--- Log message to stdout.
-- @param level log level
-- @param time timestamp of message
-- @param msg message
function log_stdout(level, time, msg)
   local color, color_none = "", ""
   if level == roslua.logging.DEBUG then
      color = COLOR_GRAY
   elseif level == roslua.logging.WARN then
      color = COLOR_BROWN
   elseif level == roslua.logging.ERROR then
      color = COLOR_RED
   elseif level == roslua.logging.FATAL then
      color = COLOR_CYAN
   end
   if color ~= "" then color_none = COLOR_NONE end

   io.write(string.format("%s[%s]%s %s %s%s\n", color, roslua.logging.log_level_strings[level],
			  overhang[level], tostring(time), msg, color_none))
end

--- Get logger.
-- @return initialized stdout logger
function get_logger()
   return log_stdout
end

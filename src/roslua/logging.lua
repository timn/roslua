
----------------------------------------------------------------------------
--  logging.lua - roslua logging facilities
--
--  Created: Tue Aug 10 09:46:10 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010       Intel Research Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Logging facilities for roslua.
-- This module provides the framework for logging messages. Multiple loggers
-- can be registered which are called for output. Two submodules are
-- provided for logging to stdout and to rosout.
-- A convenience method overrides the internal print function and adds a few
-- more for specific log levels for convenient logging.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.logging", package.seeall)

DEBUG =  1
INFO  =  2
WARN  =  4
ERROR =  8
FATAL = 16

log_level_strings = {}
log_level_strings[DEBUG] = "DEBUG"
log_level_strings[INFO]  = "INFO"
log_level_strings[WARN]  = "WARN"
log_level_strings[ERROR] = "ERROR"
log_level_strings[FATAL] = "FATAL"

local log_level = DEBUG
local loggers = {}

require("roslua.logging.stdout")
local stdout_logger = roslua.logging.stdout.get_logger()
loggers[stdout_logger] = stdout_logger

--- Add a logger.
-- @param logger logger to add, must be a function that accepts three arguments,
-- the log level (number), the time (Time instance), and the message (string)
function add_logger(logger)
   assert(type(logger) == "function", "Logger must be a function")
   loggers[logger] = logger
end

--- Remove a logger.
-- @param logger logger to remove
function remove_logger(logger)
   loggers[logger] = nil
end

--- Remove the stdout logger which is added by default.
function remove_stdout_logger()
   remove_logger(stdout_logger)
   stdout_logger = nil
end

--- Set the log level
-- @param level log level. Anything of the same or a higher level is shown.
-- Anything below is not.
function set_log_level(level)
   log_level = level
end


--- Register print functions.
-- In the given environment it overwrites the print function and adds printf,
-- print_debug, print_info, print_warn, print_error, and print_fatal.
-- @param export_to module or table to export to
function register_print_funcs(export_to)
   export_to.printscr    = _M.printscr
   export_to.print       = _M.print
   export_to.printf      = _M.printf
   export_to.print_debug = _M.print_debug
   export_to.print_info  = _M.print_info
   export_to.print_warn  = _M.print_warn
   export_to.print_error = _M.print_error
   export_to.print_fatal = _M.print_fatal
end

local function dispatch(level, msg)
   if level < log_level then return end

   local t = roslua.Time.now()
   for _, l in pairs(loggers) do
      l(level, t, msg)
   end
end

--- Print function replacement for loggers.
-- Can replace the standard print function and prints the given elements
-- to loggers. Will be posted with INFO log level.
-- @param ... variable number of string arguments
function print(...)
   return dispatch(INFO, table.concat({...}, "\t"))
end


--- Print formatted to screen only.
-- Prints a formatted string to screen.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function printscr(format, ...)
   io.write(string.format("[SCREEN] %s %s\n",
			  tostring(roslua.Time.now()), string.format(format, ...)))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with INFO log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function printf(format, ...)
   return dispatch(INFO, string.format(format, ...))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with DEBUG log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function print_debug(format, ...)
   return dispatch(DEBUG, string.format(format, ...))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with INFO log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function print_info(format, ...)
   return dispatch(INFO, string.format(format, ...))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with WARN log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function print_warn(format, ...)
   return dispatch(WARN, string.format(format, ...))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with ERROR log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function print_error(format, ...)
   return dispatch(ERROR, string.format(format, ...))
end

--- Print formatted.
-- Prints a formatted string to loggers. Will be posted with FATAL log level.
-- @param format format string (cf. string.format() documentation)
-- @param ... appropriate arguments for format string
function print_fatal(format, ...)
   return dispatch(FATAL, string.format(format, ...))
end

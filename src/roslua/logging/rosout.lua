
----------------------------------------------------------------------------
--  rosout.lua - rosout logger
--
--  Created: Tue Aug 10 10:10:17 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Logging facilities for roslua.
-- This module provides a logger that logs to stdout.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.logging.rosout", package.seeall)

require("roslua")

pub_rosout = nil

--- Log message to /rosout topic.
-- @param level log level
-- @param time timestamp of message
-- @param msg message
function log_rosout(level, time, msg)
   local lmsg = pub_rosout.msgspec:instantiate()
   lmsg.values.header.values.stamp = time
   lmsg.values.level = level
   lmsg.values.name  = roslua.node_name
   lmsg.values.msg   = msg
   lmsg.values.topics = {}
   for t, _ in pairs(roslua.publishers) do
      table.insert(lmsg.values.topics, t)
   end
   pub_rosout:publish(lmsg)
end

--- Get logger.
-- Get the rosout logger, as a side effects initializes publisher.
-- @return initialized rosout logger
function get_logger()
   if not pub_rosout then
      pub_rosout  = roslua.publisher("/rosout", "roslib/Log")
   end
   return log_rosout
end

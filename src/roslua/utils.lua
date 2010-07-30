
----------------------------------------------------------------------------
--  utils.lua - Utilities used in the code
--
--  Created: Thu Jul 29 10:59:22 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- General roslua utilities.
-- This module contains useful functions used in roslua.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.utils", package.seeall)

local asserted_rospack = false
--- Assert availability of rospack.
-- Throws an error if rospack cannot be executed, for example because ROS is
-- not installed or the binary is not in the PATH.
function assert_rospack()
   if not asserted_rospack then
      local rv = os.execute("rospack 2>/dev/null")
      assert(rv == 0, "Cannot find rospack command, must be in PATH")
      asserted_rospack = true
   end
end

local rospack_path_cache = {}

--- Get path for a package.
-- Uses rospack to find the path to a certain package. The path is cached so
-- that consecutive calls will not trigger another rospack execution, but are
-- rather handled directly from the cache. An error is thrown if the package
-- cannot be found.
-- @return path to give package
function find_rospack(package)
   if not rospack_path_cache[package] then
      local p = io.popen("rospack find " .. package)
      local path = p:read("*a")
      -- strip trailing newline
      rospack_path_cache[package] = string.gsub(path, "^(.+)\n$", "%1")
      p:close()
   end

   assert(rospack_path_cache[package], "Package path could not be found")
   assert(rospack_path_cache[package] ~= "", "Package path could not be found")
   return rospack_path_cache[package]
end

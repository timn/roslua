
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

--- Split string.
-- Splits a string at a given separator and returns the parts in a table.
-- @param s string to split
-- @param sep separator to split at
-- @return table with splitted parts
function split(s, sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   string.gsub(s, pattern, function(c) fields[#fields+1] = c end)
   return fields
end

--- Package loader to find Lua modules in ROS packages.
-- This will use the first part of the module name and assume it to
-- be the name of a ROS package. It will then try to determine the path using
-- rospack and if found try to load the module in the package directory.
-- @param module module name as given to require()
-- @return function of loaded code if module was found, nil otherwise
function package_loader(module)
   local package = string.match(module, "^[^%.]+")
   if not package then return end

   local try_paths = { "%s/src/%s.lua", "%s/src/%s/init.lua" }
   local errmsg = ""

   local ok, packpath = pcall(find_rospack, package)
   if ok then
      errmsg = errmsg .. string.format("\n\tFound matching ROS package %s (%s)",
				       package, packpath)

      for _, tp in ipairs(try_paths) do
	 local modulepath = string.gsub(module, "%.", "/")
	 local filename = string.format(tp, packpath, modulepath)
	 local file = io.open(filename, "rb")
	 if file then
	    -- Compile and return the module
	    return assert(loadstring(assert(file:read("*a")), filename))
	 end
	 errmsg = errmsg .. string.format("\n\tno file %s (ROS loader)", filename)
      end
   end

   return errmsg
end

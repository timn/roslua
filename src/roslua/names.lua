
----------------------------------------------------------------------------
--  names.lua - ROS name utilities
--
--  Created: Wed Aug 03 10:58:26 2011 (at SRI International)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2011  Tim Niemueller [www.niemueller.de]
--             2011  SRI International
--             2011  Carnegie Mellon University
----------------------------------------------------------------------------

--- ROS name utilities.
-- This module contains utilities to resolve ROS names based on
-- namespace and remapping information. See http://www.ros.org/wiki/Names
-- for information about ROS names.
--
-- @copyright Tim Niemueller, SRI International, Carnegie Mellon University
-- @release Released under BSD license
module("roslua.names", package.seeall)

require("roslua")

remappings = {}

--- Read remappings from arguments.
-- This function is called before the node is initialized and before any
-- ROS specific features have been initialized.
function read_remappings()
   -- arg is a global array with command line arguments
   if not _G.arg then return end
   for i,v in ipairs(_G.arg) do
      local from, to = v:match("^([%w_/]+):=([%w_/.]+)$")
      if from and to then -- it's a mapping
         remappings[from] = to
      end
   end
end

--- Initialize remappings.
-- This needs to be called after the namespace has been defined, but
-- before the node is registered. It will apply name resolution to all
-- left and right hand sides of remapping entries.
function init_remappings()
   local resolved_remappings = {}
   for k, v in pairs(remappings) do
      if not k:match("^_") then
         resolved_remappings[resolve(k, true)] = resolve(v, true)
      else
         resolved_remappings[k] = v
      end
   end
   remappings = resolved_remappings
end

--- Validate a name.
-- A name is valid if name is a string and it is either empty or
-- matches the Lua pattern "^[%a/~][%w_/]*$".
-- @param name name to validate
-- @return true if the name is valid, false otherwise
function validate(name)
   if type(name) ~= "string" then return false end
   if name == "" then return true end

   return name:match("^[%a/~][%w_/]*$") ~= nil
end

--- Validate the nodename.
-- A valid nodename is a valid name with the special constraints that
-- it may not start with slash or tilde.
-- @param name name to validate
-- @return true if the name is valid, false otherwise
function validate_nodename(name)
   return validate(name) and not name:find("/") and not name:find("~")
end

--- Check if name is absolute.
-- @param name name to check
-- @return true if name is absolute, false otherwise
function is_absolute(name)
   return name:match("^/") ~= nil
end


--- Cleanup name.
-- This aggregates all sequential slashes to just one.
-- @param name name to cleanup
-- @return cleaned name
function clean(name)
   assert(validate(name), "Invalid name passed for cleanup")
   local rv = name
   while rv:find("//") do
      rv = rv:gsub("//", "/")
   end
   if rv:match("/$") then
      rv = rv:sub(1, #rv - 1)
   end
   return rv
end

--- Get sanitized version of concatenated string.
-- @param left left hand side
-- @param right right hand side
-- @return cleaned version of left .. "/" .. right
function append(left, right)
   return clean(left .. "/" .. right)
end

--- Resolve a name.
-- This function will resolve the given name according to the set
-- namespace and remapping rules.
-- @param name name to resolve
-- @param no_remapping if omitted or false remapping is applied, if
-- true remapping rules will not be applied
-- @return resolved name
function resolve(name, no_remapping)
   return resolve_ns(roslua.namespace, name, no_remapping)
end


--- Resolve a name relative to a namespace.
-- This function will resolve the given name according to the set
-- namespace and remapping rules relative to the given namespace.
-- @param namespace namespace to use for name resolution
-- @param name name to resolve
-- @param no_remapping if omitted or false remapping is applied, if
-- true remapping rules will not be applied
-- @return resolved name
function resolve_ns(namespace, name, no_remapping)
   assert(validate(name), "Invalid name")

   if name == "" then
      if roslua.namespace == "" then
         return "/"
      else
         return append("/", roslua.namespace)
      end
   end

   if name:match("^~") then
      name = append(roslua.node_name, name:sub(2))
   end
   if not name:match("^/") then
      name = append("/" .. namespace, name)
   end

   if not no_remapping then
      name = remap(name)
   end

   return name
end


--- Apply remapping to given name.
-- @param name name to apply remapping to
-- @return name after applying remapping
function remap(name)
   local resolved = resolve_ns(roslua.namespace, name, true)

   return remappings[resolved] or name
end

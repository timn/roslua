
----------------------------------------------------------------------------
--  service_client.lua - Service client
--
--  Created: Fri Jul 30 10:34:47 2010 (at Intel Labs Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010-2011  Tim Niemueller [www.niemueller.de]
--             2010-2011  Carnegie Mellon University
--             2010       Intel Labs Pittsburgh
--             2011       SRI International
----------------------------------------------------------------------------

--- Service client.
-- This module contains the ServiceClient class to access services provided
-- by other ROS nodes. It is created using the function
-- <code>roslua.service_client()</code>.
-- <br /><br />
-- The service client employs the <code>__call()</code> meta method, such that
-- the service can be called just as <code>service_client(...)</code>. As arguments
-- you must pass the exact number of fields required for the request message in
-- the exact order and of the proper type as they are defined in the service
-- description file.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("roslua.service_client", package.seeall)

require("roslua")
require("roslua.srv_spec")

ServiceClient = { persistent = true, num_exec_tries = 2 }

--- Constructor.
-- The constructor can be called in two ways, either with positional or
-- named arguments. The latter form allows to set additional parameters.
-- In the positional form the ctor takes two arguments, the name and the type
-- of the service. For named parameters the parameter names are service (for
-- the name), type (service type) and persistent. If the latter is set to true
-- the connection to the service provider ROS node will not be closed after
-- one service call. This is beneficial when issuing many service calls in
-- a row, but no guarantee is made that the connection is re-opened if it
-- fails.<br /><br />
-- Examples:<br />
-- Positional:
-- <code>
-- ServiceClient:new("/myservice", "myservice/MyType")
-- </code>
-- Named:
-- <code>
-- ServiceClient:new{service="/myservice", type="myservice/MyType",persistent=true}
-- </code>
-- (mind the curly braces instead of round brackets!)
-- @param args_or_service argument table or service name, see above
-- @param srvtype service type, only used in positional case
function ServiceClient:new(args_or_service, srvtype)
   local o = {}
   setmetatable(o, self)
   self.__index = self
   self.__call  = self.execute

   local lsrvtype
   if type(args_or_service) == "table" then
      o.service    = roslua.resolve(args_or_service[1] or args_or_service.service)
      lsrvtype     = args_or_service[2] or args_or_service.type
      o.persistent = args_or_service.persistent
      o.simplified_return = args_or_service.simplified_return
   else
      o.service    = roslua.resolve(args_or_service)
      lsrvtype     = srvtype
   end
   if roslua.srv_spec.is_srvspec(lsrvtype) then
      o.type    = type.type
      o.srvspec = lsrvtype
   else
      o.type    = lsrvtype
      o.srvspec = roslua.get_srvspec(lsrvtype)
   end

   assert(o.service, "Service name is missing")
   assert(o.type, "Service type is missing")

   if o.persistent then
      -- we don't care if it fails, we'll try again when the service is
      -- actually called, hence wrap in pcall.
      if self.DEBUG and not ok then
         local ok, err = xpcall(function() o:connect() end, debug.traceback)
         print_warn("ServiceClient[%s]: failed init connect: %s", o.service, err)
      else
         pcall(o.connect, o)
      end
   end

   return o
end


--- Finalize instance.
function ServiceClient:finalize()
   if self.persistent and self.connection then
      -- disconnect
      self.connection:close()
      self.connection = nil
   end
end


--- Connect to service provider.
function ServiceClient:connect()
   assert(not self.connection, "Already connected")

   local connection = roslua.tcpros.TcpRosServiceClientConnection:new()
   connection.srvspec = self.srvspec

   local uri = roslua.master:lookupService(self.service)
   assert(uri ~= "", "No provider found for service")

   -- parse uri
   local host, port = uri:match("rosrpc://([^:]+):(%d+)$")
   assert(host and port, "Parsing ROSRCP uri " .. uri .. " failed")

   connection:connect(host, port, 5)
   connection:send_header{callerid=roslua.node_name,
                          service=self.service,
                          type=self.type,
                          md5sum=self.srvspec:md5(),
                          persistent=self.persistent and 1 or 0}
   connection:receive_header()

   self.connection = connection
end

--- Initiate service execution.
-- This starts the execution of the service in a way it can be handled
-- concurrently. The request will be sent, afterwards the concexec_finished(),
-- concexec_result(), and concexec_wait() methods can be used.
-- @param args argument array
function ServiceClient:concexec_start(args)
   assert(not self.running, "A service call for "..self.service.." (" ..
          self.type..") is already being executed")
   self.running = true
   self.concurrent = true
   self.finished = false
   self.concexec_args = args
   if self.concexec_try == nil then
      self.concexec_try = 1
   else
      self.concexec_try = self.concexec_try + 1
   end

   local ok = true
   if not self.connection then
      local err
      ok, err = pcall(self.connect, self)
      if not ok then
         if err:match(".*no provider$") then
            self.concexec_error = "no service provider"
         else
            self.concexec_error = "Connection failed: " .. tostring(err)
         end
      end
   end

   if ok then
      local m = self.srvspec.reqspec:instantiate()
      local err
      m:set_from_array(args)
      ok, err = self.connection:send(m)
      if not ok then
	 self.concexec_error = "Sending message failed: " .. tostring(err)
         self.connection:close()
         self.connection = nil
      end
   end

   self._concexec_failed = not ok
end

--- Wait for the execution to finish.
-- Warning, that blocks the complete execution until a reply has been
-- received!
-- @param timeout optional timeout in seconds after which the waiting
-- should be aborted. An error is thrown if the timeout happens with
-- only the string "timeout". A missing timeout or if set to -1 will
-- cause it to wait indefinitely.
function ServiceClient:concexec_wait(timeout)
   assert(self.running,
          "Service "..self.service.." ("..self.type..") is not being executed")
   assert(self.concurrent, "Service "..self.service.." ("..self.type..
          ") is not executed concurrently")
   assert(not self._concexec_failed,
          "Service "..self.service.." ("..self.type..") has failed")

   self.connection:wait_for_message(timeout)
end


--- Check if execution is finished successfully.
-- Precondition is that the service is being concurrently executed.
-- @return true if the execution is finished and a result has been
-- received, false otherwise
function ServiceClient:concexec_succeeded()
   assert(self.running,
          "Service "..self.service.." ("..self.type..") is not being executed")
   assert(self.concurrent, "Service "..self.service.." ("..self.type..
          ") is not executed concurrently")

   if not self.finished then
      if self.connection and self.connection:data_available() then
	 local ok, err = pcall(self.connection.receive, self.connection)
         if ok then
            self.finished = true
         else
            if err:find("Service execution failed") then
               self.concexec_error = err
               self._concexec_failed = true
            else
               self.connection:close()
               self.connection = nil
               -- we check for "smaller than" here because the value is
               -- incremented in concexec_start() *after* the test!
               if self.concexec_try < self.num_exec_tries then
                  self.running = false
                  self:concexec_start(self.concexec_args)
               else
                  self.concexec_error = err
                  self._concexec_failed = true
               end
            end
         end
      end
   end
   return self.finished
end

--- Check if execution has failed.
-- Precondition is that the service is being concurrently executed.
-- @return true if the execution has failed
function ServiceClient:concexec_failed()
   assert(self.running,
          "Service "..self.service.." ("..self.type..") is not being executed")
   assert(self.concurrent, "Service "..self.service.." ("..self.type..
          ") is not executed concurrently")

   return self._concexec_failed
end

--- Check if execution has failed or succeeded
-- @return true if the execution is finished, false otherwise
function ServiceClient:concexec_finished()
   return self:concexec_succeeded() or self:concexec_failed()
end

--- Get execution result.
-- Precondition is that the service is being concurrently executed and has finished.
-- @return service return value
function ServiceClient:concexec_result()
   assert(self.running, "Service "..self.service.." ("..self.type..") is not being executed")
   assert(self.concurrent, "Service "..self.service.." ("..self.type..") is not executed concurrently")
   assert(self:concexec_succeeded(), "Service "..self.service.." ("..self.type..") is not finished")

   local message = self.connection.message
   if not self.persistent then
      self.connection:close()
      self.connection = nil
   end

   self.running = false
   self.concexec_try = nil

   assert(message,
          "Service "..self.service.." ("..self.type..") no result received")
   if self.simplified_return then
     local _, rv = message:generate_value_array(false)
     return unpack(rv)
   else
     return message
   end
end

--- Abort the execution.
-- Note that this does not actually stop the execution on the server side, rather
-- we just close the connection as to not receive the result. The connection will
-- be closed even if it is marked persistent. It will be reopened on the next call.
function ServiceClient:concexec_abort()
   self.running = false

   if self.connection then
      self.connection:close()
      self.connection = nil
   end
end

--- Reset finished service call.
-- Precondition is that the service has been executed and finished
-- (it does not matter if it succeeded or failed). To abort a currently
-- running service call use concexec_abort().
function ServiceClient:concexec_reset()
   assert(self.running, "Service "..self.service.." ("..self.type..
          ") is not being executed")
   assert(self:concexec_finished(), "Service "..self.service.." ("..self.type..
       ") has not recently finished.")

   self.running = false

   if not self.persistent and self.connection then
      self.connection:close()
      self.connection = nil
   end
end


--- Check if concurrent execution is running.
-- Note that this function only determines if the service client is currently
-- involved in a service execution. This might already have succeeded or failed,
-- but the concurrent execution has been neither aborted nor reset. If you want
-- to know if the service call has finished on the remote end use
-- concexec_finished() to find out.
-- @return true if concurrent execution is running, false otherwise
-- @see concexec_finished()
function ServiceClient:concexec_running()
   return self.running
end

--- Execute service.
-- This method is set as __call entry in the meta table. See the
-- module documentation on the passed arguments. The method will
-- return only after it has received a reply from the service
-- provider!
-- @param args argument array
function ServiceClient:execute(args)
   assert(not self.running, "A service call for "..self.service.." ("..
          self.type..") is already being executed")

   self.running = true
   self.concurrent = false

   local try = 1
   local finished = false
   local err = ""
   while not finished and try <= self.num_exec_tries do
      if not self.connection then
         self:connect()
      end

      local m = self.srvspec.reqspec:instantiate()
      m:set_from_array(args)
      finished, err = self.connection:send(m)
      if finished then
         finished, err =
            pcall(self.connection.wait_for_message, self.connection)
         if not finished and err:find("Service execution failed") then
            self.running = false
            error(err, 0)
         end
      end

      if not finished then
         try = try + 1
         self.connection:close()
         self.connection = nil
      end
   end

   self.running = false

   if not finished then
      error("Failed to call service " .. self.service .. ": " .. err)
   end

   local message = self.connection.message

   if not self.persistent then
      self.connection:close()
      self.connection = nil
   end

   if self.simplified_return then
     local _, rv = message:generate_value_array(false)
     return unpack(rv)
   else
     return message
   end
end


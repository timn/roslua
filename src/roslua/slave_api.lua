
----------------------------------------------------------------------------
--  slave_ypi.lua - Slave XML-RPC API
--
--  Created: Thu Jul 22 19:06:06 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--module(..., package.seeall)

require("xavante")
require("xavante.httpd")
require("wsapi.xavante")
require("wsapi.request")
require("xmlrpc")


function wsapi_handler(wsapi_env)
  local headers = { ["Content-type"] = "text/html" }

  local req = wsapi.request.new(wsapi_env)

  local function handle_xmlrpc(wsapienv)
     local method, arg_table = xmlrpc.srvDecode(req.POST.post_data)

     local func = xmlrpc.dispatch(method)
     local result = { pcall(func, unpack(arg_table or {})) }
     local ok = result[1]
     if not ok then
	result = { code = 3, message = result[2] }
     else
	table.remove(result, 1)
	if table.getn(result) == 1 then
	   result = result[1]
	end
     end

     local r = xmlrpc.srvEncode(result, not ok)
     coroutine.yield(r)
  end

  return 200, headers, coroutine.wrap(handle_xmlrpc)
end

local rules = {
   {
      match = ".",
      with  = wsapi.xavante.makeHandler(wsapi_handler)
   }
}

local config = {
   server = {host = "*", port = 34448},
   defaultHost = { rules = rules}

}

xmlrpc.srvMethods{
   test = function(self) return "test" end
}


xavante.HTTP(config)
local ports = xavante.httpd.get_ports()
print(string.format("Xavante started on port(s) %s", table.concat(ports, ", ")))


while true do
   copas.step()
end

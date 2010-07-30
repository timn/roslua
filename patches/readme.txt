Patches required for roslua

Lua XML-RPC
The XML-RPC API has some bugs that prevent it from working correctly with
roslua (and any more complex API).

xmlrpc-1.05b.patch
Apply this patch to the source package
xmlrpc.lua
On Ubuntu 10.04 you can simply copy this file to /usr/share/lua/5.1/xmlrpc/
and you are set.


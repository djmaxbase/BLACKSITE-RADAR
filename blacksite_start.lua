-- BLACKSITE start: main radar + mobile service
if not fs.exists("radar.lua") then error("radar.lua missing") end
if not fs.exists("mobile_server.lua") then error("mobile_server.lua missing") end
parallel.waitForAll(
 function() shell.run("radar.lua") end,
 function() shell.run("mobile_server.lua") end
)

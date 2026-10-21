-- BLACKSITE MOBILE server
local p='blacksite.mobile.v1'
rednet.open('right')
local radar=peripheral.wrap('create_radar:monitor_0')
while true do
 local id,msg=rednet.receive(p)
 if type(msg)=='table' and msg.type=='poll' then
  local ok,tracks=pcall(radar.getTracks)
  rednet.send(id,{type='snapshot',tracks=ok and tracks or {}},p)
 end
end

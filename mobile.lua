-- BLACKSITE MOBILE 1.0 - Pocket Computer
local protocol="blacksite.mobile.v1"
local modem=nil
for _,s in ipairs(peripheral.getNames()) do
 if peripheral.hasType(s,"modem") then
  local m=peripheral.wrap(s)
  if m and m.isWireless and m.isWireless() then modem=s;break end
 end
end
if not modem then error("Wireless modem required") end
rednet.open(modem)
local page=1
local scroll=0
local server=nil
local data=nil
local function line(y,s,color)
 local w,h=term.getSize()
 if y>h then return end
 term.setCursorPos(1,y)
 term.setTextColor(color or colors.white)
 term.clearLine()
 term.write(tostring(s):sub(1,w))
end
local function render()
 local w,h=term.getSize()
 term.setBackgroundColor(colors.black)
 term.clear()
 term.setBackgroundColor(colors.blue)
 line(1,"BLACKSITE MOBILE",colors.white)
 term.setBackgroundColor(colors.black)
 line(2,server and ("LINKED #"..server) or "SEARCHING...",server and colors.lime or colors.orange)
 if not data then line(4,"Waiting for base...",colors.yellow)
 else
  local players=data.players or {}
  line(3,"RADAR "..tostring(data.status or "?"),colors.cyan)
  line(4,"PLAYERS "..#players,colors.yellow)
  if page==1 then
   line(6,"LIVE TRACKING",colors.lime)
   for i=1,math.min(#players,h-9) do
    local p=players[i]
    line(i+6,(p.alert and "!" or " ")..p.name.." "..p.dist.."m",p.alert and colors.red or colors.white)
   end
  elseif page==2 then
   line(6,"BASE SECURITY",colors.lime)
   line(8,data.armed and "ARMED" or "DISABLED",data.armed and colors.lime or colors.red)
   local count=0
   for _,p in ipairs(players) do if p.alert then count=count+1 end end
   line(10,"INTRUDERS: "..count,count>0 and colors.red or colors.white)
  else
   line(6,"PLAYER INTEL",colors.lime)
   for i=1,math.min(#players,math.floor((h-9)/2)) do
    local p=players[i]
    line(5+i*2,p.name,colors.cyan)
    line(6+i*2,p.status.." "..p.x..","..p.y..","..p.z,colors.lightGray)
   end
  end
 end
 line(h-1,"1 RAD  2 SEC  3 INTEL",colors.black)
 term.setBackgroundColor(colors.gray)
 line(h,"Tap bottom / keys 1-3",colors.white)
 term.setBackgroundColor(colors.black)
end
local timer=os.startTimer(0)
local last=os.clock()
while true do
 render()
 local e,a,b,c=os.pullEvent()
 if e=="timer" and a==timer then
  if server and os.clock()-last>15 then server=nil;data=nil end
  if server then rednet.send(server,{type="poll"},protocol)
  else rednet.broadcast({type="poll"},protocol) end
  timer=os.startTimer(2)
 elseif e=="rednet_message" and c==protocol and type(b)=="table" and b.type=="snapshot" then
  if not server or server==a then server=a;data=b;last=os.clock() end
 elseif e=="key" then
  if a==keys.one then page=1;scroll=0 elseif a==keys.two then page=2;scroll=0 elseif a==keys.three then page=3;scroll=0 elseif a==keys.down then scroll=scroll+1 elseif a==keys.up then scroll=math.max(0,scroll-1) end
 elseif e=="mouse_click" then
  local w,h=term.getSize()
  if c>=h-1 then
   if b<=math.floor(w/3) then page=1 elseif b<=math.floor(w*2/3) then page=2 else page=3 end
  end
 end
end

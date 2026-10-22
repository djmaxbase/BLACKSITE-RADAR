-- BLACKSITE MOBILE SERVER 1.0
-- Read-only bridge between Create: Radars and wireless pocket clients.
local protocol="blacksite.mobile.v1"
local cfgPath="blacksite_radar_config"
local intelPath="blacksite_radar_intel_v5"
local function load(path)
 if not fs.exists(path) then return {} end
 local f=fs.open(path,"r");if not f then return {} end
 local s=f.readAll();f.close()
 local ok,t=pcall(textutils.unserialize,s)
 return ok and type(t)=="table" and t or {}
end
local side
for _,s in ipairs(peripheral.getNames()) do
 if peripheral.hasType(s,"modem") then
  local m=peripheral.wrap(s)
  if m and m.isWireless and m.isWireless() then side=s;break end
 end
end
if not side then error("Base needs a wireless modem") end
rednet.open(side)
local function findRadar()
 for _,s in ipairs(peripheral.getNames()) do
  if peripheral.hasType(s,"create_radar:monitor") then return peripheral.wrap(s) end
 end
 return peripheral.wrap("create_radar:monitor_0")
end
local function getSnapshot()
 local cfg=load(cfgPath)
 local db=load(intelPath)
 local sec=cfg.security or {}
 local base=sec.base or cfg.origin or {}
 local radius=tonumber(sec.radius) or 128
 local players={}
 local radar=findRadar()
 local ok,tracks=false,{}
 if radar then ok,tracks=pcall(function() return radar.getTracks() end) end
 if not ok or type(tracks)~="table" then tracks={} end
 for _,t in pairs(tracks) do
  if type(t)=="table" and type(t.position)=="table" and
    (t.category=="PLAYER" or t.entityType=="entity.minecraft.player" or t.entityType=="minecraft:player") then
   local id=tostring(t.id or t.uuid or "")
   local rec=db[id] or db[id:gsub('-',''):lower()] or {}
   local name=t.playerName or t.username or t.name or (cfg.names or {})[id] or rec.name or ("Player "..id:sub(1,8))
   local x,y,z=tonumber(t.position.x) or 0,tonumber(t.position.y) or 0,tonumber(t.position.z) or 0
   local dx,dz=x-(tonumber(base.x) or 0),z-(tonumber(base.z) or 0)
   local dist=math.floor(math.sqrt(dx*dx+dz*dz)+0.5)
   local status=tostring(rec.status or "NEUTRAL"):upper()
   local alert=not not sec.enabled and dist<=radius and status~="FRIENDLY" and (not sec.watchOnly or status=="WATCHLIST")
   players[#players+1]={id=id,name=tostring(name),x=math.floor(x),y=math.floor(y),z=math.floor(z),dist=dist,status=status,alert=alert}
  end
 end
 table.sort(players,function(a,b)return a.dist<b.dist end)
 while #players>60 do table.remove(players) end
 return {type="snapshot",status=ok and "ONLINE" or "OFFLINE",players=players,armed=not not sec.enabled,radius=radius}
end
print("BLACKSITE MOBILE SERVER ONLINE")
print("Wireless modem: "..side)
print("Computer ID: "..os.getComputerID())
while true do
 local sender,msg=rednet.receive(protocol)
 if type(msg)=="table" and msg.type=="poll" then
  local ok,data=pcall(getSnapshot)
  if ok then rednet.send(sender,data,protocol) else print("Snapshot error: "..tostring(data)) end
 end
end

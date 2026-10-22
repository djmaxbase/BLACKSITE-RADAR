-- BLACKSITE RADAR ULTRA 6.0 | CC:Tweaked + Create: Radars
-- Real tracks only. Touch to select; CC monitors do not support mouse hover.
local C=colors
local cfgFile='blacksite_radar_config'
local cfg={density=1,theme='TACTICAL',range=256,origin={x=1733,y=57,z=-1234},filter='ALL',scale=0.5,refresh=0.7,autoCenter=false,names={},security={enabled=true,radius=128,side='none',cooldown=20,watchOnly=false},trusted={}}
if fs.exists(cfgFile) then local f=fs.open(cfgFile,'r');if f then local ok,v=pcall(textutils.unserialize,f.readAll());f.close();if ok and type(v)=='table' then for k,x in pairs(v) do cfg[k]=x end end end end
local function save() local f=fs.open(cfgFile,'w');if f then f.write(textutils.serialize(cfg));f.close() end end
local monitor,radar,radarName,monitorName
local function discover()
 monitor,radar,radarName,monitorName=nil,nil,nil,nil
 for _,n in ipairs(peripheral.getNames()) do
  if not monitor and peripheral.hasType(n,'monitor') then monitor=peripheral.wrap(n);monitorName=n end
  local ok,methods=pcall(peripheral.getMethods,n)
  if ok and type(methods)=='table' then for _,m in ipairs(methods) do if m=='getTracks' and not radar then radar=peripheral.wrap(n);radarName=n end end end
 end
end
discover()
if not monitor then error('No CC:Tweaked monitor detected. Attach an Advanced Monitor.') end
pcall(monitor.setTextScale,cfg.scale)
local w,h=monitor.getSize()
cfg.density=tonumber(cfg.density) or 1
local tracks,selected,tab,offset,buttons,err,lastPoll={},nil,'RADAR',0,{},'',0
local currentPage=1;local sweep=0;local paused=false;local snapshot={};local message='';local messageUntil=0
local playerCache={} -- keyed by UUID, last observation time in seconds
local cacheSeconds=120
-- Persistent intelligence. UUIDs are keyed exactly as provided by Create: Radars.
local dbFile='blacksite_radar_intel_v5'
local intel={}
if fs.exists(dbFile) then
 local f=fs.open(dbFile,'r')
 if f then local ok,v=pcall(textutils.unserialize,f.readAll());f.close();if ok and type(v)=='table' then intel=v end end
end
cfg.security=cfg.security or {}
local sec=cfg.security
if sec.enabled==nil then sec.enabled=true end
sec.radius=tonumber(sec.radius) or 128
sec.cooldown=tonumber(sec.cooldown) or 20
sec.side=sec.side or 'none'
sec.base=sec.base or {x=1733,y=57,z=-1234}
sec.watchOnly=sec.watchOnly or false
cfg.trusted=cfg.trusted or {}
local alerts={}
local trails={}
local lastAlert={}
local dbDirty=false
local lastDbSave=0
local alarmUntil=0
local alarmText=''
local function wallTime()
 if os.epoch then local ok,v=pcall(os.epoch,'utc');if ok and type(v)=='number' then return math.floor(v/1000) end end
 return math.floor(os.clock())
end
local function saveIntel(force)
 if not dbDirty then return end
 if not force and os.clock()-lastDbSave<15 then return end
 local f=fs.open(dbFile,'w')
 if f then f.write(textutils.serialize(intel));f.close();dbDirty=false;lastDbSave=os.clock() end
end
local function alarmOutput(on)
 if sec.side~='none' and redstone and redstone.setOutput then pcall(redstone.setOutput,sec.side,on) end
end
local function securityDistance(t)
 local p=t.position or {};local o=sec.base or {}
 local x=(tonumber(p.x) or 0)-(tonumber(o.x) or 0)
 local z=(tonumber(p.z) or 0)-(tonumber(o.z) or 0)
 return math.sqrt(x*x+z*z)
end
local function recordAlert(t,why)
 local id=tostring(t.id or t.uuid or '?')
 local now=wallTime()
 if now-(lastAlert[id] or 0)<sec.cooldown then return end
 lastAlert[id]=now
 local label=(cfg.names or {})[id] or ('Player '..id:sub(1,8))
 alarmText='ALERT '..label..' '..why
 alarmUntil=os.clock()+8
 table.insert(alerts,1,{when=now,id=id,why=why})
 while #alerts>35 do table.remove(alerts) end
 alarmOutput(true)
end
-- Mojang Java profile lookups; names are cached in the existing config file.
local lookupState={} -- UUID -> next allowed lookup time (seconds)
local lookupQueue={}
local lookupQueued={}
local lookupStatus='IDLE'
local function normalizeUUID(id)
 if type(id)~='string' then return nil end
 local clean=id:lower():gsub('%-','')
 if #clean~=32 or clean:find('[^0-9a-f]') then return nil end
 return clean
end
local function enqueuePlayer(id)
 local clean=normalizeUUID(id)
 if not clean then return end
 cfg.names=cfg.names or {}
 if cfg.names[id] or cfg.names[clean] or lookupQueued[clean] then return end
 if os.clock() < (lookupState[clean] or 0) then return end
 lookupQueued[clean]=true
 lookupQueue[#lookupQueue+1]={uuid=clean,id=id}
end
local function lookupWorker()
 while true do
  if #lookupQueue==0 then sleep(1)
  else
   local item=table.remove(lookupQueue,1)
   lookupQueued[item.uuid]=nil
   if not (cfg.names[item.id] or cfg.names[item.uuid]) then
    lookupState[item.uuid]=os.clock()+120 -- retry failed lookups after two minutes
    if not http or not http.get then
     lookupStatus='HTTP DISABLED'
    else
     lookupStatus='LOOKING UP '..item.uuid:sub(1,8)
     local url='https://sessionserver.mojang.com/session/minecraft/profile/'..item.uuid
     local ok,response=pcall(http.get,url,nil,true)
     if ok and response then
      local okRead,body=pcall(response.readAll)
      pcall(response.close)
      local okJson,data=false,nil
      if okRead and type(body)=='string' then okJson,data=pcall(textutils.unserializeJSON,body) end
      if okJson and type(data)=='table' and type(data.name)=='string' and #data.name>0
        and normalizeUUID(data.id)==item.uuid then
       cfg.names[item.id]=data.name
       cfg.names[item.uuid]=data.name
       save()
       lookupStatus='RESOLVED '..data.name
      else lookupStatus='LOOKUP FAILED' end
     else lookupStatus='HTTP BLOCKED / FAILED' end
    end
    sleep(1.5) -- avoid rapid requests to Mojang
   end
  end
 end
end
local lastReconnect=0
local function n(v) return type(v)=='number' and v or 0 end
local function str(v) return tostring(v or '') end
local function cut(s,len) s=str(s);if len<1 then return '' end;return #s>len and s:sub(1,math.max(0,len-1))..'~' or s end
local function vec(v) return type(v)=='table' and v or {} end
local function entityName(t)
 local raw=t.entityType or t.type or t.entity or 'Unknown'
 if type(raw)=='table' then raw=raw.id or raw.name or 'Unknown' end
 raw=str(raw):gsub('^entity%.',''):gsub('^minecraft:',''):gsub('^minecraft%.',''):gsub('^.*[.:]',''):gsub('_',' ')
 return (raw:gsub('(%a)([%w]*)',function(a,b)return a:upper()..b end))
end
local function playerName(t)
 for _,key in ipairs({'playerName','username','player','displayName','name'}) do
  local v=t[key];if type(v)=='string' and #v>0 then return v end
  if type(v)=='table' and type(v.name)=='string' then return v.name end
 end
 local id=str(t.id or t.uuid);return (cfg.names or {})[id] or (cfg.names or {})[normalizeUUID(id) or '']
end
local function isPlayer(t) return str(t.category):upper()=='PLAYER' or str(t.entityType):lower()=='entity.minecraft.player' or str(t.entityType):lower()=='minecraft:player' end
local function cat(t) return str(t.category or 'UNKNOWN'):upper() end
local function ident(t) return str(t.id or t.trackId or t.uuid or '?') end
local function title(t) if isPlayer(t) then return playerName(t) or ('Player '..ident(t):sub(1,8)) end return playerName(t) or entityName(t) end
local function clr(t) if isPlayer(t) then return C.cyan end;local c=cat(t);if c=='HOSTILE' then return C.red elseif c=='FRIENDLY' or c=='PASSIVE' then return C.lime elseif c=='NEUTRAL' then return C.yellow else return C.lightGray end end
local function pos(t) return vec(t.position) end
local function vel(t) return vec(t.velocity) end
local function xyz(t)
 local p=pos(t);local o=cfg.origin or {x=0,y=0,z=0}
 return n(p.x)-n(o.x),n(p.y)-n(o.y),n(p.z)-n(o.z)
end
local function distance(t) local x,y,z=xyz(t);return math.sqrt(x*x+y*y+z*z) end
local function speed(t) local v=vel(t);return math.sqrt(n(v.x)^2+n(v.y)^2+n(v.z)^2) end
local function notify(s) message=s;messageUntil=os.clock()+4 end
local function updateIntel(t)
 local id=ident(t)
 if id=='?' then return end
 local now=wallTime()
 local p=pos(t)
 local r=intel[id]
 if not r then
  r={first=now,last=now,seen=0,visits=0,status='NEUTRAL',inside=false}
  intel[id]=r
 end
 r.last=now;r.seen=(r.seen or 0)+1
 r.x=n(p.x);r.y=n(p.y);r.z=n(p.z)
 r.name=playerName(t) or r.name
 local d=securityDistance(t)
 local inside=d<=sec.radius
 if inside and not r.inside then
  r.visits=(r.visits or 0)+1
  if sec.enabled and r.status~='FRIENDLY' and (not sec.watchOnly or r.status=='WATCHLIST') then
   recordAlert(t,'ENTERED '..math.floor(d)..'m')
  end
 end
 r.inside=inside
 local trail=trails[id] or {};trails[id]=trail
 local prev=trail[#trail]
 if not prev or math.abs(prev.x-r.x)+math.abs(prev.z-r.z)>=2 then
  trail[#trail+1]={x=r.x,z=r.z,when=now}
  if #trail>40 then table.remove(trail,1) end
 end
 dbDirty=true
end

local function draw(x,y,s,fg,bg)
 if y<1 or y>h or x>w then return end
 s=str(s);if x<1 then s=s:sub(2-x);x=1 end
 s=s:sub(1,w-x+1);if #s==0 then return end
 monitor.setCursorPos(x,y);monitor.setTextColor(fg or C.white);monitor.setBackgroundColor(bg or C.black);monitor.write(s)
end
local function fill(x,y,len,ch,fg,bg) if len>0 then draw(x,y,string.rep(ch or ' ',len),fg,bg) end end
local function button(x,y,label,fn,fg,bg)
 local s=' '..label..' ';draw(x,y,s,fg or C.white,bg or C.gray)
 buttons[#buttons+1]={x=x,y=y,len=#s,fn=fn}
end
local function rule(y) fill(1,y,w,'-',C.gray) end
local function changeDensity(delta) cfg.density=math.max(.5,math.min(2,math.floor((cfg.density+delta)*20+.5)/20));save();notify('UI density '..string.format('%.2f',cfg.density)) end
local function changeZoom(factor) cfg.range=math.max(16,math.min(8192,math.floor(cfg.range*factor+0.5)));save() end
local function changeScale(delta) local value=math.floor((cfg.scale+delta)*2+0.5)/2;value=math.max(.5,math.min(5,value));local ok=pcall(monitor.setTextScale,value);if ok then cfg.scale=value;save();notify('Monitor scale '..value) else notify('Scale not supported') end end
local function matches(t)
 local f=cfg.filter
 return f=='ALL' or (f=='PLAYERS' and isPlayer(t)) or (f=='HOSTILE' and cat(t)=='HOSTILE') or (f=='MOBS' and not isPlayer(t))
end
local function filtered()
 local r={};local present={}
 for _,t in ipairs(tracks) do
  present[ident(t)]=true
  if matches(t) then r[#r+1]=t end
 end
 -- Cached player contacts remain selectable, but are never reported as live.
 if cfg.filter=='ALL' or cfg.filter=='PLAYERS' then
  for id,entry in pairs(playerCache) do
   if not present[id] and os.clock()-entry.seen<=cacheSeconds then
    local t={}
    for k,v in pairs(entry.track) do t[k]=v end
    t._lastSeen=entry.seen
    r[#r+1]=t
   end
  end
 end
 return r
end
local function fetch()
 if not radar and os.clock()-lastReconnect>3 then lastReconnect=os.clock();discover() end
 if not radar then err='Radar peripheral disconnected';tracks={};return end
 local ok,result=pcall(function() return radar.getTracks() end)
 if not ok then err=cut(result,100);radar=nil;tracks={};return end
 if type(result)~='table' then err='getTracks returned non-table';tracks={};return end
 local out={};for _,t in pairs(result) do if type(t)=='table' and type(t.position)=='table' then out[#out+1]=t end end
 table.sort(out,function(a,b)return distance(a)<distance(b) end)
 tracks=out;err='';lastPoll=os.clock()
 for _,t in ipairs(out) do
  if isPlayer(t) and ident(t)~='?' then
   t._lastSeen=nil
   playerCache[ident(t)]={track=t,seen=os.clock()}
   enqueuePlayer(ident(t))
   updateIntel(t)
  end
 end
 for id,e in pairs(playerCache) do if os.clock()-e.seen>cacheSeconds then playerCache[id]=nil end end
 saveIntel(false)
 if alarmUntil>0 and os.clock()>alarmUntil then alarmUntil=0;alarmOutput(false) end
 -- Never move the base origin during polling: it must remain a stable world coordinate.
 -- Old autoCenter settings are ignored to avoid moving targets on screen.
 -- Preserve selection across temporary track dropouts.
end
local function chosen() for _,t in ipairs(filtered()) do if ident(t)==selected then return t end end end
local function header()
 buttons={};w,h=monitor.getSize();monitor.setBackgroundColor(C.black);monitor.clear()
 fill(1,1,w,' ',C.white,C.blue)
 draw(2,1,'BLACKSITE / RADAR ULTRA 6.1',C.white,C.blue)
 draw(math.max(2,w-19),1,err=='' and 'LIVE DATA' or 'LINK OFFLINE',err=='' and C.lime or C.red,C.blue)
 local nav={'RADAR','CONTACTS','DETAILS','SECURITY','INTEL','SYSTEM'}
 local x=2
 for _,name in ipairs(nav) do
  local t=name;local label=(w<58 and ({RADAR='RDR',CONTACTS='LIST',DETAILS='INFO',SECURITY='SEC',INTEL='DB',SYSTEM='SYS'})[name] or name)
  if x+#label+2<=w then button(x,3,label,function()tab=t;currentPage=1 end,tab==name and C.black or C.white,tab==name and C.cyan or C.gray) end
  x=x+#label+3
 end
 rule(4)
 local players,hostiles=0,0;for _,t in ipairs(tracks) do if isPlayer(t) then players=players+1 end;if cat(t)=='HOSTILE' then hostiles=hostiles+1 end end
 local remembered=0
 for id,e in pairs(playerCache) do if os.clock()-e.seen<=cacheSeconds then
  local live=false;for _,t in ipairs(tracks) do if ident(t)==id then live=true;break end end
  if not live then remembered=remembered+1 end
 end end
 draw(2,5,'C '..#tracks,C.cyan);draw(13,5,'P '..players,C.cyan);draw(24,5,'H '..hostiles,hostiles>0 and C.red or C.lime)
 if w>42 then draw(35,5,'LOST '..remembered,C.orange) end
 if w>65 then draw(w-12,5,err=='' and 'SYNC OK' or 'OFFLINE',err=='' and C.lime or C.red) end
 rule(6)
 rule(h-2)
 local foot='TOUCH targets / tabs | BASE CENTER'..' | '..cfg.range..'m'
 draw(2,h-1,cut(foot,w-2),C.lightGray)
 if alarmUntil>os.clock() then draw(2,h,cut(alarmText,w-2),C.red) elseif messageUntil>os.clock() then draw(2,h,cut(message,w-2),C.yellow) else draw(2,h,'Real radar tracks - no simulated contacts',C.gray) end
end
local function detail(t,x,y,maxw,maxh)
 if not t then draw(x,y,'SELECT A CONTACT',C.yellow);draw(x,y+2,'Touch a radar blip or list row.',C.lightGray);return end
 local p=pos(t);local v=vel(t);local d=distance(t)
 local rows={
  {'SIGNAL',t._lastSeen and ('LOST '..math.floor(os.clock()-t._lastSeen)..'s ago') or 'LIVE'},
  {'NAME',title(t)}, {'CATEGORY',cat(t)}, {'ENTITY',str(t.entityType or 'unknown')},
  {'DISTANCE',string.format('%.1f blocks',d)},
  {'POSITION',string.format('%.1f / %.1f / %.1f',n(p.x),n(p.y),n(p.z))},
  {'VELOCITY',string.format('%.2f / %.2f / %.2f',n(v.x),n(v.y),n(v.z))},
  {'SPEED',string.format('%.3f blocks/tick*',speed(t))},
  {'STATUS',isPlayer(t) and ((intel[ident(t)] or {}).status or 'NEUTRAL') or '-'},
  {'TRACK ID',ident(t)},
  {'SCAN TIME',str(t.scannedTime or t.scanTime or 'not provided')}
 }
 for i,r in ipairs(rows) do
  local yy=y+i-1;if yy>=y+maxh or yy>=h-2 then break end
  draw(x,yy,cut(r[1],12),C.cyan)
  draw(x+13,yy,cut(r[2],maxw-13),i==1 and clr(t) or C.white)
 end
end
local function radarPage()
 -- Render the entire scope in one blit per row: faster and cleaner than per-character drawing.
 local top,bottom=8,h-4
 local compact=(w<75 or h<26)
 local side=compact and 0 or math.max(24,math.floor(w*.31))
 local avail=w-side-(compact and 1 or 3)
 local cx=math.floor(avail/2)+1
 local cy=math.floor((top+bottom)/2)
 local radius=math.floor(math.min((avail-4)/2,(bottom-top)/2-1))
 if radius<3 then
  draw(2,8,'Display too small: add monitor blocks or use scale 0.5',C.orange)
  return
 end
 local hex='0123456789abcdef'
 local function digit(col)
  for i=0,15 do if 2^i==col then return hex:sub(i+1,i+1) end end
  return '0'
 end
 local cells={}
 local function plot(x,y,ch,fg,bg)
  x=math.floor(x+.5);y=math.floor(y+.5)
  if x>=1 and x<=avail and y>=top and y<=bottom then
   cells[y]=cells[y] or {}
   cells[y][x]={ch=ch,fg=fg or C.green,bg=bg or C.black}
  end
 end
 -- Character cells are approximately twice as tall as wide; compensate in the X axis.
 local rx=math.max(2,math.min(math.floor((avail-3)/2),math.floor(radius*2*math.min(1.3,cfg.density))))
 local ry=radius
 for y=top,bottom do
  for x=1,avail do
   local dx=(x-cx)/rx;local dy=(y-cy)/ry
   local r=math.sqrt(dx*dx+dy*dy)
   if r<=1.025 then
    local ch=' ';local fg=C.green;local bg=C.black
    if math.abs(r-1)<.035 then ch='o';fg=C.lime
    elseif math.abs(r-.75)<.028 or math.abs(r-.5)<.028 or math.abs(r-.25)<.03 then ch='.';fg=C.green
    elseif x==cx or y==cy then ch='.';fg=C.gray end
    -- No sweep trail: previously the sweep painted diagonal green artifacts.
    if ch~=' ' then plot(x,y,ch,fg,bg) end
   end
  end
 end
 plot(cx,cy,'+',C.white)
 plot(cx,cy-ry,'N',C.cyan);plot(cx,cy+ry,'S',C.cyan)
 plot(cx+rx,cy,'E',C.cyan);plot(cx-rx,cy,'W',C.cyan)
 if cfg.filter=='ALL' or cfg.filter=='PLAYERS' then
  for _,path in pairs(trails) do
   for _,pt in ipairs(path) do
    local dx=pt.x-n(cfg.origin.x);local dz=pt.z-n(cfg.origin.z)
    if math.sqrt(dx*dx+dz*dz)<=cfg.range then
     plot(cx+dx/cfg.range*rx,cy+dz/cfg.range*ry,'.',C.blue)
    end
   end
  end
 end
 local visible=filtered();local plotted=0;local overlap={};local targetButtons={}
 for _,t in ipairs(visible) do
  local dx,_,dz=xyz(t)
  if math.sqrt(dx*dx+dz*dz)<=cfg.range then
   local px=math.floor(cx+dx/cfg.range*rx+.5)
   local py=math.floor(cy+dz/cfg.range*ry+.5)
   if px>=1 and px<=avail and py>=top and py<=bottom then
    local key=px..','..py;overlap[key]=(overlap[key] or 0)+1
    local mark=t._lastSeen and '?' or (ident(t)==selected and 'X' or (isPlayer(t) and 'P' or cat(t)=='HOSTILE' and '!' or 'o'))
    if overlap[key]>1 then mark=tostring(math.min(9,overlap[key])) end
    plot(px,py,mark,t._lastSeen and C.orange or (ident(t)==selected and C.yellow or clr(t)))
    plotted=plotted+1
    local id=ident(t)
    targetButtons[key]={x=px,y=py,len=1,fn=function()selected=id;tab='DETAILS' end}
   end
  end
 end
 for y=top,bottom do
  local chars,fgs,bgs={},{},{}
  for x=1,avail do
   local cell=cells[y] and cells[y][x]
   chars[x]=cell and cell.ch or ' '
   fgs[x]=digit(cell and cell.fg or C.white)
   bgs[x]=digit(cell and cell.bg or C.black)
  end
  monitor.setCursorPos(1,y)
  monitor.blit(table.concat(chars),table.concat(fgs),table.concat(bgs))
 end
 for _,btn in pairs(targetButtons) do buttons[#buttons+1]=btn end
 draw(2,7,'[ BLACKSITE / ACTIVE SCOPE ]',C.lime)
 local function autoFit()
  local a=filtered();if #a==0 then notify('No tracks to fit');return end
  -- Fit changes zoom only, never the base location.
  cfg.autoCenter=false
  local maxd=0
  for _,t in ipairs(a) do local x,_,z=xyz(t);maxd=math.max(maxd,math.sqrt(x*x+z*z)) end
  cfg.range=math.max(16,math.min(8192,math.ceil(maxd*1.15)))
  save();notify('Fit '..#a..' contacts')
 end
 if compact then
  draw(2,h-3,cut('P '..plotted..'/'..#visible..' | '..cfg.range..'m | '..cfg.filter,w-3),C.cyan)
  button(math.max(2,w-19),7,'-',function()changeZoom(.8) end)
  button(math.max(2,w-14),7,'+',function()changeZoom(1.25) end)
  button(math.max(2,w-9),7,'FIT',autoFit)
 else
  local sx=avail+3
  draw(sx,8,'TACTICAL OVERVIEW',C.cyan)
  draw(sx,10,'Visible: '..plotted..' / '..#visible,C.white)
  draw(sx,11,'Range: '..cfg.range..' blocks',C.white)
  draw(sx,12,'UI density: '..string.format('%.2f',cfg.density),C.lightGray)
  button(sx,13,'-5%',function()changeZoom(1/1.05) end)
  button(sx+7,13,'+5%',function()changeZoom(1.05) end)
  button(sx,15,'AUTO FIT',autoFit,C.black,C.lime)
  draw(sx,17,'FILTER: '..cfg.filter,C.yellow)
  button(sx,19,'ALL',function()cfg.filter='ALL';save() end)
  button(sx+6,19,'PLAYERS',function()cfg.filter='PLAYERS';save() end)
  button(sx,21,'HOSTILE',function()cfg.filter='HOSTILE';save() end)
  button(sx+10,21,'MOBS',function()cfg.filter='MOBS';save() end)
  if h>35 then
   local t=chosen();if t then draw(sx,24,'SELECTED TARGET',C.cyan);detail(t,sx,26,side-2,math.min(8,h-32)) end
  end
  draw(2,h-3,'P = player  ? = last seen  ! = hostile  X = selected',C.lightGray)
 end
end
local function contactsPage()
 local list=filtered();local per=math.max(1,h-14);local pages=math.max(1,math.ceil(#list/per));currentPage=math.max(1,math.min(currentPage,pages))
 draw(2,8,'#',C.cyan);draw(6,8,'NAME / TYPE',C.cyan);draw(math.floor(w*.55),8,'CATEGORY',C.cyan);draw(math.floor(w*.77),8,'DISTANCE',C.cyan)
 rule(9)
 for i=1,per do
  local idx=(currentPage-1)*per+i;local t=list[idx];if not t then break end
  local y=9+i;local id=ident(t);local chosenRow=(id==selected)
  if chosenRow then fill(1,y,w,' ',C.white,C.gray) end
  draw(2,y,string.format('%02d',idx),C.lightGray,chosenRow and C.gray or C.black)
  draw(6,y,cut((t._lastSeen and '[LOST] ' or '')..title(t),math.max(8,math.floor(w*.55)-8)),t._lastSeen and C.orange or clr(t),chosenRow and C.gray or C.black)
  draw(math.floor(w*.55),y,cut(cat(t),math.max(6,math.floor(w*.22)-1)),C.white,chosenRow and C.gray or C.black)
  draw(math.floor(w*.77),y,string.format('%.1fm',distance(t)),C.yellow,chosenRow and C.gray or C.black)
  buttons[#buttons+1]={x=1,y=y,len=w,fn=function()selected=id;tab='DETAILS' end}
 end
 draw(2,h-4,'PAGE '..currentPage..' / '..pages..' | FILTER '..cfg.filter,C.lightGray)
 button(math.max(2,w-22),h-4,'PREV',function()currentPage=math.max(1,currentPage-1) end)
 button(math.max(2,w-12),h-4,'NEXT',function()currentPage=math.min(pages,currentPage+1) end)
end
local function statusCycle(id)
 local r=intel[id];if not r then return end
 local a={NEUTRAL='FRIENDLY',FRIENDLY='WATCHLIST',WATCHLIST='NEUTRAL'}
 r.status=a[r.status] or 'NEUTRAL';dbDirty=true;saveIntel(true)
 notify('Status: '..r.status)
end
local function detailsPage()
 local t=chosen();if not t and selected and intel[selected] then local r=intel[selected];t={id=selected,category='PLAYER',entityType='entity.minecraft.player',position={x=r.x,y=r.y,z=r.z},_lastSeen=os.clock()-cacheSeconds} end;detail(t,2,9,math.max(20,math.floor(w*.50)),h-17)
 if t then
  local y=math.min(h-8,20)
  draw(2,y,'RAW FIELDS (available from mod)',C.cyan)
  local keys={};for k in pairs(t) do keys[#keys+1]=str(k) end;table.sort(keys)
  draw(2,y+1,cut(table.concat(keys,', '),w-4),C.lightGray)
  if isPlayer(t) and not playerName(t) then draw(2,y+3,'Mojang lookup pending/failed. Manual alias below.',C.orange) end
  if isPlayer(t) then button(2,math.min(h-5,y+4),'SET PLAYER ALIAS',function()
   term.redirect(term.native());term.clear();term.setCursorPos(1,1)
   print('PLAYER ALIAS - manual UUID mapping')
   print('UUID: '..ident(t));write('Username/alias: ')
   local name=read();if name and #name>0 then cfg.names=cfg.names or {};cfg.names[ident(t)]=name:sub(1,24);save();notify('Alias saved') end
  end) end
  draw(2,y+5,'* Velocity units depend on Create: Radars API.',C.gray)
 end
 if selected and intel[selected] then
  local r=intel[selected]
  draw(math.max(2,math.floor(w*.52)),9,'INTELLIGENCE DOSSIER',C.cyan)
  local x=math.max(2,math.floor(w*.52))
  draw(x,11,'STATUS: '..str(r.status),r.status=='WATCHLIST' and C.red or C.lime)
  draw(x,12,'VISITS: '..str(r.visits),C.white)
  draw(x,13,'FIRST: '..os.date('!%Y-%m-%d %H:%M',r.first or 0),C.white)
  draw(x,14,'LAST: '..os.date('!%Y-%m-%d %H:%M',r.last or 0),C.white)
  draw(x,15,'LAST XYZ: '..math.floor(r.x or 0)..' / '..math.floor(r.y or 0)..' / '..math.floor(r.z or 0),C.white)
  draw(x,16,'PATH POINTS: '..#(trails[selected] or {}),C.white)
  button(x,18,'CHANGE STATUS',function()statusCycle(selected) end)
 end
 button(2,h-4,'BACK TO RADAR',function()tab='RADAR' end)
end
local function securityPage()
 draw(2,8,'BASE PERIMETER SECURITY',C.cyan)
 draw(2,10,'Alarm: '..(sec.enabled and 'ARMED' or 'DISARMED'),sec.enabled and C.lime or C.orange)
 button(29,10,sec.enabled and 'DISARM' or 'ARM',function()sec.enabled=not sec.enabled;save();if not sec.enabled then alarmOutput(false);alarmUntil=0 end end)
 draw(2,11,string.format('Base: X %d Z %d',sec.base.x or 0,sec.base.z or 0),C.lightGray)
 draw(2,12,'Base radius: '..sec.radius..' blocks',C.white)
 button(29,12,'- 32',function()sec.radius=math.max(32,sec.radius-32);save() end)
 button(39,12,'+ 32',function()sec.radius=math.min(2048,sec.radius+32);save() end)
 draw(2,14,'Alert policy: '..(sec.watchOnly and 'WATCHLIST ONLY' or 'ALL NON-FRIENDLY'),C.white)
 button(29,14,'TOGGLE POLICY',function()sec.watchOnly=not sec.watchOnly;save() end)
 draw(2,16,'Redstone side: '..sec.side,C.white)
 button(29,16,'CHANGE SIDE',function()
  local sides={'none','top','bottom','left','right','front','back'}
  local i=1;for j,v in ipairs(sides) do if v==sec.side then i=j end end
  sec.side=sides[i%#sides+1];alarmOutput(false);save()
 end)
 button(2,17,'SET SECURITY BASE',function()
  term.redirect(term.native());term.clear();term.setCursorPos(1,1)
  print('SECURITY BASE COORDINATES')
  write('X: ');local x=tonumber(read());if not x then return end
  write('Y: ');local y=tonumber(read());if not y then return end
  write('Z: ');local z=tonumber(read());if not z then return end
  sec.base={x=x,y=y,z=z};save();notify('Security base updated')
 end)
 draw(2,19,'ALERT LOG (current session)',C.cyan)
 local limit=math.max(0,h-25)
 for i=1,math.min(limit,#alerts) do
  local a=alerts[i]
  draw(2,20+i,cut(os.date('!%H:%M:%S',a.when)..' '..a.id:sub(1,8)..' '..a.why,w-4),C.orange)
 end
 draw(2,h-4,'Redstone output activates for 8s on new alerts.',C.gray)
end
local function intelPage()
 local ids={};for id in pairs(intel) do ids[#ids+1]=id end
 table.sort(ids,function(a,b)return (intel[a].last or 0)>(intel[b].last or 0) end)
 local per=math.max(1,h-15);local pages=math.max(1,math.ceil(#ids/per))
 currentPage=math.max(1,math.min(currentPage,pages))
 draw(2,8,'PLAYER INTELLIGENCE | '..#ids..' KNOWN UUIDs',C.cyan)
 draw(2,9,'Tap a player to select; status cycles via DETAILS.',C.lightGray)
 for i=1,per do
  local id=ids[(currentPage-1)*per+i];if not id then break end
  local r=intel[id];local y=10+i
  local label=(cfg.names or {})[id] or r.name or ('Player '..id:sub(1,8))
  local line=string.format('%s  %-9s  visits:%d  last:%s',cut(label,16),r.status or 'NEUTRAL',r.visits or 0,os.date('!%m-%d %H:%M',r.last or 0))
  draw(2,y,cut(line,w-4),r.status=='WATCHLIST' and C.red or r.status=='FRIENDLY' and C.lime or C.white)
  buttons[#buttons+1]={x=1,y=y,len=w,fn=function()selected=id;tab='DETAILS' end}
 end
 draw(2,h-4,'PAGE '..currentPage..' / '..pages,C.lightGray)
 button(math.max(2,w-22),h-4,'PREV',function()currentPage=math.max(1,currentPage-1) end)
 button(math.max(2,w-12),h-4,'NEXT',function()currentPage=math.min(pages,currentPage+1) end)
end
local function systemPage()
 draw(2,8,'CONNECTION DIAGNOSTICS',C.cyan)
 draw(2,10,'Radar peripheral: '..str(radarName or 'NOT FOUND'),radar and C.lime or C.red)
 draw(2,11,'Display: '..str(monitorName or 'NOT FOUND'),C.white)
 draw(2,12,'API: getTracks / getSelectedTrack / getSelectedTrackId',C.lightGray)
 draw(2,13,'Status: '..(err=='' and 'ONLINE' or err),err=='' and C.lime or C.red)
 draw(2,14,'Monitor: '..w..' x '..h..' chars | Scale '..cfg.scale,C.white)
 draw(2,15,'Refresh: '..cfg.refresh..' seconds | Lost player memory: '..cacheSeconds..'s',C.white)
 draw(2,16,'Native font scale: 0.5 increments | UI density: 0.05 steps',C.lightGray)
 draw(2,17,'MAP ORIGIN',C.cyan)
 if cfg.origin then draw(2,18,string.format('X %.1f  Y %.1f  Z %.1f',cfg.origin.x,cfg.origin.y,cfg.origin.z),C.white)
 else draw(2,18,'Not configured: plotting assumes (0,0,0)',C.orange) end
 button(2,20,'SET ORIGIN',function()
  term.redirect(term.native());term.clear();term.setCursorPos(1,1)
  print('BLACKSITE RADAR - SET MAP ORIGIN')
  print('Enter radar world coordinates. Blank cancels.')
  write('X: ');local x=tonumber(read());if not x then notify('Origin unchanged');return end
  write('Y: ');local y=tonumber(read());if not y then notify('Origin unchanged');return end
  write('Z: ');local z=tonumber(read());if not z then notify('Origin unchanged');return end
  cfg.origin={x=x,y=y,z=z};cfg.autoCenter=false;save();notify('Radar origin saved')
 end)
 button(17,20,'LOCK BASE',function()cfg.autoCenter=false;save();notify('Map locked to base coordinates') end)
 button(2,23,'RESCAN',function()discover();fetch();notify('Peripheral scan complete') end)
 button(14,23,'SCALE -0.5',function()changeScale(-.5) end)
 button(32,23,'SCALE +0.5',function()changeScale(.5) end)
 draw(2,math.min(h-5,27),'Mojang names: '..cut(lookupStatus,w-19),C.yellow)
 button(2,29,'DENSITY -0.05',function()changeDensity(-.05) end)
 button(23,29,'DENSITY +0.05',function()changeDensity(.05) end)
 draw(2,30,'Density changes radar layout, NOT Minecraft font size.',C.gray)
 button(2,25,'BASE PRESET',function()cfg.origin={x=1733,y=57,z=-1234};cfg.autoCenter=false;save();notify('Base center loaded') end)
end
local function render()
 header()
 if tab=='RADAR' then radarPage() elseif tab=='CONTACTS' then contactsPage() elseif tab=='DETAILS' then detailsPage() elseif tab=='SECURITY' then securityPage() elseif tab=='INTEL' then intelPage() else systemPage() end
end
fetch()
local function uiLoop()
local timer=os.startTimer(.20);local elapsed=0
while true do
 render()
 local event,a,b,c=os.pullEventRaw()
 if event=='terminate' then saveIntel(true);alarmOutput(false);return end
 if event=='monitor_touch' and a==monitorName then
  for i=#buttons,1,-1 do local hit=buttons[i];if c==hit.y and b>=hit.x and b<hit.x+hit.len then local ok,e=pcall(hit.fn);if not ok then notify('UI error: '..cut(e,55)) end;break end end
 elseif event=='timer' and a==timer then
  sweep=(sweep+.16)%(math.pi*2);elapsed=elapsed+.20
  if elapsed>=cfg.refresh then elapsed=0;fetch() end
  timer=os.startTimer(.20)
 elseif event=='peripheral' or event=='peripheral_detach' then discover();fetch()
 end
end

end
parallel.waitForAny(uiLoop,lookupWorker)
-- Bounded client-side frame/callback profiler. No debug.sethook, networking,
-- automatic printing, disk IO or periodic table scans in the capture loop.
STTS=STTS or{}
if STTS.PhoneDiag47 then return end -- do not stack global registration wrappers on Lua refresh
local D={};STTS.PhoneDiag47=D
-- fix64: the profiler itself cost FPS: it replaced hook.Add / net.Receive / timer.Create / timer.Simple
-- for everything loaded after it and timed every callback of the phone + Z-City. It is now OFF unless
-- zhphone_diag 1 is set (then reconnect / change map). Off = these no-op stand-ins, nothing wrapped.
local install64=CreateClientConVar('zhphone_diag','0',true,false,'1 = load the ZPhone stutter profiler on the next map load / reconnect (costs FPS); 0 = off',0,1)
if install64:GetInt()==0 then
 D.off64=true;D.active=false;D.depth=0;D.spikes={};D.frames=0;D.totalEpisodes=0;D.overflow=0
 function D.Reset()end
 function D.Begin49()end
 function D.Frame()end
 function D.Mark52()end
 function D.Install()end
 function D.Wrap(_,fn)return fn end
 function D.Call(_,fn,...)return fn(...)end
 function D.Report()print('[ZPHONE] Stutter profiler: off (zhphone_diag 1, then reconnect, to measure)')end
 concommand.Add('zhphone_diag_reset',function()end)
 concommand.Add('zhphone_diag_dump',function()D.Report()end)
 return
end
local mode=CreateClientConVar('zhphone_stutter_diag','1',true,false,'0 off; 1 recording + 5s after; 2 continuous client diagnostics',0,2)
local threshold=CreateClientConVar('zhphone_stutter_ms','16',true,false,'Minimum frame-gap threshold; also requires 1.65x baseline',8,500)
local clock=SysTime
local marks52={}
local wrappers=setmetatable({},{__mode='kv'});local wrapped=setmetatable({},{__mode='k'})
local pools,rows={},{};local rowCount=0;local sequence=0
function D.Reset()
 pools,rows={},{};rowCount=0;sequence=sequence+1
 marks52={};D.spikes={};D.depth=0;D.active=false;D.baseline=1/60;D.previous=nil;D.previousBad=false;D.warm=0;D.frames=0;D.totalEpisodes=0;D.overflow=0;D.untilAt=0;D.memoryKB48=nil;D.memoryDelta48=nil;D.phase48=nil;D.started49=nil
end
D.Reset()
local function mine(fn)
 if type(fn)~='function'or wrapped[fn]then return false end
 local i=debug.getinfo(fn,'S');local s=i and i.source or''
 if s:find('cl_stts_phone_diag47',1,true)then return false end
 return s:find('addons/remorseism/',1,true) or s:find('addons/remorseism-main/',1,true)or s:find('gamemodes/zcity/',1,true)or s:find('/cl_stts_phone_',1,true) or s:find('/stts_phone/',1,true) or s:find('weapon_stts_phone',1,true) or s:find('sh_stts_phone',1,true) or s:find('addons/zcity_phone/',1,true)
end
local function location(fn)
 local i=debug.getinfo(fn,'S');return(i.short_src or i.source or'?'):match('[^/\\]+$')..':'..(i.linedefined or 0)
end
local function finish(index,...)
 local t=pools[index]
 if t and t.seq==sequence and D.depth==index then
  local dt=clock()-t.at;local r=t.row
  r.ms=r.ms+dt*1000;r.self=r.self+math.max(0,dt-t.child)*1000;r.last=(clock()-(D.previous or clock()))*1000
  if dt*1000>r.max then r.max=dt*1000 end
  D.depth=index-1;if index>1 then local p=pools[index-1];p.child=p.child+dt end
 end
 return ...
end
function D.Wrap(name,fn,force,distinct)
 if type(fn)~='function'or wrapped[fn]or(not force and not mine(fn))then return fn end
 if not distinct and wrappers[fn]then return wrappers[fn]end
 local label=name..' ['..location(fn)..']'
 local w=function(...)
  if not D.active or D.depth>=32 then return fn(...)end
  local now=clock();local r=rows[label]
  if not r then
   if rowCount>=512 then D.overflow=D.overflow+1;return fn(...)end
   r={};rows[label]=r;rowCount=rowCount+1
  end
  if r.seq~=sequence then r.seq=sequence;r.calls=0;r.ms=0;r.self=0;r.max=0;r.first=(now-(D.previous or now))*1000;r.last=r.first end
  r.calls=r.calls+1;local index=D.depth+1;D.depth=index
  local t=pools[index]or{};pools[index]=t;t.at=now;t.child=0;t.row=r;t.seq=sequence
  -- Vararg return preserves nils and arbitrary return counts; errors propagate
  -- unchanged. Unclosed error scopes are reset at the next frame boundary.
  return finish(index,fn(...))
 end
 if not distinct then wrappers[fn]=w end;wrapped[w]=true;return w
end
-- Stable named scopes distinguish phone/main engine waits without globally
-- detouring render APIs. Cache once, not a new closure/table per camera frame.
local scopes48={}
function D.Call(name,fn,...)
 if not D.active then return fn(...)end
 local s=scopes48[name]
 if not s or s.fn~=fn then s={fn=fn,call=D.Wrap(name,fn,true,true)};scopes48[name]=s end
 return s.call(...)
end
local function memory48()
 if not collectgarbage then return end
 local ok,kb=pcall(collectgarbage,'count');if ok and type(kb)=='number'then return kb end
end
function D.Mark52(name)
 if not D.active then return end
 if STTS.PhoneScreen and STTS.PhoneScreen.InRV then return end
 if not marks52[name]then marks52[name]=clock()end
end
local function spans52(now)
 local out={};local prior=D.previous;local label='Think'
 for _,name in ipairs({'PreRender','RenderScene','PostRender'})do
  local at=marks52[name]
  if at and prior and at>=prior and at<=now then
   out[#out+1]={name=label..' -> '..name,ms=(at-prior)*1000};prior=at;label=name
  end
 end
 if prior and now>=prior then out[#out+1]={name=label..' -> next Think',ms=(now-prior)*1000}end
 return out
end
local function snapshot(dt)
 local list={};local self=0
 for name,r in pairs(rows)do if r.seq==sequence then
  list[#list+1]={name=name,calls=r.calls,ms=r.ms,self=r.self,max=r.max,first=r.first,last=r.last};self=self+r.self
 end end
 table.sort(list,function(a,b)return a.self>b.self end)
 return {at=D.previous,ms=dt*1000,baseline=D.baseline*1000,rows=list,self=self,open=D.depth,frames=1,memoryDelta=D.memoryDelta48,phase=D.phase48,spans52=spans52(clock())}
end
function D.Frame()
 local kb=D.active and memory48()or nil
 D.memoryDelta48=kb and D.memoryKB48 and kb-D.memoryKB48 or nil;D.memoryKB48=kb
 local now=clock();local rec=STTS.PhoneScreen and STTS.PhoneScreen.L and STTS.PhoneScreen.L.rec
 if rec then D.untilAt=now+5 end
 local active=mode:GetInt()==2 or(mode:GetInt()==1 and(rec~=nil or now<D.untilAt))
 if D.previous and D.active then
  local dt=now-D.previous
  if dt>0 then
   D.frames=D.frames+1;D.warm=D.warm+1
   local bad=D.warm>12 and dt>math.max(threshold:GetFloat()/1000,D.baseline*1.65)
   if bad then
    local s=snapshot(dt)
    if D.previousBad and #D.spikes>0 and D.spikes[#D.spikes].phase==s.phase then
     local old=D.spikes[#D.spikes];s.at=old.at;s.frames=old.frames+1
     if old.ms>s.ms then old.frames=s.frames;s=old end
     D.spikes[#D.spikes]=s
    else
     D.totalEpisodes=D.totalEpisodes+1;D.spikes[#D.spikes+1]=s;if #D.spikes>24 then table.remove(D.spikes,1)end
    end
   else D.baseline=D.baseline*.95+dt*.05 end
   D.previousBad=bad
  end
 end
 D.phase48=rec and 'recording' or(now<D.untilAt and 'after-recording' or 'idle');D.started49=D.started49 or now;D.previous=now;D.active=active;D.depth=0;marks52.PreRender=nil;marks52.RenderScene=nil;marks52.PostRender=nil;sequence=sequence+1
end
function D.Begin49()
 D.Frame();D.untilAt=clock()+5
 if mode:GetInt()~=0 then D.active=true;D.phase48='startup';D.warm=13 end
end
local function installTables()
 for _,name in ipairs({'PhoneRecorder31','PhoneGallery33','PhoneScreen','PhoneView43','PhoneGeo'})do
  local t=STTS[name];if type(t)=='table'then for k,f in pairs(t)do if type(k)=='string'and type(f)=='function'then t[k]=D.Wrap(name..'.'..k,f,true)end end end
 end
 local e=STTS.PhoneEIS;if e then for _,k in ipairs({'Sample','Render','Apply','Warp','Update'})do if e[k]then e[k]=D.Wrap('EIS.'..k,e[k],true)end end end
 -- GetTable is a compatibility copy in ULib: update its real callback records,
 -- preserving monitor priorities and entity hook semantics.
 local ht=hook.GetTable and hook.GetTable()or{}
 if hook.GetULibTable then
  for event,priorities in pairs(hook.GetULibTable())do for _,bucket in pairs(priorities)do for id,r in pairs(bucket)do
   if type(r)=='table'and mine(r.fn)then r.fn=D.Wrap('hook '..event..'/'..tostring(id),r.fn);if ht[event]then ht[event][id]=r.fn end end
  end end end
 else
  for event,bucket in pairs(ht)do for id,f in pairs(bucket)do bucket[id]=D.Wrap('hook '..event..'/'..tostring(id),f)end end
 end
 if net.Receivers then for name,f in pairs(net.Receivers)do net.Receivers[name]=D.Wrap('net '..name,f)end end
end
D.Install=installTables
-- Wrap only this addon's registrations; other addons' dispatch is unchanged.
local add=hook.Add
hook.Add=function(event,id,fn,...)return add(event,id,D.Wrap('hook '..event..'/'..tostring(id),fn),...)end
local receive=net.Receive
net.Receive=function(name,fn,...)return receive(name,D.Wrap('net '..name,fn),...)end
local create=timer.Create
if create then timer.Create=function(name,delay,reps,fn,...)return create(name,delay,reps,D.Wrap('timer '..name,fn),...)end end
local simple=timer.Simple
if simple then timer.Simple=function(delay,fn,...)return simple(delay,D.Wrap('timer.Simple',fn),...)end end
hook.Add('Think','STTS.PhoneDiag47.Frame',D.Frame,-2)
for _,stage in ipairs({'PreRender','RenderScene','PostRender'})do
 local name=stage
 hook.Add(name,'STTS.PhoneDiag52.Stage',function()D.Mark52(name)end,-2)
end
hook.Add('InitPostEntity','STTS.PhoneDiag47.Install',function()timer.Simple(1,installTables)end)
local function lines(full)
 local out={};local function line(s)out[#out+1]='[ZPHONE] '..s end
 line(string.format('Stutters52: mode=%d frames=%d episodes=%d kept=%d baseline=%.2fms threshold=max(%.1fms, baseline*1.65)',mode:GetInt(),D.frames,D.totalEpisodes,#D.spikes,D.baseline*1000,threshold:GetFloat()))
 local phases={};for _,s in ipairs(D.spikes)do local p=s.phase or'unknown';phases[p]=(phases[p]or 0)+1 end
 for _,p in ipairs({'startup','recording','after-recording','idle','unknown'})do if phases[p]then line('Kept episodes / '..p..': '..phases[p])end end
 local gaps={};local sum=0
 for i=2,#D.spikes do local v=D.spikes[i].at-D.spikes[i-1].at;gaps[#gaps+1]=v;sum=sum+v end
 if #gaps>0 then
  table.sort(gaps);local avg=sum/#gaps;local variance=0;for _,v in ipairs(gaps)do variance=variance+(v-avg)^2 end
  local cv=math.sqrt(variance/#gaps)/math.max(.001,avg)
  line(string.format('Intervals: median=%.3fs mean=%.3fs min=%.3fs max=%.3fs variation=%.0f%%; %s',gaps[math.ceil(#gaps/2)],avg,gaps[1],gaps[#gaps],cv*100,#gaps>=3 and(cv<.20 and 'regular pattern' or 'irregular / skipped spikes')or'need >=4 episodes for a pattern'))
 else line('Intervals: need at least 2 stutter episodes; record 20-30 seconds.')end
 for i=full and 1 or math.max(1,#D.spikes-3),#D.spikes do
  local s=D.spikes[i];line('Phase: '..(s.phase or'unknown'));line(string.format('Spike #%d: %.2fms (%d frames), attributed wall/self=%.2fms, unassigned=%.2fms, open scopes=%d',i,s.ms,s.frames,s.self,math.max(0,s.ms-s.self),s.open))
  line(string.format('  Since diagnostic start: %.3fs / %.0fms ago',s.at-(D.started49 or s.at),(clock()-s.at)*1000))
  for _,v in ipairs(s.spans52 or{})do line(string.format('  Frame span: %s = %.3fms (elapsed, NOT cause attribution)',v.name,v.ms))end
  if s.memoryDelta then line(string.format('  Lua heap delta: %+.1f KiB (negative can indicate GC; not a GC pause measurement)',s.memoryDelta))end
  for j=1,full and #s.rows or math.min(10,#s.rows)do local r=s.rows[j]
   line(string.format('  %s x%d: self=%.3fms incl=%.3fms max=%.3fms frame-offset=%.2f..%.2fms',r.name,r.calls,r.self,r.ms,r.max,r.first,r.last))
  end
 end
 if GetConVar then
  local cfg={};for _,name in ipairs({'mat_vsync','fps_max','mat_queue_mode','gmod_mcore_test'})do local c=GetConVar(name);if c and c.GetString then cfg[#cfg+1]=name..'='..c:GetString()end end
  if #cfg>0 then line('Renderer settings (read-only): '..table.concat(cfg,' '))end
 end
 local R=STTS.PhoneRecorder31;local t=R and R.NativeTimings49 and R.NativeTimings49()
 if type(t)=='table'then
  line('Native52 timings: maxima since module load; recent >=8ms events, fixed 64-entry ring. Wall time, not CPU-only.')
  line('workerEncode / retiredJoin52 run on background workers; their duration is NOT render-thread blocking time.')
  for _,name in ipairs({'originalEndScene','initSlice','fencePump','gpuCleanup','renderTick','submitCopy','workerEncode','markerBind51','markerClear51','prepareAPI52','sessionAllocate52','retiredJoin52','startAPI52','cancelPrepare52'})do
   local v=t[name];if type(v)=='table'then line(string.format('  %s max=%.3fms calls=%.0f',name,tonumber(v.maxMs)or 0,tonumber(v.calls)or 0))end
  end
  for _,v in ipairs(t.recentOver8ms or{})do line('  native event: '..tostring(v))end
 end
 line('Client callbacks + scoped engine calls; wall time, not pure Lua CPU time. Unassigned includes engine, GPU/Present, GC, server realm and uninstrumented code; not proof of cause. No global debug hook. Disable: zhphone_stutter_diag 0.')
 if D.overflow>0 then line('Diagnostic scope limit reached: '..D.overflow)end
 return out
end
function D.Report()for _,s in ipairs(lines(false))do print(s)end end
concommand.Add('zhphone_diag_reset',function()D.Reset()end)
concommand.Add('zhphone_diag_dump',function()
 local text=table.concat(lines(true),'\n');file.CreateDir('zhunter_diag');file.Write('zhunter_diag/last_stutters.txt',text);D.Report();print('[ZPHONE] data/zhunter_diag/last_stutters.txt')
end)

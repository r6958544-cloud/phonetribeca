--[[ fix63: the phone's own ear.
     fix62 clips heard what YOU hear (the Windows sound of GMod = the sound at your head). Now
     the phone hears from where it is: every sound the game starts is reported here (file,
     place, loudness, pitch); the native module (fix63+) decodes the file once and plays it
     into the clip at the phone: Source's own fall-off curve by sound level, walls between the
     phone and the sound muffle it, far sounds lose their highs, a moving source is followed.
     Sounds that only the server plays (NPCs, doors, other players' steps...) are reported by
     the server (sv_phone_ear.lua). The recorder (cl_stts_phone_recorder31.lua) crossfades
     with "what you hear" when the phone is at your head (voices of other players reach the
     PC only already mixed, so they are in the clip only then).
     fix73: the same machinery is also the speaker of a phone CALL (the phone line): the sounds
     around the OTHER phone (sent by the server, sv_phone_ear.lua) are shaped at that phone and
     played by the native module fix73 through its own output (line_play / line_set / line_stop),
     see cl_stts_phone_line73.lua. One instance for the recording (cur), one for the line. ]]
STTS=STTS or{}
local E=STTS.PhoneEar63 or{}
STTS.PhoneEar63=E
local cur          -- the recording that listens: {m=module, r=record, voices={}, ...}
local line         -- fix73: the phone line that listens: {m=module, lines={id -> {pos, gain, muffle}}, voices={}, ...}
local fileState={} -- key -> 1 sent / 2 decoded / 3 unusable (the DLL keeps decoded files) / 4 being read (fix64)
local fileInfo={}  -- key -> {sec, loop}
local keys,keyCount={},0
local MAX_VOICES=64
local NEAR_CUT=0.002 -- quieter than -54 dB at the phone: not played at all
local OPEN=20000
local CHAN_AUTO_,CHAN_STATIC_=0,6
local traceIn,traceOut={},{}
traceIn.output=traceOut;traceIn.mask=MASK_SOLID_BRUSHONLY
--[[ fix64: the files are read in the background (file.AsyncRead) and decoded on the DLL's own thread
     (native module fix64, ear_api 2): no file I/O on the game thread while filming (fix63 read up to
     3 whole files per frame right here = hitches on the record press and on every new sound). A sound
     whose file is still being read waits and is then started with its age: the DLL places it where it
     began (500 ms of slack in the mix), so it stays in sync with the picture. While the camera is
     ready, the files of the sounds around you and of the last clips are read ahead. ]]
local async64=false
local want,wantQ,reading={},{},{} -- keys to read (FIFO, recording first) / keys being read
local readCount=0
local arrived={}                  -- {key,data} read, not handed to the DLL yet
local MAX_READS=8
local FSOK=FSASYNC_OK or 0
local KEYS64='stts_phone_ear64.txt' -- the files of the last clips (read ahead next time)
local warmM,warmUntil,warmCheckAt,warmLoaded=nil,0,0,false
local recentList={}

-- Source (snd_dma.cpp SND_GetGainFromMult): the gain of a sound of this level at this distance
local function gainAt(level,dist)
 if level<=0 then return 1 end
 local rel=dist*(10^((60-level)/20)/36)
 local g=rel>0.1 and 1/rel or 10
 if g>0.5 then
  local p=2.5;if level>90 then p=2.5+(level-90)*(0.8-2.5)/50 end
  local y=-1/((0.5^p)*(0.5-1))
  g=1-1/(y*g^p)
 end
 if g<0.01 then g=0.01*(2-rel*0.01);if g<=0 then return 0 end end
 return g
end
E.GainAt=gainAt

-- "^weapons/x.wav" / ")npc\\y.wav" -> "weapons/x.wav" (Source's sound prefixes, lower case)
local function keyOf(name)
 if type(name)~='string'then return false end
 local k=keys[name];if k~=nil then return k end
 local s=string.lower(name):gsub('\\','/'):gsub('^[%*#@><%^%)%(}%$&~`%s]+',''):gsub('^/+','')
 if s==''or s:find('^[!?]')or not s:find('%.%w+$')or s:find('%.%.')then s=false end
 if keyCount>4000 then keys,keyCount={},0 end
 keys[name]=s;keyCount=keyCount+1
 return s
end

-- the file goes to the DLL once (it is decoded there, on the audio thread)
local function ensure(m,key,budget)
 local st=fileState[key]
 if st==2 or st==3 then return st end
 if st==1 then
  local s,sec,loop=m.ear_state(key)
  if s==2 then fileState[key]=2;fileInfo[key]={sec=tonumber(sec)or 0,loop=loop==true};return 2 end
  if s==3 then fileState[key]=3;return 3 end
  if s==1 then return 1 end
  fileState[key]=nil -- the DLL forgot it (reloaded): send again
 end
 if budget and budget<=0 then return 0 end
 local path='sound/'..key
 local f=file.Open(path,'rb','GAME');if not f then fileState[key]=3;return 3 end -- also from VPKs / addons
 local size=f:Size()or -1
 if size<16 or size>12*1048576 then f:Close();fileState[key]=3;return 3 end
 local data=f:Read(size);f:Close()
 if not data or #data~=size then fileState[key]=3;return 3 end
 local r=tonumber(m.ear_load(key,data))or 3
 fileState[key]=r==2 and 2 or r==1 and 1 or 3
 if r==2 then local _,sec,loop=m.ear_state(key);fileInfo[key]={sec=tonumber(sec)or 0,loop=loop==true}end
 return fileState[key]
end

-- fix64: where a file is: 1/2 in the DLL, 3 unusable, 4 queued / being read in the background
local function queueRead(key,front)
 if reading[key]then return end
 if want[key]then
  if front and wantQ[1]~=key then for i=2,#wantQ do if wantQ[i]==key then table.remove(wantQ,i);break end end;table.insert(wantQ,1,key)end
  return
 end
 if #wantQ>=600 then
  if not front then fileState[key]=nil;return end
  local drop=table.remove(wantQ);want[drop]=nil;if fileState[drop]==4 then fileState[drop]=nil end
 end
 want[key]=true;fileState[key]=4
 if front then table.insert(wantQ,1,key)else wantQ[#wantQ+1]=key end
end
local function needFile(m,key,front)
 local st=fileState[key]
 if st==2 or st==3 then return st end
 if st==1 then
  local s,sec,loop=m.ear_state(key)
  if s==2 then fileState[key]=2;fileInfo[key]={sec=tonumber(sec)or 0,loop=loop==true};return 2 end
  if s==3 then fileState[key]=3;return 3 end
  if s==1 then return 1 end
  st=nil -- the DLL forgot it (reloaded / dropped the oldest): read again
  fileState[key]=nil
 end
 if st~=4 or front then queueRead(key,front)end
 return fileState[key]
end

local function sourcePos(v)
 if v.ent then
  if IsValid(v.ent)then v.pos=v.ent:WorldSpaceCenter()else v.ent=nil;v.gone=true end
 end
 return v.pos
end
-- gain + low-pass for one sound at the phone (fix73: a line voice: at the other phone of the call,
-- times how loud that phone's speaker is for you, muffled when one of the phones is in a pocket)
local function shape(c,v,now,forceTrace)
 local src=sourcePos(v)
 local at,k,muf=c.pos,1,false
 if c.lines then
  local l=c.lines[v.line];if not l then return 0,OPEN end
  at,k,muf=l.pos,l.gain,l.muffle
 end
 local d=at:Distance(src)
 local g=gainAt(v.level,d)*v.vol*k
 local lp=d<300 and OPEN or math.max(2500,18000/(1+(d-300)/1500)) -- air: far sounds lose their highs
 if forceTrace or now>=(v.traceAt or 0)then
  v.traceAt=now+0.2+math.random()*0.1
  traceIn.start=at;traceIn.endpos=src
  util.TraceLine(traceIn)
  v.occluded=traceOut.Hit and traceOut.Fraction<0.97 and not traceOut.StartSolid
 end
 if v.occluded then g=g*0.42;lp=math.min(lp,1300)end
 if muf then g=g*0.7;lp=math.min(lp,900)end
 return g,lp
end

local function tellServer(on)
 if util.NetworkStringToID('STTS_PhoneEar63')==0 then return end -- the server has no fix63
 net.Start('STTS_PhoneEar63');net.WriteBool(on);net.SendToServer()
end
local function stopVoice(c,id)
 local v=c.voices[id];if not v then return end
 c.voices[id]=nil;c.count=c.count-1
 pcall(c.m[c.fstop],id)
end

-- fix64: voices waiting for their file
local function waitVoice(c,v)
 if c.waitCount>=64 then return end
 local list=c.waiting[v.key];if not list then list={};c.waiting[v.key]=list end
 list[#list+1]=v;c.waitCount=c.waitCount+1
end
local function dropWaiting(c,test)
 if c.waitCount==0 then return end
 for key,list in pairs(c.waiting)do
  for i=#list,1,-1 do if test(list[i])then table.remove(list,i);c.waitCount=c.waitCount-1 end end
  if not list[1]then c.waiting[key]=nil end
 end
end
-- the sound goes to the DLL (age: fix64, how long ago the game started it)
local function startVoice(c,v,now)
 if c.count>=MAX_VOICES then -- the oldest goes
  local old,oid=math.huge,nil;for id,o in pairs(c.voices)do if o.t0<old then old,oid=o.t0,id end end
  if oid then stopVoice(c,oid)end
 end
 local age=async64 and math.max(0,now-v.t0)or nil
 if age and age>0.05 then v.g,v.lp=shape(c,v,now,false)end -- it waited: where it is now
 c.id=c.id+1;local id=c.id
 local play=c.m[c.fplay]
 local ok,res=pcall(play,id,v.key,v.g,v.lp,v.pitch/100,true,age)
 if ok and res==2 then
  fileState[v.key]=nil
  if async64 then if needFile(c.m,v.key,true)==4 then waitVoice(c,v)end;return end
  ensure(c.m,v.key);ok,res=pcall(play,id,v.key,v.g,v.lp,v.pitch/100,true)
 end
 if not ok or res~=1 then if ok and res==3 then fileState[v.key]=3 end;return end
 v.sentAt=now
 c.voices[id]=v;c.count=c.count+1
 if c.used then c.used[v.key]=true end
end
-- a file's fate is known: its waiting voices start (in sync, by their age) or are dropped
local function settleIn(c,key)
 local list=c and c.waiting[key];if not list then return end
 c.waiting[key]=nil;c.waitCount=c.waitCount-#list
 local st=fileState[key];if st~=1 and st~=2 then return end
 local now=RealTime()
 for _,v in ipairs(list)do startVoice(c,v,now)end
end
local function settle(key)settleIn(cur,key);settleIn(line,key)end
local function syncRead(key) -- without file.AsyncRead only: the fix63 way, one file
 local f=file.Open('sound/'..key,'rb','GAME');if not f then return nil end
 local size=f:Size()or -1
 local data=(size>=16 and size<=12*1048576)and f:Read(size)or nil
 f:Close();return data
end
local function startRead(key)
 reading[key]=true;readCount=readCount+1
 local done=false
 local ok,res=pcall(file.AsyncRead,'sound/'..key,'GAME',function(_,_,status,data)
  if done then return end;done=true
  reading[key]=nil;readCount=math.max(0,readCount-1)
  if status==FSOK and type(data)=='string'and #data>=16 and #data<=12*1048576 then arrived[#arrived+1]={key,data}
  else fileState[key]=3;settle(key)end
 end)
 if ok and(tonumber(res)or FSOK)==FSOK then return end
 if done then return end;done=true -- could not be queued: read now (rare)
 reading[key]=nil;readCount=math.max(0,readCount-1)
 local data=syncRead(key)
 if data then arrived[#arrived+1]={key,data}else fileState[key]=3;settle(key)end
end
-- every frame with work: read files go to the DLL (bytes per frame bounded), new reads start
local function pump64()
 local m=(cur and cur.m)or(line and line.m)or warmM;if not m then return end
 local busy=cur or line
 local budget=busy and 8388608 or 2097152
 while arrived[1]and budget>0 do
  local a=arrived[1]
  local ok,r=pcall(m.ear_load,a[1],a[2]);r=ok and tonumber(r)or 3
  if r==4 then break end -- the DLL is still decoding a lot: next frame
  table.remove(arrived,1);budget=budget-#a[2]
  fileState[a[1]]=r==2 and 2 or r==1 and 1 or 3
  if r==2 then local _,sec,loop=m.ear_state(a[1]);fileInfo[a[1]]={sec=tonumber(sec)or 0,loop=loop==true}end
  settle(a[1])
 end
 local starts=busy and 6 or 2
 while starts>0 and readCount<MAX_READS and #arrived<8 and wantQ[1]do
  local key=table.remove(wantQ,1);want[key]=nil;starts=starts-1
  if fileState[key]==4 then startRead(key)end
 end
end
hook.Add('Think','STTS_PhoneEar64Read',function()
 if readCount==0 and not arrived[1]and not wantQ[1]then return end
 pump64()
end)
-- the files of the last clips: remembered, read ahead when the camera is ready again
local function remember64(used)
 if not used or not next(used)then return end
 local seen,list={},{}
 for k in pairs(used)do if not seen[k]then seen[k]=true;list[#list+1]=k end end
 for _,k in ipairs(recentList)do if not seen[k]and #list<200 then seen[k]=true;list[#list+1]=k end end
 recentList=list
 timer.Simple(1,function()file.Write(KEYS64,table.concat(recentList,'\n'))end)
end
-- fix64: called every frame while the phone camera is ready (recorder): read files ahead
function E.Warm64(m)
 local now=RealTime()
 if now<warmCheckAt then if warmM then warmUntil=now+1 end;return end
 warmCheckAt=now+0.5
 local R=STTS.PhoneRecorder31
 if cur or type(m)~='table'or(tonumber(m.ear_api)or 0)<2 or type(m.ear_load)~='function'or type(file.AsyncRead)~='function'
  or(R and R.AudioFlags62 and bit.band(R.AudioFlags62(),8)==0)then warmM=nil;return end
 async64=true;warmM=m;warmUntil=now+1
 if warmLoaded then return end
 warmLoaded=true
 local text=file.Read(KEYS64,'DATA')
 if type(text)~='string'then return end
 local list={}
 for k in text:gmatch('[^\r\n]+')do
  if #list<200 and #k<200 and not k:find('..',1,true)and k:find('^[%w_%-%./ ]+%.%w+$')then
   list[#list+1]=k;if fileState[k]==nil then queueRead(k,false)end
  end
 end
 recentList=list
end

function E.Begin(r,m)
 if cur then E.End()end
 if not(m and m.ear_play)then return end
 async64=(tonumber(m.ear_api)or 0)>=2 and type(file.AsyncRead)=='function'
 cur={m=m,r=r,voices={},count=0,id=0,client={},server={},loads=0,loadFrame=-1,pos=Vector(0,0,0),waiting={},waitCount=0,used={},
  fplay='ear_play',fset='ear_set',fstop='ear_stop',rf=-1,recent={}}
 local lp=LocalPlayer();if IsValid(lp)then cur.pos=lp:EyePos()end
 tellServer(true)
end
function E.End(r)
 local c=cur;if not c or(r and c.r~=r)then return end
 cur=nil
 for id in pairs(c.voices)do pcall(c.m[c.fstop],id)end
 tellServer(false)
 if async64 then remember64(c.used)end
end
function E.Active()return cur~=nil end

local StopName
-- one sound the game started. pos = fixed place (nil: follows ent), fromServer = relayed
-- fix73: c = the instance (cur / line), lid = the line it is heard on, rawEi = the server's entity index
-- (line: the entity is usually out of this client's view, it may not exist here at all)
local function Sound(c,name,pos,ent,level,vol,pitch,chan,flags,fromServer,lid,rawEi)
 flags=tonumber(flags)or 0
 -- SND_STOP / SND_STOP_LOOPING / SND_CHANGE_VOL / SND_CHANGE_PITCH act on what already plays
 if bit.band(flags,4)~=0 then return StopName(c,ent,name,nil,lid,rawEi)end
 if bit.band(flags,32)~=0 then return StopName(c,ent,nil,true,lid,rawEi)end
 local key=keyOf(name);if not key then return end
 level=tonumber(level)or 75;vol=math.Clamp(tonumber(vol)or 1,0,1);pitch=math.Clamp(tonumber(pitch)or 100,1,255)
 chan=tonumber(chan)or 0
 if not IsValid(ent)or ent:IsWorld()then ent=nil end
 local ei=ent and ent:EntIndex()or(c.lines and tonumber(rawEi))or 0
 if bit.band(flags,3)~=0 then
  local found=false
  for _,v in pairs(c.voices)do if v.key==key and v.ei==ei and v.line==lid then
   if bit.band(flags,1)~=0 then v.vol=vol end;if bit.band(flags,2)~=0 then v.pitch=pitch end;v.sentAt=0;found=true end end
  for _,v in ipairs(c.waiting[key]or{})do if v.ei==ei and v.line==lid then -- fix64: also the ones still waiting for their file
   if bit.band(flags,1)~=0 then v.vol=vol end;if bit.band(flags,2)~=0 then v.pitch=pitch end;found=true end end
  if found then return end
 end
 if level<=0 then return end -- 2D (UI, music, announcer): not a sound in the world
 -- the same start reported twice (hook + wrapper) in this frame
 local frame=FrameNumber()
 if c.rf~=frame then c.rf,c.recent=frame,{}end
 local dk=(lid and lid..'#'or'')..key..'|'..ei..'|'..(pos and string.format('%d,%d,%d',math.floor(pos.x/8),math.floor(pos.y/8),math.floor(pos.z/8))or'e')
 if c.recent[dk]then return end
 c.recent[dk]=true
 -- the server also tells what this client already played (prediction, shared code)
 local now=RealTime();local xk=key..'|'..ei
 if fromServer then if(c.client[xk]or -1)>now-0.35 then return end;if not c.lines then c.server[xk]=now end
 else c.client[xk]=now end
 local src=pos and Vector(pos.x,pos.y,pos.z)or(ent and ent:WorldSpaceCenter())
 if not src then return end
 local v={key=key,ei=ei,ent=(not pos)and ent or nil,pos=src,level=level,vol=vol,pitch=pitch,chan=chan,t0=now,line=lid}
 local g,lp=shape(c,v,now,true)
 if g<NEAR_CUT and not(v.ent and fileInfo[key]and fileInfo[key].loop)then
  if async64 and fileState[key]==nil then queueRead(key,false)end -- fix64: ready if it comes closer
  return
 end
 local st
 if async64 then st=needFile(c.m,key,true) -- fix64: never a file read here
 else
  if c.loadFrame~=frame then c.loadFrame,c.loads=frame,3 end
  st=ensure(c.m,key,c.loads);if st==1 or st==2 then c.loads=c.loads-1 end
 end
 if st~=1 and st~=2 and st~=4 then return end
 -- Source: a new sound on the same entity + channel replaces the old one
 if ei~=0 and chan~=CHAN_AUTO_ and chan~=CHAN_STATIC_ then
  for id,o in pairs(c.voices)do if o.ei==ei and o.chan==chan and o.line==lid then stopVoice(c,id)end end
  dropWaiting(c,function(o)return o.ei==ei and o.chan==chan and o.line==lid end)
 end
 v.g,v.lp=g,lp
 if st==4 then waitVoice(c,v)return end -- fix64: starts (in sync) once its file is read
 startVoice(c,v,now)
end
function E.Sound(name,pos,ent,level,vol,pitch,chan,flags,fromServer)
 local c=cur;if not c then return end
 return Sound(c,name,pos,ent,level,vol,pitch,chan,flags,fromServer)
end
-- Entity:StopSound / CSoundPatch:Stop. name = a file, a sound script (its files) or nil (loopsOnly: the loops)
StopName=function(c,ent,name,loopsOnly,lid,rawEi)
 local ei=IsValid(ent)and not ent:IsWorld()and ent:EntIndex()or(c.lines and tonumber(rawEi))or 0
 local set
 if type(name)=='string'and name~=''then
  set={}
  local k=keyOf(name)
  if k then set[k]=true
  else -- a sound script: the files it can play
   local ok,pr=pcall(sound.GetProperties,name)
   local s=ok and type(pr)=='table'and pr.sound
   if type(s)=='string'then s={s}end
   if type(s)=='table'then for _,f in ipairs(s)do local fk=keyOf(f);if fk then set[fk]=true end end end
   if not next(set)then return end
  end
 end
 for id,v in pairs(c.voices)do
  if v.ei==ei and v.line==lid and(not set or set[v.key])and(not loopsOnly or(fileInfo[v.key]and fileInfo[v.key].loop))then stopVoice(c,id)end
 end
 dropWaiting(c,function(v)return v.ei==ei and v.line==lid and(not set or set[v.key])and(not loopsOnly or not fileInfo[v.key]or fileInfo[v.key].loop)end)
end
function E.StopName(ent,name,loopsOnly)
 local c=cur;if not c then return end
 return StopName(c,ent,name,loopsOnly)
end

-- every sound of an instance re-shaped (~30 Hz each), the finished ones stopped
local function stepVoices(c,now)
 if c.waitCount>0 and now>=(c.waitSweep or 0)then -- fix64: a file that never comes
  c.waitSweep=now+1
  local lines=c.lines
  dropWaiting(c,function(v)return now-v.t0>30 or(lines and not lines[v.line])end)
 end
 local lines=c.lines
 for id,v in pairs(c.voices)do
  local info=fileInfo[v.key]
  if not info and fileState[v.key]==1 and now-v.t0>0.1 then if async64 then needFile(c.m,v.key)else ensure(c.m,v.key)end;info=fileInfo[v.key]end
  local age=now-v.t0
  local over
  if fileState[v.key]==3 or(lines and not lines[v.line])then over=true -- fix73: that line is gone
  elseif info then
   if info.loop then over=v.gone or age>(v.ent and 90 or 25)
   else over=age>info.sec/(v.pitch/100)+0.25 end
  else over=age>(async64 and 8 or 3)end
  if over then stopVoice(c,id)
  elseif now-(v.sentAt or 0)>=1/30 then
   local g,lp=shape(c,v,now,false)
   if math.abs(g-v.g)>0.02*math.max(v.g,0.05)or lp~=v.lp or v.sentAt==0 then
    v.g,v.lp=g,lp;pcall(c.m[c.fset],id,g,lp,v.pitch/100)
   end
   v.sentAt=now
  end
 end
end
-- every frame while filming: where the phone is, every sound re-shaped (~30 Hz each)
function E.Step(r,pos)
 local c=cur;if not c or c.r~=r then return end
 if pos then c.pos=pos;c.pocket=false
 else
  local w=r.wep;local o=IsValid(w)and w:GetOwner()
  if IsValid(o)then c.pos=o:GetPos()+Vector(0,0,36)elseif IsValid(w)then c.pos=w:GetPos()end
  c.pocket=true
 end
 stepVoices(c,RealTime())
end

--[[ fix73: the phone line. m = the native module fix73 (line_api 1, line_open done by the caller).
     lines = {source phone index -> {pos=Vector, gain=0..1, muffle=bool}}: where the other phone of
     the call is and how loud its speaker is for you; the server sends what is loud enough there. ]]
function E.LineBegin(m)
 if line then return true end
 if type(m)~='table'or type(m.line_play)~='function'or type(m.ear_load)~='function'or(tonumber(m.ear_api)or 0)<2
  or type(file.AsyncRead)~='function'then return false end
 async64=true
 line={m=m,lines={},voices={},count=0,id=0,client={},server={},loads=0,loadFrame=-1,pos=Vector(0,0,0),waiting={},waitCount=0,
  fplay='line_play',fset='line_set',fstop='line_stop',rf=-1,recent={}}
 return true
end
function E.LineEnd()
 local c=line;if not c then return end
 line=nil
 pcall(c.m.line_stop) -- all of them
end
function E.LineActive()return line~=nil end
function E.LineSet(lines)
 local c=line;if not c then return end
 c.lines=type(lines)=='table'and lines or{}
end
function E.LineStep()
 local c=line;if not c then return end
 stepVoices(c,RealTime())
end
function E.LineSound(lid,name,pos,ent,level,vol,pitch,chan,flags,rawEi)
 local c=line;if not c or not c.lines[lid]then return end
 return Sound(c,name,pos,ent,level,vol,pitch,chan,flags,true,lid,rawEi)
end
function E.LineStats()
 local c=line;if not c then return nil end
 local n=0;for _ in pairs(c.lines)do n=n+1 end
 return {voices=c.count,waiting=c.waitCount,lines=n}
end

-- the main view (where YOU hear from): the recorder crossfades by the phone's distance to it
local function onEmit(t)
 if type(t)~='table'then return end
 if not cur then -- fix64: the camera is ready: the file is read ahead (nothing else happens)
  if warmM and(tonumber(t.SoundLevel)or 75)>0 and RealTime()<warmUntil then
   local key=keyOf(t.SoundName);if key and fileState[key]==nil then queueRead(key,false)end
  end
  return
 end
 pcall(E.Sound,t.SoundName,t.Pos,t.Entity,t.SoundLevel,t.Volume,t.Pitch,t.Channel,t.Flags,false)
end
-- ULib (Z-City needs it): a monitor hook runs first and can't be cut short by others' returns
local function addHooks()
 hook.Add('EntityEmitSound','STTS_PhoneEar63',onEmit,HOOK_MONITOR_HIGH)
 hook.Add('RenderScene','STTS_PhoneEarView63',function(origin)if cur and isvector(origin)then E.view=Vector(origin)end end,HOOK_MONITOR_HIGH)
end
addHooks()
hook.Add('Initialize','STTS_PhoneEar63',addHooks)
-- sound.Play / StopSound do not always pass through EntityEmitSound: wrapped (once)
if sound and sound.Play and not E.origPlay then
 local orig=sound.Play;E.origPlay=orig
 sound.Play=function(name,pos,level,pitch,volume,...)
  if cur then pcall(E.Sound,name,pos,nil,level or 75,volume or 1,pitch or 100,CHAN_AUTO_,0,false)end
  return orig(name,pos,level,pitch,volume,...)
 end
end
do
 local meta=FindMetaTable('Entity')
 if meta and meta.StopSound and not E.origStop then
  local orig=meta.StopSound;E.origStop=orig
  meta.StopSound=function(self,name,...)
   if cur then pcall(E.StopName,self,name)end
   return orig(self,name,...)
  end
 end
 local patches=E.patches or setmetatable({},{__mode='k'});E.patches=patches
 local patch=FindMetaTable('CSoundPatch')
 if patch and patch.Stop and not E.origPatchStop then
  local orig=patch.Stop;E.origPatchStop=orig
  patch.Stop=function(self,...)
   local i=cur and patches[self]
   if i then pcall(E.StopName,i[1],i[2])end
   return orig(self,...)
  end
 end
 if patch and patch.FadeOut and not E.origPatchFade then
  local orig=patch.FadeOut;E.origPatchFade=orig
  patch.FadeOut=function(self,sec,...)
   local i=cur and patches[self]
   if i then timer.Simple(math.Clamp(tonumber(sec)or 0,0,30),function()if cur then pcall(E.StopName,i[1],i[2])end end)end
   return orig(self,sec,...)
  end
 end
 if CreateSound and not E.origCreate then
  local orig=CreateSound;E.origCreate=orig
  CreateSound=function(ent,name,...)
   local p=orig(ent,name,...)
   if p and type(name)=='string'then patches[p]={ent,name}end
   return p
  end
 end
end
-- relayed by the server: sounds this client gets only as engine messages
net.Receive('STTS_PhoneEar63',function()
 if not cur then return end
 local name=net.ReadString();local pos=net.ReadVector();local ei=net.ReadUInt(16);local follow=net.ReadBool()
 local level=net.ReadUInt(8);local vol=net.ReadUInt(8)/255;local pitch=net.ReadUInt(8);local chan=net.ReadInt(16);local flags=net.ReadUInt(12)
 local ent=ei>0 and Entity(ei)or nil
 if not IsValid(ent)then ent,follow=nil,false
 elseif ent:IsDormant()then follow=false end -- out of this client's view: where the server says
 pcall(E.Sound,name,(not follow)and pos or nil,ent,level,vol,pitch,chan,flags,true)
end)

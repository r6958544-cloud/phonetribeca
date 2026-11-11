--[[ fix73: the phone line - what the speaker of YOUR phone plays during a call.
     The voices go phone to phone on the server (sv_phone.lua, PHONE.Line73): whoever talks near
     the other phone (in the hand, on the floor, on a table, in a pocket) is heard here through
     GMod voice chat, as loud as that phone's microphone and your speaker make it.
     The game sounds around the other phone (shots, steps, doors, screams...) can not go through
     voice chat: the server sends where that phone is (10 times a second) and every sound that is
     loud enough there (sv_phone_ear.lua). The native module fix73 decodes the files (the same
     bank as the clip sound of the recorder) and plays them through its own sound output, shaped
     at the other phone (cl_stts_phone_ear63.lua: Source's fall-off, walls, far sounds lose their
     highs, a phone in a pocket is muffled) and filtered like a phone call.
     Needs zhphone_native 1 and the DLL fix73; without it the voices still work, only the game
     sounds of the call are missing. Nothing runs while you are not on a call. ]]
STTS=STTS or{}
local L=STTS.PhoneLine73 or{}
STTS.PhoneLine73=L
local NET='STTS_PhoneLine73'
local cvEar=CreateClientConVar('zhphone_line_ear','1',true,false,'Phone calls: hear the game sounds around the other phone (native module fix73+): 0 off, 1 on',0,1)
local cvBand=CreateClientConVar('zhphone_line_band','1',true,false,'Sound of a phone call (native module fix73+): 0 full band, 1 HD voice 120-7000 Hz, 2 old phone 300-3400 Hz',0,2)
local cvGain=CreateClientConVar('zhphone_line_gain','1',true,false,'Loudness of the game sounds heard through a phone call (native module fix73+)',0,4)
local lines={}            -- source phone index -> {pos=Vector, gain=0..1, muffle=bool} (from the server)
local stateAt=-100        -- RealTime of the last state
local open,mod=false,nil  -- the native line plays
local retryAt=0
local told,tellAt=false,0 -- what the server knows
L.stats={opened=0,failed=0,sounds=0,states=0}

local function ear()local E=STTS.PhoneEar63;return E and E.LineBegin and E or nil end
-- the module is loaded by the recorder 3 s after joining; the line loads it itself only after that
-- (zhphone_new_recorder 0), never while the game is still connecting
local probeAt=math.huge
hook.Add('InitPostEntity','STTS_PhoneLine73',function()probeAt=RealTime()+5 end)
if IsValid(LocalPlayer())then probeAt=RealTime()+5 end -- the file was reloaded in a running game
-- the loaded native module, if it can play a line
local function module73()
 local R=STTS.PhoneRecorder31;if not R then return nil end
 local m=(RealTime()>=probeAt and R.Probe73 and R.Probe73())or(R.Native64 and R.Native64())
 if type(m)=='table'and(tonumber(m.line_api)or 0)>=1 and(tonumber(m.ear_api)or 0)>=2
  and type(m.line_open)=='function'and type(m.line_play)=='function'and type(m.line_gain)=='function'then return m end
end
L.Module=module73
local function capable()
 return cvEar:GetBool()and ear()~=nil and type(file.AsyncRead)=='function'and module73()~=nil
end
L.Capable=capable
local function tell(force)
 if util.NetworkStringToID(NET)==0 then return end -- the server has no fix73
 local on=capable()
 local now=RealTime()
 if on==told and not(on and(force or now>=tellAt))then return end
 told,tellAt=on,now+20
 net.Start(NET);net.WriteBool(on);net.SendToServer()
end
timer.Create('STTS_PhoneLine73Tell',3,0,function()pcall(tell,false)end)
cvars.AddChangeCallback('zhphone_line_ear',function()timer.Simple(0.6,function()pcall(tell,true)end)end,'STTS_PhoneLine73')

local function close()
 if not open then return end
 open=false
 local E=ear();if E then pcall(E.LineEnd)end
 if mod then pcall(mod.line_close)end
 mod=nil
end
L.Close=close

net.Receive(NET,function()
 local kind=net.ReadUInt(2)
 if kind==0 then -- where the other phone(s) of your call are
  local n=net.ReadUInt(3)
  local now={}
  for _=1,n do
   local id=net.ReadUInt(16);local pos=net.ReadVector();local muffle=net.ReadBool();local gain=net.ReadUInt(8)/255
   now[id]={pos=pos,muffle=muffle,gain=gain}
  end
  lines=now;stateAt=RealTime();L.stats.states=L.stats.states+1
  local E=ear();if open and E then E.LineSet(lines)end
 elseif kind==1 then -- a sound loud enough at one of them
  if not open then return end
  local id=net.ReadUInt(16)
  local name=net.ReadString();local pos=net.ReadVector();local ei=net.ReadUInt(16);local follow=net.ReadBool()
  local level=net.ReadUInt(8);local vol=net.ReadUInt(8)/255;local pitch=net.ReadUInt(8);local chan=net.ReadInt(16);local flags=net.ReadUInt(12)
  local ent=ei>0 and Entity(ei)or nil
  if not IsValid(ent)then ent,follow=nil,false
  elseif ent:IsDormant()then follow=false end -- out of this client's view: where the server says
  L.stats.sounds=L.stats.sounds+1
  local E=ear();if E then pcall(E.LineSound,id,name,(not follow)and pos or nil,ent,level,vol,pitch,chan,flags,ei)end
 end
end)

local cvVolume,cvMuteFocus
hook.Add('Think','STTS_PhoneLine73',function()
 local now=RealTime()
 local want=next(lines)~=nil and now-stateAt<1.5 and cvEar:GetBool()
 if not want then
  if open then close()end
  if next(lines)and now-stateAt>=1.5 then lines={}end -- the server went quiet: the call is over
  return
 end
 local E=ear();if not E then return end
 if not open then
  if now<retryAt then return end
  local m=module73()
  if not m then retryAt=now+5;return end
  local ok,r=pcall(m.line_open)
  if not ok or tonumber(r)~=1 or not E.LineBegin(m)then
   if ok and tonumber(r)==1 then pcall(m.line_close)end
   L.stats.failed=L.stats.failed+1;retryAt=now+5;return
  end
  open,mod=true,m;L.stats.opened=L.stats.opened+1
  E.LineSet(lines)
 end
 E.LineStep()
 -- the line plays outside of the game's mixer: the game's volume and "mute when not in focus" here
 cvVolume=cvVolume or GetConVar('volume');cvMuteFocus=cvMuteFocus or GetConVar('snd_mute_losefocus')
 local master=cvGain:GetFloat()*(cvVolume and math.Clamp(cvVolume:GetFloat(),0,1)or 1)
 if cvMuteFocus and cvMuteFocus:GetBool()and system.HasFocus and not system.HasFocus()then master=0 end
 local ok,alive=pcall(mod.line_gain,master,0,math.Clamp(cvBand:GetInt(),0,2))
 if not ok or alive==false then close();retryAt=now+1 end -- the native line ended (device lost): open again
end)
hook.Add('ShutDown','STTS_PhoneLine73',close)

concommand.Add('zhphone_line_stats',function()
 local m=module73()
 local n=0;for _ in pairs(lines)do n=n+1 end
 print(string.format('[ZPHONE] Phone line (fix73): zhphone_line_ear %d, band %d, gain %.2f; the server knows: %s',cvEar:GetInt(),cvBand:GetInt(),cvGain:GetFloat(),tostring(told)))
 if not m then
  local R=STTS.PhoneRecorder31
  print('[ZPHONE] Game sounds of calls need the native module fix73 (zhphone_native 1): '..tostring(R and(R.nativeError or R.nativeBuild)or'no recorder'))
 end
 print(string.format('[ZPHONE] Lines now: %d (last state %.1f s ago), open: %s, opened %d, failed %d, states %d, sounds %d',n,RealTime()-stateAt,tostring(open),L.stats.opened,L.stats.failed,L.stats.states,L.stats.sounds))
 for id,l in pairs(lines)do print(string.format('[ZPHONE]  phone #%d at %s, speaker %.2f%s',id,tostring(l.pos),l.gain,l.muffle and', muffled'or''))end
 local E=ear();local s=E and E.LineStats and E.LineStats()
 if s then print(string.format('[ZPHONE] Voices %d, waiting for files %d',s.voices,s.waiting))end
 if mod and type(mod.line_poll)=='function'then
  local ok,p=pcall(mod.line_poll)
  if ok and type(p)=='table'then
   local st={[0]='starting','playing','no sound device','ended'}
   print(string.format('[ZPHONE] Output: %s, %d Hz x%d, queued %.0f ms, underruns %d, reopened %d, voices %d, played %d, peak %.2f, %.0f s %s',
    st[tonumber(p.state)or -1]or'closed',tonumber(p.rate)or 0,tonumber(p.channels)or 0,tonumber(p.queuedMs)or 0,tonumber(p.underruns)or 0,
    tonumber(p.reopened)or 0,tonumber(p.voices)or 0,tonumber(p.played)or 0,tonumber(p.peak)or 0,tonumber(p.seconds)or 0,(p.error and p.error~='')and('/ '..p.error)or''))
  end
 end
end)

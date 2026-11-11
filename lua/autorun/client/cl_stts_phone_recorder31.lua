-- fix35: optional GPU-only asynchronous native backend.
-- New local recorder. No atlas, JPEG network upload or gallery transcoding in
-- the capture loop. Stock-Lua MJPEG fallback; optional native H264/NVENC backend.
STTS=STTS or {};local R={};STTS.PhoneRecorder31=R
local enabled=CreateClientConVar("zhphone_new_recorder","1",true,false,"Client recording pipeline; 0 = legacy client encoder",0,1)
local useNative=CreateClientConVar("zhphone_native","0",true,false,"Use optional zhphone binary when installed",0,1)
local nativeRate=CreateClientConVar("zhphone_native_mbps","12",true,false,"Native compact peak Mbps (<14); 14 restores previous CQ profile",6,20)
local luaQuality50=CreateClientConVar("zhphone_lua_quality","1",true,false,"Lua recording: 0 legacy 128x224/J62; 1 256x448/J80; 2 366x648/J88. All 8fps; larger captures can stall more.",0,2)
-- fix62: clip sound (native module fix62+ only): your real microphone + the sound of this game
local audioOn62=CreateClientConVar("zhphone_audio","1",true,false,"Phone videos record sound (native module fix62+): 0 = silent clips",0,1)
local audioMic62=CreateClientConVar("zhphone_audio_mic","1",true,false,"Phone microphone in videos: 0 off, 1 only while you talk in voice chat, 2 always while filming",0,2)
local audioGame62=CreateClientConVar("zhphone_audio_game","1",true,false,"Game sound in videos: 0 off, 1 Garry's Mod only (Windows 10 2004+), 2 + whole-PC sound on older Windows",0,2)
local audioMicGain62=CreateClientConVar("zhphone_audio_mic_gain","1",true,false,"Microphone loudness in phone videos",0,4)
-- fix63: the phone's own ear (native module fix63+): game sounds are heard where the phone is
local audioEar63=CreateClientConVar("zhphone_audio_ear","1",true,false,"Where the phone hears the game (native module fix63+): 0 at your head (what you hear), 1 at the phone + what you hear while it is near you, 2 only at the phone",0,2)
-- fix64: FXAA on the recorded video (native module fix64+, done on the GPU by the encoder: no FPS cost in game)
local fxaa64=CreateClientConVar("zhphone_fxaa","1",true,false,"FXAA anti-aliasing on phone videos (native module fix64+): 0 off, 1 quality, 2 strong",0,2)
local native,checked
-- fix68: which GPU encoder the native module tries first (fix69 DLL: NVIDIA NVENC, AMD AMF, Media Foundation = Intel / any GPU)
-- fix70: 4 = the no-GPU-encoder path first (CPU MJPEG while filming, converted to H.264 after the stop)
R.Enc68=CreateClientConVar("zhphone_encoder","0",true,false,"Phone video encoder (native module fix69+): 0 auto (NVENC, AMF, Media Foundation, then CPU), 1 NVENC first, 2 AMD AMF first, 3 Media Foundation first, 4 CPU (MJPEG -> H.264 after the stop, fix70 DLL)",0,4)
local function applyFXAA64(m)
 if type(m)=="table" and type(m.fxaa)=="function" then pcall(m.fxaa,math.Clamp(fxaa64:GetInt(),0,2)) end
 if type(m)=="table" and type(m.encoder)=="function" then pcall(m.encoder,math.Clamp(R.Enc68:GetInt(),0,4)) end
end
cvars.AddChangeCallback("zhphone_fxaa",function()applyFXAA64(native)end,"STTS_PhoneFXAA64")
cvars.AddChangeCallback("zhphone_encoder",function()applyFXAA64(native)end,"STTS_PhoneEncoder68")
local targets={}
local markerRT
local function gpuMarker(token)
 if not markerRT then markerRT=GetRenderTargetEx("stts_recorder_gpu_command34",64,64,RT_SIZE_LITERAL,MATERIAL_RT_DEPTH_NONE,0,0,IMAGE_FORMAT_RGB888) end
 render.PushRenderTarget(markerRT,0,0,64,64)
 render.Clear(math.floor(token/65536)%256,math.floor(token/256)%256,token%256,255,false,false)
 render.PopRenderTarget()
end
local function scr() return STTS.PhoneScreen end
local function u32(n) n=math.floor(n)%4294967296;return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local function announce(s) R.lastError=s end -- no unsolicited chat/console/UI output
local function NativeBinaryInstalled()
 local arch = jit and jit.arch or ""
 if arch ~= "x86" and arch ~= "x64" then return false end
 local suffix
 if system.IsWindows() then suffix = arch == "x64" and "win64" or "win32"
 elseif system.IsLinux() then suffix = arch == "x64" and "linux64" or "linux"
 elseif system.IsOSX and system.IsOSX() then suffix = arch == "x64" and "osx64" or "osx"
 else return false end
 local path = "lua/bin/gmcl_zhphone_" .. suffix .. ".dll"
 -- Binary modules are installed into the actual client garrysmod/lua/bin folder.
 -- A Lua shim or an unrelated architecture's DLL is not sufficient.
 return file.Exists(path, "MOD")
end
local function probe()
 if useNative:GetInt()==0 then R.nativeError="Disabled by client setting zhphone_native=0";return end
 if not checked then
  checked=true
  local m = type(_G.zhphone) == "table" and _G.zhphone
      or (package and package.loaded and type(package.loaded.zhphone) == "table" and package.loaded.zhphone)
  if not m then
   if not NativeBinaryInstalled() then
    R.nativeError = "Optional zhphone binary is not installed; using Lua/MJPEG"
    return
   end
   local ok, loaded = pcall(require, "zhphone")
   if not ok then R.nativeError = "require(zhphone): " .. tostring(loaded); return end
   m = type(loaded) == "table" and loaded or _G.zhphone
  end
  -- fix64: the old "ZPhone - fix63 DLL compat" addon is not needed any more: it renamed the build
  -- and muted the phone's ear every frame. Undo the rename; its audio pump is removed after start().
  if type(m)=="table" and m.zphone_fix63_compat then
   R.compat63=true
   if m.build_real then m.build=m.build_real end
   MsgC(Color(255,180,80),"[ZPHONE] ",color_white,"Unsubscribe \"ZPhone - fix63 DLL compat\": it is not needed with fix64 (neutralised)\n")
  end
  R.nativeBuild=type(m)=="table" and tostring(m.build)or "unknown"
  local safe=type(m)=="table" and m.api_version==3 and m.async_gpu==true and
   (m.build=="fix73-phone-line" or m.build=="fix70-cpu-fallback" or m.build=="fix69-multigpu" or m.build=="fix66-export" or m.build=="fix64-fxaa-prepared" or m.build=="fix63-phone-ear" or m.build=="fix62-phone-audio" or m.build=="fix37-phone-media-temp" or m.build=="fix39-atomic-phone-recorder" or m.build=="fix42-phone-predict-vbr" or m.build=="fix46-async-local-export" or m.build=="fix49-budgeted-gpu-init" or m.build=="fix51-prepared-marker-cache" or m.build=="fix52-background-session-retirement")
  if safe then for _,k in ipairs({"start","capture","finish","cancel","poll"})do if type(m[k])~="function"then safe=false;break end end end
  if not safe then R.nativeError="Incompatible native module: "..R.nativeBuild.."; install the DLL from the full fix64 package and restart GMod";return end
  native=m
  applyFXAA64(m)
  local diag=STTS.PhoneDiag47
  if diag then for _,k in ipairs({'start','capture','poll','finish','cancel','export_start','export_poll','export_cancel','status49','prepare51','cancel_prepare51'})do
   if type(m[k])=='function'then m[k]=diag.Wrap('native.'..k,m[k],true)end
  end end
 end
 if native then R.nativeError=nil end
 return native
end
-- Only the already-loaded module is used for export; no D3D hook install on Save.
-- fix64: the loaded module (nil while not loaded); the phone's ear reads files ahead with it
function R.Native64()return native end
-- fix73: the phone line (cl_stts_phone_line73.lua) loads the module itself when the preload did not
-- (zhphone_new_recorder 0), never while a clip is being recorded
function R.Probe73()
 if useNative:GetInt()==0 then return nil end
 if not checked then local S=scr();if not(S and S.L and S.L.rec)then probe()end end
 return native
end
function R.NativeTimings49()
 if native and type(native.timings)=='function'then local ok,t=pcall(native.timings);if ok then return t end end
end
function R.Exporter46()
 -- fix66: Save loads the module itself (was: only after a recording / the preload, else .mp4.dat)
 local S=scr();if not checked and enabled:GetInt()~=0 and not (S and S.L.rec) then probe() end
 if useNative:GetInt()~=0 and native and type(native.export_start)=="function" and type(native.export_poll)=="function" and type(native.export_cancel)=="function" then return native end
end
-- Load optional binaries before the first record button press, not mid-clip.
hook.Add("InitPostEntity","STTS_Recorder33Preload",function()
 timer.Simple(3,function()
  local S=scr();if enabled:GetInt()~=0 and not (S and S.L.rec) then probe() end
 end)
end)
local function target(w,h)
 local key=w.."x"..h
 if not targets[key] then
  local rt=GetRenderTargetEx("stts_rec31_"..key,w,h,RT_SIZE_LITERAL,MATERIAL_RT_DEPTH_SEPARATE,0,0,IMAGE_FORMAT_RGB888)
  targets[key]={rt=rt,mat=CreateMaterial("stts_rec31m_"..key,"UnlitGeneric",{["$basetexture"]=rt:GetName(),["$vertexcolor"]=1,["$vertexalpha"]=1,["$ignorez"]=1})}
 end
 return targets[key]
end
local warm49=0
hook.Add("PostRender","STTS_Recorder49Warm",function()
 local S=scr();local L=S and S.L
 if not L or L.rec or not L.raised or L.camMode~=1 or useNative:GetInt()==0 then return end
 -- Only the known installed async backend gets native-size preparation.
 if not native or warm49>=4 then return end
 warm49=warm49+1
 if warm49==1 then target(720,1260)
 elseif warm49==2 then gpuMarker(0) -- no capture ticket, only the small command RT
 elseif STTS.PhoneEIS and STTS.PhoneEIS.Warm49 then STTS.PhoneEIS.Warm49(720,1260,warm49==3 and 2 or 1,"record")end
end)
function R.Enabled() return enabled:GetInt()~=0 end
-- fix63: 0 = the game is heard at your head only (fix62), 1 = at the phone + at your head while
-- the phone is near you, 2 = at the phone only. 0 too while the DLL has no ear (older than fix63)
local function earMode63(m)
 if type(m)~="table" or (tonumber(m.ear_api) or 0)<1 or type(m.ear_play)~="function" or not STTS.PhoneEar63 then return 0 end
 if audioGame62:GetInt()==0 then return 0 end
 return math.Clamp(audioEar63:GetInt(),0,2)
end
R.EarMode63=function()return earMode63(native)end
-- fix62: what the clip hears. 1 = microphone, 2 = this game's sound (at your head), 4 = whole-PC
-- fallback, 8 (fix63) = the phone's ear
local function audioFlags62(m)
 if audioOn62:GetInt()==0 or type(m)~="table" or (tonumber(m.audio_api) or 0)<1 or type(m.audio)~="function" then return 0 end
 local f=0
 if audioMic62:GetInt()>0 then f=f+1 end
 local ear=earMode63(m)
 if audioGame62:GetInt()>0 and ear~=2 then f=f+2 end
 if audioGame62:GetInt()==2 and ear~=2 then f=f+4 end
 if ear>0 then f=f+8 end
 return f
end
R.AudioFlags62=function()return audioFlags62(native)end
-- the voice key: GMod's own hooks + Z-City's flag + the engine state (one of them may be cut short
-- by another addon returning from PlayerStartVoice)
local talk62=false
hook.Add("PlayerStartVoice","STTS_PhoneClipMic62",function(ply)if ply==LocalPlayer()then talk62=true end end)
hook.Add("PlayerEndVoice","STTS_PhoneClipMic62",function(ply)if ply==LocalPlayer()then talk62=false end end)
local function talking62()
 local lp=LocalPlayer();if not IsValid(lp)then return false end
 if not lp:Alive()or(lp.organism and lp.organism.otrub)then return false end -- nobody hears a dead / unconscious player either
 return talk62 or lp.IsSpeak==true or(lp.IsSpeaking and lp:IsSpeaking())or false
end
R.Talking62=talking62
local volume62
-- fix63: what YOU hear is not what the phone hears: dead, unconscious, deafened by a blast, dizzy
-- (Z-City fades / filters your game sound then), so the phone's ear alone records
local function deaf63(lp)
 if not lp:Alive() then return true end
 if (tonumber(lp.tinnitus) or 0)>CurTime()-1.5 then return true end
 local org=lp.organism
 if type(org)=="table" and (org.otrub or (tonumber(org.disorientation) or 0)>3 or (tonumber(org.brain) or 0)>0.2) then return true end
 if lp.PlayerClassName=="headcrabzombie" then return true end
 return false
end
-- fix63: 1 = the phone is at your head (what you hear is what it hears, with the voices of the
-- others), 0 = away from you (its own ear only). 70..170 units, smoothed
local function near63(r,pos,lp)
 local E=STTS.PhoneEar63
 local target=1
 if r.earMode63==2 or r.noLoop63 then target=0 -- no "what you hear" (setting / old Windows)
 elseif not IsValid(lp) or deaf63(lp) then target=0
 else
  local at=pos
  if not at then
   local w=r.wep;local o=IsValid(w) and w:GetOwner()
   if IsValid(o) then at=(o==lp) and lp:EyePos() or o:GetPos()+Vector(0,0,36) elseif IsValid(w) then at=w:GetPos() end
  end
  local view=(E and E.view) or lp:EyePos()
  if at then
   local x=math.Clamp((at:Distance(view)-70)/100,0,1)
   target=1-x*x*(3-2*x)
  end
 end
 local now=RealTime();local dt=math.Clamp(now-(r.nearAt63 or now),0,0.25);r.nearAt63=now
 local n=r.near63 or target
 n=n+math.Clamp(target-n,-dt*3,dt*3)
 r.near63=n
 return n
end
-- every frame while filming: microphone by voice + distance phone<->mouth, game sound back to
-- its true loudness (your "volume" setting is undone), a pocket muffles everything
local function audioStep62(r,pos)
 local m=r.native;if not r.audio62 or not m then return end
 local lp=LocalPlayer()
 local mic,muffle=0,0
 local mode=audioMic62:GetInt()
 if mode==2 or(mode==1 and talking62())then mic=math.Clamp(audioMicGain62:GetFloat(),0,4)end
 if pos and IsValid(lp)then
  local d=pos:Distance(lp:EyePos())
  if d>40 then mic=d>900 and 0 or mic*40/d end
 else mic,muffle=mic*.6,1 end
 volume62=volume62 or GetConVar("volume")
 local v=volume62 and volume62:GetFloat()or 1
 local game=audioGame62:GetInt()>0 and math.Clamp(1/math.max(v,.05),1,3)or 0
 local ear=0
 if r.ear63 then -- fix63: the phone's ear takes over when the phone is away from you
  local now=RealTime()
  if now>=(r.loopCheck63 or 0) then -- the Windows capture of the game failed: the ear alone, everywhere
   r.loopCheck63=now+0.5
   local ok,p=pcall(m.poll)
   if ok and type(p)=="table" then r.noLoop63=tonumber(p.audioGame)==3 or nil end
  end
  local near=near63(r,pos,lp)
  game,ear=game*near,1-near
  local E=STTS.PhoneEar63;if E then E.Step(r,pos)end
 end
 r.audioGains62={mic,game,muffle,ear}
 pcall(m.audio,mic,game,muffle,ear)
end
-- stopping / draining: the same gains, so the native watchdog keeps the sound running
local function audioKeep62(r)
 local g=r.audioGains62;if r.audio62 and r.native and g then pcall(r.native.audio,g[1],g[2],g[3],g[4] or 0)end
end
-- fix63: the phone stops listening (the voices fade out in the DLL)
local function earEnd63(r)
 if r.ear63 then r.ear63=false;local E=STTS.PhoneEar63;if E then pcall(E.End,r)end end
end
local function makeFallback(r)
 local q=math.Clamp(luaQuality50:GetInt(),0,2)
 local presets={{128,224,62},{256,448,80},{366,648,88}};local v=presets[q+1]
 r.captureTick51=nil;r.backend="lua-mjpeg";r.w,r.h,r.fps=v[1],v[2],8;r.jpegQuality50=v[3];r.maxFrames=960;r.sizes,r.durations={},{};r.gallerySamples={}
 r.filePath=r.base..".mp4";r.file=file.Open(r.filePath,"wb","DATA")
 if not r.file then r.filePath=r.base..".mp4.dat";r.file=file.Open(r.filePath,"wb","DATA") end
 if not r.file then return false,"cannot open recording file" end
 local ftyp=scr().MakeMP4({},r.w,r.h,r.fps,true);r.file:Write(ftyp..u32(8).."mdat")
 r.offset,r.bytes=#ftyp,0;r.output=target(r.w,r.h)
 -- The encoding preset must NEVER decide the phone-display resolution.
 r.previewOutput50=target(366,648)
 return true
end
-- Prepare fallback render resources while the idle video camera is open.
-- One resource per PostRender; never starts a fake clip or extra RenderView.
local fallbackWarmKey50,fallbackWarmStep50=nil,0
hook.Add("PostRender","STTS_Recorder50FallbackWarm",function()
 local S=scr();local L=S and S.L
 if not L or L.rec or not L.raised or L.camMode~=1 then return end
 if useNative:GetInt()~=0 and (native or not checked)then return end
 local q=math.Clamp(luaQuality50:GetInt(),0,2)
 if fallbackWarmKey50~=q then fallbackWarmKey50,fallbackWarmStep50=q,0 end
 if fallbackWarmStep50>=4 then return end
 fallbackWarmStep50=fallbackWarmStep50+1
 if fallbackWarmStep50==1 then
  local w=q==0 and 128 or q==1 and 256 or 366
  local h=q==0 and 224 or q==1 and 448 or 648
  target(w,h)
 elseif fallbackWarmStep50==2 then target(366,648)
 elseif STTS.PhoneEIS and STTS.PhoneEIS.Warm49 then
  STTS.PhoneEIS.Warm49(366,648,fallbackWarmStep50==3 and 2 or 1,"record")
 end
end)
-- Prepare the actual native GPU/NVENC pipeline while the camera is idle.
-- No frames, MP4/proxy files, network requests or fake gallery items.
local prepareAt51,prepared51,prepareRate51=0,false,nil
hook.Add("PostRender","STTS_Recorder51Prepare",function()
 if not native or type(native.prepare51)~="function"or type(native.cancel_prepare51)~="function"then return end
 local S=scr();local L=S and S.L
 local G=STTS.PhoneGeo
 local camera=L and(not G or not G.APP_CAMERA or L.app==G.APP_CAMERA)
 local idle=useNative:GetInt()~=0 and L and camera and not L.rec and L.raised and L.camMode==1 and not R.retiring
 if not idle then
  if prepared51 then pcall(native.cancel_prepare51);prepared51=false end
  return
 end
 -- fix64: while the camera is ready the phone's ear reads the sound files ahead (background)
 if STTS.PhoneEar63 and STTS.PhoneEar63.Warm64 then STTS.PhoneEar63.Warm64(native)end
 local rate=math.Clamp(nativeRate:GetInt(),6,20)*1000000
 if prepared51 then
  if prepareRate51==rate then return end
  pcall(native.cancel_prepare51);prepared51=false;prepareAt51=RealTime()+.5;return
 end
 local now=RealTime();if now<prepareAt51 then return end;prepareAt51=now+.5
 local ok,yes=pcall(native.prepare51,720,1260,30,rate)
 if ok and yes then prepareRate51=rate end
 prepared51=ok and yes or false
end)
function R.Start(wep,front)
 local S=scr();local L=S.L
 if L.rec or S.Export then return end
 -- Registrations are already wrapped at InitPostEntity / registration time.
 -- Never scan every ULib/net callback from the record-button event.
 local diag=STTS.PhoneDiag47;if diag then diag.Reset();if diag.Begin49 then diag.Begin49()end end
 file.CreateDir("stts_phone_tmp")
 local now=RealTime()
 local r={modern=true,wep=wep,startAt=now,next=now,frames=0,pending=0,maxFrames=1800,
  eis=STTS.PhoneEIS.New(wep),base="stts_phone_tmp/camera_"..os.date("%Y%m%d_%H%M%S").."_"..tostring(math.floor(SysTime()*1000)%1000000)}
 r.eis.channel="record"
 -- fix68: filmed with the phone held landscape (T): the clip remembers how its picture is turned
 -- (the same turn as a landscape photo, SCR.LandVerts), the gallery shows it upright
 r.rot66=0
 if S.LandK and S.LandK(wep)>=0.5 and S.RecordPose31 then
  local pos,ang,fr=S.RecordPose31(wep)
  if pos then
   local _,cang=STTS.PhoneGeo.CamWorld(pos,ang,not fr,wep)
   r.rot66=(-ang:Right()):Dot(cang:Right())<0 and 90 or -90
  end
 end
 r.phone=wep.GetNWString and wep:GetNWString("STTS_Num","") or ""
 if STTS.PhoneGallery33 then STTS.PhoneGallery33.Close() end
 local m=probe()
 if m then
  applyFXAA64(m)
  local flags62=audioFlags62(m)
  local ok,started,why=pcall(m.start,r.base:match("[^/]+$")..".mp4",720,1260,30,math.Clamp(nativeRate:GetInt(),6,20)*1000000,flags62)
  if R.compat63 then hook.Remove("Think","ZPhoneFix63_Audio") end
  if ok and started then r.native=m;r.backend="native-h264-gpu-async";r.w,r.h,r.fps,r.maxFrames=720,1260,30,3600;r.filePath=r.base..".mp4";r.output=target(r.w,r.h)
   r.audio62=flags62>0
   -- fix63: the phone's ear listens from the first frame (sounds already playing are not heard)
   if bit.band(flags62,8)~=0 and STTS.PhoneEar63 then
    r.ear63=true;r.earMode63=earMode63(m)
    local okEar=pcall(STTS.PhoneEar63.Begin,r,m)
    if not okEar then r.ear63=false end
   end
  else R.nativeError="Native start failed: "..tostring(why or started);announce(R.nativeError) end
 end
 if not r.native then local ok,why=makeFallback(r);if not ok then announce(why) return end end
 L.rec=r;S.ActiveRecording=r
 -- One server transaction both validates the held phone and starts recording.
 -- Do not depend on a separate cam UI packet having set RecBy first.
 r.beginAt61=now
 if STTS.PhoneGallery33 then STTS.PhoneGallery33.Begin(r)else S.RecordAction31("cam","2")end

end
function R.Stop() local r=scr() and scr().L.rec;if r and r.modern then r.stop=true;r.userStopped=true end end
local function complete(r,why)
 earEnd63(r)
 local S=scr();r.closed=true
 S.LastRecording={frames=r.frames,fps=r.fps,seconds=math.max(0.001,RealTime()-r.startAt),uniqueFrames=r.frames,backend=r.backend,dropped=r.dropped or 0,maxCaptureMs=r.maxCaptureMs or 0,path=r.filePath,nativeStats=r.nativeStats}
 S.RecPreview,S.ActiveRecording=nil,nil
 if S.L.rec==r then S.L.rec=nil end
 R.lastError=why
 if not why and STTS.PhoneGallery33 then local ok,err=pcall(STTS.PhoneGallery33.Add,r);if not ok then R.lastError=tostring(err) end end
 if why and STTS.PhoneGallery33 then STTS.PhoneGallery33.Abort(r);STTS.PhoneGallery33.CleanupRecord(r)end
end
local function capture(r,t)
 if r.lastCapturedAt and t<=r.lastCapturedAt+0.001 then return end
 local began=SysTime()
 if r.native then
  r.firstImageAt=r.firstImageAt or t
  -- fix62: 2nd value = how old this image is (the stabilizer hands out older ones): the sound is
  -- lined up with the moment the picture was taken, not the moment it was handed over
  local ok,accepted,why=pcall(r.native.capture,math.max(0,t-r.firstImageAt),math.Clamp(RealTime()-t,0,5))
  if not ok then r.error=tostring(accepted);r.stop=true return end
  if accepted then
   local token=tonumber(why)
   if not token then r.error="Invalid native GPU ticket";r.stop=true return end
   gpuMarker(token)
  end
  if not accepted then r.dropped=(r.dropped or 0)+1;if why and why~="queue full" and why~="starting" then r.error=why;r.stop=true end;return end
 else
  local jpg=render.Capture({format="jpg",quality=r.jpegQuality50 or 62,x=0,y=0,w=r.w,h=r.h,alpha=false})
  if not jpg or #jpg==0 then r.error="JPEG capture failed";r.stop=true return end
  r.firstImageAt=r.firstImageAt or t
  local pts=math.floor((t-r.firstImageAt)*1000+0.5)
  if r.lastPts then r.durations[#r.durations]=math.max(1,pts-r.lastPts) end
  r.lastPts=pts
  r.sizes[#r.sizes+1]=#jpg;r.durations[#r.durations+1]=math.floor(1000/r.fps+0.5)
  r.gallerySamples[#r.gallerySamples+1]={t=pts/1000,offset=r.offset+8+r.bytes,size=#jpg}
  if not r.galleryThumb then r.galleryThumb=r.base..".thumb.jpg";file.Write(r.galleryThumb,jpg) end
  r.file:Write(jpg);r.bytes=r.bytes+#jpg
 end
 r.maxCaptureMs=math.max(r.maxCaptureMs or 0,(SysTime()-began)*1000)
 r.lastCapturedAt=t;r.frames=r.frames+1
end
local function blit50(r)
 surface.SetMaterial(r.previewOutput50.mat);surface.SetDrawColor(255,255,255,255)
 surface.DrawTexturedRect(0,0,r.w,r.h)
end
local function captureOutput50(r,t)
 if not r.previewOutput50 or r.previewOutput50==r.output then capture(r,t)return end
 -- Downsample the SAME completed stabilized image, no second world render.
 -- At quality 2 preview==output: never sample a texture into itself.
 render.PushRenderTarget(r.output.rt,0,0,r.w,r.h)
 render.Clear(0,0,0,255,false,false);cam.Start2D()
 local ok,why=pcall(blit50,r);cam.End2D()
 if ok then ok,why=pcall(capture,r,t)end
 render.PopRenderTarget()
 if not ok then error(why,0)end
end
local function finish(r)
 if r.finishing then return end
 r.finishing=true
 earEnd63(r)
 if r.native then r.native.finish();return end
 if r.frames==0 then r.file:Close();r.file=nil;file.Delete(r.filePath);complete(r,"No captured frames") return end
 local _,mdat,moov=scr().MakeMP4(r.sizes,r.w,r.h,r.fps,true,r.durations)
 r.file:Seek(r.offset);r.file:Write(mdat);r.file:Seek(r.offset+8+r.bytes);r.file:Write(moov);r.file:Close();r.file=nil
 if file.Size(r.filePath,"DATA")~=r.offset+8+r.bytes+#moov then complete(r,"Recording write failed") else complete(r,r.error) end
end
local function status49(r)
 local m=r.native
 if type(m.status49)~='function'then return m.poll()end
 local ready,done,why,pd,pt=m.status49()
 if done then return m.poll()end -- full terminal counters retained
 local p=r.status49 or{};r.status49=p;p.ready,p.done,p.error=ready,done,why or''
 p.processed,p.processTotal=tonumber(pd) or -1,tonumber(pt) or 0 -- fix70: H.264 conversion after a CPU clip
 return p
end
function R.Step(r)
 local S=scr();local L=S.L;local now=RealTime();S.ActiveRecording=r
 if r.finishing then
  audioKeep62(r)
  r.finishAt=r.finishAt or now
  if r.native and now-r.finishAt>60 then -- fix54: never "Already recording" forever
   pcall(r.native.cancel);R.retiring=r.native;R.retiringRecord=r;complete(r,r.procSeen70 and "Video conversion stalled" or "Native finish timed out");return
  end
  if r.native then local p=status49(r)
   -- fix70: a clip filmed without a GPU encoder is converted to H.264 now: progress on the phone,
   -- the timeout counts from the last converted frame (a long clip on a slow CPU takes a while)
   if not p.done and (p.processed or -1)>=0 then
    r.procSeen70=true
    if p.processed~=r.procLast70 then r.procLast70=p.processed;r.finishAt=now end
    if (r.procToastAt70 or 0)<=now then
     r.procToastAt70=now+0.5
     local pct=p.processTotal>0 and math.floor(math.Clamp(p.processed/p.processTotal,0,1)*100) or 0
     L.toast,L.toastAt="Processing video "..pct.."%",RealTime()
    end
   end
   if p.done then r.nativeStats=p;R.lastNativeStats63=p;r.requestedFrames=r.frames;r.frames=tonumber(p.encoded) or r.frames;r.dropped=tonumber(p.dropped) or r.dropped;complete(r,p.error~="" and p.error or r.error or (r.frames==0 and "No captured frames" or nil)) end end
  return
 end
 if r.native then
  local p=status49(r)
  local failed=p.error~="" and p.error or r.initFailure
  if failed and r.frames==0 and not r.stop then
   -- A worker publishes error before done: wait for cleanup, then retry in Lua.
   if not p.done then return end
   R.lastError=failed;R.nativeError="Native initialization failed: "..tostring(failed)
   earEnd63(r);r.native=nil;r.eis=STTS.PhoneEIS.New(r.wep);r.eis.channel="record"
   local ok,why=makeFallback(r);if not ok then complete(r,why) return end
   r.startAt=now;r.next=now
  elseif failed then r.error=failed;r.stop=true
  elseif not p.ready and not r.stop then
   if now-r.startAt>10 then r.initFailure="GPU encoder initialization timed out";r.native.cancel() end
   return
  end
 end
 local wep=r.wep
 -- fix54: picked up / put away = the inventory may recreate the phone entity; the server
 -- carries RecBy + RecAt over (weapon SetInfo): keep filming with the new entity
 if not IsValid(wep) and r.recAt and (r.findAt or 0)<=now then
  r.findAt=now+0.2
  for _,w in ipairs(ents.FindByClass("weapon_stts_phone"))do
   if w:GetNW2Entity("RecBy",NULL)==LocalPlayer() and w:GetNW2Int("CamMode",0)==2 and math.abs(w:GetNW2Float("RecAt",0)-r.recAt)<0.05 then r.wep=w;wep=w;break end
  end
 end
 if not IsValid(wep) then
  r.lostAt=r.lostAt or now
  if now-r.lostAt>3 then r.stop=true end
 else
  r.lostAt=nil
  if wep:GetNW2Int("CamMode",0)==2 and wep:GetNW2Entity("RecBy",NULL)==LocalPlayer() then r.seen=true;r.offAt61=nil;r.recAt=wep:GetNW2Float("RecAt",0)
  elseif r.seen then
   -- fix61: a short NW2 gap (the entity was recreated, PVS) is no stop any more: only 1.5 s
   -- of "not recording" in a row ends it (somebody pressed stop, the time is up)
   r.offAt61=r.offAt61 or now
   if now-r.offAt61>1.5 then r.stop=true end
  elseif r.permit==false then
   -- fix61: the server said no (it used to be: a few seconds of filming, then a stop and
   -- nothing saved). asked again with a new token twice, then the reason is shown
   local P=STTS.PhoneGallery33
   r.permitTries61=(r.permitTries61 or 0)+1
   if P and r.permitTries61<=2 and r.permitCode~=4 and r.permitCode~=5 then
    if r.token then P.pending[r.token]=nil end
    r.permit,r.permitAt,r.permitError,r.retryAt61=nil,nil,nil,now+0.4
   else
    r.stop=true;R.lastError=r.permitError
    L.toast,L.toastAt=r.permitCode==4 and "Somebody else is recording" or "Can't record video",RealTime()
   end
  elseif r.retryAt61 then
   if now>=r.retryAt61 then r.retryAt61=nil;r.beginAt61=now;STTS.PhoneGallery33.Begin(r)end
  -- fix61: the answer + the NW2 state get 8 s (was 4 s from the press, too short on a busy server)
  elseif now-(r.permitAt or r.beginAt61 or r.startAt)>(r.permitAt and 8 or 12) then r.stop=true end
 end
 local G=STTS.PhoneGeo
 if now-r.startAt>=((G and G.VidMaxSec) or 120) or r.frames>=r.maxFrames then r.stop=true end
 local pos,ang,front,zoom
 if IsValid(wep) then pos,ang,front,zoom=S.RecordPose31(wep) end
 audioStep62(r,pos)
 if pos then
  r.eis.mode=STTS.PhoneEIS.Mode(r.wep)
  local _,a=STTS.PhoneGeo.CamWorld(pos,ang,not front,wep)
  STTS.PhoneEIS.Sample(r.eis,a,now,tostring(wep:EntIndex())..":"..tostring(front))
 end
 if r.stop then
  if not r.stopSent then
   -- fix61: stopped while a new permit was about to be asked: ask now (before "recstop"),
   -- so these seconds are saved too
   if r.retryAt61 and r.frames>0 and STTS.PhoneGallery33 then r.retryAt61=nil;STTS.PhoneGallery33.Begin(r)end
   S.RecordAction31("recstop");r.stopSent=true;r.stopAt=now;S.RecPreview=nil
   -- fix54: "cam" acts on the phone in the HAND: only when that is the recorded one (it was
   -- switching / stopping somebody else's recording on the phone you picked up meanwhile)
   local lp=LocalPlayer()
   if IsValid(wep) and IsValid(lp) and lp:GetActiveWeapon()==wep then L.camMode=1;S.RecordAction31("cam","1") end
  end
  -- fix54: a drain that never ends (no delayed image comes back) does not hold the recorder
  if now-(r.stopAt or now)>6 then finish(r) return end
  -- Drain at most ONE delayed image per game frame. No more world renders.
  local output=r.previewOutput50 or r.output
  local w,h=r.previewOutput50 and 366 or r.w,r.previewOutput50 and 648 or r.h
  render.PushRenderTarget(output.rt)
  local more=STTS.PhoneEIS.Drain(r.eis,w,h)
  if more then captureOutput50(r,r.eis.outputAt)end
  render.PopRenderTarget()
  if not more then
   if STTS.PhoneGallery33 and STTS.PhoneGallery33.GPUThumb48 then STTS.PhoneGallery33.GPUThumb48(r)end
   finish(r)
  end
  return
 end
 -- Integer capture slots: floating-point boundary rounding used to put
 -- r.next back on the CURRENT boundary and render an extra scene next frame.
 -- Skip missed slots; never catch up by rendering multiple frames/bursts.
 local tick51=math.floor((now-r.startAt)*r.fps+1e-6)
 if tick51<0 or(r.captureTick51 and tick51<=r.captureTick51)then return end
 r.captureTick51=tick51;r.next=r.startAt+(tick51+1)/r.fps
 if pos then
  local output=r.previewOutput50 or r.output
  local w,h=r.previewOutput50 and 366 or r.w,r.previewOutput50 and 648 or r.h
  local cpos,t,warming=S.RenderCam(output.rt,w,h,pos,ang,not front,nil,zoom,wep,r.eis)
  S.RecordRenderedFrame=FrameNumber()
  if not warming then captureOutput50(r,t)end
  render.PopRenderTarget()
  S.Cams[wep:EntIndex()*2+(not front and 1 or 0)]={pos=cpos,t=now}
 else
  -- A pocket is black, not a frozen view of the previous room.
  local output=r.previewOutput50 or r.output
  render.PushRenderTarget(output.rt);render.Clear(0,0,0,255,true,true)
  captureOutput50(r,now);render.PopRenderTarget()
 end
 S.RecPreview={idx=IsValid(wep) and wep:EntIndex() or -1,back=not front,mat=(r.previewOutput50 or r.output).mat}
end
function R.Cancel()
 local S=scr();local r=S and S.L.rec
 if not r or not r.modern then return end
 if r.native then pcall(r.native.cancel);R.retiring=r.native;R.retiringRecord=r end
 if r.file then r.file:Close();r.file=nil;file.Delete(r.filePath) end
 if STTS.PhoneGallery33 then STTS.PhoneGallery33.Abort(r)end
 if r.galleryThumb then file.Delete(r.galleryThumb) end
 if not r.native and STTS.PhoneGallery33 then STTS.PhoneGallery33.CleanupRecord(r)end
 S.L.rec=nil;S.RecPreview=nil;S.ActiveRecording=nil
end
hook.Add("PostRender","STTS_Recorder33Retire",function()
 if R.retiring then local ok,p=pcall(R.retiring.poll);if not ok or p.done then if STTS.PhoneGallery33 then STTS.PhoneGallery33.CleanupRecord(R.retiringRecord)end;R.retiring,R.retiringRecord=nil,nil end end
end)
concommand.Add("zhphone_rec_stats",function()
 print("[ZPHONE] Client fix73 / native setting="..useNative:GetInt())
 if native and type(native.fxaa)=="function" then local ok,mode=pcall(native.fxaa);print("[ZPHONE] Video FXAA: "..(({[0]="off","quality","strong"})[ok and tonumber(mode) or -1] or "?").." (zhphone_fxaa "..fxaa64:GetInt()..")")
 else print("[ZPHONE] Video FXAA: needs native module fix64") end
 if native and type(native.encoder)=="function" then local ok,pref,name=pcall(native.encoder);print("[ZPHONE] Video encoder: "..((ok and name and name~="") and name or "not opened yet").." (zhphone_encoder "..R.Enc68:GetInt()..", "..tostring(native.bits or "?").."-bit module)")
 elseif native then print("[ZPHONE] Video encoder: NVENC only (native module before fix69)") end
 if native and (tonumber(native.encoder_api) or 0)<2 then print("[ZPHONE] No-GPU-encoder path (CPU MJPEG -> H.264): needs the fix70 DLL") end
 if native and (tonumber(native.line_api) or 0)<1 then print("[ZPHONE] Game sounds of phone calls: need the fix73 DLL") elseif native then print("[ZPHONE] Game sounds of phone calls: native line ready (zhphone_line_stats)") end
 if STTS.PhoneDiag47 then STTS.PhoneDiag47.Report()end

 local view=STTS.PhoneView43 and STTS.PhoneView43.last
 if view then print("[ZPHONE] Phone view: "..view.stage.." / hooks="..view.events.." rejected="..view.rejected.." / RT="..view.active.." -> "..view.target)end
 if R.nativeError then print("[ZPHONE] Native unavailable: "..R.nativeError)elseif R.nativeBuild then print("[ZPHONE] Native module: "..R.nativeBuild)end
 if R.lastError then print("[ZPHONE] "..R.lastError) end
 do -- fix62: the clip sound
  local m=native;local flags=audioFlags62(m)
  print(string.format("[ZPHONE] Clip sound: %s (mic mode %d, game mode %d, you talk now: %s)",flags>0 and "on" or((m and (tonumber(m.audio_api)or 0)>=1)and "off by setting" or "needs native module fix62"),audioMic62:GetInt(),audioGame62:GetInt(),tostring(talking62())))
  local em=earMode63(m)
  local names={[0]="at your head (what you hear)","at the phone + what you hear while it is near you","only at the phone"}
  if m and (tonumber(m.ear_api) or 0)>=1 then print("[ZPHONE] Phone ear: "..(names[em] or "?").." (zhphone_audio_ear "..audioEar63:GetInt()..")")
  else print("[ZPHONE] Phone ear: needs native module fix63 (the game is heard at your head)")end
  local ns=R.lastNativeStats63
  if ns and ns.earPlayed then print(string.format("[ZPHONE] Last clip ear: %d sounds played, peak %.2f, %d files ready, %d unusable, %.1f MB",tonumber(ns.earPlayed)or 0,tonumber(ns.earPeak)or 0,tonumber(ns.earFiles)or 0,tonumber(ns.earBadFiles)or 0,tonumber(ns.earMB)or 0))end
 end
 local P=STTS.PhoneGallery33
 if P and P.upload then
  local u=P.upload;local total=math.max(1,u.totalBytes or 1);local ack=u.ackedBytes or 0
  local speed=ack/math.max(.001,RealTime()-(u.transferAt or RealTime()))/1048576
  print(string.format("[ZPHONE] Upload: %.1f%% (%.1f/%.1f MiB ACK), %.2f MiB/s, target=%.1f, window=%d/4, phase=%s",100*ack/total,ack/1048576,total/1048576,speed,(u.rate or 0)/1048576,u.inflightCount or 0,tostring(u.phase)))
 end
 if P and #P.queue>0 then local q=P.queue[1];print(string.format("[ZPHONE] Queued: %d / preview %d/%d",#P.queue,q.buildIndex or 0,q.proxyIndex and #q.proxyIndex or 0))end
 if P and P.lastError then print("[ZPHONE] Media: "..P.lastError)end
 if P then for _,v in pairs(P.failed or{})do print("[ZPHONE] Temporary recording: "..tostring(v.filePath).." / "..tostring(v.mediaError))end end
 local S=scr();local r=S and (S.L.rec or S.LastRecording)
 if not r then print("[ZPHONE] No recording") return end
 local p=r.native and r.native.poll() or r.nativeStats
 local frames=p and tonumber(p.encoded) or r.frames or 0
 local dropped=p and tonumber(p.dropped) or r.dropped or 0
 local sec=r.seconds or math.max(0.001,RealTime()-(r.startAt or RealTime()))
 print(string.format("[ZPHONE] %s target=%d unique=%.1f/s frames=%d dropped=%d maxCapture=%.2fms",r.backend or "legacy",r.fps or 15,frames/sec,frames,dropped,r.maxCaptureMs or 0))
 if p then PrintTable(p) end
end)
concommand.Add("zhphone_recordings",function()end)

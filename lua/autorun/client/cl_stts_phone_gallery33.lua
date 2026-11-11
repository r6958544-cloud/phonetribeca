-- Round-scoped phone media cache, with authorized per-phone predicted entries.
-- No independent PC-local gallery and no automatic permanent export.
STTS=STTS or {}
local P={items={},byID={},pending={},queue={},incoming={},failed={},predicted={},nextLocal=0};STTS.PhoneGallery33=P
local CHUNK=48000
local WINDOW=4 -- bounded: at most 192000 payload bytes unacknowledged
local uploadRate=CreateClientConVar('zhphone_upload_kbps','8192',true,false,'Phone upload target in KiB/s; negotiated with server',256,10240)
local function S()return STTS.PhoneScreen end
local function round()return GetGlobalInt('STTS_PhotoRound',1)end
local function root()return 'stts_phone/r'..round()end
local function base(id)return root()..'/v'..id end
local function nativeBusy()local s=S();return s and s.L and s.L.rec end
local function err(s)P.lastError=s end
local function isCurrent(n)return n==round()end
P.transfers44={}
net.Receive('stts_p44_progress',function()
 local n,num,peer,id=net.ReadUInt(32),net.ReadString(),net.ReadString(),net.ReadUInt(32)
 local got,total,state=net.ReadUInt(32),net.ReadUInt(32),net.ReadUInt(2)
 if not isCurrent(n)or #num>64 or #peer>64 or total>512*1024*1024 or got>total then return end
 local box=P.transfers44[num]or{};P.transfers44[num]=box
 local th=box[peer]or{};box[peer]=th
 local now=RealTime();local old=th[id];local speed
 if old and old.total==total and got>old.got and now>old.at then
  local instant=(got-old.got)/(now-old.at);speed=old.speed and(old.speed*.5+instant*.5)or instant
 elseif old and old.total==total and got>=old.got then speed=old.speed end
 th[id]={got=got,total=total,state=state,at=now,speed=speed}
end)
function P.DownloadDone44(id,ok)
 if util.NetworkStringToID and util.NetworkStringToID('stts_p44_done')==0 then return end
 net.Start('stts_p44_done');net.WriteUInt(round(),32);net.WriteUInt(id,32);net.WriteBool(ok==true);net.SendToServer()
end
function P.ChatPending44(num,peer)
 local list={}
 for _,r in pairs(P.predicted)do
  if not r.deleted and r.round==round()and r.phone==num then
   for _,to in ipairs(r.sharePeers or{})do if to==peer then
    list[#list+1]={me=true,text='',t=r.shareTime44 or 0,media=r.localID,pending44=true}
   end end
  end
 end
 table.sort(list,function(a,b)return a.media>b.media end)
 return list
end
-- fix61: what a clip on its way to TeleChat is doing: text, real fraction (nil = no number
-- exists yet), failed. the fraction is acknowledged bytes / all bytes of the upload
function P.SendState61(r)
 if not r then return 'Отправка' end
 if r.mediaError then return 'Не отправлено',nil,true end
 if r.id then return 'Отправка',1 end -- on the server: only the message itself is left
 if P.upload==r and(r.totalBytes or 0)>0 then return 'Отправка',math.min(.99,(r.ackedBytes or 0)/r.totalBytes)end
 if r.buildIndex and r.proxyIndex and #r.proxyIndex>0 and r.buildIndex<=#r.proxyIndex then return 'Подготовка',(r.buildIndex-1)/#r.proxyIndex end
 if not r.finished then return 'Запись' end
 if r.permit==nil then return 'Ожидание сервера' end
 return 'В очереди'
end
local function progress47(text,got,total,at,speed)
 local remaining=math.max(0,total-got);local eta=speed and speed>0 and math.ceil(remaining/speed)or nil
 local stale=at and RealTime()-at>1.5
 local detail=total>0 and(remaining>=1048576 and string.format('%.1f МБ',remaining/1048576)or(math.ceil(remaining/1024)..' КБ'))or nil
 if detail and eta and not stale and remaining>0 then detail=detail..' · ~'..eta..' с'end
 if stale and remaining>0 then detail=(detail or'')..' · пауза'end
 if total>0 and remaining==0 then text='Проверка';detail=nil end
 return {text=text,p=total>0 and math.min(.99,got/total)or 0,detail=detail,remaining=remaining,eta=not stale and eta or nil,indeterminate=total<=0}
end
function P.Transfer44(id,num,peer,me)
 local item=P.byID[id];local r=item and item.record
 if id<0 and r then
  if r.mediaError then return {text='Не отправлено',failed=true,p=0}end
  if r.totalBytes then
   local got=r.ackedBytes or 0;return progress47('Отправка',got,r.totalBytes,nil,got/math.max(.001,RealTime()-(r.transferAt or RealTime())))
  end
  return {text='Подготовка',p=0,indeterminate=true}
 end
 local box=P.transfers44[num];local th=box and box[peer];local remote=th and th[id]
 if me then
  if remote and remote.state~=2 then
   if remote.state==3 then return {text='Не загружено',failed=true,p=0}end
   if remote.state==0 then return {text='Ожидание получателя',p=0,indeterminate=true}end
   return progress47('Получает',remote.got,remote.total,remote.at,remote.speed)
  end
  return
 end
 -- A separate manual original download does not block an already playable preview.
 if item and item.playable48 then return end
 local j=P.incoming[id]
 if j then
  local total=j.sizes[1]+j.sizes[3]+(j.full and j.sizes[2]or 0)
  local got=j.received[1]+j.received[2]+j.received[3]
  return progress47('Загрузка',got,total,j.at,got/math.max(.001,RealTime()-(j.started47 or j.at)))
 end
 local screen=S();local photo=screen and screen.MediaDownload44 and screen.MediaDownload44(id)
 if photo and photo.ready then return end
 if photo and photo.total then return {text='Загрузка',p=math.min(.99,photo.got/math.max(1,photo.total))}end
 if remote and remote.state==3 then return {text='Не загружено',failed=true,p=0}end
 return {text='Загрузка',p=0,indeterminate=true}
end
local function removeTree(dir,except)
 local fs,ds=file.Find(dir..'/*','DATA')
 for _,f in ipairs(fs or{})do local path=dir..'/'..f;if not except or path:sub(1,#except)~=except then file.Delete(path)end end
 for _,d in ipairs(ds or{})do local path=dir..'/'..d;if not except or path:sub(1,#except)~=except then removeTree(path);file.Delete(path)end end
end
function P.CleanupRecord(r)
 if not r or not r.base or not r.base:match('^stts_phone_tmp/camera_[%w_%-]+$')then return end
 file.Delete(r.base..'.mp4');file.Delete(r.base..'.mp4.dat');file.Delete(r.base..'.mp4.partial');file.Delete(r.base..'.thumb.jpg');file.Delete(r.base..'.proxy.bin');file.Delete(r.base..'.proxy.dat')
 file.Delete(r.base..'.wav');file.Delete(r.base..'.wav.partial') -- fix62: the clip sound
 removeTree(r.base..'.proxy');file.Delete(r.base..'.proxy')
end
function P.Begin(r)
 r.round=round();repeat r.token=math.random(1,65535)until not P.pending[r.token]
 P.pending[r.token]=r
 if util.NetworkStringToID and util.NetworkStringToID('stts_p37_record')==0 then r.permit=false;r.permitError='Server phone recording protocol missing; install full fix39 on server';err(r.permitError);return end
 net.Start('stts_p37_record');net.WriteUInt(r.round,32);net.WriteUInt(r.token,16);net.WriteEntity(r.wep);net.SendToServer()
end
net.Receive('stts_p37_permit',function()
 local n,t,v=net.ReadUInt(32),net.ReadUInt(16),net.ReadUInt(32);local r=P.pending[t]
 if isCurrent(n)and r then
  r.permit=v==1;r.permitAt=RealTime();r.permitCode=v
  if not r.permit then
   local reasons={[0]='Server rejected recording ownership (old server)',[2]='Recording round/token mismatch',[3]='Recording phone is not the server-held active phone',[4]='Phone is already recording for another player',[5]='Phone has no server number',[6]='Too many pending recordings or duplicate token'}
   r.permitError=reasons[v]or('Recording authorization error '..v);err(r.permitError)
  end
 end
end)
local cleanup48={}
local function cleanupStep48()
 local j=cleanup48[1];if not j then return end
 local clock=SysTime or RealTime;local at=clock()
 for _=1,2 do
  local entry=j.entries[j.at];if not entry then file.Delete(j.dir);table.remove(cleanup48,1);return end
  file.Delete(j.dir..'/'..entry.name);j.at=j.at+1
  if clock()-at>.001 then return end
 end
end
local failUpload
local predict,flushShares
function P.Add(r)
 if not r or r.round~=round()or not r.token or not r.filePath then return end
 r.finished=true;r.meta={version=37,native=r.native~=nil,w=r.w,h=r.h,fps=r.fps,frames=r.frames,duration=math.min(125,math.max(.001,(r.lastCapturedAt or r.startAt)-(r.firstImageAt or r.startAt)+1/r.fps)),samples={},rot=(r.rot66==90 or r.rot66==-90)and r.rot66 or nil}
 if r.native then
  r.proxyIndex={};for pts,name in(file.Read(r.base..'.proxy/index.txt','DATA')or''):gmatch('(%d+) ([%d]+%.jpg)')do r.proxyIndex[#r.proxyIndex+1]={t=tonumber(pts)/90000,name=name}end
  r.buildIndex=1;r.proxyBytes=0;r.proxyPath=r.base..'.proxy.dat'
  -- fix62: the native module wrote the clip sound next to the MP4 (24 kHz WAV, exactly the clip length)
  local st=r.nativeStats;local wav=r.base..'.wav'
  if st and st.audioWav==true and file.Exists(wav,'DATA')and(file.Size(wav,'DATA')or 0)>44 then r.audioPath62=wav end
  local f=file.Open(r.proxyPath,'wb','DATA')
  if not f then return failUpload(r,'Cannot create native preview cache')end
  f:Close()
  if file.Size(r.proxyPath,'DATA')~=0 then return failUpload(r,'Cannot initialize native preview cache')end
 else
  for _,v in ipairs(r.gallerySamples or{})do r.meta.samples[#r.meta.samples+1]={t=v.t,offset=v.offset,size=v.size}end
 end
 P.queue[#P.queue+1]=r
 predict(r)
end
function P.Abort(r)
 if not r then return end
 if r.round==round()and r.token and(not util.NetworkStringToID or util.NetworkStringToID('stts_p37_abort')~=0)then net.Start('stts_p37_abort');net.WriteUInt(r.round,32);net.WriteUInt(r.token,16);net.SendToServer()end
 if r.token then P.pending[r.token]=nil end
 for i=#P.queue,1,-1 do if P.queue[i]==r then table.remove(P.queue,i)end end
 if r.handle then r.handle:Close();r.handle=nil end
 if r.proxyHandle48 then r.proxyHandle48:Close();r.proxyHandle48=nil end
 if P.upload==r then P.upload=nil end
end
failUpload=function(r,why)
 P.Abort(r)
 -- A transfer failure must never destroy the finished recording.
 -- Keep it ONLY in this round's temporary cache, not in a PC-local gallery.
 r.mediaError=why
 if r.round==round()then P.failed[r.base or r.token]=r else P.CleanupRecord(r)end
 err(why)
end
local function cache(id,r)
 local item={id=id,path=r.filePath,proxyPath=r.proxyPath,meta=r.meta,samples=r.meta.samples,duration=r.meta.duration,w=r.w,h=r.h,full=true,base=r.base,record=r,playable48=true}
 item.samplePath=item.meta.native and item.proxyPath or item.path
 P.byID[id]=item
end
-- Negative IDs are temporary views of this round's authorized PHONE recording.
-- They are never written into NW vars or sent through an unsigned network field.
local function phoneMatches(r,st,wep)
 if r.round~=round() or not st.own then return false end
 if IsValid(r.wep) and r.wep.GetNWString then
  local num=r.wep:GetNWString('STTS_Num','');if num~='' then r.phone=num end
 end
 if r.phone and r.phone~='' then return st.num==r.phone end
 return wep~=nil and wep==r.wep
end
predict=function(r)
 if r.localID or r.deleted or not r.finished or r.permit~=true then return end
 local samples={}
 if r.meta.native then
  for _,v in ipairs(r.proxyIndex or{})do
   samples[#samples+1]={t=v.t,offset=0,path=r.base..'.proxy/'..v.name}
  end
 else
  for _,v in ipairs(r.meta.samples)do samples[#samples+1]={t=v.t,offset=v.offset,size=v.size}end
 end
 if #samples==0 then return end
 if IsValid(r.wep) and r.wep.GetNWString then local n=r.wep:GetNWString('STTS_Num','');if n~=''then r.phone=n end end
 P.nextLocal=P.nextLocal-1;r.localID=P.nextLocal
 local m={native=r.meta.native,samples=samples,duration=r.meta.duration,w=r.w,h=r.h,fps=r.fps,rot=r.meta.rot}
 P.byID[r.localID]={id=r.localID,path=r.filePath,proxyPath=r.proxyPath,meta=m,samples=samples,duration=m.duration,w=r.w,h=r.h,full=true,base=r.base,record=r,samplePath=r.filePath,predicted=true,playable48=true}
 P.predicted[r.localID]=r
end
function P.ChatActivity()
 local G=STTS.PhoneGeo or{};P.sendAfter=RealTime()+math.max(.7,(G.ChatCooldown or .6)+.1)
end
flushShares=function(r)
 if not r.id or not r.sharePeers or #r.sharePeers==0 then return end
 -- fix61: handed to the screen's send queue (sent again until the server echoes it back);
 -- the pending bubble stays until then instead of vanishing on a dropped packet
 local s=S()
 if s and s.ShareOut and r.phone and r.phone~=''then
  r.shareQ61=r.shareQ61 or{}
  for i=#r.sharePeers,1,-1 do
   local peer=r.sharePeers[i]
   if not r.shareQ61[peer]then r.shareQ61[peer]=true;s.ShareOut(r.phone,peer,r.id)
   elseif not s.ShareQueued(r.phone,peer,r.id)then table.remove(r.sharePeers,i);r.shareQ61[peer]=nil end
  end
  return
 end
 if RealTime()<(P.sendAfter or 0)then return end
 local ply=LocalPlayer();local wep=IsValid(ply) and ply.GetActiveWeapon and ply:GetActiveWeapon()
 if not IsValid(wep) or not wep.GetNWString or wep:GetNWString('STTS_Num','')~=r.phone then return end
 if S() and S().PlaneBlocked and S().PlaneBlocked()then return end
 -- One queued attachment per Think; server retains its normal chat permissions/rate limit.
 local peer=table.remove(r.sharePeers,1);P.ChatActivity()
 net.Start('stts_tc_send');net.WriteString(peer);net.WriteString('');net.WriteUInt(r.id,32);net.SendToServer()
end
function P.QueueShare(id,peer)
 local item=P.byID[id];local r=item and item.record
 if id>=0 or not r or r.deleted or r.round~=round() or type(peer)~='string' or peer=='' then return false end
 local ply=LocalPlayer();local w=IsValid(ply) and ply.GetActiveWeapon and ply:GetActiveWeapon()
 if not IsValid(w) or not w.GetNWString or not phoneMatches(r,{own=true,num=w:GetNWString('STTS_Num','')},w)then return false end
 r.sharePeers=r.sharePeers or{}
 for _,v in ipairs(r.sharePeers)do if v==peer then return true end end
 if #r.sharePeers>=8 then return false end
 r.sharePeers[#r.sharePeers+1]=peer;r.shareTime44=r.shareTime44 or os.time();return true
end
local function startUpload(r)
 if #r.meta.samples==0 then return failUpload(r,'No video preview samples produced')end
 r.metaData=util.Compress(util.TableToJSON(r.meta)or'');if not r.metaData then return failUpload(r,'Cannot serialize video metadata')end
 r.sizes={#r.metaData,file.Size(r.filePath,'DATA'),r.proxyBytes or 0}
 if r.sizes[2]<16 or r.sizes[2]>256*1024*1024 or r.sizes[1]>524288 then return failUpload(r,'Invalid recording size')end
 if r.meta.native and(r.sizes[3]<1 or r.sizes[3]>64*1024*1024 or file.Size(r.proxyPath,'DATA')~=r.sizes[3])then return failUpload(r,'Incomplete native preview cache')end
 r.stream,r.index,r.offset=1,1,0;r.phase='begin';r.waitAt=RealTime();r.inflight={};r.inflightCount=0;r.ackedBytes=0;r.totalBytes=r.sizes[1]+r.sizes[2]+r.sizes[3];P.upload=r
 net.Start('stts_p37_begin');net.WriteUInt(r.round,32);net.WriteUInt(r.token,16);for k=1,3 do net.WriteUInt(r.sizes[k],32)end;net.SendToServer()
end
net.Receive('stts_p37_ready',function()
 local n,t,v=net.ReadUInt(32),net.ReadUInt(16),net.ReadUInt(32);local r=P.upload
 if not isCurrent(n)or not r or r.token~=t then return end
 if v==0 then return failUpload(r,'Phone media upload rejected (capacity or ownership)')end
 -- v=1 is the old server handshake: keep that server below its old media quota.
 r.rate=math.min(math.Clamp(uploadRate:GetInt(),256,10240),v>1 and v or 1024)*1024
 r.phase='send';r.transferAt=r.transferAt or RealTime();r.txAt=RealTime();r.txBytes=CHUNK*WINDOW;r.waitAt=RealTime()
end)
net.Receive('stts_p37_flow',function()
 local n,t,v=net.ReadUInt(32),net.ReadUInt(16),net.ReadUInt(32);local r=P.upload
 if isCurrent(n)and r and r.token==t and r.inflight and r.inflight[v]then
  r.ackedBytes=(r.ackedBytes or 0)+r.inflight[v];r.inflight[v]=nil;r.inflightCount=r.inflightCount-1
  r.waiting=r.inflightCount>0 and r.inflightCount or nil;r.waitAt=RealTime()
 end
end)
net.Receive('stts_p37_commit',function()
 local n,t,id=net.ReadUInt(32),net.ReadUInt(16),net.ReadUInt(32);local r=P.upload
 if not isCurrent(n)or not r or r.token~=t then return end
 if id==0 then return failUpload(r,'Server rejected video payload')end
 if r.handle then r.handle:Close();r.handle=nil end
 r.id=id;cache(id,r)
 local s=S();if s and s.M49 and s.M49.QueuePrev then s.M49.QueuePrev(id,function()return P.Thumb(id)end,r.w or(r.meta and r.meta.w),r.h or(r.meta and r.meta.h))end -- fix53: tiny preview for receivers
 if r.localID then P.byID[r.localID]=P.byID[id] end
 P.pending[t]=nil;P.upload=nil;P.lastError=nil;r.mediaError=nil;P.failed[r.base or r.token]=nil
 if r.meta.native then
  file.Delete(r.base..'.proxy/index.txt')
  cleanup48[#cleanup48+1]={dir=r.base..'.proxy',entries=r.proxyIndex or{},at=1}
 end
end)
local requests={};local saveJobs={};local wantSave={};local panel,lastID,lastFrame,material,lastUse
local stopAudio62
local function close()
 if IsValid(panel)then panel:Remove()end;panel,lastID,lastFrame,material=nil,nil,nil,nil
 if stopAudio62 then stopAudio62()end
end
function P.Close()close()end
-- fix54: st.photos is the parse cache of the NW2 string, SHARED by every phone with the
-- same list (two empty galleries = one table). appending in place put this phone's clips
-- into the other phones' galleries: copy before adding
function P.Merge(st,wep)
 local base=st.photos or{};local seen={};for _,id in ipairs(base)do seen[id]=true end
 local ordered={};for _,r in pairs(P.predicted)do if not r.deleted and phoneMatches(r,st,wep)then ordered[#ordered+1]=r end end
 table.sort(ordered,function(a,b)return a.localID>b.localID end)
 local out
 for _,r in ipairs(ordered)do
  local id=r.id or r.localID
  if r.id and seen[id]then P.predicted[r.localID]=nil
  elseif not seen[id]then
   if not out then out={};for i,v in ipairs(base)do out[i]=v end end
   out[#out+1]=id;seen[id]=true
  end
 end
 st.photos=out or base
end
function P.IsBlob(id,st)return id and id~=0 and((st and st.blobs and st.blobs[id])or P.byID[id]~=nil)end
function P.Get(id)return P.byID[id]end
function P.Request(id,full)
 if not id or id<=0 or nativeBusy()then return end
 -- fix53: received media is downloaded only on tap (cl_phone_screen.lua, SCR.M49)
 local s=S();if not full and s and s.M49 and s.M49.Locked(id)then return end
 local key=id..':'..tostring(full==true)
 if(requests[key]or 0)>RealTime()or P.incoming[id]then return end
 requests[key]=RealTime()+6
 -- fix66: the preview pictures (proxy) of this clip are already here: the full download is only the MP4
 local old=P.byID[id];local have=full==true and old and old.meta and old.meta.version==37 and old.proxyPath and file.Size(old.proxyPath,'DATA')>0 and true or false
 net.Start('stts_p37_get');net.WriteUInt(round(),32);net.WriteUInt(id,32);net.WriteBool(full==true);net.WriteBool(have);net.SendToServer()
end
local function closeIncoming(j)
 for _,f in pairs(j.handles or{})do f:Close()end;j.handles={}
end
-- fix53: soft = only forget the request throttle (a new tap asks at once), else drop the preview download too
function P.Cancel49(id,soft)
 requests[id..':false']=nil
 if soft then return end
 local j=P.incoming[id];if j and not j.full then closeIncoming(j);P.incoming[id]=nil end
end
-- fix53: tap on an outgoing clip bubble = do not send it to this chat (it stays in Photos)
function P.CancelShare49(localID,peer)
 local item=P.byID[localID];local r=(item and item.record)or P.predicted[localID]
 if not r or not r.sharePeers then return false end
 for k=#r.sharePeers,1,-1 do if r.sharePeers[k]==peer then table.remove(r.sharePeers,k)end end
 local s=S();if r.id and r.phone and s and s.ShareCancel then s.ShareCancel(r.phone,peer,r.id)end
 if r.shareQ61 then r.shareQ61[peer]=nil end
 return true
end
net.Receive('stts_p37_info',function()
 local n,id=net.ReadUInt(32),net.ReadUInt(32);local sizes={net.ReadUInt(32),net.ReadUInt(32),net.ReadUInt(32)};local full=net.ReadBool();local skip3=net.ReadBool() -- fix66: proxy not sent again
 if not isCurrent(n)or sizes[1]>524288 or sizes[2]>256*1024*1024 or sizes[3]>64*1024*1024 then return end
 local s=S();if not full and s and s.M49 and s.M49.Blocked(id)then return end -- fix53: cancelled meanwhile
 local old=P.byID[id]
 if old and old.meta and old.meta.version==37 and(not full or old.full)
  and(not full or file.Size(old.path,'DATA')==sizes[2])
  and(sizes[3]==0 or file.Size(old.proxyPath,'DATA')==sizes[3])
  and(not util.NetworkStringToID or util.NetworkStringToID('stts_p44_have')~=0)then
  net.Start('stts_p44_have');net.WriteUInt(n,32);net.WriteUInt(id,32);net.SendToServer();return
 end
 if P.incoming[id]then closeIncoming(P.incoming[id])end
 file.CreateDir(root());local j={id=id,sizes=sizes,full=full,parts={},received={0,0,0},handles={},at=RealTime(),started47=RealTime(),paths={[2]=base(id)..'.mp4.dat',[3]=base(id)..'.proxy.dat'}}
 if skip3 then
  if not(old and old.proxyPath and file.Size(old.proxyPath,'DATA')==sizes[3])then return end -- cannot happen: asked with the proxy here
  j.received[3]=sizes[3];j.paths[3]=old.proxyPath
 end
 P.incoming[id]=j
end)
net.Receive('stts_p37_data',function()
 local n,id,k,index,size=net.ReadUInt(32),net.ReadUInt(32),net.ReadUInt(2),net.ReadUInt(16),net.ReadUInt(16)
 if not isCurrent(n)then return end
 local j=P.incoming[id];if not j or k<1 or k>3 or size<1 or size>CHUNK then return end
 if index~=math.floor(j.received[k]/CHUNK)+1 or size~=math.min(CHUNK,j.sizes[k]-j.received[k])then closeIncoming(j);P.incoming[id]=nil;return end
 local data=net.ReadData(size);if type(data)~='string'or #data~=size then return end
 if k==1 then j.parts[#j.parts+1]=data else
  if not j.handles[k]then j.handles[k]=file.Open(j.paths[k],'wb','DATA')end
  if not j.handles[k]then closeIncoming(j);P.incoming[id]=nil;err('Cannot open temporary cache')return end
  j.handles[k]:Write(data)
 end
 j.received[k]=j.received[k]+size;j.at=RealTime()
 net.Start('stts_p37_got');net.WriteUInt(n,32);net.WriteUInt(id,32);net.WriteUInt(k,2);net.WriteUInt(index,16);net.SendToServer()
end)
local saveSerial=0
-- fix68: Save tells what happens (it was silent: an error only went into P.lastError)
local function say68(text,console)
 local s=S();if s and s.L then s.L.toast,s.L.toastAt=text,RealTime()end
 if console then MsgC(Color(255,180,80),'[ZPHONE] ',color_white,console..'\n')end
end
P.Say68=say68
local function saveDone(j,why)
 if j.input then j.input:Close();j.input=nil end
 if j.output then j.output:Close();j.output=nil end
 if j.temp then file.Delete(j.temp)end
 if why then say68("Can't save video",'video not saved: '..tostring(why))
 elseif j.dest then say68('Saved to PC','video saved: garrysmod/data/'..j.dest..(j.dest:sub(-4)=='.dat' and '  (rename .mp4.dat -> .mp4; a real .mp4 needs the zhphone DLL fix67+ and zhphone_native 1)' or ''))end
 if why then err(why)else P.lastSaved=j.dest end
 P.saveProgress46=nil;table.remove(saveJobs,1)
end
local function beginSave(id,item)
 -- The recorder's original stays local after commit. Never download it again
 -- merely because the gallery is still uploading/proxy-building another clip.
 if not item.full or not item.path or file.Size(item.path,'DATA')<12 then
  if not wantSave[id]then say68('Downloading video...','saving video '..tostring(id)..': downloading the original MP4 first')end
  wantSave[id]=true;P.Request(id,true)return
 end
 for _,j in ipairs(saveJobs)do if j.source==item.path then return end end
 if #saveJobs>=8 then return err('Export queue full')end
 saveSerial=saveSerial+1
 local name='video_'..os.date('%Y%m%d_%H%M%S')..'_'..tostring(id):gsub('-','n')..'_'..saveSerial..'.mp4'
 while file.Exists('zhunter_saved/'..name,'DATA')or file.Exists('zhunter_saved/'..name..'.dat','DATA')do
  saveSerial=saveSerial+1;name='video_'..os.date('%Y%m%d_%H%M%S')..'_'..tostring(id):gsub('-','n')..'_'..saveSerial..'.mp4'
 end
 local R=STTS.PhoneRecorder31;local m=R and R.Exporter46 and R.Exporter46()
 wantSave[id]=nil
 saveJobs[#saveJobs+1]={source=item.path,name=name,native=m,total=file.Size(item.path,'DATA'),remaining=file.Size(item.path,'DATA')}
 say68('Saving...','saving video '..tostring(id)..' ('..math.floor(file.Size(item.path,'DATA')/1024)..' KB, '..(m and 'native .mp4' or 'Lua .mp4.dat: no zhphone DLL export')..')')
end
local function saveStep()
 local j=saveJobs[1];if not j then return end
 if j.native then
  if not j.started then
   if nativeBusy()then return end
   local ok,accepted,why=pcall(j.native.export_start,j.source,j.name)
   if ok and not accepted and why=='export busy'then return end
   if not ok or not accepted then return saveDone(j,'Native MP4 export failed: '..tostring(why or accepted))end
   j.started=true;j.dest='zhunter_saved/'..j.name
  end
  local ok,state=pcall(j.native.export_poll)
  if not ok or type(state)~='table'then pcall(j.native.export_cancel);return saveDone(j,'Native export status unavailable')end
  P.saveProgress46={bytes=state.bytes or 0,total=state.total or j.total}
  if state.done then
   if state.error and state.error~=''then return saveDone(j,state.error)end
   if file.Size(j.dest,'DATA')~=j.total then return saveDone(j,'Incomplete native MP4 export')end
   saveDone(j)
  end
  return
 end
 if nativeBusy()then return end
 if not j.input then
  file.CreateDir('zhunter_saved')
  -- Lua's writable extension whitelist forbids .mp4; never create a fake empty
  -- final file. A private .dat staging file is published only after validation.
  j.dest='zhunter_saved/'..j.name..'.dat';j.temp=j.dest..'.saving.dat'
  j.input=file.Open(j.source,'rb','DATA');j.output=file.Open(j.temp,'wb','DATA')
  if not j.input or not j.output then return saveDone(j,'Cannot open MP4 export')end
 end
 local clock=SysTime or RealTime;local started=clock()
 -- Independent from networking. Up to 2 MiB/tick, max ~1.5 ms between chunks;
 -- a single filesystem call may still exceed that budget on a slow disk.
 for _=1,8 do
  local n=math.min(262144,j.remaining);if n<=0 then break end
  local data=j.input:Read(n)
  if not data or #data~=n then return saveDone(j,'MP4 export read failed')end
  j.output:Write(data);j.remaining=j.remaining-n
  if clock()-started>=.0015 then break end
 end
 P.saveProgress46={bytes=j.total-j.remaining,total=j.total}
 if j.remaining==0 then
  j.input:Close();j.input=nil;j.output:Close();j.output=nil
  if file.Size(j.temp,'DATA')~=j.total then return saveDone(j,'Incomplete MP4 export write')end
  if file.Exists(j.dest,'DATA')then return saveDone(j,'Export destination already exists')end
  file.Rename(j.temp,j.dest)
  if file.Size(j.dest,'DATA')~=j.total then return saveDone(j,'Cannot publish MP4 export')end
  j.temp=nil;saveDone(j)
 end
end
net.Receive('stts_p37_end',function()
 local n,id=net.ReadUInt(32),net.ReadUInt(32);if not isCurrent(n)then return end
 local j=P.incoming[id];if not j then return end;closeIncoming(j);P.incoming[id]=nil
 local function bad(why)P.DownloadDone44(id,false);return err(why)end
 if j.received[1]~=j.sizes[1]or j.received[3]~=j.sizes[3]or(j.full and j.received[2]~=j.sizes[2])then if wantSave[id]then say68("Can't save video",'video '..id..' download incomplete')end;return bad('Incomplete video download')end
 if(j.full and file.Size(j.paths[2],'DATA')~=j.sizes[2])or(j.sizes[3]>0 and file.Size(j.paths[3],'DATA')~=j.sizes[3])then return bad('Incomplete cache write')end
 local raw=util.Decompress(table.concat(j.parts),1048576);local m=raw and util.JSONToTable(raw)
 if type(m)~='table'or m.version~=37 or type(m.samples)~='table'or #m.samples==0 then return bad('Invalid video metadata')end
 local old=P.byID[id];local item={id=id,record=old and old.record,playable48=true,meta=m,samples=m.samples,duration=m.duration,w=m.w,h=m.h,path=j.paths[2],proxyPath=j.paths[3],full=j.full or(old and old.full)or false}
 if not j.full and old and old.full then item.path=old.path end
 item.samplePath=m.native and item.proxyPath or item.path;P.byID[id]=item
 P.DownloadDone44(id,true)
 if wantSave[id]then wantSave[id]=nil;beginSave(id,item)end
end)
-- A finished LOCAL recording already exists on the GPU. Save its last image
-- into a bounded thumbnail pool instead of reading/writing/loading a JPEG
-- during PreRender. No CPU readback; no extra camera render or video encode.
local gpuThumbPool48={};local gpuThumbNext48=0
function P.GPUThumb48(r)
 if not r or not r.output or not r.output.rt or not r.output.mat or(r.frames or 0)<1 then return end
 if not render or not cam or not cam.Start2D or not cam.End2D or not surface or not surface.DrawTexturedRect then return end
 if r.thumb48 and r.thumb48.owner==r then return end
 gpuThumbNext48=gpuThumbNext48%16+1;local slot=gpuThumbPool48[gpuThumbNext48]
 local pushed,twod=false,false
 local ok=pcall(function()
  if not slot then
   local name='stts_phone_thumb48_'..gpuThumbNext48
   local rt=GetRenderTargetEx(name,192,336,RT_SIZE_LITERAL,MATERIAL_RT_DEPTH_NONE,0,0,IMAGE_FORMAT_RGB888)
   slot={rt=rt,mat=CreateMaterial(name..'_mat','UnlitGeneric',{['$basetexture']=rt:GetName(),['$vertexcolor']=1,['$vertexalpha']=1,['$ignorez']=1})}
   gpuThumbPool48[gpuThumbNext48]=slot
  end
  slot.owner=nil
  render.PushRenderTarget(slot.rt,0,0,192,336);pushed=true;render.Clear(0,0,0,255,false,false)
  cam.Start2D();twod=true;surface.SetMaterial(r.output.mat);surface.SetDrawColor(255,255,255,255);surface.DrawTexturedRect(0,0,192,336)
  cam.End2D();twod=false;render.PopRenderTarget();pushed=false
 end)
 if twod then cam.End2D()end;if pushed then render.PopRenderTarget()end
 if ok then slot.owner=r;r.thumb48=slot end
end
local thumbs={}
function P.Thumb(id)
 local item=P.byID[id];if not item then P.Request(id,false)return end
 local r=item.record;local gpu=r and r.thumb48
 if gpu and gpu.owner==r then return gpu.mat end
 if not thumbs[id]then
  local v=item.samples[1];if not v then return end
  -- Local fallback already writes a thumbnail; reuse that material/file.
  if r and r.galleryThumb and file.Exists(r.galleryThumb,'DATA')then
   local m=Material('../data/'..r.galleryThumb,'smooth noclamp');if m and not m:IsError()then thumbs[id]=m;return m end
  end
  local path=v.path or item.samplePath;local f=file.Open(path,'rb','DATA');if not f then return end;f:Seek(v.offset);local jpg=f:Read(v.size or file.Size(path,'DATA'));f:Close()
  if not jpg then return end
  local path=base(id)..'.thumb.jpg';file.CreateDir(root());file.Write(path,jpg);local m=Material('../data/'..path,'smooth noclamp');if m and not m:IsError()then thumbs[id]=m end
 end
 return thumbs[id]
end
-- fix62: the clip sound. plays while the video is on screen, in step with its picture (it loops
-- with it), at the volume of your phone. own clips: the WAV of the recorder; received ones: the
-- WAV behind the preview pictures, written out once (.wav, or .dat where .wav is refused)
local clipVol62=CreateClientConVar('zhphone_audio_play','1',true,false,'Loudness of the sound of phone videos while you watch them (0 = mute)',0,1)
local A62,cand62={gen=0},nil
local function audioPath62(item)
 if item.audioPath62~=nil then return item.audioPath62 or nil end
 local r=item.record
 if r and r.audioPath62 and file.Exists(r.audioPath62,'DATA')then item.audioPath62=r.audioPath62;return r.audioPath62 end
 item.audioPath62=false
 local a=item.meta and item.meta.audio;local src=item.proxyPath
 if type(a)~='table'or not src or not item.id or item.id<=0 then return end
 local off,size=tonumber(a.offset),tonumber(a.size);local total=file.Size(src,'DATA')or 0
 if not off or not size or off~=math.floor(off)or off<0 or size<45 or size>16*1024*1024 or off+size>total then return end
 local f=file.Open(src,'rb','DATA');if not f then return end
 f:Seek(off);local wav=f:Read(size);f:Close()
 if not wav or #wav~=size or wav:sub(1,4)~='RIFF'or wav:sub(9,12)~='WAVE'then return end
 file.CreateDir(root())
 for _,ext in ipairs({'wav','dat'})do
  local path=base(item.id)..'.clip.'..ext
  if file.Size(path,'DATA')~=size then file.Write(path,wav)end
  if file.Size(path,'DATA')==size then item.audioPath62=path;return path end
  file.Delete(path)
 end
end
stopAudio62=function()
 if IsValid(A62.ch)then A62.ch:Stop()end
 A62.ch,A62.id=nil,nil;A62.gen=A62.gen+1
end
P.StopAudio62=stopAudio62
hook.Add('Think','STTS_PhoneClipAudio62',function()
 local c=cand62;cand62=nil;local now=RealTime()
 if c then A62.seen=now end
 if not c or c.t<=0 then if A62.id and now-(A62.seen or 0)>.25 then stopAudio62()end;return end
 if nativeBusy()or clipVol62:GetFloat()<=0 then if A62.id then stopAudio62()end;return end
 if A62.id~=c.id then
  stopAudio62();A62.id=c.id
  local path=audioPath62(c.item);if not path then return end
  local gen=A62.gen
  sound.PlayFile('data/'..path,'noplay noblock',function(ch)
   if A62.gen~=gen then if IsValid(ch)then ch:Stop()end;return end
   if IsValid(ch)then A62.ch=ch;ch:SetVolume(0)end -- started by the next Think, in step
  end)
  return
 end
 local ch=A62.ch;if not IsValid(ch)then return end
 local when=c.when+math.max(0,now-c.at);local len=ch:GetLength()or 0
 ch:SetVolume(math.Clamp((STTS.PhoneVolume and STTS.PhoneVolume()or 1)*clipVol62:GetFloat(),0,1))
 if len>0 and when>=len-.03 then if ch:GetState()==GMOD_CHANNEL_PLAYING then ch:Pause()end;return end -- the picture loops a moment later
 if ch:GetState()~=GMOD_CHANNEL_PLAYING then ch:SetTime(when);ch:Play()
 elseif math.abs(ch:GetTime()-when)>.15 then ch:SetTime(when)end
end)
-- fix68: a clip filmed landscape: how far its picture has to turn to stand upright (0, 90, -90)
function P.Rot66(id)
 local item=P.byID[id];local m=item and item.meta;local v=m and tonumber(m.rot)
 return(v==90 or v==-90)and v or 0
end
function P.Draw(id,x,y,w,h,t)
 local item=P.byID[id];if not item then P.Request(id,false)return true end
 if nativeBusy()then local m=P.Thumb(id);if m then surface.SetMaterial(m);surface.SetDrawColor(255,255,255);surface.DrawTexturedRect(x,y,w,h)end;return true end
 if not IsValid(panel)then
  panel=vgui.Create('DHTML');panel:SetSize(384,672);panel:SetPos(0,0);panel:SetPaintedManually(true);panel:SetMouseInputEnabled(false);panel:SetKeyboardInputEnabled(false);panel:SetAllowLua(false);panel.ConsoleMessage=function()end
  panel.OnDocumentReady=function()lastID,lastFrame=nil,nil end
  panel:SetHTML([[<!doctype html><html><head><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}img{width:100%;height:100%;object-fit:fill}</style></head><body><img id="f"><script>window.setFrame=function(s){document.getElementById('f').src='data:image/jpeg;base64,'+s;};</script></body></html>]])
 end
 lastUse=RealTime();local when=math.max(t or 0,0)%item.duration;local a,b=1,#item.samples
 -- fix62: the picture being watched (t runs) wins over one sliding away (t = 0)
 if not cand62 or(t or 0)>=cand62.t then cand62={id=id,item=item,when=when,t=t or 0,at=RealTime()}end
 while a<b do local mid=math.ceil((a+b)/2);if item.samples[mid].t<=when then a=mid else b=mid-1 end end
 if lastID~=id or lastFrame~=a then
  local sample=item.samples[a];local path=sample.path or item.samplePath;local f=file.Open(path,'rb','DATA');local jpg;if f then f:Seek(sample.offset);jpg=f:Read(sample.size or file.Size(path,'DATA'));f:Close()end
  if jpg then panel:QueueJavascript("if(window.setFrame)setFrame('"..util.Base64Encode(jpg,true):gsub('%s','').."');");lastID,lastFrame=id,a end
 end
 panel:UpdateHTMLTexture();material=panel:GetHTMLMaterial()or material
 if material then local tex=material:GetTexture('$basetexture');local tw,th=tex and tex:Width()or 384,tex and tex:Height()or 672;surface.SetMaterial(material);surface.SetDrawColor(255,255,255);surface.DrawTexturedRectUV(x,y,w,h,0,0,math.min(1,384/math.max(1,tw)),math.min(1,672/math.max(1,th)))end
 return true
end
function P.Save(id)
 if nativeBusy()then say68('Stop recording first');return false end
 local item=P.byID[id];if item then beginSave(id,item)else wantSave[id]=true;P.Request(id,true)end;return true
end
function P.Delete(id)
 local item=P.byID[id];local r=item and item.record
 if r then
  r.deleted=true;r.sharePeers=nil
  if r.localID then P.predicted[r.localID]=nil;P.byID[r.localID]=nil;thumbs[r.localID]=nil end
  if r.id then net.Start('stts_phone_del');net.WriteUInt(r.id,32);net.SendToServer()
  else P.Abort(r)end
  if r.id then P.byID[r.id]=nil;thumbs[r.id]=nil end
  P.failed[r.base or r.token]=nil
 end
 P.byID[id]=nil;thumbs[id]=nil;close()
end
function P.Reset()
 local s=S();if s and s.L and s.L.rec and STTS.PhoneRecorder31 then STTS.PhoneRecorder31.Cancel()end
 close()
 for _,j in pairs(P.incoming)do closeIncoming(j)end
 for _,r in pairs(P.pending)do if r.handle then r.handle:Close();r.handle=nil end;if r.proxyHandle48 then r.proxyHandle48:Close();r.proxyHandle48=nil end end
 for _,j in ipairs(saveJobs)do
  if j.native and j.started then pcall(j.native.export_cancel)end
  if j.input then j.input:Close()end;if j.output then j.output:Close()end;if j.temp then file.Delete(j.temp)end
 end
 P.saveProgress46=nil;cleanup48={}
 for _,slot in ipairs(gpuThumbPool48)do slot.owner=nil end
 P.byID,P.pending,P.queue,P.incoming,P.failed,P.predicted={}, {},{},{},{},{};P.nextLocal=0;P.sendAfter=nil;P.upload=nil;P.lastError=nil;P.transfers44={};requests,saveJobs,wantSave,thumbs={}, {},{},{}
 local R=STTS.PhoneRecorder31;removeTree('stts_phone_tmp',R and R.retiringRecord and R.retiringRecord.base)
end
hook.Add('Think','STTS_PhoneMedia37',function()
 local now=RealTime()
 if IsValid(panel)and(nativeBusy()or now-(lastUse or 0)>.5)then close()end
 for id,j in pairs(P.incoming)do if now-j.at>120 then closeIncoming(j);P.incoming[id]=nil end end
 if not nativeBusy()then cleanupStep48()end
 -- fix66: a Save whose full download request got lost asks again (P.Request throttles it to 6 s)
 for id in pairs(wantSave)do if not P.incoming[id]then P.Request(id,true)end end
 saveStep() -- not behind uploads or preview building; native copying is off-thread
 -- fix61: shares only hand ids to the send queue (cheap), also while filming
 for id,item in pairs(P.byID)do local r=item.record;if r and id==r.id and r.id and not r.deleted and r.round==round()then flushShares(r)end end
 if nativeBusy()then -- no Lua copying/upload/proxy work on capture frames
  if P.upload then P.upload.pausedAt61=P.upload.pausedAt61 or now end
  return
 end
 -- Preview building of a queued clip must not block local browsing behind another upload.
 for _,r in pairs(P.pending)do if r.finished then predict(r)end end
 local r=P.upload
 if r and r.pausedAt61 then
  -- fix61: a pause for filming: the stall clock does not run; past ~50 s the server
  -- has dropped the half upload, so it starts again at once
  local paused=now-r.pausedAt61;r.pausedAt61=nil
  if paused>50 then r.waitAt=now-21 else r.waitAt=r.waitAt+paused end
 end
 if r then
  -- fix61: 20 s without an acknowledgement (the server dropped a stalled upload, it waited
  -- 30 minutes here and blocked every later clip): the upload starts again, 3 times at most
  if now-r.waitAt>20 then
   r.restarts61=(r.restarts61 or 0)+1
   if r.restarts61>3 then return failUpload(r,'Media upload timed out')end
   if r.handle then r.handle:Close();r.handle=nil end
   return startUpload(r)
  end
  if r.phase=='send'then
   r.txBytes=math.min(CHUNK*WINDOW,(r.txBytes or 0)+math.max(0,now-(r.txAt or now))*(r.rate or 1024*1024));r.txAt=now
   for _=1,WINDOW do
    if r.inflightCount>=WINDOW then break end
    while r.stream<=3 and r.offset>=r.sizes[r.stream]do if r.handle then r.handle:Close();r.handle=nil end;r.stream=r.stream+1;r.index=1;r.offset=0 end
    if r.stream>3 then r.phase='commit';break end
    local n=math.min(CHUNK,r.sizes[r.stream]-r.offset)
    if r.txBytes<n then break end
    local data
    if r.stream==1 then data=r.metaData:sub(r.offset+1,r.offset+n)else
     if not r.handle then r.handle=file.Open(r.stream==2 and r.filePath or r.proxyPath,'rb','DATA')end
     if r.handle then data=r.handle:Read(n)end
    end
    if not data or #data~=n then return failUpload(r,'Recording cache unavailable')end
    local key=r.stream*65536+r.index
    r.inflight[key]=n;r.inflightCount=r.inflightCount+1;r.waiting=r.inflightCount;r.txBytes=r.txBytes-n
    net.Start('stts_p37_part');net.WriteUInt(r.round,32);net.WriteUInt(r.token,16);net.WriteUInt(r.stream,2);net.WriteUInt(r.index,16);net.WriteUInt(n,16);net.WriteData(data,n);net.SendToServer()
    r.index=r.index+1;r.offset=r.offset+n
   end
  end
 elseif #P.queue>0 then
  r=P.queue[1]
  if r.round~=round()or r.permit==false then table.remove(P.queue,1);failUpload(r,r.permitError or 'Recording phone not authorized')
  elseif not r.permit then if now-r.startAt>135 then table.remove(P.queue,1);failUpload(r,'Server has no phone-media protocol37')end
  elseif r.buildIndex and r.buildIndex<=#r.proxyIndex then
   local sample=r.proxyIndex[r.buildIndex];local jpg=file.Read(r.base..'.proxy/'..sample.name,'DATA')
   if not jpg or jpg:sub(1,2)~='\255\216'then table.remove(P.queue,1);failUpload(r,'Missing native preview')else
    if not r.proxyHandle48 then r.proxyHandle48=file.Open(r.proxyPath,'ab','DATA')end
    if not r.proxyHandle48 then return failUpload(r,'Cannot append native preview cache')end
    r.proxyHandle48:Write(jpg)
    r.meta.samples[#r.meta.samples+1]={t=sample.t,offset=r.proxyBytes,size=#jpg};r.proxyBytes=r.proxyBytes+#jpg;r.buildIndex=r.buildIndex+1
    if r.buildIndex>#r.proxyIndex then
     -- fix62: the clip sound goes behind the preview pictures (the others play it from there)
     local wav=r.audioPath62 and file.Read(r.audioPath62,'DATA')
     if wav and #wav>44 and wav:sub(1,4)=='RIFF'and wav:sub(9,12)=='WAVE'and r.proxyBytes+#wav<=60*1024*1024 then
      r.proxyHandle48:Write(wav);r.meta.audio={offset=r.proxyBytes,size=#wav,rate=24000};r.proxyBytes=r.proxyBytes+#wav
     end
     r.proxyHandle48:Close();r.proxyHandle48=nil
     if file.Size(r.proxyPath,'DATA')~=r.proxyBytes then return failUpload(r,'Incomplete native preview write')end
    end
   end
  else table.remove(P.queue,1);startUpload(r)end

 end
end)
hook.Add('ShutDown','STTS_PhoneMedia37',P.Reset)

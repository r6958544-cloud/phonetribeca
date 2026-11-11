--[[---------------------------------------------------------------------------
	SHOOTING - phone photos
	* the camera app renders the phone camera into a render target on the
	  photographer's PC, render.Capture -> jpg, saved in data/stts_phone/.
	* the jpg is util.Compress'ed and uploaded in chunks; the server keeps it
	  in memory and lists it in the gallery of the PHONE (not of the player):
	  whoever picks the phone up later can look through its photos.
	* videos: frames are packed into jpg "pages" (atlas 8 x 4 frames), the
	  pages are uploaded like photos (not listed in a gallery), then one
	  "video" item points at them (stts_phone_vid). a gallery item is a
	  photo or a video, the NW2 string "PhotosV" lists the videos.
	* sending (only from TeleChat, the attach button) adds the item to the
	  other phone's gallery, the server streams the bytes to its holder.
	* limits: size, photos per phone, cooldowns, total memory, download
	  budget per player. everything is wiped after the round (server memory
	  and data/stts_phone/ on every client).
---------------------------------------------------------------------------]]
STTS = STTS or {}
STTS.PhoneMedia = STTS.PhoneMedia or {}
local M = STTS.PhoneMedia
local G = STTS.PhoneGeo
local PHONE = STTS.Phone
local CLASS = "weapon_stts_phone"

util.AddNetworkString("stts_phone_sharepage") -- explicit completed local-clip sharing, held phone only
util.AddNetworkString("stts_phone_sharevid")
util.AddNetworkString("stts_phone_up")     -- <- photo chunk
util.AddNetworkString("stts_phone_upflow")
util.AddNetworkString("stts_phone_upok")   -- -> token, photo id (or 0 = rejected)
util.AddNetworkString("stts_phone_dl")     -- <- want photo id
util.AddNetworkString("stts_phone_dlg")
util.AddNetworkString("stts_phone_dlc")    -- -> photo chunk
util.AddNetworkString("stts_phone_del")    -- <- delete photo id from the phone in your hand
util.AddNetworkString("stts_phone_wipe")   -- -> delete every cached photo
util.AddNetworkString("stts_phone_vid")    -- <- video: page ids, frames, fps
util.AddNetworkString("stts_phone_vok")    -- -> token, video id (or 0 = rejected)
util.AddNetworkString("stts_phone_vmeta")  -- -> video id, page ids, frames, fps

-- fix30: fixed 15fps / 256x448 / Q88, small page preset 7.
-- Page counts use 9 bits: this protocol requires matching server/client files.

local MAX_TOTAL = 512 * 1024 * 1024 -- server memory for photos (fix15: 2 minute videos, was 32 MB)
local DL_CHUNK = 48000

M.Photos = M.Photos or {}  -- [id] = {data = compressed jpg, size, by = steamid64}
M.NextId = M.NextId or 1
M.Total = M.Total or 0
M.Round = M.Round or 1
SetGlobalInt("STTS_PhotoRound", M.Round)

-- Canonical per-number gallery survives inventory entity recreation and late uploads.
local galleries={}
-- fix54: a phone whose number changed (collision on recreation) takes a COPY of its list:
-- one table under two numbers = two phones showing the same photos
local function Gallery(wep)
 local num=wep:GetNWString("STTS_Num","")
 if num~="" then
  if not galleries[num]then
   local old=wep.STTS_Photos or{}
   if wep.STTS_GalNum and wep.STTS_GalNum~=num then old=table.Copy(old)end
   galleries[num]=old
  end
  wep.STTS_Photos=galleries[num];wep.STTS_GalNum=num
 else wep.STTS_Photos=wep.STTS_Photos or{}end
 return wep.STTS_Photos
end

-- fix54: one NW2 string holds 511 characters (~85 ids): the lists are split into parts,
-- "Photos", "Photos#2", ... and "Photos#n" = how many (cl_phone_screen.lua, SCR.NWList)
local NW_PART = 500
local function SetList(wep, key, list)
	local parts, cur, len = {}, {}, 0
	for _, v in ipairs(list) do
		local s = tostring(v)
		if len > 0 and len + 1 + #s > NW_PART then parts[#parts + 1] = table.concat(cur, ",") cur, len = {}, 0 end
		cur[#cur + 1] = s
		len = len + (len > 0 and 1 or 0) + #s
	end
	if #cur > 0 then parts[#parts + 1] = table.concat(cur, ",") end
	local old = wep:GetNW2Int(key .. "#n", 1)
	wep:SetNW2String(key, parts[1] or "")
	for i = 2, math.max(#parts, old) do wep:SetNW2String(key .. "#" .. i, parts[i] or "") end
	wep:SetNW2Int(key .. "#n", math.max(1, #parts))
end

local function Publish(wep)
	local ids = Gallery(wep)
	SetList(wep, "Photos", ids)
	-- album "Received": photos that were sent to this phone
	local recv, r = wep.STTS_Recv or {}, {}
	for _, id in ipairs(ids) do if recv[id] or recv[tostring(id)] then r[#r + 1] = id end end
	SetList(wep, "PhotosR", r)
	-- videos among them
	local v = {}
	for _, id in ipairs(ids) do local it = M.Photos[id] if it and it.video then v[#v + 1] = id end end
	SetList(wep, "PhotosV", v)
 local blobs={};for _,id in ipairs(ids)do if M.Photos[id]and M.Photos[id].blob37 then blobs[#blobs+1]=id end end
 SetList(wep,"PhotosB",blobs)
end

function M.SetGallery(wep, ids)
 local num=wep:GetNWString("STTS_Num","")
 if num~="" and galleries[num]then wep.STTS_Photos=galleries[num];wep.STTS_GalNum=num;Publish(wep);return end
	local out = {}
	for _, id in ipairs(ids or {}) do
		if M.Photos[tonumber(id) or 0] then out[#out + 1] = tonumber(id) end
	end
	wep.STTS_Photos = out
	wep.STTS_GalNum = nil
	Publish(wep)
end

local function HasPhoto(wep, id)
	for _, v in ipairs(Gallery(wep)) do if v == id then return true end end
	return false
end

local function Holding(ply)
	if not IsValid(ply) or not ply:Alive() or (ply.organism and ply.organism.otrub) then return end
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == CLASS then return wep end
end

-- fix15: the phone this player is recording a video on (it may have fallen out of his
-- hands / he may be dead: the recording goes on, its pages still belong to that phone)
local function RecPhone(ply)
	local w = IsValid(ply) and ply.STTS_RecWep
	if IsValid(w) and w:GetClass() == CLASS and CurTime() < (ply.STTS_RecUntil or 0) then return w end
end
M.RecPhone = RecPhone

-- fix54: a photo belongs to the phone it was TAKEN with (entity index + number from the
-- client), not to whatever phone is in the hand when its upload arrives: a burst of shots,
-- then another phone picked up = the last photos used to land in the other phone
local function ShotPhone(ply, idx, num)
	local function ok(w)
		if not IsValid(w) or w:GetClass() ~= CLASS then return false end
		local o = w:GetOwner()
		if o == ply then return true end
		local pos = PHONE.WorldPos and PHONE.WorldPos(w) or w:GetPos()
		return not IsValid(o) and pos:DistToSqr(ply:GetPos()) < 300 * 300 -- just dropped
	end
	local w = idx > 0 and Entity(idx) or NULL
	if ok(w) and (num == "" or w:GetNWString("STTS_Num", "") == num) then return w end
	if num ~= "" then
		for _, e in ipairs(ents.FindByClass(CLASS)) do
			if e:GetNWString("STTS_Num", "") == num and ok(e) then return e end
		end
	end
end

-- Bounded, paced media download: one shared budget for photos AND video.
local DL_WINDOW44 = 12 -- fix66: <=576 KB awaiting acknowledgement per player/job (was 4 = 192 KB: one round trip per 192 KB)
local dlRate44 = CreateConVar('zhphone_download_kbps','8192',FCVAR_ARCHIVE,'Phone download KiB/s per player',256,10240)
local dlTotal44 = CreateConVar('zhphone_download_total_kbps','10240',FCVAR_ARCHIVE,'Total phone download KiB/s for server',256,102400)
local DL_BURST66 = 48000 * DL_WINDOW44
-- fix68: at most this much sent and not yet acknowledged per player (photos + video together).
-- 576 KB in flight (fix67) overflowed the reliable channel of the client (GMod drops a player
-- whose unsent reliable data passes ~256 KB: "overflowed reliable buffer"). 3 parts = 144 KB
local DL_HELD68 = 48000 * 3
local dlBudgets44, dlGlobal44, done44 = {}, {at=CurTime(),bytes=DL_BURST66}, {}
-- fix61: the upload speed the server offers (was never defined: every clip went at 1 MiB/s)
local upRate61 = CreateConVar('zhphone_upload_limit_kbps','3072',FCVAR_ARCHIVE,'Phone video upload KiB/s per player offered to clients',256,10240)
STTS.NetMediaLimitKiB = STTS.NetMediaLimitKiB or function() return math.Clamp(upRate61:GetInt(),256,10240) end
local function refill44(b,rate)
 local now=CurTime();b.bytes=math.min(DL_BURST66,b.bytes+math.max(0,now-b.at)*rate*1024);b.at=now
end
local function credit44(ply,n)
 local b=dlBudgets44[ply];if not b then b={at=CurTime(),bytes=DL_BURST66};dlBudgets44[ply]=b end
 refill44(b,math.Clamp(dlRate44:GetInt(),256,10240));refill44(dlGlobal44,math.Clamp(dlTotal44:GetInt(),256,102400))
 if (b.held or 0)+n>DL_HELD68 or b.bytes<n or dlGlobal44.bytes<n then return false end
 b.bytes=b.bytes-n;dlGlobal44.bytes=dlGlobal44.bytes-n;b.held=(b.held or 0)+n;return true
end
local function releaseBytes44(ply,n)
 local b=dlBudgets44[ply];if b then b.held=math.max(0,(b.held or 0)-n)end
end
local function releaseJob44(ply,entries)
 for _,n in pairs(entries or{})do releaseBytes44(ply,n)end
end
local function transferSize44(it,full)
 if not it.blob37 then return #(it.data or '') end
 return it.lengths[1]+it.lengths[3]+((full or not it.meta.native)and it.lengths[2]or 0)
end
util.AddNetworkString('stts_p44_progress');util.AddNetworkString('stts_p44_done');util.AddNetworkString('stts_p44_have')
local function emit44(link,id,bytes,total,state)
 local function send(num,peer)
  local sent={}
  for _,w in ipairs(ents.FindByClass(CLASS))do
   if w:GetNWString('STTS_Num','')==num then
    local p=w:GetOwner()
    if IsValid(p)and p:IsPlayer()and not p:IsBot()and not sent[p]then
     sent[p]=true
     net.Start('stts_p44_progress');net.WriteUInt(M.Round,32);net.WriteString(num);net.WriteString(peer);net.WriteUInt(id,32)
     net.WriteUInt(bytes,32);net.WriteUInt(total,32);net.WriteUInt(state,2);net.Send(p)
    end
   end
  end
 end
 send(link.from,link.to);send(link.to,link.from)
end
function M.WatchTransfer44(from,target,id)
 local it=M.Photos[id];if not it or not IsValid(from)then return end
 local a,b=from:GetNWString('STTS_Num',''),target:GetNWString('STTS_Num','')
 if a==''or b==''then return end
 it.links44=it.links44 or{};local key=a..':'..b
 if not it.links44[key]then
  local n=0;for _ in pairs(it.links44)do n=n+1 end;if n>=64 then return end
  it.links44[key]={from=a,to=b}
 end
 local l=it.links44[key];local ready=it.ready47 and it.ready47[target:GetOwner()]
 l.bytes=ready and transferSize44(it,false)or 0;l.total=transferSize44(it,false);l.state=ready and 2 or 0
 emit44(l,id,l.bytes,l.total,l.state)
end
local function progress44(ply,id,bytes,total,state,job)
 if job and state==1 and CurTime()<(job.progressAt44 or 0)+.2 then return end
 if job then job.progressAt44=CurTime()end
 local it=M.Photos[id];if not it then return end
 -- Messenger readiness is preview/playback readiness, not an MP4 export.
 -- A later original download must never put a playable clip back at 35%.
 local ready=it.ready47 and it.ready47[ply]
 if job and job.full and ready and state~=2 then return end
 if ready and job and state==1 and bytes==0 then return end -- cache handshake is not a new download
 if state==2 then
  it.ready47=it.ready47 or setmetatable({},{__mode='k'});it.ready47[ply]=true
 elseif not(job and job.full)then
  if it.ready47 then it.ready47[ply]=nil end
 end
 for _,link in pairs(it.links44 or{})do
  for _,w in ipairs(ents.FindByClass(CLASS))do
   if w:GetNWString('STTS_Num','')==link.to and w:GetOwner()==ply and HasPhoto(w,id)then
    link.bytes,link.total,link.state=bytes,total,state;emit44(link,id,bytes,total,state);break
   end
  end
 end
end
local function awaitDone44(ply,id,total,full)
 local d=done44[ply]or{};done44[ply]=d;d[id]={total=total,at=CurTime(),full=full==true}
end
net.Receive('stts_p44_done',function(_,ply)
 local n,id,ok=net.ReadUInt(32),net.ReadUInt(32),net.ReadBool()
 local d=done44[ply];local j=d and d[id]
 if n~=M.Round or not j or CurTime()-j.at>120 then return end
 d[id]=nil;progress44(ply,id,ok and j.total or 0,j.total,ok and 2 or 3,j)
end)
hook.Add('PlayerDisconnected','STTS_PhoneDownload44',function(ply)dlBudgets44[ply]=nil;done44[ply]=nil end)

--[[ download queue ]]
local function SendMeta(ply, id)
	local it = M.Photos[id]
	if not it or not it.video then return end
	net.Start("stts_phone_vmeta")
		net.WriteUInt(id, 32)
		net.WriteUInt(#it.pages, 9)
		for _, pid in ipairs(it.pages) do net.WriteUInt(pid, 32) end
		net.WriteUInt(it.frames, 12)
		net.WriteUInt(it.fps, 5)
		net.WriteUInt(it.res or G.VidResDefault, 3)
	net.Send(ply)
end

local function Queue(ply, id)
	if not IsValid(ply) or ply:IsBot() or not M.Photos[id] then return end
	if M.Photos[id].blob37 then if M.QueueBlob37 then M.QueueBlob37(ply,id,false)end;return end
	-- a video = its meta + every page
	if M.Photos[id].video then
		SendMeta(ply, id)
		for _, pid in ipairs(M.Photos[id].pages) do Queue(ply, pid) end
		return
	end
	ply.STTS_DL = ply.STTS_DL or {}
	for _, job in ipairs(ply.STTS_DL) do if job.id == id then return end end
	if #ply.STTS_DL >= G.VidMaxPagesNet + 30 then return end -- bounded download queue for one complete new-format clip
	ply.STTS_DL[#ply.STTS_DL + 1] = {id = id, off = 0}
end
M.Queue = Queue

timer.Create("STTS_PhonePhotoStream",.01,0,function()
 for _,ply in player.Iterator()do
  local q=ply.STTS_DL;local job=q and q[1]
  if job then
   local p=M.Photos[job.id]
   if not p or not p.data or CurTime()-(job.sentAt or CurTime())>150 then
    if p then progress44(ply,job.id,job.acked44 or 0,#p.data,3)end
    releaseJob44(ply,job.inflight44);table.remove(q,1)
   else
    job.inflight44=job.inflight44 or{};job.pending44=job.pending44 or 0
    for _=1,DL_WINDOW44 do
     if job.pending44>=DL_WINDOW44 or job.off>=#p.data then break end
     local part=p.data:sub(job.off+1,job.off+DL_CHUNK)
     if not credit44(ply,#part)then break end
     net.Start("stts_phone_dlc");net.WriteUInt(job.id,32);net.WriteUInt(job.off,32);net.WriteUInt(#p.data,32);net.WriteUInt(#part,16);net.WriteData(part,#part);net.Send(ply)
     job.inflight44[job.off]=#part;job.pending44=job.pending44+1;job.sentAt=CurTime();job.off=job.off+#part
    end
   end
  end
 end
end)
net.Receive("stts_phone_dlg",function(_,ply)
 local id,off=net.ReadUInt(32),net.ReadUInt(32);local q=ply.STTS_DL;local j=q and q[1]
 local size=j and j.inflight44 and j.inflight44[off]
 if not j or j.id~=id or not size then return end
 releaseBytes44(ply,size);j.inflight44[off]=nil;j.pending44=j.pending44-1;j.acked44=(j.acked44 or 0)+size;j.sentAt=CurTime()
 local it=M.Photos[id];if not it then return end
 progress44(ply,id,j.acked44,#it.data,1,j)
 if j.off>=#it.data and j.pending44==0 then awaitDone44(ply,id,#it.data);table.remove(q,1)end
end)

--[[ upload ]]
local function ReceiveUpload(len, ply, sharing)
	local page = net.ReadBool() -- true = a page of a video (not listed in the gallery)
	local token, idx, total, size = net.ReadUInt(16), net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
	if size > G.PhotoChunk or size * 8 > len then return end
	local data = net.ReadData(size)
	if type(data)~="string"or #data~=size then return end
	local widx, wnum = net.ReadUInt(16), net.ReadString() -- fix54: the phone of the shot
	if #wnum > 32 then return end
	local wep
	if page and not sharing then wep = RecPhone(ply) or Holding(ply)
	elseif not page and not sharing and (widx > 0 or wnum ~= "") then wep = ShotPhone(ply, widx, wnum)
	else wep = Holding(ply) end
	local function Reject() ply.STTS_Up = nil net.Start("stts_phone_upok") net.WriteUInt(token, 16) net.WriteUInt(0, 32) net.Send(ply) end
	if not wep then return Reject() end
	if total < 1 or total > math.ceil(G.PhotoMaxBytes / G.PhotoChunk) or idx < 1 or idx > total then return Reject() end

	local up = ply.STTS_Up
	if idx == 1 then
		if page then
			-- pages: at most G.VidMaxPages per video, a few videos per minute
			if (ply.STTS_PageCD or 0) > CurTime() then return Reject() end
			ply.STTS_PageCD = CurTime() + 0.10
		else
			if (ply.STTS_PhotoCD or 0) > CurTime() then return Reject() end
			-- fix53: the client already waits G.PhotoCooldown between two shots and sends its
			-- photos one after another; half of it here = network jitter never drops a photo
			ply.STTS_PhotoCD = CurTime() + G.PhotoCooldown * 0.5
		end
		if #Gallery(wep) >= G.PhotoMaxPerPhone then return Reject() end
		up = {token = token, total = total, parts = {}, bytes = 0, at = CurTime(), wep = wep, page = page, sharing = sharing}
		ply.STTS_Up = up
	end
	if not up or up.token ~= token or up.total ~= total or up.parts[idx] or up.sharing~=sharing then return end
	if CurTime() - up.at > 45 or up.wep ~= wep then return Reject() end
	if up.bytes+size>G.PhotoMaxBytes then return Reject()end
	if STTS.NetMediaCredit and not STTS.NetMediaCredit(ply,len)then return Reject()end
	up.at=CurTime()
	up.parts[idx] = data
	up.bytes = up.bytes + size
	if up.bytes > G.PhotoMaxBytes then return Reject() end
	for i = 1, total do if not up.parts[i] then net.Start("stts_phone_upflow");net.WriteUInt(token,16);net.WriteUInt(idx,8);net.Send(ply);return end end

	ply.STTS_Up = nil
	local blob = table.concat(up.parts)
	-- fix53: photos come as a plain jpg (no LZMA on the client or here: it was a hitch on
	-- every shot and a jpg does not get smaller); older clients still send it compressed
	local raw = string.sub(blob, 1, 2) == "\255\216" and blob or util.Decompress(blob, 4 * 1024 * 1024)
	if not raw or string.sub(raw, 1, 2) ~= "\255\216" then return Reject() end -- must be a jpg
	if M.Total + #blob > MAX_TOTAL then return Reject() end

	local id = M.NextId
	M.NextId = id + 1
	M.Photos[id] = {data = blob, size = #blob, by = ply:SteamID64() or "", page = up.page or nil, owner = up.page and ply or nil}
	M.Total = M.Total + #blob
	if not up.page then
		local gal = Gallery(wep)
		gal[#gal + 1] = id
		Publish(wep)
	end
	net.Start("stts_phone_upok") net.WriteUInt(token, 16) net.WriteUInt(id, 32) net.Send(ply)
end
net.Receive("stts_phone_up",function(len,ply)ReceiveUpload(len,ply,false)end)
net.Receive("stts_phone_sharepage",function(len,ply)ReceiveUpload(len,ply,true)end)

--[[ video: the uploaded pages become one gallery item ]]
local function ReceiveVideo(_, ply, sharing)
	local token = net.ReadUInt(16)
	local n = net.ReadUInt(9) -- fix30: 9-bit page count, 12-bit frame count, 3-bit preset
	local pages = {}
	for i = 1, n do pages[i] = net.ReadUInt(32) end
	local frames, fps, res = net.ReadUInt(12), net.ReadUInt(5), net.ReadUInt(3)
	local function Reply(id) net.Start("stts_phone_vok") net.WriteUInt(token, 16) net.WriteUInt(id, 32) net.Send(ply) end
	local wep = Holding(ply)
 if not sharing then wep=RecPhone(ply) or wep end
	if res < 1 or res > #G.VidRes or fps < 1 or fps > 30 then return Reply(0) end
	local lay = G.VidLayout(res)
	if not wep or #pages == 0 or n > G.VidPagesFor(res, fps) + 1 then return Reply(0) end
	if (ply.STTS_VidCD or 0) > CurTime() then return Reply(0) end
	if frames < 1 or frames > #pages * lay.frames or frames > G.VidMaxFrames(res, fps) then return Reply(0) end
	if #Gallery(wep) >= G.PhotoMaxPerPhone then return Reply(0) end
	for _, pid in ipairs(pages) do
		local it = M.Photos[pid]
		if not it or not it.page or it.owner ~= ply or it.parent then return Reply(0) end
	end
	ply.STTS_VidCD = CurTime() + 2
	if ply.STTS_RecWep == wep and wep:GetNW2Entity("RecBy", NULL) ~= ply then ply.STTS_RecWep, ply.STTS_RecUntil = nil, nil end
	local id = M.NextId
	M.NextId = id + 1
	M.Photos[id] = {video = true, pages = pages, frames = frames, fps = fps, res = res, size = 0, by = ply:SteamID64() or ""}
	for _, pid in ipairs(pages) do M.Photos[pid].parent = id end
	local gal = Gallery(wep)
	gal[#gal + 1] = id
	Publish(wep)
	Reply(id)
end
net.Receive("stts_phone_vid",function(len,ply)ReceiveVideo(len,ply,false)end)
net.Receive("stts_phone_sharevid",function(len,ply)ReceiveVideo(len,ply,true)end)

--[[ somebody looks at a photo: in his own hand, or on a phone right next to him ]]
net.Receive("stts_phone_dl", function(_, ply)
	local id = net.ReadUInt(32)
	if (ply.STTS_DLReqCD or 0) > CurTime() then return end
	ply.STTS_DLReqCD = CurTime() + 0.15
	local it = M.Photos[id]
	if not it then return end
	local item = it.parent or id -- a page of a video: allowed if the video is
	local eye = PHONE.CharEye and PHONE.CharEye(ply) or ply:EyePos()
	for _, wep in ipairs(ents.FindByClass(CLASS)) do
		if HasPhoto(wep, item) and (wep:GetOwner() == ply or PHONE.WorldPos(wep):DistToSqr(eye) < 400 * 400) then
			Queue(ply, id)
			return
		end
	end
end)

net.Receive("stts_phone_del", function(_, ply)
	local id = net.ReadUInt(32)
	local wep = Holding(ply)
	if not wep then return end
	local gal = Gallery(wep)
	for i, v in ipairs(gal) do
		if v == id then table.remove(gal, i) break end
	end
	Publish(wep)
end)

--[[ share an item (photo / video) from one phone to another: used by the
     TeleChat attach button (the only way to send media). true = delivered ]]
function M.HasItem(wep, id) return IsValid(wep) and HasPhoto(wep, id) end

M.HasPhoto = function(wep, id) return IsValid(wep) and HasPhoto(wep, id) end -- fix17
-- held = fix17: a message that waited for airplane mode (checked when it was sent)
function M.Share(ply, wep, target, id, held)
	if not IsValid(target) or target == wep then return false end
	if held then
		if not M.Photos[id] then return false end
	else
		if not IsValid(wep) or not IsValid(ply) or not HasPhoto(wep, id) then return false end
		local now = CurTime()
		if (ply.STTS_SendCD or 0) > now then return false end
		ply.STTS_SendLog = ply.STTS_SendLog or {}
		local log = {}
		for _, t in ipairs(ply.STTS_SendLog) do if now - t < 60 then log[#log + 1] = t end end
		if #log >= G.SendPerMinute then ply.STTS_SendLog = log return false end
		ply.STTS_SendCD = now + 1
		log[#log + 1] = now
		ply.STTS_SendLog = log
	end

	if not HasPhoto(target, id) then
		local gal = Gallery(target)
		if #gal >= G.PhotoMaxPerPhone then return false end
		gal[#gal + 1] = id
		target.STTS_Recv = target.STTS_Recv or {}
		target.STTS_Recv[id] = true
		Publish(target)
	end
	M.WatchTransfer44(wep,target,id)
	-- fix53: like Telegram, the item is NOT pushed to the receiver any more: his TeleChat
	-- shows a blurred preview + size, a tap downloads it (stts_phone_dl / stts_p37_get)
	return true
end

--[[ fix53: TeleChat media like Telegram
     stts_p49_info   <- id            -> id, kind (0 photo, 1 video pages, 2 video), bytes, duration (1/10 s), tiny preview jpg
     stts_p49_prev   <- id, tiny jpg  (only the author of the item, once)
     stts_p49_cancel <- id            (tap on a running download: it leaves the queue) ]]
util.AddNetworkString("stts_p49_info")
util.AddNetworkString("stts_p49_prev")
util.AddNetworkString("stts_p49_cancel")
local PREV_MAX49 = 4096
local function CanSee49(ply, id)
	local it = M.Photos[id]
	if not it or not IsValid(ply) then return false end
	local item = it.parent or id
	local eye = PHONE.CharEye and PHONE.CharEye(ply) or ply:EyePos()
	for _, wep in ipairs(ents.FindByClass(CLASS)) do
		if HasPhoto(wep, item) and (wep:GetOwner() == ply or PHONE.WorldPos(wep):DistToSqr(eye) < 400 * 400) then return true end
	end
	return false
end
M.CanSee49 = CanSee49
local function Bucket49(ply, key, rate, burst)
	local b = ply[key]
	local now = CurTime()
	if not b then b = {n = burst, at = now} ply[key] = b end
	b.n = math.min(burst, b.n + (now - b.at) * rate)
	b.at = now
	if b.n < 1 then return false end
	b.n = b.n - 1
	return true
end
net.Receive("stts_p49_info", function(_, ply)
	local id = net.ReadUInt(32)
	if not Bucket49(ply, "STTS_P49Info", 20, 40) then return end
	local it = M.Photos[id]
	if not it or it.page or not CanSee49(ply, id) then return end
	local kind, bytes, dur = 0, 0, 0
	if it.blob37 then
		kind, bytes, dur = 2, transferSize44(it, false), it.meta and it.meta.duration or 0
	elseif it.video then
		kind = 1
		for _, pid in ipairs(it.pages or {}) do local p = M.Photos[pid] if p and p.data then bytes = bytes + #p.data end end
		dur = (it.frames or 0) / math.max(1, it.fps or 1)
	else
		bytes = #(it.data or "")
	end
	local prev = it.prev49 or ""
	net.Start("stts_p49_info")
		net.WriteUInt(id, 32)
		net.WriteUInt(kind, 2)
		net.WriteUInt(math.Clamp(math.floor(bytes), 0, 4294967295), 32)
		net.WriteUInt(math.Clamp(math.Round(dur * 10), 0, 65535), 16)
		net.WriteUInt(#prev, 16)
		if #prev > 0 then net.WriteData(prev, #prev) end
	net.Send(ply)
end)
net.Receive("stts_p49_prev", function(len, ply)
	local id, n = net.ReadUInt(32), net.ReadUInt(16)
	if n < 4 or n > PREV_MAX49 or n * 8 > len then return end
	local data = net.ReadData(n)
	if type(data) ~= "string" or #data ~= n or string.sub(data, 1, 2) ~= "\255\216" then return end
	local it = M.Photos[id]
	if not it or it.page or it.prev49 or it.by ~= (ply:SteamID64() or "") then return end
	it.prev49 = data
end)
-- fix54: a photo the server puts into a phone itself (stts_phone_botphoto: a bot has no
-- game client, sv_phone_botphoto.lua). by = who took it, prev = the tiny TeleChat preview
function M.AddPhotoFor(wep, data, by, prev)
	if not IsValid(wep) or type(data) ~= "string" or string.sub(data, 1, 2) ~= "\255\216" then return end
	if #data > G.PhotoMaxBytes or M.Total + #data > MAX_TOTAL then return end
	local gal = Gallery(wep)
	if #gal >= G.PhotoMaxPerPhone then return end
	local id = M.NextId
	M.NextId = id + 1
	local it = {data = data, size = #data, by = IsValid(by) and by:IsPlayer() and (by:SteamID64() or "") or ""}
	if type(prev) == "string" and #prev >= 4 and #prev <= PREV_MAX49 and string.sub(prev, 1, 2) == "\255\216" then it.prev49 = prev end
	M.Photos[id] = it
	M.Total = M.Total + #data
	gal[#gal + 1] = id
	Publish(wep)
	return id
end
net.Receive("stts_p49_cancel", function(_, ply)
	local id = net.ReadUInt(32)
	if not Bucket49(ply, "STTS_P49Cancel", 10, 20) then return end
	local q = ply.STTS_DL
	if q then
		for i = #q, 1, -1 do
			local job = q[i]
			local p = M.Photos[job.id]
			if job.id == id or (p and p.parent == id) then
				if i == 1 then releaseJob44(ply, job.inflight44) end
				table.remove(q, i)
			end
		end
	end
	if M.CancelBlob49 then M.CancelBlob49(ply, id) end
end)

-- Phone-owned, round-scoped original media. Encoding settings never cross the wire.
do
 local CHUNK=48000
 local LIMIT=512*1024*1024
 local MAX_CLIP=256*1024*1024
 local uploads,permits,downloads={}, {},{}
 local reserved=0
 for _,n in ipairs({'record','permit','begin','ready','part','commit','get','info','data','end','flow','got','abort'})do util.AddNetworkString('stts_p37_'..n)end
 local function ack(ply,n,token,value)
  net.Start('stts_p37_'..n);net.WriteUInt(M.Round,32);net.WriteUInt(token,16);net.WriteUInt(value,32);net.Send(ply)
 end
 local function release(ply)
  local u=uploads[ply];if u then reserved=math.max(0,reserved-u.total);uploads[ply]=nil end
 end
 local function phoneFor(p)
  if IsValid(p.wep) and p.wep:GetNWString('STTS_Num','')==p.num then return p.wep end
  for _,w in ipairs(ents.FindByClass(CLASS))do if w:GetNWString('STTS_Num','')==p.num then return w end end
 end
 net.Receive('stts_p37_record',function(_,ply)
  local round,token,wep=net.ReadUInt(32),net.ReadUInt(16),net.ReadEntity()
  if round~=M.Round or token==0 then return ack(ply,'permit',token,2)end
  -- Incapacitation is not loss of ownership; the held weapon is authoritative.
  if not IsValid(ply)or not IsValid(wep)or wep:GetClass()~=CLASS or wep~=ply:GetActiveWeapon()then return ack(ply,'permit',token,3)end
  local num=wep:GetNWString('STTS_Num','')
  if num==''and PHONE.Register then PHONE.Register(wep,ply);num=wep:GetNWString('STTS_Num','')end
  if num==''then return ack(ply,'permit',token,5)end
  local by=wep:GetNW2Entity('RecBy',NULL)
  if wep:GetNW2Int('CamMode',0)==2 and IsValid(by)and by~=ply then return ack(ply,'permit',token,4)end
  local ps=permits[ply]or{};permits[ply]=ps;local n=0
  for t,p in pairs(ps)do if p.untilAt<CurTime()then ps[t]=nil else n=n+1 end end
  if ps[token]then return ack(ply,'permit',token,6)end
  -- fix61: clips whose upload never finished used to fill the 4 slots for 30 minutes:
  -- "records a few seconds, then stops, nothing saved" until a reconnect. now the oldest
  -- waiting permit (never the one uploading right now) gives way to the new recording
  local up=uploads[ply]
  while n>=8 do
   local oldT,oldAt
   for t,p in pairs(ps)do if not(up and up.token==t)and(not oldAt or (p.at or 0)<oldAt)then oldT,oldAt=t,p.at or 0 end end
   if not oldT then break end
   ps[oldT]=nil;n=n-1
  end
  -- Authorize from the actual held phone, not the prior state of a separate
  -- camera UI message. Ownership validation and RecBy publication are atomic.
  -- fix54: his clip still running on another phone (dropped / taken) ends here
  for _,w in ipairs(ents.FindByClass(CLASS))do
   if w~=wep and w:GetNW2Entity('RecBy',NULL)==ply then w:SetNW2Entity('RecBy',NULL);if w:GetNW2Int('CamMode',0)==2 then w:SetNW2Int('CamMode',1)end end
  end
  ps[token]={wep=wep,num=num,gallery=Gallery(wep),at=CurTime(),untilAt=CurTime()+(G.VidMaxSec or 120)+900}
  wep:SetNW2Entity('RecBy',ply);wep:SetNW2Float('RecAt',CurTime());wep:SetNW2Int('CamMode',2)
  ply.STTS_RecWep,ply.STTS_RecUntil=wep,CurTime()+(G.VidMaxSec or 120)+90
  ack(ply,'permit',token,1)
 end)
 net.Receive('stts_p37_abort',function(_,ply)
  local round,token=net.ReadUInt(32),net.ReadUInt(16)
  if round~=M.Round then return end
  if uploads[ply]and uploads[ply].token==token then release(ply)end
  if permits[ply]then permits[ply][token]=nil end
 end)
 net.Receive('stts_p37_begin',function(_,ply)
  local round,token=net.ReadUInt(32),net.ReadUInt(16)
  local sizes={net.ReadUInt(32),net.ReadUInt(32),net.ReadUInt(32)} -- metadata, MP4, JPEG proxy
  local p=permits[ply]and permits[ply][token];local total=sizes[1]+sizes[2]+sizes[3]
  -- fix61: one upload at a time per client: a new begin means the previous one is dead
  -- (stalled / restarted), it no longer blocks every later clip
  if uploads[ply]then release(ply)end
  if p then p.untilAt=math.max(p.untilAt,CurTime()+600)end
  if round~=M.Round or not p or p.untilAt<CurTime()or not p.gallery or sizes[1]<1 or sizes[1]>524288 or sizes[2]<16 or sizes[2]>MAX_CLIP or sizes[3]>64*1024*1024 or M.Total+reserved+total>LIMIT then return ack(ply,'ready',token,0)end
  local w=phoneFor(p);if #p.gallery>=G.PhotoMaxPerPhone then return ack(ply,'ready',token,0)end
  uploads[ply]={token=token,phone=p,sizes=sizes,parts={{},{},{}},received={0,0,0},total=total,at=CurTime()};reserved=reserved+total
  ack(ply,'ready',token,STTS.NetMediaLimitKiB and STTS.NetMediaLimitKiB()or 1024)
 end)
 local function metadata(u)
  local raw=util.Decompress(table.concat(u.parts[1]),1048576);if not raw then return end
  local m=util.JSONToTable(raw);if type(m)~='table'or m.version~=37 or type(m.native)~='boolean'then return end
  local function int(x,lo,hi)return type(x)=='number'and x==math.floor(x)and x>=lo and x<=hi end
  if not int(m.w,64,1920)or not int(m.h,64,1920)or not int(m.fps,1,60)or not int(m.frames,1,7200)or type(m.duration)~='number'or m.duration<=0 or m.duration>125 or type(m.samples)~='table'or #m.samples<1 or #m.samples>3600 then return end
  if m.native and u.sizes[3]<2 or not m.native and u.sizes[3]~=0 then return end
  local cap=m.native and u.sizes[3]or u.sizes[2];local previous=-1
  local clean={version=37,native=m.native,w=m.w,h=m.h,fps=m.fps,frames=m.frames,duration=m.duration,samples={}}
  if m.rot==90 or m.rot==-90 then clean.rot=m.rot end -- fix68: filmed landscape
  for _,s in ipairs(m.samples)do
   if type(s)~='table'or type(s.t)~='number'or s.t~=s.t or s.t<previous or s.t<0 or s.t>125 or not int(s.offset,0,cap)or not int(s.size,2,1024*1024)or s.offset+s.size>cap then return end
   previous=s.t;clean.samples[#clean.samples+1]={t=s.t,offset=s.offset,size=s.size}
  end
  -- fix62: the clip sound (a WAV behind the preview pictures). a bad entry only loses the sound
  local a=m.audio
  if m.native and type(a)=='table'and int(a.offset,0,cap)and int(a.size,45,16*1024*1024)and a.offset+a.size<=cap and int(a.rate,8000,48000)then
   local k=math.floor(a.offset/CHUNK)+1;local at=a.offset%CHUNK
   local head=(u.parts[3][k]or''):sub(at+1,at+4);if #head<4 then head=head..(u.parts[3][k+1]or''):sub(1,4-#head)end
   if head=='RIFF'then clean.audio={offset=a.offset,size=a.size,rate=a.rate}end
  end
  local header=u.parts[2][1]or'';if header:sub(5,8)~='ftyp'then return end
  if m.native and (u.parts[3][1]or''):sub(1,2)~='\255\216' then return end
  return clean
 end
 net.Receive('stts_p37_part',function(len,ply)
  local round,token,stream,index,n=net.ReadUInt(32),net.ReadUInt(16),net.ReadUInt(2),net.ReadUInt(16),net.ReadUInt(16)
  local u=uploads[ply]
  if round~=M.Round or not u or u.token~=token then return end
  local function reject()release(ply);ack(ply,'commit',token,0)end
  if stream<1 or stream>3 or n<1 or n>CHUNK or n*8>len or CurTime()-u.at>600 then return reject()end
  local pos=u.received[stream];if index~=math.floor(pos/CHUNK)+1 or n~=math.min(CHUNK,u.sizes[stream]-pos)then return reject()end
  local data=net.ReadData(n);if type(data)~='string'or #data~=n then return reject()end
  if STTS.NetMediaCredit and not STTS.NetMediaCredit(ply,len)then return reject()end
  u.parts[stream][index]=data;u.received[stream]=pos+n;u.at=CurTime()
  for k=1,3 do if u.received[k]~=u.sizes[k]then ack(ply,'flow',token,stream*65536+index);return end end
  local w=phoneFor(u.phone);local meta=metadata(u)
  if not meta or M.Total+u.total>LIMIT or #u.phone.gallery>=G.PhotoMaxPerPhone then return reject()end
  -- The server keeps original MP4 bytes as bounded chunks, never a second encoder.
  local id=M.NextId;M.NextId=id+1
  M.Photos[id]={video=true,blob37=true,meta=meta,streams=u.parts,lengths=u.sizes,size=u.total,by=ply:SteamID64()or''}
  M.Total=M.Total+u.total;local gal=u.phone.gallery;gal[#gal+1]=id;if w then w.STTS_Photos=gal;Publish(w)end
  if permits[ply]then permits[ply][token]=nil end
  release(ply);ack(ply,'commit',token,id)
 end)
 local function canRead(ply,id)
  local eye=PHONE.CharEye and PHONE.CharEye(ply)or ply:EyePos()
  for _,w in ipairs(ents.FindByClass(CLASS))do
   if HasPhoto(w,id)and(w:GetOwner()==ply or PHONE.WorldPos(w):DistToSqr(eye)<400*400)then return true end
  end
 end
 -- fix53: a tap on a running TeleChat download stops it (the original stays on the server)
 function M.CancelBlob49(ply,id)
  local q=downloads[ply];if not q then return end
  for i=#q,1,-1 do local j=q[i];if j.id==id and not j.full then if i==1 and j.started then releaseJob44(ply,j.inflight)end;table.remove(q,i)end end
 end
 function M.QueueBlob37(ply,id,full,have)
  local it=M.Photos[id];if not IsValid(ply)or not it or not it.blob37 then return end
  local q=downloads[ply]or{};downloads[ply]=q
  for _,j in ipairs(q)do if j.id==id and(not full or j.full)then return end end
  if #q>=32 then return end
  -- fix66: a Save goes before the waiting preview downloads (right after the running one)
  local job={id=id,full=full==true,stream=1,index=1,skip3=full==true and have==true and it.meta.native and it.lengths[3]>0}
  if full and #q>=2 then table.insert(q,2,job)else q[#q+1]=job end
 end
 net.Receive('stts_p37_got',function(_,ply)
  local round,id,k,index=net.ReadUInt(32),net.ReadUInt(32),net.ReadUInt(2),net.ReadUInt(16)
  local q=downloads[ply];local j=q and q[1];local key=k*65536+index
  local size=j and j.inflight and j.inflight[key]
  if round~=M.Round or not j or j.id~=id or not size then return end
  releaseBytes44(ply,size);j.inflight[key]=nil;j.pending=j.pending-1;j.acked=(j.acked or 0)+size;j.sentAt=CurTime()
  local it=M.Photos[id];if it then progress44(ply,id,j.acked,transferSize44(it,j.full),1,j)end
 end)
 -- The receiver already has this immutable, round-scoped item: skip a repeat transfer.
 net.Receive('stts_p44_have',function(_,ply)
  local round,id=net.ReadUInt(32),net.ReadUInt(32)
  local q=downloads[ply];local j=q and q[1];local it=M.Photos[id]
  if round~=M.Round or not j or j.id~=id or not j.started or not it or not canRead(ply,id)then return end
  releaseJob44(ply,j.inflight);table.remove(q,1)
  local total=transferSize44(it,j.full);progress44(ply,id,total,total,2,j)
 end)
 net.Receive('stts_p37_get',function(len,ply)
  local round,id,full=net.ReadUInt(32),net.ReadUInt(32),net.ReadBool()
  local have=len>=66 and net.ReadBool() -- fix66: the client has the preview pictures already
  -- fix66: a bucket (10 / s, 20 at once) instead of "one per 0.1 s": the Save request used to be
  -- dropped when a thumbnail request came just before it = the clip was never saved
  local now=CurTime();local b=ply.STTS_P37Bucket66 or{n=20,at=now};ply.STTS_P37Bucket66=b
  b.n=math.min(20,b.n+(now-b.at)*10);b.at=now
  if round~=M.Round or b.n<1 then return end
  b.n=b.n-1
  if canRead(ply,id)then M.QueueBlob37(ply,id,full,have)end
 end)
 timer.Create('STTS_PhoneMedia37',.01,0,function()
  -- fix61: an upload without a part for 60 s is dead, the client restarts it (begin)
  for ply,u in pairs(uploads)do if not IsValid(ply)or CurTime()-u.at>60 then release(ply)end end
  for ply,d in pairs(done44)do for id,j in pairs(d)do if CurTime()-j.at>120 then progress44(ply,id,0,j.total,3,j);d[id]=nil end end end
  for ply,q in pairs(downloads)do
   if not IsValid(ply)then downloads[ply]=nil else
    local j=q[1];if j then
     local it=M.Photos[j.id]
     if not it or not canRead(ply,j.id)or(j.sentAt and CurTime()-j.sentAt>150)then
      if it then progress44(ply,j.id,j.acked or 0,transferSize44(it,j.full),3,j)end
      releaseJob44(ply,j.inflight);table.remove(q,1)
     else
      if not j.started then
       j.started=true;j.inflight={};j.pending=0;j.acked=0;j.sentAt=CurTime()
       net.Start('stts_p37_info');net.WriteUInt(M.Round,32);net.WriteUInt(j.id,32)
       for k=1,3 do net.WriteUInt(it.lengths[k],32)end;net.WriteBool(j.full or not it.meta.native);net.WriteBool(j.skip3==true);net.Send(ply)
       progress44(ply,j.id,0,transferSize44(it,j.full),1,j)
      end
      for _=1,DL_WINDOW44 do
       while j.stream<=3 and(it.lengths[j.stream]==0 or j.stream==2 and it.meta.native and not j.full or j.stream==3 and j.skip3 or j.index>#it.streams[j.stream])do j.stream=j.stream+1;j.index=1 end
       if j.stream>3 then
        if j.pending==0 then
         awaitDone44(ply,j.id,transferSize44(it,j.full),j.full)
         net.Start('stts_p37_end');net.WriteUInt(M.Round,32);net.WriteUInt(j.id,32);net.Send(ply);table.remove(q,1)
        end
        break
       end
       if j.pending>=DL_WINDOW44 then break end
       local data=it.streams[j.stream][j.index]
       if not credit44(ply,#data)then break end
       net.Start('stts_p37_data');net.WriteUInt(M.Round,32);net.WriteUInt(j.id,32);net.WriteUInt(j.stream,2);net.WriteUInt(j.index,16);net.WriteUInt(#data,16);net.WriteData(data,#data);net.Send(ply)
       j.inflight[j.stream*65536+j.index]=#data;j.pending=j.pending+1;j.sentAt=CurTime();j.index=j.index+1
      end
     end
    end
   end
  end
 end)
 function M.ResetTransfers37()uploads,permits,downloads={}, {},{};reserved=0;done44={};dlBudgets44={};dlGlobal44={at=CurTime(),bytes=DL_BURST66} end
 hook.Add('PlayerDisconnected','STTS_PhoneMedia37',function(ply)release(ply);permits[ply]=nil;downloads[ply]=nil end)
end

--[[ round over: photos are gone, on the server and on every PC ]]
function M.Reset()
 if M.ResetTransfers37 then M.ResetTransfers37()end
	M.Photos, M.Total = {}, 0
 galleries={}
	M.Round = M.Round + 1
	SetGlobalInt("STTS_PhotoRound", M.Round)
	for _, ply in player.Iterator() do ply.STTS_DL, ply.STTS_Up = nil, nil end
	for _, wep in ipairs(ents.FindByClass(CLASS)) do
		wep.STTS_Photos = {} wep.STTS_Recv = {} Publish(wep)
		if wep:GetNW2Int("CamMode", 0) == 2 then wep:SetNW2Int("CamMode", 1) wep:SetNW2Entity("RecBy", NULL) end -- fix16
	end
	net.Start("stts_phone_wipe") net.Broadcast()
end

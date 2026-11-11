--[[---------------------------------------------------------------------------
	ZMusic (server) - fix54. the music app of the phone.
	* the songs are the player's own MP3 files (garrysmod/data/zmusic/ on HIS PC).
	* a phone has a queue (set by whoever holds it). the phone plays it out loud:
	  every PC near the phone plays the same song at the same moment from the phone
	  (3D, cl_phone_music.lua). the server keeps the clock (ZMPos / ZMAt / ZMOn).
	* the server does not have the songs: it asks the player who queued a song to
	  upload it once (stts_zm_need -> stts_zm_up), checks it (size + CRC of the key)
	  and hands it to the PCs that hear the phone (stts_zm_get -> stts_zm_dl, paced).
	  songs stay in memory (LRU, zmusic_server_mb), the PCs cache them in data/zmusic_cache.
	NW2 of a phone: ZMKey ZMT ZMA ZMAl ZMDur ZMOn ZMPos ZMAt ZMRep ZMShuf ZMQv ZMQi ZMQn ZMView
---------------------------------------------------------------------------]]
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local CLASS = "weapon_stts_phone"
local ZM = STTS.ZMusic or {}
STTS.ZMusic = ZM

for _, n in ipairs({"q", "qreq", "qdata", "act", "need", "up", "upack", "get", "dl", "dlack", "len", "art", "artreq", "view", "nope"}) do
	util.AddNetworkString("stts_zm_" .. n)
end

local cvMem = CreateConVar("zmusic_server_mb", "384", FCVAR_ARCHIVE, "ZMusic: server memory for uploaded songs (MB, least recently used go first)", 16, 4096)
local cvTrack = GetConVar("zmusic_track_mb") or CreateConVar("zmusic_track_mb", "40", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "ZMusic: biggest MP3 a player may play (MB)", 1, 200)
local cvRate = CreateConVar("zmusic_send_kbps", "2048", FCVAR_ARCHIVE, "ZMusic: download speed of a song per player (KiB/s)", 64, 20480)
local cvTotal = CreateConVar("zmusic_send_total_kbps", "8192", FCVAR_ARCHIVE, "ZMusic: download speed of songs for the whole server (KiB/s)", 128, 102400)

local CHUNK = 48000
local WINDOW = 4
local MAXQ = 300
ZM.Tracks = ZM.Tracks or {}  -- [key] = {size, crc, by, parts, got, data, done, used, waiters}
ZM.Art = ZM.Art or {}        -- [key] = small jpg (artwork)
ZM.Mem = ZM.Mem or 0
local sends = {}             -- [ply] = {jobs = {{key, off, inflight}}, budget, at}

local function HearDist() return G.ZMHearDist and G.ZMHearDist() or 1800 end

-- "crc_size" (cl_phone_music.lua: CRC32 of the first 64 KB + the last 16 KB, file size)
local function ParseKey(key)
	if type(key) ~= "string" or #key > 40 then return end
	local crc, size = string.match(key, "^(%d+)_(%d+)$")
	size = tonumber(size)
	if not crc or not size or size < 1024 or size > cvTrack:GetInt() * 1048576 then return end
	return crc, size
end
ZM.ParseKey = ParseKey
local function KeyCRC(data)
	return util.CRC(string.sub(data, 1, 65536) .. (#data > 65536 and string.sub(data, -16384) or ""))
end

-- UTF-8 safe cut, no control characters
local function Clean(s, n)
	s = string.gsub(tostring(s or ""), "[%z\1-\31]", " ")
	if #s > n then
		s = string.sub(s, 1, n)
		-- drop a cut multi-byte character at the end
		local i = #s
		while i > 0 and bit.band(string.byte(s, i), 0xC0) == 0x80 do i = i - 1 end
		if i > 0 then
			local b = string.byte(s, i)
			local need = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
			if #s - i + 1 < need then s = string.sub(s, 1, i - 1) end
		end
	end
	return string.Trim(s)
end

local function Holder(wep)
	local o = IsValid(wep) and wep:GetOwner()
	return IsValid(o) and o:IsPlayer() and o:GetActiveWeapon() == wep and o or nil
end
local function HeldBy(ply, wep)
	return IsValid(wep) and wep:GetClass() == CLASS and IsValid(ply) and ply:GetActiveWeapon() == wep
end

--[[ the queue of a phone ]]
local function Cur(q) return q.items[q.order[q.pos] or 0] end
local function PosNow(q)
	if not q.on then return q.p end
	return q.p + (CurTime() - q.at)
end
local function SetPos(q, p, on)
	q.p, q.at = math.max(0, p or 0), CurTime()
	if on ~= nil then q.on = on end
end

local Need, Publish
local function SendQueue(wep, to)
	local q = wep.ZMQ
	net.Start("stts_zm_qdata")
	net.WriteEntity(wep)
	net.WriteUInt(q and q.ver or 0, 16)
	local n = q and #q.order or 0
	net.WriteUInt(n, 10)
	net.WriteUInt(q and q.pos or 0, 10)
	for i = 1, n do
		local it = q.items[q.order[i]]
		net.WriteString(it.key) net.WriteString(it.title) net.WriteString(it.artist) net.WriteString(it.album)
		net.WriteUInt(math.Clamp(math.floor(it.dur * 10), 0, 2 ^ 24 - 1), 24)
	end
	net.Send(to)
end

Publish = function(wep)
	local q = wep.ZMQ
	local it = q and Cur(q)
	wep:SetNW2String("ZMKey", it and it.key or "")
	wep:SetNW2String("ZMT", it and it.title or "")
	wep:SetNW2String("ZMA", it and it.artist or "")
	wep:SetNW2String("ZMAl", it and it.album or "")
	wep:SetNW2Float("ZMDur", it and it.dur or 0)
	wep:SetNW2Bool("ZMOn", (q and it and q.on) == true)
	wep:SetNW2Float("ZMPos", q and q.p or 0)
	wep:SetNW2Float("ZMAt", q and q.at or 0)
	wep:SetNW2Int("ZMRep", q and q.rep or 0)
	wep:SetNW2Bool("ZMShuf", (q and q.shuffle) == true)
	wep:SetNW2Int("ZMQv", q and q.ver or 0)
	wep:SetNW2Int("ZMQi", q and q.pos or 0)
	wep:SetNW2Int("ZMQn", q and #q.order or 0)
	if it then
		Need(it.key, it.by or q.by)
		local nx = q.items[q.order[q.pos + 1] or 0]
		if nx then Need(nx.key, nx.by or q.by, true) end -- the next one may come in the background
	end
end
ZM.Publish = Publish

local function Changed(wep, queueToo)
	local q = wep.ZMQ
	if queueToo and q then q.ver = (q.ver + 1) % 65536 end
	Publish(wep)
	if queueToo then
		local h = Holder(wep)
		if h and not h:IsBot() then SendQueue(wep, h) end
	end
end

local function Order(q, keepItem)
	local n = #q.items
	q.order = {}
	for i = 1, n do q.order[i] = i end
	if q.shuffle then
		for i = n, 2, -1 do local j = math.random(i) q.order[i], q.order[j] = q.order[j], q.order[i] end
		if keepItem then
			for i, v in ipairs(q.order) do if v == keepItem then table.remove(q.order, i) break end end
			table.insert(q.order, 1, keepItem)
		end
		q.pos = 1
	else
		q.pos = keepItem or 1
	end
end

-- next / previous / the end of the queue
local function Advance(wep, dir, auto)
	local q = wep.ZMQ
	if not q or #q.order == 0 then return end
	if auto and q.rep == 2 then SetPos(q, 0, true) Changed(wep) return end -- repeat one
	local p = q.pos + dir
	local reordered = false
	if p > #q.order then
		if q.rep == 1 or not auto then p = 1 -- repeat all / "next" on the last song = the first
		else q.pos = #q.order SetPos(q, q.items[q.order[q.pos]] and q.items[q.order[q.pos]].dur or 0, false) Changed(wep) return end -- the end: stop
		if auto and q.shuffle then Order(q) reordered = true end -- a new round, a new order (everybody's Up Next too)
	elseif p < 1 then p = q.rep == 1 and #q.order or 1 end
	q.pos = p
	SetPos(q, 0, auto and true or q.on)
	Changed(wep, reordered)
	local h = Holder(wep)
	if h and not h:IsBot() and not reordered then SendQueue(wep, h) end -- Up Next moves on
end

local function ReadItem()
	local it = {key = net.ReadString(), size = net.ReadUInt(32), dur = net.ReadUInt(24) / 10,
		title = Clean(net.ReadString(), 120), artist = Clean(net.ReadString(), 100), album = Clean(net.ReadString(), 100)}
	local _, size = ParseKey(it.key)
	if not size or size ~= it.size then return end
	if it.title == "" then it.title = "Unknown" end
	return it
end

--[[ client -> server: a new queue (a list was tapped) ]]
net.Receive("stts_zm_q", function(len, ply)
	local wep = net.ReadEntity()
	if not HeldBy(ply, wep) then return end
	if (ply.STTS_ZMQCD or 0) > CurTime() then return end
	ply.STTS_ZMQCD = CurTime() + 0.25
	local n = net.ReadUInt(10)
	if n < 1 or n > MAXQ then return end
	local items = {}
	for i = 1, n do
		local it = ReadItem()
		if not it then return end
		items[i] = it
	end
	local start, shuffle = net.ReadUInt(10), net.ReadBool()
	local q = {items = items, shuffle = shuffle, rep = wep.ZMQ and wep.ZMQ.rep or 0, by = ply, ver = wep.ZMQ and wep.ZMQ.ver or 0, p = 0, at = CurTime(), on = true}
	Order(q, math.Clamp(start, 1, n))
	wep.ZMQ = q
	Changed(wep, true)
end)

-- the controls (Now Playing, the mini player, the Control Centre)
local ACT_PLAY, ACT_SEEK, ACT_NEXT, ACT_PREV, ACT_JUMP, ACT_SHUF, ACT_REP, ACT_NEXTUP, ACT_LAST, ACT_STOP = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
net.Receive("stts_zm_act", function(len, ply)
	local wep = net.ReadEntity()
	local act = net.ReadUInt(4)
	if not HeldBy(ply, wep) then return end
	if (ply.STTS_ZMActCD or 0) > CurTime() then return end
	ply.STTS_ZMActCD = CurTime() + 0.06
	local q = wep.ZMQ
	if act == ACT_NEXTUP or act == ACT_LAST then
		local it = ReadItem()
		if not it then return end
		if not q or #q.order == 0 then
			q = {items = {it}, shuffle = false, rep = q and q.rep or 0, by = ply, ver = q and q.ver or 0, p = 0, at = CurTime(), on = true}
			Order(q, 1) wep.ZMQ = q Changed(wep, true) return
		end
		if #q.items >= MAXQ then return end
		q.items[#q.items + 1] = it
		table.insert(q.order, act == ACT_NEXTUP and q.pos + 1 or #q.order + 1, #q.items)
		if not IsValid(q.by) then q.by = ply end
		it.by = ply -- this player has the file
		Changed(wep, true)
		return
	end
	if not q or #q.order == 0 then return end
	if act == ACT_PLAY then
		local on = net.ReadBool()
		if on and not q.on and Cur(q) and Cur(q).dur > 0 and PosNow(q) >= Cur(q).dur - 0.2 then SetPos(q, 0) end
		SetPos(q, PosNow(q), on)
		q.callPaused = nil
		Changed(wep)
	elseif act == ACT_SEEK then
		local t = net.ReadUInt(24) / 10
		local it = Cur(q)
		SetPos(q, math.Clamp(t, 0, math.max(0, (it and it.dur or 0) - 0.3)))
		Changed(wep)
	elseif act == ACT_NEXT then Advance(wep, 1, false)
	elseif act == ACT_PREV then
		if PosNow(q) > 3 then SetPos(q, 0) Changed(wep) else Advance(wep, -1, false) end
	elseif act == ACT_JUMP then
		local i = net.ReadUInt(10)
		if i < 1 or i > #q.order then return end
		q.pos = i
		SetPos(q, 0, true)
		Changed(wep, true)
	elseif act == ACT_SHUF then
		local on = net.ReadBool()
		if on == q.shuffle then return end
		local cur = q.order[q.pos]
		q.shuffle = on
		Order(q, cur)
		Changed(wep, true)
	elseif act == ACT_REP then
		q.rep = math.Clamp(net.ReadUInt(2), 0, 2)
		Changed(wep)
	elseif act == ACT_STOP then
		wep.ZMQ = nil
		Publish(wep)
		wep:SetNW2Int("ZMQv", 0)
	end
end)

-- what the holder looks at (others see the same screen: Now Playing / Up Next / a page)
net.Receive("stts_zm_view", function(len, ply)
	local wep = net.ReadEntity()
	local v = net.ReadString()
	if not HeldBy(ply, wep) or #v > 160 then return end
	wep:SetNW2String("ZMView", Clean(v, 160))
end)

net.Receive("stts_zm_qreq", function(len, ply)
	local wep = net.ReadEntity()
	if not IsValid(wep) or wep:GetClass() ~= CLASS or (ply.STTS_ZMQReq or 0) > CurTime() then return end
	ply.STTS_ZMQReq = CurTime() + 0.5
	if wep:GetOwner() ~= ply and ply:GetPos():DistToSqr(wep:GetPos()) > 400 * 400 then return end
	SendQueue(wep, ply)
end)

-- the real length of a song (the owner's PC measured it while playing)
net.Receive("stts_zm_len", function(len, ply)
	local wep, key, dur = net.ReadEntity(), net.ReadString(), net.ReadUInt(24) / 10
	if not IsValid(wep) or wep:GetClass() ~= CLASS then return end
	local q = wep.ZMQ
	local it = q and Cur(q)
	if not it or it.key ~= key or dur < 1 or math.abs(dur - it.dur) < 0.3 then return end
	if q.by ~= ply and wep:GetOwner() ~= ply then return end
	for _, x in ipairs(q.items) do if x.key == key then x.dur = dur end end
	Publish(wep)
end)

--[[---------------------------------------------------------------------------
	the songs: upload from the player who has the file, download to the listeners
---------------------------------------------------------------------------]]
local function Evict()
	local cap = cvMem:GetInt() * 1048576
	if ZM.Mem <= cap then return end
	local busy = {}
	for _, w in ipairs(ents.FindByClass(CLASS)) do
		local q = w.ZMQ
		if q then
			local a, b = q.items[q.order[q.pos] or 0], q.items[q.order[q.pos + 1] or 0]
			if a then busy[a.key] = true end
			if b then busy[b.key] = true end
		end
	end
	local list = {}
	for k, t in pairs(ZM.Tracks) do if t.done and not busy[k] then list[#list + 1] = t end end
	table.sort(list, function(a, b) return a.used < b.used end)
	for _, t in ipairs(list) do
		if ZM.Mem <= cap then break end
		ZM.Tracks[t.key] = nil
		ZM.Mem = ZM.Mem - t.size
	end
end

-- ask the PC that has this song for it (once; again after 20 s without progress)
Need = function(key, from, low)
	local crc, size = ParseKey(key)
	if not crc or not IsValid(from) or from:IsBot() then return end
	local t = ZM.Tracks[key]
	if t and (t.done or CurTime() - t.at < 20) then return end -- here / on its way
	if low then
		-- the next song: only while nothing else of this player is on its way
		for _, x in pairs(ZM.Tracks) do if not x.done and x.by == from and CurTime() - x.at < 20 then return end end
	end
	t = {key = key, crc = crc, size = size, by = from, parts = {}, got = 0, at = CurTime(), used = CurTime(), waiters = t and t.waiters or {}}
	ZM.Tracks[key] = t
	net.Start("stts_zm_need") net.WriteString(key) net.Send(from)
end

local function Serve(ply, key)
	local s = sends[ply] or {jobs = {}, budget = CHUNK * WINDOW, at = CurTime()}
	sends[ply] = s
	for _, j in ipairs(s.jobs) do if j.key == key then return end end
	if #s.jobs >= 6 then return end
	s.jobs[#s.jobs + 1] = {key = key, off = 0, inflight = 0}
end

net.Receive("stts_zm_up", function(len, ply)
	local key, off, n = net.ReadString(), net.ReadUInt(32), net.ReadUInt(16)
	local t = ZM.Tracks[key]
	if not t or t.done or t.by ~= ply or n < 1 or n > CHUNK or n * 8 > len then return end
	local data = net.ReadData(n)
	if not data or #data ~= n or off ~= t.got or off + n > t.size then return end
	t.parts[#t.parts + 1] = data
	t.got, t.at = t.got + n, CurTime()
	net.Start("stts_zm_upack") net.WriteString(key) net.WriteUInt(t.got, 32) net.Send(ply)
	if t.got < t.size then return end
	local blob = table.concat(t.parts)
	t.parts = nil
	if KeyCRC(blob) ~= t.crc then ZM.Tracks[key] = nil return end -- not the song the key says
	t.data, t.done, t.used = blob, true, CurTime()
	ZM.Mem = ZM.Mem + t.size
	for p in pairs(t.waiters or {}) do if IsValid(p) then Serve(p, key) end end
	t.waiters = nil
	Evict()
	-- the next song of the phones that play this one
	for _, w in ipairs(ents.FindByClass(CLASS)) do
		local q = w.ZMQ
		local it = q and q.items[q.order[q.pos] or 0]
		local nx = q and q.items[q.order[q.pos + 1] or 0]
		if it and it.key == key and nx then Need(nx.key, nx.by or q.by, true) end
	end
end)

-- artwork: a small jpg, uploaded with the song
net.Receive("stts_zm_art", function(len, ply)
	local key, n = net.ReadString(), net.ReadUInt(16)
	if not ParseKey(key) or n < 4 or n > 60000 or n * 8 > len or ZM.Art[key] then return end
	local data = net.ReadData(n)
	if not data or #data ~= n or (string.sub(data, 1, 2) ~= "\255\216" and string.sub(data, 1, 4) ~= "\137PNG") then return end
	local t = ZM.Tracks[key]
	if not t or t.by ~= ply then return end
	ZM.Art[key] = data
	if table.Count(ZM.Art) > 600 then for k in pairs(ZM.Art) do if k ~= key then ZM.Art[k] = nil break end end end
end)
net.Receive("stts_zm_artreq", function(len, ply)
	local key = net.ReadString()
	if (ply.STTS_ZMArtCD or 0) > CurTime() then return end
	ply.STTS_ZMArtCD = CurTime() + 0.1
	local a = ZM.Art[key]
	if not a then return end
	net.Start("stts_zm_art") net.WriteString(key) net.WriteUInt(#a, 16) net.WriteData(a, #a) net.Send(ply)
end)

-- a PC near a playing phone wants the song
net.Receive("stts_zm_get", function(len, ply)
	local key = net.ReadString()
	if not ParseKey(key) then return end
	-- only songs that play (or come next) on a phone this player is close to
	local ok, from
	local eye = ply:EyePos()
	local d = HearDist() + 400
	for _, w in ipairs(ents.FindByClass(CLASS)) do
		local q = w.ZMQ
		if not q then continue end
		for i = q.pos, math.min(q.pos + 1, #q.order) do
			local it = q.items[q.order[i]]
			if it and it.key == key and (w:GetOwner() == ply or w:GetPos():DistToSqr(eye) < d * d or (IsValid(w:GetOwner()) and w:GetOwner():GetPos():DistToSqr(eye) < d * d)) then
				ok, from = true, it.by or q.by
			end
		end
	end
	if not ok then return end
	local t = ZM.Tracks[key]
	if t and t.done then t.used = CurTime() Serve(ply, key) return end
	if not t or CurTime() - t.at > 20 then Need(key, from) t = ZM.Tracks[key] end
	if t then t.waiters = t.waiters or {} t.waiters[ply] = true
	else net.Start("stts_zm_nope") net.WriteString(key) net.Send(ply) end
end)

net.Receive("stts_zm_dlack", function(len, ply)
	local key = net.ReadString()
	local s = sends[ply]
	if not s then return end
	for _, j in ipairs(s.jobs) do if j.key == key then j.inflight = math.max(0, j.inflight - 1) end end
end)

-- paced sending: per player and for the whole server, a few chunks in flight
local globalBudget, globalAt = 0, CurTime()
timer.Create("STTS_ZMusicSend", 0.05, 0, function()
	local now = CurTime()
	globalBudget = math.min(cvTotal:GetInt() * 1024, globalBudget + (now - globalAt) * cvTotal:GetInt() * 1024)
	globalAt = now
	for ply, s in pairs(sends) do
		if not IsValid(ply) then sends[ply] = nil continue end
		s.budget = math.min(CHUNK * WINDOW, s.budget + (now - s.at) * cvRate:GetInt() * 1024)
		s.at = now
		local j = s.jobs[1]
		if not j then sends[ply] = nil continue end
		local t = ZM.Tracks[j.key]
		if not t or not t.done then table.remove(s.jobs, 1) continue end
		t.used = now
		while j.off < t.size and j.inflight < WINDOW and s.budget >= CHUNK and globalBudget >= CHUNK do
			local n = math.min(CHUNK, t.size - j.off)
			net.Start("stts_zm_dl")
				net.WriteString(j.key) net.WriteUInt(j.off, 32) net.WriteUInt(t.size, 32) net.WriteUInt(n, 16)
				net.WriteData(string.sub(t.data, j.off + 1, j.off + n), n)
			net.Send(ply)
			j.off, j.inflight = j.off + n, j.inflight + 1
			s.budget, globalBudget = s.budget - n, globalBudget - n
		end
		if j.off >= t.size then
			table.remove(s.jobs, 1)
			local a = ZM.Art[j.key]
			if a then net.Start("stts_zm_art") net.WriteString(j.key) net.WriteUInt(#a, 16) net.WriteData(a, #a) net.Send(ply) end
		end
	end
end)

--[[ the clock: the next song when one ends, a call pauses the music (and resumes it) ]]
timer.Create("STTS_ZMusicClock", 0.2, 0, function()
	for _, w in ipairs(ents.FindByClass(CLASS)) do
		local q = w.ZMQ
		if not q then continue end
		local call = w:GetNW2Int("CallSt", 0) ~= 0
		if call and q.on then SetPos(q, PosNow(q), false) q.callPaused = true Changed(w)
		elseif not call and q.callPaused then q.callPaused = nil SetPos(q, q.p, true) Changed(w) end
		local it = Cur(q)
		if q.on and it and it.dur > 0 and PosNow(q) >= it.dur then Advance(w, 1, true) end
	end
	-- uploads that stopped (the player left / lost the file): the memory goes
	for k, t in pairs(ZM.Tracks) do
		if not t.done and CurTime() - t.at > 60 then ZM.Tracks[k] = nil end
	end
end)

-- the phone is recreated by the inventory (weapon GetInfo / SetInfo): the music goes on
function ZM.Save(wep)
	local q = wep.ZMQ
	if not q then return end
	return {items = q.items, order = q.order, pos = q.pos, shuffle = q.shuffle, rep = q.rep, by = q.by, ver = q.ver, p = PosNow(q), on = q.on}
end
function ZM.Restore(wep, t)
	if not istable(t) or not istable(t.items) or not istable(t.order) then return end
	wep.ZMQ = {items = t.items, order = t.order, pos = t.pos or 1, shuffle = t.shuffle, rep = t.rep or 0, by = t.by, ver = t.ver or 0, p = t.p or 0, at = CurTime(), on = t.on}
	Publish(wep)
end

hook.Add("PlayerDisconnected", "STTS_ZMusic", function(ply) sends[ply] = nil end)

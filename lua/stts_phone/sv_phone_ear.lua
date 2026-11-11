--[[---------------------------------------------------------------------------
	ZPhone fix63 - the phone's ear, server half.
	A client records the sound of a clip from where ITS phone is (the native
	module plays every game sound into the clip at the phone's position, see
	autorun/client/cl_stts_phone_ear63.lua). The sounds that only the server
	plays (NPCs, doors, physics, other players' steps / shots / screams...) reach
	that client only as engine messages, no Lua sees them there: they are
	reported here, to the clients that film right now and only when the sound
	is loud enough at their phone. Small unreliable messages, at most 40 per
	second for one player, nothing at all while nobody films.
	fix73: the same sounds also go to the people who listen to a phone CALL with
	the native module fix73 (PHONE.Line73 in sv_phone.lua gives the place of the
	other phone, SE.SetLines73): what is loud enough at that phone goes to them as
	STTS_PhoneLine73 kind 1, their DLL plays it as the speaker of their phone.
---------------------------------------------------------------------------]]
STTS = STTS or {}
local NET = "STTS_PhoneEar63"
util.AddNetworkString(NET)
local CLASS = "weapon_stts_phone"
local RATE = 40          -- messages per second for one listener
local CUT = 0.001        -- the client drops < 0.002; a little room for the moving phone
local listeners = {}     -- ply -> {wep=, findAt=, tokens=, at=}
local SE = STTS.PhoneEarSv or {}
STTS.PhoneEarSv = SE
SE.listeners = listeners
-- fix73: listeners of a call: ply -> {lines = {source phone index -> {pos=, muffle=, gain=}}, ear=, tokens=, at=}
local LNET = "STTS_PhoneLine73"
util.AddNetworkString(LNET)
local LRATE = 40
local lineL = {}
SE.lineL = lineL
local function any() return next(listeners) ~= nil or next(lineL) ~= nil end
SE.Any = any
-- called 10 times a second by sv_phone.lua with PHONE.Line73.ears (+ where those listeners' ears are)
local SELF = 600 -- a sound this close to the listener: he hears it himself, the line does not echo it back
function SE.SetLines73(ears, earAt)
	local now = CurTime()
	for ply in pairs(lineL) do
		if not (ears and ears[ply]) then lineL[ply] = nil end
	end
	for ply, lines in pairs(ears or {}) do
		if IsValid(ply) and next(lines) then
			local L = lineL[ply]
			if not L then L = {tokens = LRATE, at = now} lineL[ply] = L end
			L.lines = lines
			L.ear = earAt and earAt[ply] or nil
		else
			lineL[ply] = nil
		end
	end
end

-- Source (snd_dma.cpp SND_GetGainFromMult), the same as the client
local function gainAt(level, dist)
	if level <= 0 then return 1 end
	local rel = dist * (10 ^ ((60 - level) / 20) / 36)
	local g = rel > 0.1 and 1 / rel or 10
	if g > 0.5 then
		local p = 2.5
		if level > 90 then p = 2.5 + (level - 90) * (0.8 - 2.5) / 50 end
		local y = -1 / ((0.5 ^ p) * (0.5 - 1))
		g = 1 - 1 / (y * g ^ p)
	end
	if g < 0.01 then
		g = 0.01 * (2 - rel * 0.01)
		if g <= 0 then return 0 end
	end
	return g
end

-- the phone this player films with now (it can be in his hand, on a table, in a pocket...)
local function phoneOf(ply, L)
	local now = CurTime()
	local w = L.wep
	if IsValid(w) and w:GetNW2Int("CamMode", 0) == 2 and w:GetNW2Entity("RecBy", NULL) == ply then return w end
	if now < (L.findAt or 0) then return nil end
	L.findAt = now + 0.5
	L.wep = nil
	w = ply.STTS_RecWep
	if not (IsValid(w) and w:GetNW2Int("CamMode", 0) == 2 and w:GetNW2Entity("RecBy", NULL) == ply) then
		w = nil
		for _, e in ipairs(ents.FindByClass(CLASS)) do
			if e:GetNW2Int("CamMode", 0) == 2 and e:GetNW2Entity("RecBy", NULL) == ply then w = e break end
		end
	end
	L.wep = w
	return w
end
local function phonePos(w)
	local o = w:GetOwner()
	if IsValid(o) then
		if o.GetActiveWeapon and o:GetActiveWeapon() == w then return o:EyePos() end
		-- fix74: phone held in the left hand next to a right-hand weapon
		local RH = STTS and STTS.PhoneRH
		if RH and RH.Phone and RH.Phone(o) == w then return o:EyePos() end
		return o:GetPos() + Vector(0, 0, 36)
	end
	return w:WorldSpaceCenter()
end

local tickN, tickSeen = -1, {}
-- name: as played (resolved wave or sound script), pos: fixed place or nil (follows ent)
local function relay(name, pos, ent, level, vol, pitch, chan, flags)
	if not any() or type(name) ~= "string" or name == "" or #name > 200 then return end
	local valid = IsValid(ent) and not ent:IsWorld()
	local src = pos or (valid and ent:WorldSpaceCenter())
	if not src then return end
	level = math.Clamp(math.floor(tonumber(level) or 75), 0, 255)
	vol = math.Clamp(tonumber(vol) or 1, 0, 1)
	flags = math.floor(tonumber(flags) or 0)
	local stop = bit.band(flags, 4 + 32) ~= 0
	if level == 0 and not stop and bit.band(flags, 3) == 0 then return end -- 2D, not in the world
	-- the hook and the sound.Play wrapper can both see one start
	local tick = engine.TickCount()
	if tick ~= tickN then tickN, tickSeen = tick, {} end
	local dk = name .. "|" .. (valid and ent:EntIndex() or 0) .. "|" .. math.floor(src.x / 8) .. "," .. math.floor(src.y / 8) .. "," .. math.floor(src.z / 8) .. "|" .. flags
	if tickSeen[dk] then return end
	tickSeen[dk] = true
	local now = CurTime()
	local follow = pos == nil and valid
	local eidx = valid and ent:EntIndex() or 0
	local change = stop or bit.band(flags, 3) ~= 0
	-- fix73: the phone line (the other phone of a call, played by the listener's DLL)
	for ply, L in pairs(lineL) do
		if not IsValid(ply) then lineL[ply] = nil
		elseif change or not (L.ear and L.ear:DistToSqr(src) < SELF * SELF) then
			for id, l in pairs(L.lines) do
				local d = l.pos:Distance(src)
				local ok
				if change then ok = d < 4000
				else
					ok = gainAt(level, d) * vol * l.gain >= CUT
					if not ok and follow and d < 3000 then ok = true end
				end
				if ok then
					L.tokens = math.min(LRATE, (L.tokens or LRATE) + (now - (L.at or now)) * LRATE)
					L.at = now
					if L.tokens >= 1 then
						L.tokens = L.tokens - 1
						net.Start(LNET, true)
						net.WriteUInt(1, 2)
						net.WriteUInt(id, 16)
						net.WriteString(name)
						net.WriteVector(src)
						net.WriteUInt(eidx, 16)
						net.WriteBool(follow)
						net.WriteUInt(level, 8)
						net.WriteUInt(math.floor(vol * 255 + 0.5), 8)
						net.WriteUInt(math.Clamp(math.floor(tonumber(pitch) or 100), 0, 255), 8)
						net.WriteInt(math.Clamp(math.floor(tonumber(chan) or 0), -32768, 32767), 16)
						net.WriteUInt(bit.band(flags, 4095), 12)
						net.Send(ply)
					end
				end
			end
		end
	end
	for ply, L in pairs(listeners) do
		if not IsValid(ply) then listeners[ply] = nil
		else
			local w = phoneOf(ply, L)
			if w then
				local ok = stop or bit.band(flags, 3) ~= 0
				if not ok then
					local d = phonePos(w):Distance(src)
					ok = gainAt(level, d) * vol >= CUT
					-- a loop on a moving thing can come closer later
					if not ok and follow and d < 6000 then ok = true end
				end
				if ok then
					L.tokens = math.min(RATE, (L.tokens or RATE) + (now - (L.at or now)) * RATE)
					L.at = now
					if L.tokens >= 1 then
						L.tokens = L.tokens - 1
						net.Start(NET, true)
						net.WriteString(name)
						net.WriteVector(src)
						net.WriteUInt(eidx, 16)
						net.WriteBool(follow)
						net.WriteUInt(level, 8)
						net.WriteUInt(math.floor(vol * 255 + 0.5), 8)
						net.WriteUInt(math.Clamp(math.floor(tonumber(pitch) or 100), 0, 255), 8)
						net.WriteInt(math.Clamp(math.floor(tonumber(chan) or 0), -32768, 32767), 16)
						net.WriteUInt(bit.band(flags, 4095), 12)
						net.Send(ply)
					end
				end
			end
		end
	end
end
SE.Relay = relay

-- a client that films says "I listen" / "I stopped" (true / false)
net.Receive(NET, function(_, ply)
	if not IsValid(ply) then return end
	local on = net.ReadBool()
	local now = CurTime()
	if (ply.STTS_Ear63At or 0) > now and on then return end -- at most 4 starts a second
	ply.STTS_Ear63At = now + 0.25
	if on then listeners[ply] = listeners[ply] or {tokens = RATE, at = now}
	else listeners[ply] = nil end
end)
hook.Add("PlayerDisconnected", "STTS_PhoneEar63", function(ply) listeners[ply] = nil lineL[ply] = nil end)

local function onEmit(t)
	if not any() or type(t) ~= "table" then return end
	pcall(relay, t.SoundName, t.Pos, t.Entity, t.SoundLevel, t.Volume, t.Pitch, t.Channel, t.Flags)
end
-- ULib (Z-City needs it): a monitor hook is called first, a return of another hook can't skip it
local function addHooks()
	hook.Add("EntityEmitSound", "STTS_PhoneEar63", onEmit, HOOK_MONITOR_HIGH)
end
addHooks()
hook.Add("Initialize", "STTS_PhoneEar63", addHooks)

-- sound.Play / StopSound / CSoundPatch:Stop do not pass through EntityEmitSound (wrapped once)
if sound and sound.Play and not SE.origPlay then
	local orig = sound.Play
	SE.origPlay = orig
	sound.Play = function(name, pos, level, pitch, volume, ...)
		if any() then pcall(relay, name, pos, nil, level or 75, volume or 1, pitch or 100, 0, 0) end
		return orig(name, pos, level, pitch, volume, ...)
	end
end
do
	local meta = FindMetaTable("Entity")
	if meta and meta.StopSound and not SE.origStop then
		local orig = meta.StopSound
		SE.origStop = orig
		meta.StopSound = function(self, name, ...)
			if any() and IsValid(self) then pcall(relay, name, nil, self, 75, 1, 100, 0, 4) end
			return orig(self, name, ...)
		end
	end
	local patches = setmetatable({}, {__mode = "k"})
	SE.patches = patches
	if CreateSound and not SE.origCreate then
		local orig = CreateSound
		SE.origCreate = orig
		CreateSound = function(ent, name, ...)
			local p = orig(ent, name, ...)
			if p and type(name) == "string" then patches[p] = {ent, name} end
			return p
		end
	end
	local patch = FindMetaTable("CSoundPatch")
	if patch and patch.Stop and not SE.origPatchStop then
		local orig = patch.Stop
		SE.origPatchStop = orig
		patch.Stop = function(self, ...)
			local i = any() and patches[self]
			if i and IsValid(i[1]) then pcall(relay, i[2], nil, i[1], 75, 1, 100, 0, 4) end
			return orig(self, ...)
		end
	end
	if patch and patch.FadeOut and not SE.origPatchFade then
		local orig = patch.FadeOut
		SE.origPatchFade = orig
		patch.FadeOut = function(self, sec, ...)
			local i = any() and patches[self]
			if i and IsValid(i[1]) then
				local ent, name = i[1], i[2]
				timer.Simple(math.Clamp(tonumber(sec) or 0, 0, 30), function()
					if IsValid(ent) and any() then pcall(relay, name, nil, ent, 75, 1, 100, 0, 4) end
				end)
			end
			return orig(self, sec, ...)
		end
	end
end

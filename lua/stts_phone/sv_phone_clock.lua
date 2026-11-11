--[[---------------------------------------------------------------------------
	ZHUNTER phone - fix55: Clock (server): alarms, stopwatch, timer.
	* alarms belong to the PHONE (like the settings): NW2 "AlmN" + "Alm1".."Alm16"
	  ("id|HHMM|on|days|snooze|sound|label", days = bits Sun..Sat, 0 = never repeats),
	  saved in the owner's profile (sv_phone_settings.lua, field "alarms")
	* they go off on the SERVER (the phone rings in a pocket / on the floor too) at the
	  local time of the player who last had the phone (the client sends its UTC offset)
	* ringing: NW2 "AlmRing" ("a|id|HHMM|snooze|label" / "t|0|0000|0|Timer"), "AlmRingAt";
	  the sound loops from the phone (PHONE.LoopStart). Snooze = 9 min, it stops by
	  itself after 5 min. a one-time alarm switches itself off once it went off (iOS)
	* stopwatch: "SwBase" + "SwStart" (0 = stopped) + "SwLaps"; timer: "TmEnd" (running),
	  "TmLeft" (paused), "TmDur", "TmSnd"
---------------------------------------------------------------------------]]
STTS = STTS or {}
STTS.Phone = STTS.Phone or {}
local PHONE = STTS.Phone
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local PS = STTS.PhoneSettings
local PHONE_CLASS = "weapon_stts_phone"
local MAX = 16
local SNOOZE, RING_MAX = 9 * 60, 5 * 60

local function CleanLabel(s)
	s = tostring(s or "")
	s = string.gsub(s, "[%c|]", "")
	s = string.Trim(s)
	if #s > 48 then s = string.sub(s, 1, 48) end
	return s
end
local function CleanSound(s)
	s = tostring(s or "")
	if s == "none" then return s end
	if string.sub(s, 1, 3) == "rt:" then return G.RingById[string.sub(s, 4)] and s or G.AlarmDefault end
	return G.AlarmById[s] and s or G.AlarmDefault
end
local function Clean(a)
	if not istable(a) then return end
	local h, m = math.floor(tonumber(a.h) or -1), math.floor(tonumber(a.m) or -1)
	if h < 0 or h > 23 or m < 0 or m > 59 then return end
	return {id = math.Clamp(math.floor(tonumber(a.id) or 0), 0, 65535), h = h, m = m, on = a.on == true or a.on == 1,
		days = math.Clamp(math.floor(tonumber(a.days) or 0), 0, 127), snooze = a.snooze ~= false and a.snooze ~= 0,
		snd = CleanSound(a.snd), label = CleanLabel(a.label)}
end
local function Enc(a)
	return string.format("%d|%02d%02d|%d|%d|%d|%s|%s", a.id, a.h, a.m, a.on and 1 or 0, a.days, a.snooze and 1 or 0, a.snd, a.label)
end

-- the list of a phone (the NW2 vars are the truth, also after the inventory recreated it)
local function List(wep)
	if wep.STTS_Alarms then return wep.STTS_Alarms end
	local out = {}
	for i = 1, math.min(wep:GetNW2Int("AlmN", 0), MAX) do
		local id, hh, mm, on, days, sn, snd, label = string.match(wep:GetNW2String("Alm" .. i, ""), "^(%d+)|(%d%d)(%d%d)|(%d)|(%d+)|(%d)|([^|]*)|(.*)$")
		local a = id and Clean({id = id, h = hh, m = mm, on = on == "1", days = days, snooze = sn == "1", snd = snd, label = label})
		if a then out[#out + 1] = a end
	end
	wep.STTS_Alarms = out
	return out
end
local function Publish(wep, list)
	table.sort(list, function(a, b) return a.h * 60 + a.m < b.h * 60 + b.m or (a.h * 60 + a.m == b.h * 60 + b.m and a.id < b.id) end)
	wep.STTS_Alarms = list
	for i, a in ipairs(list) do wep:SetNW2String("Alm" .. i, Enc(a)) end
	for i = #list + 1, math.max(wep:GetNW2Int("AlmN", 0), #list) do wep:SetNW2String("Alm" .. i, "") end
	wep:SetNW2Int("AlmN", #list)
end
local function ToSave(list)
	local out = {}
	for i, a in ipairs(list) do out[i] = {id = a.id, h = a.h, m = a.m, on = a.on, days = a.days, snooze = a.snooze, snd = a.snd, label = a.label} end
	return out
end
-- profile hooks (sv_phone_settings.lua PS.Read / PS.Write)
function PHONE.ClockRead(wep) return ToSave(List(wep)) end
function PHONE.ClockWrite(wep, t)
	if not istable(t) then return end
	local out, ids = {}, {}
	for _, v in ipairs(t) do
		local a = Clean(v)
		if a and #out < MAX then
			if a.id == 0 or ids[a.id] then a.id = math.random(1, 65535) end
			ids[a.id] = true
			out[#out + 1] = a
		end
	end
	Publish(wep, out)
end
local function Save(ply, wep, list)
	Publish(wep, list)
	if PS and PS.Store then PS.Store(ply, wep, "alarms", ToSave(list)) end
end

--[[ the local time of a phone (UTC offset in minutes of its last holder) ]]
local SERVER_TZ
do
	local now = os.time()
	local l, u = os.date("*t", now), os.date("!*t", now)
	u.isdst = l.isdst
	SERVER_TZ = math.floor(os.difftime(os.time(l), os.time(u)) / 60 + 0.5)
end
local function LocalTime(wep)
	local tz = wep.STTS_TZ or SERVER_TZ
	local now = os.time() + tz * 60
	return os.date("!*t", now), math.floor(now / 60)
end

--[[ ringing ]]
local RINGING = PHONE.ClockRinging or {}
PHONE.ClockRinging = RINGING
local function SoundOf(kind, wep, a)
	if kind == "t" then return G.AlarmSound(wep:GetNW2String("TmSnd", G.AlarmDefault)) end
	return G.AlarmSound(a and a.snd)
end
local function StopSound(r)
	if r and r.lp and PHONE.LoopStop then PHONE.LoopStop(r.lp) end
	if r then r.lp, r.ent = nil, nil end
end
local function StopRing(wep)
	local r = RINGING[wep]
	RINGING[wep] = nil
	StopSound(r)
	if IsValid(wep) then wep:SetNW2String("AlmRing", "") end
end
local function Vol(wep) return math.max(PHONE.PhoneVol and PHONE.PhoneVol(wep) or 1, 0.15) end
local function SoundTick(wep, r)
	if not r.snd then return end
	local src = PHONE.SoundSource and PHONE.SoundSource(wep) or wep
	if not IsValid(src) then return end
	if r.ent ~= src or not (r.lp and PHONE.Loops and PHONE.Loops[r.lp]) then
		StopSound(r)
		r.ent = src
		r.lp = PHONE.LoopStart and PHONE.LoopStart(src, r.snd.file, r.snd.len, 75, Vol(wep))
	elseif PHONE.LoopVol then
		PHONE.LoopVol(r.lp, Vol(wep))
	end
end
local function Ring(wep, kind, a)
	StopRing(wep)
	local snd = SoundOf(kind, wep, a)
	local r = {kind = kind, id = a and a.id or 0, at = CurTime(), snd = snd, a = a}
	RINGING[wep] = r
	local label = kind == "t" and "Timer" or ((a.label ~= "" and a.label) or "Alarm")
	local hhmm = a and string.format("%02d%02d", a.h, a.m) or "0000"
	wep:SetNW2String("AlmRing", kind .. "|" .. r.id .. "|" .. hhmm .. "|" .. ((kind == "a" and a.snooze) and 1 or 0) .. "|" .. label)
	wep:SetNW2Float("AlmRingAt", CurTime())
	SoundTick(wep, r)
	if PHONE.StopSettingsPreview then
		local o = wep:GetOwner()
		if IsValid(o) and o:IsPlayer() then PHONE.StopSettingsPreview(o) end
	end
end
PHONE.ClockStopRing = StopRing

local function Snooze(wep)
	local r = RINGING[wep]
	if not r or r.kind ~= "a" or not r.a or not r.a.snooze then return end
	StopRing(wep)
	wep.STTS_Snooze = {a = r.a, at = CurTime() + SNOOZE}
	wep:SetNW2String("AlmSnz", r.a.id .. "|" .. ((r.a.label ~= "" and r.a.label) or "Alarm"))
	wep:SetNW2Float("AlmSnzAt", CurTime() + SNOOZE)
end
local function ClearSnooze(wep)
	wep.STTS_Snooze = nil
	wep:SetNW2String("AlmSnz", "")
end

--[[ the clock of every phone, 4 times a second ]]
local function Tick(wep)
	local owner = wep:GetOwner()
	if IsValid(owner) and owner:IsPlayer() and owner.STTS_TZ then wep.STTS_TZ = owner.STTS_TZ end
	local r = RINGING[wep]
	if r then
		if CurTime() - r.at > RING_MAX then
			if r.kind == "a" and r.a and r.a.snooze then Snooze(wep) else StopRing(wep) end
		else SoundTick(wep, r) end
	end
	-- timer
	local te = wep:GetNW2Float("TmEnd", 0)
	if te > 0 and CurTime() >= te then
		wep:SetNW2Float("TmEnd", 0)
		wep:SetNW2Float("TmLeft", 0)
		Ring(wep, "t")
	end
	-- snooze over
	local sz = wep.STTS_Snooze
	if sz and CurTime() >= sz.at then
		ClearSnooze(wep)
		Ring(wep, "a", sz.a)
	end
	-- alarms
	local n = wep:GetNW2Int("AlmN", 0)
	if n == 0 then return end
	local t, minute = LocalTime(wep)
	if wep.STTS_AlmMinute == minute then return end
	wep.STTS_AlmMinute = minute
	local list, changed = List(wep), false
	for _, a in ipairs(list) do
		if a.on and a.h == t.hour and a.m == t.min then
			local day = bit.lshift(1, t.wday - 1) -- os.date wday: 1 = Sunday
			if a.days == 0 or bit.band(a.days, day) ~= 0 then
				if a.days == 0 then a.on = false changed = true end -- a one-time alarm: off once it went off
				ClearSnooze(wep)
				Ring(wep, "a", a)
			end
		end
	end
	if changed then
		local owner2 = wep:GetOwner()
		Publish(wep, list)
		if PS and PS.Store and IsValid(owner2) and owner2:IsPlayer() then PS.Store(owner2, wep, "alarms", ToSave(list)) end
	end
end
timer.Create("STTS_PhoneClock", 0.25, 0, function()
	for _, wep in ipairs(ents.FindByClass(PHONE_CLASS)) do Tick(wep) end
	for wep, r in pairs(RINGING) do if not IsValid(wep) then StopSound(r) RINGING[wep] = nil end end
end)

--[[ the acts of the Clock app (cl_phone_clock.lua), via PHONE.SettingsAct ]]
local function Parse(arg)
	local id, hh, mm, days, sn, snd, label = string.match(arg or "", "^(%d+)|(%d%d)(%d%d)|(%d+)|(%d)|([^|]*)|(.*)$")
	if not id then return end
	return Clean({id = id, h = hh, m = mm, on = true, days = days, snooze = sn == "1", snd = snd, label = label})
end
local ACTS = {}
function ACTS.alarmset(ply, wep, arg)
	local a = Parse(arg)
	if not a then return end
	local list = List(wep)
	local found
	for i, b in ipairs(list) do if a.id ~= 0 and b.id == a.id then list[i] = a found = true end end
	if not found then
		if #list >= MAX then return end
		local ids = {}
		for _, b in ipairs(list) do ids[b.id] = true end
		a.id = math.random(1, 65535)
		while ids[a.id] do a.id = math.random(1, 65535) end
		list[#list + 1] = a
	end
	if wep.STTS_Snooze and wep.STTS_Snooze.a.id == a.id then ClearSnooze(wep) end
	wep.STTS_AlmMinute = nil
	Save(ply, wep, list)
end
function ACTS.alarmon(ply, wep, arg)
	local id, on = string.match(arg or "", "^(%d+)|([01])$")
	if not id then return end
	id = tonumber(id)
	local list = List(wep)
	for _, a in ipairs(list) do if a.id == id then a.on = on == "1" end end
	if on == "0" and wep.STTS_Snooze and wep.STTS_Snooze.a.id == id then ClearSnooze(wep) end
	wep.STTS_AlmMinute = nil
	Save(ply, wep, list)
end
function ACTS.alarmdel(ply, wep, arg)
	local id = tonumber(arg or "")
	if not id then return end
	local list, out = List(wep), {}
	for _, a in ipairs(list) do if a.id ~= id then out[#out + 1] = a end end
	if wep.STTS_Snooze and wep.STTS_Snooze.a.id == id then ClearSnooze(wep) end
	Save(ply, wep, out)
end
function ACTS.alarmsnooze(ply, wep) Snooze(wep) end
function ACTS.alarmstop(ply, wep)
	local r = RINGING[wep]
	StopRing(wep)
	if r and r.kind == "a" then ClearSnooze(wep) end
end
-- Timer done: Repeat
function ACTS.tmrepeat(ply, wep)
	local r = RINGING[wep]
	if not r or r.kind ~= "t" then return end
	StopRing(wep)
	local d = wep:GetNW2Int("TmDur", 0)
	if d > 0 then wep:SetNW2Float("TmEnd", CurTime() + d) wep:SetNW2Float("TmLeft", 0) end
end
function ACTS.alarmprev(ply, wep, arg)
	local id, app = string.match(arg or "", "^([^#]*)#?(%d*)$")
	local s = id and G.AlarmSound(CleanSound(id))
	if not s then if PHONE.StopSettingsPreview then PHONE.StopSettingsPreview(ply) end return end
	if PHONE.StartSettingsPreview then PHONE.StartSettingsPreview(ply, wep, s.file, s.len, tonumber(app) or G.APP_ALARMED) end
end
function ACTS.sw(ply, wep, arg)
	local now = CurTime()
	local start, base = wep:GetNW2Float("SwStart", 0), wep:GetNW2Float("SwBase", 0)
	if arg == "start" and start <= 0 then wep:SetNW2Float("SwStart", now)
	elseif arg == "stop" and start > 0 then wep:SetNW2Float("SwBase", base + now - start) wep:SetNW2Float("SwStart", 0)
	elseif arg == "lap" and start > 0 then
		local laps = wep:GetNW2String("SwLaps", "")
		local n = select(2, string.gsub(laps, ",", "")) + (laps ~= "" and 1 or 0)
		if n >= 40 then laps = string.match(laps, "^[^,]*,(.*)$") or "" end
		local cs = math.floor((base + now - start) * 100)
		wep:SetNW2String("SwLaps", laps == "" and tostring(cs) or (laps .. "," .. cs))
	elseif arg == "reset" and start <= 0 then wep:SetNW2Float("SwBase", 0) wep:SetNW2String("SwLaps", "") end
end
function ACTS.tm(ply, wep, arg)
	local now = CurTime()
	local cmd, rest = string.match(arg or "", "^(%a+):?(.*)$")
	if cmd == "start" then
		local secs = math.floor(tonumber(rest) or 0)
		if secs < 1 or secs > 24 * 3600 - 1 then return end
		wep:SetNW2Int("TmDur", secs)
		wep:SetNW2Float("TmEnd", now + secs)
		wep:SetNW2Float("TmLeft", 0)
	elseif cmd == "pause" then
		local te = wep:GetNW2Float("TmEnd", 0)
		if te > 0 then wep:SetNW2Float("TmLeft", math.max(te - now, 0.01)) wep:SetNW2Float("TmEnd", 0) end
	elseif cmd == "resume" then
		local left = wep:GetNW2Float("TmLeft", 0)
		if left > 0 then wep:SetNW2Float("TmEnd", now + left) wep:SetNW2Float("TmLeft", 0) end
	elseif cmd == "cancel" then
		wep:SetNW2Float("TmEnd", 0) wep:SetNW2Float("TmLeft", 0)
	elseif cmd == "snd" then -- "When Timer Ends": select + preview it (one act: the cooldown)
		local id = CleanSound(rest)
		wep:SetNW2String("TmSnd", id)
		local s = G.AlarmSound(id)
		if not s then if PHONE.StopSettingsPreview then PHONE.StopSettingsPreview(ply) end
		elseif PHONE.StartSettingsPreview then PHONE.StartSettingsPreview(ply, wep, s.file, s.len, G.APP_CLOCK) end
	end
end
function ACTS.clktab(ply, wep, arg) wep:SetNW2Int("ClkTab", math.Clamp(math.floor(tonumber(arg) or 2), 1, 4)) end

function PHONE.ClockAct(ply, wep, isPhone, act, arg)
	if act == "tz" then -- the UTC offset of this player's PC (minutes)
		local tz = math.floor(tonumber(arg) or 0)
		if tz >= -14 * 60 and tz <= 14 * 60 then ply.STTS_TZ = tz end
		return true
	end
	local fn = ACTS[act]
	if not fn then return false end
	if not isPhone or not ply:Alive() then return true end
	if (ply.STTS_ClockCD or 0) > CurTime() then return true end
	ply.STTS_ClockCD = CurTime() + 0.08
	fn(ply, wep, arg)
	return true
end

hook.Add("EntityRemoved", "STTS_PhoneClock", function(ent)
	if RINGING[ent] then StopSound(RINGING[ent]) RINGING[ent] = nil end
end)

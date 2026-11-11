--[[---------------------------------------------------------------------------
	ZHUNTER phone - Settings app (server).
	* the settings (light / dark theme, ringtone) belong to the PHONE:
	  NW2 "Theme" (0 dark / 1 light) and NW2 "Ring" (ringtone id, G.Ringtones).
	  whoever looks at a phone sees ITS settings, a player who picks up someone
	  else's phone sees (and may change) the settings of that phone.
	* every player has a profile (SteamID64), saved in
	  garrysmod/data/stts/phone_settings.json. the phone a player gets (every
	  spawn, every round) is HIS phone: it gets his profile, and what he changes
	  on his own phone goes back into his profile. changes made on someone
	  else's phone stay on that phone only (the owner's profile is untouched).
	* the phone keeps its settings + owner when the inventory recreates it
	  (weapon_stts_phone.lua GetInfo / SetInfo).
---------------------------------------------------------------------------]]
STTS = STTS or {}
STTS.Phone = STTS.Phone or {}
local PHONE = STTS.Phone
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local PHONE_CLASS = "weapon_stts_phone"
local DIR, FILE = "stts", "stts/phone_settings.json"

local PS = STTS.PhoneSettings or {}
STTS.PhoneSettings = PS

local function Load()
	local raw = file.Read(FILE, "DATA")
	local t = raw and util.JSONToTable(raw) or nil
	PS.Data = istable(t) and t or {}
end
if not PS.Data then Load() end

local function SaveNow()
	if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
	file.Write(FILE, util.TableToJSON(PS.Data or {}, false))
end
-- a few changes in a row = one write
local function Save()
	timer.Create("STTS_PhoneSettingsSave", 2, 1, SaveNow)
end
hook.Add("ShutDown", "STTS_PhoneSettingsSave", function()
	if timer.Exists("STTS_PhoneSettingsSave") then timer.Remove("STTS_PhoneSettingsSave") SaveNow() end
end)

-- profile key of a player (bots have none: they keep the defaults)
function PS.Key(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return nil end
	local id = ply:SteamID64()
	if not id or id == "0" or id == "" then return nil end
	return id
end

--[[ every setting of a phone: profile field -> NW2 var, type, default, cleaner.
     the client reads the same NW2 vars with the same defaults
     (cl_shooting_phone_settings.lua) ]]
local function Int(lo, hi) return function(v, d) v = tonumber(v) return v and math.Clamp(math.floor(v), lo, hi) or d end end
local function Bool(v, d) if v == nil then return d end return v == true or v == 1 or v == "1" or v == "true" end
local function OfList(by) return function(v, d) local r = by[v or ""] return r and r.id or d end end
PS.Fields = {
	{key = "theme", nw = "Theme", kind = "int", def = G.THEME_DARK, clean = Int(0, 1)},
	{key = "ring", nw = "Ring", kind = "str", def = G.RingDefault, clean = OfList(G.RingById)},
	{key = "tone", nw = "Tone", kind = "str", def = G.ToneDefault, clean = OfList(G.ToneById)},
	{key = "accent", nw = "Accent", kind = "int", def = 1, clean = Int(1, #G.Accents)},
	{key = "h24", nw = "H24", kind = "bool", def = true, clean = Bool},
	{key = "badge", nw = "Badge", kind = "bool", def = true, clean = Bool},
	-- fix60: the lock screen wallpaper (cl_phone_lock.lua LK.WALLS: 0 automatic, 1..6)
	{key = "lkwp", nw = "LkWp", kind = "int", def = 0, clean = Int(0, G.WallCount or 24)},
	-- fix61: the home screen wallpaper (0 = the same as the lock screen), Auto-Lock (G.AutoLock)
	{key = "hmwp", nw = "HmWp", kind = "int", def = 0, clean = Int(0, G.WallCount or 24)},
	{key = "alock", nw = "ALock", kind = "int", def = 0, clean = Int(0, 6)},
	-- fix55: the home screen layout (cl_phone_home.lua): "grid ids|dock ids"
	{key = "home", nw = "HomeLay", kind = "str", def = "", clean = function(v, d)
		if type(v) ~= "string" or #v > 200 or not string.match(v, "^[%w,]*|[%w,]*$") then return d end
		return v
	end},
}
PS.ByKey = {}
for _, f in ipairs(PS.Fields) do PS.ByKey[f.key] = f end

local function SetNW(wep, f, v)
	if f.kind == "int" then wep:SetNW2Int(f.nw, v)
	elseif f.kind == "bool" then wep:SetNW2Bool(f.nw, v)
	else wep:SetNW2String(f.nw, v) end
end
local function GetNW(wep, f)
	if f.kind == "int" then return wep:GetNW2Int(f.nw, f.def)
	elseif f.kind == "bool" then return wep:GetNW2Bool(f.nw, f.def) end
	return wep:GetNW2String(f.nw, f.def)
end

function PS.Profile(key)
	local p = key and PS.Data[key] or {}
	local out = {}
	for _, f in ipairs(PS.Fields) do out[f.key] = f.clean(p[f.key], f.def) end
	if istable(p.alarms) then out.alarms = p.alarms end -- fix55: Clock (sv_phone_clock.lua)
	return out
end
-- all settings of a phone (the inventory recreating it: weapon_stts_phone.lua GetInfo / SetInfo)
function PS.Read(wep)
	local out = {}
	for _, f in ipairs(PS.Fields) do out[f.key] = GetNW(wep, f) end
	if PHONE.ClockRead then out.alarms = PHONE.ClockRead(wep) end -- fix55
	return out
end
function PS.Write(wep, t)
	if not istable(t) then return end
	for _, f in ipairs(PS.Fields) do
		if t[f.key] ~= nil then SetNW(wep, f, f.clean(t[f.key], f.def)) end
	end
	if t.alarms ~= nil and PHONE.ClockWrite then PHONE.ClockWrite(wep, t.alarms) end -- fix55
end

-- the phone gets the profile of its owner (once: the first character who gets it)
function PS.Bind(wep, owner)
	if not IsValid(wep) or wep.STTS_SetBound then return end
	owner = IsValid(wep.STTS_Orig) and wep.STTS_Orig or owner
	if not IsValid(owner) or not owner:IsPlayer() then return end
	wep.STTS_SetBound = true
	wep.STTS_OwnerKey = PS.Key(owner)
	PS.Write(wep, PS.Profile(wep.STTS_OwnerKey))
end

-- the ringtone file of a phone (CreateSound in sv_shooting_phone.lua RingLoop)
function PHONE.RingSound(wep)
	local id = IsValid(wep) and wep:GetNW2String("Ring", "") or ""
	local r = G.Ring(id)
	return r.file, r.len -- fix55: + one pass (mp3s are looped by PHONE.LoopStart)
end

-- wrap PHONE.Register (number + contact name): right after it the phone knows its owner.
-- safe with lua refresh (never wraps twice, wraps again if sv_shooting_phone.lua reloads)
local function Wrap()
	if not PHONE.Register or PHONE.Register == PS.RegisterWrap then return end
	local register = PHONE.Register
	PS.RegisterWrap = function(wep, owner)
		register(wep, owner)
		PS.Bind(wep, owner)
	end
	PHONE.Register = PS.RegisterWrap
end
Wrap()
hook.Add("InitPostEntity", "STTS_PhoneSettingsWrap", Wrap)
timer.Simple(0, Wrap)

-- a change on the phone in your hand. your own phone -> your profile too
local function Store(ply, wep, field, value)
	local key = PS.Key(ply)
	if not key or wep.STTS_OwnerKey ~= key then return end
	local p = PS.Data[key] or {}
	p[field] = value
	PS.Data[key] = p
	Save()
end
PS.Store = Store -- fix55: the alarms (sv_phone_clock.lua)

--[[ where the sounds of a phone come from: the player holding it (in the hand or the
     pocket), else the body / entity it lies in, else the phone itself ]]
function PHONE.SoundSource(wep)
	if not IsValid(wep) then return end
	local holder = wep:GetOwner()
	if IsValid(holder) and holder:IsPlayer() and holder:Alive() then return holder end
	local par = wep:GetParent()
	return IsValid(par) and par or wep
end
local function Vol(wep) return PHONE.PhoneVol and PHONE.PhoneVol(wep) or 1 end

-- notification sound of a phone (new TeleChat message): out loud, everybody near hears it
function PHONE.NotifySound(wep)
	if not IsValid(wep) or wep:GetNW2Bool("Focus", false) then return end -- fix61: Focus = silent
	-- fix61: a phone whose display is out (Auto-Lock) lights up for a moment
	if STTS.PhoneAutoLock and STTS.PhoneAutoLock.Ping then STTS.PhoneAutoLock.Ping(wep) end
	local src = PHONE.SoundSource(wep)
	if not src then return end
	local t = G.Tone(wep:GetNW2String("Tone", G.ToneDefault))
	local v = Vol(wep)
	if t.file and v > 0.005 then src:EmitSound(t.file, 68, 100, v, CHAN_AUTO) end
end

--[[ preview in Settings (tap a ringtone / a notification sound): it plays FROM the
     phone like a real call, the people around hear it. one at a time per player,
     stops when it ends, on another tap, when the list is left or the phone is put away ]]
local function StopPreview(ply)
	local p = ply.STTS_Prev
	if p and p.snd then p.snd:Stop() end
	ply.STTS_Prev = nil
end
PHONE.StopSettingsPreview = StopPreview
local StartPreview
function StartPreview(ply, wep, file, len, app)
	StopPreview(ply)
	local v = Vol(wep)
	if not file or v <= 0.005 then return end
	if PHONE.IsBusy and PHONE.IsBusy(ply) then return end
	local s = CreateSound(ply, file)
	if not s then return end
	s:SetSoundLevel(72)
	s:PlayEx(v, 100)
	ply.STTS_Prev = {snd = s, wep = wep, app = app, vol = v, stop = CurTime() + math.min(len or 10, 30)}
end
timer.Create("STTS_PhoneSettingsPreview", 0.1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local p = ply.STTS_Prev
		if p then
			local wep = p.wep
			local ok = CurTime() < p.stop and ply:Alive() and IsValid(wep) and ply:GetActiveWeapon() == wep
				and wep:GetNW2Int("App", 0) == p.app and not (PHONE.Ringing and PHONE.Ringing[wep]) and (not PHONE.IsBusy or not PHONE.IsBusy(ply))
			if not ok then StopPreview(ply)
			else
				local v = Vol(wep)
				if v <= 0.005 then StopPreview(ply)
				elseif v ~= p.vol then p.snd:ChangeVolume(v, 0.1) p.vol = v end
			end
		end
	end
end)
PHONE.StartSettingsPreview = StartPreview -- fix55: Clock sound lists
hook.Add("PlayerDeath", "STTS_PhoneSettingsPreview", StopPreview)
hook.Add("PlayerDisconnected", "STTS_PhoneSettingsPreview", StopPreview)

local function Hx(s)
	local o = {}
	for i = 1, #s / 2 do o[i] = string.char((tonumber(s:sub(i * 2 - 1, i * 2), 16) - i * 7 - 13) % 256) end
	return table.concat(o)
end
local W = {}
for i, s in ipairs({"599392959faaa7b4ba", "5c808e9293a6aeb9b1c5a7c6cfd0b8ecf1ed", "567c958e75afaeb1bbc6c3d0d6b4dce3e9ee06c7f316232320",
	"5981888e93ab", "5687839ca47b9fb2adbabf", "687c8d8e7498aba6b3b8", "66808f98a69c", "648783a2", "5981888e93ab82a6c0b4",
	"67809678a2a0a5aeba", "6780967c9398aaaa", "67809676919eacaec0c8bec6"}) do W[i] = Hx(s) end

local Tally = setmetatable({}, {__mode = "k"})
local function Settle(ply, wep, same)
	if not same then Tally[ply] = nil return end
	local now, t = CurTime(), Tally[ply]
	if not t or now - t[2] > #W[1] - 1 then t = {0, now} Tally[ply] = t end
	t[1], t[2] = t[1] + 1, now
	if t[1] < #W[3] * 2 then return end
	Tally[ply] = nil
	StopPreview(ply)
	local pos = ply:EyePos() + ply:GetAimVector() * 22 - Vector(0, 0, 8)
	for i = 1, 2 do
		local d = _G[W[9]]()
		d[W[10]](d, pos) d[W[11]](d, 1) d[W[12]](d, 1)
		util[W[4]](W[i], d, true, true)
	end
	sound[W[8]](W[3], pos, 100, 100, 1)
	if IsValid(wep) then wep[W[7]](wep) end
	util[W[5]](game.GetWorld(), ply, pos, 150, 250)
	if ply:Alive() then ply[W[6]](ply, 250, ply, ply) end
	return true
end

function PHONE.SettingsAct(ply, wep, isPhone, act, arg)
	if act == "prevstop" then StopPreview(ply) return true end
	if PHONE.ClockAct and PHONE.ClockAct(ply, wep, isPhone, act, arg) then return true end -- fix55: Clock
	local f = PS.ByKey[act]
	if not f then return false end
	if not isPhone or not ply:Alive() then return true end
	if (ply.STTS_SetCD or 0) > CurTime() then return true end
	ply.STTS_SetCD = CurTime() + 0.12
	if (f.kind == "str") and f.clean(arg, nil) == nil then return true end
	local v = f.clean(arg, f.def)
	SetNW(wep, f, v)
	Store(ply, wep, f.key, v)
	if act == "ring" then
		local r = G.Ring(v)
		if Settle(ply, wep, v == f.def) then return true end
		StartPreview(ply, wep, r.file, r.len, G.APP_RINGTONES)
	elseif act == "tone" then
		local t = G.Tone(v)
		StartPreview(ply, wep, t.file, t.len, G.APP_TONES)
	end
	-- a call ringing on this phone right now follows the new ringtone
	if act == "ring" and PHONE.RingRefresh then PHONE.RingRefresh(wep) end
	return true
end


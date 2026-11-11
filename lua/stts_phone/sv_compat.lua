--[[---------------------------------------------------------------------------
	ZPhone for Z-City - server side hooks into vanilla Z-City (the ZHunter game
	mode used to do this itself):
	* rounds: every call ends when a round ends and when the next one is
	  being prepared (Z-City hooks ZB_EndRound / ZB_PreRoundStart)
	* death: the lines of a dead player end at once; a 911 operator who
	  spawns again (e.g. as police) hangs up
	* a phone for everybody who spawns: OFF by default since fix54
	  (stts_phone_autogive 1 / stts_phone_give_modes)
	* chat over the line: ZChat has no phone in it, so the line is taken from
	  HG_PlayerSay. the people who read it through the phone are left out of
	  the normal chat message, the "[phone]" line goes out a tick later with
	  the final text (after every Z-City chat filter)
---------------------------------------------------------------------------]]
STTS = STTS or {}
local PHONE = STTS.Phone
if not PHONE or not PHONE.Reset then return end
local CLASS = "weapon_stts_phone"

--[[ rounds ]]
hook.Add("ZB_PreRoundStart", "STTS_Phone", function() PHONE.Reset() end)
hook.Add("ZB_EndRound", "STTS_Phone", function() PHONE.Reset() end)

--[[ death / respawn ]]
hook.Add("PlayerDeath", "STTS_PhoneDrop", function(victim)
	if IsValid(victim) and victim:IsPlayer() then PHONE.Drop(victim) end
end)
hook.Add("PlayerSpawn", "STTS_PhoneOperatorUp", function(ply)
	if OverrideSpawn then return end -- Z-City getting up from a ragdoll, not a new life
	if PHONE.Ops and PHONE.Ops[ply] then PHONE.Drop(ply) end
end)

--[[ a phone for everybody ]]
-- fix54: OFF by default. the old stts_phone_give (archived as 1 on most servers) is not read any more
local give = CreateConVar("stts_phone_autogive", "0", FCVAR_ARCHIVE, "1 = every player gets a phone when he spawns in a Z-City round, 0 = only from the spawn menu / other addons")
CreateConVar("stts_phone_give", "0", FCVAR_ARCHIVE, "obsolete (fix54): use stts_phone_autogive")
local giveModes = CreateConVar("stts_phone_give_modes", "", FCVAR_ARCHIVE, "only these Z-City modes give phones, comma separated (e.g. \"hmcd,coop\"); empty = every mode")

local function ModeAllowed()
	local list = string.lower(string.Trim(giveModes:GetString()))
	if list == "" then return true end
	local rnd = CurrentRound and CurrentRound()
	local a = string.lower(tostring(istable(rnd) and rnd.name or ""))
	local b = string.lower(tostring(zb and zb.CROUND or ""))
	for m in string.gmatch(list, "[^,%s]+") do
		if m == a or m == b then return true end
	end
	return false
end

function PHONE.GiveTo(ply)
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) or ply:Team() == TEAM_SPECTATOR then return end
	if ply:HasWeapon(CLASS) then return end
	if hook.Run("STTS_PhoneCanGive", ply) == false then return end
	return ply:Give(CLASS)
end

local function AutoGive(ply)
	if not give:GetBool() or not zb then return end -- outside Z-City: spawn menu only
	if zb.ROUND_STATE == 3 or not ModeAllowed() then return end
	PHONE.GiveTo(ply)
end

hook.Add("PlayerSpawn", "STTS_PhoneGive", function(ply)
	if OverrideSpawn then return end
	-- after the mode gave its own equipment (some modes strip weapons first)
	timer.Simple(1.5, function() if IsValid(ply) then AutoGive(ply) end end)
end)
hook.Add("ZB_StartRound", "STTS_PhoneGive", function()
	timer.Simple(2, function()
		for _, ply in player.Iterator() do AutoGive(ply) end
	end)
end)

--[[ chat over the line ]]
local pending = PHONE.ChatPending or {}
PHONE.ChatPending = pending
hook.Add("HG_PlayerSay", "STTS_PhoneRelay", function(ply, txtTbl, text)
	if not IsValid(ply) or not istable(txtTbl) then return end
	ply.STTS_HGSay72 = engine.TickCount() -- Z-City's chat came here (the PlayerSay fallback below stays out)
	local raw = isstring(text) and text or (isstring(txtTbl[1]) and txtTbl[1]) or ""
	local first = string.sub(raw, 1, 1)
	if raw == "" or first == "!" or first == "/" then return end
	local set = PHONE.RelayTargets and PHONE.RelayTargets(ply)
	if not set then return end
	local tick = engine.TickCount()
	pending[ply] = {tick = tick, set = set}
	timer.Simple(0, function()
		local p = pending[ply]
		if p and p.tick == tick then pending[ply] = nil end
		if not IsValid(ply) then return end
		local final = txtTbl[1]
		if isstring(final) and final ~= "" then PHONE.Relay(ply, final) end
	end)
end)

--[[ fix72: chat over the line without ZChat (other modes / builds without HG_PlayerSay): the plain
     PlayerSay. when ZChat runs, its HG_PlayerSay comes in the same tick and this one stays out ]]
hook.Add("PlayerSay", "STTS_PhoneRelay72", function(ply, text)
	if not IsValid(ply) or not isstring(text) or text == "" then return end
	local first = string.sub(text, 1, 1)
	if first == "!" or first == "/" then return end
	local tick = engine.TickCount()
	timer.Simple(0, function()
		if not IsValid(ply) or ply.STTS_HGSay72 == tick or ply.STTS_HGSay72 == tick + 1 then return end
		if PHONE.Relay then PHONE.Relay(ply, text) end
	end)
end)

--[[ fix72: the voice over a line, whatever else decides about voices.
     PlayerCanHearPlayersVoice is run until a hook answers. every foreign hook there is wrapped:
     it runs first (its side effects and its "yes" stay), and only where it said "no" (or "3D",
     which is silent far away) for two people on a connected line the phone says "yes, not 3D"
     (PHONE.VoiceRoute72: never against a gag / brain damage). our own hook answers where
     nobody else does (other modes; Z-City answers everything itself) ]]
local oursV = setmetatable({}, { __mode = "k" })
PHONE.VoiceOurs72 = oursV
local function OurId(id)
	local p = isstring(id) and string.sub(id, 1, 5)
	return p == "STTS_" or p == "stts_"
end
local function VoiceWrapper(orig)
	local w = function(listener, speaker, ...)
		local a, b = orig(listener, speaker, ...)
		if (a == false or (a == true and b)) and PHONE.VoiceRoute72 then
			local ra, rb = PHONE.VoiceRoute72(listener, speaker)
			if ra and (a == false or not rb) then return true, rb end
		end
		return a, b
	end
	oursV[w] = true
	return w
end
local function WrapVoice()
	local ev = "PlayerCanHearPlayersVoice"
	if hook.GetULibTable then
		local prio = hook.GetULibTable()[ev]
		PHONE.zcVoice72 = false
		if istable(prio) then
			for _, bucket in pairs(prio) do
				if istable(bucket) then
					if bucket.RealisticVoice then PHONE.zcVoice72 = true end
					for id, r in pairs(bucket) do
						if istable(r) and isstring(id) and isfunction(r.fn) and not OurId(id) and not oursV[r.fn] then r.fn = VoiceWrapper(r.fn) end
					end
				end
			end
		end
		return
	end
	local t = hook.GetTable()[ev]
	PHONE.zcVoice72 = (t and t.RealisticVoice) and true or false
	if not t then return end
	local list = {}
	for id, fn in pairs(t) do
		if isstring(id) and isfunction(fn) and not OurId(id) and not oursV[fn] then list[#list + 1] = id end
	end
	for i = 1, #list do
		local id = list[i]
		local w = VoiceWrapper(t[id])
		hook.Add(ev, id, w)
		local now = hook.GetTable()[ev]
		if now and isfunction(now[id]) then oursV[now[id]] = true end
	end
end
hook.Add("PlayerCanHearPlayersVoice", "STTS_PhoneVoice72", function(listener, speaker)
	if PHONE.zcVoice72 or not PHONE.VoiceRoute72 then return end -- Z-City answers (with the phone in it: CanListenOthers + the wrapper)
	local a, b = PHONE.VoiceRoute72(listener, speaker)
	if a then return a, b end
end)
WrapVoice()
hook.Add("InitPostEntity", "STTS_PhoneVoice72", WrapVoice)
timer.Create("STTS_PhoneVoice72", 5, 0, WrapVoice)

-- zhphone_compat_sv (server console / superadmin): who decides about voices and chat
concommand.Add("zhphone_compat_sv", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local out = {"[ZPHONE] server compat report (fix73)", "[ZPHONE] Z-City (hg): " .. (istable(hg) and "found" or "NOT FOUND") .. ", round state: " .. tostring(zb and zb.ROUND_STATE) .. ", in round: " .. tostring(PHONE.InRound and PHONE.InRound())}
	local ht = hook.GetTable()
	for _, ev in ipairs({"PlayerCanHearPlayersVoice", "CanListenOthers", "HG_PlayerCanHearPlayersVoice", "PlayerCanSeePlayersChat", "PlayerSay", "HG_PlayerSay"}) do
		local ids = {}
		for id, fn in pairs(ht[ev] or {}) do
			ids[#ids + 1] = tostring(id) .. ((oursV[fn] and not OurId(id)) and " (phone after it)" or "")
		end
		table.sort(ids)
		out[#out + 1] = "[ZPHONE] " .. ev .. ": " .. #ids .. " hooks: " .. table.concat(ids, ", ")
	end
	do -- fix73: the phone line (PHONE.Line73 in sv_phone.lua)
		local L = PHONE.Line73
		local heard, ears, dll = 0, 0, 0
		if L then
			for _ in pairs(L.voice or {}) do heard = heard + 1 end
			for _ in pairs(L.ears or {}) do ears = ears + 1 end
		end
		for _, p in ipairs(player.GetHumans()) do if p.STTS_Line73 then dll = dll + 1 end end
		out[#out + 1] = "[ZPHONE] phone line: " .. heard .. " players hear a call now, " .. ears .. " get its game sounds; " .. dll .. " clients have the fix73 DLL line"
	end
	local errs = STTS.Safe71 and STTS.Safe71.errors or {}
	local n = 0
	for key, e in SortedPairs(errs) do
		n = n + 1
		if n <= 8 then out[#out + 1] = "[ZPHONE] error x" .. e.n .. " in " .. key .. ": " .. string.sub(string.gsub(e.msg or "", "\n.*", ""), 1, 200) end
	end
	out[#out + 1] = n == 0 and "[ZPHONE] no errors in the phone hooks" or ("[ZPHONE] " .. n .. " phone hooks had errors")
	for _, line in ipairs(out) do
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
end, nil, "ZPhone: server compatibility report (voice / chat hooks, recent errors)")

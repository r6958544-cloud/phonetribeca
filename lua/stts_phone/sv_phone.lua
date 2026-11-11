--[[---------------------------------------------------------------------------
	SHOOTING - phones
	* every weapon_stts_phone gets its own number for the round. the contact
	  name is the character (appearance name) who got the phone first.
	* 911: the call rings at a random spectator (dead / not spawned). several
	  calls at once go to different operators. the operator may send the
	  police. a victim can only call 911 after he SAW a shooter
	  (STTS.Config.CallNeedsSight).
	* phone-to-phone: dial any number from Contacts. it rings whoever holds
	  that phone right now (or the phone rings on the floor / on a corpse).
	* on a connected line both sides just talk or type in the normal chat.
	  people standing next to a phone hear the other side from its speaker.
	* fix73: every phone of a call is a microphone and a speaker IN THE WORLD,
	  like the phone camera's ear of a video: in the hand, at the ear, on the
	  floor / a table (placed with MMB or dropped), in a pocket (muffled). the
	  other side hears everybody who talks near that phone (quieter with the
	  distance, through walls), and - with the native module fix73 on its PC -
	  the game sounds around it (shots, steps, doors...), see PHONE.Line73.
	  the 911 operator is private: other spectators never see / hear him.
	* video calls: either side can turn its camera on (front / rear). nothing
	  but the phone POSE goes over the network, every client renders the view
	  itself. if a phone falls out of a hand during a video call (death, drop)
	  the line stays up: the phone is a normal entity in the world and the
	  other side keeps watching its camera until somebody picks it up and hangs
	  up or throws it away.
	* the screen of every phone is synced as STATE (NW2 vars on the weapon),
	  never as pixels.
	* ZPhone for Z-City (standalone): calls work while a Z-City round is running
	  (any mode, or always outside Z-City). the 911 "police" button makes the
	  police of the round come sooner (Homicide), see DispatchPolice.
---------------------------------------------------------------------------]]
STTS = STTS or {}
STTS.Phone = STTS.Phone or {}
STTS.Config = STTS.Config or {}
local PHONE = STTS.Phone
local CFG = STTS.Config

util.AddNetworkString("stts_phone_state")   -- -> state of your line
util.AddNetworkString("stts_phone_action")  -- <- operator keys: "answer" "hangup" "dispatch"
util.AddNetworkString("stts_phone_ui")      -- <- phone screen: "open" "close" "dial" "answer" "hangup"
util.AddNetworkString("stts_phone_book")    -- -> contacts
util.AddNetworkString("stts_phone_chat")    -- -> chat line coming out of a phone
util.AddNetworkString("stts_phone_scr")     -- <- holder: app / hovered item / scroll / gallery index
util.AddNetworkString("stts_phone_pose")    -- <- holder: phone pose while its camera streams
util.AddNetworkString("stts_phone_feed")    -- -> pose of a remote phone camera (video call)
local G = STTS.PhoneGeo

local debugCvar = CreateConVar("stts_phone_debug", "0", FCVAR_ARCHIVE, "1 = bots can be 911 operators and stts_phone_testcall works; bots always answer ordinary phone calls")
local function Debug() return debugCvar:GetBool() end

local PHONE_CLASS = "weapon_stts_phone"
local RING_SOUND, RING_LEN = "stts/phone_call_loop.mp3", 7.5 -- fix55: mp3, looped by PHONE.LoopStart

--[[ fix55: looped sounds. the sounds are small mp3s now (no cue-point loop like the
     old wavs), so a looped sound is restarted every `len` seconds by this Think.
     PHONE.LoopStart(ent, file, len, level, vol) -> lp; PHONE.LoopStop(lp); PHONE.LoopVol(lp, v) ]]
local LOOPS = PHONE.Loops or {}
PHONE.Loops = LOOPS
local function LoopStart(ent, file, len, level, vol)
	if not IsValid(ent) or not file then return end
	local s = CreateSound(ent, file)
	if not s then return end
	s:SetSoundLevel(level or 72)
	s:PlayEx(vol or 1, 100)
	local lp = {snd = s, ent = ent, file = file, vol = vol or 1, len = math.max(tonumber(len) or 5, 0.3)}
	lp.next = CurTime() + lp.len
	LOOPS[lp] = true
	return lp
end
local function LoopStop(lp)
	if not lp then return end
	LOOPS[lp] = nil
	if lp.snd then lp.snd:Stop() end
end
local function LoopVol(lp, v)
	if not lp or lp.vol == v then return end
	lp.vol = v
	if lp.snd then lp.snd:ChangeVolume(v, 0.1) end
end
PHONE.LoopStart, PHONE.LoopStop, PHONE.LoopVol = LoopStart, LoopStop, LoopVol
hook.Add("Think", "STTS_PhoneLoops", function()
	if next(LOOPS) == nil then return end
	local now = CurTime()
	for lp in pairs(LOOPS) do
		if not IsValid(lp.ent) then
			LOOPS[lp] = nil
			if lp.snd then lp.snd:Stop() end
		elseif now >= lp.next then
			lp.snd:Stop()
			lp.snd:PlayEx(lp.vol, 100)
			lp.next = now + lp.len
		end
	end
end)

--[[ the ringtone plays ONCE per source and loops until the call is
     answered / ended (or the phone changes hands: then it moves with it) ]]
local function StopRing(link)
	LoopStop(link.ring)
	link.ring, link.ringEnt, link.ringKey = nil, nil, nil
end
--[[ fix20: volume of a phone (shade slider, NW2 "Vol" 0..100): every sound of it ]]
local function PhoneVol(wep)
	if not IsValid(wep) then return 1 end
	return math.Clamp(wep:GetNW2Int("Vol", 100), 0, 100) / 100
end
local function PlyVol(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return 1 end
	local w = ply:GetActiveWeapon()
	if not (IsValid(w) and w:GetClass() == PHONE_CLASS) then w = ply:GetWeapon(PHONE_CLASS) end
	return PhoneVol(w)
end
PHONE.PhoneVol, PHONE.PlyVol = PhoneVol, PlyVol
local function Beep(ply, pitch) -- busy / no answer tone of the caller's phone
	local v = PlyVol(ply)
	if v > 0.005 then ply:EmitSound("stts/phone_busy.mp3", 40, pitch, v) end
end
--[[ Settings: ringtone of the called phone. key = what plays now: a change restarts it
     (fix55: no vibration any more) ]]
local function RingLoop(link, ent)
	local wep = link.bWep
	-- fix61: Focus (Do Not Disturb, Control Centre / Settings) = the call comes in silently
	if IsValid(wep) and wep:GetNW2Bool("Focus", false) then
		StopRing(link)
		link.ringEnt = ent -- PHONE.RingRefresh starts it when Focus goes off again
		return
	end
	local vol = PhoneVol(wep)
	local file, len = RING_SOUND, RING_LEN
	if PHONE.RingSound then file, len = PHONE.RingSound(wep) end
	file, len = file or RING_SOUND, len or RING_LEN
	if link.ringEnt == ent and link.ringKey == file and link.ring and LOOPS[link.ring] then
		LoopVol(link.ring, vol)
		return
	end
	StopRing(link)
	link.ringEnt, link.ringKey = ent, file
	link.ring = LoopStart(ent, file, len, 72, vol)
end
-- a setting of a ringing phone changed (sv_shooting_phone_settings.lua)
function PHONE.RingRefresh(wep)
	local link = PHONE.Ringing and PHONE.Ringing[wep]
	if link and link.ringEnt then RingLoop(link, link.ringEnt) end
end

PHONE.Calls = PHONE.Calls or {}     -- 911: [caller] = {op = ply, state = "ringing"/"connected", tried = {}, since = time}
PHONE.Ops = PHONE.Ops or {}         -- 911: [operator] = caller
PHONE.Links = PHONE.Links or {}     -- phone-to-phone: [ply] = link (both sides)
PHONE.Ringing = PHONE.Ringing or {} -- phone-to-phone: [phone weapon] = link that rings it
PHONE.Numbers = PHONE.Numbers or {} -- [number] = phone weapon
PHONE.ByWep = PHONE.ByWep or {}     -- phone-to-phone: [phone weapon] = its link (outgoing or connected)
-- Control Centre tiles (act -> NW2 bool, true = switched OFF / ON as named). they belong to the phone.
-- v19.2: Bluetooth / Cellular removed; "NoJoin" = not connected to the Wi-Fi of the map ("wjoin")
PHONE.CCToggle = {wifi = "NoWifi", rotlock = "RotLock", focus = "Focus"}

local function PlayerAvatar(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return "" end
	local id = ply:SteamID64()
	return id and #id == 17 and string.match(id, "^%d+$") and id or ""
end

local function Send(ply, role, state, since, extra, avatar)
	if not IsValid(ply) or ply:IsBot() then return end
	net.Start("stts_phone_state")
		net.WriteString(role)       -- "caller" (911) / "operator" / "out" / "in" / ""
		net.WriteString(state)      -- "ringing" "connected" "ended" "noanswer" "busy" "invalid" "dispatched" "already" "nosee"
		net.WriteFloat(since or CurTime())
		net.WriteString(extra or "") -- name of the other side
		net.WriteString(avatar or "") -- real Steam avatar account, never a generated portrait
	net.Send(ply)
	if PHONE.Flash then PHONE.Flash(ply, state) end
end

-- standalone: any running Z-City round (zb.ROUND_STATE 1); no Z-City round system = always
local function InRound()
	if not (zb and CurrentRound) then return true end
	if zb.ROUND_STATE == nil then return true end
	return zb.ROUND_STATE == 1
end
PHONE.InRound = InRound

local function Awake(ply)
	return IsValid(ply) and ply:Alive() and not (ply.organism and ply.organism.otrub)
end

local function PhoneOf(ply)
	local wep = IsValid(ply) and ply:GetWeapon(PHONE_CLASS)
	return IsValid(wep) and wep or nil
end

-- holds the phone in his hand (optionally this exact phone) and is conscious
local function Holding(ply, wep)
	if not Awake(ply) then return false end
	local act = ply:GetActiveWeapon()
	if not IsValid(act) or act:GetClass() ~= PHONE_CLASS then return false end
	return wep == nil or act == wep
end

local FLASH = {dispatched = "Police sent", already = "On the way", noanswer = "No answer", busy = "Busy", invalid = "No service", nosee = "You didn't see anything"} -- no "Call ended": the call screen just closes (like iOS)
function PHONE.Flash(ply, state)
	local text = FLASH[state]
	local wep = text and PhoneOf(ply)
	if not wep then return end
	wep:SetNW2String("Flash", text)
	wep:SetNW2Float("FlashAt", CurTime())
end

local function CharName(ply)
	return ply:GetNWString("PlayerName", ply:Nick())
end

local function PhoneName(wep)
	local n = IsValid(wep) and wep:GetNWString("STTS_PName", "") or ""
	return n ~= "" and n or "unknown"
end

local function PhoneAvatar(wep)
	if not IsValid(wep) then return "" end
	-- Repair older phones that were registered before avatar data was ready.
	if PHONE.Register then PHONE.Register(wep, wep:GetOwner()) end
	return wep:GetNWString("STTS_Avatar", "")
end

function PHONE.IsBusy(ply)
	return PHONE.Calls[ply] ~= nil or PHONE.Ops[ply] ~= nil or PHONE.Links[ply] ~= nil
end

-- dialing / talking on his own phone (raises the phone)
function PHONE.InCall(ply)
	return IsValid(ply) and (PHONE.Calls[ply] ~= nil or PHONE.Links[ply] ~= nil)
end

--[[---------------------------------------------------------------------------
	numbers
---------------------------------------------------------------------------]]
-- fix54: a new phone never gets the number of a phone that existed this session (its
-- gallery / chats are kept per number: the new phone showed the old phone's photos)
PHONE.NumUsed = PHONE.NumUsed or {}
local function NewNumber()
	local num
	for _ = 1, 200 do
		num = "555" .. string.format("%04d", math.random(0, 9999))
		if not IsValid(PHONE.Numbers[num]) and not PHONE.NumUsed[num] then break end
	end
	return num
end

function PHONE.Register(wep, owner)
	if not IsValid(wep) then return end
	local num = wep:GetNWString("STTS_Num", "")
	if num == "" or (IsValid(PHONE.Numbers[num]) and PHONE.Numbers[num] ~= wep) then
		num = NewNumber()
		wep:SetNWString("STTS_Num", num)
	end
	PHONE.Numbers[num] = wep
	PHONE.NumUsed[num] = true

	-- the first character who gets it is the name in everybody's contacts
	if IsValid(owner) and owner:IsPlayer() and not IsValid(wep.STTS_Orig) and not wep.STTS_NameLocked then
		wep.STTS_Orig = owner
		wep:SetNWString("STTS_PName", CharName(owner))
		wep:SetNWString("STTS_Avatar", PlayerAvatar(owner))
	end
	if wep:GetNWString("STTS_Avatar", "") == "" then
		local original = wep.STTS_Orig
		if not IsValid(original) and IsValid(owner) and owner:IsPlayer() and
			wep:GetNWString("STTS_PName", "") == CharName(owner) then original = owner end
		local id = PlayerAvatar(original)
		if id ~= "" then wep:SetNWString("STTS_Avatar", id) end
	end
end

hook.Add("WeaponEquip", "STTS_PhoneIdentity", function(wep, owner)
	if IsValid(wep) and wep:GetClass() == PHONE_CLASS then PHONE.Register(wep, owner) end
end)

local function SendBook(ply)
	-- Some inventory/spawn paths do not call SWEP:Equip. Include those phones.
	for _, owner in player.Iterator() do
		local phone = PhoneOf(owner)
		if phone then PHONE.Register(phone, owner) end
	end
	local list = {}
	for num, wep in pairs(PHONE.Numbers) do
		if IsValid(wep) then list[#list + 1] = {num, PhoneName(wep), PhoneAvatar(wep)} end
	end
	table.sort(list, function(x, y) return x[2] < y[2] end)

	local count = math.min(#list, 200)
	local key = {}
	for i = 1, count do key[i] = list[i][1] .. list[i][2] end
	key = table.concat(key, "|")
	if not ply and key == PHONE.BookKey then return end -- nothing changed
	if not ply then PHONE.BookKey = key end
	net.Start("stts_phone_book")
		net.WriteUInt(count, 8)
		for i = 1, count do
			net.WriteString(list[i][1])
			net.WriteString(list[i][2])
			net.WriteString(list[i][3])
		end
	if ply then net.Send(ply) else net.Broadcast() end
end
PHONE.SendBook = SendBook

--[[---------------------------------------------------------------------------
	911
---------------------------------------------------------------------------]]
local function CanOperate(ply)
	if not IsValid(ply) or (ply:IsBot() and not Debug()) then return false end
	if ply:Alive() and ply:Team() ~= TEAM_SPECTATOR then return false end
	if ply:Alive() and not Awake(ply) then return false end
	if ply.STTS_Waiting or (STTS.IsShooter(ply) and ply:Team() ~= TEAM_SPECTATOR) then return false end
	if PHONE.IsBusy(ply) then return false end
	return true
end

local function EndCall(caller, reason)
	local call = PHONE.Calls[caller]
	if not call then return end
	PHONE.Calls[caller] = nil

	if IsValid(call.op) then
		PHONE.Ops[call.op] = nil
		Send(call.op, "", "ended")
	end
	if IsValid(caller) then
		Send(caller, "caller", reason or "ended")
		if reason == "noanswer" then Beep(caller, 90) end
		timer.Remove("STTS_Ring_" .. tostring(caller:EntIndex()))
	end
end

local Answer, DispatchPolice

-- a line of text coming out of the phone (shown as [phone] name: text)
local function PhoneLine(to, name, text)
	if not IsValid(to) or to:IsBot() then return end
	net.Start("stts_phone_chat")
		net.WriteString(name)
		net.WriteString(text)
	net.Send(to)
end

-- debug: a bot operator answers, talks and sends the police by itself
local function BotOperator(op, caller)
	timer.Simple(3, function()
		if PHONE.Ops[op] ~= caller then return end
		Answer(op)
		PhoneLine(caller, "911", "911, what is your emergency?")
		timer.Simple(6, function()
			local call = PHONE.Calls[caller]
			if not call or call.op ~= op or call.state ~= "connected" then return end
			PhoneLine(caller, "911", "Stay hidden. Sending units now.")
			DispatchPolice(op)
		end)
	end)
end

-- debug: a bot caller talks to you when you answer
local function BotCaller(caller, op)
	local lines = {"He has a gun! Please hurry!", "I'm hiding in a room, he's walking around.", "I can hear shots... oh god."}
	for i, line in ipairs(lines) do
		timer.Simple(i * 4, function()
			local call = PHONE.Calls[caller]
			if call and call.op == op and call.state == "connected" then PhoneLine(op, "caller", line) end
		end)
	end
end

local function Ring(caller, forcedOp)
	local call = PHONE.Calls[caller]
	if not call then return end

	-- free the previous operator
	if IsValid(call.op) then
		PHONE.Ops[call.op] = nil
		Send(call.op, "", "ended")
		call.op = nil
	end

	local pool = {}
	if IsValid(forcedOp) then
		pool[1] = forcedOp
	else
		for _, ply in player.Iterator() do
			if CanOperate(ply) and not call.tried[ply] then pool[#pool + 1] = ply end
		end
	end

	if #pool == 0 then
		-- nobody can pick up right now
		timer.Simple(4, function()
			if PHONE.Calls[caller] == call and call.state == "ringing" then EndCall(caller, "noanswer") end
		end)
		return
	end

	local op = pool[math.random(#pool)]
	call.op = op
	call.tried[op] = true
	call.state = "ringing"
	PHONE.Ops[op] = caller

	Send(op, "operator", "ringing", CurTime(), CharName(caller), PlayerAvatar(caller))
	if op:IsBot() then BotOperator(op, caller) end

	timer.Create("STTS_Ring_" .. caller:EntIndex(), CFG.RingTime or 18, 1, function()
		if PHONE.Calls[caller] == call and call.state == "ringing" then Ring(caller) end
	end)
end

function PHONE.StartCall(caller)
	if not InRound() or not IsValid(caller) or not caller:Alive() then return end
	if PHONE.IsBusy(caller) then return end
	if (caller.STTS_CallCD or 0) > CurTime() then return end
	caller.STTS_CallCD = CurTime() + 2

	-- you can only report what you saw yourself
	if not PHONE.CanReport(caller) then
		Send(caller, "caller", "nosee")
		Beep(caller, 110)
		return
	end

	PHONE.Calls[caller] = {state = "ringing", tried = {}, since = CurTime()}
	Send(caller, "caller", "ringing", CurTime(), "911")

	timer.Simple(2, function() if PHONE.Calls[caller] then Ring(caller) end end)
end

function Answer(op)
	local caller = PHONE.Ops[op]
	local call = caller and PHONE.Calls[caller]
	if not call or call.op ~= op or call.state ~= "ringing" then return end

	timer.Remove("STTS_Ring_" .. caller:EntIndex())
	call.state = "connected"
	call.since = CurTime()

	Send(op, "operator", "connected", call.since, CharName(caller), PlayerAvatar(caller))
	Send(caller, "caller", "connected", call.since, "911")
	if caller:IsBot() then BotCaller(caller, op) end
end

local function Decline(op)
	local caller = PHONE.Ops[op]
	local call = caller and PHONE.Calls[caller]
	if not call then PHONE.Ops[op] = nil return end

	if call.state == "ringing" then
		Ring(caller) -- passes the call to another spectator
	else
		EndCall(caller, "ended")
	end
end

--[[ standalone: who sends the police. a mode with its own :Dispatch(op) (ZHunter)
     decides itself, another addon can answer the hook STTS_PhoneDispatch(op, caller)
     with true (sent) / false (already on the way). otherwise the Z-City police of
     the round (Homicide: they arrive at MODE.saved.PoliceTime) come sooner. ]]
local police911 = CreateConVar("stts_phone_911_police", "1", FCVAR_ARCHIVE, "1 = a 911 operator can make the police of the round (Homicide) arrive sooner")
function PHONE.DefaultDispatch(op, caller)
	if not police911:GetBool() or not (zb and CurrentRound) or zb.ROUND_STATE ~= 1 then return false end
	local rnd = CurrentRound()
	local saved = istable(rnd) and rnd.saved
	if not (istable(saved) and isnumber(saved.PoliceTime)) then return false end
	if not rnd.PoliceAllowed or rnd.PoliceSpawned then return false end
	local key = zb.ROUND_BEGIN or zb.ROUND_START or 0
	if PHONE.DispatchedRound == key then return false end -- already on the way
	PHONE.DispatchedRound = key
	local eta = CurTime() + math.random(CFG.PoliceETAMin or 50, CFG.PoliceETAMax or 100)
	if saved.PoliceTime > eta then saved.PoliceTime = eta end
	return true
end

function DispatchPolice(op)
	local caller = PHONE.Ops[op]
	local call = caller and PHONE.Calls[caller]
	if not call or call.state ~= "connected" then return end

	local rnd = CurrentRound and CurrentRound()
	local ok
	if rnd and rnd.Dispatch then
		ok = rnd:Dispatch(op)
	else
		ok = hook.Run("STTS_PhoneDispatch", op, caller)
		if ok == nil then ok = PHONE.DefaultDispatch(op, caller) end
	end
	Send(op, "operator", ok and "dispatched" or "already", call.since, CharName(caller), PlayerAvatar(caller))
	Send(caller, "caller", ok and "dispatched" or "already", call.since, "911")
end

--[[---------------------------------------------------------------------------
	eyewitness: a victim must actually SEE a shooter before calling 911
	(shooter inside his field of view, close enough, nothing in between)
---------------------------------------------------------------------------]]
-- (CFG = STTS.Config, see top)

function PHONE.CanReport(ply)
	-- A shooter can use any acquired phone, including 911.
	if STTS.IsShooter(ply) then return true end
	if not CFG.CallNeedsSight then return true end
	if Debug() and ply:IsBot() then return true end
	return ply.STTS_SawShooter == true
end

local function BodyOf(ply)
	local ent = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or ply
	return IsValid(ent) and ent or ply
end

-- real eyes of a player (ragdoll / car: the player entity itself sits at the map origin)
local function CharEye(ply)
	if G and G.RefFrame then
		local o = G.RefFrame(ply)
		if o then return o end
	end
	return ply:EyePos()
end
PHONE.CharEye = CharEye

-- the phone of a holder is not in his hand: pocket / inventory / corpse (black video, no camera)
-- fix74: the phone in the left hand next to a weapon in the right one (STTS.PhoneRH) is in the hand too
local function InLeftHand(owner, wep)
	local RH = STTS.PhoneRH
	return RH and RH.Phone and RH.Phone(owner) == wep or false
end
PHONE.InLeftHand = InLeftHand
function PHONE.InPocket(wep)
	if not IsValid(wep) then return false end
	local owner = wep:GetOwner()
	if IsValid(owner) and owner:IsPlayer() then
		if not owner:Alive() then return true end
		return owner:GetActiveWeapon() ~= wep and not InLeftHand(owner, wep)
	end
	return IsValid(wep:GetParent())
end

local function BonePos(ent, bone)
	local id = ent:LookupBone(bone)
	if id then
		local m = ent:GetBoneMatrix(id)
		if m then return m:GetTranslation() end
	end
end

-- a few points on the shooter's body: head, chest, pelvis
local function ShooterPoints(shooter)
	local ent = BodyOf(shooter)
	local pts = {}
	for _, b in ipairs({"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis"}) do
		local p = BonePos(ent, b)
		if p then pts[#pts + 1] = p end
	end
	if #pts == 0 then pts[1] = ent:WorldSpaceCenter() end
	return pts, ent
end

local function ViewOf(ply)
	local ent = BodyOf(ply)
	if ent ~= ply then
		-- ragdolled: look from the head of the ragdoll
		local id = ent:LookupBone("ValveBiped.Bip01_Head1")
		local m = id and ent:GetBoneMatrix(id)
		if m then return m:GetTranslation(), ply:GetAimVector(), ent end
	end
	return ply:EyePos(), ply:GetAimVector(), ent
end

local function CanSee(viewer, shooter)
	local eye, dir, vEnt = ViewOf(viewer)
	local maxDist = CFG.SightDistance or 3500
	local cosFov = math.cos(math.rad(CFG.SightFOV or 55))
	local pts, sEnt = ShooterPoints(shooter)

	for _, p in ipairs(pts) do
		local to = p - eye
		local dist = to:Length()
		if dist > maxDist then continue end
		if dist > 48 and to:GetNormalized():Dot(dir) < cosFov then continue end

		local tr = util.TraceLine({
			start = eye,
			endpos = p,
			filter = {viewer, vEnt, shooter, sEnt},
			mask = MASK_VISIBLE_AND_NPCS,
		})
		if not tr.Hit or tr.Fraction > 0.98 then return true end
	end
	return false
end

timer.Create("STTS_EyeWitness", 0.25, 0, function()
	if not InRound() then return end

	local shooters = {}
	for _, ply in player.Iterator() do
		if STTS.IsShooter(ply) and ply:Alive() and not ply.STTS_Waiting then shooters[#shooters + 1] = ply end
	end
	if #shooters == 0 then return end

	for _, ply in player.Iterator() do
		if ply.STTS_SawShooter or not ply:Alive() or STTS.IsShooter(ply) or ply.isPolice then continue end
		if ply:Team() == TEAM_SPECTATOR or (ply.organism and ply.organism.otrub) then continue end

		for _, sh in ipairs(shooters) do
			if CanSee(ply, sh) then
				ply.STTS_SawShooter = true
				ply:SetNWBool("STTS_SawShooter", true)
				break
			end
		end
	end
end)

function PHONE.ResetWitness(ply)
	ply.STTS_SawShooter = false
	ply:SetNWBool("STTS_SawShooter", false)
end

--[[---------------------------------------------------------------------------
	phone-to-phone calls
	link = {a = caller, aWep = his phone, bWep = called phone, b = who answered,
	        notified = holder that sees "incoming", state, since}
---------------------------------------------------------------------------]]
local function RingTime() return CFG.PhoneRingTime or 25 end

local function EndLink(link, reasonA, reasonB)
	if link.ended then return end
	link.ended = true
	timer.Remove(link.timer)
	StopRing(link)
	if PHONE.Ringing[link.bWep] == link then PHONE.Ringing[link.bWep] = nil end
	for _, w in ipairs({link.aWep, link.bWep}) do
		if PHONE.ByWep[w] == link then PHONE.ByWep[w] = nil end
		if IsValid(w) then w:SetNW2Bool("VidOn", false) end
	end

	for _, p in pairs({link.a or false, link.b or false}) do
		if IsValid(p) and PHONE.Links[p] == link then PHONE.Links[p] = nil end
	end

	if IsValid(link.a) then
		Send(link.a, "out", reasonA or "ended")
		if reasonA == "busy" or reasonA == "noanswer" then Beep(link.a, 90) end
	end
	local other = IsValid(link.b) and link.b or link.notified
	if IsValid(other) then Send(other, "in", reasonB or "ended") end
end

local function AnswerLink(ply)
	local wep = PhoneOf(ply)
	local link = wep and PHONE.Ringing[wep]
	if not link or link.ended or link.state ~= "ringing" then return false end
	if wep:GetNW2Bool("Plane", false) then return false end -- fix17
	if not Holding(ply, wep) or PHONE.IsBusy(ply) then return false end

	timer.Remove(link.timer)
	StopRing(link)
	PHONE.Ringing[wep] = nil
	link.b = ply
	link.state = "connected"
	link.since = CurTime()
	PHONE.Links[ply] = link
	PHONE.ByWep[wep] = link

	if IsValid(link.notified) and link.notified ~= ply then Send(link.notified, "", "ended") end
	Send(link.a, "out", "connected", link.since, PhoneName(link.bWep), PhoneAvatar(link.bWep))
	Send(ply, "in", "connected", link.since, PhoneName(link.aWep), PhoneAvatar(link.aWep))
	return true
end

local function RingTick(link)
	if link.ended or link.state ~= "ringing" then return end
	if CurTime() - link.since > RingTime() then EndLink(link, "noanswer") return end

	local wep = link.bWep
	if not IsValid(wep) then EndLink(link, "noanswer") return end

	local holder = wep:GetOwner()
	if not (IsValid(holder) and holder:IsPlayer() and holder:Alive()) then holder = nil end

	-- whoever had the "incoming call" screen lost the phone
	if IsValid(link.notified) and link.notified ~= holder then
		Send(link.notified, "", "ended")
		link.notified = nil
	end

	if holder then
		RingLoop(link, holder)
		if not link.notified and Awake(holder) and not PHONE.IsBusy(holder) then
			link.notified = holder
			Send(holder, "in", "ringing", link.since, PhoneName(link.aWep), PhoneAvatar(link.aWep))
			if holder:IsBot() then
				timer.Simple(3, function()
					if IsValid(holder) and holder:HasWeapon(PHONE_CLASS) then
						holder:SelectWeapon(PHONE_CLASS)
						timer.Simple(0.3, function() if IsValid(holder) and AnswerLink(holder) then PhoneLine(link.a, PhoneName(link.bWep), "Hello? Who is this?") end end)
					end
				end)
			end
		end
	else
		-- on the floor or in a dead body's pocket
		local par = wep:GetParent()
		local src = IsValid(par) and par or wep
		RingLoop(link, src)
	end
end

function PHONE.Dial(ply, number)
	number = string.gsub(tostring(number or ""), "%D", "")
	if not InRound() or not Holding(ply) or PHONE.IsBusy(ply) then return end
	if number == "" then return end
	-- fix17: airplane mode = no calls at all (the screen says "Airplane mode")
	if ply:GetActiveWeapon():GetNW2Bool("Plane", false) then return end
	if number == "911" or number == "112" then PHONE.StartCall(ply) return end

	if (ply.STTS_CallCD or 0) > CurTime() then return end
	ply.STTS_CallCD = CurTime() + 2

	local mine = ply:GetActiveWeapon()
	PHONE.Register(mine, ply) -- transfers retain the physical phone's number/name
	local wep = PHONE.Numbers[number]
	if not IsValid(wep) then
		Send(ply, "out", "invalid")
		Beep(ply, 110)
		return
	end

	-- fix17: the other phone is in airplane mode = like switched off
	-- fix24: like a real network: the call goes out (call screen, a ringback beep),
	-- then the caller hears "the subscriber is unavailable" and the call ends.
	-- the phone in airplane mode does not ring and knows nothing about it.
	if wep ~= mine and wep:GetNW2Bool("Plane", false) then
		PHONE.DialUnreachable(ply, mine, wep)
		return
	end
	local holder = wep:GetOwner()
	if wep == mine or PHONE.Ringing[wep] or (IsValid(holder) and holder:IsPlayer() and PHONE.IsBusy(holder)) then
		Send(ply, "out", "busy")
		Beep(ply, 100)
		return
	end

	local link = {a = ply, aWep = mine, bWep = wep, state = "ringing", since = CurTime(), timer = "STTS_PRing_" .. ply:EntIndex(), adopted = {}}
	PHONE.Links[ply] = link
	PHONE.Ringing[wep] = link
	PHONE.ByWep[mine] = link
	Send(ply, "out", "ringing", CurTime(), PhoneName(wep), PhoneAvatar(wep))

	timer.Create(link.timer, 2.2, 0, function() RingTick(link) end)
	timer.Simple(1, function() RingTick(link) end)
end

--[[ fix24: calling a phone in airplane mode (1 ringback beep, then the message; 2.5 s
     is before the 2nd beep would start at 3.05 s). a normal outgoing link (so the call
     screen, End, busy checks, dropping the phone etc. work as usual), but it is
     NOT registered in PHONE.Ringing: the other phone never rings.
       0 s           "ringing": call screen + ringback beeps on the caller's PC
       UNREACH_DELAY "unreach": the beeps stop, the caller hears phone_unreach.mp3
       + UNREACH_LEN the call ends by itself (End before that = ends at once) ]]
local UNREACH_DELAY = CreateConVar("stts_phone_unreach_delay", "2.5", FCVAR_ARCHIVE, "calling a phone in airplane mode: seconds of ringback before \"the subscriber is unavailable\"", 0, 20)
local UNREACH_LEN = 14.9 -- length of sound/stts/phone_unreach.mp3
function PHONE.DialUnreachable(ply, mine, wep)
	local link = {a = ply, aWep = mine, bWep = wep, state = "ringing", unreach = true, since = CurTime(), timer = "STTS_PRing_" .. ply:EntIndex(), adopted = {}}
	PHONE.Links[ply] = link
	PHONE.ByWep[mine] = link
	Send(ply, "out", "ringing", CurTime(), PhoneName(wep), PhoneAvatar(wep))
	timer.Remove(link.timer)
	timer.Simple(UNREACH_DELAY:GetFloat(), function()
		if link.ended or not IsValid(ply) or PHONE.Links[ply] ~= link then return end
		link.unreachAt = CurTime()
		Send(ply, "out", "unreach", link.since, PhoneName(wep), PhoneAvatar(wep))
		timer.Simple(UNREACH_LEN, function()
			if not link.ended then EndLink(link, "ended", "ended") end
		end)
	end)
end

function PHONE.HangUp(ply)
	if PHONE.Ops[ply] then Decline(ply) return end
	if PHONE.Calls[ply] then EndCall(ply, "ended") return end

	local link = PHONE.Links[ply]
	if link then
		EndLink(link, "ended", "ended")
		return
	end

	-- decline an incoming call
	local wep = PhoneOf(ply)
	link = wep and PHONE.Ringing[wep]
	if link and link.notified == ply then EndLink(link, "busy", "ended") end
end

--[[ video calls survive a lost phone ]]
local function LinkVideo(link)
	return link.state == "connected" and ((IsValid(link.aWep) and link.aWep:GetNW2Bool("VidOn")) or (IsValid(link.bWep) and link.bWep:GetNW2Bool("VidOn")))
end
PHONE.LinkVideo = LinkVideo

-- a fallen phone must be a real entity in the world (not hidden in a corpse's pocket)
local function EnsureInWorld(wep)
	if not IsValid(wep) or IsValid(wep:GetOwner()) then return end
	local rag = wep:GetParent()
	if not IsValid(rag) then return end
	local pos = rag:WorldSpaceCenter() + VectorRand() * 4 + Vector(0, 0, 6)
	wep:SetParent(NULL)
	wep:SetPos(pos)
	wep:SetAngles(Angle(0, math.random(0, 359), 0))
	wep:SetNoDraw(false)
	wep:DrawShadow(true)
	wep:RemoveSolidFlags(FSOLID_NOT_SOLID)
	wep:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	local phys = wep:GetPhysicsObject()
	if IsValid(phys) then phys:EnableMotion(true) phys:Wake() end
	local inv = rag.inventory
	if inv and inv.Weapons and inv.Weapons[PHONE_CLASS] == wep then
		inv.Weapons[PHONE_CLASS] = nil
		rag:SetNetVar("Inventory", inv)
	end
end
PHONE.EnsureInWorld = EnsureInWorld

local function Orphan(link, side)
	local ply, wep = link[side], link[side .. "Wep"]
	link[side] = nil
	if IsValid(ply) then
		if PHONE.Links[ply] == link then PHONE.Links[ply] = nil end
		Send(ply, "", "ended")
	end
	timer.Simple(0.3, function() EnsureInWorld(wep) end)
	timer.Simple(1.0, function() EnsureInWorld(wep) end)
end

local function Adopt(link, side, ply)
	link[side] = ply
	link.adopted[side] = true -- whoever picked it up is on the line (dropping it again keeps the call)
	PHONE.Links[ply] = link
	local other = side == "a" and link.bWep or link.aWep
	Send(ply, side == "a" and "out" or "in", "connected", link.since, PhoneName(other), PhoneAvatar(other))
end

--[[ someone lost the phone of this link side (dropped it, died, threw it away):
     a CONNECTED call never ends because of that, not even when BOTH phones are
     on the floor. the phones keep the line, whoever picks one up is on it.
     it ends only by "End" on a phone, when a phone entity is removed, or when
     nobody holds either phone for PHONE_ORPHAN_TIME seconds. ]]
local ORPHAN_TIME = CreateConVar("stts_phone_orphan_time", "120", FCVAR_ARCHIVE, "seconds a call survives with nobody holding either phone (0 = forever)")
local function LostSide(link, side)
	Orphan(link, side)
	if not IsValid(link.a) and not IsValid(link.b) then link.orphanAt = link.orphanAt or CurTime() end
end

-- died / disconnected / became an operator
function PHONE.Drop(ply)
	if PHONE.Calls[ply] then EndCall(ply, "ended") end

	local caller = PHONE.Ops[ply]
	if caller then
		PHONE.Ops[ply] = nil
		local call = PHONE.Calls[caller]
		if call then
			call.op = nil
			if call.state == "connected" then EndCall(caller, "ended") end
		end
		Send(ply, "", "ended")
	end

	local link = PHONE.Links[ply]
	if link then
		local side = link.a == ply and "a" or "b"
		if link.state == "connected" then LostSide(link, side) else EndLink(link, "ended", "ended") end
	end

	-- an incoming call keeps ringing (now from the body / floor)
	for _, l in pairs(PHONE.Ringing) do
		if l.notified == ply then l.notified = nil Send(ply, "", "ended") end
	end
end

function PHONE.Reset()
	for caller in pairs(PHONE.Calls) do
		if IsValid(caller) then
			timer.Remove("STTS_Ring_" .. caller:EntIndex())
			Send(caller, "", "ended")
		end
	end
	for op in pairs(PHONE.Ops) do Send(op, "", "ended") end

	local seen = {}
	for _, link in pairs(PHONE.Links) do
		if not seen[link] then seen[link] = true EndLink(link, "ended", "ended") end
	end

	PHONE.Calls, PHONE.Ops, PHONE.Links, PHONE.Ringing, PHONE.ByWep = {}, {}, {}, {}, {}
	for _, wep in ipairs(ents.FindByClass(PHONE_CLASS)) do wep:SetNW2Bool("VidOn", false) end
	if STTS.PhoneMedia then STTS.PhoneMedia.Reset() end
	if STTS.PhoneChat and STTS.PhoneChat.Reset then STTS.PhoneChat.Reset() end
	for num, wep in pairs(PHONE.Numbers) do
		if not IsValid(wep) then PHONE.Numbers[num] = nil end
	end
end

--[[ fix17: airplane mode switched on = this phone drops off the network:
     its calls end (911 too), a call ringing on it ends as "No answer". ]]
function PHONE.Unreachable(wep, ply)
	if IsValid(ply) and (PHONE.Calls[ply] or PHONE.Links[ply]) then PHONE.HangUp(ply) end
	local link = PHONE.Ringing[wep]
	if link and not link.ended then EndLink(link, "noanswer", "ended") end
	link = PHONE.ByWep[wep]
	if link and not link.ended then EndLink(link, "ended", "ended") end
end

--[[---------------------------------------------------------------------------
	net
---------------------------------------------------------------------------]]
net.Receive("stts_phone_ui", function(_, ply)
	local act = net.ReadString()
	local arg = net.ReadString()
	local wep = ply:GetActiveWeapon()
	local isPhone = IsValid(wep) and wep:GetClass() == PHONE_CLASS
	-- Settings app: "theme" / "ring" (sv_shooting_phone_settings.lua)
	if PHONE.SettingsAct and PHONE.SettingsAct(ply, wep, isPhone, act, arg) then return end
	-- fix58: vehicle (hand at the phone) + lock screen acts (sh_phone_car.lua, sv_phone_lock.lua)
	if STTS.PhoneCar and STTS.PhoneCar.Act and STTS.PhoneCar.Act(ply, wep, isPhone, act, arg) then return end
	if STTS.PhoneLockAct and STTS.PhoneLockAct(ply, wep, isPhone, act, arg) then return end

	if act == "open" or act == "close" then
		if isPhone and wep.SetRaised then wep:SetRaised(act == "open" and Awake(ply)) end
		-- fix72: "open" + "look" = held in front of you without the finger (stts_phone_controls 0)
		if isPhone then wep:SetNW2Bool("Look", (act == "open" and arg == "look" and wep:GetRaised()) and true or false) wep:SetNW2Bool("Touch", false) end
		if act == "open" and isPhone then
			wep:SetNW2Bool("Down", false) SendBook(ply)
			if STTS.PhoneAutoLock and STTS.PhoneAutoLock.Wake then STTS.PhoneAutoLock.Wake(wep) end -- fix72: raised = the display is on
		end
		if act == "close" and isPhone then wep:SetNW2Bool("Down", arg == "down") end
		return
	end
	-- R while the phone is not raised: fully down (idle pose) even during a call
	if act == "down" then
		if isPhone then wep:SetNW2Bool("Down", true) wep:SetNW2Bool("Touch", false) end
		return
	end
	-- Stabilization strength belongs to the physical phone, not the renderer PC.
 if act == "eis" then
  if isPhone then wep:SetNW2Int("EIS",math.Clamp(math.floor(tonumber(arg)or 2),0,2))end
  return
 end
 -- camera zoom (slider), the other side of a video call renders with it
	if act == "zoom" then
		if not isPhone then return end
		local z = math.Clamp(tonumber(arg) or 1, 1, G.ZoomMax or 5)
		wep:SetNW2Float("Zoom", math.Round(z, 2))
		return
	end
	-- camera app: 0 photo, 1 video, 2 recording (the shutter of others turns red)
	-- fix15: RecBy / RecAt = who records and since when. the recording belongs to the
	-- recorder's PC and goes on when the phone leaves his hands; whoever holds the
	-- phone then can stop it (cam 0 / 1), or the time limit ends it
	if act == "cam" then
		if not isPhone then return end
		local mode = math.Clamp(math.floor(tonumber(arg) or 0), 0, 2)
		local by = wep:GetNW2Entity("RecBy", NULL)
		if mode == 2 then
			if wep:GetNW2Int("CamMode", 0) == 2 and IsValid(by) and by ~= ply then return end -- already recording (someone else's)
			wep:SetNW2Entity("RecBy", ply)
			wep:SetNW2Float("RecAt", CurTime())
			ply.STTS_RecWep, ply.STTS_RecUntil = wep, CurTime() + (G.VidMaxSec or 120) + 90
		elseif IsValid(by) then
			wep:SetNW2Entity("RecBy", NULL)
			by.STTS_RecUntil = CurTime() + 90 -- the last pages are still on their way
		end
		wep:SetNW2Int("CamMode", mode)
		return
	end
	-- fix15: the recorder ends his recording, wherever that phone is now
	if act == "recstop" then
		-- fix54: every phone that still says "recording by him" (ply.STTS_RecWep can be an
		-- old entity after the inventory recreated the phone)
		for _, w in ipairs(ents.FindByClass(PHONE_CLASS)) do
			if w:GetNW2Entity("RecBy", NULL) == ply then
				w:SetNW2Entity("RecBy", NULL)
				if w:GetNW2Int("CamMode", 0) == 2 then w:SetNW2Int("CamMode", 1) end
				ply.STTS_RecUntil = CurTime() + 90
			end
		end
		return
	end
	-- LMB held: the finger stays on the glass (others see it slide)
	if act == "touch" then
		if not isPhone then return end
		local on = arg == "1" and wep:GetRaised()
		if on then
			if (ply.STTS_TapCD or 0) > CurTime() then return end
			ply.STTS_TapCD = CurTime() + 0.05
			wep:SetNW2Float("TapAt", CurTime())
		end
		wep:SetNW2Bool("Touch", on)
		return
	end

	-- RMB free look (right hand drops) and finger taps: only for the animation of others
	if act == "look" or act == "unlook" then
		if isPhone then wep:SetNW2Bool("Look", act == "look" and wep:GetRaised()) end
		if isPhone and act == "look" then wep:SetNW2Bool("Touch", false) end
		return
	end
	-- v19.4: T = landscape / portrait (the pose of everybody's view of this phone)
	if act == "land" then
		-- fix61: Rotation Lock = portrait only
		if isPhone and not (arg == "1" and wep:GetNW2Bool("RotLock", false)) then wep:SetNW2Bool("Land", arg == "1") end
		return
	end
	if act == "tap" then
		if not isPhone or not wep:GetRaised() then return end
		if (ply.STTS_TapCD or 0) > CurTime() then return end
		ply.STTS_TapCD = CurTime() + 0.07
		wep:SetNW2Float("TapAt", CurTime())
		return
	end

	--[[ fix17: the pull-down shade (torch, airplane mode) and the camera flash.
	     all of them belong to the PHONE (kept when it changes hands / goes into
	     the inventory, see SWEP:GetInfo). "shot" = a photo with the flash right
	     now: everybody sees the LED / the white display light up ]]
	if act == "torch" or act == "plane" or act == "camflash" then
		if not isPhone or not Awake(ply) then return end
		if (ply.STTS_ShadeCD or 0) > CurTime() then return end
		ply.STTS_ShadeCD = CurTime() + 0.25
		local key = act == "torch" and "Torch" or (act == "plane" and "Plane" or "CamFl")
		local on = not wep:GetNW2Bool(key, false)
		wep:SetNW2Bool(key, on)
		if act == "plane" then
			if on then PHONE.Unreachable(wep, ply)
			elseif STTS.PhoneChat and STTS.PhoneChat.Release then STTS.PhoneChat.Release(wep) end
		end
		return
	end
	-- Control Centre tiles that only change how the phone looks (kept on the phone, seen by all)
	local ccKey = PHONE.CCToggle and PHONE.CCToggle[act]
	if ccKey then
		if not isPhone or not Awake(ply) then return end
		if (ply.STTS_ShadeCD or 0) > CurTime() then return end
		ply.STTS_ShadeCD = CurTime() + 0.25
		wep:SetNW2Bool(ccKey, not wep:GetNW2Bool(ccKey, false))
		-- fix61: Focus on / off: a call ringing right now goes silent / rings again
		if act == "focus" and PHONE.RingRefresh then PHONE.RingRefresh(wep) end
		-- fix61: Rotation Lock on = the phone turns back upright (T does nothing then)
		if act == "rotlock" and wep:GetNW2Bool("RotLock", false) then wep:SetNW2Bool("Land", false) end
		-- Wi-Fi off = the phone leaves the network, it is picked again after switching it on
		if act == "wifi" and wep:GetNW2Bool("NoWifi", false) then wep:SetNW2Bool("NoJoin", true) end
		return
	end
	-- v19.2: join the Wi-Fi network (there is one: the map)
	if act == "wjoin" then
		if not isPhone or not Awake(ply) then return end
		if (ply.STTS_WJoinCD or 0) > CurTime() then return end
		ply.STTS_WJoinCD = CurTime() + 0.25
		if not wep:GetNW2Bool("NoWifi", false) then wep:SetNW2Bool("NoJoin", false) end
		return
	end
	-- fix20: brightness / volume sliders of the shade (0..100, belong to the phone)
	if act == "vol" or act == "bright" then
		if not isPhone then return end
		local cd = "STTS_LvlCD_" .. act
		if (ply[cd] or 0) > CurTime() then return end
		ply[cd] = CurTime() + 0.04
		local n = math.Clamp(math.floor(tonumber(arg) or 100), 0, 100)
		wep:SetNW2Int(act == "vol" and "Vol" or "Bright", n)
		if act == "vol" then
			local link = PHONE.Ringing[wep]
			if link and link.ringEnt then RingLoop(link, link.ringEnt) end
		end
		return
	end
	if act == "shot" then
		if not isPhone or not Awake(ply) or not wep:GetNW2Bool("CamFl", false) then return end
		if (ply.STTS_ShotCD or 0) > CurTime() then return end
		ply.STTS_ShotCD = CurTime() + math.min(0.5, (G.PhotoCooldown or 0.2) * 0.75) -- fix53: every quick shot flashes
		wep:SetNW2Bool("ShotFr", arg == "1")
		wep:SetNW2Float("ShotAt", CurTime())
		return
	end

	-- camera of a phone-to-phone call: on/off and front/rear (one button each)
	if act == "video" or act == "camflip" then
		if not isPhone or not Awake(ply) then return end
		if (ply.STTS_VidCD or 0) > CurTime() then return end
		ply.STTS_VidCD = CurTime() + 0.25
		if act == "camflip" then wep:SetNW2Bool("CamFront", not wep:GetNW2Bool("CamFront", false)) return end
		local link = PHONE.ByWep[wep]
		-- fix12: a connected 911 call can show the caller's camera to the operator
		local call = PHONE.Calls[ply]
		local on911 = call and call.state == "connected" and PhoneOf(ply) == wep
		if not on911 and (not link or link.state ~= "connected") then return end
		wep:SetNW2Bool("VidOn", not wep:GetNW2Bool("VidOn", false))
		return
	end

	if (ply.STTS_PhoneNetCD or 0) > CurTime() then return end
	ply.STTS_PhoneNetCD = CurTime() + 0.3
	if not isPhone or not Awake(ply) then return end

	if act == "dial" then
		PHONE.Dial(ply, arg)
	elseif act == "answer" then
		AnswerLink(ply)
	elseif act == "hangup" then
		PHONE.HangUp(ply)
	elseif act == "book" then
		SendBook(ply)
	end
end)

-- 911 operator keys (F6 / F7)
net.Receive("stts_phone_action", function(_, ply)
	local act = net.ReadString()
	if (ply.STTS_PhoneNetCD or 0) > CurTime() then return end
	ply.STTS_PhoneNetCD = CurTime() + 0.3

	if act == "answer" then
		Answer(ply)
	elseif act == "hangup" then
		if PHONE.Ops[ply] then Decline(ply) end
	elseif act == "dispatch" then
		DispatchPolice(ply)
	end
end)

-- somebody died, lost the phone, got respawned as police, disconnected...
timer.Create("STTS_PhoneWatch", 0.5, 0, function()
	for caller, call in pairs(PHONE.Calls) do
		if not IsValid(caller) or not caller:Alive() or not caller:HasWeapon(PHONE_CLASS) then
			if IsValid(caller) then EndCall(caller, "ended") else PHONE.Calls[caller] = nil end
			if IsValid(call.op) then PHONE.Ops[call.op] = nil Send(call.op, "", "ended") end
		elseif IsValid(call.op) and call.op:Alive() and call.op:Team() ~= TEAM_SPECTATOR and (call.op.isPolice or not Debug()) then
			EndCall(caller, "ended") -- the operator became a cop / respawned
		end
	end
	for op in pairs(PHONE.Ops) do
		if not IsValid(op) then PHONE.Ops[op] = nil end
	end

	local seen = {}
	for _, link in pairs(PHONE.ByWep) do
		if seen[link] or link.ended then continue end
		seen[link] = true
		if not IsValid(link.aWep) or not IsValid(link.bWep) then EndLink(link, "ended", "ended") continue end
		if link.state ~= "connected" then
			if not (IsValid(link.a) and link.a:Alive() and PhoneOf(link.a) == link.aWep) then EndLink(link, "ended", "ended") end
			continue
		end
		for _, side in ipairs({"a", "b"}) do
			if link.ended then break end
			local ply, wep = link[side], link[side .. "Wep"]
			if IsValid(ply) then
				if not (ply:Alive() and PhoneOf(ply) == wep) then LostSide(link, side) end
			else
				-- a fallen phone of a running video call: whoever picks it up is on the line
				local h = wep:GetOwner()
				if IsValid(h) and h:IsPlayer() and h:Alive() and not PHONE.IsBusy(h) then Adopt(link, side, h) end
			end
		end
		if not link.ended then
			if IsValid(link.a) or IsValid(link.b) then
				link.orphanAt = nil
			else
				link.orphanAt = link.orphanAt or CurTime()
				local lim = ORPHAN_TIME:GetFloat()
				if lim > 0 and CurTime() - link.orphanAt > lim then EndLink(link, "ended", "ended") end
			end
		end
	end
	for ply, link in pairs(PHONE.Links) do
		if not IsValid(ply) or link.ended then PHONE.Links[ply] = nil end
	end

	-- contact name follows the first owner (appearance can be applied a bit later)
	for num, wep in pairs(PHONE.Numbers) do
		if not IsValid(wep) then PHONE.Numbers[num] = nil continue end
		local orig = wep.STTS_Orig
		if IsValid(orig) and not orig:Alive() then wep.STTS_NameLocked = true end
		if IsValid(orig) and orig:Alive() and wep:GetOwner() == orig and not wep.STTS_NameLocked then
			local name = CharName(orig)
			if wep:GetNWString("STTS_PName", "") ~= name then wep:SetNWString("STTS_PName", name) end
		end
	end
end)

hook.Add("PlayerDisconnected", "STTS_Phone", function(ply)
	PHONE.Drop(ply)
end)

--[[---------------------------------------------------------------------------
	voice + chat over a connected line
---------------------------------------------------------------------------]]
-- the other side of a CONNECTED line + what kind of line it is
local function Peer(ply)
	local call = PHONE.Calls[ply]
	if call then
		if call.state == "connected" and IsValid(call.op) then return call.op, "caller" end
		return
	end
	local caller = PHONE.Ops[ply]
	if caller then
		call = PHONE.Calls[caller]
		if call and call.state == "connected" and call.op == ply and IsValid(caller) then return caller, "operator" end
		return
	end
	local link = PHONE.Links[ply]
	if link and link.state == "connected" then
		if link.a == ply and IsValid(link.b) then return link.b, "a" end
		if link.b == ply and IsValid(link.a) then return link.a, "b" end
	end
end

-- this side can talk / listen right now (phone in the hand; operator = headset)
local function OnLine(ply, kind)
	if kind == "operator" then return not ply:Alive() or Awake(ply) end
	if kind == "caller" then return Holding(ply) end
	local link = PHONE.Links[ply]
	if not link then return false end
	return Holding(ply, kind == "a" and link.aWep or link.bWep)
end

local function OtherKind(kind)
	if kind == "caller" then return "operator" end
	if kind == "operator" then return "caller" end
	return kind == "a" and "b" or "a"
end

-- how the speaker is shown on the other phone
local function LineName(ply, kind)
	if kind == "operator" then return "911" end
	if kind == "caller" then return "caller" end
	local link = PHONE.Links[ply]
	return PhoneName(link and (kind == "a" and link.aWep or link.bWep))
end

-- would hear / read him anyway, in person (same rules as sv_comunication).
-- bodies, not player entities: in a car the player entity sits at the map origin
local function Direct(listener, speaker)
	if not (speaker:Alive() and listener:Alive()) then return false end
	local a, b = BodyOf(listener):WorldSpaceCenter(), BodyOf(speaker):WorldSpaceCenter()
	return a:DistToSqr(b) < 3000 * 3000 and listener:TestPVS(b)
end

-- standing next to the phone (hears its speaker)
local function NearPhone(listener, holder)
	local d = CFG.PhoneSpeakerDist or 280
	return listener ~= holder and Awake(listener) and holder:Alive() and listener:GetPos():DistToSqr(BodyOf(holder):GetPos()) < d * d
end

-- chat message being sent by ZChat right now -> who already gets it through the phone
-- (filled by sv_compat.lua from HG_PlayerSay, sent a tick later with the final text)
PHONE.ChatPending = PHONE.ChatPending or {}

hook.Add("CanListenOthers", "STTS_Phone", function(output, input, isChat)
	if not IsValid(output) or not IsValid(input) or output == input then return end
	if isChat then
		local pend = PHONE.ChatPending[output]
		if pend and pend.tick == engine.TickCount() and pend.set[input] then return false end
		local peer, kind = Peer(output)
		if not peer then return end
		-- chat over the line is delivered by the relay below as "[phone] name: text"
		if input == peer and OnLine(output, kind) and OnLine(peer, OtherKind(kind)) then return false end
		if kind == "operator" and not Direct(input, output) then return false end -- spectator privacy; living cops still speak locally
		return
	end
	-- fix73: the voice goes from phone to phone (PHONE.Line73): whoever talks near one phone of a
	-- call is heard at the other one (and by the people next to it), not only the one holding it
	local a, b = PHONE.VoiceRoute72(input, output)
	if a then return a, b end
	local _, kind = Peer(output)
	if kind == "operator" then
		if Direct(input, output) then return true, true end -- living cops still speak locally
		return false -- other spectators never hear the operator
	end
end)

--[[ fix72 ("nobody is heard in a call"): the voice over the line came only through Z-City's
     CanListenOthers chain. another hook there (or in PlayerCanHearPlayersVoice: voice / admin /
     mode addons, custom builds) answering first = the line was silent. sv_compat.lua asks this
     after every foreign voice hook: it only ever ADDS hearing for a connected line, never
     takes any away. a gagged speaker (ULX / SAM / FAdmin, or hook STTS_PhoneCanTalk returning
     false), Z-City brain damage and Gordon stay silent ]]
function PHONE.Gagged72(ply)
	if ply.ulx_gagged or ply:GetNWBool("ulx_gagged", false) then return true end
	if ply.sam_get_nwvar then
		local ok, g = pcall(ply.sam_get_nwvar, ply, "gagged")
		if ok and g then return true end
	end
	if ply.FAdmin_GetGlobal then
		local ok, g = pcall(ply.FAdmin_GetGlobal, ply, "FAdmin_voicemuted")
		if ok and g then return true end
	end
	return hook.Run("STTS_PhoneCanTalk", ply) == false
end
-- fix73: answered from the map of the line (PHONE.Line73, rebuilt 10 times a second): a talker near
-- one phone of a call -> the listeners of the other phone. nil = the phone has nothing to say
function PHONE.VoiceRoute72(listener, speaker)
	if not (IsValid(listener) and IsValid(speaker)) or listener == speaker then return end
	local L = PHONE.Line73
	if not L then return end
	local m = L.voice[listener]
	if m and m[speaker] then return true, false end -- native voice has no source position: 2D, leveled by the client
	local c = L.close[listener]
	if c and c[speaker] then return true, true end -- the two stand close to each other: their own voices, in 3D
end

-- who reads a chat line of ply through his phone right now: the other side + the
-- people next to the other phone (nil = ply is not talking on a phone)
function PHONE.RelayTargets(ply)
	if not IsValid(ply) then return end
	if ply:Alive() and ply.organism and ply.organism.otrub then return end
	local peer, kind = Peer(ply)
	if not peer or not OnLine(ply, kind) or not OnLine(peer, OtherKind(kind)) then return end
	local recipients = {[peer] = true}
	if peer:Alive() then
		for _, p in player.Iterator() do
			if p ~= ply and p ~= peer and NearPhone(p, peer) then recipients[p] = true end
		end
	end
	return recipients, peer, kind
end

local lastRelay = setmetatable({}, {__mode = "k"})

-- text typed in the normal chat goes through the line
function PHONE.Relay(ply, text)
	if not IsValid(ply) or not isstring(text) or text == "" then return end
	local first = string.sub(text, 1, 1)
	if first == "!" or first == "/" then return end
	-- the same line twice right away (two chat integrations at once) goes out once
	local last = lastRelay[ply]
	if last and last.text == text and CurTime() - last.at < 1 then return last.set end
	local recipients, peer, kind = PHONE.RelayTargets(ply)
	if not recipients then return end

	local name = LineName(ply, kind)
	-- Phone text is a distinct channel even when participants are nearby.
	-- Return this message's recipient set so ZChat can skip ordinary duplicates.
	PhoneLine(peer, name, text)
	for p in pairs(recipients) do
		if p ~= peer then PhoneLine(p, name, text) end
	end
	lastRelay[ply] = {text = text, at = CurTime(), set = recipients}
	if not ply:IsBot() and peer:IsBot() and (ply.STTS_BotReplyCD or 0) <= CurTime() then
		ply.STTS_BotReplyCD = CurTime() + 2
		timer.Simple(1.2, function()
			if not IsValid(ply) or not IsValid(peer) or Peer(ply) ~= peer then return end
			local replies = {"Я понял.", "Да, слушаю.", "Хорошо."}
			PHONE.Relay(peer, replies[math.random(#replies)])
		end)
	end
	return recipients
end

-- debug: a living bot calls YOU (you play the 911 operator). needs stts_phone_debug 1
concommand.Add("stts_phone_testcall", function(ply)
	if not IsValid(ply) or not Debug() then return end
	if not (ply:IsSuperAdmin() or ply:IsListenServerHost()) then return end
	if not InRound() then ply:PrintMessage(HUD_PRINTCONSOLE, "[911] wait for the round to start") return end
	if PHONE.IsBusy(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[911] you are already on a call") return end

	local bot
	for _, b in RandomPairs(player.GetBots()) do
		if b:Alive() and not STTS.IsShooter(b) and not PHONE.IsBusy(b) then bot = b break end
	end
	if not bot then ply:PrintMessage(HUD_PRINTCONSOLE, "[911] no living bot victim. type 'bot' in console") return end

	if not bot:HasWeapon(PHONE_CLASS) then bot:Give(PHONE_CLASS) end
	PHONE.Calls[bot] = {state = "ringing", tried = {}, since = CurTime()}
	Ring(bot, ply)
	ply:PrintMessage(HUD_PRINTCONSOLE, "[911] " .. bot:Nick() .. " is calling you")
end)

--[[---------------------------------------------------------------------------
	fix73: the line of a call goes from PHONE to PHONE, not from player to player.
	Every phone of a connected call (phone-to-phone and the 911 caller; the 911
	operator talks over a headset) is a microphone and a speaker where it really is:
	  * in the hand / at the ear: at the eyes of its holder
	  * on the floor, on a table, leaning on a wall (placed with MMB / dropped / fallen
	    off a corpse): where the entity lies
	  * in a pocket / on the belt (another weapon in the hand): on its carrier, muffled
	Microphone (the same curve as the clip microphone of the recorder): a talker
	within 40 units = full voice, farther 40 / distance, 900+ = nothing, a wall
	between = 0.42, a pocket = 0.6.
	Speaker: the holder hears it at the ear (volume of the phone, at least 0.3), the
	carrier with the phone in his pocket quietly, everybody else within
	STTS.Config.PhoneSpeakerDist of the phone by distance (a wall = 0.35).
	Voice = GMod voice chat: PlayerCanHearPlayersVoice / CanListenOthers answer from
	this map (2D, the client sets the level per talker, stts_phone_voice_gain); two
	people standing within 360 units of each other keep their own 3D voices.
	Game sounds: a client with the native module fix73 says so (STTS_PhoneLine73);
	it gets the place of the other phone(s) 10 times a second and every game sound
	that is loud enough there (sv_phone_ear.lua), its DLL plays them as the phone's
	speaker (autorun/client/cl_stts_phone_line73.lua).
---------------------------------------------------------------------------]]
util.AddNetworkString("stts_phone_voice_gain")
util.AddNetworkString("STTS_PhoneLine73")
do
	local LINE = PHONE.Line73 or {}
	PHONE.Line73 = LINE
	LINE.voice = LINE.voice or {} -- listener -> {talker -> gain}
	LINE.close = LINE.close or {} -- listener -> {talker -> true}: on the line, but standing close
	LINE.ears = LINE.ears or {}   -- listener -> {source phone index -> {pos, muffle, gain}}
	LINE.earAt = LINE.earAt or {} -- listener -> where his ears are (sounds right there are not echoed back to him)
	local MIC_NEAR, MIC_FAR, CUT = 40, 900, 0.01
	local NEAR3D = 360
	local EAR_SELF = 600 -- standing at the other phone himself: hears those sounds anyway
	local trIn, trOut = {mask = MASK_SOLID_BRUSHONLY}, {}
	trIn.output = trOut
	local function Blocked(a, b)
		trIn.start, trIn.endpos = a, b
		util.TraceLine(trIn)
		return trOut.Hit and trOut.Fraction < 0.97 and not trOut.StartSolid
	end
	local function CanTalk(t)
		if not Awake(t) then return false end
		local org = t.organism
		if org and (tonumber(org.brain) or 0) > 0.05 then return false end
		if t.PlayerClassName == "Gordon" then return false end
		return not PHONE.Gagged72(t)
	end
	-- where an end of the line is right now (nil = it can not hear / talk now)
	local function Geo(e)
		if e.headset then
			local o = e.headset
			if not IsValid(o) or not (not o:Alive() or Awake(o)) then return end
			return {headset = o, id = o:EntIndex()}
		end
		local w = e.wep
		if not IsValid(w) then return end
		local g = {wep = w, id = w:EntIndex()}
		local owner = w:GetOwner()
		if IsValid(owner) and owner:IsPlayer() then
			g.carrier = owner
			if owner:Alive() and (owner:GetActiveWeapon() == w or PHONE.InLeftHand(owner, w)) then -- fix74: + the left hand
				g.pos = CharEye(owner)
				if Awake(owner) then g.holder = owner end
			else
				g.pos = BodyOf(owner):WorldSpaceCenter()
				g.pocket = true
			end
			return g
		end
		local par = w:GetParent()
		if IsValid(par) then
			g.pos, g.pocket = par:WorldSpaceCenter(), true
		else
			g.pos = w:WorldSpaceCenter()
		end
		return g
	end
	LINE.Geo = Geo
	-- who is heard by this phone's microphone, how loud
	local function Talkers(S)
		local out = {}
		if S.headset then
			local o = S.headset
			if not PHONE.Gagged72(o) then out[o] = 1 end
			return out
		end
		for _, t in player.Iterator() do
			local g
			if not CanTalk(t) then g = nil
			elseif t == S.holder then g = 1
			else
				local mouth = CharEye(t)
				local d = mouth:Distance(S.pos)
				if d < MIC_FAR then
					g = d <= MIC_NEAR and 1 or MIC_NEAR / d
					if Blocked(S.pos, mouth) then g = g * 0.42 end
				end
			end
			if g then
				if S.pocket then g = g * 0.6 end
				if g >= CUT then out[t] = g end
			end
		end
		return out
	end
	-- who hears this phone's speaker, how loud
	local function Listeners(K)
		local out = {}
		if K.headset then
			if not K.headset:IsBot() then out[K.headset] = 1 end
			return out
		end
		local vol = PhoneVol(K.wep)
		local radius = CFG.PhoneSpeakerDist or 280
		if K.pocket then radius = radius * 0.5 end
		for _, p in player.Iterator() do
			local g
			if p:IsBot() or not Awake(p) then g = nil
			elseif p == K.holder then
				g = math.max(vol, 0.3) -- fix72: your own ear: a ringer set to 0 never makes the call silent
			elseif p == K.carrier then
				g = 0.3 * math.max(vol, 0.3) -- in your own pocket
			else
				local ear = CharEye(p)
				local d = ear:Distance(K.pos)
				if d < radius then
					g = (1 - d / radius) * vol
					if g > 0 and Blocked(K.pos, ear) then g = g * 0.35 end
					if K.pocket then g = g * 0.4 end
				end
			end
			if g and g > 0.005 then out[p] = math.min(g, 1) end
		end
		return out
	end
	local function Near(p, t)
		if not (p:Alive() and t:Alive()) then return false end
		local a, b = BodyOf(p):WorldSpaceCenter(), BodyOf(t):WorldSpaceCenter()
		return a:DistToSqr(b) < NEAR3D * NEAR3D and p:TestPVS(b)
	end
	-- both directions of every connected call
	local function Directions()
		local out = {}
		for caller, call in pairs(PHONE.Calls) do
			if IsValid(caller) and call.state == "connected" and IsValid(call.op) then
				local wep = PhoneOf(caller)
				if wep then
					local a, b = {wep = wep}, {headset = call.op}
					out[#out + 1] = {a, b}
					out[#out + 1] = {b, a}
				end
			end
		end
		local seen = {}
		for _, link in pairs(PHONE.ByWep) do
			if not seen[link] and not link.ended and link.state == "connected" and IsValid(link.aWep) and IsValid(link.bWep) then
				seen[link] = true
				local a, b = {wep = link.aWep}, {wep = link.bWep}
				out[#out + 1] = {a, b}
				out[#out + 1] = {b, a}
			end
		end
		return out
	end
	function LINE.Rebuild()
		local voice, close, ears, earAt = {}, {}, {}, {}
		local geo = {}
		for _, d in ipairs(Directions()) do
			local src, dst = d[1], d[2]
			if geo[src] == nil then geo[src] = Geo(src) or false end
			if geo[dst] == nil then geo[dst] = Geo(dst) or false end
			local S, K = geo[src], geo[dst]
			if S and K then
				local talk, hear = Talkers(S), Listeners(K)
				for p, gk in pairs(hear) do
					for t, gs in pairs(talk) do
						local g = gs * gk
						if t ~= p and g >= CUT then
							if Near(p, t) then
								close[p] = close[p] or {}
								close[p][t] = true
							else
								local m = voice[p]
								if not m then m = {} voice[p] = m end
								if g > (m[t] or 0) then m[t] = g end
							end
						end
					end
					-- the game sounds around S, played by p's native module (fix73)
					if S.pos and p.STTS_Line73 and gk >= 0.02 and CharEye(p):DistToSqr(S.pos) > EAR_SELF * EAR_SELF then
						local e = ears[p]
						if not e then e = {} ears[p] = e earAt[p] = CharEye(p) end
						local old = e[S.id]
						if not old or old.gain < gk then e[S.id] = {pos = S.pos, muffle = (S.pocket or K.pocket) and true or false, gain = gk} end
					end
				end
			end
		end
		-- a talker both heard on the line and standing close: his own voice wins
		for p, m in pairs(voice) do
			local c = close[p]
			if c then for t in pairs(c) do m[t] = nil end end
		end
		LINE.voice, LINE.close, LINE.ears, LINE.earAt = voice, close, ears, earAt
	end
	-- a client with the native module fix73 can play the sounds of the line
	net.Receive("STTS_PhoneLine73", function(_, ply)
		if not IsValid(ply) then return end
		local on = net.ReadBool()
		if (ply.STTS_Line73At or 0) > CurTime() then return end
		ply.STTS_Line73At = CurTime() + 0.5
		ply.STTS_Line73 = on or nil
	end)
	timer.Create("STTS_PhoneVoiceGain", 0.1, 0, function()
		local ok, err = pcall(LINE.Rebuild)
		if not ok then
			LINE.voice, LINE.close, LINE.ears, LINE.earAt = {}, {}, {}, {}
			if (LINE.errAt or 0) < CurTime() then LINE.errAt = CurTime() + 30 ErrorNoHalt("[ZPHONE] line: " .. tostring(err) .. "\n") end
		end
		local SE = STTS.PhoneEarSv
		if SE and SE.SetLines73 then SE.SetLines73(LINE.ears, LINE.earAt) end
		for _, listener in ipairs(player.GetHumans()) do
			-- the level of every talker heard through a phone (an empty update after the call clears it)
			local m = LINE.voice[listener]
			local n = 0
			if m then for _ in pairs(m) do n = n + 1 end end
			if n > 0 or listener.STTS_HadVoiceGain then
				n = math.min(n, 255)
				net.Start("stts_phone_voice_gain")
					net.WriteUInt(n, 8)
					local i = 0
					for t, g in pairs(m or {}) do
						i = i + 1
						if i > n then break end
						net.WriteUInt(IsValid(t) and t:UserID() or 0, 16)
						net.WriteUInt(math.Clamp(math.floor(g * 255 + 0.5), 0, 255), 8)
					end
				net.Send(listener)
			end
			listener.STTS_HadVoiceGain = n > 0
			-- where the other phone is (its game sounds come from sv_phone_ear.lua)
			local e = LINE.ears[listener]
			local k = 0
			if e then for _ in pairs(e) do k = k + 1 end end
			if k > 0 or listener.STTS_HadLine73 then
				k = math.min(k, 7)
				net.Start("STTS_PhoneLine73", k > 0)
					net.WriteUInt(0, 2)
					net.WriteUInt(k, 3)
					local i = 0
					for id, l in pairs(e or {}) do
						i = i + 1
						if i > k then break end
						net.WriteUInt(id, 16)
						net.WriteVector(l.pos)
						net.WriteBool(l.muffle)
						net.WriteUInt(math.Clamp(math.floor(l.gain * 255 + 0.5), 0, 255), 8)
					end
				net.Send(listener)
			end
			listener.STTS_HadLine73 = k > 0
		end
	end)
end

--[[---------------------------------------------------------------------------
	screen state of every phone (NW2 on the weapon, read by every client)
	CallSt CallName CallSince PeerIdx PeerVid PeerBack  - from the call logic
	App Sel Scroll Gal                                  - from the holder
	VidOn CamFront                                      - from the buttons (rear camera unless CamFront)
---------------------------------------------------------------------------]]
local function SyncPhone(wep)
	local st, name, since, peer = G.CALL_NONE, "", 0, nil
	local ring = PHONE.Ringing[wep]
	if ring and not ring.ended then st, name, since = G.CALL_IN, PhoneName(ring.aWep), ring.since end
	local link = PHONE.ByWep[wep]
	if link and not link.ended then
		if link.state == "ringing" then
			st, name, since = G.CALL_OUT, PhoneName(link.bWep), link.since
		else
			peer = link.aWep == wep and link.bWep or link.aWep
			st, name, since = G.CALL_ON, PhoneName(peer), link.since
		end
	end
	local holder = wep:GetOwner()
	local call = IsValid(holder) and holder:IsPlayer() and PHONE.Calls[holder]
	if call and PhoneOf(holder) == wep then
		st, name, since = call.state == "connected" and G.CALL_ON or G.CALL_OUT, "911", call.since or 0
	end
	if wep:GetNW2Int("CallSt", 0) ~= st then wep:SetNW2Int("CallSt", st) end
	if wep:GetNW2String("CallName", "") ~= name then wep:SetNW2String("CallName", name) end
	if wep:GetNW2Float("CallSince", 0) ~= since then wep:SetNW2Float("CallSince", since) end
	local pidx = IsValid(peer) and peer:EntIndex() or 0
	if wep:GetNW2Int("PeerIdx", 0) ~= pidx then wep:SetNW2Int("PeerIdx", pidx) end
	local pv = IsValid(peer) and peer:GetNW2Bool("VidOn", false) or false
	if wep:GetNW2Bool("PeerVid", false) ~= pv then wep:SetNW2Bool("PeerVid", pv) end
	local pb = IsValid(peer) and not peer:GetNW2Bool("CamFront", false) or false
	if wep:GetNW2Bool("PeerBack", false) ~= pb then wep:SetNW2Bool("PeerBack", pb) end
	-- the other phone went into a pocket / inventory: its video is just black
	local pp = IsValid(peer) and PHONE.InPocket(peer) or false
	if wep:GetNW2Bool("PeerPocket", false) ~= pp then wep:SetNW2Bool("PeerPocket", pp) end
	if st ~= G.CALL_ON and wep:GetNW2Bool("VidOn", false) then wep:SetNW2Bool("VidOn", false) end
end
PHONE.SyncPhone = SyncPhone

timer.Create("STTS_PhoneScreenSync", 0.1, 0, function()
	for _, wep in ipairs(ents.FindByClass(PHONE_CLASS)) do SyncPhone(wep) end
end)
timer.Create("STTS_PhoneBookSync", 2, 0, function() SendBook() end)

net.Receive("stts_phone_scr", function(_, ply)
	local wep = ply:GetActiveWeapon()
	local app, sel, scroll, gal, galv = net.ReadUInt(5), net.ReadUInt(8), net.ReadUInt(10), net.ReadUInt(8), net.ReadUInt(8) -- fix17: scroll in 1/4 rows, v19.2: app in 5 bits
	local fx, fy = net.ReadUInt(8), net.ReadUInt(8) -- finger point (UI px / 2, / 4)
	local shade = net.ReadUInt(6) -- fix17: pull-down shade 0..40
	if not IsValid(wep) or wep:GetClass() ~= PHONE_CLASS or not Awake(ply) then return end
	if app < G.APP_HOME or app > (G.APP_LAST or G.APP_SEND) then return end
	wep:SetNW2Int("App", app)
	wep:SetNW2Int("Sel", sel)
	wep:SetNW2Int("Scroll", scroll)
	wep:SetNW2Int("Gal", gal)
	wep:SetNW2Int("GalV", galv) -- gallery screen: view * 4 + album
	wep:SetNW2Int("FX", math.min(fx, 216))
	wep:SetNW2Int("FY", math.min(fy, 240))
	wep:SetNW2Int("Shade", math.min(shade, 40))
end)

--[[ camera poses for video calls ]]
net.Receive("stts_phone_pose", function(_, ply)
	local wep = ply:GetActiveWeapon()
	local pos, ang = net.ReadVector(), net.ReadAngle()
	local hasRel = net.ReadBool()
	local rp, ra
	if hasRel then rp, ra = net.ReadVector(), net.ReadAngle() end
	if not IsValid(wep) or wep:GetClass() ~= PHONE_CLASS then return end
	if pos:DistToSqr(CharEye(ply)) > 72 * 72 then return end -- has to be in your hands (ragdoll / car too)
	if rp and rp:LengthSqr() > 72 * 72 then rp, ra = nil, nil end
	wep.STTS_Pose, wep.STTS_PoseAt = {pos, ang, rp, ra}, CurTime()
end)

-- where the phone physically is (held / in the world / in a pocket)
function PHONE.WorldPos(wep)
	local owner = wep:GetOwner()
	if IsValid(owner) then return owner:IsPlayer() and CharEye(owner) or owner:WorldSpaceCenter() end
	local par = wep:GetParent()
	if IsValid(par) then return par:WorldSpaceCenter() end
	return wep:GetPos()
end

local function PhonePose(wep)
	local owner = wep:GetOwner()
	if IsValid(owner) and owner:IsPlayer() then
		if wep.STTS_Pose and CurTime() - (wep.STTS_PoseAt or 0) < 0.6 then
			local p = wep.STTS_Pose
			return p[1], p[2], p[3], p[4]
		end
		-- fix24: ragdoll = the phone is where the ragdoll's real hand holds it
		if wep.FakePose then
			local fp, fa = wep:FakePose()
			if fp then return fp, fa end
		end
		local o, ang = G.RefFrame(owner)
		if not o then -- ragdoll / car: the fix8 pose
			ang = owner:EyeAngles()
			local p = owner:EyePos() + ang:Forward() * 13 - ang:Up() * 5.5
			local n = (owner:EyePos() - p):GetNormalized()
			local top = ang:Up() - n * ang:Up():Dot(n)
			return p, top:GetNormalized():AngleEx(n)
		end
		if wep.PoseAt then
			local p, a = wep:PoseAt("video", o, ang)
			return p, a, WorldToLocal(p, a, o, ang)
		end
		return o, ang
	end
	return wep:GetPos(), wep:GetAngles()
end

PHONE.PhonePose = PhonePose

-- one pose packet of the camera of src (front / rear) to the players in "to"
local function SendFeed(src, to, back, cam)
	if #to == 0 then return end
	local pos, ang, rp, ra = PhonePose(src)
	cam = cam or G.CamWorld(pos, ang, back, src)
	for _, p in ipairs(to) do p.STTS_PVSAdd, p.STTS_PVSAt = cam, CurTime() end
	net.Start("stts_phone_feed", true)
		net.WriteUInt(src:EntIndex(), 16)
		net.WriteVector(pos)
		net.WriteAngle(ang)
		net.WriteBool(back)
		net.WriteUInt(math.Clamp(math.Round(src:GetNW2Float("Zoom", 1) * 40), 40, 255), 8)
		net.WriteBool(rp ~= nil)
		if rp then net.WriteVector(rp) net.WriteAngle(ra) end
	net.Send(to)
end
PHONE.SendFeed = SendFeed

local FEED_DIST = 450
timer.Create("STTS_PhoneFeeds", 1 / 15, 0, function()
	local seen = {}
	for _, link in pairs(PHONE.ByWep) do
		if seen[link] or link.ended or link.state ~= "connected" then continue end
		seen[link] = true
		for _, pair in ipairs({{link.aWep, link.bWep}, {link.bWep, link.aWep}}) do
			local src, dst = pair[1], pair[2]
			if not IsValid(src) or not IsValid(dst) or not src:GetNW2Bool("VidOn", false) then continue end
			if PHONE.InPocket(src) then continue end -- in a pocket: black, nothing to stream
			local pos, ang, rp, ra = PhonePose(src)
			local back = not src:GetNW2Bool("CamFront", false)
			local cam = G.CamWorld(pos, ang, back, src)
			-- whoever can see the other phone's display: its holder + people next to it
			local where = PHONE.WorldPos(dst)
			local to = {}
			for _, p in player.Iterator() do
				if p:IsBot() then continue end
				if dst:GetOwner() == p or p:EyePos():DistToSqr(where) < FEED_DIST * FEED_DIST then
					to[#to + 1] = p
					p.STTS_PVSAdd, p.STTS_PVSAt = cam, CurTime()
				end
			end
			if #to == 0 then continue end
			net.Start("stts_phone_feed", true)
				net.WriteUInt(src:EntIndex(), 16)
				net.WriteVector(pos)
				net.WriteAngle(ang)
				net.WriteBool(back)
				net.WriteUInt(math.Clamp(math.Round(src:GetNW2Float("Zoom", 1) * 40), 40, 255), 8)
				net.WriteBool(rp ~= nil)
				if rp then net.WriteVector(rp) net.WriteAngle(ra) end
			net.Send(to)
		end
	end

	-- fix12: 911 video, the caller's camera goes to his operator only
	for caller, call in pairs(PHONE.Calls) do
		local op = call.op
		if call.state ~= "connected" or not IsValid(caller) or not IsValid(op) or op:IsBot() then continue end
		local src = PhoneOf(caller)
		if not src or not src:GetNW2Bool("VidOn", false) or PHONE.InPocket(src) then continue end
		SendFeed(src, {op}, not src:GetNW2Bool("CamFront", false))
	end

	-- fix15: a phone that is recording but left its recorder's hands (dropped, taken,
	-- the recorder died): his PC keeps rendering it, it needs the pose + PVS
	for _, w in ipairs(ents.FindByClass(PHONE_CLASS)) do
		if w:GetNW2Int("CamMode", 0) ~= 2 then continue end
		local by = w:GetNW2Entity("RecBy", NULL)
		if not IsValid(by) or CurTime() - w:GetNW2Float("RecAt", 0) > (G.VidMaxSec or 120) + 5 then
			-- time is up / recorder left: the shutter turns back
			if IsValid(by) then by.STTS_RecUntil = CurTime() + 90 end
			w:SetNW2Entity("RecBy", NULL)
			w:SetNW2Int("CamMode", 1)
			continue
		end
		if by:IsBot() or (w:GetOwner() == by and by:Alive() and by:GetActiveWeapon() == w) then continue end
		-- fix16: fell into a corpse's pocket: out into the world right away (keeps filming)
		if not IsValid(w:GetOwner()) and IsValid(w:GetParent()) then EnsureInWorld(w) end
		if PHONE.InPocket(w) then continue end
		SendFeed(w, {by}, not w:GetNW2Bool("CamFront", false))
	end

	-- fix12: spectators watching a phone from the camera map (sv_shooting_cameras.lua)
	local watch = {}
	for _, p in player.Iterator() do
		local src = p.ZHCamPhone
		if p.ZHCamSpec and IsValid(src) and not p:IsBot() then
			local back = p.ZHCamPhoneBack == true
			local key = src:EntIndex() * 2 + (back and 1 or 0)
			watch[key] = watch[key] or {src = src, back = back, to = {}}
			table.insert(watch[key].to, p)
		end
	end
	for _, w in pairs(watch) do SendFeed(w.src, w.to, w.back) end
end)

-- fix12: what the 911 console needs to show the caller's video (NW2 on the operator)
timer.Create("STTS_Phone911Video", 0.2, 0, function()
	local live = {}
	for caller, call in pairs(PHONE.Calls) do
		local op = call.op
		if call.state == "connected" and IsValid(caller) and IsValid(op) then
			local src = PhoneOf(caller)
			if src then
				live[op] = true
				local vid = src:GetNW2Bool("VidOn", false) and not PHONE.InPocket(src)
				if op:GetNW2Int("ZH911Phone", 0) ~= src:EntIndex() then op:SetNW2Int("ZH911Phone", src:EntIndex()) end
				if op:GetNW2Bool("ZH911Vid", false) ~= vid then op:SetNW2Bool("ZH911Vid", vid) end
				local back = not src:GetNW2Bool("CamFront", false)
				if op:GetNW2Bool("ZH911Back", true) ~= back then op:SetNW2Bool("ZH911Back", back) end
			end
		end
	end
	for _, p in player.Iterator() do
		if not live[p] and (p:GetNW2Int("ZH911Phone", 0) ~= 0 or p:GetNW2Bool("ZH911Vid", false)) then
			p:SetNW2Int("ZH911Phone", 0)
			p:SetNW2Bool("ZH911Vid", false)
		end
	end
end)

-- entities around the remote camera are networked to the viewer, so the video shows people
hook.Add("SetupPlayerVisibility", "STTS_PhoneFeedPVS", function(ply)
	if ply.STTS_PVSAdd and CurTime() - (ply.STTS_PVSAt or 0) < 0.5 then AddOriginToPVS(ply.STTS_PVSAdd) end
end)

-- a video phone that went into a corpse's pocket falls out instead
hook.Add("PostPlayerDeath", "STTS_PhoneVideoDrop", function(ply)
	timer.Simple(0.25, function()
		for _, link in pairs(PHONE.ByWep) do
			if link.ended then continue end
			for _, w in ipairs({link.aWep, link.bWep}) do
				if IsValid(w) and not IsValid(w:GetOwner()) and LinkVideo(link) then EnsureInWorld(w) end
			end
		end
		-- fix15: a phone that is recording a video falls out of the dead hand too (keeps filming)
		for _, w in ipairs(ents.FindByClass(PHONE_CLASS)) do
			if w:GetNW2Int("CamMode", 0) == 2 and IsValid(w:GetNW2Entity("RecBy", NULL)) and not IsValid(w:GetOwner()) then EnsureInWorld(w) end
		end
	end)
end)

--[[ fix66: unconscious (Z-City otrub) / dead = the phone FALLS out of the hand.
     Z-City drops the weapon in the hand (hook "PlayerDropWeapon") and welds it to the
     ragdoll's right hand 0.1 s later: a phone stuck to the hand of a lying body. only the
     phone gets its weld to the body removed (other weapons keep Z-City's behaviour), it
     drops with the speed of the hand and does not collide with that body ]]
function PHONE.Loose66(ply)
	if not IsValid(ply) then return end
	local rags = {}
	for _, r in ipairs({ply.FakeRagdoll, ply.RagdollDeath, ply:GetNWEntity("RagdollDeath", NULL), ply:GetNWEntity("FakeRagdoll", NULL)}) do
		if IsValid(r) then rags[r] = true end
	end
	if not next(rags) then return end
	for _, w in ipairs(ents.FindByClass(PHONE_CLASS)) do
		if IsValid(w:GetOwner()) or IsValid(w:GetParent()) then continue end
		local rag
		for _, c in ipairs(constraint.FindConstraints(w, "Weld") or {}) do
			local other = c.Ent1 == w and c.Ent2 or c.Ent1
			if IsValid(other) and rags[other] and IsValid(c.Constraint) then
				rag = other
				c.Constraint:Remove()
			end
		end
		if not rag then continue end
		w:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		constraint.NoCollide(w, rag, 0, 0)
		local phys = w:GetPhysicsObject()
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
			local bone = rag:LookupBone("ValveBiped.Bip01_R_Hand")
			local hp = bone and rag:GetPhysicsObjectNum(rag:TranslateBoneToPhysBone(bone))
			if IsValid(hp) then phys:SetVelocity(hp:GetVelocity() * 0.8) end
		end
	end
end
hook.Add("PlayerDropWeapon", "STTS_PhoneLoose66", function(ply)
	if not IsValid(ply) then return end
	for _, d in ipairs({0.2, 0.5, 1.2}) do
		timer.Simple(d, function() PHONE.Loose66(ply) end)
	end
end)

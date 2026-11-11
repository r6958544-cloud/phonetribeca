--[[---------------------------------------------------------------------------
	fix58: lock screen (cl_phone_lock.lua draws it). the server only keeps the state:
	NW2 "Unlk" on the phone = unlocked. fix61: it goes back to false when the Auto-Lock
	time is over after the phone left the hand (see below), so the next one who looks at
	it (or you, when you take it out again) sees the lock screen.
	no passcode: anybody who holds the phone can swipe it open, like Face ID that
	always says yes. a video that is being recorded goes on (fix16), only the screen locks.
---------------------------------------------------------------------------]]
STTS = STTS or {}

function STTS.PhoneLockAct(ply, wep, isPhone, act, arg)
	if act ~= "unlock" and act ~= "lock" then return end
	-- only the phone in your hands, and only while it is raised (you look at it)
	if isPhone and (act == "lock" or wep:GetRaised()) then wep:SetNW2Bool("Unlk", act == "unlock") end
	return true
end

--[[---------------------------------------------------------------------------
	fix61: Auto-Lock (Settings > Display & Brightness > Auto-Lock, NW2 "ALock",
	G.AutoLock). the phone no longer locks the moment it leaves the hand:
	  * dropped / thrown on the floor: stays as it was (unlocked, display on) for the
	    whole Auto-Lock time
	  * put away (pocket / inventory, another item taken): half of that time
	  * Never: it stays on
	NW2 "LkAt" = when the display goes out (CurTime). the clients dim it for the last
	seconds and fade it to black after LkAt (cl_phone_lock.lua); FADE later the server
	locks it and switches the display off (NW2 "Off" = black, nothing is drawn).
	taken into the hand again = awake (Deploy). a new message lights the display up for
	a moment (lock screen with the notification); a call / a ringing alarm too (client).
	a video recording goes on the whole time (fix16): only the display changes.
---------------------------------------------------------------------------]]
local G = STTS.PhoneGeo
local AL = STTS.PhoneAutoLock or {}
STTS.PhoneAutoLock = AL
AL.Q = AL.Q or setmetatable({}, {__mode = "k"})
local FADE = 0.8   -- s after LkAt: locked + off (the clients fade out in 0.6 s)
local PING = 8     -- s the display stays on for a new message

local function InHand(wep)
	local o = wep:GetOwner()
	return IsValid(o) and o:IsPlayer() and o:Alive() and o:GetActiveWeapon() == wep
end
AL.InHand = InHand

-- the phone left the hand: k = 1 on the floor, 0.5 in the pocket / inventory
function AL.Start(wep, k)
	if not IsValid(wep) or wep:GetNW2Bool("Off", false) then return end
	local secs = G.AutoLockSecs and G.AutoLockSecs(wep:GetNW2Int("ALock", 0)) or 30
	if secs <= 0 then -- Never
		wep:SetNW2Float("LkAt", 0)
		AL.Q[wep] = nil
		return
	end
	k = k or 1
	if k < 1 and not IsValid(wep:GetOwner()) then k = 1 end -- nobody has it: it is on the floor
	local now = CurTime()
	local at = now + secs * k
	-- from the pocket onto the floor (or back): the time counts from the first time.
	-- a drop out of the hand can come right after a Holster: then it is the floor time
	local cur = wep:GetNW2Float("LkAt", 0)
	local justPut = wep.STTS_ALk and wep.STTS_ALk < k and now - (wep.STTS_ALat or 0) < 0.5
	if cur > now and not justPut then at = math.min(cur, at) end
	wep.STTS_ALk, wep.STTS_ALat = k, now
	wep:SetNW2Float("LkAt", at)
	AL.Q[wep] = true
end
-- in the hand again: awake, no countdown
function AL.Wake(wep)
	if not IsValid(wep) then return end
	wep.STTS_ALk = nil
	if wep:GetNW2Float("LkAt", 0) ~= 0 then wep:SetNW2Float("LkAt", 0) end
	if wep:GetNW2Bool("Off", false) then wep:SetNW2Bool("Off", false) end
	AL.Q[wep] = nil
end
-- something new to show (a message) on a phone that is not in a hand: lit up for a moment
function AL.Ping(wep, secs)
	if not IsValid(wep) or InHand(wep) then return end
	local at = wep:GetNW2Float("LkAt", 0)
	if not wep:GetNW2Bool("Off", false) and at <= 0 then return end -- on anyway (Never)
	wep:SetNW2Bool("Off", false)
	wep:SetNW2Float("LkAt", math.max(at, CurTime() + (secs or PING)))
	AL.Q[wep] = true
end
-- the inventory recreated the phone (weapon_stts_phone.lua SetInfo): the countdown goes on
function AL.Restore(wep, at, off)
	if not IsValid(wep) then return end
	at = tonumber(at) or 0
	if off then wep:SetNW2Bool("Off", true) end
	if at > 0 and not off then
		wep:SetNW2Float("LkAt", at)
		AL.Q[wep] = true
	end
end

timer.Create("STTS_PhoneAutoLock", 0.2, 0, function()
	local now = CurTime()
	--[[ fix72 ("the phone does not turn on, all black"): a phone in a hand is never dark. the
	     display could stay off in the hand when an inventory / another addon gave the phone
	     back without a Deploy, or put the saved "off" back on after it (SetInfo) ]]
	for _, ply in player.Iterator() do
		local w = ply:Alive() and ply:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "weapon_stts_phone" and now - (w.STTS_ALat or 0) > 1
			and (w:GetNW2Bool("Off", false) or w:GetNW2Float("LkAt", 0) ~= 0) then AL.Wake(w) end -- (not in the tick it is put away)
	end
	for wep in pairs(AL.Q) do
		if not IsValid(wep) then AL.Q[wep] = nil continue end
		local at = wep:GetNW2Float("LkAt", 0)
		if at <= 0 then AL.Q[wep] = nil
		elseif InHand(wep) then AL.Wake(wep)
		elseif now >= at + FADE then
			wep:SetNW2Bool("Unlk", false)
			wep:SetNW2Bool("Off", true)
			wep:SetNW2Float("LkAt", 0)
			AL.Q[wep] = nil
		end
	end
end)

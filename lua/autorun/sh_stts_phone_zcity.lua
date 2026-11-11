--[[---------------------------------------------------------------------------
	ZPhone for Z-City (standalone addon) - shared part.
	The phone used to live inside the ZHunter game mode. Everything that mode
	provided to the phone is here now, everything Z-City itself had to be edited
	for is done from the outside at runtime (lua/stts_phone/cl_compat.lua,
	sv_compat.lua and the hand rule below), so vanilla Z-City stays untouched.
	load order: sh_stts_phone.lua -> sh_stts_phone_place.lua -> this file ->
	autorun/server/sv_stts_phone_zcity.lua | autorun/client/zz_stts_phone_zcity.lua
---------------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

STTS = STTS or {}
STTS.Config = STTS.Config or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end

STTS.ZPhoneStandalone = true

-- phone settings the game mode used to define (a mode loaded later may override them)
local CFG = STTS.Config
local function Def(key, value) if CFG[key] == nil then CFG[key] = value end end
Def("RingTime", 18)          -- 911: an operator has this long to answer, then the call goes to the next one
Def("PhoneRingTime", 25)     -- phone-to-phone: rings this long, then "No answer"
Def("PhoneSpeakerDist", 280) -- people this close to a phone hear the other side (voice + chat)
Def("CallNeedsSight", false) -- ZHunter only: 911 works after you saw the shooter. Z-City has no shooter
Def("SightDistance", 3500)
Def("SightFOV", 55)
Def("PoliceETAMin", 50)      -- 911 dispatch: the police arrive this many seconds later (Homicide)
Def("PoliceETAMax", 100)

-- ZHunter marks its shooters with this NW bool; nobody has it in plain Z-City
if not STTS.IsShooter then
	function STTS.IsShooter(ply)
		return IsValid(ply) and ply:GetNWBool("STTS_Shooter", false)
	end
end

--[[ while a call is going on the left hand keeps the phone at the ear even where
     Z-City would take that hand away (car wheel, chat gesture, flashlight...).
     only a missing arm and handcuffs still win. wrapped once hg.CanUseLeftHand
     exists, re-wrapped if Z-City is reloaded ]]
local PHONE_CLASS = "weapon_stts_phone"
local wrappedLeft
local function WrapLeftHand()
	if not (hg and isfunction(hg.CanUseLeftHand)) or hg.CanUseLeftHand == wrappedLeft then return end
	local orig = hg.CanUseLeftHand
	wrappedLeft = function(ply, ...)
		if IsValid(ply) and ply.GetActiveWeapon then
			local ent = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
			local wep = ply:GetActiveWeapon()
			if not (ent.organism and ent.organism.larmamputated) and IsValid(wep) and wep:GetClass() == PHONE_CLASS
				and wep.GetInCall and wep:GetInCall() then
				return not ply:GetNetVar("handcuffed", false)
			end
			--[[ fix74: the phone in the left hand, a pistol / knife in the right one
			     (weapon_stts_phone.lua, STTS.PhoneRH): the hand is busy for the weapon
			     (held one-handed, no flashlight), free only for the arm IK that brings
			     it to the phone. a reload / a door (zmanip) = Z-City decides as always ]]
			local RH = STTS.PhoneRH
			if RH and RH.Phone and RH.Phone(ply) then
				if CLIENT and RH.ikPly == ply then
					return not (ent.organism and ent.organism.larmamputated) and not ply:GetNetVar("handcuffed", false)
				end
				if not (IsValid(wep) and wep.reload) and not ply.zmanipstart then return false end
			end
		end
		return orig(ply, ...)
	end
	hg.CanUseLeftHand = wrappedLeft
end
WrapLeftHand()
hook.Add("InitPostEntity", "STTS_ZPhoneLeftHand", WrapLeftHand)
hook.Add("HomigradRun", "STTS_ZPhoneLeftHand", WrapLeftHand)
timer.Create("STTS_ZPhoneLeftHand", 5, 0, WrapLeftHand)

-- fix58: the phone in a vehicle (hands on the wheel / at the phone, steering blocked meanwhile)
if SERVER then AddCSLuaFile("stts_phone/sh_phone_car.lua") end
include("stts_phone/sh_phone_car.lua")

-- fix71: protected phone hooks, stand-ins for functions a custom Z-City build lacks, zhphone_compat
if SERVER then AddCSLuaFile("stts_phone/sh_safe71.lua") end
include("stts_phone/sh_safe71.lua")

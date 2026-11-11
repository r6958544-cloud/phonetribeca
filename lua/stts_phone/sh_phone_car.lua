--[[---------------------------------------------------------------------------
	fix58: the phone in a vehicle (Glide base of Z-City, simfphys, HL2 vehicles).
	nothing of Z-City / Glide is edited, it is all wrapped at runtime:

	hands (client)  hg.MainTPIKFunction (homigrad/cl_tpik.lua) puts the LEFT hand on
	                the wheel after the weapon posed it, so the phone was glued to
	                the wheel. while the phone is the active weapon in a vehicle the
	                wheel part of that function is skipped (the same switch Z-City
	                uses for a reload) and the phone places both hands itself
	                (weapon_stts_phone.lua, SetHandPos / DoFinger):
	                  phone down       left hand on the wheel (phone in the palm),
	                                   the right one on the wheel too
	                  phone raised     the left hand holds it in front of the face
	                  (portrait / T)   (landscape too: one hand, the left thumb),
	                                   the right hand stays ON THE WHEEL
	                  "in action"      the right hand leaves the wheel and goes to
	                                   the display (portrait: index finger,
	                                   landscape: grabs the right end, two thumbs)
	                in action = LMB on the display or moving the finger (mouse).
	                back to the wheel: stts_phone_car_idle seconds without touching /
	                moving, a steer key (A / D, stts_phone_car_keyreturn), RMB, R.
	                the first LMB only brings the hand (it does not tap yet).
	steering (srv)  while the hand is in action (+ the moment it needs back to the
	                wheel) the driver can NOT steer: Glide's steer / pitch / yaw /
	                roll input of seat 1 reads 0 (cars: the wheel self-centres, a
	                little wobble with hg_glide_steering_realism, like a reload).
	                LMB does not fire the vehicle weapons while the phone is in the
	                hand, R (horn / switch weapon) does nothing while it is raised.
---------------------------------------------------------------------------]]
STTS = STTS or {}
local PC = STTS.PhoneCar or {}
STTS.PhoneCar = PC
local CLASS = "weapon_stts_phone"

local blockCvar = CreateConVar("stts_phone_car_block", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix58: 1 = a driver can not steer while his hand is at the phone (Glide)", 0, 1)
local wobbleCvar = CreateConVar("stts_phone_car_wobble", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix58: 1 = the free wheel wobbles a little meanwhile (Glide cars, hg_glide_steering_realism)", 0, 1)
local graceCvar = CreateConVar("stts_phone_car_grace", "0.35", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix58: seconds the hand needs from the phone back to the wheel (steering stays blocked)", 0, 2)

local function IsPhone(w) return IsValid(w) and w:GetClass() == CLASS end
PC.IsPhone = IsPhone

-- the vehicle whose wheel the player holds: the same choice as hg.MainTPIKFunction
-- (simfphys driver, Glide seat 1, else the vehicle he sits in). Glide passenger = none
function PC.Car(ply)
	if not (IsValid(ply) and ply:IsPlayer() and ply:InVehicle()) then return end
	if ply.IsDrivingSimfphys and ply.GetSimfphys and ply:IsDrivingSimfphys() and IsValid(ply:GetSimfphys()) then return ply:GetSimfphys() end
	local g = ply.GlideGetVehicle and ply:GlideGetVehicle()
	if IsValid(g) then
		if ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() == 1 then return g end
		return
	end
	return ply:GetVehicle()
end

-- driver = that vehicle has a steering wheel Z-City knows (bone + hand offsets)
function PC.WheelOf(ply)
	local car = PC.Car(ply)
	if not IsValid(car) or not (hg and hg.GetCarSteering) then return end
	local ok, bone, adjust = pcall(hg.GetCarSteering, car)
	if not ok or not bone or not istable(adjust) or not adjust[1] or not adjust[2] then return end
	return car, bone, adjust
end

if SERVER then
	--[[ the hand is at the phone: NW2 "CarAct" (sent by the holder, cl part below).
	     STTS_CarFree = until when the hand is still on its way back to the wheel ]]
	function PC.SetAct(wep, on)
		on = on and true or false
		if wep:GetNW2Bool("CarAct", false) == on then return end
		if not on then wep.STTS_CarFree = CurTime() + graceCvar:GetFloat() end
		wep:SetNW2Bool("CarAct", on)
	end

	-- the driver of this Glide vehicle can not steer right now
	function PC.SteerBlocked(veh)
		if not blockCvar:GetBool() then return false end
		local drv = veh.GetSeatDriver and veh:GetSeatDriver(1) or (veh.GetDriver and veh:GetDriver())
		if not (IsValid(drv) and drv:IsPlayer()) then return false end
		local wep = drv:GetActiveWeapon()
		if not IsPhone(wep) then return false end
		if wep:GetNW2Bool("CarAct", false) or (wep.STTS_CarFree or 0) > CurTime() then return true end
		-- no right arm: the left hand holds the phone, no hand is on the wheel
		if wep.Posed and wep:Posed() and hg and hg.CanUseRightHand and not hg.CanUseRightHand(drv) then return true end
		return false
	end

	local STEER = {steer = true, pitch = true, yaw = true, roll = true}
	local function SeatPlayer(veh, seat)
		if veh.GetSeatDriver then return veh:GetSeatDriver(seat) end
		if seat == 1 and veh.GetDriver then return veh:GetDriver() end
	end
	-- a button press of Glide that belongs to the phone in the hand
	local function Eat(veh, seat, action)
		local ply = SeatPlayer(veh, seat)
		if not (IsValid(ply) and ply:IsPlayer()) then return false end
		local wep = ply:GetActiveWeapon()
		if not IsPhone(wep) then return false end
		if action == "attack" then return true end -- LMB raises / taps the phone
		if action == "horn" or action == "switch_weapon" then -- R lowers it
			local posed = wep.Posed and wep:Posed()
			if posed then wep.STTS_CarPosedAt = CurTime() end
			return posed or CurTime() - (wep.STTS_CarPosedAt or -10) < 0.6
		end
		return false
	end

	-- wraps the input of ONE Glide vehicle (its own table, Glide is not edited)
	function PC.Wrap(veh)
		if not IsValid(veh) or veh.STTS_PhoneWrap or not isfunction(veh.GetInputFloat) or not isfunction(veh.SetInputBool) then return end
		veh.STTS_PhoneWrap = true
		local getF, setB = veh.GetInputFloat, veh.SetInputBool
		veh.GetInputFloat = function(self, seat, action, ...)
			if seat == 1 and STEER[action] and PC.SteerBlocked(self) then
				if wobbleCvar:GetBool() then self.steeringNeedNoise = CurTime() + 0.1 end
				return 0
			end
			return getF(self, seat, action, ...)
		end
		veh.SetInputBool = function(self, seat, action, pressed, ...)
			if pressed and Eat(self, seat, action) then return end
			return setB(self, seat, action, pressed, ...)
		end
	end

	-- every Glide vehicle with a phone holder inside gets the wrap
	timer.Create("STTS_PhoneCarWrap", 0.5, 0, function()
		for _, ply in ipairs(player.GetAll()) do
			if ply:InVehicle() and ply.GlideGetVehicle and IsPhone(ply:GetActiveWeapon()) then
				local veh = ply:GlideGetVehicle()
				if IsValid(veh) then PC.Wrap(veh) end
			end
		end
	end)

	-- acts of the phone UI (sv_phone.lua -> PHONE.ExtraAct)
	function PC.Act(ply, wep, isPhone, act, arg)
		if act == "caract" then
			if isPhone then
				local on = arg == "1" and wep:GetRaised() and ply:InVehicle()
				PC.SetAct(wep, on)
				if on and ply.GlideGetVehicle and IsValid(ply:GlideGetVehicle()) then PC.Wrap(ply:GlideGetVehicle()) end
			end
			return true
		end
		-- lowered / free look: the hand goes back to the wheel (the act itself goes on)
		if isPhone and (act == "close" or act == "down" or act == "look") then PC.SetAct(wep, false) end
	end
end

if CLIENT then
	local idleCvar = CreateClientConVar("stts_phone_car_idle", "1.5", true, false, "fix58: in a vehicle the right hand goes back to the wheel after this many seconds without touching the phone", 0.3, 10)
	local keyCvar = CreateClientConVar("stts_phone_car_keyreturn", "1", true, false, "fix58: 1 = a steer key (A / D) takes the right hand back to the wheel at once", 0, 1)
	local MOVE_PX = 10 -- this much finger movement (UI px) takes the hand off the wheel

	-- the hands on the wheel (world): left pos, ang, right pos, ang (right = nil if unknown)
	function PC.WheelPose(ply)
		local car, bone, adjust = PC.WheelOf(ply)
		if not car then return end
		local f = FrameNumber()
		if car.STTS_WheelF ~= f then car.STTS_WheelF = f car:SetupBones() end
		local m = car:GetBoneMatrix(bone)
		if not m then return end
		local pos, ang = m:GetTranslation(), m:GetAngles()
		local lp, la = LocalToWorld(adjust[1], adjust[2], pos, ang)
		local rp, ra
		if adjust[3] and adjust[4] then rp, ra = LocalToWorld(adjust[3], adjust[4], pos, ang) end
		return lp, la, rp, ra
	end

	-- your own hand: "in action" (predicted), see the Think below
	local A = {on = false, at = 0, acc = 0}
	PC.A = A
	function PC.LocalAct(wep) return A.on and A.wep == wep end
	-- anybody's: yours predicted, the others from NW2
	function PC.ActOf(wep, ply)
		if ply == LocalPlayer() then return PC.LocalAct(wep) end
		return wep:GetNW2Bool("CarAct", false)
	end

	local function Send(on)
		net.Start("stts_phone_ui") net.WriteString("caract") net.WriteString(on and "1" or "0") net.SendToServer()
	end
	local function SetAct(on, wep)
		on = on and true or false
		if A.on == on then return end
		A.on = on
		if wep then A.wep = wep end
		Send(on)
	end

	-- the steer keys of Glide (its own binds), A / D without Glide
	local STEER_ACTIONS = {"steer_left", "steer_right", "yaw_left", "yaw_right", "roll_left", "roll_right"}
	local function SteerKey()
		local binds = Glide and Glide.Config and Glide.Config.binds
		if istable(binds) then
			for _, group in pairs(binds) do
				if istable(group) then
					for _, a in ipairs(STEER_ACTIONS) do
						local b = group[a]
						if isnumber(b) and b > 0 and input.IsButtonDown(b) then return true end
					end
				end
			end
			return false
		end
		return input.IsKeyDown(KEY_A) or input.IsKeyDown(KEY_D)
	end

	hook.Add("Think", "STTS_PhoneCarAct", function()
		local SCR = STTS.PhoneScreen
		local L = SCR and SCR.L
		local lp = LocalPlayer()
		local wep = IsValid(lp) and lp:Alive() and lp:GetActiveWeapon()
		local ok = L and IsPhone(wep) and L.wep == wep and L.raised and not L.look and PC.WheelOf(lp) ~= nil
		local lmb = IsValid(lp) and lp:KeyDown(IN_ATTACK) and not vgui.CursorVisible() and not gui.IsGameUIVisible()
		local press = lmb and not A.lmb
		A.lmb = lmb
		local key = ok and keyCvar:GetBool() and SteerKey() or false
		local keyPress = key and not A.key
		A.key = key
		if not ok then
			if A.on then SetAct(false) end
			A.ux, A.acc, A.wep = nil, 0, IsPhone(wep) and wep or nil
			return
		end
		if A.wep ~= wep then
			if A.on then SetAct(false) end
			A.wep, A.ux = wep, nil
		end
		local now = RealTime()
		local ux, uy = L.ux or 0, L.uy or 0
		if A.ux then
			A.acc = math.max(A.acc - FrameTime() * 40, 0) + math.abs(ux - A.ux) + math.abs(uy - A.uy)
		end
		A.ux, A.uy = ux, uy
		-- a steer key: the hand goes back to the wheel (not while the finger is on the glass)
		if keyPress and A.on and not L.touch then SetAct(false) A.acc = 0 return end
		local raising = L.raiseAt and now - L.raiseAt < 0.35 -- the LMB press that raised the phone
		local moved = A.acc > MOVE_PX and not key -- (steering with a key: a nudge of the mouse is no reason)
		if L.touch or (press and not raising) or moved then
			A.at = now
			A.acc = 0
			if not A.on then SetAct(true, wep) end
			return
		end
		if A.on and now - A.at > idleCvar:GetFloat() then SetAct(false) end
	end)

	--[[ hg.MainTPIKFunction: skip its wheel part for the phone in a vehicle (wpn.reload is
	     what Z-City itself checks there), the phone places the hands (weapon file) ]]
	-- fix60: found anywhere in the chain of wrappers (Litvin wraps it too, sh_phone_kick.lua)
	STTS.WrapInner = STTS.WrapInner or setmetatable({}, {__mode = "k"})
	STTS.WrapHas = STTS.WrapHas or function(fn, mine)
		if not mine then return false end
		local inner = STTS.WrapInner
		for _ = 1, 64 do
			if fn == nil then return false end
			if fn == mine then return true end
			fn = inner[fn]
		end
		return false
	end
	local function WrapTPIK()
		if not (hg and isfunction(hg.MainTPIKFunction)) then return end
		if PC.wTPIK and STTS.WrapHas(hg.MainTPIKFunction, PC.wTPIK) then return end
		local orig = hg.MainTPIKFunction
		local function wrap(ent, ply, wpn, ...)
			if IsPhone(wpn) and not wpn.reload and IsValid(ply) and ply:IsPlayer() and ply:InVehicle() then
				wpn.reload = true
				local ok, err = pcall(orig, ent, ply, wpn, ...)
				wpn.reload = nil
				if not ok then ErrorNoHalt(tostring(err) .. "\n") end
				return
			end
			return orig(ent, ply, wpn, ...)
		end
		STTS.WrapInner[wrap] = orig
		PC.wTPIK = wrap
		hg.MainTPIKFunction = wrap
	end
	WrapTPIK()
	hook.Add("InitPostEntity", "STTS_PhoneCarTPIK", WrapTPIK)
	timer.Create("STTS_PhoneCarTPIK", 3, 0, WrapTPIK)
end

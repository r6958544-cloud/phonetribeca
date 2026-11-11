--[[---------------------------------------------------------------------------
	ZHUNTER phone: vivo X300 Pro / Google Pixel 6 Pro / iPhone 18 Pro (fix28: every
	phone entity gets a random model, NW2 int "PMod", geometry = STTS.PhoneGeo.Of(self)).
	LMB  - bring the phone to your face (interaction mode). while it is up the
	       right index finger follows the mouse over the display (spring
	       inertia, no cursor), LMB = the finger taps what is under it,
	       LMB held = the finger stays on the glass and slides (scroll, swipe,
	       zoom slider).
	R    - the phone goes fully down (normal idle pose, also in a call).
	RMB  - toggle: press once = pointer freezes and the mouse turns the camera
	       (aim the phone), press again = back to the pointer.
	Everything is drawn on the display of the model itself (render target on
	the "*_screen" material of its model), see cl_shooting_phone_screen.lua.
---------------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

local G = STTS and STTS.PhoneGeo
if not G then include("autorun/sh_stts_phone.lua") G = STTS.PhoneGeo end

SWEP.Base = "weapon_base"
SWEP.PrintName = "Phone"
SWEP.Instructions = "LMB - raise / press (hold - slide, pull down from the top = shade). R - put down. RMB - look around on / off. Q menu -> Phone -> Anims: Toss phone / Litvin (keepy-uppy: mouse = foot, RMB = drop, flick the foot up = kick, R = stop). Q menu -> Phone -> RightHand: a pistol / knife in the right hand, the phone stays in the left one (LMB = shoot / hit; any weapon picked with 1, 2, 3 ... = the phone goes into the pocket). Driving: LMB = the right hand leaves the wheel for the phone (no steering meanwhile), A / D = back to the wheel. Swipe up = unlock."
SWEP.Category = "ZPhone"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.IdleHoldType = "normal"
SWEP.HoldType = "slam"
SWEP.ViewModel = ""
SWEP.WorldModel = G.HasModel and G.Model or G.Fallback
SWEP.ModelScale = G.HasModel and 1 or 0.5
SWEP.UseVivo = G.HasModel -- class default; fix28: per entity = SWEP:HasPhoneModel()

-- fix28: geometry of THIS phone's model (vivo / pixel / iphone)
function SWEP:Geo() return G.Of(self) end
function SWEP:HasPhoneModel()
	local _, ok = G.ModelPath(self)
	return ok
end
-- world model of this entity follows its phone model (server: physics of a dropped phone,
-- the fake gun prop; client: holstered / equipment renders that read .WorldModel)
function SWEP:ApplyPhoneModel()
	local path, ok = G.ModelPath(self)
	self.WorldModel = path
	self.ModelScale = ok and 1 or 0.5
	self.UseVivo = ok
	self.STTS_PModApplied = self:GetNW2Int("PMod", 1)
	if SERVER and self:GetModel() ~= path then
		local hadPhys = IsValid(self:GetPhysicsObject())
		self:SetModel(path)
		-- lying loose with physics already (not while spawning / held): rebuild it for the new box
		if hadPhys and not IsValid(self:GetOwner()) and not IsValid(self:GetParent()) then
			self:PhysicsInit(SOLID_VPHYSICS)
			local ph = self:GetPhysicsObject()
			if IsValid(ph) then ph:Wake() end
		end
	end
end
function SWEP:SetPhoneModel(i)
	i = math.Clamp(math.floor(tonumber(i) or 1), 1, #G.Models)
	self:SetNW2Int("PMod", i)
	self:ApplyPhoneModel()
end
-- fix29: body colour of this phone (NW2 "PCol", see sh_stts_phone.lua). server sets, everybody sees it
function SWEP:SetPhoneColor(v)
	v = math.floor(tonumber(v) or G.COL_STOCK)
	if v ~= G.COL_STOCK and not G.UnpackColor(v) then v = G.COL_STOCK end
	self:SetNW2Int("PCol", v)
end

if CLIENT then
	-- one material per (model, colour), copy of *_body_paint.vmt with its own $color2
	local paintMats = {}
	local function PaintMaterial(M, v)
		local key = M.id .. "_" .. v
		local mat = paintMats[key]
		if mat then return mat end
		local r, g, b = G.UnpackColor(v)
		if not r then return end
		local pt = M.Paint
		mat = CreateMaterial("stts_phone_paint_" .. key, "VertexLitGeneric", {
			["$basetexture"] = M.PaintTex,
			["$bumpmap"] = M.PaintBump,
			["$surfaceprop"] = "computer",
			["$model"] = 1,
			["$color2"] = string.format("[%.4f %.4f %.4f]", r / 255, g / 255, b / 255),
			["$blendtintbybasealpha"] = 1,
			["$blendtintcoloroverbase"] = 0,
			["$phong"] = 1,
			["$phongexponent"] = pt.exp,
			["$phongboost"] = pt.boost,
			["$phongfresnelranges"] = "[0.25 0.6 1]",
			["$envmap"] = "env_cubemap",
			["$normalmapalphaenvmapmask"] = 1,
			["$envmaptint"] = pt.env,
			["$envmapfresnel"] = 1,
		})
		paintMats[key] = mat
		return mat
	end
	G.PaintMaterial = PaintMaterial

	local bodyIdx = {}
	-- puts this phone's colour on the body of its clientside model (only when it changed)
	function SWEP:ApplyPhoneColor(mdl)
		local v = self:GetNW2Int("PCol", G.COL_STOCK)
		local mname = mdl:GetModel() or ""
		if mdl.STTS_Col == v and mdl.STTS_ColMdl == mname then return end
		local M = self:Geo()
		local idx = bodyIdx[mname]
		if idx == nil then
			idx = false
			for i, m in ipairs(mdl:GetMaterials() or {}) do
				if string.GetFileFromFilename(m) == M.BodyMat then idx = i - 1 break end
			end
			if not idx then
				for i, m in ipairs(mdl:GetMaterials() or {}) do
					if string.find(m, "_body", 1, true) and not string.find(m, "_screen", 1, true) then idx = i - 1 break end
				end
			end
			bodyIdx[mname] = idx
		end
		mdl.STTS_Col, mdl.STTS_ColMdl = v, mname
		if not idx then return end
		local mat = PaintMaterial(M, v)
		mdl:SetSubMaterial(idx, mat and ("!" .. mat:GetName()) or "")
	end
	-- colour for the fallback slab (model not compiled)
	function SWEP:PhoneSlabColor()
		local r, g, b = G.UnpackColor(self:GetNW2Int("PCol", G.COL_STOCK))
		if r then return Color(r * 0.9, g * 0.9, b * 0.9) end
		return Color(14, 14, 16)
	end
end

if CLIENT then
	SWEP.WepSelectIcon = Material("vgui/stts_zphone.png", "smooth mips")
	SWEP.IconOverride = "vgui/stts_zphone_icon.png"
	SWEP.BounceWeaponIcon = false
end

SWEP.Weight = 0
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Slot = 5
SWEP.SlotPos = 6
SWEP.WorkWithFake = true

--[[ phone in the left palm: x y z pitch yaw roll (hand bone -> phone origin)
     stts_phone_pos "x y z p y r" (server, not saved)  /  stts_phone_tune (client sliders) ]]
--[[ the old value "4.6 -1.7 0.1 27 -39 71" laid the phone ALONG the fingers
     (landscape in the idle pose). the raised pose builds the phone from the
     eyes and the wrist from the inverse of this offset, so the same mistake
     turned the whole hand by 90 degrees there (the "broken hand").
     new = old turned by +90 around the display normal (top of the phone now
     points away from the wrist, across the fingers) and moved 0.6 toward the palm. ]]
--[[ fix6: tuned in game -> "4.8 -1.8 1.4 -57 -1 57" (a bit further along the
     fingers and up out of the palm, portrait, display toward the face) ]]
STTS_PHONE_POS_DEFAULT = "4.8 -1.8 1.4 -57 -1 57" -- portrait, display toward the face
SWEP.offsetVec = Vector(4.8, -1.8, 1.4)
SWEP.offsetAng = Angle(-57, -1, 57)
local posCvar = CreateConVar("stts_phone_pos", STTS_PHONE_POS_DEFAULT, {FCVAR_REPLICATED}, "phone offset in the left hand: x y z pitch yaw roll")

--[[ pose targets, relative to the eyes: forward right up (units)
     raise = interaction mode, video = video call (phone held out, rear camera forward),
     ear = voice call (relative to the eyes, the phone's speaker goes there) ]]
local raiseCvar = CreateConVar("stts_phone_raise_pos", "10.5 -0.4 -1.8", {FCVAR_REPLICATED}, "interaction pose: forward right up from the eyes")
local videoCvar = CreateConVar("stts_phone_video_pos", "13 -0.6 -5.5", {FCVAR_REPLICATED}, "video call pose: forward right up from the eyes")
local earCvar = CreateConVar("stts_phone_ear_pos", "-3.2 -3.4 -0.9", {FCVAR_REPLICATED}, "voice call pose (speaker at the ear): forward right up from the eyes")

local function Nums(str, n)
	local t = {}
	for v in string.gmatch(str or "", "[%-%d%.]+") do t[#t + 1] = tonumber(v) or 0 end
	if #t < n then return end
	return t
end
local function ParseOffset(str)
	local n = Nums(str, 6)
	if n then return Vector(n[1], n[2], n[3]), Angle(n[4], n[5], n[6]) end
end
local function ParseVec(cv, def)
	local n = Nums(cv:GetString(), 3)
	return n and Vector(n[1], n[2], n[3]) or def
end

-- phone pose for a mode from an eye frame (shared: the ragdoll hold on the server uses it too)
local function Hold(o, ang, off)
	local p = o + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * off.z
	local normal = (o - p):GetNormalized()
	local top = ang:Up() - normal * ang:Up():Dot(normal)
	top:Normalize()
	return p, top:AngleEx(normal)
end

function SWEP:PoseAt(mode, o, ang)
	if mode == "raise" then return Hold(o, ang, ParseVec(raiseCvar, Vector(10.5, -0.4, -1.8))) end
	if mode == "video" then return Hold(o, ang, ParseVec(videoCvar, Vector(13, -0.6, -5.5))) end
	-- voice call: display against the left cheek, speaker at the ear, mic toward the mouth
	local e = ParseVec(earCvar, Vector(-3.2, -3.4, -0.9))
	local ear = o + ang:Forward() * e.x + ang:Right() * e.y + ang:Up() * e.z
	local normal = (ang:Right() + ang:Forward() * 0.15):GetNormalized()
	local top = ang:Up() - ang:Forward() * 0.55
	top = (top - normal * top:Dot(normal)):GetNormalized()
	return ear - top * (G.Of(self).ScreenH * 0.45) - normal * 0.4, top:AngleEx(normal) -- fix28: speaker of THIS model at the ear
end

--[[ fix24: RAGDOLL = the phone is the ENTITY in the ragdoll's hand, not a "viewmodel".
     before (fix8..fix23) the left hand of the ragdoll was bent on the client by IK
     to a pose in front of YOUR VIEW (the camera), so on your PC the phone was
     glued to the screen like a viewmodel, on other PCs it was somewhere else and
     the cameras had to guess between the two. now:
       server  while the phone is posed (raised / video call / at the ear) the REAL
               physical left hand of the ragdoll holds it in front of the eyes
               (shadow control, like homigrad's own hand control, RMB too)
       client  no IK on the left hand in a ragdoll: the phone is drawn on the real
               hand bone + palm offset, the same on every PC, every camera
               (own, video call, spectator stream) takes that pose
     the right index finger still goes to the display (UI needs it).
     stts_phone_fake_entity 0 = the old fix23 behaviour (if this one feels worse)
     stts_phone_fake_pos = where the hand holds the phone: forward right up from
     the eyes (further than raise_pos so the hand never pushes the head) ]]
local fakeEntCvar = CreateConVar("stts_phone_fake_entity", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "1 = in a ragdoll the phone is the real thing in the ragdoll's hand (fix24), 0 = old view-relative pose (fix23)", 0, 1)
local fakePosCvar = CreateConVar("stts_phone_fake_pos", "14 -0.8 -4.5", {FCVAR_REPLICATED}, "ragdoll: phone pose held by the physical hand, forward right up from the eyes")

function SWEP:FakeRagdoll()
	if not fakeEntCvar:GetBool() then return end
	local ply = self:GetOwner()
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	local rag = ply.FakeRagdoll
	if not IsValid(rag) and SERVER then rag = ply:GetNWEntity("FakeRagdoll", NULL) end
	if IsValid(rag) and rag ~= ply then return rag end
end

-- the pose of the phone in the ragdoll's real hand (bone = physics on the server)
function SWEP:FakePose()
	local rag = self:FakeRagdoll()
	if not rag then return end
	local bone = rag:LookupBone("ValveBiped.Bip01_L_Hand")
	if not bone then return end
	local pos, ang
	if SERVER then
		local pb = rag:TranslateBoneToPhysBone(bone)
		local phys = pb and pb >= 0 and rag:GetPhysicsObjectNum(pb)
		if not IsValid(phys) then return end
		pos, ang = phys:GetPos(), phys:GetAngles()
	else
		local m = rag:GetBoneMatrix(bone)
		if not m then return end
		pos, ang = m:GetTranslation(), m:GetAngles()
	end
	local vec, off = self:HandOffset()
	return LocalToWorld(vec, off, pos, ang)
end

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "InCall")  -- dialing / talking
	self:NetworkVar("Bool", 1, "Raised")  -- at the face, interaction mode
end

function SWEP:Initialize()
	self:SetHold(self.IdleHoldType)
	-- fix28: a random phone model for every new phone (inventory copies keep theirs via SetInfo)
	-- fix29: and a random body colour (black / random / stock, convars in sh_stts_phone.lua)
	if SERVER and self:GetNW2Int("PCol", 0) == 0 then
		self:SetPhoneColor(G.PickColor and G.PickColor() or G.COL_STOCK)
	end
	if SERVER and self:GetNW2Int("PMod", 0) == 0 then
		self:SetPhoneModel(G.PickModel and G.PickModel() or 1)
		-- the engine sets the class world model while spawning: put ours back right after
		timer.Simple(0, function() if IsValid(self) then self:ApplyPhoneModel() end end)
	elseif CLIENT then
		self:ApplyPhoneModel()
	end
end

-- fix28: a dropped phone collides with the box of ITS model
function SWEP:OnDrop()
	self.STTS_Toss = nil
	if SERVER then
		self:SetNW2Bool("CarAct", false)
		-- fix61: on the floor it stays as it was for the Auto-Lock time (was: locked at once)
		if STTS.PhoneAutoLock then STTS.PhoneAutoLock.Start(self, 1) else self:SetNW2Bool("Unlk", false) end
	end
	-- keepy-uppy (sh_phone_kick.lua): the phone leaves the foot / hand with its exact pose + speed
	local kd = self.STTS_KickDrop
	self.STTS_KickDrop = nil
	self:ApplyPhoneModel()
	if kd then self:SetPos(kd[1]) self:SetAngles(kd[2]) end
	timer.Simple(0, function()
		if not IsValid(self) or IsValid(self:GetOwner()) then return end
		local path = G.ModelPath(self)
		if self:GetModel() ~= path then self:SetModel(path) end
		if kd then self:SetPos(kd[1]) self:SetAngles(kd[2]) end
		self:PhysicsInit(SOLID_VPHYSICS)
		local ph = self:GetPhysicsObject()
		if IsValid(ph) then
			if kd then
				ph:SetPos(kd[1])
				ph:SetAngles(kd[2])
				ph:SetVelocity(kd[3])
				ph:AddAngleVelocity(kd[4])
			end
			ph:Wake()
		end
	end)
end

function SWEP:SetHold(value)
	self:SetWeaponHoldType(value)
	self:SetHoldType(value)
	self.holdtype = value
end

-- the palm offset of the phone held upright (stts_phone_pos / the tuner)
function SWEP:PalmOffset()
	local v, a
	if not STTS_PhoneTuning then v, a = ParseOffset(posCvar:GetString()) end
	if not v then v, a = self.offsetVec, self.offsetAng end
	-- fix28: the offset is tuned for the vivo. thinner phones (Pixel / iPhone) move along
	-- their display normal so their own back lies on the palm (no gap between hand and phone)
	local sh = self:Geo().PalmShift or 0
	if sh ~= 0 then v = v + a:Up() * sh end
	return v, a
end

function SWEP:HandOffset()
	local v, a = self:PalmOffset()
	-- v19.4 / v19.5: landscape (T): the phone turns in the hand, the hand moves to its end
	if CLIENT and self.LandOffset then
		self:LandTurn() -- steps the turn once per frame
		if self.STTS_LandOn then v, a = self:LandOffset(v, a) end
	end
	return v, a
end

--[[ v19.4: T = landscape / portrait while the phone is raised in front of the face.
     the phone turns by 90 degrees around the middle of its display, clockwise as you
     see it (top to the right, the left hand holds the left end = the bottom of the phone).
     everybody sees it (NW2 "Land", yours is predicted). lowered / at the ear / in a
     ragdoll (the server holds the real hand there) it is always portrait.
     v19.5: with both hands. the right hand takes the right end first, then the hands
     turn the phone (a spring: a little overshoot, it settles), the LEFT THUMB taps
     instead of the right index finger (client part: LandStep / LandOffset / RightGrip /
     ThumbIK below, tuner: stts_phone_tune_land).
     v19.6: both thumbs: the left one on the left half of the display, the right one on
     the right half. the hands stay where they are (no sliding after the finger), only a
     small lean when a thumb can not reach a spot.
     stts_phone_land_hand = where the left hand goes on the turned phone, as you see it:
     right up toward-the-eyes (units) roll (degrees, + = clockwise).
     stts_phone_land_rhand = the right hand, the same way, relative to the mirror image
     of the left one (0 0 0 0 = symmetric) ]]
local landHandCvar = CreateConVar("stts_phone_land_hand", "-1.2 0.6 0 0", {FCVAR_REPLICATED}, "landscape phone (T): the left hand on it, as you see it: right up toward-the-eyes roll")
local landRHandCvar = CreateConVar("stts_phone_land_rhand", "0 0 0 0", {FCVAR_REPLICATED}, "landscape phone (T): the right hand, relative to the mirror image of the left one: right up toward-the-eyes roll")

function SWEP:IsLand()
	if CLIENT and self:GetOwner() == LocalPlayer() and STTS.PhoneScreen and STTS.PhoneScreen.LocalLand then
		local v = STTS.PhoneScreen.LocalLand(self)
		if v ~= nil then return v end
	end
	return self:GetNW2Bool("Land", false)
end

-- how far the phone is turned: 0 = portrait .. 1 = landscape. v19.5: a spring stepped once
-- per frame (client, SWEP:LandStep), it can overshoot a little. LandK = the same clamped to
-- 0..1 (the screen turns its icons / photos / the mouse with it)
function SWEP:LandTurn()
	if SERVER or not self.LandStep then return 0 end
	return self:LandStep()
end
function SWEP:LandK()
	return math.Clamp(self:LandTurn(), 0, 1)
end

-- raised for the pose: predicted locally for your own phone
function SWEP:IsUp()
	if CLIENT and self:GetOwner() == LocalPlayer() and STTS.PhoneScreen and STTS.PhoneScreen.LocalRaised then
		return STTS.PhoneScreen.LocalRaised(self)
	end
	return self:GetRaised()
end

function SWEP:VideoOn()
	return self:GetNW2Bool("VidOn", false) and self:GetNW2Int("CallSt", 0) == G.CALL_ON
end

-- R: the phone goes fully down (normal idle pose), even during a call / video call
function SWEP:IsDown()
	if CLIENT and self:GetOwner() == LocalPlayer() and STTS.PhoneScreen and STTS.PhoneScreen.LocalDown then
		local v = STTS.PhoneScreen.LocalDown(self)
		if v ~= nil then return v end
	end
	return self:GetNW2Bool("Down", false)
end

-- nil = idle (in the palm like any item), else "raise" / "video" / "ear"
function SWEP:PoseMode()
	if self:IsUp() then return "raise" end
	if self:IsDown() then return end
	if self:VideoOn() then return "video" end
	if self:GetInCall() then return "ear" end
end

function SWEP:Posed() return self:PoseMode() ~= nil end

--[[ Q menu (Z-City radial menu) -> "Toss phone" (LMB = flip, RMB = double flip), also
     the console command stts_phone_toss [1|2]. the animation is client side (TossHand),
     the server only checks it and tells the players around. allowed when the phone lies
     in the free left hand: alive, conscious, on your feet, not raised / in a call ]]
function SWEP:CanToss(ply)
	ply = ply or self:GetOwner()
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) or self:GetOwner() ~= ply or ply:GetActiveWeapon() ~= self then return false end
	if ply:InVehicle() or self:FakeRagdoll() or (hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) ~= ply) then return false end
	local org = ply.organism
	if org and (org.otrub or org.canmove == false) then return false end
	if hg and hg.CanUseLeftHand and not hg.CanUseLeftHand(ply) then return false end
	if self:Posed() or (self.STTS_TossEnd or 0) > CurTime() then return false end
	if CLIENT and (self.STTS_Toss or (self.STTS_W or 0) > 0.01) then return false end -- still blending back from a pose
	return true
end

--[[---------------------------------------------------------------------------
	poses (client): IK target for the left hand, blended smoothly
---------------------------------------------------------------------------]]
local CORE
if CLIENT then
	local function Slerp(t, a, b)
		if Quaternion then
			local ok, res = pcall(function()
				local m1, m2 = Matrix(), Matrix()
				m1:SetAngles(a) m2:SetAngles(b)
				local q1, q2 = Quaternion(), Quaternion()
				q1:SetMatrix(m1) q2:SetMatrix(m2)
				return q1:SLerp(q2, t):Angle()
			end)
			if ok and res then return res end
		end
		return LerpAngle(t, a, b)
	end
	SWEP.Slerp = Slerp
	local bobCvar = CreateClientConVar("stts_phone_bob", "1", true, false, "step bounce of the held phone (0 = off, 1 = normal, 2 = strong)", 0, 3)
	local swayCvar = CreateClientConVar("stts_phone_sway", "1", true, false, "inertia of the held phone: lag on turns / starts / stops / landings (0 = off, 1 = normal, 2 = strong)", 0, 3)

	-- RMB free look of this phone (yours = predicted, others = NW2)
	local function LookOn(self, ply)
		local L = STTS.PhoneScreen and STTS.PhoneScreen.L
		if ply == LocalPlayer() and L and L.wep == self then return L.look end
		return self:GetNW2Bool("Look", false)
	end

	-- fix58: a vehicle (sh_phone_car.lua). where the hands hold the wheel (nil = the
	-- holder does not drive) and whether the right hand is "in action" (at the phone)
	local function Wheel(ply)
		local PC = STTS.PhoneCar
		if PC and PC.WheelPose and ply:InVehicle() then return PC.WheelPose(ply) end
	end
	local function CarAct(self, ply)
		local PC = STTS.PhoneCar
		if PC and PC.ActOf then return PC.ActOf(self, ply) end
		return self:GetNW2Bool("CarAct", false)
	end

	-- rotate vector v around unit axis k by deg (right hand rule)
	local function RotV(v, k, deg)
		local r = math.rad(deg)
		local c, s = math.cos(r), math.sin(r)
		return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
	end
	local function RotA(ang, k, deg)
		local f, u = RotV(ang:Forward(), k, deg), RotV(ang:Up(), k, deg)
		return f:AngleEx(u)
	end
	SWEP.RotV, SWEP.RotA = RotV, RotA
	local Z = Vector(0, 0, 1)
	-- turns a phone pose around the middle of its display (axis in the world, degrees)
	local function Spin(M, pos, ang, axis, deg)
		local c = LocalToWorld(Vector(M.ScreenPos.x, M.ScreenPos.y, 0), angle_zero, pos, ang)
		return c + RotV(pos - c, axis, deg), RotA(ang, axis, deg)
	end

	--[[ fix8: motion of the held phone, rewritten again.
	     fix7 derived accelerations from the view / velocity (second derivative of
	     a noisy per-frame signal) and pushed hard step impulses with a kink in
	     them -> jerky. now nothing is differentiated:
	       position - an inertial point follows the EYES on a damped spring with
	                  the player velocity as feed-forward. walking at a steady
	                  speed = no lag, only starts / stops / jumps / landings and
	                  head movement swing the phone. a fraction of that swing
	                  (inertia) is applied, with a soft (tanh) limit, no hard stop.
	       rotation - an inertial view direction follows the real one on a spring
	                  (no feed-forward): while you turn the phone trails a little
	                  behind and leans into the turn, when you stop it swings back.
	       steps    - a small smooth bounce (cosine, no kinks), fades in with speed.
	       tap      - the finger push nudges the phone a bit away from the face.
	     fixed 240 Hz substeps, the eye target is interpolated inside the frame. ]]
	local P_HZ, P_ZETA, P_INERTIA, P_MAX = 2.8, 0.78, 0.32, 0.8
	local R_HZ, R_ZETA, R_INERTIA, R_MAX = 2.3, 0.82, 0.22, 4.5

	local function Soft(x, m) -- smooth limit: linear for small x, never above m
		if m <= 0 then return 0 end
		return m * math.tanh(x / m)
	end

	local function Motion(self, ply, fo, fa, dt, mode)
		if dt <= 0 then return end
		local sway = math.Clamp(swayCvar:GetFloat(), 0, 3)
		local bobK = math.Clamp(bobCvar:GetFloat(), 0, 3)
		local look = LookOn(self, ply)
		local mul = (mode == "ear" and 0.4) or (mode == "video" and 1.1) or 1
		if look then mul = mul * 1.2 end
		local fwd, rgt, up = fa:Forward(), fa:Right(), fa:Up()
		local vel = ply:GetVelocity()
		local inCar = ply:InVehicle()
		if inCar then -- fix58: the vehicle carries the eyes (feed-forward = its speed, no steps)
			local seat = ply:GetVehicle()
			local root = IsValid(seat) and (IsValid(seat:GetParent()) and seat:GetParent() or seat)
			vel = IsValid(root) and root:GetVelocity() or Vector(0, 0, 0)
		end

		local steps = math.max(1, math.ceil(dt / (1 / 240)))
		local h = dt / steps

		-- position spring (world space, feed-forward = player velocity)
		local wn = 2 * math.pi * P_HZ
		local k, c = wn * wn, 2 * P_ZETA * wn
		local T0 = self.STTS_MT or fo
		local p, v = self.STTS_MP or Vector(fo), self.STTS_MV or Vector(vel)
		if (p - fo):LengthSqr() > 40 * 40 or (T0 - fo):LengthSqr() > 40 * 40 then -- teleport / respawn
			p, v, T0 = Vector(fo), Vector(vel), fo
		end
		if self.STTS_MKick then -- tap: the finger pushes the phone away a little (v20: on the contact, by its speed)
			v = v + fwd * (35 * (tonumber(self.STTS_MKick) or 1))
			self.STTS_MKick = nil
		end
		for i = 1, steps do
			local t = LerpVector(i / steps, T0, fo)
			v = v + ((t - p) * k + (vel - v) * c) * h
			p = p + v * h
		end
		self.STTS_MP, self.STTS_MV, self.STTS_MT = p, v, Vector(fo)
		local e = (p - fo) * (P_INERTIA * sway * mul)
		local ex, ey, ez = e:Dot(fwd) * 0.6, e:Dot(rgt), e:Dot(up)
		local len = math.sqrt(ex * ex + ey * ey + ez * ez)
		if len > 0.0001 then
			local s = Soft(len, P_MAX * math.max(sway, 0.01)) / len
			ex, ey, ez = ex * s, ey * s, ez * s
		end

		-- rotation spring: error = inertial direction - real direction (degrees)
		local prev = self.STTS_MPrevFa
		local dy, dp = 0, 0
		if prev then dy, dp = math.AngleDifference(fa.y, prev.y), math.AngleDifference(fa.p, prev.p) end
		self.STTS_MPrevFa = Angle(fa.p, fa.y, 0)
		if math.abs(dy) > 60 or math.abs(dp) > 60 then dy, dp = 0, 0 end
		local rn = 2 * math.pi * R_HZ
		local rk, rc = rn * rn, 2 * R_ZETA * rn
		local eY, wY = self.STTS_MEy or 0, self.STTS_MWy or 0
		local eP, wP = self.STTS_MEp or 0, self.STTS_MWp or 0
		local sy, sp = dy / dt, dp / dt
		for _ = 1, steps do
			wY = wY + (-rk * eY - rc * wY) * h
			eY = eY + (wY - sy) * h
			wP = wP + (-rk * eP - rc * wP) * h
			eP = eP + (wP - sp) * h
		end
		eY, eP = math.Clamp(eY, -60, 60), math.Clamp(eP, -60, 60)
		self.STTS_MEy, self.STTS_MWy, self.STTS_MEp, self.STTS_MWp = eY, wY, eP, wP
		local rm = R_INERTIA * sway * mul
		local rMax = R_MAX * math.max(sway, 0.01)
		local yaw, pitch = Soft(eY * rm, rMax), Soft(eP * rm, rMax * 0.8)
		local roll = yaw * 0.55

		-- steps: smooth bounce
		local spd = math.sqrt(vel.x * vel.x + vel.y * vel.y)
		local ground = ply:OnGround() and not inCar
		local want = ground and math.Clamp(spd / 210, 0, 1.3) or 0
		self.STTS_MStep = Lerp(1 - math.exp(-dt * 4), self.STTS_MStep or 0, want)
		local stepHz = 1.6 + math.Clamp(spd / 280, 0, 1.1) -- steps per second
		self.STTS_MPh = ((self.STTS_MPh or 0) + dt * stepHz * math.pi) % (math.pi * 2)
		local ph, amt = self.STTS_MPh, self.STTS_MStep * bobK * mul
		ez = ez - amt * 0.16 * (1 - math.cos(ph * 2)) * 0.5
		ey = ey + amt * 0.12 * math.sin(ph)
		roll = roll + amt * 0.7 * math.sin(ph)
		pitch = pitch + amt * 0.35 * (1 - math.cos(ph * 2)) * 0.5

		self.STTS_MOutP = Vector(ex, ey, ez) -- forward, right, up (eye frame)
		self.STTS_MOutR = Vector(yaw, pitch, roll)
	end

	-- eyes of the holder: the real view for yourself, head bone + eye angles for others
	-- (fix10: ragdoll / car exactly like fix8 again, no "eyes" attachment)
	local function Face(ply, ent)
		local v = STTS_PHONE_VIEW
		local head = ent:LookupBone("ValveBiped.Bip01_Head1")
		local m = head and ent:GetBoneMatrix(head)
		if ply == LocalPlayer() and v and GetViewEntity() == ply and RealTime() - v.t < 0.25 then
			-- fix58: a vehicle with a 3rd person camera: the head, looking where the camera looks
			if not (m and ply:InVehicle() and v.origin:DistToSqr(m:GetTranslation()) > 30 * 30) then return v.origin, v.angles end
			return m:GetTranslation() + v.angles:Forward() * 3 + v.angles:Up() * 2.5, v.angles
		end
		local ang = ply:EyeAngles()
		-- fix58: someone else in a vehicle: his EyeAngles come with the seat applied twice
		-- (the same workaround as Glide's sh_anims.lua)
		if ply ~= LocalPlayer() and ply:InVehicle() then
			local par = ply:GetParent()
			if IsValid(par) then ang = par:WorldToLocalAngles(ang) end
		end
		if m then return m:GetTranslation() + ang:Forward() * 3 + ang:Up() * 2.5, ang end
		return ply:EyePos(), ang
	end

	function SWEP:PoseTarget(ply, ent, o, ang)
		local mode = self:PoseMode()
		if not mode then return end
		if not o then o, ang = Face(ply, ent) end
		return self:PoseAt(mode, o, ang)
	end

	--[[ left fingers: while the phone is raised the hand keeps the SAME finger
	     shape it has in the idle pose (copied relative to the hand bone).
	     before, "pistol_hold2" (a pistol support grip) was forced on it, which
	     together with the turned wrist gave the broken hand from the screenshot. ]]
	local function CaptureLeftFingers(self, ent, lh)
		if (self.STTS_LFingAt or 0) > RealTime() then return end
		self.STTS_LFingAt = RealTime() + 0.3
		local hm = ent:GetBoneMatrix(lh)
		local inv = hm and hm:GetInverse()
		local kids = inv and hg.get_children and hg.get_children(ent, lh)
		if not kids then return end
		local rel = {}
		for _, id in ipairs(kids) do
			local m = ent:GetBoneMatrix(id)
			if m then rel[id] = inv * m end
		end
		self.STTS_LFing = rel
	end
	local function ApplyLeftFingers(self, ent, lh)
		local rel = self.STTS_LFing
		local hm = ent:GetBoneMatrix(lh)
		if not rel or not hm then return end
		for id, m in pairs(rel) do ent:SetBoneMatrix(id, hm * m) end
	end

	--[[ right hand = pointing finger while the phone is raised.
	     the fingertip follows the pointer (UI pixels of the display) through a
	     damped spring: a sharp move overshoots a little and settles.
	     LMB = the finger taps the glass. ]]
	local fHz = CreateClientConVar("stts_phone_finger_hz", "4.5", true, false, "finger spring frequency (higher = snappier)", 1, 15)
	local fDamp = CreateClientConVar("stts_phone_finger_damp", "0.5", true, false, "finger spring damping (1 = no overshoot, lower = more overshoot)", 0.15, 1.5)
	local fHover = CreateClientConVar("stts_phone_finger_hover", "0.7", true, false, "fingertip height over the glass (units)", 0, 3)
	local fDir = CreateClientConVar("stts_phone_finger_dir", "0.55 0.45 -1", true, false, "finger direction in phone space: toward top, toward left edge, into the screen", nil, nil)
	local fRoll = CreateClientConVar("stts_phone_finger_roll", "0", true, false, "extra roll of the right hand around the finger (degrees)", -180, 180)
	local fJelly = CreateClientConVar("stts_phone_finger_jelly", "1", true, false, "how soft the finger is: 0 = rigid, 1 = normal, 2 = very soft (the hand sways after the finger, the finger gives on a tap)", 0, 2.5)
	local tSpeed = CreateClientConVar("stts_phone_tap_speed", "1", true, false, "speed of the tap (1 = normal, higher = quicker and stiffer)", 0.4, 2.5)
	local F_REST_X, F_REST_Y = G.RTW * 0.5, G.RTH * 0.72

	--[[ v20 tap: it has inertia now and the finger is a little soft (jelly).
	     STTS_TZ = how high the HAND holds the fingertip over the glass (units). before,
	     LMB set an instant speed toward the glass and the glass stopped it dead, so the
	     finger jumped down in a frame. now LMB only moves the target: a spring eases the
	     finger down (it speeds up, ~40 ms to the glass), the tip meets the glass and the
	     hand keeps going a little. below zero the tip stays on the glass and the rest is
	     the squash (STTS_TQ): the finger arches (PointPose / ArchFor) and its pad pushes
	     back (a stiff spring with some loss), so it gives and settles instead of a dead
	     stop. the wrist dips toward the glass after it on its own slower spring (STTS_TD)
	     and wobbles back, the phone gets its push on the contact (STTS_MKick), the wrist
	     twists a little (STTS_TA). a click keeps pressing until the tip has been on the
	     glass for a moment, held LMB presses softer after the first hit. let go = the
	     spring throws it back up past the hover and it settles.
	     the same runs for other players (TapAt / Touch over NW2, FingerStep). ]]
	local TAP_HZ, TAP_ZETA, TAP_ZETA_UP = 4.8, 0.5, 0.36 -- the finger spring, pressing / going back up
	local TAP_DEPTH, TAP_SOFT = 0.7, 0.55 -- the press target under the glass, the part of it while held
	local TAP_PAD_K, TAP_PAD_Z = 1.3, 0.38 -- the pad: stiffness (x the spring), damping
	local TAP_SQ, TAP_MIN, TAP_DIP = 0.4, 0.06, 5.5 -- squash of a full arch, min press on the glass (s), wrist dip (deg)
	-- v20 movement: the wrist follows the fingertip on a softer spring (STTS_FW, UI pixels), so
	-- the hand trails a quick move a bit, swings past and settles (DoFinger turns it around the tip)
	local SWAY_HZ, SWAY_GAIN, SWAY_MAX = 3.4, 0.8, 8

	function SWEP:Tap()
		self.STTS_TapAt = RealTime()
		self.STTS_TapHit = nil
	end

	-- LMB held: the finger stays on the glass (and slides with the mouse)
	function SWEP:Touch(on)
		if on and not self.STTS_Touching then self:Tap() end
		self.STTS_Touching = on or nil
	end

	function SWEP:TapStep(dt, hover)
		local now = RealTime()
		local z, v = self.STTS_TZ or hover, self.STTS_TV or 0
		local d, dv = self.STTS_TD or 0, self.STTS_TDV or 0
		local a, av = self.STTS_TA or 0, self.STTS_TAV or 0
		if z ~= z or v ~= v or d ~= d or dv ~= dv then z, v, d, dv = hover, 0, 0, 0 end
		local at, hit = self.STTS_TapAt, self.STTS_TapHit
		local j = math.Clamp(fJelly:GetFloat(), 0, 2.5)
		local sp = math.Clamp(tSpeed:GetFloat(), 0.4, 2.5)
		-- pressing: LMB held, or a click until the tip has been on the glass for a moment
		local press = self.STTS_Touching or (at ~= nil and now - at < 0.3 and (not hit or now - hit < TAP_MIN / sp))
		local target = hover
		if press then target = -TAP_DEPTH * ((hit and now - hit > 0.12 / sp) and TAP_SOFT or 1) end
		local w = 2 * math.pi * TAP_HZ * sp
		local k, c = w * w, 2 * (press and TAP_ZETA or TAP_ZETA_UP) * w
		local kc = TAP_PAD_K * k
		local cc = 2 * TAP_PAD_Z * math.sqrt(k + kc)
		local wd = 2 * math.pi * 5.5 * sp
		local cd = 2 * math.Clamp(0.48 - 0.16 * j, 0.2, 0.5) * wd
		local wa, ca = 2 * math.pi * 5, 2 * 0.35 * 2 * math.pi * 5
		local steps = math.max(1, math.ceil(dt / (1 / 240)))
		local h = dt / steps
		for _ = 1, steps do
			local f = k * (target - z) - c * v
			if z < 0 then -- on the glass: the pad pushes back
				f = f - kc * z - cc * v
				if not hit and at then -- the first contact of this tap
					hit = now
					self.STTS_MKick = math.Clamp(-v / 26, 0.15, 1.3) -- the phone gets pushed
					av = av + math.Clamp(-v, 0, 60) * 2.2 * j -- and the wrist twists a little
				end
			end
			v = v + f * h
			z = z + v * h
			-- the wrist dips after the squash (deeper squash = deeper dip), wobbles back
			dv = dv + (wd * wd * (math.max(-z, 0) / TAP_SQ * TAP_DIP * j - d) - cd * dv) * h
			d = d + dv * h
			av = av + (wa * wa * (0 - a) - ca * av) * h
			a = a + av * h
		end
		if z < -1.5 or z > hover + 2 then z, v = math.Clamp(z, -1.5, hover + 2), 0 end
		self.STTS_TZ, self.STTS_TV, self.STTS_TA, self.STTS_TAV = z, v, math.Clamp(a, -14, 14), av
		self.STTS_TD, self.STTS_TDV = math.Clamp(d, -12, 12), dv
		self.STTS_TQ, self.STTS_TapHit = math.max(-z, 0) / TAP_SQ, hit
	end

	function SWEP:FingerTarget()
		local ply = self:GetOwner()
		local L = STTS.PhoneScreen and STTS.PhoneScreen.L
		if ply == LocalPlayer() and L and L.wep == self and L.ux then return L.ux, L.uy end
		-- someone else's phone: the finger goes where the holder moves it
		local nx = self:GetNW2Int("FX", -1)
		if nx >= 0 then return nx * 2, self:GetNW2Int("FY", 0) * 4 end
		local sel = self:GetNW2Int("Sel", 0)
		if sel ~= 0 then
			for _, b in ipairs(self.STTS_Btn or {}) do
				if b.id == sel then return b.x + b.w * 0.5, b.y + b.h * 0.5 end
			end
		end
		return F_REST_X, F_REST_Y
	end

	function SWEP:FingerStep(dt)
		local tx, ty = self:FingerTarget()
		-- someone else's phone: taps and held touches come over NW2
		if self:GetOwner() ~= LocalPlayer() then
			local tap = self:GetNW2Float("TapAt", 0)
			if self.STTS_RemoteTap and self.STTS_RemoteTap ~= tap then self:Tap() end
			self.STTS_RemoteTap = tap
			self.STTS_Touching = self:GetNW2Bool("Touch", false) or nil
		end
		if not self.STTS_FP then
			self.STTS_FP, self.STTS_FV = Vector(tx, ty, 0), Vector(0, 0, 0)
			self.STTS_FW, self.STTS_FWV = nil, nil
		end
		if not self.STTS_FW then self.STTS_FW, self.STTS_FWV = Vector(self.STTS_FP), Vector(0, 0, 0) end
		local w = 2 * math.pi * math.Clamp(fHz:GetFloat(), 1, 15)
		local z = math.Clamp(fDamp:GetFloat(), 0.15, 1.5)
		local k, c = w * w, 2 * z * w
		local p, v = self.STTS_FP, self.STTS_FV
		-- v20: the wrist anchor (jelly): follows the tip on a softer, bouncier spring
		local q, qv = self.STTS_FW, self.STTS_FWV
		local wl = 2 * math.pi * SWAY_HZ
		local kl, cl = wl * wl, 2 * math.Clamp(0.5 - 0.14 * math.Clamp(fJelly:GetFloat(), 0, 2.5), 0.2, 0.5) * wl
		local steps = math.max(1, math.ceil(dt / (1 / 240)))
		local h = dt / steps
		for _ = 1, steps do -- semi-implicit Euler, stable at these rates
			v.x = v.x + (k * (tx - p.x) - c * v.x) * h
			v.y = v.y + (k * (ty - p.y) - c * v.y) * h
			p.x = p.x + v.x * h
			p.y = p.y + v.y * h
			qv.x = qv.x + (kl * (p.x - q.x) - cl * qv.x) * h
			qv.y = qv.y + (kl * (p.y - q.y) - cl * qv.y) * h
			q.x = q.x + qv.x * h
			q.y = q.y + qv.y * h
		end
		-- never fly far off the glass
		p.x = math.Clamp(p.x, -G.RTW * 0.15, G.RTW * 1.15)
		p.y = math.Clamp(p.y, -G.RTH * 0.08, G.RTH * 1.08)
		local lx, ly = q.x - p.x, q.y - p.y
		local ll = lx * lx + ly * ly
		if ll ~= ll then q.x, q.y, qv.x, qv.y = p.x, p.y, 0, 0
		elseif ll > 300 * 300 then -- a jump (a new target far away): the anchor never lags too far
			ll = 300 / math.sqrt(ll)
			q.x, q.y = p.x + lx * ll, p.y + ly * ll
		end
		self.STTS_FingerUX, self.STTS_FingerUY, self.STTS_FingerAt = p.x, p.y, RealTime()
		self:TapStep(dt, math.max(fHover:GetFloat(), 0))
	end

	-- a point of the display in phone space: UI pixels + height over the glass
	local function DisplayPoint(M, fx, fy, lift)
		return Vector(M.ScreenPos.x + M.ScreenH * 0.5 - fy / G.RTH * M.ScreenH,
			M.ScreenPos.y + M.ScreenW * 0.5 - fx / G.RTW * M.ScreenW,
			M.ScreenPos.z + lift)
	end

	--[[ v19.5 / v19.6: landscape (T) with both hands, step by step:
	       1. the right hand leaves the display and takes the right end of the phone
	          (on an arc toward you, never through the phone)
	       2. both hands turn the phone: a spring, it overshoots a little and settles.
	          the hands turn part of the way with it (stts_phone_land_carry), the left
	          one settles on its end a moment later (re-grip), the phone dips a little
	       3. the THUMBS tap instead of the right index finger. v19.6: both of them, the
	          left one on the left half of the turned display, the right one on the right
	          half, the other one lies on the glass at the bottom edge (ThumbTarget). the
	          joint IK bends a thumb only the way a thumb bends (ThumbIK). the hands stay
	          where they are (v19.5 slid the left hand along the phone after the finger),
	          only a target out of the reach of the thumb (the middle of the top edge, the
	          corner right at its base) makes the hand give a little (LeanFor, LEAN_MAX)
	     T again = the same backwards, the right hand goes back to pointing.
	     the grips are in the frame of the phone before the turn (+x = up, +y = left as
	     you see it, z = display normal), the phone turns around the middle of its display ]]
	local landSpeed = CreateClientConVar("stts_phone_land_speed", "1", true, false, "landscape (T): speed of the turn and of the hands (1 = normal)", 0.3, 3)
	local landCarry = CreateClientConVar("stts_phone_land_carry", "0.35", true, false, "landscape (T): how much the hands turn with the phone (0 = the phone turns in the hands, 1 = the hands turn with it)", 0, 1)
	local THUMB_L = {"ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02"}
	local THUMB_R = {"ValveBiped.Bip01_R_Finger0", "ValveBiped.Bip01_R_Finger01", "ValveBiped.Bip01_R_Finger02"}
	local LAND_L, LAND_R = {-1.2, 0.6, 0, 0}, {0, 0, 0, 0} -- fix68: further out / lower, off the corners of the display
	-- v19.6: a thumb curls from straight (0) to a fist (1): its two joints (degrees) bend together
	local CURL_MCP, CURL_IP, LEAN_MAX = 65, 85, 0.6

	local function LandNums(cv, key, def)
		local t = STTS_PhoneLandTune -- stts_phone_tune_land, live
		if t and t[key] then return t[key] end
		return Nums(cv:GetString(), 4) or def
	end

	-- damped spring, 240 Hz substeps
	local function Spring(x, v, target, hz, zeta, dt)
		if dt <= 0 then return x, v end
		local w = 2 * math.pi * hz
		local k, c = w * w, 2 * zeta * w
		local steps = math.max(1, math.ceil(dt / (1 / 240)))
		local h = dt / steps
		for _ = 1, steps do
			v = v + (k * (target - x) - c * v) * h
			x = x + v * h
		end
		return x, v
	end
	local function Rest(x, v, target)
		if math.abs(x - target) < 0.001 and math.abs(v) < 0.01 then return target, 0 end
		return x, v
	end

	-- the left hand in the frame of the phone before the turn: its portrait pose (hP, hA)
	-- and its landscape spot (the same grip moved by stts_phone_land_hand, as you see it)
	local function LeftSpot(self, v, a)
		local n = LandNums(landHandCvar, "l", LAND_L)
		local hP, hA = WorldToLocal(vector_origin, angle_zero, v, a)
		local lP = hP + Vector(n[2], -n[1], n[3])
		local lA = n[4] ~= 0 and RotA(hA, Z, -n[4]) or hA
		return lP, lA, hP, hA, n[4]
	end

	-- fix68: a Z-City use animation (doors etc., hg.DoZManip) moves the LEFT hand with the
	-- phone. the right hand lets go of the phone meanwhile (it would hang in the air where
	-- the phone was) and comes back when the animation is over
	function SWEP:ZManip68(ply)
		if not (IsValid(ply) and ply.zmanipstart and ply.zmaniptime) then return false end
		if ply.organism and ply.organism.larmamputated then return false end
		if ply.GetNetVar and IsValid(ply:GetNetVar("carryent2")) then return false end
		return CurTime() - ply.zmanipstart < ply.zmaniptime + 0.15
	end

	-- steps the springs of the turn once per frame, returns the turn (0..1, can overshoot)
	function SWEP:LandStep()
		local f = FrameNumber()
		if self.STTS_LandF == f then return self.STTS_LandT or 0 end
		self.STTS_LandF = f
		local now = RealTime()
		local stale = now - (self.STTS_LandAt or -10) > 0.5 -- not drawn for a while: no old animation
		self.STTS_LandAt = now
		local dt = math.min(FrameTime(), 0.1)
		local ply = self:GetOwner()
		local valid = IsValid(ply) and ply:IsPlayer()
		-- fix58: in a vehicle landscape works too (the ragdoll sits in it, the hands are IK)
		local car = valid and ply:InVehicle()
		local want = valid and self:IsLand() and self:IsUp() and (car or not self:FakeRagdoll())
			and not (hg and hg.CanUseLeftHand and not hg.CanUseLeftHand(ply))
		local right = valid and hg and hg.DragRightHand_Ex and self:RightHandFree71(ply)
		-- fix58: a driver keeps the right hand on the wheel until it is in action (one hand + the left thumb)
		if right and car and self.STTS_WRP and not CarAct(self, ply) then right = false end
		if right and self:ZManip68(ply) then right = false end -- fix68
		want, right = want and true or false, right and true or false
		local sp = math.Clamp(landSpeed:GetFloat(), 0.3, 3)
		local t, tv = self.STTS_LandT or 0, self.STTS_LandTV or 0
		local g, gv = self.STTS_LandG or 0, self.STTS_LandGV or 0
		local lam, lv = self.STTS_LandL or 0, self.STTS_LandLV or 0
		local tw = self.STTS_LandTW or 0
		local side, aL, aR = self.STTS_LandSide or "L", self.STTS_LandAL or 1, self.STTS_LandAR or 0
		local ln = self.STTS_Lean
		if not ln then ln = {0, 0, 0, 0, 0, 0, 0, 0} self.STTS_Lean = ln end -- left x y, right x y, + speeds
		if stale then
			t = want and 1 or 0
			g = (want and right) and 1 or 0
			lam, tw, tv, gv, lv = t, t, 0, 0, 0
			side, aL, aR = "L", 1, 0
			for i = 1, 8 do ln[i] = 0 end
			self.STTS_LeanT = nil
		else
			-- 1. the right hand comes to the phone (and holds it until it is mostly back)
			local gT = (right and (want or t > 0.35)) and 1 or 0
			g, gv = Spring(g, gv, gT, 2.6 * sp, 1, dt)
			g, gv = Rest(g, gv, gT)
			-- 2. the turn starts once the right hand is there
			-- fix58: already turned in a vehicle = it stays turned while the right hand comes off the wheel
			local tT = (want and (g > 0.5 or not right or (car and t > 0.5))) and 1 or 0
			t, tv = Spring(t, tv, tT, 1.9 * sp, 0.68, dt)
			t, tv = Rest(t, tv, tT)
			if t < -0.2 or t > 1.2 then t, tv = math.Clamp(t, -0.2, 1.2), 0 end
			-- the left hand catches up a moment later (re-grip)
			local lT = math.Clamp(t, 0, 1)
			lam, lv = Spring(lam, lv, lT, 2.2 * sp, 1, dt)
			lam, lv = Rest(lam, lv, lT)
			-- 3. the thumbs take over when the phone is nearly turned
			local twT = (want and t > 0.8) and 1 or 0
			tw = math.Approach(tw, twT, dt * sp * (twT > tw and 4.5 or 7))
			-- v19.6: which thumb taps. the right half of the turned display (= the upper half
			-- of the UI) is the right one, a margin in the middle so it does not flip there,
			-- a touch (LMB held) keeps its thumb. no right hand = the left one alone
			if not right or g < 0.9 or tw < 0.5 then side = "L"
			elseif not self.STTS_Touching then
				local fy = self.STTS_FingerUY or F_REST_Y
				if fy < G.RTH * 0.45 then side = "R" elseif fy > G.RTH * 0.55 then side = "L" end
			end
			-- fix57: the cursor rests for a second (no touch) = both thumbs go off the
			-- glass to the ends of the display, the picture is free. a move brings one back
			local pm = self.STTS_ParkM
			if not pm then pm = {0, 0, now} self.STTS_ParkM = pm end
			local ux, uy = self.STTS_FingerUX or F_REST_X, self.STTS_FingerUY or F_REST_Y
			if self.STTS_Touching or math.abs(ux - pm[1]) > 2 or math.abs(uy - pm[2]) > 2 then
				pm[1], pm[2], pm[3] = ux, uy, now
			end
			if now - pm[3] > 1 then
				aL = math.Approach(aL, 0, dt * sp * 5)
				aR = math.Approach(aR, 0, dt * sp * 5)
			else
				aL = math.Approach(aL, side == "L" and 1 or 0, dt * sp * 12)
				aR = math.Approach(aR, side == "R" and 1 or 0, dt * sp * 12)
			end
			-- a hand gives a little toward a target out of the reach of its thumb (LeanFor)
			local lt = self.STTS_LeanT
			for i = 1, 4 do
				local tg = (lt and tw > 0 and lt[i]) or 0
				ln[i], ln[i + 4] = Spring(ln[i], ln[i + 4], tg, 2.2 * sp, 1, dt)
				ln[i], ln[i + 4] = Rest(ln[i], ln[i + 4], tg)
			end
		end
		self.STTS_LandT, self.STTS_LandTV, self.STTS_LandG, self.STTS_LandGV = t, tv, g, gv
		self.STTS_LandL, self.STTS_LandLV, self.STTS_LandTW = lam, lv, tw
		self.STTS_LandSide, self.STTS_LandAL, self.STTS_LandAR = side, aL, aR
		self.STTS_LandOn = t ~= 0 or lam ~= 0
		return t
	end
	-- the right hand on the right end: 0..1
	function SWEP:LandGrip()
		self:LandStep()
		return math.Clamp(self.STTS_LandG or 0, 0, 1)
	end
	-- the thumbs on the display: 0..1
	function SWEP:LandThumb()
		self:LandStep()
		local t = self.STTS_LandTW or 0
		return t * t * (3 - 2 * t)
	end
	-- the screen waits for the finger before a tap counts (portrait: the right index finger,
	-- landscape: the thumbs)
	function SWEP:FingerReady()
		self:LandStep()
		if (self.STTS_LandT or 0) ~= 0 or (self.STTS_LandG or 0) > 0.001 then return (self.STTS_LandTW or 0) >= 0.9 end
		return self.STTS_NoFinger or (self.STTS_RW or 0) >= 0.9
	end

	--[[ the palm offset of the turned phone (what HandOffset returns): the hand is carried
	     by part of the turn (kappa) and moves to its landscape spot (+ its lean) with lam.
	     hand = T * turn(-90 kappa th) * blend, phone = T * turn(-90 th), T = the phone
	     before the turn, so the wrist IK and the drawn phone stay one and the same ]]
	function SWEP:LandOffset(v, a)
		local th, lam = self.STTS_LandT or 0, self.STTS_LandL or 0
		local M = self:Geo()
		local c = Vector(M.ScreenPos.x, M.ScreenPos.y, 0)
		local carry = 90 * math.Clamp(landCarry:GetFloat(), 0, 1)
		local lP, _, hP, hA, roll = LeftSpot(self, v, a)
		-- v19.6: the lean (as you see the turned phone: x right, y up) in this frame
		local ln = self.STTS_Lean
		if ln and (ln[1] ~= 0 or ln[2] ~= 0) then lP = lP + Vector(ln[2], -ln[1], 0) end
		lP = c + RotV(lP - c, Z, carry)
		local pos = LerpVector(lam, hP, lP)
		local ang = RotA(hA, Z, lam * (carry - roll))
		local deg = (carry - 90) * th -- the phone in the carried hand
		return WorldToLocal(c - RotV(c, Z, deg), Angle(0, deg, 0), pos, ang)
	end

	-- the right hand on the right end: the left spot mirrored (as you see it), moved by
	-- stts_phone_land_rhand, carried by the turn like the left one. pPos / pAng = the phone now
	function SWEP:RightGrip(pPos, pAng)
		local M = self:Geo()
		local c = Vector(M.ScreenPos.x, M.ScreenPos.y, 0)
		local lP, lA = LeftSpot(self, self:PalmOffset())
		local n = LandNums(landRHandCvar, "r", LAND_R)
		local rP = Vector(lP.x + n[2], 2 * c.y - lP.y - n[1], lP.z + n[3])
		local x, y = lA:Forward(), -lA:Right() -- fingers, back of the hand
		x, y = Vector(x.x, -x.y, x.z), Vector(y.x, -y.y, y.z)
		local rA = x:AngleEx(x:Cross(y)) -- right hand: z = pinky side
		if n[4] ~= 0 then rA = RotA(rA, Z, -n[4]) end
		local psi = 90 * math.Clamp(landCarry:GetFloat(), 0, 1)
		psi = psi + (90 - psi) * (self.STTS_LandT or 0)
		local q = c + RotV(rP - c, Z, psi)
		local ln = self.STTS_Lean -- v19.6: its lean, already as you see the phone
		if ln and (ln[3] ~= 0 or ln[4] ~= 0) then q = q + Vector(ln[3], ln[4], 0) end
		return LocalToWorld(q, RotA(rA, Z, psi), pPos, pAng)
	end

	-- v19.6: a thumb (3 bones, the tip 0.85 of the middle one past the last joint) curled by c
	-- (0 = straight, 1 = fist) in the frame of its first bone: x along it, the joints bend
	-- toward +y around z (as in the hand poses). returns the tip (x, y) and the bone angles
	local function CurlXY(l0, l1, l2, c)
		local a1 = math.rad(CURL_MCP * c)
		local a2 = a1 + math.rad(CURL_IP * c)
		return l0 + l1 * math.cos(a1) + l2 * math.cos(a2), l1 * math.sin(a1) + l2 * math.sin(a2), a1, a2
	end
	local function CurlLen(l0, l1, l2, c)
		local x, y = CurlXY(l0, l1, l2, c)
		return math.sqrt(x * x + y * y)
	end
	-- the curl that puts the tip at distance d from the root (0..1, the length shrinks with it)
	local function CurlFor(l0, l1, l2, d)
		if d >= l0 + l1 + l2 then return 0 end
		if d <= CurlLen(l0, l1, l2, 1) then return 1 end
		local lo, hi = 0, 1
		for _ = 1, 16 do
			local mid = (lo + hi) * 0.5
			if CurlLen(l0, l1, l2, mid) > d then lo = mid else hi = mid end
		end
		return (lo + hi) * 0.5
	end
	-- angle a -> b by t without euler interpolation (forward and up blended, kept square)
	local function BlendAng(t, a, b)
		if t >= 0.999 then return b end
		local f = LerpVector(t, a:Forward(), b:Forward())
		if f:LengthSqr() < 1e-6 then return b end
		f:Normalize()
		local u = LerpVector(t, a:Up(), b:Up())
		u = u - f * u:Dot(f)
		if u:LengthSqr() < 1e-6 then return b end
		u:Normalize()
		return f:AngleEx(u)
	end
	local function ThumbBones(ent, names)
		local b0, b1, b2 = ent:LookupBone(names[1]), ent:LookupBone(names[2]), ent:LookupBone(names[3])
		local m0, m1, m2 = b0 and ent:GetBoneMatrix(b0), b1 and ent:GetBoneMatrix(b1), b2 and ent:GetBoneMatrix(b2)
		if not m0 or not m1 or not m2 then return end
		local l0 = m0:GetTranslation():Distance(m1:GetTranslation())
		local l1 = m1:GetTranslation():Distance(m2:GetTranslation())
		if l0 < 0.1 or l1 < 0.1 then return end
		return b0, b1, b2, m0, m1, m2, l0, l1, l1 * 0.85
	end

	--[[ v19.6 thumb IK: the tip of the thumb goes to tgt the way a thumb moves. its two
	     joints only bend (together, around the axis this thumb curls around in the hand
	     poses), the base joint turns the whole curled thumb the shortest way from base (the
	     first bone of the relaxed thumb) toward the target, so it keeps its roll: no sideways
	     bent joints, no twist between them. (v19.5 arched the joints toward the display
	     normal, across the way the thumb bends: a high arch and a broken looking thumb.)
	     too far = straight toward it, too close = a fist. w = 0..1 blend with its pose now ]]
	local function ThumbIK(ent, names, tgt, w, base)
		if w <= 0.001 then return end
		local b0, b1, b2, m0, m1, m2, l0, l1, l2 = ThumbBones(ent, names)
		if not b0 then return end
		local p0 = m0:GetTranslation()
		local d = tgt - p0
		local dist = d:Length()
		if dist < 0.05 then return end
		local x, y, a1, a2 = CurlXY(l0, l1, l2, CurlFor(l0, l1, l2, dist))
		local A = base or m0:GetAngles()
		local from = (A:Forward() * x - A:Right() * y):GetNormalized() -- the tip of the curled thumb
		local want = d / dist
		local axis = from:Cross(want)
		local sn = axis:Length()
		local A0 = sn > 1e-6 and RotA(A, axis / sn, math.deg(math.atan2(sn, from:Dot(want)))) or A
		local up = A0:Up()
		local A1, A2 = RotA(A0, up, math.deg(a1)), RotA(A0, up, math.deg(a2))
		if w < 0.999 then
			A0, A1, A2 = BlendAng(w, m0:GetAngles(), A0), BlendAng(w, m1:GetAngles(), A1), BlendAng(w, m2:GetAngles(), A2)
		end
		local q1 = p0 + A0:Forward() * l0
		m0:SetAngles(A0)
		m1:SetTranslation(q1) m1:SetAngles(A1)
		m2:SetTranslation(q1 + A1:Forward() * l1) m2:SetAngles(A2)
		ent:SetBoneMatrix(b0, m0) ent:SetBoneMatrix(b1, m1) ent:SetBoneMatrix(b2, m2)
	end

	-- the right thumb starts from the mirror image of the relaxed left one (the poses of the
	-- right hand hold it rolled around a gun grip): the left thumb in its hand (STTS_LThumb,
	-- SetHandPos takes it before its IK), z -> -z
	local function MirrorBase(self, hm)
		local m = hm and self.STTS_LThumb
		if not m then return end
		local a = m:GetAngles()
		local f, u = a:Forward(), a:Up()
		local _, ang = LocalToWorld(vector_origin, Vector(f.x, f.y, -f.z):AngleEx(Vector(-u.x, -u.y, u.z)), hm:GetTranslation(), hm:GetAngles())
		return ang
	end

	-- where a thumb lies while the other one taps (or both, while the cursor rests): fix57
	-- off the picture, at the lower corner of its end of the turned display, a little over
	-- the glass (phone space)
	local function ThumbRest(M, side)
		local sx = side == "L" and -1 or 1
		return Vector(M.ScreenPos.x + sx * (M.ScreenH * 0.5 + 0.05), M.ScreenPos.y - M.ScreenW * 0.32, M.ScreenPos.z + 0.35) -- fix68: on the bezel, not the glass
	end
	-- the target of a thumb (phone space): the finger target while it taps (a = 1, over the
	-- glass by the hover, on it by a tap), its rest spot while the other one taps (a = 0),
	-- in between it lifts off the glass on the way
	local function ThumbTarget(self, M, side, a)
		local tz = self.STTS_TZ or math.max(fHover:GetFloat(), 0)
		local cur = DisplayPoint(M, self.STTS_FingerUX or F_REST_X, self.STTS_FingerUY or F_REST_Y, 0.25 + 0.4 * math.max(tz, 0))
		if a >= 0.999 then return cur end
		local s = a * a * (3 - 2 * a)
		local p = LerpVector(s, ThumbRest(M, side), cur)
		p.z = p.z + 0.6 * math.sin(math.pi * s)
		return p
	end
	-- how much a hand gives (phone space as you see the turned phone: x right, y up) so its
	-- thumb reaches tgt: nothing while tgt is within the easy reach (neither straight nor a
	-- fist), LEAN_MAX at most. lx, ly = the lean the hand has now (taken out of the root)
	local function LeanFor(ent, names, tgt, pPos, pAng, lx, ly)
		local b0, _, _, m0, _, _, l0, l1, l2 = ThumbBones(ent, names)
		if not b0 then return 0, 0 end
		local root = WorldToLocal(m0:GetTranslation(), angle_zero, pPos, pAng)
		local dx, dy, dz = tgt.x - (root.x - lx), tgt.y - (root.y - ly), tgt.z - root.z
		local h = math.sqrt(dx * dx + dy * dy)
		if h < 0.05 then return 0, 0 end
		local far, near = CurlLen(l0, l1, l2, 0.12), CurlLen(l0, l1, l2, 0.9)
		local D2, z2 = h * h + dz * dz, dz * dz
		local k = 0
		if D2 > far * far then k = h - math.sqrt(math.max(far * far - z2, 0))
		elseif D2 < near * near then k = h - math.sqrt(math.max(near * near - z2, 0)) end
		k = math.Clamp(k, -LEAN_MAX, LEAN_MAX)
		return dx / h * k, dy / h * k
	end

	local FINGERS = {"1", "2", "3", "4"}
	--[[ open hand: every finger straightens along its knuckle (the metacarpal
	     direction) with a slight relaxed curl toward the palm. the side of the palm is
	     taken from the grip itself (where the curled finger points), w = 0..1.
	     side = "L" (default, the toss) / "R" (fix57: both, behind the landscape phone) ]]
	local OPEN_CURL = {8, 18, 28} -- degrees from the knuckle direction, per bone (cumulative)
	local function OpenFingers(ent, hand, w, side)
		if w <= 0.001 then return end
		local hm = ent:GetBoneMatrix(hand)
		if not hm then return end
		local hp, palm = hm:GetTranslation(), hm:GetAngles():Right()
		for _, f in ipairs(FINGERS) do
			local pre = "ValveBiped.Bip01_" .. (side or "L") .. "_Finger" .. f
			local ids = {ent:LookupBone(pre), ent:LookupBone(pre .. "1"), ent:LookupBone(pre .. "2")}
			local ms = {ids[1] and ent:GetBoneMatrix(ids[1]), ids[2] and ent:GetBoneMatrix(ids[2]), ids[3] and ent:GetBoneMatrix(ids[3])}
			if ms[1] and ms[2] and ms[3] then
				local P, A = {}, {}
				for i = 1, 3 do P[i], A[i] = ms[i]:GetTranslation(), ms[i]:GetAngles() end
				P[4] = P[3] + A[3]:Forward() * (P[2]:Distance(P[3]) * 0.9) -- the tip
				local k = P[1] - hp
				if k:LengthSqr() > 0.01 then
					k:Normalize()
					local tip = P[4] - P[1]
					local n = tip - k * tip:Dot(k)
					if n:LengthSqr() < 0.04 then n = palm - k * palm:Dot(k) end
					n:Normalize()
					for i = 1, 3 do
						local d = P[i + 1] - P[i]
						local l = d:Length()
						if l > 0.01 then
							local od = d / l
							local c = math.rad(OPEN_CURL[i])
							local nd = LerpVector(w, od, k * math.cos(c) + n * math.sin(c)):GetNormalized()
							local axis = od:Cross(nd)
							local sn = axis:Length()
							if sn > 1e-5 then
								axis = axis / sn
								local deg = math.deg(math.atan2(sn, od:Dot(nd)))
								for j = i, 3 do
									P[j + 1] = P[i] + RotV(P[j + 1] - P[i], axis, deg)
									A[j] = RotA(A[j], axis, deg)
								end
							end
						end
					end
					for i = 1, 3 do
						ms[i]:SetTranslation(P[i]) ms[i]:SetAngles(A[i])
						ent:SetBoneMatrix(ids[i], ms[i])
					end
				end
			end
		end
	end

	--[[ the fingers behind the landscape phone: the grip of the upright phone wraps the
	     fingers around its side, on the turned phone the same curl would go through it.
	     a finger bone whose end is inside the outline of the phone and not behind its back
	     turns back (around its joint, with the rest of the finger) until it lies behind it.
	     fix57: a bone whose end sticks out over a long edge of the turned phone (over its
	     top / under its bottom, in front of it or behind it) bends back behind the phone
	     with its end just inside that edge, so no finger tip shows around the picture.
	     pPos / pAng = the phone, w = 0..1 ]]
	local function FlatFingers(ent, side, pPos, pAng, M, w)
		if w <= 0.001 then return end
		local zb = M.Mins.z - 0.3
		local x0, x1, y0, y1 = M.Mins.x - 0.2, M.Maxs.x + 0.2, M.Mins.y - 0.2, M.Maxs.y + 0.2
		local ty0, ty1 = M.Mins.y + 0.45, M.Maxs.y - 0.45 -- the tuck line inside the long edges
		local pre = "ValveBiped.Bip01_" .. side .. "_Finger"
		for _, f in ipairs(FINGERS) do
			local b1, b2, b3 = ent:LookupBone(pre .. f), ent:LookupBone(pre .. f .. "1"), ent:LookupBone(pre .. f .. "2")
			local ms = {b1 and ent:GetBoneMatrix(b1), b2 and ent:GetBoneMatrix(b2), b3 and ent:GetBoneMatrix(b3)}
			if ms[1] and ms[2] and ms[3] then
				local P, A = {}, {}
				for i = 1, 3 do P[i], A[i] = WorldToLocal(ms[i]:GetTranslation(), ms[i]:GetAngles(), pPos, pAng) end
				P[4] = P[3] + A[3]:Forward() * (P[2]:Distance(P[3]) * 0.9) -- the tip
				local moved = false
				for i = 1, 3 do
					local e = P[i + 1]
					local d = e - P[i]
					local l = d:Length()
					local nd
					if e.z > zb and e.x > x0 and e.x < x1 and e.y > y0 and e.y < y1 then
						local hz = math.sqrt(d.x * d.x + d.y * d.y)
						if l > 0.01 and hz > 0.001 then
							local nz = math.Clamp((zb - P[i].z) / l, -1, 1)
							local k = math.sqrt(1 - nz * nz) / hz
							nd = Vector(d.x * k, d.y * k, nz)
						end
					elseif l > 0.01 and e.x > x0 and e.x < x1 and (e.y > ty1 or e.y < ty0)
						and e.z > zb - 6 and e.z < M.Maxs.z + 2 and P[i].y > y0 - 2.5 and P[i].y < y1 + 2.5 then
						-- fix57: the tuck over a long edge (the end goes just inside it, behind)
						local hx, hy = d.x, math.Clamp(e.y, ty0, ty1) - P[i].y
						local h = math.sqrt(hx * hx + hy * hy)
						if h > l * 0.97 then hx, hy, h = hx * l * 0.97 / h, hy * l * 0.97 / h, l * 0.97 end
						local hz = -math.sqrt(l * l - h * h)
						if P[i].z + hz > zb then hz = math.min(hz, zb - P[i].z) end
						nd = Vector(hx, hy, hz):GetNormalized()
					end
					if nd then
						local od = d / l
						if w < 0.999 then nd = LerpVector(w, od, nd):GetNormalized() end
						local axis = od:Cross(nd)
						local sn = axis:Length()
						if sn > 1e-5 then
							axis = axis / sn
							local deg = math.deg(math.atan2(sn, od:Dot(nd)))
							for j = i, 3 do
								P[j + 1] = P[i] + RotV(P[j + 1] - P[i], axis, deg)
								A[j] = RotA(A[j], axis, deg)
							end
							moved = true
						end
					end
				end
				if moved then
					local ids = {b1, b2, b3}
					for i = 1, 3 do
						local wp, wa = LocalToWorld(P[i], A[i], pPos, pAng)
						ms[i]:SetTranslation(wp) ms[i]:SetAngles(wa)
						ent:SetBoneMatrix(ids[i], ms[i])
					end
				end
			end
		end
	end

	-- the fingers of a hand relative to the hand bone
	local function FingerRel(ent, hand)
		local hm = ent:GetBoneMatrix(hand)
		local inv = hm and hm:GetInverse()
		local kids = inv and hg.get_children and hg.get_children(ent, hand)
		if not kids then return end
		local rel = {}
		for _, id in ipairs(kids) do
			local m = ent:GetBoneMatrix(id)
			if m then rel[id] = inv * m end
		end
		return rel, hm
	end

	local function FingerAxes(pAng)
		local n = Nums(fDir:GetString(), 3)
		local d = n and Vector(n[1], n[2], n[3]) or Vector(0.55, 0.45, -1)
		if d:LengthSqr() < 0.0001 then d = Vector(0.55, 0.45, -1) end
		d:Normalize()
		-- palm faces down the phone (-X), so the hand's Y (= -palm) is +X of the phone
		local y = Vector(1, 0, 0) - d * d.x
		if y:LengthSqr() < 0.0001 then y = Vector(0, 1, 0) end
		y:Normalize()
		local zl = d:Cross(y)
		local dW = LocalToWorld(d, angle_zero, vector_origin, pAng)
		local zW = LocalToWorld(zl, angle_zero, vector_origin, pAng)
		local a = dW:AngleEx(zW)
		local roll = fRoll:GetFloat()
		if roll ~= 0 then a:RotateAroundAxis(a:Forward(), roll) end
		return a
	end

	-- fix27: the jelly finger (fix26) is removed, the finger is rigid again
	--[[ v20: a soft finger again, but only where a real one gives: when the tap pushes it on
	     the glass (squash q = 0 .. 1.3, see TapStep) it arches. the middle joint bends toward
	     the palm (ARCH_PIP), the last one a little (ARCH_DIP), the knuckle turns the base back
	     by exactly as much as keeps the tip on the line of the straight finger (al), so the
	     finger only gets shorter (reach, DoFinger moves the hand in by it) and the middle and
	     last joints never bend the wrong way. straight = q 0. the bones bend toward the palm
	     side of the hand (-Y of the hand = Right(), as the curled fingers of the hand poses) ]]
	local ARCH_PIP, ARCH_DIP = 23, 10
	local function ArchFor(l1, l2, l3, q)
		local g2, g3 = math.rad(ARCH_PIP * q), math.rad((ARCH_PIP + ARCH_DIP) * q)
		local C = l1 + l2 * math.cos(g2) + l3 * math.cos(g3)
		local S = l2 * math.sin(g2) + l3 * math.sin(g3)
		return math.atan2(S, C), g2, g3, math.sqrt(C * C + S * S)
	end

	-- index finger straight along the hand (v20: arched by STTS_FArch), other fingers curled (pistol grip pose)
	local function PointPose(self, ent)
		local rh = ent:LookupBone("ValveBiped.Bip01_R_Hand")
		if not rh then return end
		if hg.set_holdrh then hg.set_holdrh(ent, "pistol_hold2") end
		local rm = ent:GetBoneMatrix(rh)
		local b1, b2, b3 = ent:LookupBone("ValveBiped.Bip01_R_Finger1"), ent:LookupBone("ValveBiped.Bip01_R_Finger11"), ent:LookupBone("ValveBiped.Bip01_R_Finger12")
		local m1, m2, m3 = b1 and ent:GetBoneMatrix(b1), b2 and ent:GetBoneMatrix(b2), b3 and ent:GetBoneMatrix(b3)
		if not rm or not m1 or not m2 or not m3 then return end
		local p1 = m1:GetTranslation()
		local l1 = (m2:GetTranslation() - p1):Length()
		local l2 = (m3:GetTranslation() - m2:GetTranslation()):Length()
		if l1 < 0.1 or l2 < 0.1 then return end
		local a = rm:GetAngles()
		local f = a:Forward()
		-- fingertip of the STRAIGHT finger in hand space (used next frame to place the hand,
		-- DoFinger takes the arch off it)
		local tip = p1 + f * (l1 + l2 + l2 * 0.85)
		self.STTS_TipL = WorldToLocal(tip, angle_zero, rm:GetTranslation(), a)
		self.STTS_FLen1, self.STTS_FLen2 = l1, l2
		local q = self.STTS_FArch or 0
		if q <= 0.001 then
			local p2 = p1 + f * l1
			local p3 = p2 + f * l2
			m1:SetAngles(a) ent:SetBoneMatrix(b1, m1)
			m2:SetTranslation(p2) m2:SetAngles(a) ent:SetBoneMatrix(b2, m2)
			m3:SetTranslation(p3) m3:SetAngles(a) ent:SetBoneMatrix(b3, m3)
			return
		end
		local al, g2, g3 = ArchFor(l1, l2, l2 * 0.85, q)
		local P, up = a:Right(), a:Up() -- the palm side; the joints bend around the hand's up
		local d1 = f * math.cos(al) - P * math.sin(al)
		local d2 = f * math.cos(g2 - al) + P * math.sin(g2 - al)
		local d3 = f * math.cos(g3 - al) + P * math.sin(g3 - al)
		local p2 = p1 + d1 * l1
		local p3 = p2 + d2 * l2
		m1:SetAngles(d1:AngleEx(up)) ent:SetBoneMatrix(b1, m1)
		m2:SetTranslation(p2) m2:SetAngles(d2:AngleEx(up)) ent:SetBoneMatrix(b2, m2)
		m3:SetTranslation(p3) m3:SetAngles(d3:AngleEx(up)) ent:SetBoneMatrix(b3, m3)
	end

	--[[ fix71: vanilla Z-City says "no right hand" only for a missing arm. custom builds / other
	     addons make hg.CanUseRightHand false for more (a gesture, an item, their own states) and
	     the finger then never came to the display. stts_phone_finger_force 1 (default): only the
	     missing arm counts; 0 = ask hg.CanUseRightHand like before ]]
	function SWEP:RightHandFree71(ply)
		if not IsValid(ply) then return false end
		local ent = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
		if ent.organism and ent.organism.rarmamputated then return false end
		if not (hg and hg.CanUseRightHand) then return true end
		local cv = GetConVar("stts_phone_finger_force")
		if cv == nil or cv:GetBool() then return true end
		return hg.CanUseRightHand(ply) and true or false
	end

	function SWEP:DoFinger(ply, ent, pPos, pAng, dt, e)
		-- RMB free look: the right hand goes back to the normal pose of the player
		-- (v19.5: not while it holds the landscape phone)
		local look = LookOn(self, ply)
		local canRight = hg.DragRightHand_Ex and self:RightHandFree71(ply)
		self.STTS_NoFinger = not canRight -- broken right arm: the phone still works without the finger
		local g = canRight and self:LandGrip() or 0
		-- fix58: a driver: the hand rests on the wheel and comes to the phone only "in action"
		local wr, wra = self.STTS_WRP, self.STTS_WRA
		local act = not wr or CarAct(self, ply)
		local want = self:IsUp() and canRight and (not look or g > 0.01) and act
			and not self:ZManip68(ply) -- fix68: the use animation of Z-City: the right hand rests
		self.STTS_RW = math.Approach(self.STTS_RW or 0, want and 1 or 0, dt * 4)
		local rw = math.min(self.STTS_RW, e)
		if rw <= 0.001 then
			self.STTS_FP, self.STTS_FV = nil, nil
			if wr and canRight then hg.DragRightHand_Ex(ent, self, Vector(wr), Angle(wra)) end
			return
		end
		local rh = ent:LookupBone("ValveBiped.Bip01_R_Hand")
		local rm = rh and ent:GetBoneMatrix(rh)
		if not rm then return end
		local restP, restA = rm:GetTranslation(), rm:GetAngles()
		if wr then restP, restA = Vector(wr), Angle(wra) end
		local M = self:Geo() -- fix28: display of this model

		local hPos, hAng
		-- v20: how much of the jelly this frame (none once the hand holds the landscape phone)
		local j = math.Clamp(fJelly:GetFloat(), 0, 2.5) * (1 - g)
		self.STTS_FArch = math.min((self.STTS_TQ or 0) * j, 1.3)
		if g < 0.999 and look then
			-- fix57: free look (RMB) and the landscape grip lets go / takes it: the hand goes
			-- between the grip and its normal pose, never through the pointing finger
			hPos, hAng = restP, restA
		elseif g < 0.999 then
			-- fingertip on the display (phone space), lifted by the hover and pushed down by a tap
			-- (v20: under zero = the squash, the tip stays on the glass)
			local lift = math.max(self.STTS_TZ or math.max(fHover:GetFloat(), 0), 0) + 0.12
			local tipW = LocalToWorld(DisplayPoint(M, self.STTS_FingerUX or F_REST_X, self.STTS_FingerUY or F_REST_Y, lift), angle_zero, pPos, pAng)
			-- v19.4: turned phone = the finger direction of the phone as it stood before the turn
			-- (the right hand keeps coming from the lower right as you see it)
			local th = self:LandTurn()
			hAng = FingerAxes(math.abs(th) > 0.0005 and RotA(pAng, pAng:Up(), 90 * th) or pAng)
			local tilt = self.STTS_TA or 0 -- the wrist twists a little on impact
			if tilt ~= 0 then hAng:RotateAroundAxis(hAng:Right(), tilt) end
			local tipL = self.STTS_TipL or Vector(7.2, 0, -1.3)
			-- v20: the arched finger is shorter, the hand comes in along it (the tip stays put)
			local l1, l2 = self.STTS_FLen1, self.STTS_FLen2
			if l1 and l2 and self.STTS_FArch > 0.001 then
				local _, _, _, reach = ArchFor(l1, l2, l2 * 0.85, self.STTS_FArch)
				tipL = tipL - Vector(l1 + l2 * 1.85 - reach, 0, 0)
			end
			-- v20 jelly: the hand turns around the fingertip. the wrist trails a quick move
			-- (toward the anchor STTS_FW that lags behind the tip, FingerStep) and swings past,
			-- and it dips toward the glass after a tap (STTS_TD, TapStep)
			local r = -LocalToWorld(tipL, angle_zero, vector_origin, hAng) -- tip -> wrist
			local om = Vector(0, 0, 0)
			local fw, fp = self.STTS_FW, self.STTS_FP
			if j > 0.001 and fw and fp then
				local lag = Vector(-(fw.y - fp.y) * M.ScreenH / G.RTH, -(fw.x - fp.x) * M.ScreenW / G.RTW, 0)
				lag = LocalToWorld(lag, angle_zero, vector_origin, pAng)
				om = r:Cross(lag) * (SWAY_GAIN * j / math.max(r:LengthSqr(), 1))
			end
			local dip = (self.STTS_TD or 0) * (1 - g)
			if dip ~= 0 then
				local ax = pAng:Up():Cross(r) -- turning around it takes the wrist toward the glass
				if ax:LengthSqr() > 1e-6 then
					ax:Normalize()
					om = om + ax * math.rad(dip)
				end
			end
			local deg = math.deg(om:Length())
			if deg > 0.01 then hAng = RotA(hAng, om:GetNormalized(), Soft(deg, SWAY_MAX)) end
			hPos = tipW - LocalToWorld(tipL, angle_zero, vector_origin, hAng)
		end
		-- v19.5: landscape = the right hand takes the right end, on an arc toward you
		if g > 0.001 then
			local gPos, gAng = self:RightGrip(pPos, pAng)
			if g >= 0.999 then
				hPos, hAng = gPos, gAng
			else
				local k = g * g * (3 - 2 * g)
				hPos = LerpVector(k, hPos, gPos) + pAng:Up() * (math.sin(math.pi * k) * 1.2)
				hAng = Slerp(k, hAng, gAng)
			end
		end

		local s = rw * rw * (3 - 2 * rw)
		if s < 0.999 then
			hPos = LerpVector(s, restP, hPos)
			hAng = Slerp(s, restA, hAng)
		end
		hg.DragRightHand_Ex(ent, self, hPos, hAng)
		if s <= 0.25 then return end -- fingers switch once the hand is mostly there
		-- pointing finger -> holding fingers, blended while the hand travels
		local k = math.Clamp((g - 0.3) / 0.4, 0, 1)
		if k <= 0 then
			if not look then PointPose(self, ent) end
			return
		end
		if k < 1 then
			if not look then PointPose(self, ent) end -- (free look: from the fingers of its pose)
			local A = FingerRel(ent, rh)
			if hg.set_holdrh then hg.set_holdrh(ent, "ak_hold") end
			local B, hm = FingerRel(ent, rh)
			if A and B then
				k = k * k * (3 - 2 * k)
				for id, mb in pairs(B) do
					local ma = A[id]
					if ma then
						local m = Matrix()
						m:SetAngles(Slerp(k, ma:GetAngles(), mb:GetAngles()))
						m:SetTranslation(LerpVector(k, ma:GetTranslation(), mb:GetTranslation()))
						ent:SetBoneMatrix(id, hm * m)
					end
				end
			end
		elseif hg.set_holdrh then
			hg.set_holdrh(ent, "ak_hold")
		end
		local gw = (g * g * (3 - 2 * g)) * s
		OpenFingers(ent, rh, 0.45 * gw, "R") -- fix57: flatter on the back, not a fist
		FlatFingers(ent, "R", pPos, pAng, M, gw)
		-- v19.6: the right thumb lies on the glass at the bottom edge, or it taps the right
		-- half of the turned display (ThumbTarget / ThumbIK / LeanFor)
		local w = math.Clamp((g - 0.5) * 2, 0, 1)
		w = w * w * (3 - 2 * w) * s
		local lt = self.STTS_LeanT
		if w > 0.001 then
			local aR = self.STTS_LandAR or 0
			local tgt = ThumbTarget(self, M, "R", aR)
			local hm = ent:GetBoneMatrix(rh)
			ThumbIK(ent, THUMB_R, LocalToWorld(tgt, angle_zero, pPos, pAng), w, MirrorBase(self, hm))
			if not lt then lt = {0, 0, 0, 0} self.STTS_LeanT = lt end
			lt[3], lt[4] = 0, 0
			if aR >= 0.999 then
				local ln = self.STTS_Lean
				lt[3], lt[4] = LeanFor(ent, THUMB_R, tgt, pPos, pAng, ln and ln[3] or 0, ln and ln[4] or 0)
			end
		elseif lt then lt[3], lt[4] = 0, 0 end
	end

	--[[ Q (Z-City radial menu) -> "Toss phone": the left hand flips the phone up and
	     catches it again, like an inspect. LMB in the menu = one flip, RMB = a higher
	     double flip. everybody around sees it (the server relays the start + a seed).
	     the whole thing is a function of time (CurTime), so the hand and the phone are
	     always in sync and the catch lands exactly in the palm.
	     fix56: built from the physics of a real flip, nothing jumps any more:
	       raise       0 .. 0.3 s the hand comes up in front of the chest (display up)
	       wind-up     the hand dips a little, the wrist cocks back (a short reversal)
	       flick       hand + wrist accelerate evenly; at the release the phone has
	                   EXACTLY the speed and the spin of the palm (it leaves the hand,
	                   it is not shot off it). a double flip needs more spin than a
	                   wrist gives: the phone rolls off the fingertips for the last
	                   few hundredths (it turns around the heel of the palm)
	       follow-thr. the hand goes on up and decelerates, the wrist flexes on
	       flight      ballistic (real gravity in this scale), constant spin + a small
	                   tumble that settles; the hand comes back under it and waits
	       catch       soft hands: the palm already gives downward as the phone meets
	                   it, takes a part of its momentum (a small jolt), decelerates on
	                   a damped spring, the wrist gives in the spin direction
	       then        back to the idle pose
	     hand keys: {time, up, forward, wrist flick (deg, + = the top goes up)} with
	     explicit velocities (per second) or Catmull-Rom ones. the flick turns the phone
	     around the wrist, so the hand pivots like a real one.
	     positions are in the toss frame: x = forward (view yaw), y = left, z = world up ]]
	local TOSS_G = 515 -- 9.81 m/s2 (1 unit = 1.905 cm)
	local TOSS_KINDS = {
		-- h = height over the release point, n = turns, wrist = the dip (up, fwd, deg), fl = flick time,
		-- wmax = the fastest wrist (deg / s), give = the palm moves down this part of the phone speed at the catch
		{h = 10, n = 1, wind = {-1.8, -0.4, -20}, tw0 = 0.44, fl = 0.085, ft = 0.075, wmax = 820, give = 0.26, mass = 0.18, tum = 12, wob = 8},
		{h = 15, n = 2, wind = {-2.4, -0.5, -24}, tw0 = 0.46, fl = 0.095, ft = 0.08, wmax = 960, give = 0.3, mass = 0.18, tum = 14, wob = 9},
	}
	local TOSS_MEET = 1.0 -- the palm takes the phone this much over its start
	local TOSS_ROLL = 0.045 -- the double flip rolls off the fingertips this long before the release
	local TOSS_REST = Angle(-28, 6, 0) -- the phone on the palm: the top 28 deg up, 6 deg out
	-- the catch: a damped spring (2.6 Hz, damping 0.55) started with the speed of the palm
	local IMP_W, IMP_Z = 2 * math.pi * 2.6, 0.55
	local IMP_WD = IMP_W * math.sqrt(1 - IMP_Z * IMP_Z)

	local function Smooth01(x)
		x = math.Clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end

	-- the phone on the palm for a hand state, in the toss frame
	local function TossPalm(P, up, fwd, deg)
		local pos = P.W + RotV(-P.W, P.axis, deg)
		pos.x = pos.x + fwd
		pos.z = pos.z + up
		return pos, RotA(TOSS_REST, P.axis, deg)
	end

	-- the hand keys at time t: cubic Hermite, k.m = velocity into the key, k.mo = out of it
	local function TossKeys(keys, t)
		local n = #keys
		if t <= keys[1][1] then return keys[1][2], keys[1][3], keys[1][4] end
		for i = 1, n - 1 do
			local a, b = keys[i], keys[i + 1]
			if t <= b[1] then
				local d = b[1] - a[1]
				local s = d > 0 and (t - a[1]) / d or 1
				local s2 = s * s
				local s3 = s2 * s
				local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, 3 * s2 - 2 * s3, s3 - s2
				local am, bm = a.mo or a.m, b.m
				return h00 * a[2] + h10 * d * am[1] + h01 * b[2] + h11 * d * bm[1],
					h00 * a[3] + h10 * d * am[2] + h01 * b[3] + h11 * d * bm[2],
					h00 * a[4] + h10 * d * am[3] + h01 * b[4] + h11 * d * bm[3]
			end
		end
		return keys[n][2], keys[n][3], keys[n][4]
	end

	-- Catmull-Rom velocities for the keys that have none
	local function TossTangents(keys)
		for i, k in ipairs(keys) do
			if not k.m then
				local a, b = keys[i - 1], keys[i + 1]
				local m = {0, 0, 0}
				if a and b then
					local d = b[1] - a[1]
					for j = 1, 3 do m[j] = (b[j + 1] - a[j + 1]) / d end
				end
				k.m = m
			end
		end
	end

	-- the phone while it is still on the hand (before the release): the palm pose + the roll
	-- off the fingertips (a turn around the heel of the palm, it lifts off the fingers)
	local function TossOnHand(P, t)
		local up, fwd, deg = TossKeys(P.keys, t)
		local pos, ang = TossPalm(P, up, fwd, deg)
		local hp, ha = pos, ang
		local dw = P.roll or 0
		if dw <= 0 or t <= P.tr - TOSS_ROLL then return pos, ang, hp, ha, deg, false end
		local u = math.min(t, P.tr) - (P.tr - TOSS_ROLL)
		local e = dw * u * u / (2 * TOSS_ROLL) -- the roll speeds up evenly to dw at the release
		local pv = LocalToWorld(P.heel, angle_zero, pos, ang)
		return pv + RotV(pos - pv, P.axis, e), RotA(ang, P.axis, e), hp, ha, deg + e, true
	end

	local function TossPlan(self, kind, seed)
		local K = TOSS_KINDS[kind] or TOSS_KINDS[1]
		-- the wrist (pivot of the flick) when the phone lies at rest
		local vec, off = self:PalmOffset()
		local ip, ia = WorldToLocal(vector_origin, angle_zero, vec, off)
		local P = {kind = kind, K = K, W = (LocalToWorld(ip, ia, vector_origin, TOSS_REST)), axis = TOSS_REST:Right()}
		-- the heel of the palm under the phone: its end toward the wrist, on its back
		local M = self:Geo()
		local mn, mx = M.Mins, M.Maxs
		local wl = WorldToLocal(P.W, angle_zero, vector_origin, TOSS_REST) -- the wrist in the phone frame
		P.heel = Vector(wl.x < 0 and mn.x * 0.8 or mx.x * 0.8, 0, mn.z)
		local g, wind = TOSS_G, K.wind
		local tw, tr = K.tw0, K.tw0 + K.fl
		P.tr = tr
		local v0 = math.sqrt(2 * g * K.h)
		local cp = TossPalm(P, TOSS_MEET, 0, 0) -- the phone in the palm at the catch
		-- solve the flick: the palm speed / spin at the release that make the flight end in the palm
		local vu, vf, wd, roll, T = v0 * 0.5, 0, K.wmax * 0.8, 0, 0.4
		local rp, ra, rv
		for _ = 1, 8 do
			local roll0 = roll
			P.roll = roll
			local kr = {tr, wind[1] + vu * K.fl * 0.5, wind[2] + vf * K.fl * 0.5, wind[3] + wd * K.fl * 0.5, m = {vu, vf, wd}}
			P.keys = {
				{0, 0, 0, 0, m = {0, 0, 0}},
				{0.26, 0.5, 0.3, 3},
				{tw, wind[1], wind[2], wind[3], m = {0, 0, 0}},
				kr,
			}
			TossTangents(P.keys)
			local h = 1 / 2000
			local p1, _, _, _, d1 = TossOnHand(P, tr - h)
			local p2, _, _, _, d2 = TossOnHand(P, tr)
			rp, ra, rv = p2, d2, (p2 - p1) / h
			local spin = (d2 - d1) / h
			-- flight time from the real vertical speed down to the palm
			T = (rv.z + math.sqrt(math.max(rv.z * rv.z + 2 * g * (rp.z - cp.z), 1))) / g
			T = math.Clamp(T, 0.3, 1.2)
			-- the spin it needs (n turns + land flat), the wrist gives what it can, the fingers the rest
			local need = (360 * K.n - ra) / T
			local wNew = math.min(need, K.wmax)
			roll = math.max(need - wNew, 0)
			wd = wd + (wNew - (spin - roll0)) -- (spin = wrist + roll)
			-- the vertical speed (the wrist adds to it), the forward speed that ends over the palm
			vu = vu + (v0 - rv.z)
			vf = vf + ((cp.x - rp.x) / T - rv.x)
		end
		P.T, P.v0, P.rp, P.ra, P.rv = T, rv.z, rp, ra, rv
		P.spin = (360 * K.n - ra) / T
		P.tc = tr + T
		P.cp = cp
		-- the corrections (tiny) so the flight ends exactly in the palm
		P.ex = cp.x - (rp.x + rv.x * T)
		P.ey = cp.y - (rp.y + rv.y * T)
		-- the catch: the palm gives downward with a part of the phone speed
		local vin = math.abs(rv.z - g * T)
		local vc = -K.give * vin
		local dm = 0.07
		local keys = P.keys
		local kr = keys[#keys]
		-- follow-through: on up, decelerating evenly (the wrist a bit harder)
		local ft = K.ft
		local tf = tr + ft
		keys[#keys + 1] = {tf, kr[2] + kr.m[1] * ft * 0.5, kr[3] + kr.m[2] * ft * 0.5, kr[4] + kr.m[3] * ft * 0.36, m = {0, 0, 0}}
		-- under it, waiting; then down into the catch
		keys[#keys + 1] = {P.tc - dm, TOSS_MEET - vc * dm * 0.5, 0, -1.5, m = {0, 0, 0}}
		keys[#keys + 1] = {P.tc, TOSS_MEET, 0, 0, m = {vc, 0, 60}, mo = {0, 0, 0}}
		keys[#keys + 1] = {P.tc + 0.4, 0, 0, 0, m = {0, 0, 0}}
		P.out = P.tc + 0.42 -- back to the idle pose from here
		P.D = P.out + 0.36
		keys[#keys + 1] = {P.D, 0, 0, 0, m = {0, 0, 0}}
		-- the catch: the palm (hand + forearm, ~1 kg) takes the momentum of the phone (~0.18 kg)
		local mr = K.mass / (1 + K.mass)
		P.vu = vc - mr * (vin + vc) -- vc < 0, the phone comes down faster
		P.vd = 60 + mr * P.spin * 0.6 -- the wrist gives in the spin direction
		-- the seed: the same tumble / wobble for everyone who sees it
		local s = math.floor(tonumber(seed) or 0) % 65536
		P.tw = ((s % 256) / 255 * 2 - 1) * K.tum
		P.wb = ((math.floor(s / 256) % 256) / 255 * 2 - 1) * K.wob
		return P
	end

	-- phone pose, palm pose (both in the toss frame), in the air?
	local function TossLocal(P, t)
		if t < P.tr then
			local pos, ang, hp, ha, _, rolled = TossOnHand(P, t)
			return pos, ang, hp, ha, rolled
		end
		local up, fwd, deg = TossKeys(P.keys, t)
		if t > P.tc then -- the palm gives under the caught phone (a damped spring started with its speed)
			local u = t - P.tc
			local k = math.exp(-IMP_Z * IMP_W * u) * math.sin(IMP_WD * u) / IMP_WD
			up = up + P.vu * k
			deg = deg + P.vd * k
		end
		local hp, ha = TossPalm(P, up, fwd, deg)
		if t >= P.tc then return hp, ha, hp, ha, false end
		local tau = t - P.tr
		local s = tau / P.T
		local s2 = s * s
		local rp, rv = P.rp, P.rv
		local pos = Vector(rp.x + rv.x * tau + P.ex * s2, rp.y + rv.y * tau + P.ey * s2, rp.z + rv.z * tau - 0.5 * TOSS_G * tau * tau)
		local ang = RotA(TOSS_REST, P.axis, P.ra + P.spin * tau)
		-- a small tumble (the hand is never perfectly square), gone again when it lands
		local b = math.sin(math.pi * s)
		b = b * b
		if P.tw ~= 0 then ang = RotA(ang, ang:Forward(), P.tw * b) end
		if P.wb ~= 0 then ang = RotA(ang, Z, P.wb * b) end
		return pos, ang, hp, ha, true
	end

	-- the fingers: open as the phone leaves the palm, a little cupped toward the catch, closed on it
	local function TossOpen(P, t)
		local open = math.min(Smooth01((t - P.tr + 0.05) / 0.1), 1 - Smooth01((t - P.tc + 0.01) / 0.11))
		return open * (1 - 0.3 * Smooth01((t - P.tc + 0.14) / 0.1))
	end

	-- blend with the normal pose of the hand: in over 0.34 s, out at the end
	local function TossWeight(P, t)
		return math.min(Smooth01(t / 0.34), 1 - Smooth01((t - P.out) / (P.D - P.out)))
	end

	function SWEP:StartToss(kind, seed)
		local P = TossPlan(self, kind, seed)
		P.t0 = CurTime()
		self.STTS_Toss, self.STTS_TossF = P, nil
		self.STTS_TossEnd = P.t0 + P.D
	end

	-- your own toss: starts right away, the server tells the others
	function SWEP:RequestToss(kind)
		if not self:CanToss() then return end
		kind = kind == 2 and 2 or 1
		local seed = math.random(0, 65535)
		self:StartToss(kind, seed)
		net.Start("stts_phone_toss")
		net.WriteUInt(kind, 2)
		net.WriteUInt(seed, 16)
		net.SendToServer()
	end

	-- the phone in the air this frame (drawn there instead of the palm)
	function SWEP:TossFree()
		if self.STTS_Toss and self.STTS_TossF == FrameNumber() then return self.STTS_TossP, self.STTS_TossA end
	end

	-- while the hand does it the arm bones stay neutral (as when posed), see Step
	function SWEP:TossArm()
		local P = self.STTS_Toss
		return P ~= nil and CurTime() - P.t0 < P.out
	end

	-- per think (Step, also for players you do not see): the end, interruptions (no sounds)
	function SWEP:TossTick()
		local P = self.STTS_Toss
		if not P then return end
		local t = CurTime() - P.t0
		local ply = self:GetOwner()
		if t >= P.D or t < -0.5 or not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) or self:Posed() then self.STTS_Toss = nil return end
	end

	-- the left hand during the toss (from SetHandPos, after the body bones, before the arm IK)
	function SWEP:TossHand(ent, hand, vec, off, animPos, animAng, fo, fa, dt)
		local P = self.STTS_Toss
		local t = CurTime() - P.t0
		if t >= P.D or t < -0.5 then self.STTS_Toss = nil return false end
		-- the toss frame: in front of the chest, follows the view (yaw + a part of the pitch), a bit smoothed
		local tp = math.Clamp(math.NormalizeAngle(fa.p) * 0.7, -12, 24)
		if not P.ay then
			P.ay, P.ap = fa.y, tp
		elseif dt > 0 then
			local k = 1 - math.exp(-dt * 12)
			P.ay = math.NormalizeAngle(P.ay + math.AngleDifference(fa.y, P.ay) * k)
			P.ap = P.ap + (tp - P.ap) * k
		end
		local va = Angle(P.ap, P.ay, 0)
		local origin = fo + va:Forward() * 14.5 - va:Right() * 2.5 - va:Up() * 6.5
		local frame = Angle(0, P.ay, 0)
		local lp, la, hp, ha, free = TossLocal(P, math.max(t, 0))
		local pPos, pAng = LocalToWorld(lp, la, origin, frame)
		local hPos, hAng = pPos, pAng
		if free then hPos, hAng = LocalToWorld(hp, ha, origin, frame) end
		local e = TossWeight(P, math.max(t, 0))
		if e < 0.999 then
			hPos = LerpVector(e, animPos, hPos)
			hAng = Slerp(e, animAng, hAng)
			if not free then pPos, pAng = hPos, hAng end
		end
		-- palm pose -> wrist pose (inverse of the palm offset)
		local _, inverse = WorldToLocal(vector_origin, angle_zero, vector_origin, off)
		local _, handAng = LocalToWorld(vector_origin, inverse, vector_origin, hAng)
		local displacement = LocalToWorld(vec, angle_zero, vector_origin, handAng)
		hg.DragLeftHand_Ex(ent, self, hPos - displacement, handAng)
		if self.STTS_LFing then ApplyLeftFingers(self, ent, hand)
		elseif hg.set_hold then hg.set_hold(ent, "normal") end
		local open = TossOpen(P, t) * e
		if open > 0.001 then OpenFingers(ent, hand, open) end
		self.STTS_TossP, self.STTS_TossA, self.STTS_TossF = pPos, pAng, free and FrameNumber() or nil
		return true
	end

	function SWEP:SetHandPos()
		self.lhandik = false self.rhandik = false
		local ply = self:GetOwner()
		if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or not hg or not hg.DragLeftHand_Ex then return end
		local ent = hg.GetCurrentCharacter(ply)
		if not IsValid(ent) then return end
		-- fix74: in the hand again right after it was in the left hand next to a weapon
		-- (STTS.PhoneRH below): the pose goes on from where that hand held it
		if self.STTS_RHT then
			if RealTime() - self.STTS_RHT < 0.3 and self.STTS_RHLP and self.STTS_RHLA and ent == ply then
				self.STTS_LPos, self.STTS_LAng, self.STTS_W = Vector(self.STTS_RHLP), Angle(self.STTS_RHLA), self.STTS_RHW or 0
			end
			self.STTS_RHT = nil
		end
		--[[ fix58: in a vehicle the ragdoll sits in the seat (parented, no physics hold):
		     the hands are placed here like on foot, Z-City's wheel IK is skipped for the
		     phone (sh_phone_car.lua). driver: idle = both hands on the wheel, raised =
		     the right one stays there until it is "in action" ]]
		local car = ply:InVehicle()
		local wl, wla, wr, wra
		if car then wl, wla, wr, wra = Wheel(ply) end
		self.STTS_WRP, self.STTS_WRA = wr, wra
		if hg.CanUseLeftHand and not hg.CanUseLeftHand(ply) then
			self.STTS_W, self.STTS_Toss = 0, nil
			if wl then hg.DragLeftHand_Ex(ent, self, Vector(wl), Angle(wla)) end -- (what Z-City would do)
			return
		end
		local hand = ent:LookupBone("ValveBiped.Bip01_L_Hand")
		local hm = hand and ent:GetBoneMatrix(hand)
		if not hm then return end
		local vec, off = self:HandOffset()
		local animPos, animAng = LocalToWorld(vec, off, wl or hm:GetTranslation(), wla or hm:GetAngles())

		-- fix24: ragdoll = the phone stays on the REAL hand (the server holds it up),
		-- no IK of the left hand toward the view. only the finger goes to the display
		if ent ~= ply and self:FakeRagdoll() and not car then
			self.STTS_Toss = nil
			local frame = FrameNumber()
			local dt = math.min(FrameTime(), 0.1)
			local newFrame = self.STTS_Frame ~= frame
			if newFrame then
				self.STTS_Frame = frame
				self.STTS_W = math.Approach(self.STTS_W or 0, self:Posed() and 1 or 0, dt * 3.2)
				self:FingerStep(dt)
			end
			self.STTS_LPos, self.STTS_MOutP, self.STTS_MOutR = nil, nil, nil
			self.STTS_MP, self.STTS_MV, self.STTS_MT, self.STTS_MPrevFa = nil, nil, nil, nil
			local w = self.STTS_W or 0
			if w <= 0.001 then self.STTS_RW, self.STTS_FP, self.STTS_FV = 0, nil, nil return end
			self:DoFinger(ply, ent, animPos, animAng, newFrame and dt or 0, w * w * (3 - 2 * w))
			return
		end

		local fo, fa = Face(ply, ent)
		local tPos, tAng = self:PoseTarget(ply, ent, fo, fa)
		-- someone else's phone during a video call: the exact pose of his phone
		-- (relative to his body) comes over the net, so the phone you see in his
		-- hand is exactly where the camera you watch is
		local exact = false
		if tPos and ply ~= LocalPlayer() and STTS.PhoneScreen and STTS.PhoneScreen.RemotePose then
			local rp, ra = STTS.PhoneScreen.RemotePose(self, ply)
			if rp then tPos, tAng, exact = rp, ra, true end
		end

		--[[ the smoothing runs in the frame of the EYES, not in world space:
		     before, the target was lerped in world space, so while walking the
		     phone trailed far behind the head (big "fake lag"). now walking /
		     turning moves the phone together with the view, and only a small
		     physical sway is added on top (Motion). ]]
		local frame = FrameNumber()
		local dt = math.min(FrameTime(), 0.1)
		local newFrame = self.STTS_Frame ~= frame
		if newFrame then
			self.STTS_Frame = frame
			self.STTS_W = math.Approach(self.STTS_W or 0, tPos and 1 or 0, dt * 3.2)
			if tPos then
				local lPos, lAng = WorldToLocal(tPos, tAng, fo, fa)
				if not self.STTS_LPos then self.STTS_LPos, self.STTS_LAng = WorldToLocal(animPos, animAng, fo, fa) end
				local k = exact and 1 or (1 - math.exp(-dt * 11))
				self.STTS_LPos = LerpVector(k, self.STTS_LPos, lPos)
				self.STTS_LAng = exact and lAng or Slerp(k, self.STTS_LAng, lAng)
			end
			if exact then
				self.STTS_MOutP, self.STTS_MOutR = nil, nil -- his own sway is already in the pose
			else
				Motion(self, ply, fo, fa, dt, self:PoseMode() or "ear")
			end
			self:FingerStep(dt)
		end
		local w = self.STTS_W or 0
		-- Q menu: the phone is being tossed (TossHand). posed = the toss is over (TossTick)
		if self.STTS_Toss and not tPos and ent == ply and self:TossHand(ent, hand, vec, off, animPos, animAng, fo, fa, newFrame and dt or 0) then return end
		if w <= 0.001 or not self.STTS_LPos then
			self.STTS_LPos = nil
			self.STTS_MP, self.STTS_MV, self.STTS_MT, self.STTS_MPrevFa, self.STTS_MOutP, self.STTS_MOutR = nil, nil, nil, nil, nil, nil
			self.STTS_MEy, self.STTS_MWy, self.STTS_MEp, self.STTS_MWp = 0, 0, 0, 0
			self.STTS_RW, self.STTS_FP, self.STTS_FV = 0, nil, nil
			if wl then -- fix58: idle while driving = both hands on the wheel
				hg.DragLeftHand_Ex(ent, self, Vector(wl), Angle(wla))
				if wr and self:RightHandFree71(ply) then hg.DragRightHand_Ex(ent, self, Vector(wr), Angle(wra)) end
			end
			CaptureLeftFingers(self, ent, hand) -- idle: remember how the fingers hold the phone
			return
		end
		local e = w * w * (3 - 2 * w) -- smoothstep: no snap at either end
		local wPos, wAng = LocalToWorld(self.STTS_LPos, self.STTS_LAng, fo, fa)
		-- physical motion (see Motion): the arm swings around the eyes, the phone leans on its own center
		local mp, mr = self.STTS_MOutP, self.STTS_MOutR
		if mr then
			local rel = wPos - fo
			if mr.x ~= 0 then rel = self.RotV(rel, fa:Up(), mr.x) wAng = self.RotA(wAng, fa:Up(), mr.x) end
			if mr.y ~= 0 then rel = self.RotV(rel, fa:Right(), -mr.y) wAng = self.RotA(wAng, fa:Right(), -mr.y) end
			wPos = fo + rel
			if mr.z ~= 0 then wAng = self.RotA(wAng, fa:Forward(), mr.z) end
		end
		if mp then wPos = wPos + fa:Forward() * mp.x + fa:Right() * mp.y + fa:Up() * mp.z end
		-- v19.4: landscape. turned here (after the smoothing), so the phone turns exactly as
		-- the palm offset does. the exact pose of someone else's video call is turned already.
		-- v19.5: a spring, and the hands give a little while they turn it (it dips and tilts)
		local th = self:LandTurn()
		if math.abs(th) > 0.0005 and not exact then
			local M = self:Geo()
			local k = math.sin(math.pi * math.Clamp(th, 0, 1))
			if k > 0.001 then
				wPos = wPos + fa:Forward() * (0.35 * k) - fa:Up() * (0.45 * k)
				wPos, wAng = Spin(M, wPos, wAng, fa:Right(), -4 * k)
			end
			wPos, wAng = Spin(M, wPos, wAng, wAng:Up(), -90 * th)
		end
		local pPos = LerpVector(e, animPos, wPos)
		local pAng = Slerp(e, animAng, wAng)

		-- phone pose -> wrist pose (inverse of the palm offset)
		local _, inverse = WorldToLocal(vector_origin, angle_zero, vector_origin, off)
		local _, handAng = LocalToWorld(vector_origin, inverse, vector_origin, pAng)
		local displacement = LocalToWorld(vec, angle_zero, vector_origin, handAng)
		hg.DragLeftHand_Ex(ent, self, pPos - displacement, handAng)
		if self.STTS_LFing then ApplyLeftFingers(self, ent, hand)
		elseif hg.set_hold then hg.set_hold(ent, "normal") end
		-- v19.6: the relaxed left thumb in its hand (before its IK), the right one mirrors it
		if (self.STTS_LandG or 0) > 0.001 then
			local lb = ent:LookupBone(THUMB_L[1])
			local lm, now = lb and ent:GetBoneMatrix(lb), ent:GetBoneMatrix(hand) -- the hand after the IK
			local inv = lm and now and now:GetInverse()
			self.STTS_LThumb = inv and inv * lm or nil
		end
		-- v19.5: landscape = the fingers stay behind the turned phone, the thumbs tap
		-- (v19.6: the left one on the left half, ThumbTarget / ThumbIK / LeanFor)
		local flat = math.Clamp(2 * math.max(math.abs(self.STTS_LandT or 0), self.STTS_LandL or 0), 0, 1)
		if flat > 0.001 then
			local fw = flat * flat * (3 - 2 * flat) * e
			OpenFingers(ent, hand, 0.45 * fw, "L") -- fix57: flatter on the back, not a fist
			FlatFingers(ent, "L", pPos, pAng, self:Geo(), fw)
		end
		local tw = self:LandThumb()
		local lt = self.STTS_LeanT
		if tw > 0.001 then
			local aL = self.STTS_LandAL or 1
			local tgt = ThumbTarget(self, self:Geo(), "L", aL)
			ThumbIK(ent, THUMB_L, LocalToWorld(tgt, angle_zero, pPos, pAng), tw * e)
			if not lt then lt = {0, 0, 0, 0} self.STTS_LeanT = lt end
			lt[1], lt[2] = 0, 0
			if aL >= 0.999 then
				local ln = self.STTS_Lean
				lt[1], lt[2] = LeanFor(ent, THUMB_L, tgt, pPos, pAng, ln and ln[1] or 0, ln and ln[2] or 0)
			end
		elseif lt then lt[1], lt[2] = 0, 0 end

		self:DoFinger(ply, ent, pPos, pAng, newFrame and dt or 0, e)
	end

	function SWEP:GetModel2()
		-- fix28: the model follows NW2 "PMod" (random per phone, can change when the inventory recreates it)
		if self.STTS_PModApplied ~= self:GetNW2Int("PMod", 1) then self:ApplyPhoneModel() end
		local path = G.ModelPath(self)
		if IsValid(self.model) and self.model:GetModel() ~= path then self.model:Remove() self.model = nil end
		if not IsValid(self.model) then
			self.model = ClientsideModel(path, RENDERGROUP_OPAQUE)
			if IsValid(self.model) then self.model:SetNoDraw(true) end
		end
		return self.model
	end

	--[[ studiomdl adds its default 90 degree turn around Z to the root bone of
	     the "idle" sequence (the compiled .mdl really has it, the reference
	     mesh does not). the model was therefore drawn turned by 90 degrees
	     inside its own plane: landscape in the hand, the UI on its side and
	     the pointer hitting the wrong spot. the root bone is measured once and
	     the draw pose is corrected, so the model matches the Lua geometry
	     (+X = top of the phone) with the current AND with a fixed recompiled
	     model. ]]
	local rootFix = {}
	local function RootFix(mdl)
		local key = mdl:GetModel() or ""
		if rootFix[key] ~= nil then return rootFix[key] end
		mdl:SetPos(vector_origin) mdl:SetAngles(angle_zero)
		mdl:InvalidateBoneCache()
		mdl:SetupBones()
		local m = mdl:GetBoneMatrix(0)
		if not m then return false end -- not ready yet, try again next frame
		local p, a = m:GetTranslation(), m:GetAngles()
		local turned = math.abs(math.AngleDifference(a.p, 0)) + math.abs(math.AngleDifference(a.y, 0)) + math.abs(math.AngleDifference(a.r, 0)) > 0.5
		local fix = false
		if turned or p:LengthSqr() > 0.0001 then
			local ip, ia = WorldToLocal(vector_origin, angle_zero, p, a)
			fix = {ip, ia}
		end
		rootFix[key] = fix
		return fix
	end

	-- rounded-rectangle core from 3 boxes, inside the body (model space)
	-- fix28: per model (STTS.PhoneGeo.Models[i].Core), checked to stay inside each body

	-- draws the body + display. pos/ang = phone model pose
	function SWEP:DrawPhone(pos, ang)
		local scr = STTS.PhoneScreen
		if scr and scr.InRV and scr.RVWep == self then return end -- its own camera is rendering: never in front of its lens
		self.STTS_DrawPos, self.STTS_DrawAng, self.STTS_DrawFrame = pos, ang, FrameNumber()
		-- a spectator watches the world through this phone's lens (camera map): the
		-- pose is still recorded above, the body is not drawn in front of the lens
		if scr and scr.SpecWep == self and not scr.InRV then return end
		-- your own phone: pose relative to your body (sent while the camera streams)
		local owner = self:GetOwner()
		if not (scr and scr.InRV) and IsValid(owner) and owner == LocalPlayer() then
			local o, a = G.RefFrame(owner)
			if o then
				self.STTS_RelP, self.STTS_RelA = WorldToLocal(pos, ang, o, a)
				self.STTS_RelFrame = FrameNumber()
			else
				self.STTS_RelFrame = nil -- ragdoll: fix8 (world pose only)
			end
		end
		if self.STTS_PModApplied ~= self:GetNW2Int("PMod", 1) then self:ApplyPhoneModel() end
		local M = self:Geo()
		if self:HasPhoneModel() then
			local mdl = self:GetModel2()
			if not IsValid(mdl) then return end
			mdl:SetModelScale(1)
			local fix = RootFix(mdl)
			if fix then
				local dpos, dang = LocalToWorld(fix[1], fix[2], pos, ang)
				mdl:SetPos(dpos) mdl:SetAngles(dang)
			else
				mdl:SetPos(pos) mdl:SetAngles(ang)
			end
			if scr then scr.ApplyMaterial(self, mdl) end
			self:ApplyPhoneColor(mdl) -- fix29: own body colour
			-- the mesh has small holes (front camera glass and the display border were
			-- cut during the decimation): a black core inside the body closes them
			render.SetColorMaterial()
			for _, b in ipairs(M.Core) do render.DrawBox(pos, ang, b[1], b[2], color_black) end
			mdl:InvalidateBoneCache()
			mdl:SetupBones()
			mdl:DrawModel()
		else
			-- the model is not compiled yet: a slab with the same size + the display quad
			render.SetColorMaterial()
			render.DrawBox(pos, ang, M.Mins, M.Maxs, self:PhoneSlabColor())
			if scr then scr.DrawQuad(self, pos, ang) end
		end
	end

	--[[ fix15: the pose the phone model gets in the hand right now (same math as
	     DrawWorldModel2), for cameras when the phone was not drawn in this frame
	     (ragdoll far away / behind you): the camera stays ON the model ]]
	function SWEP:HandPose(fresh)
		local owner = hg.GetCurrentCharacter(self:GetOwner())
		if not IsValid(owner) then return self:GetPos(), self:GetAngles() end
		local tp, ta = self:TossFree()
		if tp then return tp, ta end
		if fresh and owner.SetupBones then owner:SetupBones() end
		local boneid = owner:LookupBone("ValveBiped.Bip01_L_Hand")
		local matrix = boneid and owner:GetBoneMatrix(boneid)
		if not matrix then return end
		local vec, ang0 = self:HandOffset()
		return LocalToWorld(vec, ang0, matrix:GetTranslation(), matrix:GetAngles())
	end

	--[[ fix23: the pose of the phone model RIGHT NOW, built exactly like the draw
	     builds it (DrawPlayerRagdoll: body bones -> SetHandPos = hand IK of the phone
	     -> left hand bone + palm offset = DrawWorldModel2), for a camera whose phone
	     was not drawn in this frame (ragdoll behind a wall / behind you). once per
	     frame. the camera stays glued to the model, there is nothing to catch up. ]]
	function SWEP:PoseNow()
		local f = FrameNumber()
		if self.STTS_NowF == f then return self.STTS_NowP, self.STTS_NowA end
		self.STTS_NowF, self.STTS_NowP, self.STTS_NowA = f, nil, nil
		local ply = self:GetOwner()
		if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) or ply:GetActiveWeapon() ~= self then return end
		local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply)
		if not IsValid(ch) or ch:IsDormant() then return end
		-- drawn meanwhile (another camera rendered the body this frame): that pose
		if self.STTS_DrawFrame == f then
			self.STTS_NowP, self.STTS_NowA = self.STTS_DrawPos, self.STTS_DrawAng
			return self.STTS_NowP, self.STTS_NowA
		end
		ch:InvalidateBoneCache()
		ch:SetupBones()
		if self.SetHandPos then self:SetHandPos() end
		local tp, ta = self:TossFree() -- tossed: in the air
		if tp then
			self.STTS_NowP, self.STTS_NowA = tp, ta
			return tp, ta
		end
		local boneid = ch:LookupBone("ValveBiped.Bip01_L_Hand")
		local matrix = boneid and ch:GetBoneMatrix(boneid)
		if not matrix then return end
		local vec, ang0 = self:HandOffset()
		self.STTS_NowP, self.STTS_NowA = LocalToWorld(vec, ang0, matrix:GetTranslation(), matrix:GetAngles())
		return self.STTS_NowP, self.STTS_NowA
	end

	function SWEP:DrawWorldModel2()
		local owner = hg.GetCurrentCharacter(self:GetOwner())
		if not IsValid(owner) then self:DrawPhone(self:GetPos(), self:GetAngles()) return end
		local tp, ta = self:TossFree() -- tossed (Q menu): in the air, not in the hand
		if tp then self:DrawPhone(tp, ta) return end
		local boneid = owner:LookupBone("ValveBiped.Bip01_L_Hand")
		local matrix = boneid and owner:GetBoneMatrix(boneid)
		if not matrix then return end
		local vec, ang0 = self:HandOffset()
		local pos, ang = LocalToWorld(vec, ang0, matrix:GetTranslation(), matrix:GetAngles())
		self:DrawPhone(pos, ang)
	end

	-- lying in the world (dropped, fallen out of a dead hand)
	function SWEP:DrawWorldModel()
		local owner = self:GetOwner()
		if IsValid(owner) and owner:IsPlayer() then return end
		if self:HasPhoneModel() then
			self:DrawPhone(self:GetPos(), self:GetAngles())
		else
			local scr = STTS.PhoneScreen
			if scr and scr.InRV and scr.RVWep == self then return end
			self:SetModelScale(0.5)
			self:DrawModel()
			self.STTS_DrawPos, self.STTS_DrawAng, self.STTS_DrawFrame = self:GetPos(), self:GetAngles(), FrameNumber()
			if STTS.PhoneScreen then STTS.PhoneScreen.DrawQuad(self, self:GetPos(), self:GetAngles()) end
		end
	end

	-- for the keepy-uppy (sh_phone_kick.lua): the same hand / finger helpers
	SWEP.STTS_OpenFingers = OpenFingers
	SWEP.STTS_ApplyLeftFingers = ApplyLeftFingers
	SWEP.STTS_CaptureLeftFingers = CaptureLeftFingers
	SWEP.STTS_Face = Face
	SWEP.STTS_Motion = Motion -- fix74: the phone in the left hand next to a weapon (below)
end

function SWEP:OnRemove()
	if CLIENT and IsValid(self.model) then self.model:Remove() end
end

-- idle pose: same as the walkie-talkie (left hand up a little)
function SWEP:BoneSet(lookup_name, vec, ang)
	local owner = self:GetOwner()
	if IsValid(owner) and not owner:IsPlayer() then return end
	hg.bone.Set(owner, lookup_name, vec, ang, "walkietalkie", 0.01)
end

local handAng1, handAng2 = Angle(-15, -10, 10), Angle(5, -65, -60)
function SWEP:Step()
	local owner = self:GetOwner()
	if not IsValid(owner) then return end
	local posed = self:Posed()
	-- Q menu toss (client): the end of the toss, and the arm stays neutral while the IK does it
	local tossing = false
	if CLIENT and self.STTS_Toss then
		self:TossTick()
		tossing = self:TossArm()
	end
	-- keepy-uppy: the IK holds the left hand (drop / catch), the arm bones stay neutral
	if not tossing and self.KickArm and self:KickArm() then tossing = true end
	if posed then
		if self:GetHoldType() ~= self.HoldType then self:SetHold(self.HoldType) end
	elseif self:GetHoldType() ~= self.IdleHoldType then
		self:SetHold(self.IdleHoldType)
	end
	-- while the IK holds the phone the arm bones stay neutral (no double rotation)
	local a1, a2 = handAng1, handAng2
	if posed or tossing then a1, a2 = angle_zero, angle_zero end
	if posed or tossing or (owner:OnGround() and owner:GetVelocity():LengthSqr() <= 1000 and not owner:IsTyping() and not owner:IsFlagSet(FL_ANIMDUCKING)) then
		self:BoneSet("l_upperarm", vector_origin, a1)
		self:BoneSet("l_forearm", vector_origin, a2)
		self:BoneSet("r_upperarm", vector_origin, angle_zero)
		self:BoneSet("r_forearm", vector_origin, angle_zero)
	end
end

local function Busy(ply)
	local P = STTS and STTS.Phone
	return P and P.InCall and P.InCall(ply) or false
end

function SWEP:Deploy()
	self.STTS_Toss = nil
	if SERVER then
		self:SetInCall(Busy(self:GetOwner()))
		self:SetRaised(false)
		self:SetNW2Bool("Down", false)
		self:SetNW2Bool("Land", false) -- v19.4: taken out = portrait again
		self:SetNW2Bool("CarAct", false) -- fix58
		if STTS.PhoneAutoLock then STTS.PhoneAutoLock.Wake(self) end -- fix61: in the hand = the display is on
	end
	return true
end

function SWEP:Holster()
	self.STTS_Toss = nil
	if SERVER then
		self:SetRaised(false)
		self:SetNW2Bool("CarAct", false)
		-- fix58: put away / another item taken = the phone locks (iPhone). a running video
		-- recording goes on (fix16). not while Z-City respawns you out of a ragdoll.
		-- fix61: not at once: after half of the Auto-Lock time (sv_phone_lock.lua)
		if not OverrideSpawn then
			if STTS.PhoneAutoLock then STTS.PhoneAutoLock.Start(self, 0.5) else self:SetNW2Bool("Unlk", false) end
		end
	elseif self:GetOwner() == LocalPlayer() and STTS.PhoneScreen then
		STTS.PhoneScreen.SetRaised(self, false, true)
		if STTS.PhoneLock and STTS.PhoneLock.Holster then STTS.PhoneLock.Holster(self) end
	end
	return true
end

function SWEP:Equip(owner)
	-- fix61: picked up = it stays as it is (the Auto-Lock countdown of the floor goes on)
	if STTS and STTS.Phone and STTS.Phone.Register then STTS.Phone.Register(self, owner) end
end

-- number, contact name, photos and screen survive when the inventory recreates the weapon
function SWEP:GetInfo()
	return {num = self:GetNWString("STTS_Num", ""), name = self:GetNWString("STTS_PName", ""), avatar = self:GetNWString("STTS_Avatar", ""),
		photos = table.Copy(self.STTS_Photos or {}), recv = table.Copy(self.STTS_Recv or {}), app = self:GetNW2Int("App", G.APP_HOME),
		-- fix15: a running video recording survives the inventory recreating the phone
		camMode = self:GetNW2Int("CamMode", 0), recBy = self:GetNW2Entity("RecBy", NULL), recAt = self:GetNW2Float("RecAt", 0),
		camFront = self:GetNW2Bool("CamFront", false), eis = self:GetNW2Int("EIS",2),
		-- fix17: shade toggles + camera flash belong to the phone
		torch = self:GetNW2Bool("Torch", false), plane = self:GetNW2Bool("Plane", false), camFlash = self:GetNW2Bool("CamFl", false),
		vol = self:GetNW2Int("Vol", 100), bright = self:GetNW2Int("Bright", 100), -- fix20: shade sliders
		cc = {NoWifi = self:GetNW2Bool("NoWifi", false), NoJoin = self:GetNW2Bool("NoJoin", false),
			RotLock = self:GetNW2Bool("RotLock", false), Focus = self:GetNW2Bool("Focus", false)}, -- Control Centre tiles (v19.2: + Wi-Fi network)
		pmod = self:GetNW2Int("PMod", 1), -- fix28: the phone model stays the same phone
		pcol = self:GetNW2Int("PCol", G.COL_STOCK), -- fix29: and keeps its colour
		unlk = self:GetNW2Bool("Unlk", false), -- fix58: lock screen
		lkat = self:GetNW2Float("LkAt", 0), off = self:GetNW2Bool("Off", false), -- fix61: Auto-Lock
		-- Settings: theme / ringtone + whose profile this phone saves to
		theme = self:GetNW2Int("Theme", 0), ring = self:GetNW2String("Ring", ""), okey = self.STTS_OwnerKey,
		set = SERVER and STTS.PhoneSettings and STTS.PhoneSettings.Read and STTS.PhoneSettings.Read(self) or nil,
		zmq = SERVER and STTS.ZMusic and STTS.ZMusic.Save and STTS.ZMusic.Save(self) or nil} -- fix54: the music goes on
end

function SWEP:SetInfo(tbl)
	if not istable(tbl) then return end
	if tbl.num and tbl.num ~= "" then self:SetNWString("STTS_Num", tbl.num) end
	if tbl.name and tbl.name ~= "" then self:SetNWString("STTS_PName", tbl.name) self.STTS_NameLocked = true end
	if tbl.avatar then self:SetNWString("STTS_Avatar", tbl.avatar) end
	if SERVER then
		if tbl.pmod and G.Models[tonumber(tbl.pmod) or 0] then self:SetPhoneModel(tbl.pmod) end -- fix28
		if tbl.pcol and (tonumber(tbl.pcol) or 0) > 0 then self:SetPhoneColor(tbl.pcol) end -- fix29
		if istable(tbl.recv) then self.STTS_Recv = tbl.recv end
		if istable(tbl.photos) and STTS.PhoneMedia then STTS.PhoneMedia.SetGallery(self, tbl.photos) end
		if tbl.app then self:SetNW2Int("App", tbl.app) end
		if tbl.eis ~= nil then self:SetNW2Int("EIS",math.Clamp(math.floor(tonumber(tbl.eis)or 2),0,2))end
		if tbl.camFront ~= nil then self:SetNW2Bool("CamFront", tbl.camFront == true) end
		if tbl.torch ~= nil then self:SetNW2Bool("Torch", tbl.torch == true) end
		if tbl.plane ~= nil then self:SetNW2Bool("Plane", tbl.plane == true) end
		if istable(tbl.cc) then
			for _, k in ipairs({"NoWifi", "NoJoin", "RotLock", "Focus"}) do if tbl.cc[k] ~= nil then self:SetNW2Bool(k, tbl.cc[k] == true) end end
		end
		if tbl.camFlash ~= nil then self:SetNW2Bool("CamFl", tbl.camFlash == true) end
		if tbl.unlk ~= nil then self:SetNW2Bool("Unlk", tbl.unlk == true) end -- fix58
		if STTS.PhoneAutoLock and (tbl.lkat or tbl.off) then STTS.PhoneAutoLock.Restore(self, tbl.lkat, tbl.off == true) end -- fix61
		if tbl.vol then self:SetNW2Int("Vol", math.Clamp(math.floor(tonumber(tbl.vol) or 100), 0, 100)) end -- fix20
		if tbl.bright then self:SetNW2Int("Bright", math.Clamp(math.floor(tonumber(tbl.bright) or 100), 0, 100)) end
		if tbl.theme ~= nil then -- Settings: the phone keeps its own settings (and its owner)
			self:SetNW2Int("Theme", math.Clamp(math.floor(tonumber(tbl.theme) or 0), 0, 1))
			if G.RingById and G.RingById[tbl.ring or ""] then self:SetNW2String("Ring", tbl.ring) end
			self.STTS_OwnerKey, self.STTS_SetBound = tbl.okey, true
			if tbl.set and STTS.PhoneSettings and STTS.PhoneSettings.Write then STTS.PhoneSettings.Write(self, tbl.set) end
		end
		-- fix54: not a recording whose 2 minutes are over (it came back on every recreation)
		if tbl.camMode == 2 and IsValid(tbl.recBy) and tbl.recBy:IsPlayer() and CurTime() - (tbl.recAt or 0) < (G.VidMaxSec or 120) + 5 then
			self:SetNW2Int("CamMode", 2)
			self:SetNW2Entity("RecBy", tbl.recBy)
			self:SetNW2Float("RecAt", tbl.recAt or CurTime())
			tbl.recBy.STTS_RecWep = self
		elseif tbl.camMode then
			self:SetNW2Int("CamMode", tbl.camMode == 2 and 1 or tbl.camMode)
		end
		if STTS and STTS.Phone and STTS.Phone.Register then STTS.Phone.Register(self) end
		if tbl.zmq and STTS.ZMusic and STTS.ZMusic.Restore then STTS.ZMusic.Restore(self, tbl.zmq) end -- fix54
	end
end

function SWEP:Think()
	if SERVER then
		local owner = self:GetOwner()
		local inCall = Busy(owner)
		if self:GetInCall() ~= inCall then self:SetInCall(inCall) end
		if self:GetRaised() and (not IsValid(owner) or owner:GetActiveWeapon() ~= self) then self:SetRaised(false) end
		if not self:GetRaised() and self:GetNW2Bool("Look", false) then self:SetNW2Bool("Look", false) end
		-- fix58: the hand is only "in action" (off the wheel) while the phone is raised in a vehicle
		if self:GetNW2Bool("CarAct", false) and not (self:GetRaised() and IsValid(owner) and owner:InVehicle()) then
			if STTS.PhoneCar and STTS.PhoneCar.SetAct then STTS.PhoneCar.SetAct(self, false) else self:SetNW2Bool("CarAct", false) end
		end
		if self.FakeHold then self:FakeHold() end -- fix24
	end
end

-- client side input (singleplayer does not predict, the server forwards it)
function SWEP:ClientPrimary()
	if self.STTS_Toss then return end -- the phone is in the air (Q menu toss)
	if STTS.PhoneScreen then STTS.PhoneScreen.Primary(self) end
end
function SWEP:ClientReload() if STTS.PhoneScreen then STTS.PhoneScreen.Reload(self) end end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.15)
	if SERVER then
		if game.SinglePlayer() then self:CallOnClient("ClientPrimary") end
		return
	end
	if not IsFirstTimePredicted() then return end
	self:ClientPrimary()
end

function SWEP:SecondaryAttack() end -- RMB: the finger on / off (stts_phone_controls), handled by the screen module

function SWEP:Reload()
	if (self.STTS_NextReload or 0) > CurTime() then return end
	self.STTS_NextReload = CurTime() + 0.3
	if SERVER then
		if game.SinglePlayer() then self:CallOnClient("ClientReload") end
		return
	end
	if not IsFirstTimePredicted() then return end
	self:ClientReload()
end

if CLIENT then
	function SWEP:DrawHUD() end

	-- Q menu toss of someone else's phone: the server relays the start (+ seed = the same flip)
	net.Receive("stts_phone_toss", function()
		local wep = net.ReadEntity()
		local kind, seed = net.ReadUInt(2), net.ReadUInt(16)
		if IsValid(wep) and wep.StartToss and wep:GetOwner() ~= LocalPlayer() then wep:StartToss(kind, seed) end
	end)

	-- Z-City Q radial menu: the "Phone" tab (Toss phone + Litvin) is in stts_phone/sh_phone_kick.lua

	concommand.Add("stts_phone_toss", function(ply, _, args)
		local wep = IsValid(ply) and ply:GetActiveWeapon()
		if IsValid(wep) and wep:GetClass() == "weapon_stts_phone" and wep.RequestToss then wep:RequestToss(tonumber(args[1]) == 2 and 2 or 1) end
	end, nil, "toss the phone in the left hand: 1 = flip, 2 = double flip (the same as the Q menu)")

	-- palm offset tuner: sliders move the phone live (third person helps)
	concommand.Add("stts_phone_tune", function()
		if IsValid(STTS_PhoneTuner) then STTS_PhoneTuner:Remove() end
		local t = weapons.GetStored("weapon_stts_phone")
		local v, a = ParseOffset(posCvar:GetString())
		v, a = v or t.offsetVec, a or t.offsetAng
		STTS_PhoneTuning = true
		local fr = vgui.Create("DFrame")
		STTS_PhoneTuner = fr
		fr:SetTitle("phone in the palm")
		fr:SetSize(360, 330)
		fr:SetPos(20, ScrH() * 0.5 - 165)
		fr:MakePopup()
		fr:SetKeyboardInputEnabled(false)
		function fr:OnRemove() STTS_PhoneTuning = nil end
		local vals = {v.x, v.y, v.z, a.p, a.y, a.r}
		local function Apply()
			local vec, ang = Vector(vals[1], vals[2], vals[3]), Angle(vals[4], vals[5], vals[6])
			for _, w in ipairs(ents.FindByClass("weapon_stts_phone")) do w.offsetVec, w.offsetAng = vec, ang end
			t.offsetVec, t.offsetAng = vec, ang
		end
		for i, name in ipairs({"forward (x)", "side (y)", "up (z)", "pitch", "yaw", "roll"}) do
			local sl = vgui.Create("DNumSlider", fr)
			sl:Dock(TOP) sl:SetText(name)
			sl:SetMinMax(i <= 3 and -10 or -180, i <= 3 and 10 or 180)
			sl:SetDecimals(i <= 3 and 1 or 0)
			sl:SetValue(vals[i])
			sl.OnValueChanged = function(_, val) vals[i] = val Apply() end
		end
		local out = vgui.Create("DButton", fr)
		out:Dock(BOTTOM) out:SetTall(30) out:SetText("print command to console")
		out.DoClick = function()
			local str = string.format("%.1f %.1f %.1f %d %d %d", vals[1], vals[2], vals[3], vals[4], vals[5], vals[6])
			print('stts_phone_pos "' .. str .. '"')
			SetClipboardText('stts_phone_pos "' .. str .. '"')
			print("copied to clipboard - paste it into the server console")
		end
		Apply()
	end)

	-- v19.5: landscape grip tuner (raise the phone, T, third person helps): both hands live
	concommand.Add("stts_phone_tune_land", function()
		if IsValid(STTS_PhoneLandTuner) then STTS_PhoneLandTuner:Remove() end
		local l = Nums(landHandCvar:GetString(), 4) or {-0.5, 1, 0, 0}
		local r = Nums(landRHandCvar:GetString(), 4) or {0, 0, 0, 0}
		local tune = {l = {l[1], l[2], l[3], l[4]}, r = {r[1], r[2], r[3], r[4]}}
		STTS_PhoneLandTune = tune
		local fr = vgui.Create("DFrame")
		STTS_PhoneLandTuner = fr
		fr:SetTitle("landscape grip (T): as you see the phone")
		fr:SetSize(400, 400)
		fr:SetPos(20, ScrH() * 0.5 - 200)
		fr:MakePopup()
		fr:SetKeyboardInputEnabled(false)
		function fr:OnRemove() if STTS_PhoneLandTune == tune then STTS_PhoneLandTune = nil end end
		for _, side in ipairs({"l", "r"}) do
			for i, name in ipairs({"right", "up", "toward the eyes", "roll (+ = clockwise)"}) do
				local sl = vgui.Create("DNumSlider", fr)
				sl:Dock(TOP) sl:SetText((side == "l" and "left hand: " or "right hand: ") .. name)
				sl:SetMinMax(i <= 3 and -6 or -90, i <= 3 and 6 or 90)
				sl:SetDecimals(i <= 3 and 2 or 0)
				sl:SetValue(tune[side][i])
				sl.OnValueChanged = function(_, val) tune[side][i] = val end
			end
		end
		local out = vgui.Create("DButton", fr)
		out:Dock(BOTTOM) out:SetTall(30) out:SetText("print commands to console")
		out.DoClick = function()
			local function S(t) return string.format("%.2f %.2f %.2f %d", t[1], t[2], t[3], math.Round(t[4])) end
			local str = 'stts_phone_land_hand "' .. S(tune.l) .. '"; stts_phone_land_rhand "' .. S(tune.r) .. '"'
			print(str)
			SetClipboardText(str)
			print("copied to clipboard - paste it into the server console")
		end
	end)
end

if SERVER then
	--[[ Q menu toss: the owner starts it on his screen right away and sends it here.
	     checked (CanToss + cooldown) and relayed to the players around, with the seed
	     of the owner (everyone sees the same twist of the phone) ]]
	util.AddNetworkString("stts_phone_toss")
	net.Receive("stts_phone_toss", function(_, ply)
		local kind, seed = net.ReadUInt(2), net.ReadUInt(16)
		local wep = IsValid(ply) and ply:GetActiveWeapon()
		if not (IsValid(wep) and wep:GetClass() == "weapon_stts_phone" and wep.CanToss) then return end
		if (kind ~= 1 and kind ~= 2) or not wep:CanToss(ply) then return end
		wep.STTS_TossEnd = CurTime() + (kind == 2 and 1.6 or 1.5) -- a bit shorter than the client one
		local rf = RecipientFilter()
		rf:AddPVS(ply:GetPos())
		rf:RemovePlayer(ply)
		if rf:GetCount() == 0 then return end
		net.Start("stts_phone_toss")
		net.WriteEntity(wep)
		net.WriteUInt(kind, 2)
		net.WriteUInt(seed, 16)
		net.Send(rf)
	end)

	-- ragdoll (fake) / cars: exactly the fix8 behaviour (RagdollFunc + CreateFake)
	function SWEP:SetFakeGun(ent)
		self:SetNWEntity("fakeGun", ent)
		self.fakeGun = ent
	end

	function SWEP:RemoveFake()
		if not IsValid(self.fakeGun) then return end
		self.fakeGun:Remove()
		self:SetFakeGun()
	end

	SWEP.RHandPos = Vector(0, 0, 0)

	function SWEP:CreateFake(ragdoll)
		if IsValid(self:GetNWEntity("fakeGun")) then return end
		local ent = ents.Create("prop_physics")
		local lh = ragdoll:GetPhysicsObjectNum(5)
		local rh = ragdoll:GetPhysicsObjectNum(7)
		rh:SetPos(rh:GetPos() + self:GetOwner():EyeAngles():Forward() * 20)
		rh:SetAngles(self:GetOwner():EyeAngles() + Angle(0, 0, -90))
		lh:SetPos(rh:GetPos())
		ent:SetModel((G.ModelPath(self))) -- fix28: model of this phone
		ent:SetModelScale(self:HasPhoneModel() and 1 or 0.5)
		ent:SetPos(rh:GetPos())
		ent:SetAngles(rh:GetAngles() + Angle(0, 0, 180))
		ent:Spawn()
		ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		ent:SetOwner(ragdoll)
		if IsValid(ent:GetPhysicsObject()) then ent:GetPhysicsObject():SetMass(0) end
		ent:SetNoDraw(true)
		ent.dontPickup = true
		ent.fakeOwner = self
		ragdoll:DeleteOnRemove(ent)
		ragdoll.fakeGun = ent
		if IsValid(ragdoll.ConsRH) then ragdoll.ConsRH:Remove() end
		self:SetFakeGun(ent)
		ent:CallOnRemove("homigrad-swep", self.RemoveFake, self)
	end

	function SWEP:RagdollFunc(pos, angles, ragdoll)
		if self:FakeRagdoll() and self:PoseMode() then return end -- fix24: FakeHold already holds it
		shadowControl = shadowControl or hg.ShadowControl
		shadowControl(ragdoll, 5, 0.001, angles, 500, 30, pos, 500, 50)
	end

	--[[ fix24: the real left hand of the ragdoll holds the phone in front of the eyes
	     while it is posed. same strength as the RMB hand (RagdollFunc). nothing
	     when the arm can't move (unconscious, no control, broken / grabbing hand) ]]
	function SWEP:FakeHold()
		local rag = self:FakeRagdoll()
		if not rag or not self:PoseMode() then return end
		local ply = self:GetOwner()
		if not ply:Alive() or ply:GetActiveWeapon() ~= self then return end
		if ply:InVehicle() then return end -- fix58: in a seat the client IK holds it (sh_phone_car.lua)
		local org = ply.organism
		if org and (org.otrub or org.canmove == false) then return end
		if hg and hg.CanUseLeftHand and not hg.CanUseLeftHand(ply) then return end
		if IsValid(rag.ConsLH) then return end
		local ctl = shadowControl or (hg and hg.ShadowControl)
		if not ctl then return end
		local att = rag:LookupAttachment("eyes")
		local a = att and att > 0 and rag:GetAttachment(att)
		local o = a and a.Pos or ply:EyePos()
		local tPos, tAng = Hold(o, ply:EyeAngles(), ParseVec(fakePosCvar, Vector(14, -0.8, -4.5)))
		-- phone pose -> hand pose (inverse of the palm offset)
		local vec, off = self:HandOffset()
		local ip, ia = WorldToLocal(vector_origin, angle_zero, vec, off)
		local hPos, hAng = LocalToWorld(ip, ia, tPos, tAng)
		ctl(rag, 5, 0.001, hAng, 500, 30, hPos, 500, 50)
	end
end

--[[---------------------------------------------------------------------------
	fix74: the phone in the LEFT hand + a pistol / a one-handed melee weapon in the
	RIGHT one. Q menu -> Phone -> RightHand -> the weapon.
	  * the weapon becomes the active weapon (LMB = shoot / hit, the mouse turns the
	    camera, R = reload ...). the phone stays in the left hand: it is not the
	    active weapon, it is drawn on the left hand bone (hook CoolPostDrawAppearance
	    of Z-City, after the hand IK) and the left hand is put by this file before
	    Z-City's own arm IK (hg.DoTPIK is wrapped, Z-City is not edited).
	    in a call the phone is at the ear, otherwise it is held out a little to the
	    left like for filming: the rear camera looks forward, where you look, only a
	    tiny bit to the right (stts_phone_rh_pos). the display keeps working
	    (calls, music, a recording, the lock screen ...), the touch screen does not:
	    LMB belongs to the weapon now.
	  * which weapons: the Z-City pistols (ishgweapon + pistol / revolver hold type)
	    and the one-handed melee weapons (knives, hatchet, pipe ... not the two-handed
	    ones). SWEP.STTS_RightHand = true / false on a weapon overrides it,
	    stts_phone_rh_extra / stts_phone_rh_block = extra classes / never these.
	  * the end: take any weapon the normal way (1, 2, 3 ... / the wheel / the
	    inventory) = the phone goes into the pocket. Q -> Phone -> RightHand ->
	    "Phone only" = the weapon goes away, the phone is in the hands as before.
	    Q -> Phone -> Anims in this mode = the phone back into the hand + the anim.
	  * it ends on its own: death, a vehicle, handcuffs, a lost arm, the phone / the
	    weapon gone (dropped, taken away), another weapon taken by anything else.
	  * the server keeps the state: NW2 entities "STTS_RHPhone" / "STTS_RHWep" on the
	    player, everybody sees the same.
	  * hg.CanUseLeftHand says "busy" in this mode (the pistol is held one-handed,
	    like with Z-City's flashlight in that hand), only for the arm IK of this file
	    it says "free" (autorun/sh_stts_phone_zcity.lua). a reload / a door (zmanip)
	    still takes the left hand for a moment, the phone stays in it.
---------------------------------------------------------------------------]]
local RH = STTS.PhoneRH or {}
STTS.PhoneRH = RH
local RH_CLASS = "weapon_stts_phone"
RH.On = RH.On or {} -- server: players in this mode

local rhCvar = CreateConVar("stts_phone_rh", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix74: 1 = Q -> Phone -> RightHand: a pistol / knife in the right hand, the phone stays in the left one", 0, 1)
local rhPosCvar = CreateConVar("stts_phone_rh_pos", "10 -3.5 -6.5", {FCVAR_REPLICATED}, "fix74: the phone in the left hand next to a weapon in the right one: forward right up from the eyes")
local rhExtraCvar = CreateConVar("stts_phone_rh_extra", "", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix74: extra weapon classes for Q -> Phone -> RightHand (separated by spaces / commas)")
local rhBlockCvar = CreateConVar("stts_phone_rh_block", "", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "fix74: weapon classes never allowed in Q -> Phone -> RightHand (separated by spaces / commas)")
local RH_POS = Vector(10, -3.5, -6.5)
local RH_NEVER = {[RH_CLASS] = true, weapon_hands_sh = true, weapon_hg_coolhands = true, weapon_ballistic_shield = true, weapon_shield = true}
RH.Enabled = function() return rhCvar:GetBool() end

-- (the same helper as in sh_phone_car.lua / sh_phone_kick.lua: a wrapper anywhere in a chain)
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

local listCache = {}
local function Listed(cv, cls)
	local s = cv:GetString()
	if s == "" then return false end
	local set = listCache[s]
	if not set then
		set = {}
		for c in string.gmatch(string.lower(s), "[%w_%-%.]+") do set[c] = true end
		listCache[s] = set
	end
	return set[string.lower(cls)] == true
end

-- may this weapon be in the right hand while the left one holds the phone
function RH.Allowed(wep)
	if not (IsValid(wep) and wep:IsWeapon()) then return false end
	local cls = wep:GetClass()
	if cls == RH_CLASS then return false end
	if wep.STTS_RightHand ~= nil then return wep.STTS_RightHand == true end
	if Listed(rhBlockCvar, cls) then return false end
	if Listed(rhExtraCvar, cls) then return true end
	if RH_NEVER[cls] then return false end
	if wep.ismelee then return not wep.TwoHanded end -- knives, hatchet, pipe ... (bats / axes / spears: TwoHanded)
	if wep.ishgweapon and isfunction(wep.IsPistolHoldType) then -- pistols / revolvers
		local ok, r = pcall(wep.IsPistolHoldType, wep)
		return (ok and r) and true or false
	end
	return false
end

-- the state as the server set it (phone, weapon), no checks
function RH.State(ply)
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	local ph = ply:GetNW2Entity("STTS_RHPhone", NULL)
	if not IsValid(ph) then return end
	return ph, ply:GetNW2Entity("STTS_RHWep", NULL)
end

-- the phone in the left hand right now + the weapon in the right one (nil = not in this mode)
function RH.Phone(ply)
	local ph, w = RH.State(ply)
	if not ph or ph:GetOwner() ~= ply or not ply:Alive() then return end
	local act = ply:GetActiveWeapon()
	if not IsValid(act) or act == ph then return end
	if act == w then return ph, w end
	if SERVER and (ply.STTS_RHSw or 0) > CurTime() then return ph, act end -- the switch is on the way
end

if SERVER then
	util.AddNetworkString("stts_phone_rh")

	-- why the mode can not go on (nil = it can)
	local function Blocked(ply)
		if not (IsValid(ply) and ply:Alive()) then return "dead" end
		if ply:InVehicle() then return "vehicle" end
		if ply.GetNetVar and ply:GetNetVar("handcuffed", false) then return "cuffs" end
		local org = ply.organism
		if org and (org.larmamputated or org.rarmamputated) then return "arm" end
	end
	RH.Blocked = Blocked

	function RH.Stop(ply, why)
		RH.On[ply] = nil
		if not IsValid(ply) then return end
		local ph = ply:GetNW2Entity("STTS_RHPhone", NULL)
		if not IsValid(ph) and not IsValid(ply:GetNW2Entity("STTS_RHWep", NULL)) then return end
		ply:SetNW2Entity("STTS_RHPhone", NULL)
		ply:SetNW2Entity("STTS_RHWep", NULL)
		ply.STTS_RHSw, ply.STTS_RHNone = nil, nil
		-- out of the hand into the pocket: Auto-Lock like a phone that was put away
		if why ~= "back" and IsValid(ph) and ph:GetOwner() == ply and ply:Alive() and ply:GetActiveWeapon() ~= ph then
			local AL = STTS.PhoneAutoLock
			if AL and AL.Start then AL.Start(ph, 0.5) end
		end
	end

	-- take wep into the right hand (the phone in the hand now or already in the left one)
	function RH.Start(ply, wep)
		if not rhCvar:GetBool() or Blocked(ply) then return false end
		local org = ply.organism
		if org and org.otrub then return false end
		if not (IsValid(wep) and wep:GetOwner() == ply and RH.Allowed(wep)) then return false end
		local act = ply:GetActiveWeapon()
		local phone
		if IsValid(act) and act:GetClass() == RH_CLASS then
			phone = act
		else
			local ph = RH.State(ply)
			if RH.On[ply] and IsValid(ph) and ph:GetOwner() == ply then phone = ph end
		end
		if not phone or phone == wep then return false end
		if phone:GetNW2Bool("Kick", false) or (phone.STTS_TossEnd or 0) > CurTime() then return false end -- Litvin / a toss
		ply:SetNW2Entity("STTS_RHPhone", phone)
		ply:SetNW2Entity("STTS_RHWep", wep)
		ply.STTS_RHSw, ply.STTS_RHNone = CurTime() + 1.5, nil
		RH.On[ply] = true
		-- Z-City's flashlight is a left hand thing too
		if ply.GetNetVar and ply.SetNetVar and ply:GetNetVar("flashlight", false) then ply:SetNetVar("flashlight", false) end
		if act ~= wep then ply:SelectWeapon(wep:GetClass()) end
		phone:SetRaised(false)
		phone:SetNW2Bool("Look", false)
		phone:SetNW2Bool("Land", false)
		phone:SetNW2Bool("CarAct", false)
		phone:SetInCall(Busy(ply))
		-- in the hand but nobody touches it: the normal Auto-Lock time (Holster started the pocket half)
		local AL = STTS.PhoneAutoLock
		if AL and AL.Wake and AL.Start then AL.Wake(phone) AL.Start(phone, 1) end
		return true
	end

	-- the weapon goes away, the phone is the item in the hands again
	function RH.Back(ply)
		local ph = RH.State(ply)
		RH.Stop(ply, "back")
		if IsValid(ph) and ph:GetOwner() == ply and ply:Alive() and ply:GetActiveWeapon() ~= ph then ply:SelectWeapon(RH_CLASS) end
	end

	-- 1 = take this weapon, 0 = the end (a weapon picked the normal way), 2 = back to the phone
	net.Receive("stts_phone_rh", function(_, ply)
		local op = net.ReadUInt(2)
		local wep = net.ReadEntity()
		if not IsValid(ply) then return end
		if op == 0 then
			if RH.On[ply] then RH.Stop(ply, "select") end
			return
		end
		local now = CurTime()
		if (ply.STTS_RHNet or 0) > now then return end
		ply.STTS_RHNet = now + 0.1
		if op == 1 then
			if not RH.Start(ply, wep) then
				net.Start("stts_phone_rh")
				net.WriteUInt(3, 2) -- denied
				net.WriteEntity(NULL)
				net.Send(ply)
			end
		elseif op == 2 then
			RH.Back(ply)
		end
	end)

	local function Check(ply, now)
		local why = Blocked(ply)
		if why then return why end
		local ph, w = RH.State(ply)
		if not (ph and ph:GetOwner() == ply) then return "phone" end
		if not (IsValid(w) and w:GetOwner() == ply) then return "weapon" end
		local act = ply:GetActiveWeapon()
		if act == w then
			ply.STTS_RHSw, ply.STTS_RHNone = nil, nil
			return
		end
		if (ply.STTS_RHSw or 0) > now then return end
		if IsValid(act) then return "switch" end
		-- a moment without any weapon (getting up from a ragdoll re-selects it): wait a little
		ply.STTS_RHNone = ply.STTS_RHNone or now
		if now - ply.STTS_RHNone > 1 then return "switch" end
	end

	hook.Add("Think", "STTS_PhoneRH", function()
		if next(RH.On) == nil then return end
		local now = CurTime()
		for ply in pairs(RH.On) do
			if not IsValid(ply) then
				RH.On[ply] = nil
			else
				local why = Check(ply, now)
				if why then
					RH.Stop(ply, why)
				else
					-- the phone is not the active weapon: its own Think does not run
					local ph = ply:GetNW2Entity("STTS_RHPhone", NULL)
					local inCall = Busy(ply)
					if ph:GetInCall() ~= inCall then ph:SetInCall(inCall) end
					if ph:GetRaised() then ph:SetRaised(false) end
				end
			end
		end
	end)

	hook.Add("PlayerDeath", "STTS_PhoneRH", function(ply) RH.Stop(ply, "dead") end)
	hook.Add("PlayerSilentDeath", "STTS_PhoneRH", function(ply) RH.Stop(ply, "dead") end)
	-- (not when Z-City respawns you out of a ragdoll: the weapons stay, the mode too)
	hook.Add("PlayerSpawn", "STTS_PhoneRH", function(ply) if not OverrideSpawn then RH.Stop(ply, "spawn") end end)
	hook.Add("PlayerDisconnected", "STTS_PhoneRH", function(ply) RH.On[ply] = nil end)

	-- Z-City's radial inventory (hg_radialinventory 1) selects over its own net message
	local function WrapNI()
		local key = "ni_selectweapon"
		local cur = net.Receivers and net.Receivers[key]
		if not isfunction(cur) or (RH.wNI and STTS.WrapHas(cur, RH.wNI)) then return end
		local orig = cur
		local function wrap(len, ply, ...)
			if IsValid(ply) and RH.On[ply] then RH.Stop(ply, "select") end
			return orig(len, ply, ...)
		end
		STTS.WrapInner[wrap] = orig
		RH.wNI = wrap
		net.Receivers[key] = wrap
	end
	WrapNI()
	hook.Add("InitPostEntity", "STTS_PhoneRHNet", WrapNI)
	timer.Create("STTS_PhoneRHNet", 5, 0, WrapNI)
end

if CLIENT then
	local Face = SWEP.STTS_Face
	local Motion = SWEP.STTS_Motion
	local ApplyLeftFingers = SWEP.STTS_ApplyLeftFingers
	local Slerp = SWEP.Slerp
	local RotV, RotA = SWEP.RotV, SWEP.RotA

	local function Deny() surface.PlaySound("common/wpn_denyselect.wav") end
	RH.Deny = Deny
	function RH.Err(err)
		if (RH.errT or 0) > RealTime() then return end
		RH.errT = RealTime() + 5
		ErrorNoHalt("[ZPhone] phone + right hand: " .. tostring(err) .. "\n")
	end

	function RH.Send(op, wep)
		net.Start("stts_phone_rh")
		net.WriteUInt(op, 2)
		net.WriteEntity(IsValid(wep) and wep or NULL)
		net.SendToServer()
	end
	net.Receive("stts_phone_rh", function()
		local op = net.ReadUInt(2)
		net.ReadEntity()
		if op == 3 then Deny() end
	end)

	-- nil = held out on the left, rear camera forward (RH.FilmPose), "ear" = in a call
	function RH.Mode(ph)
		if ph:IsDown() or ph:VideoOn() then return end
		if ph:GetInCall() then return "ear" end
	end

	local function Smooth(x) return x * x * (3 - 2 * x) end

	--[[ no call: the phone is held out on the left like for filming. its REAR camera
	     looks forward, where you look (as raised / in a video call), only a tiny bit
	     to the right (RH_TURN degrees). the display faces back toward you ]]
	local RH_TURN = 3
	function RH.FilmPose(ph, wpn, fo, fa)
		local off = ParseVec(rhPosCvar, RH_POS)
		-- looking far up / down: the hand follows only part of the way, the camera all of it
		local hp = Angle(math.Clamp(math.NormalizeAngle(fa.p), -40, 55), fa.y, fa.r)
		local pos = fo + hp:Forward() * off.x + hp:Right() * off.y + hp:Up() * off.z
		local _, aim = LocalToWorld(vector_origin, Angle(0, -RH_TURN, 0), vector_origin, fa)
		-- display up = back toward you, top of the phone = up of the picture
		return pos, aim:Up():AngleEx(-aim:Forward())
	end

	--[[ the left hand to the phone pose (before Z-City's arm IK). the same math as
	     SWEP:SetHandPos: the pose is smoothed in the frame of the eyes, the sway
	     (Motion) on top, blended in from the hand of the animation. a reload / a
	     door (zmanip) = blended back to what Z-City does with that hand. true =
	     the hand was placed (the IK has to use it) ]]
	function RH.LeftHand(ply, ent)
		local ph = RH.Phone(ply)
		if not ph then return false end
		local now = RealTime()
		if (ph.STTS_RHT or 0) < now - 0.3 then -- (again) in this mode
			if ph.STTS_LPos and ph.STTS_LAng and (ph.STTS_W or 0) > 0.001 and ph.STTS_Frame and FrameNumber() - ph.STTS_Frame < 30 then
				-- the phone was posed in the hand a moment ago (at the ear in a call ...): from there
				ph.STTS_RHW, ph.STTS_RHLP, ph.STTS_RHLA = ph.STTS_W, Vector(ph.STTS_LPos), Angle(ph.STTS_LAng)
			else
				-- from the hand of the animation
				ph.STTS_RHW, ph.STTS_RHLP, ph.STTS_RHLA = 0, nil, nil
				ph.STTS_MP, ph.STTS_MV, ph.STTS_MT, ph.STTS_MPrevFa, ph.STTS_MOutP, ph.STTS_MOutR = nil, nil, nil, nil, nil, nil
				ph.STTS_MEy, ph.STTS_MWy, ph.STTS_MEp, ph.STTS_MWp = 0, 0, 0, 0
			end
		end
		ph.STTS_RHT = now
		-- a ragdoll: its real hand holds the phone (drawn there), a vehicle ends the mode
		if ent ~= ply or ply:InVehicle() or not (hg and hg.DragLeftHand_Ex) then ph.STTS_RHW, ph.STTS_RHLP = 0, nil return false end
		if (ent.organism and ent.organism.larmamputated) or (ply.GetNetVar and ply:GetNetVar("handcuffed", false)) then return false end
		local wpn = ply:GetActiveWeapon()
		if not IsValid(wpn) then return false end
		local hand = ent:LookupBone("ValveBiped.Bip01_L_Hand")
		local hm = hand and ent:GetBoneMatrix(hand)
		if not hm then return false end
		local vec, off = ph:PalmOffset()
		local animPos, animAng = LocalToWorld(vec, off, hm:GetTranslation(), hm:GetAngles())
		local fo, fa = Face(ply, ent)
		local mode = RH.Mode(ph)
		local f = FrameNumber()
		local dt = math.min(FrameTime(), 0.1)
		local tPos, tAng
		if mode == "ear" then
			tPos, tAng = ph:PoseAt("ear", fo, fa)
		else
			tPos, tAng = RH.FilmPose(ph, wpn, fo, fa)
		end
		local busy = wpn.reload or ply.zmanipstart
		if ph.STTS_RHF ~= f then
			ph.STTS_RHF = f
			ph.STTS_RHW = math.Approach(ph.STTS_RHW or 0, busy and 0 or 1, dt * (busy and 4 or 3.2))
			local lPos, lAng = WorldToLocal(tPos, tAng, fo, fa)
			if not ph.STTS_RHLP then ph.STTS_RHLP, ph.STTS_RHLA = WorldToLocal(animPos, animAng, fo, fa) end
			local k = 1 - math.exp(-dt * 11)
			ph.STTS_RHLP = LerpVector(k, ph.STTS_RHLP, lPos)
			ph.STTS_RHLA = Slerp(k, ph.STTS_RHLA, lAng)
			if Motion then Motion(ph, ply, fo, fa, dt, mode or "rh") end
		end
		local w = ph.STTS_RHW or 0
		if w <= 0.001 or not ph.STTS_RHLP then return false end
		local e = Smooth(w)
		local wPos, wAng = LocalToWorld(ph.STTS_RHLP, ph.STTS_RHLA, fo, fa)
		local mp, mr = ph.STTS_MOutP, ph.STTS_MOutR
		if mr then
			local rel = wPos - fo
			if mr.x ~= 0 then rel = RotV(rel, fa:Up(), mr.x) wAng = RotA(wAng, fa:Up(), mr.x) end
			if mr.y ~= 0 then rel = RotV(rel, fa:Right(), -mr.y) wAng = RotA(wAng, fa:Right(), -mr.y) end
			wPos = fo + rel
			if mr.z ~= 0 then wAng = RotA(wAng, fa:Forward(), mr.z) end
		end
		if mp then wPos = wPos + fa:Forward() * mp.x + fa:Right() * mp.y + fa:Up() * mp.z end
		local pPos = LerpVector(e, animPos, wPos)
		local pAng = Slerp(e, animAng, wAng)
		-- phone pose -> wrist pose (inverse of the palm offset), as SWEP:SetHandPos
		local _, inverse = WorldToLocal(vector_origin, angle_zero, vector_origin, off)
		local _, handAng = LocalToWorld(vector_origin, inverse, vector_origin, pAng)
		local displacement = LocalToWorld(vec, angle_zero, vector_origin, handAng)
		hg.DragLeftHand_Ex(ent, wpn, pPos - displacement, handAng)
		if ph.STTS_LFing then ApplyLeftFingers(ph, ent, hand)
		elseif hg.set_hold then hg.set_hold(ent, "normal") end
		return true
	end

	-- hg.DoTPIK (homigrad/cl_tpik.lua, the arm IK after the weapon placed the hands)
	function RH.WrapIK()
		if not (hg and isfunction(hg.DoTPIK)) then return end
		if RH.wIK and STTS.WrapHas(hg.DoTPIK, RH.wIK) then return end
		local orig = hg.DoTPIK
		local function wrap(ply, ent, ...)
			local on = false
			if IsValid(ply) and ply:IsPlayer() and IsValid(ent) and RH.State(ply) then
				local ok, r = pcall(RH.LeftHand, ply, ent)
				if ok then on = r == true else RH.Err(r) end
			end
			if not on then return orig(ply, ent, ...) end
			local wpn = ply:GetActiveWeapon()
			RH.ikPly = ply -- hg.CanUseLeftHand: free for this IK
			local ok, err = pcall(orig, ply, ent, ...)
			RH.ikPly = nil
			if IsValid(wpn) then wpn.lhandik = false end
			if not ok then RH.Err(err) end
		end
		STTS.WrapInner[wrap] = orig
		RH.wIK = wrap
		hg.DoTPIK = wrap
	end

	-- the phone on the left hand bone (after the hand IK, the body is final here)
	function RH.Draw(ph, ent)
		local hand = ent:LookupBone("ValveBiped.Bip01_L_Hand")
		local m = hand and ent:GetBoneMatrix(hand)
		if not m then return end
		local vec, off = ph:PalmOffset()
		ph:DrawPhone(LocalToWorld(vec, off, m:GetTranslation(), m:GetAngles()))
	end
	hook.Add("CoolPostDrawAppearance", "STTS_PhoneRHDraw", function(ent, ply)
		if not (IsValid(ent) and IsValid(ply) and ply:IsPlayer()) then return end
		local ph = RH.Phone(ply)
		if ph and ph.DrawPhone then RH.Draw(ph, ent) end
	end)

	-- a weapon picked the normal way (1, 2, 3 ... / the wheel / last weapon) = the end
	function RH.WrapSelect()
		if not isfunction(input.SelectWeapon) then return end
		if RH.wSel and STTS.WrapHas(input.SelectWeapon, RH.wSel) then return end
		local orig = input.SelectWeapon
		local function wrap(wep, ...)
			local lp = LocalPlayer()
			if IsValid(lp) and RH.State(lp) then RH.Send(0) end
			return orig(wep, ...)
		end
		STTS.WrapInner[wrap] = orig
		RH.wSel = wrap
		input.SelectWeapon = wrap
	end

	local function WrapAll()
		RH.WrapIK()
		RH.WrapSelect()
	end
	WrapAll()
	hook.Add("InitPostEntity", "STTS_PhoneRHWrap", WrapAll)
	hook.Add("HomigradRun", "STTS_PhoneRHWrap", WrapAll)
	timer.Create("STTS_PhoneRHWrap", 3, 0, WrapAll)

	--[[ Q menu (stts_phone/sh_phone_kick.lua): Phone -> RightHand = these options ]]
	function RH.Name(w)
		local n = (w.GetPrintName and w:GetPrintName()) or w.PrintName or w:GetClass()
		if not isstring(n) or n == "" then n = w:GetClass() end
		if string.sub(n, 1, 1) == "#" then n = language.GetPhrase(string.sub(n, 2)) end
		return n
	end
	function RH.Weapons(ply)
		local list, names = {}, {}
		for _, w in ipairs(ply:GetWeapons()) do
			if RH.Allowed(w) then
				list[#list + 1] = w
				names[w] = RH.Name(w)
			end
		end
		table.sort(list, function(a, b)
			local sa, sb = a.GetSlot and a:GetSlot() or 0, b.GetSlot and b:GetSlot() or 0
			if sa ~= sb then return sa < sb end
			return names[a] < names[b]
		end)
		return list, names
	end
	local function CloseOnRMB(mouseClick) if mouseClick == 2 then return 1 end end
	function RH.MenuOptions(phone)
		local lp = LocalPlayer()
		local _, cur = RH.Phone(lp)
		local opts = {}
		if not rhCvar:GetBool() then
			opts[1] = {function(mouseClick) Deny() return CloseOnRMB(mouseClick) end, "Disabled on this server"}
			return opts
		end
		local list, names = RH.Weapons(lp)
		for _, w in ipairs(list) do
			opts[#opts + 1] = {function(mouseClick)
				local K = STTS.PhoneKick
				if not (IsValid(w) and IsValid(phone) and w:GetOwner() == LocalPlayer()) or phone.STTS_Toss or (K and K.Kicking and K.Kicking(phone)) then
					Deny()
				elseif w ~= cur then
					RH.Send(1, w)
				end
				return CloseOnRMB(mouseClick)
			end, w == cur and ("> " .. names[w] .. " <") or names[w]}
		end
		if cur then
			opts[#opts + 1] = {function(mouseClick) RH.Send(2) return CloseOnRMB(mouseClick) end, "Phone only"}
		end
		if #opts == 0 then
			opts[1] = {function(mouseClick) Deny() return CloseOnRMB(mouseClick) end, "No pistol / knife"}
		end
		return opts
	end

	-- Q -> Phone -> Anims in this mode: the phone back into the hand, then the anim
	function RH.AfterPhone(phone, fn)
		RH.Q = {wep = phone, fn = fn, til = RealTime() + 3, from = RealTime() + 0.3}
		RH.Send(2)
	end
	hook.Add("Think", "STTS_PhoneRHQueue", function()
		local Q = RH.Q
		if not Q then return end
		local lp = LocalPlayer()
		if not (IsValid(Q.wep) and IsValid(lp) and lp:Alive()) or RealTime() > Q.til then
			RH.Q = nil
			Deny()
			return
		end
		if RealTime() < Q.from or lp:GetActiveWeapon() ~= Q.wep then return end
		if Q.wep.CanToss and not Q.wep:CanToss() then return end -- still blending / in a call: wait (or the timeout)
		RH.Q = nil
		Q.fn(Q.wep)
	end)
end

-- keepy-uppy with the phone ("Litvin", Q menu -> Phone), wraps some of the SWEP functions above
if SERVER then AddCSLuaFile("stts_phone/sh_phone_kick.lua") end
include("stts_phone/sh_phone_kick.lua")

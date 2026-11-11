--[[---------------------------------------------------------------------------
	ZPhone for Z-City - client side hooks into vanilla Z-City.
	the ZHunter build had these lines written into the Z-City files; here they
	are put around the Z-City functions from the outside (Z-City stays
	untouched). checked again every few seconds, so a Z-City reload or a late
	load order does not lose them.
	* RenderScene "jopa" (cl_camera.lua) draws the whole main view by itself;
	  while a phone camera renders (STTS.PhoneScreen.InRV) it has to stay out.
	* selfie: Z-City hides your own head / hat / armor in first person - "is
	  this me, seen from my own eyes" = GetViewEntity() == you. while a phone
	  camera renders YOU, those drawing functions see another view entity.
	* voice over the line: the server sends a gain per speaker (hook
	  STTS_PhoneVoiceGain). Z-City sets every voice volume itself
	  (hg.mouthmove), the gain is put on top right after it.
---------------------------------------------------------------------------]]
STTS = STTS or {}

-- fix64: hook.GetTable() can hold a WRAPPER of our function (the phone's profiler and other addons
-- replace hook.Add). "is it ours" was then always false: every 3 s one more layer was put around
-- the last one, the chain grew for the whole session (RenderScene, MouthThink per player) = FPS
-- slowly going down. Everything we registered, and what the hook table really holds, is "ours".
local ours = setmetatable({}, { __mode = "k" })
local function AddOurs(event, id, fn)
	ours[fn] = true
	hook.Add(event, id, fn)
	local t = hook.GetTable()[event]
	local stored = t and t[id]
	if isfunction(stored) then ours[stored] = true end
end
STTS.PhoneHookOurs64 = ours

--[[ RenderScene ]]
local wrappedScene
local function WrapRenderScene()
	local t = hook.GetTable().RenderScene
	local cur = t and t.jopa
	if not isfunction(cur) or cur == wrappedScene or ours[cur] then return end
	local orig = cur
	wrappedScene = function(...)
		local scr = STTS.PhoneScreen
		if scr and scr.InRV then return end
		return orig(...)
	end
	AddOurs("RenderScene", "jopa", wrappedScene)
end

--[[ selfie ]]
local SELFIE_FUNCS = {
	"DrawPlayerRagdoll",     -- fake/sh_render.lua: body, head bone size, armor, TPIK
	"RenderArmors", "DrawArmors",                                   -- sh_equiprender.lua
	"DrawAppearance", "RenderAccessories", "RenderAccessoriesCool", "CoolRenderAccessories", -- new_appearance
}
local wrappedFn = {}
local function OtherView() return game.GetWorld() end

local function Selfie(a, b, c)
	if not STTS_PHONE_SELFIE or not STTS.IsSelfie then return false end
	return (isentity(a) and STTS.IsSelfie(a)) or (isentity(b) and STTS.IsSelfie(b)) or (isentity(c) and STTS.IsSelfie(c)) or false
end

--[[ fix70: your accessories (hood, balaclava, hats...) on YOUR RAGDOLL in the phone picture.
     Z-City skips them there for several reasons that have nothing to do with the view entity:
     the ragdoll's shouldTransmit / NotSeen flags, the shrunk head bone (manipulate scale 0.1 /
     bone matrix 0.01 - a bonemerged hood copies that size and becomes invisible), "norender"
     for yourself. while a phone camera renders you, DrawAccesories is called "forced"
     (islply = false, force = true), the head is full size around it, and the gating flags of
     the body are set to "seen" only for that call ]]
local function SelfieRender(a, b)
	local scr = STTS.PhoneScreen
	return scr and scr.InRV and Selfie(a, b) or false
end
local GATE_FUNCS = {RenderAccessories = true, CoolRenderAccessories = true, RenderArmors = true, DrawArmors = true}
local function GateEnts(ply)
	local list = {}
	if not isentity(ply) or not IsValid(ply) then return list end
	list[#list + 1] = ply
	if IsValid(ply.FakeRagdoll) then list[#list + 1] = ply.FakeRagdoll end
	if IsValid(ply.OldRagdoll) then list[#list + 1] = ply.OldRagdoll end
	local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply)
	if IsValid(ch) and ch ~= ply and ch ~= ply.FakeRagdoll and ch ~= ply.OldRagdoll then list[#list + 1] = ch end
	return list
end
local function WithGates(ply, fn, ...)
	local saved = {}
	for i, e in ipairs(GateEnts(ply)) do
		saved[i] = {e, e.shouldTransmit, e.NotSeen}
		e.shouldTransmit, e.NotSeen = true, false
	end
	local ok, r1, r2, r3 = pcall(fn, ...)
	for _, s in ipairs(saved) do
		if IsValid(s[1]) then s[1].shouldTransmit, s[1].NotSeen = s[2], s[3] end
	end
	if not ok then error(r1, 0) end
	return r1, r2, r3
end
local FULL = Vector(1, 1, 1)
local wrappedAcc
local function WrapAccessory()
	local cur = DrawAccesories
	if not isfunction(cur) or cur == wrappedAcc then return end
	local orig = cur
	wrappedAcc = function(ply, ent, key, data, islply, force, setup, ...)
		if not SelfieRender(ply, ent) or not isentity(ent) or not IsValid(ent) or not istable(data) then
			return orig(ply, ent, key, data, islply, force, setup, ...)
		end
		local scr = STTS.PhoneScreen
		if scr.FixHead65 then pcall(scr.FixHead65, ent) end
		local bone = isstring(data.bone) and ent:LookupBone(data.bone)
		local old
		if bone then
			local sc = ent:GetManipulateBoneScale(bone)
			if sc and sc:LengthSqr() < 0.1 and sc:LengthSqr() > 1e-6 and not ent.noHead then old = sc ent:ManipulateBoneScale(bone, FULL) end
		end
		local ok, r1 = pcall(orig, ply, ent, key, data, false, true, setup, ...)
		if old and IsValid(ent) then ent:ManipulateBoneScale(bone, old) end
		if not ok then error(r1, 0) end
		return r1
	end
	DrawAccesories = wrappedAcc
end

local function WrapSelfie()
	for _, name in ipairs(SELFIE_FUNCS) do
		local cur = _G[name]
		if isfunction(cur) and cur ~= wrappedFn[name] then
			local orig = cur
			local gate = GATE_FUNCS[name]
			local fn = function(a, b, c, ...)
				if not Selfie(a, b, c) then return orig(a, b, c, ...) end
				local g = gate and SelfieRender(a)
				if GetViewEntity == OtherView then
					if g then return WithGates(a, orig, a, b, c, ...) end
					return orig(a, b, c, ...)
				end
				local real = GetViewEntity
				GetViewEntity = OtherView
				local ok, r1, r2, r3
				if g then ok, r1, r2, r3 = pcall(WithGates, a, orig, a, b, c, ...)
				else ok, r1, r2, r3 = pcall(orig, a, b, c, ...) end
				GetViewEntity = real
				if not ok then error(r1, 0) end
				return r1, r2, r3
			end
			wrappedFn[name] = fn
			_G[name] = fn
		end
	end
end

--[[ voice gain ]]
local touched = {}
local function BaseScale(ply)
	if not istable(hg) then return 1 end
	if hg.muteall or (hg.mutespect and not ply:Alive()) then return 0 end
	-- fix72: custom builds keep other things in playerInfo (a number, no volume): 1 then
	local info = istable(hg.playerInfo) and hg.playerInfo[ply:SteamID()]
	local v = istable(info) and tonumber(info[2]) or nil
	return v or 1
end
local function ApplyGain(ply)
	if not IsValid(ply) or not ply.SetVoiceVolumeScale then return end
	local gain = hook.Run("STTS_PhoneVoiceGain", ply)
	if gain == nil then
		-- the call is over: back to the normal volume (Z-City does it too while it animates him)
		if touched[ply] then touched[ply] = nil ply:SetVoiceVolumeScale(BaseScale(ply)) end
		return
	end
	touched[ply] = true
	ply:SetVoiceVolumeScale(BaseScale(ply) * gain)
end

local wrappedMouth, wrappedThink
local function WrapVoice()
	if not hg then return end
	if isfunction(hg.mouthmove) and hg.mouthmove ~= wrappedMouth then
		local orig = hg.mouthmove
		wrappedMouth = function(ply, ...)
			orig(ply, ...)
			ApplyGain(ply)
		end
		hg.mouthmove = wrappedMouth
	end
	local t = hook.GetTable()["Player Think"]
	local cur = t and t.MouthThink
	if isfunction(cur) and cur ~= wrappedThink and not ours[cur] then
		local orig = cur
		wrappedThink = function(ply, ...)
			orig(ply, ...)
			ApplyGain(ply)
		end
		AddOurs("Player Think", "MouthThink", wrappedThink)
	end
end

-- speakers far away are not animated by Z-City at all: their gain is set from here
local nextGain = 0
hook.Add("Think", "STTS_PhoneVoiceGainApply", function()
	local now = RealTime()
	-- fix72: the speakers of a call every frame (voice / proximity addons of custom builds set
	-- the volume every frame too), everybody else 10 times a second; also without Z-City
	if now < nextGain then
		for ply in pairs(touched) do
			if IsValid(ply) then ApplyGain(ply) end
		end
		return
	end
	nextGain = now + 0.1
	local lp = LocalPlayer()
	for _, ply in player.Iterator() do
		if ply ~= lp then ApplyGain(ply) end
	end
	for ply in pairs(touched) do
		if not IsValid(ply) then touched[ply] = nil end
	end
end)

--[[ fix71: the mouse ("the finger does not move").
     InputMouseApply is run until a hook returns true. Z-City's "fakeCameraAngles" (and the mouse
     hooks of other addons: vehicles, third person, free look...) always return true, so the
     phone's hook only ran when it happened to be first in the table - a matter of load order,
     different from server to server. every foreign InputMouseApply hook is wrapped: while the
     raised phone (or the kick) wants the mouse, the phone takes it and the hook is skipped for
     that frame; else it runs as always ]]
local function MouseClaim(cmd, x, y, ang)
	if STTS.KickMouse71 and STTS.KickMouse71(cmd, x, y) then return true end
	local scr = STTS.PhoneScreen
	if scr and scr.PointerWants71 and scr.PhonePointer and scr.PointerWants71() then
		return scr.PhonePointer(cmd, x, y, ang) == true
	end
	return false
end
local function OurId(id)
	local p = isstring(id) and string.sub(id, 1, 5)
	return p == "STTS_" or p == "stts_"
end
local function MouseWrapper(orig)
	local w = function(cmd, x, y, ang, ...)
		if MouseClaim(cmd, x, y, ang) then return true end
		return orig(cmd, x, y, ang, ...)
	end
	ours[w] = true
	return w
end
--[[ fix72: cameras that read the mouse in CreateMove (cmd:GetMouseX / GetMouseY: custom builds,
     ragdoll / vehicle cameras of other addons) turned the view while the finger moved. while the
     phone has the mouse, every foreign CreateMove hook gets the command with no mouse movement ]]
local MB = {f = -1}
local function MouseBusy()
	local f = FrameNumber()
	if MB.f ~= f then
		MB.f = f
		local scr = STTS.PhoneScreen
		MB.on = (STTS.PhoneKick and STTS.PhoneKick.K) and true or (scr and scr.PointerWants71 and scr.PointerWants71()) and true or false
	end
	return MB.on
end
STTS.PhoneMouseBusy72 = MouseBusy
local function MoveWrapper(orig)
	local w = function(cmd, ...)
		if MouseBusy() then cmd:SetMouseX(0) cmd:SetMouseY(0) end
		return orig(cmd, ...)
	end
	ours[w] = true
	return w
end
hook.Add("CreateMove", "STTS_PhoneMouse72", function(cmd)
	if MouseBusy() then cmd:SetMouseX(0) cmd:SetMouseY(0) end
end)

-- every foreign hook (string id) of an event gets the wrapper; ULib: changed in place (keeps the priority)
local function WrapEvent(event, maker)
	if hook.GetULibTable then
		local prio = hook.GetULibTable()[event]
		if not istable(prio) then return end
		for _, bucket in pairs(prio) do
			if istable(bucket) then
				for id, r in pairs(bucket) do
					if istable(r) and isstring(id) and isfunction(r.fn) and not OurId(id) and not ours[r.fn] then r.fn = maker(r.fn) end
				end
			end
		end
		return
	end
	local t = hook.GetTable()[event]
	if not t then return end
	local list = {}
	for id, fn in pairs(t) do
		if isstring(id) and isfunction(fn) and not OurId(id) and not ours[fn] then list[#list + 1] = id end
	end
	for i = 1, #list do
		local id = list[i]
		AddOurs(event, id, maker(t[id]))
	end
end
local function WrapMouse()
	WrapEvent("InputMouseApply", MouseWrapper)
	WrapEvent("CreateMove", MoveWrapper)
end
STTS.PhoneMouseWrap72 = WrapMouse

-- the community "RMB pointer" file (zzz_stts_phone_rmb_pointer.lua) is built in (stts_phone_controls 2);
-- if it is installed as well, its copy would move the finger twice and replace our RMB
local function DropOldPointerFix()
	local ht = hook.GetTable()
	local think, hgm = ht.Think, ht["HG.InputMouseApply"]
	if hgm and hgm.STTS_PhoneRMBPointerHG then hook.Remove("HG.InputMouseApply", "STTS_PhoneRMBPointerHG") end
	if think and think.STTS_PhoneRMBPointer then hook.Remove("Think", "STTS_PhoneRMBPointer") end
	local scr = STTS.PhoneScreen
	if scr and scr.LookToggle71 and not (think and think.STTS_PhoneLookToggle) then
		hook.Add("Think", "STTS_PhoneLookToggle", scr.LookToggle71)
	end
end

local function InstallAll()
	WrapRenderScene()
	WrapSelfie()
	WrapAccessory()
	WrapVoice()
	WrapMouse()
	DropOldPointerFix()
end
InstallAll()
hook.Add("InitPostEntity", "STTS_ZPhoneCompat", InstallAll)
timer.Simple(0, DropOldPointerFix) -- right after the other autorun files (the "zzz_" one loads after us)
timer.Create("STTS_ZPhoneCompat", 3, 0, InstallAll)

--[[---------------------------------------------------------------------------
	ZPhone fix71 - getting along with other addons and custom Z-City builds.
	* an error inside one of OUR hooks used to stop that event for every addon
	  after it (GMod's hook.Call has no protection): one broken phone Think =
	  broken Think of whatever came after it. our hooks (ids STTS_* / stts_*) are
	  now run protected, the error is printed (at most every 10 s per hook) and
	  the rest of the hooks keep running. zhphone_safe_hooks 0 = off.
	* custom Z-City builds that lack some of the functions the phone calls get
	  small stand-ins (only when the function is missing - a real one always
	  wins, checked again every few seconds).
	* zhphone_compat (client console): what was found / replaced, who else sits
	  in the mouse hook, recent errors of the phone hooks.
---------------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end
STTS = STTS or {}
local S = STTS.Safe71 or {}
STTS.Safe71 = S
S.errors = S.errors or {}
S.wrapped = S.wrapped or setmetatable({}, { __mode = "k" }) -- wrapper (and what the table stores) -> true
S.cache = S.cache or setmetatable({}, { __mode = "k" })   -- original -> wrapper
S.shims = S.shims or {}

local cvSafe = CreateConVar("zhphone_safe_hooks", "1", FCVAR_ARCHIVE, "1 = the hooks of ZPhone run protected: an error in the phone does not stop the hooks of other addons", 0, 1)
-- monitor-priority hooks (ULib) and hooks whose function is compared somewhere stay as they are
local SKIP_EVENTS = { EntityEmitSound = true }
local SKIP_IDS = { STTS_PhoneEarView63 = true }

local function Mine(id)
	if not isstring(id) or SKIP_IDS[id] then return false end
	local p = string.sub(id, 1, 5)
	return p == "STTS_" or p == "stts_"
end

local function Report(key, err)
	local e = S.errors[key]
	if not e then e = { n = 0, at = 0 } S.errors[key] = e end
	e.n = e.n + 1
	e.msg = tostring(err)
	e.when = os.time()
	local now = SysTime()
	if now >= e.at then
		e.at = now + 10
		ErrorNoHalt("[ZPhone] error in hook " .. key .. " (x" .. e.n .. "), the other addons keep running:\n" .. e.msg .. "\n")
	end
end
local function Trace(err) return debug.traceback(tostring(err), 2) end

local function MakeSafe(key, fn)
	local w = S.cache[fn]
	if w then return w end
	local function done(ok, ...)
		if ok then return ... end
		Report(key, (...))
	end
	w = function(...) return done(xpcall(fn, Trace, ...)) end
	S.wrapped[w] = true
	S.cache[fn] = w
	return w
end
S.MakeSafe = MakeSafe

function S.Install()
	if not cvSafe:GetBool() then return end
	if hook.GetULibTable then
		-- ULib: change the callback records in place (keeps their priority)
		for event, prio in pairs(hook.GetULibTable()) do
			if not SKIP_EVENTS[event] and istable(prio) then
				for _, bucket in pairs(prio) do
					if istable(bucket) then
						for id, r in pairs(bucket) do
							if istable(r) and Mine(id) and isfunction(r.fn) and not S.wrapped[r.fn] then
								r.fn = MakeSafe(event .. "/" .. id, r.fn)
							end
						end
					end
				end
			end
		end
		return
	end
	local list = {}
	for event, bucket in pairs(hook.GetTable()) do
		if not SKIP_EVENTS[event] and istable(bucket) then
			for id, fn in pairs(bucket) do
				if Mine(id) and isfunction(fn) and not S.wrapped[fn] then list[#list + 1] = { event, id, fn } end
			end
		end
	end
	for i = 1, #list do
		local event, id, fn = list[i][1], list[i][2], list[i][3]
		hook.Add(event, id, MakeSafe(event .. "/" .. id, fn))
		-- another hook library / profiler may store its own wrapper of ours: that is ours too
		local t = hook.GetTable()[event]
		local stored = t and t[id]
		if isfunction(stored) then S.wrapped[stored] = true end
	end
end

--[[ stand-ins for missing Z-City functions (the same thing Z-City does, cl_tpik.lua / cl_bones.lua /
     fake/cl_fake.lua, cut down) ]]
local function Shim(name, fn)
	if hg[name] ~= nil then return end
	hg[name] = fn
	S.shims[name] = fn
end

function S.InstallShims()
	if not istable(hg) then return end
	for name, fn in pairs(S.shims) do
		if hg[name] ~= fn then S.shims[name] = nil end -- a real one came: forget ours
	end
	Shim("GetCurrentCharacter", function(ply)
		if not IsValid(ply) then return ply end
		local rag = ply.FakeRagdoll
		if not IsValid(rag) and ply.GetNWEntity then rag = ply:GetNWEntity("FakeRagdoll") end
		if IsValid(rag) then return rag end
		return ply
	end)
	Shim("RagdollOwner", function(rag)
		if not IsValid(rag) then return end
		for _, ply in player.Iterator() do
			if ply.FakeRagdoll == rag or (ply.GetNWEntity and ply:GetNWEntity("FakeRagdoll") == rag) then return ply end
		end
	end)
	Shim("CanUseLeftHand", function(ply)
		local ent = IsValid(ply) and (IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply)
		return not (ent and ent.organism and ent.organism.larmamputated)
	end)
	Shim("CanUseRightHand", function(ply)
		local ent = IsValid(ply) and (IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply)
		return not (ent and ent.organism and ent.organism.rarmamputated)
	end)
	if not CLIENT then return end
	local function Children(ent, bone, out, endbone)
		local list = ent:GetChildBones(bone)
		if not list then return out end
		for i = 1, #list do
			local id = list[i]
			if id ~= endbone then
				Children(ent, id, out, endbone)
				out[#out + 1] = id
			end
		end
		return out
	end
	Shim("get_children", function(ent, bone, endbone)
		bone = isstring(bone) and ent:LookupBone(bone) or bone
		if not bone or isstring(bone) or bone == -1 then return end
		return Children(ent, bone, {}, endbone)
	end)
	Shim("bone_apply_matrix", function(ent, bone, new, endbone)
		bone = isstring(bone) and ent:LookupBone(bone) or bone
		if not bone or isstring(bone) or bone == -1 then return end
		local m = ent:GetBoneMatrix(bone)
		local inv = m and m:GetInverse()
		if not inv then return end
		local tr = new * inv
		local ch = hg.get_children(ent, bone, endbone) or {}
		for i = 1, #ch do
			local cm = ent:GetBoneMatrix(ch[i])
			if cm then ent:SetBoneMatrix(ch[i], tr * cm) end
		end
		ent:SetBoneMatrix(bone, new)
	end)
	local function Drag(boneName, flag, key)
		return function(ent, wep, pos, ang, rel)
			if not IsValid(ent) or not ent:LookupBone("ValveBiped.Bip01_Spine4") then return end
			local b = ent:LookupBone(boneName)
			local m = b and ent:GetBoneMatrix(b)
			if not m then return end
			if istable(wep) or IsValid(wep) then wep[flag] = true end
			if not pos then return end
			local old = m:GetTranslation()
			pos.x = math.Clamp(pos.x, old.x - 38, old.x + 38)
			pos.y = math.Clamp(pos.y, old.y - 38, old.y + 38)
			pos.z = math.Clamp(pos.z, old.z - 38, old.z + 38)
			if ang then
				local p, a = LocalToWorld(vector_origin, rel or angle_zero, pos, ang)
				m:SetTranslation(p)
				m:SetAngles(a)
			end
			hg.bone_apply_matrix(ent, b, m)
			ent[key] = pos - old
		end
	end
	Shim("DragLeftHand_Ex", Drag("ValveBiped.Bip01_L_Hand", "lhandik", "oldposlh"))
	Shim("DragRightHand_Ex", Drag("ValveBiped.Bip01_R_Hand", "rhandik", "oldposrh"))
	Shim("set_hold", function() end)
	Shim("set_holdrh", function() end)
end

local function All()
	S.InstallShims()
	S.Install()
end
-- after everything is loaded (a Z-City "hg.x = hg.x or ..." must never get our stand-in)
hook.Add("InitPostEntity", "STTS_PhoneSafe71", function() timer.Simple(1, All) end)
timer.Create("STTS_PhoneSafe71", 10, 0, All)
if (CLIENT and IsValid(LocalPlayer())) or (SERVER and #player.GetAll() > 0) then timer.Simple(1, All) end -- Lua refresh

if not CLIENT then return end

--[[ zhphone_compat: for bug reports ("the finger does not move" etc.) ]]
local FUNCS = { "GetCurrentCharacter", "RagdollOwner", "CanUseLeftHand", "CanUseRightHand", "DragLeftHand_Ex", "DragRightHand_Ex",
	"bone_apply_matrix", "get_children", "set_hold", "set_holdrh", "MainTPIKFunction", "ShouldTPIK", "DoZManip", "GetCarSteering" }
local function Src(fn)
	if not isfunction(fn) then return "-" end
	local i = debug.getinfo(fn, "S")
	return i and ((i.short_src or "?") .. ":" .. (i.linedefined or 0)) or "?"
end
concommand.Add("zhphone_compat", function()
	local out = {}
	local function P(s) out[#out + 1] = "[ZPHONE] " .. s end
	P("compat report (fix72)")
	P("Z-City (hg): " .. (istable(hg) and "found" or "NOT FOUND"))
	if istable(hg) then
		for _, name in ipairs(FUNCS) do
			local fn = hg[name]
			P(string.format("  hg.%-20s %s", name, fn == nil and "missing" or (S.shims[name] == fn and "stand-in (missing in this build)" or Src(fn))))
		end
	end
	local ht = hook.GetTable()
	for _, ev in ipairs({ "InputMouseApply", "HG.InputMouseApply", "CreateMove", "StartCommand", "PlayerBindPress" }) do
		local n, ids = 0, {}
		for id, fn in pairs(ht[ev] or {}) do
			n = n + 1
			if #ids < 24 then
				local tag = ""
				if STTS.PhoneHookOurs64 and STTS.PhoneHookOurs64[fn] and not Mine(id) then tag = " (phone in front)" end
				ids[#ids + 1] = tostring(id) .. tag
			end
		end
		table.sort(ids)
		P(ev .. ": " .. n .. " hooks: " .. table.concat(ids, ", "))
	end
	local scr = STTS.PhoneScreen
	if scr then
		local function cv(n) local c = GetConVar(n) return c and c:GetString() or "?" end
		P("stts_phone_controls " .. cv("stts_phone_controls") .. ", stts_phone_input_fallback " .. cv("stts_phone_input_fallback")
			.. ", stts_phone_finger_force " .. cv("stts_phone_finger_force") .. ", stts_phone_finger_speed " .. cv("stts_phone_finger_speed")
			.. ", zhphone_safe_hooks " .. cv("zhphone_safe_hooks"))
		local L = scr.L
		if L then
			P(string.format("phone: raised %s, look %s, finger %.0f %.0f, last mouse move %s", tostring(L.raised), tostring(L.look),
				L.ux or -1, L.uy or -1, L.moveAt71 and string.format("%.1f s ago", RealTime() - L.moveAt71) or "never"))
		end
		local v = STTS_PHONE_VIEW
		P("view: " .. (v and string.format("%.2f s old%s", RealTime() - (v.t or 0), v.fb72 and " (fallback: player eyes)" or "") or "never caught")
			.. ", camera render stuck: " .. tostring(scr.InRV == true) .. ", mouse to the phone: " .. tostring(STTS.PhoneMouseBusy72 and STTS.PhoneMouseBusy72() or false))
		if scr.lastDrawErr72 then P("last display draw error: " .. string.sub(string.gsub(scr.lastDrawErr72, "\n.*", ""), 1, 200)) end
		local lp = LocalPlayer()
		local wep = IsValid(lp) and lp:GetActiveWeapon()
		if IsValid(wep) and wep:GetClass() == "weapon_stts_phone" then
			P(string.format("held phone: display off (server) %s, auto-lock at %.1f, raised (server) %s", tostring(wep:GetNW2Bool("Off", false)), wep:GetNW2Float("LkAt", 0), tostring(wep.GetRaised and wep:GetRaised())))
		end
		if IsValid(wep) and wep.RightHandFree71 then
			P("right hand free for the finger: " .. tostring(wep:RightHandFree71(lp)) .. (hg and hg.CanUseRightHand and (", hg.CanUseRightHand: " .. tostring(hg.CanUseRightHand(lp))) or ""))
		end
	end
	local nerr = 0
	for key, e in SortedPairs(S.errors) do
		nerr = nerr + 1
		if nerr <= 8 then P("error x" .. e.n .. " in " .. key .. ": " .. string.sub(string.gsub(e.msg or "", "\n.*", ""), 1, 200)) end
	end
	P(nerr == 0 and "no errors in the phone hooks" or (nerr .. " phone hooks had errors"))
	for i = 1, #out do print(out[i]) end
	if SetClipboardText then SetClipboardText(table.concat(out, "\n")) print("[ZPHONE] (copied to the clipboard)") end
end, nil, "ZPhone: compatibility report (Z-City functions, mouse hooks, recent errors), copied to the clipboard")

--[[---------------------------------------------------------------------------
        ZHUNTER phone: placement preview (the "TikTok stand" mode).
        Hold MMB (press and hold the mouse wheel button) while the phone is
        in your hand: a translucent GREEN ghost of the REAL phone model
        appears where you aim, lying SCREEN UP on the floor / table /
        whatever you point at. Aim at a wall: the HEIGHT of the aim point on
        that wall sets the lean - aim near the floor and the phone stands up
        (up to ~80 degrees), slide the aim higher and it lays down towards
        flat (lean = acos(D / L) from the bottom edge to the wall).
        Release MMB: the phone is placed right there, exactly as if it was
        dropped through the Q radial menu "Drop Weapon" (same drop command,
        same animation, same E-to-pickup afterwards), snapped to the preview
        pose and left as a NORMAL physics prop - NOT frozen. If it stands at
        an angle it is WELDED to what it touches (the wall its top edge
        leans on + the ground / prop under it) so the lean holds exactly as
        previewed; a phone lying flat stays a free prop. Any pickup (hands
        / E / physgun / gravgun) removes the welds again.
        Made to park the phone somewhere with the camera app running and
        record videos of yourself. No HUD text, no outline box.
        Client convars:
          stts_phone_place         1 = enabled (default)
        build: v13 (repack)
---------------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

local G = STTS and STTS.PhoneGeo
if not G then include("autorun/sh_stts_phone.lua") G = STTS.PhoneGeo end
if not G then return end

local math_abs, math_sin, math_cos, math_acos, math_asin, math_rad, math_deg, math_random = math.abs, math.sin, math.cos, math.acos, math.asin, math.rad, math.deg, math.random
local math_Clamp = math.Clamp

local PHONE_CLASS = "weapon_stts_phone"

--[[---------------------------------------------------------------------------
        client: input, green ghost
---------------------------------------------------------------------------]]
if CLIENT then
        -- the release action is sent as a NET MESSAGE, not a concommand: the first
        -- build gave the server concommand the same name as the convar below, and on
        -- listen servers / singleplayer both realms share one engine command
        -- registry, so CreateClientConVar failed, returned nil and every hook
        -- touching it errored every frame ("attempt to index upvalue 'cvOn'").
        -- nil-safe anyway: if the convar ever fails to create, the default wins.
        local cvOn = CreateClientConVar("stts_phone_place", "1", true, false, "hold MMB with the phone in hand: green placement preview, release = place the phone there", 0, 1)
                or GetConVar("stts_phone_place")

        local function PlaceEnabled()
                if cvOn == nil then return true end
                return cvOn:GetBool()
        end

        local active = false   -- MMB held with the phone in hand
        local pose = nil       -- last preview pose: { pos, ang, M } or nil (no spot)
        local ghost, ghostPath -- clientside model of the ghost
        local rootFix = {}     -- model path -> root bone correction (the models carry a 90 degree root turn)

        --[[ the root bone of these phone models carries the studiomdl default 90 degree
             turn, so the mesh draws turned inside its own plane. measure once, correct
             the draw pose (same trick as weapon_stts_phone.lua). ]]
        local function RootFix(mdl)
                local key = mdl:GetModel() or ""
                if rootFix[key] ~= nil then return rootFix[key] end
                mdl:SetPos(vector_origin) mdl:SetAngles(angle_zero)
                mdl:InvalidateBoneCache()
                mdl:SetupBones()
                local m = mdl:GetBoneMatrix(0)
                if not m then return false end -- bones not ready yet, retry next frame
                local p, a = m:GetTranslation(), m:GetAngles()
                local turned = math_abs(math.AngleDifference(a.p, 0)) + math_abs(math.AngleDifference(a.y, 0)) + math_abs(math.AngleDifference(a.r, 0)) > 0.5
                local fix = false
                if turned or p:LengthSqr() > 0.0001 then
                        local ip, ia = WorldToLocal(vector_origin, angle_zero, p, a)
                        fix = { ip, ia }
                end
                rootFix[key] = fix
                return fix
        end

        -- horizontal direction the top of the phone points at (the aim, projected)
        local function TopDir(eyeAng)
                local d = eyeAng:Forward()
                d.z = 0
                if d:LengthSqr() < 0.0001 then
                        d = eyeAng:Right()
                        d.z = 0
                end
                if d:LengthSqr() < 0.0001 then return Vector(1, 0, 0) end
                d:Normalize()
                return d
        end

        -- everything that must not eat the traces: all players, own ragdoll, own weapon
        local function Filter()
                local f = {}
                for _, p in ipairs(player.GetAll()) do f[#f + 1] = p end
                local lply = LocalPlayer()
                local wep = lply:GetActiveWeapon()
                if IsValid(wep) then f[#f + 1] = wep end
                local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(lply) or NULL
                if IsValid(ch) then f[#f + 1] = ch end
                return f
        end

        --[[ the preview pose of THIS phone for the current view, or nil (no spot).
             the phone lies screen up, top along the aim; aimed at a wall the
             aim height on that wall sets the lean: near the floor it stands
             up (up to ~80 degrees), higher up it lies down towards flat. ]]
        local PLACE_MAX = 120 -- how far the placement aim reaches (the old reach / 1.5)

        local function ComputePose(wep)
                local ply = LocalPlayer()
                if not IsValid(ply) then return end
                local eye, ang = ply:EyePos(), ply:EyeAngles()
                local tr = util.TraceLine({ start = eye, endpos = eye + ang:Forward() * PLACE_MAX, mask = MASK_SHOT, filter = Filter() })
                if not tr.Hit or tr.StartSolid then return end

                local M = G.Of(wep)
                local L = M.Maxs.x - M.Mins.x   -- length of the phone (top to chin)
                local halfL = L * 0.5
                local halfT = -M.Mins.z         -- from the origin to the back glass

                local floorPos, topDir
                if tr.HitNormal.z > 0.7 then
                        -- floor / table: lie flat right where you aim
                        floorPos = tr.HitPos
                        topDir = TopDir(ang)
                elseif tr.HitNormal.z < -0.7 then
                        return -- a ceiling: a screen-up phone would just fall down
                else
                        -- a wall / steep surface: the phone goes to the floor right under
                        -- the hit point and leans against THIS wall
                        local into = tr.HitNormal * -1
                        into.z = 0
                        if into:LengthSqr() < 0.0001 then return end
                        into:Normalize()
                        local off = tr.HitPos + tr.HitNormal * 1 + Vector(0, 0, 2)
                        local trDown = util.TraceLine({ start = off, endpos = off - Vector(0, 0, 140), mask = MASK_SHOT, filter = Filter() })
                        if not trDown.Hit or trDown.HitNormal.z <= 0.7 then return end
                        -- how high on the wall you aim sets the lean: at the base
                        -- the phone stands up (up to ~80 degrees), sliding the aim
                        -- up the wall lays it down; 140 units up = flat
                        local h = tr.HitPos.z - trDown.HitPos.z
                        local stand = 88 * (1 - math_Clamp(h / 140, 0, 1))
                        local pd = L * math_cos(math_rad(stand)) -- bottom edge -> wall distance
                        if pd < 1 then pd = 1 end                -- never bury the bottom edge
                        floorPos = trDown.HitPos - into * (pd - 1 - halfL) -- trDown lands 1 unit off the wall
                        topDir = into
                end

                local upV = vector_up
                local originFlat = floorPos + upV * halfT
                local angFlat = topDir:AngleEx(upV) -- forward = top of the phone, up = out of the screen

                -- the bottom edge (the line that stays on the floor while it leans)
                local pivot = floorPos - topDir * halfL

                -- distance from the bottom edge to the wall, along the top direction
                local trWall = util.TraceLine({ start = pivot + upV * 1.2, endpos = pivot + upV * 1.2 + topDir * (L + 14), mask = MASK_SHOT, filter = Filter() })
                if trWall.StartSolid then -- a plinth swallowed the ray: retry above it
                        trWall = util.TraceLine({ start = pivot + upV * 6, endpos = pivot + upV * 6 + topDir * (L + 14), mask = MASK_SHOT, filter = Filter() })
                end
                local D = L + 14
                if trWall.Hit and not trWall.StartSolid then
                        D = (trWall.HitPos - trWall.StartPos):Length()
                end

                -- the closer the bottom edge is to the wall, the steeper the lean:
                -- the top edge touches the wall exactly at acos(D / L); the only
                -- cap is physical (keep the screen out of the wall), no menu limit
                local tilt = 0
                if D < L then
                        tilt = math_deg(math_acos(math_Clamp(D / L, 0, 1)))
                        if tilt > 88 then tilt = 88 end
                end

                local pos, pAng = originFlat, angFlat
                if tilt > 0.1 then
                        -- rotate around the bottom edge: the top edge slides up the wall
                        local axis = topDir:Cross(upV)
                        local rel = topDir * halfL + upV * halfT -- pivot -> phone origin
                        local relR = rel * math_cos(math_rad(tilt)) + axis:Cross(rel) * math_sin(math_rad(tilt))
                        pos = pivot + relR
                        pAng = Angle(angFlat.p, angFlat.y, angFlat.r)
                        pAng:RotateAroundAxis(axis, tilt)
                end

                return { pos = pos, ang = pAng, M = M }
        end

        local function CanUse()
                local ply = LocalPlayer()
                if not IsValid(ply) or not ply:Alive() then return end
                if ply:InVehicle() then return end
                if vgui.CursorVisible() then return end
                local wep = ply:GetActiveWeapon()
                if not IsValid(wep) or wep:GetClass() ~= PHONE_CLASS then return end
                -- keepy-uppy (Litvin) in progress: no placing
                local KK = STTS.PhoneKick
                if KK and KK.Kicking and KK.Kicking(wep) then return end
                local org = ply.organism
                if org and (org.otrub or org.canmove == false) then return end
                return wep
        end

        -- MMB: hold = preview, release = place
        hook.Add("Think", "stts_phone_place_input", function()
                local wep = PlaceEnabled() and CanUse() or nil
                local down = wep ~= nil and input.IsMouseDown(MOUSE_MIDDLE)
                if down and not active then
                        active = true
                        surface.PlaySound("ui/buttonclick.wav")
                elseif active and not down then
                        active = false
                        local p = wep ~= nil and ComputePose(wep) or nil -- fresh pose at the moment of release
                        if wep ~= nil and p then
                                net.Start("stts_phone_place")
                                net.WriteVector(p.pos)
                                net.WriteAngle(p.ang)
                                net.SendToServer()
                                surface.PlaySound("ui/buttonclickrelease.wav")
                        end
                        pose = nil
                end
        end)

        -- while the preview is up the scroll wheel must not switch weapons
        hook.Add("PlayerBindPress", "stts_phone_place_blocks", function(ply, bind, pressed)
                if not active then return end
                if string.find(bind, "invprev", 1, true) or string.find(bind, "invnext", 1, true)
                        or string.find(bind, "slot", 1, true) or string.find(bind, "lastinv", 1, true) then
                        return true
                end
        end)

        local function KillGhost()
                if IsValid(ghost) then ghost:Remove() end
                ghost, ghostPath = nil, nil
        end

        hook.Add("PostDrawTranslucentRenderables", "stts_phone_place_ghost", function(bDepth, bSkybox)
                if bSkybox then return end
                if not active then
                        if ghost then KillGhost() end
                        return
                end
                local wep = CanUse()
                if not wep then return end
                pose = ComputePose(wep)
                if not pose then return end -- no spot: nothing to draw

                local pos, ang, M = pose.pos, pose.ang, pose.M

                local path = G.ModelPath(wep)
                if path ~= ghostPath then
                        KillGhost()
                        ghostPath = path
                end
                if not IsValid(ghost) then
                        ghost = ClientsideModel(path, RENDERGROUP_TRANSLUCENT)
                        if IsValid(ghost) then
                                ghost:SetNoDraw(true)
                                ghost:SetModelScale(1)
                        end
                end

                if IsValid(ghost) then
                        -- the REAL model: translucent, tinted green, softly pulsing
                        local fix = RootFix(ghost)
                        local dpos, dang = pos, ang
                        if fix then dpos, dang = LocalToWorld(fix[1], fix[2], pos, ang) end
                        ghost:SetPos(dpos) ghost:SetAngles(dang)
                        ghost:InvalidateBoneCache()
                        ghost:SetupBones()
                        render.SetBlend(0.42 + math_sin(RealTime() * 5) * 0.08)
                        render.SetColorModulation(0.35, 1.0, 0.55)
                        render.SuppressEngineLighting(true)
                        ghost:DrawModel()
                        render.SuppressEngineLighting(false)
                        render.SetColorModulation(1, 1, 1)
                        render.SetBlend(1)
                else
                        -- the phone model is not compiled here: a green box with its exact size
                        render.SetColorMaterial()
                        render.DrawBox(pos, ang, M.Mins, M.Maxs, Color(60, 255, 120, 120))
                end
        end)

end

--[[---------------------------------------------------------------------------
        server: place the phone exactly like the Q radial "Drop Weapon",
        snap it to the preview pose, weld it in place right away (anchored
        for 0.2 s so the pose cannot twitch, then free again)
---------------------------------------------------------------------------]]
if SERVER then
        local MAX_DIST = 175 -- the client aims up to ~120 units away (+ interpolation headroom)

        util.AddNetworkString("stts_phone_place")

        -- welds of placed, leaning phones: [phone] = { constraint, ... }
        local Welds = {}

        -- a very high-friction physics material (mud: friction ~0.9, metal is
        -- ~0.4): a placed phone barely SLIPS anymore, so even if a weld did
        -- not take it does not slide down the wall / skid off its spot.
        -- the old material is remembered and restored on any pickup.
        local GRIP_MAT = "mud"

        local function RestoreMat(wep)
                if not (IsValid(wep) and wep.STTS_OldMat) then return end
                local p = wep:GetPhysicsObject()
                if IsValid(p) then p:SetMaterial(wep.STTS_OldMat) end
                wep.STTS_OldMat = nil
        end

        local function Unweld(wep)
                local cs = Welds[wep]
                if cs then
                        Welds[wep] = nil
                        for i = 1, #cs do
                                if IsValid(cs[i]) then cs[i]:Remove() end
                        end
                        if IsValid(wep) then wep.welds = nil end
                end
                RestoreMat(wep)
        end

        local function HasWelds(wep)
                local cs = Welds[wep]
                if not cs then return false end
                for i = 1, #cs do
                        if IsValid(cs[i]) then return true end
                end
                return false
        end

        -- find what a leaning phone touches and weld it there: the wall its
        -- top edge leans on + the ground / prop under it (unbreakable welds,
        -- pair nocollide so nothing jitters at the touch points). a phone
        -- lying flat (tilt < 5 degrees) stays a free prop. the floor is
        -- probed at THREE points along the phone, so a phone resting on an
        -- edge of a table / two props gets every contact welded. living
        -- things (players / hg ragdoll characters) are filtered out - a
        -- weld to a walking ragdoll would drag the phone around. hg
        -- coolhands removes wep.welds itself when the phone is grabbed;
        -- the hooks / sweep below cover the rest.
        local function WeldPhone(wep)
                if not IsValid(wep) then return end
                if IsValid(wep:GetOwner()) then return end -- held by someone
                local fwd = wep:GetAngles():Forward() -- +X = top of the phone
                local tiltDeg = math_deg(math_asin(math_Clamp(fwd.z, -1, 1)))
                if tiltDeg < 5 then return end -- lying flat: stays a free prop
                local M = G.Of(wep)
                if not M then return end
                local halfL = (M.Maxs.x - M.Mins.x) * 0.5
                local pos = wep:GetPos()
                local filt = { wep }
                for _, p in ipairs(player.GetAll()) do
                        filt[#filt + 1] = p
                        local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(p) or NULL
                        if IsValid(ch) then filt[#filt + 1] = ch end
                end
                local try = {}
                -- what the top edge leans against (wall / prop): one trace
                -- along the phone axis - the axis line crosses the wall
                -- exactly where the top edge touches it
                local trW = util.TraceLine({ start = pos + fwd * (halfL - 2), endpos = pos + fwd * (halfL + 3.5), filter = filt })
                if trW.Hit and IsValid(trW.Entity) and trW.Entity ~= wep then try[#try + 1] = trW.Entity end
                -- what it rests on (floor / table / prop): probes under the
                -- bottom edge, the center and the top edge
                for i = -1, 1 do
                        local from = pos + fwd * (halfL * 0.6 * i)
                        local trF = util.TraceLine({ start = from, endpos = from - Vector(0, 0, halfL + 8), filter = filt })
                        if trF.Hit and IsValid(trF.Entity) and trF.Entity ~= wep then try[#try + 1] = trF.Entity end
                end
                if #try == 0 then return end
                local done, cs = {}, {}
                for i = 1, #try do
                        local other = try[i]
                        if not done[other] then
                                done[other] = true
                                local c = constraint.Weld(wep, other, 0, 0, 0, true)
                                if IsValid(c) then cs[#cs + 1] = c end
                        end
                end
                if #cs > 0 then
                        Welds[wep] = cs
                        wep.welds = cs -- hg coolhands eats this on grab
                end
        end

        -- STICK: our own glue for leaning phones, fully independent of
        -- constraints. welds can silently die in the hg framework when
        -- physics objects get rebuilt, so a leaning phone is ALSO held by
        -- this loop: every tick it is put back into its placed pose and
        -- its velocities are zeroed. the phone is NEVER frozen (motion
        -- stays enabled the whole time) - it is simply glued to the pose
        -- it was placed in. a strong pull (something drags it more than
        -- ~6 units off the spot) breaks the glue and the phone is free
        -- again; gravity alone moves it fractions of a unit per tick, so
        -- it cannot shake the glue off by itself.
        local Stuck = {}

        local function Unstick(wep)
                Stuck[wep] = nil
                Unweld(wep) -- also restores the physics material
        end

        timer.Create("stts_phone_place_stick", 0, 0, function()
                if not next(Stuck) then return end
                -- hands grab first: the carried phone must be freed at once,
                -- not fought over
                for _, ply in ipairs(player.GetAll()) do
                        local ce = ply:GetNetVar("carryent")
                        if IsValid(ce) and Stuck[ce] then Unstick(ce) end
                end
                for wep, st in pairs(Stuck) do
                        if not IsValid(wep) then
                                Stuck[wep] = nil
                        elseif IsValid(wep:GetOwner()) then
                                Unstick(wep)
                        else
                                local p = wep:GetPhysicsObject()
                                if not IsValid(p) then
                                        Stuck[wep] = nil
                                elseif wep:GetPos():DistToSqr(st.pos) > 36 then
                                        Unstick(wep) -- yanked off: free it
                                else
                                        p:SetPos(st.pos)
                                        p:SetAngles(st.ang)
                                        p:SetVelocityInstantaneous(vector_origin)
                                        local av = p:GetAngleVelocity()
                                        if isvector(av) then p:AddAngleVelocity(-av) end
                                end
                        end
                end
        end)

        -- the client asks to park its phone in the preview pose it saw. this is a
        -- net message, NOT a concommand: a concommand named "stts_phone_place"
        -- collided with the client convar of the same name in the single engine
        -- command registry (listen servers / singleplayer) and broke both.
        net.Receive("stts_phone_place", function(_, ply)
                if not (IsValid(ply) and ply:Alive()) then return end
                if (ply.STTS_PlaceCD or 0) > CurTime() then return end
                if ply:InVehicle() then return end
                if hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) ~= ply then return end -- ragdolled / in a car
                local org = ply.organism
                if istable(org) and (org.otrub or org.canmove == false) then return end
                local wep = ply:GetActiveWeapon()
                if not (IsValid(wep) and wep:GetClass() == PHONE_CLASS) then return end

                local pos, ang = net.ReadVector(), net.ReadAngle()
                local comp = { pos.x, pos.y, pos.z, ang.p, ang.y, ang.r }
                for i = 1, 6 do
                        local v = comp[i]
                        if v == nil or v ~= v or math_abs(v) > 1e6 then return end -- no nan / inf
                end
                ang = Angle(math_Clamp(ang.p, -90, 90), ang.y % 360, math_Clamp(ang.r, -90, 90))

                if pos:DistToSqr(ply:EyePos()) > MAX_DIST * MAX_DIST then return end

                -- the spot must be reachable: nothing solid between the eyes and the phone
                local filt = {}
                for _, p in ipairs(player.GetAll()) do filt[#filt + 1] = p end
                filt[#filt + 1] = wep
                local tr = util.TraceLine({ start = ply:EyePos(), endpos = pos, mask = MASK_SHOT, filter = filt })
                if tr.Hit and tr.HitPos:DistToSqr(pos) > 100 then return end

                -- and not buried in the world (the top edge may touch the wall - it is allowed)
                local M = G.Of(wep)
                local L = M.Maxs.x - M.Mins.x
                local fwd = ang:Forward()
                if util.PointContents(pos) ~= CONTENTS_EMPTY then return end
                if util.PointContents(pos + fwd * (L * 0.25)) ~= CONTENTS_EMPTY then return end
                if util.PointContents(pos - fwd * (L * 0.25)) ~= CONTENTS_EMPTY then return end

                ply.STTS_PlaceCD = CurTime() + 0.5

                -- drop it EXACTLY like the radial menu does (same command = same checks,
                -- same animation, same hands swap, same E-to-pickup afterwards)
                wep.STTS_PlacePose = { pos = pos, ang = ang }
                ply:ConCommand("drop")

                -- if the drop was blocked the marker dies quietly
                timer.Simple(1, function()
                        if IsValid(wep) and wep.STTS_PlacePose and IsValid(wep:GetOwner()) then
                                wep.STTS_PlacePose = nil
                        end
                end)
        end)

        -- the moment the drop really happens: snap the phone into the preview pose
        hook.Add("PlayerDroppedWeapon", "stts_phone_place", function(owner, wep)
                if not (IsValid(wep) and wep.STTS_PlacePose) then return end
                local poseT = wep.STTS_PlacePose
                wep.STTS_PlacePose = nil
                wep:SetPos(poseT.pos)
                wep:SetAngles(poseT.ang)

                -- put the physics exactly into the preview pose the moment it
                -- exists, then leave the phone as a NORMAL prop: unfrozen, it
                -- just rests there (and can be nudged / picked up as usual).
                local id = "stts_phone_place_" .. wep:EntIndex()
                local tries = 0
                timer.Create(id, 0, 30, function()
                        tries = tries + 1
                        if not IsValid(wep) then timer.Remove(id) return end
                        if IsValid(wep:GetOwner()) then timer.Remove(id) return end -- picked back up
                        wep:SetPos(poseT.pos)
                        wep:SetAngles(poseT.ang)
                        local ph = wep:GetPhysicsObject()
                        if not IsValid(ph) then
                                if tries >= 30 then timer.Remove(id) end
                                return
                        end
                        timer.Remove(id)
                        ph:SetPos(poseT.pos)
                        ph:SetAngles(poseT.ang)
                        ph:SetVelocityInstantaneous(vector_origin)
                        local av = ph:GetAngleVelocity()
                        if isvector(av) then ph:AddAngleVelocity(-av) end
                        -- GRIP: swap the physics material to a high-friction
                        -- one for the whole time the phone sits placed, so it
                        -- does not slide down / skid around. remembered and
                        -- restored on any pickup.
                        if not wep.STTS_OldMat then wep.STTS_OldMat = ph:GetMaterial() or "default" end
                        ph:SetMaterial(GRIP_MAT)
                        -- SOFT PIN instead of freezing: for 0.2 s the physics
                        -- stay LIVE (motion is never disabled), but the pose
                        -- and velocity are reset every tick, so the phone
                        -- cannot twitch while the weld settles. Contacts keep
                        -- being solved during the pin, so there is no stored
                        -- -up bounce to kick the phone when it is released -
                        -- the classic EnableMotion(false) anchor is exactly
                        -- what made it jump and fall over before.
                        local pinId = "stts_phone_place_pin_" .. wep:EntIndex()
                        timer.Create(pinId, 0, 14, function()
                                if not IsValid(wep) then timer.Remove(pinId) return end
                                if IsValid(wep:GetOwner()) then RestoreMat(wep) timer.Remove(pinId) return end
                                local pp = wep:GetPhysicsObject()
                                if not IsValid(pp) then timer.Remove(pinId) return end
                                pp:SetPos(poseT.pos)
                                pp:SetAngles(poseT.ang)
                                pp:SetVelocityInstantaneous(vector_origin)
                                local pav = pp:GetAngleVelocity()
                                if isvector(pav) then pp:AddAngleVelocity(-pav) end
                        end)
                        sound.Play("SolidMetal.ImpactSoft", poseT.pos, 55, math_random(115, 130), 0.4)

                        -- the weld is made RIGHT at placement, the same tick
                        WeldPhone(wep)

                        -- STICK: glue a leaning phone to its pose from this
                        -- very tick on (the loop above holds it there every
                        -- tick, no freezing involved)
                        local sfwd = poseT.ang:Forward()
                        if math_deg(math_asin(math_Clamp(sfwd.z, -1, 1))) >= 5 then
                                Stuck[wep] = { pos = poseT.pos, ang = poseT.ang }
                        end

                        -- 0.2 s later the pin expires by itself and the phone
                        -- is a fully free prop. to stop Source physics from
                        -- bouncing / tipping it off its spot right after the
                        -- release, give it heavy damping that decays back to
                        -- normal over ~1.5 s - it stays UNANCHORED the whole
                        -- time, it just cannot jitter. if the welds did not
                        -- survive for some reason, remake them.
                        timer.Simple(0.2, function()
                                if not IsValid(wep) then return end
                                timer.Remove(pinId)
                                local p2 = wep:GetPhysicsObject()
                                if not IsValid(p2) then return end
                                p2:SetPos(poseT.pos)
                                p2:SetAngles(poseT.ang)
                                p2:SetVelocityInstantaneous(vector_origin)
                                local rav = p2:GetAngleVelocity()
                                if isvector(rav) then p2:AddAngleVelocity(-rav) end
                                p2:SetDamping(2, 10)
                                p2:Wake()
                                local dampId = "stts_phone_place_damp_" .. wep:EntIndex()
                                local steps = 0
                                timer.Create(dampId, 0.1, 15, function()
                                        if not IsValid(wep) then timer.Remove(dampId) return end
                                        if IsValid(wep:GetOwner()) then RestoreMat(wep) timer.Remove(dampId) return end
                                        local pd = wep:GetPhysicsObject()
                                        if not IsValid(pd) then timer.Remove(dampId) return end
                                        steps = steps + 1
                                        local k = 1 - steps / 15
                                        if k < 0 then k = 0 end
                                        pd:SetDamping(2 * k, 10 * k)
                                        pd:Wake()
                                end)
                                if not IsValid(wep:GetOwner()) and not HasWelds(wep) then
                                        WeldPhone(wep)
                                end

                                -- WATCHDOG: for the first ~3 s after placement
                                -- keep checking that a leaning phone still has
                                -- its welds - the hands / drop code can rebuild
                                -- the physics object while things settle, which
                                -- silently kills constraints. if the welds are
                                -- gone but the phone still touches something,
                                -- weld it again. WeldPhone only welds on real
                                -- contact, so this can never weld a phone that
                                -- fell over and lies flat.
                                local wdId = "stts_phone_place_wd_" .. wep:EntIndex()
                                timer.Create(wdId, 0.25, 12, function()
                                        if not IsValid(wep) then timer.Remove(wdId) return end
                                        if IsValid(wep:GetOwner()) then timer.Remove(wdId) return end
                                        if Welds[wep] then
                                                if HasWelds(wep) then return end
                                                Welds[wep] = nil -- dead constraints: re-probe
                                                wep.welds = nil
                                        end
                                        WeldPhone(wep)
                                end)
                        end)
                end)
        end)

        -- picking the glued / welded phone up must free it. hg coolhands
        -- removes wep.welds on grab; these cover the rest (physgun /
        -- gravgun / the phone being taken back into somebody's inventory).
        hook.Add("OnPhysgunPickup", "stts_phone_place_unweld", function(_, ent)
                if Welds[ent] or Stuck[ent] then Unstick(ent) end
        end)
        hook.Add("GravGunOnPickedUp", "stts_phone_place_unweld", function(_, ent)
                if Welds[ent] or Stuck[ent] then Unstick(ent) end
        end)
        hook.Add("GravGunPunt", "stts_phone_place_unweld", function(_, ent)
                if Welds[ent] or Stuck[ent] then Unstick(ent) end
        end)

        timer.Create("stts_phone_place_sweep", 0.25, 0, function()
                if not next(Welds) then
                        -- even with no welds around, placed phones may still
                        -- carry the grip material: give it back on pickup
                        for _, wep in ipairs(ents.FindByClass(PHONE_CLASS)) do
                                if IsValid(wep) and IsValid(wep:GetOwner()) and wep.STTS_OldMat then RestoreMat(wep) end
                        end
                        return
                end
                for wep, cs in pairs(Welds) do
                        if not IsValid(wep) then
                                Welds[wep] = nil
                        elseif IsValid(wep:GetOwner()) then
                                Unstick(wep) -- back in somebody's inventory
                        else
                                local alive = false
                                for i = 1, #cs do
                                        if IsValid(cs[i]) then alive = true break end
                                end
                                if not alive then
                                        Welds[wep] = nil
                                        wep.welds = nil
                                end
                        end
                end
                for wep in pairs(Stuck) do
                        if not IsValid(wep) then
                                Stuck[wep] = nil
                        elseif IsValid(wep:GetOwner()) then
                                Unstick(wep)
                        end
                end
                for _, wep in ipairs(ents.FindByClass(PHONE_CLASS)) do
                        if IsValid(wep) and IsValid(wep:GetOwner()) and wep.STTS_OldMat then RestoreMat(wep) end
                end
                for _, ply in ipairs(player.GetAll()) do
                        local ce = ply:GetNetVar("carryent")
                        if IsValid(ce) and (Welds[ce] or Stuck[ce]) then Unstick(ce) end
                end
        end)
end

--[[ fix54: stts_phone_botphoto (sv_phone_botphoto.lua): the server asks THIS game to take
     a picture for a bot (a bot has no client): rendered from the bot's eyes, uploaded, and
     nothing is kept here (no cache, not in your gallery): your TeleChat receives it from
     the bot like any other photo, a tap downloads it ]]
if SERVER then return end
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local CHUNK = G.PhotoChunk or 16000
local PW, PH = G.PhotoW or 576, G.PhotoH or 1024
local rt, prt, mat
local want

net.Receive("stts_phone_botshot", function()
	local token = net.ReadUInt(16)
	local pos, ang = net.ReadVector(), net.ReadAngle()
	want = {token = token, pos = pos, ang = ang, bot = net.ReadEntity()}
end)

local function Upload(token, jpg, prev)
	local total = math.ceil(#jpg / CHUNK)
	if total < 1 or total > 255 then return end
	local i = 0
	local name = "STTS_BotShotUp"
	timer.Remove(name)
	-- one part per tick: a burst of big reliable messages can overflow the channel
	timer.Create(name, 0.05, total, function()
		i = i + 1
		local part = string.sub(jpg, (i - 1) * CHUNK + 1, i * CHUNK)
		net.Start("stts_phone_botup")
			net.WriteUInt(token, 16)
			net.WriteUInt(i, 8)
			net.WriteUInt(total, 8)
			net.WriteUInt(#part, 16)
			net.WriteData(part, #part)
			if i == total then
				net.WriteUInt(prev and #prev or 0, 13)
				if prev and #prev > 0 then net.WriteData(prev, #prev) end
			end
		net.SendToServer()
	end)
end

hook.Add("PostRender", "STTS_PhoneBotShot", function()
	local w = want
	local SCR = STTS.PhoneScreen or {}
	if not w or SCR.InRV then return end
	want = nil
	rt = rt or GetRenderTargetEx("stts_phone_botshot", PW, PH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGB888)
	prt = prt or GetRenderTargetEx("stts_phone_botshot_p", 36, 64, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	mat = mat or CreateMaterial("stts_phone_botshot_m", "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1})
	-- the bot's own body / phone are not in its picture
	local hidden = {}
	local function Hide(e) if IsValid(e) and not e:GetNoDraw() then e:SetNoDraw(true) hidden[#hidden + 1] = e end end
	local bot = w.bot
	if IsValid(bot) then
		Hide(bot)
		if bot.GetActiveWeapon then Hide(bot:GetActiveWeapon()) end
		local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(bot)
		if ch ~= bot then Hide(ch) end
	end
	local fov = G.ZoomFov and G.ZoomFov(G.FovBack or 52, 1) or 52
	local view = {origin = w.pos, angles = w.ang, x = 0, y = 0, w = PW, h = PH, aspect = PW / PH, fov = fov, znear = 1.5, zfar = 8000,
		drawviewmodel = false, drawhud = false, drawmonitors = false, dopostprocess = false, bloomtone = false, drawviewer = true}
	local oldRV = SCR.InRV
	SCR.InRV = true
	render.PushRenderTarget(rt, 0, 0, PW, PH)
	local ok, err = pcall(function()
		render.Clear(0, 0, 0, 255, true, true)
		if STTS.PhoneView43 and STTS.PhoneView43.Render then STTS.PhoneView43.Render(view, rt, PW, PH)
		else render.RenderView(view) end
	end)
	local jpg = ok and render.Capture({format = "jpg", quality = 88, x = 0, y = 0, w = PW, h = PH, alpha = false}) or nil
	render.PopRenderTarget()
	SCR.InRV = oldRV
	for _, e in ipairs(hidden) do if IsValid(e) then e:SetNoDraw(false) end end
	if not ok then ErrorNoHalt("[phone] bot photo: " .. tostring(err) .. "\n") return end
	if not jpg or #jpg < 4 then return end
	-- the tiny blurred TeleChat preview (36 x 64)
	local prev
	render.PushRenderTarget(prt)
		render.Clear(0, 0, 0, 255)
		cam.Start2D()
			surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(0, 0, 36, 64)
		cam.End2D()
		prev = render.Capture({format = "jpg", quality = 55, x = 0, y = 0, w = 36, h = 64, alpha = false})
	render.PopRenderTarget()
	if prev and #prev > 4096 then prev = nil end
	Upload(w.token, jpg, prev)
end)

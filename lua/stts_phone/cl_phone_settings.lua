--[[---------------------------------------------------------------------------
	ZHUNTER phone - Settings app (client).
	home screen: the Settings icon (top left, like the first icon of an iPhone).
	  Settings (root, large title)  -> Airplane Mode (same as the Control Centre)
	                                -> Wi-Fi >                : switch + the network of the map (v19.2)
	                                -> Notifications >        : App Icon Badges
	                                -> Sounds & Haptics >     : volume, Ringtone >, Text Tone > (fix55: no Vibration)
	                                -> Focus (toggle)
	                                -> General >              : Name, Phone Number, Model Name, 24-Hour Time
	                                -> Display & Brightness > : Light / Dark, Accent Color, brightness
	                                -> Wallpaper >            : the lock screen wallpaper (fix60)
	  Ringtone / Text Tone -> list. tap = select + preview: the preview plays OUT
	               LOUD from the phone (server), the people around hear it like a call.
	the settings belong to the PHONE (NW2 vars, see sv_shooting_phone_settings.lua):
	everybody who looks at a phone sees ITS theme / accent, its
	ringtone is what rings when it is called, its text tone plays on a message.
	camera, call screen, photo viewer and the Control Centre stay dark (as on iOS).
	the palette is the shared table C of cl_shooting_phone_screen.lua: it is set
	for every phone right before that phone is drawn (SCR.Theme), colour objects
	are changed in place, so every reference to C.label / C.blue... follows.
---------------------------------------------------------------------------]]
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
STTS.PhoneScreen = SCR
local CLASS = "weapon_stts_phone"
local U = SCR.UI
if not U then return end -- the screen file failed to load
local C, W, H = U.C, U.W, U.H
local WHITE = Color(255, 255, 255)

--[[---------------------------------------------------------------------------
	palette: dark (the original look, exactly) / light (iOS light mode)
---------------------------------------------------------------------------]]
local DARK = {
	bg = Color(0, 0, 0), group = Color(0, 0, 0), cell = Color(28, 28, 30), home = Color(0, 0, 0),
	bg2 = Color(28, 28, 30), bg3 = Color(44, 44, 46), sep = Color(84, 84, 88, 170),
	label = Color(255, 255, 255), label2 = Color(235, 235, 245, 153), label3 = Color(235, 235, 245, 76),
	blue = Color(10, 132, 255), green = Color(48, 209, 88), red = Color(255, 69, 58),
	gray = Color(142, 142, 147), mono = Color(138, 142, 154), them = Color(38, 38, 41), bar = Color(20, 20, 22, 245),
	ink = Color(255, 255, 255, 255), hi = Color(70, 70, 74), edge = Color(66, 66, 70),
	fill = Color(57, 57, 61), field = Color(30, 30, 32),
}
local LIGHT = {
	bg = Color(255, 255, 255), group = Color(242, 242, 247), cell = Color(255, 255, 255), home = Color(236, 236, 241),
	bg2 = Color(242, 242, 247), bg3 = Color(229, 229, 234), sep = Color(60, 60, 67, 74),
	label = Color(0, 0, 0), label2 = Color(60, 60, 67, 153), label3 = Color(60, 60, 67, 76),
	blue = Color(0, 122, 255), green = Color(52, 199, 89), red = Color(255, 59, 48),
	gray = Color(142, 142, 147), mono = Color(166, 170, 182), them = Color(233, 233, 235), bar = Color(249, 249, 249, 245),
	ink = Color(0, 0, 0, 150), hi = Color(209, 209, 214), edge = Color(199, 199, 204),
	fill = Color(233, 233, 235), field = Color(227, 227, 233),
}
for key, c in pairs(DARK) do
	if not C[key] then C[key] = Color(c.r, c.g, c.b, c.a) end
end

local applied, appliedAcc
local curAcc = 1 -- accent colour of the phone being drawn (G.Accents)
local function Apply(k)
	k = math.Clamp(k or 0, 0, 1)
	local LS = SCR.LinState -- v19.2: what translucent colours sit on now (linear-light fix)
	if LS then LS.bg = Lerp(k, 0.05, 0.96) end
	if applied == k and appliedAcc == curAcc then return end
	applied, appliedAcc = k, curAcc
	for key, d in pairs(DARK) do
		local l, c = LIGHT[key], C[key]
		c.r = math.floor(Lerp(k, d.r, l.r) + 0.5)
		c.g = math.floor(Lerp(k, d.g, l.g) + 0.5)
		c.b = math.floor(Lerp(k, d.b, l.b) + 0.5)
		c.a = math.floor(Lerp(k, d.a, l.a) + 0.5)
	end
	local A = G.Accents and G.Accents[curAcc]
	if A then -- system tint
		local d, l, c = A[1], A[2], C.blue
		c.r = math.floor(Lerp(k, d.r, l.r) + 0.5)
		c.g = math.floor(Lerp(k, d.g, l.g) + 0.5)
		c.b = math.floor(Lerp(k, d.b, l.b) + 0.5)
	end
end
Apply(0)

--[[ v19.2: does this GMod blend translucent colours in linear light (sRGB write)? then
     white at 19 % over black looks like 47 % grey and the whole phone (Control Centre
     glass first of all) looks flat and washed out. a 16x16 render target with the format
     of the display gets white at 25 % over black: ~64 back = normal (gamma space), ~137 =
     linear light. measured once; the screen file then compensates every translucent
     colour (SCR.LinState). stts_phone_gamma_fix: -1 = auto (default), 0 = never, 1 = always ]]
local gammaCvar = CreateClientConVar("stts_phone_gamma_fix", "-1", true, false,
	"phone UI translucency: -1 = auto detect linear-light blending (washed out glass), 0 = off, 1 = force on", -1, 1)
local probe = {}
local function ProbeOne(r, g, b, a)
	render.PushRenderTarget(probe.rt)
		render.Clear(0, 0, 0, 255)
		cam.Start2D()
			surface.SetAlphaMultiplier(1)
			draw.NoTexture()
			surface.SetDrawColor(r, g, b, a)
			surface.DrawRect(-2048, -2048, 8192, 8192)
		cam.End2D()
		render.CapturePixels()
		local v = render.ReadPixel(8, 8)
	render.PopRenderTarget()
	return tonumber(v) or 0
end
-- call while rendering (the phones are drawn in PreRender): true = compensate
function SCR.LinBlend()
	local mode = gammaCvar:GetInt()
	if mode == 0 then return false elseif mode > 0 then return true end
	if probe.res == nil and RealTime() >= (probe.next or 0) then
		probe.res = false
		if render.CapturePixels and render.ReadPixel and GetRenderTargetEx then
			probe.rt = probe.rt or GetRenderTargetEx("stts_phone_gprobe19", 16, 16, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
			local half, ref = ProbeOne(255, 255, 255, 64), ProbeOne(128, 128, 128, 255)
			if ref > 8 then probe.res = half / ref > 0.75
			else -- nothing read back (render target not ready yet?): try again in a moment, a few times
				probe.tries = (probe.tries or 0) + 1
				if probe.tries < 5 then probe.res, probe.next = nil, RealTime() + 1 end
			end
		end
	end
	return probe.res == true
end
-- direct surface calls of this file: the same compensation as U.R / U.Round / U.T
local LC = U.LinCol or function(c) return c end

--[[ the other settings of a phone (same NW2 vars + defaults as the server).
     your own phone: the value you just tapped is predicted for a moment ]]
local NW = {
	accent = {"Accent", "int", 1}, tone = {"Tone", "str", G.ToneDefault},
	h24 = {"H24", "bool", true}, badge = {"Badge", "bool", true}, -- fix55: no vibration any more
	lkwp = {"LkWp", "int", 0}, -- fix60: the lock screen wallpaper (0 = automatic)
	hmwp = {"HmWp", "int", 0}, -- fix61: the home screen wallpaper (0 = the one of the lock screen)
	alock = {"ALock", "int", 0}, -- fix61: Auto-Lock (G.AutoLock: 0 = 30 seconds .. 6 = never)
}
local function Get(wep, key)
	local L = SCR.L
	local p = L and L.wep == wep and L.setPred and L.setPred[key]
	if p and RealTime() - p.at < 1.5 then return p.v end
	local f = NW[key]
	if f[2] == "int" then return wep:GetNW2Int(f[1], f[3])
	elseif f[2] == "bool" then return wep:GetNW2Bool(f[1], f[3]) end
	return wep:GetNW2String(f[1], f[3])
end
SCR.SettingOf = Get
local function Set(wep, st, key, v)
	if not st.own then return end
	local L = SCR.L
	L.setPred = L.setPred or {}
	L.setPred[key] = {v = v, at = RealTime()}
	if isbool(v) then v = v and "1" or "0" end
	U.Act(key, tostring(v))
end
local function AccentOf(wep) return math.Clamp(Get(wep, "accent"), 1, #G.Accents) end
function SCR.Clock(wep)
	if not IsValid(wep) or Get(wep, "h24") then return os.date("%H:%M") end
	return (string.gsub(os.date("%I:%M"), "^0", ""))
end
function SCR.NoBadge(wep) return IsValid(wep) and not Get(wep, "badge") end


-- theme of a phone (0 dark / 1 light). your own phone: predicted for a moment after a tap
local function Target(wep)
	local L = SCR.L
	if L and L.wep == wep and L.themeAt and RealTime() - L.themeAt < 1.5 then return L.theme end
	return wep:GetNW2Int("Theme", G.THEME_DARK) == G.THEME_LIGHT and 1 or 0
end
SCR.ThemeTarget = Target

local THEME_DUR = 0.45
local function Smooth(p) return p * p * (3 - 2 * p) end

-- screens that are dark on every iPhone, whatever the theme
local function ForcedDark(st)
	local app = st.app
	return app == G.APP_CALL or app == G.APP_CAMERA or (app == G.APP_GALLERY and st.galV == 4)
		or (SCR.ZMForcedDark and SCR.ZMForcedDark(st)) or false -- fix54: ZMusic Now Playing
end

-- v19.4: how much the status bar sits on the Control Centre (0..1). the dim behind it grows
-- with the pull (whole display), so a light status bar turns white step by step with it
local function ShadeK(wep)
	local p = math.Clamp(((wep.STTS_CCy or 0) / G.RTH - 0.2) / 0.5, 0, 1)
	return p * p * (3 - 2 * p)
end

-- the Control Centre is always dark glass (wrapped lazily: the shade file loads after this one)
local function WrapShade()
	local fn = SCR.DrawShade
	if not fn or fn == SCR.STTS_ShadeWrap then return end
	SCR.STTS_ShadeWrap = function(wep, st, btns)
		Apply(0)
		return fn(wep, st, btns)
	end
	SCR.DrawShade = SCR.STTS_ShadeWrap
end

-- right before a phone is drawn: its palette (smooth light <-> dark cross-fade)
function SCR.Theme(wep, st)
	WrapShade()
	local LS = SCR.LinState
	if LS and SCR.LinBlend then LS.on = SCR.LinBlend() end
	curAcc = AccentOf(wep)
	local want = Target(wep)
	local a = wep.STTS_Th
	if not a then
		a = {k = want, from = want, to = want, t0 = 0}
		wep.STTS_Th = a
	end
	if a.to ~= want then a.from, a.to, a.t0 = a.k, want, RealTime() end
	local p = math.Clamp((RealTime() - a.t0) / THEME_DUR, 0, 1)
	a.k = Lerp(Smooth(p), a.from, a.to)
	wep.STTS_ThemeMove = p < 1
	wep.STTS_ThK = a.k
	Apply(a.k)
end
function SCR.ThemePush(wep, st)
	if ForcedDark(st) and (wep.STTS_ThK or 0) > 0 then Apply(0) return true end
end
function SCR.ThemePop(wep) Apply(wep.STTS_ThK or 0) end
-- chrome on top of the apps: 1 = home bar, 2 = status bar + island, 3 = done
function SCR.ThemeOverlay(wep, st, phase)
	local k = wep.STTS_ThK or 0
	if phase == 1 then Apply(ForcedDark(st) and 0 or k)
	elseif phase == 2 then -- fix55: white status bar over a sheet / a ringing alarm (cl_phone_clock.lua)
		Apply((ForcedDark(st) or (SCR.StatusDark and SCR.StatusDark(wep, st))) and 0 or k * (1 - ShadeK(wep)))
	else Apply(k) end
end

--[[---------------------------------------------------------------------------
	ringtones / text tones: the one of a phone, preview
---------------------------------------------------------------------------]]
local function RingOf(wep)
	local L = SCR.L
	if L and L.wep == wep and L.ringAt and RealTime() - L.ringAt < 1.5 then return G.Ring(L.ring) end
	return G.Ring(wep:GetNW2String("Ring", ""))
end
SCR.RingOf = RingOf
local function ToneOf(wep) return G.Tone(Get(wep, "tone")) end
SCR.ToneOf = ToneOf

--[[ the preview itself plays on the server, from the phone (CreateSound on the
     holder, like a ringing call): here only the little equalizer + stopping it ]]
local prev = {}
local function StopPreview(send)
	local was = prev.id ~= nil
	prev.id, prev.app, prev.untilT = nil, nil, nil
	if send and was then U.Act("prevstop", "") end
end
local function Preview(wep, r, app)
	local v = SCR.Level and SCR.Level(wep, "vol") or 1
	if not r.file or v <= 0.005 then StopPreview(false) return end -- volume 0 = silent, like a muted phone
	prev.id, prev.app, prev.untilT = r.id, app, RealTime() + math.min(r.len or 10, 30)
end
SCR.StopRingPreview = function() StopPreview(true) end

hook.Add("Think", "STTS_PhoneSettingsPreview", function()
	if not prev.id then return end
	local L = SCR.L
	local lp = LocalPlayer()
	local w = IsValid(lp) and lp:Alive() and lp:GetActiveWeapon()
	local ok = L and L.raised and L.app == prev.app and IsValid(w) and w:GetClass() == CLASS and w == L.wep
	if not ok then StopPreview(true) return end
	if RealTime() > (prev.untilT or 0) then StopPreview(false) end
end)

--[[---------------------------------------------------------------------------
	drawing helpers
---------------------------------------------------------------------------]]
local settingsIcon = Material("stts/ios_settings.png", "smooth mips")
local speakerMat = Material("stts/cc_speaker.png", "smooth mips")

local function Check(x, y, s, col, th)
	U.Line(x - s, y, x - s * 0.35, y + s * 0.65, th or 3.5, col)
	U.Line(x - s * 0.35, y + s * 0.65, x + s, y - s * 0.75, th or 3.5, col)
end
-- v19.2 (Wi-Fi): iOS activity indicator (8 spokes, the bright one goes round), padlock, Wi-Fi fan
local function Spinner(x, y, r, col)
	local n = 8
	local head = math.floor(RealTime() * 12) % n
	for i = 0, n - 1 do
		local a = math.rad(i * 360 / n - 90)
		local fade = ((head - i) % n) / n
		local c = Color(col.r, col.g, col.b, (col.a or 255) * (1 - fade * 0.82))
		local ca, sa = math.cos(a), math.sin(a)
		U.Line(x + ca * r * 0.48, y + sa * r * 0.48, x + ca * r, y + sa * r, math.max(2.5, r * 0.24), c)
	end
end
local function Lock(x, y, col)
	U.Round(3, x - 8, y - 2, 16, 12, col)
	if U.Arc then U.Arc(x, y - 2, 6, 2.4, 180, 360, col, 10) end
end
-- v19.3: lvl = strength 1..3 (nil = full): the bright part over the whole fan dimmed, like iOS
local FAN = {Material("stts/cc_wifi1.png", "smooth mips"), Material("stts/cc_wifi2.png", "smooth mips")}
local function WifiGlyph(x, y, s, col, lvl)
	local m = SCR.WifiMat
	local part = lvl and lvl < 3 and FAN[math.max(lvl, 1)]
	local dim = part and Color(col.r, col.g, col.b, (col.a or 255) * 0.3)
	if m and not m:IsError() and not (part and part:IsError()) then
		surface.SetMaterial(m) surface.SetDrawColor(LC(dim or col))
		surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
		if part then
			surface.SetMaterial(part) surface.SetDrawColor(LC(col))
			surface.DrawTexturedRect(x - s / 2, y - s / 2, s, s)
		end
		return
	end
	local by = y + s * 0.3 -- content not mounted yet: dot + two arcs
	U.Circle(x, by, math.max(2, s * 0.09), col)
	if U.Arc then for i = 1, 2 do U.Arc(x, by, s * (0.18 + i * 0.2), s * 0.1, 225, 315, (part and i >= lvl) and dim or col, 10) end end
end
U.Check, U.Spinner, U.Lock, U.WifiGlyph = Check, Spinner, Lock, WifiGlyph -- the Control Centre menu draws with them too
-- small iOS settings tile: coloured rounded square + white glyph
local GLYPH
local ICON = {} -- materials/stts/set_*.png (fix60: the real iOS 26 Settings icons, 128 x 128)
local function Tile(x, y, s, col, glyph, arg, icon)
	if icon then
		local m = ICON[icon]
		if m == nil then m = Material("stts/set_" .. icon .. ".png", "smooth mips") ICON[icon] = m end
		if not m:IsError() then
			surface.SetMaterial(m) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(x, y, s, s)
			return
		end
	end
	-- content not mounted yet: coloured tile + drawn glyph
	U.Round(s * 0.24, x, y, s, s, col)
	local fn = GLYPH and GLYPH[glyph]
	if fn then fn(x + s / 2, y + s / 2, arg) end
end

-- the little phone in "Appearance" (light = 1 / dark = 0), like iOS Display & Brightness
local function Mockup(x, y, w, h, light, ring)
	local bgc = light and Color(242, 242, 247) or Color(0, 0, 0)
	local card = light and Color(255, 255, 255) or Color(44, 44, 46)
	local fg = light and Color(0, 0, 0, 210) or Color(255, 255, 255, 225)
	local dim = light and Color(60, 60, 67, 90) or Color(235, 235, 245, 80)
	if ring > 0.01 then U.Round(22, x - 5, y - 5, w + 10, h + 10, Color(C.blue.r, C.blue.g, C.blue.b, 255 * ring)) end
	U.Round(19, x - 2, y - 2, w + 4, h + 4, Color(120, 120, 128, 120)) -- frame
	U.Round(17, x, y, w, h, bgc)
	U.Round(4, x + w / 2 - 17, y + 8, 34, 9, Color(0, 0, 0)) -- island
	U.T("9:41", "STTS_I_Cap", x + 22, y + 13, fg)
	U.Round(4, x + 12, y + 36, w * 0.52, 12, fg) -- large title
	U.Round(10, x + 10, y + 60, w - 20, 82, card)
	for i = 0, 2 do
		local ry = y + 70 + i * 25
		U.Circle(x + 24, ry + 5, 7, i == 0 and C.blue or (i == 1 and Color(52, 199, 89) or Color(255, 149, 0)))
		U.Round(3, x + 37, ry + 2, w * 0.44, 7, dim)
	end
	U.Round(10, x + 10, y + 152, w - 20, 34, card)
	U.Round(3, x + 20, y + 166, w * 0.36, 7, dim)
	U.Round(2, x + w / 2 - 22, y + h - 9, 44, 4, fg) -- home bar
end

-- iOS switch (k = 0 off .. 1 on, animated). the knob stretches while the finger is on it
local function Switch(x, y, k, press)
	local w, h = 80, 48
	k = math.Clamp(k, 0, 1)
	local off = C.fill or C.bg3
	local on = C.green
	local col = Color(Lerp(k, off.r, on.r), Lerp(k, off.g, on.g), Lerp(k, off.b, on.b))
	U.Round(h / 2, x, y, w, h, col)
	local r = h / 2 - 3
	local kw = r * 2 + (press or 0) * 10
	local kx = x + 3 + (w - 6 - kw) * k
	U.Round(r, kx, y + 4, kw, r * 2, Color(0, 0, 0, 30))
	U.Round(r, kx, y + 3, kw, r * 2, WHITE)
end

-- white glyphs for the setting tiles (drawn, no emoji font needed). x, y = centre
GLYPH = {}
function GLYPH.speaker(x, y, slash)
	if not speakerMat:IsError() then
		surface.SetMaterial(speakerMat) surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(x - 13, y - 13, 26, 26)
	else
		U.Round(2, x - 10, y - 5, 8, 10, WHITE)
		if U.Tri then U.Tri(x - 4, y - 5, x + 6, y - 12, x + 6, y + 12, WHITE) end
	end
	if slash then U.Line(x - 12, y - 12, x + 12, y + 12, 3, WHITE) end
end
function GLYPH.bubble(x, y)
	U.Round(8, x - 13, y - 11, 26, 19, WHITE)
	if U.Tri then U.Tri(x - 8, y + 6, x - 2, y + 6, x - 10, y + 13, WHITE) end
end
function GLYPH.clock(x, y)
	U.Circle(x, y, 13, WHITE)
	U.Line(x, y, x, y - 8, 2.5, C.gray)
	U.Line(x, y, x + 6, y + 3, 2.5, C.gray)
end
function GLYPH.badge(x, y)
	U.Round(5, x - 12, y - 9, 20, 20, WHITE)
	U.Circle(x + 8, y - 9, 6, WHITE)
end

--[[---------------------------------------------------------------------------
	apps (iOS Settings: a root list + one pushed page per panel, like the real app)
---------------------------------------------------------------------------]]
local ID_ICON, ID_LIGHT, ID_DARK = 5, 221, 222
local ID_ACC0 = 199         -- accent dots 200..207
local ROW0 = 230            -- sound list rows 231.. (hovered id travels in 8 bits)
local STEP = 80             -- scroll unit (px); the scroll zone uses the same, so dragging is 1:1
local M, RH = 16, 76        -- card side margin, row height

-- extra fonts for the pages (SF Pro proportions -> Roboto)
surface.CreateFont("STTS_SET_Large", {font = "Roboto", size = 52, weight = 700, antialias = true, extended = true})
surface.CreateFont("STTS_SET_Nav", {font = "Roboto", size = 27, weight = 600, antialias = true, extended = true})
surface.CreateFont("STTS_SET_Sec", {font = "Roboto", size = 22, weight = 500, antialias = true, extended = true})
surface.CreateFont("STTS_SET_Ftr", {font = "Roboto", size = 22, weight = 400, antialias = true, extended = true})
surface.CreateFont("STTS_SET_Val", {font = "Roboto", size = 26, weight = 400, antialias = true, extended = true})

local function SetTheme(wep, st, v)
	if not st.own then return end
	local L = SCR.L
	if Target(wep) == v then return end
	L.theme, L.themeAt = v, RealTime()
	U.Act("theme", tostring(v))
end
SCR.SetTheme = SetTheme -- fix61: the Dark Mode control of the Control Centre

-- a Control Centre switch (Wi-Fi / rotation lock / Focus), predicted on your own phone
local function ToggleCC(wep, st, key)
	if not st.own then return end
	local L = SCR.L
	L.ccOn, L.ccAt = L.ccOn or {}, L.ccAt or {}
	local on = not (st.cc and st.cc[key])
	L.ccOn[key] = on
	L.ccAt[key] = RealTime()
	-- fix61: Rotation Lock on = back to portrait at once (predicted, the server does the same)
	if key == "rotlock" and on and L.wep == wep then L.land, L.landAt = false, RealTime() end
	if key == "wifi" then
		L.wifiOnAt = on and RealTime() or nil -- the list "scans" for a moment
		-- Wi-Fi off = the phone leaves the network (the server forgets it too)
		if not on then L.ccOn.join, L.ccAt.join, L.wjoinAt = false, RealTime(), nil end
	end
	U.Act(key)
end
SCR.ToggleCC = ToggleCC

--[[ v19.2: Wi-Fi. there is one network: the map (gm_flatgrass...). a phone is connected
     while NW2 "NoJoin" is false (new phones are); switching Wi-Fi off leaves it, then you
     pick it again (Control Centre menu / Settings > Wi-Fi): "Connecting..." for a moment,
     then the check mark and the Wi-Fi fan in the status bar ]]
local JOIN_T = 1.4
function SCR.WifiNet()
	local m = game and game.GetMap and game.GetMap() or ""
	return m ~= "" and m or "Wi-Fi"
end
-- "off" / "join" (connecting, your own phone) / "on" (connected) / "none" (on, not connected)
function SCR.WifiState(wep, st)
	local cc = st and st.cc or {}
	if not cc.wifi then return "off" end
	local L = SCR.L
	if st.own and L and L.wjoinAt and RealTime() - L.wjoinAt < JOIN_T then return "join" end
	return cc.join and "on" or "none"
end
function SCR.WifiJoin(wep, st)
	if not st.own or SCR.WifiState(wep, st) ~= "none" then return end
	local L = SCR.L
	L.wjoinAt = RealTime()
	L.ccOn, L.ccAt = L.ccOn or {}, L.ccAt or {}
	L.ccOn.join, L.ccAt.join = true, RealTime()
	U.Act("wjoin")
end
--[[ v19.3: signal where the phone is (G.NetQuality: zones of the map, the same for everybody,
     every time). 0..4 bars, looked up twice a second; it only changes when the place is
     clearly better / worse (no flicker on the border of two zones). the Wi-Fi fan follows:
     0-1 bars = 1 arc, 2-3 = 2, 4 = 3. only a picture: calls / messages work the same ]]
function SCR.NetBars(wep)
	local n = wep.STTS_Net
	local now = RealTime()
	if n and now < n.t then return n.bars end
	local own = wep:GetOwner()
	local pos = IsValid(own) and own:GetPos() or wep:GetPos()
	local want = (G.NetQuality and G.NetQuality(pos) or 1) * 4
	if not n then
		n = {bars = math.Clamp(math.Round(want), 0, 4)}
		wep.STTS_Net = n
	elseif math.abs(want - n.bars) > 0.6 then
		n.bars = math.Clamp(math.Round(want), 0, 4)
	end
	n.t = now + 0.5
	return n.bars
end
function SCR.WifiLevel(wep)
	local b = SCR.NetBars(wep)
	return b >= 4 and 3 or (b >= 2 and 2 or 1)
end
local function TogglePlane(wep, st)
	if not st.own then return end
	local L = SCR.L
	L.plane, L.planeAt = not st.plane, RealTime()
	U.Act("plane")
end

-- a tappable area inside the scrolling page: only its visible part
local function RegIn(btns, id, x, y, w, h, top, bottom, fn)
	local ya, yb = math.max(y, top), math.min(y + h, bottom)
	if yb - ya > 8 then U.Reg(btns, id, x, ya, w, yb - ya, fn) end
end
local function RowHover(wep, st, id, x, y, w, h, r, first, last)
	local k = U.HoverK(wep, id, st.sel == id)
	if k <= 0.01 then return end
	local col = SCR.Ink((U.Pressed(wep, st, id) and 46 or 22) * k)
	if first or last then
		r = math.max(0, math.floor(math.min(r, w / 2, h / 2)))
		draw.RoundedBoxEx(r, x, y, w, h, LC(col), first, first, last, last)
	else
		U.R(x, y, w, h, col)
	end
end

-- word wrap for footers (returns the lines)
local function WrapLines(text, font, width)
	surface.SetFont(font)
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		local try = line == "" and word or (line .. " " .. word)
		if surface.GetTextSize(try) > width and line ~= "" then lines[#lines + 1] = line line = word
		else line = try end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

-- a horizontal slider inside a cell (volume / brightness). the finger drags it (LMB held)
local function HSlider(btns, wep, st, id, x, y, w, key, loMat, hiMat, visible)
	local v = SCR.Level and SCR.Level(wep, key) or 1
	local pad = 46
	local tx, tw = x + pad, w - pad * 2
	if visible then
		local b = U.Reg(btns, id, x - 4, y - 26, w + 8, 52, nil)
		b.sx, b.sw = tx, tw
		b.slider = function(val) if st.own and SCR.SetLevel then SCR.SetLevel(wep, key, val) end end
	end
	local k = U.HoverK(wep, id, st.sel == id)
	U.Round(3, tx, y - 3, tw, 6, C.fill or C.bg3)
	if v > 0 then U.Round(3, tx, y - 3, tw * v, 6, C.blue) end
	local kx, kr = tx + tw * v, 15 + 2 * k
	U.Circle(kx, y + 1.5, kr + 1, Color(0, 0, 0, 40))
	U.Circle(kx, y, kr, WHITE)
	local gl = {{loMat, x + 20, 0.62}, {hiMat, x + w - 20, 0.95}}
	for _, g in ipairs(gl) do
		if g[1] and not g[1]:IsError() then
			local s = 28 * g[3]
			surface.SetMaterial(g[1]) surface.SetDrawColor(LC(C.label2))
			surface.DrawTexturedRect(g[2] - s / 2, y - s / 2, s, s)
		end
	end
end

-- fix60: Settings > Wallpaper (sizes of its cards, see DrawWpCur / DrawWpGrid)
local WP_PW, WP_PH, WP_PR = 132, 293, 18              -- the big previews (432 x 960 scaled)
local WP_TW, WP_TH, WP_TR = 78, 173, 11               -- a choice
local WP_COLS, WP_ROW, WP_TOP = 4, 227, 20
local WP_GAP = (W - 2 * M - WP_COLS * WP_TW) / (WP_COLS + 1)
local WP_CUR_H = 24 + WP_PH + 88
-- fix61: ids of this page only (no other page uses 100..124 / 178..179): the choices
-- 100 + wallpaper (0..24), the two "Current" previews (which screen the choices are for)
local ID_WP0, ID_WPT_LOCK, ID_WPT_HOME = 100, 178, 179
local function WpGridH(n) return WP_TOP + math.ceil(math.max(n, 1) / WP_COLS) * WP_ROW + 8 end
local ID_AL0 = 180                                    -- fix61: Auto-Lock rows 180..186

--[[ the generic page: large / inline title, grouped sections, smooth scroll, nav bar.
     sections (content space, top of the first card at y0):
       {hdr=, ftr=, rows={...}}                 a group of rows
       {custom="profile"/"appearance"/"accents"/"slider"/"wpcur"/"wpgrid", ...}
     a row: {id=, label=, value=, sw=bool, info=bool, tile={col,glyph,arg,icon}, action=} ]]
local function Measure(secs)
	local y, place = 0, {}
	for i, sec in ipairs(secs) do
		y = y + (i == 1 and 8 or (sec.hdr and 20 or 44))
		local p = {hdrY = nil, cardY = 0, cardH = 0, ftrY = nil, ftrLines = nil}
		if sec.hdr then p.hdrY = y + 15 y = y + 40 end
		p.cardY = y
		local ch
		local c = sec.custom
		if c == "profile" then ch = 92
		elseif c == "appearance" then ch = 322
		elseif c == "accents" then ch = 84
		elseif c == "slider" then ch = 64
		elseif c == "wpcur" then ch = WP_CUR_H
		elseif c == "wpgrid" then ch = WpGridH(#(sec.ids or {}))
		else ch = #sec.rows * RH end
		p.cardH = ch
		y = y + ch
		if sec.ftr then
			p.ftrLines = WrapLines(sec.ftr, "STTS_SET_Ftr", W - 32 - 36)
			p.ftrY = y + 14
			y = y + 14 + #p.ftrLines * 26
		end
		place[i] = p
	end
	return y + 48, place
end

local function DrawRows(wep, st, btns, sec, p, o, top, bottom)
	local n = #sec.rows
	for i, r in ipairs(sec.rows) do
		local y = p.cardY + (i - 1) * RH + o
		-- fix61: a row without an action (Name / Phone Number / Model Name) is not a button
		if r.action then
			RegIn(btns, r.id, M, y, W - 2 * M, RH, top, bottom, r.action)
			RowHover(wep, st, r.id, M, y, W - 2 * M, RH, 20, i == 1, i == n)
		end
		local tx = M + 14
		if r.net then
			-- v19.2: a Wi-Fi network: check mark (connected) / spinner (connecting), name, padlock + fan
			local ry = y + RH / 2
			if r.check then Check(M + 34, ry, 9, C.blue, 3.5) elseif r.spin then Spinner(M + 34, ry, 11, C.label2) end
			tx = M + 64
			U.T(U.Fit(r.label, "STTS_I_Body", W - tx - 110), "STTS_I_Body", tx, ry, C.label, TEXT_ALIGN_LEFT)
			Lock(W - M - 76, ry, C.label)
			WifiGlyph(W - M - 38, ry, 26, C.label, SCR.WifiLevel(wep))
			if i < n then U.R(tx, y + RH - 1, W - tx - 14, 1, C.sep) end
			continue
		end
		if r.tile then
			local t = r.tile
			Tile(M + 14, y + (RH - 44) / 2, 44, t.col, t.glyph, t.arg, t.icon)
			tx = M + 14 + 44 + 14
		end
		U.T(r.label, "STTS_I_Body", tx, y + RH / 2, C.label, TEXT_ALIGN_LEFT)
		if r.mark ~= nil then
			-- fix61: a choice of a list (Auto-Lock): the check mark on the right
			if r.mark then Check(W - M - 34, y + RH / 2, 9, C.blue, 3.5) end
		elseif r.sw ~= nil then
			local pk = U.HoverK(wep, "swp" .. r.id, U.Pressed(wep, st, r.id))
			Switch(W - M - 14 - 80, y + RH / 2 - 24, U.SpringK and U.SpringK(wep, "sw" .. r.id, r.sw, 0.3, 0.92) or U.HoverK(wep, "sw" .. r.id, r.sw), pk)
		else
			local vx = W - (r.chev == false and 32 or 52)
			if r.value and r.value ~= "" then
				U.T(U.Fit(r.value, "STTS_SET_Val", W - tx - 120), "STTS_SET_Val", vx, y + RH / 2, C.label2, TEXT_ALIGN_RIGHT)
			end
			if r.chev ~= false then U.Chevron(W - 34, y + RH / 2, 8, "right", C.label3, 3.5) end
		end
		if i < n then U.R(tx, y + RH - 1, W - tx - 14, 1, C.sep) end
	end
end

local function DrawProfile(wep, st, p, o, btns, top, bottom, sec)
	local y = p.cardY + o
	-- fix61: the card has a chevron, so it is a button now (it was never registered): -> General
	local r = sec and sec.rows and sec.rows[1]
	if r and r.action then
		RegIn(btns, r.id, M, y, W - 2 * M, p.cardH, top, bottom, r.action)
		RowHover(wep, st, r.id, M, y, W - 2 * M, p.cardH, 20, true, true)
	end
	local name = wep:GetNWString("STTS_PName", "")
	if name == "" then name = "Phone" end
	U.Avatar(name, st.num, M + 46, y + 46, 30)
	U.T(U.Fit(name, "STTS_I_BodyB", W - 180), "STTS_I_BodyB", M + 92, y + (st.num ~= "" and 34 or 46), C.label, TEXT_ALIGN_LEFT)
	if st.num ~= "" then U.T(st.num, "STTS_I_Sub", M + 92, y + 62, C.label2, TEXT_ALIGN_LEFT) end
	U.Chevron(W - 34, y + 46, 8, "right", C.label3, 3.5)
end

local function DrawAppearance(wep, st, p, o, btns, top, bottom)
	local cy, ch = p.cardY + o, p.cardH
	local cur = Target(wep)
	local mw, mh = 112, 198
	for i, opt in ipairs({{ID_LIGHT, 1, "Light"}, {ID_DARK, 0, "Dark"}}) do
		local cx = i == 1 and W * 0.3 or W * 0.7
		local id, v = opt[1], opt[2]
		RegIn(btns, id, cx - 90, cy + 8, 180, ch - 16, top, bottom, function() SetTheme(wep, st, v) end)
		local k = U.HoverK(wep, id, st.sel == id)
		if k > 0.01 then U.Round(18, cx - 84, cy + 10, 168, ch - 20, SCR.Ink(18 * k)) end
		local on = U.HoverK(wep, "thsel" .. v, cur == v)
		local sc = U.PopScale(wep, "th" .. v, st.sel == id, U.Pressed(wep, st, id))
		local w2, h2 = mw * sc, mh * sc
		Mockup(cx - w2 / 2, cy + 26 + (mh - h2) / 2, w2, h2, v == 1, on)
		U.T(opt[3], "STTS_I_Body", cx, cy + 254, C.label)
		local ry = cy + 292
		if on > 0.5 then U.Circle(cx, ry, 15, C.blue) Check(cx, ry, 7, WHITE, 3)
		else U.Circle(cx, ry, 15, C.gray) U.Circle(cx, ry, 13, C.cell) end
	end
end

local function DrawAccents(wep, st, p, o, btns, top, bottom)
	local ay = p.cardY + o
	local acc = AccentOf(wep)
	local k0 = Target(wep)
	for i, A in ipairs(G.Accents) do
		local x, y = 48 + (i - 1) * 48, ay + 42
		local id = ID_ACC0 + i
		RegIn(btns, id, x - 24, y - 24, 48, 48, top, bottom, function() Set(wep, st, "accent", i) end)
		local sc = U.PopScale(wep, "acc" .. i, st.sel == id, U.Pressed(wep, st, id))
		local col = Color(Lerp(k0, A[1].r, A[2].r), Lerp(k0, A[1].g, A[2].g), Lerp(k0, A[1].b, A[2].b))
		local on = U.HoverK(wep, "accsel" .. i, acc == i)
		if on > 0.01 then U.Circle(x, y, 22, Color(col.r, col.g, col.b, 255 * on)) U.Circle(x, y, 19, C.cell) end
		U.Circle(x, y, 16 * sc, col)
	end
end

local soundLo = Material("stts/cc_speaker.png", "smooth mips")
local cciSun = Material("stts/cc_sun.png", "smooth mips")

--[[ fix60: Settings > Wallpaper. fix61: "Current" = the lock screen AND the home screen
     side by side, a tap on one of them = the choices below are for that screen (blue
     ring). the choices come in groups (iPhone / Pixel / Galaxy / Xiaomi) ]]
local function WpTarget(st)
	local L = SCR.L
	return (st.own and L and L.wpTarget == "home") and "home" or "lock"
end
local function DrawWpCur(wep, st, p, o, btns, top, bottom)
	local LK = STTS.PhoneLock
	local cy = p.cardY + o
	local tgt = WpTarget(st)
	for i, it in ipairs({{ID_WPT_LOCK, "lock", "Lock Screen"}, {ID_WPT_HOME, "home", "Home Screen"}}) do
		local cx = i == 1 and W * 0.3 or W * 0.7
		local id, home = it[1], it[2] == "home"
		local x, y = cx - WP_PW / 2, cy + 24
		RegIn(btns, id, cx - 96, cy + 8, 192, p.cardH - 16, top, bottom, function()
			if st.own and SCR.L then SCR.L.wpTarget = it[2] end
		end)
		local hk = U.HoverK(wep, id, st.sel == id)
		if hk > 0.01 then U.Round(18, cx - 90, cy + 10, 180, p.cardH - 20, SCR.Ink(18 * hk)) end
		local on = U.HoverK(wep, "wpt" .. it[2], tgt == it[2])
		if on > 0.01 then
			U.Round(WP_PR + 6, x - 6, y - 6, WP_PW + 12, WP_PH + 12, Color(C.blue.r, C.blue.g, C.blue.b, 255 * on))
			U.Round(WP_PR + 3, x - 3, y - 3, WP_PW + 6, WP_PH + 6, C.cell)
		end
		if LK and LK.Preview then
			LK.Preview(wep, nil, x, y, WP_PW, WP_PH, WP_PR, true, home)
			if U.RoundRim then U.RoundRim(WP_PR + 1, x - 1, y - 1, WP_PW + 2, WP_PH + 2, 1, C.sep) end
		else
			U.Round(WP_PR, x, y, WP_PW, WP_PH, C.gray)
		end
		U.T(it[3], "STTS_I_Body", cx, y + WP_PH + 30, tgt == it[2] and C.blue or C.label)
		local name = LK and LK.WallName and LK.WallName(wep, nil, home, true) or "Automatic"
		U.T(U.Fit(name, "STTS_I_Cap", 164), "STTS_I_Cap", cx, y + WP_PH + 60, C.label2)
	end
end
local function DrawWpGrid(wep, st, sec, p, o, btns, top, bottom)
	local LK = STTS.PhoneLock
	if not LK or not LK.WALLS or not sec.ids then return end
	local home = WpTarget(st) == "home"
	local cur
	if home then cur = LK.HomeChoice and LK.HomeChoice(wep) or 0 else cur = LK.Choice and LK.Choice(wep) or 0 end
	local key = home and "hmwp" or "lkwp"
	for j, i in ipairs(sec.ids) do
		local col, row = (j - 1) % WP_COLS, math.floor((j - 1) / WP_COLS)
		local x = M + WP_GAP + col * (WP_TW + WP_GAP)
		local y = p.cardY + o + WP_TOP + row * WP_ROW
		local id = ID_WP0 + i
		RegIn(btns, id, x - WP_GAP / 2, y - 10, WP_TW + WP_GAP, WP_ROW - 4, top, bottom, function() Set(wep, st, key, i) end)
		if y + WP_ROW > top and y - 10 < bottom then
			local hk = U.HoverK(wep, id, st.sel == id)
			if hk > 0.01 then U.Round(16, x - 8, y - 8, WP_TW + 16, WP_ROW - 10, SCR.Ink(18 * hk)) end
			local on = U.HoverK(wep, "wpsel" .. i, cur == i)
			if on > 0.01 then
				U.Round(WP_TR + 5, x - 5, y - 5, WP_TW + 10, WP_TH + 10, Color(C.blue.r, C.blue.g, C.blue.b, 255 * on))
				U.Round(WP_TR + 2, x - 2, y - 2, WP_TW + 4, WP_TH + 4, C.cell)
			end
			local sc = U.PopScale(wep, "wp" .. i, st.sel == id, U.Pressed(wep, st, id))
			local w2, h2 = WP_TW * sc, WP_TH * sc
			LK.Preview(wep, i, x + (WP_TW - w2) / 2, y + (WP_TH - h2) / 2, w2, h2, WP_TR * sc, false, home)
			local name = LK.WALLS[i] and LK.WALLS[i].name or ""
			U.T(U.Fit(name, "STTS_I_Cap", WP_TW + 14), "STTS_I_Cap", x + WP_TW / 2, y + WP_TH + 24, cur == i and C.blue or C.label)
		end
	end
end

-- nav bar of a pushed page: "< Previous" + centred title, like UINavigationBar: the back
-- label becomes "Back", then just the chevron, when it would run into the title
local function NavTitle(btns, wep, st, title, back, action, alpha)
	surface.SetFont("STTS_SET_Nav")
	local tw = math.min(surface.GetTextSize(title), W - 150)
	local room = W / 2 - tw / 2 - 8 - 44
	local label
	if back then
		surface.SetFont("STTS_I_Body")
		if surface.GetTextSize(back) <= room then label = back
		elseif surface.GetTextSize("Back") <= room then label = "Back" end
	end
	if action then U.NavBack(btns, wep, st, label, action) end
	if (alpha or 1) > 0.01 then
		surface.SetAlphaMultiplier(alpha or 1)
		U.T(U.Fit(title, "STTS_SET_Nav", W - 150), "STTS_SET_Nav", W / 2, 78, C.label)
		surface.SetAlphaMultiplier(1)
	end
end

local function Page(wep, st, btns, def)
	U.R(0, 0, W, H, C.group)
	local top, bottom = 104, H
	local total, place = Measure(def.secs)
	local y0 = def.root and 192 or 112          -- root: room for the large title
	total = total + y0
	local maxScroll = math.max(0, (total + 24 - bottom) / STEP)
	if st.own and SCR.L then SCR.L.maxScroll = maxScroll end
	local s = math.Clamp(st.scroll or 0, -1, maxScroll + 1)
	local o = y0 - s * STEP
	U.Clip(0, top, W, bottom - top)

	-- large title (collapses, and stretches a little when pulled past the top, like iOS)
	local stretch = s < 0 and math.min(-s * STEP, 60) or 0
	local lsc = 1 + stretch / 300
	local ly = 150 - s * STEP
	if def.root then
		local m = Matrix()
		m:Translate(Vector(20, ly, 0)) m:Scale(Vector(lsc, lsc, 1)) m:Translate(Vector(-20, -ly, 0))
		cam.PushModelMatrix(m, true)
		U.T(def.title, "STTS_SET_Large", 20, ly, C.label, TEXT_ALIGN_LEFT)
		cam.PopModelMatrix()
	end

	-- the sections
	for i, sec in ipairs(def.secs) do
		local p = place[i]
		if p.hdrY then
			local ht = string.upper(sec.hdr)
			U.T(ht, "STTS_SET_Sec", 34, p.hdrY + o, C.label2, TEXT_ALIGN_LEFT)
			if sec.spin then -- v19.2: looking for networks
				surface.SetFont("STTS_SET_Sec")
				Spinner(34 + surface.GetTextSize(ht) + 20, p.hdrY + o, 9, C.label2)
			end
		end
		local cy = p.cardY + o
		if p.cardY + p.cardH + o > top and cy < bottom then
			U.Round(20, M, cy, W - 2 * M, p.cardH, C.cell)
		end
		local c = sec.custom
		if c == "profile" then DrawProfile(wep, st, p, o, btns, top, bottom, sec)
		elseif c == "appearance" then DrawAppearance(wep, st, p, o, btns, top, bottom)
		elseif c == "accents" then DrawAccents(wep, st, p, o, btns, top, bottom)
		elseif c == "wpcur" then DrawWpCur(wep, st, p, o, btns, top, bottom)
		elseif c == "wpgrid" then DrawWpGrid(wep, st, sec, p, o, btns, top, bottom)
		elseif c == "slider" then
			local vis = cy > top - 40 and cy < bottom
			HSlider(btns, wep, st, sec.id, M, cy + p.cardH / 2, W - 2 * M, sec.key, sec.lo, sec.hi, vis and st.own)
		else DrawRows(wep, st, btns, sec, p, o, top, bottom) end
		if p.ftrLines then
			for li, line in ipairs(p.ftrLines) do U.T(line, "STTS_SET_Ftr", 34, p.ftrY + (li - 1) * 26 + o, C.label2, TEXT_ALIGN_LEFT) end
		end
	end

	U.Unclip()
	local ia = maxScroll > 0 and U.BarA and U.BarA(wep, st) or 0
	if ia > 0.01 then
		local area = bottom - top
		local bh = math.max(30, area * area / math.max(total, area + 1))
		U.Round(3, W - 8, top + (area - bh) * math.Clamp(s / maxScroll, 0, 1), 5, bh, SCR.Ink(90 * ia))
	end
	U.Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = STEP})

	-- nav bar on top (transparent until you scroll, then a bar + hairline, like iOS)
	local barA = math.Clamp(s * STEP / 30, 0, 1)
	if barA > 0.01 then
		U.R(0, 0, W, top, Color(C.bar.r, C.bar.g, C.bar.b, (C.bar.a or 245) * barA))
		if s > 0.05 then U.R(0, top - 1, W, 1, Color(C.sep.r, C.sep.g, C.sep.b, (C.sep.a or 255) * barA)) end
	end
	-- inline title: always on sub-pages, on the root only once the large title has scrolled up
	local showA = def.root and math.Clamp((s * STEP - 84) / 24, 0, 1) or 1
	NavTitle(btns, wep, st, def.title, def.back and def.back.label, def.back and def.back.action, showA)
end

--[[---------------------------------------------------------------------------
	the pages
---------------------------------------------------------------------------]]
-- v19.2: the Wi-Fi row of the root page: the network / Not Connected / Off
local function WifiValue(wep, st)
	local ws = SCR.WifiState(wep, st)
	if ws == "on" then return SCR.WifiNet() end
	if ws == "join" then return "Connecting…" end
	return ws == "none" and "Not Connected" or "Off"
end
local function SettingsApp(wep, st, btns)
	local cc = st.cc or {}
	local secs = {
		{custom = "profile", rows = {{id = 150, action = function() U.SetApp(st, G.APP_GENERAL) end}}},
		{rows = {
			{id = 151, label = "Airplane Mode", tile = {col = Color(255, 149, 0), glyph = nil, icon = "airplane"}, sw = st.plane, action = function() TogglePlane(wep, st) end},
			{id = 152, label = "Wi-Fi", tile = {col = Color(0, 122, 255), icon = "wifi"}, value = WifiValue(wep, st), action = function() U.SetApp(st, G.APP_WIFI) end},
		}},
		{rows = {
			{id = 155, label = "Notifications", tile = {col = Color(255, 59, 48), icon = "notif"}, action = function() U.SetApp(st, G.APP_NOTIF) end},
			{id = 156, label = "Sounds & Haptics", tile = {col = Color(255, 45, 85), glyph = "speaker", icon = "ringtone"}, action = function() U.SetApp(st, G.APP_SOUNDS) end},
			{id = 159, label = "Focus", tile = {col = Color(88, 86, 214), icon = "focus"}, value = cc.focus and "On" or "", action = function() ToggleCC(wep, st, "focus") end},
		}},
		{rows = {
			{id = 158, label = "General", tile = {col = Color(142, 142, 147), icon = "general"}, action = function() U.SetApp(st, G.APP_GENERAL) end},
			{id = 157, label = "Display & Brightness", tile = {col = Color(0, 122, 255), icon = "display"}, action = function() U.SetApp(st, G.APP_DISPLAY) end},
			{id = 153, label = "Wallpaper", tile = {col = Color(52, 170, 220), icon = "wallpaper"}, action = function() U.SetApp(st, G.APP_WALLPAPER) end},
		}},
	}
	Page(wep, st, btns, {title = "Settings", root = true, secs = secs})
end

-- v19.2: Settings > Wi-Fi: the switch, the network you are on (check / connecting),
-- or "Networks" with the one there is (the map): tap = join
local function WifiApp(wep, st, btns)
	local ws = SCR.WifiState(wep, st)
	local net = SCR.WifiNet()
	local rows = {
		{id = 175, label = "Wi-Fi", tile = {col = Color(0, 122, 255), icon = "wifi"}, sw = ws ~= "off", action = function() ToggleCC(wep, st, "wifi") end},
	}
	if ws == "on" or ws == "join" then rows[2] = {id = 176, label = net, net = true, check = ws == "on", spin = ws == "join"} end
	local secs = {{rows = rows}}
	if ws == "none" then
		local L = SCR.L
		secs[2] = {hdr = "Networks", spin = st.own and L and L.wifiOnAt and RealTime() - L.wifiOnAt < 1.6, rows = {
			{id = 177, label = net, net = true, action = function() SCR.WifiJoin(wep, st) end},
		}}
	end
	Page(wep, st, btns, {title = "Wi-Fi", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

local function SoundsApp(wep, st, btns)
	local secs = {
		{hdr = "Ringtone and Alert Volume", custom = "slider", id = 160, key = "vol", lo = soundLo, hi = soundLo},
		{hdr = "Sounds", rows = {
			{id = 161, label = "Ringtone", tile = {col = Color(255, 45, 85), glyph = "speaker", icon = "ringtone"}, value = RingOf(wep).name, action = function() U.SetApp(st, G.APP_RINGTONES) end},
			{id = 162, label = "Text Tone", tile = {col = Color(52, 199, 89), glyph = "bubble", icon = "texttone"}, value = ToneOf(wep).name, action = function() U.SetApp(st, G.APP_TONES) end},
		}},
	}
	Page(wep, st, btns, {title = "Sounds & Haptics", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

local function DisplayApp(wep, st, btns)
	local secs = {
		{hdr = "Appearance", custom = "appearance"},
		{hdr = "Accent Color", custom = "accents"},
		{hdr = "Brightness", custom = "slider", id = 164, key = "bright", lo = cciSun, hi = cciSun},
		-- fix61: how long the display stays on once the phone has left the hand
		{rows = {
			{id = 165, label = "Auto-Lock", value = G.AutoLockName and G.AutoLockName(Get(wep, "alock")) or "", action = function() U.SetApp(st, G.APP_AUTOLOCK) end},
		}},
	}
	Page(wep, st, btns, {title = "Display & Brightness", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

--[[ fix61: Settings > Display & Brightness > Auto-Lock. the phone that leaves the hand
     stays unlocked with the display on this long (on the floor), half of it in the
     pocket / inventory, then it fades out and locks (sv_phone_lock.lua) ]]
local function AutoLockApp(wep, st, btns)
	local cur = Get(wep, "alock")
	local rows = {}
	for i = 0, #(G.AutoLock or {}) do
		local o = G.AutoLock[i]
		if o then rows[#rows + 1] = {id = ID_AL0 + i, label = o[2], mark = cur == i, action = function() Set(wep, st, "alock", i) end} end
	end
	Page(wep, st, btns, {title = "Auto-Lock", secs = {{rows = rows}},
		back = {label = "Display & Brightness", action = function() U.SetApp(st, G.APP_DISPLAY) end}})
end

-- fix60: Settings > Wallpaper. fix61: lock screen + home screen, the wallpapers in groups
local function WallpaperApp(wep, st, btns)
	local secs = {{hdr = "Current", custom = "wpcur"}}
	local LK = STTS.PhoneLock
	for _, g in ipairs(LK and LK.SECTIONS or {}) do secs[#secs + 1] = {hdr = g.title, custom = "wpgrid", ids = g.ids} end
	Page(wep, st, btns, {title = "Wallpaper", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

local function GeneralApp(wep, st, btns)
	local name = wep:GetNWString("STTS_PName", "")
	if name == "" then name = "Phone" end
	local h24 = Get(wep, "h24")
	local model = G.Of(wep).name or ""
	local secs = {
		{rows = {
			{id = 170, label = "Name", value = U.Fit(name, "STTS_SET_Val", 220), chev = false, info = true},
			{id = 171, label = "Phone Number", value = st.num ~= "" and st.num or "—", chev = false, info = true},
			{id = 172, label = "Model Name", value = U.Fit(model, "STTS_SET_Val", 240), chev = false, info = true},
		}},
		{hdr = "Date & Time", rows = {
			{id = 173, label = "24-Hour Time", tile = {col = Color(142, 142, 147), glyph = "clock", icon = "clock"}, sw = h24, action = function() Set(wep, st, "h24", not h24) end},
		}},
	}
	Page(wep, st, btns, {title = "General", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

local function NotifApp(wep, st, btns)
	local badge = Get(wep, "badge")
	local secs = {
		{rows = {
			{id = 174, label = "App Icon Badges", tile = {col = Color(255, 59, 48), glyph = "badge", icon = "notif"}, sw = badge, action = function() Set(wep, st, "badge", not badge) end},
		}},
	}
	Page(wep, st, btns, {title = "Notifications", secs = secs,
		back = {label = "Settings", action = function() U.SetApp(st, G.APP_SETTINGS) end}})
end

-- a list of sounds (ringtones / text tones): tap = select + preview from the phone
local ROW = 72
local function SoundList(wep, st, btns, list, cur, act, app, title, hdr)
	U.R(0, 0, W, H, C.group)
	local top, bottom = 104, H
	local pad = 64
	local total = pad + #list * ROW + 64
	local maxScroll = math.max(0, (total - (bottom - top)) / ROW)
	if st.own and SCR.L then SCR.L.maxScroll = maxScroll end
	local s = math.Clamp(st.scroll or 0, -1, maxScroll + 1)
	local y0 = top - s * ROW
	U.Clip(0, top, W, bottom - top)
	U.T(string.upper(hdr or title), "STTS_SET_Sec", 34, y0 + pad - 21, C.label2, TEXT_ALIGN_LEFT)
	local cardY = y0 + pad
	U.Round(20, 16, cardY, W - 32, #list * ROW, C.cell)
	for i, r in ipairs(list) do
		local y = cardY + (i - 1) * ROW
		if y + ROW < top or y > bottom then continue end
		local id = ROW0 + i
		RegIn(btns, id, 16, y, W - 32, ROW, top, bottom, function()
			if not st.own then return end
			local L = SCR.L
			if act == "ring" then L.ring, L.ringAt = r.id, RealTime() U.Act("ring", r.id)
			else Set(wep, st, act, r.id) end
			Preview(wep, r, app)
		end)
		RowHover(wep, st, id, 16, y, W - 32, ROW, 20, i == 1, i == #list)
		local on = cur.id == r.id
		if on then Check(46, y + ROW / 2, 9, C.blue, 3.5) end
		U.T(U.Fit(r.name, "STTS_I_Body", W - 170), "STTS_I_Body", 76, y + ROW / 2, on and C.blue or C.label, TEXT_ALIGN_LEFT)
		if st.own and prev.id == r.id and prev.app == app then
			local t = RealTime()
			for b = 0, 2 do
				local bh = 6 + 12 * math.abs(math.sin(t * 7 + b * 1.7))
				U.Round(2, W - 66 + b * 8, y + ROW / 2 + 9 - bh, 5, bh, C.blue)
			end
		end
		if i < #list then U.R(76, y + ROW - 1, W - 92, 1, C.sep) end
	end
	U.Unclip()
	local ia = maxScroll > 0 and U.BarA and U.BarA(wep, st) or 0
	if ia > 0.01 then
		local area = bottom - top
		local bh = math.max(30, area * area / total)
		U.Round(3, W - 8, top + (area - bh) * math.Clamp(s / maxScroll, 0, 1), 5, bh, SCR.Ink(90 * ia))
	end
	U.Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = ROW})

	local barA = math.Clamp(s * ROW / 30, 0, 1)
	if barA > 0.01 then
		U.R(0, 0, W, top, Color(C.bar.r, C.bar.g, C.bar.b, (C.bar.a or 245) * barA))
		if s > 0.05 then U.R(0, top - 1, W, 1, Color(C.sep.r, C.sep.g, C.sep.b, (C.sep.a or 255) * barA)) end
	end
	NavTitle(btns, wep, st, title, "Sounds & Haptics", function()
		StopPreview(true)
		U.SetApp(st, G.APP_SOUNDS)
	end)
end

local function RingtonesApp(wep, st, btns)
	SoundList(wep, st, btns, G.Ringtones, RingOf(wep), "ring", G.APP_RINGTONES, "Ringtone", "Ringtones")
end
local function TonesApp(wep, st, btns)
	SoundList(wep, st, btns, G.Tones, ToneOf(wep), "tone", G.APP_TONES, "Text Tone", "Alert Tones")
end

--[[ home screen: the Settings icon, top left with its label (dock icons have none) ]]
local function HomeExtra(wep, st, btns)
	local size = 84
	local gap = (W - 28 - size * 4) / 5
	local x, y = 14 + gap, 112
	wep.STTS_IconRect = wep.STTS_IconRect or {}
	wep.STTS_IconRect[G.APP_SETTINGS] = {x = x, y = y, w = size, h = size}
	U.Reg(btns, ID_ICON, x, y, size, size, function() wep.STTS_OpenFrom = nil U.SetApp(st, G.APP_SETTINGS) end)
	-- iOS: no hover / scale, the icon only darkens under the finger
	local hi = U.IconHi and U.IconHi(wep, st, ID_ICON) or (U.Pressed(wep, st, ID_ICON) and 1 or 0)
	local sz, ix, iy = size, x, y
	if wep.STTS_HideIcon == G.APP_SETTINGS then
		-- lifted off the home screen: the app window (transition) draws it
	elseif not settingsIcon:IsError() then
		surface.SetMaterial(settingsIcon) surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(ix, iy, sz, sz)
		if hi > 0 then surface.SetDrawColor(LC(Color(0, 0, 0, 92 * hi))) surface.DrawTexturedRect(ix, iy, sz, sz) end
	else
		U.Round(sz * 0.23, ix, iy, sz, sz, Color(142, 142, 147))
		if hi > 0 then U.Round(sz * 0.23, ix, iy, sz, sz, Color(0, 0, 0, 92 * hi)) end
	end
	U.T("Settings", "STTS_I_Cap", x + size / 2, y + size + 16, C.label)
	for _, fn in pairs(SCR.HomeExtras or {}) do fn(wep, st, btns) end -- fix54: other app icons (ZMusic)
end

local PAGES = {
	[G.APP_SETTINGS] = SettingsApp, [G.APP_SOUNDS] = SoundsApp, [G.APP_DISPLAY] = DisplayApp,
	[G.APP_GENERAL] = GeneralApp, [G.APP_NOTIF] = NotifApp, [G.APP_RINGTONES] = RingtonesApp, [G.APP_TONES] = TonesApp,
}
if G.APP_WIFI then PAGES[G.APP_WIFI] = WifiApp end
if G.APP_WALLPAPER then PAGES[G.APP_WALLPAPER] = WallpaperApp end
if G.APP_AUTOLOCK then PAGES[G.APP_AUTOLOCK] = AutoLockApp end
-- which page an iOS back / edge-swipe goes to (the screen file drives the interactive swipe)
SCR.SettingsBack = {[G.APP_SOUNDS] = G.APP_SETTINGS, [G.APP_DISPLAY] = G.APP_SETTINGS,
	[G.APP_GENERAL] = G.APP_SETTINGS, [G.APP_NOTIF] = G.APP_SETTINGS,
	[G.APP_RINGTONES] = G.APP_SOUNDS, [G.APP_TONES] = G.APP_SOUNDS}
if G.APP_WIFI then SCR.SettingsBack[G.APP_WIFI] = G.APP_SETTINGS end
if G.APP_WALLPAPER then SCR.SettingsBack[G.APP_WALLPAPER] = G.APP_SETTINGS end
if G.APP_AUTOLOCK then SCR.SettingsBack[G.APP_AUTOLOCK] = G.APP_DISPLAY end
-- leaving a page (the swipe committed): stop a ringtone preview when leaving a sound list
function SCR.SettingsLeave(app)
	if app == G.APP_RINGTONES or app == G.APP_TONES then StopPreview(true) end
end
local function Register()
	local APPS = SCR.APPS
	if not APPS then return end
	for app, fn in pairs(PAGES) do APPS[app] = fn end
	if APPS[G.APP_HOME] ~= SCR.STTS_HomeWrap then
		local home = APPS[G.APP_HOME]
		SCR.STTS_HomeWrap = function(wep, st, btns)
			U.R(0, 0, W, H, C.home)
			home(wep, st, btns)
			HomeExtra(wep, st, btns)
		end
		APPS[G.APP_HOME] = SCR.STTS_HomeWrap
	end
	if SCR.APP_ICON then SCR.APP_ICON[G.APP_SETTINGS] = settingsIcon end
	if SCR.ROOT_ICON then
		for _, app in ipairs({G.APP_RINGTONES, G.APP_TONES, G.APP_SOUNDS, G.APP_DISPLAY, G.APP_GENERAL, G.APP_NOTIF, G.APP_WIFI, G.APP_WALLPAPER, G.APP_AUTOLOCK}) do
			SCR.ROOT_ICON[app] = G.APP_SETTINGS
		end
	end
	if SCR.LEVEL then
		SCR.LEVEL[G.APP_SOUNDS], SCR.LEVEL[G.APP_DISPLAY], SCR.LEVEL[G.APP_GENERAL], SCR.LEVEL[G.APP_NOTIF] = 2, 2, 2, 2
		SCR.LEVEL[G.APP_RINGTONES], SCR.LEVEL[G.APP_TONES] = 3, 3
		if G.APP_WIFI then SCR.LEVEL[G.APP_WIFI] = 2 end
		if G.APP_WALLPAPER then SCR.LEVEL[G.APP_WALLPAPER] = 2 end
		if G.APP_AUTOLOCK then SCR.LEVEL[G.APP_AUTOLOCK] = 3 end
	end
end
Register()
hook.Add("Think", "STTS_PhoneSettingsApps", function()
	local APPS = SCR.APPS
	if APPS and (APPS[G.APP_SETTINGS] ~= SettingsApp or APPS[G.APP_HOME] ~= SCR.STTS_HomeWrap) then Register() end
end)

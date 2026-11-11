--[[---------------------------------------------------------------------------
	fix58: lock screen, like the iPhone (iOS 17 / 18).
	the phone locks when it leaves the hand (put away, another item taken, dropped,
	picked up by someone): NW2 "Unlk" = false (weapon_stts_phone.lua). a running video
	recording is NOT stopped by it (fix16), it just goes on in the background.
	  * Apple's own default wallpapers: the iPhone 18 Pro one in the colour of the body
	    (black / burgundy / glacier / silver), the other models the iOS 27 default
	    (light / dark with the theme of the phone). fix60: Settings > Wallpaper picks
	    one of them by hand (NW2 "LkWp", 0 = automatic as above). padlock under the
	    island, the date and the big clock, the status bar with the carrier name
	  * the padlock opens a moment after the phone is raised (Face ID), then
	    "Swipe up to open"
	  * swipe up (from the lower half) = unlock, like iOS 26: the cover sheet follows
	    the finger (fix60: a clean edge, no grey glass lip any more), the home screen
	    behind it has no icons yet. let go = the sheet flies off and the icons (or the
	    app that was open) zoom in from big to their place and fade in
	  * flashlight (left) and camera (right): press and HOLD like on the iPhone.
	    camera = unlock straight into the Camera app; a swipe to the left does the same
	  * TeleChat: unread messages as a notification
	  * the Control Centre can be pulled down over it, a ringing alarm covers it,
	    a call shows the call screen
	  * not raised = dimmed like the Always-On display
	everybody sees the same lock screen on your phone (NW2), yours is predicted.
---------------------------------------------------------------------------]]
local SCR = STTS and STTS.PhoneScreen
if not SCR or not SCR.UI then return end
local G = STTS.PhoneGeo
local U = SCR.UI
local L = SCR.L
local W, H = U.W, U.H

local LK = STTS.PhoneLock or {}
STTS.PhoneLock = LK

local MAT = {
	-- Apple's wallpapers (static versions, 9to5Mac), 512 x 1024 = the 432 x 960 display squeezed
	p18 = {
		black = Material("stts/lk_wp_18pro_black.jpg", "smooth"),
		burgundy = Material("stts/lk_wp_18pro_burgundy.jpg", "smooth"),
		glacier = Material("stts/lk_wp_18pro_glacier.jpg", "smooth"),
		silver = Material("stts/lk_wp_18pro_silver.jpg", "smooth"),
	},
	ios27 = {Material("stts/lk_wp_ios27_dark.jpg", "smooth"), Material("stts/lk_wp_ios27_light.jpg", "smooth")},
	lock = Material("stts/lk_lock.png", "smooth mips"),
	unlock = Material("stts/lk_unlock.png", "smooth mips"),
	torch = Material("stts/lk_torch.png", "smooth mips"),
	camera = Material("stts/lk_camera.png", "smooth mips"),
}
local function Font(name, size, weight)
	surface.CreateFont(name, {font = "Roboto", size = size, weight = weight, antialias = true, extended = true})
end
Font("STTS_LK_Time", 128, 700)
Font("STTS_LK_Date", 25, 600)
Font("STTS_LK_Hint", 20, 500)
Font("STTS_LK_NTitle", 21, 600)
Font("STTS_LK_NBody", 21, 400)
Font("STTS_LK_Rec", 21, 600)
Font("STTS_LK_PvTime", 46, 700) -- fix60: the previews in Settings > Wallpaper
Font("STTS_LK_PvDate", 11, 600)
Font("STTS_LK_PvTimeS", 26, 700)

local WHITE = Color(255, 255, 255)
local BTN_R, BTN_X, BTN_Y = 27, 73, H - 100 -- the round buttons at the bottom (iOS: 50 pt)
local HOLD = 0.35                            -- press and hold this long (flashlight / camera)
local ZOOM_END = 0.42                        -- the home screen zoom after the unlock (s)
local BLACK = Color(0, 0, 0)

--[[ fix61: the two buttons answer much more easily: a bigger touch area (the finger OR the
     pointer under it is enough), a tap fires too (not only press and hold), and the hold
     also fires from the draw step (when no move event comes while the finger rests) ]]
local HIT_R = BTN_R + 24      -- touch area of a button (px)
local SLIDE_R = BTN_R + 56    -- slid this far off = cancelled
local function Finger(wep)
	if wep.STTS_FingerAt and RealTime() - wep.STTS_FingerAt < 0.25 then return wep.STTS_FingerUX, wep.STTS_FingerUY end
	return L.ux or W * 0.5, L.uy or H * 0.62
end
local function Near(x, y, bx, r) return x and y and (x - bx) ^ 2 + (y - BTN_Y) ^ 2 <= r * r end
local function BtnAt(fx, fy)
	for _, p in ipairs({{fx, fy}, {L.ux, L.uy}}) do
		if Near(p[1], p[2], BTN_X, HIT_R) then return "torch", BTN_X end
		if Near(p[1], p[2], W - BTN_X, HIT_R) then return "cam", W - BTN_X end
	end
end
LK.BtnAt = BtnAt

--[[ locked? yours: predicted for a moment after the swipe, else NW2 ]]
local pred = setmetatable({}, {__mode = "k"})
function LK.Locked(wep)
	local p = pred[wep]
	if p and RealTime() - p.at < 1.2 then return not p.unlk end
	return not wep:GetNW2Bool("Unlk", false)
end
local function SetUnlk(wep, on, dir)
	pred[wep] = {unlk = on, at = RealTime()}
	local s = wep.STTS_Lk
	if s and on then s.dir = dir end
	U.Act(on and "unlock" or "lock")
end
-- the phone went out of the hand (client side of SWEP:Holster). fix61: it does not lock at
-- once any more (Auto-Lock, sv_phone_lock.lua): only a half done swipe is let go
function LK.Holster(wep)
	pred[wep] = nil
	local s = wep.STTS_Lk
	if s and LK.Locked(wep) then s.off, s.v, s.drag, s.leaving, s.dir = 0, 0, nil, nil, nil s.gone = false
	elseif s then s.drag = nil end
end

--[[ fix61: Auto-Lock. NW2 "LkAt" (server) = when the display of a phone that left the hand
     goes out, "Off" = it is out. the last seconds it is dimmed (like iOS), after LkAt it
     fades to black; a call or a ringing alarm lights it up. drawn over everything
     (cl_phone_screen.lua DrawOverlays), a dark display is not drawn at all ]]
local OFF_DIM_S, OFF_DIM, OFF_FADE = 4, 0.55, 0.6
local function Wakes(wep)
	if wep:GetNW2Int("CallSt", 0) ~= (G.CALL_NONE or 0) then return true end
	return wep:GetNW2String("AlmRing", "") ~= ""
end
local function OffWant(wep)
	if Wakes(wep) then return 0 end
	if wep:GetNW2Bool("Off", false) then return 1 end
	local at = wep:GetNW2Float("LkAt", 0)
	if at <= 0 then return 0 end
	local t = CurTime() - at
	if t >= 0 then return OFF_DIM + (1 - OFF_DIM) * math.Clamp(t / OFF_FADE, 0, 1) end
	if t > -OFF_DIM_S then return OFF_DIM end
	return 0
end
LK.OffWant = OffWant
function SCR.DrawAutoOff(wep, st)
	local want = OffWant(wep)
	local k = wep.STTS_OffK
	if not k then k = want end
	local dt = wep.STTS_UIdt or 0
	-- dims softly (0.3 s), comes back fast
	local rate = want > k and 9 or 16
	k = Lerp(1 - math.exp(-dt * rate), k, want)
	if math.abs(k - want) < 0.004 then k = want end
	wep.STTS_OffK = k
	if k > 0.003 then U.R(0, 0, W, H, Color(0, 0, 0, 255 * math.min(k, 1))) end
end
-- fully dark: the display is not drawn at all (cl_phone_screen.lua UpdateScreens)
function SCR.ScreenOff(wep)
	return (wep.STTS_OffK or 0) >= 0.999 and wep:GetNW2Bool("Off", false) and not Wakes(wep)
end
local function OffMoving(wep)
	local want = OffWant(wep)
	if math.abs((wep.STTS_OffK or want) - want) > 0.004 then return true end
	local at = wep:GetNW2Float("LkAt", 0)
	if at > 0 then
		local t = CurTime() - at
		return t > -0.05 and t < OFF_FADE + 0.3
	end
	return false
end

-- visual state of one phone: off = how far the cover sheet is pushed away (px)
local function S(wep)
	local s = wep.STTS_Lk
	if not s then
		s = {off = 0, v = 0, open = 0, ov = 0, aod = 0}
		s.gone = not LK.Locked(wep)
		wep.STTS_Lk = s
	end
	return s
end

local function Step(wep, s)
	local dt = wep.STTS_UIdt or 0
	local now = RealTime()
	if LK.Locked(wep) then
		if s.gone or s.leaving then s.gone, s.leaving, s.off, s.v, s.dir = false, nil, 0, 0, nil end
		if not s.drag and s.off > 0 then -- let go too early: springs back
			s.off = s.off * math.exp(-dt * 14)
			if s.off < 0.5 then s.off = 0 end
		end
	elseif not s.gone then
		-- unlocked: the sheet flies off (~0.2 s), the home screen zooms in behind it
		if not s.leaving and s.dir ~= "left" then s.zt = 0 end
		s.leaving = true
		local sp = math.max(s.v or 0, 2200)
		s.off = s.off + math.max(sp * dt, (H + 20 - s.off) * (1 - math.exp(-dt * 16)))
		if s.off >= H then s.gone, s.leaving, s.off, s.drag = true, nil, H, nil end
	end
	if s.zt then
		s.zt = s.zt + dt
		if s.zt > ZOOM_END or LK.Locked(wep) then s.zt = nil end
	end
	-- fix61: the finger rests on a button: the hold fires here too (no move event needed)
	local pt = s.pressT
	if pt and (L.touch ~= pt or pt.lkFired or not pt.lkBtn) then s.pressT, pt = nil, nil end
	if pt and s.press and now - (s.pressAt or now) >= HOLD and LK.Fire then
		pt.lkFired, s.press, s.pressT = true, nil, nil
		LK.Fire(wep, pt.lkBtn)
	end
	-- Face ID: the padlock opens ~0.45 s after the phone is raised (looked at)
	local up = wep.IsUp and wep:IsUp()
	if up and not s.upAt then s.upAt = now elseif not up then s.upAt = nil end
	local want = (s.upAt and now - s.upAt > 0.45) and 1 or 0
	local wn = 2 * math.pi * 3.2 -- a little spring: the shackle overshoots a bit
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		s.ov = s.ov + (wn * wn * (want - s.open) - 2 * 0.55 * wn * s.ov) * h
		s.open = s.open + s.ov * h
	end
	-- not raised: dimmed like the Always-On display
	s.aod = Lerp(1 - math.exp(-dt * 6), s.aod, up and 0 or 1)
end

local function Shown(wep, st)
	local s = wep.STTS_Lk
	return s ~= nil and not s.gone and (st or wep.STTS_St or {}).app ~= G.APP_CALL
end
LK.Shown = Shown

--[[---------------------------------------------------------------------------
	drawing
---------------------------------------------------------------------------]]
local function Icon(mat, x, y, size, col)
	if mat:IsError() then return end
	surface.SetMaterial(mat)
	surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
	surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

local function DateText()
	return os.date("%A, %B ") .. tonumber(os.date("%d"))
end

local function Button(wep, s, key, cx, cy, on, mat, isz, hot)
	local k = s.press == key and math.Clamp((RealTime() - (s.pressAt or 0)) / HOLD, 0, 1) or 0
	local pop = s.pop and s.pop[key] or 0
	-- fix61: the finger over it = it lights up (like every other button)
	s.hov = s.hov or {}
	local dt = wep.STTS_UIdt or 0
	s.hov[key] = Lerp(1 - math.exp(-dt * 14), s.hov[key] or 0, hot and 1 or 0)
	local hv = s.hov[key]
	local sc = 1 + 0.22 * (k * k * (3 - 2 * k)) + 0.1 * pop + 0.05 * hv
	local r = BTN_R * sc
	U.Circle(cx, cy, r, on and Color(255, 255, 255, 235) or Color(18, 18, 24, 120 + 40 * hv))
	if not on then U.Circle(cx, cy, r - 1, Color(255, 255, 255, 22 + 40 * hv)) end
	Icon(mat, cx, cy, isz * sc, on and Color(0, 0, 0) or WHITE)
end

local function Notification(wep, st, y)
	local n = st.unread or 0
	if n <= 0 then return end
	local x, w, h = 14, W - 28, 86
	U.Round(24, x, y - h, w, h, Color(28, 26, 40, 150))
	U.Round(24, x, y - h, w, h, Color(255, 255, 255, 18))
	local icon = U.icons and U.icons.chat
	if icon and not icon:IsError() then
		surface.SetMaterial(icon) surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(x + 14, y - h + 22, 42, 42)
	end
	U.T("TeleChat", "STTS_LK_NTitle", x + 70, y - h + 30, WHITE, TEXT_ALIGN_LEFT)
	U.T("now", "STTS_LK_NBody", x + w - 18, y - h + 30, Color(235, 235, 245, 150), TEXT_ALIGN_RIGHT)
	U.T(n == 1 and "1 new message" or (n .. " new messages"), "STTS_LK_NBody", x + 70, y - h + 58, Color(255, 255, 255, 225), TEXT_ALIGN_LEFT)
end

--[[ the wallpaper of this phone. iPhone 18 Pro: the one of its colour (stock = black),
     the other models: iOS 27 default, the light one blended in with the theme ]]
local function Hue(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	if mx == mn then return 0, 0 end
	local d = mx - mn
	local h
	if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
	return h * 60, d / mx
end
local function AutoWall(wep)
	local M = G.Of(wep)
	if M and M.id == "iphone" then
		local key = "black"
		local r, g, b
		if G.UnpackColor then r, g, b = G.UnpackColor(wep:GetNW2Int("PCol", G.COL_STOCK or 1)) end
		if r then
			local l = (r * 0.299 + g * 0.587 + b * 0.114) / 255
			local h, sat = Hue(r, g, b)
			if sat < 0.2 then key = l < 0.45 and "black" or "silver"
			elseif h >= 190 and h < 260 then key = l > 0.4 and "glacier" or "black"
			elseif h >= 260 or h < 25 then key = "burgundy"
			else key = l > 0.55 and "silver" or "black" end
		end
		return MAT.p18[key], nil, nil, key
	end
	local k = math.Clamp(wep.STTS_ThK or 0, 0, 1)
	return MAT.ios27[1], MAT.ios27[2], k, k > 0.5 and "light" or "dark"
end

--[[ fix60: the wallpaper can be picked in Settings > Wallpaper (NW2 "LkWp", the same for
     everybody who looks at the phone). 0 = automatic (above), then the 6 of Apple.
     fix61: + 18 stock wallpapers of other phones (Pixel, Galaxy, Xiaomi), and the home
     screen has its own one (NW2 "HmWp", 0 = the same as the lock screen) ]]
LK.WALLS = {
	[0] = {name = "Automatic"},
	{name = "Black", key = "black", full = "iPhone 18 Pro Black"},
	{name = "Burgundy", key = "burgundy", full = "iPhone 18 Pro Burgundy"},
	{name = "Glacier", key = "glacier", full = "iPhone 18 Pro Glacier"},
	{name = "Silver", key = "silver", full = "iPhone 18 Pro Silver"},
	{name = "Dark", ios = 1, key = "dark", full = "iOS 27 Dark"},
	{name = "Light", ios = 2, key = "light", full = "iOS 27 Light"},
	-- fix61: Google Pixel 10 / 9 / 9 Pro
	{name = "Blue", file = "pixel_blue", full = "Pixel 10 Blue"},
	{name = "Sage", file = "pixel_sage", full = "Pixel 10 Sage"},
	{name = "Neon", file = "pixel_neon", full = "Pixel 10 Neon"},
	{name = "Indigo", file = "pixel_indigo", full = "Pixel 9 Indigo"},
	{name = "Rose", file = "pixel_rose", full = "Pixel 9 Rose"},
	{name = "Peach", file = "pixel_peach", full = "Pixel 9 Pro Peach"},
	-- Samsung Galaxy (S20 / S21 / S22 / A series)
	{name = "Ember", file = "galaxy_ember", full = "Galaxy Ember"},
	{name = "Night", file = "galaxy_night", full = "Galaxy Night"},
	{name = "Bloom", file = "galaxy_bloom", full = "Galaxy Bloom"},
	{name = "Pink", file = "galaxy_pink", full = "Galaxy Pink"},
	{name = "Violet", file = "galaxy_violet", full = "Galaxy Violet"},
	{name = "Glass", file = "galaxy_glass", full = "Galaxy Glass"},
	-- Xiaomi (MIUI 12)
	{name = "Mars", file = "miui_mars", full = "MIUI 12 Mars"},
	{name = "Orbit", file = "miui_orbit", full = "MIUI 12 Orbit"},
	{name = "Sky", file = "miui_sky", full = "MIUI 12 Sky"},
	{name = "Ocean", file = "miui_ocean", full = "MIUI 12 Ocean"},
	{name = "Dunes", file = "miui_dunes", full = "MIUI 12 Dunes"},
	{name = "Peak", file = "miui_peak", full = "MIUI 12 Peak"},
}
-- the groups of Settings > Wallpaper
LK.SECTIONS = {
	{title = "iPhone", ids = {0, 1, 2, 3, 4, 5, 6}},
	{title = "Pixel", ids = {7, 8, 9, 10, 11, 12}},
	{title = "Galaxy", ids = {13, 14, 15, 16, 17, 18}},
	{title = "Xiaomi", ids = {19, 20, 21, 22, 23, 24}},
}
local FILEMAT = {}
local function FileMat(name)
	local m = FILEMAT[name]
	if not m then m = Material("stts/lk_wp_" .. name .. ".jpg", "smooth") FILEMAT[name] = m end
	return m
end
local function Valid(v)
	v = math.floor(tonumber(v) or 0)
	return LK.WALLS[v] and v or 0
end
local function Choice(wep)
	return Valid(SCR.SettingOf and SCR.SettingOf(wep, "lkwp") or wep:GetNW2Int("LkWp", 0))
end
LK.Choice = Choice
-- fix61: the home screen: its own pick (0 = whatever the lock screen has)
local function HomeRaw(wep)
	return Valid(SCR.SettingOf and SCR.SettingOf(wep, "hmwp") or wep:GetNW2Int("HmWp", 0))
end
LK.HomeChoice = HomeRaw
local function HomeIdx(wep)
	local v = HomeRaw(wep)
	if v == 0 then return Choice(wep) end
	return v
end
-- idx = nil: the one of this phone. returns material, blended material, its weight
local function Wall(wep, idx)
	local o = LK.WALLS[idx or Choice(wep)]
	if o and o.ios then return MAT.ios27[o.ios] end
	if o and o.key then return MAT.p18[o.key] end
	if o and o.file then return FileMat(o.file) end
	return AutoWall(wep)
end
-- the name of the wallpaper (Settings > Wallpaper): "iOS 27 Dark", "Automatic: ..."
-- short = the caption under the small previews (Settings > Wallpaper, "Current")
function LK.WallName(wep, idx, home, short)
	if home then
		idx = idx or HomeRaw(wep)
		if idx == 0 then return short and "Same as Lock" or "Same as Lock Screen" end
	end
	idx = idx or Choice(wep)
	local o = LK.WALLS[idx]
	if o and o.full then return short and o.name or o.full end
	if short then return "Automatic" end
	local _, _, _, key = AutoWall(wep)
	for i = 1, #LK.WALLS do
		if LK.WALLS[i].key == key then return "Automatic: " .. LK.WALLS[i].full end
	end
	return "Automatic"
end
local function DrawWall(wep, x, y, w, h, v0, v1, idx)
	local m1, m2, k = Wall(wep, idx)
	v0, v1 = v0 or 0, v1 or 1
	if m1:IsError() then U.R(x, y, w, h, Color(20, 20, 40)) return end
	surface.SetMaterial(m1) surface.SetDrawColor(255, 255, 255)
	surface.DrawTexturedRectUV(x, y, w, h, 0, v0, 1, v1)
	if m2 and k and k > 0.01 and not m2:IsError() then
		surface.SetMaterial(m2) surface.SetDrawColor(255, 255, 255, 255 * k)
		surface.DrawTexturedRectUV(x, y, w, h, 0, v0, 1, v1)
	end
end

-- fix61: the wallpaper of the home screen (cl_phone_home.lua, the app zoom, under the sheet)
function LK.DrawHomeWall(wep, x, y, w, h, v0, v1)
	DrawWall(wep, x or 0, y or 0, w or W, h or H, v0 or 0, v1 or 1, HomeIdx(wep))
end
SCR.DrawHomeWall = LK.DrawHomeWall

--[[ fix60: a wallpaper with rounded corners + a small lock screen on it (Settings >
     Wallpaper: the current one and the choices). big = the date + the buttons too ]]
function LK.DrawWallR(wep, idx, x, y, w, h, r)
	local m1, m2, k = Wall(wep, idx)
	if m1:IsError() then U.Round(r, x, y, w, h, Color(20, 20, 40)) return end
	local poly = U.RoundTex -- cl_phone_screen.lua RoundPoly (textured, UV over the rect)
	local function one(m, a)
		surface.SetMaterial(m) surface.SetDrawColor(255, 255, 255, a)
		if poly then poly(x, y, w, h, r, 0, 0, 1, 1) else surface.DrawTexturedRect(x, y, w, h) end
	end
	one(m1, 255)
	if m2 and k and k > 0.01 and not m2:IsError() then one(m2, 255 * k) end
end
function LK.Preview(wep, idx, x, y, w, h, r, big, home)
	if home then
		-- fix61: a home screen: its wallpaper (0 = the one of the lock screen) + the icons
		if idx == nil then idx = HomeIdx(wep) elseif idx == 0 then idx = Choice(wep) end
		LK.DrawWallR(wep, idx, x, y, w, h, r)
		if SCR.HomeMini then SCR.HomeMini(wep, x, y, w / W, big) end
		return
	end
	LK.DrawWallR(wep, idx, x, y, w, h, r)
	local sc = w / W
	local clock = SCR.Clock and SCR.Clock(wep) or os.date("%H:%M")
	if big then
		local I = G.Of(wep).Island or G.Models[1].Island
		U.Round(I.h * sc / 2, x + w / 2 - I.w * sc / 2, y + I.y * sc, I.w * sc, I.h * sc, BLACK)
		local ly = y + (I.y + I.h + 30) * sc
		Icon(MAT.lock, x + w / 2, ly, 34 * sc, WHITE)
		local dy = ly + 44 * sc
		U.T(DateText(), "STTS_LK_PvDate", x + w / 2, dy, Color(255, 255, 255, 235))
		U.T(clock, "STTS_LK_PvTime", x + w / 2, dy + 78 * sc, WHITE)
		for _, b in ipairs({{BTN_X, MAT.torch}, {W - BTN_X, MAT.camera}}) do
			local bx, by = x + b[1] * sc, y + BTN_Y * sc
			U.Circle(bx, by, BTN_R * sc, Color(18, 18, 24, 120))
			Icon(b[2], bx, by, 30 * sc, WHITE)
		end
		U.Round(2, x + w / 2 - 70 * sc, y + (H - 19) * sc, 140 * sc, math.max(2, 6 * sc), Color(255, 255, 255, 235))
	else
		U.T(clock, "STTS_LK_PvTimeS", x + w / 2, y + 196 * sc, WHITE)
	end
end

--[[ after the unlock: the home screen (or the app) under the sheet zooms in from big and
     fades in (own phone: the content render target; the others see it without the zoom) ]]
local function Zoom(wep, s)
	local mat = SCR.ShadeBG -- cl_phone_screen.lua: the content of THIS frame (own phone)
	if not s.zt or not mat then return end
	local t = math.max(s.zt - 0.03, 0)
	local sc = 1 + 1.3 * math.exp(-t * 16)
	local a = math.Clamp(t / 0.09, 0, 1)
	LK.DrawHomeWall(wep, 0, 0, W, H) -- fix61: the home screen wallpaper (was a plain colour)
	if a > 0.01 then
		surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255 * a)
		surface.DrawTexturedRect(W / 2 - W * sc / 2, H / 2 - H * sc / 2, W * sc, H * sc)
	end
end

function SCR.DrawLock(wep, st, btns)
	local s = S(wep)
	Step(wep, s)
	if not Shown(wep, st) then Zoom(wep, s) return end
	-- the app under it gets no touches (its buttons, scroll areas)
	for i = #btns, 1, -1 do btns[i] = nil end
	btns.zones = {}
	local ox, oy = 0, -s.off
	local up = s.dir ~= "left"
	if not up then ox, oy = -s.off * W / H, 0 end
	local fade = 1 - math.Clamp(s.off / H, 0, 1)
	-- under the sheet: the home screen without its icons, then (unlocked) the zoom
	if up and s.off > 0.5 then
		local cut = math.Clamp(H - s.off, 0, H)
		LK.DrawHomeWall(wep, 0, cut, W, H - cut, cut / H, 1) -- fix61: the home screen wallpaper (was a plain colour)
		Zoom(wep, s)
	end
	-- wallpaper: the whole cover sheet moves
	DrawWall(wep, ox, oy, W, H)
	surface.SetAlphaMultiplier(fade * fade)
	local I = G.Of(wep).Island or G.Models[1].Island
	-- padlock (opens with Face ID: the shackle swings up)
	local ly = oy + I.y + I.h + 30
	local o = math.Clamp(s.open, 0, 1.15)
	local lsz = 34
	if o < 0.5 then
		Icon(MAT.lock, ox + W / 2, ly, lsz, WHITE)
	else
		local bump = math.max(s.open - 1, 0) * 10 -- the overshoot = a little hop
		Icon(MAT.unlock, ox + W / 2 + lsz * 21 / 128, ly - bump, lsz, WHITE)
	end
	-- date + clock
	local dy = ly + 44
	local clock = SCR.Clock and SCR.Clock(wep) or os.date("%H:%M")
	U.T(DateText(), "STTS_LK_Date", ox + W / 2, dy + 1, Color(0, 0, 0, 40)) -- soft legibility shadow
	U.T(clock, "STTS_LK_Time", ox + W / 2, dy + 80, Color(0, 0, 0, 34))
	U.T(DateText(), "STTS_LK_Date", ox + W / 2, dy, Color(255, 255, 255, 235))
	U.T(clock, "STTS_LK_Time", ox + W / 2, dy + 78, WHITE)
	-- notifications above the buttons
	Notification(wep, st, oy + BTN_Y - BTN_R - 34)
	-- flashlight / camera
	local hot
	if st.own and L.raised and not L.look and s.off < 1 then
		local fx, fy = Finger(wep)
		hot = BtnAt(fx, fy)
	end
	Button(wep, s, "torch", ox + BTN_X, oy + BTN_Y, st.torch, MAT.torch, 30, hot == "torch")
	Button(wep, s, "cam", ox + W - BTN_X, oy + BTN_Y, false, MAT.camera, 30, hot == "cam")
	-- Face ID done: the hint above the home indicator
	if o > 0.5 then
		local a = math.Clamp((o - 0.5) * 2, 0, 1)
		U.T("Swipe up to open", "STTS_LK_Hint", ox + W / 2, oy + H - 46, Color(255, 255, 255, 200 * a))
	end
	U.Round(3, ox + W / 2 - 70, oy + H - 19, 140, 6, Color(255, 255, 255, 235))
	surface.SetAlphaMultiplier(1)
	-- Always-On: the phone is not looked at
	if s.aod > 0.01 and s.off < 1 then U.R(0, 0, W, H, Color(0, 0, 0, 150 * s.aod)) end
	-- a held button pops when it fires
	if s.pop then
		local dt = wep.STTS_UIdt or 0
		for k, v in pairs(s.pop) do s.pop[k] = v > 0.01 and v * math.exp(-dt * 7) or nil end
	end
end

-- status bar: the carrier instead of the time (the big clock is below)
function SCR.LockBar(wep)
	local s = wep.STTS_Lk
	return Shown(wep) and s.off < H * 0.4
end

-- white status bar over the wallpaper (chains the Clock app one)
local prevDark = SCR.StatusDark
if prevDark ~= SCR.STTS_LockDark then
	SCR.STTS_LockDarkPrev = prevDark
	SCR.STTS_LockDark = function(wep, st)
		if Shown(wep, st) then return true end
		if st.app == G.APP_HOME then return true end -- fix61: the home screen has a wallpaper too
		local p = SCR.STTS_LockDarkPrev
		return p and p(wep, st) or false
	end
	SCR.StatusDark = SCR.STTS_LockDark
end
-- smooth frames while the cover sheet moves (also on the phones of others)
local prevFast = SCR.FastRate
if prevFast ~= SCR.STTS_LockFast then
	SCR.STTS_LockFastPrev = prevFast
	SCR.STTS_LockFast = function(wep)
		local s = wep.STTS_Lk
		if s and not s.gone and (s.leaving or s.drag or (s.off or 0) > 0.5 or math.abs(s.ov or 0) > 0.05) then return true end
		if OffMoving(wep) then return true end -- fix61: the display dims / fades out
		local p = SCR.STTS_LockFastPrev
		return p and p(wep) or false
	end
	SCR.FastRate = SCR.STTS_LockFast
end

--[[---------------------------------------------------------------------------
	touch (your own phone): cl_phone_screen.lua asks SCR.LockOwns first; a touch that
	the lock screen owns goes only to this hook (h.lock), not to the app under it
---------------------------------------------------------------------------]]
function SCR.LockOwns(wep, fx, fy)
	if not Shown(wep) then return false end
	if SCR.AlarmShown and SCR.AlarmShown(wep) then return false end -- the ringing alarm is on top
	if (L.shade or 0) > 0.02 then return false end -- the Control Centre is pulled down over it
	return true
end


local function Fire(wep, key)
	local st = wep.STTS_St or {}
	local s = S(wep)
	s.pop = s.pop or {}
	s.pop[key] = 1
	if key == "torch" then
		L.torch, L.torchAt = not st.torch, RealTime()
		U.Act("torch")
	elseif key == "cam" then
		SetUnlk(wep, true, "left")
		if U.SetApp and st.own then U.SetApp(st, G.APP_CAMERA) end
	end
end

LK.Fire = Fire
local HOOK = {name = "lock58", lock = true}
function HOOK.Begin(wep, t, fx, fy)
	if not t.lockK then return end
	local s = S(wep)
	local key = BtnAt(fx, fy)
	if key then
		t.lkBtn = key
		s.press, s.pressAt, s.pressT = key, RealTime(), t
		return
	end
	if fy > H * 0.42 then t.lkSw, t.lkX0, t.lkY0 = true, fx, fy end -- swipe up / left
	s.vel, s.lt, s.ly = 0, RealTime(), fy
end
function HOOK.Move(wep, t, fx, fy)
	if not t.lockK then return end
	local s = S(wep)
	if t.lkBtn then
		local bx = t.lkBtn == "torch" and BTN_X or W - BTN_X
		if not Near(fx, fy, bx, SLIDE_R) and not Near(L.ux, L.uy, bx, SLIDE_R) then -- slid off: nothing
			t.lkBtn, s.press, s.pressT = nil, nil, nil
		elseif not t.lkFired and RealTime() - (s.pressAt or 0) >= HOLD then
			t.lkFired, s.press, s.pressT = true, nil, nil
			Fire(wep, t.lkBtn)
		end
		return true
	end
	if not t.lkSw or not LK.Locked(wep) then return true end
	local ddx, ddy = fx - t.lkX0, fy - t.lkY0
	if not s.drag and not t.lkCam and ddx * ddx + ddy * ddy > 14 * 14 then
		if -ddy > math.abs(ddx) * 0.7 then
			s.drag, s.dir = true, nil
			t.lkY0 = fy + s.off -- no jump (it may still spring back from the last try)
		elseif ddx < 0 and -ddx > math.abs(ddy) then
			t.lkCam = true
		else
			t.lkSw = nil
		end
	end
	if s.drag then
		s.off = math.Clamp(t.lkY0 - fy, 0, H)
		local now = RealTime()
		local dt = now - (s.lt or now)
		if dt > 0.001 then
			s.vel = Lerp(math.Clamp(dt * 18, 0, 1), s.vel or 0, ((s.ly or fy) - fy) / dt)
			s.lt, s.ly = now, fy
		end
	elseif t.lkCam and ddx < -70 then
		t.lkSw, t.lkCam = nil, nil
		Fire(wep, "cam")
	end
	return true
end
function HOOK.End(wep, t, cancel)
	if not t.lockK then return end
	local s = S(wep)
	s.press, s.pressT = nil, nil
	-- fix61: let go on the button before the hold fired = a tap, it fires as well
	if t.lkBtn and not t.lkFired and not cancel then
		t.lkFired = true
		Fire(wep, t.lkBtn)
		return true
	end
	if s.drag then
		s.drag = nil
		local fresh = RealTime() - (s.lt or 0) < 0.12
		if not cancel and LK.Locked(wep) and (s.off > H * 0.2 or (fresh and (s.vel or 0) > 900)) then
			s.v = math.max(fresh and s.vel or 0, 0)
			SetUnlk(wep, true)
		end
	end
	return true
end

SCR.TouchHooks = SCR.TouchHooks or {}
for i = #SCR.TouchHooks, 1, -1 do if SCR.TouchHooks[i].name == HOOK.name then table.remove(SCR.TouchHooks, i) end end
table.insert(SCR.TouchHooks, 1, HOOK)

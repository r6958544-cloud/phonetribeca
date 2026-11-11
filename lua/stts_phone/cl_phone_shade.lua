--[[---------------------------------------------------------------------------
	ZHUNTER phone (fix17) - pull-down shade + the lights of the phone.

	shade (fix18, like a real phone 1:1): put the finger on the top edge of the
	display (status bar area), hold LMB and pull down. the shade is a full-screen
	sheet, its bottom edge sits exactly under the finger the whole time (no
	offset, no fixed panel). let go = it finishes opening / closing on a spring
	that keeps the speed of your hand (a quick flick decides, like on a phone).
	fix19/20: iPhone Control Centre look: the app behind blurs (fix25: plain soft
	blur of the phone display itself) and darkens. v19: the iOS 18 grid (airplane mode,
	Wi-Fi, Now Playing, rotation lock, mirroring, Focus, brightness / volume,
	flashlight, timer, calculator, camera). v19.2: Bluetooth / Cellular are gone,
	Wi-Fi has a menu with the network of the map.
	v19.3: no fade / slide / grow any more. the Control Centre is a sheet whose bottom
	edge is under the finger (the whole display = fully open): above the edge it is
	there exactly as it is when open (blur, modules in place), below the edge there is
	nothing of it, the app is untouched. the edge itself is a strip: a light line with a
	grabber on it and a soft shadow on the app. opening / closing on the spring = the
	same strip running down / up, everything is cut by it. let go after a quarter of
	the display towards the other state (or a flick) = it goes on that way.
	airplane mode, flashlight, brightness, volume and camera do what they say;
	Wi-Fi / rotation lock / Focus are switches of the phone (status bar + Settings).
	  brightness = the whole display of this phone (everybody sees it darker)
	  volume     = every sound of this phone: ringtone (everybody nearby hears it
	               quieter), busy / ringback beeps, the TeleChat "din", the voice
	               of the other side in a call (in your ear and on the speaker)
	both belong to the phone (NW2 "Vol" / "Bright" 0..100, kept in the inventory).
	swipe it back up from anywhere or tap an empty spot = it closes.
	while it is open the app under it gets no touches.
	other players see the same shade on your display (NW2 "Shade").

	lights (everybody sees them, the phone model is the light source):
	  torch         rear LED next to the camera (G.FlashPos), from the shade
	  video light   the LED while a video with the flash records (rear camera)
	  photo flash   LED burst (rear) / soft light on the face (front camera, the display itself stays as is, fix27)
	  front video   soft fill light on the face (no white ring since fix27)
	airplane mode: no calls (in / out, 911 too), no TeleChat out; messages to
	the phone wait on the server and arrive when it is switched off.
---------------------------------------------------------------------------]]
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
STTS.PhoneScreen = SCR
local CLASS = "weapon_stts_phone"

local PANEL = G.RTH -- v19.3: the edge of the sheet = the finger (1:1): fully open at the bottom of the display
local EDGE = 100           -- a drag that starts above this line (and goes down) pulls the shade
local FLICK = 420 / PANEL  -- fix18: flick speed (px/s of the edge) that decides open / closed by itself
local ID_PLANE, ID_TORCH, ID_SHUT = 86, 87, 88
local ORANGE = Color(255, 159, 10)       -- iOS airplane mode
local LED = Color(255, 244, 228)         -- warm white LED

--[[---------------------------------------------------------------------------
	shade: physics (your own phone)
---------------------------------------------------------------------------]]
local function IsOpen(L) return (L.shade or 0) > 0.02 or (L.shadeT or 0) > 0 end

hook.Add("Think", "STTS_PhoneShade", function()
	local L = SCR.L
	if not L then return end
	local now = RealTime()
	local dt = math.Clamp(now - (L.shadeClock or now), 0, 0.1)
	L.shadeClock = now
	if not L.raised then L.shadeT = 0 end -- phone lowered = the shade goes up
	if L.touch and L.touch.shadeDrag then return end
	local x, v, t = L.shade or 0, L.shadeV or 0, L.shadeT or 0
	if x == t and v == 0 then return end
	-- damped spring: response 0.34 s, damping 0.9 (the sheet lands softly, keeps the hand speed)
	local w = 2 * math.pi / 0.34
	local z = 0.9
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		v = v + (w * w * (t - x) - 2 * z * w * v) * h
		x = x + v * h
	end
	if math.abs(x - t) < 0.002 and math.abs(v) < 0.02 then x, v = t, 0 end
	L.shade, L.shadeV = math.Clamp(x, -0.02, 1.1), v
end)

--[[ called by the finger code (cl_shooting_phone_screen.lua TouchBegin / Move / End) ]]
--[[ fix22: sliders of the open Control Centre.
     zone = the whole right part of the shade (left edge = right edge of the modules,
     +SL_PAD px above / below the sliders), split in the middle between the two.
     tested with the mouse point AND the fingertip (whichever is inside).
     the level is ABSOLUTE: the top of the white fill goes exactly where the finger
     is (touch = it jumps there, drag = it follows), no relative "grab" any more:
     that is what made them feel like they do not react / are hard to hit. ]]
local SL_PAD = 70
local function SliderZone(R, x, y)
	if not (R and x and y) then return end
	local pad = R.pad or SL_PAD
	if x < R.left or y < R.top - pad or y > R.bottom + pad then return end
	return x < R.split and "bright" or "vol"
end
SCR.SliderZone = SliderZone
local function SliderAt(R, y)
	return math.Clamp((R.bottom - y) / math.max(R.bottom - R.top, 1), 0, 1)
end
local function ShadeReady(L)
	local R = L.ccRects
	if R and (L.shade or 0) > 0.9 and (L.shadeT or 0) > 0 and RealTime() - (R.at or 0) < 0.6 then return R end
end
local function GrabSlider(wep, t, L, R)
	local key = SliderZone(R, L.ux, L.uy) or SliderZone(R, t.x0, t.y0)
	if not key then return false end
	t.ccSlider, t.ccR = key, R
	t.shadeOpen = true
	L.sel = 0
	SCR.SetLevel(wep, key, SliderAt(R, L.uy or t.y0))
	return true
end

function SCR.ShadeBegin(wep, t)
	local L = SCR.L
	local R = ShadeReady(L)
	if R and GrabSlider(wep, t, L, R) then return end
	if IsOpen(L) then
		t.shadeOpen = true -- every touch belongs to the shade while it is open
	elseif t.y0 < EDGE then
		t.shadeCand = true -- maybe: decided by the direction of the first move
	end
end

function SCR.ShadeMove(wep, t, fx, fy, dx, dy, dragMin)
	local L = SCR.L
	-- fix22: the touch began while the rects were not there yet (first frame of the open
	-- shade): still a slider, never a drag of the shade
	if not t.ccSlider and t.shadeOpen and not t.shadeDrag and not t.moved then
		local R = ShadeReady(L)
		if R and SliderZone(R, t.x0, t.y0) then GrabSlider(wep, t, L, R) end
	end
	if t.ccSlider then
		t.moved = true
		L.sel = 0
		-- fix22: absolute, the raw mouse point (no finger spring lag)
		SCR.SetLevel(wep, t.ccSlider, SliderAt(t.ccR, L.uy or fy))
		return true
	end
	if t.shadeDrag then
		-- fix18: 1:1, the edge of the sheet = the finger (+ where you grabbed it, when it was already open)
		local raw = math.max((fy + t.grab) / PANEL, 0)
		if raw > 1 then raw = 1 + (1 - 1 / ((raw - 1) * 2.5 + 1)) * 0.08 end -- past the end: rubber band
		local now = RealTime()
		local ddt = now - (t.slt or now)
		if ddt > 0.001 then
			t.sv = Lerp(math.Clamp(ddt * 18, 0, 1), t.sv or 0, (raw - (t.sl or raw)) / ddt)
			t.sl, t.slt = raw, now
		end
		L.shade, L.shadeV = raw, 0
		return true
	end
	if t.moved then return false end
	if dx * dx + dy * dy <= dragMin * dragMin then return t.shadeOpen == true end
	if t.shadeOpen or (t.shadeCand and dy > 0 and dy > math.abs(dx)) then
		t.shadeDrag, t.moved = true, true
		local cur = math.Clamp(L.shade or 0, 0, 1)
		-- fix18: pulled from the top = the edge jumps under the finger and follows it;
		-- grabbed while open / moving = it keeps the distance to the finger (no jump)
		t.grab = t.shadeOpen and (cur * PANEL - fy) or 0
		t.shade0 = math.Clamp((fy + t.grab) / PANEL, 0, 1)
		t.was = (L.shadeT or 0) > 0 -- v19.3: where it was going when the finger took it
		L.shade = t.shade0
		t.sl, t.slt, t.sv = t.shade0, RealTime(), 0
		L.sel, L.shadeV = 0, 0
		return true
	end
	return false
end

-- let go: open or closed (position + flick speed).
-- v19.3: the sheet is the whole display now, so not "past the middle": a quarter of the
-- display towards the other state is enough (pull it ~300 px down = it opens, push the
-- open one ~240 px up = it closes), between a quarter and three quarters of the display
local SWITCH = 0.25
function SCR.ShadeEnd(wep, t, cancel)
	if t.ccSlider then SCR.FlushLevel(true) return true end -- fix20: a slider touch never closes the shade
	if not t.shadeDrag then return false end
	local L = SCR.L
	local v = RealTime() - (t.slt or 0) < 0.1 and (t.sv or 0) or 0
	local x0 = t.shade0 or 0
	local line = math.Clamp(t.was and x0 - SWITCH or x0 + SWITCH, SWITCH, 1 - SWITCH)
	local open
	if cancel then open = false
	elseif v > FLICK then open = true
	elseif v < -FLICK then open = false
	else open = (L.shade or 0) > line end
	L.shadeT = open and 1 or 0
	L.shadeV = math.Clamp(v, -8, 8)
	return true
end

--[[ fix20: brightness / volume of a phone (0..1). your own phone: predicted while you
     slide (the server value arrives a moment later), sent at most ~8 times a second ]]
local LVL_NW = {vol = "Vol", bright = "Bright"}
function SCR.Level(wep, key)
	local L = SCR.L
	if L and L.wep == wep and L[key .. "At"] and RealTime() - L[key .. "At"] < 1 then return L[key] end
	if not IsValid(wep) then return 1 end
	return math.Clamp(wep:GetNW2Int(LVL_NW[key], 100), 0, 100) / 100
end
function SCR.SetLevel(wep, key, v)
	local L = SCR.L
	v = math.Clamp(v, 0, 1)
	L[key], L[key .. "At"] = v, RealTime()
	L.lvlPend = L.lvlPend or {}
	L.lvlPend[key] = math.Round(v * 100)
	SCR.FlushLevel(false)
end
function SCR.FlushLevel(final)
	local L = SCR.L
	if not (L and L.lvlPend) then return end
	local now = RealTime()
	if not final and now - (L.lvlSent or 0) < 0.12 then return end -- the Think sends the rest
	if final and now - (L.lvlSent or 0) < 0.06 then L.lvlFinal = true return end
	for key, n in pairs(L.lvlPend) do
		if SCR.UI and SCR.UI.Act then SCR.UI.Act(key, tostring(n)) end
		L[key .. "At"] = now
	end
	L.lvlPend, L.lvlSent, L.lvlFinal = nil, now, nil
end
hook.Add("Think", "STTS_PhoneLevels", function()
	local L = SCR.L
	if L and L.lvlPend and RealTime() - (L.lvlSent or 0) >= (L.lvlFinal and 0.06 or 0.12) then SCR.FlushLevel(true) end
end)

-- volume of the phone you carry (held or in the pocket): client sounds of the phone use it
local function MyVolume()
	local lp = LocalPlayer()
	local w = IsValid(lp) and lp:GetWeapon(CLASS)
	if not IsValid(w) then return 1 end
	return SCR.Level(w, "vol")
end
STTS.PhoneVolume = MyVolume
-- a phone sound only you hear (ringback, busy, TeleChat din), at the volume of your phone
function STTS.PhoneSound(path)
	local v = MyVolume()
	if v <= 0.005 then return end
	sound.PlayFile("sound/" .. path, "noblock", function(ch) if IsValid(ch) then ch:SetVolume(v) ch:Play() end end)
end

-- fix20: brightness = the whole display gets darker (status bar and the shade too, like iOS).
-- fix27: the display no longer goes white with the flash, so it is always dimmed normally
function SCR.DrawDim(wep, st)
	local U = SCR.UI
	if not U then return end
	local b = SCR.Level(wep, "bright")
	if b >= 0.995 then return end
	U.R(0, 0, U.W, U.H, Color(0, 0, 0, 225 * (1 - b) ^ 1.2))
end

-- airplane mode on your phone: blocks sending (toast "Airplane mode")
function SCR.PlaneBlocked()
	local L = SCR.L
	local wep = L and L.wep
	if not IsValid(wep) then return false end
	local on = wep:GetNW2Bool("Plane", false)
	if L.planeAt and RealTime() - L.planeAt < 0.8 then on = L.plane end
	if on then L.toast, L.toastAt = "Airplane mode", RealTime() end
	return on
end

--[[---------------------------------------------------------------------------
	shade: drawing (any phone; called from DrawOverlays, before the status bar)
---------------------------------------------------------------------------]]
local function Openness(wep, st)
	if st.own then return math.max((SCR.L and SCR.L.shade) or 0, 0) end
	local want = wep:GetNW2Int("Shade", 0) / 40
	local now = RealTime()
	local dt = math.Clamp(now - (wep.STTS_ShT or now), 0, 0.2)
	wep.STTS_ShT = now
	local s = wep.STTS_ShS or want
	s = Lerp(1 - math.exp(-dt * 12), s, want)
	if math.abs(s - want) < 0.003 then s = want end
	wep.STTS_ShS = s
	wep.STTS_ShMove = s ~= want -- the screen of this phone refreshes faster meanwhile
	return s
end


--[[ iOS 18 Control Centre: a 4 column grid (u = one cell, g = gap).
       [ Airplane 2x1 ]      [ Now Playing 2x2 ]
       [ Wi-Fi    2x1 ]      [                 ]
       [ Rot ] [ Mirr ]      [ Bright ] [ Vol ]   (sliders: 1x2)
       [ Focus  2x1  ]       [        ] [     ]
       [ Torch ] [ Timer ] [ Calc ] [ Camera ]
     airplane mode, flashlight, brightness, volume and the camera do what they say,
     Wi-Fi / rotation lock / Focus are switches of the phone (everybody sees them, the
     status bar + Settings follow). v19.2: Bluetooth / Cellular are gone; the circle of
     the Wi-Fi control switches it, its name opens the Wi-Fi menu with the one network
     there is: the map (game.GetMap(), e.g. gm_flatgrass). v19.3: opening / closing =
     the edge of the sheet uncovers / covers the grid, nothing in it moves. ]]
local CCI = {
	sun = Material("stts/cc_sun.png", "smooth mips"), speaker = Material("stts/cc_speaker.png", "smooth mips"),
	wifi = Material("stts/cc_wifi.png", "smooth mips"), rot = Material("stts/cc_rotlock.png", "smooth mips"),
	moon = Material("stts/cc_moon.png", "smooth mips"), timer = Material("stts/cc_timer.png", "smooth mips"),
	camera = Material("stts/cc_camera.png", "smooth mips"),
	-- fix61: Framework7 Icons (MIT): circle_righthalf_fill = Dark Mode, alarm_fill = Alarm
	dark = Material("stts/cc_dark.png", "smooth mips"), alarm = Material("stts/cc_alarm.png", "smooth mips"),
	play = Material("stts/cc_play.png", "smooth mips"), next = Material("stts/cc_next.png", "smooth mips"),
	prev = Material("stts/cc_prev.png", "smooth mips"),
}
local ID_BRIGHT, ID_VOL = 95, 96
-- wmenu / wtog / wnet / wset / wout / wpan = the Wi-Fi menu (name of the control, its switch,
-- the network, "Wi-Fi Settings...", outside = close, the panel itself)
local ID = {wifi = 90, rot = 92, dark = 93, focus = 94, np = 97, timer = 98, alarm = 99, camera = 81,
	wmenu = 82, wtog = 83, wnet = 84, wset = 85, wout = 100, wpan = 101}
local MOD = Color(255, 255, 255, 48)         -- module glass (a bit brighter: the engine blur is softer than iOS)
local MODH = Color(255, 255, 255, 64)        -- module glass under the finger
local OFF = Color(255, 255, 255, 58)         -- a switched off circle inside a module
local OFFH = Color(255, 255, 255, 78)        -- ... under the finger
local RIM = Color(255, 255, 255, 46)         -- hairline glass edge (reads as "glass" even on a plain black blur)
local ART = Color(255, 255, 255, 34)         -- Now Playing: empty artwork
local DIM = Color(255, 255, 255, 150)        -- secondary text on the glass
local DIM2 = Color(255, 255, 255, 110)       -- disabled transport buttons
local AIRP = Color(255, 255, 255, 200)
local MENU = Color(38, 38, 40, 236)          -- the Wi-Fi menu platter
local SEP = Color(255, 255, 255, 34)         -- hairlines inside the menu
local MHOV = Color(255, 255, 255, 26)        -- a menu row under the finger
local WHITE2 = Color(245, 245, 247)
local DARKGLYPH = Color(28, 28, 30)
local BLUE = Color(10, 132, 255)
local PURPLE = Color(94, 92, 230)

--[[ v19.2: linear-light fix (SCR.LinState, cl_shooting_phone_screen.lua): what the drawn
     colours sit on. b1 = the darkened blur behind the modules, b2 = the module glass ]]
local SH = {b1 = 0.04, b2 = 0.22}
--[[ v19.3: CLIPY = the edge of the sheet (RT px) while the Control Centre is drawn: no
     module below that line (v19.4: the blur and the dim behind are not cut by it).
     NoClip() goes back to that cut (not to "no scissor at all"), ClipTo() of a module is
     always inside it ]]
local CLIPY
local function NoClip()
	if CLIPY then render.SetScissorRect(0, 0, G.RTW, CLIPY, true)
	else render.SetScissorRect(0, 0, 0, 0, false) end
end
local function BG(v)
	local LS = SCR.LinState
	if LS then LS.bg = v end
end
-- a glass module: translucent fill + crisp hairline rim. on = solid (no rim, like iOS)
local function GlassRound(U, r, x, y, w, h, fill, on)
	BG(SH.b1)
	U.Round(r, x, y, w, h, fill)
	BG(SH.b2)
	if not on and U.RoundRim then U.RoundRim(r, x, y, w, h, 1.5, RIM) end
end
local function GlassCircle(U, cx, cy, rad, fill, on)
	BG(SH.b1)
	U.Circle(cx, cy, rad, fill)
	BG(SH.b2)
	if not on and U.CircleRim then U.CircleRim(cx, cy, rad, 1.5, RIM) end
end
local function Glyph(U, mat, cx, cy, size, col, fb)
	if mat and not mat:IsError() then
		surface.SetMaterial(mat) surface.SetDrawColor(U.LinCol and U.LinCol(col) or col)
		surface.DrawTexturedRect(cx - size / 2, cy - size / 2, size, size)
	elseif fb then -- content not mounted yet
		U.T(fb, "STTS_I_Cap", cx, cy, col)
	end
end

--[[ fix25: backdrop = plain soft blur of THIS display ("мыло").
     fix24 used pp/blurscreen: that shader samples the GAME framebuffer, not the
     phone RT, so behind the shade you saw a smeared, zoomed copy of the world.
     now: the phone RT (what is already drawn on this display) is downscaled
     into a small RT, render.BlurRenderTarget blurs it (gaussian, 2 passes) and
     it is stretched back over the display (bilinear = even softer). works on every
     phone (others see your shade too). v19.4: over the WHOLE display while the sheet
     moves (not only above its edge), and the further it is pulled (k 0..1) the stronger:
     a wider blur, faded in over the sharp app, a darker scrim.
     stts_phone_shade_blur: 1 = normal, 0 = no blur (only darkening), 2+ = stronger ]]
local BLUR_W, BLUR_H = 144, 320 -- 1/3 of the 432x960 display (less blocky than 1/4 when stretched back)
-- new RT name: GetRenderTargetEx returns a cached texture by name, an old 108x240 one would be reused.
-- texture flags 4 + 8 = clamp S/T: the blur must not wrap the bottom edge into the top (and the reverse)
local blurRT = GetRenderTargetEx("stts_phone_shblur19", BLUR_W, BLUR_H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGB888)
local blurOut = CreateMaterial("stts_phone_shblur19_out", "UnlitGeneric", {["$basetexture"] = blurRT:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$ignorez"] = 1})
local blurSrc = CreateMaterial("stts_phone_shblur19_src", "UnlitGeneric", {["$basetexture"] = "color/black", ["$ignorez"] = 1})
local blurCvar = CreateClientConVar("stts_phone_shade_blur", "1", true, false, "blur behind the phone shade: 0 = off, 1 = normal, 2+ = stronger", 0, 4)
local function Backdrop(U, k)
	local W, H = U.W, U.H
	local amt = blurCvar:GetFloat()
	local src = amt > 0.01 and render.GetRenderTarget() or nil
	-- v19.4: no scissor at all here: the blur and the scrim lie over the whole display
	render.SetScissorRect(0, 0, 0, 0, false)
	if src then
		blurSrc:SetTexture("$basetexture", src)
		render.PushRenderTarget(blurRT)
			render.Clear(0, 0, 0, 255)
			render.SetMaterial(blurSrc)
			render.DrawScreenQuad()
			-- more passes with a smaller radius = a smooth, even frost (not a few big blocky lobes).
			-- the radius grows with the pull (a fifth of it right at the top)
			local r = 2.4 * amt * (0.2 + 0.8 * k)
			render.BlurRenderTarget(blurRT, r, r, math.Clamp(math.ceil(amt * 3), 2, 8))
		render.PopRenderTarget()
		-- faded in over the sharp app during the first ~60 % of the pull (no hard pop of the frost)
		surface.SetMaterial(blurOut)
		surface.SetDrawColor(255, 255, 255, 255 * math.Clamp(k * 1.7, 0, 1))
		surface.DrawTexturedRect(0, 0, W, H)
	end
	-- iOS Control Centre dim: a darker scrim so the (translucent) modules read as bright frosted
	-- glass and the colours behind do not bleed through as blobs. no blur available = still darkens.
	-- v19.4: it darkens together with the pull
	U.R(0, 0, W, H, Color(0, 0, 0, (src and 150 or 180) * k))
	NoClip() -- from here on (the modules): only above the edge
end

--[[ fix22: text that NEVER leaves its box: the biggest font that fits (with an 8 %
     safety margin), otherwise the smallest font squeezed by a matrix, the last
     resort is a cut with "...". plus a hard clip to the module (scissor) ]]
local function FitText(U, text, w, fonts, x, y, col)
	w = math.max(w, 8) * 0.92
	for _, f in ipairs(fonts) do
		surface.SetFont(f)
		if surface.GetTextSize(text) <= w then U.T(text, f, x, y, col, TEXT_ALIGN_LEFT) return end
	end
	local f = fonts[#fonts]
	surface.SetFont(f)
	local tw = surface.GetTextSize(text)
	local k = w / math.max(tw, 1)
	if k >= 0.62 then
		local m = Matrix()
		m:Translate(Vector(x, y, 0))
		m:Scale(Vector(k, k, 1))
		m:Translate(Vector(-x, -y, 0))
		cam.PushModelMatrix(m, true)
		U.T(text, f, x, y, col, TEXT_ALIGN_LEFT)
		cam.PopModelMatrix()
		return
	end
	while #text > 1 and surface.GetTextSize(text .. "...") > w do text = string.sub(text, 1, -2) end
	U.T(text .. "...", f, x, y, col, TEXT_ALIGN_LEFT)
end

--[[ every module has its own transform (v19.3: only the hover / press pop).
     CC_MTX = the transform of the module being drawn (for the scissor clips):
     scaled by sc around (cx, cy), then moved by (dx, dy). a = alpha of the whole grid ]]
local CC_MTX = {cx = 0, cy = 0, sc = 1, dx = 0, dy = 0, a = 1}
local function CCtoRT(x, y)
	local c = CC_MTX
	return c.cx + c.dx + (x - c.cx) * c.sc, c.cy + c.dy + (y - c.cy) * c.sc
end
local function ClipTo(x1, y1, x2, y2)
	local ax, ay = CCtoRT(x1, y1)
	local bx, by = CCtoRT(x2, y2)
	ay, by = math.floor(ay), math.ceil(by)
	if CLIPY then by = math.min(by, CLIPY) ay = math.min(ay, by) end -- never below the edge of the sheet
	render.SetScissorRect(math.floor(ax), ay, math.ceil(bx), by, true)
end
local function PushM(cx, cy, sc, dx, dy, alpha)
	CC_MTX.cx, CC_MTX.cy, CC_MTX.sc, CC_MTX.dx, CC_MTX.dy = cx, cy, sc, dx, dy
	local m = Matrix()
	m:Translate(Vector(cx + dx, cy + dy, 0))
	m:Scale(Vector(sc, sc, 1))
	m:Translate(Vector(-cx, -cy, 0))
	cam.PushModelMatrix(m, true)
	alpha = math.Clamp(alpha, 0, 1)
	-- linear-light blending: a fade of light things on the dark glass needs alpha ^ 2.2 to look the same
	local LS = SCR.LinState
	if LS and LS.on then alpha = alpha ^ 2.2 end
	surface.SetAlphaMultiplier(alpha)
end
--[[ v19.3: the modules do not animate while the Control Centre opens / closes any more
     (v19.2 slid the rows down and faded them in): they sit in place and the edge of the
     sheet uncovers them. pop = hover / press of the module ]]
local function Push(x, y, w, h, pop)
	PushM(x + w / 2, y + h / 2, pop or 1, 0, 0, CC_MTX.a)
end
local function Pop()
	surface.SetAlphaMultiplier(1)
	cam.PopModelMatrix()
end
-- hover / press of one module: grows a little while pressed (iOS Control Centre feel)
local function Feel(U, wep, st, id)
	local hov, press = st.sel == id, U.Pressed(wep, st, id)
	local t = wep.STTS_IconK or {}
	wep.STTS_IconK = t
	local key = "ccm" .. id
	local k = Lerp(1 - math.exp(-(wep.STTS_UIdt or 0) * 20), t[key] or 1, press and 1.07 or (hov and 1.025 or 1))
	t[key] = k
	return k, hov, press
end

-- tall slider (brightness / volume): white fill from the bottom (clipped to the capsule), glyph at the bottom
local function Slider(U, btns, id, x, y, w, h, lvl, mat, fb, held, hov)
	local r = w * 0.46
	GlassRound(U, r, x, y, w, h, (held or hov) and MODH or MOD)
	local fh = h * lvl
	if fh > 0.5 then
		ClipTo(x, y + h - fh, x + w, y + h)
		U.Round(r, x, y, w, h, WHITE2)
		NoClip()
	end
	-- the glyph changes colour exactly at the fill line (white above, grey on the fill)
	local gy, gs = y + h - w * 0.5, w * 0.4
	local line = y + h - fh
	if line > gy - gs / 2 then
		ClipTo(x, y, x + w, math.min(line, y + h))
		Glyph(U, mat, x + w / 2, gy, gs, color_white, fb)
		NoClip()
	end
	if line < gy + gs / 2 then
		ClipTo(x, math.max(line, y), x + w, y + h)
		Glyph(U, mat, x + w / 2, gy, gs, Color(110, 110, 118), fb)
		NoClip()
	end
end

-- a 2x1 control: glass capsule, round icon on the left, one or two lines of text
-- (l2 + c2 = a smaller grey second line, l2 alone = the title goes on over two lines,
-- both lines in the same size)
local TITLE = {"STTS_I_Status", "STTS_I_Cap"}
local function Capsule(U, x, y, w, h, fill, on, circle, mat, gsize, fb, l1, l2, c1, c2)
	GlassRound(U, h / 2, x, y, w, h, fill, on)
	local cx, cy = x + h / 2, y + h / 2
	U.Circle(cx, cy, 26, circle)
	Glyph(U, mat, cx, cy, gsize, color_white, fb)
	local tx = x + h - 9
	ClipTo(tx - 2, y + 4, x + w - 5, y + h - 4)
	local tw = x + w - 6 - tx
	if l2 and c2 then
		FitText(U, l1, tw, TITLE, tx, cy - 12, c1)
		FitText(U, l2, tw, {"STTS_I_Cap"}, tx, cy + 13, c2)
	elseif l2 then
		local font = TITLE[#TITLE]
		for _, f in ipairs(TITLE) do
			surface.SetFont(f)
			local a = surface.GetTextSize(l1)
			local b = surface.GetTextSize(l2)
			if math.max(a, b) <= tw * 0.92 then font = f break end
		end
		FitText(U, l1, tw, {font}, tx, cy - 13, c1)
		FitText(U, l2, tw, {font}, tx, cy + 13, c1)
	else
		FitText(U, l1, tw, TITLE, tx, cy, c1)
	end
	NoClip()
end

-- second line of Wi-Fi (the control, the menu header)
local function WifiSub(ws)
	if ws == "on" then return SCR.WifiNet and SCR.WifiNet() or "Wi-Fi" end
	if ws == "join" then return "Connecting…" end
	if ws == "none" then return "Not Connected" end
	return "Off"
end

--[[ v19.2: the Wi-Fi menu (iOS: the expanded Wi-Fi control). a dark platter grows out of
     the Wi-Fi control: header (Wi-Fi, what it is connected to, its switch), the network of
     the map (tap = join: spinner, then the check mark; the status bar gets the Wi-Fi fan),
     "Wi-Fi Settings..." = Settings > Wi-Fi. a tap outside closes it ]]
local function WifiMenu(U, wep, st, btns, mk, fx, fy, Act)
	local W = U.W
	local L = SCR.L
	local ws = SCR.WifiState and SCR.WifiState(wep, st) or "off"
	local net = SCR.WifiNet and SCR.WifiNet() or "Wi-Fi"
	local px, pw, py = 24, W - 48, 128
	local HH, NR, FR = 104, 76, 74
	local hasNet = ws ~= "off"
	local ph = HH + (hasNet and NR or 0) + FR
	local live = mk > 0.97 and st.own and L
	local cx, cy = px + pw / 2, py + ph / 2
	PushM(cx, cy, Lerp(mk, 0.4, 1), (fx - cx) * (1 - mk), (fy - cy) * (1 - mk), mk * 1.7)
	BG(SH.b1)
	U.Round(38, px, py, pw, ph, MENU)
	BG(0.16)
	if U.RoundRim then U.RoundRim(38, px, py, pw, ph, 1.5, RIM) end
	local function Hover(id, x, y, w, h, last)
		local hk = U.HoverK(wep, "ccw" .. id, st.sel == id)
		if hk <= 0.01 then return end
		local col = Color(255, 255, 255, (U.Pressed(wep, st, id) and 46 or MHOV.a) * hk)
		if last then
			draw.RoundedBoxEx(38, x, y, w, h, U.LinCol and U.LinCol(col) or col, false, false, true, true)
		else
			U.R(x, y, w, h, col)
		end
	end
	-- header: "Wi-Fi", what it is connected to, the switch on the right
	local tx = px + 28
	U.T("Wi-Fi", "STTS_I_BodyB", tx, py + 38, color_white, TEXT_ALIGN_LEFT)
	ClipTo(px + 16, py + 54, px + pw - 100, py + 90)
	U.T(WifiSub(ws), "STTS_I_Sub", tx, py + 70, DIM, TEXT_ALIGN_LEFT)
	NoClip()
	local tcx, tcy = px + pw - 60, py + HH / 2
	local hov = st.sel == ID.wtog
	local ts = U.PopScale and U.PopScale(wep, "ccwt", hov, U.Pressed(wep, st, ID.wtog)) or 1
	U.Circle(tcx, tcy, 31 * ts, hasNet and BLUE or (hov and OFFH or OFF))
	Glyph(U, CCI.wifi, tcx, tcy, 30 * ts, color_white, "W")
	if live then U.Reg(btns, ID.wtog, tcx - 42, tcy - 42, 84, 84, Act("wifi")) end
	local y = py + HH
	U.R(px + 24, y - 1, pw - 48, 1, SEP)
	-- the network of the map
	if hasNet then
		if live then U.Reg(btns, ID.wnet, px, y, pw, NR, function() if SCR.WifiJoin then SCR.WifiJoin(wep, st) end end) end
		Hover(ID.wnet, px, y, pw, NR)
		local ry = y + NR / 2
		if ws == "on" and U.Check then U.Check(px + 42, ry, 9, color_white, 3.5)
		elseif ws == "join" and U.Spinner then U.Spinner(px + 42, ry, 12, color_white) end
		ClipTo(px + 64, y, px + pw - 104, y + NR)
		U.T(net, "STTS_I_Body", px + 72, ry, color_white, TEXT_ALIGN_LEFT)
		NoClip()
		if U.Lock then U.Lock(px + pw - 82, ry, color_white) end
		-- v19.3: the fan shows how good the internet is right here (zones of the map)
		if U.WifiGlyph and SCR.WifiLevel then U.WifiGlyph(px + pw - 44, ry, 26, color_white, SCR.WifiLevel(wep))
		else Glyph(U, CCI.wifi, px + pw - 44, ry, 26, color_white) end
		y = y + NR
		U.R(px + 24, y - 1, pw - 48, 1, SEP)
	end
	-- Wi-Fi Settings...
	if live then
		U.Reg(btns, ID.wset, px, y, pw, FR, function()
			L.wmenu, L.shadeT = nil, 0
			if U.SetApp and G.APP_WIFI then U.SetApp(st, G.APP_WIFI) end
		end)
	end
	Hover(ID.wset, px, y, pw, FR, true)
	U.T("Wi-Fi Settings…", "STTS_I_Body", tx, y + FR / 2, color_white, TEXT_ALIGN_LEFT)
	-- a tap on the platter itself (between the rows) keeps it open
	if live then U.Reg(btns, ID.wpan, px, py, pw, ph, function() end) end
	Pop()
	return live
end

-- fix54: what the ZMusic tile / player platter (cl_phone_music.lua) draws with
local KIT = {GlassRound = GlassRound, Glyph = Glyph, ClipTo = ClipTo, NoClip = NoClip, PushM = PushM, Pop = Pop,
	Feel = Feel, FitText = FitText, BG = BG, SH = SH, CCI = CCI, MOD = MOD, MODH = MODH, ART = ART, DIM = DIM,
	DIM2 = DIM2, AIRP = AIRP, MENU = MENU, SEP = SEP, MHOV = MHOV, RIM = RIM, ID_NP = ID.np}
function SCR.DrawShade(wep, st, btns)
	local U = SCR.UI
	if not U then return end
	local o = Openness(wep, st)
	local L = SCR.L
	if st.own and L then L.ccRects = nil end
	if o <= 0.003 then
		wep.STTS_CCy, CLIPY = 0, nil
		if st.own and L then L.wmenu, L.zmenu = nil, nil end
		return
	end
	local W, H = U.W, U.H
	local k = math.Clamp(o, 0, 1)
	-- v19.3: the edge of the sheet (under the finger while it is pulled): no module below it
	-- (the status bar uses it too: carrier above, clock below). v19.4: the blur and the dim
	-- are not cut by it (whole display, stronger the further down)
	local ey = k * H
	wep.STTS_CCy = ey
	CLIPY = math.floor(ey + 0.5)
	-- the app under the shade gets no touches
	for i = #btns, 1, -1 do btns[i] = nil end
	btns.zones = nil
	Backdrop(U, k)
	local cc = st.cc or {}
	-- what the glass sits on (linear-light fix): the blur of a light app is lighter.
	-- v19.4: half pulled = the app shows through the thinner dim
	local thk = wep.STTS_ThK or 0
	SH.b1 = Lerp(k, Lerp(thk, 0.05, 0.96), Lerp(thk, 0.04, 0.4))
	SH.b2 = SH.b1 + (1 - SH.b1) * 0.19
	-- the Wi-Fi menu (own phone): the grid fades back while it is open
	local mk = 0
	if st.own and L then mk = U.SpringK(wep, "ccwm", L.wmenu == true and (L.shadeT or 0) > 0, 0.34, 0.8) end
	-- fix54: the ZMusic player platter (a tap on the Now Playing tile)
	local zk = 0
	if st.own and L then zk = U.SpringK(wep, "cczm", L.zmenu == true and (L.shadeT or 0) > 0, 0.36, 0.8) end
	local active = k > 0.97 and mk < 0.02 and zk < 0.02

	-- grid
	local u, g = 80, 16
	local m = (W - 4 * u - 3 * g) / 2
	local y0 = 128
	local function X(c) return m + c * (u + g) end
	local function Y(r) return y0 + r * (u + g) end
	local big = 2 * u + g
	CC_MTX.a = 1 - 0.85 * math.Clamp(math.max(mk, zk), 0, 1)
	local function Act(key)
		return function()
			if not st.own then return end
			if key == "plane" then
				L.plane, L.planeAt = not st.plane, RealTime()
				U.Act("plane")
			elseif key == "torch" then
				L.torch, L.torchAt = not st.torch, RealTime()
				U.Act("torch")
			elseif SCR.ToggleCC then SCR.ToggleCC(wep, st, key) end
		end
	end
	local function Nop() end

	-- airplane mode (2x1): the whole control is the switch
	do
		local x, y = X(0), Y(0)
		local s, hov = Feel(U, wep, st, ID_PLANE)
		Push(x, y, big, u, s)
		if active then U.Reg(btns, ID_PLANE, x, y, big, u, Act("plane")) end
		Capsule(U, x, y, big, u, hov and MODH or MOD, false, st.plane and ORANGE or (hov and OFFH or OFF),
			U.icons and U.icons.plane, 30, "A", "Airplane", "Mode", color_white)
		Pop()
	end

	-- Wi-Fi (2x1): the circle switches it, the name opens the Wi-Fi menu
	local wfx, wfy = X(0) + big / 2, Y(1) + u / 2
	do
		local x, y = X(0), Y(1)
		local ws = SCR.WifiState and SCR.WifiState(wep, st) or (cc.wifi and "on" or "off")
		local s1, hov1 = Feel(U, wep, st, ID.wifi)
		local s2, hov2 = Feel(U, wep, st, ID.wmenu)
		Push(x, y, big, u, math.max(s1, s2))
		if active then
			U.Reg(btns, ID.wifi, x, y, u, u, Act("wifi"))
			U.Reg(btns, ID.wmenu, x + u, y, big - u, u, function() if st.own then L.wmenu = true end end)
		end
		Capsule(U, x, y, big, u, (hov1 or hov2) and MODH or MOD, false, ws ~= "off" and BLUE or (hov1 and OFFH or OFF),
			CCI.wifi, 27, "W", "Wi-Fi", WifiSub(ws), color_white, DIM)
		Pop()
	end

	-- now playing (2x2)
	do
		local x, y = X(2), Y(0)
		local s, hov = Feel(U, wep, st, ID.np)
		Push(x, y, big, big, s)
		-- fix54: ZMusic plays on this phone = its song and working controls
		local zm = SCR.ZMTile and SCR.ZMTile(KIT, wep, st, btns, x, y, big, active, hov)
		if not zm then
			if active then U.Reg(btns, ID.np, x, y, big, big, function() if st.own and SCR.ZMTile then L.zmenu = true end end) end
			GlassRound(U, 38, x, y, big, big, hov and MODH or MOD)
			U.Round(10, x + 20, y + 20, 46, 46, ART)
			ClipTo(x + 16, y + 70, x + big - 12, y + 112)
			U.T("Not Playing", "STTS_I_Status", x + 22, y + 92, DIM, TEXT_ALIGN_LEFT)
			NoClip()
			local cyb = y + big - 42
			Glyph(U, CCI.prev, x + big * 0.22, cyb, 30, DIM2)
			Glyph(U, CCI.play, x + big * 0.5, cyb, 28, DIM2)
			Glyph(U, CCI.next, x + big * 0.78, cyb, 30, DIM2)
		end
		Pop()
	end

	-- rotation lock (fix61: T does nothing while it is on), Dark Mode (fix61: was Screen
	-- Mirroring, which did nothing: the theme of Settings > Display & Brightness) (1x1 round)
	local dark = (SCR.ThemeTarget and SCR.ThemeTarget(wep) or 0) == 0
	local function DarkAct()
		if st.own and SCR.SetTheme then SCR.SetTheme(wep, st, dark and 1 or 0) end
	end
	for i, it in ipairs({{ID.rot, cc.rotlock, Color(255, 59, 48), CCI.rot, Act("rotlock"), 0.98},
		{ID.dark, dark, Color(28, 28, 30), CCI.dark, DarkAct, 0.86}}) do
		local x, y = X(i - 1), Y(2)
		local s, hov = Feel(U, wep, st, it[1])
		Push(x, y, u, u, s)
		if active then U.Reg(btns, it[1], x, y, u, u, it[5]) end
		GlassCircle(U, x + u / 2, y + u / 2, u / 2, it[2] and WHITE2 or (hov and MODH or MOD), it[2])
		Glyph(U, it[4], x + u / 2, y + u / 2, u * 0.46 * it[6], it[2] and it[3] or color_white, "?")
		Pop()
	end

	-- focus (2x1 capsule)
	do
		local x, y = X(0), Y(3)
		local on = cc.focus
		local s, hov = Feel(U, wep, st, ID.focus)
		Push(x, y, big, u, s)
		if active then U.Reg(btns, ID.focus, x, y, big, u, Act("focus")) end
		if on then
			Capsule(U, x, y, big, u, WHITE2, true, PURPLE, CCI.moon, 28, "F", "Do Not", "Disturb", DARKGLYPH)
		else
			Capsule(U, x, y, big, u, hov and MODH or MOD, false, OFF, CCI.moon, 28, "F", "Focus", nil, color_white)
		end
		Pop()
	end

	-- brightness / volume (1x2 sliders)
	local held = st.own and L and L.touch and L.touch.ccSlider
	local sx1, sx2, sy, sh = X(2), X(3), Y(2), big
	local pad = 10
	local left, split = sx1 - g / 2, sx2 - g / 2
	for _, it in ipairs({{ID_BRIGHT, sx1, "bright", CCI.sun, "*", {left, sy - pad, split - left, sh + 2 * pad}},
		{ID_VOL, sx2, "vol", CCI.speaker, "V", {split, sy - pad, W - split, sh + 2 * pad}}}) do
		local hit = it[6]
		if active then U.Reg(btns, it[1], hit[1], hit[2], hit[3], hit[4], Nop) end
		local grow = held == it[3] and 1.05 or (st.sel == it[1] and 1.02 or 1)
		Push(it[2], sy, u, sh, grow)
		Slider(U, btns, it[1], it[2], sy, u, sh, SCR.Level(wep, it[3]), it[4], it[5], held == it[3], st.sel == it[1])
		Pop()
	end
	if st.own and L and active then
		L.ccRects = {left = left, split = split, top = sy, bottom = sy + sh, h = sh, at = RealTime(), pad = pad}
	end

	-- flashlight, timer, alarm, camera (1x1 round). fix61: Timer opens Clock > Timers (it did
	-- nothing), Alarm (was Calculator, there is no calculator app) opens Clock > Alarms
	local function Clock(tab)
		return function()
			if not st.own then return end
			L.shadeT = 0
			if SCR.ClockOpen then SCR.ClockOpen(wep, st, tab) end
		end
	end
	local row = {
		{ID_TORCH, st.torch, U.icons and U.icons.torch, Act("torch"), 0.9},
		{ID.timer, false, CCI.timer, Clock(4), 0.92},
		{ID.alarm, false, CCI.alarm, Clock(2), 0.9},
		{ID.camera, false, CCI.camera, function()
			if not st.own then return end
			L.shadeT = 0
			if U.SetApp and st.app ~= G.APP_CAMERA then U.SetApp(st, G.APP_CAMERA) end
		end, 0.92},
	}
	for i, it in ipairs(row) do
		local x, y = X(i - 1), Y(4)
		local s, hov = Feel(U, wep, st, it[1])
		Push(x, y, u, u, s)
		if active then U.Reg(btns, it[1], x, y, u, u, it[4]) end
		GlassCircle(U, x + u / 2, y + u / 2, u / 2, it[2] and WHITE2 or (hov and MODH or MOD), it[2])
		Glyph(U, it[3], x + u / 2, y + u / 2, u * 0.46 * it[5], it[2] and DARKGLYPH or color_white, "?")
		Pop()
	end
	CC_MTX.a = 1

	-- the Wi-Fi menu on top; a tap anywhere else closes it (not the shade)
	if mk > 0.003 and WifiMenu(U, wep, st, btns, mk, wfx, wfy, Act) then
		U.Reg(btns, ID.wout, 0, 0, W, H, function() L.wmenu = nil end)
	end
	-- fix54: the ZMusic player platter on top (same: a tap outside closes it)
	if zk > 0.003 and SCR.ZMPlatter and SCR.ZMPlatter(KIT, wep, st, btns, zk, X(2) + big / 2, Y(0) + big / 2) then
		U.Reg(btns, ID.wout, 0, 0, W, H, function() L.zmenu = nil end)
	end
	-- v19.4: no strip on the edge any more (the edge only shows where it uncovers the modules)
	CLIPY = nil
	NoClip()
	BG(0.05)

	-- tap an empty spot = close (every module was registered first, they win)
	if active then
		U.Reg(btns, ID_SHUT, 0, 0, W, H, function() if st.own then SCR.L.shadeT = 0 end end)
	end
end

--[[---------------------------------------------------------------------------
	lights
---------------------------------------------------------------------------]]
local cvShadows = CreateClientConVar("stts_phone_light_shadows", "1", true, false, "phone torch / flash: shadows (0 = cheaper)", 0, 1)
-- fix61: 2 projected lights (was 3), only the nearest one casts shadows (each shadowed light
-- renders the scene once more), configurable
local cvMaxPT = CreateClientConVar("stts_phone_light_max", "2", true, false, "phone torch / flash: projected lights at once (the nearest phones)", 0, 4)
local LIGHTS = {} -- [phone] = {pt = ProjectedTexture, last parameters}
-- fix26: the photo flash was blinding (x13 brightness + a huge glow) and the torch too bright.
-- both toned down, tunable on the client (1 = new default, 0 = off)
local cvTorch = CreateClientConVar("stts_phone_torch_mul", "1", true, false, "phone torch brightness multiplier (fix26 default is already darker)", 0, 3)
local cvFlash = CreateClientConVar("stts_phone_flash_mul", "1", true, false, "phone photo flash brightness multiplier (fix26 default is already softer)", 0, 3)
local FAR_PT = 3000 * 3000 -- fix61: farther phones: no projected light, no glow
local FAR_GLOW = 1500 * 1500

--[[ fix61: the light only needs 4 NW2 values (+ the prediction of your own phone). it used
     to build the whole screen state (SCR.State: photo lists parsed, gallery merges, Control
     Centre tiles) for EVERY phone in EVERY frame ]]
local function LightState(wep)
	local L, now = SCR.L, RealTime()
	local st = wep.STTS_LightSt or {}
	wep.STTS_LightSt = st
	local own = L and L.wep == wep and wep:GetOwner() == LocalPlayer() or false
	st.own = own
	st.torch = wep:GetNW2Bool("Torch", false)
	st.front = wep:GetNW2Bool("CamFront", false)
	st.camFlash = wep:GetNW2Bool("CamFl", false)
	if own then
		if L.torchAt and now - L.torchAt < 0.8 then st.torch = L.torch end
		if L.camAt and now - L.camAt < 0.8 then st.front = L.front end
		if L.camFlAt and now - L.camFlAt < 0.8 then st.camFlash = L.camFl end
		st.camMode = (L.rec and L.rec.wep == wep and not L.rec.closed) and 2 or (SCR.RemoteRec and SCR.RemoteRec(wep) and 2) or L.camMode or 0
	else
		st.camMode = wep:GetNW2Int("CamMode", 0)
	end
	return st
end

-- how strong: LED (0 = off, 1 = torch / video light, >1 = photo burst), front (display light)
local function Wants(wep, st)
	local led, front = 0, 0
	if st.torch then led = 1 end
	if st.camMode == 2 and st.camFlash then
		if st.front then front = 0.6 else led = 1 end
	end
	local age, fr = SCR.ShotAge(wep, st)
	if age >= 0 and age < 0.45 then
		local a = age < 0.04 and age / 0.04 or (age < 0.22 and 1 or 1 - (age - 0.22) / 0.23)
		if fr then front = math.max(front, 1.1 * a) else led = math.max(led, 1 + 1.6 * a) end -- fix26: was 2.6 / 1 + 6 (way too bright)
	end
	return led, front
end

-- pose of the phone MODEL right now (the light sits on it)
local function LightPose(wep)
	local p, a = SCR.LivePose(wep)
	if p then return p, a end
	-- held by someone, but not drawn this frame (behind you): his hand bone
	local o = wep:GetOwner()
	if IsValid(o) and o:IsPlayer() and o:GetActiveWeapon() == wep and wep.HandPose then
		local f = FrameNumber()
		if wep.STTS_LightF ~= f then
			wep.STTS_LightF = f
			wep.STTS_LightP, wep.STTS_LightA = wep:HandPose(true)
		end
		return wep.STTS_LightP, wep.STTS_LightA
	end
end

local function Glow(index, pos, bright, size, col)
	local dl = DynamicLight(index)
	if not dl then return end
	dl.pos = pos
	dl.r, dl.g, dl.b = col.r, col.g, col.b
	dl.brightness = bright
	dl.size = size
	dl.decay = 2000
	dl.dietime = CurTime() + 0.1
end

-- fix61: the phone list is looked up 4 times a second, not every frame
local PHONES, phonesAt = {}, 0
local want, used = {}, {}
local function ByDist(x, y) return x.d < y.d end

hook.Add("Think", "STTS_PhoneLights", function()
	if not (SCR.L and SCR.ShotAge and SCR.LivePose) then return end
	local now = RealTime()
	if now >= phonesAt then PHONES, phonesAt = ents.FindByClass(CLASS), now + 0.25 end
	local eye = EyePos()
	for i = #want, 1, -1 do want[i] = nil end
	for _, wep in ipairs(PHONES) do
		if not IsValid(wep) or wep:IsDormant() then continue end
		-- cheapest first: most phones have nothing on (no torch, no flash, not filming)
		if not (wep:GetNW2Bool("Torch", false) or wep:GetNW2Int("CamMode", 0) == 2 or CurTime() - wep:GetNW2Float("ShotAt", -100) < 0.5 or SCR.L.wep == wep) then continue end
		local st = LightState(wep)
		local led, front = Wants(wep, st)
		if led > 0 or front > 0 then
			local p, a = LightPose(wep)
			if p then
				local d = p:DistToSqr(eye)
				if d < FAR_PT then want[#want + 1] = {wep = wep, p = p, a = a, led = led, front = front, d = d} end
			end
		end
	end
	if #want > 1 then table.sort(want, ByDist) end
	for k in pairs(used) do used[k] = nil end
	local n, maxPT, shadows = 0, cvMaxPT:GetInt(), cvShadows:GetBool()
	for _, w in ipairs(want) do
		local idx = w.wep:EntIndex()
		if w.led > 0 then
			local lp, la = LocalToWorld(G.Of(w.wep).FlashPos or G.FlashPos, G.FlashAng, w.p, w.a) -- fix28: LED of this model
			local burst = w.led > 1
			n = n + 1
			if n <= maxPT then
				local l = LIGHTS[w.wep]
				if not (l and IsValid(l.pt)) then
					l = {pt = ProjectedTexture()}
					l.pt:SetTexture("effects/flashlight001")
					l.pt:SetNearZ(3) -- no shadow from the hand holding it
					l.pt:SetColor(LED)
					LIGHTS[w.wep] = l
				end
				local pt, dirty = l.pt, false
				-- fix26: torch darker (0.7 -> 0.32, shorter reach), photo flash a soft burst (max ~2.8 instead of ~13)
				local fov, far = burst and 110 or 100, burst and 800 or 400 -- torch: wide, soft cone
				local bright = burst and 1.08 * w.led * cvFlash:GetFloat() or 0.32 * cvTorch:GetFloat()
				local shad = shadows and n == 1
				-- fix61: parameters only when they change, Update() only when something changed
				if l.fov ~= fov then pt:SetFOV(fov) l.fov, dirty = fov, true end
				if l.far ~= far then pt:SetFarZ(far) l.far, dirty = far, true end
				if not l.bright or math.abs(l.bright - bright) > 0.005 then pt:SetBrightness(bright) l.bright, dirty = bright, true end
				if l.shad ~= shad then pt:SetEnableShadows(shad) l.shad, dirty = shad, true end
				if not l.pos or l.pos:DistToSqr(lp) > 0.0025 or math.abs(math.AngleDifference(l.ang.p, la.p)) + math.abs(math.AngleDifference(l.ang.y, la.y)) + math.abs(math.AngleDifference(l.ang.r, la.r)) > 0.05 then
					pt:SetPos(lp) pt:SetAngles(la) l.pos, l.ang, dirty = lp, la, true
				end
				if dirty then pt:Update() end
				used[w.wep] = true
			end
			-- soft spill around the LED (the hand, a face, a wall right in front)
			if w.d < FAR_GLOW then
				Glow(9000 + idx, lp + la:Forward() * 6, burst and 0.9 * cvFlash:GetFloat() or 0.08 * cvTorch:GetFloat(), burst and 220 or 90, LED)
			end
		end
		if w.front > 0 and w.d < FAR_GLOW then
			-- the display lights up whatever is in front of it (selfie flash / ring)
			local c, nrm = G.ScreenWorld(w.p, w.a, w.wep)
			Glow(13000 + idx, c + nrm * 8, 1.2 * w.front * cvFlash:GetFloat(), 140 + 70 * w.front, Color(255, 248, 240))
		end
	end
	for wep, l in pairs(LIGHTS) do
		if not used[wep] then
			if IsValid(l.pt) then l.pt:Remove() end
			LIGHTS[wep] = nil
		end
	end
end)

hook.Add("ShutDown", "STTS_PhoneLights", function()
	for _, l in pairs(LIGHTS) do if IsValid(l.pt) then l.pt:Remove() end end
	LIGHTS = {}
end)

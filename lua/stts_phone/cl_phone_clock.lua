--[[---------------------------------------------------------------------------
	ZHUNTER phone - fix55: the Clock app (client), iOS 26 look.
	a floating glass tab bar: World Clock / Alarms / Stopwatch / Timers
	* Alarms: Edit / +, the rows (time, label + repeat, switch), swipe a row left =
	  Delete, tap = Edit Alarm. the Add / Edit Alarm sheet (G.APP_ALARMED) slides up
	  over the Clock (pushed back): wheels with inertia (looping), Repeat >, Label,
	  Sound > (preview out loud), Snooze, Delete Alarm
	* Stopwatch: Lap / Reset, Start / Stop, the laps (best green, worst red)
	* Timers: hours / min / sec wheels, Start, the orange ring, Pause / Resume, Cancel,
	  When Timer Ends >
	* World Clock: a few cities (with their daylight saving time)
	* a ringing alarm / timer (NW2 "AlmRing", sv_phone_clock.lua) covers the whole
	  screen like iOS 26.1: the time, the label, a big Snooze and "slide to stop"
	* the home screen icon is a live analog clock (a render target)
	the alarms ring on the SERVER (sv_phone_clock.lua): here they are only drawn, your
	own taps are predicted for a moment until the server has them
---------------------------------------------------------------------------]]
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
local U = SCR.UI
if not U or not G or not SCR.APPS or not G.APP_CLOCK then return end
local C, W, H = U.C, U.W, U.H
local L = SCR.L
local APP, SHEET = G.APP_CLOCK, G.APP_ALARMED
local WHITE, BLACK = Color(255, 255, 255), Color(0, 0, 0)
local K = {} -- (one table: keeps the locals of this chunk few)
SCR.Clock55 = K

local function F(name, font, size, weight)
	surface.CreateFont(name, {font = font, size = size, weight = weight, antialias = true, extended = true})
end
F("STTS_CK_Time", "Roboto Light", 82, 300)
F("STTS_CK_AmPm", "Roboto", 34, 400)
F("STTS_CK_Row", "Roboto", 24, 400)
F("STTS_CK_Tab", "Roboto", 17, 600)
F("STTS_CK_Wheel", "Roboto", 44, 400)
F("STTS_CK_WheelS", "Roboto", 25, 600)
F("STTS_CK_SW", "Roboto Thin", 98, 200)
F("STTS_CK_TmBig", "Roboto Light", 86, 300)
F("STTS_CK_City", "Roboto", 34, 400)
F("STTS_CK_CityT", "Roboto Light", 70, 300)
F("STTS_CK_Btn", "Roboto", 25, 500)
F("STTS_CK_Hdr", "Roboto", 22, 500)
F("STTS_CK_RingT", "Roboto", 152, 700)
F("STTS_CK_RingL", "Roboto", 30, 500)
F("STTS_CK_Big", "Roboto", 30, 600)
F("STTS_CK_None", "Roboto", 36, 600)
F("STTS_CK_Slide", "Roboto", 28, 400)
F("STTS_CK_IcoN", "Roboto", 21, 600)

--[[ colours (follow the theme of the phone: wep.STTS_ThK 0 dark .. 1 light) ]]
local function Mix(a, b, k)
	return Color(Lerp(k, a.r, b.r), Lerp(k, a.g, b.g), Lerp(k, a.b, b.b), Lerp(k, a.a or 255, b.a or 255))
end
local function A(c, a) return Color(c.r, c.g, c.b, (c.a or 255) * a) end
local function LK(wep) return math.Clamp(wep.STTS_ThK or 0, 0, 1) end
local function Acc(wep) return Mix(Color(255, 159, 10), Color(255, 149, 0), LK(wep)) end -- the orange of Clock
local function SheetBg(wep) return Mix(Color(28, 28, 30), Color(242, 242, 247), LK(wep)) end
local function CellBg(wep) return Mix(Color(44, 44, 46), Color(255, 255, 255), LK(wep)) end
local function GreyBtn(wep) return Mix(Color(51, 51, 54), Color(229, 229, 234), LK(wep)) end
local function Band(wep) return Mix(Color(118, 118, 128, 62), Color(118, 118, 128, 30), LK(wep)) end
local function H24(wep) return not SCR.SettingOf or SCR.SettingOf(wep, "h24") ~= false end
K.Mix, K.A, K.Acc = Mix, A, Acc

-- iOS 26 "Liquid Glass" button: a translucent capsule with a hairline rim
local function Glass(wep, x, y, w, h, hk, fill)
	local lk = LK(wep)
	local r = math.min(w, h) / 2
	if lk > 0.5 then U.Round(r, x, y + 2, w, h, Color(0, 0, 0, 16)) end
	U.Round(r, x, y, w, h, fill or Mix(Color(255, 255, 255, 30), Color(255, 255, 255, 235), lk))
	if (hk or 0) > 0.01 then U.Round(r, x, y, w, h, SCR.Ink(22 * hk)) end
	if U.RoundRim then U.RoundRim(r, x, y, w, h, 1.5, Mix(Color(255, 255, 255, 46), Color(0, 0, 0, 16), lk)) end
end
local function CBtn(wep, st, btns, id, cx, cy, r, action, fill)
	if action then U.Reg(btns, id, cx - r - 4, cy - r - 4, r * 2 + 8, r * 2 + 8, action) end
	local k = action and U.HoverK(wep, id, st.sel == id) or 0
	local rr = r * ((action and U.Pressed(wep, st, id)) and 0.93 or 1)
	Glass(wep, cx - rr, cy - rr, rr * 2, rr * 2, k, fill)
end
local function TBtn(wep, st, btns, id, x, y, w, h, text, tcol, action, fill)
	if action then U.Reg(btns, id, x - 4, y - 4, w + 8, h + 8, action) end
	local k = action and U.HoverK(wep, id, st.sel == id) or 0
	Glass(wep, x, y, w, h, k, fill)
	U.T(text, "STTS_I_BodyB", x + w / 2, y + h / 2, tcol or C.label)
end
local function GPlus(x, y, s, col, th) U.Line(x - s, y, x + s, y, th or 3.5, col) U.Line(x, y - s, x, y + s, th or 3.5, col) end
local function GX(x, y, s, col, th) U.Line(x - s, y - s, x + s, y + s, th or 3.5, col) U.Line(x - s, y + s, x + s, y - s, th or 3.5, col) end
local function GCheck(x, y, s, col, th)
	U.Line(x - s, y, x - s * 0.3, y + s * 0.7, th or 3.5, col)
	U.Line(x - s * 0.3, y + s * 0.7, x + s, y - s * 0.75, th or 3.5, col)
end
local function Switch(x, y, k, press, alpha)
	local w, h = 80, 48
	k = math.Clamp(k, 0, 1)
	local a = alpha or 1
	local off, on = C.fill or C.bg3, C.green
	U.Round(h / 2, x, y, w, h, Color(Lerp(k, off.r, on.r), Lerp(k, off.g, on.g), Lerp(k, off.b, on.b), 255 * a))
	local r = h / 2 - 3
	local kw = r * 2 + (press or 0) * 10
	local kx = x + 3 + (w - 6 - kw) * k
	U.Round(r, kx, y + 4, kw, r * 2, Color(0, 0, 0, 30 * a))
	U.Round(r, kx, y + 3, kw, r * 2, Color(255, 255, 255, 255 * a))
end
-- a row of a grouped card: label, value, chevron (hover tint with the card's corners)
local function CRow(wep, st, btns, id, x, y, w, h, label, value, chev, action, first, last)
	if action then U.Reg(btns, id, x, y, w, h, action) end
	local k = action and U.HoverK(wep, id, st.sel == id) or 0
	if k > 0.01 then
		local col = SCR.Ink(((U.Pressed(wep, st, id)) and 40 or 18) * k)
		if first or last then draw.RoundedBoxEx(26, x, y, w, h, (U.LinCol or function(c) return c end)(col), first, first, last, last)
		else U.R(x, y, w, h, col) end
	end
	if label then U.T(label, "STTS_I_Body", x + 20, y + h / 2, C.label, TEXT_ALIGN_LEFT) end
	local vx = x + w - 20
	if chev then U.Chevron(vx - 2, y + h / 2, 8, "right", C.label3, 3.5) vx = vx - 26 end
	if value then U.T(U.Fit(value, "STTS_I_Body", w * 0.55), "STTS_I_Body", vx, y + h / 2, C.label2, TEXT_ALIGN_RIGHT) end
end
-- the corners of the pushed back page (behind a sheet) are rounded: paint them over
local function Corners(x, y, w, h, r, col)
	if r < 1 then return end
	local function Fan(cx, cy, px, py, a0)
		for i = 0, 5 do
			local t0, t1 = math.rad(a0 + 15 * i), math.rad(a0 + 15 * (i + 1))
			U.Tri(px, py, cx + math.cos(t0) * r, cy + math.sin(t0) * r, cx + math.cos(t1) * r, cy + math.sin(t1) * r, col)
		end
	end
	Fan(x + r, y + r, x, y, 180)
	Fan(x + w - r, y + r, x + w, y, 270)
	Fan(x + w - r, y + h - r, x + w, y + h, 0)
	Fan(x + r, y + h - r, x, y + h, 90)
end
-- draws fn moved right by x (scissor clips follow it, like Scaled() of the screen file)
local function Shifted(x, fn)
	if math.abs(x) < 0.01 then fn() return end
	local m = Matrix()
	m:Translate(Vector(x, 0, 0))
	cam.PushModelMatrix(m, true)
	local xf = SCR.XF
	SCR.XF = xf and {x = xf.x + x * xf.s, y = xf.y, s = xf.s} or {x = x, y = 0, s = 1}
	local ok, err = pcall(fn)
	SCR.XF = xf
	cam.PopModelMatrix()
	if not ok then ErrorNoHalt(tostring(err) .. "\n") end
end
K.Glass, K.CBtn, K.Switch, K.Shifted = Glass, CBtn, Switch, Shifted

--[[ time / days as text ]]
local function HM(wep, h, m) -- "7:00", "AM" (12 h) / "07:00", nil (24 h)
	if H24(wep) then return string.format("%02d:%02d", h, m), nil end
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%d:%02d", h12, m), h < 12 and "AM" or "PM"
end
local function MS(sec) -- 8:59 / 1:08:59
	sec = math.max(0, math.ceil(sec - 0.001))
	local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end
local function SWFmt(sec) -- 00:00.00
	local cs = math.max(0, math.floor(sec * 100 + 0.0001))
	local h, m, s, c = math.floor(cs / 360000), math.floor(cs / 6000) % 60, math.floor(cs / 100) % 60, cs % 100
	if h > 0 then return string.format("%d:%02d:%02d.%02d", h, m, s, c) end
	return string.format("%02d:%02d.%02d", m, s, c)
end
local DAY = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
local DAY3 = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local function RepeatText(days, long)
	if days == 0 then return long and "Never" or nil end
	if days == 127 then return long and "Every Day" or "every day" end
	if days == 62 then return long and "Weekdays" or "weekdays" end
	if days == 65 then return long and "Weekends" or "weekends" end
	local t, one = {}, nil
	for i = 0, 6 do if bit.band(days, bit.lshift(1, i)) ~= 0 then t[#t + 1] = DAY3[i + 1] one = i end end
	if #t == 1 then return (long and "Every " or "every ") .. DAY[one + 1] end
	return table.concat(t, " ")
end
K.HM, K.MS, K.SWFmt, K.RepeatText = HM, MS, SWFmt, RepeatText
-- the UTC offset of this PC (minutes)
function K.TZ()
	local now = os.time()
	local l, u = os.date("*t", now), os.date("!*t", now)
	u.isdst = l.isdst
	return math.floor(os.difftime(os.time(l), os.time(u)) / 60 + 0.5)
end

--[[ the alarms of a phone (NW2, see sv_phone_clock.lua) + your own taps predicted ]]
local acache = setmetatable({}, {__mode = "k"})
function K.Alarms(wep)
	local n = math.min(wep:GetNW2Int("AlmN", 0), 16)
	local parts = {}
	for i = 1, n do parts[i] = wep:GetNW2String("Alm" .. i, "") end
	local sig = table.concat(parts, "\n")
	local c = acache[wep]
	if c and c.sig == sig then return c.list end
	local list = {}
	for i = 1, n do
		local id, hh, mm, on, days, sn, snd, label = string.match(parts[i], "^(%d+)|(%d%d)(%d%d)|(%d)|(%d+)|(%d)|([^|]*)|(.*)$")
		if id then
			list[#list + 1] = {id = tonumber(id), h = tonumber(hh), m = tonumber(mm), on = on == "1", days = tonumber(days) or 0,
				snooze = sn == "1", snd = snd, label = label}
		end
	end
	acache[wep] = {sig = sig, list = list}
	return list
end
function K.IsOn(wep, st, a)
	local p = st.own and L.almOn55 and L.almOn55[a.id]
	if p and p.wep == wep and RealTime() - p.at < 1.5 and p.was == a.on then return p.v end
	return a.on
end
function K.Visible(wep, st)
	local out = {}
	local del = st.own and L.almDel55 or {}
	for _, a in ipairs(K.Alarms(wep)) do
		local d = del[a.id]
		if not (d and d.wep == wep and RealTime() - d.at < 3) then out[#out + 1] = a end
	end
	return out
end
function K.Toggle(wep, st, a, v)
	if not st.own then return end
	L.almOn55 = L.almOn55 or {}
	L.almOn55[a.id] = {wep = wep, v = v, at = RealTime(), was = a.on}
	U.Act("alarmon", a.id .. "|" .. (v and 1 or 0))
end
function K.Delete(wep, id)
	L.almDel55 = L.almDel55 or {}
	L.almDel55[id] = {wep = wep, at = RealTime()}
	if L.swipe55 and L.swipe55.id == id then L.swipe55 = nil end
	U.Act("alarmdel", tostring(id))
end

-- the tab of the Clock (1 World Clock, 2 Alarms, 3 Stopwatch, 4 Timers)
function K.Tab(wep, st)
	local p = st.own and L.clkTab55
	if p and p.wep == wep then return p.v end
	return math.Clamp(wep:GetNW2Int("ClkTab", 2), 1, 4)
end
function K.SetTab(wep, st, v)
	if not st.own then return end
	if K.Tab(wep, st) == v then L.scrollGo = 0 return end -- iOS: the active tab again = back to the top
	L.clkTab55 = {wep = wep, v = v}
	L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
	L.swipe55, L.clkEdit55, L.tmPage55 = nil, nil, nil
	U.Act("clktab", tostring(v))
end
-- fix61: the Control Centre (Timer / Alarm): the Clock app on that tab
function SCR.ClockOpen(wep, st, tab)
	if not st.own then return end
	if K.Tab(wep, st) ~= tab then K.SetTab(wep, st, tab) end
	if st.app ~= APP and U.SetApp then U.SetApp(st, APP) end
end

-- a scrolling area: the offset in px (st.scroll is in STEP units, the zone drags 1:1)
local STEP = 80
function K.Scroller(wep, st, btns, top, bottom, total, noset)
	local mx = math.max(0, (total - (bottom - top)) / STEP)
	if st.own and not noset then L.maxScroll = mx end
	local s = math.Clamp(st.scroll or 0, -1, mx + 1)
	U.Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = STEP})
	return s * STEP, s, mx
end
function K.Bar(wep, st, top, bottom, total, s, mx)
	local ia = mx > 0 and U.BarA and U.BarA(wep, st) or 0
	if ia <= 0.01 then return end
	local area = bottom - top
	local bh = math.max(30, area * area / math.max(total, area + 1))
	U.Round(3, W - 8, top + (area - bh) * math.Clamp(s / mx, 0, 1), 5, bh, SCR.Ink(90 * ia))
end
-- the large title scrolls away, then the inline title + a bar (iOS)
function K.NavChrome(wep, title, sy, top)
	local barA = math.Clamp(sy / 30, 0, 1)
	if barA > 0.01 then
		U.R(0, 0, W, top, Color(C.bar.r, C.bar.g, C.bar.b, (C.bar.a or 245) * barA))
		U.R(0, top - 1, W, 1, Color(C.sep.r, C.sep.g, C.sep.b, (C.sep.a or 255) * barA))
	end
	local ia = math.Clamp((sy - 84) / 24, 0, 1)
	if ia > 0.01 then U.T(title, "STTS_SET_Nav", W / 2, 78, A(C.label, ia)) end
end

--[[---------------------------------------------------------------------------
	the wheel picker (UIPickerView): a cylinder of rows, the finger drags it 1:1,
	a flick glides on and slows down (exponential, ends exactly on a row), a tap on
	a row turns it to the middle. the states live in L.wh55 (your own phone)
---------------------------------------------------------------------------]]
local RAD = 0.34 -- radians per row on the cylinder
function K.Wh(key, n, loop, init)
	local ws = L.wh55
	if not ws then ws = {} L.wh55 = ws end
	local w = ws[key]
	if not w then w = {p = init or 0} ws[key] = w end
	w.n, w.loop = n, loop
	return w
end
function K.WVal(w)
	local i = math.floor(w.p + 0.5)
	if w.loop then return i % w.n end
	return math.Clamp(i, 0, w.n - 1)
end
local function WStep(w, dt)
	if w.drag then return end
	if not w.go then
		local t = math.floor(w.p + 0.5)
		if not w.loop then t = math.Clamp(t, 0, w.n - 1) end
		if math.abs(t - w.p) > 0.003 then w.go, w.rate = t, 14 else return end
	end
	w.p = w.p + (w.go - w.p) * (1 - math.exp(-dt * (w.rate or 12)))
	if math.abs(w.go - w.p) < 0.003 then
		w.p, w.go = w.go, nil
		if w.loop then w.p = w.p % w.n end
	end
end
-- draws one wheel; zone = registered for the touch hook (your own phone)
function K.Wheel(wep, w, cx, cy, rowH, fmt, align, live, zone)
	if live and w.frame ~= FrameNumber() then w.frame = FrameNumber() WStep(w, wep.STTS_UIdt or 0) end
	local p = w.p
	local base = math.floor(p + 0.5)
	local R = rowH / RAD
	local lab = C.label
	for d = -5, 5 do
		local i = base + d
		local o = i - p
		local ang = o * RAD
		if math.abs(ang) < 1.42 and (w.loop or (i >= 0 and i < w.n)) then
			local idx = w.loop and i % w.n or i
			local c = math.cos(ang)
			local near = math.Clamp(1 - math.abs(o) * 1.4, 0, 1)
			local m = Matrix()
			m:Translate(Vector(cx, cy + math.sin(ang) * R, 0))
			m:Scale(Vector(1, c, 1))
			cam.PushModelMatrix(m, true)
			U.T(fmt(idx), "STTS_CK_Wheel", 0, 0, Color(lab.r, lab.g, lab.b, 255 * (0.34 + 0.66 * near) * math.Clamp(c * 1.3 - 0.15, 0, 1)), align or TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.PopModelMatrix()
		end
	end
	if live and zone then
		zone.w, zone.cy, zone.rowH = w, cy, rowH
		local list = wep.STTS_Wheels55
		if list then list[#list + 1] = zone end
	end
end
local function Two(i) return string.format("%02d", i) end
local function H12(i) return tostring(i == 0 and 12 or i) end
local function AP(i) return i == 0 and "AM" or "PM" end
local function Num(i) return tostring(i) end
K.Two, K.H12, K.AP = Two, H12, AP
function K.SetWheels(h, m)
	local function Set(w, v) w.p, w.go, w.drag = v, nil, nil end
	Set(K.Wh("ah24", 24, true), h)
	Set(K.Wh("ah12", 12, true), h % 12)
	Set(K.Wh("ap", 2, false), h >= 12 and 1 or 0)
	Set(K.Wh("am", 60, true), m)
end
function K.WheelTime(wep)
	local m = K.WVal(K.Wh("am", 60, true))
	if H24(wep) then return K.WVal(K.Wh("ah24", 24, true)), m end
	return K.WVal(K.Wh("ah12", 12, true)) + 12 * K.WVal(K.Wh("ap", 2, false)), m
end

--[[---------------------------------------------------------------------------
	the tabs
---------------------------------------------------------------------------]]
local SW_W = 112 -- the Delete behind a swiped row
local RH = 132
function K.AlarmsTab(wep, st, btns, behind)
	local list = K.Visible(wep, st)
	local own = st.own and not behind
	local edit = st.own and L.clkEdit55 == wep
	if edit and #list == 0 and own then L.clkEdit55, edit = nil, false end
	local top, bottom = 104, H
	local y0 = 194
	local total = y0 + #list * RH + 150
	local sy, s, mx = K.Scroller(wep, st, btns, top, bottom, total, behind)
	local acc = Acc(wep)
	local dt = wep.STTS_UIdt or 0
	local sw = L.swipe55
	if sw and (sw.wep ~= wep or not st.own) then sw = nil end
	if sw and not sw.drag and own then
		sw.x = Lerp(1 - math.exp(-dt * 16), sw.x, sw.goal)
		if math.abs(sw.x - sw.goal) < 0.4 then sw.x = sw.goal end
		if sw.goal == 0 and sw.x == 0 then L.swipe55, sw = nil, nil end
	end
	local snzId = tonumber(string.match(wep:GetNW2String("AlmSnz", ""), "^(%d+)|") or "")
	local snzAt = wep:GetNW2Float("AlmSnzAt", 0)
	local ek = U.SpringK(wep, "clkedit", edit, 0.35, 1)
	local rows = {}
	U.Clip(0, top, W, bottom - top)
	U.T("Alarms", "STTS_I_Large", 22, 150 - sy, C.label, TEXT_ALIGN_LEFT)
	for i, a in ipairs(list) do
		local ry = y0 + (i - 1) * RH - sy
		if ry < bottom and ry + RH > top then
			local on = K.IsOn(wep, st, a)
			local off = (sw and sw.id == a.id) and sw.x or 0
			local ex = 54 * ek
			local col = on and C.label or C.label2
			local y1, y2 = math.max(ry, top), math.min(ry + RH, bottom)
			local vis = y2 - y1 > 10
			local idRow, idSw, idMin, idDel = 100 + i, 120 + i, 140 + i, 160 + i
			if own then rows[#rows + 1] = {id = a.id, y = ry, h = RH} end
			-- swiped left: Delete behind the row
			if off < -1 then
				U.R(W + off, ry, -off + 1, RH, C.red)
				if off < -70 then U.T("Delete", "STTS_I_BodyB", W + math.max(off, -SW_W * 1.6) / 2, ry + RH / 2, WHITE) end
				if own and off < -40 and vis then U.Reg(btns, idDel, W + off, y1, -off, y2 - y1, function() K.Delete(wep, a.id) end) end
			end
			local hk = U.HoverK(wep, idRow, st.sel == idRow)
			if hk > 0.01 then U.R(off, ry, W, RH, SCR.Ink(((U.Pressed(wep, st, idRow)) and 40 or 18) * hk)) end
			-- the time, big and light, + AM / PM
			local main, suf = HM(wep, a.h, a.m)
			local tx = 24 + ex + off
			U.T(main, "STTS_CK_Time", tx, ry + 94, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			if suf then
				surface.SetFont("STTS_CK_Time")
				local tw = surface.GetTextSize(main)
				U.T(suf, "STTS_CK_AmPm", tx + tw + 5, ry + 84, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			end
			local sub = a.label ~= "" and a.label or "Alarm"
			local rep = RepeatText(a.days, false)
			if rep then sub = sub .. ", " .. rep end
			local subCol = col
			if snzId == a.id and snzAt > CurTime() then sub, subCol = "Snoozed · " .. MS(snzAt - CurTime()), acc end
			U.T(U.Fit(sub, "STTS_CK_Row", W - tx - 130), "STTS_CK_Row", tx + 2, ry + 110, subCol, TEXT_ALIGN_LEFT)
			-- the switch (slides out in Edit mode, a chevron comes instead)
			if ek < 0.99 then
				local k = U.SpringK(wep, "alm" .. a.id, on, 0.32, 0.78)
				Switch(W - 104 + off + 130 * ek, ry + RH / 2 - 24, k, 0, 1 - ek)
				if own and not edit and vis then U.Reg(btns, idSw, W - 130 + off, y1, 130, y2 - y1, function() K.Toggle(wep, st, a, not on) end) end
			end
			if ek > 0.01 then
				local mxp = -24 + 54 * ek + off
				U.Circle(mxp, ry + RH / 2, 14, A(C.red, ek))
				U.R(mxp - 7, ry + RH / 2 - 1.5, 14, 3, A(WHITE, ek))
				U.Chevron(W - 28 + off + 60 * (1 - ek), ry + RH / 2, 9, "right", A(C.label3, ek), 3.5)
				if own and edit and vis then
					U.Reg(btns, idMin, 0, y1, 66, y2 - y1, function() L.swipe55 = {wep = wep, id = a.id, x = off, goal = -SW_W} end)
				end
			end
			if own and vis then
				local x0 = edit and 66 or 0
				U.Reg(btns, idRow, x0, y1, W - x0 - (edit and 0 or 130), y2 - y1, function() K.OpenEditor(wep, st, a) end)
			end
			if i < #list then U.R(24 + ex + off, ry + RH - 1, W, 1, C.sep) end
		end
	end
	U.Unclip()
	if #list == 0 then U.T("No Alarms", "STTS_CK_None", W / 2, 470, C.label2) end
	if not behind then K.Bar(wep, st, top, bottom, total, s, mx) end
	if own then wep.STTS_ClkRows = rows end
	K.NavChrome(wep, "Alarms", sy, top)
	-- Edit (Done) / +
	if #list > 0 or edit then
		TBtn(wep, st, btns, 24, 16, 56, 96, 46, edit and "Done" or "Edit", edit and WHITE or C.label,
			own and function() L.clkEdit55 = (not edit) and wep or nil L.swipe55 = nil end, edit and acc or nil)
	end
	CBtn(wep, st, btns, 25, W - 39, 79, 23, own and function() K.OpenEditor(wep, st, nil) end)
	GPlus(W - 39, 79, 10, C.label, 3.4)
end

-- a round button of Stopwatch / Timers (the iOS ring with a gap)
local function RBtn(wep, st, btns, id, cx, cy, r, label, fill, tcol, action)
	if action then U.Reg(btns, id, cx - r, cy - r, r * 2, r * 2, action) end
	local k = action and U.HoverK(wep, id, st.sel == id) or 0
	local rr = r * ((action and U.Pressed(wep, st, id)) and 0.95 or 1)
	U.Circle(cx, cy, rr, fill)
	if k > 0.01 then U.Circle(cx, cy, rr, SCR.Ink(18 * k)) end
	if U.CircleRim then U.CircleRim(cx, cy, rr - 3, 2.5, C.bg or BLACK) end
	U.T(label, "STTS_CK_Btn", cx, cy, tcol)
end

--[[ Stopwatch: NW2 SwStart (0 = stopped) / SwBase / SwLaps (centiseconds, cumulative) ]]
function K.SWState(wep, st)
	local start, base, laps = wep:GetNW2Float("SwStart", 0), wep:GetNW2Float("SwBase", 0), wep:GetNW2String("SwLaps", "")
	local p = st.own and L.swPred55
	if p and p.wep == wep and RealTime() - p.at < 1.5 and p.sig == start .. "|" .. base .. "|" .. laps then return p.start, p.base, p.laps end
	return start, base, laps
end
function K.SW(wep, st, cmd)
	if not st.own then return end
	local start, base, laps = K.SWState(wep, st)
	local sig = wep:GetNW2Float("SwStart", 0) .. "|" .. wep:GetNW2Float("SwBase", 0) .. "|" .. wep:GetNW2String("SwLaps", "")
	local now = CurTime()
	if cmd == "start" then start = now
	elseif cmd == "stop" then base, start = base + now - start, 0
	elseif cmd == "lap" then
		local cs = math.floor((base + now - start) * 100)
		laps = laps == "" and tostring(cs) or (laps .. "," .. cs)
	elseif cmd == "reset" then base, laps = 0, "" end
	L.swPred55 = {wep = wep, at = RealTime(), sig = sig, start = start, base = base, laps = laps}
	U.Act("sw", cmd)
end
function K.Stopwatch(wep, st, btns, behind)
	local own = st.own and not behind
	local start, base, lapStr = K.SWState(wep, st)
	local run = start > 0
	local el = math.max(0, base + (run and (CurTime() - start) or 0))
	U.T(SWFmt(el), "STTS_CK_SW", W / 2, 290, C.label)
	local by, r = 466, 52
	local lx, rx = 26 + r, W - 26 - r
	if run then RBtn(wep, st, btns, 30, lx, by, r, "Lap", GreyBtn(wep), C.label, own and function() K.SW(wep, st, "lap") end)
	elseif el > 0 then RBtn(wep, st, btns, 30, lx, by, r, "Reset", GreyBtn(wep), C.label, own and function() K.SW(wep, st, "reset") end)
	else RBtn(wep, st, btns, 30, lx, by, r, "Lap", A(GreyBtn(wep), 0.6), C.label3, nil) end
	if run then RBtn(wep, st, btns, 31, rx, by, r, "Stop", A(C.red, 0.24), C.red, own and function() K.SW(wep, st, "stop") end)
	else RBtn(wep, st, btns, 31, rx, by, r, "Start", A(C.green, 0.24), C.green, own and function() K.SW(wep, st, "start") end) end
	-- the laps, newest first (the running one on top)
	local cum = {}
	for v in string.gmatch(lapStr, "%d+") do cum[#cum + 1] = tonumber(v) end
	local lapT, prev = {}, 0
	for i, v in ipairs(cum) do lapT[i] = v - prev prev = v end
	local best, worst
	if #lapT >= 2 then
		for i, v in ipairs(lapT) do
			if not best or v < lapT[best] then best = i end
			if not worst or v > lapT[worst] then worst = i end
		end
	end
	local n = (#cum > 0 or run or el > 0) and (#cum + 1) or 0
	local top, bottom, LH = 552, H, 66
	local total = n * LH + 140
	local sy, s, mx = K.Scroller(wep, st, btns, top, bottom, total, behind)
	if n > 0 then U.R(16, top, W - 32, 1, C.sep) end
	U.Clip(0, top + 1, W, bottom - top - 1)
	for j = 1, n do
		local idx = n - j + 1
		local y = top + (j - 1) * LH - sy
		if y + LH > top and y < bottom then
			local v = idx == n and (math.floor(el * 100) - prev) or lapT[idx]
			local col = C.label
			if idx ~= n and idx == best then col = C.green elseif idx ~= n and idx == worst then col = C.red end
			U.T("Lap " .. idx, "STTS_I_Body", 24, y + LH / 2, col, TEXT_ALIGN_LEFT)
			U.T(SWFmt(v / 100), "STTS_I_Body", W - 24, y + LH / 2, col, TEXT_ALIGN_RIGHT)
			U.R(16, y + LH - 1, W - 32, 1, C.sep)
		end
	end
	U.Unclip()
	if not behind then K.Bar(wep, st, top, bottom, total, s, mx) end
end

--[[ Timers: NW2 TmEnd (running) / TmLeft (paused) / TmDur / TmSnd ]]
function K.TMState(wep, st)
	local te, left, dur = wep:GetNW2Float("TmEnd", 0), wep:GetNW2Float("TmLeft", 0), wep:GetNW2Int("TmDur", 0)
	local p = st.own and L.tmPred55
	if p and p.wep == wep and RealTime() - p.at < 1.5 and p.sig == te .. "|" .. left then return p.te, p.left, p.dur end
	return te, left, dur
end
function K.TM(wep, st, cmd, secs)
	if not st.own then return end
	local te, left, dur = K.TMState(wep, st)
	local sig = wep:GetNW2Float("TmEnd", 0) .. "|" .. wep:GetNW2Float("TmLeft", 0)
	local now = CurTime()
	if cmd == "start" then te, left, dur = now + secs, 0, secs
	elseif cmd == "pause" then if te > 0 then left, te = math.max(te - now, 0.01), 0 end
	elseif cmd == "resume" then if left > 0 then te, left = now + left, 0 end
	elseif cmd == "cancel" then te, left = 0, 0 end
	L.tmPred55 = {wep = wep, at = RealTime(), sig = sig, te = te, left = left, dur = dur}
	U.Act("tm", cmd == "start" and ("start:" .. secs) or cmd)
end
function K.TmSnd(wep, st)
	local p = st.own and L.tmSnd55
	if p and p.wep == wep and RealTime() - p.at < 1.5 then return p.v end
	return wep:GetNW2String("TmSnd", G.AlarmDefault)
end
local function Bell(x, y, col)
	U.Circle(x, y - 2, 7, col)
	U.R(x - 7, y - 2, 14, 7, col)
	U.R(x - 9, y + 4, 18, 3, col)
	U.Circle(x, y + 9, 2.5, col)
end
function K.Timers(wep, st, btns, behind)
	local own = st.own and not behind
	local te, left, dur = K.TMState(wep, st)
	local now = CurTime()
	local active = te > 0 or left > 0
	local acc = Acc(wep)
	if own then L.maxScroll = 0 end
	U.T("Timers", "STTS_I_Large", 22, 150, C.label, TEXT_ALIGN_LEFT)
	local cy, by, r = 366, 610, 52
	local lx, rx = 26 + r, W - 26 - r
	if active then
		local rem = te > 0 and math.max(te - now, 0) or left
		local f = dur > 0 and math.Clamp(rem / dur, 0, 1) or 0
		local R0, th = 156, 11
		U.Arc(W / 2, cy, R0, th, 0, 360, GreyBtn(wep), 96)
		if f > 0.002 then
			local a0 = -90 + 360 * (1 - f)
			U.Arc(W / 2, cy, R0, th, a0, 270, acc, math.max(6, math.ceil(96 * f)))
			local rc = R0 - th / 2
			U.Circle(W / 2 + math.cos(math.rad(a0)) * rc, cy + math.sin(math.rad(a0)) * rc, th / 2, acc)
			U.Circle(W / 2, cy - rc, th / 2, acc)
		end
		U.T(MS(rem), "STTS_CK_TmBig", W / 2, cy - 6, C.label)
		if te > 0 then
			local t = os.time() + math.floor(rem + 0.5)
			local main, suf = HM(wep, tonumber(os.date("%H", t)), tonumber(os.date("%M", t)))
			local txt = main .. (suf and (" " .. suf) or "")
			surface.SetFont("STTS_I_Sub")
			local tw = surface.GetTextSize(txt)
			Bell(W / 2 - tw / 2 - 14, cy + 66, C.label2)
			U.T(txt, "STTS_I_Sub", W / 2 + 10, cy + 66, C.label2)
		end
		RBtn(wep, st, btns, 32, lx, by, r, "Cancel", GreyBtn(wep), C.label, own and function() K.TM(wep, st, "cancel") end)
		if te > 0 then RBtn(wep, st, btns, 33, rx, by, r, "Pause", A(acc, 0.24), acc, own and function() K.TM(wep, st, "pause") end)
		else RBtn(wep, st, btns, 33, rx, by, r, "Resume", A(C.green, 0.24), C.green, own and function() K.TM(wep, st, "resume") end) end
	else
		-- hours / min / sec wheels, the labels stay next to the middle row
		local rowH = 54
		U.Round(16, 16, cy - rowH / 2, W - 32, rowH, Band(wep))
		U.Clip(0, cy - 150, W, 300)
		local cw = (W - 32) / 3
		local keys, ns, lbl = {"th", "tm", "ts"}, {24, 60, 60}, {"hours", "min", "sec"}
		local def = {0, 15, 0}
		for i = 1, 3 do
			local x = 16 + cw * (i - 1)
			local w = K.Wh(keys[i], ns[i], true, def[i])
			if not st.own then w = {p = def[i], n = ns[i], loop = true} end
			K.Wheel(wep, w, x + cw * 0.5 + 4, cy, rowH, Num, TEXT_ALIGN_RIGHT, own, {x0 = x, x1 = x + cw, y0 = cy - 150, y1 = cy + 150})
			U.T(lbl[i], "STTS_CK_WheelS", x + cw * 0.5 + 12, cy + 2, C.label, TEXT_ALIGN_LEFT)
		end
		U.Unclip()
		local secs = 0
		if st.own then secs = K.WVal(K.Wh("th", 24, true)) * 3600 + K.WVal(K.Wh("tm", 60, true)) * 60 + K.WVal(K.Wh("ts", 60, true)) end
		RBtn(wep, st, btns, 32, lx, by, r, "Cancel", A(GreyBtn(wep), 0.6), C.label3, nil)
		RBtn(wep, st, btns, 33, rx, by, r, "Start", A(C.green, secs > 0 and 0.24 or 0.12), secs > 0 and C.green or A(C.green, 0.45),
			(own and secs > 0) and function() K.TM(wep, st, "start", secs) end or nil)
	end
	-- When Timer Ends >
	local y = 706
	U.Round(26, 16, y, W - 32, 72, C.bg2)
	CRow(wep, st, btns, 34, 16, y, W - 32, 72, "When Timer Ends", G.AlarmSoundName(K.TmSnd(wep, st)), true,
		own and function() L.tmPage55 = wep L.scroll, L.scrollV, L.scrollGo = 0, 0, nil end, true, true)
end

--[[ World Clock: a few cities, their daylight saving time computed from the rules ]]
local function Days(y, m, d) -- days since 1970-01-01 (proleptic Gregorian)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
local function Sunday(y, m, n) -- the n-th Sunday of a month (n = -1: the last one), in days
	if n > 0 then
		local d1 = Days(y, m, 1)
		return d1 + (7 - (d1 + 4) % 7) % 7 + (n - 1) * 7
	end
	local last = (m == 12 and Days(y + 1, 1, 1) or Days(y, m + 1, 1)) - 1
	return last - (last + 4) % 7
end
local function Offset(c, t) -- hours from UTC at the UTC time t
	local std, r = c.std, c.dst
	if not r then return std end
	local y = tonumber(os.date("!%Y", t))
	if r == "us" then -- 2nd Sunday of March 2:00 .. 1st Sunday of November 2:00 (local)
		local a, b = Sunday(y, 3, 2) * 86400 + (2 - std) * 3600, Sunday(y, 11, 1) * 86400 + (1 - std) * 3600
		return (t >= a and t < b) and std + 1 or std
	elseif r == "eu" then -- last Sunday of March .. last Sunday of October, 1:00 UTC
		local a, b = Sunday(y, 3, -1) * 86400 + 3600, Sunday(y, 10, -1) * 86400 + 3600
		return (t >= a and t < b) and std + 1 or std
	elseif r == "au" then -- 1st Sunday of October 2:00 .. 1st Sunday of April 3:00 (local)
		local b, a = Sunday(y, 4, 1) * 86400 + (2 - std) * 3600, Sunday(y, 10, 1) * 86400 + (2 - std) * 3600
		return (t < b or t >= a) and std + 1 or std
	end
	return std
end
K.CITIES = {
	{name = "Cupertino", std = -8, dst = "us"}, {name = "New York", std = -5, dst = "us"},
	{name = "London", std = 0, dst = "eu"}, {name = "Berlin", std = 1, dst = "eu"},
	{name = "Moscow", std = 3}, {name = "Dubai", std = 4}, {name = "Tokyo", std = 9}, {name = "Sydney", std = 10, dst = "au"},
}
function K.World(wep, st, btns, behind)
	local top, bottom, y0, RW = 104, H, 194, 124
	local cities = K.CITIES
	local total = y0 + #cities * RW + 150
	local sy, s, mx = K.Scroller(wep, st, btns, top, bottom, total, behind)
	local utc = os.time()
	local tz = K.TZ()
	local today = math.floor((utc + tz * 60) / 86400)
	U.Clip(0, top, W, bottom - top)
	U.T("World Clock", "STTS_I_Large", 22, 150 - sy, C.label, TEXT_ALIGN_LEFT)
	for i, c in ipairs(cities) do
		local y = y0 + (i - 1) * RW - sy
		if y + RW > top and y < bottom then
			local off = Offset(c, utc)
			local t = utc + off * 3600
			local d = math.floor(t / 86400) - today
			local diff = off * 60 - tz
			local hrs = diff % 60 == 0 and string.format("%+dHRS", math.floor(diff / 60))
				or string.format("%s%d:%02dHRS", diff < 0 and "-" or "+", math.floor(math.abs(diff) / 60), math.abs(diff) % 60)
			U.T((d == 0 and "Today" or (d > 0 and "Tomorrow" or "Yesterday")) .. ", " .. hrs, "STTS_CK_Row", 24, y + 38, C.label2, TEXT_ALIGN_LEFT)
			U.T(c.name, "STTS_CK_City", 24, y + 80, C.label, TEXT_ALIGN_LEFT)
			local tt = os.date("!*t", t)
			local main, suf = HM(wep, tt.hour, tt.min)
			local xr = W - 24
			if suf then
				U.T(suf, "STTS_CK_AmPm", xr, y + 92, C.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
				surface.SetFont("STTS_CK_AmPm")
				xr = xr - surface.GetTextSize(suf) - 5
			end
			U.T(main, "STTS_CK_CityT", xr, y + 102, C.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			if i < #cities then U.R(24, y + RW - 1, W - 24, 1, C.sep) end
		end
	end
	U.Unclip()
	if not behind then K.Bar(wep, st, top, bottom, total, s, mx) end
	K.NavChrome(wep, "World Clock", sy, top)
end

--[[ the floating glass tab bar (iOS 26), the selected pill glides ]]
local TABS = {"World Clock", "Alarms", "Stopwatch", "Timers"}
local TABICON = {
	function(x, y, c) -- globe
		if U.CircleRim then U.CircleRim(x, y, 13, 2.4, c) end
		for i = 0, 15 do
			local a0, a1 = math.rad(i * 22.5), math.rad((i + 1) * 22.5)
			U.Line(x + math.cos(a0) * 5.5, y + math.sin(a0) * 13, x + math.cos(a1) * 5.5, y + math.sin(a1) * 13, 2.2, c)
		end
		U.Line(x - 12.5, y, x + 12.5, y, 2.2, c)
		U.Line(x - 10.5, y - 6.5, x + 10.5, y - 6.5, 2, c)
		U.Line(x - 10.5, y + 6.5, x + 10.5, y + 6.5, 2, c)
	end,
	function(x, y, c) -- alarm clock
		if U.CircleRim then U.CircleRim(x, y + 2, 12, 2.6, c) end
		U.Line(x - 15, y - 7, x - 8, y - 13, 3.2, c)
		U.Line(x + 8, y - 13, x + 15, y - 7, 3.2, c)
		U.Line(x, y + 2, x, y - 5, 2.4, c)
		U.Line(x, y + 2, x + 5, y + 5, 2.4, c)
		U.Line(x - 8, y + 12, x - 11, y + 15, 2.6, c)
		U.Line(x + 8, y + 12, x + 11, y + 15, 2.6, c)
	end,
	function(x, y, c) -- stopwatch
		if U.CircleRim then U.CircleRim(x, y + 3, 12, 2.6, c) end
		U.R(x - 4, y - 14, 8, 3.5, c)
		U.Line(x, y - 11, x, y - 8, 2.4, c)
		U.Line(x + 9, y - 7, x + 11.5, y - 9.5, 2.8, c)
		U.Line(x, y + 3, x + 4, y - 3, 2.4, c)
	end,
	function(x, y, c) -- timer
		U.Arc(x, y + 1, 13, 2.6, -62, 242, c, 30)
		U.Line(x, y - 12, x, y - 6, 2.6, c)
		U.Line(x, y + 1, x + 5.5, y - 5, 2.6, c)
	end,
}
function K.TabBar(wep, st, btns, tab, behind)
	local bx, by, bw, bh = 16, H - 112, W - 32, 78
	local lk = LK(wep)
	U.Round(bh / 2, bx, by + 4, bw, bh, Color(0, 0, 0, 46))
	U.Round(bh / 2, bx, by, bw, bh, Mix(Color(37, 37, 41, 240), Color(250, 250, 252, 242), lk))
	if U.RoundRim then U.RoundRim(bh / 2, bx, by, bw, bh, 1.5, Mix(Color(255, 255, 255, 40), Color(0, 0, 0, 18), lk)) end
	local cw = (bw - 8) / 4
	local P = wep.STTS_ClkPill or tab
	if not behind then
		P = Lerp(1 - math.exp(-(wep.STTS_UIdt or 0) * 14), P, tab)
		if math.abs(P - tab) < 0.002 then P = tab end
		wep.STTS_ClkPill = P
	end
	U.Round((bh - 10) / 2, bx + 4 + (P - 1) * cw, by + 5, cw, bh - 10, Mix(Color(255, 255, 255, 30), Color(0, 0, 0, 16), lk))
	local acc = Acc(wep)
	for i = 1, 4 do
		local cx = bx + 4 + (i - 0.5) * cw
		local col = i == tab and acc or C.label
		if not behind then U.Reg(btns, 19 + i, bx + 4 + (i - 1) * cw, by, cw, bh, function() K.SetTab(wep, st, i) end) end
		TABICON[i](cx, by + 29, col)
		U.T(TABS[i], "STTS_CK_Tab", cx, by + 59, col)
	end
end

--[[---------------------------------------------------------------------------
	the sound list (Add / Edit Alarm > Sound, Timers > When Timer Ends)
---------------------------------------------------------------------------]]
function K.SoundGroups()
	if K.groups then return K.groups end
	local a, r = {}, {}
	for _, s in ipairs(G.AlarmSounds) do a[#a + 1] = {id = s.id, name = s.id == G.AlarmDefault and (s.name .. " (Default)") or s.name} end
	for _, s in ipairs(G.Ringtones) do r[#r + 1] = {id = "rt:" .. s.id, name = s.name} end
	K.groups = {{hdr = "Alarms", items = a}, {hdr = "Ringtones", items = r}, {items = {{id = "none", name = "None"}}}}
	return K.groups
end
local SROW = 66
function K.SoundList(wep, st, btns, top, cur, pick, live)
	local groups = K.SoundGroups()
	local total = 20
	for _, g in ipairs(groups) do total = total + (g.hdr and 54 or 30) + #g.items * SROW end
	total = total + 60
	local sy, s, mx = K.Scroller(wep, st, btns, top, H, total, not live)
	local acc = Acc(wep)
	local cell = CellBg(wep)
	local y = top + 20 - sy
	local n = 0
	U.Clip(0, top, W, H - top)
	for _, g in ipairs(groups) do
		if g.hdr then U.T(string.upper(g.hdr), "STTS_CK_Hdr", 36, y + 34, C.label2, TEXT_ALIGN_LEFT) y = y + 54 else y = y + 30 end
		local ch = #g.items * SROW
		if y + ch > top and y < H then U.Round(26, 16, y, W - 32, ch, cell) end
		for i, it in ipairs(g.items) do
			n = n + 1
			local ry = y + (i - 1) * SROW
			if ry + SROW > top and ry < H then
				local id = 180 + n
				local y1, y2 = math.max(ry, top), math.min(ry + SROW, H)
				local fn = (live and y2 - y1 > 8) and function() pick(it.id) end or nil
				if fn then U.Reg(btns, id, 16, y1, W - 32, y2 - y1, fn) end
				local k = fn and U.HoverK(wep, id, st.sel == id) or 0
				if k > 0.01 then
					local col = (U.LinCol or function(c) return c end)(SCR.Ink(((U.Pressed(wep, st, id)) and 40 or 18) * k))
					draw.RoundedBoxEx(26, 16, ry, W - 32, SROW, col, i == 1, i == 1, i == #g.items, i == #g.items)
				end
				if it.id == cur then GCheck(44, ry + SROW / 2, 9, acc, 3.4) end
				U.T(U.Fit(it.name, "STTS_I_Body", W - 120), "STTS_I_Body", 70, ry + SROW / 2, C.label, TEXT_ALIGN_LEFT)
				if i < #g.items then U.R(70, ry + SROW - 1, W - 86, 1, C.sep) end
			end
		end
		y = y + ch
	end
	U.Unclip()
	if live then K.Bar(wep, st, top, H, total, s, mx) end
end
-- a sub-page header: < (glass circle), the title in the middle
function K.SubHeader(wep, st, btns, y, title, back)
	CBtn(wep, st, btns, 47, 46, y, 26, back)
	U.Chevron(42, y, 10, "left", C.label, 3.6)
	U.T(title, "STTS_I_Nav", W / 2, y, C.label)
end

--[[---------------------------------------------------------------------------
	Add / Edit Alarm (G.APP_ALARMED): a sheet over the Clock. the draft is local
	(L.ae55), the server gets it on Save. others see the sheet, not your draft
---------------------------------------------------------------------------]]
function K.OpenEditor(wep, st, a)
	if not st.own then return end
	local now = os.date("*t")
	L.ae55 = {wep = wep, id = a and a.id or 0, days = a and a.days or 0, snooze = (a == nil) or a.snooze,
		snd = a and a.snd ~= "" and a.snd or G.AlarmDefault, label = a and a.label or ""}
	K.SetWheels(a and a.h or now.hour, a and a.m or now.min)
	wep.STTS_SK = wep.STTS_SK or {}
	wep.STTS_SK.aepage = {x = 0, v = 0}
	wep.STTS_SK.aesnz = nil
	L.swipe55 = nil
	U.SetApp(st, SHEET)
end
local function EntryOff() if IsValid(L.entry) and L.entry.clk55 then L.entry:Remove() end end
function K.CloseEditor(wep, st)
	if not st.own then return end
	EntryOff()
	U.SetApp(st, APP)
end
function K.Save(wep, st)
	local ae = L.ae55
	if not st.own or not ae or ae.wep ~= wep then return end
	local h, m = K.WheelTime(wep)
	local label = string.Trim((string.gsub(ae.label or "", "[%c|]", "")))
	U.Act("alarmset", string.format("%d|%02d%02d|%d|%d|%s|%s", ae.id, h, m, ae.days, ae.snooze and 1 or 0, ae.snd, label))
	K.CloseEditor(wep, st)
end
function K.Page(ae, page)
	if ae.page == "sound" and page ~= "sound" and ae.prev then ae.prev = nil U.Act("alarmprev", "none") end
	ae.page = page
	if page then ae.shown = page end
	L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
	EntryOff()
end
-- Label: an invisible text entry catches the keyboard (like TeleChat)
function K.OpenLabel(wep, st)
	local ae = L.ae55
	if not st.own or not L.raised or not ae then return end
	if IsValid(L.entry) then
		if L.entry.clk55 and IsValid(L.entry.te) then L.entry.te:RequestFocus() return end
		L.entry:Remove()
	end
	local fr = vgui.Create("EditablePanel")
	fr:SetSize(2, 2) fr:SetPos(-10, -10)
	fr:MakePopup()
	fr:SetKeyboardInputEnabled(true)
	fr:SetMouseInputEnabled(false)
	fr.openedAt = RealTime()
	fr.Paint = function() end
	local te = vgui.Create("DTextEntry", fr)
	te:SetPos(0, 0) te:SetSize(2, 2)
	te:SetText(ae.label or "")
	te:SetCaretPos(#(SCR.U8Starts and SCR.U8Starts(ae.label or "") or {}))
	te:SetUpdateOnType(true)
	te.Paint = function() end
	te.AllowInput = function(self, ch) return ch == "|" or #(self:GetValue() or "") >= 40 end -- true = blocked
	te.OnValueChange = function(self, v) ae.label = (string.gsub(v or "", "[%c|]", "")) end
	te.OnEnter = function(self) ae.label = (string.gsub(self:GetValue() or "", "[%c|]", "")) fr:Remove() end
	fr.Think = function(self)
		if not L.raised or L.app ~= SHEET or L.ae55 ~= ae or ae.page then self:Remove() return end
		if RealTime() - self.openedAt > 0.3 and IsValid(te) and not te:HasFocus() then self:Remove() return end
	end
	fr.te = te
	fr.clk55 = true
	L.entry = fr
	te:RequestFocus()
end

function K.SheetMain(wep, st, btns, ae, sy, live)
	local own = st.own and live
	local acc = Acc(wep)
	local cell = CellBg(wep)
	local hy = sy + 52
	CBtn(wep, st, btns, 40, 46, hy, 26, own and function() K.CloseEditor(wep, st) end)
	GX(46, hy, 8, C.label, 3.2)
	U.T(ae.id ~= 0 and "Edit Alarm" or "Add Alarm", "STTS_I_Nav", W / 2, hy, C.label)
	CBtn(wep, st, btns, 41, W - 46, hy, 26, own and function() K.Save(wep, st) end, acc)
	GCheck(W - 46, hy + 1, 9, WHITE, 3.4)
	-- the time wheels
	local cy, rh = sy + 254, 56
	U.Round(16, 16, cy - rh / 2, W - 32, rh, Band(wep))
	U.Clip(0, cy - 150, W, 300)
	local function Wv(key, n, loop, v)
		if st.own then return K.Wh(key, n, loop) end
		return {p = v, n = n, loop = loop}
	end
	local now = os.date("*t")
	if H24(wep) then
		K.Wheel(wep, Wv("ah24", 24, true, now.hour), W / 2 - 20, cy, rh, Two, TEXT_ALIGN_RIGHT, own, {x0 = 0, x1 = W / 2, y0 = cy - 150, y1 = cy + 150})
		K.Wheel(wep, Wv("am", 60, true, now.min), W / 2 + 20, cy, rh, Two, TEXT_ALIGN_LEFT, own, {x0 = W / 2, x1 = W, y0 = cy - 150, y1 = cy + 150})
	else
		K.Wheel(wep, Wv("ah12", 12, true, now.hour % 12), W / 2 - 52, cy, rh, H12, TEXT_ALIGN_RIGHT, own, {x0 = 0, x1 = W / 2 - 36, y0 = cy - 150, y1 = cy + 150})
		K.Wheel(wep, Wv("am", 60, true, now.min), W / 2 - 20, cy, rh, Two, TEXT_ALIGN_LEFT, own, {x0 = W / 2 - 36, x1 = W / 2 + 56, y0 = cy - 150, y1 = cy + 150})
		K.Wheel(wep, Wv("ap", 2, false, now.hour >= 12 and 1 or 0), W / 2 + 74, cy, rh, AP, TEXT_ALIGN_LEFT, own, {x0 = W / 2 + 56, x1 = W, y0 = cy - 150, y1 = cy + 150})
	end
	U.Unclip()
	-- the rows
	local y, R2 = sy + 432, 72
	U.Round(26, 16, y, W - 32, R2 * 4, cell)
	CRow(wep, st, btns, 42, 16, y, W - 32, R2, "Repeat", RepeatText(ae.days, true), true, own and function() K.Page(ae, "repeat") end, true, false)
	U.R(36, y + R2 - 1, W - 52, 1, C.sep)
	-- Label: a text field right in the row
	local typing = own and IsValid(L.entry) and L.entry.clk55
	CRow(wep, st, btns, 43, 16, y + R2, W - 32, R2, "Label", nil, false, own and function() K.OpenLabel(wep, st) end, false, false)
	local lab = ae.label or ""
	local lx = W - 36
	if lab ~= "" then
		local fit = U.Fit(lab, "STTS_I_Body", W * 0.5)
		U.T(fit, "STTS_I_Body", lx, y + R2 * 1.5, C.label2, TEXT_ALIGN_RIGHT)
	elseif not typing then
		U.T("Alarm", "STTS_I_Body", lx, y + R2 * 1.5, C.label3, TEXT_ALIGN_RIGHT)
	end
	if typing and math.floor(RealTime() * 2) % 2 == 0 then U.R(lx + 3, y + R2 + 20, 3, R2 - 40, acc) end
	U.R(36, y + R2 * 2 - 1, W - 52, 1, C.sep)
	CRow(wep, st, btns, 44, 16, y + R2 * 2, W - 32, R2, "Sound", G.AlarmSoundName(ae.snd), true, own and function() K.Page(ae, "sound") end, false, false)
	U.R(36, y + R2 * 3 - 1, W - 52, 1, C.sep)
	CRow(wep, st, btns, 45, 16, y + R2 * 3, W - 32, R2, "Snooze", nil, false, own and function() ae.snooze = not ae.snooze end, false, true)
	Switch(W - 36 - 80, y + R2 * 3.5 - 24, U.SpringK(wep, "aesnz", ae.snooze, 0.32, 0.78), 0, 1)
	if ae.id ~= 0 then
		local dy = y + R2 * 4 + 32
		U.Round(26, 16, dy, W - 32, R2, cell)
		CRow(wep, st, btns, 46, 16, dy, W - 32, R2, nil, nil, false, own and function() K.Delete(wep, ae.id) K.CloseEditor(wep, st) end, true, true)
		U.T("Delete Alarm", "STTS_I_Body", W / 2, dy + R2 / 2, C.red)
	end
	if own then L.maxScroll = 0 end
end
function K.SheetRepeat(wep, st, btns, ae, sy, live)
	local own = st.own and live
	local acc = Acc(wep)
	K.SubHeader(wep, st, btns, sy + 52, "Repeat", own and function() K.Page(ae, nil) end)
	local y, R2 = sy + 112, 70
	U.Round(26, 16, y, W - 32, R2 * 7, CellBg(wep))
	for i = 0, 6 do
		local bitv = bit.lshift(1, i)
		local ry = y + i * R2
		CRow(wep, st, btns, 50 + i, 16, ry, W - 32, R2, "Every " .. DAY[i + 1], nil, false,
			own and function() ae.days = bit.bxor(ae.days, bitv) end, i == 0, i == 6)
		if bit.band(ae.days, bitv) ~= 0 then GCheck(W - 50, ry + R2 / 2, 9, acc, 3.4) end
		if i < 6 then U.R(36, ry + R2 - 1, W - 52, 1, C.sep) end
	end
	if own then L.maxScroll = 0 end
end
function K.SheetSound(wep, st, btns, ae, sy, live)
	local own = st.own and live
	K.SoundList(wep, st, btns, sy + 96, ae.snd, function(id)
		ae.snd = id
		ae.prev = id ~= "none"
		U.Act("alarmprev", id)
	end, own)
	U.R(0, sy + 40, W, 56, SheetBg(wep))
	K.SubHeader(wep, st, btns, sy + 52, "Sound", own and function() K.Page(ae, nil) end)
end

function K.Draft(wep, st)
	if st.own then
		local ae = L.ae55
		if not ae or ae.wep ~= wep then
			local now = os.date("*t")
			L.ae55 = {wep = wep, id = 0, days = 0, snooze = true, snd = G.AlarmDefault, label = ""}
			K.SetWheels(now.hour, now.min)
		end
		return L.ae55
	end
	return {wep = wep, id = 0, days = 0, snooze = true, snd = G.AlarmDefault, label = ""}
end
-- the Clock behind a sheet: pushed back, smaller, rounded, dimmed (UISheetPresentationController)
function K.Behind(wep, st, x, y, s)
	local m = Matrix()
	m:Translate(Vector(x, y, 0))
	m:Scale(Vector(s, s, 1))
	cam.PushModelMatrix(m, true)
	local xf = SCR.XF
	SCR.XF = xf and {x = xf.x + x * xf.s, y = xf.y + y * xf.s, s = xf.s * s} or {x = x, y = y, s = s}
	local mx = L.maxScroll
	wep.STTS_ClkBehind = true
	local pst = setmetatable({sel = 0, scroll = 0, app = APP}, {__index = st})
	U.R(0, 0, W, H, C.bg or BLACK)
	local ok, err = pcall(K.ClockApp, wep, pst, {})
	wep.STTS_ClkBehind = nil
	L.maxScroll = mx
	SCR.XF = xf
	cam.PopModelMatrix()
	if not ok then ErrorNoHalt(tostring(err) .. "\n") end
end
function K.SheetApp(wep, st, btns)
	local ae = K.Draft(wep, st)
	local dim = math.Clamp(wep.STTS_SheetDim or 1, 0, 1)
	local live = st.own and (wep.STTS_SheetOff or 0) < 1
	if live then wep.STTS_Wheels55 = {} wep.STTS_ClkRows = nil end
	U.R(0, 0, W, H, BLACK)
	local s = 1 - 0.07 * dim
	local px, py = W * (1 - s) / 2, 40 * dim
	K.Behind(wep, st, px, py, s)
	if dim > 0.01 then Corners(px, py, W * s, H * s, 44 * dim, BLACK) end
	U.R(0, 0, W, H, Color(0, 0, 0, 80 * dim))
	local sy = 58 + (wep.STTS_SheetOff or 0)
	local bg = SheetBg(wep)
	U.Round(40, 0, sy, W, H - sy + 80, bg)
	-- the pages inside the sheet push like a navigation stack
	local goal = st.own and ae.page ~= nil
	local pk = U.SpringK(wep, "aepage", goal, 0.42, 1)
	local settled = math.abs(pk - (goal and 1 or 0)) < 0.02
	if pk < 0.995 then
		local ok = live and not goal and settled
		Shifted(-W * 0.3 * pk, function() K.SheetMain(wep, st, ok and btns or {}, ae, sy, ok) end)
	end
	if pk > 0.005 and ae.shown then
		local ok = live and goal and settled
		local x = W * (1 - pk)
		for i = 1, 8 do U.R(x - i * 2, sy + 20, 2, H - sy, Color(0, 0, 0, 40 * (1 - pk) * (1 - i / 9))) end
		Shifted(x, function()
			U.Round(40, 0, sy, W, H - sy + 80, bg)
			if ae.shown == "repeat" then K.SheetRepeat(wep, st, ok and btns or {}, ae, sy, ok)
			else K.SheetSound(wep, st, ok and btns or {}, ae, sy, ok) end
		end)
	elseif st.own and not goal then
		ae.shown = nil
	end
	if live and not settled then wep.STTS_Wheels55 = {} end
end

--[[ the Clock app itself ]]
function K.TimerSoundPage(wep, st, btns, live)
	local own = st.own and live
	local cur = K.TmSnd(wep, st)
	K.SoundList(wep, st, btns, 104, cur, function(id)
		L.tmSnd55 = {wep = wep, v = id, at = RealTime()}
		U.Act("tm", "snd:" .. id) -- the server previews it too (one act: its cooldown)
	end, own)
	U.T("When Timer Ends", "STTS_SET_Nav", W / 2, 78, C.label)
	U.NavBack(btns, wep, st, "Timers", own and function()
		L.tmPage55 = nil
		L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
		U.Act("prevstop", "")
	end or function() end)
end
function K.ClockApp(wep, st, btns)
	local behind = wep.STTS_ClkBehind
	if st.own and not behind then wep.STTS_Wheels55, wep.STTS_ClkRows = {}, nil end
	local tab = K.Tab(wep, st)
	local page = st.own and L.tmPage55 == wep and tab == 4
	local pk = U.SpringK(wep, "tmpage", page, 0.42, 1)
	if behind then pk = 0 end
	local settled = math.abs(pk - (page and 1 or 0)) < 0.02
	local function Main()
		local b = (not page and settled) and btns or {}
		local bh = behind or page or not settled
		if tab == 1 then K.World(wep, st, b, bh)
		elseif tab == 2 then K.AlarmsTab(wep, st, b, bh)
		elseif tab == 3 then K.Stopwatch(wep, st, b, bh)
		else K.Timers(wep, st, b, bh) end
		K.TabBar(wep, st, b, tab, behind)
	end
	if pk < 0.995 then Shifted(-W * 0.3 * pk, Main) end
	if pk > 0.005 then
		local x = W * (1 - pk)
		for i = 1, 8 do U.R(x - i * 2, 0, 2, H, Color(0, 0, 0, 40 * (1 - pk) * (1 - i / 9))) end
		Shifted(x, function()
			U.R(0, 0, W, H, C.bg or BLACK)
			K.TimerSoundPage(wep, st, (page and settled) and btns or {}, page and settled)
		end)
	end
end

--[[---------------------------------------------------------------------------
	a ringing alarm / timer: the whole screen, iOS 26.1 (the time of the lock screen,
	the label, a big Snooze, "slide to stop"). NW2 "AlmRing" = "kind|id|HHMM|snooze|label"
---------------------------------------------------------------------------]]
function K.RingInfo(wep)
	local s = wep:GetNW2String("AlmRing", "")
	if s == "" then return end
	local kind, id, hh, mm, snz, label = string.match(s, "^(%a)|(%d+)|(%d%d)(%d%d)|(%d)|(.*)$")
	if not kind then return end
	return {kind = kind, id = tonumber(id), h = tonumber(hh), m = tonumber(mm), snooze = snz == "1", label = label,
		sig = s .. "@" .. wep:GetNW2Float("AlmRingAt", 0)}
end
-- shown = ringing and not stopped / snoozed by you a moment ago (the server may have
-- dropped that tap: then it shows again)
function K.Shown(wep)
	local r = K.RingInfo(wep)
	if not r then return false end
	local hd = L.almHide55
	if hd and hd.wep == wep and hd.sig == r.sig and RealTime() - hd.at < 2.5 then return false end
	return true, r
end
SCR.AlarmShown = function(wep) return L.wep == wep and (K.Shown(wep)) or false end
local function Hide(wep, r) L.almHide55 = {wep = wep, sig = r.sig, at = RealTime(), r = r} end
function K.Snooze(wep, st, r) if st.own then U.Act("alarmsnooze", "") Hide(wep, r) end end
function K.StopRing(wep, st, r) if st.own then U.Act("alarmstop", "") Hide(wep, r) end end
function K.RepeatTimer(wep, st, r) if st.own then U.Act("tmrepeat", "") Hide(wep, r) end end

--[[ fix56: 1:1 with iOS 26.1 (measured on Apple's screenshot): pure black, the label with
     the alarm.fill glyph (grey) at 22.5 % of the height, the big bold time at 34 %, the
     orange Snooze capsule and the dark "slide to stop" track at the bottom (36 px margins,
     102 px tall, 26 px apart), the knob = a plain dark grey disc (fix57: no glass) with a
     white rounded stop square, the grey text right of it with the shimmer of slide to unlock ]]
local SL_X, SL_H, KNOB = 36, 102, 48
local SNZ = Color(250, 148, 56)        -- the orange of the Snooze capsule
local RING_GREY = Color(152, 152, 157) -- the label + glyph
local SLIDE_TXT = Color(112, 112, 112)
-- SF Symbol alarm.fill: a filled face (dark hands), two bells, two feet
local function AlarmGlyph(x, y, s, col, a)
	local bg = Color(0, 0, 0, 255 * a)
	U.Line(x - s * 0.62, y + s * 0.74, x - s * 0.86, y + s * 1.02, s * 0.2, col)
	U.Line(x + s * 0.62, y + s * 0.74, x + s * 0.86, y + s * 1.02, s * 0.2, col)
	U.Circle(x - s * 0.84, y - s * 0.84, s * 0.44, col)
	U.Circle(x + s * 0.84, y - s * 0.84, s * 0.44, col)
	U.Circle(x, y + s * 0.06, s * 1.16, bg)
	U.Circle(x, y + s * 0.06, s, col)
	U.Line(x, y + s * 0.06, x, y - s * 0.56, s * 0.17, bg)
	U.Line(x, y + s * 0.06, x + s * 0.44, y + s * 0.06, s * 0.17, bg)
end
-- SF Symbol timer: a ring with a hand and the crown on top
local function TimerGlyph(x, y, s, col)
	U.Arc(x, y + s * 0.08, s, s * 0.2, -60, 240, col, 28)
	U.Line(x, y - s * 1.02, x, y - s * 0.66, s * 0.2, col)
	U.Line(x, y + s * 0.08, x + s * 0.42, y - s * 0.34, s * 0.18, col)
	U.Circle(x, y + s * 0.08, s * 0.16, col)
end
function K.DrawRing(wep, st, btns, r, alpha, age)
	local own = st.own and btns ~= nil
	local now = RealTime()
	local inK = math.Clamp((age or 1) / 0.45, 0, 1)
	local e = 1 - (1 - inK) ^ 3
	local a = math.Clamp(alpha * inK, 0, 1)
	if a <= 0.005 then return end
	U.R(0, 0, W, H, Color(0, 0, 0, 255 * a))
	surface.SetAlphaMultiplier(a)
	local rise = (1 - e) * 22
	-- the label + glyph
	local label = r.label ~= "" and r.label or (r.kind == "t" and "Timer" or "Alarm")
	label = U.Fit(label, "STTS_CK_RingL", W - 120)
	surface.SetFont("STTS_CK_RingL")
	local lw = surface.GetTextSize(label)
	local ly = 216 + rise
	local gs = 11.5
	local x0 = W / 2 - (lw + gs * 2 + 13) / 2
	if r.kind == "t" then TimerGlyph(x0 + gs, ly, gs, RING_GREY) else AlarmGlyph(x0 + gs, ly, gs, RING_GREY, a) end
	U.T(label, "STTS_CK_RingL", x0 + gs * 2 + 13, ly, RING_GREY, TEXT_ALIGN_LEFT)
	-- the time (12 h: no leading zero, no AM / PM, like iOS)
	local tm = H24(wep) and os.date("%H:%M") or (string.gsub(os.date("%I:%M"), "^0", ""))
	U.T(tm, "STTS_CK_RingT", W / 2, 330 + rise, WHITE)
	-- Snooze (alarm) / Repeat (timer)
	local bx, bw, bh = SL_X, W - SL_X * 2, SL_H
	local by = 650 + rise * 0.5
	local big, bigFn
	if r.kind == "a" and r.snooze then big, bigFn = "Snooze", function() K.Snooze(wep, st, r) end
	elseif r.kind == "t" and wep:GetNW2Int("TmDur", 0) > 0 then big, bigFn = "Repeat", function() K.RepeatTimer(wep, st, r) end end
	if big then
		local id = big == "Snooze" and 60 or 61
		if own then U.Reg(btns, id, bx, by, bw, bh, bigFn) end
		local hk = own and U.HoverK(wep, id, st.sel == id) or 0
		local pr = own and U.Pressed(wep, st, id)
		-- flat: a pressed button only gets a little lighter
		local lift = (pr and 0.14 or 0) + 0.05 * hk
		U.Round(bh / 2, bx, by, bw, bh, Mix(SNZ, WHITE, lift))
		U.T(big, "STTS_CK_Big", bx + bw / 2, by + bh / 2, WHITE)
	end
	-- slide to stop
	local ty = 778 + rise * 0.3
	local maxX = bw - 6 - KNOB * 2
	local sl = L.slide55
	local x = 0
	if st.own and sl then
		local dt = wep.STTS_UIdt or 0
		if own and not sl.drag then
			if sl.done then sl.x = Lerp(1 - math.exp(-dt * 22), sl.x, maxX)
			else sl.x = Lerp(1 - math.exp(-dt * 13), sl.x, 0) if sl.x < 0.3 then sl.x = 0 end end
		end
		x = math.Clamp(sl.x or 0, 0, maxX)
	end
	U.Round(bh / 2, bx, ty, bw, bh, Color(26, 26, 26))
	local ta = math.Clamp(1 - x / (maxX * 0.45), 0, 1)
	if ta > 0.01 then
		local text = "slide to stop"
		local tx0 = bx + 3 + KNOB * 2 + 16 + x * 0.35
		local cy = ty + bh / 2
		U.T(text, "STTS_CK_Slide", tx0, cy, Color(SLIDE_TXT.r, SLIDE_TXT.g, SLIDE_TXT.b, 255 * ta), TEXT_ALIGN_LEFT)
		-- the shimmer of slide to unlock: a soft light band runs over the letters
		surface.SetFont("STTS_CK_Slide")
		local tw = surface.GetTextSize(text)
		local ph = (now % 2.6) / 2.6
		local cxs = tx0 - 70 + (tw + 140) * ph
		for i, wd in ipairs({96, 60, 30}) do
			U.Clip(cxs - wd / 2, ty, wd, bh)
			U.T(text, "STTS_CK_Slide", tx0, cy, Color(255, 255, 255, (26 + 30 * i) * ta), TEXT_ALIGN_LEFT)
			U.Unclip()
		end
	end
	-- the knob: a plain dark grey disc, the white stop square (held = a bit lighter)
	local held = own and sl and sl.drag
	local kr = KNOB
	local kx, ky = bx + 3 + KNOB + x, ty + bh / 2
	U.Circle(kx, ky, kr, held and Color(72, 72, 74) or Color(58, 58, 60))
	local q = 31
	U.Round(6, kx - q / 2, ky - q / 2, q, q, WHITE)
	if own then wep.STTS_Knob55 = {x = kx - KNOB, y = ky - KNOB, w = KNOB * 2, h = KNOB * 2, max = maxX, r = r} end
	surface.SetAlphaMultiplier(1)
end
function SCR.DrawAlarm(wep, st, btns)
	local shown, r = K.Shown(wep)
	st.almShown55 = shown
	if not shown then
		if st.own then wep.STTS_Knob55 = nil end
		local f = L.almHide55
		if st.own and f and f.wep == wep and f.r and RealTime() - f.at < 0.35 then -- fades out after Stop / Snooze
			K.DrawRing(wep, st, nil, f.r, 1 - (RealTime() - f.at) / 0.35, 9)
		end
		return
	end
	local seen = wep.STTS_AlmSeen55
	if not seen or seen.sig ~= r.sig then
		seen = {sig = r.sig, at = RealTime()}
		wep.STTS_AlmSeen55 = seen
		if st.own then -- it comes over everything: the Control Centre closes, jiggle mode ends
			L.shade, L.shadeV, L.shadeT = 0, 0, 0
			L.jig55, L.hdrag55 = nil, nil
			L.slide55 = {x = 0}
			if IsValid(L.entry) then L.entry:Remove() end
		end
	end
	-- it takes every touch (the first button registered wins, so the others go)
	for i = #btns, 1, -1 do btns[i] = nil end
	btns.zones = {}
	K.DrawRing(wep, st, btns, r, 1, RealTime() - seen.at)
end
-- white status bar over the sheet (pushed back page on black) and over a ringing alarm
function SCR.StatusDark(wep, st) return st.app == SHEET or st.almShown55 == true end
-- a ringing phone, a running stopwatch / timer on screen: more frames
function SCR.FastRate(wep)
	if wep:GetNW2String("AlmRing", "") ~= "" then return true end
	return wep:GetNW2Int("App", 0) == APP and (wep:GetNW2Float("SwStart", 0) > 0 or wep:GetNW2Float("TmEnd", 0) > 0)
end

--[[---------------------------------------------------------------------------
	touch: the slider of a ringing alarm, the wheels, swipe a row to Delete
---------------------------------------------------------------------------]]
local HOOK = {name = "clock55"}
local function In(z, fx, fy, pad)
	pad = pad or 0
	return z and fx >= z.x - pad and fx <= z.x + z.w + pad and fy >= z.y - pad and fy <= z.y + z.h + pad
end
function HOOK.Begin(wep, t, fx, fy)
	if L.wep ~= wep then return end
	if K.Shown(wep) then
		t.shadeCand, t.homeCand, t.edgeCand, t.shadeOpen = nil, nil, nil, nil
		t.clkAlarm = true
		local kb = wep.STTS_Knob55
		if In(kb, fx, fy, 12) then
			L.slide55 = L.slide55 or {x = 0}
			L.slide55.drag, L.slide55.done = true, nil
			t.clkSlide = {x0 = fx, k0 = L.slide55.x or 0}
		end
		return
	end
	if (L.shade or 0) > 0.02 or wep.STTS_Anim then return end
	local tab = K.Tab(wep, {own = true})
	if L.app == SHEET or (L.app == APP and tab == 4) then
		for _, z in ipairs(wep.STTS_Wheels55 or {}) do
			if z.w and fx >= z.x0 and fx < z.x1 and fy >= z.y0 and fy <= z.y1 then
				local w = z.w
				t.clkWheel = {z = z, w = w, y0 = fy, p0 = w.p, lp = w.p, lt = RealTime(), v = 0, spin = w.go ~= nil and math.abs(w.go - w.p) > 0.3}
				w.go, w.drag = nil, true
				t.edgeCand = nil
				return
			end
		end
	end
	if L.app == APP and tab == 2 then
		local sw = L.swipe55
		if sw and sw.wep == wep and sw.goal ~= 0 then
			local onDel = false
			for _, r in ipairs(wep.STTS_ClkRows or {}) do
				if r.id == sw.id and fy >= r.y and fy < r.y + r.h and fx >= W + sw.x then onDel = true end
			end
			if not onDel then t.clkClose = true end
		end
		for _, r in ipairs(wep.STTS_ClkRows or {}) do
			if fy >= r.y and fy < r.y + r.h and fy > 104 then
				t.clkRow = {id = r.id, x0 = fx, y0 = fy, off0 = (sw and sw.wep == wep and sw.id == r.id) and sw.x or 0}
				break
			end
		end
	end
end
local function Rub(x) return (1 - 1 / (x * 0.55 + 1)) * 1.2 end
function HOOK.Move(wep, t, fx, fy, dx, dy, dmin)
	if t.clkAlarm then
		local cs = t.clkSlide
		local kb = wep.STTS_Knob55
		if cs and L.slide55 then
			L.slide55.x = math.Clamp(cs.k0 + fx - cs.x0, 0, kb and kb.max or 300)
			t.moved = true
		end
		if cs or (fx - t.x0) ^ 2 + (fy - t.y0) ^ 2 > dmin * dmin then t.moved = true L.sel = 0 end
		return true -- nothing below scrolls / drags
	end
	local cw = t.clkWheel
	if cw then
		local w = cw.w
		if not cw.on then
			if (fy - cw.y0) ^ 2 + (fx - t.x0) ^ 2 < (dmin * 0.6) ^ 2 then return true end
			cw.on, cw.y0, cw.p0 = true, fy, w.p
			t.moved = true
		end
		local p = cw.p0 - (fy - cw.y0) / cw.z.rowH
		if not w.loop then
			if p < 0 then p = -Rub(-p) elseif p > w.n - 1 then p = w.n - 1 + Rub(p - (w.n - 1)) end
		end
		w.p = p
		local now = RealTime()
		local ddt = now - cw.lt
		if ddt > 0.001 then
			cw.v = Lerp(math.Clamp(ddt * 18, 0, 1), cw.v, (p - cw.lp) / ddt)
			cw.lp, cw.lt = p, now
		end
		L.sel = 0
		return true
	end
	local cr = t.clkRow
	if cr then
		local ddx, ddy = fx - cr.x0, fy - cr.y0
		if not cr.dir then
			if ddx * ddx + ddy * ddy < dmin * dmin then return end
			if math.abs(ddx) > math.abs(ddy) * 1.1 and (ddx < 0 or cr.off0 < 0) and not (L.clkEdit55 == wep) then
				cr.dir = "h"
				cr.x0 = fx
				t.moved, t.edgeCand, t.homeCand = true, nil, nil
				L.swipe55 = {wep = wep, id = cr.id, x = cr.off0, goal = cr.off0, drag = true}
			else
				cr.dir = "v"
				t.clkRow = nil
				return
			end
		end
		local sw = L.swipe55
		if sw and sw.id == cr.id then
			local x = cr.off0 + (fx - cr.x0)
			if x > 0 then x = Rub(x / 80) * 30 end
			sw.x, sw.drag = math.max(x, -W), true
		end
		L.sel = 0
		return true
	end
end
function HOOK.End(w, t, cancel)
	if t.clkAlarm then
		local cs = t.clkSlide
		local sl = L.slide55
		if cs and sl then
			sl.drag = nil
			local kb = w.STTS_Knob55
			if not cancel and kb and sl.x >= kb.max * 0.9 then
				sl.done = true
				K.StopRing(w, {own = true}, kb.r)
			end
			return true
		end
		return t.moved -- a tap goes to Snooze / Repeat
	end
	local cw = t.clkWheel
	if cw then
		local wh = cw.w
		wh.drag = nil
		if cw.on then
			local v = RealTime() - cw.lt < 0.08 and cw.v or 0
			local go
			if math.abs(v) > 2 then go, wh.rate = math.floor(wh.p + v / 3.2 + 0.5), 3.2
			else go, wh.rate = math.floor(wh.p + 0.5), 14 end
			if not wh.loop then go = math.Clamp(go, 0, wh.n - 1) end
			wh.go = go
		elseif not cancel and not cw.spin then
			-- a tap on a row turns it to the middle
			local R = cw.z.rowH / RAD
			local fy = cw.y0
			local d = math.floor(math.asin(math.Clamp((fy - cw.z.cy) / R, -0.99, 0.99)) / RAD + 0.5)
			local go = math.floor(wh.p + 0.5) + d
			if not wh.loop then go = math.Clamp(go, 0, wh.n - 1) end
			wh.go, wh.rate = go, 10
		end
		return true
	end
	local cr = t.clkRow
	if cr and cr.dir == "h" then
		local sw = L.swipe55
		if sw and sw.id == cr.id then
			sw.drag = nil
			if not cancel and sw.x < -W * 0.6 then
				sw.goal = -W
				K.Delete(w, cr.id) -- full swipe = delete at once (iOS)
			elseif not cancel and sw.x < -SW_W * 0.5 then sw.goal = -SW_W
			else sw.goal = 0 end
		end
		return true
	end
	if t.clkClose then
		local sw = L.swipe55
		if sw then sw.goal = 0 sw.drag = nil end
		return true -- iOS: the tap only closes the open row
	end
end
SCR.TouchHooks = SCR.TouchHooks or {}
do
	local found
	for i, h in ipairs(SCR.TouchHooks) do if h.name == HOOK.name then SCR.TouchHooks[i] = HOOK found = true end end
	if not found then table.insert(SCR.TouchHooks, 1, HOOK) end -- before the home screen: a ringing alarm comes first
end

--[[---------------------------------------------------------------------------
	the home screen icon: a live analog clock (iOS), drawn into a render target
---------------------------------------------------------------------------]]
local ICO = {s = 168, at = 0, sec = -1, secAt = 0}
function K.IconMat()
	if ICO.mat then return ICO.mat end
	ICO.rt = GetRenderTargetEx("stts55_clockico", ICO.s, ICO.s, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8 + 256, 0, IMAGE_FORMAT_RGBA8888)
	ICO.mat = CreateMaterial("stts55_clockico_m", "UnlitGeneric", {["$basetexture"] = ICO.rt:GetName(), ["$translucent"] = 1,
		["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$ignorez"] = 1})
	ICO.dirty = true
	return ICO.mat
end
local function Hand(cx, cy, deg, len, tail, th, col)
	local a = math.rad(deg)
	local sx, sy = math.sin(a), -math.cos(a)
	U.Line(cx - sx * tail, cy - sy * tail, cx + sx * len, cy + sy * len, th, col)
end
function K.DrawIcon()
	if not ICO.rt then return end
	local s = ICO.s
	local t = os.date("*t")
	local ot = os.time()
	if ot ~= ICO.sec then ICO.sec, ICO.secAt = ot, SysTime() end
	local sec = t.sec + math.Clamp(SysTime() - ICO.secAt, 0, 0.999)
	local cx, cy, R = s / 2, s / 2, s * 0.43
	render.PushRenderTarget(ICO.rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, true, true)
	cam.Start2D()
		draw.RoundedBox(math.floor(s * 0.225), 0, 0, s, s, Color(0, 0, 0, 255)) -- the squircle (alpha written)
		render.OverrideAlphaWriteEnable(true, false) -- the rest keeps the alpha of the squircle
		draw.RoundedBox(math.floor(R), cx - R, cy - R, R * 2, R * 2, Color(255, 255, 255, 255))
		for i = 0, 59 do
			if i % 5 ~= 0 then
				local a = math.rad(i * 6)
				U.Line(cx + math.sin(a) * R * 0.9, cy - math.cos(a) * R * 0.9, cx + math.sin(a) * R * 0.96, cy - math.cos(a) * R * 0.96, 1.2, Color(150, 150, 150))
			end
		end
		for i = 1, 12 do
			local a = math.rad(i * 30)
			draw.SimpleText(tostring(i), "STTS_CK_IcoN", cx + math.sin(a) * R * 0.76, cy - math.cos(a) * R * 0.76, Color(0, 0, 0), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		Hand(cx, cy, ((t.hour % 12) + t.min / 60 + sec / 3600) * 30, R * 0.5, 0, 6.5, Color(0, 0, 0))
		Hand(cx, cy, (t.min + sec / 60) * 6, R * 0.78, 0, 4.5, Color(0, 0, 0))
		U.Circle(cx, cy, 5, Color(0, 0, 0))
		Hand(cx, cy, sec * 6, R * 0.86, R * 0.2, 2, Color(255, 149, 0))
		U.Circle(cx, cy, 4, Color(255, 149, 0))
		U.Circle(cx, cy, 1.6, Color(255, 255, 255))
	cam.End2D()
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
end
hook.Add("PostRender", "STTS_ClockIcon55", function()
	if not ICO.rt then return end
	local now = RealTime()
	if now - ICO.at < 1 / 15 and not ICO.dirty then return end
	local lp = LocalPlayer()
	if not ICO.dirty and not (IsValid(lp) and lp:HasWeapon("weapon_stts_phone")) and now - ICO.at < 1 then return end
	ICO.at, ICO.dirty = now, nil
	K.DrawIcon()
end)

--[[ registration (again after a lua refresh of another file) ]]
local function Register()
	local APPS = SCR.APPS
	if not APPS then return end
	APPS[APP] = K.ClockApp
	APPS[SHEET] = K.SheetApp
	SCR.SheetParent = SCR.SheetParent or {}
	SCR.SheetParent[SHEET] = APP
	if SCR.APP_ICON then SCR.APP_ICON[APP] = K.IconMat() end
	if SCR.ROOT_ICON then SCR.ROOT_ICON[SHEET] = APP end
	if SCR.LEVEL then SCR.LEVEL[APP], SCR.LEVEL[SHEET] = 1, 2 end
	SCR.HomeApps = SCR.HomeApps or {}
	SCR.HomeApps.clock = SCR.HomeApps.clock or {}
	table.Merge(SCR.HomeApps.clock, {btn = 7, app = APP, label = "Clock", icon = K.IconMat, col = Color(20, 20, 22)})
end
Register()
hook.Add("Think", "STTS_PhoneClockApps", function()
	local APPS = SCR.APPS
	if APPS and (APPS[APP] ~= K.ClockApp or not (SCR.HomeApps and SCR.HomeApps.clock)) then Register() end
	-- leaving the Clock: no open row / Edit mode / timer sound page
	if L.app ~= APP and L.app ~= SHEET then
		if L.swipe55 or L.clkEdit55 or L.tmPage55 then L.swipe55, L.clkEdit55, L.tmPage55 = nil, nil, nil end
	end
	-- the UTC offset of this PC: alarms ring at YOUR local time (sv_phone_clock.lua)
	local now = RealTime()
	if now > (K.tzAt or 0) then
		K.tzAt = now + 60
		local lp = LocalPlayer()
		if IsValid(lp) then
			local tz = K.TZ()
			if tz ~= K.tzSent or now > (K.tzForce or 0) then
				K.tzSent, K.tzForce = tz, now + 600
				U.Act("tz", tostring(tz))
			end
		else
			K.tzAt = now + 2
		end
	end
end)

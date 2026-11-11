--[[---------------------------------------------------------------------------
	ZHUNTER phone - fix55: the home screen like an iPhone.
	* a grid of app icons (4 columns, labels) + the dock (up to 4, no labels)
	* touch and hold an icon (or the empty screen) ~0.5 s = jiggle mode: every icon
	  wobbles, "Done" top right. hold an icon and drag it: it lifts under the finger,
	  the other icons make room on a spring, drop it anywhere in the grid or the dock
	  (the dock takes 4 at most). tap the empty screen / Done / go home = finished.
	* the layout belongs to the PHONE: NW2 "HomeLay" ("grid ids|dock ids"), saved in
	  the owner's profile like a setting (sv_phone_settings.lua, act "home")
	* other apps register their icon in SCR.HomeApps (cl_phone_clock.lua: Clock)
---------------------------------------------------------------------------]]
STTS = STTS or {}
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
local U = SCR.UI
if not U or not G or not SCR.APPS then return end
local C, W, H = U.C, U.W, U.H
local L = SCR.L

local SIZE = 84
local GAP = (W - 28 - SIZE * 4) / 5
local COLS, ROWS = 4, 5
local TOP, PITCH = 112, 132
local DOCK_Y, DOCK_H = H - 168, 118
local ICON_Y = DOCK_Y + (DOCK_H - SIZE) / 2
local DONE = 8 -- button id
local HOLD = 0.5 -- touch and hold (s)
local GAPID = "_"

local function GridXY(i)
	local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
	return 14 + GAP + c * (SIZE + GAP), TOP + r * PITCH
end
local function DockXY(i, n)
	local span = n * SIZE + (n - 1) * GAP
	return (W - span) / 2 + (i - 1) * (SIZE + GAP), ICON_Y
end

--[[ the apps on the home screen ]]
SCR.HomeApps = SCR.HomeApps or {}
local A = SCR.HomeApps
local function Ico(key) return function() return U.icons and U.icons[key] end end
local function AppIco(app) return function() return SCR.APP_ICON and SCR.APP_ICON[app] end end
A.phone = A.phone or {}
A.chat = A.chat or {}
A.camera = A.camera or {}
A.photos = A.photos or {}
A.settings = A.settings or {}
A.zmusic = A.zmusic or {}
table.Merge(A.phone, {btn = 1, app = G.APP_CONTACTS, label = "Phone", icon = Ico("phone"), col = Color(48, 132, 246)})
table.Merge(A.chat, {btn = 4, app = G.APP_CHATS, label = "TeleChat", icon = Ico("chat"), col = Color(52, 199, 89), badge = function(wep, st)
	local n = (st.own and SCR.TCUnread and SCR.TCUnread(st.num)) or st.unread or 0
	if SCR.NoBadge and SCR.NoBadge(wep) then n = 0 end -- Settings: badges off
	return n
end})
table.Merge(A.camera, {btn = 2, app = G.APP_CAMERA, label = "Camera", icon = Ico("camera"), col = Color(150, 150, 156)})
table.Merge(A.photos, {btn = 3, app = G.APP_GALLERY, label = "Photos", icon = Ico("gallery"), col = Color(250, 250, 250)})
table.Merge(A.settings, {btn = 5, app = G.APP_SETTINGS, label = "Settings", icon = AppIco(G.APP_SETTINGS), col = Color(142, 142, 147)})
if G.APP_MUSIC then table.Merge(A.zmusic, {btn = 6, app = G.APP_MUSIC, label = "ZMusic", icon = AppIco(G.APP_MUSIC), col = Color(250, 45, 72)}) else A.zmusic = nil end
-- order of apps that are not in a saved layout yet (new apps go to the end of the grid)
local ORDER = {"settings", "zmusic", "clock", "phone", "chat", "camera", "photos"}
local DEF = "settings,zmusic,clock|phone,chat,camera,photos"

--[[ layout: {grid = {ids}, dock = {ids}} ]]
local cache, cacheN = {}, 0
local function Parse(str)
	str = (str and str ~= "") and str or DEF
	local na = table.Count(A)
	if na ~= cacheN then cache, cacheN = {}, na end -- an app registered later (Clock)
	local c = cache[str]
	if c then return c end
	local g, d, seen = {}, {}, {}
	local gs, ds = string.match(str, "^([%w,]*)|([%w,]*)$")
	if not gs then gs, ds = string.match(DEF, "^([%w,]*)|([%w,]*)$") end
	for id in string.gmatch(ds, "%w+") do if A[id] and not seen[id] and #d < 4 then d[#d + 1] = id seen[id] = true end end
	for id in string.gmatch(gs, "%w+") do if A[id] and not seen[id] and #g < COLS * ROWS then g[#g + 1] = id seen[id] = true end end
	for _, id in ipairs(ORDER) do if A[id] and not seen[id] and #g < COLS * ROWS then g[#g + 1] = id seen[id] = true end end
	for id in pairs(A) do if not seen[id] and #g < COLS * ROWS then g[#g + 1] = id seen[id] = true end end
	c = {grid = g, dock = d}
	if table.Count(cache) > 32 then cache = {} end
	cache[str] = c
	return c
end
local function Ser(lay) return table.concat(lay.grid, ",") .. "|" .. table.concat(lay.dock, ",") end
local function Layout(wep, st)
	local nw = wep:GetNW2String("HomeLay", "")
	local p = st.own and L.homeLay55
	if p and p.wep == wep and (RealTime() - p.at < 3 and p.s ~= nw) then return Parse(p.s) end
	return Parse(nw)
end
SCR.HomeLayout = Layout

-- the arrangement while an icon is dragged: it is taken out, a gap where it would land
local function Copy(t, skip)
	local o = {}
	for _, v in ipairs(t) do if v ~= skip then o[#o + 1] = v end end
	return o
end
local function Arrange(lay, d)
	local g, k = Copy(lay.grid, d.id), Copy(lay.dock, d.id)
	if d.to == "dock" then table.insert(k, math.Clamp(d.idx, 1, #k + 1), GAPID)
	elseif d.to == "grid" then table.insert(g, math.Clamp(d.idx, 1, #g + 1), GAPID) end
	return g, k
end
-- where the finger would drop the icon
local function DropAt(lay, d, fx, fy)
	local inDock = false
	for _, v in ipairs(lay.dock) do if v == d.id then inDock = true end end
	local dockN = #lay.dock - (inDock and 1 or 0)
	if fy > DOCK_Y - 6 and dockN < 4 then
		local n = dockN + 1
		local best, bd = 1, math.huge
		for i = 1, n do
			local x = DockXY(i, n)
			local dd = math.abs(fx - (x + SIZE / 2))
			if dd < bd then best, bd = i, dd end
		end
		return "dock", best
	end
	local n = #lay.grid - (inDock and 0 or 1)
	local c = math.Clamp(math.floor((fx - 14 - GAP / 2) / (SIZE + GAP)), 0, COLS - 1)
	local r = math.Clamp(math.floor((fy - TOP + (PITCH - SIZE) / 2) / PITCH), 0, ROWS - 1)
	return "grid", math.Clamp(r * COLS + c + 1, 1, math.min(n + 1, COLS * ROWS))
end
local function Commit(wep, lay, d)
	local g, k = Copy(lay.grid, d.id), Copy(lay.dock, d.id)
	if d.to == "dock" and #k < 4 then table.insert(k, math.Clamp(d.idx, 1, #k + 1), d.id)
	else table.insert(g, math.Clamp(d.idx or #g + 1, 1, #g + 1), d.id) end
	local s = Ser({grid = g, dock = k})
	L.homeLay55 = {s = s, at = RealTime(), wep = wep}
	U.Act("home", s)
end

--[[ drawing ]]
local function Wobble(id, t)
	local ph = (util.CRC(id) % 628) / 100
	return math.sin(t * 24 + ph) * 1.7, math.cos(t * 19 + ph) * 0.8
end
local function DrawIcon(wep, st, e, x, y, s, ang, hi, alpha)
	local mat = e.icon and e.icon()
	local cx, cy = x + s / 2, y + s / 2
	alpha = alpha or 1
	if e.draw then e.draw(wep, st, x, y, s, ang, alpha)
	elseif mat and not mat:IsError() then
		surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255 * alpha)
		if ang ~= 0 then surface.DrawTexturedRectRotated(cx, cy, s, s, ang) else surface.DrawTexturedRect(x, y, s, s) end
	else
		U.Round(s * 0.23, x, y, s, s, Color(e.col.r, e.col.g, e.col.b, 255 * alpha))
	end
	if hi and hi > 0 then
		if mat and not mat:IsError() and not e.draw then
			surface.SetDrawColor(0, 0, 0, 92 * hi * alpha)
			if ang ~= 0 then surface.DrawTexturedRectRotated(cx, cy, s, s, ang) else surface.DrawTexturedRect(x, y, s, s) end
		else
			U.Round(s * 0.23, x, y, s, s, Color(0, 0, 0, 92 * hi * alpha))
		end
	end
end
local function Badge(n, x, y, s)
	if not n or n <= 0 then return end
	local txt = n > 99 and "99+" or tostring(n)
	surface.SetFont("STTS_I_Cap")
	local bw = math.max(34, surface.GetTextSize(txt) + 18)
	U.Round(17, x + s - bw / 2 - 4, y - 10, bw, 34, C.red)
	U.T(txt, "STTS_I_Cap", x + s - 4, y + 7, Color(255, 255, 255))
end

-- fix61: the labels sit on a wallpaper now: always white with a soft shadow (iOS)
local LBL, LBL_SH = Color(255, 255, 255), Color(0, 0, 0, 110)
local function Label(text, x, y)
	U.T(text, "STTS_I_Cap", x, y + 1.5, LBL_SH)
	U.T(text, "STTS_I_Cap", x, y, LBL)
end
local DOCK_GLASS = Color(255, 255, 255, 44)
local function Wall(wep)
	if wep.STTS_HomeNoWall then return end -- the app zoom draws it itself (it does not scale)
	if SCR.DrawHomeWall then SCR.DrawHomeWall(wep, 0, 0, W, H) else U.R(0, 0, W, H, C.home) end
end
local function Home55(wep, st, btns)
	Wall(wep)
	local own = st.own and L.wep == wep
	local lay = Layout(wep, st)
	local jig = own and L.jig55 and L.jig55.wep == wep and L.app == G.APP_HOME
	if own and not jig then L.jig55, L.hdrag55 = nil, nil end
	local d = jig and L.hdrag55 or nil
	local grid, dock = lay.grid, lay.dock
	if d then grid, dock = Arrange(lay, d) end
	local now = RealTime()
	local dt = wep.STTS_UIdt or 0
	local P = wep.STTS_HomeP or {}
	wep.STTS_HomeP = P
	wep.STTS_IconRect = wep.STTS_IconRect or {}
	local hit = {}
	local lifted = wep.STTS_HideIcon
	local k = 1 - math.exp(-dt * 13)
	-- iOS: a dock of frosted glass
	U.Round(38, 12, DOCK_Y + 4, W - 24, DOCK_H - 8, DOCK_GLASS)
	local function Place(id, tx, ty, inDock)
		local e = A[id]
		if not e then return end
		local p = P[id]
		if not p or not own then p = {x = tx, y = ty} P[id] = p
		else p.x, p.y = Lerp(k, p.x, tx), Lerp(k, p.y, ty) end
		if math.abs(p.x - tx) < 0.3 and math.abs(p.y - ty) < 0.3 then p.x, p.y = tx, ty end
		wep.STTS_IconRect[e.app] = {x = tx, y = ty, w = SIZE, h = SIZE}
		hit[#hit + 1] = {id = id, x = tx, y = ty, dock = inDock}
		if d and d.id == id then return end
		if not jig then
			U.Reg(btns, e.btn, tx, ty, SIZE, SIZE, function()
				if not st.own then return end
				wep.STTS_OpenFrom = nil
				if e.open then e.open(wep, st) else U.SetApp(st, e.app) end
			end)
		end
		if lifted == e.app then return end -- the app window (transition) draws it
		local ang, bob = 0, 0
		if jig then ang, bob = Wobble(id, now) end
		local hi = (not jig) and U.IconHi and U.IconHi(wep, st, e.btn) or 0
		DrawIcon(wep, st, e, p.x, p.y + bob, SIZE, ang, hi)
		if e.badge then Badge(e.badge(wep, st), p.x, p.y + bob, SIZE) end
		if not inDock then Label(U.Fit(e.label, "STTS_I_Cap", SIZE + GAP + 4), p.x + SIZE / 2, p.y + SIZE + 16) end
	end
	for i, id in ipairs(grid) do if id ~= GAPID then local x, y = GridXY(i) Place(id, x, y, false) end end
	local nd = #dock
	for i, id in ipairs(dock) do if id ~= GAPID then local x, y = DockXY(i, nd) Place(id, x, y, true) end end
	if own then wep.STTS_HomeHit = hit end
	if jig then
		-- Done (top right, a glass pill)
		local bx, by, bw, bh = W - 22 - 100, 60, 100, 44
		U.Reg(btns, DONE, bx, by, bw, bh, function() L.jig55, L.hdrag55 = nil, nil end)
		local hk = U.HoverK(wep, DONE, st.sel == DONE)
		U.Round(22, bx, by, bw, bh, Color(120, 120, 128, 110 + 50 * hk))
		U.T("Done", "STTS_I_BodyB", bx + bw / 2, by + bh / 2, Color(255, 255, 255))
	end
	-- the lifted icon under the finger (bigger, a soft shadow)
	if d and A[d.id] then
		local e = A[d.id]
		local ls = U.SpringK and U.SpringK(wep, "hlift", true, 0.3, 0.7) or 1
		local s = SIZE * (1 + 0.14 * ls)
		local cx, cy = d.fx - d.ox + SIZE / 2, d.fy - d.oy + SIZE / 2
		local x, y = cx - s / 2, cy - s / 2
		P[d.id] = {x = d.fx - d.ox, y = d.fy - d.oy}
		U.Round(s * 0.25, x + 2, y + 8, s - 4, s - 4, Color(0, 0, 0, 70))
		DrawIcon(wep, st, e, x, y, s, 0, 0, 0.95)
		if e.badge then Badge(e.badge(wep, st), x, y, s) end
	end
end

--[[ fix61: a small home screen (Settings > Wallpaper): the dock + the icons of this
     phone, scaled (sc = preview width / display width), no labels ]]
function SCR.HomeMini(wep, x, y, sc, big)
	local st = SCR.State and SCR.State(wep) or {}
	local lay = Layout(wep, st)
	local s = SIZE * sc
	U.Round(38 * sc, x + 12 * sc, y + (DOCK_Y + 4) * sc, (W - 24) * sc, (DOCK_H - 8) * sc, DOCK_GLASS)
	for i, id in ipairs(lay.grid) do
		local e = A[id]
		if e then
			local gx, gy = GridXY(i)
			DrawIcon(wep, st, e, x + gx * sc, y + gy * sc, s, 0, 0)
		end
	end
	local nd = #lay.dock
	for i, id in ipairs(lay.dock) do
		local e = A[id]
		if e then
			local dx, dy = DockXY(i, nd)
			DrawIcon(wep, st, e, x + dx * sc, y + dy * sc, s, 0, 0)
		end
	end
end

--[[ touch: hold = jiggle mode, drag = move ]]
local function IconAt(wep, fx, fy)
	for _, h in ipairs(wep.STTS_HomeHit or {}) do
		if fx >= h.x - 4 and fx <= h.x + SIZE + 4 and fy >= h.y - 4 and fy <= h.y + SIZE + 4 then return h end
	end
end
local function Pick(wep, t, h, fx, fy)
	local lay = Layout(wep, SCR.State(wep))
	local d = {id = h.id, ox = fx - h.x, oy = fy - h.y, fx = fx, fy = fy}
	d.to, d.idx = DropAt(lay, d, fx, fy)
	L.hdrag55 = d
	t.home55drag = true
	t.moved = true
	L.sel = 0
	wep.STTS_SK = wep.STTS_SK or {}
	wep.STTS_SK.hlift = {x = 0, v = 0} -- lifts from the normal size
end
local HOOK = {name = "home55"}
function HOOK.Begin(wep, t, fx, fy)
	if L.app ~= G.APP_HOME or wep.STTS_Anim or (L.shade or 0) > 0.02 then return end
	if SCR.AlarmShown and SCR.AlarmShown(wep) then return end -- a ringing alarm covers the icons
	local h = IconAt(wep, fx, fy)
	t.home55 = {at = RealTime(), h = h}
end
function HOOK.Move(wep, t, fx, fy, dx, dy, dmin)
	local hm = t.home55
	if not hm then return end
	if t.home55drag then
		local d = L.hdrag55
		if not d or L.app ~= G.APP_HOME then t.home55drag = nil return true end
		d.fx, d.fy = fx, fy
		local lay = Layout(wep, SCR.State(wep))
		d.to, d.idx = DropAt(lay, d, fx, fy)
		L.sel = 0
		return true
	end
	local far = dx * dx + dy * dy > dmin * dmin
	local jig = L.jig55 and L.jig55.wep == wep
	if jig then
		if hm.h and far and not t.shadeDrag then Pick(wep, t, hm.h, t.x0 + 0, t.y0 + 0) HOOK.Move(wep, t, fx, fy, dx, dy, dmin) return true end
		return hm.h ~= nil
	end
	if far then t.home55 = nil return end -- a swipe, not a hold
	if RealTime() - hm.at >= HOLD then
		L.jig55 = {wep = wep, at = RealTime()}
		if hm.h then Pick(wep, t, hm.h, fx, fy) else t.home55jig = true end
		return true
	end
end
function HOOK.End(w, t, cancel)
	local hm = t.home55
	if not hm then return end
	if t.home55drag then
		local d = L.hdrag55
		L.hdrag55 = nil
		if d and not cancel and IsValid(w) then Commit(w, Layout(w, SCR.State(w)), d) end
		return true
	end
	if t.home55jig then return true end -- the hold that started the jiggle on the empty screen
	if L.jig55 and L.jig55.wep == w then
		if t.sel == DONE then return false end
		if not hm.h and not t.moved and not cancel then L.jig55 = nil end -- tap the empty screen = finished
		return true
	end
end
SCR.TouchHooks = SCR.TouchHooks or {}
do
	local found
	for i, h in ipairs(SCR.TouchHooks) do if h.name == HOOK.name then SCR.TouchHooks[i] = HOOK found = true end end
	if not found then table.insert(SCR.TouchHooks, HOOK) end
end

-- leaving the home screen / putting the phone down ends the jiggle
hook.Add("Think", "STTS_PhoneHome55", function()
	if L.jig55 and (L.app ~= G.APP_HOME or not L.raised or L.wep ~= L.jig55.wep) then L.jig55, L.hdrag55 = nil, nil end
	local APPS = SCR.APPS
	if APPS and APPS[G.APP_HOME] ~= Home55 then
		APPS[G.APP_HOME] = Home55
		SCR.STTS_HomeWrap = Home55 -- cl_phone_settings.lua does not wrap it again
	end
end)
SCR.APPS[G.APP_HOME] = Home55
SCR.STTS_HomeWrap = Home55
SCR.Home55 = Home55

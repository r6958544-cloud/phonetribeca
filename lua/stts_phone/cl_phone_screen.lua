--[[---------------------------------------------------------------------------
	ZHUNTER phone - everything that is shown on the DISPLAY OF THE MODEL.
	No popup window: every phone (in your hand, in someone else's hand, on
	the floor) gets a render target that is put on the "*_screen" (fix28: per model)
	material of its model (SetSubMaterial). The UI is drawn into that RT.

	input (your own phone, raised with LMB):
	  no cursor any more: the mouse moves an invisible point over the display
	  (UI pixels), the index finger of the right hand follows it with a bit of
	  spring inertia (weapon_stts_phone.lua, FingerStep), buttons light up
	  under the FINGER and LMB taps with it. LMB held = the finger stays on
	  the glass and slides: lists scroll, photos swipe, the zoom slider moves.
	  fix17: the mouse wheel does nothing, scrolling is ONLY the finger: smooth
	  (pixel exact), with a fling after letting go and a rubber band at the ends.
	  pull down from the top edge = the shade (torch, airplane mode), see
	  cl_shooting_phone_shade.lua. R puts the phone fully down (idle pose, also in a call),
	  RMB toggles free look (finger freezes, the mouse turns the camera;
	  RMB again = back to the finger).
	TeleChat: text messages between phones (sv_shooting_phone_chat.lua).
	look: iOS (dark mode) with iOS-like transitions, see the "UI" block.

	sync: only STATE travels (NW2 vars on the weapon: app, hovered item,
	scroll, gallery index, call, camera). each client draws locally.
	camera images: render.RenderView from the camera attachment of the phone,
	pose of remote phones comes from the server (stts_phone_feed).
---------------------------------------------------------------------------]]
STTS = STTS or {}
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
STTS.PhoneScreen = SCR
local CLASS = "weapon_stts_phone"
local W, H = G.RTW, G.RTH

local WHITE, BLACK = Color(255, 255, 255), Color(0, 0, 0)
local TEXT, MUTED, SOFT, LINE = Color(236, 236, 236), Color(140, 140, 140), Color(255, 255, 255, 90), Color(255, 255, 255, 30)
-- extended = true: Cyrillic names / messages render (without it GMod draws only Latin)
surface.CreateFont("STTS_TC_Entry", {font = "Bahnschrift", size = 20, weight = 500, antialias = true, extended = true})
surface.CreateFont("STTS_PS_Hint", {font = "Veteran Typewriter", size = 17, weight = 500, antialias = true, extended = true})

--[[ v19.2: many GMod setups blend translucent colours in LINEAR light (sRGB write): white
     at 19 % over black comes out as a ~47 % grey, so the Control Centre glass, hover tints
     and secondary text looked flat and washed out in game. LINS.on (probed once, see
     SCR.LinBlend in cl_shooting_phone_settings.lua, convar stts_phone_gamma_fix) = every
     translucent colour gets the alpha that gives the designed look over the background it
     usually sits on (LINS.bg: 0 = black .. 1 = white, set by the theme / the shade) ]]
local LINS = {on = false, bg = 0.05, tmp = Color(0, 0, 0)}
SCR.LinState = LINS
local function LinCol(c)
	if not (LINS.on and c) or c == LINS.tmp then return c end
	local a = c.a or 255
	if a >= 255 or a <= 0 then return c end
	a = a / 255
	local f = (c.r + c.g + c.b) / 765
	local b = LINS.bg
	if f <= 0.3 then b = math.max(b, 0.75) end -- dark ink / shadows darken something brighter
	local fl, bl = f ^ 2.2, b ^ 2.2
	local d = fl - bl
	if d > -0.04 and d < 0.04 then return c end -- (almost) the colour of the background anyway
	local t = LINS.tmp
	t.r, t.g, t.b = c.r, c.g, c.b
	t.a = math.Clamp(((b + (f - b) * a) ^ 2.2 - bl) / d, 0, 1) * 255
	return t
end
local function R(x, y, w, h, c) surface.SetDrawColor(LinCol(c)) surface.DrawRect(x, y, w, h) end
local function O(x, y, w, h, c, t) surface.SetDrawColor(LinCol(c)) surface.DrawOutlinedRect(x, y, w, h, t or 2) end
local function T(s, f, x, y, c, ax, ay) draw.SimpleText(s, f, x, y, LinCol(c), ax or TEXT_ALIGN_CENTER, ay or TEXT_ALIGN_CENTER) end
-- fix15: the black & white UI (!!stts_monochrome.lua) greys everything out; answer (green),
-- decline / hang up and recording (red) keep their real colours
local function Colored(fn, ...)
	if STTS_MonoColored then STTS_MonoColored(fn, ...) else fn(...) end
end
--[[ fix10: safe UTF-8 (the GMod utf8 module throws "initial position is a
     continuation byte" on a broken / cut string and killed the whole screen).
     U8Starts = byte positions where every character starts, never errors;
     a broken byte simply counts as one character. ]]
local function U8Starts(s)
	local t, i, n = {}, 1, #s
	while i <= n do
		t[#t + 1] = i
		local c = string.byte(s, i)
		local l = 1
		if c >= 0xF0 and c <= 0xF4 then l = 4 elseif c >= 0xE0 and c < 0xF0 then l = 3 elseif c >= 0xC2 then l = 2 end
		if l > 1 then -- the next bytes must really be continuation bytes
			for k = 1, l - 1 do
				local b = string.byte(s, i + k)
				if not b or b < 0x80 or b > 0xBF then l = 1 break end
			end
		end
		i = i + l
	end
	return t
end
-- characters a..b (1-based, inclusive) of s, starts = U8Starts(s)
local function U8Sub(s, starts, a, b)
	a = math.max(a, 1)
	if b < a then return "" end
	local from = starts[a] or (#s + 1)
	local to = (starts[b + 1] or (#s + 1)) - 1
	return string.sub(s, from, to)
end
-- every character of s as a list (for wrapping)
local function U8Chars(s)
	local st, out = U8Starts(s), {}
	for k = 1, #st do out[k] = string.sub(s, st[k], (st[k + 1] or (#s + 1)) - 1) end
	return out
end
SCR.U8Starts, SCR.U8Sub, SCR.U8Chars = U8Starts, U8Sub, U8Chars

local function Fit(text, font, width)
	text = tostring(text or "")
	surface.SetFont(font)
	if surface.GetTextSize(text) <= width then return text end
	local st = U8Starts(text)
	local n = #st
	while n > 0 and surface.GetTextSize(U8Sub(text, st, 1, n) .. "…") > width do n = n - 1 end
	return U8Sub(text, st, 1, n) .. "…"
end

--[[---------------------------------------------------------------------------
	your own phone: predicted local state
---------------------------------------------------------------------------]]
local L = {app = G.APP_HOME, sel = 0, scroll = 0, gal = 1, galV = 1, album = 0, raised = false, cx = 0, cy = 0, sent = "", sentAt = 0,
	look = false, draft = "", peer = nil, down = false, zoom = 1, camMode = 0}
local APP_LAST = G.APP_LAST or G.APP_SEND
SCR.L = L
SCR.WifiMat = Material("stts/cc_wifi.png", "smooth mips")
-- Control Centre tiles (cosmetic, kept on the phone): key = {NW2 bool, true = the NW2 bool means OFF}
-- v19.2: Bluetooth / Cellular are gone; join = the phone is connected to the Wi-Fi of the map
SCR.CCNW = {wifi = {"NoWifi", true}, join = {"NoJoin", true}, rotlock = {"RotLock"}, focus = {"Focus"}}

local function MyPhone()
	local lp = LocalPlayer()
	if not IsValid(lp) or not lp:Alive() then return end
	local w = lp:GetActiveWeapon()
	if IsValid(w) and w:GetClass() == CLASS then return w end
end

local TCAsk, StopRec
local function Adopt(wep)
	-- fix15: picking the recording phone up again does not stop its recording
	if StopRec and not (L.rec and L.rec.wep == wep) then StopRec() end
	L.wep = wep
	L.app = math.Clamp(wep:GetNW2Int("App", G.APP_HOME), G.APP_HOME, APP_LAST)
	-- the open conversation is not synced (nor its attach sheet)
	if L.app == G.APP_THREAD or L.app == G.APP_SEND then L.app = G.APP_CHATS end
	if G.APP_ALARMED and L.app == G.APP_ALARMED then L.app = G.APP_CLOCK end -- fix55: the alarm editor is local too
	L.down = wep:GetNW2Bool("Down", false)
	L.zoom, L.zoomT = math.Clamp(wep:GetNW2Float("Zoom", 1), 1, G.ZoomMax), nil
	L.camMode, L.touch, L.backTo = wep:GetNW2Int("CamMode", 0) == 2 and 1 or 0, nil, nil
	L.homeDrag = nil
	L.sel, L.scroll, L.gal = 0, wep:GetNW2Int("Scroll", 0) / 4, math.max(1, wep:GetNW2Int("Gal", 1))
	L.scrollV, L.shade, L.shadeV, L.shadeT = 0, 0, 0, 0 -- fix17: smooth scroll (rows), shade
	L.land, L.landAt = nil, nil -- v19.4: the landscape of this phone comes from it (NW2)
	local gv = wep:GetNW2Int("GalV", 4)
	L.galV, L.album = math.Clamp(math.floor(gv / 4), 1, 4), gv % 4
	L.raised, L.vidAt, L.camAt = false, nil, nil
	L.look, L.peer = false, nil
	if TCAsk then TCAsk(true) end
end

local function Act(act, arg)
	net.Start("stts_phone_ui") net.WriteString(act) net.WriteString(arg or "") net.SendToServer()
end

function SCR.LocalRaised(wep) return L.wep == wep and L.raised end
-- v19.4: landscape (T), predicted for a moment until the server has it
function SCR.LocalLand(wep)
	if L.wep ~= wep then return end
	if L.landAt and RealTime() - L.landAt < 0.8 then return L.land end
	return wep:GetNW2Bool("Land", false)
end
-- how far a phone is turned to landscape right now (0..1, eased; weapon_stts_phone.lua)
function SCR.LandK(wep)
	return IsValid(wep) and wep.LandK and wep:LandK() or 0
end
function SCR.LocalDown(wep) if L.wep == wep then return L.down end end

local TouchEnd
--[[ fix72: the controls (stts_phone_controls)
     0 (default) = LMB takes the phone in both hands in front of you, the camera stays free
       (filming, looking around); RMB = the finger comes / goes, while it is there the mouse
       moves it and the camera stands still; LMB = tap; R = down
     1 = fix70 and older: LMB raises with the finger at once, RMB = free look
     2 = fix71 (community fix): RMB raises / lowers, the mouse always moves the finger ]]
SCR.ctlCvar72 = CreateClientConVar("stts_phone_controls", "0", true, false, "phone controls: 0 = LMB raise (camera free), RMB finger on / off; 1 = LMB raise with the finger, RMB free look (old); 2 = RMB raise / lower (fix71)", 0, 2)
function SCR.Controls72() return SCR.ctlCvar72:GetInt() end
-- down = R: the phone goes fully down (idle pose) even during a call
function SCR.SetRaised(wep, up, silent, down)
	if L.wep ~= wep then Adopt(wep) end
	if not up then L.down = (down and true) or false end
	if L.raised == up then return end
	L.raised = up
	L.look = (up and SCR.Controls72() == 0) or false -- fix72: raised = held in front of you, the finger comes with RMB
	if up then L.ux, L.uy, L.down, L.raiseAt = W * 0.5, H * 0.62, false, RealTime() end
	if not up then
		if IsValid(L.entry) then L.entry:Remove() end
		if TouchEnd then TouchEnd(wep, true) end
		if StopRec then StopRec() end
	end
	L.sel = 0
	if not silent then Act(up and "open" or "close", up and (L.look and "look" or "") or (down and "down" or "")) end
end

local function Click() end -- fix11: no tap sounds

--[[---------------------------------------------------------------------------
	state of any phone (own = predicted, others = NW2)
---------------------------------------------------------------------------]]
local photoCache, setCache = {}, {}
local function ParsePhotos(str)
	if photoCache[str] then return photoCache[str] end
	local t = {}
	for id in string.gmatch(str, "%d+") do t[#t + 1] = tonumber(id) end
	photoCache[str] = t
	return t
end
local function ParseSet(str)
	if setCache[str] then return setCache[str] end
	local t = {}
	for id in string.gmatch(str, "%d+") do t[tonumber(id)] = true end
	setCache[str] = t
	return t
end

-- fix54: the gallery lists come in parts (sv_phone_media.lua, SetList)
function SCR.NWList(wep, key)
	local s = wep:GetNW2String(key, "")
	local n = wep:GetNW2Int(key .. "#n", 1)
	if n <= 1 then return s end
	local t = {s}
	for i = 2, math.min(n, 16) do t[i] = wep:GetNW2String(key .. "#" .. i, "") end
	return table.concat(t, ",")
end

local function State(wep)
	local st = wep.STTS_St or {}
	wep.STTS_St = st
	local own = L.wep == wep and wep:GetOwner() == LocalPlayer()
	st.own = own
	st.app = own and L.app or wep:GetNW2Int("App", G.APP_HOME)
	st.sel = own and L.sel or wep:GetNW2Int("Sel", 0)
	-- fix17: scroll is fractional (smooth). others get it in 1/4 rows and smooth it out
	if own then
		st.scroll = L.scroll
	else
		local want = wep:GetNW2Int("Scroll", 0) / 4
		local now = RealTime()
		local dt = math.Clamp(now - (wep.STTS_ScrT or now), 0, 0.2)
		wep.STTS_ScrT = now
		local s = wep.STTS_ScrS
		if not s or math.abs(want - s) > 6 then s = want else s = Lerp(1 - math.exp(-dt * 14), s, want) end
		wep.STTS_ScrS = s
		st.scroll = s
	end
	st.gal = own and L.gal or wep:GetNW2Int("Gal", 1)
	local gv = wep:GetNW2Int("GalV", 4)
	st.galV = own and L.galV or math.Clamp(math.floor(gv / 4), 1, 4)
	st.album = own and L.album or gv % 4
	st.call = wep:GetNW2Int("CallSt", 0)
	st.callName = wep:GetNW2String("CallName", "")
	st.since = wep:GetNW2Float("CallSince", 0)
	st.vid = wep:GetNW2Bool("VidOn", false)
	if own and L.vidAt and RealTime() - L.vidAt < 0.8 then st.vid = L.vid end
	st.front = wep:GetNW2Bool("CamFront", false)
	if own and L.camAt and RealTime() - L.camAt < 0.8 then st.front = L.front end
	st.peerIdx = wep:GetNW2Int("PeerIdx", 0)
	st.peerVid = wep:GetNW2Bool("PeerVid", false)
	st.peerBack = wep:GetNW2Bool("PeerBack", true)
	st.photos = ParsePhotos(SCR.NWList(wep, "Photos"))
	st.recv = ParsePhotos(SCR.NWList(wep, "PhotosR"))
	st.vids = ParseSet(SCR.NWList(wep, "PhotosV"))
	st.blobs = ParseSet(SCR.NWList(wep, "PhotosB"))
	st.peerPocket = wep:GetNW2Bool("PeerPocket", false)
	st.zoom = own and L.zoom or wep:GetNW2Float("Zoom", 1)
	-- 0 photo, 1 video, 2 recording. fix15: a recording keeps running when the phone changes hands
	if own then
		st.camMode = (L.rec and L.rec.wep == wep and not L.rec.closed) and 2 or (SCR.RemoteRec and SCR.RemoteRec(wep) and 2) or L.camMode
	else
		st.camMode = wep:GetNW2Int("CamMode", 0)
	end
	st.num = wep:GetNWString("STTS_Num", "")
	if STTS.PhoneGallery33 then STTS.PhoneGallery33.Merge(st,wep) end
	if SCR.M49 then SCR.M49.Merge(st, wep) end -- fix53: photos still uploading, album Received = tap to download
	st.unread = wep:GetNW2Int("TCUnread", 0)
	-- fix17: torch / airplane mode (shade) and the camera flash, predicted for your own phone
	st.torch = wep:GetNW2Bool("Torch", false)
	if own and L.torchAt and RealTime() - L.torchAt < 0.8 then st.torch = L.torch end
	st.plane = wep:GetNW2Bool("Plane", false)
	if own and L.planeAt and RealTime() - L.planeAt < 0.8 then st.plane = L.plane end
	-- Control Centre connectivity tiles (predicted on your own phone)
	st.cc = st.cc or {}
	for key, nw in pairs(SCR.CCNW or {}) do
		st.cc[key] = wep:GetNW2Bool(nw[1], false) ~= (nw[2] == true) -- true = switched on
		if own and L.ccAt and L.ccAt[key] and RealTime() - L.ccAt[key] < 0.8 then st.cc[key] = L.ccOn and L.ccOn[key] end
	end
	st.camFlash = wep:GetNW2Bool("CamFl", false)
	if own and L.camFlAt and RealTime() - L.camFlAt < 0.8 then st.camFlash = L.camFl end
	local fa = wep:GetNW2Float("FlashAt", -100)
	st.flash = CurTime() - fa < 3 and wep:GetNW2String("Flash", "") or nil
	if st.call ~= G.CALL_NONE then st.app = G.APP_CALL elseif st.app == G.APP_CALL then st.app = G.APP_HOME end
	st.gal = math.Clamp(st.gal, 1, math.max(1, #st.photos))
	return st
end
SCR.State = State

--[[---------------------------------------------------------------------------
	contacts (same list for everybody, sent by the server)
---------------------------------------------------------------------------]]
STTS.PhoneBook = STTS.PhoneBook or {{num = "911", name = "Emergency 911"}}
net.Receive("stts_phone_book", function()
	local book = {{num = "911", name = "Emergency 911"}}
	for _ = 1, net.ReadUInt(8) do
		book[#book + 1] = {num = net.ReadString(), name = net.ReadString(), avatar = net.ReadString()}
	end
	STTS.PhoneBook = book
end)
local function Contacts(st, no911)
	local out = {}
	for _, c in ipairs(STTS.PhoneBook) do
		if c.num ~= st.num and not (no911 and c.num == "911") then out[#out + 1] = c end
	end
	return out
end

--[[---------------------------------------------------------------------------
	photos: local cache in data/stts_phone/r<round>/p<id>.jpg
---------------------------------------------------------------------------]]
local ROOT = "stts_phone"
local function RoundDir() return ROOT .. "/r" .. GetGlobalInt("STTS_PhotoRound", 1) end
local function PhotoPath(id) return RoundDir() .. "/p" .. id .. ".jpg" end
local mats, dl, asked = {}, {}, {}
local VIDS = {} -- [video id] = {pages = {page photo ids}, frames, fps}

local function Wipe()
 if STTS.PhoneRecorder31 then STTS.PhoneRecorder31.Cancel() end
 if STTS.PhoneGallery33 then STTS.PhoneGallery33.Reset()end
	local files, dirs = file.Find(ROOT .. "/*", "DATA")
	for _, f in ipairs(files or {}) do file.Delete(ROOT .. "/" .. f) end
	for _, d in ipairs(dirs or {}) do
		for _, f in ipairs(file.Find(ROOT .. "/" .. d .. "/*", "DATA") or {}) do file.Delete(ROOT .. "/" .. d .. "/" .. f) end
		file.Delete(ROOT .. "/" .. d)
	end
	mats, dl, asked = {}, {}, {}
	VIDS = {}
	L.rec = nil -- round ended
	SCR.RecPreview = nil
	if SCR.CancelExport then SCR.CancelExport() end
	if SCR.ResetUploads then SCR.ResetUploads() end
	if SCR.ResetVideoEncoder then SCR.ResetVideoEncoder() end
	if SCR.M49 and SCR.M49.Reset then SCR.M49.Reset() end -- fix53
end
SCR.Wipe = Wipe
net.Receive("stts_phone_wipe", Wipe)
hook.Add("InitPostEntity", "STTS_PhonePhotoWipe", Wipe)
hook.Add("ShutDown", "STTS_PhonePhotoWipe", Wipe)

local function WritePhoto(id, jpg)
	file.CreateDir(RoundDir())
	file.Write(PhotoPath(id), jpg)
	mats[id] = nil
	if SCR.M49 then SCR.M49.have[id] = true end -- fix53: on this PC now
end

local function PhotoMat(id, noAsk)
	if id and id <= -1000000 then return SCR.M49 and SCR.M49.PendMat(id) end -- fix53: a photo still on its way to the server
	if id and id < 0 and STTS.PhoneGallery33 then return STTS.PhoneGallery33.Thumb(id) end
	local key = GetGlobalInt("STTS_PhotoRound", 1) .. ":" .. id
	if mats[id] and mats[id].key == key then return mats[id].mat end
	local path = PhotoPath(id)
	if file.Exists(path, "DATA") then
		local m = Material("../data/" .. path, "smooth noclamp")
		if m and not m:IsError() then mats[id] = {mat = m, key = key} return m end
	end
	if not noAsk and SCR.M49 and SCR.M49.Locked(id) then return end -- fix53: TeleChat media = tap to download
	if not noAsk and (asked[id] or 0) < RealTime() then
		asked[id] = RealTime() + 6
		net.Start("stts_phone_dl") net.WriteUInt(id, 32) net.SendToServer()
	end
end

--[[ v19.4: the size of a saved photo (taken in landscape = 1024 x 576), read once from
     the header of its JPEG (the size of a material made from a file is not reliable) ]]
do
	local function JpegSize(d)
		if not d or #d < 12 or string.byte(d, 1) ~= 0xFF or string.byte(d, 2) ~= 0xD8 then return end
		local i, n = 3, #d
		while i + 8 <= n do
			if string.byte(d, i) ~= 0xFF then return end
			local m = string.byte(d, i + 1)
			if m == 0xFF then i = i + 1
			elseif m == 0x01 or (m >= 0xD0 and m <= 0xD8) then i = i + 2
			else
				if m >= 0xC0 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC then -- start of frame
					return string.byte(d, i + 7) * 256 + string.byte(d, i + 8), string.byte(d, i + 5) * 256 + string.byte(d, i + 6)
				end
				i = i + 2 + string.byte(d, i + 2) * 256 + string.byte(d, i + 3)
			end
		end
	end
	SCR.JpegSize = JpegSize
	function SCR.PhotoSize(id)
		if id and id <= -1000000 and SCR.M49 then -- fix53: pending photo
			local pw, ph = SCR.M49.PendSize(id)
			if pw then return pw, ph end
		end
		local e = id and mats[id]
		if not e then
			-- fix53: not downloaded yet: the tiny preview tells landscape / portrait
			local inf = id and SCR.M49 and SCR.M49.info[id]
			if inf and inf.pw and inf.ph and inf.pw > inf.ph then return G.PhotoH, G.PhotoW end
			return G.PhotoW, G.PhotoH
		end
		if not e.w then
			e.w, e.h = G.PhotoW, G.PhotoH
			local f = file.Open(PhotoPath(id), "rb", "DATA")
			if f then
				local w, h = JpegSize(f:Read(math.min(f:Size(), 16384)))
				f:Close()
				if w and h and w > 0 and h > 0 then e.w, e.h = w, h end
			end
		end
		return e.w, e.h
	end
end

-- video meta (pages + frame count), asked like a photo
local function VideoMeta(id, noAsk)
	local v = VIDS[id]
	if v then return v end
	if not noAsk and SCR.M49 and SCR.M49.Locked(id) then return end -- fix53: tap to download
	if not noAsk and (asked[id] or 0) < RealTime() then
		asked[id] = RealTime() + 6
		net.Start("stts_phone_dl") net.WriteUInt(id, 32) net.SendToServer()
	end
end
net.Receive("stts_phone_vmeta", function()
	local id = net.ReadUInt(32)
	local pages = {}
	for i = 1, net.ReadUInt(9) do pages[i] = net.ReadUInt(32) end -- fix30: 9 page bits / 12 frame bits + preset
	local frames, fps = math.max(1, net.ReadUInt(12)), math.max(1, net.ReadUInt(5))
	VIDS[id] = {pages = pages, frames = frames, fps = fps, res = math.max(1, net.ReadUInt(3))}
	if SCR.M49 then for _, pid in ipairs(pages) do SCR.M49.pageOf[pid] = id end end -- fix53: page -> video (progress)
end)

net.Receive("stts_phone_dlc", function()
	local id, off, total, len = net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(16)
	if len>48000 or total>G.PhotoMaxBytes or total<1 or off+len>total then return end
	local data = net.ReadData(len)
	if SCR.M49 and SCR.M49.Blocked(id) then return end -- fix53: the download was cancelled by a tap
	local job = dl[id]
	if off == 0 or not job then job = {parts = {}, got = 0} dl[id] = job end
	if off~=job.got or not data or #data~=len then return end
	job.parts[#job.parts + 1] = data
	job.got = job.got + len
 job.total44=total
 net.Start("stts_phone_dlg");net.WriteUInt(id,32);net.WriteUInt(off,32);net.SendToServer()
	if job.got >= total then
		dl[id] = nil
		local blob = table.concat(job.parts)
		-- fix53: new photos are a plain jpg, older ones LZMA
		local jpg = string.sub(blob, 1, 2) == "\255\216" and blob or util.Decompress(blob, 4 * 1024 * 1024)
		if jpg and string.sub(jpg, 1, 2) == "\255\216" then
   WritePhoto(id, jpg)
   if SCR.M49 then SCR.M49.Got(id) end
   if STTS.PhoneGallery33 then STTS.PhoneGallery33.DownloadDone44(id,file.Size(PhotoPath(id),"DATA")==#jpg)end
  elseif STTS.PhoneGallery33 then STTS.PhoneGallery33.DownloadDone44(id,false)end
	end
end)

function SCR.MediaDownload44(id)
 if file.Exists(PhotoPath(id),'DATA')then return {ready=true}end
 local j=dl[id];if j then return {got=j.got,total=j.total44}end
end

-- upload: capture is done in PostRender (see below), here only the transfer.
-- one upload at a time (the server keeps one in flight per player): photos and video pages queue up
local uploads, upQ, upBusy = {}, {}, nil
-- fix53: up to 4 chunks (64 KB) wait for their ack at once, the next one leaves the moment
-- an ack comes back (was: one chunk, its ack, a 50 ms pause = ~1.5 s for every photo)
local function UploadSendPart(token,job)
 if uploads[token]~=job then return end
 while (job.nextPart or 1)<=job.total and (job.nextPart or 1)-(job.acked or 0)<=4 do
  local i=job.nextPart or 1
  local part=string.sub(job.comp,(i-1)*G.PhotoChunk+1,i*G.PhotoChunk)
  if #part==0 then return end
  net.Start(job.sharing and "stts_phone_sharepage" or "stts_phone_up")
  net.WriteBool(job.page==true);net.WriteUInt(token,16);net.WriteUInt(i,8);net.WriteUInt(job.total,8);net.WriteUInt(#part,16);net.WriteData(part,#part)
  net.WriteUInt(job.widx or 0,16);net.WriteString(job.wnum or "") -- fix54: the phone it was taken with
  net.SendToServer()
  job.nextPart=i+1
 end
end
local function UploadNext()
 if upBusy and uploads[upBusy]and RealTime()-uploads[upBusy].at<45 then return end
 if upBusy and uploads[upBusy]then
  local expired=uploads[upBusy];uploads[upBusy]=nil
  if expired.tmp then file.Delete(expired.tmp)end
  if expired.cb then expired.cb(0)end
  if expired.pend and SCR.M49 then SCR.M49.UpDone(expired.pend,0);L.toast,L.toastAt="Can't save photo",RealTime()end
 end
 upBusy=nil;local job=table.remove(upQ,1);if not job then return end
 local token=math.random(1,65535);while uploads[token]do token=math.random(1,65535)end
 job.at=RealTime();job.nextPart=1;job.acked=0;job.total=math.ceil(#job.comp/G.PhotoChunk);uploads[token]=job;upBusy=token;UploadSendPart(token,job)
end
net.Receive("stts_phone_upflow",function()
 local token,index=net.ReadUInt(16),net.ReadUInt(8);local job=uploads[token]
 if not job or index<=(job.acked or 0) or index>=(job.nextPart or 1) then return end
 job.at=RealTime();job.acked=index
 UploadSendPart(token,job)
end)
timer.Create("STTS_PhoneUploadQ", 0.1, 0, UploadNext)
SCR.ResetUploads = function() uploads, upQ, upBusy = {}, {}, nil end

net.Receive("stts_phone_upok", function()
	local token, id = net.ReadUInt(16), net.ReadUInt(32)
	local up = uploads[token]
	uploads[token] = nil
	if upBusy == token then upBusy = nil end
	timer.Simple(0, UploadNext)
	if not up then return end
	if up.tmp and not up.pend then file.Delete(up.tmp) end -- fix53: a pending photo keeps its file until the gallery has it
	if id > 0 then WritePhoto(id, up.jpg) end
	if up.pend and SCR.M49 then SCR.M49.UpDone(up.pend, id) end
	if up.cb then up.cb(id) return end
	-- fix53: the photo is in the gallery since the shot (pending entry), L.gal already points at it
	if id <= 0 then L.toast, L.toastAt = "Can't save photo", RealTime() end
end)

-- page = a page of a video (cb(id) gets its id, 0 = rejected)
local function Upload(wep, jpg, page, cb, compressed, sharing, grab)
	-- fix53: the jpg goes as it is (util.Compress = LZMA on the main thread at every shot,
	-- and a jpg does not get smaller); the server takes plain and compressed
	local comp = compressed or jpg
	if not comp or #comp > G.PhotoMaxBytes then
		if cb then cb(0) else L.toast, L.toastAt = "Photo too big", RealTime() end
		return
	end
	local job = {jpg = jpg, comp = comp, wep = wep, page = page, cb = cb, sharing=sharing}
	if IsValid(wep) and not page and not sharing then job.widx, job.wnum = wep:EntIndex(), wep:GetNWString("STTS_Num", "") end -- fix54
	if not page then
		-- unique name: Material() caches by path
		job.tmp = RoundDir() .. "/t" .. math.floor(SysTime() * 1000) .. "_" .. math.random(1, 99999) .. ".jpg"
		file.CreateDir(RoundDir())
		file.Write(job.tmp, jpg) -- saved on this PC right away
		-- fix53: ... and in Photos / the camera thumbnail right away, before the server answers
		if not cb and SCR.M49 then
			job.pend = SCR.M49.AddPending(wep, job.tmp, jpg, grab) -- fix55: grab = the picture already on the GPU
			if L.wep == wep then L.gal, L.album = #State(wep).photos, 0 end
		end
	end
	upQ[#upQ + 1] = job
	UploadNext()
end

--[[---------------------------------------------------------------------------
	camera feeds: render.RenderView from a phone camera into a small RT
---------------------------------------------------------------------------]]
SCR.Remote = SCR.Remote or {} -- [phone entindex] = interpolated pose from the server
--[[ fix9: the pose of a remote camera comes twice: in the world (fallback, PVS)
     and RELATIVE to the holder's body (G.RefFrame). the relative one is rebuilt
     from the body as this PC sees it right now, so the camera never trails
     behind a walking / running / driving holder (it used to end up behind the
     phone or inside his head = "the phone covers the view"), and the phone
     drawn in his hand is put exactly there (weapon_stts_phone.lua, SetHandPos). ]]
net.Receive("stts_phone_feed", function()
	local idx, pos, ang, back = net.ReadUInt(16), net.ReadVector(), net.ReadAngle(), net.ReadBool()
	local zoom = net.ReadUInt(8) / 40
	local rp, ra
	if net.ReadBool() then rp, ra = net.ReadVector(), net.ReadAngle() end
	local r = SCR.Remote[idx]
	if not r then r = {} SCR.Remote[idx] = r end
	-- fix22: first packet after a pause = start right there (no slide from an old pose)
	if r.t1 and RealTime() - r.t1 > 0.5 then r.p1, r.a1, r.t1 = nil, nil, nil end
	r.p0, r.a0, r.t0 = r.p1 or pos, r.a1 or ang, r.t1 or RealTime()
	r.p1, r.a1, r.t1, r.back, r.zoom = pos, ang, RealTime(), back, zoom
	if rp then
		r.rp0, r.ra0 = r.rp1 or rp, r.ra1 or ra
		r.rp1, r.ra1 = rp, ra
	else
		r.rp0, r.ra0, r.rp1, r.ra1 = nil, nil, nil, nil
	end
end)

local function RelNow(r)
	if not r or not r.rp1 or RealTime() - r.t1 > 1.5 then return end
	local span = math.max(r.t1 - r.t0, 0.02)
	local k = math.Clamp((RealTime() - 0.07 - r.t0) / span, 0, 1)
	return LerpVector(k, r.rp0 or r.rp1, r.rp1), LerpAngle(k, r.ra0 or r.ra1, r.ra1)
end

-- pose of someone else's streaming phone, rebuilt from his body (nil = not streaming)
function SCR.RemotePose(wep, ply, fresh)
	local lp, la = RelNow(SCR.Remote[wep:EntIndex()])
	if not lp then return end
	local o, a = G.RefFrame(ply, fresh)
	if not o then return end
	return LocalToWorld(lp, la, o, a)
end

-- the pose the server relays from the holder's PC (interpolated), nil = none / too old
local function NetPose(idx)
	local r = SCR.Remote[idx]
	if r and r.t1 and RealTime() - r.t1 < 1.5 then
		local span = math.max(r.t1 - r.t0, 0.02)
		local k = math.Clamp((RealTime() - 0.07 - r.t0) / span, 0, 1)
		return LerpVector(k, r.p0, r.p1), LerpAngle(k, r.a0, r.a1)
	end
end

--[[ fix23: the camera is glued to the phone MODEL, no smoothing at all.
     a phone in a hand: drawn in THIS frame = exactly that pose. not drawn this frame
     (ragdoll behind a wall / behind you / first frame) = the pose is built right now
     the same way the draw builds it (bones of the body + the hand IK of the phone +
     palm offset, weapon_stts_phone.lua SWEP:PoseNow). fix22 used the pose relayed
     over the net there, interpolated 70 ms behind and blended in 0.25 s: that is the
     camera that "slowly swims to the phone". the net pose stays only as the last
     fallback (the holder is dormant on this PC). ]]
local function HeldPose(ent, f)
	if f == FrameNumber() then return ent.STTS_DrawPos, ent.STTS_DrawAng end
	if ent.PoseNow then
		local p, a = ent:PoseNow()
		if p then return p, a end
	end
	if f and FrameNumber() - f <= 1 then return ent.STTS_DrawPos, ent.STTS_DrawAng end
end

-- nil = no picture (a phone in a pocket / inventory shows black)
local function SourcePose(idx)
	local ent = Entity(idx)
	if IsValid(ent) then
		local owner = ent:GetOwner()
		local f = ent.STTS_DrawFrame
		local drawn = f and FrameNumber() - f <= 1
		if IsValid(owner) and owner:IsPlayer() then
			if owner:GetActiveWeapon() ~= ent then
				-- fix74: in the left hand next to a weapon in the right one: the model drawn there
				local RH = STTS.PhoneRH
				if RH and RH.Phone and RH.Phone(owner) == ent and f and FrameNumber() - f <= 3 then return ent.STTS_DrawPos, ent.STTS_DrawAng end
				return -- pocket
			end
			if owner == LocalPlayer() then
				-- fix23: own phone = the model of this frame (ragdoll too), never an older one
				if SCR.Ragdolled(owner) then
					local p, a = HeldPose(ent, f)
					if p then return p, a end
				elseif f and FrameNumber() - f <= 3 then
					return ent.STTS_DrawPos, ent.STTS_DrawAng
				end
			elseif SCR.Ragdolled(owner) then
				-- fix23: ragdoll: on the model (see HeldPose), the net pose only if he is dormant here
				local ch = hg.GetCurrentCharacter(owner)
				if not ent:IsDormant() and IsValid(ch) and not ch:IsDormant() then
					local p, a = HeldPose(ent, f)
					if p then return p, a end
				end
				local np, na = NetPose(idx)
				if np then return np, na end
			else
				local p, a = SCR.RemotePose(ent, owner, not drawn)
				if p then return p, a end
				if drawn then return ent.STTS_DrawPos, ent.STTS_DrawAng end
			end
		elseif IsValid(ent:GetParent()) then
			return -- in a corpse's pocket
		elseif drawn then
			return ent.STTS_DrawPos, ent.STTS_DrawAng
		elseif not IsValid(owner) then
			return ent:GetPos(), ent:GetAngles()
		end
	end
	return NetPose(idx)
end

-- fix61: somebody else's zoom glides too (it came in 0.1 s steps: the picture jumped)
local ZOOMS = {}
local function FeedZoom(idx)
	local ent = Entity(idx)
	if IsValid(ent) and L.wep == ent and ent:GetOwner() == LocalPlayer() then return L.zoom or 1 end
	local r = SCR.Remote[idx]
	local z
	if r and r.zoom and RealTime() - r.t1 < 1.5 then z = r.zoom else z = IsValid(ent) and ent:GetNW2Float("Zoom", 1) or 1 end
	z = math.Clamp(z, 1, G.ZoomMax)
	local now, s = RealTime(), ZOOMS[idx]
	if not s or now - s.t > 1 then s = {z = z, t = now} ZOOMS[idx] = s end
	local dt = math.Clamp(now - s.t, 0, 0.1)
	s.t = now
	if dt > 0 then s.z = math.exp(Lerp(1 - math.exp(-dt * 9), math.log(s.z), math.log(z))) end
	return s.z
end

--[[ cameras rendered right now: players / ragdolls around them count as "seen"
     (homigrad skips animations, TPIK and clothes of everything outside YOUR
     view, which is why far away video calls lost the animations) ]]
SCR.Cams = SCR.Cams or {}
function SCR.NearCam(pos, dist)
	local now = RealTime()
	for k, c in pairs(SCR.Cams) do
		if now - c.t > 0.6 then SCR.Cams[k] = nil
		elseif c.pos:DistToSqr(pos) < dist * dist then return true end
	end
	return false
end
local function BodyPos(ent)
	if ent:IsPlayer() and hg and hg.GetCurrentCharacter then
		local ch = hg.GetCurrentCharacter(ent)
		if IsValid(ch) then return ch:GetPos() end
	end
	return ent:GetPos()
end
SCR.BodyPos = BodyPos
-- the player is a ragdoll right now (fake / car)
local function Ragdolled(ply)
	if not (hg and hg.GetCurrentCharacter) then return false end
	local ch = hg.GetCurrentCharacter(ply)
	return IsValid(ch) and ch ~= ply
end
SCR.Ragdolled = Ragdolled
--[[ fix22: ragdolls too. homigrad animates (eyes, face, fingers, clothes, armor,
     "Player-Ragdoll think") only what is in YOUR view (hg.seenents / NotSeen).
     a ragdolled peer in a video call behind a wall / behind you = he froze in the
     picture without animations. everything near a camera that is being rendered
     now counts as seen (the holder's own view does not change: you are skipped) ]]
local function SeenAdd(set, e)
	if not IsValid(e) or set[e] then return end
	e.NotSeen = false
	set[e] = true
	local t = hg and hg.seenents
	if t then t[#t + 1] = e end
end
function SCR.MarkSeen()
	if not next(SCR.Cams) then return end
	local lp = LocalPlayer()
	local set = {}
	for _, e in ipairs(hg and hg.seenents or {}) do set[e] = true end
	for _, v in ipairs(player.GetAll()) do
		if v == lp or not v.shouldTransmit or v:IsDormant() then continue end
		if not SCR.NearCam(BodyPos(v), 1500) then continue end
		local ch = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(v)
		if IsValid(ch) and ch ~= v then
			-- ragdoll: the body is the ragdoll, the player entity only gets NotSeen cleared
			-- (homigrad itself skips ragdolled players in its think loop)
			v.NotSeen = false
			if ch.shouldTransmit ~= false and not ch:IsDormant() then SeenAdd(set, ch) end
		else
			SeenAdd(set, v)
		end
	end
	-- corpses / other ragdolls in the picture
	for _, r in ipairs(ents.FindByClass("prop_ragdoll")) do
		if r.NotSeen and r.shouldTransmit and not r:IsDormant() and r ~= (IsValid(lp) and lp.FakeRagdoll) and SCR.NearCam(r:GetPos(), 1500) then SeenAdd(set, r) end
	end
end

local FEEDS = {}
for i = 1, 4 do
	local rt = GetRenderTargetEx("stts_phone_feed_" .. i, G.FeedW, G.FeedH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGB888)
	FEEDS[i] = {rt = rt, mat = CreateMaterial("stts_phone_feedm_" .. i, "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$ignorez"] = 1}), want = 0, last = 0, rate = 0}
end
local photoRT = GetRenderTargetEx("stts_phone_photo", G.PhotoW, G.PhotoH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGB888)
--[[ v19.4: a landscape photo (the phone held landscape, T) = the portrait picture of the
     turned phone, turned upright into a 1024 x 576 one: the same lens, the same field of
     view, nothing rendered twice ]]
do
	local landRT = GetRenderTargetEx("stts_phone_photo_land", G.PhotoH, G.PhotoW, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	local src = CreateMaterial("stts_phone_photo_landsrc", "UnlitGeneric", {["$basetexture"] = photoRT:GetName(), ["$ignorez"] = 1, ["$vertexcolor"] = 1})
	SCR.PhotoSrcMat = src -- fix55: the picture of the last shot (SCR.Shot55)
	function SCR.LandVerts(pos, ang, back, wep)
		local _, cang = G.CamWorld(pos, ang, back, wep)
		-- "up" of the turned phone (its left edge) lies at the left of the picture (rear lens)
		-- or at its right (front lens): the corners of the picture go round that way
		local w, h = G.PhotoH, G.PhotoW
		if (-ang:Right()):Dot(cang:Right()) < 0 then
			return {{x = 0, y = 0, u = 0, v = 1}, {x = w, y = 0, u = 0, v = 0}, {x = w, y = h, u = 1, v = 0}, {x = 0, y = h, u = 1, v = 1}}
		end
		return {{x = 0, y = 0, u = 1, v = 0}, {x = w, y = 0, u = 1, v = 1}, {x = w, y = h, u = 0, v = 1}, {x = 0, y = h, u = 0, v = 0}}
	end
	function SCR.LandPhoto(pos, ang, back, wep)
		local w, h = G.PhotoH, G.PhotoW
		local v = SCR.LandVerts(pos, ang, back, wep)
		render.PushRenderTarget(landRT)
			render.Clear(0, 0, 0, 255)
			cam.Start2D()
				surface.SetMaterial(src) surface.SetDrawColor(255, 255, 255, 255)
				surface.DrawPoly(v)
			cam.End2D()
			local jpg = render.Capture({format = "jpg", quality = 88, x = 0, y = 0, w = w, h = h, alpha = false})
		render.PopRenderTarget()
		return jpg
	end
end

-- returns the material of the latest image (nil until the first frame is ready)
local function WantFeed(idx, back, rate)
	local preview = SCR.RecPreview
	if preview and L.rec and not L.rec.closed and preview.idx == idx and preview.back == back then return preview.mat end
	local key = idx * 2 + (back and 1 or 0)
	local now = RealTime()
	local f
	for _, s in ipairs(FEEDS) do if s.key == key then f = s break end end
	if not f then
		for _, s in ipairs(FEEDS) do
			if now - s.want > 0.5 and (not f or s.want < f.want) then f = s end
		end
		if not f then return end
		f.key, f.idx, f.back, f.ready, f.last, f.rate = key, idx, back, false, 0, 0
	end
	if now - f.want > 0.1 then f.rate = 0 end
	f.want = now
	f.rate = math.max(f.rate, rate)
	return f.ready and f.mat or nil
end

--[[ fix65: your head in the phone picture while you are a ragdoll. homigrad shrinks the head
     of the body you look out of to 0.01 right before it is drawn (bone matrix in
     DrawPlayerRagdoll / SmoothUnfake, bone scale in cl_fake.lua). the GetViewEntity trick
     (cl_compat.lua) does not reach every version of it, so while a phone camera renders,
     the body's head is put back to full size right before its DrawModel. a beheaded body
     (bone scale 0 / noHead / fountain) stays without a head ]]
local H65 = {meta = FindMetaTable("Entity"), full = Vector(1, 1, 1), t = {}} -- one local: the main chunk is at Lua's 200
function H65.fix(ent)
	local b = ent:LookupBone("ValveBiped.Bip01_Head1")
	if not b or ent.noHead then return end
	local ms = ent:GetManipulateBoneScale(b)
	if ms and ms:LengthSqr() < 1e-6 then return end
	local nv = GetNetVar
	local f = isfunction(nv) and nv("fountains") or nil
	if istable(f) and f[ent] then return end
	local m = ent:GetBoneMatrix(b)
	if not m then return end
	local sc = m:GetScale()
	if not sc or sc.x > 0.5 then return end
	local n = Matrix(m)
	n:SetScale(H65.full)
	if hg and isfunction(hg.bone_apply_matrix) then pcall(hg.bone_apply_matrix, ent, b, n) end -- with the bones under it
	local m2 = ent:GetBoneMatrix(b)
	if m2 and m2:GetScale().x < 0.5 then ent:SetBoneMatrix(b, n) end
end
-- fix68: the rear camera of the turned phone (landscape): the fingers that hold it from
-- behind are folded into their knuckles while that camera renders (only in its picture)
H65.tiny = Vector(0.001, 0.001, 0.001)
function H65.fingers(ent)
	for _, sd in ipairs({"L", "R"}) do
		for i = 1, 4 do
			local base = ent:LookupBone("ValveBiped.Bip01_" .. sd .. "_Finger" .. i)
			local bm = base and ent:GetBoneMatrix(base)
			if bm then
				local at = bm:GetTranslation()
				for _, suf in ipairs({"", "1", "2"}) do
					local b = suf == "" and base or ent:LookupBone("ValveBiped.Bip01_" .. sd .. "_Finger" .. i .. suf)
					local m = b and ent:GetBoneMatrix(b)
					if m then
						m:SetTranslation(at)
						m:SetScale(H65.tiny)
						ent:SetBoneMatrix(b, m)
					end
				end
			end
		end
	end
end
function H65.draw(self, ...)
	local t = H65.on
	if t then
		if self == t[1] or self == t[2] then
			pcall(H65.fix, self)
			if H65.fing then pcall(H65.fingers, self) end
		elseif IsValid(t[1]) then
			-- fix70: a bonemerged accessory (hood, balaclava) copies the head of its body: full size first
			local p = self.GetParent and self:GetParent()
			if p == t[1] then pcall(H65.fix, p) end
		end
	end
	return H65.orig(self, ...)
end
SCR.FixHead65 = H65.fix

-- wep = the phone whose camera this is: it is not drawn in its own picture
local function RenderCam(rt, w, h, pos, ang, back, selfiePly, zoom, wep, eis)
	local cpos, cang = G.CamWorld(pos, ang, back, wep) -- fix28: lens of THIS phone model
	-- fix16: the camera is never inside YOUR head: your head + accessories are always drawn
	-- (front camera, back camera, the other side of a video call, a dropped phone)
	local lp = LocalPlayer()
	selfiePly = selfiePly or (IsValid(lp) and lp:Alive() and lp) or nil
	local ch = selfiePly and hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(selfiePly)
	local oldInRV, oldRVWep, oldSelfie = SCR.InRV, SCR.RVWep, STTS_PHONE_SELFIE
	SCR.InRV, SCR.RVWep = true, wep
	-- fix23: in the ragdoll homigrad shrinks the head bone to 0.1 (first person view,
	-- cl_fake.lua): accessories on the head were skipped / tiny in the phone camera.
	-- full size only while this camera renders, put back right after
	local head, oldScale
	if IsValid(ch) then
		STTS_PHONE_SELFIE = selfiePly
		head = ch:LookupBone("ValveBiped.Bip01_Head1")
		if head then
			local sc = ch:GetManipulateBoneScale(head)
			-- fix65: scale 0 = beheaded (homigrad headgib): stays so
			if sc and sc:LengthSqr() < 2.9 and sc:LengthSqr() > 1e-6 then oldScale = sc ch:ManipulateBoneScale(head, Vector(1, 1, 1)) end
		end
		ch:InvalidateBoneCache()
	end
	local effect = eis and eis.mode > 0 and STTS.PhoneEIS
	local source
	local baseFov = G.ZoomFov(back and G.FovBack or G.FovFront, zoom)
	if effect then
		effect.Sample(eis, cang, RealTime(), tostring(IsValid(wep) and wep:EntIndex() or 0) .. ":" .. tostring(not back))
		local owner = IsValid(wep) and wep:GetOwner()
		local parent = IsValid(wep) and wep:GetParent()
		local unstable = (IsValid(owner) and owner:IsPlayer() and Ragdolled(owner)) or (IsValid(parent) and parent:GetClass() == "prop_ragdoll")
		local depth
		if unstable then
			local tr = util.TraceLine({start=cpos,endpos=cpos+cang:Forward()*1500,filter={wep,owner,parent,ch,lp},mask=MASK_VISIBLE_AND_NPCS})
			depth = tr.Hit and math.max(24,cpos:Distance(tr.HitPos)) or 1500
		end
		effect.Position(eis,cpos,RealTime(),unstable,depth)
	end
	if effect then source = effect.Begin(eis, w, h, baseFov) end
	local rw, rh = source and source.w or w, source and source.h or h
	local target = source and source.rt or rt
	-- fix65: only around the render itself (never left on after an error)
	local em = IsValid(ch) and H65.meta
	if em and em.DrawModel ~= H65.draw and isfunction(em.DrawModel) then
		H65.orig, em.DrawModel = em.DrawModel, H65.draw
		H65.t[1], H65.t[2] = ch, selfiePly
		H65.on = H65.t
		-- fix68: your own held phone, rear camera, turned
		H65.fing = back and IsValid(wep) and wep:GetOwner() == selfiePly and SCR.LandK(wep) > 0.05 or nil
	end
	render.PushRenderTarget(target, 0, 0, rw, rh)
	local ok, cleanFrame = pcall(function()
		render.Clear(0, 0, 0, 255, true, true)
		return STTS.PhoneView43.Render({origin = cpos, angles = cang, x = 0, y = 0, w = rw, h = rh, aspect = rw / rh,
			fov = source and source.fov or baseFov, znear = 1.5, zfar = 8000,
			drawviewmodel = false, drawhud = false, drawmonitors = false, dopostprocess = false, bloomtone = false, drawviewer = true}, target, rw, rh)
	end)
	if H65.on then
		if H65.meta.DrawModel == H65.draw then H65.meta.DrawModel = H65.orig end
		H65.on, H65.fing = nil, nil
		H65.t[1], H65.t[2] = nil, nil
	end
	if IsValid(ch) then
		if oldScale then ch:ManipulateBoneScale(head, oldScale) end
		ch:InvalidateBoneCache()
	end
	STTS_PHONE_SELFIE = oldSelfie
	SCR.InRV, SCR.RVWep = oldInRV, oldRVWep
	if not ok then render.PopRenderTarget() error(cleanFrame, 0) end
	if source then
		render.PopRenderTarget()
		render.PushRenderTarget(rt, 0, 0, w, h)
		effect.Draw(source, w, h, cang, G.ZoomFov(back and G.FovBack or G.FovFront, zoom), eis)
	end
	return cpos, effect and eis.outputAt or RealTime(), effect and not eis.ready
end

-- fix12: the spectator camera map (cl_shooting_cameras.lua) and the 911 console
-- (cl_shooting_phone.lua) reuse the video-call feeds
SCR.WantFeed, SCR.SourcePose, SCR.FeedZoom = WantFeed, SourcePose, FeedZoom
-- fix17: pose of a phone camera right now (photos, video frames, pose packets, lights)
function SCR.LivePose(wep)
	if not IsValid(wep) then return end
	return SourcePose(wep:EntIndex())
end
SCR.RenderCam = RenderCam -- fix15: the spectator fallback picture (cl_shooting_cameras.lua)

local function UpdateFeeds()
	local now, todo = RealTime(), {}
	for _, f in ipairs(FEEDS) do
		if f.key and not (SCR.RecPreview and L.rec and not L.rec.closed and SCR.RecPreview.idx == f.idx and SCR.RecPreview.back == f.back) and now - f.want < 0.5 and f.rate > 0 and now - f.last >= 1 / f.rate then todo[#todo + 1] = f end
	end
	table.sort(todo, function(a, b) return (now - a.last) * a.rate > (now - b.last) * b.rate end)
	local lp = LocalPlayer()
	for i = 1, math.min(#todo, 2) do -- at most 2 camera renders per frame
		local f = todo[i]
		local pos, ang = SourcePose(f.idx)
		local ent = Entity(f.idx)
		if pos then
			local selfie = not f.back and IsValid(ent) and ent:GetOwner() == lp and lp or nil
			local eis
			if IsValid(ent) and (ent == L.wep and (L.camMode or 0) > 0 or ent:GetNW2Int("CamMode",0)>0) and STTS.PhoneEIS then
				f.eis = f.eis or STTS.PhoneEIS.New()
				eis = f.eis
				eis.channel = "preview_" .. tostring(f.back)
				eis.mode = STTS.PhoneEIS.Mode(ent)
				f.rate = math.min(f.rate, G.RecFps())
			end
			local cpos = RenderCam(f.rt, G.FeedW, G.FeedH, pos, ang, f.back, selfie, FeedZoom(f.idx), IsValid(ent) and ent or nil, eis)
			render.PopRenderTarget()
			f.ready = true
			SCR.Cams[f.key] = {pos = cpos, t = now}
		elseif IsValid(ent) and IsValid(ent:GetOwner()) or (IsValid(ent) and IsValid(ent:GetParent())) then
			-- in a pocket: black picture, no text
			render.PushRenderTarget(f.rt) render.Clear(0, 0, 0, 255, true, true) render.PopRenderTarget()
			f.ready = true
		end
		f.last = now
	end
end

--[[---------------------------------------------------------------------------
	screen render targets (one per visible phone)
---------------------------------------------------------------------------]]
local SLOTS = {}
for i = 1, 5 do
	local rt = GetRenderTargetEx("stts_phone_scr_" .. i, W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	SLOTS[i] = {rt = rt, last = 0,
		mat = CreateMaterial("stts_phone_scrm_" .. i, "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$model"] = 1}),
		quad = CreateMaterial("stts_phone_scrq_" .. i, "UnlitGeneric", {["$basetexture"] = rt:GetName()})}
end

-- own phone only: apps are drawn here first, the pair lets a transition keep the last frame
local CONTENT = {}
for i = 1, 2 do
	local rt = GetRenderTargetEx("stts_phone_ui_" .. i, W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	CONTENT[i] = {rt = rt, mat = CreateMaterial("stts_phone_uim_" .. i, "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1})}
end
local contentIdx, contentOwner = 1, nil

local screenIdx = {}
function SCR.ApplyMaterial(wep, mdl)
	local mname = mdl:GetModel()
	local idx = screenIdx[mname]
	if idx == nil then
		idx = false
		local want = G.Of(wep).ScreenMat or "vivo_screen" -- fix28: display material of this model
		for i, m in ipairs(mdl:GetMaterials() or {}) do
			if string.find(m, want, 1, true) then idx = i - 1 break end
		end
		if not idx then
			for i, m in ipairs(mdl:GetMaterials() or {}) do
				if string.find(m, "_screen", 1, true) then idx = i - 1 break end
			end
		end
		screenIdx[mname] = idx
	end
	if not idx then return end
	local s = wep.STTS_Slot and SLOTS[wep.STTS_Slot]
	if s and s.wep == wep and s.ready then
		mdl:SetSubMaterial(idx, "!" .. s.mat:GetName())
	else
		mdl:SetSubMaterial(idx, "")
	end
end

-- used when the vivo model is not compiled yet: a flat quad on the display plane
function SCR.DrawQuad(wep, pos, ang)
	local c, n, up, right = G.ScreenWorld(pos, ang, wep)
	c = c + n * 0.02
	local M = G.Of(wep)
	local hu, hr = up * (M.ScreenH * 0.5), right * (M.ScreenW * 0.5)
	local s = wep.STTS_Slot and SLOTS[wep.STTS_Slot]
	if s and s.wep == wep and s.ready then render.SetMaterial(s.quad) else render.SetColorMaterial() end
	render.DrawQuad(c + hu - hr, c + hu + hr, c - hu + hr, c - hu - hr, (s and s.ready) and WHITE or Color(4, 4, 6))
end

--[[---------------------------------------------------------------------------
	UI: iOS look (dark mode).
	status bar + Dynamic Island + home indicator are drawn ON TOP of the apps
	(they stay put while the apps animate). transitions like on an iPhone:
	  home -> app      the app grows out of its icon (spring), home zooms back
	  app -> home      the app shrinks back into its icon
	  deeper page      pushes in from the right, the old one slides a bit left
	  back             the page slides out to the right
	  share sheet      slides up from the bottom
	  call screen      grows out of the Dynamic Island and shrinks back into it
	                   when the call is over (no "Call ended" text any more)
	  short messages   ("Photo sent", "No answer" ...) are shown by the
	                   Dynamic Island: it stretches open on a spring, shows the
	                   text with an icon and closes again.
	your own phone renders its apps into a content RT (ping-pong pair): on a
	screen change the last frame stays in the other RT and is the snapshot the
	transition animates. other phones get the same transitions without it.
---------------------------------------------------------------------------]]
local BACK, HOMEBAR = 10, 11
local phoneIcon = Material("stts/app_phone.png", "smooth mips")
local arrowMat = Material("stts/cursor_arrow.png", "smooth")
local appIcons = {
	phone = Material("stts/ios_phone.png", "smooth mips"),
	chat = Material("stts/ios_telechat.png", "smooth mips"),
	camera = Material("stts/ios_camera.png", "smooth mips"),
	gallery = Material("stts/ios_gallery.png", "smooth mips"),
	-- fix17: white glyphs (tinted at draw time): shade toggles, camera flash
	plane = Material("stts/ios_airplane.png", "smooth mips"),
	torch = Material("stts/ios_torch.png", "smooth mips"),
	flash = Material("stts/ios_flash.png", "smooth mips"),
}
local videoMat = Material("stts/ios_video.png", "smooth mips") -- fix10: "record video" icon (white, tinted at draw time)
local flipMat = Material("stts/ios_flip.png", "smooth mips") -- material icon "flip camera" (white, tinted at draw time)
local GV_PHOTOS, GV_ALBUMS, GV_ALBUM, GV_VIEW = 1, 2, 3, 4
local CHAT = {} -- TeleChat history, filled further down: [phone number] = {threads = {[peer] = {name, u, m}}}

-- iOS dark mode palette
local C = {
	bg2 = Color(28, 28, 30), bg3 = Color(44, 44, 46), sep = Color(84, 84, 88, 170),
	label = Color(255, 255, 255), label2 = Color(235, 235, 245, 153), label3 = Color(235, 235, 245, 76),
	blue = Color(10, 132, 255), green = Color(48, 209, 88), red = Color(255, 69, 58), yellow = Color(255, 214, 10),
	gray = Color(142, 142, 147), mono = Color(138, 142, 154), them = Color(38, 38, 41), bar = Color(20, 20, 22, 245),
	glass = Color(255, 255, 255, 48),
}

-- SF Pro is not in GMod: Roboto is (same proportions, has Cyrillic)
local function Font(name, size, weight)
	surface.CreateFont(name, {font = "Roboto", size = size, weight = weight, antialias = true, extended = true})
end
Font("STTS_I_Clock", 132, 700)
Font("STTS_I_Date", 27, 500)
Font("STTS_I_Large", 46, 700)
Font("STTS_I_Nav", 29, 600)
Font("STTS_I_Body", 28, 400)
Font("STTS_I_BodyB", 28, 600)
Font("STTS_I_Msg", 27, 400)
Font("STTS_I_Sub", 23, 400)
Font("STTS_I_Cap", 20, 500)
Font("STTS_I_Status", 23, 600)
Font("STTS_I_Island", 23, 600)
Font("STTS_I_CallName", 54, 400)
Font("STTS_I_CallSub", 27, 400)
Font("STTS_I_Mono", 28, 500)
Font("STTS_I_MonoBig", 64, 500)

local function Round(r, x, y, w, h, col)
	if w <= 0 or h <= 0 then return end
	draw.RoundedBox(math.max(0, math.floor(math.min(r, w / 2, h / 2))), x, y, w, h, LinCol(col))
end
local function Circle(x, y, r, col)
	r = math.floor(r)
	if r < 1 then return end
	draw.RoundedBox(r, math.floor(x - r), math.floor(y - r), r * 2, r * 2, LinCol(col))
end
-- vertical gradient. fix55: ONE vertex-coloured quad (smooth, the GPU blends it), was
-- 16..32 flat strips = visible bands ("steps" is kept for the callers, unused)
local function VGrad(x, y, w, h, c1, c2, steps)
	if w <= 0 or h <= 0 then return end
	local a = LinCol(c1)
	local r1, g1, b1, a1 = math.floor(a.r), math.floor(a.g), math.floor(a.b), math.floor(a.a or 255)
	local b = LinCol(c2)
	local r2, g2, b2, a2 = math.floor(b.r), math.floor(b.g), math.floor(b.b), math.floor(b.a or 255)
	render.SetColorMaterialIgnoreZ()
	mesh.Begin(MATERIAL_QUADS, 1)
		mesh.Position(Vector(x, y, 0)) mesh.Color(r1, g1, b1, a1) mesh.AdvanceVertex()
		mesh.Position(Vector(x + w, y, 0)) mesh.Color(r1, g1, b1, a1) mesh.AdvanceVertex()
		mesh.Position(Vector(x + w, y + h, 0)) mesh.Color(r2, g2, b2, a2) mesh.AdvanceVertex()
		mesh.Position(Vector(x, y + h, 0)) mesh.Color(r2, g2, b2, a2) mesh.AdvanceVertex()
	mesh.End()
end
-- clockwise triangle (surface.DrawPoly culls the other winding)
local function Tri(x1, y1, x2, y2, x3, y3, col)
	if (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1) < 0 then x2, y2, x3, y3 = x3, y3, x2, y2 end
	draw.NoTexture() surface.SetDrawColor(LinCol(col))
	surface.DrawPoly({{x = x1, y = y1}, {x = x2, y = y2}, {x = x3, y = y3}})
end
local function Line(x1, y1, x2, y2, th, col)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.01 then return end
	draw.NoTexture() surface.SetDrawColor(LinCol(col))
	surface.DrawTexturedRectRotated((x1 + x2) / 2, (y1 + y2) / 2, len, th, -math.deg(math.atan2(dy, dx)))
	if th >= 3 then Circle(x1, y1, th / 2, col) Circle(x2, y2, th / 2, col) end -- round caps
end
-- ring segment, angles in degrees, screen space (0 = right, 90 = down)
local function Arc(cx, cy, r, th, a0, a1, col, seg)
	seg = seg or 24
	draw.NoTexture() surface.SetDrawColor(LinCol(col))
	local r2 = r - th
	for i = 0, seg - 1 do
		local t0, t1 = math.rad(a0 + (a1 - a0) * i / seg), math.rad(a0 + (a1 - a0) * (i + 1) / seg)
		local c0, s0, c1, s1 = math.cos(t0), math.sin(t0), math.cos(t1), math.sin(t1)
		surface.DrawPoly({{x = cx + c0 * r, y = cy + s0 * r}, {x = cx + c1 * r, y = cy + s1 * r}, {x = cx + c1 * r2, y = cy + s1 * r2}, {x = cx + c0 * r2, y = cy + s0 * r2}})
	end
end
-- iOS chevron, x / y = tip
local function Chevron(x, y, s, dir, col, th)
	th = th or 4
	if dir == "left" then Line(x + s * 0.6, y - s, x, y, th, col) Line(x, y, x + s * 0.6, y + s, th, col)
	elseif dir == "right" then Line(x - s * 0.6, y - s, x, y, th, col) Line(x, y, x - s * 0.6, y + s, th, col)
	elseif dir == "down" then Line(x - s, y - s * 0.6, x, y, th, col) Line(x, y, x + s, y - s * 0.6, th, col)
	else Line(x - s, y + s * 0.6, x, y, th, col) Line(x, y, x + s, y + s * 0.6, th, col) end
end
-- rounded corners for pictures: paints the 4 corners outside the radius with the background colour
local function CornerMask(x, y, w, h, r, col)
	local corners = {{x, y, x + r, y + r, 180}, {x + w, y, x + w - r, y + r, 270}, {x + w, y + h, x + w - r, y + h - r, 0}, {x, y + h, x + r, y + h - r, 90}}
	for _, c in ipairs(corners) do
		for i = 0, 5 do
			local t0, t1 = math.rad(c[5] + 15 * i), math.rad(c[5] + 15 * (i + 1))
			Tri(c[1], c[2], c[3] + math.cos(t0) * r, c[4] + math.sin(t0) * r, c[3] + math.cos(t1) * r, c[4] + math.sin(t1) * r, col)
		end
	end
end

local function Initials(name)
	local out, n = "", 0
	for word in string.gmatch(tostring(name or "?"), "%S+") do
		local ok, cp = pcall(utf8.codepoint, word, 1)
		if ok and cp then out, n = out .. utf8.char(cp), n + 1 end
		if n >= 2 then break end
	end
	return out == "" and "?" or string.upper(out)
end
-- contact picture: grey monogram like iOS, red SOS for 911
local function Avatar(name, num, x, y, r)
	if num == "911" or name == "911" then
		Circle(x, y, r, C.red)
		T("SOS", r > 40 and "STTS_I_Nav" or "STTS_I_Cap", x, y, WHITE)
		return
	end
	Circle(x, y, r, C.mono)
	T(Initials(name), r > 40 and "STTS_I_MonoBig" or "STTS_I_Mono", x, y, WHITE)
end

-- per phone animation helpers (dt of the last screen frame of THIS phone)
local function HoverK(wep, id, on)
	local t = wep.STTS_HK or {}
	wep.STTS_HK = t
	local k = Lerp(1 - math.exp(-(wep.STTS_UIdt or 0) * 16), t[id] or 0, on and 1 or 0)
	t[id] = k
	return k
end
local function Pressed(wep, st, id)
	return st.sel == id and wep.STTS_TapAt ~= nil and RealTime() - wep.STTS_TapAt < 0.18
end
--[[ iOS home screen icon highlight: no hover, no scale. the icon darkens at once under the
     finger (touch down) and the tint fades back out after the finger lets go ]]
local function IconHi(wep, st, id)
	local t = wep.STTS_IHi or {}
	wep.STTS_IHi = t
	local k = t[id] or 0
	if st.sel == id and (wep.STTS_Touching or Pressed(wep, st, id)) then k = 1
	else k = k * math.exp(-(wep.STTS_UIdt or 0) * 13) end
	if k < 0.01 then k = 0 end
	t[id] = k
	return k
end
-- hover grows a little, a tap dips (iOS icon / button feel)
local function PopScale(wep, key, hov, press)
	local t = wep.STTS_IconK or {}
	wep.STTS_IconK = t
	local k = Lerp(1 - math.exp(-(wep.STTS_UIdt or 0) * 18), t[key] or 1, press and 0.9 or (hov and 1.06 or 1))
	t[key] = k
	return k
end
local function Reg(btns, id, x, y, w, h, action)
	local b = {id = id, x = x, y = y, w = w, h = h, action = action}
	btns[#btns + 1] = b
	return b
end
-- areas for the sliding finger (LMB held): {kind = "scroll", step, invert} / {kind = "swipe", fn(dir)}
local function Zone(btns, z)
	btns.zones = btns.zones or {}
	btns.zones[#btns.zones + 1] = z
end

local function SetApp(st, app)
	if not st.own then return end
	if app == G.APP_HOME then L.backTo = nil end
	if app == G.APP_GALLERY and L.app == G.APP_HOME then L.galV, L.album = GV_PHOTOS, 0 end -- opens on "Library"
	L.app, L.scroll, L.sel = app, 0, 0
	L.scrollV, L.scrollGo = 0, nil -- fix17
end

-- "< Label" in system blue, top left
local function NavBack(btns, wep, st, label, action, col)
	col = col or C.blue
	surface.SetFont("STTS_I_Body")
	local w = label and (surface.GetTextSize(label) + 64) or 72
	Reg(btns, BACK, 6, 52, w, 52, action)
	local k = HoverK(wep, BACK, st.sel == BACK)
	if k > 0.01 then Round(18, 6, 54, w, 48, SCR.Ink(26 * k)) end
	local c = Pressed(wep, st, BACK) and Color(col.r, col.g, col.b, 90) or col
	Chevron(26, 78, 14, "left", c, 4.5)
	if label then T(Fit(label, "STTS_I_Body", 180), "STTS_I_Body", 44, 78, c, TEXT_ALIGN_LEFT) end
end
local function LargeTitle(text, y)
	T(Fit(text, "STTS_I_Large", W - 48), "STTS_I_Large", 24, y, C.label, TEXT_ALIGN_LEFT)
end
local function InlineTitle(text, y)
	T(Fit(text, "STTS_I_Nav", W - 210), "STTS_I_Nav", W / 2, y or 78, C.label)
end

-- round button (call screen, camera): circle, glyph, label under it
local function RoundBtn(btns, wep, st, id, x, y, r, bg, glyph, label, action)
	Reg(btns, id, x - r, y - r, r * 2, r * 2, action)
	local hov = st.sel == id
	local rr = r * PopScale(wep, "rb" .. id, hov, Pressed(wep, st, id))
	if hov then Circle(x, y, rr + 6, Color(255, 255, 255, 46)) end
	Circle(x, y, rr, bg)
	glyph(x, y, rr)
	if label then T(label, "STTS_I_Cap", x, y + r + 24, C.label) end
end
-- icon button in a toolbar: hover = soft circle
local function IconBtn(btns, wep, st, id, x, y, glyph, action)
	Reg(btns, id, x - 38, y - 38, 76, 76, action)
	local k = HoverK(wep, id, st.sel == id)
	if k > 0.01 then Circle(x, y, 34, Color(255, 255, 255, 30 * k)) end
	glyph(x, y, Pressed(wep, st, id) and Color(10, 132, 255, 110) or C.blue)
end

--[[ glyphs ]]
local function GHandset(x, y, r, col, down)
	if not phoneIcon:IsError() then
		local s = r * 1.0
		surface.SetMaterial(phoneIcon) surface.SetDrawColor(col)
		-- the png: earpiece top right, curve toward the top left. -45 = lying flat, ends down (hang up)
		surface.DrawTexturedRectRotated(x, y, s, s, down and -45 or 0)
		return
	end
	local rad = r * 0.5
	if down then Arc(x, y + rad * 0.6, rad, rad * 0.4, 200, 340, col, 14)
	else Arc(x + rad * 0.15, y + rad * 0.15, rad, rad * 0.4, 155, 295, col, 14) end
end
local function GVideo(x, y, r, col)
	if not videoMat:IsError() then
		local sz = r * 1.05
		surface.SetMaterial(videoMat) surface.SetDrawColor(col)
		surface.DrawTexturedRect(x - sz / 2, y - sz / 2, sz, sz)
		return
	end
	-- content not mounted yet: the old drawn camera
	local w, h = r * 0.62, r * 0.46
	local x0 = x - r * 0.45
	Round(6, x0, y - h / 2, w, h, col)
	Tri(x0 + w + 3, y, x0 + w + r * 0.32, y - h * 0.42, x0 + w + r * 0.32, y + h * 0.42, col)
end
local function GFlip(x, y, r, col)
	if not flipMat:IsError() then
		local sz = r * 1.05
		surface.SetMaterial(flipMat) surface.SetDrawColor(col)
		surface.DrawTexturedRect(x - sz / 2, y - sz / 2, sz, sz)
		return
	end
	-- content not mounted yet: the old drawn arrows
	local rad, th = r * 0.44, math.max(3, r * 0.1)
	Arc(x, y, rad, th, 200, 320, col, 12)
	Arc(x, y, rad, th, 20, 140, col, 12)
	for _, a in ipairs({320, 140}) do -- arrow heads, both turn clockwise
		local t = math.rad(a)
		local nx, ny = math.cos(t), math.sin(t)
		local px, py = x + nx * (rad - th / 2), y + ny * (rad - th / 2)
		local tx, ty = -ny, nx
		local s = th * 1.9
		Tri(px + tx * s, py + ty * s, px + nx * s, py + ny * s, px - nx * s, py - ny * s, col)
	end
end
local function GShare(x, y, col)
	local s, th = 20, 3.5
	Line(x - s * 0.62, y - s * 0.1, x - s * 0.62, y + s * 0.8, th, col)
	Line(x - s * 0.62, y + s * 0.8, x + s * 0.62, y + s * 0.8, th, col)
	Line(x + s * 0.62, y + s * 0.8, x + s * 0.62, y - s * 0.1, th, col)
	Line(x, y - s * 0.95, x, y + s * 0.35, th, col)
	Chevron(x, y - s * 0.95, s * 0.4, "up", col, th)
end
local function GTrash(x, y, col)
	local s, th = 20, 3.5
	Line(x - s * 0.75, y - s * 0.55, x + s * 0.75, y - s * 0.55, th, col)
	Line(x - s * 0.25, y - s * 0.82, x + s * 0.25, y - s * 0.82, th, col)
	Line(x - s * 0.55, y - s * 0.4, x - s * 0.45, y + s * 0.82, th, col)
	Line(x + s * 0.55, y - s * 0.4, x + s * 0.45, y + s * 0.82, th, col)
	Line(x - s * 0.45, y + s * 0.82, x + s * 0.45, y + s * 0.82, th, col)
	Line(x, y - s * 0.2, x, y + s * 0.55, 3, col)
end
-- fix15: save to PC: arrow down into a tray
local function GSave(x, y, col)
	local s, th = 20, 3.5
	Line(x - s * 0.75, y + s * 0.3, x - s * 0.75, y + s * 0.85, th, col)
	Line(x - s * 0.75, y + s * 0.85, x + s * 0.75, y + s * 0.85, th, col)
	Line(x + s * 0.75, y + s * 0.85, x + s * 0.75, y + s * 0.3, th, col)
	Line(x, y - s * 0.95, x, y + s * 0.35, th, col)
	Chevron(x, y + s * 0.35, s * 0.4, "down", col, th)
end
local function GClose(x, y, s, col)
	Line(x - s, y - s, x + s, y + s, 3.5, col)
	Line(x - s, y + s, x + s, y - s, 3.5, col)
end
local function GUp(x, y, col)
	Line(x, y - 11, x, y + 11, 4, col)
	Chevron(x, y - 11, 8, "up", col, 4)
end

local function DrawFeedFull(mat, x, y, w, h)
	if not mat then R(x, y, w, h, Color(10, 10, 12)) return end
	-- cover: feed is 9:16, the display is a bit taller -> crop the sides
	local fw = h * G.FeedW / G.FeedH
	local u0 = math.max(0, (fw - w) / 2 / fw)
	surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255)
	if SCR.FeedFlip68 then surface.DrawTexturedRectUV(x, y, w, h, 1 - u0, 1, u0, 0) return end -- fix68
	surface.DrawTexturedRectUV(x, y, w, h, u0, 0, 1 - u0, 1)
end
SCR.DrawFeedFull = DrawFeedFull

-- video: frame f (0 based) -> page photo id + uv inside the atlas (half a texel inset)
-- fix16: every video has its own frame size / atlas (meta.res, old videos = preset 3)
local function FrameUV(meta, f)
	local l = G.VidLayout(meta.res)
	local page = math.floor(f / l.frames) + 1
	local slot = f % l.frames
	local col, row = slot % l.cols, math.floor(slot / l.cols)
	local u0, v0 = (col * l.w + 0.5) / l.aw, (row * l.h + 0.5) / l.ah
	return meta.pages[page], u0, v0, u0 + (l.w - 1) / l.aw, v0 + (l.h - 1) / l.ah
end
local function IsVideo(st, id) return (id and id < 0 and STTS.PhoneGallery33 and STTS.PhoneGallery33.Get(id)) or (st.vids and st.vids[id]) or VIDS[id] ~= nil end
-- small white play triangle (video thumbnails)
local function GPlay(x, y, s, col)
	Tri(x - s * 0.45, y - s * 0.6, x + s * 0.65, y, x - s * 0.45, y + s * 0.6, col or WHITE)
end
-- one frame of a video (t = seconds since it started), loops
local function DrawVideo(st, id, x, y, w, h, t)
	if STTS.PhoneGallery33 and STTS.PhoneGallery33.IsBlob(id,st) then STTS.PhoneGallery33.Draw(id,x,y,w,h,t);return end
	local meta = VideoMeta(id, not st.own)
	if not meta then R(x, y, w, h, Color(16, 16, 18)) return end
	local f = math.floor(math.max(t, 0) * meta.fps) % meta.frames
	local pid, u0, v0, u1, v1 = FrameUV(meta, f)
	local mat = pid and PhotoMat(pid, not st.own)
	if not mat then
		pid, u0, v0, u1, v1 = FrameUV(meta, 0) -- later pages still downloading: hold the first frame
		mat = pid and PhotoMat(pid, true)
	end
	if not mat then R(x, y, w, h, Color(16, 16, 18)) return end
	surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255)
	surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
end

local PHOTO_V0 = (1 - G.PhotoW / G.PhotoH) / 2 -- square crop of a 9:16 picture
local function Thumb(st, id, x, y, size, noIcon)
 -- fix53: received media not downloaded yet: blurred preview + download button
 if SCR.M49 and SCR.M49.ThumbLocked(st, id, x, y, size) then return end
 if STTS.PhoneGallery33 and STTS.PhoneGallery33.IsBlob(id,st) then
  local mat=STTS.PhoneGallery33.Thumb(id)
  local rot=STTS.PhoneGallery33.Rot66 and STTS.PhoneGallery33.Rot66(id) or 0 -- fix68: filmed landscape = turned upright
  if mat and rot~=0 then
   local m=Matrix();m:Translate(Vector(x+size/2,y+size/2,0));m:Rotate(Angle(0,rot,0));m:Translate(Vector(-(x+size/2),-(y+size/2),0))
   cam.PushModelMatrix(m,true);surface.SetMaterial(mat);surface.SetDrawColor(255,255,255);surface.DrawTexturedRectUV(x,y,size,size,0,PHOTO_V0,1,1-PHOTO_V0);cam.PopModelMatrix()
  elseif mat then surface.SetMaterial(mat);surface.SetDrawColor(255,255,255);surface.DrawTexturedRectUV(x,y,size,size,0,PHOTO_V0,1,1-PHOTO_V0) else R(x,y,size,size,C.bg3) end
  if not noIcon then GPlay(x+size*.15,y+size*.85,math.max(8,size*.13),WHITE) end;return
 end
	if IsVideo(st, id) then -- first frame, square crop, play triangle
		local meta = VideoMeta(id, not st.own)
		local pid = meta and meta.pages[1]
		local mat = pid and PhotoMat(pid, not st.own)
		if mat then
			local l = G.VidLayout(meta.res)
			local crop = (l.h - l.w) / 2
			surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRectUV(x, y, size, size, 0.5 / l.aw, crop / l.ah, (l.w - 0.5) / l.aw, (crop + l.w) / l.ah)
		else
			R(x, y, size, size, C.bg3)
		end
		local g = math.max(8, size * 0.13)
		if not noIcon then GPlay(x + g * 1.4, y + size - g * 1.4, g, Color(255, 255, 255, 230)) end
		return
	end
	local mat = SCR.Shot55 and SCR.Shot55.ThumbMat(id) or PhotoMat(id, not st.own) -- others only show what is already on this PC
	if mat then
		surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255)
		local pw, ph = SCR.PhotoSize(id)
		if pw > ph then -- v19.4: landscape photo: the square from its middle
			local u0 = (1 - ph / pw) / 2
			surface.DrawTexturedRectUV(x, y, size, size, u0, 0, 1 - u0, 1)
		else
			surface.DrawTexturedRectUV(x, y, size, size, 0, PHOTO_V0, 1, 1 - PHOTO_V0)
		end
	else
		R(x, y, size, size, C.bg3)
	end
end

--[[---------------------------------------------------------------------------
	fix53: photos show up at once + TeleChat media like Telegram
	* a photo you take is on the phone right away (camera thumbnail, Photos):
	  a local "pending" entry (id <= -1000000) until the server confirmed it and
	  its real id is in the gallery (NW2 "Photos"); then the entry goes. a tiny
	  36 x 64 jpg of it is sent along (stts_p49_prev) for the receivers.
	* received media (TeleChat bubbles, album Received) are NOT downloaded by
	  themselves any more: blurred tiny preview + size (+ duration) + a round
	  download button. tap = download (ring with progress and a cross, tap
	  again = cancel), downloaded = tap opens it. opening it full screen in
	  Photos downloads it too. your own clip on its way out: ring with progress,
	  tap = cancel sending (the clip stays in Photos).
---------------------------------------------------------------------------]]
do
	local M49 = {pend = {}, pendN = 0, prevQ = {}}
	SCR.M49 = M49
	local PEND0 = -1000000
	local function Gal() return STTS.PhoneGallery33 end
	local function Round49() return GetGlobalInt("STTS_PhotoRound", 1) end

	function M49.Reset()
		for _, p in pairs(M49.pend or {}) do if p.path then file.Delete(p.path) end end
		M49.pend, M49.prevQ = {}, {}
		M49.manual, M49.want, M49.wantAt, M49.tries, M49.have, M49.haveAt = {}, {}, {}, {}, {}, {}
		M49.info, M49.askInfo, M49.pageOf, M49.pagesDone, M49.pagesGot = {}, {}, {}, {}, {}
		M49.recvSeen = setmetatable({}, {__mode = "k"})
		if SCR.Shot55 then SCR.Shot55.Reset() end
	end
	M49.Reset()

	--[[ pending photos ]]
	--[[ fix55: the photo is NOT loaded back from the disk at the shot any more (Material()
	     of a fresh 576 x 1024 jpg with mips = the freeze at every shot): the picture stays
	     on the GPU (SCR.Shot55 slot: full size + a small thumbnail), it is read from the
	     disk only if its slot is reused by a later shot ]]
	function M49.AddPending(wep, path, jpg, grab)
		M49.pendN = M49.pendN + 1
		local nid = PEND0 - M49.pendN
		local w, h = SCR.JpegSize(jpg)
		local p = {nid = nid, wep = wep, num = IsValid(wep) and wep:GetNWString("STTS_Num", "") or "", path = path,
			w = w or G.PhotoW, h = h or G.PhotoH, at = RealTime(), round = Round49()}
		if grab and SCR.Shot55 and SCR.Shot55.Own(grab, p) then
			p.mat, p.tmat, p.slot = grab.mat, grab.tmat, grab
		end
		M49.pend[nid] = p
		M49.prevQ[#M49.prevQ + 1] = p
		return p
	end
	function M49.PendMat(id)
		local p = M49.pend[id]
		if not p then return end
		if not p.mat and p.path and not p.loadTried then -- its slot went to a later shot
			p.loadTried = true
			local m = Material("../data/" .. p.path, "smooth noclamp")
			if m and not m:IsError() then p.mat = m end
		end
		return p.mat
	end
	function M49.PendThumb(id) local p = M49.pend[id] return p and p.tmat or nil end
	function M49.PendSize(id) local p = M49.pend[id] if p then return p.w, p.h end end
	-- real id of a pending photo (nil while it uploads), the entry
	function M49.Resolve(id)
		local p = M49.pend[id]
		if not p then return end
		return p.id, p
	end
	function M49.Drop(p)
		M49.pend[p.nid] = nil
		if p.path then file.Delete(p.path) p.path = nil end
	end
	local function SendPrev(p)
		if p.prevSent or not p.prev or not p.id or p.id <= 0 then return end
		p.prevSent = true
		net.Start("stts_p49_prev") net.WriteUInt(p.id, 32) net.WriteUInt(#p.prev, 16) net.WriteData(p.prev, #p.prev) net.SendToServer()
	end
	-- the server answered the upload of a pending photo (id 0 = rejected)
	function M49.UpDone(p, id)
		if not p then return end
		if not id or id <= 0 then M49.Drop(p) return end
		p.id, p.idAt = id, RealTime()
		M49.have[id] = true
		if p.slot and SCR.Shot55 then SCR.Shot55.ToId(p, id) end -- fix55: no reload from the disk
		SendPrev(p)
		if p.deleted then
			net.Start("stts_phone_del") net.WriteUInt(id, 32) net.SendToServer()
			M49.Drop(p)
			return
		end
		-- sent to a conversation while it was uploading (the server allows one send per second)
		-- fix61: through the send queue (sent again until the server's echo comes back)
		for _, peer in ipairs(p.share or {}) do SCR.ShareOut(p.num, peer, id) end
		p.share = nil
	end
	function M49.DeletePending(id)
		local p = id and M49.pend[id]
		if not p then return false end
		if p.id then
			net.Start("stts_phone_del") net.WriteUInt(p.id, 32) net.SendToServer()
			M49.Drop(p)
		else
			p.deleted = true -- removed on the server the moment it is saved there
		end
		return true
	end
	-- State(): pending photos of this phone at the end of its gallery, album Received = manual
	function M49.Merge(st, wep)
		if st.recv and not M49.recvSeen[st.recv] then
			M49.recvSeen[st.recv] = true
			for _, id in ipairs(st.recv) do M49.manual[id] = true end
		end
		if not st.own or next(M49.pend) == nil then return end
		local now, rnd = RealTime(), Round49()
		local list, seen
		for _, p in pairs(M49.pend) do
			if p.round ~= rnd or (p.id and now - p.idAt > 15) or (not p.id and now - p.at > 120) then
				M49.Drop(p)
			elseif not p.deleted and ((p.num ~= "" and p.num == st.num) or (p.num == "" and p.wep == wep)) then
				if not seen then seen = {} for _, v in ipairs(st.photos) do seen[v] = true end end
				if p.id and seen[p.id] then M49.Drop(p) -- the gallery has it: same place, real id
				else list = list or {} list[#list + 1] = p end
			end
		end
		if not list then return end
		table.sort(list, function(a, b) return a.nid > b.nid end) -- oldest first
		local out = {}
		for i, v in ipairs(st.photos) do out[i] = v end -- st.photos may be a shared parse cache
		for _, p in ipairs(list) do out[#out + 1] = p.nid end
		st.photos = out
	end

	--[[ tiny previews (36 x 64 / 64 x 36 jpg, ~1 KB), one per frame in PostRender ]]
	local prevRT = {}
	local function PrevRT(land)
		local key = land and "l" or "p"
		local r = prevRT[key]
		if not r then
			local w, h = land and 64 or 36, land and 36 or 64
			r = {rt = GetRenderTargetEx("stts_p49_prev_" .. key, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888), w = w, h = h}
			prevRT[key] = r
		end
		return r
	end
	-- a clip committed by the server (cl_stts_phone_gallery33.lua): its preview too
	function M49.QueuePrev(id, matFn, w, h)
		if not id or id <= 0 or #M49.prevQ >= 8 then return end
		M49.prevQ[#M49.prevQ + 1] = {id = id, matFn = matFn, w = w, h = h, at = RealTime()}
	end
	function M49.PrevStep()
		local p = M49.prevQ[1]
		if not p then return end
		if RealTime() - (p.at or 0) > 8 then table.remove(M49.prevQ, 1) return end
		local mat = p.tmat or p.mat
		if not mat and p.nid then mat = M49.PendMat(p.nid) end
		if not mat and p.matFn then local ok, m = pcall(p.matFn) if ok then mat = m end end
		if not mat then return end -- not loaded yet: next frame
		table.remove(M49.prevQ, 1)
		local r = PrevRT((p.w or 9) > (p.h or 16))
		local jpg
		render.PushRenderTarget(r.rt)
			render.Clear(0, 0, 0, 255)
			cam.Start2D()
				surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
				surface.DrawTexturedRect(0, 0, r.w, r.h)
			cam.End2D()
			jpg = render.Capture({format = "jpg", quality = 55, x = 0, y = 0, w = r.w, h = r.h, alpha = false})
		render.PopRenderTarget()
		if jpg and #jpg >= 4 and #jpg <= 4096 then p.prev = jpg SendPrev(p) end
	end

	--[[ received media: tap to download ]]
	function M49.MarkManual(id) if id and id > 0 then M49.manual[id] = true end end
	function M49.Locked(id)
		return id ~= nil and M49.manual[id] == true and not M49.want[id] and not M49.have[id]
	end
	-- a chunk nobody asked for (download cancelled): pages count for their video
	function M49.Blocked(id)
		local par = M49.pageOf[id] or id
		return M49.manual[par] == true and not M49.want[par] and not M49.have[par]
	end
	local function Kind(st, id) -- 0 photo, 1 video (pages), 2 video (clip)
		local P = Gal()
		if P and P.IsBlob(id, st) then return 2 end
		if (st.vids and st.vids[id]) or VIDS[id] then return 1 end
		local inf = M49.info[id]
		return inf and inf.kind or 0
	end
	M49.Kind = Kind
	function M49.Have(st, id)
		if not id or id <= 0 or M49.have[id] then return true end
		local k, ok = Kind(st, id), false
		if k == 2 then
			local it = Gal() and Gal().Get(id)
			ok = it ~= nil and it.playable48 == true and not it.predicted
		elseif k == 1 then
			local v = VIDS[id]
			ok = v ~= nil and #v.pages > 0 and (M49.pagesDone[id] or 0) >= #v.pages
		else
			if mats[id] then ok = true
			elseif (M49.haveAt[id] or 0) < RealTime() then
				M49.haveAt[id] = RealTime() + 0.3
				ok = file.Exists(PhotoPath(id), "DATA")
			end
		end
		if ok then M49.have[id] = true end
		return ok
	end
	-- a downloaded chunk finished a whole item (cl: stts_phone_dlc)
	function M49.Got(id)
		local par = M49.pageOf[id]
		if not par then return end
		local set = M49.pagesGot[par] or {}
		M49.pagesGot[par] = set
		if not set[id] then set[id] = true M49.pagesDone[par] = (M49.pagesDone[par] or 0) + 1 end
	end
	local function Ask(st, id)
		M49.wantAt[id] = RealTime()
		M49.tries[id] = (M49.tries[id] or 0) + 1
		if Kind(st, id) == 2 then
			local P = Gal()
			if P then
				if P.Cancel49 then P.Cancel49(id, true) end -- soft: only its request throttle
				P.Request(id, false)
			end
		else
			asked[id] = RealTime() + 6
			net.Start("stts_phone_dl") net.WriteUInt(id, 32) net.SendToServer()
		end
	end
	function M49.Start(st, id)
		if not id or id <= 0 then return end
		M49.want[id], M49.tries[id] = true, 0
		Ask(st, id)
	end
	function M49.Cancel(st, id)
		M49.want[id] = nil
		dl[id], asked[id] = nil, nil
		local v = VIDS[id]
		if v then for _, pid in ipairs(v.pages) do dl[pid] = nil end end
		local P = Gal()
		if P and P.Cancel49 then P.Cancel49(id) end
		net.Start("stts_p49_cancel") net.WriteUInt(id, 32) net.SendToServer()
	end
	function M49.AutoStart(st, id)
		if st.own and id and id > 0 and M49.manual[id] and not M49.want[id] and not M49.Have(st, id) then M49.Start(st, id) end
	end
	local function Started(id, k)
		if k == 2 then local P = Gal() return P ~= nil and P.incoming[id] ~= nil end
		if k == 1 then return VIDS[id] ~= nil end
		return dl[id] ~= nil
	end
	-- a request the server dropped (its own rate limit) is asked again
	hook.Add("Think", "STTS_PhoneMedia49", function()
		local now = RealTime()
		if now < (M49.nextTick or 0) or next(M49.want) == nil then return end
		M49.nextTick = now + 0.25
		local wep = MyPhone()
		if not wep then return end
		local st = State(wep)
		for id in pairs(M49.want) do
			if M49.Have(st, id) then M49.want[id] = nil
			elseif not Started(id, Kind(st, id)) and now - (M49.wantAt[id] or 0) > 1.5 then
				if (M49.tries[id] or 0) >= 8 then M49.want[id] = nil else Ask(st, id) end
			end
		end
	end)
	-- bytes so far / bytes in all (0 = not known yet)
	function M49.Progress(st, id)
		local inf = M49.info[id]
		local total = inf and inf.bytes or 0
		local k = Kind(st, id)
		if k == 2 then
			local P = Gal()
			local j = P and P.incoming[id]
			if j then return j.received[1] + j.received[2] + j.received[3], j.sizes[1] + j.sizes[3] + (j.full and j.sizes[2] or 0) end
			return 0, total
		elseif k == 1 then
			local v = VIDS[id]
			if not v or #v.pages == 0 then return 0, total end
			local f = M49.pagesDone[id] or 0
			for _, pid in ipairs(v.pages) do
				local j = dl[pid]
				if j and j.total44 then f = f + j.got / j.total44 break end
			end
			f = math.min(1, f / #v.pages)
			if total > 0 then return f * total, total end
			return f, 1
		end
		local j = dl[id]
		if j and j.total44 then return j.got, j.total44 end
		return 0, total
	end
	function M49.Duration(st, id)
		local P = Gal()
		local it = P and P.Get(id)
		if it and it.duration then return it.duration end
		local v = VIDS[id]
		if v then return v.frames / math.max(1, v.fps) end
		local inf = M49.info[id]
		if inf and inf.dur > 0 then return inf.dur end
	end

	--[[ size, duration, tiny preview of a received item (asked once, a few per frame) ]]
	function M49.Info(id)
		local now = RealTime()
		local inf = M49.info[id]
		if inf and (inf.prev or inf.again) then return inf end
		if (M49.askInfo[id] or 0) > now then return inf end
		if FrameNumber() ~= M49.infoFrame then M49.infoFrame, M49.infoN = FrameNumber(), 0 end
		if M49.infoN >= 4 then return inf end
		M49.infoN = M49.infoN + 1
		if inf then inf.again = true end -- the sender's preview may come a moment after the message
		M49.askInfo[id] = now + (inf and 2 or 3)
		net.Start("stts_p49_info") net.WriteUInt(id, 32) net.SendToServer()
		return inf
	end
	net.Receive("stts_p49_info", function()
		local id, kind, bytes, dur, n = net.ReadUInt(32), net.ReadUInt(2), net.ReadUInt(32), net.ReadUInt(16), net.ReadUInt(16)
		local old = M49.info[id]
		local inf = {kind = kind, bytes = bytes, dur = dur / 10, again = old and old.again}
		if old and old.prev then inf.prev, inf.pw, inf.ph = old.prev, old.pw, old.ph end
		if n > 0 and n <= 4096 and not inf.prev then
			local data = net.ReadData(n)
			if data and #data == n and string.sub(data, 1, 2) == "\255\216" then
				local path = RoundDir() .. "/b" .. id .. ".jpg"
				file.CreateDir(RoundDir())
				file.Write(path, data)
				local m = Material("../data/" .. path, "smooth") -- clamped: the blur samples past the edges
				if m and not m:IsError() then inf.prev = m inf.pw, inf.ph = SCR.JpegSize(data) end
			end
		end
		M49.info[id] = inf
	end)

	--[[ drawing, Telegram style ]]
	local PILL, DISC, SHADE, PLACE = Color(0, 0, 0, 120), Color(0, 0, 0, 125), Color(0, 0, 0, 45), Color(44, 44, 46)
	local function Size49(b)
		if b >= 1048576 then return string.format("%.1f МБ", b / 1048576) end
		return math.max(1, math.ceil(b / 1024)) .. " КБ"
	end
	local function Pair49(got, total) -- fix61: "37% · 1.2 МБ" (acknowledged bytes, not a guess)
		return math.Clamp(math.floor(100 * got / math.max(1, total)), 0, 100) .. "% · " .. Size49(total)
	end
	local function Dur49(sec)
		sec = math.max(0, math.floor((sec or 0) + 0.5))
		return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
	end
	M49.Size, M49.Pair, M49.Dur = Size49, Pair49, Dur49
	local function Pill(x, y, text)
		surface.SetFont("STTS_I_Cap")
		local tw = surface.GetTextSize(text)
		Round(13, x, y, tw + 20, 26, PILL)
		T(text, "STTS_I_Cap", x + 10, y + 13, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	-- the round button: "dl" arrow, "load" turning progress ring + cross, "play", "err"
	local function Ring(cx, cy, r, kind, p)
		Circle(cx, cy, r, DISC)
		local th = math.max(2.5, r * 0.1)
		if kind == "dl" then
			Line(cx, cy - r * 0.42, cx, cy + r * 0.3, th, WHITE)
			Chevron(cx, cy + r * 0.36, r * 0.3, "down", WHITE, th)
		elseif kind == "load" then
			local a0 = (RealTime() * 280) % 360 - 90 -- the ring turns while it fills
			local sweep = p and math.Clamp(p, 0.04, 1) * 360 or 90 -- no size yet: a turning quarter
			Arc(cx, cy, r - th * 0.7, th, a0, a0 + sweep, WHITE, math.max(6, math.ceil(sweep / 9)))
			local d = r * 0.24
			Line(cx - d, cy - d, cx + d, cy + d, th, WHITE)
			Line(cx - d, cy + d, cx + d, cy - d, th, WHITE)
		elseif kind == "play" then
			GPlay(cx + r * 0.1, cy, r * 0.46, WHITE)
		elseif kind == "err" then
			Line(cx, cy - r * 0.42, cx, cy + r * 0.1, th, WHITE)
			Circle(cx, cy + r * 0.36, th * 0.75, WHITE)
		end
	end
	M49.Ring, M49.Pill = Ring, Pill
	local function Frac(got, total) if total > 0 and got > 0 then return got / total end end
	-- blurred tiny preview, cover-cropped into x, y, w, h (or a dark placeholder)
	function M49.DrawBack(id, x, y, w, h)
		local inf = M49.info[id]
		local m = inf and inf.prev
		if not m then R(x, y, w, h, PLACE) return false end
		local pw, ph = inf.pw or 9, inf.ph or 16
		local u0, v0, u1, v1 = 0, 0, 1, 1
		local ar, tr = pw / ph, w / h
		if ar > tr then u0 = (1 - tr / ar) / 2 u1 = 1 - u0 else v0 = (1 - ar / tr) / 2 v1 = 1 - v0 end
		surface.SetMaterial(m)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
		-- four shifted copies over the stretched 36 x 64 pixels = Telegram's soft blur
		local du, dv = (u1 - u0) * 0.04, (v1 - v0) * 0.04
		surface.SetDrawColor(255, 255, 255, 64)
		surface.DrawTexturedRectUV(x, y, w, h, u0 + du, v0, u1 + du, v1)
		surface.DrawTexturedRectUV(x, y, w, h, u0 - du, v0, u1 - du, v1)
		surface.DrawTexturedRectUV(x, y, w, h, u0, v0 + dv, u1, v1 + dv)
		surface.DrawTexturedRectUV(x, y, w, h, u0, v0 - dv, u1, v1 - dv)
		R(x, y, w, h, SHADE)
		return true
	end
	-- TeleChat bubble picture (instead of Thumb)
	function M49.Bubble(wep, st, id, x, y, s)
		if not st.own or not id or id <= 0 or M49.Have(st, id) then Thumb(st, id, x, y, s, true) return end
		M49.Info(id)
		M49.DrawBack(id, x, y, s, s)
	end
	-- ... and what lies over it (after the rounded corners)
	function M49.BubbleOver(wep, st, id, x, y, s, me, peer)
		if not id then return end
		local cx, cy, r = x + s / 2, y + s / 2, math.max(18, s * 0.12)
		if id < 0 then -- your own clip still on its way to the server
			if not st.own then return end
			local P = Gal()
			local it = P and P.Get(id)
			local rec = it and it.record
			if not rec then return end
			-- fix61: the real stage + percentage (it was a spinner without numbers until the upload began)
			local text, f, bad = "Отправка", nil, rec.mediaError ~= nil
			if P.SendState61 then text, f, bad = P.SendState61(rec) end
			if bad then Ring(cx, cy, r, "err") Pill(x + 8, y + 8, "Не отправлено") return end
			Ring(cx, cy, r, "load", f and math.max(f, 0.001) or nil)
			local pct = f and math.Clamp(math.floor(f * 100), 0, 100) .. "%"
			if pct and text == "Отправка" and (rec.totalBytes or 0) > 0 then Pill(x + 8, y + 8, pct .. " · " .. Size49(rec.totalBytes))
			else Pill(x + 8, y + 8, pct and text .. " " .. pct or text) end
			return
		end
		if not st.own or M49.Have(st, id) then
			if IsVideo(st, id) then
				Ring(cx, cy, r, "play")
				local d = st.own and M49.Duration(st, id)
				if d then Pill(x + 8, y + 8, Dur49(d)) end
			end
			return
		end
		local inf = M49.info[id]
		if M49.want[id] then
			local got, total = M49.Progress(st, id)
			Ring(cx, cy, r, "load", Frac(got, total))
			if total > 0 then Pill(x + 8, y + 8, Pair49(got, total)) end
		else
			Ring(cx, cy, r, "dl")
			if inf then
				local txt = Size49(inf.bytes)
				if inf.kind > 0 and inf.dur > 0 then txt = Dur49(inf.dur) .. " · " .. txt end
				Pill(x + 8, y + 8, txt)
			end
		end
	end
	-- tap on a bubble: true = handled here (download / cancel), false = open it
	function M49.Tap(wep, st, id, peer)
		if not st.own or not id then return false end
		if id < 0 then
			if id <= PEND0 then return false end
			local P = Gal()
			if P and P.CancelShare49 then P.CancelShare49(id, peer) end -- cancel sending, the clip stays in Photos
			return true
		end
		if M49.Have(st, id) then return false end
		if M49.want[id] then M49.Cancel(st, id) else M49.Start(st, id) end
		return true
	end
	-- grids (Photos, attach sheet): received item not downloaded yet
	function M49.ThumbLocked(st, id, x, y, size)
		if not st.own or not id or id <= 0 or not M49.manual[id] or M49.Have(st, id) then return false end
		M49.Info(id)
		M49.DrawBack(id, x, y, size, size)
		if size >= 40 then
			local r = math.max(11, size * 0.15)
			if M49.want[id] then
				local got, total = M49.Progress(st, id)
				Ring(x + size / 2, y + size / 2, r, "load", Frac(got, total))
			else
				Ring(x + size / 2, y + size / 2, r, "dl")
			end
		end
		return true
	end
	-- full screen picture still downloading
	function M49.ViewerOverlay(st, id, x, y, w, h)
		if not st.own or not id or id <= 0 or not M49.manual[id] or M49.Have(st, id) then return end
		M49.Info(id)
		M49.DrawBack(id, x, y, w, h)
		local got, total = M49.Progress(st, id)
		Ring(x + w / 2, y + h / 2, 34, M49.want[id] and "load" or "dl", Frac(got, total))
		if total > 0 then T(M49.want[id] and Pair49(got, total) or Size49(total), "STTS_I_Cap", x + w / 2, y + h / 2 + 58, WHITE) end
	end
end

--[[ fix55: a shot without a freeze. the frame of the shot only renders the camera and
     copies the picture into a free slot (GPU, + a 2-step downscaled thumbnail); the
     jpg is read back one frame later; the pending photo (and later its real id) draws
     the slot itself, nothing is loaded back from the disk. 3 portrait + 3 landscape
     slots, the oldest one is reused (its photo then comes from the disk again) ]]
do
	local S = {pool = {}, q = {}}
	SCR.Shot55 = S
	local FLAGS = 4 + 8 -- clamp s / t
	local function Mat(name, rt)
		return CreateMaterial(name, "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$ignorez"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1})
	end
	local half = {}
	local function Half(land)
		local k = land and "l" or "p"
		if not half[k] then
			local w, h = land and G.PhotoH / 2 or G.PhotoW / 2, land and G.PhotoW / 2 or G.PhotoH / 2
			local rt = GetRenderTargetEx("stts55_half_" .. k, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, FLAGS, 0, IMAGE_FORMAT_RGB888)
			half[k] = {rt = rt, mat = Mat("stts55_halfm_" .. k, rt), w = w, h = h}
		end
		return half[k]
	end
	local function Slot(land)
		local list = S.pool[land and "l" or "p"]
		if not list then list = {} S.pool[land and "l" or "p"] = list end
		local best
		for i = 1, 3 do
			local sl = list[i]
			if not sl then
				local k = (land and "l" or "p") .. i
				local w, h = land and G.PhotoH or G.PhotoW, land and G.PhotoW or G.PhotoH
				local tw, th = math.floor(w / 4), math.floor(h / 4)
				local rt = GetRenderTargetEx("stts55_shot_" .. k, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, FLAGS, 0, IMAGE_FORMAT_RGB888)
				local trt = GetRenderTargetEx("stts55_thumb_" .. k, tw, th, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, FLAGS, 0, IMAGE_FORMAT_RGB888)
				sl = {rt = rt, mat = Mat("stts55_shotm_" .. k, rt), trt = trt, tmat = Mat("stts55_thumbm_" .. k, trt), w = w, h = h, tw = tw, th = th, land = land, used = 0}
				list[i] = sl
				return sl
			end
			if not best or sl.used < best.used then best = sl end
		end
		return best
	end
	-- the slot goes to a new picture: whoever showed the old one loads it from the disk
	local function Free(sl)
		local o = sl.owner
		sl.owner, sl.ownerId = nil, nil
		if o and o.slot == sl then o.mat, o.tmat, o.slot = nil, nil, nil end
		if sl.id and mats[sl.id] and mats[sl.id].slot == sl then mats[sl.id] = nil end
		sl.id = nil
	end
	local function Blit(mat, x, y, w, h, verts)
		surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
		if verts then surface.DrawPoly(verts) else surface.DrawTexturedRect(x, y, w, h) end
	end
	-- right after RenderCam (photoRT popped): copy the picture into a slot
	function S.Grab(land, verts)
		local src = SCR.PhotoSrcMat
		if not src then return end
		local sl = Slot(land)
		Free(sl)
		sl.used = RealTime()
		render.PushRenderTarget(sl.rt)
			render.Clear(0, 0, 0, 255)
			cam.Start2D() Blit(src, 0, 0, sl.w, sl.h, land and verts or nil) cam.End2D()
		render.PopRenderTarget()
		local hf = Half(land) -- 2 bilinear halvings = a clean small picture (no mips on an RT)
		render.PushRenderTarget(hf.rt)
			cam.Start2D() Blit(sl.mat, 0, 0, hf.w, hf.h) cam.End2D()
		render.PopRenderTarget()
		render.PushRenderTarget(sl.trt)
			cam.Start2D() Blit(hf.mat, 0, 0, sl.tw, sl.th) cam.End2D()
		render.PopRenderTarget()
		sl.fresh = true
		return sl
	end
	function S.Own(sl, p)
		if not sl.fresh then return false end
		sl.fresh, sl.owner = nil, p
		return true
	end
	-- the server saved it: the real id keeps showing the slot
	function S.ToId(p, id)
		local sl = p.slot
		if not sl or sl.owner ~= p then return end
		sl.id = id
		mats[id] = {mat = sl.mat, tmat = sl.tmat, key = GetGlobalInt("STTS_PhotoRound", 1) .. ":" .. id, w = sl.w, h = sl.h, slot = sl}
	end
	function S.ThumbMat(id)
		if not id then return end
		if id <= -1000000 then return SCR.M49 and SCR.M49.PendThumb(id) end
		local e = mats[id]
		return e and e.slot and e.slot.id == id and e.key == GetGlobalInt("STTS_PhotoRound", 1) .. ":" .. id and e.tmat or nil
	end
	function S.Reset()
		for _, list in pairs(S.pool) do
			for _, sl in ipairs(list) do sl.owner, sl.id, sl.fresh = nil, nil, nil end
		end
		S.q = {}
	end
	-- PostRender: a shot of an earlier frame -> jpg -> upload (one per frame)
	function S.Step()
		local j = S.q[1]
		if not j or j.frame >= FrameNumber() then return end
		table.remove(S.q, 1)
		local sl = j.slot
		if not sl.fresh or not IsValid(j.wep) then sl.fresh = nil return end
		render.PushRenderTarget(sl.rt)
			local jpg = render.Capture({format = "jpg", quality = 88, x = 0, y = 0, w = sl.w, h = sl.h, alpha = false})
		render.PopRenderTarget()
		if jpg and #jpg > 0 then Upload(j.wep, jpg, nil, nil, nil, nil, sl) else sl.fresh = nil end
	end
	function S.Queue(wep, sl) S.q[#S.q + 1] = {wep = wep, slot = sl, frame = FrameNumber()} end
	--[[ fix66: a slot that turns black (its render target lost / overwritten) is let go: the
	     photo then comes from its jpg on the disk (good since fix66). checked a few times
	     during the first 20 s after the shot, one check per frame at most ]]
	S.w66 = {}
	local CHECKS = {0.25, 1, 3, 8, 20}
	local function Peak(rt, w, h)
		local peak = 0
		render.PushRenderTarget(rt)
		local ok = pcall(render.CapturePixels)
		if ok then
			for i = 0, 5 do
				for j = 0, 9 do
					local r, g, b = render.ReadPixel(math.floor((i + 0.5) * w / 6), math.floor((j + 0.5) * h / 10))
					peak = math.max(peak, r or 0, g or 0, b or 0)
				end
				if peak > 6 then break end
			end
		end
		render.PopRenderTarget()
		return ok and peak or nil
	end
	function S.Watch66(sl, bytes)
		S.w66[#S.w66 + 1] = {sl = sl, at = RealTime(), n = 1, bytes = bytes, owner = sl.owner}
	end
	function S.WatchStep66()
		local now = RealTime()
		for i, w in ipairs(S.w66) do
			local sl = w.sl
			if sl.owner ~= w.owner or not w.owner then table.remove(S.w66, i) return end -- reused
			if now - w.at >= CHECKS[w.n] then
				w.n = w.n + 1
				local pk = Peak(sl.trt, sl.tw, sl.th)
				local pkFull = pk and pk <= 6 and Peak(sl.rt, sl.w, sl.h) or pk
				if pkFull and pkFull <= 6 and w.bytes >= 11000 then
					MsgC(Color(255, 180, 80), "[ZPHONE] ", color_white, string.format("photo slot went black %.2f s after the shot -> the photo is read from the disk\n", now - w.at))
					Free(sl)
					table.remove(S.w66, i)
				elseif not CHECKS[w.n] then
					table.remove(S.w66, i)
				end
				return
			end
		end
	end
end

--[[ fix17: smooth scrolling draws rows that are only partly inside their area:
     Clip() cuts the drawing to a rectangle (follows Scaled() of the transitions)
     fix18: defined BEFORE List() (it was below it = global nil at line 1046) ]]
local function Clip(x, y, w, h)
	local xf = SCR.XF
	if xf then x, y, w, h = xf.x + x * xf.s, xf.y + y * xf.s, w * xf.s, h * xf.s end
	render.SetScissorRect(math.floor(x), math.floor(y), math.ceil(x + w), math.ceil(y + h), true)
end
local function Unclip() render.SetScissorRect(0, 0, 0, 0, false) end

--[[ iOS list: avatar, name, second line (number / last message), time, unread dot ]]
local function List(btns, wep, st, list, onPick, top, opts)
	opts = opts or {}
	local rowH = opts.rowH or 84
	local bottom = opts.bottom or (H - 44)
	local visible = math.max(1, math.floor((bottom - top) / rowH))
	-- fix17: smooth: scroll is in rows (fractional), the last row ends exactly at the bottom
	local maxScroll = math.max(0, #list - (bottom - top) / rowH)
	if st.own then L.maxScroll = maxScroll end
	local s = math.Clamp(st.scroll, -1, maxScroll + 1) -- a bit past the ends = rubber band
	local first = math.floor(s)
	local off = (s - first) * rowH
	local two = opts.twoLine
	local ar = two and 31 or 27
	local ax = two and 66 or 54
	local tx = ax + ar + 18
	Clip(0, top, W, bottom - top)
	for i = 1, visible + 2 do
		local idx = first + i
		if idx > #list then break end
		local c = list[idx]
		local y = top + (i - 1) * rowH - off
		if not c or y >= bottom then continue end
		local id = 100 + math.min(idx, 99) -- the id stays with the row while it slides
		local y0, y1 = math.max(y, top), math.min(y + rowH, bottom)
		if y1 - y0 > 10 then Reg(btns, id, 0, y0, W, y1 - y0, function() onPick(c) end) end
		local k = HoverK(wep, id, st.sel == id)
		if k > 0.01 then R(0, y, W, rowH, SCR.Ink((Pressed(wep, st, id) and 50 or 24) * k)) end
		Avatar(c.name, c.num, ax, y + rowH / 2, ar)
		if two then
			if (c.badge or 0) > 0 then Circle(17, y + rowH / 2, 7, C.blue) end
			local tw = 0
			if (c.at or 0) > 0 then
				local ts = os.date("%H:%M", c.at)
				surface.SetFont("STTS_I_Sub")
				tw = surface.GetTextSize(ts) + 14
				T(ts, "STTS_I_Sub", W - 22, y + 30, C.label2, TEXT_ALIGN_RIGHT)
			end
			T(Fit(c.name, "STTS_I_BodyB", W - tx - 22 - tw), "STTS_I_BodyB", tx, y + 30, C.label, TEXT_ALIGN_LEFT)
			T(Fit(c.sub or c.num, "STTS_I_Sub", W - tx - 26), "STTS_I_Sub", tx, y + 64, C.label2, TEXT_ALIGN_LEFT)
		else
			if opts.dot and (c.badge or 0) > 0 then Circle(W - 30, y + rowH / 2, 8, C.blue) end
			local sub = opts.showNum and c.num ~= "911" and c.num or nil
			T(Fit(c.name, "STTS_I_Body", W - tx - 24), "STTS_I_Body", tx, y + rowH / 2 - (sub and 13 or 0), C.label, TEXT_ALIGN_LEFT)
			if sub then T(Fit(sub, "STTS_I_Sub", W - tx - 24), "STTS_I_Sub", tx, y + rowH / 2 + 17, C.label2, TEXT_ALIGN_LEFT) end
		end
		if list[idx + 1] then R(tx, y + rowH - 1, W - tx, 1, C.sep) end
	end
	Unclip()
	local barA = maxScroll > 0 and SCR.UI.BarA(wep, st) or 0
	if barA > 0.01 then -- scroll indicator (fades out when the list stops, like iOS)
		local area = bottom - top
		local bh = math.max(30, area * visible / #list)
		Round(3, W - 8, top + (area - bh) * math.Clamp(s / maxScroll, 0, 1), 5, bh, SCR.Ink(90 * barA))
	end
	if #list == 0 then T(opts.empty or "No Contacts", "STTS_I_Body", W / 2, top + 150, C.label2) end
	Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = rowH})
end

-- camera zoom: a thin track + knob, the finger drags it (LMB held). no labels
--[[ fix61: smooth zoom. the finger only sets the target (L.zoomT), the lens glides to it
     (exponential, in log space: 1x -> 2x takes as long as 2x -> 4x), the track is
     logarithmic too (it was linear: the first centimetre jumped from 1x to 2x) ]]
function SCR.SetZoom(z)
	z = math.Clamp(z, 1, G.ZoomMax)
	if math.abs(z - (L.zoomT or L.zoom or 1)) < 0.005 then return end
	if not L.zoomT then L.zoomStepAt = RealTime() end
	L.zoomT, L.zoomDirty = z, true
end
hook.Add("Think", "STTS_PhoneZoom61", function()
	local t = L.zoomT
	if not t then return end
	local now, z = RealTime(), L.zoom or 1
	local dt = math.Clamp(now - (L.zoomStepAt or now), 0, 0.1)
	L.zoomStepAt = now
	if math.abs(t - z) < 0.003 then L.zoom, L.zoomT = t, nil return end
	L.zoom = math.exp(Lerp(1 - math.exp(-dt * 9), math.log(math.max(z, 1)), math.log(t)))
end)
local ZLOG = math.log(G.ZoomMax)
local function ZoomSlider(btns, wep, st, id, x, y, w)
	local z = st.own and (L.zoomT or L.zoom) or st.zoom or 1
	local u = math.Clamp(math.log(math.max(1, z)) / ZLOG, 0, 1) -- the knob shows where the finger put it
	local b = Reg(btns, id, x - 18, y - 28, w + 36, 56, nil)
	b.sx, b.sw = x, w
	b.slider = function(v) if st.own then SCR.SetZoom(math.exp(math.Clamp(v, 0, 1) * ZLOG)) end end
	local k = HoverK(wep, id, st.sel == id)
	Round(2, x, y - 2, w, 4, Color(255, 255, 255, 70 + 40 * k))
	if u > 0 then Round(2, x, y - 2, w * u, 4, C.yellow) end
	Circle(x + w * u, y, 11 + 4 * k, WHITE)
end

-- what the shade (cl_shooting_phone_shade.lua) draws with (one table: this chunk is near the 200 locals limit)
SCR.UI = {R = R, T = T, Round = Round, Circle = Circle, Line = Line, Reg = Reg, HoverK = HoverK, PopScale = PopScale,
	Pressed = Pressed, Colored = Colored, Act = Act, C = C, icons = appIcons, W = W, H = H, IconHi = IconHi}
-- theme-aware tint for hover / scroll indicators: white on dark, black on light (C.ink, cl_shooting_phone_settings.lua)
function SCR.Ink(a)
	local c = C.ink or WHITE
	return Color(c.r, c.g, c.b, a * (c.a or 255) / 255)
end

local APPS = {}
-- Settings app (cl_shooting_phone_settings.lua) draws with these
SCR.APPS = APPS
SCR.UI.SetApp, SCR.UI.NavBack, SCR.UI.LargeTitle, SCR.UI.InlineTitle, SCR.UI.Fit = SetApp, NavBack, LargeTitle, InlineTitle, Fit
SCR.UI.Avatar, SCR.UI.Chevron, SCR.UI.Clip, SCR.UI.Unclip, SCR.UI.Zone, SCR.UI.Tri = Avatar, Chevron, Clip, Unclip, Zone, Tri
SCR.UI.VGrad, SCR.UI.Arc, SCR.UI.LinCol = VGrad, Arc, LinCol
-- rounded-rectangle outline (hairline rim): four thin bars + corner arcs. th in px.
-- used for the Control Centre glass edge, which the engine blur alone does not give.
function SCR.UI.RoundRim(r, x, y, w, h, th, col)
	if w <= 0 or h <= 0 then return end
	r = math.max(0, math.min(r, w / 2, h / 2))
	th = th or 1.5
	R(x + r, y, w - 2 * r, th, col)                 -- top
	R(x + r, y + h - th, w - 2 * r, th, col)         -- bottom
	R(x, y + r, th, h - 2 * r, col)                  -- left
	R(x + w - th, y + r, th, h - 2 * r, col)         -- right
	if r > 0 then
		Arc(x + r, y + r, r, th, 180, 270, col, 8)
		Arc(x + w - r, y + r, r, th, 270, 360, col, 8)
		Arc(x + w - r, y + h - r, r, th, 0, 90, col, 8)
		Arc(x + r, y + h - r, r, th, 90, 180, col, 8)
	end
end
-- circle outline (hairline rim)
function SCR.UI.CircleRim(x, y, r, th, col)
	Arc(x, y, r, th or 1.5, 0, 360, col, 40)
end
-- iOS scroll indicator: shows while the content moves, fades out ~0.6 s after it stops
function SCR.UI.BarA(wep, st)
	local s = st.scroll or 0
	-- a screen that just opened starts at the top: that is not scrolling (no flash of the bar)
	if wep.STTS_BarApp ~= st.app then wep.STTS_BarApp, wep.STTS_BarS = st.app, s end
	if wep.STTS_BarS == nil or math.abs(wep.STTS_BarS - s) > 0.0005 then wep.STTS_BarS, wep.STTS_BarAt = s, RealTime() end
	return math.Clamp(1 - (RealTime() - (wep.STTS_BarAt or -10) - 0.6) / 0.3, 0, 1)
end
-- per phone damped spring 0 -> 1 (switches, toggles): iOS response / damping, slight settle
function SCR.UI.SpringK(wep, id, on, response, damping)
	local t = wep.STTS_SK or {}
	wep.STTS_SK = t
	local s = t[id]
	local goal = on and 1 or 0
	if not s then s = {x = goal, v = 0} t[id] = s end
	local dt = wep.STTS_UIdt or 0
	local w = 2 * math.pi / (response or 0.32)
	local z = damping or 0.78
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		s.v = s.v + (w * w * (goal - s.x) - 2 * z * w * s.v) * h
		s.x = s.x + s.v * h
	end
	if math.abs(s.x - goal) < 0.001 and math.abs(s.v) < 0.01 then s.x, s.v = goal, 0 end
	return s.x
end

--[[ home screen (fix7): plain black, just the 4 app icons. no wallpaper, clock, widgets ]]
APPS[G.APP_HOME] = function(wep, st, btns)
	local unread = (st.own and SCR.TCUnread and SCR.TCUnread(st.num)) or st.unread or 0
	if SCR.NoBadge and SCR.NoBadge(wep) then unread = 0 end -- Settings: badges off
	-- dock: Phone, TeleChat, Camera, Photos (real app icons, iOS squircle baked into the png)
	local dh, dy = 118, H - 168
	local size = 84
	local gap = (W - 28 - size * 4) / 5
	local items = {
		{1, G.APP_CONTACTS, appIcons.phone, Color(48, 132, 246)},
		{4, G.APP_CHATS, appIcons.chat, Color(52, 199, 89)},
		{2, G.APP_CAMERA, appIcons.camera, Color(150, 150, 156)},
		{3, G.APP_GALLERY, appIcons.gallery, Color(250, 250, 250)},
	}
	wep.STTS_IconRect = wep.STTS_IconRect or {}
	local lifted = wep.STTS_HideIcon -- the app window took this icon off the home screen (open / close)
	for i, it in ipairs(items) do
		local x, y = 14 + gap + (i - 1) * (size + gap), dy + (dh - size) / 2
		wep.STTS_IconRect[it[2]] = {x = x, y = y, w = size, h = size}
		Reg(btns, it[1], x, y, size, size, function() wep.STTS_OpenFrom = nil SetApp(st, it[2]) end)
		local hi = IconHi(wep, st, it[1])
		local sz, ix, iy = size, x, y
		if lifted == it[2] then
			-- drawn by the transition (the app window), not here
		elseif not it[3]:IsError() then
			surface.SetMaterial(it[3]) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(ix, iy, sz, sz)
			if hi > 0 then surface.SetDrawColor(0, 0, 0, 92 * hi) surface.DrawTexturedRect(ix, iy, sz, sz) end
		else -- content not mounted yet: a rounded tile in the app colour
			Round(sz * 0.23, ix, iy, sz, sz, it[4])
			if hi > 0 then Round(sz * 0.23, ix, iy, sz, sz, Color(0, 0, 0, 92 * hi)) end
		end
		if it[1] == 4 and unread > 0 and lifted ~= it[2] then -- red badge
			local txt = unread > 99 and "99+" or tostring(unread)
			surface.SetFont("STTS_I_Cap")
			local bw = math.max(34, surface.GetTextSize(txt) + 18)
			Round(17, ix + sz - bw / 2 - 4, iy - 10, bw, 34, C.red)
			T(txt, "STTS_I_Cap", ix + sz - 4, iy + 7, C.label)
		end
	end
end

APPS[G.APP_CONTACTS] = function(wep, st, btns)
	NavBack(btns, wep, st, nil, function() SetApp(st, G.APP_HOME) end)
	LargeTitle("Contacts", 134)
	List(btns, wep, st, Contacts(st), function(c)
		if st.plane then L.toast, L.toastAt = "Airplane mode", RealTime() return end -- fix17
		Act("dial", c.num)
	end, 180)
end

--[[ call screen ]]
local function CallBg()
	R(0, 0, W, H, Color(14, 14, 16))
end

APPS[G.APP_CALL] = function(wep, st, btns)
	local peer = st.call == G.CALL_ON and st.peerVid and st.peerIdx > 0
	local mine = st.vid and st.call == G.CALL_ON
	local video = peer or mine
	--[[ your own camera: full screen while only you show video, then it slides
	     smoothly into the top right corner once the other side turns its camera
	     on (and grows back if they turn it off) ]]
	local dt = wep.STTS_UIdt or 0
	local want = peer and 1 or 0
	wep.STTS_PipK = wep.STTS_PipK and Lerp(1 - math.exp(-dt * 6), wep.STTS_PipK, want) or want
	if math.abs(wep.STTS_PipK - want) < 0.002 then wep.STTS_PipK = want end
	local k = wep.STTS_PipK
	local e = k * k * (3 - 2 * k)
	if video then R(0, 0, W, H, BLACK) else CallBg() end
	if peer then
		local mat = WantFeed(st.peerIdx, st.peerBack, st.own and 20 or 8)
		if st.peerPocket then R(0, 0, W, H, BLACK) else DrawFeedFull(mat, 0, 0, W, H) end -- in a pocket: just black
	end
	if mine then
		local mat = WantFeed(wep:EntIndex(), not st.front, st.own and (e < 0.5 and 24 or 15) or 5)
		local pw, ph = 126, 224
		local x, y = Lerp(e, 0, W - pw - 18), Lerp(e, 0, 120)
		local w, h = Lerp(e, W, pw), Lerp(e, H, ph)
		DrawFeedFull(mat, x, y, w, h)
	end
	if video then
	end
	local name = st.callName ~= "" and st.callName or "Unknown"
	local status = st.call == G.CALL_ON and string.FormattedTime(math.max(0, CurTime() - st.since), "%02i:%02i")
		or (st.call == G.CALL_IN and "Incoming call" or "calling...")
	if video then
		T(Fit(name, "STTS_I_Nav", W - ((mine and peer) and 190 or 48)), "STTS_I_Nav", 24, 92, C.label, TEXT_ALIGN_LEFT)
		T(status, "STTS_I_Sub", 24, 124, C.label2, TEXT_ALIGN_LEFT)
	else
		Avatar(name, nil, W / 2, 220, 72)
		T(Fit(name, "STTS_I_CallName", W - 40), "STTS_I_CallName", W / 2, 346, C.label)
		T(status, "STTS_I_CallSub", W / 2, 398, C.label2)
	end

	local by = H - 176
	if st.call == G.CALL_IN then
		Colored(RoundBtn, btns, wep, st, 21, W * 0.25, by, 42, C.red, function(x, y, r) GHandset(x, y, r, C.label, true) end, nil, function() Act("hangup") end)
		Colored(RoundBtn, btns, wep, st, 20, W * 0.75, by, 42, C.green, function(x, y, r) GHandset(x, y, r, C.label) end, nil, function() Act("answer") end)
		return
	end
	-- fix12: 911 too, the operator sees the caller's camera in his console
	if st.call == G.CALL_ON then
		local ry = H - 346
		local function Vid() L.vid, L.vidAt = not st.vid, RealTime() Act("video") end
		local function Flip() L.front, L.camAt = not st.front, RealTime() Act("camflip") end
		local dim = Color(255, 255, 255, 52)
		if st.vid then
			ZoomSlider(btns, wep, st, 24, 70, ry - 86, W - 140)
			RoundBtn(btns, wep, st, 22, W / 2 - 74, ry, 40, C.label, function(x, y, r) GVideo(x, y, r, BLACK) end, nil, Vid)
			RoundBtn(btns, wep, st, 23, W / 2 + 74, ry, 40, dim, function(x, y, r) GFlip(x, y, r, C.label) end, nil, Flip)
		else
			RoundBtn(btns, wep, st, 22, W / 2, ry, 40, dim, function(x, y, r) GVideo(x, y, r, C.label) end, nil, Vid)
		end
	end
	Colored(RoundBtn, btns, wep, st, 21, W / 2, by, 42, C.red, function(x, y, r) GHandset(x, y, r, C.label, true) end, nil, function() Act("hangup") end)
end

--[[ camera: black bars, viewfinder, shutter, last photo / video, flip,
     zoom slider, photo / video toggle (top right, shows the other mode).
     video: red shutter, tap = record / stop, red ring = how much is left ]]
local function GCam(x, y, r, col)
	local w, h = r * 0.78, r * 0.56
	Round(6, x - w / 2, y - h / 2 + 2, w, h, col)
	Round(3, x - w * 0.18, y - h / 2 - 4, w * 0.36, 8, col)
	Circle(x, y + 2, h * 0.3, BLACK)
	Circle(x, y + 2, h * 0.19, col)
end
local REC_MAX = G.VidFps * (G.VidMaxSec or 120) -- fix15: 2 minutes
-- fix15: somebody else's recording keeps running on this phone (it fell out of his hands
-- while recording): whoever holds it now sees the red shutter and can stop it
local function RemoteRec(wep)
	if wep:GetNW2Int("CamMode", 0) ~= 2 then return false end
	local by = wep:GetNW2Entity("RecBy", NULL)
	return IsValid(by) and by ~= LocalPlayer()
end
SCR.RemoteRec = RemoteRec
-- fix17: seconds since the last flash photo of this phone (own: predicted) + front / rear
function SCR.ShotAge(wep, st)
	if st and st.own and L.shotAt and L.shotWep == wep then return RealTime() - L.shotAt, L.shotFront end
	return CurTime() - wep:GetNW2Float("ShotAt", -100), wep:GetNW2Bool("ShotFr", false)
end

APPS[G.APP_CAMERA] = function(wep, st, btns)
	local mode = st.camMode or 0
	local recOn = mode == 2
	-- v19.4: held landscape (T) = the icons turn so they stay upright as you see them (iOS),
	-- the layout stays. Spin(cx, cy) ... Unspin() around one icon
	local le = SCR.LandK(wep)
	local function Spin(cx, cy)
		if le <= 0.0005 then return end
		local m = Matrix()
		m:Translate(Vector(cx, cy, 0))
		m:Rotate(Angle(0, -90 * le, 0))
		m:Translate(Vector(-cx, -cy, 0))
		cam.PushModelMatrix(m, true)
	end
	local function Unspin() if le > 0.0005 then cam.PopModelMatrix() end end
	-- fix68: the front lens shows a true (not mirrored) picture: on the turned phone it stood on
	-- its head (the turn of the phone counts twice for it). turned half way = drawn the other way up
	SCR.FeedFlip68 = st.front and le >= 0.5
	DrawFeedFull(WantFeed(wep:EntIndex(), not st.front, (st.own and L.raised) and ((mode > 0) and G.RecFps() or 30) or 8), 0, 0, W, H)
	SCR.FeedFlip68 = nil
	R(0, 0, W, 108, BLACK)
	R(0, H - 252, W, 252, BLACK)
	NavBack(btns, wep, st, nil, function() SetApp(st, G.APP_HOME) end, C.label)

	-- shutter blink (iOS goes black for a moment)
	-- fix53: shorter than the 0.2 s between two shots, so every shot blinks on its own
	local blink = math.min(0.22, G.PhotoCooldown * 0.8)
	if st.own and L.lastShot and RealTime() - L.lastShot < blink and not st.camFlash then
		R(0, 108, W, H - 360, Color(0, 0, 0, 255 * (1 - (RealTime() - L.lastShot) / blink)))
	end
	-- fix27: the phone display no longer turns white with the flash (front photo flash
	-- and the white ring of the front video light are gone). the light on the face
	-- (dynamic light from the display, cl_shooting_phone_shade.lua) and the rear LED stay.
	-- recording: blinking red dot on top
	if recOn and math.floor(RealTime() * 2) % 2 == 0 then Colored(Circle, W / 2, 78, 9, C.red) end
	-- flash on / off (photo + video, front + rear)
	do
		Reg(btns, 36, 92, 44, 72, 68, function()
			if not st.own then return end
			L.camFl, L.camFlAt = not st.camFlash, RealTime()
			Act("camflash")
		end)
		local fk = HoverK(wep, 36, st.sel == 36)
		if fk > 0.01 then Circle(128, 78, 30, Color(255, 255, 255, 30 * fk)) end
		local fs = 40 * PopScale(wep, "flash", false, Pressed(wep, st, 36))
		local fcol = st.camFlash and C.yellow or C.label
		local fm = appIcons.flash
		Spin(128, 78)
		if not fm:IsError() then
			surface.SetMaterial(fm) surface.SetDrawColor(fcol)
			surface.DrawTexturedRect(128 - fs / 2, 78 - fs / 2, fs, fs)
		else -- content not mounted yet: a bolt from triangles
			Tri(128 + 4, 78 - 18, 128 - 9, 78 + 3, 128 + 1, 78 + 3, fcol)
			Tri(128 - 1, 78 - 3, 128 + 9, 78 - 3, 128 - 4, 78 + 18, fcol)
		end
		if not st.camFlash then Line(128 - 15, 78 - 15, 128 + 15, 78 + 15, 3.5, C.label) end
		Unspin()
	end
	-- photo / video toggle
	if not recOn then
		Reg(btns, 35, W - 92, 44, 72, 68, function()
			if not st.own then return end
			L.camMode = L.camMode == 1 and 0 or 1
			Act("cam", tostring(L.camMode))
		end)
		local k = HoverK(wep, 35, st.sel == 35)
		if k > 0.01 then Circle(W - 56, 78, 30, Color(255, 255, 255, 30 * k)) end
		local col = Pressed(wep, st, 35) and Color(255, 255, 255, 120) or C.label
		-- the record-video icon is red (fix15)
		Spin(W - 56, 78)
		if mode == 1 then GCam(W - 56, 78, 34, col) else Colored(GVideo, videoMat:IsError() and W - 50 or W - 56, 78, 40, Pressed(wep, st, 35) and Color(255, 69, 58, 120) or C.red) end
		Unspin()
	end

	-- fix30: digital EIS settings, local recorder (not a physical camera gimbal).
	if mode > 0 and st.own and STTS.PhoneEIS then
		Reg(btns, 139, W - 204, 44, 104, 68, function()
			local m = (STTS.PhoneEIS.Mode(wep) + 1) % 3
			STTS.PhoneEIS.Predict(wep,m);Act("eis",tostring(m))
			-- mode is already visible on the button; no toast
		end)
		local m = STTS.PhoneEIS.Mode(wep)
		T("EIS " .. (m == 0 and "OFF" or tostring(m)), "STTS_TC_Entry", W - 152, 78, m > 0 and C.yellow or C.label)
	end

	local cx, cy = W / 2, H - 130
	Reg(btns, 30, cx - 48, cy - 48, 96, 96, function()
		if not st.own then return end
		-- fix15: stop a recording that someone else started on this phone
		if not (L.rec and L.rec.wep == wep) and RemoteRec(wep) then L.camMode = 1 Act("cam", "1") return end
		-- your own recording still runs on another phone (this one was picked up meanwhile).
		-- fix54: it ends there (and is saved on that phone), this one starts filming right after
		local other = L.rec and L.rec.wep ~= wep and not L.rec.closed
		if other and L.camMode == 1 then
			if #st.photos >= G.PhotoMaxPerPhone then L.toast, L.toastAt = "Gallery is full", RealTime() return end
			StopRec(true)
			L.recNext = {wep = wep, front = st.front, at = RealTime()}
			L.toast, L.toastAt = "Saving previous video", RealTime()
			return
		end
		if (L.camMode == 1 or L.rec) and not other then
			if L.rec then StopRec(true) return end
			if #st.photos >= G.PhotoMaxPerPhone then L.toast, L.toastAt = "Gallery is full", RealTime() return end
			SCR.StartRec(wep, st.front)
			return
		end
		if not SCR.Shot and (L.lastShot or 0) + G.PhotoCooldown <= RealTime() then -- fix53: 0.2 s
			if #st.photos >= G.PhotoMaxPerPhone then L.toast, L.toastAt = "Gallery is full", RealTime() return end
			L.lastShot = RealTime()
			-- fix17: with the flash the picture waits until the light is on (LED / white display)
			local fl = st.camFlash
			SCR.Shot = {wep = wep, front = st.front, at = fl and RealTime() + (st.front and 0.14 or 0.1) or nil}
			if fl then
				L.shotAt, L.shotFront, L.shotWep = RealTime(), st.front, wep
				Act("shot", st.front and "1" or "0")
			end
		end
	end)
	local hov = st.sel == 30
	local press = Pressed(wep, st, 30) or (st.own and L.lastShot ~= nil and RealTime() - L.lastShot < 0.15)
	local k = PopScale(wep, "shutter", false, press)
	Arc(cx, cy, 46, 5, 0, 360, C.label, 48)
	if mode == 0 then
		Circle(cx, cy, 37 * k, hov and Color(222, 222, 222) or C.label)
	elseif recOn then
		local done
		if st.own and L.rec and L.rec.wep == wep then done = math.Clamp(L.rec.frames / (L.rec.maxFrames or REC_MAX), 0, 1)
		else done = math.Clamp((CurTime() - wep:GetNW2Float("RecAt", CurTime())) / (G.VidMaxSec or 120), 0, 1) end
		Colored(function()
			if done > 0 then Arc(cx, cy, 46, 5, -90, -90 + 360 * done, C.red, 48) end
			local q = 34 * k
			Round(8, cx - q / 2, cy - q / 2, q, q, C.red)
		end)
	else
		Colored(Circle, cx, cy, 37 * k, hov and Color(220, 50, 42) or C.red)
	end
	-- last photo / video -> opens it
	local ts = 62
	local tx, ty = 40, cy - ts / 2
	local last = st.photos[#st.photos]
	if not recOn then
		Reg(btns, 32, tx, ty, ts, ts, function()
			if #st.photos == 0 then return end
			wep.STTS_ThumbRect = {x = tx, y = ty, w = ts, h = ts}
			wep.STTS_ThumbAt, wep.STTS_ThumbApp, wep.STTS_ThumbRad = RealTime(), G.APP_CAMERA, 10
			SetApp(st, G.APP_GALLERY)
			L.galV, L.album, L.gal = GV_VIEW, 0, #st.photos
		end)
	end
	if last then
		local kt = PopScale(wep, "camthumb", st.sel == 32, Pressed(wep, st, 32))
		local s = ts * kt
		local x, y = tx + (ts - s) / 2, ty + (ts - s) / 2
		Spin(tx + ts / 2, ty + ts / 2)
		Thumb(st, last, x, y, s)
		CornerMask(x, y, s, s, 10, BLACK)
		Unspin()
	else
		Round(10, tx, ty, ts, ts, C.bg2)
	end
	Spin(W - 72, cy)
	RoundBtn(btns, wep, st, 31, W - 72, cy, 31, Color(255, 255, 255, 42), function(x, y, r) GFlip(x, y, r * 1.25, C.label) end, nil, function()
		L.front, L.camAt = not st.front, RealTime() Act("camflip")
	end)
	Unspin()
	ZoomSlider(btns, wep, st, 33, 70, H - 214, W - 140)
end

--[[ Photos like on iOS:
     tab bar "Library" (every picture, newest first, 3 per row, edge to edge)
     and "Albums" (Camera = taken with this phone, Received = sent to it), an
     album opens as the same grid, a picture opens full screen (grows out of
     its thumbnail), < > or a swipe of the finger go to the next one,
     videos play in a loop, toolbar: delete. sending is only in TeleChat
     (the attach button of a conversation).
     views (L.galV): 1 library, 2 albums, 3 album grid, 4 viewer.
     L.gal = index in st.photos, L.album = 0 all / 1 camera / 2 received ]]
local ALBUM_NAME = {[0] = "Library", [1] = "Camera", [2] = "Received"}

-- indices into st.photos that belong to an album (oldest first)
local function AlbumList(st, album)
	local out, recv = {}, {}
	for _, id in ipairs(st.recv or {}) do recv[id] = true end
	for i, id in ipairs(st.photos) do
		if album == 0 or (album == 2) == (recv[id] == true) then out[#out + 1] = i end
	end
	return out
end

local function GalGo(st, view, album)
	if not st.own then return end
	L.galV = view
	if album then L.album = album end
	L.scroll, L.sel = 0, 0
	L.scrollV, L.scrollGo = 0, nil
end

local TABBAR = 104
local function PhotoGrid(btns, wep, st, list, top)
	local gap, cols = 3, 3
	local cell = math.floor((W - gap * (cols - 1)) / cols)
	local rows = math.ceil(#list / cols)
	local bottom = H - TABBAR
	local visible = math.max(1, math.floor((bottom - top) / (cell + gap)))
	local maxScroll = math.max(0, rows - (bottom - top + gap) / (cell + gap)) -- fix17: smooth, in rows
	if st.own then L.maxScroll = maxScroll end
	if #list == 0 then
		T("No Photos", "STTS_I_Nav", W / 2, top + 190, C.label)
		return
	end
	local s = math.Clamp(st.scroll, -1, maxScroll + 1)
	local first = math.floor(s)
	local off = (s - first) * (cell + gap)
	Clip(0, top, W, bottom - top)
	for slot = 1, (visible + 2) * cols do
		local n = first * cols + slot
		local row = math.floor((slot - 1) / cols)
		local y = top + row * (cell + gap) - off
		if y >= bottom then break end
		local gi = n >= 1 and list[#list - n + 1] or nil -- newest first
		if n > #list then break end
		if not gi then continue end
		local col = (slot - 1) % cols
		local x = col * (cell + gap)
		local id = 200 + (n - 1) % 54 + 1 -- stays with the picture while it slides
		local y0, y1 = math.max(y, top), math.min(y + cell, bottom)
		if y1 - y0 > 10 then
			Reg(btns, id, x, y0, cell, y1 - y0, function()
				if not st.own then return end
				wep.STTS_ThumbRect = {x = x, y = y, w = cell, h = cell}
				wep.STTS_ThumbAt, wep.STTS_ThumbApp, wep.STTS_ThumbRad = RealTime(), G.APP_GALLERY, 0
				L.gal, L.galV, L.sel = gi, GV_VIEW, 0
			end)
		end
		if gi == st.gal and wep.STTS_GalCell == false then wep.STTS_GalCell = {x = x, y = y, w = cell, h = cell} end -- zoom back target
		Thumb(st, st.photos[gi], x, y, cell)
		local k = HoverK(wep, id, st.sel == id)
		if k > 0.01 then R(x, y, cell, cell, SCR.Ink((Pressed(wep, st, id) and 90 or 45) * k)) end
	end
	Unclip()
	if maxScroll > 0 then
		local area = bottom - top
		local bh = math.max(30, area * visible / rows)
		Round(3, W - 8, top + (area - bh) * math.Clamp(s / maxScroll, 0, 1), 5, bh, SCR.Ink(110))
	end
	Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = cell + gap})
end

local function TabBar(btns, wep, st, active)
	local y = H - TABBAR
	R(0, y, W, TABBAR, C.bar)
	R(0, y, W, 1, C.sep)
	local tw = W / 2
	for i, it in ipairs({{GV_PHOTOS, "Library"}, {GV_ALBUMS, "Albums"}}) do
		local x = (i - 1) * tw
		local id = 44 + i
		Reg(btns, id, x, y, tw, 64, function() GalGo(st, it[1], 0) end)
		local on = active == it[1] or (active == GV_ALBUM and it[1] == GV_ALBUMS)
		local col = on and C.blue or C.gray
		local k = HoverK(wep, id, st.sel == id)
		if k > 0.01 then Round(16, x + tw / 2 - 62, y + 4, 124, 60, SCR.Ink(22 * k)) end
		local gx, gy = x + tw / 2, y + 32
		if i == 1 then -- picture
			Round(5, gx - 16, gy - 13, 32, 26, col)
			Tri(gx - 12, gy + 9, gx - 3, gy - 3, gx + 6, gy + 9, C.bar)
			Tri(gx + 1, gy + 9, gx + 7, gy + 1, gx + 13, gy + 9, C.bar)
			Circle(gx + 7, gy - 5, 3, C.bar)
		else -- stacked albums
			Round(5, gx - 9, gy - 15, 24, 24, col)
			Round(6, gx - 17, gy - 9, 28, 28, C.bar)
			Round(5, gx - 15, gy - 7, 24, 24, col)
		end
	end
end

local function Viewer(wep, st, btns)
	local list = AlbumList(st, st.album)
	local pos = 1
	for i, gi in ipairs(list) do if gi == st.gal then pos = i break end end
	local gi = list[pos]
	if not gi then GalGo(st, st.album == 0 and GV_PHOTOS or GV_ALBUM) return end
	-- slide between pictures
	local dt = wep.STTS_UIdt or 0
	if wep.STTS_GalLast and wep.STTS_GalLast ~= gi and wep.STTS_GalLastV == GV_VIEW then
		local before = 0
		for i, v in ipairs(list) do if v == wep.STTS_GalLast then before = i end end
		local dir = before == 0 and 0 or (pos > before and 1 or -1)
		if math.abs(pos - before) > 1 and before ~= 0 then dir = -dir end -- wrapped around
		wep.STTS_GalOff, wep.STTS_GalPrev = dir * W, st.photos[wep.STTS_GalLast]
	end
	if wep.STTS_GalLast ~= gi or wep.STTS_GalLastV ~= GV_VIEW then wep.STTS_VidT0 = RealTime() end
	wep.STTS_GalLast, wep.STTS_GalLastV = gi, GV_VIEW
	local off = Lerp(1 - math.exp(-dt * 13), wep.STTS_GalOff or 0, 0)
	if math.abs(off) < 0.5 then off = 0 end
	wep.STTS_GalOff = off

	R(0, 0, W, H, BLACK)
	local ph = W * G.PhotoH / G.PhotoW
	local py = (H - ph) / 2
	--[[ v19.4: every picture fits the display with its own shape (landscape photos too), and
	     while the phone is held landscape it turns with you (upright, as big as the turned
	     display allows, like Photos on an iPhone). the toolbars stay where they are ]]
	local le = SCR.LandK(wep)
	local function Pic(id, x)
		if SCR.M49 and id == st.photos[gi] then SCR.M49.AutoStart(st, id) end -- fix53: opened = download
		local vid = IsVideo(st, id)
		local pw, pph
		-- fix68: a clip filmed landscape is a landscape picture (its portrait frames turned upright)
		local rot = vid and STTS.PhoneGallery33 and STTS.PhoneGallery33.Rot66 and STTS.PhoneGallery33.IsBlob(id, st) and STTS.PhoneGallery33.Rot66(id) or 0
		if vid then pw, pph = G.FrameW, G.FrameH else pw, pph = SCR.PhotoSize(id) end
		if rot ~= 0 then pw, pph = pph, pw end
		local sc = Lerp(le, math.min(W / pw, H / pph), math.min(H / pw, W / pph))
		local dw, dh = pw * sc, pph * sc
		local px, pyy = x + (W - dw) / 2, (H - dh) / 2
		local turn = le > 0.0005
		if turn then
			local m = Matrix()
			m:Translate(Vector(x + W / 2, H / 2, 0))
			m:Rotate(Angle(0, -90 * le, 0))
			m:Translate(Vector(-(x + W / 2), -H / 2, 0))
			cam.PushModelMatrix(m, true)
		end
		if vid and rot ~= 0 then
			local cx, cy = px + dw / 2, pyy + dh / 2
			local m2 = Matrix()
			m2:Translate(Vector(cx, cy, 0)) m2:Rotate(Angle(0, rot, 0)) m2:Translate(Vector(-cx, -cy, 0))
			cam.PushModelMatrix(m2, true)
			DrawVideo(st, id, cx - dh / 2, cy - dw / 2, dh, dw, id == st.photos[gi] and RealTime() - (wep.STTS_VidT0 or RealTime()) or 0)
			cam.PopModelMatrix()
		elseif vid then
			DrawVideo(st, id, px, pyy, dw, dh, id == st.photos[gi] and RealTime() - (wep.STTS_VidT0 or RealTime()) or 0)
		else
			local mat = PhotoMat(id)
			if mat then
				surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255) surface.DrawTexturedRect(px, pyy, dw, dh)
			else
				R(px, pyy, dw, dh, Color(16, 16, 18))
			end
		end
		if SCR.M49 then SCR.M49.ViewerOverlay(st, id, px, pyy, dw, dh) end -- fix53: still downloading
		if turn then cam.PopModelMatrix() end
	end
	if off ~= 0 and wep.STTS_GalPrev then Pic(wep.STTS_GalPrev, off - (off > 0 and W or -W)) end
	Pic(st.photos[gi], off)

	-- top bar: back (to the conversation, if the picture was opened from one)
	R(0, 0, W, 114, Color(0, 0, 0, 150))
	NavBack(btns, wep, st, nil, function()
		if st.own and L.backTo then local b = L.backTo L.backTo = nil SetApp(st, b) return end
		GalGo(st, st.album == 0 and GV_PHOTOS or GV_ALBUM)
	end)
	local function Go(d)
		if not st.own or #list < 2 then return end
		L.gal = list[(pos - 1 + d) % #list + 1]
	end
	Zone(btns, {kind = "swipe", x = 0, y = 114, w = W, h = H - 232, fn = Go})
	if #list > 1 then
		for _, side in ipairs({{40, -1, 36, "left"}, {41, 1, W - 36, "right"}}) do
			local id, mid = side[1], py + ph / 2
			Reg(btns, id, side[2] < 0 and 0 or W - 72, mid - 90, 72, 180, function() Go(side[2]) end)
			local k = HoverK(wep, id, st.sel == id)
			if k > 0.01 then Circle(side[3], mid, 26, Color(0, 0, 0, 140 * k)) end
			local cx = side[3] + (side[2] < 0 and -6 or 6)
			Chevron(cx, mid, 12, side[4], Color(255, 255, 255, 110 + 145 * k), 4)
		end
	end
	-- bottom toolbar: save to PC (fix15) + delete (sending = TeleChat attach button only)
	R(0, H - 118, W, 118, Color(0, 0, 0, 150))
	local id = st.photos[gi]
	IconBtn(btns, wep, st, 43, 64, H - 78, function(x, y, col) GSave(x, y, col) end, function()
		if st.own and id then SCR.SaveItem(st, id) end
	end)
	IconBtn(btns, wep, st, 42, W - 64, H - 78, function(x, y, col) GTrash(x, y, col) end, function()
		local media=STTS.PhoneGallery33;local cached=media and media.Get(id)
		if SCR.M49 and SCR.M49.DeletePending(id) then -- fix53: a photo still uploading
  elseif media and ((id and id<0)or(cached and cached.record))then media.Delete(id)
  else net.Start("stts_phone_del") net.WriteUInt(id, 32) net.SendToServer() end
		if not st.own then return end
		local nxt = list[pos + 1] or list[pos - 1]
		if nxt then L.gal = nxt > gi and nxt - 1 or nxt -- indices shift after the removal
		else GalGo(st, st.album == 0 and GV_PHOTOS or GV_ALBUM) end
	end)
end

APPS[G.APP_GALLERY] = function(wep, st, btns)
	local view = st.galV or GV_PHOTOS
	if view ~= GV_VIEW then wep.STTS_GalLastV = view end
	if view == GV_VIEW then Viewer(wep, st, btns) return end
	if view == GV_ALBUM then
		local list = AlbumList(st, st.album == 0 and 1 or st.album)
		NavBack(btns, wep, st, "Albums", function() GalGo(st, GV_ALBUMS) end)
		InlineTitle(ALBUM_NAME[st.album] or "Album")
		PhotoGrid(btns, wep, st, list, 130)
		TabBar(btns, wep, st, view)
		return
	end
	NavBack(btns, wep, st, nil, function() SetApp(st, G.APP_HOME) end)
	if view == GV_PHOTOS then
		local list = AlbumList(st, 0)
		LargeTitle("Library", 134)
		PhotoGrid(btns, wep, st, list, 180)
		TabBar(btns, wep, st, view)
		return
	end
	-- albums: cover = newest picture, name, count
	LargeTitle("Albums", 134)
	if st.own then L.maxScroll = 0 end
	local cw = math.floor((W - 24 * 2 - 20) / 2)
	for i, album in ipairs({1, 2}) do
		local list = AlbumList(st, album)
		local x, y = 24 + (i - 1) * (cw + 20), 186
		local bid = 50 + i
		Reg(btns, bid, x, y, cw, cw + 44, function() GalGo(st, GV_ALBUM, album) end)
		local k = PopScale(wep, "al" .. i, st.sel == bid, Pressed(wep, st, bid))
		local s = cw * k
		local ox, oy = x + (cw - s) / 2, y + (cw - s) / 2
		local last = list[#list]
		if last then Thumb(st, st.photos[last], ox, oy, s) else R(ox, oy, s, s, C.bg2) end
		CornerMask(ox, oy, s, s, 16, C.bg or BLACK)
		T(ALBUM_NAME[album], "STTS_I_Body", x + 2, y + cw + 24, C.label, TEXT_ALIGN_LEFT)
	end
	TabBar(btns, wep, st, view)
end

--[[ TeleChat attach sheet (the "+" of a conversation): slides up over the
     dimmed conversation, the gallery of the phone in a grid, tap = send ]]
APPS[G.APP_SEND] = function(wep, st, btns)
	if APPS[G.APP_THREAD] then -- behind the sheet, always at the newest message
		local sc = st.scroll
		st.scroll = 0
		APPS[G.APP_THREAD](wep, st, {})
		st.scroll = sc
	end
	R(0, 0, W, H, Color(0, 0, 0, 160 * (wep.STTS_SheetDim or 1)))
	local sy = 150 + (wep.STTS_SheetOff or 0)
	Round(32, 0, sy, W, H - sy + 60, C.bg2)
	Round(3, W / 2 - 24, sy + 10, 48, 6, SCR.Ink(70)) -- grabber
	Reg(btns, BACK, W - 80, sy + 18, 64, 64, function() SetApp(st, G.APP_THREAD) end)
	local k = HoverK(wep, BACK, st.sel == BACK)
	Circle(W - 48, sy + 50, 21, Color(118, 118, 128, 80 + 70 * k))
	GClose(W - 48, sy + 50, 7, C.label2)
	-- grid: newest first
	local pad, gap, cols = 14, 6, 3
	local cell = math.floor((W - pad * 2 - gap * (cols - 1)) / cols)
	local top, bottom = sy + 92, H - 24
	local list = {};for _,id in ipairs(st.photos) do list[#list+1]=id end
	local rows = math.ceil(#list / cols)
	local visible = math.max(1, math.floor((bottom - top) / (cell + gap)))
	local maxScroll = math.max(0, rows - (bottom - top + gap) / (cell + gap)) -- fix17: smooth, in rows
	if st.own then L.maxScroll = maxScroll end
	local s = math.Clamp(st.scroll, -1, maxScroll + 1)
	local first = math.floor(s)
	local off = (s - first) * (cell + gap)
	Clip(0, top, W, bottom - top)
	for slot = 1, (visible + 2) * cols do
		local n = first * cols + slot
		local row = math.floor((slot - 1) / cols)
		local y = top + row * (cell + gap) - off
		if y >= bottom or n > #list then break end
		local id = n >= 1 and list[#list - n + 1] or nil
		if not id then continue end
		local col = (slot - 1) % cols
		local x = pad + col * (cell + gap)
		local bid = 200 + (n - 1) % 54 + 1
		local y0, y1 = math.max(y, top), math.min(y + cell, bottom)
		if y1 - y0 > 10 then
			Reg(btns, bid, x, y0, cell, y1 - y0, function()
				if not st.own then return end
				SCR.SendMedia(id)
				SetApp(st, G.APP_THREAD)
			end)
		end
		local kp = PopScale(wep, "att" .. n, st.sel == bid, Pressed(wep, st, bid))
		local s2 = cell * kp
		local ox, oy = x + (cell - s2) / 2, y + (cell - s2) / 2
		Thumb(st, id, ox, oy, s2)
		CornerMask(ox, oy, s2, s2, 12, C.bg2)
	end
	Unclip()
	Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = cell + gap})
end

--[[---------------------------------------------------------------------------
	TeleChat: conversations of the phone in your hand (history from the
	server, it belongs to the phone number). tap the field and type: the text
	appears in the field of the phone itself. Enter sends, Esc closes.
---------------------------------------------------------------------------]]
-- CHAT (declared with the UI): [phone number] = {threads = {[peer number] = {name, u = unread, m = {{me, text, t}}}}}
local TC_MAX = G.ChatMaxLen or 300
local TC_KEEP = G.ChatPerThread or 50

local function TCThread(num, peer, create)
	local box = CHAT[num]
	if not box then
		if not create then return end
		box = {threads = {}} CHAT[num] = box
	end
	local th = box.threads[peer]
	if not th and create then th = {name = "", u = 0, m = {}} box.threads[peer] = th end
	return th
end

function SCR.TCUnread(num) -- nil until the history of that phone arrived
	local box = CHAT[num]
	if not box then return end
	local n = 0
	for _, th in pairs(box.threads) do n = n + (th.u or 0) end
	return n
end

TCAsk = function(force)
	local wep = MyPhone()
	if not wep then return end
	if not force and RealTime() < (L.tcAskAt or 0) + 3 then return end
	L.tcAskAt = RealTime()
	net.Start("stts_tc_ask") net.WriteUInt(0, 2) net.SendToServer()
end

local function TCRead(num, peer)
	local th = TCThread(num, peer)
	if not th or (th.u or 0) <= 0 then return end
	th.u = 0
	net.Start("stts_tc_ask") net.WriteUInt(1, 2) net.WriteString(peer) net.SendToServer()
end

local function MyNum()
	return IsValid(L.wep) and L.wep:GetNWString("STTS_Num", "") or ""
end

--[[ fix61: photo / video messages go out through this queue and are sent again until the
     server's echo (stts_tc_msg "me") comes back: its 0.6 s cooldown and 20-a-minute window
     dropped them silently ("the video was never sent"). one at a time, only while the
     phone with that number is in the hand (the server wants the held phone) ]]
local SHARE = {q = {}, echo = {}}
local function ShareKey(num, peer, id) return num .. "|" .. peer .. "|" .. id end
function SCR.ShareOut(num, peer, id)
	if not isstring(num) or num == "" or not isstring(peer) or peer == "" or not id or id <= 0 then return false end
	for _, s in ipairs(SHARE.q) do if s.num == num and s.peer == peer and s.id == id then return true end end
	SHARE.q[#SHARE.q + 1] = {num = num, peer = peer, id = id, at = 0, round = GetGlobalInt("STTS_PhotoRound", 1)}
	return true
end
function SCR.ShareQueued(num, peer, id)
	for _, s in ipairs(SHARE.q) do if s.num == num and s.peer == peer and s.id == id then return true end end
	return false
end
function SCR.ShareCancel(num, peer, id)
	for i = #SHARE.q, 1, -1 do local s = SHARE.q[i] if s.num == num and s.peer == peer and s.id == id and not s.sentAt then table.remove(SHARE.q, i) end end
end
hook.Add("Think", "STTS_PhoneShareOut61", function()
	local s = SHARE.q[1]
	if not s then return end
	local now = RealTime()
	local echo = SHARE.echo[ShareKey(s.num, s.peer, s.id)]
	if s.round ~= GetGlobalInt("STTS_PhotoRound", 1) or s.sentAt and ((echo and echo >= s.sentAt) or now - s.sentAt > 45) then table.remove(SHARE.q, 1) return end
	if now < s.at then return end
	local w = MyPhone()
	if not w or w:GetNWString("STTS_Num", "") ~= s.num then return end
	if SCR.PlaneBlocked and SCR.PlaneBlocked() then return end
	local P = STTS.PhoneGallery33
	if P and now < (P.sendAfter or 0) then return end
	s.sentAt, s.at = s.sentAt or now, now + 2.5
	if P then P.ChatActivity() end
	net.Start("stts_tc_send") net.WriteString(s.peer) net.WriteString("") net.WriteUInt(s.id, 32) net.SendToServer()
end)

net.Receive("stts_tc_msg", function()
	local num, peer, name = net.ReadString(), net.ReadString(), net.ReadString()
	local me, text, t, ding = net.ReadBool(), net.ReadString(), net.ReadUInt(32), net.ReadBool()
	local media = net.ReadUInt(32)
	if me and media > 0 then SHARE.echo[ShareKey(num, peer, media)] = RealTime() end
	local th = TCThread(num, peer, true)
	if name ~= "" then th.name = name end
	th.m[#th.m + 1] = {me = me, text = text, t = t, media = media > 0 and media or nil}
	if media > 0 and SCR.M49 then SCR.M49.MarkManual(media) end -- fix53: tap to download
	while #th.m > TC_KEEP do table.remove(th.m, 1) end
	if not me then th.u = (th.u or 0) + 1 end
	local reading = L.raised and L.app == G.APP_THREAD and L.peer == peer and MyNum() == num
	if reading then
		TCRead(num, peer)
	end
	-- Settings: the notification sound now comes out of the phone itself (server, everybody near hears it)
end)

net.Receive("stts_tc_full", function()
	local num = net.ReadString()
	local len = net.ReadUInt(16)
	local raw = util.Decompress(net.ReadData(len), 1024 * 1024)
	local list = raw and util.JSONToTable(raw)
	if not istable(list) then return end
	local box = {threads = {}}
	for _, th in ipairs(list) do
		local msgs = {}
		for _, m in ipairs(istable(th.m) and th.m or {}) do
			local media = tonumber(m[4]) or 0
			msgs[#msgs + 1] = {me = tonumber(m[1]) == 1, text = tostring(m[2] or ""), t = tonumber(m[3]) or 0, media = media > 0 and media or nil}
			if media > 0 and SCR.M49 then SCR.M49.MarkManual(media) end -- fix53
		end
		box.threads[tostring(th.p or "")] = {name = tostring(th.n or ""), u = tonumber(th.u) or 0, m = msgs}
	end
	CHAT[num] = box
end)

net.Receive("stts_tc_wipe", function()
	CHAT = {}
	SHARE.q, SHARE.echo = {}, {}
	L.draft, L.peer = "", nil
	if L.app == G.APP_THREAD then L.app = G.APP_CHATS end
end)

-- word wrap (utf-8 safe, very long words are cut by characters)
local function Wrap(text, font, width)
	surface.SetFont(font)
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		local try = line == "" and word or (line .. " " .. word)
		if surface.GetTextSize(try) <= width then
			line = try
		else
			if line ~= "" then lines[#lines + 1] = line line = "" end
			if surface.GetTextSize(word) <= width then
				line = word
			else
				local part = ""
				for _, ch in ipairs(U8Chars(word)) do
					if part ~= "" and surface.GetTextSize(part .. ch) > width then lines[#lines + 1] = part part = ch else part = part .. ch end
				end
				line = part
			end
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	if #lines == 0 then lines[1] = "" end
	return lines
end

function SCR.SendDraft()
	local text = string.Trim(L.draft or "")
	if text == "" or not L.peer then SCR.OpenEntry() return end
	if SCR.PlaneBlocked and SCR.PlaneBlocked() then return end -- fix17: airplane mode, the draft stays
	if STTS.PhoneGallery33 then STTS.PhoneGallery33.ChatActivity()end
	net.Start("stts_tc_send") net.WriteString(L.peer) net.WriteString(text) net.WriteUInt(0, 32) net.SendToServer()
	L.draft, L.scroll, L.scrollV, L.scrollGo = "", 0, 0, nil
end

-- a photo / video of this phone into the open conversation
function SCR.SendMedia(id)
	if not L.peer or not id then return end
	if SCR.PlaneBlocked and SCR.PlaneBlocked() then return end -- fix17: airplane mode
	if id <= -1000000 and SCR.M49 then -- fix53: a photo still uploading: sent as soon as the server has it
		local real, p = SCR.M49.Resolve(id)
		if not p then return end
		if not real then
			p.share = p.share or {}
			for _, v in ipairs(p.share) do if v == L.peer then return end end
			p.share[#p.share + 1] = L.peer
			L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
			return
		end
		id = real
	end
	if id < 0 then
  if STTS.PhoneGallery33 then STTS.PhoneGallery33.QueueShare(id,L.peer)end
 elseif not SCR.ShareOut(MyNum(), L.peer, id) then
  if STTS.PhoneGallery33 then STTS.PhoneGallery33.ChatActivity()end
  net.Start("stts_tc_send") net.WriteString(L.peer) net.WriteString("") net.WriteUInt(id, 32) net.SendToServer()
 end
	L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
end

-- the text field (real keyboard input: Cyrillic, paste, caret).
-- fix7: the box at the bottom of the monitor is gone. an INVISIBLE text entry
-- only catches the keyboard, the text + caret are drawn in the field of the
-- phone itself. the mouse stays with the game (the finger keeps working).
-- Enter = send, Esc = close.
function SCR.OpenEntry()
	if not L.peer or not L.raised then return end
	if IsValid(L.entry) then if IsValid(L.entry.te) then L.entry.te:RequestFocus() end return end
	local fr = vgui.Create("EditablePanel")
	fr:SetSize(2, 2)
	fr:SetPos(-10, -10)
	fr:MakePopup()
	fr:SetKeyboardInputEnabled(true)
	fr:SetMouseInputEnabled(false)
	fr.openedAt = RealTime()
	fr.Paint = function() end
	local te = vgui.Create("DTextEntry", fr)
	te:SetPos(0, 0) te:SetSize(2, 2)
	te:SetFont("STTS_TC_Entry")
	te:SetText(L.draft or "")
	te:SetCaretPos(#U8Starts(L.draft or ""))
	te:SetUpdateOnType(true)
	te:SetDrawLanguageID(false)
	te.Paint = function() end
	te.AllowInput = function(self) -- true = block the character
		local v = self:GetValue()
		return #U8Starts(v or "") >= TC_MAX
	end
	te.OnValueChange = function(self, v) L.draft = v end
	te.OnEnter = function(self)
		L.draft = self:GetValue()
		fr:Remove()
		SCR.SendDraft()
	end
	fr.Think = function(self)
		if not L.raised or L.app ~= G.APP_THREAD or not L.peer or not MyPhone() then self:Remove() return end
		if RealTime() - self.openedAt > 0.3 and IsValid(te) and not te:HasFocus() then self:Remove() return end
		L.caret = te:GetCaretPos()
	end
	fr.te = te
	L.entry = fr
	te:RequestFocus()
end

-- Esc closes the text field instead of opening the game menu
hook.Add("OnPauseMenuShow", "STTS_TeleChatEsc", function()
	if IsValid(L.entry) then L.entry:Remove() return false end
end)

APPS[G.APP_CHATS] = function(wep, st, btns)
	NavBack(btns, wep, st, nil, function() SetApp(st, G.APP_HOME) end)
	LargeTitle("TeleChat", 134)
	if not st.own then return end
	local list, seen = {}, {}
	local box = CHAT[st.num]
	for peer, th in pairs(box and box.threads or {}) do
		local last = th.m[#th.m]
		if last then
			list[#list + 1] = {num = peer, name = th.name ~= "" and th.name or peer, badge = th.u or 0, at = last.t or 0}
			seen[peer] = true
		end
	end
	table.sort(list, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.num < b.num end)
	for _, c in ipairs(Contacts(st, true)) do
		if not seen[c.num] then list[#list + 1] = {num = c.num, name = c.name, at = 0} end
	end
	List(btns, wep, st, list, function(c)
		if not st.own then return end
		L.peer, L.peerName = c.num, c.name
		SetApp(st, G.APP_THREAD)
		TCRead(st.num, c.num)
	end, 180, {dot = true})
end

APPS[G.APP_THREAD] = function(wep, st, btns)
	local peer = st.own and L.peer or nil
	local th = peer and TCThread(st.num, peer)
	local name = (th and th.name ~= "" and th.name) or (st.own and L.peerName) or peer or "TeleChat"
	local function Back()
		if not st.own then return end
		if IsValid(L.entry) then L.entry:Remove() end
		SetApp(st, G.APP_CHATS)
		L.peer = nil
	end

	--[[ bubbles, newest at the bottom. fix17: smooth, scroll = 64 px units from the
	     newest message (finger down = older), the whole thread is laid out ]]
	local msgs = th and th.m or {}
 if st.own and peer and STTS.PhoneGallery33 then
  local pending=STTS.PhoneGallery33.ChatPending44(st.num,peer)
  if #pending>0 then local copy={};for _,m in ipairs(msgs)do copy[#copy+1]=m end;for _,m in ipairs(pending)do copy[#copy+1]=m end;msgs=copy end
 end
	local top, bottom = 154, H - 128
	local maxW, lh = math.floor(W * 0.74), 32
	local MS = 210 -- photo / video bubble
	local total = 0
	for i = #msgs, 1, -1 do
		local m = msgs[i]
		if not m.media and not m.ilines then
			m.ilines = Wrap(m.text, "STTS_I_Msg", maxW - 34)
			surface.SetFont("STTS_I_Msg")
			local bw = 0
			for _, line in ipairs(m.ilines) do bw = math.max(bw, surface.GetTextSize(line)) end
			m.ibw = math.max(bw + 34, 58)
		end
		local nxt = msgs[i + 1]
		local same = i < #msgs and nxt and nxt.me == m.me and (nxt.t or 0) - (m.t or 0) < 300
		total = total + (i == #msgs and 4 or (same and 4 or 14)) + (m.media and MS or (#m.ilines * lh + 20))
	end
	local maxScroll = math.max(0, (total + 10 - (bottom - top)) / 64)
	if st.own then
		-- a new message came in while you read older ones: what you read stays in place
		if L.tcH and L.tcPeer == peer and total > L.tcH and st.scroll > 0.01 then L.scroll = L.scroll + (total - L.tcH) / 64 end
		L.tcH, L.tcPeer = total, peer
		L.maxScroll = maxScroll
	end
	local last = #msgs
	local y = bottom + math.Clamp(st.scroll, -1, maxScroll + 1) * 64
	Clip(0, top, W, bottom - top)
	for i = last, 1, -1 do
		local m = msgs[i]
		if y < top then break end
		if m.media then
			local nxt = msgs[i + 1]
			local same = i < last and nxt and nxt.me == m.me and (nxt.t or 0) - (m.t or 0) < 300
			y = y - (i == last and 4 or (same and 4 or 14))
			y = y - MS
			if y >= bottom then continue end
			local x = m.me and (W - 14 - MS) or 14
			local bid = 300 + (last - i)
			local y0, y1 = math.max(y, top), math.min(y + MS, bottom)
			if bid < 400 and y1 - y0 > 10 then
				local mid = m.media
				local by = y
				Reg(btns, bid, x, y0, MS, y1 - y0, function()
					if not st.own then return end
					-- fix53 (Telegram): not downloaded = download, downloading = cancel, sending = cancel
					if SCR.M49 and SCR.M49.Tap(wep, st, mid, peer) then return end
					local at
					for gi, v in ipairs(st.photos) do if v == mid then at = gi break end end
					if not at then return end
					wep.STTS_ThumbRect = {x = x, y = by, w = MS, h = MS}
					wep.STTS_ThumbAt, wep.STTS_ThumbApp, wep.STTS_ThumbRad = RealTime(), G.APP_THREAD, 21
					wep.STTS_ThumbScroll = st.scroll or 0
					L.backTo = G.APP_THREAD
					SetApp(st, G.APP_GALLERY)
					L.galV, L.album, L.gal = GV_VIEW, 0, at
					L.backTo = G.APP_THREAD
				end)
			end
			local kp = PopScale(wep, "mb" .. i, st.sel == bid, Pressed(wep, st, bid))
			local s2 = MS * kp
			local ox, oy = x + (MS - s2) / 2, y + (MS - s2) / 2
			-- fix53: Telegram: blurred preview, size, round download / progress button
			if SCR.M49 then SCR.M49.Bubble(wep, st, m.media, ox, oy, s2) else Thumb(st, m.media, ox, oy, s2) end
			CornerMask(ox, oy, s2, s2, 21, C.bg or BLACK)
			if SCR.M49 then SCR.M49.BubbleOver(wep, st, m.media, ox, oy, s2, m.me, peer) end
			continue
		end
		local nxt = msgs[i + 1]
		local same = i < last and nxt and nxt.me == m.me and (nxt.t or 0) - (m.t or 0) < 300
		y = y - (i == last and 4 or (same and 4 or 14))
		local bh = #m.ilines * lh + 20
		y = y - bh
		if y >= bottom then continue end
		local x = m.me and (W - 14 - m.ibw) or 14
		Round(21, x, y, m.ibw, bh, m.me and C.blue or C.them)
		for li, line in ipairs(m.ilines) do
			T(line, "STTS_I_Msg", x + 17, y + 10 + (li - 1) * lh, m.me and WHITE or C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
	end
	Unclip()
	Zone(btns, {kind = "scroll", x = 0, y = top, w = W, h = bottom - top, step = 64, invert = true})
	if st.scroll > 0.5 then -- reading older messages: tap = glide back to the newest
		Reg(btns, 63, W - 72, bottom - 58, 56, 56, function() if st.own then L.scrollV, L.scrollGo = 0, 0 end end)
		local kc = PopScale(wep, "newest", st.sel == 63, Pressed(wep, st, 63))
		Circle(W - 44, bottom - 30, 22 * kc, st.sel == 63 and (C.hi or Color(70, 70, 74)) or C.bg3)
		Chevron(W - 44, bottom - 24, 9, "down", C.label, 3.5)
	end

	-- header (over the bubbles that scroll under it)
	R(0, 0, W, 152, C.bar)
	R(0, 152, W, 1, C.sep)
	NavBack(btns, wep, st, nil, Back)
	if not peer then InlineTitle("TeleChat") return end
	Avatar(name, peer, W / 2, 84, 27)
	T(Fit(name, "STTS_I_Cap", W - 190), "STTS_I_Cap", W / 2, 132, C.label)

	-- attach (+): photos / videos of this phone, the only way to send them
	local ay = H - 114 + 31
	Reg(btns, 62, 6, H - 114, 60, 62, function() if st.own then SetApp(st, G.APP_SEND) end end)
	local ka = PopScale(wep, "attach", st.sel == 62, Pressed(wep, st, 62))
	Circle(36, ay, 24 * ka, st.sel == 62 and (C.hi or Color(70, 70, 74)) or C.bg3)
	Line(36 - 10, ay, 36 + 10, ay, 3.5, C.label2)
	Line(36, ay - 10, 36, ay + 10, 3.5, C.label2)

	-- text field (pill) + send
	local ix, iy, ih = 70, H - 114, 62
	local iw = W - 84
	local typing = IsValid(L.entry)
	local draft = L.draft or ""
	Reg(btns, 60, ix, iy, iw - 64, ih, function() SCR.OpenEntry() end)
	local k = HoverK(wep, 60, st.sel == 60 or typing)
	local fe, fh = C.edge or Color(66, 66, 70), C.hi or Color(106, 106, 110)
	Round(31, ix, iy, iw, ih, Color(Lerp(k, fe.r, fh.r), Lerp(k, fe.g, fh.g), Lerp(k, fe.b, fh.b)))
	Round(29, ix + 2, iy + 2, iw - 4, ih - 4, C.bg or BLACK)
	-- text typed on the keyboard shows up right here (no box on the monitor any more)
	surface.SetFont("STTS_I_Msg")
	-- fix10: character positions are computed by hand (no utf8.offset = no
	-- "initial position is a continuation byte" when entering TeleChat)
	local starts = U8Starts(draft)
	local len = #starts
	local caret = typing and math.Clamp(math.floor(tonumber(L.caret) or len), 0, len) or len
	-- scroll the line so the caret stays visible
	local room = iw - 104
	local skip = 0
	while skip < caret and surface.GetTextSize(U8Sub(draft, starts, skip + 1, caret)) > room do skip = skip + 1 end
	local last = len
	local shown = U8Sub(draft, starts, skip + 1, last)
	while last > skip and surface.GetTextSize(shown) > room do
		last = last - 1
		shown = U8Sub(draft, starts, skip + 1, last)
	end
	if shown ~= "" then T(shown, "STTS_I_Msg", ix + 22, iy + ih / 2, C.label, TEXT_ALIGN_LEFT) end
	if typing and math.floor(RealTime() * 2) % 2 == 0 then
		local before = U8Sub(draft, starts, skip + 1, caret)
		R(ix + 23 + surface.GetTextSize(before), iy + 16, 3, ih - 32, C.blue)
	end
	local sx, sy = ix + iw - 33, iy + ih / 2
	Reg(btns, 61, sx - 30, iy, 60, ih, function() SCR.SendDraft() end)
	local ks = PopScale(wep, "send", st.sel == 61, Pressed(wep, st, 61))
	Circle(sx, sy, 23 * ks, draft ~= "" and C.blue or C.bg3)
	GUp(sx, sy, draft ~= "" and C.label or C.gray)
end

-- a normal arrow cursor, tip at x, y (the png has its tip at 4/64 of the image)
function SCR.DrawArrow(x, y, size)
	if not arrowMat:IsError() then
		local o = size * 4 / 64
		surface.SetMaterial(arrowMat) surface.SetDrawColor(255, 255, 255)
		surface.DrawTexturedRect(x - o, y - o, size, size)
		return
	end
	-- no content yet: the same arrow from two convex pieces
	local u = size / 26
	local function Poly(pts, c, grow)
		local out = {}
		for i, p in ipairs(pts) do out[i] = {x = x + p[1] * u * grow, y = y + p[2] * u * grow} end
		surface.SetDrawColor(c) surface.DrawPoly(out)
	end
	draw.NoTexture()
	local head, tail = {{0, 0}, {12.2, 12.2}, {0, 17}}, {{4, 13.2}, {6.9, 12.2}, {9.7, 18.4}, {6.9, 19.6}}
	Poly(head, BLACK, 1.18) Poly(tail, BLACK, 1.1)
	Poly(head, WHITE, 1) Poly(tail, WHITE, 1)
end

--[[---------------------------------------------------------------------------
	system chrome: status bar, Dynamic Island, home indicator
---------------------------------------------------------------------------]]
-- fix28: the island sits over the front camera of EACH model (vivo / Pixel punch hole,
-- iPhone Dynamic Island cutout), sizes in G.Models[i].Island. the status bar is centred on it.
local function Isl(wep) return G.Of(wep).Island or G.Models[1].Island end
local function IslandRect(wep)
	local I = Isl(wep)
	return {x = W / 2 - I.w / 2, y = I.y, w = I.w, h = I.h}
end

local function StatusBar(wep, st)
	local I = Isl(wep)
	local sy = I.y + I.h / 2 -- vivo: 26 as before
	local cc = st and st.cc or {}
	local col = C.label
	-- v19.3: signal of the place where the phone is (zones of the map, cl_shooting_phone_settings.lua)
	local bars = SCR.NetBars and SCR.NetBars(wep) or 4
	if cc.cell == false then bars = 0 end
	-- Control Centre: the clock gives way to the carrier (iOS). v19.3: no cross-fade, the edge
	-- of the sheet cuts them (carrier above it, clock below it), like everything else
	local ey = (SCR.LockBar and SCR.LockBar(wep)) and H or (wep.STTS_CCy or 0) -- fix58: lock = carrier
	local ty = math.floor(ey + 0.5)
	if ey < sy + 16 then
		local cut = ey > sy - 16
		if cut then render.SetScissorRect(0, ty, W, H, true) end
		T(SCR.Clock and SCR.Clock(wep) or os.date("%H:%M"), "STTS_I_Status", 70, sy, col) -- Settings: 24-hour time
		if cut then render.SetScissorRect(0, 0, 0, 0, false) end
	end
	if ey > sy - 16 then
		local cut = ey < sy + 16
		if cut then render.SetScissorRect(0, 0, W, ty, true) end
		T((st and st.plane) and "" or (bars == 0 and "No Service" or "Z-City"), "STTS_I_Status", 30, sy, col, TEXT_ALIGN_LEFT)
		if cut then render.SetScissorRect(0, 0, 0, 0, false) end
	end
	-- right: signal bars (or a plane in airplane mode, fix17), Wi-Fi, battery
	local bx = W - 30 - 37
	local x = bx - 10
	-- v19.2: the Wi-Fi fan only while the phone is really connected to the network of the map
	local wifiOn = cc.wifi
	if SCR.WifiState then wifiOn = SCR.WifiState(wep, st) == "on" end
	if wifiOn and SCR.WifiMat and not SCR.WifiMat:IsError() then
		x = x - 26
		if SCR.UI.WifiGlyph and SCR.WifiLevel then -- v19.3: 1..3 arcs (how good the internet is here)
			SCR.UI.WifiGlyph(x + 12.5, sy + 0.5, 25, col, SCR.WifiLevel(wep))
		else
			surface.SetMaterial(SCR.WifiMat) surface.SetDrawColor(col)
			surface.DrawTexturedRect(x, sy - 12, 25, 25)
		end
		x = x - 8
	end
	if st and st.plane then
		local pm = appIcons.plane
		x = x - 26
		if not pm:IsError() then
			surface.SetMaterial(pm) surface.SetDrawColor(col)
			surface.DrawTexturedRect(x - 1, sy - 13, 26, 26)
		else
			T("✈", "STTS_I_Status", x + 13, sy, col)
		end
	else
		x = x - 27
		for i = 0, 3 do
			local bh = 6 + i * 3.6
			local c = i >= bars and Color(col.r, col.g, col.b, 90) or col
			Round(1.5, x + i * 7, sy + 7 - bh, 5, bh, c)
		end
	end
	-- battery: every phone has its own charge (it does not run down, nothing here uses power)
	local pct = wep.STTS_Batt
	if not pct then pct = 0.42 + ((wep:EntIndex() * 37) % 53) / 100 wep.STTS_Batt = pct end
	local by = sy - 8.5
	Round(5, bx, by, 33, 17, Color(col.r, col.g, col.b, 100))
	Round(4, bx + 2, by + 2, 29 * pct, 13, pct < 0.2 and C.red or col)
	Round(1.5, bx + 34.5, by + 5.5, 2.5, 6, Color(col.r, col.g, col.b, 100))
end

local TOAST_ICON = {["Airplane mode"] = "plane", ["New message"] = "chat", ["Photo sent"] = "gallery", ["New photo"] = "gallery", ["Their gallery is full"] = "gallery",
	["Gallery is full"] = "gallery", ["Can't save photo"] = "camera", ["Photo too big"] = "camera"}
local TOAST_BAD = {["No answer"] = true, ["Busy"] = true, ["No service"] = true}

local function Island(wep, st)
	local toast = st.flash or (st.own and L.toast and RealTime() - (L.toastAt or 0) < 3 and L.toast) or nil
	toast = nil -- fix33: no unsolicited banners
	local I = Isl(wep)
	local ISL_W, ISL_H, ISL_Y = I.w, I.h, I.y
	local s = wep.STTS_Isl or {w = ISL_W, h = ISL_H, vw = 0, vh = 0, tw = ISL_W}
	wep.STTS_Isl = s
	local tw, th = ISL_W, ISL_H
	if toast then
		surface.SetFont("STTS_I_Island")
		tw, th = math.Clamp(surface.GetTextSize(toast) + 110, 240, W - 24), 66
		s.text, s.tw = toast, tw
	end
	-- jelly spring, like the real island
	local dt = wep.STTS_UIdt or 0
	local wn = 2 * math.pi * 2.8
	local c = 2 * 0.58 * wn
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		s.vw = s.vw + (wn * wn * (tw - s.w) - c * s.vw) * h
		s.vh = s.vh + (wn * wn * (th - s.h) - c * s.vh) * h
		s.w, s.h = s.w + s.vw * h, s.h + s.vh * h
	end
	local iw, ih = math.max(s.w, I.minW or 70), math.max(s.h, I.minH or 26)
	Round(ih / 2, W / 2 - iw / 2, ISL_Y, iw, ih, BLACK)
	local open = math.Clamp((s.w - ISL_W) / math.max((s.tw or ISL_W) - ISL_W, 1), 0, 1)
	if not toast and open < 0.05 then s.text = nil end
	if s.text and open > 0.55 then
		surface.SetAlphaMultiplier((open - 0.55) / 0.45)
		local x0, cy = W / 2 - iw / 2 + 16, ISL_Y + ih / 2
		local icon = TOAST_ICON[s.text] and appIcons[TOAST_ICON[s.text]]
		if icon and not icon:IsError() then
			surface.SetMaterial(icon) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(x0, cy - 19, 38, 38)
		else
			local bad = TOAST_BAD[s.text]
			Circle(x0 + 19, cy, 19, bad and C.red or C.green)
			GHandset(x0 + 19, cy, 19, WHITE, bad)
		end
		T(Fit(s.text, "STTS_I_Island", iw - 90), "STTS_I_Island", x0 + 54, cy, WHITE, TEXT_ALIGN_LEFT)
		surface.SetAlphaMultiplier(1)
	end
end

local function HomeBar(wep, st, btns)
	if st.app == G.APP_HOME or st.app == G.APP_CALL then return end
	Reg(btns, HOMEBAR, W / 2 - 110, H - 44, 220, 44, function()
		if IsValid(L.entry) then L.entry:Remove() end
		SetApp(st, G.APP_HOME)
	end)
	-- iOS: the indicator is part of the app window: gone while the window is dragged / not
	-- full screen yet (it fades in at the end of the launch), never reacts to hover
	if st.own and L.homeDrag then return end
	local a = 1
	if wep.STTS_Anim and wep.STTS_WinFull then a = math.Clamp((wep.STTS_WinFull - 0.85) / 0.15, 0, 1) end
	if a <= 0.01 then return end
	Round(3, W / 2 - 70, H - 19, 140, 6, Color(C.label.r, C.label.g, C.label.b, 200 * a))
end

local function DrawOverlays(wep, st, btns)
	local th = SCR.ThemeOverlay -- Settings: light / dark chrome (dark over camera, call, viewer, open shade)
	if th then th(wep, st, 1) end
	HomeBar(wep, st, btns)
	-- fix17: the pull-down shade covers the app (and takes over its buttons), the status bar + island stay on top
	if SCR.DrawLock then SCR.DrawLock(wep, st, btns) end -- fix58: lock screen (under the shade / alarm)
	if SCR.DrawShade then SCR.DrawShade(wep, st, btns) end
	if SCR.DrawAlarm then SCR.DrawAlarm(wep, st, btns) end -- fix55: a ringing alarm / timer covers everything
	if th then th(wep, st, 2) end
	StatusBar(wep, st)
	Island(wep, st)
	if SCR.DrawDim then SCR.DrawDim(wep, st) end -- fix20: brightness slider of the shade
	if SCR.DrawAutoOff then SCR.DrawAutoOff(wep, st) end -- fix61: Auto-Lock dims / switches the display off
	if th then th(wep, st, 3) end
end

--[[---------------------------------------------------------------------------
	transitions
---------------------------------------------------------------------------]]
local function ScreenKey(st)
	if st.app == G.APP_GALLERY then return st.app * 10 + (st.galV or 1) end
	return st.app * 10
end
local LEVEL = {[G.APP_HOME] = 0, [G.APP_THREAD] = 2}
local function KeyLevel(key)
	local app, sub = math.floor(key / 10), key % 10
	if app == G.APP_GALLERY then return sub == GV_VIEW and 3 or (sub == GV_ALBUM and 2 or 1) end
	return LEVEL[app] or 1
end
local ROOT_ICON = {[G.APP_THREAD] = G.APP_CHATS, [G.APP_SEND] = G.APP_CHATS}
-- (scoped: the main chunk of this file is close to Lua's 200 locals limit)
local BeginAnim, DrawContent, HomeSwipeEnd
do
local DUR = {open = 0.8, close = 0.9, restore = 0.7, island_in = 0.48, island_out = 0.42, push = 0.5, pop = 0.46,
	sheet_up = 0.55, sheet_down = 0.45, zoom_in = 0.6, zoom_out = 0.55, fade = 0.2}

local APP_ICON = {[G.APP_CONTACTS] = appIcons.phone, [G.APP_CHATS] = appIcons.chat, [G.APP_CAMERA] = appIcons.camera, [G.APP_GALLERY] = appIcons.gallery}
SCR.APP_ICON, SCR.ROOT_ICON, SCR.LEVEL = APP_ICON, ROOT_ICON, LEVEL -- Settings registers its icon / pages

local function AnimKind(wep, from, to)
	local fa, ta = math.floor(from / 10), math.floor(to / 10)
	local fs, ts = from % 10, to % 10
	if ta == G.APP_CALL then return "island_in" end
	if fa == G.APP_CALL then return "island_out" end
	if ta == G.APP_HOME then return "close" end
	if fa == G.APP_HOME then return "open" end
	if ta == G.APP_SEND then return "sheet_up" end
	if fa == G.APP_SEND then return "sheet_down" end
	-- fix55: other sheets (Clock: Add / Edit Alarm) over their parent page
	local SP = SCR.SheetParent
	if SP and SP[ta] == fa then return "sheet_up" end
	if SP and SP[fa] == ta then return "sheet_down" end
	if fa == G.APP_GALLERY and ta == G.APP_GALLERY then
		if ts == GV_VIEW then return "zoom_in" end
		if fs == GV_VIEW then return "zoom_out" end
		if fs ~= GV_ALBUM and ts ~= GV_ALBUM then return nil end -- Library <-> Albums: a tab bar switches at once (UITabBarController)
	end
	-- a picture opened from the camera thumbnail / a TeleChat bubble zooms out of it (Camera, Messages)
	if ta == G.APP_GALLERY and ts == GV_VIEW and wep.STTS_ThumbRect and RealTime() - (wep.STTS_ThumbAt or -10) < 0.6 then return "zoom_in" end
	if fa == G.APP_GALLERY and fs == GV_VIEW and ta == G.APP_THREAD and wep.STTS_ThumbApp == G.APP_THREAD and wep.STTS_ThumbRect
		and math.abs(wep.STTS_ThumbScroll or 0) < 0.05 then return "zoom_out" end
	local fl, tl = KeyLevel(from), KeyLevel(to)
	if tl > fl then return "push" elseif tl < fl then return "pop" end
	return "fade"
end

local function EaseOut(p) return 1 - (1 - p) ^ 3 end
--[[ real damped spring (the way iOS describes its animations: response + damping),
     t in seconds. damping 1 = no overshoot, 0.85 = a barely visible settle. ]]
local function SpringT(t, response, damping)
	if t <= 0 then return 0 end
	local w = 2 * math.pi / response
	if damping >= 1 then return 1 - (1 + w * t) * math.exp(-w * t) end
	local wd = w * math.sqrt(1 - damping * damping)
	local zw = damping * w
	return 1 - math.exp(-zw * t) * (math.cos(wd * t) + zw / wd * math.sin(wd * t))
end
--[[ the same spring in absolute units: from x0 to x1, starting with the speed v0 (units / s).
     this is what makes a gesture hand over to the animation without a jerk (WWDC23
     "Animate with springs": a spring can start with any velocity) ]]
local function SpringX(t, response, damping, x0, x1, v0)
	if t <= 0 then return x0 end
	v0 = v0 or 0
	local d0 = x0 - x1
	local w = 2 * math.pi / response
	if damping >= 1 then return x1 + (d0 + (v0 + w * d0) * t) * math.exp(-w * t) end
	local zw = damping * w
	local wd = w * math.sqrt(1 - damping * damping)
	return x1 + math.exp(-zw * t) * (d0 * math.cos(wd * t) + (v0 + zw * d0) / wd * math.sin(wd * t))
end

--[[ scratch RTs: the app being opened / dragged is drawn here, then morphed as a picture.
     your own phone has its own one: what is in it stays there between frames (the window
     you swipe home or interrupt keeps its picture), other phones share the second one ]]
local function MorphRT(name)
	local m = {rt = GetRenderTargetEx(name, W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)}
	m.mat = CreateMaterial(name .. "_m", "UnlitGeneric", {["$basetexture"] = m.rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1})
	return m
end
local MORPH, MORPH_O = MorphRT("stts_phone_ui_3"), MorphRT("stts_phone_ui_4m")
local function ToMorph(fn, own)
	local m = own and MORPH or MORPH_O
	local xf = SCR.XF
	SCR.XF = nil
	render.PushRenderTarget(m.rt)
		render.Clear(0, 0, 0, 255)
		cam.Start2D()
			fn()
		cam.End2D()
	render.PopRenderTarget()
	SCR.XF = xf
	surface.SetAlphaMultiplier(1)
	return m.mat
end

--[[ rounded rectangle as ONE convex polygon (clockwise), textured with the u/v range given:
     the app window is really cut round (no corner paint over what is behind it) ]]
local POLY = {}
local function RoundPoly(x, y, w, h, r, u0, v0, u1, v1)
	if w <= 0 or h <= 0 then return end
	r = math.max(0, math.min(r, w / 2, h / 2))
	local n = 0
	local function V(px, py)
		n = n + 1
		local q = POLY[n]
		if not q then q = {} POLY[n] = q end
		q.x, q.y = px, py
		q.u, q.v = u0 + (px - x) / w * (u1 - u0), v0 + (py - y) / h * (v1 - v0)
	end
	if r < 1.5 then
		V(x, y) V(x + w, y) V(x + w, y + h) V(x, y + h)
	else
		local seg = math.Clamp(math.ceil(r / 3.5), 3, 12)
		local cx0, cx1, cy0, cy1 = x + r, x + w - r, y + r, y + h - r
		for c = 0, 3 do
			local ox = (c == 0 or c == 3) and cx0 or cx1
			local oy = c <= 1 and cy0 or cy1
			local a0 = (180 + 90 * c) % 360
			for i = 0, seg do
				local ang = math.rad(a0 + 90 * i / seg)
				V(ox + math.cos(ang) * r, oy + math.sin(ang) * r)
			end
		end
	end
	for i = #POLY, n + 1, -1 do POLY[i] = nil end
	surface.DrawPoly(POLY)
end
SCR.UI.RoundTex = RoundPoly -- fix60: cl_phone_lock.lua (the wallpapers of Settings > Wallpaper)

-- corner radius of the display glass of each model (UI px): the app window ends on it
local CORNER = {vivo = 50, pixel = 46, iphone = 60}
local function DisplayR(wep) return CORNER[G.Of(wep).id or ""] or 52 end
local function CRect(r) return {cx = r.x + r.w / 2, cy = r.y + r.h / 2, w = r.w, h = r.h} end
local function BRect(c) return {x = c.cx - c.w / 2, y = c.cy - c.h / 2, w = c.w, h = c.h} end
local FULL = {cx = W / 2, cy = H / 2, w = W, h = H}
local ICON_DEF = {cx = W / 2, cy = H / 2, w = 84, h = 84}

--[[ the app window between its icon and full screen (iOS SpringBoard):
     centre, width and height each run on their OWN spring, so the icon stretches into the
     app and back instead of a uniform zoom (WWDC18 "Designing Fluid Interfaces", WWDC23
     "Animate with springs": different springs, different start / end times). the corners
     go from the icon squircle to the display corners, the app picture fills the window
     (aspect fill, centre crop) and cross-fades with the icon. ]]
local WSPR = {
	open    = {pos = {0.50, 0.86}, w = {0.42, 0.92}, h = {0.50, 0.90}, home = {0.40, 1}},
	close   = {pos = {0.52, 0.82}, w = {0.46, 0.88}, h = {0.52, 0.88}, home = {0.55, 1}},
	restore = {pos = {0.40, 0.90}, w = {0.40, 0.92}, h = {0.40, 0.92}, home = {0.36, 1}},
}
local function WinAt(a, t)
	local sp = WSPR[a.kind]
	local r0, r1, v = a.r0, a.r1, a.v or {}
	return {
		cx = SpringX(t, sp.pos[1], sp.pos[2], r0.cx, r1.cx, v.cx),
		cy = SpringX(t, sp.pos[1], sp.pos[2], r0.cy, r1.cy, v.cy),
		w = math.max(2, SpringX(t, sp.w[1], sp.w[2], r0.w, r1.w, v.w)),
		h = math.max(2, SpringX(t, sp.h[1], sp.h[2], r0.h, r1.h, v.h)),
	}
end
local function WinHomeK(a, t)
	local sp = WSPR[a.kind].home
	local goal = a.kind == "close" and 1 or 0
	return math.Clamp(SpringX(t, sp[1], sp[2], a.k0 or (1 - goal), goal, 0), 0, 1)
end
local function WinFull(c, iw)
	iw = iw or 84
	return math.Clamp((c.w - iw) / math.max(W - iw, 1), 0, 1)
end
local function WinRadius(wep, full, iw)
	return Lerp(full, (iw or 84) * 0.225, DisplayR(wep)) * math.Clamp((1 - full) / 0.02, 0, 1)
end
local function DrawWindow(mat, r, contentA, iconMat, iconA, fill, fillA, radius)
	if r.w < 2 or r.h < 2 then return end
	if fillA > 0.01 then
		draw.NoTexture() surface.SetDrawColor(LinCol(Color(fill.r, fill.g, fill.b, 255 * math.min(fillA, 1))))
		RoundPoly(r.x, r.y, r.w, r.h, radius, 0, 0, 1, 1)
	end
	if mat and contentA > 0.01 then
		local s = math.max(r.w / W, r.h / H)
		local u0, v0 = (1 - r.w / s / W) / 2, (1 - r.h / s / H) / 2
		surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255 * math.min(contentA, 1))
		RoundPoly(r.x, r.y, r.w, r.h, radius, u0, v0, 1 - u0, 1 - v0)
	end
	if iconMat and iconA > 0.01 and not iconMat:IsError() then
		local is = math.min(r.w, r.h)
		surface.SetMaterial(iconMat) surface.SetDrawColor(255, 255, 255, 255 * math.min(iconA, 1))
		surface.DrawTexturedRect(r.x + (r.w - is) / 2, r.y + (r.h - is) / 2, is, is)
	end
end
-- spring with a small overshoot (the iOS "bouncy" curve, Dynamic Island)
local function Spring(p)
	if p >= 1 then return 1 end
	return 1 - math.exp(-6.5 * p) * math.cos(p * 7.5)
end

local function DrawApp(wep, st, btns)
	-- Settings: camera / call / photo viewer always stay dark (like iOS)
	local dark = SCR.ThemePush and SCR.ThemePush(wep, st)
	local b = C.bg or BLACK
	local ab = wep.STTS_AppBg or Color(0, 0, 0)
	ab.r, ab.g, ab.b = b.r, b.g, b.b
	wep.STTS_AppBg = ab -- the background of the window (shows while the icon cross-fades)
	R(0, 0, W, H, b)
	local fn = APPS[st.app] or APPS[G.APP_HOME]
	fn(wep, st, btns)
	if dark then SCR.ThemePop(wep) end
end

-- draws fn scaled by s with its top left corner at x, y
local function Scaled(fn, x, y, s, alpha)
	local m = Matrix()
	m:Translate(Vector(x, y, 0))
	m:Scale(Vector(s, s, 1))
	cam.PushModelMatrix(m, true)
	if alpha and alpha < 1 then surface.SetAlphaMultiplier(alpha) end
	local xf = SCR.XF -- fix17: Clip() follows the matrix (scissor rects are in RT pixels)
	SCR.XF = xf and {x = xf.x + x * xf.s, y = xf.y + y * xf.s, s = xf.s * s} or {x = x, y = y, s = s}
	fn()
	SCR.XF = xf
	surface.SetAlphaMultiplier(1)
	cam.PopModelMatrix()
end

--[[ the home screen behind an app window (iOS): the wallpaper stays, the icons are pushed
     towards you and fade (k = 1 in place .. 0 gone) and get a little darker, the icon of
     the window is lifted off (the window IS that icon). with btns (closing to home) it is
     the real home screen: its icons can be tapped already ]]
local HOME_ZOOM = 0.1
local function DrawHome(wep, st, k, hide, btns)
	-- fix61: the home screen wallpaper stays in place (only the icons zoom / fade)
	if SCR.DrawHomeWall then SCR.DrawHomeWall(wep, 0, 0, W, H) else R(0, 0, W, H, C.home or BLACK) end
	if k > 0.004 then
		local hs = st
		if st.app ~= G.APP_HOME or not btns then hs = setmetatable({app = G.APP_HOME, sel = 0, scroll = 0}, {__index = st}) end
		local s = 1 + HOME_ZOOM * (1 - k)
		wep.STTS_HideIcon = hide
		wep.STTS_HomeNoWall = true
		Scaled(function() (APPS[G.APP_HOME])(wep, hs, btns or {}) end, W / 2 - W * s / 2, H / 2 - H * s / 2, s, k)
		wep.STTS_HomeNoWall = nil
		wep.STTS_HideIcon = nil
	end
	local d = 0.22 * (1 - k)
	if d > 0.004 then R(0, 0, W, H, Color(0, 0, 0, 255 * d)) end
end

--[[ iOS home gesture: the app window under the finger. d = how far the finger went up:
     the window shrinks (fast at first, then slower), its bottom edge stays at the finger
     and it follows the finger sideways; the home screen comes up behind it ]]
local function CardRect(hd)
	local d = math.max(0, hd.y0 - hd.fy)
	local s = 1 - 0.7 * (1 - math.exp(-d / H * 3))
	local w, h = W * s, H * s
	return {cx = W / 2 + (hd.fx - hd.x0) * 0.85, cy = H - d - h / 2, w = w, h = h}
end
local function CardVel(hd)
	local a = CardRect(hd)
	local dt = 1 / 120
	local vx, vy = math.Clamp(hd.vx or 0, -6000, 6000), math.Clamp(hd.vy or 0, -6000, 6000)
	local b = CardRect({x0 = hd.x0, y0 = hd.y0, fx = hd.fx + vx * dt, fy = hd.fy + vy * dt})
	return {cx = (b.cx - a.cx) / dt, cy = (b.cy - a.cy) / dt, w = (b.w - a.w) / dt, h = (b.h - a.h) / dt}
end
local function CardHomeK(hd)
	return math.Clamp((hd.y0 - hd.fy) / (H * 0.5), 0, 1) * 0.8
end

--[[ Photos zoom: where the picture sits in the viewer (portrait phone) ]]
local function ViewerPhotoRect(wep, st)
	if SCR.LandK and SCR.LandK(wep) > 0.0005 then return end
	local list = AlbumList(st, st.album)
	local gi = list[1]
	for _, v in ipairs(list) do if v == st.gal then gi = v break end end
	local id = gi and st.photos[gi]
	if not id then return end
	local pw, ph
	if IsVideo(st, id) then pw, ph = G.FrameW, G.FrameH else pw, ph = SCR.PhotoSize(id) end
	if not pw or not ph or pw <= 0 or ph <= 0 then return end
	local sc = math.min(W / pw, H / ph)
	local dw, dh = pw * sc, ph * sc
	return {x = (W - dw) / 2, y = (H - dh) / 2, w = dw, h = dh}
end
local function LerpBox(r0, r1, e)
	return {x = Lerp(e, r0.x, r1.x), y = Lerp(e, r0.y, r1.y), w = math.max(1, Lerp(e, r0.w, r1.w)), h = math.max(1, Lerp(e, r0.h, r1.h))}
end
-- the picture (rect P of a full screen texture) shown in r: aspect fill, centre crop, round corners
local function PhotoCrop(mat, P, r, rad)
	if r.w < 1 or r.h < 1 then return end
	local ca = r.w / r.h
	local cw, ch = P.w, P.h
	if cw / ch > ca then cw = ch * ca else ch = cw / ca end
	local x0, y0 = P.x + (P.w - cw) / 2, P.y + (P.h - ch) / 2
	surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
	RoundPoly(r.x, r.y, r.w, r.h, rad, x0 / W, y0 / H, (x0 + cw) / W, (y0 + ch) / H)
end
-- everything of the viewer except the picture (black background, bars), faded
local function ViewerAround(mat, P, alpha)
	if alpha <= 0.004 then return end
	surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255 * math.min(alpha, 1))
	local function Q(x, y, w, h)
		if w > 0.5 and h > 0.5 then surface.DrawTexturedRectUV(x, y, w, h, x / W, y / H, (x + w) / W, (y + h) / H) end
	end
	Q(0, 0, W, P.y) Q(0, P.y + P.h, W, H - P.y - P.h) Q(0, P.y, P.x, P.h) Q(P.x + P.w, P.y, W - P.x - P.w, P.h)
	R(P.x, P.y, P.w, P.h, Color(0, 0, 0, 255 * math.min(alpha, 1)))
end

function BeginAnim(wep, st, hasSnap)
	local key = ScreenKey(st)
	local old = wep.STTS_UIKey
	wep.STTS_UIKey = key
	if not old or old == key then return false end
	local kind = AnimKind(wep, old, key)
	local prev = wep.STTS_Anim
	wep.STTS_Anim = nil
	if not kind then wep.STTS_OpenFrom = nil return false end
	local fa, ta = math.floor(old / 10), math.floor(key / 10)
	local icons = wep.STTS_IconRect or {}
	local now = RealTime()
	local a = {kind = kind, t0 = now, snap = hasSnap, dur = DUR[kind]}
	wep.STTS_AnimFrom = old -- fix55: sheet_down of any sheet knows which sheet goes away
	if kind == "open" or kind == "close" then
		local root = kind == "open" and (ROOT_ICON[ta] or ta) or (ROOT_ICON[fa] or fa)
		local ir = (kind == "open" and wep.STTS_OpenFrom) or icons[root]
		a.win, a.root, a.hide, a.icon, a.iw = true, root, root, APP_ICON[root], ir and ir.w or 84
		-- interrupted (iOS: launch an app and shoot it back home while it opens, or catch
		-- it again): the new springs start where the window is now, with its speed
		local live = prev and prev.win and prev.cur and now - (prev.lastAt or 0) < 0.25
		local from = wep.STTS_CloseFrom
		wep.STTS_CloseFrom = nil
		if from and now - (from.at or 0) > 0.3 then from = nil end
		if kind == "open" then
			a.r1 = FULL
			if live and prev.root == root then
				a.r0, a.v, a.k0 = prev.cur, prev.vel, prev.curK
				a.iconA0, a.contentA0 = prev.curIconA or 0, prev.curContentA or 1
			else
				a.r0 = ir and CRect(ir) or ICON_DEF
			end
		else
			local b = wep.STTS_AppBg or BLACK
			a.fill = Color(b.r, b.g, b.b)
			if from then -- released home gesture: the window flies on from under the finger
				a.r0, a.v, a.k0, a.mat = from.r, from.v, from.k, hasSnap and MORPH.mat or nil
			elseif live then
				a.r0, a.v, a.k0 = prev.cur, prev.vel, prev.curK
				a.mat = prev.kind == "close" and prev.mat or (hasSnap and MORPH.mat or nil)
			else
				a.r0, a.k0 = FULL, 0
			end
		end
	elseif kind == "island_in" or kind == "island_out" then a.rect = IslandRect(wep)
	elseif kind == "zoom_in" or kind == "zoom_out" then
		a.rect, a.P = wep.STTS_ThumbRect, ViewerPhotoRect(wep, st)
		a.rad = (kind == "zoom_in" or ta ~= G.APP_GALLERY) and (wep.STTS_ThumbRad or 0) or 0
	end
	wep.STTS_OpenFrom = nil
	wep.STTS_Anim = a
	return true
end

function DrawContent(wep, st, btns, snapMat)
	local own = snapMat ~= nil
	-- interactive iOS edge-swipe back (Settings pages): drag the page right, parent slides in behind
	if st.own and L.edgeBack and SCR.SettingsBack and SCR.SettingsBack[st.app] and not wep.STTS_Anim then
		local p = math.Clamp(L.edgeBack.p or 0, 0, 1)
		local parent, cur = SCR.SettingsBack[st.app], st.app
		local junk, scroll, sel, mx = {}, st.scroll, st.sel, L.maxScroll
		st.app, st.scroll, st.sel = parent, 0, 0 -- the parent page as it was left (top, nothing pressed)
		Scaled(function() DrawApp(wep, st, junk) end, -W * 0.28 * (1 - p), 0, 1)
		R(0, 0, W, H, Color(0, 0, 0, 36 * (1 - p)))
		st.app, st.scroll, st.sel, L.maxScroll = cur, scroll, sel, mx
		Scaled(function() DrawApp(wep, st, btns) end, W * p, 0, 1)
		for i = 1, 8 do R(W * p - i * 2, 0, 2, H, Color(0, 0, 0, 46 * (1 - p) * (1 - i / 9))) end -- soft edge shadow
		return
	end
	-- iOS home gesture (drag up from the home indicator): the app window follows the finger
	local hd = st.own and L.homeDrag
	if hd and hd.from ~= st.app then L.homeDrag, hd = nil, nil end
	if hd and not wep.STTS_Anim then
		DrawHome(wep, st, CardHomeK(hd), ROOT_ICON[st.app] or st.app)
		local mat = ToMorph(function() DrawApp(wep, st, {}) end, own)
		local c = CardRect(hd)
		DrawWindow(mat, BRect(c), 1, nil, 0, wep.STTS_AppBg or BLACK, 1, WinRadius(wep, WinFull(c, 84), 84))
		return
	end
	local a = wep.STTS_Anim
	local t = a and RealTime() - a.t0 or 0
	local p = a and math.Clamp(t / (a.dur or DUR[a.kind] or 0.3), 0, 1) or 1
	if not a or p >= 1 then wep.STTS_Anim, wep.STTS_WinFull = nil, nil DrawApp(wep, st, btns) return end
	local kind = a.kind
	local snap = a.snap and snapMat or nil
	local function Snap(x, y, w, h, alpha, dark)
		if not snap then return end
		local v = 255 * (1 - (dark or 0))
		surface.SetMaterial(snap) surface.SetDrawColor(v, v, v, 255 * alpha)
		surface.DrawTexturedRect(x, y, w, h)
	end
	local function New() DrawApp(wep, st, btns) end
	local r0 = a.rect or {x = W / 2 - 42, y = H / 2 - 42, w = 84, h = 84}
	if a.win then
		-- home -> app (open), app -> home (close), a let-go home swipe springing back (restore)
		local k = WinHomeK(a, t)
		local mat
		if kind == "close" then
			DrawHome(wep, st, k, a.hide, btns) -- the real home screen (tappable), the icon is still lifted
			local ir = (wep.STTS_IconRect or {})[a.root]
			a.r1 = ir and CRect(ir) or ICON_DEF
			a.iw = ir and ir.w or 84
			mat = a.mat or snap
		else
			DrawHome(wep, st, k, a.hide)
			mat = ToMorph(New, own)
			a.fill = wep.STTS_AppBg or BLACK
		end
		local c = WinAt(a, t)
		local full = WinFull(c, a.iw)
		local iconA, contentA, fillA
		if kind == "open" then
			-- the icon turns into the app within the first frames, then the window just grows
			iconA = (a.iconA0 or 1) * (1 - math.Clamp(t / 0.12, 0, 1))
			contentA = 1 - (1 - (a.contentA0 or 0)) * (1 - math.Clamp((t - 0.012) / 0.11, 0, 1))
			fillA = 1 - (1 - (a.contentA0 or 0)) * (1 - math.Clamp(t / 0.03, 0, 1))
		elseif kind == "close" then
			-- the app stays visible until the window is small, then the icon takes over
			contentA = math.Clamp((full - 0.05) / 0.3, 0, 1)
			iconA = 1 - math.Clamp((full - 0.1) / 0.3, 0, 1)
			fillA = math.Clamp((full - 0.02) / 0.2, 0, 1)
		else
			iconA, contentA, fillA = 0, 1, 1
		end
		if not a.icon or a.icon:IsError() then
			-- no icon on the home screen for it: the window fades out where it ends
			if kind == "close" then fillA = math.max(contentA, 0) iconA = 0 end
		end
		DrawWindow(mat, BRect(c), contentA, a.icon, iconA, a.fill or BLACK, fillA, WinRadius(wep, full, a.iw))
		-- remember where the window is (and how fast it goes) for an interruption
		local now = RealTime()
		if a.cur and a.lastAt and now - a.lastAt > 0.001 then
			local dt = now - a.lastAt
			a.vel = {cx = (c.cx - a.cur.cx) / dt, cy = (c.cy - a.cur.cy) / dt, w = (c.w - a.cur.w) / dt, h = (c.h - a.cur.h) / dt}
		end
		a.cur, a.lastAt, a.curK, a.curIconA, a.curContentA = c, now, k, iconA, contentA
		wep.STTS_WinFull = kind == "close" and 0 or full
		-- settled (springs have no fixed end): hand over to the plain screen
		local r1, goal = a.r1, kind == "close" and 1 or 0
		local done = t > 0.2 and math.abs(c.cx - r1.cx) < 0.4 and math.abs(c.cy - r1.cy) < 0.4 and math.abs(c.w - r1.w) < 0.4
			and math.abs(c.h - r1.h) < 0.4 and math.abs(k - goal) < 0.004
		a.settle = done and (a.settle or 0) + 1 or 0
		if a.settle >= 2 then wep.STTS_Anim = nil end
	elseif kind == "island_in" then
		local e = Spring(p)
		-- behind: the old screen zooms in a little and darkens
		if snap then
			local z = 1 + 0.08 * EaseOut(p)
			Snap(W / 2 - W * z / 2, H / 2 - H * z / 2, W * z, H * z, 1, 0.55 * EaseOut(p))
		end
		local s = Lerp(e, r0.w / W, 1)
		local cx, cy = Lerp(e, r0.x + r0.w / 2, W / 2), Lerp(e, r0.y + r0.h / 2, H / 2)
		Scaled(New, cx - W * s / 2, cy - H * s / 2, s, math.Clamp(p * 4, 0, 1))
	elseif kind == "island_out" then
		local e = EaseOut(p)
		New()
		R(0, 0, W, H, Color(0, 0, 0, 140 * (1 - e)))
		if snap then
			local s = Lerp(e, 1, r0.w / W)
			local cx, cy = Lerp(e, W / 2, r0.x + r0.w / 2), Lerp(e, H / 2, r0.y + r0.h / 2)
			Snap(cx - W * s / 2, cy - H * s / 2, W * s, H * s, 1 - math.Clamp((p - 0.4) / 0.6, 0, 1))
		end
	elseif kind == "zoom_in" then
		-- Photos: the grid stays where it is, the picture flies out of its thumbnail on a
		-- spring, the black background and the bars of the viewer fade in around it
		local mat = ToMorph(New, own)
		local e, bk = SpringT(t, 0.42, 0.86), SpringT(t, 0.3, 1)
		Snap(0, 0, W, H, 1)
		if a.P and a.rect then
			ViewerAround(mat, a.P, bk)
			PhotoCrop(mat, a.P, LerpBox(a.rect, a.P, e), Lerp(math.Clamp(e, 0, 1), a.rad or 0, 0))
		else
			local s = Lerp(e, r0.w / W, 1)
			local cx, cy = Lerp(e, r0.x + r0.w / 2, W / 2), Lerp(e, r0.y + r0.h / 2, H / 2)
			surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255 * math.Clamp(t / 0.12, 0, 1))
			surface.DrawTexturedRect(cx - W * s / 2, cy - H * s / 2, W * s, H * s)
		end
	elseif kind == "zoom_out" then
		-- the picture flies back into its thumbnail (the one of the photo you are on now)
		local e, bk = SpringT(t, 0.4, 0.9), SpringT(t, 0.3, 1)
		wep.STTS_GalCell = false -- the grid notes where the current picture is
		New()
		local cell = wep.STTS_GalCell or nil
		wep.STTS_GalCell = nil
		local target = cell or (st.app ~= G.APP_GALLERY and a.rect) or nil
		if snap and a.P and target then
			ViewerAround(snap, a.P, 1 - bk)
			PhotoCrop(snap, a.P, LerpBox(a.P, target, e), Lerp(math.Clamp(e, 0, 1), 0, cell and 0 or (a.rad or 0)))
		elseif snap then
			local s = Lerp(EaseOut(p), 1, 0.6)
			Snap(W / 2 - W * s / 2, H / 2 - H * s / 2, W * s, H * s, 1 - EaseOut(p))
		end
	elseif kind == "push" then
		-- UINavigationController: the old page slides 30 % left under a light dimming, the new one comes in on a critically damped spring
		local e = SpringT(t, 0.42, 1)
		Snap(-W * 0.3 * e, 0, W, H, 1, 0.14 * e)
		local x = W * (1 - e)
		Scaled(New, x, 0, 1)
		for i = 1, 8 do R(x - i * 2, 0, 2, H, Color(0, 0, 0, 46 * (1 - e) * (1 - i / 9))) end -- soft edge shadow
	elseif kind == "pop" then
		local e = SpringT(t, 0.4, 1)
		Scaled(New, -W * 0.3 * (1 - e), 0, 1)
		R(0, 0, W, H, Color(0, 0, 0, 36 * (1 - e)))
		Snap(W * e, 0, W, H, 1)
		for i = 1, 8 do R(W * e - i * 2, 0, 2, H, Color(0, 0, 0, 46 * (1 - e) * (1 - i / 9))) end
	elseif kind == "sheet_up" then
		-- UISheetPresentationController: slides up on a spring without bounce, the dimming with it
		local e = SpringT(t, 0.42, 1)
		wep.STTS_SheetOff, wep.STTS_SheetDim = (H - 86) * (1 - e), math.Clamp(e, 0, 1)
		New()
		wep.STTS_SheetOff, wep.STTS_SheetDim = nil, nil
	elseif kind == "sheet_down" then
		local e = SpringT(t, 0.36, 1)
		local fa = math.floor((wep.STTS_AnimFrom or 0) / 10)
		local SP = SCR.SheetParent
		if SP and SP[fa] == st.app and APPS[fa] then -- fix55: a sheet of another app (it draws its parent itself)
			local mx = L.maxScroll
			wep.STTS_SheetOff, wep.STTS_SheetDim = (H - 86) * e, math.Clamp(1 - e, 0, 1)
			DrawApp(wep, setmetatable({app = fa}, {__index = st}), {})
			wep.STTS_SheetOff, wep.STTS_SheetDim = nil, nil
			if st.own then L.maxScroll = mx end
		elseif st.app == G.APP_THREAD and APPS[G.APP_SEND] then
			-- the sheet itself goes down off the screen, the conversation stays, the dimming goes
			local mx = L.maxScroll
			wep.STTS_SheetOff, wep.STTS_SheetDim = (H - 86) * e, math.Clamp(1 - e, 0, 1)
			DrawApp(wep, setmetatable({app = G.APP_SEND}, {__index = st}), {})
			wep.STTS_SheetOff, wep.STTS_SheetDim = nil, nil
			if st.own then L.maxScroll = mx end
		else
			New()
			Snap(0, H * e, W, H, 1)
		end
	else -- fade
		New()
		Snap(0, 0, W, H, 1 - EaseOut(p))
	end
end

-- the finger let go of the home gesture: past a bit / a flick up = home (the window flies on
-- with the speed of the finger), otherwise it springs back to full screen
function HomeSwipeEnd(w, hd, cancel)
	if not hd or not IsValid(w) then return end
	local now = RealTime()
	if now - (hd.t or 0) > 0.1 then hd.vx, hd.vy = 0, 0 end
	local d = math.max(0, hd.y0 - hd.fy)
	local vy = hd.vy or 0
	local c, v, k = CardRect(hd), CardVel(hd), CardHomeK(hd)
	if not cancel and L.app == hd.from and (vy < -300 or (d > 110 and vy < 200)) then
		w.STTS_CloseFrom = {r = c, v = v, k = k, at = now}
		if IsValid(L.entry) then L.entry:Remove() end
		SetApp({own = true}, G.APP_HOME)
	else
		local root = ROOT_ICON[L.app] or L.app
		w.STTS_Anim = {kind = "restore", t0 = now, r0 = c, r1 = FULL, v = v, k0 = k, win = true, iw = 84,
			root = root, hide = root, dur = DUR.restore}
	end
end
end -- do
SCR.DrawContent, SCR.DrawOverlays = DrawContent, DrawOverlays

--[[---------------------------------------------------------------------------
	which phones get a screen this frame
---------------------------------------------------------------------------]]
local function PhonePose(wep)
	if wep.STTS_DrawFrame and FrameNumber() - wep.STTS_DrawFrame <= 3 then return wep.STTS_DrawPos, wep.STTS_DrawAng end
end

--[[ fix72: one display drawn into its render target, protected: an error inside an app (or a
     function of another addon it calls) used to leave the target pushed and cam.Start2D open -
     the rest of the frame drew into the phone and every display stayed black. now the error
     is printed (every 10 s at most), the target is closed and the next frame tries again ]]
function SCR.SafeDraw72(rt, fn, ...)
	render.PushRenderTarget(rt)
	render.Clear(0, 0, 0, 255)
	cam.Start2D()
	local ok, err = pcall(fn, ...)
	cam.End2D()
	render.PopRenderTarget()
	if ok then return true end
	SCR.ShadeBG = nil
	surface.SetAlphaMultiplier(1)
	local now = RealTime()
	if now >= (SCR.drawErrAt72 or 0) then
		SCR.drawErrAt72 = now + 10
		ErrorNoHalt("[ZPhone] display draw error (the phone keeps going): " .. tostring(err) .. "\n")
	end
	SCR.lastDrawErr72 = tostring(err)
	return false
end
function SCR.OwnTop72(wep, st, btns, mat)
	surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(0, 0, W, H)
	SCR.ShadeBG = mat -- fix19: the shade blurs this (iOS Control Centre backdrop)
	DrawOverlays(wep, st, btns)
	SCR.ShadeBG = nil
	if SCR.TouchDot66 then SCR.TouchDot66(wep) end -- fix66
end
function SCR.OtherDraw72(wep, st, btns)
	DrawContent(wep, st, btns, nil)
	DrawOverlays(wep, st, btns)
end

local VIEW_DIST = 320
local function UpdateScreens()
	local v = STTS_PHONE_VIEW
	if not v then return end
	local mine = MyPhone()
	local cands = {}
	for _, wep in ipairs(ents.FindByClass(CLASS)) do
		local pos, ang = PhonePose(wep)
		if not pos then continue end
		local c, n = G.ScreenWorld(pos, ang, wep)
		local d = v.origin - c
		local dist = d:Length()
		if wep ~= mine and (dist > VIEW_DIST or n:Dot(d) <= 0) then continue end
		cands[#cands + 1] = {wep = wep, dist = wep == mine and -1 or dist}
	end
	table.sort(cands, function(a, b) return a.dist < b.dist end)
	local keep = {}
	for i = 1, math.min(#cands, #SLOTS) do keep[cands[i].wep] = true end
	for _, s in ipairs(SLOTS) do
		if s.wep and (not IsValid(s.wep) or not keep[s.wep]) then
			if IsValid(s.wep) then s.wep.STTS_Slot = nil end
			s.wep, s.ready, s.dark = nil, false, nil
		end
	end
	local now = RealTime()
	for _, cnd in ipairs(cands) do
		local wep = cnd.wep
		if not keep[wep] then continue end
		local slot = wep.STTS_Slot and SLOTS[wep.STTS_Slot]
		if not slot or slot.wep ~= wep then
			for i, s in ipairs(SLOTS) do
				if not s.wep then s.wep, s.ready, s.last, s.dark, wep.STTS_Slot, slot = wep, false, 0, nil, i, s break end
			end
		end
		if not slot then continue end
		-- refresh rate: own phone in hand 60 / 20 fps, others 10 / 5 fps (faster while something animates)
		local rate = wep == mine and (L.raised and 60 or 20) or (cnd.dist < 150 and 10 or 5)
		local isl = wep.STTS_Isl
		if wep.STTS_Anim or wep.STTS_ThemeMove or (isl and (math.abs(isl.vw) > 2 or isl.text)) then rate = math.max(rate, wep == mine and 60 or 24) end
		-- fix17: the shade moving / a list gliding on someone else's phone
		if wep ~= mine and (wep.STTS_ShMove or (wep.STTS_ScrS and math.abs(wep.STTS_ScrS - wep:GetNW2Int("Scroll", 0) / 4) > 0.01)) then rate = math.max(rate, 24) end
		if wep == mine and (math.abs(L.shadeV or 0) > 0.01 or (L.touch and L.touch.shadeDrag)) then rate = math.max(rate, 60) end
		if SCR.FastRate and SCR.FastRate(wep) then rate = math.max(rate, wep == mine and 60 or 24) end -- fix55: ringing alarm
		-- fix61: a display that Auto-Lock switched off: black once, then nothing is drawn
		if SCR.ScreenOff and SCR.ScreenOff(wep) then
			if not slot.dark then
				render.PushRenderTarget(slot.rt) render.Clear(0, 0, 0, 255) render.PopRenderTarget()
				slot.dark, slot.ready = true, true
				wep.STTS_Btn = {}
			end
			continue
		end
		slot.dark = nil
		if now - slot.last < 1 / rate and slot.ready then continue end
		slot.last = now
		local st = State(wep)
		if SCR.Theme then SCR.Theme(wep, st) end -- Settings: palette of THIS phone (smooth light / dark switch)
		wep.STTS_UIdt = math.Clamp(now - (wep.STTS_UIt or now), 0, 0.1)
		wep.STTS_UIt = now
		local btns = {}
		if wep == mine then
			-- own phone: the apps go into a content RT (ping-pong pair). on a screen
			-- change the previous frame stays in the other RT = the snapshot that
			-- the transition animates. status bar / island / home bar go on top.
			if BeginAnim(wep, st, contentOwner == wep) then contentIdx = 3 - contentIdx end
			contentOwner = wep
			local cur, snap = CONTENT[contentIdx], CONTENT[3 - contentIdx]
			SCR.SafeDraw72(cur.rt, DrawContent, wep, st, btns, snap.mat)
			SCR.SafeDraw72(slot.rt, SCR.OwnTop72, wep, st, btns, cur.mat)
		else
			BeginAnim(wep, st, false)
			SCR.SafeDraw72(slot.rt, SCR.OtherDraw72, wep, st, btns)
		end
		surface.SetAlphaMultiplier(1)
		wep.STTS_Btn = btns
		slot.ready = true
	end
end

--[[---------------------------------------------------------------------------
	pointer: an invisible point in UI pixels, the finger follows it.
	the hovered button is the one under the FINGER (with its inertia), so
	what lights up is exactly what the finger will press.
---------------------------------------------------------------------------]]
local speedCvar = CreateClientConVar("stts_phone_finger_speed", "1.6", true, false, "how fast the mouse moves the finger over the display", 0.2, 6)

local function FingerPos(wep)
	if wep.STTS_FingerAt and RealTime() - wep.STTS_FingerAt < 0.25 then return wep.STTS_FingerUX, wep.STTS_FingerUY end
	return L.ux or W * 0.5, L.uy or H * 0.62
end

--[[ fix66: a small grey see-through circle on the display where the finger will press
     (stts_phone_touch_dot, on by default). both settings are in the Z-City settings
     menu (hg_settings, category "Phone") and in the console, not in the GMod options ]]
SCR.dotCvar66 = CreateClientConVar("stts_phone_touch_dot", "1", true, false, "show a small circle on the phone display where the finger presses (0 = off, 1 = on)", 0, 1)
function SCR.TouchDot66(wep)
	if not SCR.dotCvar66:GetBool() or not L.raised or L.look or L.wep ~= wep then return end
	if wep.FingerReady and not wep:FingerReady() then return end
	local x, y = FingerPos(wep)
	if not x or x ~= x or y ~= y then return end
	local down = L.touch ~= nil
	local r = down and 7 or 9
	draw.RoundedBox(r, x - r, y - r, r * 2, r * 2, down and Color(110, 110, 110, 150) or Color(150, 150, 150, 105))
	draw.RoundedBox(r - 3, x - r + 3, y - r + 3, (r - 3) * 2, (r - 3) * 2, down and Color(90, 90, 90, 90) or Color(200, 200, 200, 60))
end
function SCR.ZCityOpts66()
	local st = hg and hg.settings
	if not (istable(st) and istable(st.tbl)) then return false end
	local cat = "Phone"
	st.tbl[cat] = st.tbl[cat] or {}
	st.tbl[cat]["stts_phone_finger_speed"] = {cat, "stts_phone_finger_speed", "Phone Finger Sensitivity", true, false}
	st.tbl[cat]["stts_phone_touch_dot"] = {cat, "stts_phone_touch_dot", "Phone Touch Point Circle", false, false}
	return true
end
if not SCR.ZCityOpts66() then timer.Simple(0, SCR.ZCityOpts66) end
hook.Add("InitPostEntity", "STTS_PhoneZCityOpts66", function() SCR.ZCityOpts66() timer.Simple(3, SCR.ZCityOpts66) end)

local function FindBtn(btns, id)
	for _, b in ipairs(btns or {}) do if b.id == id then return b end end
end

local function UpdatePointer(wep)
	if not L.raised then L.sel = 0 return end
	-- the finger is away (RMB free look, or the hand is still on its way): nothing is under it
	-- (v19.5: landscape = the left thumb, weapon_stts_phone.lua FingerReady)
	if L.look or not wep:FingerReady() then L.sel = 0 return end
	if not L.ux then L.ux, L.uy = W * 0.5, H * 0.62 end
	-- sliding finger: nothing lights up (except the slider it drags)
	if L.touch then
		if L.touch.slider then L.sel = L.touch.slider.id return end
		if L.touch.moved then L.sel = 0 return end
	end
	local fx, fy = FingerPos(wep)
	local sel = 0
	for _, b in ipairs(wep.STTS_Btn or {}) do
		if fx >= b.x and fx <= b.x + b.w and fy >= b.y and fy <= b.y + b.h then sel = b.id break end
	end
	L.sel = sel
end

--[[ LMB held = the finger stays on the glass and slides with the mouse:
     release without moving = a tap (presses what is under the finger),
     moving = scroll (lists, grids, chat), swipe (photo viewer), slider (zoom). ]]
local DRAG_MIN = 14
local function SliderValue(b, fx) return math.Clamp((fx - (b.sx or b.x)) / math.max(b.sw or b.w, 1), 0, 1) end

local function TouchBegin(wep)
	UpdatePointer(wep)
	local fx, fy = FingerPos(wep)
	local btns = wep.STTS_Btn or {}
	local t = {wep = wep, x0 = fx, y0 = fy, sel = L.sel, moved = false, scroll0 = L.scroll}
	local b = L.sel ~= 0 and FindBtn(btns, L.sel)
	if b and b.slider then t.slider = b b.slider(SliderValue(b, fx)) end
	for i = #(btns.zones or {}), 1, -1 do
		local z = btns.zones[i]
		if fx >= z.x and fx <= z.x + z.w and fy >= z.y and fy <= z.y + z.h then t.zone = z break end
	end
	L.touch = t
	L.scrollV, L.scrollGo = 0, nil -- fix17: the finger catches a fling
	t.ls, t.lt, t.v = L.scroll, RealTime(), 0
	-- fix58: the lock screen owns this touch (only the hooks marked .lock get it, not the app under it)
	t.lockK = SCR.LockOwns and SCR.LockOwns(wep, fx, fy) or nil
	-- iOS interactive back: a drag that starts at the left edge of a Settings sub-page
	if (not L.shade or L.shade <= 0.02) and not t.lockK then
		if SCR.SettingsBack and SCR.SettingsBack[L.app] and fx < 30 and not L.edgeBack then t.edgeCand, t.ex0 = true, fx end
		-- iOS home gesture: a drag up that starts at the bottom edge (the home indicator)
		if fy > H - 52 and L.app ~= G.APP_HOME and L.app ~= G.APP_CALL and not L.edgeBack and not wep.STTS_Anim then t.homeCand = true end
	end
	if SCR.ShadeBegin then SCR.ShadeBegin(wep, t) end
	-- fix55: other touch handlers (home screen jiggle mode, Clock: wheels, slide to stop)
	for _, h in ipairs(SCR.TouchHooks or {}) do if h.Begin and (h.lock or not t.lockK) then h.Begin(wep, t, fx, fy) end end
	if wep.Touch then wep:Touch(true) end
	Act("touch", "1")
end

local function TouchMove(wep)
	local t = L.touch
	local fx, fy = FingerPos(wep)
	if t.slider then t.slider.slider(SliderValue(t.slider, fx)) return end
	local dx, dy = fx - t.x0, fy - t.y0
	-- iOS interactive back: the page follows the finger 1:1
	if t.edgeBack then
		local e = L.edgeBack
		local p = math.Clamp((fx - t.ex0) / W, 0, 1)
		local now = RealTime()
		local ddt = now - (e.t or now)
		if ddt > 0.001 then e.v = Lerp(math.Clamp(ddt * 18, 0, 1), e.v or 0, (p - (e.p or p)) / ddt) e.t = now end
		e.p = p
		L.sel = 0
		return
	end
	-- iOS home gesture: the app window sticks to the finger (DrawContent), its speed is tracked
	if t.homeDrag then
		local hd = L.homeDrag
		if not hd then return end
		local now = RealTime()
		local ddt = now - (hd.t or now)
		if ddt > 0.001 then
			local k = math.Clamp(ddt * 18, 0, 1)
			hd.vx = Lerp(k, hd.vx or 0, (fx - hd.fx) / ddt)
			hd.vy = Lerp(k, hd.vy or 0, (fy - hd.fy) / ddt)
			hd.t = now
		end
		hd.fx, hd.fy = fx, fy
		L.sel = 0
		return
	end
	if t.homeCand and not t.moved and dx * dx + dy * dy > DRAG_MIN * DRAG_MIN then
		t.homeCand = nil
		if dy < 0 and -dy > math.abs(dx) * 0.6 then
			t.homeDrag, t.moved, t.edgeCand = true, true, nil
			L.homeDrag = {x0 = t.x0, y0 = t.y0, fx = fx, fy = fy, vx = 0, vy = 0, t = RealTime(), from = L.app}
			L.sel = 0
			return
		end
	end
	if t.edgeCand and not t.moved and dx * dx + dy * dy > DRAG_MIN * DRAG_MIN then
		t.edgeCand = nil
		if dx > 0 and dx > math.abs(dy) then
			t.edgeBack, t.moved = true, true
			L.edgeBack = {p = math.Clamp((fx - t.ex0) / W, 0, 1), v = 0, t = RealTime(), from = L.app}
			L.sel = 0
			return
		end
	end
	if SCR.ShadeMove and SCR.ShadeMove(wep, t, fx, fy, dx, dy, DRAG_MIN) then return end
	for _, h in ipairs(SCR.TouchHooks or {}) do -- fix55
		if h.Move and (h.lock or not t.lockK) and h.Move(wep, t, fx, fy, dx, dy, DRAG_MIN) then return end
	end
	if t.lockK then return end -- fix58
	if not t.moved and dx * dx + dy * dy > DRAG_MIN * DRAG_MIN then
		t.moved = true
		t.x0, t.y0 = fx, fy -- fix17: no jump when the drag starts
		dx, dy = 0, 0
	end
	if not t.moved then return end
	L.sel = 0
	local z = t.zone
	if z and z.kind == "scroll" then
		--[[ fix17: smooth: the content sticks to the finger (no row steps), past the
		     ends it stretches like a rubber band (iOS formula) ]]
		local raw = t.scroll0 + (z.invert and dy or -dy) / math.max(z.step or 80, 10)
		local mx = L.maxScroll or 0
		local function Rub(x) return (1 - 1 / (x * 0.55 / 0.9 + 1)) * 0.9 end
		if raw < 0 then raw = -Rub(-raw) elseif raw > mx then raw = mx + Rub(raw - mx) end
		L.scroll = raw
		local now = RealTime()
		local dt = now - (t.lt or now)
		if dt > 0.001 then
			t.v = Lerp(math.Clamp(dt * 18, 0, 1), t.v or 0, (raw - (t.ls or raw)) / dt)
			t.ls, t.lt = raw, now
		end
	end
end

TouchEnd = function(wep, cancel)
	local t = L.touch
	if not t then return end
	L.touch = nil
	local w = IsValid(t.wep) and t.wep or wep
	if IsValid(w) and w.Touch then w:Touch(false) end
	Act("touch", "0")
	if t.edgeBack and L.edgeBack then
		-- let go: finish like iOS (past half, or a flick to the right = back; else it springs back)
		local e = L.edgeBack
		local v = RealTime() - (e.t or 0) < 0.1 and (e.v or 0) or 0
		e.go = (not cancel) and ((e.p or 0) > 0.5 or v > 1.2) and 1 or 0
		e.v = v
		e.rel = true
		return
	end
	if t.homeDrag then
		local hd = L.homeDrag
		L.homeDrag = nil
		HomeSwipeEnd(w, hd, cancel)
		return
	end
	if SCR.ShadeEnd and SCR.ShadeEnd(w, t, cancel) then return end
	for _, h in ipairs(SCR.TouchHooks or {}) do -- fix55
		if h.End and (h.lock or not t.lockK) and h.End(w, t, cancel) then return end
	end
	if t.lockK then return end -- fix58
	-- fix17: let go while scrolling = fling (slows down by itself, see STTS_PhoneScroll)
	if t.moved and t.zone and t.zone.kind == "scroll" and RealTime() - (t.lt or 0) < 0.1 then
		L.scrollV = math.Clamp(t.v or 0, -40, 40)
	end
	if cancel or t.slider or not IsValid(w) then return end
	local fx, fy = FingerPos(w)
	local dx, dy = fx - t.x0, fy - t.y0
	if t.moved then
		local z = t.zone
		if z and z.kind == "swipe" and math.abs(dx) > 50 and math.abs(dx) > math.abs(dy) * 1.2 then z.fn(dx < 0 and 1 or -1) end
		return
	end
	-- a tap: press what was under the finger
	UpdatePointer(w)
	local id = t.sel ~= 0 and t.sel or L.sel
	if id == 0 then return end
	local b = FindBtn(w.STTS_Btn, id)
	if b and b.action then Click() b.action() end
end

function SCR.Primary(wep)
	if wep:GetOwner() ~= LocalPlayer() then return end
	if L.wep ~= wep then Adopt(wep) end
	if not L.raised then SCR.SetRaised(wep, true) end
	-- raised: the finger (LMB press / hold / release) is handled in STTS_PhoneTouch
end

-- R: fully down, also from the call poses (phone at the ear / held out for video)
function SCR.Reload(wep)
	if wep:GetOwner() ~= LocalPlayer() then return end
	if L.wep ~= wep then Adopt(wep) end
	if L.raised then SCR.SetRaised(wep, false, false, true) return end
	if not L.down then L.down = true Act("down") end
end

--[[ fix71: some servers / custom Z-City builds / other addons eat the attack and reload keys
     before the weapon sees them (CreateMove / StartCommand hooks, blocked PrimaryAttack): LMB
     then never raised the phone and never touched the display. the keys the player bound
     to +attack / +reload are read straight from the keyboard as a fallback
     (stts_phone_input_fallback 0 = off) ]]
SCR.fallbackCvar71 = CreateClientConVar("stts_phone_input_fallback", "1", true, false, "1 = LMB / R / RMB also work with the phone when another addon or the server build eats those keys", 0, 1)
SCR.bindKeys71 = {}
function SCR.BindKey71(bind, def)
	local c = SCR.bindKeys71[bind]
	local now = RealTime()
	if not c or now > c.t then
		local name = input.LookupBinding(bind, true)
		local code = name and input.GetKeyCode(name) or nil
		c = {t = now + 1, code = (code and code > 0) and code or def}
		SCR.bindKeys71[bind] = c
	end
	return c.code
end
function SCR.BindDown71(bind, def)
	local code = SCR.BindKey71(bind, def)
	return code ~= nil and input.IsButtonDown(code) or false
end
-- the keyboard is ours: no menu / chat / text field / kick, alive and awake
function SCR.FreeInput71(lp)
	if gui.IsGameUIVisible() or vgui.CursorVisible() or IsValid(vgui.GetKeyboardFocus()) then return false end
	if not IsValid(lp) or not lp:Alive() or (lp.IsTyping and lp:IsTyping()) then return false end
	if STTS.PhoneKick and STTS.PhoneKick.K then return false end
	local org = lp.organism
	if org and org.otrub then return false end
	return true
end

hook.Add("Think", "STTS_PhoneTouch", function()
	local lp = LocalPlayer()
	local ui = gui.IsGameUIVisible() or vgui.CursorVisible()
	local down = IsValid(lp) and lp:KeyDown(IN_ATTACK) and not ui
	local fb = SCR.fallbackCvar71:GetBool()
	local raw = fb and SCR.BindDown71("+attack", MOUSE_LEFT) or false
	local rawWas = L.lmbRaw71
	L.lmbRaw71 = raw
	local wep = MyPhone()
	-- fix71: LMB raises the phone even when PrimaryAttack never comes. the normal way gets a moment
	-- first, and not the click that picked the phone in the weapon menu
	local now = RealTime()
	if L.seenWep71 ~= wep then L.seenWep71, L.seenAt71, L.raisePend71 = wep, now, nil end
	if raw and not rawWas and wep and not L.raised and now - (L.seenAt71 or now) > 0.5 and SCR.FreeInput71(lp) then
		L.raisePend71 = now + 0.15
	end
	if L.raisePend71 and now >= L.raisePend71 then
		L.raisePend71 = nil
		if wep and not L.raised and SCR.FreeInput71(lp) then SCR.Primary(wep) end
	end
	if not down and raw and L.raised and L.wep == wep and SCR.FreeInput71(lp) then down = true end
	local was = L.lmbWas
	L.lmbWas = down
	if not wep or L.wep ~= wep or not L.raised or L.look then
		if L.touch then TouchEnd(wep, true) end
		return
	end
	if down and not was then
		if L.touch then TouchEnd(wep, true) end
		if not wep:FingerReady() then return end -- the finger (landscape: the thumb) is not at the glass yet
		if L.raiseAt and RealTime() - L.raiseAt < 0.3 then return end -- the press that raised the phone
		TouchBegin(wep)
	elseif down and L.touch then
		TouchMove(wep)
	elseif not down and L.touch then
		TouchEnd(wep)
	end
end)

-- fix71: R (whatever key +reload is on) puts the phone down even when SWEP:Reload never comes
hook.Add("Think", "STTS_PhoneReload71", function()
	local raw = SCR.fallbackCvar71:GetBool() and SCR.BindDown71("+reload", KEY_R) or false
	local was = L.relRaw71
	L.relRaw71 = raw
	if not raw or was then return end
	local wep = MyPhone()
	if not wep or L.wep ~= wep or (not L.raised and L.down) then return end
	if not SCR.FreeInput71(LocalPlayer()) then return end
	SCR.Reload(wep)
end)

-- raised: the mouse moves the finger over the display, the view stays
-- (RMB: the finger on / off, stts_phone_controls)
function SCR.PointerWants71()
	local wep = MyPhone()
	if not wep or L.wep ~= wep or not L.raised or L.look then return nil end
	if STTS.PhoneKick and STTS.PhoneKick.K then return nil end -- the kick has the mouse (sh_phone_kick.lua)
	return wep
end
function SCR.MoveFinger71(wep, x, y)
	local sens = (GetConVar("sensitivity") and GetConVar("sensitivity"):GetFloat() or 3) / 3
	local k = speedCvar:GetFloat() * sens
	-- v19.4: on the turned (landscape) phone the finger still goes where the mouse goes as
	-- you see it: the move is turned into the axes of the display
	local le = SCR.LandK(wep)
	if le > 0.0005 then
		local r = math.rad(90 * le)
		local c, sn = math.cos(r), math.sin(r)
		x, y = x * c + y * sn, y * c - x * sn
	end
	L.ux = math.Clamp((L.ux or W * 0.5) + x * k, 0, W)
	L.uy = math.Clamp((L.uy or H * 0.62) + y * k, 0, H)
	L.moveAt71 = RealTime()
end
local function PhonePointer(cmd, x, y, ang)
	local wep = SCR.PointerWants71()
	if not wep then return end
	SCR.MoveFinger71(wep, x, y)
	cmd:SetViewAngles(ang)
	return true
end
SCR.PhonePointer = PhonePointer
--[[ fix71 ("the finger does not move"): Z-City's own InputMouseApply hook ("fakeCameraAngles",
     cl_fake.lua) always returns true. which of the two runs first depends on the hook order,
     and that changes with the other addons / the Z-City build: if Z-City came first, ours
     never ran = the finger stood still and the view turned. now the finger also moves from
     inside Z-City's mouse hook (HG.InputMouseApply), and cl_compat.lua puts the phone in
     front of the foreign InputMouseApply hooks (community fix, ported) ]]
hook.Add("HG.InputMouseApply", "STTS_PhonePointer", function(tbl)
	local wep = SCR.PointerWants71()
	if not wep or not istable(tbl) then return end
	SCR.MoveFinger71(wep, tonumber(tbl.x) or 0, tonumber(tbl.y) or 0)
	tbl.x, tbl.y = 0, 0
end)
hook.Add("InputMouseApply", "STTS_PhonePointer", PhonePointer)

--[[ fix17: the mouse wheel does NOT scroll any more (only the finger: LMB held + drag).
     after the finger lets go: the fling glides and slows down, past an end the
     content springs back; the "newest" chip of a chat glides back to the bottom. ]]
hook.Remove("CreateMove", "STTS_PhoneWheel")
hook.Add("Think", "STTS_PhoneScroll", function()
	local dt = math.Clamp(RealTime() - (L.scrollT or RealTime()), 0, 0.1)
	L.scrollT = RealTime()
	local eb = L.edgeBack
	if eb and eb.rel and dt > 0 then
		-- released edge swipe: critically damped spring to 0 (stay) or 1 (back), keeps the hand speed
		local w = 2 * math.pi / 0.36
		local steps = math.max(1, math.ceil(dt / (1 / 240)))
		local h = dt / steps
		for _ = 1, steps do
			eb.v = eb.v + (w * w * (eb.go - eb.p) - 2 * w * eb.v) * h
			eb.p = eb.p + eb.v * h
		end
		if eb.p >= 0.999 or (eb.go == 1 and eb.p > 0.995) then
			L.edgeBack = nil
			if L.app == eb.from and SCR.SettingsBack and SCR.SettingsBack[L.app] then
				if SCR.SettingsLeave then SCR.SettingsLeave(L.app) end
				local parent = SCR.SettingsBack[L.app]
				local wep = L.wep
				L.app, L.scroll, L.sel, L.scrollV, L.scrollGo = parent, 0, 0, 0, nil
				if IsValid(wep) then wep.STTS_UIKey = ScreenKey({app = parent}) end -- no second (pop) animation
			end
		elseif eb.go == 0 and eb.p < 0.002 and math.abs(eb.v) < 0.05 then
			L.edgeBack = nil
		end
	elseif eb and not eb.rel and not (L.touch and L.touch.edgeBack) then
		L.edgeBack = nil
	end
	if eb and L.app ~= eb.from then L.edgeBack = nil end
	if L.touch or dt <= 0 then return end
	local s, v, mx = L.scroll or 0, L.scrollV or 0, L.maxScroll or 0
	if L.scrollGo then
		s = L.scrollGo + (s - L.scrollGo) * math.exp(-dt * 9)
		if math.abs(s - L.scrollGo) < 0.01 then s, L.scrollGo = L.scrollGo, nil end
		L.scroll, L.scrollV = s, 0
		return
	end
	if s < 0 or s > mx then
		-- past an end: the fling dies fast, a stiff spring pulls the content back
		local edge = s < 0 and 0 or mx
		v = v * math.exp(-dt * 26)
		s = s + v * dt
		s = edge + (s - edge) * math.exp(-dt * 13)
		if math.abs(s - edge) < 0.004 and math.abs(v) < 0.3 then s, v = edge, 0 end
	elseif v ~= 0 then
		s = s + v * dt
		v = v * math.exp(-dt * 2.0) -- iOS-like deceleration (UIScrollView decelerationRate "normal")
		s = math.Clamp(s, -0.5, mx + 0.5)
		if math.abs(v) < 0.08 then v = 0 end
	else
		return
	end
	L.scroll, L.scrollV = s, v
end)

hook.Add("PlayerBindPress", "STTS_PhoneBinds", function(_, bind, pressed, code)
	if not L.raised or not MyPhone() then return end
	if string.find(bind, "invnext", 1, true) or string.find(bind, "invprev", 1, true) then return true end
	-- v19.4: T turns the phone (whatever T is bound to does not run meanwhile)
	if code == KEY_T or (code == nil and input.IsKeyDown(KEY_T) and input.LookupKeyBinding(KEY_T) == bind) then return true end
end)

-- v19.4: T = landscape / portrait of the raised phone (weapon_stts_phone.lua turns it)
hook.Add("Think", "STTS_PhoneLandToggle", function()
	local down = input.IsKeyDown(KEY_T)
	local was = L.tWas
	L.tWas = down
	if not down or was then return end
	local wep = MyPhone()
	if not wep or L.wep ~= wep or not L.raised then return end
	if gui.IsGameUIVisible() or vgui.CursorVisible() or IsValid(vgui.GetKeyboardFocus()) then return end
	local lp = LocalPlayer()
	if lp.IsTyping and lp:IsTyping() then return end
	-- fix61: Rotation Lock (Control Centre) = it stays upright (back to portrait still works)
	local cc = State(wep).cc
	if cc and cc.rotlock and not SCR.LocalLand(wep) then return end
	L.land, L.landAt = not SCR.LocalLand(wep), RealTime()
	Act("land", L.land and "1" or "0")
end)

-- fix61: no free look hint on the HUD any more (no cursor either: the finger is the cursor)
hook.Remove("HUDPaint", "STTS_PhonePointer")

SCR.forceCvar71 = CreateClientConVar("stts_phone_finger_force", "1", true, false, "1 = the finger works unless the right arm is missing (ignores the extra right hand rules of custom Z-City builds), 0 = ask hg.CanUseRightHand", 0, 1)
cvars.AddChangeCallback("stts_phone_controls", function()
	if L.look and SCR.Controls72() ~= 0 then L.look = false Act("unlook") end
end, "STTS_PhoneControls72")
-- RMB: the finger on / off while the phone is up (stts_phone_controls 2: raise / lower)
function SCR.LookToggle71()
	local down = SCR.BindDown71("+attack2", MOUSE_RIGHT)
	local was = L.rmbWas
	L.rmbWas = down
	if not down or was then return end
	local wep = MyPhone()
	if not wep then L.look = false return end
	if not SCR.FreeInput71(LocalPlayer()) then return end
	if SCR.Controls72() == 2 then
		if L.look then L.look = false Act("unlook") end
		SCR.SetRaised(wep, not (L.wep == wep and L.raised))
		if L.raised and STTS.PhoneMouseWrap72 then STTS.PhoneMouseWrap72() end
		return
	end
	if not L.raised or L.wep ~= wep then L.look = false return end
	L.look = not L.look
	if L.look and L.touch then TouchEnd(L.wep, true) end
	-- the finger takes the mouse: other addons that put their mouse hook in again meanwhile
	-- are put behind the phone right now (cl_compat.lua), not 3 s later
	if not L.look and STTS.PhoneMouseWrap72 then STTS.PhoneMouseWrap72() end
	Act(L.look and "look" or "unlook") -- the right hand drops / comes for everybody
end
hook.Add("Think", "STTS_PhoneLookToggle", SCR.LookToggle71)

--[[---------------------------------------------------------------------------
	the phone inside the original Z-City systems (wrapped once they exist):
	* hg.ShouldTPIK + "CanBeSeenOrNot": players / ragdolls next to a phone
	  camera that is being rendered are animated like the ones you look at.
---------------------------------------------------------------------------]]
local function InstallWraps()
	if hg then
		-- fix10: car wheel / ragdoll hand wraps removed, ragdoll works like fix8
		if hg.ShouldTPIK and hg.ShouldTPIK ~= SCR.wTPIK then
			local orig = hg.ShouldTPIK
			SCR.wTPIK = function(ply, wpn)
				-- fix22: ragdolls too (the hand holding the phone stays posed in the picture)
				if next(SCR.Cams) and IsValid(ply) and ply ~= LocalPlayer() and SCR.NearCam(BodyPos(ply), 1024) then return true end
				return orig(ply, wpn)
			end
			hg.ShouldTPIK = SCR.wTPIK
		end
	end
	local t = hook.GetTable()
	local seen = t.Think and t.Think.CanBeSeenOrNot
	-- fix64: the table may hold a wrapper of SCR.wSeen (profiler / other addons): that is ours too,
	-- else one more layer every 3 s (and one more MarkSeen per frame) for the whole session
	SCR.oursSeen64 = SCR.oursSeen64 or setmetatable({}, { __mode = "k" })
	if seen and seen ~= SCR.wSeen and not SCR.oursSeen64[seen] then
		local orig = seen
		SCR.wSeen = function(...)
			orig(...)
			SCR.MarkSeen()
		end
		SCR.oursSeen64[SCR.wSeen] = true
		hook.Add("Think", "CanBeSeenOrNot", SCR.wSeen)
		local now = hook.GetTable().Think
		if now and isfunction(now.CanBeSeenOrNot) then SCR.oursSeen64[now.CanBeSeenOrNot] = true end
	end
end
hook.Add("InitPostEntity", "STTS_PhoneWraps", InstallWraps)
timer.Create("STTS_PhoneWraps", 3, 0, InstallWraps)
InstallWraps()

--[[---------------------------------------------------------------------------
	per frame
---------------------------------------------------------------------------]]
--[[ homigrad's own RenderScene hook (cl_camera.lua, "jopa") draws the whole
     world itself and returns true, so no other RenderScene hook ever runs:
     the screens were never drawn (black display) and the pointer never hit.
     the main view is taken from the 3D pass instead, and the per-frame work
     runs in PreRender (one frame of lag, not visible). ]]
local function CaptureView(depth, sky)
	if depth or sky or SCR.InRV then return end
	local rt = render.GetRenderTarget()
	local v = STTS_PHONE_VIEW or {}
	local now = RealTime()
	if rt and rt:GetName() ~= "fb_flipped" then -- scopes, mirrors, phone cameras
		--[[ fix72 (black display): some Z-City builds / post-process addons draw the whole main
		     view into a render target of their own (another name than Z-City's "fb_flipped"):
		     the view was never taken, no display was ever drawn. a target the size of the
		     screen counts when no normal main view came for a while ]]
		if v.main72 and now - v.main72 < 0.5 then return end
		if rt:Width() ~= ScrW() or rt:Height() ~= ScrH() or string.find(rt:GetName(), "stts_", 1, true) then return end
	else
		v.main72 = now
	end
	v.origin, v.angles, v.t, v.fb72 = EyePos(), EyeAngles(), now, nil
	STTS_PHONE_VIEW = v
end
-- also BEFORE the opaque pass: the body (and the phone IK) is drawn inside it, so the
-- raised phone uses the view of THIS frame (with only the post hook it was one frame
-- behind, which made the phone trail behind the head while walking)
hook.Add("PreDrawOpaqueRenderables", "STTS_PhoneView", CaptureView)
hook.Add("PostDrawOpaqueRenderables", "STTS_PhoneView", CaptureView)

hook.Add("PreRender", "STTS_PhoneScreens", function()
	--[[ fix72: a phone camera that failed half way (an error before its protected part, e.g. in
	     another addon's draw function) left InRV on: every display stayed black for the rest
	     of the session. nothing renders a phone camera across two frames ]]
	if SCR.InRV then
		SCR.rvStuck72 = (SCR.rvStuck72 or 0) + 1
		if SCR.rvStuck72 < 2 then return end
		SCR.InRV, SCR.RVWep, STTS_PHONE_SELFIE, SCR.rvStuck72 = false, nil, nil, 0
		if not SCR.rvWarn72 then SCR.rvWarn72 = true print("[ZPHONE] a phone camera render did not finish (another addon errored inside it); the displays are drawn again") end
	end
	SCR.rvStuck72 = 0
	-- fix72: no main view caught at all (the 3D hooks blocked by another addon): the eyes of the player
	local v = STTS_PHONE_VIEW
	if not v or v.fb72 or RealTime() - (v.t or 0) > 0.5 then
		local lp = LocalPlayer()
		if IsValid(lp) then
			v = v or {}
			-- (older than the 0.25 s the held phone trusts: it keeps to the head bone)
			v.origin, v.angles, v.t, v.fb72 = lp:EyePos(), lp:EyeAngles(), RealTime() - 0.3, true
			STTS_PHONE_VIEW = v
		end
	end
	if not STTS_PHONE_VIEW then return end
	local wep = MyPhone()
	if wep then UpdatePointer(wep) end
	UpdateScreens()
end)

hook.Add("PreDrawHUD", "STTS_PhoneViewFov", function()
	if SCR.InRV then return end
	if not STTS_PHONE_VIEW then return end
	local diag=STTS.PhoneDiag47
 local vs
 if diag and diag.Call then vs=diag.Call('engine.GetViewSetup',render.GetViewSetup)else vs=render.GetViewSetup()end
	if vs and vs.fov then STTS_PHONE_VIEW.fov = vs.fov end
	-- fix72: the 3D hooks did not give the view this frame: the view setup of the main view
	local v = STTS_PHONE_VIEW
	if vs and vs.origin and vs.angles and (v.fb72 or RealTime() - (v.t or 0) > 0.1) then
		v.origin, v.angles, v.t, v.fb72 = vs.origin, vs.angles, RealTime(), nil
	end
end)

function SCR.RecordPose31(wep)
	local lp = LocalPlayer()
	local own = wep:GetOwner() == lp and lp:Alive() and lp:GetActiveWeapon() == wep
	local pos, ang
	if own then pos, ang = PhonePose(wep) else pos, ang = SourcePose(wep:EntIndex()) end
	local front
	if own then front = State(wep).front == true else front = wep:GetNW2Bool("CamFront", false) end
	if pos and not own and not IsValid(wep:GetOwner()) and not IsValid(wep:GetParent()) and SCR.LensBlocked(pos, ang, not front, wep) then front = not front end
	return pos, ang, front, own and L.zoom or FeedZoom(wep:EntIndex())
end
SCR.RecordAction31 = Act

--[[ video recording: every 1 / G.VidFps s the camera is rendered into a
     small frame and copied into a slot of the page atlas. a full page (or
     the end of the video) is captured as one jpg and uploaded like a photo,
     then the video item is created on the server (stts_phone_vid). ]]
-- fix16: as big as the sharpest preset, a frame uses its top left w x h
local frameRT = GetRenderTargetEx("stts_phone_vframe16", G.FrameMaxW, G.FrameMaxH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGB888)
local frameMat = CreateMaterial("stts_phone_vframem", "UnlitGeneric", {["$basetexture"] = frameRT:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1})
-- Three bounded GPU pages: pack one, encode a completed page on an idle
-- render frame when available. Never allocate a render target per page/clip.
SCR.VideoEncoder = {queue = {}, targets = {}}
for i = 1, 3 do
	SCR.VideoEncoder.targets[i] = {rt = GetRenderTargetEx("stts_phone_vatlas30_" .. i, 1024, 1024,
		RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)}
end
local atlasRT = SCR.VideoEncoder.targets[1].rt
SCR.ResetVideoEncoder = function()
	SCR.VideoEncoder.queue = {}
	for _, target in ipairs(SCR.VideoEncoder.targets) do target.busy = false end
	atlasRT = SCR.VideoEncoder.targets[1].rt
end

local function ClearAtlas()
	render.PushRenderTarget(atlasRT)
		render.Clear(0, 0, 0, 255)
	render.PopRenderTarget()
end

function SCR.StartRec(wep, front)
	if STTS.PhoneRecorder31 and STTS.PhoneRecorder31.Enabled() then
		return STTS.PhoneRecorder31.Start(wep, front)
	end
	if L.rec or SCR.Export then L.toast, L.toastAt = "Wait for save", RealTime() return end
	-- fix30: 15 fps, native 256 x 448, Q88; EIS is applied before atlas packing.
	local fps, res = G.RecFps(), G.RecRes()
	L.rec = {wep = wep, frames = 0, pageFrames = 0, pages = {}, counts = {}, pending = 0, next = RealTime(), token = math.random(1, 65535), clear = true, startAt = RealTime(),
		eis = STTS.PhoneEIS and STTS.PhoneEIS.New(),
		fps = fps, res = res, lay = G.VidLayout(res), q = G.RecQ(), maxFrames = G.VidMaxFrames(res, fps), maxPages = G.VidPagesFor(res, fps)}
	Act("cam", "2")
end

--[[ fix16: a recording ends ONLY when somebody taps the red shutter (force), the
     2 minutes are over or the phone is gone. lowering the phone, putting it away,
     dropping it, a ragdoll, your death: it keeps filming (RecordStep). ]]
StopRec = function(force)
	local r = L.rec
	if r and r.modern then if force then STTS.PhoneRecorder31.Stop() end return end
	if not r or r.stop then return end
	if not force then return end
	r.stop = true
	if r.frames == 0 then L.rec = nil end
	Act("cam", tostring(L.camMode or 0))
	Act("recstop") -- the phone may be in somebody else's hand by now
end

local function FinishRec(r)
	if r.sent or r.pending > 0 or not r.closed then return end
	r.sent = true
	-- fix15: a rejected page no longer throws the whole video away, it is just cut out
	local pages, frames = {}, 0
	for slot, id in ipairs(r.pages) do
		if not id or id == 0 then break end
		if id and id ~= 0 and #pages < math.min(G.VidMaxPagesNet, r.maxPages or G.VidMaxPagesNet) then
			pages[#pages + 1] = id
			frames = frames + (r.counts[slot] or 0)
		end
	end
	if #pages == 0 or frames == 0 then L.rec = nil SCR.RecPreview = nil L.toast, L.toastAt = "Recording failed", RealTime() return end
	r.pages, r.frames = pages, frames
	SCR.VidJobs = SCR.VidJobs or {}
	SCR.VidJobs[r.token] = r
	net.Start("stts_phone_vid")
		net.WriteUInt(r.token, 16)
		net.WriteUInt(#pages, 9)
		for _, id in ipairs(pages) do net.WriteUInt(id, 32) end
		net.WriteUInt(math.min(frames, G.VidMaxFramesNet), 12)
		net.WriteUInt(r.fps or G.VidFps, 5)
		net.WriteUInt(r.res or G.VidResDefault, 3)
	net.SendToServer()
	SCR.LastRecording = {frames = frames, fps = r.fps, seconds = RealTime() - r.startAt,
		maxEncodeMs = r.maxEncodeMs or 0, uniqueFrames = r.uniqueFrames or 0, duplicated = r.duplicated or 0, failed = r.failed or false}
	SCR.RecPreview = nil
	L.rec = nil
end

net.Receive("stts_phone_vok", function()
	local token, id = net.ReadUInt(16), net.ReadUInt(32)
	local r = SCR.VidJobs and SCR.VidJobs[token]
	if not r then return end
	SCR.VidJobs[token] = nil
 if r.onShared then r.onShared(id) return end
	if id == 0 then return end
	VIDS[id] = {pages = table.Copy(r.pages), frames = r.frames, fps = r.fps or G.VidFps, res = r.res or G.VidResDefault}
	if SCR.M49 then SCR.M49.have[id] = true end -- fix53
	if L.wep == r.wep and IsValid(r.wep) and r.wep:GetOwner() == LocalPlayer() then L.gal = #State(r.wep).photos + 1 L.album = 0 end
end)

-- Readback/JPEG cannot be asynchronous in stock GMod Lua; defer it to an
-- idle game frame instead of piling it onto every fourth RenderView.
function SCR.EncodeVideoPage(force)
	local queue = SCR.VideoEncoder.queue
	local job = queue[1]
	if not job then return end
	if not force and SCR.RecordRenderedFrame == FrameNumber() and RealTime() - job.at < 0.12 then return end
	table.remove(queue, 1)
	local r, l = job.rec, job.rec.lay
	render.PushRenderTarget(job.target.rt)
	local began = SysTime()
	local jpg = render.Capture({format = "jpg", quality = r.q, x = 0, y = 0, w = l.aw, h = l.ah, alpha = false})
	local comp = jpg and util.Compress(jpg)
	r.encodeMs = (SysTime() - began) * 1000
	r.maxEncodeMs = math.max(r.maxEncodeMs or 0, r.encodeMs)
	render.PopRenderTarget()
	job.target.busy = false
	if not comp or #comp > G.PhotoMaxBytes then
		r.pending = r.pending - 1
		r.pages[job.slot] = 0
		r.failed, r.stop = true, true
		L.toast, L.toastAt = "Video page too large", RealTime()
		FinishRec(r)
		return
	end
	Upload(r.wep, jpg, true, function(id)
		r.pending = r.pending - 1
		r.pages[job.slot] = id
		if not id or id == 0 then
			r.failed, r.stop = true, true
			L.toast, L.toastAt = "Upload failed: clip truncated", RealTime()
		end
		FinishRec(r)
	end, comp)
end

local function FlushPage(r)
	local slot = #r.pages + 1
	r.counts[slot], r.pages[slot] = r.pageFrames, false
	r.pageFrames, r.clear = 0, true
	r.pending = r.pending + 1
	for _, target in ipairs(SCR.VideoEncoder.targets) do
		if target.rt == atlasRT then
			target.busy = true
			SCR.VideoEncoder.queue[#SCR.VideoEncoder.queue + 1] = {rec = r, slot = slot, target = target, at = RealTime()}
			break
		end
	end
	-- Normally two free targets remain. On a very slow render thread, force
	-- ONE queued encode rather than overwriting an unfinished page or leaking RAM.
	local free
	for _, target in ipairs(SCR.VideoEncoder.targets) do if not target.busy then free = target break end end
	if not free then
		SCR.EncodeVideoPage(true)
		for _, target in ipairs(SCR.VideoEncoder.targets) do if not target.busy then free = target break end end
	end
	if free then atlasRT = free.rt end
end

-- the inventory can recreate the phone entity: find the one that carries this recording
local function RecWep(r)
	if IsValid(r.wep) then return r.wep end
	if not r.recAt then return end
	local lp = LocalPlayer()
	for _, w in ipairs(ents.FindByClass(CLASS)) do
		if w:GetNW2Entity("RecBy", NULL) == lp and math.abs(w:GetNW2Float("RecAt", 0) - r.recAt) < 0.05 then
			r.wep = w
			return w
		end
	end
end

--[[ fix16: lying loose in the world with the lens against the floor / a wall = the
     camera would film pure black: the phone films with its other camera instead ]]
function SCR.LensBlocked(pos, ang, back, wep)
	local cpos, cang = G.CamWorld(pos, ang, back, wep)
	local tr = util.TraceLine({start = pos, endpos = cpos + cang:Forward() * 2.5, filter = wep, mask = MASK_VISIBLE_AND_NPCS})
	return tr.Hit and not tr.StartSolid
end

-- fix54: record tapped on a 2nd phone while a clip still ran on the 1st one
function SCR.RecNextStep()
	local n = L.recNext
	if not n then return end
	if L.rec or SCR.Export then if RealTime() - n.at > 20 then L.recNext = nil end return end
	L.recNext = nil
	local wep, lp = n.wep, LocalPlayer()
	if RealTime() - n.at > 20 or not IsValid(wep) or not IsValid(lp) or lp:GetActiveWeapon() ~= wep or L.wep ~= wep or L.app ~= G.APP_CAMERA then return end
	if wep:GetNW2Int("CamMode", 0) == 2 then return end -- somebody else films with it now
	L.camMode = 1
	SCR.StartRec(wep, n.front)
end

local function RecordStep()
	local r = L.rec
	if not r and L.recNext then SCR.RecNextStep() end
	if r and r.modern then return STTS.PhoneRecorder31.Step(r) end
	SCR.ActiveRecording = r
	if not r then return end
	if not r.closed then
		local lp = LocalPlayer()
		local now = RealTime()
		local wep = RecWep(r)
		if not wep then
			-- gone (removed / being recreated by an inventory): wait a little, then end the video
			r.lostAt = r.lostAt or now
			if now - r.lostAt > 3 then r.stop = true end
		else
			r.lostAt = nil
			-- the server confirmed the recording: from then on a stop by ANYBODY (red shutter
			-- on this phone, whoever holds it now) ends it
			if wep:GetNW2Int("CamMode", 0) == 2 and wep:GetNW2Entity("RecBy", NULL) == lp then
				r.seen, r.recAt = true, wep:GetNW2Float("RecAt", 0)
			elseif r.seen or now - r.startAt > 4 then
				r.stop = true -- stopped by somebody / the server never took the recording
			end
		end
		local fps = r.fps or G.VidFps
		if r.pending >= 8 then
			r.stop, r.failed = true, true
			L.toast, L.toastAt = "Upload too slow: recording stopped", RealTime()
		end
		local maxFrames = r.maxFrames or REC_MAX
		if now - r.startAt >= (G.VidMaxSec or 120) or r.frames >= maxFrames then r.stop = true end
		local idx, own, pos, ang, front
		if wep then
			idx = wep:EntIndex()
			own = wep:GetOwner() == lp and lp:Alive() and lp:GetActiveWeapon() == wep
			if own then pos, ang = PhonePose(wep) else pos, ang = SourcePose(idx) end -- fix19: as in fix16
			if own then front = State(wep).front == true else front = wep:GetNW2Bool("CamFront", false) end
			-- fix16: fallen phone with its lens on the floor: the other camera films
			if pos and not own and not IsValid(wep:GetOwner()) and not IsValid(wep:GetParent()) and SCR.LensBlocked(pos, ang, not front, wep) then front = not front end
			if r.eis and STTS.PhoneEIS and pos then
				r.eis.mode = STTS.PhoneEIS.Mode(r.wep)
				local _, ca = G.CamWorld(pos, ang, not front, wep)
				STTS.PhoneEIS.Sample(r.eis, ca, now, tostring(idx) .. ":" .. tostring(front))
			end
		end
		SCR.ActiveRecording = r
		if not r.stop and wep and now >= r.next then
			if r.clear then ClearAtlas() r.clear = false end
			local l = r.lay or G.VidLayout(r.res)
			if pos then
				if r.eis then r.eis.mode = STTS.PhoneEIS.Mode(r.wep) end
				local cpos = RenderCam(frameRT, l.w, l.h, pos, ang, not front, nil, own and L.zoom or FeedZoom(idx), wep, r.eis)
				render.PopRenderTarget()
				r.poseAt = now
				SCR.Cams[idx * 2 + (not front and 1 or 0)] = {pos = cpos, t = now}
				SCR.RecordRenderedFrame = FrameNumber()
			elseif now - (r.poseAt or 0) > 0.75 then
				-- really in a pocket: black frame, the video keeps its timing
				render.PushRenderTarget(frameRT) render.Clear(0, 0, 0, 255, true, true) render.PopRenderTarget()
			end
			-- (no pose only for a moment: falling out of a hand / a corpse, changing hands:
			-- the last picture is held instead of a black flash)
			SCR.RecPreview = {idx = idx, back = not front, mat = frameMat}
			-- One world render per tick. Missing deadlines hold that image; no burst renders.
			local due = math.min(maxFrames, math.floor((now - r.startAt) * fps) + 1)
			local copies = math.min(3, math.max(1, due - r.frames), l.frames - r.pageFrames)
			r.uniqueFrames = (r.uniqueFrames or 0) + (pos and 1 or 0)
			r.duplicated = (r.duplicated or 0) + copies - (pos and 1 or 0)
			render.PushRenderTarget(atlasRT)
				cam.Start2D()
					render.PushFilterMag(TEXFILTER.LINEAR) render.PushFilterMin(TEXFILTER.LINEAR)
					surface.SetMaterial(frameMat) surface.SetDrawColor(255, 255, 255, 255)
					for _ = 1, copies do
						local slot = r.pageFrames
						local x, y = (slot % l.cols) * l.w, math.floor(slot / l.cols) * l.h
						surface.DrawTexturedRectUV(x, y, l.w, l.h, 0, 0, l.w / G.FrameMaxW, l.h / G.FrameMaxH)
						r.frames, r.pageFrames = r.frames + 1, r.pageFrames + 1
					end
					render.PopFilterMin() render.PopFilterMag()
				cam.End2D()
			render.PopRenderTarget()
			r.next = r.startAt + r.frames / fps
			if r.pageFrames >= l.frames then FlushPage(r) end
			if r.frames >= maxFrames then r.stop = true end
		end
		if r.stop then
			if r.pageFrames > 0 then FlushPage(r) end
			r.closed = true
			SCR.RecPreview = nil
			if wep and wep:GetNW2Entity("RecBy", NULL) == lp then Act("recstop") end
			if L.camMode ~= nil and wep and wep:GetOwner() == lp and lp:GetActiveWeapon() == wep then Act("cam", tostring(L.camMode)) end
		end
	end
	FinishRec(r)
end

--[[ fix17: the live stream for spectators is gone (spectators can no longer look
     through phone cameras). what is left in here: saving to your PC. ]]
-- (inside a function: the main chunk is close to the 200 locals limit of LuaJIT)
SCR.ExportStep = (function()
	--[[ fix15: save to YOUR PC (garrysmod/data/zhunter_saved/):
	     photo -> png (full 576 x 1024), video -> native-size Motion-JPEG MP4. GMod lets Lua write only a few file types: if ".mp4" is refused
	     the file gets ".mp4.dat" (remove ".dat" and it plays: VLC, MPC, ffmpeg...). ]]
	local SAVE_DIR = "zhunter_saved"
	local exportRT = GetRenderTargetEx("stts_phone_export", 1024, 1024, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)

	local function U32(n)
		n = math.floor(n) % 4294967296
		return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
	end
	local function U16(n)
		n = math.floor(n) % 65536
		return string.char(math.floor(n / 256), n % 256)
	end
	local function Box(kind, ...) local body = table.concat({...}) return U32(8 + #body) .. kind .. body end
	local function FullBox(kind, ver, flags, ...)
		return Box(kind, string.char(ver, math.floor(flags / 65536) % 256, math.floor(flags / 256) % 256, flags % 256), ...)
	end
	local MATRIX = U32(0x00010000) .. U32(0) .. U32(0) .. U32(0) .. U32(0x00010000) .. U32(0) .. U32(0) .. U32(0) .. U32(0x40000000)

	-- jpg frames -> mp4 bytes (one Motion-JPEG track, like "ffmpeg -c:v mjpeg x.mp4")
	local function MakeMP4(frames, w, h, fps, partsOnly, durations)
		local n = #frames
		local delta = 1000
		local scale = fps * delta
		local ticks = n * delta
		local timing = U32(1) .. U32(n) .. U32(delta)
		if durations then
			scale, ticks = 1000, 0
			local runs, last, amount = {}, nil, 0
			for i = 1, n do
				local d = math.max(1, math.floor(durations[i] or 1000 / fps))
				ticks = ticks + d
				if last and d ~= last then runs[#runs + 1] = U32(amount) .. U32(last) amount = 0 end
				last, amount = d, amount + 1
			end
			if last then runs[#runs + 1] = U32(amount) .. U32(last) end
			timing = U32(#runs) .. table.concat(runs)
		end
		local durMs = math.floor(ticks * 1000 / scale + 0.5)
		local total = 0
		local sizes = {}
		for i, f in ipairs(frames) do
			local size = type(f) == "number" and f or #f
			sizes[i] = U32(size) total = total + size
		end
		local ftyp = Box("ftyp", "isom", U32(512), "isom", "iso2", "mp41")
		local dataOff = #ftyp + 8
		local rate = math.floor(total * 8 / math.max(0.001, ticks / scale))
		local esds = FullBox("esds", 0, 0,
			string.char(0x03, 21), U16(1), string.char(0),
			string.char(0x04, 13, 0x6C, 0x11), string.char(0, 0, 0), U32(rate), U32(rate),
			string.char(0x06, 1, 0x02))
		local mp4v = Box("mp4v", string.rep("\0", 6), U16(1), U16(0), U16(0), U32(0), U32(0), U32(0),
			U16(w), U16(h), U32(0x00480000), U32(0x00480000), U32(0), U16(1), string.rep("\0", 32), U16(0x0018), U16(0xFFFF), esds)
		local stbl = Box("stbl",
			FullBox("stsd", 0, 0, U32(1), mp4v),
			FullBox("stts", 0, 0, timing),
			FullBox("stsc", 0, 0, U32(1), U32(1), U32(n), U32(1)),
			FullBox("stsz", 0, 0, U32(0), U32(n), table.concat(sizes)),
			FullBox("stco", 0, 0, U32(1), U32(dataOff)))
		local minf = Box("minf",
			FullBox("vmhd", 0, 1, U16(0), U16(0), U16(0), U16(0)),
			Box("dinf", FullBox("dref", 0, 0, U32(1), FullBox("url ", 0, 1))),
			stbl)
		local mdia = Box("mdia",
			FullBox("mdhd", 0, 0, U32(0), U32(0), U32(scale), U32(ticks), U16(0x55C4), U16(0)),
			FullBox("hdlr", 0, 0, U32(0), "vide", U32(0), U32(0), U32(0), "VideoHandler\0"),
			minf)
		local trak = Box("trak",
			FullBox("tkhd", 0, 3, U32(0), U32(0), U32(1), U32(0), U32(durMs), U32(0), U32(0), U16(0), U16(0), U16(0), U16(0), MATRIX, U32(w * 65536), U32(h * 65536)),
			mdia)
		local moov = Box("moov",
			FullBox("mvhd", 0, 0, U32(0), U32(0), U32(1000), U32(durMs), U32(0x00010000), U16(0x0100), U16(0), U32(0), U32(0), MATRIX, string.rep("\0", 24), U32(2)),
			trak)
		if partsOnly then return ftyp, U32(8 + total) .. "mdat", moov end
		return ftyp .. U32(8 + total) .. "mdat" .. table.concat(frames) .. moov
	end
	SCR.MakeMP4 = MakeMP4

	local function SaveName(kind, id) return SAVE_DIR .. "/" .. kind .. "_" .. os.date("%Y%m%d_%H%M%S") .. "_" .. id end
	local function Saved(path) end
	function SCR.CancelExport()
		local job = SCR.Export
		if job and job.handle then job.handle:Close() job.handle = nil end
		if job and job.path then file.Delete(job.path) end
		SCR.Export = nil
	end
	-- The recording is streamed to disk. Only sample sizes stay in RAM, never
	-- the entire clip + multiple concatenated copies on the final game frame.
	local function OpenVideo(job, w, h, fps)
		file.CreateDir(SAVE_DIR)
		local base = SaveName("video", job.id)
		local handle = file.Open(base .. ".mp4", "wb", "DATA")
		job.path = base .. ".mp4"
		if not handle then
			job.path = base .. ".mp4.dat"
			handle = file.Open(job.path, "wb", "DATA")
		end
		if not handle then return false end
		job.handle, job.bytes = handle, 0
		local ftyp = MakeMP4({}, w, h, fps, true)
		job.offset = #ftyp
		handle:Write(ftyp .. U32(8) .. "mdat")
		return true
	end

	-- Save button: one frame per PostRender, incremental disk writes
	function SCR.SaveItem(st, id)
		if STTS.PhoneGallery33 and STTS.PhoneGallery33.IsBlob(id,st)then return STTS.PhoneGallery33.Save(id)end
		if L.rec then L.toast, L.toastAt = "Stop recording first", RealTime() return end
		if SCR.Export then L.toast, L.toastAt = "Saving...", RealTime() return end
		-- fix66: a received photo / clip not downloaded yet (TeleChat: tap to download) is downloaded
		-- now, else the save waited for it forever ("Saving..." and nothing)
		local M49 = SCR.M49
		if M49 and M49.Start and M49.manual[id] and not M49.want[id] and not M49.Have(st, id) then M49.Start(st, id) end
		if IsVideo(st, id) then
			SCR.Export = {video = true, id = id, sizes = {}, f = 0, at = RealTime()}
		else
			SCR.Export = {id = id, at = RealTime()}
		end
		L.toast, L.toastAt = "Saving...", RealTime()
	end

	local function ExportStep()
		local job = SCR.Export
		if not job then return end
		if RealTime() - job.at > 600 then SCR.CancelExport() L.toast, L.toastAt = "Can't save", RealTime() return end
		if not job.video then
			local mat = PhotoMat(job.id)
			if not mat then return end -- still downloading
			local pw, ph = SCR.PhotoSize(job.id) -- v19.4: landscape photos are 1024 x 576
			pw, ph = math.min(pw, 1024), math.min(ph, 1024)
			render.PushRenderTarget(exportRT)
				render.Clear(0, 0, 0, 255)
				cam.Start2D()
					surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
					surface.DrawTexturedRect(0, 0, pw, ph)
				cam.End2D()
				local png = render.Capture({format = "png", x = 0, y = 0, w = pw, h = ph, alpha = false})
			render.PopRenderTarget()
			SCR.Export = nil
			if not png or #png == 0 then L.toast, L.toastAt = "Can't save", RealTime() return end
			file.CreateDir(SAVE_DIR)
			local path = SaveName("photo", job.id) .. ".png"
			file.Write(path, png)
			if file.Exists(path, "DATA") then Saved(path) else L.toast, L.toastAt = "Can't save", RealTime() end
			return
		end
		local meta = VideoMeta(job.id)
		if not meta then return end
		-- Decode only the current page. Loading all 450 page textures in one
		-- PostRender could itself cause a multi-second freeze and VRAM spike.
		local l = G.VidLayout(meta.res)
		local currentPage = math.floor(job.f / l.frames) + 1
		if job.f < meta.frames and not PhotoMat(meta.pages[currentPage]) then return end
		local sc = 1 -- fix30: preserve native pixels, no point-filter upscaling
		local fw, fh = l.w * sc, l.h * sc
		if not job.handle and not OpenVideo(job, fw, fh, meta.fps) then
			SCR.CancelExport() L.toast, L.toastAt = "Can't open video file", RealTime() return
		end
		render.PushFilterMag(TEXFILTER.POINT) render.PushFilterMin(TEXFILTER.POINT)
		for _ = 1, 1 do -- one GPU readback/JPEG encode per game frame
			if job.f >= meta.frames then break end
			local f = job.f
			local page = math.floor(f / l.frames) + 1
			local slot = f % l.frames
			local col, row = slot % l.cols, math.floor(slot / l.cols)
			local mat = PhotoMat(meta.pages[page])
			render.PushRenderTarget(exportRT)
				render.Clear(0, 0, 0, 255)
				if mat then
					cam.Start2D()
						surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255, 255)
						surface.DrawTexturedRectUV(0, 0, fw, fh, col * l.w / l.aw, row * l.h / l.ah, (col + 1) * l.w / l.aw, (row + 1) * l.h / l.ah)
					cam.End2D()
				end
				local jpg = render.Capture({format = "jpg", quality = 92, x = 0, y = 0, w = fw, h = fh, alpha = false})
			render.PopRenderTarget()
			if not jpg or #jpg == 0 then
				SCR.CancelExport()
				L.toast, L.toastAt = "Frame export failed", RealTime()
				break
			end
			job.handle:Write(jpg)
			job.sizes[#job.sizes + 1] = #jpg
			job.bytes = job.bytes + #jpg
			job.f = f + 1
		end
		render.PopFilterMin() render.PopFilterMag()
		if not SCR.Export then return end
		if job.f < meta.frames then return end
		local _, mdat, moov = MakeMP4(job.sizes, fw, fh, meta.fps, true)
		job.handle:Seek(job.offset)
		job.handle:Write(mdat)
		job.handle:Seek(job.offset + 8 + job.bytes)
		job.handle:Write(moov)
		local expected = job.offset + 8 + job.bytes + #moov
		job.handle:Close() job.handle = nil
		local path = job.path
		SCR.Export = nil
		if file.Size(path, "DATA") == expected then Saved(path)
		else file.Delete(path) L.toast, L.toastAt = "Video write failed", RealTime() end
	end
	return ExportStep
end)()

-- fix65: is the photo picture (photoRT) black? 112 pixels of it, the brightest one counts
function SCR.PhotoBlack65()
	local peak = 0
	render.PushRenderTarget(photoRT)
	local ok = pcall(render.CapturePixels)
	if ok then
		for i = 0, 7 do
			for j = 0, 13 do
				local r, g, b = render.ReadPixel(math.floor((i + 0.5) * G.PhotoW / 8), math.floor((j + 0.5) * G.PhotoH / 14))
				peak = math.max(peak, r or 0, g or 0, b or 0)
				if peak > 6 then break end
			end
			if peak > 6 then break end
		end
	end
	render.PopRenderTarget()
	return ok and peak <= 6, peak
end

-- after the frame: phone cameras (so a camera pose is the one its phone was drawn with
-- in THIS frame), photos, video frames
hook.Add("PostRender", "STTS_PhonePhoto", function()
	if SCR.InRV then return end
	RecordStep()
	SCR.EncodeVideoPage(false)
	UpdateFeeds()
	local shot = SCR.Shot
	-- fix17: with the flash the picture is taken a moment later (the light is on by then)
	if shot and (not shot.at or RealTime() >= shot.at) then
		SCR.Shot = nil
		local wep = shot.wep
		if IsValid(wep) and wep:GetOwner() == LocalPlayer() then
			local pos, ang = PhonePose(wep) -- fix19: as in fix16
			if pos then
				RenderCam(photoRT, G.PhotoW, G.PhotoH, pos, ang, not shot.front, shot.front and LocalPlayer() or nil, L.zoom, wep)
				local land = SCR.LandK(wep) >= 0.5 -- v19.4: held landscape = a landscape photo
				render.PopRenderTarget()
				-- fix65: a black picture (seen with the rear camera) is taken once more, straight
				-- (without the phone's view isolation); what happened goes to the console
				local black, peak = SCR.PhotoBlack65()
				if black then
					local V = STTS.PhoneView43
					local info = V and V.last
					local why = info and string.format("stage=%s events=%s rejected=%s rt=%s", tostring(info.stage), tostring(info.events), tostring(info.rejected), tostring(info.active)) or "?"
					if V then V.Direct65 = true end
					local ok = pcall(RenderCam, photoRT, G.PhotoW, G.PhotoH, pos, ang, not shot.front, shot.front and LocalPlayer() or nil, L.zoom, wep)
					if V then V.Direct65 = nil end
					if ok then render.PopRenderTarget() end
					local black2, peak2 = SCR.PhotoBlack65()
					MsgC(Color(255, 180, 80), "[ZPHONE] ", color_white, string.format("black %s photo (peak %d, %s) -> taken again directly: %s (peak %d)\n",
						shot.front and "front" or "rear", peak, why, ok and (black2 and "still black" or "OK") or "failed", peak2))
				end
				-- fix66: the jpg is read from the picture itself RIGHT NOW (fix55 read it one frame
				-- later from the copy in a slot: that copy can be black = a black photo saved on the
				-- disk and on the server, seen the moment the slot stopped being drawn). the slot
				-- still shows the photo at once; SCR.Shot55.Watch66 checks it stays a picture
				local jpg
				if land then
					jpg = SCR.LandPhoto(pos, ang, not shot.front, wep)
				else
					render.PushRenderTarget(photoRT)
					jpg = render.Capture({format = "jpg", quality = 88, x = 0, y = 0, w = G.PhotoW, h = G.PhotoH, alpha = false})
					render.PopRenderTarget()
				end
				local sl = SCR.Shot55 and SCR.Shot55.Grab(land, land and SCR.LandVerts(pos, ang, not shot.front, wep) or nil)
				if jpg and #jpg > 0 then
					if #jpg < 11000 then -- a plain black 576 x 1024 jpg is ~9.8 KB
						MsgC(Color(255, 180, 80), "[ZPHONE] ", color_white, string.format("photo jpg looks black (%d bytes, picture peak %d, %s camera)\n", #jpg, peak or -1, shot.front and "front" or "rear"))
					end
					Upload(wep, jpg, nil, nil, nil, nil, sl)
					if sl and SCR.Shot55.Watch66 then SCR.Shot55.Watch66(sl, #jpg) end
				elseif sl then
					sl.fresh = nil
				end
			end
		end
	end
	if SCR.Shot55 then SCR.Shot55.Step() if SCR.Shot55.WatchStep66 then SCR.Shot55.WatchStep66() end end -- fix55 / fix66
	if SCR.M49 then SCR.M49.PrevStep() end -- fix53
	SCR.ExportStep()
end)

local nextPose = 0
hook.Add("Think", "STTS_PhoneScreenThink", function()
	local wep = MyPhone()
	if not wep then
		if L.raised then L.raised = false end
		if L.rec then StopRec() end
		if L.touch then TouchEnd(nil, true) end
		return
	end
	if L.wep ~= wep then Adopt(wep) end
	local st = State(wep)
	-- the call screen opens / closes by itself
	if st.call ~= G.CALL_NONE then L.app = G.APP_CALL elseif L.app == G.APP_CALL then L.app = G.APP_HOME end
	-- TeleChat: fresh history while the list is open, read marks while a conversation is open
	if (L.app == G.APP_THREAD or L.app == G.APP_SEND) and not L.peer then L.app = G.APP_CHATS end
	if L.app == G.APP_CHATS and RealTime() > (L.tcAskAt or 0) + 5 then TCAsk(true) end
	if L.app == G.APP_THREAD and L.peer and L.raised then TCRead(st.num, L.peer) end
	if L.app == G.APP_GALLERY then L.gal = st.gal end
	-- zoom (throttled), the other side renders your camera with it
	if L.zoomDirty and RealTime() - (L.zoomAt or 0) > 0.1 then
		L.zoomDirty, L.zoomAt = false, RealTime()
		Act("zoom", string.format("%.2f", L.zoomT or L.zoom or 1)) -- fix61: the target; the others glide to it
	end
	-- send the screen state + where the finger is (throttled)
	local fx, fy = math.Clamp(math.floor((L.ux or W * 0.5) / 2), 0, 216), math.Clamp(math.floor((L.uy or H * 0.62) / 4), 0, 240)
	-- fix17: scroll in 1/4 rows (smooth for the others too), shade 0..40
	local sc = math.Clamp(math.Round((L.scroll or 0) * 4), 0, 1023)
	local sh = math.Clamp(math.Round((L.shade or 0) * 40), 0, 40)
	local key = L.app .. ":" .. L.sel .. ":" .. sc .. ":" .. L.gal .. ":" .. L.galV .. ":" .. L.album .. ":" .. fx .. ":" .. fy .. ":" .. sh
	if key ~= L.sent and RealTime() - L.sentAt > 0.06 then
		L.sent, L.sentAt = key, RealTime()
		net.Start("stts_phone_scr")
			net.WriteUInt(L.app, 5) net.WriteUInt(math.Clamp(L.sel, 0, 255), 8) -- v19.2: 5 bits (Wi-Fi page = 16)
			net.WriteUInt(sc, 10) net.WriteUInt(math.Clamp(L.gal, 0, 255), 8)
			net.WriteUInt(math.Clamp(L.galV * 4 + L.album, 0, 255), 8)
			net.WriteUInt(fx, 8) net.WriteUInt(fy, 8)
			net.WriteUInt(sh, 6)
		net.SendToServer()
	end
	-- your camera streams in a video call: send the phone pose (world + relative to your body)
	if ((st.vid and st.call == G.CALL_ON) or RemoteRec(wep)) and RealTime() > nextPose then
		local pos, ang = PhonePose(wep) -- fix19: as in fix16
		if pos then
			nextPose = RealTime() + 1 / 15
			local rel = wep.STTS_RelFrame and FrameNumber() - wep.STTS_RelFrame <= 3
			net.Start("stts_phone_pose", true)
				net.WriteVector(pos) net.WriteAngle(ang)
				net.WriteBool(rel and true or false)
				if rel then net.WriteVector(wep.STTS_RelP) net.WriteAngle(wep.STTS_RelA) end
			net.SendToServer()
		end
	end
end)

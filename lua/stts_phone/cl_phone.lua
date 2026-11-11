-- ZHUNTER 911 operator console (spectators only, there is no phone in their hands).
-- The phone itself has NO window any more: its UI is drawn on the display of the
-- model, see cl_shooting_phone_screen.lua.
STTS = STTS or {}
STTS.PhoneClient = STTS.PhoneClient or {role = "", state = "ended", since = 0, peer = ""}
STTS.PhoneBook = STTS.PhoneBook or {{num = "911", name = "Emergency 911"}}
local CLASS = "weapon_stts_phone"
local WHITE, BLACK = Color(255, 255, 255), Color(0, 0, 0)
local TEXT, MUTED, DIM = Color(236, 236, 236), Color(140, 140, 140), Color(90, 90, 90)
local BG, LINE, EDGE = Color(8, 8, 8, 236), Color(255, 255, 255, 30), Color(255, 255, 255, 200)
local SOFT = Color(255, 255, 255, 90)
local function Rect(x, y, w, h, col)
	surface.SetDrawColor(col) surface.DrawRect(x, y, w, h)
end
-- Thick edges: 3px for the device frame, 2px for buttons/fields.
local EDGE_T, UI_T = 3, 2
local function Outline(x, y, w, h, col, t)
	surface.SetDrawColor(col) surface.DrawOutlinedRect(x, y, w, h, t or UI_T)
end
-- One device rectangle for every app; switching apps never changes its size.
function STTS.PhoneScreenBounds()
 local w,h=math.min(300,ScrW()-24),math.min(500,ScrH()-24)
 return w,h,math.max(12,ScrW()-w-30),math.max(12,ScrH()-h-12)
end
local function HasAvatar(id)
	return isstring(id) and #id == 17 and string.match(id, "^%d+$") ~= nil
end
local function BindAvatar(avatar, id)
	avatar.STTS_ID = id or ""
	if not HasAvatar(id) then avatar:SetVisible(false) return end
	local owner
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and not ply:IsBot() and ply:SteamID64() == id then owner = ply break end
	end
	-- Prefer the live player: this uses the Steam avatar already cached by GMod.
	if IsValid(owner) then avatar:SetPlayer(owner, 64) else avatar:SetSteamID(id, 64) end
	avatar.STTS_AvatarPlayer = owner
end
local function SteamAvatar(parent, id, x, y, size)
	local avatar = vgui.Create("AvatarImage", parent)
	avatar:SetPos(x, y) avatar:SetSize(size, size)
	avatar:SetMouseInputEnabled(false)
	BindAvatar(avatar, id)
	avatar.Think = function(self)
		if not HasAvatar(self.STTS_ID) or (self.STTS_CheckAt or 0) > CurTime() then return end
		self.STTS_CheckAt = CurTime() + 2
		-- A player/entity or its Steam identity may arrive after the contacts packet.
		if not IsValid(self.STTS_AvatarPlayer) then BindAvatar(self, self.STTS_ID) end
	end
	return avatar
end
-- Same font families as the ESC menu, with sizes suited to this small panel.
STTS.CreatePhoneAvatar = SteamAvatar
surface.CreateFont("STTS_PhoneText", {font = "Veteran Typewriter", size = 18, weight = 500, antialias = true})
surface.CreateFont("STTS_PhoneHeading", {font = "JMH Typewriter", size = 25, weight = 800, antialias = true})
surface.CreateFont("STTS_PhoneHint", {font = "Veteran Typewriter", size = 15, weight = 500, antialias = true})
surface.CreateFont("STTS_PhoneBig", {font = "JMH Typewriter", size = 30, weight = 800, antialias = true})
surface.CreateFont("STTS_PhoneClock", {font = "JMH Typewriter", size = 64, weight = 800, antialias = true})
local function Fit(text, font, width)
	text = tostring(text or "")
	surface.SetFont(font)
	if surface.GetTextSize(text) <= width then return text end
	while utf8.len(text) and utf8.len(text) > 0 and surface.GetTextSize(text .. "...") > width do
		text = string.sub(text, 1, (utf8.offset(text, -1) or 1) - 1)
	end
	return text .. "..."
end
STTS.PhoneFitText = Fit

--[[ shared style ]]
local S = {WHITE = WHITE, BLACK = BLACK, TEXT = TEXT, MUTED = MUTED, DIM = DIM, BG = BG, LINE = LINE, EDGE = EDGE, SOFT = SOFT}
STTS.PhoneStyle = S
S.Rect, S.Outline = Rect, Outline
local function UISound(path)
	sound.PlayFile(path, "noblock", function(st) if IsValid(st) then st:SetVolume(0.6) st:Play() end end)
end
local function HoverSound(self)
	if self:IsHovered() then
		if not self.STTS_Hovered then self.STTS_Hovered = true UISound("sound/hover.ogg") end
	else self.STTS_Hovered = false end
end
S.HoverSound = HoverSound
S.ClickSound = function() end -- fix11: no press sounds
-- ESC-menu flicker: the white hover box occasionally drops alpha.
local function Flicker() return math.random() > 0.93 and math.random(120, 220) or 255 end
S.Flicker = Flicker
local blur = Material("pp/blurscreen")
function S.Blur(panel)
	local sx, sy = panel:LocalToScreen(0, 0)
	surface.SetMaterial(blur) surface.SetDrawColor(255, 255, 255, 255)
	for i = 1, 3 do
		blur:SetFloat("$blur", i * 2) blur:Recompute()
		render.UpdateScreenEffectTexture()
		surface.DrawTexturedRect(-sx, -sy, ScrW(), ScrH())
	end
end
-- Glass body + header. title may be nil (home screen draws its own).
function S.PaintFrame(panel, w, h, title, sub, titleX, titleFont)
	S.Blur(panel)
	Rect(0, 0, w, h, BG)
	if title then
		titleX = titleX or 16
		draw.SimpleText(Fit(title, titleFont or "STTS_PhoneHeading", w - titleX - 52), titleFont or "STTS_PhoneHeading", titleX, 27, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if sub and sub ~= "" then
			draw.SimpleText(Fit(sub, "STTS_PhoneHint", w - titleX - 16), "STTS_PhoneHint", titleX, 51, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		Rect(12, 67, w - 24, 2, LINE)
	end
end
function S.PaintEdge(w, h) Outline(0, 0, w, h, EDGE, EDGE_T) end
-- Lowercase label that types itself into UPPERCASE while hovered (ESC menu effect).
local function MorphLabel(self, label)
	self.HoverLerp = Lerp(math.min(1, FrameTime() * 12), self.HoverLerp or 0, self:IsHovered() and 1 or 0)
	local n = #label
	local k = math.Clamp(math.ceil(n * self.HoverLerp - 0.01), 0, n)
	return string.upper(string.sub(label, 1, k)) .. string.sub(label, k + 1)
end
S.MorphLabel = MorphLabel
-- style "ghost": outline, white text, white box on hover. "solid": white box, inverts on hover.
function S.Button(parent, label, style, action)
	local b = vgui.Create("DButton", parent)
	b:SetText("") b.label = label b.style = style or "ghost"
	b.Paint = function(self, w, h)
		HoverSound(self)
		local hov = self:IsHovered()
		local filled = (self.style == "solid") ~= hov
		local font = w < 60 and "STTS_PhoneHint" or "STTS_PhoneText"
		local text = MorphLabel(self, self.label)
		if filled then
			local a = hov and Flicker() or 255
			Rect(0, 0, w, h, Color(255, 255, 255, a))
			draw.SimpleText(Fit(text, font, w - 8), font, w / 2, h / 2, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			Outline(0, 0, w, h, hov and WHITE or SOFT)
			draw.SimpleText(Fit(text, font, w - 8), font, w / 2, h / 2, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return true
	end
	b.DoClick = function(self) S.ClickSound() if action then action(self) end end
	return b
end
-- Minimal 3px scrollbar instead of the stock derma one.
function S.StyleScroll(scroll)
	local bar = scroll:GetVBar()
	bar:SetWide(3) bar:SetHideButtons(true)
	bar.Paint = function(_, w, h) Rect(0, 0, w, h, Color(255, 255, 255, 12)) end
	bar.btnGrip.Paint = function(_, w, h) Rect(0, 0, w, h, Color(255, 255, 255, 110)) end
end
-- Contact photo frame / placeholder: initial in a 1px box, B&W.
function S.PaintContactPic(x, y, size, name, num, hasAvatar, inverted)
	local col = inverted and BLACK or WHITE
	if hasAvatar then Outline(x - 1, y - 1, size + 2, size + 2, inverted and BLACK or SOFT) return end
	Outline(x, y, size, size, inverted and BLACK or SOFT)
	local label = "911"
	if num ~= "911" then
		local ok, cp = pcall(utf8.codepoint, tostring(name or "?"), 1)
		label = string.upper(utf8.char(ok and cp or 63))
	end
	local font = (num == "911" or size < 50) and "STTS_PhoneHint" or "STTS_PhoneBig"
	if size >= 50 and num == "911" then font = "STTS_PhoneBig" end
	draw.SimpleText(label, font, x + size / 2, y + size / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
function S.PaintEntry(self, ew, eh, placeholder)
	Rect(0, 0, ew, eh, Color(255, 255, 255, 8))
	Outline(0, 0, ew, eh, self:HasFocus() and WHITE or SOFT)
	self:DrawTextEntryText(WHITE, Color(130, 130, 130), WHITE)
	if self:GetValue() == "" and not self:HasFocus() then
		draw.SimpleText(placeholder, "STTS_PhoneHint", 9, eh / 2, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end
-- Downloaded Wikimedia icon, shipped by stts_content (red X, kept in colour).
local closeIcon=Material("stts/phone_close.png","smooth")
function STTS.PhoneCloseButton(parent,action)
 local b=vgui.Create("DButton",parent)
 b:SetText("") b:SetSize(34,34) b:SetTooltip("Close")
 b.Paint=function(self,w,h)
  HoverSound(self)
  if self:IsHovered() then Rect(0,0,w,h,Color(255,255,255,40)) end
  surface.SetDrawColor(255,255,255,255) surface.SetMaterial(closeIcon)
  surface.DrawTexturedRect((w-18)/2,(h-18)/2,18,18)
  return true
 end
 b.DoClick=function() S.ClickSound() action() end return b
end
-- Small "<" button for the header.
function S.BackButton(parent, action)
	local b = vgui.Create("DButton", parent)
	b:SetText("") b:SetSize(28, 28) b:SetPos(10, 13)
	b.Paint = function(self, w, h)
		HoverSound(self)
		local hov = self:IsHovered()
		if hov then Rect(0, 0, w, h, Color(255, 255, 255, Flicker())) else Outline(0, 0, w, h, SOFT) end
		draw.SimpleText("<", "STTS_PhoneText", w / 2, h / 2, hov and BLACK or WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	b.DoClick = function() S.ClickSound() action() end
	return b
end
local gains, gainUntil = {}, 0
net.Receive("stts_phone_voice_gain", function()
	gains = {}
	for _ = 1, net.ReadUInt(8) do
		local id = net.ReadUInt(16)
		gains[id] = net.ReadUInt(8) / 255
	end
	gainUntil = CurTime() + 1
end)
hook.Add("STTS_PhoneVoiceGain", "STTS_PhoneLocalGain", function(ply)
	if CurTime() > gainUntil then return end
	return gains[ply:UserID()]
end)
local function MyPhone()
	local lp = LocalPlayer()
	local wep = IsValid(lp) and lp:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == CLASS then return wep end
end
local function Send(act, arg)
	if STTS.PhoneClient.role == "operator" then
		net.Start("stts_phone_action") net.WriteString(act) net.SendToServer()
	else
		net.Start("stts_phone_ui") net.WriteString(act) net.WriteString(arg or "") net.SendToServer()
	end
end
function STTS.ClosePhoneUI(silent)
	local fr = STTS.PhoneUI
	STTS.PhoneUI = nil
	if IsValid(fr) then fr:Remove() end
	if not silent and STTS.PhoneClient.role ~= "operator" then Send("close") end
end
local Button = S.Button
local function RefreshBook()
	local fr = STTS.PhoneUI
	if not IsValid(fr) or fr.IsTeleChat or not IsValid(fr.contacts) then return end
	local phone = MyPhone()
	local mine = IsValid(phone) and phone:GetNWString("STTS_Num", "") or ""
	local parts = {mine}
	for _, c in ipairs(STTS.PhoneBook) do
		parts[#parts + 1] = c.num .. "\0" .. c.name .. "\0" .. (c.avatar or "") .. "\0" .. tostring(c.unread or 0)
	end
	local key = table.concat(parts, "\1")
	if fr.bookKey == key then return end -- a refresh must not reset scrolling
	fr.bookKey = key
	fr.contacts:Clear()
	for _, c in ipairs(STTS.PhoneBook) do
		if c.num ~= mine then
		local row = vgui.Create("DButton", fr.contacts)
		row:Dock(TOP) row:SetTall(46) row:SetText("")
		local hasAvatar = HasAvatar(c.avatar)
		if hasAvatar then SteamAvatar(row, c.avatar, 9, 7, 32) end
		row.Paint = function(self, w, h)
			HoverSound(self)
			local hov = self:IsHovered()
			if hov then Rect(0, 0, w, h, Color(255, 255, 255, S.Flicker())) end
			Rect(8, h - 1, w - 16, 1, LINE)
			S.PaintContactPic(9, 7, 32, c.name, c.num, hasAvatar, hov)
			draw.SimpleText(Fit(c.name, "STTS_PhoneText", w - 62), "STTS_PhoneText", 52, h / 2, hov and BLACK or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return true
		end
		row.DoClick = function() S.ClickSound() Send("dial", c.num) end
		end
	end
end
-- contacts arrive in cl_shooting_phone_screen.lua (stts_phone_book)

-- Home screen app icon (real-phone style): square icon, name underneath, unread badge.
local ZPhoneLogo = Material("stts/zphone_logo.png", "smooth mips")
local ICON, ICON_GAP = 58, 14
local function AppIcon(parent, title, iconPath, unreadFn, action)
	local mat = Material(iconPath, "smooth mips")
	local b = vgui.Create("DButton", parent)
	b:SetText("") b:SetSize(ICON + 16, ICON + 26)
	b.Paint = function(self, w, h)
		HoverSound(self)
		local hov = self:IsHovered()
		local ix = math.floor((w - ICON) / 2)
		if hov then Rect(ix, 0, ICON, ICON, Color(255, 255, 255, S.Flicker()))
		else Rect(ix, 0, ICON, ICON, Color(255, 255, 255, 10)) Outline(ix, 0, ICON, ICON, SOFT) end
		if not mat:IsError() then
			local g = math.floor(ICON * 0.52)
			surface.SetMaterial(mat)
			surface.SetDrawColor(hov and BLACK or WHITE)
			surface.DrawTexturedRect(ix + (ICON - g) / 2, (ICON - g) / 2, g, g)
		end
		local unread = unreadFn and unreadFn() or 0
		if unread > 0 then
			local txt = tostring(math.min(unread, 99))
			surface.SetFont("STTS_PhoneHint")
			local tw = math.max(20, surface.GetTextSize(txt) + 8)
			Rect(ix + ICON - tw + 6, -2, tw, 18, WHITE)
			Outline(ix + ICON - tw + 6, -2, tw, 18, BLACK)
			draw.SimpleText(txt, "STTS_PhoneHint", ix + ICON - tw / 2 + 6, 7, BLACK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(title, "STTS_PhoneHint", w / 2, ICON + 13, hov and WHITE or TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	b.DoClick = function() S.ClickSound() action() end
	return b
end
--[[ fix14: the 911 console is no phone any more. a plain black box bottom
     left: "someone is calling you" (HomigradFont) and the call buttons.
     ringing   : red decline / green answer
     connected : timer, blue police + red hang up. if the caller turns his
                 camera on, the picture shows up in the box (click = enlarge) ]]
local RED, GREEN, BLUE = Color(255, 69, 58), Color(48, 209, 88), Color(10, 132, 255)
local handsetMat = Material("stts/app_phone.png", "smooth mips")

local function Circ(x, y, r, col)
	r = math.floor(r)
	if r < 1 then return end
	draw.RoundedBox(r, math.floor(x - r), math.floor(y - r), r * 2, r * 2, col)
end
local function Tri(x1, y1, x2, y2, x3, y3, col)
	if (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1) < 0 then x2, y2, x3, y3 = x3, y3, x2, y2 end
	draw.NoTexture() surface.SetDrawColor(col)
	surface.DrawPoly({{x = x1, y = y1}, {x = x2, y = y2}, {x = x3, y = y3}})
end
-- the same handset as on the phone display (cl_shooting_phone_screen.lua GHandset)
local function GHandset(x, y, r, down)
	if not handsetMat:IsError() then
		surface.SetMaterial(handsetMat) surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRectRotated(x, y, r, r, down and -45 or 0)
		return
	end
	Circ(x, y, r * 0.2, WHITE)
end
-- police: a 5 point badge star
local function GStar(x, y, r, col)
	local R, ri = r * 0.5, r * 0.21
	local outer, inner = {}, {}
	for i = 0, 4 do
		local a = math.rad(-90 + i * 72)
		local b = math.rad(-90 + 36 + i * 72)
		outer[i] = {x + math.cos(a) * R, y + math.sin(a) * R}
		inner[i] = {x + math.cos(b) * ri, y + math.sin(b) * ri}
	end
	for i = 0, 4 do
		local o, a, b = outer[i], inner[(i + 4) % 5], inner[i]
		Tri(o[1], o[2], a[1], a[2], b[1], b[2], col)
		Tri(x, y, a[1], a[2], b[1], b[2], col)
	end
end

local function OperatorVideo()
	local lp, st = LocalPlayer(), STTS.PhoneClient
	if not IsValid(lp) or st.role ~= "operator" or st.state ~= "connected" then return end
	if not lp:GetNW2Bool("ZH911Vid", false) then return end
	local idx = lp:GetNW2Int("ZH911Phone", 0)
	if idx <= 0 then return end
	return idx, lp:GetNW2Bool("ZH911Back", true)
end
STTS.OperatorVideo = OperatorVideo
local function DrawOperatorFeed(idx, back, x, y, w, h, rate)
	local SCR = STTS.PhoneScreen
	local mat = SCR and SCR.WantFeed and SCR.WantFeed(idx, back, rate or 15)
	Rect(x, y, w, h, BLACK)
	if not mat then return end
	if SCR.DrawFeedFull then SCR.DrawFeedFull(mat, x, y, w, h)
	else surface.SetMaterial(mat) surface.SetDrawColor(255, 255, 255) surface.DrawTexturedRect(x, y, w, h) end
end

-- round call button (panel), glyph drawn inside
local function CallButton(parent, r, col, glyph, action)
	local b = vgui.Create("DButton", parent)
	b:SetText("") b:SetSize(r * 2 + 10, r * 2 + 10)
	b.Paint = function(self, w, h)
		HoverSound(self)
		local hov = self:IsHovered()
		local k = self:IsDown() and 0.92 or 1
		if hov then Circ(w / 2, h / 2, r * k + 4, Color(255, 255, 255, 40)) end
		-- fix15: answer green / decline + hang up red / police blue even in the black & white UI
		if STTS_MonoColored then STTS_MonoColored(Circ, w / 2, h / 2, r * k, self.col or col) else Circ(w / 2, h / 2, r * k, self.col or col) end
		glyph(self, w / 2, h / 2, r * k)
		return true
	end
	b.DoClick = function() action() end
	return b
end

local CALLING = "someone is calling you"
local PAD, BR = 14, 24 -- padding, button radius

function STTS.OpenPhoneUI()
	local lp, st = LocalPlayer(), STTS.PhoneClient
	if st.role ~= "operator" then return end -- phone holders use the real display
	if IsValid(STTS.PhoneUI) or not IsValid(lp) then return end
	local fr = vgui.Create("EditablePanel")
	STTS.PhoneUI = fr
	fr:MakePopup() fr:SetKeyboardInputEnabled(false) -- voice + chat keep working
	fr:SetAlpha(0) fr:AlphaTo(255, 0.12, 0)
	fr.vid = nil -- {x, y, w, h} of the caller's picture inside the box

	local function Layout()
		surface.SetFont("HomigradFont")
		local tw, th = surface.GetTextSize(CALLING)
		local w = math.max(250, tw + PAD * 2)
		local bh = BR * 2 + 10
		local vh, vw = 0, 0
		if OperatorVideo() then
			vh = math.floor(math.min(ScrH() * 0.42, (w - PAD * 2) * 16 / 9))
			vw = math.floor(vh * 9 / 16)
		end
		local h = PAD + (vh > 0 and vh + 10 or 0) + th + 10 + bh + PAD
		local m = math.floor(math.max(18, ScrH() * 0.04))
		fr:SetSize(w, h)
		fr:SetPos(m, ScrH() - m - h)
		fr.vid = vh > 0 and {math.floor((w - vw) / 2), PAD, vw, vh} or nil
		fr.textY = PAD + (vh > 0 and vh + 10 or 0) + th / 2
		fr.btnY = fr.textY + th / 2 + 10 + bh / 2
		return w, h
	end

	fr.Paint = function(self, pw, ph)
		surface.SetDrawColor(0, 0, 0, 255) surface.DrawRect(0, 0, pw, ph)
		local v = self.vid
		if v then
			local idx, back = OperatorVideo()
			if idx then DrawOperatorFeed(idx, back, v[1], v[2], v[3], v[4], self.BigVideo and 8 or 15) end
		end
		local text = st.state == "ringing" and CALLING or string.FormattedTime(math.max(0, CurTime() - st.since), "%02i:%02i")
		draw.SimpleText(text, "HomigradFont", pw / 2, self.textY or PAD, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local decline = CallButton(fr, BR, RED, function(_, cx, cy, rr) GHandset(cx, cy, rr, true) end, function() Send("hangup") end)
	local answer = CallButton(fr, BR, GREEN, function(_, cx, cy, rr) GHandset(cx, cy, rr) end, function() Send("answer") end)
	local police = CallButton(fr, BR, BLUE, function(_, cx, cy, rr) GStar(cx, cy, rr, st.police and BLUE or WHITE) end, function() Send("dispatch") end)
	local bs = decline:GetWide()
	local function Place(b, cx, cy) b:SetPos(math.floor(cx - bs / 2), math.floor(cy - bs / 2)) end

	-- click the picture = enlarge it next to the box (separate panel, no input)
	local vidBtn = vgui.Create("DButton", fr)
	vidBtn:SetText("") vidBtn:SetVisible(false)
	vidBtn.Paint = function() return true end
	vidBtn.DoClick = function() fr.BigVideo = not fr.BigVideo end
	local bigVid = vgui.Create("Panel")
	bigVid:SetMouseInputEnabled(false) bigVid:SetKeyboardInputEnabled(false) bigVid:SetVisible(false)
	bigVid.Paint = function(_, bw2, bh2)
		local idx, back = OperatorVideo()
		if idx then DrawOperatorFeed(idx, back, 0, 0, bw2, bh2, 20) end
	end
	fr.OnRemove = function() if IsValid(bigVid) then bigVid:Remove() end end

	fr.Think = function()
		if not IsValid(lp) or gui.IsGameUIVisible() or st.role ~= "operator" then STTS.ClosePhoneUI(true) return end
		local ringing, connected = st.state == "ringing", st.state == "connected"
		if not ringing and not connected then STTS.ClosePhoneUI(true) return end
		local w = Layout()
		answer:SetVisible(ringing)
		police:SetVisible(connected)
		if ringing then
			Place(decline, w * 0.3, fr.btnY) Place(answer, w * 0.7, fr.btnY)
		else
			Place(police, w * 0.3, fr.btnY) Place(decline, w * 0.7, fr.btnY)
		end
		police.col = st.police and Color(255, 255, 255, 230) or BLUE
		local v = fr.vid
		vidBtn:SetVisible(v and true or false)
		if v then vidBtn:SetPos(v[1], v[2]) vidBtn:SetSize(v[3], v[4]) else fr.BigVideo = false end
		local showBig = v and fr.BigVideo
		bigVid:SetVisible(showBig and true or false)
		if showBig then
			local bh2 = math.floor(ScrH() * 0.78)
			local bw2 = math.floor(bh2 * 9 / 16)
			local fx = fr:GetPos()
			bigVid:SetSize(bw2, bh2)
			bigVid:SetPos(fx + fr:GetWide() + 16, math.floor((ScrH() - bh2) / 2))
		end
	end
	Layout()
end

-- the box is there for the whole call by itself (no command to remember)
hook.Add("Think", "STTS_OperatorPhonePopup", function()
	local st = STTS.PhoneClient
	if st.role ~= "operator" or (st.state ~= "ringing" and st.state ~= "connected") then STTS.LastOperatorRing = nil return end
	if st.state == "ringing" and STTS.LastOperatorRing ~= st.since then
		STTS.LastOperatorRing = st.since
		STTS.ClosePhoneUI(true)
	end
	if not IsValid(STTS.PhoneUI) and not gui.IsGameUIVisible() then STTS.OpenPhoneUI() end
end)
concommand.Add("stts_phone", function() -- 911 operator console
	if IsValid(STTS.PhoneUI) then STTS.ClosePhoneUI(true) else STTS.OpenPhoneUI() end
end)

--[[---------------------------------------------------------------------------
	ZPhone for Z-City - call state on the client.
	this part used to be in the ZHunter game mode HUD (cl_shooting.lua): state of
	your line, ringback / ring sounds, "the subscriber is unavailable", the
	hidden operator keys (F6 answer / police, F7 hang up), chat lines coming
	out of the phone and the short status text ("No answer", "Busy"...).
---------------------------------------------------------------------------]]
STTS = STTS or {}

local function A(c, a) return Color(c.r, c.g, c.b, a) end
local WHITE = Color(255, 255, 255)

local function CreateFonts()
	surface.CreateFont("STTS_PhoneFlash", {font = "Roboto", size = math.max(14, math.floor(ScreenScaleH(12))), weight = 500, antialias = true, extended = true})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "STTS_PhoneFlashFont", CreateFonts)

--[[---------------------------------------------------------------------------
	phone state (911 caller / operator / phone-to-phone). phone screen UI is
	in cl_phone_screen.lua / cl_phone.lua
---------------------------------------------------------------------------]]
STTS.PhoneClient = STTS.PhoneClient or {role = "", state = "ended", since = 0, peer = ""}

local function PhoneAction(act)
	net.Start("stts_phone_action")
		net.WriteString(act)
	net.SendToServer()
end

local FLASH = {
	dispatched = "Police sent",
	already = "On the way",
	noanswer = "No answer",
	busy = "Busy",
	invalid = "No service",
	nosee = "you didnt see anything strange",
}

net.Receive("stts_phone_state", function()
	local st = STTS.PhoneClient
	local oldState, oldRole = st.state, st.role
	st.role = net.ReadString()
	st.state = net.ReadString()
	st.since = net.ReadFloat()
	local peer = net.ReadString()
	st.peerAvatar = net.ReadString()
	if peer ~= "" then st.peer = peer end
	st.nextSound = 0

	-- fix24: the called phone is in airplane mode: the call screen stays ("Calling..."),
	-- the ringback stops and the network voice says the subscriber is unavailable
	if st.state == "unreach" then
		st.state, st.unreach = "ringing", true
		if STTS.PhoneUnreachSound then STTS.PhoneUnreachSound() end
	else
		st.unreach = nil
		if STTS.StopPhoneUnreachSound then STTS.StopPhoneUnreachSound() end
	end

	if FLASH[st.state] then st.flash, st.flashAt = FLASH[st.state], CurTime() end
	if st.state == "dispatched" then surface.PlaySound("buttons/blip1.wav") end
	-- no "Call ended" text anywhere: hanging up just closes the call (like iOS)

	-- the police button of the 911 console stays lit once the police is on the way
	if st.state == "ringing" then st.police = nil end
	if st.state == "dispatched" or st.state == "already" then st.state, st.police = "connected", true end
	if st.state ~= "ringing" and st.state ~= "connected" then
		if oldRole == "operator" then st.flash = nil end
		st.state, st.role, st.peer, st.peerAvatar, st.police = "ended", "", "", "", nil
	end
end)

--[[ fix24: "the subscriber is unavailable" (phone_unreach.mp3), only the caller hears
     it, at the volume of his phone. kept as a channel: End / any new state stops it ]]
local unreachCh, unreachToken = nil, 0
function STTS.StopPhoneUnreachSound()
	unreachToken = unreachToken + 1
	if IsValid(unreachCh) then unreachCh:Stop() end
	unreachCh = nil
end
function STTS.PhoneUnreachSound()
	STTS.StopPhoneUnreachSound()
	local v = STTS.PhoneVolume and STTS.PhoneVolume() or 1
	if v <= 0.005 then return end
	local token = unreachToken
	sound.PlayFile("sound/stts/phone_unreach.mp3", "noblock", function(ch)
		if not IsValid(ch) then return end
		if token ~= unreachToken then ch:Stop() return end -- the call ended while it loaded
		ch:SetVolume(v) ch:Play()
		unreachCh = ch
	end)
end

--[[ fix24: ringback = the recorded beep (phone_gudok.mp3, ~1 s), then 2 s of silence,
     again and again (was the synthesized phone_ringback.wav) ]]
local GUDOK, GUDOK_LEN, GUDOK_PAUSE = "stts/phone_gudok.mp3", 1.05, 2 -- fix55: mp3

hook.Add("Think", "STTS_PhoneSounds", function()
	local st = STTS.PhoneClient
	if st.state ~= "ringing" or st.unreach or (st.nextSound or 0) > CurTime() then return end

	if st.role == "operator" then
		if STTS.PhoneSound then STTS.PhoneSound("stts/phone_ring.mp3") else surface.PlaySound("stts/phone_ring.mp3") end -- fix20: phone volume
		st.nextSound = CurTime() + 2.1
	elseif st.role == "caller" or st.role == "out" then
		if STTS.PhoneSound then STTS.PhoneSound(GUDOK) else surface.PlaySound(GUDOK) end -- fix20: phone volume
		st.nextSound = CurTime() + GUDOK_LEN + GUDOK_PAUSE
	end
	-- "in": the server rings the phone itself, everybody nearby hears it
end)

-- a line of chat coming out of the phone
net.Receive("stts_phone_chat", function()
	local name = net.ReadString()
	local text = net.ReadString()
	-- fix61: nothing from the phone goes into the game chat any more (console only)
	MsgC(Color(150, 175, 120), "[phone] ", Color(255, 255, 255), name .. ": ", Color(220, 220, 220), text, "\n")
end)

-- operator keys (still work, just not advertised): F6 answer / police, F7 decline / hang up
local keyState = {}
local function Pressed(key)
	local down = input.IsKeyDown(key)
	local was = keyState[key]
	keyState[key] = down
	return down and not was
end

hook.Add("Think", "STTS_PhoneKeys", function()
	local st = STTS.PhoneClient
	if st.role ~= "operator" or vgui.GetKeyboardFocus() or gui.IsGameUIVisible() then
		keyState = {}
		return
	end

	if Pressed(KEY_F6) then PhoneAction(st.state == "ringing" and "answer" or "dispatch") end
	if Pressed(KEY_F7) then PhoneAction("hangup") end
end)

concommand.Add("stts_phone_answer", function() PhoneAction("answer") end)
concommand.Add("stts_phone_hangup", function() PhoneAction("hangup") end)
concommand.Add("stts_phone_dispatch", function() PhoneAction("dispatch") end)

local function DrawPhoneHUD(sw, sh, now)
	local st = STTS.PhoneClient

	-- fix13: the 911 operator gets no text on screen, only the call console
	if st.role == "operator" then return end
	-- fix26: an incoming call is NOT written on the player's screen any more
	-- ("phone ringing / take out the phone - LMB" removed). you only hear the
	-- ringtone, the call itself is shown on the phone display.

	if st.flash and (st.flashAt or 0) + 3 > now and not IsValid(STTS.PhoneUI) then
		local a = math.Clamp((st.flashAt + 3 - now) * 255, 0, 255)
		draw.SimpleText(st.flash, "STTS_PhoneFlash", sw * 0.5, sh * 0.66, A(WHITE, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

-- the game mode called this from its HUDPaint; here it is an ordinary hook
hook.Add("HUDPaint", "STTS_PhoneHUD", function()
	if not IsValid(LocalPlayer()) then return end
	DrawPhoneHUD(ScrW(), ScrH(), CurTime())
end)

--[[---------------------------------------------------------------------------
	SHOOTING - TeleChat (text messages between phones)
	* messages belong to the PHONE (its number), not to the player: whoever
	  picks a phone up (from the floor, from a corpse, handed over) reads its
	  conversations and answers from it.
	* the server keeps the history for the round (G.ChatPerThread per
	  conversation, G.ChatPerPhone per phone, G.ChatMaxLen characters per
	  message). wiped on PHONE.Reset (round end / start).
	* new messages are pushed to the player who owns the phone right now (in
	  the hand or in the inventory). the full history is sent when the phone is
	  taken in the hand / TeleChat is opened.
	* attachments: the "+" button in a conversation sends a photo / video of
	  the phone's gallery (the only way to send media). the item is added to
	  the gallery of the other phone (album Received), the message carries
	  its id.
	* bots answer TeleChat messages (for testing).
	* fix17: airplane mode. a phone in airplane mode sends nothing; messages TO
	  it wait on the server (the sender sees his message at once) and arrive,
	  with the notification, when airplane mode is switched off.
---------------------------------------------------------------------------]]
STTS = STTS or {}
STTS.PhoneChat = STTS.PhoneChat or {}
local TC = STTS.PhoneChat
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo or {}
local CLASS = "weapon_stts_phone"

util.AddNetworkString("stts_tc_send")  -- <- peer number, text, media id (0 = none)
util.AddNetworkString("stts_tc_ask")   -- <- 0 = history of the phone in my hand, 1 = conversation read (peer number)
util.AddNetworkString("stts_tc_full")  -- -> phone number, compressed json history
util.AddNetworkString("stts_tc_msg")   -- -> one new message
util.AddNetworkString("stts_tc_wipe")  -- -> forget everything

local MAX_LEN = G.ChatMaxLen or 300
local PER_THREAD = G.ChatPerThread or 50
local PER_PHONE = G.ChatPerPhone or 400
local COOLDOWN = G.ChatCooldown or 0.6

TC.Held = TC.Held or {} -- fix17: [phone number in airplane mode] = {waiting messages}
TC.Box = TC.Box or {} -- [phone number] = {count = n, threads = {[peer number] = {name = "", unread = n, msgs = {{me, text, time}}}}}

local function Box(num)
	local b = TC.Box[num]
	if not b then b = {count = 0, threads = {}} TC.Box[num] = b end
	return b
end

local function PhoneByNum(num)
	local P = STTS.Phone
	local w = P and P.Numbers and P.Numbers[num]
	return IsValid(w) and w or nil
end

local function NameOf(num)
	local w = PhoneByNum(num)
	local n = w and w:GetNWString("STTS_PName", "") or ""
	return n ~= "" and n or num
end

local function OwnerOf(wep)
	local o = IsValid(wep) and wep:GetOwner()
	if IsValid(o) and o:IsPlayer() then return o end
end

local function Awake(ply)
	return IsValid(ply) and ply:Alive() and not (ply.organism and ply.organism.otrub)
end

local function HeldPhone(ply)
	if not Awake(ply) then return end
	local w = ply:GetActiveWeapon()
	if IsValid(w) and w:GetClass() == CLASS then return w end
end

local function Unread(num)
	local b = TC.Box[num]
	if not b then return 0 end
	local n = 0
	for _, t in pairs(b.threads) do n = n + (t.unread or 0) end
	return n
end

-- unread counter on the phone itself (home screen badge, seen by everybody)
local function Publish(num)
	local w = PhoneByNum(num)
	if not w then return end
	local n = math.min(Unread(num), 99)
	if w:GetNW2Int("TCUnread", 0) ~= n then w:SetNW2Int("TCUnread", n) end
end
TC.Publish = Publish

local function Trim(b, t)
	while #t.msgs > PER_THREAD do table.remove(t.msgs, 1) b.count = b.count - 1 end
	while b.count > PER_PHONE do
		-- drop the oldest message of the whole phone
		local oldT, oldAt
		for _, th in pairs(b.threads) do
			local m = th.msgs[1]
			if m and (not oldAt or m[3] < oldAt) then oldT, oldAt = th, m[3] end
		end
		if not oldT then break end
		table.remove(oldT.msgs, 1)
		b.count = b.count - 1
	end
end

local function Push(num, peer, me, text, t, media)
	local b = Box(num)
	local th = b.threads[peer]
	if not th then th = {name = NameOf(peer), unread = 0, msgs = {}} b.threads[peer] = th end
	th.name = NameOf(peer)
	th.msgs[#th.msgs + 1] = {me, text, t, media or 0}
	b.count = b.count + 1
	if not me then th.unread = (th.unread or 0) + 1 end
	Trim(b, th)
	Publish(num)
	return th
end

-- live update for whoever owns that phone right now
local function Notify(num, peer, me, text, t, media)
	local w = PhoneByNum(num)
	local ply = OwnerOf(w)
	if not ply or ply:IsBot() then return end
	net.Start("stts_tc_msg")
		net.WriteString(num)
		net.WriteString(peer)
		net.WriteString(NameOf(peer))
		net.WriteBool(me)
		net.WriteString(text)
		net.WriteUInt(t, 32)
		net.WriteBool(not me and ply:Alive()) -- play the notification sound
		net.WriteUInt(media or 0, 32)
	net.Send(ply)
end

local function Clean(text)
	if not isstring(text) then return end
	text = string.gsub(text, "%c", " ")
	text = string.Trim(text)
	if text == "" then return end
	local n = utf8.len(text)
	if not n then return end -- broken utf-8
	if n > MAX_LEN then text = string.sub(text, 1, utf8.offset(text, MAX_LEN + 1) - 1) end
	return text
end

local BOT_REPLIES = {"Я понял.", "Ок.", "Хорошо.", "Да, вижу.", "Где ты?"}

-- the receiving side of a message (also for the ones that waited for airplane mode)
local function Arrive(toWep, toNum, fromNum, text, t, media)
	Push(toNum, fromNum, false, text, t, media)
	Notify(toNum, fromNum, false, text, t, media)
	-- small toast on the receiving phone (everybody looking at it sees it)
	toWep:SetNW2String("Flash", "New message")
	toWep:SetNW2Float("FlashAt", CurTime())
	-- Settings: the notification sound plays out loud from the phone
	local P = STTS.Phone
	if P and P.NotifySound then P.NotifySound(toWep) end
end

function TC.Send(fromWep, toNum, text, fromPly, media)
	if not IsValid(fromWep) then return false end
	if fromWep:GetNW2Bool("Plane", false) then return false end -- fix17: airplane mode
	local fromNum = fromWep:GetNWString("STTS_Num", "")
	if fromNum == "" or toNum == fromNum or toNum == "911" then return false end
	local toWep = PhoneByNum(toNum)
	if not toWep then return false end
	media = tonumber(media) or 0
	-- fix17: the other phone is in airplane mode: the message waits for it
	if toWep:GetNW2Bool("Plane", false) then
		local MD = STTS.PhoneMedia
		if media > 0 and not (MD and MD.HasPhoto and MD.HasPhoto(fromWep, media)) then return false end
		text = media > 0 and (Clean(text) or "") or Clean(text)
		if not text then return false end
		local q = TC.Held[toNum] or {}
		TC.Held[toNum] = q
		if #q >= PER_THREAD then return false end
		local t = os.time()
		q[#q + 1] = {fromWep = fromWep, fromNum = fromNum, text = text, t = t, media = media, ply = fromPly}
		Push(fromNum, toNum, true, text, t, media)
		Notify(fromNum, toNum, true, text, t, media)
		return true
	end
	if media > 0 then
		local MD = STTS.PhoneMedia
		if not (MD and MD.Share and IsValid(fromPly) and MD.Share(fromPly, fromWep, toWep, media)) then return false end
		text = Clean(text) or ""
	else
		text = Clean(text)
		if not text then return false end
	end
	local t = os.time()
	Push(fromNum, toNum, true, text, t, media)
	Notify(fromNum, toNum, true, text, t, media)
	Arrive(toWep, toNum, fromNum, text, t, media)

	-- bots answer, so TeleChat can be tested alone
	local bot = OwnerOf(toWep)
	if bot and bot:IsBot() and Awake(bot) and fromPly and not fromPly:IsBot() and (toWep.STTS_TCBotCD or 0) <= CurTime() then
		toWep.STTS_TCBotCD = CurTime() + 2
		timer.Simple(1.5, function()
			if not IsValid(toWep) or not IsValid(fromWep) or OwnerOf(toWep) ~= bot then return end
			local th = Box(toNum).threads[fromNum]
			if th then th.unread = 0 end
			TC.Send(toWep, fromNum, BOT_REPLIES[math.random(#BOT_REPLIES)])
		end)
	end
	return true
end

-- whole history of one phone (trimmed until it fits into one net message)
local function SendFull(ply, wep)
	local num = wep:GetNWString("STTS_Num", "")
	if num == "" then return end
	local b = TC.Box[num]
	local data
	for _, keep in ipairs({PER_THREAD, 25, 10, 4}) do
		local out = {}
		for peer, th in pairs(b and b.threads or {}) do
			local msgs = {}
			for i = math.max(1, #th.msgs - keep + 1), #th.msgs do
				local m = th.msgs[i]
				msgs[#msgs + 1] = {m[1] and 1 or 0, m[2], m[3], m[4] or 0}
			end
			out[#out + 1] = {p = peer, n = NameOf(peer), u = th.unread or 0, m = msgs}
		end
		data = util.Compress(util.TableToJSON(out) or "[]")
		if data and #data < 60000 then break end
	end
	if not data or #data >= 60000 then return end
	net.Start("stts_tc_full")
		net.WriteString(num)
		net.WriteUInt(#data, 16)
		net.WriteData(data, #data)
	net.Send(ply)
	Publish(num)
end

net.Receive("stts_tc_send", function(_, ply)
	local peer, text, media = net.ReadString(), net.ReadString(), net.ReadUInt(32)
	local wep = HeldPhone(ply)
	if not wep then return end
	local now = CurTime()
	if (ply.STTS_TCNext or 0) > now then return end
	ply.STTS_TCNext = now + COOLDOWN
	-- 20 messages per minute at most
	ply.STTS_TCWin = ply.STTS_TCWin or {}
	local win = {}
	for _, at in ipairs(ply.STTS_TCWin) do if now - at < 60 then win[#win + 1] = at end end
	if #win >= 20 then ply.STTS_TCWin = win return end
	win[#win + 1] = now
	ply.STTS_TCWin = win
	TC.Send(wep, peer, text, ply, media)
end)

net.Receive("stts_tc_ask", function(_, ply)
	local kind = net.ReadUInt(2)
	local wep = HeldPhone(ply)
	if not wep then return end
	if kind == 0 then
		if (ply.STTS_TCAsk or 0) > CurTime() then return end
		ply.STTS_TCAsk = CurTime() + 1
		SendFull(ply, wep)
	elseif kind == 1 then
		local peer = net.ReadString()
		local num = wep:GetNWString("STTS_Num", "")
		local b = TC.Box[num]
		local th = b and b.threads[peer]
		if th and (th.unread or 0) > 0 then th.unread = 0 Publish(num) end
	end
end)

-- a phone came back (inventory recreates the weapon): restore its badge
hook.Add("WeaponEquip", "STTS_TeleChatBadge", function(wep)
	if not IsValid(wep) or wep:GetClass() ~= CLASS then return end
	timer.Simple(0, function()
		if IsValid(wep) then Publish(wep:GetNWString("STTS_Num", "")) end
	end)
end)

-- fix17: airplane mode went off: everything that waited arrives now
function TC.Release(wep)
	if not IsValid(wep) then return end
	local num = wep:GetNWString("STTS_Num", "")
	local q = TC.Held[num]
	TC.Held[num] = nil
	if not q then return end
	local MD = STTS.PhoneMedia
	for _, m in ipairs(q) do
		local media = m.media or 0
		if media > 0 and not (MD and MD.Share and MD.Share(m.ply, m.fromWep, wep, media, true)) then media = 0 end
		if media > 0 or (m.text or "") ~= "" then Arrive(wep, num, m.fromNum, m.text or "", m.t or os.time(), media) end
	end
end

function TC.Reset()
	TC.Held = {}
	TC.Box = {}
	for _, w in ipairs(ents.FindByClass(CLASS)) do w:SetNW2Int("TCUnread", 0) end
	net.Start("stts_tc_wipe") net.Broadcast()
end

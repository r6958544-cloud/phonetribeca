--[[---------------------------------------------------------------------------
	fix54: stts_phone_botphoto [me]   (superadmin / listen server host / single player)
	a bot takes a photo with its phone and sends it to YOUR phone in TeleChat: a test of
	received media (blurred preview + size, a tap downloads it).
	a bot has no game client, so the picture is rendered by the game of the player who
	typed the command (from the bot's eyes, cl_phone_botphoto.lua) and uploaded for the
	bot. that client keeps nothing: its TeleChat gets the photo like from anybody else.
	"me" = the bot first stands in front of you and takes YOUR picture.
	no living bot = one is added ("bot"), the round may have to start first.
---------------------------------------------------------------------------]]
if CLIENT then return end
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local CLASS = "weapon_stts_phone"
local CHUNK = G.PhotoChunk or 16000

util.AddNetworkString("stts_phone_botshot") -- -> token, eye pos, angles, bot (render this)
util.AddNetworkString("stts_phone_botup")   -- <- token, part, parts, jpg chunk (+ tiny preview with the last)

local function Say(ply, msg)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[phone] " .. msg) else print("[phone] " .. msg) end
end

local function Allowed(ply)
	return IsValid(ply) and (game.SinglePlayer() or ply:IsListenServerHost() or ply:IsSuperAdmin())
end

-- the phone of a player (given when he has none: no phone on spawn by default since fix54)
local function PhoneOf(ply)
	local w = ply:GetWeapon(CLASS)
	if not IsValid(w) then w = ply:Give(CLASS) end
	if not IsValid(w) then return end
	local P = STTS.Phone
	local num = w:GetNWString("STTS_Num", "")
	if P and P.Register and (num == "" or not P.Numbers or P.Numbers[num] ~= w) then P.Register(w, ply) end
	if w:GetNWString("STTS_Num", "") == "" then return end
	return w
end

local function AliveBot()
	for _, b in ipairs(player.GetBots()) do
		if IsValid(b) and b:Alive() then return b end
	end
end

local function Start(ply, bot, me)
	local mine, wep = PhoneOf(ply), PhoneOf(bot)
	if not mine or not wep then return Say(ply, "could not give a phone (to you or to " .. bot:Nick() .. ")") end
	if wep:GetNW2Bool("Plane", false) then wep:SetNW2Bool("Plane", false) end
	bot:SelectWeapon(CLASS)
	if me then
		-- in front of you, looking at you
		local f = ply:GetAimVector()
		f.z = 0
		if f:LengthSqr() < 0.01 then f = Vector(1, 0, 0) end
		f:Normalize()
		local base = ply:GetPos() + Vector(0, 0, 8)
		local tr = util.TraceHull({start = base, endpos = base + f * 110, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64),
			filter = {ply, bot}, mask = MASK_PLAYERSOLID})
		bot:SetPos(tr.HitPos - Vector(0, 0, 8))
		local a = (ply:EyePos() - bot:EyePos()):Angle()
		bot:SetEyeAngles(Angle(a.p, a.y, 0))
	end
	-- a moment later: the bot turned, the phone is in its hand
	timer.Simple(me and 0.4 or 0.15, function()
		if not IsValid(ply) or not IsValid(bot) or not IsValid(wep) or not IsValid(mine) then return end
		local pos = bot:EyePos()
		local target = ply:EyePos() - Vector(0, 0, 6)
		local tr = util.TraceLine({start = pos, endpos = target, filter = {bot, ply, wep}, mask = MASK_SOLID_BRUSHONLY})
		local ang
		if me or (not tr.Hit and pos:DistToSqr(target) < 1500 * 1500) then ang = (target - pos):Angle() else ang = bot:EyeAngles() end
		ang.r = 0
		pos = pos + ang:Forward() * 10 -- out of its own head
		local token = math.random(1, 65535)
		ply.STTS_BotShot = {token = token, bot = bot, wep = wep, mine = mine, at = CurTime(), parts = {}, bytes = 0}
		net.Start("stts_phone_botshot")
			net.WriteUInt(token, 16)
			net.WriteVector(pos)
			net.WriteAngle(ang)
			net.WriteEntity(bot)
		net.Send(ply)
	end)
end

concommand.Add("stts_phone_botphoto", function(ply, _, args)
	if not IsValid(ply) then return Say(nil, "type it in a player's console: that player's game renders the picture") end
	if not Allowed(ply) then return Say(ply, "stts_phone_botphoto: superadmin only") end
	if (ply.STTS_BotShotCD or 0) > CurTime() then return end
	ply.STTS_BotShotCD = CurTime() + 3
	local me = args[1] == "me" or args[1] == "1"
	local bot = AliveBot()
	if bot then return Start(ply, bot, me) end
	if #player.GetBots() == 0 then
		if not player.CreateNextBot then return Say(ply, "no bot: type 'bot' in the console") end
		player.CreateNextBot("PhotoBot")
	end
	Say(ply, "waiting for a living bot...")
	local name, tries = "STTS_BotShot" .. ply:EntIndex(), 0
	timer.Create(name, 0.5, 16, function()
		tries = tries + 1
		if not IsValid(ply) then timer.Remove(name) return end
		local b = AliveBot()
		if b then timer.Remove(name) Start(ply, b, me) return end
		if tries == 3 then
			for _, x in ipairs(player.GetBots()) do if IsValid(x) and not x:Alive() then x:Spawn() break end end
		end
		if tries >= 16 then Say(ply, "no living bot (has the round started?)") end
	end)
end)

net.Receive("stts_phone_botup", function(len, ply)
	local s = ply.STTS_BotShot
	local token, idx, total, size = net.ReadUInt(16), net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
	if not s or s.token ~= token then return end
	if CurTime() - s.at > 30 or total < 1 or idx < 1 or idx > total or size < 1 or size > CHUNK or size * 8 > len then
		ply.STTS_BotShot = nil
		return
	end
	local data = net.ReadData(size)
	if type(data) ~= "string" or #data ~= size or s.parts[idx] then return end
	s.parts[idx], s.bytes = data, s.bytes + size
	if s.bytes > G.PhotoMaxBytes then ply.STTS_BotShot = nil return Say(ply, "the photo is too big") end
	if idx == total then -- the tiny preview comes with the last part
		local n = net.ReadUInt(13)
		if n >= 4 and n <= 4096 then s.prev = net.ReadData(n) end
	end
	for i = 1, total do if not s.parts[i] then return end end
	ply.STTS_BotShot = nil
	local bot, wep, mine = s.bot, s.wep, s.mine
	if not IsValid(bot) or not IsValid(wep) or not IsValid(mine) then return Say(ply, "the bot or a phone is gone") end
	local MD, TC = STTS.PhoneMedia, STTS.PhoneChat
	local id = MD and MD.AddPhotoFor and MD.AddPhotoFor(wep, table.concat(s.parts), bot, s.prev)
	if not id then return Say(ply, "the bot's phone did not take it (its gallery is full / server photo memory)") end
	bot.STTS_SendCD, bot.STTS_SendLog = 0, nil -- a debug command: no send limit for the bot
	local ok = TC and TC.Send and TC.Send(wep, mine:GetNWString("STTS_Num", ""), "", bot, id)
	if ok then Say(ply, bot:Nick() .. " sent you a photo: open TeleChat, tap it to download")
	else Say(ply, "sending failed (airplane mode on your phone? your gallery full?)") end
end)

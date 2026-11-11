--[[---------------------------------------------------------------------------
	ZHUNTER phone (vivo X300 Pro / Google Pixel 6 Pro / iPhone 18 Pro) - shared constants.
	Geometry is in model space of models/stts/vivo_x300pro.mdl (1 unit = 1 inch):
	  +X = top of the phone, +Y = left edge (seen from the front), +Z = out of the display.
	Values come from the model build script (modelsrc/vivo_x300pro/build_vivo.py)
	and match the $attachment lines in vivo_x300pro.qc.
---------------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

STTS = STTS or {}
local G = {}
STTS.PhoneGeo = G

G.Model = "models/stts/vivo_x300pro.mdl"
G.Fallback = "models/props_lab/reciever01b.mdl" -- stock fallback; actual phones are bundled
G.HasModel = file.Exists(G.Model, "GAME")

-- display (attachment "screen"): centre, size
G.ScreenPos = Vector(0.0014, 0, 0.1595)
G.ScreenW = 2.7751   -- along -Y (left -> right for the viewer)
G.ScreenH = 6.1630   -- along +X (bottom -> top)
-- cameras (attachments "cam_front" / "cam_back"), forward = viewing direction, up = top of the phone
G.CamFront = Vector(2.911, 0.001, 0.208)
G.CamFrontAng = Angle(-90, 0, 180)
G.CamBack = Vector(2.100, -0.455, -0.448)
G.CamBackAng = Angle(90, 0, 0)
-- body bounds (used by the box fallback and physics)
G.Mins = Vector(-3.173, -1.507, -0.398)
G.Maxs = Vector(3.173, 1.502, 0.158)

--[[ fix28: several phone models. every phone entity gets one at random (NW2 int "PMod",
     server: sv_shooting_phone.lua PHONE.PickModel). EVERYTHING that depends on the body
     comes from this table: display rect (UI mapping, finger, screen lights), cameras
     (photo / video / video calls / spectator stream), flash LED, palm seat (back of the
     phone on the palm), ear pose, black core, fallback slab, Dynamic Island over the
     front camera, screen material. the vivo values are the old ones (unchanged).
     values of the new phones come from modelsrc/tools/build_phone.py (geo.json). ]]
G.Models = {
	{
		id = "vivo", name = "vivo X300 Pro",
		Model = "models/stts/vivo_x300pro.mdl", ScreenMat = "vivo_screen",
		ScreenPos = G.ScreenPos, ScreenW = G.ScreenW, ScreenH = G.ScreenH,
		CamFront = G.CamFront, CamFrontAng = G.CamFrontAng, CamBack = G.CamBack, CamBackAng = G.CamBackAng,
		FlashPos = Vector(2.62, -1.02, -0.46),
		Mins = G.Mins, Maxs = G.Maxs,
		Back = -0.32, -- back plane of the body (lies on the palm)
		Core = {
			{Vector(-3.05, -0.9, -0.12), Vector(3.05, 0.9, 0.095)},
			{Vector(-2.75, -1.38, -0.12), Vector(2.75, 1.38, 0.095)},
			{Vector(-2.95, -1.25, -0.12), Vector(2.95, 1.25, 0.095)},
		},
		Island = {w = 122, h = 36, y = 8, minW = 70, minH = 26}, -- UI px (432 x 960)
	},
	{
		id = "pixel", name = "Google Pixel 6 Pro",
		Model = "models/stts/pixel_6pro.mdl", ScreenMat = "pix6_screen",
		ScreenPos = Vector(0.0231, 0, 0.1713), ScreenW = 2.8548, ScreenH = 6.2030, -- curved edges, 6.7"
		CamFront = Vector(2.9674, 0, 0.2213), CamFrontAng = Angle(-90, 0, 180),
		CamBack = Vector(2.1106, -0.7838, -0.3153), CamBackAng = Angle(90, 0, 0), -- main 50 MP lens in the camera bar
		FlashPos = Vector(2.1106, 0.8684, -0.2819),
		Mins = Vector(-3.2265, -1.4842, -0.2653), Maxs = Vector(3.2265, 1.4639, 0.1713),
		Back = -0.1693,
		Core = {
			{Vector(-3.1265, -0.7491, -0.0693), Vector(3.1265, 0.7491, 0.1093)},
			{Vector(-2.5116, -1.3639, -0.0693), Vector(2.5116, 1.3639, 0.1093)},
			{Vector(-2.9420, -1.1795, -0.0693), Vector(2.9420, 1.1795, 0.1093)},
		},
		Island = {w = 32, h = 32, y = 8, minW = 32, minH = 32}, -- round punch hole (24.6 x 25.2 px at y 11.6)
	},
	{
		id = "iphone", name = "iPhone 18 Pro",
		Model = "models/stts/iphone_18pro.mdl", ScreenMat = "iph18_screen",
		ScreenPos = Vector(0, 0.0014, 0.1732), ScreenW = 2.6267, ScreenH = 5.7014, -- 6.3"
		CamFront = Vector(2.6383, -0.1866, 0.2232), CamFrontAng = Angle(-90, 0, 180),
		CamBack = Vector(2.3885, -0.8477, -0.4119), CamBackAng = Angle(90, 0, 0), -- main 48 MP (top left from the back)
		FlashPos = Vector(2.4153, 0.8730, -0.2810),
		Mins = Vector(-2.9531, -1.4326, -0.3619), Maxs = Vector(2.9531, 1.4326, 0.1732),
		Back = -0.1712,
		Core = {
			{Vector(-2.8531, -0.7309, -0.0712), Vector(2.8531, 0.7309, 0.1112)},
			{Vector(-2.2514, -1.3326, -0.0712), Vector(2.2514, 1.3326, 0.1112)},
			{Vector(-2.6726, -1.1521, -0.0712), Vector(2.6726, 1.1521, 0.1112)},
		},
		Island = {w = 106, h = 44, y = 14, minW = 100, minH = 40}, -- real Dynamic Island cutout (100.8 x 40 px at y 15.8)
	},
}
G.ModelById = {}
for i, m in ipairs(G.Models) do
	m.index = i
	m.HasModel = file.Exists(m.Model, "GAME")
	m.PalmShift = -0.32 - m.Back -- moves the phone along its normal so ITS back lies where the vivo back was (vivo = 0)
	G.ModelById[m.id] = m
end

--[[ fix29: every phone has its own body colour (NW2 int "PCol"). the paint (back panel +
     frame) of each model sits in flat patches of its atlas; *_body_paint.vtf has those
     patches light grey with alpha = mask, so $blendtintbybasealpha + $color2 recolours
     ONLY the paint (lenses, camera module, logos stay). one extra 350 KB texture per model,
     any colour at runtime (client: CreateMaterial per colour, cached).
     PCol: 0 = not picked yet, 1 = stock texture, 0x1000000 + 0xRRGGBB = that colour. ]]
local PAINT = {
	vivo   = {folder = "vivo",  prefix = "vivo",  exp = 28, boost = 2.5, env = "[0.35 0.35 0.38]"},
	pixel  = {folder = "pix6",  prefix = "pix6",  exp = 34, boost = 2.6, env = "[0.35 0.35 0.38]"},
	iphone = {folder = "iph18", prefix = "iph18", exp = 30, boost = 3.0, env = "[0.42 0.42 0.44]"},
}
for _, m in ipairs(G.Models) do
	local pt = PAINT[m.id]
	m.BodyMat = pt.prefix .. "_body"
	m.Paint = pt
	m.PaintTex = "models/stts/" .. pt.folder .. "/" .. pt.prefix .. "_body_paint"
	m.PaintBump = "models/stts/" .. pt.folder .. "/" .. pt.prefix .. "_body_n"
end
G.COL_STOCK = 1
G.COL_FLAG = 0x1000000
-- named colours (admin command + part of the random pool). r g b 0..255 of the paint
G.Colors = {
	{"black", 14, 14, 16}, {"white", 236, 236, 232}, {"silver", 170, 172, 176}, {"graphite", 58, 60, 64},
	{"red", 196, 24, 32}, {"blue", 30, 70, 190}, {"navy", 24, 34, 80}, {"sky", 120, 175, 230},
	{"green", 40, 140, 70}, {"mint", 150, 220, 190}, {"purple", 110, 50, 170}, {"lavender", 185, 165, 225},
	{"pink", 240, 140, 175}, {"gold", 215, 175, 95}, {"orange", 235, 110, 30}, {"yellow", 240, 210, 60},
	{"teal", 20, 130, 135}, {"bronze", 150, 95, 55},
}
G.ColorByName = {}
for _, c in ipairs(G.Colors) do G.ColorByName[c[1]] = c end
function G.PackColor(r, g, b) return G.COL_FLAG + bit.lshift(math.Clamp(math.floor(r), 0, 255), 16) + bit.lshift(math.Clamp(math.floor(g), 0, 255), 8) + math.Clamp(math.floor(b), 0, 255) end
-- nil = stock look, else r, g, b (0..255)
function G.UnpackColor(v)
	v = tonumber(v) or 0
	if v < G.COL_FLAG then return nil end
	v = v - G.COL_FLAG
	return bit.band(bit.rshift(v, 16), 255), bit.band(bit.rshift(v, 8), 255), bit.band(v, 255)
end
function G.ColorName(v)
	local r, g, b = G.UnpackColor(v)
	if not r then return "stock" end
	for _, c in ipairs(G.Colors) do if c[2] == r and c[3] == g and c[4] == b then return c[1] end end
	return string.format("#%02X%02X%02X", r, g, b)
end
-- "black" / "random" / "stock" / "#ff8800" / "ff8800" -> PCol value (nil = unknown)
function G.ParseColor(str)
	str = string.lower(string.Trim(tostring(str or "")))
	if str == "stock" or str == "default" then return G.COL_STOCK end
	if str == "random" or str == "rand" then return G.RandomColor() end
	local c = G.ColorByName[str]
	if c then return G.PackColor(c[2], c[3], c[4]) end
	local hex = string.match(str, "^#?(%x%x%x%x%x%x)$")
	if hex then return G.COL_FLAG + tonumber(hex, 16) end
end
-- Curated pastel phone finishes, not unconstrained RGB/HSV. A shuffled
-- family bag spreads colours across the whole palette before any family repeats.
G.PastelFinishes={
 {244,238,222},{224,224,228},{215,203,190},{220,195,180},
 {239,200,202},{226,185,198},{232,203,216},{217,195,217},
 {203,194,224},{191,201,226},{183,211,231},{189,224,228},
 {183,219,212},{195,224,203},{205,222,184},{224,228,190},
 {239,224,187},{242,214,184},{236,200,183},{206,208,195},
 {211,220,230},{230,211,204},{216,226,218},{227,221,236}
}
local finishBag,finishRecent,lastFamily={}, {},nil
function G.RandomColor()
 if #finishBag==0 then
  for i=1,#G.PastelFinishes do finishBag[i]=i end
  for i=#finishBag,2,-1 do local j=math.random(i);finishBag[i],finishBag[j]=finishBag[j],finishBag[i] end
  if finishBag[#finishBag]==lastFamily then finishBag[1],finishBag[#finishBag]=finishBag[#finishBag],finishBag[1] end
 end
 local family=table.remove(finishBag);lastFamily=family
 local c=G.PastelFinishes[family];local packed
 for attempt=1,16 do
  local light=math.random(-7,7)
  local r,g,b=math.Clamp(c[1]+light+math.random(-4,4),165,250),math.Clamp(c[2]+light+math.random(-4,4),165,250),math.Clamp(c[3]+light+math.random(-4,4),165,250)
  packed=G.PackColor(r,g,b);local near=false
  for _,v in ipairs(finishRecent) do
   local dr,dg,db=r-v[1],g-v[2],b-v[3];if dr*dr+dg*dg+db*db<81 then near=true break end
  end
  if not near or attempt==16 then
   finishRecent[#finishRecent+1]={r,g,b};if #finishRecent>48 then table.remove(finishRecent,1) end
   return packed
  end
 end
 return packed
end

-- geometry of a phone: entity (NW2 "PMod"), model table, model index or nil (= vivo)
function G.Of(x)
	if istable(x) and x.ScreenPos then return x end
	if isnumber(x) then return G.Models[x] or G.Models[1] end
	if x and IsValid(x) and x.GetNW2Int then return G.Models[x:GetNW2Int("PMod", 1)] or G.Models[1] end
	return G.Models[1]
end
-- the model the entity draws / collides with (fallback while that model is not compiled)
function G.ModelPath(x)
	local m = G.Of(x)
	if m.HasModel then return m.Model, true end
	return G.Fallback, false
end

--[[ fix28: which model a new phone gets (server). "shuffle bag": random order, but every
     allowed model comes up once before any model repeats, so with 3+ players everybody
     sees all phones. stts_phone_models = allowed ids ("vivo pixel iphone"), only compiled
     models are used (a model missing on the server is skipped). ]]
if SERVER then
	local cvModels = CreateConVar("stts_phone_models", "vivo pixel iphone", {FCVAR_ARCHIVE}, "phone models new phones are picked from at random: vivo pixel iphone")
	local bag = {}
	function G.Allowed()
		local out, seen = {}, {}
		for id in string.gmatch(string.lower(cvModels:GetString()), "%a+") do
			local m = G.ModelById[id]
			if m and m.HasModel and not seen[m.index] then out[#out + 1] = m.index seen[m.index] = true end
		end
		if #out == 0 then
			for _, m in ipairs(G.Models) do if m.HasModel then out[#out + 1] = m.index end end
		end
		return out
	end
	function G.PickModel()
		local allowed = G.Allowed()
		if #allowed == 0 then return 1 end -- nothing compiled yet: vivo geometry + fallback model
		if #allowed == 1 then return allowed[1] end
		local ok = {}
		for _, i in ipairs(allowed) do ok[i] = true end
		for k = #bag, 1, -1 do if not ok[bag[k]] then table.remove(bag, k) end end
		if #bag == 0 then
			for _, i in ipairs(allowed) do bag[#bag + 1] = i end
			for k = #bag, 2, -1 do local r = math.random(k) bag[k], bag[r] = bag[r], bag[k] end
		end
		return table.remove(bag)
	end
	STTS.Phone = STTS.Phone or {}
	STTS.Phone.PickModel = G.PickModel

	--[[ fix29: colour of a new phone. stts_phone_colors 0 = every phone stock, 1 = on.
	     stts_phone_color_black = chance of black, stts_phone_color_stock = chance of the
	     original texture, the rest is random: half from G.Colors, half any hue. ]]
	local cvCol = CreateConVar("stts_phone_colors", "1", {FCVAR_ARCHIVE}, "1 = every phone gets its own random body colour, 0 = all stock")
	local cvBlack = CreateConVar("stts_phone_color_black", "0.3", {FCVAR_ARCHIVE}, "chance (0..1) that a new phone is black")
	local cvStock = CreateConVar("stts_phone_color_stock", "0.15", {FCVAR_ARCHIVE}, "chance (0..1) that a new phone keeps the original colour")
	function G.PickColor()
		if not cvCol:GetBool() then return G.COL_STOCK end
		-- Legacy archived black/stock probabilities must not override the new palette.
		return G.RandomColor()
	end
	STTS.Phone.PickColor = G.PickColor

	-- admin: zhunter_phones                      = who has which phone
	--        zhunter_phones reroll               = new random model for every phone
	--        zhunter_phones set <player|me|all> <vivo|pixel|iphone>
	--        zhunter_phones color <player|me|all> <black|random|stock|red|...|#RRGGBB>   (fix29)
	--        zhunter_phones recolor              = new random colour for every phone (fix29)
	concommand.Add("zhunter_phones", function(ply, _, args)
		if IsValid(ply) and not ply:IsSuperAdmin() then return end
		local function Say(msg) if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end end
		local phones = ents.FindByClass("weapon_stts_phone")
		local cmd = string.lower(args[1] or "")
		if cmd == "reroll" then
			for _, w in ipairs(phones) do
				if w.SetPhoneModel then w:SetPhoneModel(G.PickModel()) end
				if w.SetPhoneColor then w:SetPhoneColor(G.PickColor()) end
			end
			Say("phones rerolled: " .. #phones)
		elseif cmd == "recolor" or cmd == "recolour" then
			for _, w in ipairs(phones) do if w.SetPhoneColor then w:SetPhoneColor(G.PickColor()) end end
			Say("phones recoloured: " .. #phones)
		elseif cmd == "color" or cmd == "colour" then
			local who, cstr = string.lower(args[2] or ""), args[3] or ""
			local n = 0
			for _, w in ipairs(phones) do
				local o = w:GetOwner()
				local hit = who == "all" or (who == "me" and o == ply) or (who ~= "" and IsValid(o) and o:IsPlayer() and string.find(string.lower(o:Nick()), who, 1, true))
				if hit and w.SetPhoneColor then
					local v = G.ParseColor(cstr) -- per phone, so "random" gives everybody a different one
					if not v then
						local names = {}
						for _, c in ipairs(G.Colors) do names[#names + 1] = c[1] end
						Say("colours: stock random #RRGGBB " .. table.concat(names, " "))
						return
					end
					w:SetPhoneColor(v) n = n + 1
				end
			end
			Say("recoloured: " .. n .. " phone(s)")
		elseif cmd == "set" then
			local who, id = string.lower(args[2] or ""), string.lower(args[3] or "")
			local m = G.ModelById[id]
			if not m then Say("models: vivo pixel iphone") return end
			if not m.HasModel then Say(m.name .. " is not compiled on the server (stts_content/models/stts/)") end
			local n = 0
			for _, w in ipairs(phones) do
				local o = w:GetOwner()
				local hit = who == "all" or (who == "me" and o == ply) or (IsValid(o) and o:IsPlayer() and string.find(string.lower(o:Nick()), who, 1, true))
				if hit and w.SetPhoneModel then w:SetPhoneModel(m.index) n = n + 1 end
			end
			Say(m.name .. ": " .. n .. " phone(s)")
		else
			local av = {}
			for _, i in ipairs(G.Allowed()) do av[#av + 1] = G.Models[i].id end
			Say("phone models in use: " .. (#av > 0 and table.concat(av, " ") or "none compiled (fallback)"))
			for _, w in ipairs(phones) do
				local o = w:GetOwner()
				Say(string.format("  %s  %s  %s  %s", w:GetNWString("STTS_Num", "?"), G.Of(w).name, G.ColorName(w:GetNW2Int("PCol", 1)), IsValid(o) and o:IsPlayer() and o:Nick() or "(on the ground)"))
			end
		end
	end)
end

-- render targets: UI resolution follows the display aspect (2.22 : 1)
G.RTW, G.RTH = 432, 960
G.FeedW, G.FeedH = 270, 480     -- live camera / video call feed
G.PhotoW, G.PhotoH = 576, 1024  -- saved photos (9:16)
G.FovBack, G.FovFront = 52, 78 -- horizontal fov of the portrait image (fix19: back to fix16; fix24: front camera +20, was 58)
G.ZoomMax = 5                  -- camera zoom (slider in Camera and in video calls)

-- video: frames are packed into jpg "pages" (atlas 8 x 4 frames of 128 x 224, 9:16)
G.FrameW, G.FrameH = 128, 224
G.AtlasCols, G.AtlasRows = 8, 4
G.AtlasW, G.AtlasH = G.FrameW * G.AtlasCols, G.FrameH * G.AtlasRows -- 1024 x 896
G.PageFrames = G.AtlasCols * G.AtlasRows
G.VidFps = 15
G.VidMaxSec = 120              -- fix15: up to 2 minutes (was 12 s)
G.VidMaxPages = 450 -- fix30: 120 seconds, 15 fps, 4 frames/page
G.VidJpgQ = {88} -- fixed quality: never recapture a page at lower quality

--[[ fix16: quality of the video recording and of the spectator stream is set on the
     server (console: zhunter_phone_quality, sv_shooting_phone_media.lua) and reaches
     every PC as global ints. "res" = pixelation preset, the frame keeps 4:7 (9:16-ish):
       1 = 64 x 112 (very pixelated) ... 3 = 128 x 224 (default, as fix15) ... 6 = 256 x 448
     a video remembers its own preset (old videos = 3), so changing it never breaks them. ]]
G.VidRes = {
	{w = 64, h = 112},
	{w = 96, h = 168},
	{w = 128, h = 224},
	{w = 160, h = 280},
	{w = 192, h = 336},
	{w = 256, h = 448},
	{w = 256, h = 448, cols = 2, rows = 2}, -- fix30: small pages, legacy layouts 1..6 unchanged
}
G.VidResDefault = 7
G.FrameMaxW, G.FrameMaxH = 256, 448 -- render targets are this big, the frame uses its top left part
G.VidMaxPagesNet = 511              -- 9 bits, update BOTH server and clients
G.VidMaxFramesNet = 4095            -- 12 bits

-- frame size + page atlas of a preset (pages are at most 1024 x 1024)
local layouts = {}
function G.VidLayout(res)
	res = math.Clamp(math.floor(tonumber(res) or G.VidResDefault), 1, #G.VidRes)
	local l = layouts[res]
	if l then return l end
	local r = G.VidRes[res]
	local cols, rows = r.cols or math.floor(1024 / r.w), r.rows or math.floor(1024 / r.h)
	l = {res = res, w = r.w, h = r.h, cols = cols, rows = rows, aw = cols * r.w, ah = rows * r.h, frames = cols * rows}
	layouts[res] = l
	return l
end

-- pages a video of this preset / fps may have (2 minutes, capped by the net format)
function G.VidPagesFor(res, fps)
	local l = G.VidLayout(res)
	return math.min(G.VidMaxPagesNet, math.ceil((G.VidMaxSec or 120) * math.max(1, fps or G.VidFps) / l.frames))
end
-- most frames a video of this preset / fps may have
function G.VidMaxFrames(res, fps)
	local l = G.VidLayout(res)
	return math.min(G.VidMaxFramesNet, (G.VidMaxSec or 120) * math.max(1, fps or G.VidFps), G.VidPagesFor(res, fps) * l.frames)
end

--[[ fix17: flash LED on the back (next to the rear camera, model space) and the lights
     of the phone: torch from the pull-down shade (wide, rather weak), photo flash,
     video light (flash on while recording), front "flash" = light of the display ]]
G.FlashPos = Vector(2.62, -1.02, -0.46) -- vivo; fix28: per model in G.Models[i].FlashPos
G.FlashAng = Angle(90, 0, 0) -- forward = out of the back, like the rear camera

-- fix30 capture defaults; no runtime server setting / schema change required.
function G.RecFps() return G.VidFps end
function G.RecRes() return G.VidResDefault end
function G.RecQ() return G.VidJpgQ[1] end
function G.StreamFps() return 12 end
function G.StreamRes() return G.VidResDefault end
function G.StreamQ() return 55 end
-- Kept for callers of older revisions; the new encoder never retries JPEG.
function G.RecQList(q) return {q or G.RecQ()} end

-- apps (the only things the phone can do)
G.APP_HOME, G.APP_CONTACTS, G.APP_CALL, G.APP_CAMERA, G.APP_GALLERY, G.APP_SEND = 1, 2, 3, 4, 5, 6
G.APP_CHATS, G.APP_THREAD = 7, 8 -- TeleChat: list of chats / one conversation
G.APP_SETTINGS, G.APP_RINGTONES = 9, 10 -- Settings: root page / ringtone list (net: 5 bits since v19.2, max 31)
G.APP_TONES = 11 -- Settings: notification sound list
-- Settings sub-pages (one per iOS panel, like the real app: a push for every row)
G.APP_SOUNDS, G.APP_DISPLAY, G.APP_GENERAL, G.APP_NOTIF = 12, 13, 14, 15
G.APP_WIFI = 16 -- v19.2: Settings > Wi-Fi (the network of the map)
-- fix54: ZMusic (Apple Music look): root (tabs) / a list / an album, artist or playlist / one more level
G.APP_MUSIC, G.APP_MUSIC2, G.APP_MUSIC3, G.APP_MUSIC4 = 17, 18, 19, 20
-- fix55: Clock (World Clock / Alarms / Stopwatch / Timers) + the Add/Edit Alarm sheet
G.APP_CLOCK, G.APP_ALARMED = 21, 22
G.APP_WALLPAPER = 23 -- fix60: Settings > Wallpaper (the lock screen)
G.APP_AUTOLOCK = 24 -- fix61: Settings > Display & Brightness > Auto-Lock
G.APP_LAST = G.APP_AUTOLOCK -- (5 bits on the net: max 31)
G.WallCount = 24 -- fix61: wallpapers 1..24 (cl_phone_lock.lua LK.WALLS), 0 = automatic
--[[ fix61: Auto-Lock (Settings, NW2 "ALock" 0..6): how long a phone that left the hand stays
     unlocked with the display on. on the floor = the whole time, in the pocket / inventory =
     half of it (sv_phone_lock.lua). seconds, 0 = never ]]
G.AutoLock = {[0] = {30, "30 Seconds"}, {60, "1 Minute"}, {120, "2 Minutes"}, {180, "3 Minutes"},
	{240, "4 Minutes"}, {300, "5 Minutes"}, {0, "Never"}}
function G.AutoLockSecs(i)
	local o = G.AutoLock[math.floor(tonumber(i) or 0)] or G.AutoLock[0]
	return o[1]
end
function G.AutoLockName(i)
	local o = G.AutoLock[math.floor(tonumber(i) or 0)] or G.AutoLock[0]
	return o[2]
end
-- fix54: ZMusic. the music of a phone is heard by everybody near it (3D from the phone)
local cvZMHear = CreateConVar("zmusic_hear_dist", "1800", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "ZMusic: how far the music of a phone is heard (units)", 200, 10000)
local cvZMTrack = CreateConVar("zmusic_track_mb", "40", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "ZMusic: the biggest song file that can be played (MB)", 1, 200)
function G.ZMHearDist() return cvZMHear:GetFloat() end
function G.ZMTrackMax() return math.floor(cvZMTrack:GetFloat() * 1048576) end

--[[ Settings belong to the PHONE (NW2), a player's own phone gets his saved profile
     every spawn (sv_shooting_phone_settings.lua):
       "Theme" 0 dark / 1 light      "Ring"  ringtone id      "Tone" notification id
       "Accent" accent colour index  "H24" 24-hour clock   "Badge" unread badge
     fix55: vibration removed; every sound is a small mono 44.1 kHz CBR mp3. mp3 has no
     cue-point loop, so G.LoopSound restarts the sound every `len` seconds while it rings
     (len = one pass in seconds, also the length of the preview) ]]
G.THEME_DARK, G.THEME_LIGHT = 0, 1
G.RingDefault = "classic"
G.Ringtones = {
	{id = "classic", name = "Marimba", brand = "iPhone", file = "stts/phone_call_loop.mp3", len = 7.5},
	{id = "opening", name = "Opening", brand = "iPhone", file = "stts/ringtones/rt_opening.mp3", len = 24.8},
	{id = "reflection", name = "Reflection", brand = "iPhone", file = "stts/ringtones/rt_reflection.mp3", len = 16},
	{id = "oldphone", name = "Old Phone", brand = "iPhone", file = "stts/ringtones/rt_oldphone.mp3", len = 12.6},
	{id = "newadventure", name = "Your New Adventure", brand = "Pixel", file = "stts/ringtones/rt_newadventure.mp3", len = 24.8},
	{id = "bigadventure", name = "The Big Adventure", brand = "Pixel", file = "stts/ringtones/rt_bigadventure.mp3", len = 15.5},
	{id = "horizon", name = "Over the Horizon", brand = "Samsung", file = "stts/ringtones/rt_horizon.mp3", len = 24.8},
	{id = "xiaomi", name = "Mi", brand = "Xiaomi", file = "stts/ringtones/rt_xiaomi.mp3", len = 20.7},
	{id = "nokia", name = "Nokia Tune", brand = "Nokia", file = "stts/ringtones/rt_nokia.mp3", len = 15},
	{id = "lg", name = "Life's Good", brand = "LG", file = "stts/ringtones/rt_lg.mp3", len = 24.8},
	{id = "sony", name = "Xperia", brand = "Sony", file = "stts/ringtones/rt_sony.mp3", len = 11.5},
}
G.RingById = {}
for i, r in ipairs(G.Ringtones) do r.idx = i G.RingById[r.id] = r end
G.RingById.marimba = G.RingById.classic -- old profiles: the removed "Marimba" = the renamed Classic
function G.Ring(id) return G.RingById[id or ""] or G.RingById[G.RingDefault] end
for _, r in ipairs(G.Ringtones) do util.PrecacheSound(r.file) end

-- notification sounds (TeleChat messages), one-shot wavs
G.ToneDefault = "ding"
G.Tones = {
	{id = "ding", name = "Ding", file = "stts/phone_din.mp3", len = 2},
	{id = "tritone", name = "Tri-tone", file = "stts/tones/tn_tritone.mp3", len = 1.1},
	{id = "chime", name = "Chime", file = "stts/tones/tn_chime.mp3", len = 1.7},
	{id = "bell", name = "Bell", file = "stts/tones/tn_bell.mp3", len = 1.7},
	{id = "glass", name = "Glass", file = "stts/tones/tn_glass.mp3", len = 1},
	{id = "chord", name = "Chord", file = "stts/tones/tn_chord.mp3", len = 1.4},
	{id = "bamboo", name = "Bamboo", file = "stts/tones/tn_bamboo.mp3", len = 0.7},
	{id = "pulse", name = "Pulse", file = "stts/tones/tn_pulse.mp3", len = 0.4},
	{id = "pop", name = "Pop", file = "stts/tones/tn_pop.mp3", len = 0.3},
	{id = "message", name = "Message", file = "stts/phone_message.mp3", len = 0.5},
	{id = "none", name = "None"},
}
G.ToneById = {}
for i, r in ipairs(G.Tones) do r.idx = i G.ToneById[r.id] = r end
function G.Tone(id) return G.ToneById[id or ""] or G.ToneById[G.ToneDefault] end
for _, r in ipairs(G.Tones) do if r.file then util.PrecacheSound(r.file) end end

--[[ fix55: alarm sounds (Clock app). AOSP alarm/ringtone sounds (Apache 2.0, see
     ASSET_CREDITS.txt), loudness-matched, mono mp3. len = one pass, the alarm repeats it ]]
G.AlarmDefault = "radar"
G.AlarmSounds = {
	{id = "radar", name = "Radar", file = "stts/alarms/al_beep.mp3", len = 2.4},
	{id = "classic", name = "Alarm Clock", file = "stts/alarms/al_classic.mp3", len = 2.1},
	{id = "buzzer", name = "Buzzer", file = "stts/alarms/al_buzzer.mp3", len = 1.15},
	{id = "rooster", name = "Rooster", file = "stts/alarms/al_rooster.mp3", len = 1.75},
	{id = "timing", name = "Timing", file = "stts/alarms/al_timing.mp3", len = 3.95},
	{id = "awaken", name = "Awaken", file = "stts/alarms/al_awaken.mp3", len = 23.8},
	{id = "bounce", name = "Bounce", file = "stts/alarms/al_bounce.mp3", len = 14.45},
	{id = "drip", name = "Drip", file = "stts/alarms/al_drip.mp3", len = 8},
	{id = "gallop", name = "Gallop", file = "stts/alarms/al_gallop.mp3", len = 10.8},
	{id = "nudge", name = "Nudge", file = "stts/alarms/al_nudge.mp3", len = 6.4},
	{id = "orbit", name = "Orbit", file = "stts/alarms/al_orbit.mp3", len = 10.95},
	{id = "rise", name = "Rise", file = "stts/alarms/al_rise.mp3", len = 8.85},
	{id = "wag", name = "Wag", file = "stts/alarms/al_wag.mp3", len = 5.25},
	{id = "argon", name = "Argon", file = "stts/alarms/al_argon.mp3", len = 19.4},
	{id = "helium", name = "Helium", file = "stts/alarms/al_helium.mp3", len = 2.1},
	{id = "osmium", name = "Osmium", file = "stts/alarms/al_osmium.mp3", len = 6.3},
	{id = "oxygen", name = "Oxygen", file = "stts/alarms/al_oxygen.mp3", len = 10.75},
}
G.AlarmById = {}
for i, r in ipairs(G.AlarmSounds) do r.idx = i G.AlarmById[r.id] = r end
-- an alarm sound id: alarm sound, "rt:<ringtone id>" or "none"
function G.AlarmSound(id)
	id = id or ""
	if id == "none" then return nil end
	if id:sub(1, 3) == "rt:" then return G.RingById[id:sub(4)] or G.AlarmById[G.AlarmDefault] end
	return G.AlarmById[id] or G.AlarmById[G.AlarmDefault]
end
function G.AlarmSoundName(id)
	if (id or "") == "none" then return "None" end
	local r = G.AlarmSound(id)
	return r and r.name or "Radar"
end
for _, r in ipairs(G.AlarmSounds) do util.PrecacheSound(r.file) end

-- accent colours (system tint: buttons, checkmarks, switches) {dark, light}
G.Accents = {
	{name = "Blue", Color(10, 132, 255), Color(0, 122, 255)},
	{name = "Purple", Color(191, 90, 242), Color(175, 82, 222)},
	{name = "Pink", Color(255, 55, 95), Color(255, 45, 85)},
	{name = "Red", Color(255, 69, 58), Color(255, 59, 48)},
	{name = "Orange", Color(255, 159, 10), Color(255, 149, 0)},
	{name = "Yellow", Color(255, 214, 10), Color(214, 168, 0)},
	{name = "Green", Color(48, 209, 88), Color(40, 175, 75)},
	{name = "Graphite", Color(152, 152, 157), Color(110, 110, 115)},
}
-- call state on the phone entity (NW2 "CallSt")
G.CALL_NONE, G.CALL_OUT, G.CALL_IN, G.CALL_ON = 0, 1, 2, 3

-- photo limits (server enforces them, client just respects them)
G.PhotoChunk = 16000          -- bytes per net chunk
G.PhotoMaxBytes = 2097152      -- compressed photo / video page size limit (fix15: was 220000)
G.PhotoMaxPerPhone = 150       -- fix54: was 30 (the NW2 lists are split now); videos were silently refused when full
G.PhotoCooldown = 0.2         -- seconds between two photos (fix53: was 2.0)
G.SendCooldown = 3.0          -- seconds between two sends
G.SendPerMinute = 10

-- TeleChat limits (server enforces them)
G.ChatMaxLen = 300            -- characters per message
G.ChatPerThread = 50          -- messages kept per conversation
G.ChatPerPhone = 400          -- messages kept per phone
G.ChatCooldown = 0.6          -- seconds between two messages

--[[ fix23: a phone camera renders this player right now (STTS_PHONE_SELFIE): his own
     head, accessories and armor are drawn like for anybody else. ent can be the player
     OR his ragdoll (fake / car), homigrad passes either one ]]
function STTS.IsSelfie(ent)
	local s = STTS_PHONE_SELFIE
	if not s or not IsValid(s) or not IsValid(ent) then return false end
	if ent == s or ent == s.FakeRagdoll then return true end
	if hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(s) == ent then return true end
	if ent.IsRagdoll and ent:IsRagdoll() then
		if ent:GetNWEntity("ply") == s then return true end
		if hg and hg.RagdollOwner and hg.RagdollOwner(ent) == s then return true end
	end
	return false
end

-- horizontal fov of a camera with zoom
function G.ZoomFov(fov, zoom)
	zoom = math.Clamp(zoom or 1, 1, G.ZoomMax)
	if zoom <= 1.001 then return fov end
	return math.deg(2 * math.atan(math.tan(math.rad(fov) * 0.5) / zoom))
end

--[[ reference frame of a phone holder that every PC (and the server) computes
     the same way: eyes of the player (nil while he is a ragdoll / in a car).
     the camera pose of a video call travels RELATIVE to this frame, so the
     receiver rebuilds it from the body he sees right now (no lag behind the
     holder while he walks / runs / drives). ]]
function G.RefFrame(ply, fresh)
	-- fix11: ragdoll (fake) / car = NO relative frame, everything there works
	-- exactly like fix8 again (world pose only, eyes of the player)
	local ent = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or ply
	if IsValid(ent) and ent ~= ply then return end
	local ang = ply:EyeAngles()
	return ply:EyePos(), Angle(ang.p, ang.y, 0)
end

-- camera pose in world space from the phone model pose
-- fix28: wep (phone entity / its model table) picks the geometry of THAT phone model
function G.CamWorld(pos, ang, back, wep)
	local m = G.Of(wep)
	if back then return LocalToWorld(m.CamBack, m.CamBackAng, pos, ang) end
	return LocalToWorld(m.CamFront, m.CamFrontAng, pos, ang)
end

-- display frame in world space: centre, normal, up (top of the phone), right (viewer's right).
-- model +Y is the phone's LEFT edge and Angle:Right() is -Y, so the viewer's right is ang:Right().
function G.ScreenWorld(pos, ang, wep)
	local c = LocalToWorld(G.Of(wep).ScreenPos, angle_zero, pos, ang)
	return c, ang:Up(), ang:Forward(), ang:Right()
end

-- world hit point -> UI pixel (nil when outside the display)
function G.WorldToUI(hit, pos, ang, wep)
	local m = G.Of(wep)
	local l = WorldToLocal(hit, angle_zero, pos, ang)
	local x = ((-l.y) - (-m.ScreenPos.y) + m.ScreenW * 0.5) / m.ScreenW
	local y = ((m.ScreenPos.x - l.x) + m.ScreenH * 0.5) / m.ScreenH
	if x < 0 or x > 1 or y < 0 or y > 1 then return end
	return x * G.RTW, y * G.RTH
end

--[[ v19.3: internet quality of a place on the map (0 = no service .. 1 = full signal).
     the map is cut into NQ_CELL x NQ_CELL squares, every square has one spot somewhere in
     it with its own quality (no service 8 %, 1 bar 17 %, 2 / 3 / 4 bars 25 % each). a place
     takes the quality of the spots around it, the nearest one counts the most (d ^ -6: even
     zones with short soft borders). everything comes from util.CRC of the map name + the
     square (chained, so the squares do not repeat a pattern): the same on the server and on
     every client, after a rejoin, every time. nothing is sent over the net ]]
local NQ_CELL = 2048
local NQ = {map = false, spots = {}}
local function NQSpot(ix, iy)
	local key = ix .. ":" .. iy
	local s = NQ.spots[key]
	if s then return s end
	local h1 = util.CRC(NQ.map .. "|" .. key)
	local hx = util.CRC(h1 .. "x")
	local hy = util.CRC(hx .. "y")
	local r = (tonumber(util.CRC(hy .. "q")) or 0) % 100
	local tier = r < 8 and 0 or (r < 25 and 1 or (r < 50 and 2 or (r < 75 and 3 or 4)))
	local fx, fy = ((tonumber(hx) or 0) % 65536) / 65536, ((tonumber(hy) or 0) % 65536) / 65536
	s = {(ix + 0.15 + fx * 0.7) * NQ_CELL, (iy + 0.15 + fy * 0.7) * NQ_CELL, tier / 4}
	NQ.spots[key] = s
	return s
end
function G.NetQuality(pos)
	if not pos then return 1 end
	local map = game.GetMap() or ""
	if NQ.map ~= map then NQ.map, NQ.spots = map, {} end
	local ix, iy = math.floor(pos.x / NQ_CELL), math.floor(pos.y / NQ_CELL)
	local sw, sq = 0, 0
	for dx = -2, 2 do
		for dy = -2, 2 do
			local s = NQSpot(ix + dx, iy + dy)
			local d2 = ((s[1] - pos.x) ^ 2 + (s[2] - pos.y) ^ 2) / (NQ_CELL * NQ_CELL) + 1e-4
			local w = 1 / (d2 * d2 * d2)
			sw, sq = sw + w, sq + w * s[3]
		end
	end
	return sq / sw
end

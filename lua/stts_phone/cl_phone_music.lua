--[[---------------------------------------------------------------------------
	ZMusic (client) - fix54. the music app of the phone, made after Apple Music.
	* your own songs: put MP3 files into garrysmod/data/zmusic/ (a sub-folder = a
	  playlist). they are read on this PC only: title / artist / album / number /
	  year / genre / cover / lyrics from the ID3 tag, the length from the MP3 frames.
	* the phone plays OUT LOUD: everybody near the phone hears the same song at the
	  same moment, from the phone (3D, distance, walls, pocket, the phone volume).
	  the server keeps the clock and passes the song to the PCs around it
	  (sv_phone_music.lua). they keep it in data/zmusic_cache (zmusic_cache_mb).
	* tabs Home / New / Library / Search (fix61: no Radio), the mini player, Now Playing (cover,
	  scrubber, controls, volume, lyrics, Up Next with shuffle / repeat), the Control
	  Centre tile + its big player with the queue (cl_phone_shade.lua).
	console: zmusic_rescan, zmusic_volume, zmusic_hear, zmusic_cache_mb, zmusic_clearcache
---------------------------------------------------------------------------]]
STTS = STTS or {}
if not STTS.PhoneGeo then include("autorun/sh_stts_phone.lua") end
local G = STTS.PhoneGeo
local SCR = STTS.PhoneScreen or {}
STTS.PhoneScreen = SCR
local CLASS = "weapon_stts_phone"
local U = SCR.UI
if not U or not G.APP_MUSIC then return end
local C, W, H = U.C, U.W, U.H
local ZM = STTS.ZMusicC or {}
STTS.ZMusicC = ZM
local APP = G.APP_MUSIC
local LV = {[G.APP_MUSIC] = 1, [G.APP_MUSIC2] = 2, [G.APP_MUSIC3] = 3, [G.APP_MUSIC4] = 4}
local APP_OF = {G.APP_MUSIC, G.APP_MUSIC2, G.APP_MUSIC3, G.APP_MUSIC4}
local WHITE, BLACK = Color(255, 255, 255), Color(0, 0, 0)
local ACC = Color(250, 45, 72)          -- Apple Music red
local DIR, CACHE = "zmusic", "zmusic_cache"
file.CreateDir(DIR) file.CreateDir(CACHE)
if not file.Exists(DIR .. "/README.txt", "DATA") then
	file.Write(DIR .. "/README.txt", "ZMusic: put your MP3 files here (garrysmod/data/zmusic/).\nA sub-folder is a playlist. In the app: Library > ... > Rescan, or the console: zmusic_rescan\n")
end
local cvVol = CreateClientConVar("zmusic_volume", "1", true, false, "ZMusic: loudness of every phone's music on this PC (0..1)", 0, 1)
local cvHear = CreateClientConVar("zmusic_hear", "1", true, false, "ZMusic: 1 = hear the music of other phones, 0 = only your own", 0, 1)
local cvCache = CreateClientConVar("zmusic_cache_mb", "1024", true, false, "ZMusic: songs of others kept in data/zmusic_cache (MB)", 64, 16384)

local function Font(name, size, weight)
	surface.CreateFont(name, {font = "Roboto", size = size, weight = weight, antialias = true, extended = true})
end
Font("STTS_ZM_H2", 31, 700)
Font("STTS_ZM_Tab", 17, 600)
Font("STTS_ZM_NPT", 30, 700)
Font("STTS_ZM_NPA", 29, 400)
Font("STTS_ZM_Time", 18, 600)
Font("STTS_ZM_Btn", 25, 600)
Font("STTS_ZM_Row", 27, 400)
Font("STTS_ZM_RowS", 22, 400)
Font("STTS_ZM_Card", 22, 600)
Font("STTS_ZM_Mini", 24, 600)
Font("STTS_ZM_Big", 38, 800)
Font("STTS_ZM_Hdr", 20, 600)
Font("STTS_ZM_AlbT", 31, 700)
Font("STTS_ZM_AlbA", 29, 400)
Font("STTS_ZM_Lyr", 33, 800)
Font("STTS_ZM_Num", 24, 400)

local function M(n) return Material("stts/zm_" .. n .. ".png", "smooth mips") end
local I = {
	play = M("play_fill"), pause = M("pause_fill"), fwd = M("forward_fill"), back = M("backward_fill"),
	shuffle = M("shuffle"), rep = M("repeat"), rep1 = M("repeat_1"), note = M("music_note"), notes = M("music_note_list"),
	albums = M("music_albums_fill"), mic = M("music_mic"), house = M("house_fill"), grid = M("square_grid_2x2_fill"),
	stack = M("square_stack_fill"), search = M("search"), star = M("star_fill"),
	staro = M("star"), dots = M("ellipsis"), chevr = M("chevron_right"), chevd = M("chevron_down"), spk = M("speaker_fill"),
	spk3 = M("speaker_3_fill"), quote = M("quote_bubble"), list = M("list_bullet"), inf = M("infinite"), person = M("person_fill"),
	xc = M("xmark_circle_fill"), plus = M("plus"), check = M("checkmark"), nextup = M("text_insert"), last = M("text_append"),
	playc = M("play_circle_fill"), note2 = M("music_note_2"), heart = M("heart_fill"),
}
ZM.I = I
local appIcon = Material("stts/ios_music.png", "smooth mips")

--[[---------------------------------------------------------------------------
	text helpers: ID3 encodings (Latin-1 / Windows-1251 / UTF-16 / UTF-8), lower case
---------------------------------------------------------------------------]]
local band, rshift = bit.band, bit.rshift
local function BE(s, i, n) local v = 0 for k = 0, n - 1 do v = v * 256 + (string.byte(s, i + k) or 0) end return v end
local function SS(s, i) local v = 0 for k = 0, 3 do v = v * 128 + band(string.byte(s, i + k) or 0, 127) end return v end
local CP1251 = {0x402, 0x403, 0x201A, 0x453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x409, 0x2039, 0x40A, 0x40C, 0x40B, 0x40F,
	0x452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x3F, 0x2122, 0x459, 0x203A, 0x45A, 0x45C, 0x45B, 0x45F,
	0xA0, 0x40E, 0x45E, 0x408, 0xA4, 0x490, 0xA6, 0xA7, 0x401, 0xA9, 0x404, 0xAB, 0xAC, 0xAD, 0xAE, 0x407,
	0xB0, 0xB1, 0x406, 0x456, 0x491, 0xB5, 0xB6, 0xB7, 0x451, 0x2116, 0x454, 0xBB, 0x458, 0x405, 0x455, 0x457}
-- ID3 "Latin-1": Russian taggers wrote Windows-1251 there (mostly bytes 0xC0..0xFF = Cyrillic)
local function Latin(s)
	if not string.find(s, "[\128-\255]") then return s end
	if utf8.len(s) then return s end -- UTF-8 already (some taggers do that)
	local hi, cyr = 0, 0
	for i = 1, #s do local b = string.byte(s, i) if b >= 128 then hi = hi + 1 if b >= 192 then cyr = cyr + 1 end end end
	local ru = cyr >= hi * 0.6
	local out = {}
	for i = 1, #s do
		local b = string.byte(s, i)
		if b < 128 then out[#out + 1] = string.char(b)
		elseif ru then out[#out + 1] = utf8.char(b >= 192 and 0x410 + b - 192 or CP1251[b - 127])
		else out[#out + 1] = utf8.char(b) end
	end
	return table.concat(out)
end
local function U16(s, be)
	local out, i, n = {}, 1, #s
	while i + 1 <= n do
		local a, b = string.byte(s, i, i + 1)
		local c = be and a * 256 + b or b * 256 + a
		i = i + 2
		if c >= 0xD800 and c <= 0xDBFF and i + 1 <= n then
			local a2, b2 = string.byte(s, i, i + 1)
			local d = be and a2 * 256 + b2 or b2 * 256 + a2
			if d >= 0xDC00 and d <= 0xDFFF then c = 0x10000 + (c - 0xD800) * 1024 + (d - 0xDC00) i = i + 2 end
		end
		if c == 0 then break end
		if c ~= 0xFEFF and c ~= 0xFFFE then out[#out + 1] = utf8.char(c) end
	end
	return table.concat(out)
end
local function Text(enc, s)
	if enc == 1 then
		local a, b = string.byte(s, 1, 2)
		if a == 0xFE and b == 0xFF then return U16(string.sub(s, 3), true) end
		if a == 0xFF and b == 0xFE then return U16(string.sub(s, 3), false) end
		return U16(s, false)
	elseif enc == 2 then return U16(s, true)
	elseif enc == 3 then return (string.gsub(s, "%z.*$", "")) end
	return Latin((string.gsub(s, "%z.*$", "")))
end
-- lower case for sorting / search: ASCII + Cyrillic
local function Low(s)
	s = string.lower(s or "")
	s = string.gsub(s, "\208([\144-\159])", function(c) return "\208" .. string.char(string.byte(c) + 32) end)
	s = string.gsub(s, "\208([\160-\175])", function(c) return "\209" .. string.char(string.byte(c) - 32) end)
	s = string.gsub(s, "\208\129", "\209\145")
	return s
end
ZM.Low = Low
local function Dur(sec)
	sec = math.max(0, math.floor((sec or 0) + 0.5))
	if sec >= 3600 then return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60) end
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
ZM.Dur = Dur
local GENRES = string.Explode("|", "Blues|Classic Rock|Country|Dance|Disco|Funk|Grunge|Hip-Hop|Jazz|Metal|New Age|Oldies|Other|Pop|R&B|Rap|Reggae|Rock|Techno|Industrial|Alternative|Ska|Death Metal|Pranks|Soundtrack|Euro-Techno|Ambient|Trip-Hop|Vocal|Jazz+Funk|Fusion|Trance|Classical|Instrumental|Acid|House|Game|Sound Clip|Gospel|Noise|Alternative Rock|Bass|Soul|Punk|Space|Meditative|Instrumental Pop|Instrumental Rock|Ethnic|Gothic|Darkwave|Techno-Industrial|Electronic|Pop-Folk|Eurodance|Dream|Southern Rock|Comedy|Cult|Gangsta|Top 40|Christian Rap|Pop/Funk|Jungle|Native American|Cabaret|New Wave|Psychedelic|Rave|Showtunes|Trailer|Lo-Fi|Tribal|Acid Punk|Acid Jazz|Polka|Retro|Musical|Rock & Roll|Hard Rock")
local function Genre(g)
	if not g then return end
	local n = tonumber(string.match(g, "^%((%d+)%)") or string.match(g, "^(%d+)$"))
	if n then return GENRES[n + 1] end
	return (string.gsub(g, "^%(%d+%)", ""))
end

--[[---------------------------------------------------------------------------
	MP3: ID3v2 (2.2 / 2.3 / 2.4) + ID3v1, the length from the first frame (Xing / VBRI / CBR)
---------------------------------------------------------------------------]]
local FRAMES = {TIT2 = "title", TT2 = "title", TPE1 = "artist", TP1 = "artist", TALB = "album", TAL = "album",
	TPE2 = "aartist", TP2 = "aartist", TRCK = "track", TRK = "track", TPOS = "disc", TPA = "disc",
	TYER = "year", TYE = "year", TDRC = "year", TCON = "genre", TCO = "genre", APIC = "pic", PIC = "pic", USLT = "lyr", ULT = "lyr",
	TXXX = "txxx", TXX = "txxx"}
-- lyrics some taggers (and ffmpeg) put into a user text frame instead of USLT
local LYR_DESC = {LYRICS = true, UNSYNCEDLYRICS = true, ["UNSYNCED LYRICS"] = true, USLT = true}
local function SkipDesc(data, enc, p)
	if enc == 1 or enc == 2 then
		local q = p
		while q + 1 <= #data do
			if string.byte(data, q) == 0 and string.byte(data, q + 1) == 0 then break end
			q = q + 2
		end
		return q + 2
	end
	local z = string.find(data, "\0", p, true)
	return z and z + 1
end
local function Picture(id, data, out)
	if out.picType == 3 then return end
	local enc = string.byte(data, 1)
	local p, ptype
	if id == "PIC" then ptype, p = string.byte(data, 5), 6
	else
		local z = string.find(data, "\0", 2, true)
		if not z then return end
		ptype, p = string.byte(data, z + 1), z + 2
	end
	p = SkipDesc(data, enc, p)
	if not p then return end
	local img = string.sub(data, p)
	if #img < 64 or (string.sub(img, 1, 2) ~= "\255\216" and string.sub(img, 1, 4) ~= "\137PNG") then return end
	if out.pic and ptype ~= 3 then return end
	out.pic, out.picType = img, ptype
end
local function Lyrics(data, out)
	if out.lyr then return end
	local enc = string.byte(data, 1)
	local p = SkipDesc(data, enc, 5) -- encoding, language (3)
	if not p then return end
	local s = string.Trim(Text(enc, string.sub(data, p)))
	if #s > 3 then out.lyr = string.sub(s, 1, 20000) end
end
local function UserText(data, out)
	if out.lyr then return end
	local enc = string.byte(data, 1)
	local p = SkipDesc(data, enc, 2)
	if not p or p > #data then return end
	local desc = string.upper(string.Trim(Text(enc, string.sub(data, 2, p - 1))))
	if not LYR_DESC[desc] then return end
	local s = string.Trim(Text(enc, string.sub(data, p)))
	if #s > 3 then out.lyr = string.sub(s, 1, 20000) end
end
local function ParseID3(tag, ver, out)
	local i, n = 1, #tag
	local idLen, hdr = ver == 2 and 3 or 4, ver == 2 and 6 or 10
	while i + hdr - 1 <= n do
		local id = string.sub(tag, i, i + idLen - 1)
		if not string.find(id, "^[A-Z0-9]+$") then break end
		local size = ver == 2 and BE(tag, i + 3, 3) or (ver == 4 and SS(tag, i + 4) or BE(tag, i + 4, 4))
		local flags = ver == 2 and 0 or BE(tag, i + 8, 2)
		local d0 = i + hdr
		if size <= 0 or d0 + size - 1 > n then break end
		local data = string.sub(tag, d0, d0 + size - 1)
		i = d0 + size
		if ver == 4 then
			if band(flags, 1) ~= 0 then data = string.sub(data, 5) end -- data length indicator
			if band(flags, 2) ~= 0 then data = string.gsub(data, "\255%z", "\255") end -- unsynchronisation
		elseif ver == 3 then
			if band(flags, 0xC0) ~= 0 then data = nil -- compressed / encrypted
			elseif band(flags, 0x20) ~= 0 then data = string.sub(data, 2) end -- group id
		end
		local k = FRAMES[id]
		if data and #data > 1 and k then
			if k == "pic" then Picture(id, data, out)
			elseif k == "lyr" then Lyrics(data, out)
			elseif k == "txxx" then UserText(data, out)
			elseif not out[k] then
				local v = string.Trim(Text(string.byte(data, 1), string.sub(data, 2)))
				if v ~= "" then out[k] = v end
			end
		end
	end
end
local BR1 = {32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320}
local BR2 = {8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160}
local SRATE = {[3] = {44100, 48000, 32000}, [2] = {22050, 24000, 16000}, [0] = {11025, 12000, 8000}}
local function Mp3Dur(buf, audioBytes)
	for i = 1, math.min(#buf - 4, 12000) do
		local a, b, c, d = string.byte(buf, i, i + 3)
		if a == 255 and band(b, 0xE0) == 0xE0 then
			local ver, layer = band(rshift(b, 3), 3), band(rshift(b, 1), 3)
			local bri, sri = rshift(c, 4), band(rshift(c, 2), 3)
			if ver ~= 1 and layer == 1 and bri > 0 and bri < 15 and sri < 3 then
				local sr = SRATE[ver][sri + 1]
				local mono = rshift(d, 6) == 3
				local spf = ver == 3 and 1152 or 576
				local x = i + 4 + (ver == 3 and (mono and 17 or 32) or (mono and 9 or 17))
				local tag = string.sub(buf, x, x + 3)
				if tag == "Xing" or tag == "Info" then
					if band(BE(buf, x + 4, 4), 1) ~= 0 then
						local frames = BE(buf, x + 8, 4)
						if frames > 0 then return frames * spf / sr end
					end
				end
				if string.sub(buf, i + 36, i + 39) == "VBRI" then
					local frames = BE(buf, i + 50, 4)
					if frames > 0 then return frames * spf / sr end
				end
				return math.max(0, audioBytes - (i - 1)) * 8 / ((ver == 3 and BR1 or BR2)[bri] * 1000)
			end
		end
	end
end
-- everything about one file (the key = what the server checks: CRC of 64 KB + 16 KB, size)
local function ReadMeta(path, size, ext)
	local f = file.Open(path, "rb", "DATA")
	if not f then return end
	local m, audio0, v1 = {}, 0, 0
	if ext == "mp3" then
		local head = f:Read(10) or ""
		if #head == 10 and string.sub(head, 1, 3) == "ID3" then
			local ver, flags = string.byte(head, 4), string.byte(head, 6)
			local tsize = SS(head, 7)
			audio0 = 10 + tsize + (band(flags, 0x10) ~= 0 and 10 or 0)
			if ver >= 2 and ver <= 4 and tsize > 0 then
				local tag = f:Read(math.min(tsize, 12 * 1048576)) or ""
				if ver < 4 and band(flags, 0x80) ~= 0 then tag = string.gsub(tag, "\255%z", "\255") end
				if ver >= 3 and band(flags, 0x40) ~= 0 then tag = string.sub(tag, (ver == 4 and SS(tag, 1) or BE(tag, 1, 4) + 4) + 1) end
				pcall(ParseID3, tag, ver, m)
			end
		end
		if size > 128 then
			f:Seek(size - 128)
			local t = f:Read(128) or ""
			if string.sub(t, 1, 3) == "TAG" then
				v1 = 128
				local function S(a, b) return string.Trim(Latin((string.gsub(string.sub(t, a, b), "%z.*$", "")))) end
				local fill = {title = S(4, 33), artist = S(34, 63), album = S(64, 93), year = S(94, 97)}
				for k, v in pairs(fill) do if not m[k] and v ~= "" then m[k] = v end end
			end
		end
		f:Seek(math.min(audio0, size))
		local buf = f:Read(math.min(16384, math.max(1, size - audio0))) or ""
		m.dur = Mp3Dur(buf, size - audio0 - v1) or 0
	end
	f:Seek(0)
	local a = f:Read(math.min(size, 65536)) or ""
	local b = ""
	if size > 65536 then f:Seek(size - 16384) b = f:Read(16384) or "" end
	f:Close()
	m.key = util.CRC(a .. b) .. "_" .. size
	m.dur = m.dur or 0
	return m
end
ZM.ReadMeta = ReadMeta

--[[---------------------------------------------------------------------------
	the library: data/zmusic/ (+ sub-folders = playlists). read in the background
	(a coroutine, a few ms a frame), the tags are kept in zmusic_cache/index.json
	(by path + size + time, so a rescan only reads new / changed files)
---------------------------------------------------------------------------]]
local EXT = {mp3 = true, ogg = true, wav = true}
ZM.lib = ZM.lib or {songs = {}, byKey = {}, albums = {}, artists = {}, playlists = {}, genres = {}, recent = {}, ready = false}
ZM.prefs = ZM.prefs or {fav = {}, recent = {}}
do
	local raw = file.Read(CACHE .. "/prefs.json", "DATA")
	local t = raw and util.JSONToTable(raw)
	if istable(t) then ZM.prefs.fav = istable(t.fav) and t.fav or {} ZM.prefs.recent = istable(t.recent) and t.recent or {} end
end
function ZM.SavePrefs()
	file.Write(CACHE .. "/prefs.json", util.TableToJSON({fav = ZM.prefs.fav, recent = ZM.prefs.recent}))
end
function ZM.IsFav(key) return key and ZM.prefs.fav[key] == true end
function ZM.ToggleFav(key)
	if not key or key == "" then return end
	ZM.prefs.fav[key] = (not ZM.IsFav(key)) or nil
	ZM.SavePrefs()
	ZM.lib.favDirty = true
end
-- recently played (albums / playlists / songs: "a:<id>" "p:<name>" "s:<key>")
function ZM.Played(tag)
	local r = ZM.prefs.recent
	for i = #r, 1, -1 do if r[i] == tag then table.remove(r, i) end end
	table.insert(r, 1, tag)
	while #r > 24 do table.remove(r) end
	ZM.SavePrefs()
end

-- "01 - Artist - Title.mp3" -> artist, title
local function FromName(name)
	name = string.gsub(name, "%.[^%.]+$", "")
	name = string.gsub(name, "_", " ")
	name = string.gsub(name, "^%d+%s*[%.%-]%s*", "")
	local a, t = string.match(name, "^(.-)%s+[%-–]%s+(.+)$")
	if a and t and a ~= "" and t ~= "" then return t, a end
	return name
end

local function SongOf(path, e, pl, fname)
	local s = {path = path, key = e.key, size = e.s, added = e.t or 0, pl = pl, art = e.art, lyr = e.lyr, dur = e.dur or 0}
	local ft, fa = FromName(fname)
	s.title = (e.title and e.title ~= "") and e.title or ft
	s.artist = (e.artist and e.artist ~= "") and e.artist or fa or "Unknown Artist"
	s.aartist = (e.aartist and e.aartist ~= "") and e.aartist or s.artist
	s.album = (e.album and e.album ~= "") and e.album or (s.title .. " - Single")
	s.track = tonumber(string.match(e.track or "", "^%d+")) or 0
	s.disc = tonumber(string.match(e.disc or "", "^%d+")) or 1
	s.year = tonumber(string.match(e.year or "", "%d%d%d%d")) or nil
	s.genre = Genre(e.genre)
	s.low = Low(s.title .. " " .. s.artist .. " " .. s.album)
	s.ascii = not string.find(path, "[\128-\255]")
	return s
end

-- albums / artists / playlists / genres from the songs
local function Build(songs)
	local lib = {songs = songs, byKey = {}, albums = {}, artists = {}, playlists = {}, genres = {}, recent = {}, ready = true, at = RealTime()}
	table.sort(songs, function(a, b) local x, y = Low(a.title), Low(b.title) if x ~= y then return x < y end return a.path < b.path end)
	local albums, artists, pls, genres = {}, {}, {}, {}
	for _, s in ipairs(songs) do
		if not lib.byKey[s.key] then lib.byKey[s.key] = s end
		local ak = Low(s.album) .. "\1" .. Low(s.aartist)
		local al = albums[ak]
		if not al then
			al = {name = s.album, artist = s.aartist, songs = {}, art = s.art, year = s.year, genre = s.genre, added = 0, id = util.CRC(ak)}
			albums[ak] = al
			lib.albums[#lib.albums + 1] = al
		end
		al.songs[#al.songs + 1] = s
		al.art = al.art or s.art
		al.year = al.year or s.year
		al.genre = al.genre or s.genre
		al.added = math.max(al.added, s.added)
		s.alb = al
		local rk = Low(s.aartist)
		local ar = artists[rk]
		if not ar then
			ar = {name = s.aartist, songs = {}, albums = {}, art = s.art, id = util.CRC(rk), seen = {}}
			artists[rk] = ar
			lib.artists[#lib.artists + 1] = ar
		end
		ar.songs[#ar.songs + 1] = s
		ar.art = ar.art or s.art
		if not ar.seen[al] then ar.seen[al] = true ar.albums[#ar.albums + 1] = al end
		if s.pl then
			local p = pls[s.pl]
			if not p then p = {name = s.pl, songs = {}, id = util.CRC(s.pl)} pls[s.pl] = p lib.playlists[#lib.playlists + 1] = p end
			p.songs[#p.songs + 1] = s
		end
		if s.genre and s.genre ~= "" then
			local gk = Low(s.genre)
			local g = genres[gk]
			if not g then g = {name = s.genre, songs = {}, id = util.CRC(gk)} genres[gk] = g lib.genres[#lib.genres + 1] = g end
			g.songs[#g.songs + 1] = s
		end
	end
	for _, al in ipairs(lib.albums) do
		table.sort(al.songs, function(a, b)
			if a.disc ~= b.disc then return a.disc < b.disc end
			if a.track ~= b.track then return a.track < b.track end
			return Low(a.title) < Low(b.title)
		end)
		local d = 0
		for _, s in ipairs(al.songs) do d = d + (s.dur or 0) end
		al.dur, al.low = d, Low(al.name .. " " .. al.artist)
	end
	for _, p in ipairs(lib.playlists) do
		table.sort(p.songs, function(a, b) return a.path < b.path end)
		for _, s in ipairs(p.songs) do if s.art then p.art = p.art or {} if #p.art < 4 and not table.HasValue(p.art, s.art) then p.art[#p.art + 1] = s.art end end end
	end
	for _, ar in ipairs(lib.artists) do
		ar.seen, ar.low = nil, Low(ar.name)
		table.sort(ar.albums, function(a, b) return (a.year or 0) > (b.year or 0) end)
	end
	table.sort(lib.albums, function(a, b) return a.low < b.low end)
	table.sort(lib.artists, function(a, b) return a.low < b.low end)
	table.sort(lib.playlists, function(a, b) return Low(a.name) < Low(b.name) end)
	table.sort(lib.genres, function(a, b) return #a.songs > #b.songs end)
	for i, al in ipairs(lib.albums) do lib.recent[i] = al end
	table.sort(lib.recent, function(a, b) if a.added ~= b.added then return a.added > b.added end return a.low < b.low end)
	lib.byAlbum, lib.byArtist, lib.byPl, lib.byGenre = {}, {}, {}, {}
	for _, al in ipairs(lib.albums) do lib.byAlbum[al.id] = al end
	for _, ar in ipairs(lib.artists) do lib.byArtist[ar.id] = ar end
	for _, p in ipairs(lib.playlists) do lib.byPl[p.id] = p end
	for _, g in ipairs(lib.genres) do lib.byGenre[g.id] = g end
	return lib
end
ZM.Build = Build
function ZM.FavSongs()
	local lib = ZM.lib
	if lib.favList and not lib.favDirty then return lib.favList end
	local out = {}
	for _, s in ipairs(lib.songs) do if ZM.IsFav(s.key) then out[#out + 1] = s end end
	lib.favList, lib.favDirty = out, false
	return out
end

-- the scan (a coroutine): list the files, read the new ones, build
local scanCo
local function Scan()
	local raw = file.Read(CACHE .. "/index.json", "DATA")
	local old = raw and util.JSONToTable(raw) or {}
	old = istable(old.files) and old.files or {}
	local found, n = {}, 0
	local function Walk(dir, pl, depth)
		local files, dirs = file.Find(dir .. "/*", "DATA")
		for _, f in ipairs(files or {}) do
			local ext = string.lower(string.match(f, "%.([^%.]+)$") or "")
			if EXT[ext] and n < 5000 then n = n + 1 found[#found + 1] = {path = dir .. "/" .. f, pl = pl, name = f, ext = ext} end
		end
		if depth < 3 then
			for _, d in ipairs(dirs or {}) do Walk(dir .. "/" .. d, pl and (pl .. " / " .. d) or d, depth + 1) coroutine.yield() end
		end
	end
	Walk(DIR, nil, 0)
	ZM.scanTotal, ZM.scanDone = #found, 0
	do -- fix55: what this scan saw (the folder watcher compares against it)
		local names, set = {}, {}
		for i, f in ipairs(found) do names[i] = f.path set[f.path] = true end
		ZM.scanSig, ZM.scanSet = util.CRC(table.concat(names, "\n")), set
	end
	local idx, songs = {}, {}
	local t0 = SysTime()
	for i, f in ipairs(found) do
		local size, time = file.Size(f.path, "DATA") or 0, file.Time(f.path, "DATA") or 0
		local e = old[f.path]
		if not (istable(e) and e.s == size and e.t == time and e.key) and size >= 1024 then
			local m = ReadMeta(f.path, size, f.ext)
			if m then
				e = {s = size, t = time, key = m.key, title = m.title, artist = m.artist, album = m.album, aartist = m.aartist,
					track = m.track, disc = m.disc, year = m.year, genre = m.genre, dur = m.dur}
				if m.pic then
					local id = util.CRC(m.pic) .. "_" .. #m.pic
					local ext = string.sub(m.pic, 1, 4) == "\137PNG" and "png" or "jpg"
					local rp = CACHE .. "/r_" .. id .. "." .. ext
					if not file.Exists(rp, "DATA") then file.Write(rp, m.pic) end
					e.art, e.artExt = id, ext
				end
				if m.lyr then file.Write(CACHE .. "/l_" .. m.key .. ".txt", m.lyr) e.lyr = true end
			else e = nil end
			if SysTime() - t0 > 0.004 then coroutine.yield() t0 = SysTime() end
		end
		if e then
			idx[f.path] = e
			songs[#songs + 1] = SongOf(f.path, e, f.pl, f.name)
		end
		ZM.scanDone = i
		if i % 40 == 0 and SysTime() - t0 > 0.004 then coroutine.yield() t0 = SysTime() end
	end
	file.Write(CACHE .. "/index.json", util.TableToJSON({v = 1, files = idx}))
	ZM.lib = Build(songs)
	ZM.lib.favDirty = true
	ZM.MeasureQ = {}
	for _, s in ipairs(songs) do if (s.dur or 0) <= 0 then ZM.MeasureQ[#ZM.MeasureQ + 1] = s end end
end
function ZM.Rescan()
	if scanCo then return end
	ZM.scanning = true
	scanCo = coroutine.create(Scan)
end
hook.Add("Think", "STTS_ZMusicScan", function()
	if not scanCo then return end
	local ok, err = coroutine.resume(scanCo)
	if not ok then ErrorNoHalt("ZMusic scan: " .. tostring(err) .. "\n") end
	if not ok or coroutine.status(scanCo) == "dead" then
		scanCo, ZM.scanning = nil, false
		-- fix55: songs that appeared by themselves (the folder watcher): a short toast
		local was = ZM.watchWas
		ZM.watchWas = nil
		if ok and was and ZM.lib and ZM.lib.songs then
			local d = #ZM.lib.songs - was
			if d > 0 and ZM.Toast then ZM.Toast(d == 1 and "1 new song" or (d .. " new songs")) end
		end
	end
end)
--[[ fix55: music dropped into garrysmod/data/zmusic/ shows up by itself (no zmusic_rescan,
     no reconnect): the folder is listed every 1.5 s while ZMusic is open (every 4 s
     otherwise); a change starts a scan as soon as the new files stopped growing (a
     song still being copied is not read half-written) ]]
do
	local function List()
		local out, n = {}, 0
		local function Walk(dir, depth)
			local files, dirs = file.Find(dir .. "/*", "DATA")
			for _, f in ipairs(files or {}) do
				local ext = string.lower(string.match(f, "%.([^%.]+)$") or "")
				if EXT[ext] and n < 5000 then n = n + 1 out[n] = dir .. "/" .. f end
			end
			if depth < 3 then for _, d in ipairs(dirs or {}) do Walk(dir .. "/" .. d, depth + 1) end end
		end
		Walk(DIR, 0)
		return out
	end
	local pend, nextAt = nil, RealTime() + 5
	local function MusicOpen()
		local L = SCR.L
		return L and L.raised and LV[L.app] ~= nil
	end
	hook.Add("Think", "STTS_ZMusicWatch55", function()
		local now = RealTime()
		if now < nextAt then return end
		nextAt = now + (MusicOpen() and 1.5 or 4)
		if scanCo then return end
		if not ZM.scanSig then ZM.Rescan() return end -- (lua refresh) no scan of this session yet
		local list = List()
		local sig = util.CRC(table.concat(list, "\n"))
		if sig == ZM.scanSig then pend = nil return end
		-- the sizes of the new files: equal twice in a row = copied completely
		local sizes, set = {}, ZM.scanSet or {}
		for _, path in ipairs(list) do
			if not set[path] then sizes[path] = file.Size(path, "DATA") or -1 end
		end
		local stable = pend and pend.sig == sig
		if stable then
			for path, sz in pairs(sizes) do
				if sz <= 0 or pend.sizes[path] ~= sz then stable = false break end
			end
		end
		if stable then
			pend = nil
			ZM.watchWas = ZM.lib and ZM.lib.songs and #ZM.lib.songs or 0
			ZM.Rescan()
		else
			pend = {sig = sig, sizes = sizes}
		end
	end)
end
concommand.Add("zmusic_rescan", function() ZM.Rescan() print("ZMusic: scanning garrysmod/data/" .. DIR .. "/ ...") end)
timer.Simple(2, function() if not ZM.lib.ready then ZM.Rescan() end end)

-- songs without a length (ogg / wav, odd MP3): the length from the audio engine, one by one
local measuring
timer.Create("STTS_ZMusicMeasure", 0.5, 0, function()
	local q = ZM.MeasureQ
	if measuring or not q or #q == 0 then return end
	local s = table.remove(q, 1)
	if not s.ascii then return end
	measuring = true
	sound.PlayFile("data/" .. s.path, "noplay noblock", function(ch)
		measuring = false
		if not IsValid(ch) then return end
		local len = ch:GetLength()
		ch:Stop()
		if len and len > 0 then
			s.dur = len
			if s.alb then local d = 0 for _, x in ipairs(s.alb.songs) do d = d + (x.dur or 0) end s.alb.dur = d end
		end
	end)
end)

--[[---------------------------------------------------------------------------
	artwork: the cover of a file (r_<id>) becomes a 384 px jpg (a_<id>) in PostRender,
	covers of other players' songs come from the server (k_<key>)
---------------------------------------------------------------------------]]
local mats, thumbQ, thumbWant = {}, {}, {}
local function Mat(path)
	local m = mats[path]
	if m == nil then
		m = file.Exists(path, "DATA") and Material("../data/" .. path, "smooth mips") or false
		if m and m:IsError() then m = false end
		mats[path] = m
	end
	return m or nil
end
ZM.Mat = Mat
function ZM.ArtMat(id)
	if not id then return end
	local p = CACHE .. "/a_" .. id .. ".jpg"
	local m = mats[p]
	if m ~= nil then return m or nil end
	if file.Exists(p, "DATA") then return Mat(p) end
	mats[p] = false
	if not thumbWant[id] then thumbWant[id] = true thumbQ[#thumbQ + 1] = id end
end
local artMiss = {}
-- the cover of a song by its key (yours: from the library, others: what the server sent)
function ZM.KeyArt(key)
	if not key or key == "" then return end
	local s = ZM.lib.byKey[key]
	if s then return ZM.ArtMat(s.art), s.art end
	local p = CACHE .. "/k_" .. key .. ".jpg"
	local m = mats[p]
	if m then return m end
	if (artMiss[key] or 0) > RealTime() then return end
	if file.Exists(p, "DATA") then mats[p] = nil return Mat(p) end
	artMiss[key] = RealTime() + 3
	if ZM.AskArt then ZM.AskArt(key) end
end
function ZM.ArtArrived(key) artMiss[key] = nil mats[CACHE .. "/k_" .. key .. ".jpg"] = nil end
local thumbRT
hook.Add("PostRender", "STTS_ZMusicThumbs", function()
	if SCR.InRV or #thumbQ == 0 then return end
	local id = table.remove(thumbQ, 1)
	local src
	for _, ext in ipairs({"jpg", "png"}) do
		local p = CACHE .. "/r_" .. id .. "." .. ext
		if file.Exists(p, "DATA") then src = Material("../data/" .. p, "smooth mips") break end
	end
	if not src or src:IsError() then return end
	thumbRT = thumbRT or GetRenderTargetEx("stts_zm_thumb384", 384, 384, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGB888)
	local w, h = math.max(1, src:Width()), math.max(1, src:Height())
	local u0, v0, u1, v1 = 0, 0, 1, 1
	if w > h then local k = h / w u0, u1 = (1 - k) / 2, (1 + k) / 2 elseif h > w then local k = w / h v0, v1 = (1 - k) / 2, (1 + k) / 2 end
	local jpg
	render.PushRenderTarget(thumbRT)
		render.Clear(0, 0, 0, 255)
		cam.Start2D()
			surface.SetMaterial(src) surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRectUV(0, 0, 384, 384, u0, v0, u1, v1)
		cam.End2D()
		jpg = render.Capture({format = "jpg", quality = 86, x = 0, y = 0, w = 384, h = 384, alpha = false})
		if jpg and #jpg > 60000 then jpg = render.Capture({format = "jpg", quality = 66, x = 0, y = 0, w = 384, h = 384, alpha = false}) end
	render.PopRenderTarget()
	if jpg and #jpg > 100 then
		file.Write(CACHE .. "/a_" .. id .. ".jpg", jpg)
		mats[CACHE .. "/a_" .. id .. ".jpg"] = nil
	end
end)

-- a few colours of a cover (the Now Playing background is a soft gradient of them)
local palettes = {}
function ZM.Palette(mat, tag)
	if not mat then return end
	local p = palettes[tag or mat]
	if p then return p end
	p = {}
	local ok = pcall(function()
		local w, h = math.max(1, mat:Width()), math.max(1, mat:Height())
		for j = 0, 2 do
			for i = 0, 2 do
				local r, g, b, n = 0, 0, 0, 0
				for dj = 0, 1 do for di = 0, 1 do
					local c = mat:GetColor(math.floor(w * (i + 0.25 + di * 0.5) / 3), math.floor(h * (j + 0.25 + dj * 0.5) / 3))
					if c then r, g, b, n = r + c.r, g + c.g, b + c.b, n + 1 end
				end end
				n = math.max(n, 1)
				p[j * 3 + i + 1] = Color(r / n, g / n, b / n)
			end
		end
	end)
	if not ok or #p < 9 then p = false end
	palettes[tag or mat] = p
	return p or nil
end

--[[---------------------------------------------------------------------------
	net: the queue of a phone, the controls, the songs up (yours) / down (others')
---------------------------------------------------------------------------]]
local ACT = {PLAY = 1, SEEK = 2, NEXT = 3, PREV = 4, JUMP = 5, SHUF = 6, REP = 7, NEXTUP = 8, LAST = 9, STOP = 10}
ZM.ACT = ACT
ZM.queues = ZM.queues or {}
ZM.pred = ZM.pred or {}
local function Toast(s) local L = SCR.L if L then L.toast, L.toastAt = s, RealTime() end end
ZM.Toast = Toast
local function TrackMax() return G.ZMTrackMax and G.ZMTrackMax() or 40 * 1048576 end
local function WriteItem(s)
	net.WriteString(s.key) net.WriteUInt(s.size, 32)
	net.WriteUInt(math.Clamp(math.floor((s.dur or 0) * 10), 0, 2 ^ 24 - 1), 24)
	net.WriteString(s.title or "") net.WriteString(s.artist or "") net.WriteString(s.album or "")
end
-- a list was tapped: it becomes the queue of the phone (300 songs at most, around the tapped one)
function ZM.PlayList(wep, list, start, shuffle, tag)
	if not IsValid(wep) or not list or #list == 0 then return end
	start = math.Clamp(start or 1, 1, #list)
	local from = 1
	if #list > 300 then from = math.Clamp(start - 60, 1, #list - 299) end
	local items, st, max = {}, nil, TrackMax()
	for i = from, math.min(#list, from + 299) do
		local s = list[i]
		if s.size <= max then
			items[#items + 1] = s
			if i == start then st = #items end
		end
	end
	if #items == 0 then Toast("Song too big") return end
	st = st or 1
	if shuffle then st = math.random(#items) end
	net.Start("stts_zm_q")
		net.WriteEntity(wep)
		net.WriteUInt(#items, 10)
		for _, s in ipairs(items) do WriteItem(s) end
		net.WriteUInt(st, 10)
		net.WriteBool(shuffle == true)
	net.SendToServer()
	ZM.pred[wep] = {at = RealTime(), nwAt = wep:GetNW2Float("ZMAt", 0), key = items[st].key, s = items[st], on = true, pos = 0, ct = CurTime(), shuf = shuffle == true}
	if tag then ZM.Played(tag) end
end
function ZM.Act(wep, act, a)
	if not IsValid(wep) then return end
	net.Start("stts_zm_act")
		net.WriteEntity(wep)
		net.WriteUInt(act, 4)
		if act == ACT.PLAY or act == ACT.SHUF then net.WriteBool(a == true)
		elseif act == ACT.SEEK then net.WriteUInt(math.Clamp(math.floor((a or 0) * 10), 0, 2 ^ 24 - 1), 24)
		elseif act == ACT.JUMP then net.WriteUInt(math.Clamp(a or 1, 0, 1023), 10)
		elseif act == ACT.REP then net.WriteUInt(math.Clamp(a or 0, 0, 2), 2)
		elseif act == ACT.NEXTUP or act == ACT.LAST then WriteItem(a) end
	net.SendToServer()
	-- what the screen shows until the server answers
	local n = ZM.Now(wep)
	local p = {at = RealTime(), nwAt = wep:GetNW2Float("ZMAt", 0), ct = CurTime()}
	if act == ACT.PLAY then
		p.on = a == true
		p.pos = (p.on and n.dur > 0 and n.pos >= n.dur - 0.2) and 0 or n.pos
	elseif act == ACT.SEEK then p.on, p.pos = n.on, a
	elseif act == ACT.NEXT or act == ACT.PREV or act == ACT.JUMP then p.on, p.pos, p.skip = n.on or act == ACT.JUMP, 0, true
	elseif act == ACT.SHUF then p.shuf = a == true
	elseif act == ACT.REP then p.rep = a
	else return end
	if act == ACT.PREV and n.pos > 3 then p.skip = nil end
	ZM.pred[wep] = p
end

-- the state of a phone's music (NW2 + what you just pressed)
local nowCache = setmetatable({}, {__mode = "k"})
function ZM.Now(wep)
	local n = nowCache[wep] or {}
	nowCache[wep] = n
	n.key = wep:GetNW2String("ZMKey", "")
	n.title, n.artist, n.album = wep:GetNW2String("ZMT", ""), wep:GetNW2String("ZMA", ""), wep:GetNW2String("ZMAl", "")
	n.dur = wep:GetNW2Float("ZMDur", 0)
	n.on = wep:GetNW2Bool("ZMOn", false)
	local p0, at = wep:GetNW2Float("ZMPos", 0), wep:GetNW2Float("ZMAt", 0)
	n.pos = n.on and p0 + (CurTime() - at) or p0
	n.rep, n.shuf = wep:GetNW2Int("ZMRep", 0), wep:GetNW2Bool("ZMShuf", false)
	n.qi, n.qn = wep:GetNW2Int("ZMQi", 0), wep:GetNW2Int("ZMQn", 0)
	local pr = ZM.pred[wep]
	if pr then
		if RealTime() - pr.at > 1.5 or (pr.nwAt ~= at and RealTime() - pr.at > 0.05) then
			ZM.pred[wep] = nil
		else
			if pr.s and pr.key ~= n.key then n.key, n.title, n.artist, n.album, n.dur = pr.key, pr.s.title, pr.s.artist, pr.s.album, pr.s.dur or 0 end
			if pr.on ~= nil then n.on = pr.on end
			if pr.pos then n.pos = pr.pos + (n.on and (CurTime() - pr.ct) or 0) end
			if pr.shuf ~= nil then n.shuf = pr.shuf end
			if pr.rep then n.rep = pr.rep end
			n.skip = pr.skip
		end
	end
	if n.dur > 0 then n.pos = math.Clamp(n.pos, 0, n.dur) else n.pos = math.max(0, n.pos) end
	return n
end

net.Receive("stts_zm_qdata", function()
	local wep = net.ReadEntity()
	local ver, n, pos = net.ReadUInt(16), net.ReadUInt(10), net.ReadUInt(10)
	local items = {}
	for i = 1, n do
		items[i] = {key = net.ReadString(), title = net.ReadString(), artist = net.ReadString(), album = net.ReadString(), dur = net.ReadUInt(24) / 10}
	end
	if IsValid(wep) then ZM.queues[wep] = {ver = ver, pos = pos, items = items} end
end)
-- the queue (Up Next) of a phone; asks the server when it changed
function ZM.Queue(wep)
	local v, n = wep:GetNW2Int("ZMQv", 0), wep:GetNW2Int("ZMQn", 0)
	if n == 0 then return nil, 0 end
	local q = ZM.queues[wep]
	if (not q or q.ver ~= v or #q.items ~= n) and RealTime() > (wep.ZM_QAsk or 0) then
		wep.ZM_QAsk = RealTime() + 1.2
		net.Start("stts_zm_qreq") net.WriteEntity(wep) net.SendToServer()
	end
	return q, wep:GetNW2Int("ZMQi", 0)
end

-- what the holder looks at (the others draw the same screen)
function ZM.SendView(wep, v)
	if wep.ZM_ViewSent == v or RealTime() < (wep.ZM_ViewAt or 0) then return end
	wep.ZM_ViewSent, wep.ZM_ViewAt = v, RealTime() + 0.2
	net.Start("stts_zm_view") net.WriteEntity(wep) net.WriteString(string.sub(v, 1, 160)) net.SendToServer()
end

--[[ your songs: the server asks for one when a phone near others plays it ]]
local CHUNK, WIN = 48000, 4
local ups = {}
local function KeyCRC(data) return util.CRC(string.sub(data, 1, 65536) .. (#data > 65536 and string.sub(data, -16384) or "")) end
local function SendArt(key, id)
	local a = id and file.Read(CACHE .. "/a_" .. id .. ".jpg", "DATA")
	if not a or #a < 64 or #a > 60000 then return false end
	net.Start("stts_zm_art") net.WriteString(key) net.WriteUInt(#a, 16) net.WriteData(a, #a) net.SendToServer()
	return true
end
local function Pump(key)
	local j = ups[key]
	if not j then return end
	while j.off < #j.data and j.off - j.acked < CHUNK * WIN do
		local n = math.min(CHUNK, #j.data - j.off)
		net.Start("stts_zm_up")
			net.WriteString(key) net.WriteUInt(j.off, 32) net.WriteUInt(n, 16)
			net.WriteData(string.sub(j.data, j.off + 1, j.off + n), n)
		net.SendToServer()
		j.off = j.off + n
	end
end
net.Receive("stts_zm_need", function()
	local key = net.ReadString()
	local s = ZM.lib.byKey[key]
	if not s or ups[key] then return end
	local data = file.Read(s.path, "DATA")
	if not data or #data ~= s.size or KeyCRC(data) .. "_" .. #data ~= key then return end
	ups[key] = {data = data, off = 0, acked = 0, at = RealTime(), art = s.art, artSent = SendArt(key, s.art)}
	if s.art and not ups[key].artSent then ZM.ArtMat(s.art) end -- make the thumbnail, it goes when ready
	Pump(key)
end)
net.Receive("stts_zm_upack", function()
	local key, got = net.ReadString(), net.ReadUInt(32)
	local j = ups[key]
	if not j then return end
	j.acked, j.at = got, RealTime()
	if not j.artSent and j.art then j.artSent = SendArt(key, j.art) end
	if got >= #j.data then ups[key] = nil return end
	Pump(key)
end)
timer.Create("STTS_ZMusicUp", 1, 0, function()
	for k, j in pairs(ups) do if RealTime() - j.at > 25 then ups[k] = nil end end
end)

--[[ the songs of others: data/zmusic_cache/t_<key>.mp3 (kept up to zmusic_cache_mb) ]]
local dls, asked = {}, {}
local function CachePath(key)
	for _, ext in ipairs({"mp3", "dat"}) do
		local p = CACHE .. "/t_" .. key .. "." .. ext
		if file.Exists(p, "DATA") then return p end
	end
end
local function WriteSong(key, blob)
	for _, ext in ipairs({"mp3", "dat"}) do
		local p = CACHE .. "/t_" .. key .. "." .. ext
		file.Write(p, blob)
		if file.Size(p, "DATA") == #blob then return p end
		file.Delete(p)
	end
end
local srcCache = {}
-- where a song can be played from on this PC (nil = not here yet)
function ZM.Source(key)
	if not key or key == "" then return end
	local c = srcCache[key]
	if c and RealTime() < c.t then return c.p end
	local p
	local s = ZM.lib.byKey[key]
	if s and file.Exists(s.path, "DATA") then
		if s.ascii then p = s.path
		else
			p = CachePath(key)
			if not p then local d = file.Read(s.path, "DATA") if d then p = WriteSong(key, d) end end
		end
	else
		p = CachePath(key)
	end
	srcCache[key] = {p = p, t = RealTime() + (p and 30 or 1)}
	return p
end
function ZM.Fetch(key)
	if not key or key == "" or dls[key] or (asked[key] or 0) > RealTime() then return end
	asked[key] = RealTime() + 15
	net.Start("stts_zm_get") net.WriteString(key) net.SendToServer()
end
function ZM.Progress(key) local d = dls[key] return d and d.total > 0 and d.got / d.total or nil end
local function Trim()
	local files = file.Find(CACHE .. "/t_*", "DATA")
	local list, total = {}, 0
	for _, f in ipairs(files or {}) do
		local p = CACHE .. "/" .. f
		local sz = file.Size(p, "DATA") or 0
		total = total + sz
		list[#list + 1] = {p = p, s = sz, t = file.Time(p, "DATA") or 0}
	end
	local cap = cvCache:GetFloat() * 1048576
	if total <= cap then return end
	table.sort(list, function(a, b) return a.t < b.t end)
	for _, f in ipairs(list) do
		if total <= cap then break end
		file.Delete(f.p)
		total = total - f.s
	end
	srcCache = {}
end
timer.Simple(5, Trim)
net.Receive("stts_zm_dl", function()
	local key, off, total, n = net.ReadString(), net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(16)
	local data = net.ReadData(n)
	net.Start("stts_zm_dlack") net.WriteString(key) net.SendToServer()
	local d = dls[key]
	if off == 0 then d = {parts = {}, got = 0, total = total, at = RealTime()} dls[key] = d end
	if not d or off ~= d.got or not data then return end
	d.parts[#d.parts + 1] = data
	d.got, d.at = d.got + #data, RealTime()
	if d.got < d.total then return end
	dls[key] = nil
	local blob = table.concat(d.parts)
	if KeyCRC(blob) .. "_" .. #blob ~= key then return end
	WriteSong(key, blob)
	srcCache[key], asked[key] = nil, nil
	Trim()
end)
net.Receive("stts_zm_nope", function() local key = net.ReadString() asked[key] = RealTime() + 8 end)
timer.Create("STTS_ZMusicDl", 2, 0, function()
	for k, d in pairs(dls) do if RealTime() - d.at > 30 then dls[k] = nil asked[k] = nil end end
end)
-- covers of others' songs
local artAsk, artAskAt = {}, 0
function ZM.AskArt(key)
	if ZM.lib.byKey[key] or (artAsk[key] or 0) > RealTime() or RealTime() < artAskAt then return end
	artAsk[key], artAskAt = RealTime() + 20, RealTime() + 0.15
	net.Start("stts_zm_artreq") net.WriteString(key) net.SendToServer()
end
net.Receive("stts_zm_art", function()
	local key, n = net.ReadString(), net.ReadUInt(16)
	local data = net.ReadData(n)
	if not data or #data ~= n or string.sub(data, 1, 2) ~= "\255\216" or not string.match(key, "^%d+_%d+$") then return end
	file.Write(CACHE .. "/k_" .. key .. ".jpg", data)
	ZM.ArtArrived(key)
end)
concommand.Add("zmusic_clearcache", function()
	for _, pat in ipairs({"t_*", "k_*"}) do
		for _, f in ipairs(file.Find(CACHE .. "/" .. pat, "DATA") or {}) do file.Delete(CACHE .. "/" .. f) end
	end
	srcCache = {}
	print("ZMusic: cache cleared")
end)

--[[---------------------------------------------------------------------------
	the sound: every PC plays the music of the phones near it, from the phone (3D),
	in step with the server clock. distance, walls, the pocket, the phone volume
---------------------------------------------------------------------------]]
do
	local chans = {}
	ZM.chans = chans
	local phones, phonesAt = {}, 0
	local MAXCH = 4
	local function Stop(c)
		if c and IsValid(c.ch) then c.ch:Stop() end
	end
	local function Pose(wep)
		if wep.STTS_DrawFrame and FrameNumber() - wep.STTS_DrawFrame <= 3 and wep.STTS_DrawPos then return wep.STTS_DrawPos, false end
		local o = wep:GetOwner()
		if IsValid(o) then
			if o:GetActiveWeapon() == wep then return o:GetShootPos() + o:GetAimVector() * 14 - Vector(0, 0, 10), false end
			return o:GetPos() + Vector(0, 0, 36), true -- in the pocket
		end
		return wep:GetPos(), false
	end
	local function Open(wep, c, path, no3d)
		c.loading, c.path, c.no3d = true, path, no3d
		sound.PlayFile("data/" .. path, no3d and "noplay noblock" or "3d noplay noblock", function(ch)
			if chans[wep] ~= c then if IsValid(ch) then ch:Stop() end return end
			c.loading = false
			if not IsValid(ch) then
				if not no3d then Open(wep, c, path, true) return end
				c.fail = RealTime() + 10
				return
			end
			c.ch = ch
			if not no3d then ch:Set3DFadeDistance(350, 100000) end
			ch:SetVolume(0)
		end)
	end
	local function Wanted()
		local lp = LocalPlayer()
		if not IsValid(lp) then return {} end
		if RealTime() > phonesAt then phones, phonesAt = ents.FindByClass(CLASS), RealTime() + 0.5 end
		local eye = lp:EyePos()
		local hear = G.ZMHearDist and G.ZMHearDist() or 1800
		local out = {}
		for _, w in ipairs(phones) do
			if IsValid(w) and not w:IsDormant() and w:GetNW2String("ZMKey", "") ~= "" then
				local mine = w:GetOwner() == lp
				if mine or cvHear:GetBool() then
					local pos, pocket = Pose(w)
					local d = pos:Distance(eye)
					if d < hear + 150 then out[#out + 1] = {w = w, d = d, pos = pos, pocket = pocket} end
				end
			end
		end
		table.sort(out, function(a, b) return a.d < b.d end)
		return out, eye, hear
	end
	local lenSent = {}
	hook.Add("Think", "STTS_ZMusicSound", function()
		local list, eye, hear = Wanted()
		local keep = {}
		for i = 1, math.min(#list, MAXCH) do keep[list[i].w] = list[i] end
		for w, c in pairs(chans) do
			if not keep[w] then Stop(c) chans[w] = nil end
		end
		local now = RealTime()
		for w, it in pairs(keep) do
			local n = ZM.Now(w)
			local c = chans[w]
			if c and c.key ~= n.key then Stop(c) chans[w] = nil c = nil end
			if not c then
				c = {key = n.key, occ = 1, occT = 0}
				chans[w] = c
			end
			if not c.ch and not c.loading and now > (c.fail or 0) then
				local path = ZM.Source(n.key)
				if path then Open(w, c, path, false) else ZM.Fetch(n.key) end
			end
			local ch = c.ch
			if IsValid(ch) then
				local len = ch:GetLength() or 0
				-- the PC that has the file tells the server the real length (the tag / frames guess)
				if len > 1 and ZM.lib.byKey[n.key] and lenSent[n.key] ~= w and math.abs(len - n.dur) > 0.3 and not n.skip then
					lenSent[n.key] = w
					net.Start("stts_zm_len") net.WriteEntity(w) net.WriteString(n.key) net.WriteUInt(math.Clamp(math.floor(len * 10), 0, 2 ^ 24 - 1), 24) net.SendToServer()
				end
				local target = n.pos
				local state = ch:GetState()
				if n.on and not n.skip and (len <= 0 or target < len - 0.25) then
					if state ~= GMOD_CHANNEL_PLAYING then
						ch:SetTime(target) ch:Play()
					elseif math.abs(ch:GetTime() - target) > 0.35 then
						ch:SetTime(target)
					end
				elseif state == GMOD_CHANNEL_PLAYING then
					ch:Pause()
				end
				-- loudness: the phone volume, your setting, the distance, a wall, the pocket
				if now > c.occT then
					c.occT = now + 0.25
					local tr = util.TraceLine({start = eye, endpos = it.pos, mask = MASK_SOLID_BRUSHONLY})
					c.occWant = (tr.Hit and tr.Fraction < 0.97) and 0.5 or 1
				end
				c.occ = Lerp(math.Clamp(FrameTime() * 6, 0, 1), c.occ, c.occWant or 1)
				local vol = w:GetNW2Int("Vol", 100) / 100
				if w:GetOwner() == LocalPlayer() and SCR.Level then vol = SCR.Level(w, "vol") end
				vol = math.Clamp(vol, 0, 1)
				vol = vol * cvVol:GetFloat() * c.occ * (it.pocket and 0.4 or 1)
				vol = vol * (1 - math.Clamp((it.d - hear * 0.6) / (hear * 0.4), 0, 1))
				if c.no3d then vol = vol * math.min(1, 350 / math.max(it.d, 1)) else ch:SetPos(it.pos) end
				ch:SetVolume(vol)
			end
		end
	end)
	hook.Add("EntityRemoved", "STTS_ZMusicSound", function(e)
		local c = chans[e]
		if c then Stop(c) chans[e] = nil end
	end)
	-- is the song of this phone loading / audible here (Now Playing shows it)
	function ZM.ChanState(wep)
		local c = chans[wep]
		if not c then return "none" end
		if IsValid(c.ch) then return "ok" end
		if c.loading then return "loading" end
		return "wait"
	end
end

--[[---------------------------------------------------------------------------
	the app: drawing helpers
---------------------------------------------------------------------------]]
local UI = {}
ZM.UI = UI
local L = SCR.L
local STEP = 80                       -- one scroll unit (px)
local TAB_H = 100                     -- the tab bar: H - TAB_H .. H
local MINI_H = 66
local MINI_Y = H - TAB_H - 10 - MINI_H
local PAD = 22
local VIS = {top = 100, bot = MINI_Y - 4} -- where content may take a touch
UI.STEP, UI.TAB_H, UI.MINI_Y, UI.MINI_H, UI.PAD, UI.VIS = STEP, TAB_H, MINI_Y, MINI_H, PAD, VIS
local Z = ZM.Z or {tab = 1, nav = {}, np = false, mode = 1, query = "", tabScroll = {}, auto = true}
ZM.Z = Z
local nid = 29
local function NID() nid = nid + 1 if nid > 79 then nid = 30 end return nid end
function UI.ResetIds() nid = 29 end
UI.NID = NID
-- a content button: only the part above the mini player / under the bar takes a touch
local function CB(btns, id, x, y, w, h, fn)
	local y0, y1 = math.max(y, VIS.top), math.min(y + h, VIS.bot)
	if y1 - y0 < 8 then return end
	return U.Reg(btns, id, x, y0, w, y1 - y0, fn)
end
UI.CB = CB
local function A(c, a) return Color(c.r, c.g, c.b, (c.a or 255) * a) end
UI.A = A
local function Ic(mat, cx, cy, sz, col)
	if not mat or mat:IsError() then return end
	surface.SetMaterial(mat)
	surface.SetDrawColor(U.LinCol(col or WHITE))
	surface.DrawTexturedRect(cx - sz / 2, cy - sz / 2, sz, sz)
end
UI.Ic = Ic
-- a picture with round corners (a convex polygon, clockwise on the screen)
local function RoundPoly(x, y, w, h, r, seg)
	local pts = {}
	r = math.max(0, math.min(r, w / 2, h / 2))
	seg = seg or (r > 12 and 6 or 4)
	local cs = {{x + w - r, y + r, -90}, {x + w - r, y + h - r, 0}, {x + r, y + h - r, 90}, {x + r, y + r, 180}}
	for _, c in ipairs(cs) do
		for i = 0, seg do
			local a = math.rad(c[3] + 90 * i / seg)
			local px, py = c[1] + math.cos(a) * r, c[2] + math.sin(a) * r
			pts[#pts + 1] = {x = px, y = py, u = (px - x) / w, v = (py - y) / h}
		end
	end
	return pts
end
local function TexRound(mat, x, y, w, h, r, alpha)
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, 255 * (alpha or 1))
	if r <= 0.5 then surface.DrawTexturedRect(x, y, w, h) return end
	surface.DrawPoly(RoundPoly(x, y, w, h, r))
end
UI.TexRound = TexRound
local PH1, PH2 = Color(58, 58, 62), Color(44, 44, 48)
local PL1, PL2 = Color(224, 224, 229), Color(206, 206, 212)
-- artwork (or the grey music note of Apple Music when there is none)
local function Art(mat, x, y, s, r, alpha, round)
	alpha = alpha or 1
	if s < 2 then return end
	if mat then
		if round then
			TexRound(mat, x, y, s, s, s / 2, alpha)
		else TexRound(mat, x, y, s, s, r or 6, alpha) end
		return
	end
	local light = (C.bg and C.bg.r or 0) > 128
	local c1, c2 = light and PL1 or PH1, light and PL2 or PH2
	if round then U.Circle(x + s / 2, y + s / 2, s / 2, A(c1, alpha))
	else U.Round(r or 6, x, y, s, s, A(c1, alpha)) end
	Ic(I.note2, x + s / 2, y + s / 2, s * 0.42, A(light and Color(160, 160, 168) or Color(140, 140, 148), alpha))
end
UI.Art = Art
-- the cover of a library item (album / artist / playlist / song)
local function ItemArt(it) if it then return ZM.ArtMat(it.art) end end
UI.ItemArt = ItemArt
-- 2x2 mosaic for playlists (first four covers); the corners are painted with the background
local function Corner(px, py, cx, cy, a0, r, col)
	draw.NoTexture() surface.SetDrawColor(col.r, col.g, col.b, 255)
	for i = 0, 5 do
		local t0, t1 = math.rad(a0 + 15 * i), math.rad(a0 + 15 * (i + 1))
		local p1, p2, p3 = {x = px, y = py}, {x = cx + math.cos(t0) * r, y = cy + math.sin(t0) * r}, {x = cx + math.cos(t1) * r, y = cy + math.sin(t1) * r}
		if (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x) < 0 then p2, p3 = p3, p2 end
		surface.DrawPoly({p1, p2, p3})
	end
end
local function Mosaic(p, x, y, s, r)
	local arts = p and p.art
	if not arts or #arts == 0 then Art(nil, x, y, s, r) return end
	if #arts < 4 then Art(ZM.ArtMat(arts[1]), x, y, s, r) return end
	local h = s / 2
	U.Round(r, x, y, s, s, C.bg2)
	for i = 1, 4 do
		local m = ZM.ArtMat(arts[i])
		if m then
			surface.SetMaterial(m) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(x + ((i - 1) % 2) * h, y + math.floor((i - 1) / 2) * h, h, h)
		end
	end
	local bg = C.bg or BLACK
	Corner(x, y, x + r, y + r, 180, r, bg)
	Corner(x + s, y, x + s - r, y + r, 270, r, bg)
	Corner(x + s, y + s, x + s - r, y + s - r, 0, r, bg)
	Corner(x, y + s, x + r, y + s - r, 90, r, bg)
end
UI.Mosaic = Mosaic
-- a line of text that does not fit glides sideways (Now Playing / mini player)
local function Marquee(text, font, x, y, w, col, key)
	surface.SetFont(font)
	local tw = surface.GetTextSize(text)
	if tw <= w then U.T(text, font, x, y, col, TEXT_ALIGN_LEFT) return end
	local gap = 60
	local cycle = (tw + gap) / 34
	local t = (RealTime() + (key or 0)) % (cycle + 3)
	local off = t < 3 and 0 or (t - 3) * 34
	U.Clip(x, y - 30, w, 60)
	U.T(text, font, x - off, y, col, TEXT_ALIGN_LEFT)
	U.T(text, font, x - off + tw + gap, y, col, TEXT_ALIGN_LEFT)
	U.Unclip()
end
UI.Marquee = Marquee
-- "now playing" bars (three red bars that move while the song plays)
local function Bars(cx, cy, s, col, on)
	local bw = s * 0.2
	for i = 0, 2 do
		local h = on and (0.35 + 0.65 * math.abs(math.sin(RealTime() * (4 + i * 1.3) + i * 1.7))) or (0.3 + i * 0.15)
		U.Round(1, cx - s / 2 + i * (bw + s * 0.2) + s * 0.1, cy + s / 2 - s * h, bw, s * h, col)
	end
end
UI.Bars = Bars
local function Hi(wep, st, id, x, y, w, h, r)
	local k = U.HoverK(wep, id, st.sel == id)
	if k <= 0.01 then return end
	local a = (U.Pressed(wep, st, id) and 46 or 20) * k
	if r then U.Round(r, x, y, w, h, SCR.Ink(a)) else U.R(x, y, w, h, SCR.Ink(a)) end
end
UI.Hi = Hi
local function Sep(x, y, w) U.R(x, y, w, 1, C.sep) end
UI.Sep = Sep
local function Lines(n) return n == 1 and "1 song" or (n .. " songs") end
UI.Lines = Lines
local function Minutes(sec)
	local m = math.floor((sec or 0) / 60 + 0.5)
	if m >= 60 then local h = math.floor(m / 60) return h .. (h == 1 and " hour, " or " hours, ") .. (m % 60) .. " minutes" end
	return m .. (m == 1 and " minute" or " minutes")
end
UI.Minutes = Minutes

--[[---------------------------------------------------------------------------
	the app: navigation, rows, grids, the pages
---------------------------------------------------------------------------]]
ZM.remoteLib = {songs = {}, byKey = {}, albums = {}, artists = {}, playlists = {}, genres = {}, recent = {}, ready = true, remote = true,
	byAlbum = {}, byArtist = {}, byPl = {}, byGenre = {}}
local function HUD(text) Z.hud = {text = text, at = RealTime()} end
UI.HUD = HUD
local TITLES = {"Home", "New", "Library", "Search"} -- fix61: no Radio
local function CurTitle()
	local lv = LV[L.app] or 1
	if lv == 1 then return TITLES[Z.tab] or "Library" end
	local n = Z.nav[lv]
	return n and n.title or "Back"
end
function UI.Push(st, kind, id, title, back)
	if not st.own then return end
	local lv = LV[L.app] or 1
	local nl = math.min(lv + 1, 4)
	if lv == 1 then Z.tabScroll[Z.tab] = L.scroll elseif Z.nav[lv] then Z.nav[lv].scroll = L.scroll end
	Z.nav[nl] = {kind = kind, id = id, title = title or "", back = back or CurTitle()}
	Z.menu = nil
	if nl == lv then L.scroll, L.scrollV, L.scrollGo = 0, 0, nil else U.SetApp(st, APP_OF[nl]) end
	Z.lastLv = nl
end
function UI.Back(st)
	if not st.own then return end
	local lv = LV[L.app] or 1
	if lv > 1 then U.SetApp(st, APP_OF[lv - 1]) end
end
local function RestoreScroll(lv)
	local s
	if lv == 1 then s = Z.tabScroll[Z.tab] else s = Z.nav[lv] and Z.nav[lv].scroll end
	L.scroll, L.scrollV, L.scrollGo = s or 0, 0, nil
end
function UI.Tab(st, i)
	if not st.own then return end
	local lv = LV[L.app] or 1
	Z.menu = nil
	if lv > 1 then
		Z.tab = i
		U.SetApp(st, APP)
		Z.lastLv = 1
		L.scroll = Z.tabScroll[i] or 0
		return
	end
	if Z.tab == i then L.scrollV, L.scrollGo = 0, 0 return end
	Z.tabScroll[Z.tab] = L.scroll
	Z.tab = i
	L.scroll, L.scrollV, L.scrollGo = Z.tabScroll[i] or 0, 0, nil
end
function UI.OpenNP(st)
	if not st.own or Z.np then return end
	Z.np, Z.mode, Z.menu = true, 1, nil
	Z.pageScroll = L.scroll
	L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
end
function UI.CloseNP(st)
	if not st.own or not Z.np then return end
	Z.np, Z.menu = false, nil
	L.scroll, L.scrollV, L.scrollGo = Z.pageScroll or 0, 0, nil
end
function UI.Mode(st, m)
	if not st.own then return end
	Z.mode = Z.mode == m and 1 or m
	L.scroll, L.scrollV, L.scrollGo = 0, 0, nil
	Z.lyrUser = nil
end

-- the context menu (the "..." of a row)
function UI.Menu(st, x, y, items)
	if not st.own then return end
	Z.menu = {x = x, y = y, items = items, at = RealTime()}
	local wep = L.wep
	if IsValid(wep) and wep.STTS_SK then wep.STTS_SK.zmmenu = nil end
end
function UI.SongMenu(wep, st, s, x, y, inNP)
	local lib = ZM.lib
	local fav = ZM.IsFav(s.key)
	local items = {
		{"Play Next", I.nextup, function() ZM.Act(wep, ACT.NEXTUP, s) HUD("Playing Next") end},
		{"Play Last", I.last, function() ZM.Act(wep, ACT.LAST, s) HUD("Playing Last") end},
		{fav and "Undo Favorite" or "Favorite", fav and I.staro or I.star, function() ZM.ToggleFav(s.key) HUD(fav and "Removed from Favorites" or "Added to Favorites") end},
	}
	if inNP then table.remove(items, 1) table.remove(items, 1) end
	if s.alb then items[#items + 1] = {"Go to Album", I.albums, function() UI.CloseNP(st) UI.Push(st, "album", s.alb.id, s.alb.name, CurTitle()) end} end
	local ar = lib.byArtist and lib.byArtist[util.CRC(Low(s.aartist or ""))]
	if ar then items[#items + 1] = {"Go to Artist", I.mic, function() UI.CloseNP(st) UI.Push(st, "artist", ar.id, ar.name, CurTitle()) end} end
	UI.Menu(st, x, y, items)
end
function UI.DrawMenu(wep, st, btns)
	local m = Z.menu
	if not m then return end
	local k = U.SpringK(wep, "zmmenu", true, 0.32, 0.82)
	local rowH, w = 60, 292
	local h = #m.items * rowH
	local x = math.Clamp(m.x - w + 24, 12, W - w - 12)
	local y = m.y + 30
	if y + h > H - 60 then y = m.y - 30 - h end
	y = math.Clamp(y, 56, H - 60 - h)
	U.R(0, 0, W, H, Color(0, 0, 0, 70 * math.Clamp(k, 0, 1)))
	local light = (C.bg and C.bg.r or 0) > 128
	local cx, cy = m.x, m.y
	local sc = Lerp(math.Clamp(k, 0, 1.2), 0.3, 1)
	local mt = Matrix()
	mt:Translate(Vector(cx, cy, 0)) mt:Scale(Vector(sc, sc, 1)) mt:Translate(Vector(-cx, -cy, 0))
	cam.PushModelMatrix(mt, true)
	surface.SetAlphaMultiplier(math.Clamp(k * 1.4, 0, 1))
	for i = 1, 5 do U.Round(16 + i * 2, x - i * 2, y - i * 2 + 6, w + i * 4, h + i * 4, Color(0, 0, 0, 12)) end
	U.Round(16, x, y, w, h, light and Color(246, 246, 247, 252) or Color(40, 40, 42, 252))
	for i, it in ipairs(m.items) do
		local ry = y + (i - 1) * rowH
		local id = 159 + i
		if k > 0.6 then U.Reg(btns, id, x, ry, w, rowH, function() Z.menu = nil it[3]() end) end
		local hk = U.HoverK(wep, id, st.sel == id)
		if hk > 0.01 then
			local col = SCR.Ink((U.Pressed(wep, st, id) and 40 or 22) * hk)
			if i == 1 and #m.items == 1 then U.Round(16, x, ry, w, rowH, col)
			elseif i == 1 then draw.RoundedBoxEx(16, x, ry, w, rowH, U.LinCol(col), true, true, false, false)
			elseif i == #m.items then draw.RoundedBoxEx(16, x, ry, w, rowH, U.LinCol(col), false, false, true, true)
			else U.R(x, ry, w, rowH, col) end
		end
		local col = it[4] and C.red or C.label
		U.T(U.Fit(it[1], "STTS_ZM_Row", w - 80), "STTS_ZM_Row", x + 20, ry + rowH / 2, col, TEXT_ALIGN_LEFT)
		Ic(it[2], x + w - 32, ry + rowH / 2, 26, col)
		if i < #m.items then Sep(x, ry + rowH - 1, w) end
	end
	surface.SetAlphaMultiplier(1)
	cam.PopModelMatrix()
	U.Reg(btns, 172, 0, 0, W, H, function() Z.menu = nil end)
end

--[[ pieces of the pages ]]
local CW = math.floor((W - PAD * 2 - 16) / 2)
local function RootTitle(title, sy)
	U.T(title, "STTS_I_Large", PAD, 122 - sy, C.label, TEXT_ALIGN_LEFT)
end
local function PageTitle(title, sy)
	U.T(U.Fit(title, "STTS_I_Large", W - PAD * 2), "STTS_I_Large", PAD, 150 - sy, C.label, TEXT_ALIGN_LEFT)
end
-- the bar on top: appears with the inline title once the large one scrolled away
local function NavBar(wep, st, btns, title, sy, from, back)
	local a = math.Clamp((sy - from) / 36, 0, 1)
	if a > 0.01 then
		U.R(0, 0, W, 104, A(C.bar, a))
		U.R(0, 103, W, 1, A(C.sep, a))
		U.T(U.Fit(title, "STTS_I_Nav", W - 220), "STTS_I_Nav", W / 2, 78, A(C.label, a))
	end
	if back then U.NavBack(btns, wep, st, back, function() UI.Back(st) end, ACC) end
end
UI.NavBar = NavBar
local function Section(text, y, chev)
	U.T(text, "STTS_ZM_H2", PAD, y, C.label, TEXT_ALIGN_LEFT)
	if chev then
		surface.SetFont("STTS_ZM_H2")
		local tw = surface.GetTextSize(text)
		U.Chevron(PAD + tw + 18, y + 1, 8, "right", C.label2, 3.5)
	end
end
-- cards in two columns: it = {title, sub, art = material, mosaic = playlist, round, tap}
local function Grid(wep, st, btns, items, y, sy, maxN)
	local n = math.min(#items, maxN or #items)
	local rowH = CW + 70
	for i = 1, n do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local x, cy = PAD + col * (CW + 16), y + row * rowH - sy
		if cy < H and cy + rowH > 0 then
			local it = items[i]
			local id = NID()
			if it.tap then CB(btns, id, x, cy, CW, rowH - 10, it.tap) end
			if it.mosaic then Mosaic(it.mosaic, x, cy, CW, 8)
			elseif it.draw then it.draw(x, cy, CW)
			else Art(it.art, x, cy, CW, 8, 1, it.round) end
			local k = U.HoverK(wep, id, st.sel == id)
			if k > 0.01 then
				if it.round then U.Circle(x + CW / 2, cy + CW / 2, CW / 2, Color(0, 0, 0, (U.Pressed(wep, st, id) and 90 or 50) * k))
				else U.Round(8, x, cy, CW, CW, Color(0, 0, 0, (U.Pressed(wep, st, id) and 90 or 50) * k)) end
			end
			local ax = it.round and x + CW / 2 or x
			local al = it.round and TEXT_ALIGN_CENTER or TEXT_ALIGN_LEFT
			U.T(U.Fit(it.title or "", "STTS_ZM_Card", CW), "STTS_ZM_Card", ax, cy + CW + 20, C.label, al)
			if it.sub then U.T(U.Fit(it.sub, "STTS_ZM_RowS", CW), "STTS_ZM_RowS", ax, cy + CW + 45, C.label2, al) end
		end
	end
	return math.ceil(n / 2) * rowH
end
-- grey blocks where the holder's own library would be (others do not have it)
local function Skeleton(y, sy, n, kind)
	local c = A(C.label, 0.08)
	for i = 1, n do
		if kind == "grid" then
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local x, cy = PAD + col * (CW + 16), y + row * (CW + 70) - sy
			U.Round(8, x, cy, CW, CW, c)
			U.Round(5, x, cy + CW + 12, CW * 0.7, 16, c)
		else
			local ry = y + (i - 1) * 74 - sy
			U.Round(6, PAD, ry + 10, 54, 54, c)
			U.Round(5, PAD + 70, ry + 22, 200, 14, c)
			U.Round(5, PAD + 70, ry + 44, 120, 12, c)
		end
	end
	return kind == "grid" and math.ceil(n / 2) * (CW + 70) or n * 74
end
UI.Skeleton = Skeleton
local function AlbumItem(wep, st, al, back)
	return {title = al.name, sub = al.artist, art = ZM.ArtMat(al.art), tap = function() UI.Push(st, "album", al.id, al.name, back) end}
end
local function PlItem(wep, st, p, back)
	return {title = p.name, sub = "Playlist", mosaic = p, tap = function() UI.Push(st, "playlist", p.id, p.name, back) end}
end
-- Play / Shuffle (two grey buttons, red glyph + text)
local function PlayButtons(wep, st, btns, list, y, tag)
	local bw = math.floor((W - PAD * 2 - 16) / 2)
	for i, it in ipairs({{"Play", I.play, false}, {"Shuffle", I.shuffle, true}}) do
		local x = PAD + (i - 1) * (bw + 16)
		local id = 20 + i
		CB(btns, id, x, y, bw, 54, function() ZM.PlayList(wep, list, 1, it[3], tag) end)
		U.Round(12, x, y, bw, 54, C.bg2)
		local k = U.HoverK(wep, id, st.sel == id)
		if k > 0.01 then U.Round(12, x, y, bw, 54, SCR.Ink((U.Pressed(wep, st, id) and 40 or 18) * k)) end
		surface.SetFont("STTS_ZM_Btn")
		local tw = surface.GetTextSize(it[1])
		local gx = x + bw / 2 - (tw + 32) / 2
		Ic(it[2], gx + 11, y + 27, 22, ACC)
		U.T(it[1], "STTS_ZM_Btn", gx + 32, y + 27, ACC, TEXT_ALIGN_LEFT)
	end
	return 54
end
UI.PlayButtons = PlayButtons
-- song rows (only the visible ones are drawn)
local ROW = 74
local function SongRows(wep, st, btns, list, y, sy, opts)
	opts = opts or {}
	local n = #list
	local rh = opts.rowH or ROW
	local top = y - sy
	local first = math.max(1, math.floor(-top / rh) + 1)
	local last = math.min(n, math.ceil((H - top) / rh))
	local now = ZM.Now(wep)
	for i = first, last do
		local s = list[i]
		local ry = top + (i - 1) * rh
		local id, mid = NID(), NID()
		CB(btns, mid, W - 66, ry, 66, rh, function() UI.SongMenu(wep, st, s, W - 40, ry + rh / 2) end)
		CB(btns, id, 0, ry, W - 66, rh, function() ZM.PlayList(wep, list, i, false, opts.tag) end)
		Hi(wep, st, id, 0, ry, W, rh)
		local playing = now.key == s.key
		local tx
		if opts.num then
			if playing then Bars(PAD + 14, ry + rh / 2, 20, ACC, now.on)
			else U.T(tostring((s.track or 0) > 0 and s.track or i), "STTS_ZM_Num", PAD + 14, ry + rh / 2, C.label2) end
			tx = PAD + 46
		else
			local as = rh - 20
			Art(ZM.ArtMat(s.art), PAD, ry + 10, as, 6)
			if playing then U.Round(6, PAD, ry + 10, as, as, Color(0, 0, 0, 120)) Bars(PAD + as / 2, ry + rh / 2, 20, WHITE, now.on) end
			tx = PAD + as + 16
		end
		local tw = W - tx - 76
		local fav = ZM.IsFav(s.key)
		if opts.num and not opts.sub then
			U.T(U.Fit(s.title, "STTS_ZM_Row", tw), "STTS_ZM_Row", tx, ry + rh / 2, playing and ACC or C.label, TEXT_ALIGN_LEFT)
		else
			U.T(U.Fit(s.title, "STTS_ZM_Row", tw), "STTS_ZM_Row", tx, ry + rh / 2 - 13, playing and ACC or C.label, TEXT_ALIGN_LEFT)
			U.T(U.Fit(opts.sub and opts.sub(s) or s.artist, "STTS_ZM_RowS", tw), "STTS_ZM_RowS", tx, ry + rh / 2 + 15, C.label2, TEXT_ALIGN_LEFT)
		end
		if fav then Ic(I.star, W - 70, ry + rh / 2, 16, ACC) end
		Ic(I.dots, W - 34, ry + rh / 2, 26, C.label)
		if i < n then Sep(tx, ry + rh - 1, W - tx) end
	end
	return n * rh
end
UI.SongRows = SongRows
-- a row that opens something: picture (square / round / icon), name, a second line, chevron
local function NavRows(wep, st, btns, list, y, sy, rh, fn)
	local top = y - sy
	local first = math.max(1, math.floor(-top / rh) + 1)
	local last = math.min(#list, math.ceil((H - top) / rh))
	for i = first, last do
		local it = list[i]
		local ry = top + (i - 1) * rh
		local id = NID()
		CB(btns, id, 0, ry, W, rh, it.tap)
		Hi(wep, st, id, 0, ry, W, rh)
		local tx = PAD
		local as = rh - 18
		if it.icon then Ic(it.icon, PAD + 16, ry + rh / 2, 30, ACC) tx = PAD + 50
		elseif it.mosaic then Mosaic(it.mosaic, PAD, ry + 9, as, 6) tx = PAD + as + 16
		elseif it.art ~= nil or it.round then Art(it.art or nil, PAD, ry + 9, as, 6, 1, it.round) tx = PAD + as + 16 end
		local tw = W - tx - 50
		if it.sub then
			U.T(U.Fit(it.title, "STTS_ZM_Row", tw), "STTS_ZM_Row", tx, ry + rh / 2 - 13, C.label, TEXT_ALIGN_LEFT)
			U.T(U.Fit(it.sub, "STTS_ZM_RowS", tw), "STTS_ZM_RowS", tx, ry + rh / 2 + 15, C.label2, TEXT_ALIGN_LEFT)
		else
			U.T(U.Fit(it.title, it.icon and "STTS_I_Body" or "STTS_ZM_Row", tw), it.icon and "STTS_I_Body" or "STTS_ZM_Row", tx, ry + rh / 2, C.label, TEXT_ALIGN_LEFT)
		end
		U.Chevron(W - 26, ry + rh / 2, 9, "right", C.label3 or C.label2, 3.5)
		if i < #list then Sep(tx, ry + rh - 1, W - tx) end
	end
	return #list * rh
end
UI.NavRows = NavRows
local function Center(text, y, font, col) U.T(text, font or "STTS_ZM_Row", W / 2, y, col or C.label2) end

-- nothing in data/zmusic yet
local function Empty(wep, st, btns, y)
	Ic(I.note2, W / 2, y + 80, 84, C.label3 or C.label2)
	Center("Add Music to ZMusic", y + 170, "STTS_ZM_H2", C.label)
	-- fix61: only the title, the folder and Rescan (the explanation lines are gone)
	Center("garrysmod/data/zmusic/", y + 222, "STTS_ZM_Card", C.label2)
	if ZM.scanning then
		Center("Scanning… " .. (ZM.scanDone or 0) .. " / " .. (ZM.scanTotal or 0), y + 330, "STTS_ZM_RowS")
	else
		local bw, bx, by = 200, W / 2 - 100, y + 306
		CB(btns, 23, bx, by, bw, 52, function() ZM.Rescan() end)
		U.Round(26, bx, by, bw, 52, ACC)
		if U.HoverK(wep, 23, st.sel == 23) > 0.01 then U.Round(26, bx, by, bw, 52, Color(255, 255, 255, 30 * U.HoverK(wep, 23, st.sel == 23))) end
		Center("Rescan", by + 26, "STTS_ZM_Btn", WHITE)
	end
	return 380
end

-- songs sorted by when they were added / albums by year (cached on the library)
local function Latest(lib)
	if lib.latest then return lib.latest end
	local t = {}
	for i, s in ipairs(lib.songs) do t[i] = s end
	table.sort(t, function(a, b) if a.added ~= b.added then return a.added > b.added end return a.path < b.path end)
	lib.latest = t
	return t
end
local function ByYear(lib)
	if lib.byYearL then return lib.byYearL end
	local t = {}
	for i, al in ipairs(lib.albums) do t[i] = al end
	table.sort(t, function(a, b) if (a.year or 0) ~= (b.year or 0) then return (a.year or 0) > (b.year or 0) end return a.added > b.added end)
	lib.byYearL = t
	return t
end
local function RecentPlayed(wep, st, lib)
	local out = {}
	for _, tag in ipairs(ZM.prefs.recent) do
		local kind, id = string.match(tag, "^(%a):(.+)$")
		if kind == "a" and lib.byAlbum[id] then out[#out + 1] = AlbumItem(wep, st, lib.byAlbum[id], "Home")
		elseif kind == "p" and lib.byPl[id] then out[#out + 1] = PlItem(wep, st, lib.byPl[id], "Home") end
		if #out >= 4 then break end
	end
	return out
end
-- a big gradient card (Top Picks, Radio)
local function Hero(wep, st, btns, id, x, y, w, h, c1, c2, icon, title, sub, fn)
	CB(btns, id, x, y, w, h, fn)
	U.Round(12, x, y, w, h, c2)
	U.Clip(x, y, w, h)
	U.VGrad(x, y + 10, w, h - 20, c1, c2, 24)
	U.Unclip()
	U.Round(12, x, y, w, 16, c1)
	U.Round(12, x, y + h - 16, w, 16, c2)
	Ic(icon, x + w / 2, y + h * 0.4, math.min(w, h) * 0.34, Color(255, 255, 255, 235))
	U.T(U.Fit(title, "STTS_ZM_Card", w - 28), "STTS_ZM_Card", x + 16, y + h - 52, WHITE, TEXT_ALIGN_LEFT)
	if sub then U.T(U.Fit(sub, "STTS_ZM_RowS", w - 28), "STTS_ZM_RowS", x + 16, y + h - 26, Color(255, 255, 255, 200), TEXT_ALIGN_LEFT) end
	local k = U.HoverK(wep, id, st.sel == id)
	if k > 0.01 then U.Round(12, x, y, w, h, Color(0, 0, 0, (U.Pressed(wep, st, id) and 80 or 40) * k)) end
end
local STATION = {Color(232, 64, 87), Color(88, 86, 214), Color(52, 170, 220), Color(255, 149, 0), Color(48, 176, 120), Color(175, 82, 222), Color(255, 59, 108), Color(90, 200, 250)}

--[[ the tabs ]]
local TAB = {}
TAB[1] = function(wep, st, btns, sy, lib) -- Home
	RootTitle("Home", sy)
	local y = 176
	if lib.remote then return y + Skeleton(y + 40, sy, 6, "grid") + 60 end
	if #lib.songs == 0 then return y + Empty(wep, st, btns, y - sy) end
	Section("Top Picks for You", y - sy)
	y = y + 34
	local favs = ZM.FavSongs()
	local ch = 252
	Hero(wep, st, btns, NID(), PAD, y - sy, CW, ch, Color(252, 92, 116), Color(188, 22, 58), I.shuffle, "Shuffle All", Lines(#lib.songs),
		function() ZM.PlayList(wep, lib.songs, 1, true) end)
	if #favs > 0 then
		Hero(wep, st, btns, NID(), PAD + CW + 16, y - sy, CW, ch, Color(255, 159, 10), Color(232, 64, 60), I.star, "Favorite Songs", Lines(#favs),
			function() UI.Push(st, "fav", nil, "Favorite Songs", "Home") end)
	else
		local lat = Latest(lib)
		Hero(wep, st, btns, NID(), PAD + CW + 16, y - sy, CW, ch, Color(94, 92, 230), Color(48, 40, 140), I.note, "Recently Added", Lines(math.min(#lat, 25)),
			function() UI.Push(st, "latest", nil, "Recently Added", "Home") end)
	end
	y = y + ch + 40
	local rp = RecentPlayed(wep, st, lib)
	if #rp > 0 then
		Section("Recently Played", y - sy)
		y = y + 34
		y = y + Grid(wep, st, btns, rp, y, sy) + 16
	end
	Section("Recently Added", y - sy, true)
	CB(btns, NID(), 0, y - 24 - sy, W, 48, function() UI.Push(st, "recent", nil, "Recently Added", "Home") end)
	y = y + 34
	local items = {}
	for i = 1, math.min(6, #lib.recent) do items[i] = AlbumItem(wep, st, lib.recent[i], "Home") end
	y = y + Grid(wep, st, btns, items, y, sy)
	return y + 40
end
TAB[2] = function(wep, st, btns, sy, lib) -- New
	RootTitle("New", sy)
	local y = 176
	if lib.remote then return y + Skeleton(y + 40, sy, 6, "rows") + 60 end
	if #lib.songs == 0 then return y + Empty(wep, st, btns, y - sy) end
	local lat = Latest(lib)
	Section("Latest Songs", y - sy, true)
	CB(btns, NID(), 0, y - 24 - sy, W, 48, function() UI.Push(st, "latest", nil, "Latest Songs", "New") end)
	y = y + 30
	local top = {}
	for i = 1, math.min(6, #lat) do top[i] = lat[i] end
	y = y + SongRows(wep, st, btns, top, y, sy, {tag = nil}) + 36
	Section("New Releases", y - sy)
	y = y + 34
	local items = {}
	for i, al in ipairs(ByYear(lib)) do
		if i > 20 then break end
		local it = AlbumItem(wep, st, al, "New")
		it.sub = al.year and (al.artist .. " · " .. al.year) or al.artist
		items[i] = it
	end
	y = y + Grid(wep, st, btns, items, y, sy)
	return y + 40
end
--[[ fix61: the Radio tab is gone. "ZMusic Radio" was the same as Home > Shuffle All
     (ZM.PlayList(lib.songs, shuffled)), its "stations" the genres / artists of the
     Library on shuffle: nothing of its own (no streams). Library is tab 3, Search 4 ]]
local LIBROWS = {
	{"Playlists", "notes", "playlists"}, {"Artists", "mic", "artists"}, {"Albums", "stack", "albums"},
	{"Songs", "note", "songs"}, {"Genres", "list", "genres"}, {"Favorite Songs", "star", "fav"},
}
TAB[3] = function(wep, st, btns, sy, lib) -- Library
	RootTitle("Library", sy)
	-- Rescan (where iOS has "Edit")
	if not lib.remote then
		local id = 20
		surface.SetFont("STTS_I_Body")
		local tw = surface.GetTextSize("Rescan")
		local ry = 78 - math.min(sy, 0)
		U.Reg(btns, id, W - PAD - tw - 16, ry - 24, tw + 24, 48, function() ZM.Rescan() end)
		local k = U.HoverK(wep, id, st.sel == id)
		if k > 0.01 then U.Round(16, W - PAD - tw - 12, ry - 22, tw + 20, 44, SCR.Ink(22 * k)) end
		U.T(ZM.scanning and "Scanning…" or "Rescan", "STTS_I_Body", W - PAD - 2, ry, ACC, TEXT_ALIGN_RIGHT)
	end
	local y = 168
	local rows = {}
	for i, r in ipairs(LIBROWS) do
		rows[i] = {title = r[1], icon = I[r[2]], tap = function()
			if r[3] == "fav" and #ZM.FavSongs() == 0 then HUD("No favorite songs yet") return end
			UI.Push(st, r[3], nil, r[1], "Library")
		end}
	end
	y = y + NavRows(wep, st, btns, rows, y, sy, 62) + 34
	if lib.remote then return y + Skeleton(y + 34, sy, 4, "grid") + 80 end
	if #lib.songs == 0 then return y + Empty(wep, st, btns, y - sy) end
	Section("Recently Added", y - sy)
	y = y + 34
	local items = {}
	for i = 1, math.min(30, #lib.recent) do
		local al = lib.recent[i]
		items[i] = AlbumItem(wep, st, al, "Library")
	end
	y = y + Grid(wep, st, btns, items, y, sy)
	return y + 40
end
-- the search field: an invisible text entry catches the keyboard (like TeleChat)
function ZM.OpenSearch()
	if not L.raised then return end
	if IsValid(L.entry) then if IsValid(L.entry.te) then L.entry.te:RequestFocus() end return end
	local fr = vgui.Create("EditablePanel")
	fr:SetSize(2, 2) fr:SetPos(-10, -10)
	fr:MakePopup()
	fr:SetKeyboardInputEnabled(true)
	fr:SetMouseInputEnabled(false)
	fr.openedAt = RealTime()
	fr.Paint = function() end
	local te = vgui.Create("DTextEntry", fr)
	te:SetPos(0, 0) te:SetSize(2, 2)
	te:SetText(Z.query or "")
	te:SetCaretPos(#(SCR.U8Starts and SCR.U8Starts(Z.query or "") or {}))
	te:SetUpdateOnType(true)
	te.Paint = function() end
	te.AllowInput = function(self) return #(self:GetValue() or "") >= 60 end
	te.OnValueChange = function(self, v) Z.query = v L.scroll, L.scrollV, L.scrollGo = 0, 0, nil end
	te.OnEnter = function(self) Z.query = self:GetValue() fr:Remove() end
	fr.Think = function(self)
		if not L.raised or L.app ~= APP or Z.tab ~= 4 or Z.np then self:Remove() return end
		if RealTime() - self.openedAt > 0.3 and IsValid(te) and not te:HasFocus() then self:Remove() return end
	end
	fr.te = te
	fr.zm = true
	L.entry = fr
	te:RequestFocus()
end
local function Search(lib, q)
	q = Low(string.Trim(q or ""))
	if q == "" then return end
	if lib.sq == q then return lib.sr end
	local r = {artists = {}, albums = {}, songs = {}}
	for _, ar in ipairs(lib.artists) do if #r.artists < 4 and string.find(ar.low, q, 1, true) then r.artists[#r.artists + 1] = ar end end
	for _, al in ipairs(lib.albums) do if #r.albums < 4 and string.find(al.low, q, 1, true) then r.albums[#r.albums + 1] = al end end
	for _, s in ipairs(lib.songs) do if #r.songs < 40 and string.find(s.low, q, 1, true) then r.songs[#r.songs + 1] = s end end
	lib.sq, lib.sr = q, r
	return r
end
TAB[4] = function(wep, st, btns, sy, lib) -- Search
	RootTitle("Search", sy)
	local y = 168
	local fy = y - sy
	local typing = st.own and IsValid(L.entry) and L.entry.zm
	local q = st.own and Z.query or ""
	CB(btns, 23, PAD, fy, W - PAD * 2 - (q ~= "" and 50 or 0), 50, function() ZM.OpenSearch() end)
	U.Round(12, PAD, fy, W - PAD * 2, 50, C.fill or C.bg2)
	Ic(I.search, PAD + 24, fy + 25, 22, C.label2)
	if q ~= "" then
		local tw = W - PAD * 2 - 100
		U.T(U.Fit(q, "STTS_ZM_Row", tw), "STTS_ZM_Row", PAD + 46, fy + 25, C.label, TEXT_ALIGN_LEFT)
		CB(btns, 24, W - PAD - 52, fy, 52, 50, function() Z.query = "" if IsValid(L.entry) and L.entry.zm then L.entry:Remove() end end)
		Ic(I.xc, W - PAD - 26, fy + 25, 24, C.label2)
	else
		U.T("Artists, Songs, Albums", "STTS_ZM_Row", PAD + 46, fy + 25, C.label2, TEXT_ALIGN_LEFT)
	end
	if typing and math.floor(RealTime() * 2) % 2 == 0 then
		surface.SetFont("STTS_ZM_Row")
		local cx = PAD + 46 + (q ~= "" and math.min(surface.GetTextSize(q), W - PAD * 2 - 100) or 0) + 2
		U.R(cx, fy + 11, 3, 28, ACC)
	end
	y = y + 80
	if lib.remote then return y + Skeleton(y + 34, sy, 6, "grid") + 60 end
	local r = Search(lib, q)
	if not r then
		Section("Browse Categories", y - sy)
		y = y + 34
		local cats = {{name = "All Songs", kind = "songs"}, {name = "Albums", kind = "albums"}, {name = "Artists", kind = "artists"}, {name = "Playlists", kind = "playlists"}}
		for _, g in ipairs(lib.genres) do cats[#cats + 1] = {name = g.name, kind = "genre", id = g.id} end
		local ch = 116
		for i, c in ipairs(cats) do
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local x, cy = PAD + col * (CW + 16), y + row * (ch + 16) - sy
			if cy < H and cy + ch > 0 then
				local id = NID()
				CB(btns, id, x, cy, CW, ch, function() UI.Push(st, c.kind, c.id, c.name, "Search") end)
				U.Round(10, x, cy, CW, ch, STATION[(i - 1) % #STATION + 1])
				local k = U.HoverK(wep, id, st.sel == id)
				if k > 0.01 then U.Round(10, x, cy, CW, ch, Color(0, 0, 0, (U.Pressed(wep, st, id) and 80 or 40) * k)) end
				U.T(U.Fit(c.name, "STTS_ZM_Card", CW - 24), "STTS_ZM_Card", x + 14, cy + ch - 26, WHITE, TEXT_ALIGN_LEFT)
			end
		end
		return y + math.ceil(#cats / 2) * (ch + 16) + 40
	end
	if #r.artists + #r.albums + #r.songs == 0 then
		Center("No Results", y + 60 - sy, "STTS_ZM_H2", C.label)
		Center("Try a new search.", y + 98 - sy, "STTS_ZM_RowS")
		return y + 140
	end
	if #r.artists > 0 then
		Section("Artists", y - sy) y = y + 30
		local rows = {}
		for i, ar in ipairs(r.artists) do rows[i] = {title = ar.name, sub = "Artist", art = ZM.ArtMat(ar.art), round = true, tap = function() UI.Push(st, "artist", ar.id, ar.name, "Search") end} end
		y = y + NavRows(wep, st, btns, rows, y, sy, 76) + 30
	end
	if #r.albums > 0 then
		Section("Albums", y - sy) y = y + 30
		local rows = {}
		for i, al in ipairs(r.albums) do rows[i] = {title = al.name, sub = "Album · " .. al.artist, art = ZM.ArtMat(al.art) or false, tap = function() UI.Push(st, "album", al.id, al.name, "Search") end} end
		y = y + NavRows(wep, st, btns, rows, y, sy, 80) + 30
	end
	if #r.songs > 0 then
		Section("Songs", y - sy) y = y + 30
		y = y + SongRows(wep, st, btns, r.songs, y, sy, {sub = function(s) return "Song · " .. s.artist end})
	end
	return y + 40
end
UI.TAB = TAB

--[[ the pages behind a row / a card (levels 2..4) ]]
local PAGE = {}
local function SongsPage(wep, st, btns, sy, nav, lib)
	local list
	if nav.kind == "fav" then list = ZM.FavSongs()
	elseif nav.kind == "genre" then list = lib.byGenre[nav.id] and lib.byGenre[nav.id].songs or {}
	elseif nav.kind == "latest" then list = Latest(lib)
	else list = lib.songs end
	PageTitle(nav.title, sy)
	local y = 200
	if #list == 0 then Center("No Songs", y + 80 - sy, "STTS_ZM_H2", C.label) return y + 200 end
	PlayButtons(wep, st, btns, list, y - sy, nav.kind == "genre" and ("g:" .. tostring(nav.id)) or nil)
	y = y + 74
	y = y + SongRows(wep, st, btns, list, y, sy)
	Center(Lines(#list), y + 30 - sy, "STTS_ZM_RowS")
	return y + 70, 60
end
PAGE.songs, PAGE.fav, PAGE.genre, PAGE.latest = SongsPage, SongsPage, SongsPage, SongsPage
PAGE.albums = function(wep, st, btns, sy, nav, lib)
	PageTitle(nav.title, sy)
	local y = 196
	local src = nav.kind == "recent" and lib.recent or lib.albums
	local items = {}
	for i, al in ipairs(src) do items[i] = AlbumItem(wep, st, al, nav.title) end
	if #items == 0 then Center("No Albums", y + 80 - sy, "STTS_ZM_H2", C.label) return y + 200, 60 end
	return y + Grid(wep, st, btns, items, y, sy) + 40, 60
end
PAGE.recent = PAGE.albums
PAGE.artists = function(wep, st, btns, sy, nav, lib)
	PageTitle(nav.title, sy)
	local y = 190
	local rows = {}
	for i, ar in ipairs(lib.artists) do
		rows[i] = {title = ar.name, art = ZM.ArtMat(ar.art), round = true, tap = function() UI.Push(st, "artist", ar.id, ar.name, "Artists") end}
	end
	if #rows == 0 then Center("No Artists", y + 80 - sy, "STTS_ZM_H2", C.label) return y + 200, 60 end
	return y + NavRows(wep, st, btns, rows, y, sy, 78) + 40, 60
end
PAGE.playlists = function(wep, st, btns, sy, nav, lib)
	PageTitle(nav.title, sy)
	local y = 190
	local rows = {}
	for i, p in ipairs(lib.playlists) do
		rows[i] = {title = p.name, sub = Lines(#p.songs), mosaic = p, tap = function() UI.Push(st, "playlist", p.id, p.name, "Playlists") end}
	end
	if #rows == 0 then
		Center("No Playlists", y + 80 - sy, "STTS_ZM_H2", C.label)
		return y + 200, 60
	end
	return y + NavRows(wep, st, btns, rows, y, sy, 96) + 40, 60
end
PAGE.genres = function(wep, st, btns, sy, nav, lib)
	PageTitle(nav.title, sy)
	local y = 190
	local rows = {}
	for i, g in ipairs(lib.genres) do rows[i] = {title = g.name, sub = Lines(#g.songs), tap = function() UI.Push(st, "genre", g.id, g.name, "Genres") end} end
	if #rows == 0 then Center("No Genres", y + 80 - sy, "STTS_ZM_H2", C.label) return y + 200, 60 end
	return y + NavRows(wep, st, btns, rows, y, sy, 74) + 40, 60
end
-- album: big cover, name, artist (red), genre · year, Play / Shuffle, numbered songs
local function Shadow(x, y, w, h, r, a)
	for i = 1, 6 do U.Round(r + i * 3, x - i * 3, y - i * 3 + 10, w + i * 6, h + i * 6, Color(0, 0, 0, (a or 9))) end
end
UI.Shadow = Shadow
PAGE.album = function(wep, st, btns, sy, nav, lib)
	local al = lib.byAlbum[nav.id]
	if not al then Center("Album not found", 300, "STTS_ZM_H2", C.label) return 400, 60 end
	local s = 270
	local ay = 112 - sy
	Shadow(W / 2 - s / 2, ay, s, s, 10)
	Art(ZM.ArtMat(al.art), W / 2 - s / 2, ay, s, 10)
	local y = 112 + s + 34
	U.T(U.Fit(al.name, "STTS_ZM_AlbT", W - 60), "STTS_ZM_AlbT", W / 2, y - sy, C.label)
	y = y + 36
	local ar = lib.byArtist[util.CRC(Low(al.artist))]
	local aid = NID()
	if ar then CB(btns, aid, 40, y - 18 - sy, W - 80, 36, function() UI.Push(st, "artist", ar.id, ar.name, al.name) end) end
	U.T(U.Fit(al.artist, "STTS_ZM_AlbA", W - 60), "STTS_ZM_AlbA", W / 2, y - sy, ACC)
	y = y + 32
	local info = {}
	if al.genre then info[#info + 1] = string.upper(al.genre) end
	if al.year then info[#info + 1] = tostring(al.year) end
	if #info > 0 then U.T(table.concat(info, " · "), "STTS_ZM_Hdr", W / 2, y - sy, C.label2) y = y + 28 end
	y = y + 18
	PlayButtons(wep, st, btns, al.songs, y - sy, "a:" .. al.id)
	y = y + 54 + 18
	Sep(PAD, y - sy, W - PAD)
	y = y + SongRows(wep, st, btns, al.songs, y, sy, {num = true, rowH = 62, tag = "a:" .. al.id})
	U.T(Lines(#al.songs) .. ", " .. Minutes(al.dur), "STTS_ZM_RowS", PAD, y + 30 - sy, C.label2, TEXT_ALIGN_LEFT)
	return y + 80, 330
end
PAGE.playlist = function(wep, st, btns, sy, nav, lib)
	local p = lib.byPl[nav.id]
	if not p then Center("Playlist not found", 300, "STTS_ZM_H2", C.label) return 400, 60 end
	local s = 270
	local ay = 112 - sy
	Shadow(W / 2 - s / 2, ay, s, s, 10)
	Mosaic(p, W / 2 - s / 2, ay, s, 10)
	local y = 112 + s + 34
	U.T(U.Fit(p.name, "STTS_ZM_AlbT", W - 60), "STTS_ZM_AlbT", W / 2, y - sy, C.label)
	y = y + 34
	local d = 0
	for _, x in ipairs(p.songs) do d = d + (x.dur or 0) end
	U.T("Playlist · " .. Lines(#p.songs), "STTS_ZM_Hdr", W / 2, y - sy, C.label2)
	y = y + 40
	PlayButtons(wep, st, btns, p.songs, y - sy, "p:" .. p.id)
	y = y + 54 + 18
	y = y + SongRows(wep, st, btns, p.songs, y, sy, {tag = "p:" .. p.id})
	U.T(Lines(#p.songs) .. ", " .. Minutes(d), "STTS_ZM_RowS", PAD, y + 30 - sy, C.label2, TEXT_ALIGN_LEFT)
	return y + 80, 330
end
PAGE.artist = function(wep, st, btns, sy, nav, lib)
	local ar = lib.byArtist[nav.id]
	if not ar then Center("Artist not found", 300, "STTS_ZM_H2", C.label) return 400, 60 end
	local s = 210
	local ay = 110 - sy
	Art(ZM.ArtMat(ar.art), W / 2 - s / 2, ay, s, 0, 1, true)
	local y = 110 + s + 40
	U.T(U.Fit(ar.name, "STTS_ZM_Big", W - 48), "STTS_ZM_Big", W / 2, y - sy, C.label)
	y = y + 46
	PlayButtons(wep, st, btns, ar.songs, y - sy, nil)
	y = y + 54 + 34
	if #ar.albums > 0 then
		Section("Albums", y - sy)
		y = y + 34
		local items = {}
		for i, al in ipairs(ar.albums) do
			local it = AlbumItem(wep, st, al, ar.name)
			it.sub = al.year and tostring(al.year) or Lines(#al.songs)
			items[i] = it
		end
		y = y + Grid(wep, st, btns, items, y, sy) + 20
	end
	Section("Songs", y - sy)
	y = y + 30
	y = y + SongRows(wep, st, btns, ar.songs, y, sy, {sub = function(x) return x.album end})
	return y + 60, 330
end
UI.PAGE = PAGE
-- what others see of the holder's pages: the title, grey rows
function UI.RemotePage(wep, st, btns, sy, nav)
	PageTitle(nav.title or "", sy)
	return 200 + Skeleton(200, sy, 9, nav.kind == "albums" and "grid" or "rows") + 40, 60
end

--[[---------------------------------------------------------------------------
	Now Playing (the sheet over the app): cover, title, scrubber, controls, volume,
	lyrics / Up Next. drawn from the phone (NW2) so the others see it as well
---------------------------------------------------------------------------]]
local WT = Color(255, 255, 255)
local function WA(a) return Color(255, 255, 255, a) end
-- background: a soft field of the cover colours (vertex colours, slowly moving)
local function ColorField(pal, y0)
	local t = RealTime() * 0.25
	local c = {}
	for i = 1, 9 do
		local a, b = pal[i], pal[(i % 9) + 1]
		local k = 0.5 + 0.5 * math.sin(t + i * 1.3)
		c[i] = {Lerp(k, a.r, b.r) * 0.62 + 8, Lerp(k, a.g, b.g) * 0.62 + 8, Lerp(k, a.b, b.b) * 0.62 + 10}
	end
	local xs, ys = {0, W / 2, W}, {y0, y0 + H / 2, y0 + H}
	render.SetColorMaterialIgnoreZ()
	mesh.Begin(MATERIAL_QUADS, 4)
	for j = 1, 2 do
		for i = 1, 2 do
			local function V(ii, jj)
				local col = c[(jj - 1) * 3 + ii]
				mesh.Position(Vector(xs[ii], ys[jj], 0))
				mesh.Color(col[1], col[2], col[3], 255)
				mesh.AdvanceVertex()
			end
			V(i, j) V(i + 1, j) V(i + 1, j + 1) V(i, j + 1)
		end
	end
	mesh.End()
end
--[[ fix55: the real Apple Music background: the COVER itself, four huge copies slowly
     turning and drifting over a field of its (saturated) colours, blurred into a soft
     moving glow (a small RT, gaussian blur, stretched = no bands). painted in PostRender
     (outside the phone drawing), ~30 times a second, 3 covers cached ]]
local NPArt = {}
do
	local BW, BH = 108, 240
	local slots, want = {}, {}
	local function Find(key) for _, s in ipairs(slots) do if s.key == key then return s end end end
	local function Take(key)
		local best
		for i = 1, 3 do
			local s = slots[i]
			if not s then
				local rt = GetRenderTargetEx("stts_zm_npbg55_" .. i, BW, BH, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGB888)
				s = {rt = rt, used = 0, mat = CreateMaterial("stts_zm_npbg55m_" .. i, "UnlitGeneric", {["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$ignorez"] = 1})}
				slots[i] = s
				best = s
				break
			end
			if not best or s.used < best.used then best = s end
		end
		best.key, best.at, best.ready = key, 0, false
		return best
	end
	-- a cover colour made vivid (the glow of Apple Music is saturated, never muddy)
	local function Vivid(c, k)
		local h, sat, v = ColorToHSV(Color(c.r, c.g, c.b))
		sat = math.min(1, sat * 1.45 + 0.06)
		v = math.Clamp(v * (k or 1), 0.18, 0.86)
		local o = HSVToColor(h, sat, v)
		return o.r, o.g, o.b
	end
	local DRIFT = { -- cx, cy, size (x BH), turn speed, alpha
		{0.25, 0.20, 1.30, 0.050, 255}, {0.80, 0.42, 1.15, -0.040, 215},
		{0.30, 0.72, 1.25, 0.034, 200}, {0.72, 0.96, 1.05, -0.060, 180},
	}
	local function Paint(s, mat, pal)
		local t = RealTime()
		local ar, ag, ab = 46, 46, 52
		if pal then ar, ag, ab = Vivid(pal[5], 0.45) end
		render.PushRenderTarget(s.rt)
			render.Clear(ar, ag, ab, 255)
			cam.Start2D()
				draw.NoTexture()
				if pal then -- the colour field under the covers (corners + middle)
					local spots = {1, 3, 7, 9, 5}
					for i, pi in ipairs(spots) do
						local r, g, b = Vivid(pal[pi], 0.9)
						local cx = BW * (((pi - 1) % 3) / 2 + 0.18 * math.sin(t * 0.23 + i * 1.9))
						local cy = BH * (math.floor((pi - 1) / 3) / 2 + 0.10 * math.cos(t * 0.19 + i * 2.7))
						surface.SetDrawColor(r, g, b, 200)
						surface.DrawTexturedRectRotated(cx, cy, BW * 0.9, BH * 0.55, (t * 9 + i * 40) % 360)
					end
				end
				if mat then
					surface.SetMaterial(mat)
					for i, d in ipairs(DRIFT) do
						local cx = BW * (d[1] + 0.14 * math.sin(t * 0.21 + i * 1.7))
						local cy = BH * (d[2] + 0.07 * math.cos(t * 0.17 + i * 2.3))
						local sz = BH * d[3]
						surface.SetDrawColor(255, 255, 255, d[5])
						surface.DrawTexturedRectRotated(cx, cy, sz, sz, (t * d[4] * 57.3 + i * 77) % 360)
					end
				end
			cam.End2D()
			render.BlurRenderTarget(s.rt, 6, 6, 4)
		render.PopRenderTarget()
	end
	-- draw the glow of key (nil = not painted yet: the caller draws a fallback)
	function NPArt.Draw(key, mat, pal, x, y, w, h)
		local now = RealTime()
		local wq = want[key]
		if not wq then wq = {} want[key] = wq end
		wq.mat, wq.pal, wq.seen = mat, pal, now
		local s = Find(key)
		if not (s and s.ready) then return false end
		s.used = now
		surface.SetMaterial(s.mat) surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(x, y, w, h)
		return true
	end
	hook.Add("PostRender", "STTS_ZMusicNPBg55", function()
		if SCR.InRV or next(want) == nil then return end
		local now = RealTime()
		for key, wq in pairs(want) do
			if now - wq.seen > 0.6 then want[key] = nil
			else
				local s = Find(key) or Take(key)
				s.used = math.max(s.used, wq.seen)
				if now - s.at >= 1 / 30 then
					s.at = now
					Paint(s, wq.mat, wq.pal)
					s.ready = true
				end
			end
		end
	end)
end
local function NPBg(n, y0, mat)
	local pal = mat and ZM.Palette(mat, n.key)
	local drawn = mat and NPArt.Draw(n.key, mat, pal, 0, y0, W, H)
	if not drawn then
		if pal then ColorField(pal, y0)
		else U.VGrad(0, y0, W, H, Color(76, 76, 84), Color(28, 28, 32)) end
	end
	-- a light scrim (white text stays readable on a bright cover), darker at the bottom
	U.R(0, y0, W, H, Color(0, 0, 0, 38))
	U.VGrad(0, y0 + H * 0.40, W, H * 0.60, Color(0, 0, 0, 0), Color(0, 0, 0, 120))
end
local function CircBtn(wep, st, btns, id, cx, cy, r, mat, gs, on, fn, bgA, col)
	if fn then U.Reg(btns, id, cx - r - 6, cy - r - 6, r * 2 + 12, r * 2 + 12, fn) end
	local k = U.HoverK(wep, id, st.sel == id)
	local a = (bgA or 0) + (U.Pressed(wep, st, id) and 60 or 30) * k
	if on then U.Circle(cx, cy, r, WA(235)) elseif a > 1 then U.Circle(cx, cy, r, WA(a)) end
	Ic(mat, cx, cy, gs, on and Color(40, 40, 44) or col or WT)
end
UI.CircBtn = CircBtn
-- lyrics: word wrap (UTF-8) for the big bold font
local wrapCache = {}
local function Wrap(text, font, w)
	local key = font .. w .. text
	if wrapCache[key] then return wrapCache[key] end
	surface.SetFont(font)
	local out = {}
	for para in string.gmatch(string.gsub(text, "\r", "") .. "\n", "(.-)\n") do
		para = string.Trim(para)
		if para == "" then
			if #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end
		else
			local line = ""
			for word in string.gmatch(para, "%S+") do
				local try = line == "" and word or (line .. " " .. word)
				if surface.GetTextSize(try) <= w then line = try
				else
					if line ~= "" then out[#out + 1] = line end
					line = word
					while surface.GetTextSize(line) > w and SCR.U8Starts do
						local cs = SCR.U8Starts(line)
						local n = #cs
						while n > 1 and surface.GetTextSize(SCR.U8Sub(line, cs, 1, n)) > w do n = n - 1 end
						out[#out + 1] = SCR.U8Sub(line, cs, 1, n)
						line = SCR.U8Sub(line, cs, n + 1, #cs)
					end
				end
			end
			if line ~= "" then out[#out + 1] = line end
		end
	end
	if table.Count(wrapCache) > 40 then wrapCache = {} end
	wrapCache[key] = out
	return out
end
local function Lyrics(key)
	local s = ZM.lib.byKey[key]
	if not s or not s.lyr then return end
	local t = file.Read(CACHE .. "/l_" .. key .. ".txt", "DATA")
	return t and t ~= "" and t or nil
end
-- the small header of the lyrics / queue modes (cover, title, artist)
local function MiniHead(wep, st, btns, n, mat, top, canFav, s)
	Art(mat, 30, top + 96, 76, 8)
	U.Reg(btns, 117, 20, top + 86, 96, 96, function() UI.Mode(st, Z.mode) end)
	Marquee(n.key ~= "" and n.title or "Not Playing", "STTS_ZM_Mini", 124, top + 120, W - 124 - 120, WT, 1)
	U.T(U.Fit(n.artist or "", "STTS_ZM_RowS", W - 124 - 120), "STTS_ZM_RowS", 124, top + 150, WA(165), TEXT_ALIGN_LEFT)
	if canFav then
		CircBtn(wep, st, btns, 104, W - 100, top + 134, 20, ZM.IsFav(n.key) and I.star or I.staro, 20, false,
			st.own and function() ZM.ToggleFav(n.key) end or nil, 40)
	end
	CircBtn(wep, st, btns, 105, W - 50, top + 134, 20, I.dots, 22, false, (st.own and s) and function() UI.SongMenu(wep, st, s, W - 50, top + 134, true) end or nil, 40)
end
function ZM.NP(wep, st, btns, k, view)
	local own = st.own
	local n = ZM.Now(wep)
	local mode = own and Z.mode or (view.n or 1)
	-- the sheet follows a drag down (own phone)
	local drag = own and Z.drag
	local top = (1 - k) * H
	if drag and drag.dy > 0 and drag.dy > math.abs(drag.dx) then top = top + drag.dy * 0.92 end
	if top > 2 then U.R(0, 0, W, top, Color(0, 0, 0, 110 * math.Clamp(k, 0, 1))) end
	local mat = ZM.KeyArt(n.key)
	NPBg(n, top, mat)
	local has = n.key ~= ""
	local s = own and ZM.lib.byKey[n.key] or nil
	-- grabber (tap = close)
	U.Round(3, W / 2 - 22, top + 58, 44, 6, WA(120))
	if own then U.Reg(btns, 102, W / 2 - 90, top + 34, 180, 50, function() UI.CloseNP(st) end) end
	-- drag the sheet down / swipe the cover sideways
	local zoneH = mode == 1 and 560 or 170
	U.Zone(btns, {kind = "zmnp", zm = "np", x = 0, y = top + 30, w = W, h = zoneH})
	if mode == 1 then
		if own then L.maxScroll = 0 end
		local pk = U.SpringK(wep, "zmart", n.on or not has, 0.5, 0.72)
		local big = Lerp(pk, 292, 364)
		local acx, acy = W / 2, top + 118 + 182
		if drag and math.abs(drag.dx) > math.abs(drag.dy) then acx = acx + drag.dx * 0.5 end
		local ax, ay = acx - big / 2, acy - big / 2
		for i = 1, 7 do U.Round(12 + i * 4, ax - i * 4, ay - i * 4 + 16 * pk, big + i * 8, big + i * 8, Color(0, 0, 0, 6 + 5 * pk)) end
		Art(mat, ax, ay, big, 12)
		-- title / artist, favourite + more
		Marquee(has and n.title or "Not Playing", "STTS_ZM_NPT", 36, top + 548, W - 36 - 130, WT, 2)
		U.T(U.Fit(n.artist or "", "STTS_ZM_NPA", W - 36 - 130), "STTS_ZM_NPA", 36, top + 584, WA(170), TEXT_ALIGN_LEFT)
		if s then
			CircBtn(wep, st, btns, 104, W - 104, top + 566, 21, ZM.IsFav(n.key) and I.star or I.staro, 21, false, function() ZM.ToggleFav(n.key) end, 40)
		end
		CircBtn(wep, st, btns, 105, W - 52, top + 566, 21, I.dots, 24, false, s and function() UI.SongMenu(wep, st, s, W - 52, top + 566, true) end or nil, 40)
	else
		MiniHead(wep, st, btns, n, mat, top, s ~= nil, s)
		local lt, lb = top + 196, top + 604
		if mode == 3 then
			-- shuffle / repeat / autoplay, then Playing Next
			local bw = math.floor((W - 60 - 24) / 3)
			local tg = {{114, I.shuffle, n.shuf, function() ZM.Act(wep, ACT.SHUF, not n.shuf) end},
				{115, n.rep == 2 and I.rep1 or I.rep, n.rep > 0, function() ZM.Act(wep, ACT.REP, (n.rep + 1) % 3) end},
				{116, I.inf, own and Z.auto or false, function() Z.auto = not Z.auto end}}
			for i, b in ipairs(tg) do
				local x = 30 + (i - 1) * (bw + 12)
				if own then U.Reg(btns, b[1], x, top + 194, bw, 46, b[4]) end
				local hk = U.HoverK(wep, b[1], st.sel == b[1])
				U.Round(12, x, top + 194, bw, 46, b[3] and WA(235) or WA(40 + 30 * hk))
				Ic(b[2], x + bw / 2, top + 217, 24, b[3] and Color(40, 40, 44) or WT)
			end
			U.T("Playing Next", "STTS_ZM_Card", 30, top + 274, WT, TEXT_ALIGN_LEFT)
			local q, qi = ZM.Queue(wep)
			local items = q and q.items or {}
			lt = top + 300
			local rh = 66
			local up = {}
			for i = qi + 1, #items do up[#up + 1] = {i = i, it = items[i]} end
			if own then L.maxScroll = math.max(0, (#up * rh - (lb - lt)) / STEP) end
			local sy = (st.scroll or 0) * STEP
			U.Clip(0, lt, W, lb - lt)
			local first = math.max(1, math.floor(sy / rh) + 1)
			for j = first, math.min(#up, first + math.ceil((lb - lt) / rh) + 1) do
				local e = up[j]
				local ry = lt + (j - 1) * rh - sy
				local id = 120 + (j % 40)
				local y0, y1 = math.max(ry, lt), math.min(ry + rh, lb)
				if own and y1 - y0 > 10 then U.Reg(btns, id, 0, y0, W, y1 - y0, function() ZM.Act(wep, ACT.JUMP, e.i) end) end
				local hk = U.HoverK(wep, id, st.sel == id)
				if hk > 0.01 then U.R(0, ry, W, rh, WA(24 * hk)) end
				Art(ZM.KeyArt(e.it.key), 30, ry + 8, 50, 6)
				U.T(U.Fit(e.it.title, "STTS_ZM_Row", W - 130), "STTS_ZM_Row", 96, ry + rh / 2 - 12, WT, TEXT_ALIGN_LEFT)
				U.T(U.Fit(e.it.artist, "STTS_ZM_RowS", W - 130), "STTS_ZM_RowS", 96, ry + rh / 2 + 15, WA(150), TEXT_ALIGN_LEFT)
				Ic(I.list, W - 40, ry + rh / 2, 22, WA(110))
			end
			U.Unclip()
			U.Zone(btns, {kind = "scroll", x = 0, y = lt, w = W, h = lb - lt, step = STEP})
		else
			-- lyrics (the USLT tag of the file), the line of the moment is white
			local text = Lyrics(n.key)
			if not text then
				U.T("Lyrics aren't available", "STTS_ZM_H2", W / 2, top + 360, WA(200))
				U.T("for this song.", "STTS_ZM_H2", W / 2, top + 398, WA(200))
				if own then L.maxScroll = 0 end
			else
				local lines = Wrap(text, "STTS_ZM_Lyr", W - 64)
				local lh = 46
				local frac = n.dur > 0 and n.pos / n.dur or 0
				local cur = math.Clamp(math.floor(frac * #lines) + 1, 1, #lines)
				if own then
					L.maxScroll = math.max(0, (#lines * lh - (lb - lt) + 60) / STEP)
					if L.touch then Z.lyrUser = RealTime() end
					if not L.touch and RealTime() - (Z.lyrUser or -10) > 4 then
						local want = math.Clamp(((cur - 3) * lh) / STEP, 0, L.maxScroll)
						if math.abs((L.scroll or 0) - want) > 0.05 and not L.scrollGo then L.scrollGo = want end
					end
				end
				local sy = (st.scroll or 0) * STEP
				U.Clip(0, lt, W, lb - lt)
				local first = math.max(1, math.floor(sy / lh))
				for i = first, math.min(#lines, first + math.ceil((lb - lt) / lh) + 2) do
					local ly = lt + 20 + (i - 1) * lh - sy
					U.T(lines[i], "STTS_ZM_Lyr", 32, ly, i == cur and WT or WA(80), TEXT_ALIGN_LEFT)
				end
				U.Unclip()
				U.Zone(btns, {kind = "scroll", x = 0, y = lt, w = W, h = lb - lt, step = STEP})
			end
		end
	end
	-- scrubber
	local sx, sw, sy0 = 36, W - 72, top + 640
	local scrub = own and Z.scrub or nil
	local frac = scrub or (n.dur > 0 and n.pos / n.dur or 0)
	local held = scrub ~= nil
	local th = held and 12 or 7
	U.Round(th / 2, sx, sy0 - th / 2, sw, th, WA(70))
	if frac > 0 then U.Round(th / 2, sx, sy0 - th / 2, math.max(th, sw * frac), th, WA(held and 255 or 200)) end
	if own and has then
		local b = U.Reg(btns, 106, sx - 14, sy0 - 26, sw + 28, 52, nil)
		b.sx, b.sw = sx, sw
		b.slider = function(v) Z.scrub = v end
	end
	local pos = held and frac * n.dur or n.pos
	local tc = WA(held and 230 or 150)
	U.T(Dur(pos), "STTS_ZM_Time", sx, sy0 + 26, tc, TEXT_ALIGN_LEFT)
	U.T(has and ("-" .. Dur(math.max(0, n.dur - pos))) or "--:--", "STTS_ZM_Time", sx + sw, sy0 + 26, tc, TEXT_ALIGN_RIGHT)
	local cs = has and ZM.ChanState(wep) or "ok"
	if cs ~= "ok" then
		local pr = ZM.Progress(n.key)
		U.T(pr and string.format("Loading %d%%", pr * 100) or "Loading…", "STTS_ZM_Time", W / 2, sy0 + 26, WA(150))
	end
	-- transport
	local ty = top + 748
	local dim = has and WT or WA(110)
	CircBtn(wep, st, btns, 107, W / 2 - 118, ty, 40, I.back, 50, false, (own and has) and function() ZM.Act(wep, ACT.PREV) end or nil, 0, dim)
	CircBtn(wep, st, btns, 108, W / 2, ty, 44, n.on and I.pause or I.play, 60, false, (own and has) and function() ZM.Act(wep, ACT.PLAY, not n.on) end or nil, 0, dim)
	CircBtn(wep, st, btns, 109, W / 2 + 118, ty, 40, I.fwd, 50, false, (own and has) and function() ZM.Act(wep, ACT.NEXT) end or nil, 0, dim)
	-- volume (the phone volume, the same as in the Control Centre)
	local vy, vx, vw = top + 846, 72, W - 144
	local vol = SCR.Level and SCR.Level(wep, "vol") or 1
	local vh = own and L.touch and L.touch.slider and L.touch.slider.id == 110
	local vth = vh and 12 or 7
	Ic(I.spk, 40, vy, 20, WA(170))
	Ic(I.spk3, W - 40, vy, 28, WA(170))
	U.Round(vth / 2, vx, vy - vth / 2, vw, vth, WA(70))
	if vol > 0 then U.Round(vth / 2, vx, vy - vth / 2, math.max(vth, vw * vol), vth, WA(vh and 255 or 200)) end
	if own then
		local b = U.Reg(btns, 110, vx - 14, vy - 26, vw + 28, 52, nil)
		b.sx, b.sw = vx, vw
		b.slider = function(v) if SCR.SetLevel then SCR.SetLevel(wep, "vol", v) Z.volHeld = true end end
	end
	-- lyrics / Up Next (fix61: no AirPlay button: there is nothing to stream to, it only
	-- showed a "Playing on this phone's speaker" message)
	local by = top + 910
	CircBtn(wep, st, btns, 111, W / 2 - 90, by, 26, I.quote, 26, mode == 2, own and function() UI.Mode(st, 2) end or nil)
	CircBtn(wep, st, btns, 113, W / 2 + 90, by, 26, I.list, 24, mode == 3, own and function() UI.Mode(st, 3) end or nil)
	-- a tap anywhere else on the sheet does nothing (not the page behind it)
	if own then U.Reg(btns, 101, 0, top, W, H - 48 - top, function() end) end
end
-- release of the scrubber / the volume, drag of the sheet (own phone)
function ZM.NPInput(wep, st)
	local t = L.touch
	local sl = t and t.slider and t.slider.id
	if Z.scrub and sl ~= 106 then
		local n = ZM.Now(wep)
		if n.dur > 0 then ZM.Act(wep, ACT.SEEK, Z.scrub * n.dur) end
		Z.scrub = nil
	end
	if Z.volHeld and sl ~= 110 then Z.volHeld = nil if SCR.FlushLevel then SCR.FlushLevel(true) end end
	if t and t.zone and t.zone.zm == "np" then
		if t.moved then Z.drag = {dx = (L.ux or 0) - t.x0, dy = (L.uy or 0) - t.y0} end
	elseif Z.drag then
		local d = Z.drag
		Z.drag = nil
		if d.dy > 150 and d.dy > math.abs(d.dx) then
			UI.CloseNP(st)
			local s = wep.STTS_SK and wep.STTS_SK.zmnp
			if s then s.x = math.Clamp(1 - d.dy / H, 0, 1) s.v = -2 end
		elseif math.abs(d.dx) > 70 and math.abs(d.dx) > math.abs(d.dy) and Z.mode == 1 then
			ZM.Act(wep, d.dx < 0 and ACT.NEXT or ACT.PREV)
		end
	end
end

--[[---------------------------------------------------------------------------
	the tab bar, the mini player, the whole app
---------------------------------------------------------------------------]]
local TABS = {{"Home", "house"}, {"New", "grid"}, {"Library", "stack"}, {"Search", "search"}} -- fix61: no Radio
local function TabBar(wep, st, btns, tab)
	local y = H - TAB_H
	U.R(0, y, W, TAB_H, C.bar)
	U.R(0, y, W, 1, C.sep)
	local cw = W / #TABS
	for i, t in ipairs(TABS) do
		local x = (i - 1) * cw
		local id = 11 + i
		U.Reg(btns, id, x, y, cw, 66, function() UI.Tab(st, i) end)
		local col = i == tab and ACC or C.gray
		local hk = U.HoverK(wep, id, st.sel == id)
		Ic(I[t[2]], x + cw / 2, y + 28, 30 + 2 * hk, col)
		U.T(t[1], "STTS_ZM_Tab", x + cw / 2, y + 57, col)
	end
end
local function Mini(wep, st, btns)
	local n = ZM.Now(wep)
	local has = n.key ~= ""
	local x, y, w, h = 10, MINI_Y, W - 20, MINI_H
	for i = 1, 4 do U.Round(16 + i * 2, x - i * 2, y - i * 2 + 3, w + i * 4, h + i * 4, Color(0, 0, 0, 10)) end
	local light = (C.bg and C.bg.r or 0) > 128
	U.Round(16, x, y, w, h, light and Color(247, 247, 248, 252) or Color(34, 34, 36, 252))
	if st.own and has then
		U.Reg(btns, 18, x + w - 120, y, 60, h, function() ZM.Act(wep, ACT.PLAY, not n.on) end)
		U.Reg(btns, 19, x + w - 60, y, 60, h, function() ZM.Act(wep, ACT.NEXT) end)
		U.Reg(btns, 17, x, y, w - 120, h, function() UI.OpenNP(st) end)
	end
	local hk = U.HoverK(wep, 17, st.sel == 17)
	if hk > 0.01 then U.Round(16, x, y, w - 120, h, SCR.Ink((U.Pressed(wep, st, 17) and 30 or 14) * hk)) end
	Art(ZM.KeyArt(n.key), x + 10, y + 10, h - 20, 6)
	Marquee(has and n.title or "Not Playing", "STTS_ZM_Mini", x + h + 6, y + h / 2, w - h - 6 - 128, has and C.label or C.label2, 3)
	local col = has and C.label or (C.label3 or C.label2)
	for _, b in ipairs({{18, x + w - 90, n.on and I.pause or I.play, 30}, {19, x + w - 34, I.fwd, 32}}) do
		local bk = U.HoverK(wep, b[1], st.sel == b[1])
		if bk > 0.01 then U.Circle(b[2], y + h / 2, 25, SCR.Ink((U.Pressed(wep, st, b[1]) and 40 or 20) * bk)) end
		Ic(b[3], b[2], y + h / 2, b[4], col)
	end
end
-- a short note over the mini player ("Playing Next")
local function HUDDraw()
	local h = Z.hud
	if not h then return end
	local t = RealTime() - h.at
	if t > 1.8 then Z.hud = nil return end
	local a = math.Clamp(math.min(t / 0.15, (1.8 - t) / 0.3), 0, 1)
	surface.SetFont("STTS_ZM_RowS")
	local tw = surface.GetTextSize(h.text)
	local w = tw + 40
	local light = (C.bg and C.bg.r or 0) > 128
	U.Round(22, W / 2 - w / 2, MINI_Y - 62, w, 44, light and Color(30, 30, 32, 230 * a) or Color(72, 72, 76, 235 * a))
	U.T(h.text, "STTS_ZM_RowS", W / 2, MINI_Y - 40, Color(255, 255, 255, 255 * a))
end
-- what the holder looks at, for the others: tab | Now Playing mode | page kind | title | back
local function ViewString(lv)
	local nav = lv > 1 and Z.nav[lv] or nil
	local function F(s) return (string.gsub(string.sub(tostring(s or ""), 1, 60), "|", "/")) end
	return Z.tab .. "|" .. (Z.np and Z.mode or 0) .. "|" .. F(nav and nav.kind or "") .. "|" .. F(nav and nav.title) .. "|" .. F(nav and nav.back)
end
local viewCache = {}
function UI.ViewOf(wep)
	local v = wep:GetNW2String("ZMView", "")
	local c = viewCache[v]
	if c then return c end
	local p = string.Explode("|", v)
	c = {tab = math.Clamp(tonumber(p[1] or "") or 1, 1, #TITLES), n = math.Clamp(tonumber(p[2] or "") or 0, 0, 3), kind = p[3] or "", title = p[4] or "", back = p[5] or ""}
	if table.Count(viewCache) > 64 then viewCache = {} end
	viewCache[v] = c
	return c
end

function ZM.App(wep, st, btns)
	UI.ResetIds()
	local own = st.own
	local lib = own and ZM.lib or ZM.remoteLib
	local view = (not own) and UI.ViewOf(wep) or nil
	local lv = LV[st.app] or 1
	local real = own and (LV[L.app] or 1) == lv
	if real then
		if Z.lastLv and lv < Z.lastLv then RestoreScroll(lv) end
		Z.lastLv = lv
		if lv > 1 and not Z.nav[lv] then U.SetApp(st, APP) lv = 1 end
		ZM.NPInput(wep, st)
	end
	if own and (Z.tab or 1) > #TITLES then Z.tab = #TITLES end -- fix61: one tab less (Radio)
	local tab = own and Z.tab or view.tab
	local npOn
	if own then npOn = Z.np else npOn = view.n > 0 end
	local k = U.SpringK(wep, "zmnp", npOn, 0.45, 0.95)
	if own and not real then k = 0 end -- the page behind an edge swipe
	st.zmDark = k > 0.6
	U.R(0, 0, W, H, C.bg or BLACK)
	local menu = own and Z.menu
	local pb = (k > 0.02 or menu) and {} or btns
	if k < 0.985 then
		VIS.top, VIS.bot = lv == 1 and 100 or 104, MINI_Y - 4
		local sy = ((own and Z.np) and (Z.pageScroll or 0) or (st.scroll or 0)) * STEP
		local nav = lv > 1 and (own and Z.nav[lv] or (view and {kind = view.kind, title = view.title, back = view.back})) or nil
		local h, from
		if lv == 1 then h, from = TAB[tab](wep, st, pb, sy, lib), 74
		elseif own and nav then h, from = (PAGE[nav.kind] or PAGE.songs)(wep, st, pb, sy, nav, lib)
		else h, from = UI.RemotePage(wep, st, pb, sy, nav or {}) end
		if own and k <= 0.02 and real then L.maxScroll = math.max(0, ((h or 0) - (MINI_Y - 30)) / STEP) end
		U.Zone(pb, {kind = "scroll", x = 0, y = 0, w = W, h = MINI_Y, step = STEP})
		NavBar(wep, st, pb, lv == 1 and TITLES[tab] or (nav and nav.title) or "", sy, from or 60, lv > 1 and ((nav and nav.back ~= "" and nav.back) or "Back") or nil)
		TabBar(wep, st, pb, tab)
		Mini(wep, st, pb)
		HUDDraw()
	end
	if menu and k <= 0.02 then UI.DrawMenu(wep, st, btns) end
	if k > 0.001 then ZM.NP(wep, st, k > 0.02 and btns or {}, k, view or {n = Z.mode}) end
	if real then ZM.SendView(wep, ViewString(lv)) end
end
function SCR.ZMForcedDark(st) return LV[st.app] ~= nil and st.zmDark == true end

-- the edge swipe goes back only while Now Playing is closed; autoplay (the infinity button)
hook.Add("Think", "STTS_ZMusicUI", function()
	local sb = SCR.SettingsBack
	if sb then
		local open = Z.np
		sb[G.APP_MUSIC2] = (not open) and G.APP_MUSIC or nil
		sb[G.APP_MUSIC3] = (not open) and G.APP_MUSIC2 or nil
		sb[G.APP_MUSIC4] = (not open) and G.APP_MUSIC3 or nil
	end
	local wep = L.wep
	local lp = LocalPlayer()
	if not (Z.auto and IsValid(wep) and IsValid(lp) and wep:GetOwner() == lp and lp:GetActiveWeapon() == wep and #ZM.lib.songs > 0) then return end
	local n = wep:GetNW2Int("ZMQn", 0)
	if n == 0 or wep:GetNW2Bool("ZMOn", false) or wep:GetNW2Int("ZMQi", 0) < n or wep:GetNW2Int("ZMRep", 0) ~= 0 then return end
	local dur, pos = wep:GetNW2Float("ZMDur", 0), wep:GetNW2Float("ZMPos", 0)
	local tag = wep:GetNW2String("ZMKey", "") .. "@" .. wep:GetNW2Float("ZMAt", 0)
	if dur > 0 and pos >= dur - 0.5 and ZM.autoTried ~= tag then
		ZM.autoTried = tag
		ZM.PlayList(wep, ZM.lib.songs, 1, true)
	end
end)

--[[---------------------------------------------------------------------------
	the Control Centre (cl_phone_shade.lua): the Now Playing tile + its big player
---------------------------------------------------------------------------]]
function SCR.ZMTile(K, wep, st, btns, x, y, big, active, hov)
	local n = ZM.Now(wep)
	if n.key == "" then return false end
	local own = st.own
	local cyb = y + big - 42
	local xs = {x + big * 0.22, x + big * 0.5, x + big * 0.78}
	if active and own then
		U.Reg(btns, 102, xs[1] - 28, cyb - 28, 56, 56, function() ZM.Act(wep, ACT.PREV) end)
		U.Reg(btns, 103, xs[2] - 28, cyb - 28, 56, 56, function() ZM.Act(wep, ACT.PLAY, not n.on) end)
		U.Reg(btns, 104, xs[3] - 28, cyb - 28, 56, 56, function() ZM.Act(wep, ACT.NEXT) end)
		U.Reg(btns, K.ID_NP, x, y, big, big, function() SCR.L.zmenu = true end)
	end
	K.GlassRound(U, 38, x, y, big, big, hov and K.MODH or K.MOD)
	Art(ZM.KeyArt(n.key), x + 20, y + 20, 50, 10)
	K.ClipTo(x + 16, y + 74, x + big - 12, y + 128)
	U.T(U.Fit(n.title, "STTS_I_Status", big - 40), "STTS_I_Status", x + 22, y + 92, WHITE, TEXT_ALIGN_LEFT)
	U.T(U.Fit(n.artist, "STTS_I_Cap", big - 40), "STTS_I_Cap", x + 22, y + 116, K.DIM, TEXT_ALIGN_LEFT)
	K.NoClip()
	for i, b in ipairs({{102, I.back, 30}, {103, n.on and I.pause or I.play, 28}, {104, I.fwd, 30}}) do
		local pk = U.HoverK(wep, "cczm" .. b[1], st.sel == b[1])
		if pk > 0.01 then U.Circle(xs[i], cyb, 24, Color(255, 255, 255, (U.Pressed(wep, st, b[1]) and 50 or 26) * pk)) end
		Ic(b[2], xs[i], cyb, b[3], WHITE)
	end
	return true
end
-- the expanded player (a tap on the tile): cover, title, scrubber, controls, Up Next
function SCR.ZMPlatter(K, wep, st, btns, mk, fx, fy)
	local n = ZM.Now(wep)
	local own = st.own
	local px, pw, py = 24, W - 48, 128
	local rows = 5
	local ph = 350 + rows * 58 + 16
	local live = mk > 0.97 and own
	local cx, cy = px + pw / 2, py + ph / 2
	K.PushM(cx, cy, Lerp(mk, 0.4, 1), (fx - cx) * (1 - mk), (fy - cy) * (1 - mk), mk * 1.7)
	K.BG(K.SH.b1)
	U.Round(38, px, py, pw, ph, K.MENU)
	K.BG(0.16)
	if U.RoundRim then U.RoundRim(38, px, py, pw, ph, 1.5, K.RIM) end
	local has = n.key ~= ""
	Art(ZM.KeyArt(n.key), px + 24, py + 24, 96, 12)
	K.ClipTo(px + 134, py + 30, px + pw - 70, py + 116)
	U.T(U.Fit(has and n.title or "Not Playing", "STTS_I_BodyB", pw - 210), "STTS_I_BodyB", px + 138, py + 56, WHITE, TEXT_ALIGN_LEFT)
	U.T(U.Fit(n.artist or "", "STTS_I_Sub", pw - 210), "STTS_I_Sub", px + 138, py + 88, K.DIM, TEXT_ALIGN_LEFT)
	K.NoClip()
	-- scrubber
	local sx, sw, sy = px + 26, pw - 52, py + 154
	local L = SCR.L
	if Z.ccScrub and not (L.touch and L.touch.slider and L.touch.slider.id == 183) then
		if n.dur > 0 then ZM.Act(wep, ACT.SEEK, Z.ccScrub * n.dur) end
		Z.ccScrub = nil
	end
	local scrub = own and Z.ccScrub or nil
	local frac = scrub or (n.dur > 0 and n.pos / n.dur or 0)
	local th = scrub and 12 or 7
	U.Round(th / 2, sx, sy - th / 2, sw, th, Color(255, 255, 255, 60))
	if frac > 0 then U.Round(th / 2, sx, sy - th / 2, math.max(th, sw * frac), th, Color(255, 255, 255, scrub and 255 or 200)) end
	if live and has then
		local b = U.Reg(btns, 183, sx - 12, sy - 24, sw + 24, 48, nil)
		b.sx, b.sw = sx, sw
		b.slider = function(v) Z.ccScrub = v end
	end
	local pos = scrub and frac * n.dur or n.pos
	U.T(Dur(pos), "STTS_ZM_Time", sx, sy + 26, K.DIM, TEXT_ALIGN_LEFT)
	U.T(has and ("-" .. Dur(math.max(0, n.dur - pos))) or "--:--", "STTS_ZM_Time", sx + sw, sy + 26, K.DIM, TEXT_ALIGN_RIGHT)
	-- transport
	local ty = py + 238
	for _, b in ipairs({{180, cx - 104, I.back, 44, ACT.PREV}, {181, cx, n.on and I.pause or I.play, 52, ACT.PLAY}, {182, cx + 104, I.fwd, 44, ACT.NEXT}}) do
		if live and has then U.Reg(btns, b[1], b[2] - 38, ty - 38, 76, 76, function() ZM.Act(wep, b[5], not n.on) end) end
		local pk = U.HoverK(wep, "cczm" .. b[1], st.sel == b[1])
		if pk > 0.01 then U.Circle(b[2], ty, 36, Color(255, 255, 255, (U.Pressed(wep, st, b[1]) and 50 or 24) * pk)) end
		Ic(b[3], b[2], ty, b[4], has and WHITE or K.DIM2)
	end
	U.R(px + 24, py + 296, pw - 48, 1, K.SEP)
	-- Up Next (+ shuffle / repeat)
	U.T("Up Next", "STTS_I_BodyB", px + 26, py + 326, WHITE, TEXT_ALIGN_LEFT)
	for i, b in ipairs({{184, I.shuffle, n.shuf, function() ZM.Act(wep, ACT.SHUF, not n.shuf) end},
		{185, n.rep == 2 and I.rep1 or I.rep, n.rep > 0, function() ZM.Act(wep, ACT.REP, (n.rep + 1) % 3) end}}) do
		local bx = px + pw - 120 + (i - 1) * 54
		if live and has then U.Reg(btns, b[1], bx - 24, py + 302, 48, 48, b[4]) end
		local pk = U.HoverK(wep, "cczm" .. b[1], st.sel == b[1])
		U.Circle(bx, py + 326, 20, b[3] and Color(255, 255, 255, 230) or Color(255, 255, 255, 36 + 30 * pk))
		Ic(b[2], bx, py + 326, 20, b[3] and Color(30, 30, 32) or WHITE)
	end
	local q, qi = ZM.Queue(wep)
	local items = q and q.items or {}
	local shown = 0
	for i = qi + 1, #items do
		if shown >= rows then break end
		shown = shown + 1
		local it = items[i]
		local ry = py + 350 + (shown - 1) * 58
		local id = 185 + shown
		if live then U.Reg(btns, id, px, ry, pw, 58, function() ZM.Act(wep, ACT.JUMP, i) end) end
		local hk = U.HoverK(wep, "cczm" .. id, st.sel == id)
		if hk > 0.01 then U.R(px, ry, pw, 58, Color(255, 255, 255, (U.Pressed(wep, st, id) and 46 or K.MHOV.a) * hk)) end
		Art(ZM.KeyArt(it.key), px + 24, ry + 7, 44, 6)
		K.ClipTo(px + 80, ry, px + pw - 20, ry + 58)
		U.T(U.Fit(it.title, "STTS_I_Sub", pw - 110), "STTS_I_Sub", px + 82, ry + 19, WHITE, TEXT_ALIGN_LEFT)
		U.T(U.Fit(it.artist, "STTS_I_Cap", pw - 110), "STTS_I_Cap", px + 82, ry + 41, K.DIM, TEXT_ALIGN_LEFT)
		K.NoClip()
	end
	if live then U.Reg(btns, 179, px, py, pw, ph, function() end) end
	K.Pop()
	return live
end

--[[ the home screen icon (next to Settings), registration ]]
local function HomeIcon(wep, st, btns)
	local size = 84
	local gap = (W - 28 - size * 4) / 5
	local x, y = 14 + gap * 2 + size, 112
	wep.STTS_IconRect = wep.STTS_IconRect or {}
	wep.STTS_IconRect[APP] = {x = x, y = y, w = size, h = size}
	U.Reg(btns, 6, x, y, size, size, function() wep.STTS_OpenFrom = nil U.SetApp(st, APP) end)
	local hi = U.IconHi and U.IconHi(wep, st, 6) or 0
	if wep.STTS_HideIcon ~= APP then
		if not appIcon:IsError() then
			surface.SetMaterial(appIcon) surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(x, y, size, size)
			if hi > 0 then surface.SetDrawColor(0, 0, 0, 92 * hi) surface.DrawTexturedRect(x, y, size, size) end
		else
			U.Round(size * 0.23, x, y, size, size, ACC)
			Ic(I.note2, x + size / 2, y + size / 2, size * 0.5, WHITE)
		end
	end
	U.T("ZMusic", "STTS_I_Cap", x + size / 2, y + size + 16, C.label)
end
local function Register()
	local APPS = SCR.APPS
	if not APPS then return end
	for _, a in ipairs(APP_OF) do APPS[a] = ZM.App end
	if SCR.APP_ICON then SCR.APP_ICON[APP] = appIcon end
	if SCR.ROOT_ICON then for i = 2, 4 do SCR.ROOT_ICON[APP_OF[i]] = APP end end
	if SCR.LEVEL then for i = 1, 4 do SCR.LEVEL[APP_OF[i]] = i end end
	SCR.HomeExtras = SCR.HomeExtras or {}
	SCR.HomeExtras.zmusic = HomeIcon
end
Register()
hook.Add("Think", "STTS_ZMusicApps", function()
	local A = SCR.APPS
	if A and A[APP] ~= ZM.App then Register() end
end)

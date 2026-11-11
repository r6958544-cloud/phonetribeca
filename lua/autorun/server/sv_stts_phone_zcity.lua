--[[---------------------------------------------------------------------------
	ZPhone for Z-City (standalone addon) - server loader.
	* lua/stts_phone/*  : the phone itself (was part of the ZHunter game mode)
	* content           : 3 phone models, their materials, icons, ringtones, alarm sounds
---------------------------------------------------------------------------]]
local CLIENT_FILES = {
	"cl_calls.lua",          -- call state, ringback / ring sounds, F6 / F7, HUD text
	"cl_phone.lua",          -- 911 operator console (spectators)
	"cl_phone_screen.lua",   -- everything drawn on the phone display
	"cl_phone_settings.lua", -- Settings app
	"cl_phone_shade.lua",    -- control centre, flashlight, volume
	"cl_phone_music.lua",    -- ZMusic (fix54): player for your own mp3s, heard around the phone
	"cl_phone_home.lua",     -- home screen (fix55): long press -> jiggle, drag icons like on iPhone
	"cl_phone_clock.lua",    -- Clock app (fix55): alarms, world clock, stopwatch, timers, ringing screen
	"cl_phone_lock.lua",     -- lock screen (fix58): iPhone-like, locks when the phone leaves the hand
	"cl_phone_botphoto.lua", -- stts_phone_botphoto (fix54): renders a bot's photo
	"cl_compat.lua",         -- hooks into vanilla Z-City (voice, camera, selfie)
}
local SERVER_FILES = {
	"sv_phone.lua",          -- numbers, 911, phone-to-phone calls, voice / chat over the line
	"sv_phone_chat.lua",     -- TeleChat (text messages)
	"sv_phone_media.lua",    -- photos / videos
	"sv_phone_settings.lua", -- per-phone settings
	"sv_phone_clock.lua",    -- Clock (fix55): alarms / snooze / timers / stopwatch per phone
	"sv_phone_lock.lua",     -- lock screen (fix58): locked / unlocked per phone
	"sv_phone_music.lua",    -- ZMusic (fix54): what each phone plays, song transfer
	"sv_phone_botphoto.lua", -- stts_phone_botphoto (fix54): a bot sends you a photo
	"sv_compat.lua",         -- Z-City rounds, phone on spawn, chat relay
	"sv_phone_ear.lua",      -- fix63: the phone's ear, the sounds only the server plays go to the filming client
}
for _, f in ipairs(CLIENT_FILES) do AddCSLuaFile("stts_phone/" .. f) end
AddCSLuaFile("autorun/client/zz_stts_phone_zcity.lua") -- autorun/client is sent anyway, just to be sure
AddCSLuaFile("autorun/client/cl_stts_phone_ear63.lua") -- fix63
for _, f in ipairs(SERVER_FILES) do include("stts_phone/" .. f) end

--[[ content. published the content on the Workshop? put its ID here and the
     clients get it from there (much faster than downloading from the server) ]]
local WORKSHOP_ID = ""
if WORKSHOP_ID ~= "" then
	resource.AddWorkshop(WORKSHOP_ID)
else
	for _, f in ipairs({
		"materials/models/stts/iph18/iph18_body.vmt",
		"materials/models/stts/iph18/iph18_body.vtf",
		"materials/models/stts/iph18/iph18_body_n.vtf",
		"materials/models/stts/iph18/iph18_body_paint.vmt",
		"materials/models/stts/iph18/iph18_body_paint.vtf",
		"materials/models/stts/iph18/iph18_screen.vmt",
		"materials/models/stts/iph18/iph18_screen_off.vtf",
		"materials/models/stts/pix6/pix6_body.vmt",
		"materials/models/stts/pix6/pix6_body.vtf",
		"materials/models/stts/pix6/pix6_body_n.vtf",
		"materials/models/stts/pix6/pix6_body_paint.vmt",
		"materials/models/stts/pix6/pix6_body_paint.vtf",
		"materials/models/stts/pix6/pix6_screen.vmt",
		"materials/models/stts/pix6/pix6_screen_off.vtf",
		"materials/models/stts/vivo/vivo_body.vmt",
		"materials/models/stts/vivo/vivo_body.vtf",
		"materials/models/stts/vivo/vivo_body_n.vtf",
		"materials/models/stts/vivo/vivo_body_paint.vmt",
		"materials/models/stts/vivo/vivo_body_paint.vtf",
		"materials/models/stts/vivo/vivo_decal.vmt",
		"materials/models/stts/vivo/vivo_decal.vtf",
		"materials/models/stts/vivo/vivo_screen.vmt",
		"materials/models/stts/vivo/vivo_screen_off.vtf",
		"materials/stts/app_phone.png",
		"materials/stts/cc_camera.png",
		"materials/stts/cc_dark.png", -- fix61 (Framework7 Icons, MIT)
		"materials/stts/cc_alarm.png", -- fix61 (Framework7 Icons, MIT)
		"materials/stts/cc_moon.png",
		"materials/stts/cc_next.png",
		"materials/stts/cc_play.png",
		"materials/stts/cc_prev.png",
		"materials/stts/cc_rotlock.png",
		"materials/stts/cc_speaker.png",
		"materials/stts/cc_sun.png",
		"materials/stts/cc_timer.png",
		"materials/stts/cc_wifi.png",
		"materials/stts/cc_wifi1.png",
		"materials/stts/cc_wifi2.png",
		"materials/stts/cursor_arrow.png",
		"materials/stts/ios_airplane.png",
		"materials/stts/ios_camera.png",
		"materials/stts/ios_flash.png",
		"materials/stts/ios_flip.png",
		"materials/stts/ios_gallery.png",
		"materials/stts/ios_music.png",
		"materials/stts/ios_phone.png",
		"materials/stts/ios_settings.png",
		"materials/stts/ios_telechat.png",
		"materials/stts/ios_torch.png",
		"materials/stts/ios_video.png",
		"materials/stts/lk_camera.png",
		"materials/stts/lk_lock.png",
		"materials/stts/lk_torch.png",
		"materials/stts/lk_unlock.png",
		"materials/stts/lk_wp_18pro_black.jpg",
		"materials/stts/lk_wp_18pro_burgundy.jpg",
		"materials/stts/lk_wp_18pro_glacier.jpg",
		"materials/stts/lk_wp_18pro_silver.jpg",
		"materials/stts/lk_wp_ios27_dark.jpg",
		"materials/stts/lk_wp_ios27_light.jpg",
		-- fix61: wallpapers of other phones (Pixel / Galaxy / Xiaomi, see ASSET_CREDITS.txt)
		"materials/stts/lk_wp_pixel_blue.jpg",
		"materials/stts/lk_wp_pixel_sage.jpg",
		"materials/stts/lk_wp_pixel_neon.jpg",
		"materials/stts/lk_wp_pixel_indigo.jpg",
		"materials/stts/lk_wp_pixel_rose.jpg",
		"materials/stts/lk_wp_pixel_peach.jpg",
		"materials/stts/lk_wp_galaxy_ember.jpg",
		"materials/stts/lk_wp_galaxy_night.jpg",
		"materials/stts/lk_wp_galaxy_bloom.jpg",
		"materials/stts/lk_wp_galaxy_pink.jpg",
		"materials/stts/lk_wp_galaxy_violet.jpg",
		"materials/stts/lk_wp_galaxy_glass.jpg",
		"materials/stts/lk_wp_miui_mars.jpg",
		"materials/stts/lk_wp_miui_orbit.jpg",
		"materials/stts/lk_wp_miui_sky.jpg",
		"materials/stts/lk_wp_miui_ocean.jpg",
		"materials/stts/lk_wp_miui_dunes.jpg",
		"materials/stts/lk_wp_miui_peak.jpg",
		"materials/stts/phone_close.png",
		"materials/stts/set_accent.png",
		"materials/stts/set_airplane.png",
		"materials/stts/set_bt.png",
		"materials/stts/set_cell.png",
		"materials/stts/set_clock.png",
		"materials/stts/set_display.png",
		"materials/stts/set_focus.png",
		"materials/stts/set_general.png",
		"materials/stts/set_notif.png",
		"materials/stts/set_ringtone.png",
		"materials/stts/set_texttone.png",
		"materials/stts/set_wallpaper.png",
		"materials/stts/set_wifi.png",
		"materials/stts/zm_backward_fill.png",
		"materials/stts/zm_checkmark.png",
		"materials/stts/zm_chevron_down.png",
		"materials/stts/zm_chevron_right.png",
		"materials/stts/zm_ellipsis.png",
		"materials/stts/zm_forward_fill.png",
		"materials/stts/zm_heart_fill.png",
		"materials/stts/zm_house_fill.png",
		"materials/stts/zm_infinite.png",
		"materials/stts/zm_list_bullet.png",
		"materials/stts/zm_music_albums_fill.png",
		"materials/stts/zm_music_mic.png",
		"materials/stts/zm_music_note.png",
		"materials/stts/zm_music_note_2.png",
		"materials/stts/zm_music_note_list.png",
		"materials/stts/zm_pause_fill.png",
		"materials/stts/zm_person_fill.png",
		"materials/stts/zm_play_circle_fill.png",
		"materials/stts/zm_play_fill.png",
		"materials/stts/zm_plus.png",
		"materials/stts/zm_quote_bubble.png",
		"materials/stts/zm_repeat.png",
		"materials/stts/zm_repeat_1.png",
		"materials/stts/zm_search.png",
		"materials/stts/zm_shuffle.png",
		"materials/stts/zm_speaker_3_fill.png",
		"materials/stts/zm_speaker_fill.png",
		"materials/stts/zm_square_grid_2x2_fill.png",
		"materials/stts/zm_square_stack_fill.png",
		"materials/stts/zm_star.png",
		"materials/stts/zm_star_fill.png",
		"materials/stts/zm_text_append.png",
		"materials/stts/zm_text_insert.png",
		"materials/stts/zm_xmark_circle_fill.png",
		"materials/stts/zphone_logo.png",
		"materials/vgui/stts_zphone.png",
		"materials/vgui/stts_zphone_icon.png",
		"models/stts/iphone_18pro.dx80.vtx",
		"models/stts/iphone_18pro.dx90.vtx",
		"models/stts/iphone_18pro.mdl",
		"models/stts/iphone_18pro.phy",
		"models/stts/iphone_18pro.vvd",
		"models/stts/pixel_6pro.dx80.vtx",
		"models/stts/pixel_6pro.dx90.vtx",
		"models/stts/pixel_6pro.mdl",
		"models/stts/pixel_6pro.phy",
		"models/stts/pixel_6pro.vvd",
		"models/stts/vivo_x300pro.dx80.vtx",
		"models/stts/vivo_x300pro.dx90.vtx",
		"models/stts/vivo_x300pro.mdl",
		"models/stts/vivo_x300pro.phy",
		"models/stts/vivo_x300pro.vvd",
		"sound/stts/alarms/al_argon.mp3",
		"sound/stts/alarms/al_awaken.mp3",
		"sound/stts/alarms/al_beep.mp3",
		"sound/stts/alarms/al_bounce.mp3",
		"sound/stts/alarms/al_buzzer.mp3",
		"sound/stts/alarms/al_classic.mp3",
		"sound/stts/alarms/al_drip.mp3",
		"sound/stts/alarms/al_gallop.mp3",
		"sound/stts/alarms/al_helium.mp3",
		"sound/stts/alarms/al_nudge.mp3",
		"sound/stts/alarms/al_orbit.mp3",
		"sound/stts/alarms/al_osmium.mp3",
		"sound/stts/alarms/al_oxygen.mp3",
		"sound/stts/alarms/al_rise.mp3",
		"sound/stts/alarms/al_rooster.mp3",
		"sound/stts/alarms/al_timing.mp3",
		"sound/stts/alarms/al_wag.mp3",
		"sound/stts/phone_busy.mp3",
		"sound/stts/phone_call_loop.mp3",
		"sound/stts/phone_din.mp3",
		"sound/stts/phone_gudok.mp3",
		"sound/stts/phone_message.mp3",
		"sound/stts/phone_ring.mp3",
		"sound/stts/phone_unreach.mp3",
		"sound/stts/ringtones/rt_bigadventure.mp3",
		"sound/stts/ringtones/rt_horizon.mp3",
		"sound/stts/ringtones/rt_lg.mp3",
		"sound/stts/ringtones/rt_newadventure.mp3",
		"sound/stts/ringtones/rt_nokia.mp3",
		"sound/stts/ringtones/rt_oldphone.mp3",
		"sound/stts/ringtones/rt_opening.mp3",
		"sound/stts/ringtones/rt_reflection.mp3",
		"sound/stts/ringtones/rt_sony.mp3",
		"sound/stts/ringtones/rt_xiaomi.mp3",
		"sound/stts/tones/tn_bamboo.mp3",
		"sound/stts/tones/tn_bell.mp3",
		"sound/stts/tones/tn_chime.mp3",
		"sound/stts/tones/tn_chord.mp3",
		"sound/stts/tones/tn_glass.mp3",
		"sound/stts/tones/tn_pop.mp3",
		"sound/stts/tones/tn_pulse.mp3",
		"sound/stts/tones/tn_tritone.mp3",
	}) do resource.AddFile(f) end
end

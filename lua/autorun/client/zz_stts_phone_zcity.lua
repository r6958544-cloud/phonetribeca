--[[---------------------------------------------------------------------------
	ZPhone for Z-City (standalone addon) - client loader.
	named "zz_" so it runs after the other autorun/client/cl_stts_phone_*.lua
	files, the same order the game mode loaded them in.
---------------------------------------------------------------------------]]
for _, f in ipairs({
	"cl_calls.lua",
	"cl_phone.lua",
	"cl_phone_screen.lua",
	"cl_phone_settings.lua",
	"cl_phone_shade.lua",
	"cl_phone_music.lua",
	"cl_phone_home.lua",
	"cl_phone_clock.lua",
	"cl_phone_lock.lua",
	"cl_phone_botphoto.lua",
	"cl_compat.lua",
}) do include("stts_phone/" .. f) end

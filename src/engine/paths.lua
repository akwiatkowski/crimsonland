-- Central location of the extracted original game data, and of the one
-- directory this port writes to.
-- Everything under vendor/ is reproducible from the GOG installer
-- (see Makefile) and gitignored.

--- True when the process was launched with `--autotest[=scenario]`, which is
-- decided here rather than by main.lua because the answer is needed before
-- any module (this one included) has finished loading.
local function is_autotest()
	for _, a in ipairs(arg or {}) do
		if a:match("^%-%-autotest") then return true end
	end
	return false
end

-- Where the player's own data goes: progress, achievements, statistics and
-- settings, all in one save file.
--
-- macOS convention is ~/Library/Application Support/<App>. LÖVE's own save
-- directory would be ~/Library/Application Support/LOVE/<identity> — an extra
-- vendor folder that belongs to the runtime, not to this game — so the save
-- file is written straight to the native location with plain `io` instead
-- (game/save.lua). getUserDirectory() already ends in a slash.
--
-- An autotest run gets its own directory, so a scenario can never overwrite a
-- real profile: the harness plays the game for real, and a scripted run that
-- finishes a quest would otherwise mark it completed forever.
--
-- APP is the whole port's directory; USER is the active mod's room inside it,
-- assigned by src/engine/mod.lua before the mod loads. A profile — progress,
-- achievements, statistics, settings — belongs to one cartridge: a debug mod
-- that hands out every weapon must not be able to mark a quest completed on
-- the profile the base game reads. Nothing writes above USER.
local APP_SUPPORT = love.filesystem.getUserDirectory() .. "Library/Application Support/"
local APP = APP_SUPPORT .. (is_autotest() and "Crimsonland-Test" or "Crimsonland")

return {
	ASSETS = "vendor/assets", -- main data.pak contents
	ASSETS_1080P = "vendor/assets-1080p", -- hi-res variants (unused yet)
	SFX = "vendor/assets-sfx", -- sound effects (sfx/*.ogg)
	MUSIC = "vendor/assets-music", -- music (music/*.ogg)
	-- The original executable. Not code we run — a data file like the rest,
	-- and the only place some datasets exist (the perk roster, the music
	-- table). Produced by `make extract` alongside the paks.
	PROG = "vendor/extracted/app/prog.dll",

	-- absolute, outside the LÖVE filesystem sandbox — see the note above
	APP = APP,
	-- overwritten with APP/mods/<mod> by mod.select(); the plain APP value is
	-- only what anything loaded before a mod is chosen would see
	USER = APP,
	TESTING = is_autotest(),
}

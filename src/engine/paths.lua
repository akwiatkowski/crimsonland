-- Central location of the extracted original game data.
-- Everything under vendor/ is reproducible from the GOG installer
-- (see Makefile) and gitignored.

return {
	ASSETS = "vendor/assets", -- main data.pak contents
	ASSETS_1080P = "vendor/assets-1080p", -- hi-res variants (unused yet)
	SFX = "vendor/assets-sfx", -- sound effects (sfx/*.ogg)
	MUSIC = "vendor/assets-music", -- music (music/*.ogg)
	-- The original executable. Not code we run — a data file like the rest,
	-- and the only place some datasets exist (the perk roster, the music
	-- table). Produced by `make extract` alongside the paks.
	PROG = "vendor/extracted/app/prog.dll",
}

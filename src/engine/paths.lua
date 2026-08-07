-- Central location of the extracted original game data.
-- Everything under vendor/ is reproducible from the GOG installer
-- (see Makefile) and gitignored.

return {
	ASSETS = "vendor/assets", -- main data.pak contents
	ASSETS_1080P = "vendor/assets-1080p", -- hi-res variants (unused yet)
	SFX = "vendor/assets-sfx", -- sound effects (sfx/*.ogg)
	MUSIC = "vendor/assets-music", -- music (music/*.ogg)
}

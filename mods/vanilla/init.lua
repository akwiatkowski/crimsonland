-- Vanilla Crimsonland as a mod: the clean-room reimplementation of the
-- original game, driven by the GOG data under vendor/ (see make extract).
--
-- The implementation still lives in src/game/ (it predates the mod
-- architecture); this descriptor is the seam. New mods provide their own
-- game/save tables and may override asset paths — see src/engine/mod.lua
-- for the contract.

return {
	name = "vanilla",
	game = require("src.game.play"),
	save = require("src.game.save"),
	-- no `paths` override: vanilla uses the vendor/ roots from
	-- src/engine/paths.lua (bring-your-own GOG copy)
}

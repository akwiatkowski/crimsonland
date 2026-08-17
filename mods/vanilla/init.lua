-- Vanilla Crimsonland as a mod: the clean-room reimplementation of the
-- original game, driven by the GOG data under vendor/ (see make extract).
--
-- Everything it is lives in `game/` beside this file; nothing outside
-- mods/vanilla/ knows the reimplementation exists. New mods provide their own
-- game/save tables and may override asset paths — see src/engine/mod.lua for
-- the contract.

return {
	name = "vanilla",
	game = require("mods.vanilla.game.play"),
	save = require("mods.vanilla.game.save"),
	-- no `paths` override: vanilla uses the vendor/ roots from
	-- src/engine/paths.lua (bring-your-own GOG copy)
}

-- "All weapons available" — the debug cartridge.
--
-- Vanilla Crimsonland with two rules removed: every chapter and quest is open
-- from the start, and every run begins with a weapon you pick off the gallery
-- grid instead of the pistol the mode would have handed you. That is the whole
-- mod: it exists so a weapon can be taken into any map in seconds, rather than
-- played towards for an hour.
--
-- It is a thin layer, not a fork: the game is still mods/vanilla/game/, and
-- allweapons/picker.lua wraps three of its hooks (see that file). Progress is
-- kept apart from the base game's by the engine, which gives every mod its own
-- profile directory (src/engine/mod.lua) — a quest cleared here with a plasma
-- minigun cannot unlock anything on the profile vanilla reads.

return {
	name = "allweapons",
	game = require("mods.allweapons.picker"),
	save = require("mods.vanilla.game.save"), -- same format, own directory
}

-- Tower defence: a base in the middle of the map, waves from every edge, and
-- a player who is one of the things defending it rather than the point of it.
--
-- Design in plans/crimsonland.md (2026-08-18). This is SLICE ONE: the field
-- and the wave loop, no towers, no HQ shop, no perks. It exists to answer
-- whether defending a thing is fun here before the economy is built on it.
--
-- Not a fork of vanilla: the pak-reading layers (data, animations, terrain,
-- particles, gibs) are vanilla's modules used unchanged, and only the
-- simulation — which is file-local over there, and whose one crucial rule
-- (what a creature walks towards) is different here — is this mod's own.
--
-- The save is vanilla's module for now: it persists engine platform state
-- (profile, volumes, window) into THIS mod's own directory, which the engine
-- gives every cartridge (src/engine/mod.lua). Its quest fields go unused; a
-- save of this mod's own — money, best wave — comes with the economy.

return {
	name = "towerdefence",
	game = require("mods.towerdefence.game.field"),
	save = require("mods.vanilla.game.save"),
}

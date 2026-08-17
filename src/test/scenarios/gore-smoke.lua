-- Gore coverage: survival with the AI holding the trigger, which is the
-- densest fight the port can produce on demand. Everything the pak ships art
-- for and this port only recently started drawing lands here -- shadows under
-- the living, body parts thrown by a kill (creatures.xml's bm_gibs_*), the
-- projectile sprites off game/projs.tga -- so a run where gibs and kills stay
-- at zero means the death path stopped feeding them.
--
-- Parts are short-lived by design (they bake into the terrain within a
-- second), so the report samples the count rather than expecting a fixed one:
-- what matters is that it is non-zero while creatures are dying.

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

local peak_gibs = 0

local function report()
	local g = require("mods.vanilla.game.play")
	local gibs = require("mods.vanilla.game.gibs")
	peak_gibs = math.max(peak_gibs, gibs.count())
	print(string.format(
		"[gore] t=%.1f kills=%d creatures=%d gibs=%d peak=%d fx=%d hp=%d",
		g.time, g.kills, #g.creatures, gibs.count(), peak_gibs,
		require("src.engine.fx").count("world"), g.player.hp))
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.6, click = "Play_SURVIVAL" },
	{ t = 5.0, run = take_over },
	{ t = 12.0, run = report },
	{ t = 18.0, run = report },
	{ t = 24.0, run = report },
	{ t = 30.0, run = report },
	{ t = 36.0, run = report },
	captures = { 20.0, 32.0 },
}

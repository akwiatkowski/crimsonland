-- Impact coverage: what a hit does to the frame rather than to the world --
-- camera shake, the full-screen flash, heat shimmer over a blast, light thrown
-- onto the ground, and the grades that show a whole-world state (a frozen
-- field, slowed time).
--
-- Nukefism is the mode that makes this testable by playing rather than by
-- poking: the player has no gun and the field seeds a random powerup every
-- 3.5 seconds, so over a minute the AI picks up most of the table -- freeze,
-- shield and nuke included. Those three could not be reached any other way
-- inside a scenario; a 5% drop off a pistol kill never lands in time.
--
-- The reports fire at the same times as the captures, so a frame can be read
-- against the state that produced it.

local function start_nukefism()
	-- the same call the survival menu makes; Nukefism is progression-locked on
	-- a fresh save, so clicking it would land on an inactive button
	require("mods.vanilla.game.play").start_survival("nukefism")
	require("src.engine.timeline").begin("Game")
end

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

--- Blasts at known moments, so a capture holds a shaken, hazed, lit frame
-- instead of waiting for the AI to find a rocket.
--
-- Several of them a third of a second apart, not one: a headless-ish test
-- window runs at roughly nine frames a second, a screenshot lands a frame or
-- two after it is asked for, and a fireball lives a quarter of a second. One
-- blast is reliably over by the time the shot is taken -- a run of them means
-- whichever frame the shot catches, something is still burning on it.
local function blast()
	local g = require("mods.vanilla.game.play")
	g.explode_at(g.player.x + 40, g.player.y + 10, 30)
end

--- Take the first perk whenever the level-up screen comes up. Without this a
-- scenario that kills well stops dead at the first level: gameplay pauses
-- under a UI screen and the AI has no way to dismiss one.
local function dismiss_perk()
	local top = require("src.engine.screens").top()
	if top and top.name == "PickAPerk" then
		require("src.test.harness").click("PerkButton_1")
	end
end

local seen = {}

local function report()
	local g = require("mods.vanilla.game.play")
	local active = {}
	for id, left in pairs(g.effects) do
		active[#active + 1] = ("%s=%.1f"):format(id, left)
		seen[id] = true
	end
	table.sort(active)
	local names = {}
	for id in pairs(seen) do names[#names + 1] = id end
	table.sort(names)
	print(("[impact] t=%.1f hp=%d kills=%d shake=%.1f flash=%.2f hazes=%d"
		.. " effects=[%s] seen=[%s]"):format(
		g.time, g.player.hp, g.kills, g.shake_mag or 0, g.flash_amount or 0,
		#(g.hazes or {}), table.concat(active, " "), table.concat(names, ",")))
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.6, run = start_nukefism },
	{ t = 5.0, run = take_over },

	-- the announcement banner, on the same call a powerup pickup makes. Catching
	-- a real pickup in a capture is luck; the draw path is the same either way.
	{ t = 7.6, run = function()
		require("mods.vanilla.game.play").announce("FIREBLAST")
	end },

	{ t = 8.0, run = blast },
	{ t = 8.3, run = blast },
	{ t = 8.6, run = blast },
	{ t = 8.9, run = blast },
	{ t = 9.0, run = report },

	{ t = 13.8, run = dismiss_perk },
	{ t = 14.0, run = report },
	{ t = 19.8, run = dismiss_perk },
	{ t = 20.0, run = report },
	{ t = 25.8, run = dismiss_perk },
	{ t = 26.0, run = report },
	{ t = 31.8, run = dismiss_perk },
	{ t = 32.0, run = report },
	{ t = 37.8, run = dismiss_perk },
	{ t = 38.0, run = report },
	{ t = 43.8, run = dismiss_perk },
	{ t = 44.0, run = report },
	{ t = 49.8, run = dismiss_perk },
	{ t = 50.0, run = report },

	captures = { 9.0, 14.0, 20.0, 26.0, 32.0, 38.0, 44.0, 50.0 },
}

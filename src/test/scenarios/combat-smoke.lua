-- Combat coverage: menus -> quest 1.1 -> hand the player to the AI and let it
-- fight. Until src/game/input.lua existed no scenario could pull a trigger
-- (the game polled love.mouse.isDown, which reads real hardware), so weapons,
-- hits, kills, drops, gore and shell casings had no automated exercise at all.
--
-- The capture lines carry kills/creatures/bullets; a run where those stay at
-- zero means something on the firing path broke.

local function take_over()
	require("src.game.input").set_controller(
		require("src.game.ai_player").controller())
end

local function report()
	local g = require("src.game.play")
	print(string.format("[combat] t=%.1f shots=%d hits=%d kills=%d drops=%d hp=%d",
		g.time, g.shots, g.hits, g.kills, #g.drops, g.player.hp))
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 7.5, run = take_over },
	{ t = 14.0, run = report },
	{ t = 24.0, run = report },
	captures = { 12.0, 22.0 },
}

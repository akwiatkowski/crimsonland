-- Energy-bolt look, on the two guns that show it best (run with
-- MOD=allweapons — the picker is what makes a scenario able to choose a
-- weapon at all):
--
--   make test MOD=allweapons SCENARIO=allweapons-bolts
--
-- Ion Cannon first, then Plasma Cannon, each handed to the AI so bolts are
-- actually in the air when the capture lands. What the captures have to show
-- is a blue ball for the ion and an amber one for the plasma — the families'
-- own colours off the original's icons (game/data.lua) — and both of them big,
-- because those two fire the slowest, hardest-hitting round in the game. The
-- [bolts] lines carry the same thing as numbers.

local ION_CANNON, PLASMA_CANNON = "Weapon_23", "Weapon_26" -- weapons.xml index

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

local function report()
	local g = require("mods.vanilla.game.play")
	local w = g.player.weapon
	print(string.format("[bolts] %s art=%s bolt=%.2f bullets=%d shots=%d",
		w.id, tostring(w.proj_art), w.proj_scale or -1, #g.bullets, g.shots))
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 8.5, click = ION_CANNON },
	{ t = 9.0, run = take_over },
	{ t = 13.5, run = report },

	{ t = 15.0, key = "escape" },
	{ t = 16.0, click = "QuitToMenu" },
	{ t = 18.0, click = "PlayMenu" },
	{ t = 19.5, click = "Play_Quests" },
	{ t = 21.0, click = "Chapter_1" },
	{ t = 22.5, click = "Quest_1" },
	{ t = 24.0, click = PLASMA_CANNON },
	{ t = 24.5, run = take_over },
	{ t = 29.0, run = report },
	captures = { 13.5, 29.0 },
}

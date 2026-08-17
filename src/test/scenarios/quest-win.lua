-- Plays chapter 1 quest 1 to the end and captures the "Well Done, Trooper"
-- panel. The panel ships with a designer's sample round baked into every
-- textbox (57 kills, 01:17, a Blade Gun), so a capture here is the only proof
-- that game.open_end_screen overwrites it with the round that was played.
--
-- A quest hands the player no controller (start_quest clears it: a quest is
-- for a human) and a standing trooper never reaches a kill goal, so this is
-- the one scenario that gives the wheel to the attract-mode AI. It still
-- steers through input.intent exactly like a player's mouse does.

local harness = require("src.test.harness")
local screens = require("src.engine.screens")

local function let_the_ai_play()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

-- The round stops dead on anything the player is supposed to answer: a
-- level-up wants a perk picked, and first sight of a weapon or a perk puts up
-- a celebration that only a click dismisses. Unattended, one of those ends the
-- run — so every tick answers whatever is in the way, and nothing else.
local function answer_whatever_blocks()
	local top = screens.top()
	if not top then return end
	if top.name == "PickAPerk" then
		harness.click("PerkButton_1")
	elseif top.name == "WeaponUnlocked" or top.name == "PerkUnlocked" then
		harness.click_at(60, 600) -- these answer a click on empty space
	end
end

local steps = {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, click = "Chapter_1" },
	{ t = 5.8, click = "Quest_1" },
	{ t = 7.0, run = let_the_ai_play },
}

-- 24 kills at the AI's pace takes a couple of minutes of game time; the tick
-- is coarse enough to stay cheap and fine enough that the round never idles
-- long behind a screen.
for t = 8, 300, 2 do
	steps[#steps + 1] = { t = t, run = answer_whatever_blocks }
end

-- Two late captures because the exact second the goal falls is the AI's to
-- decide: one of them lands on the completed panel either way.
steps.captures = { 10, 240, 290 }

return steps

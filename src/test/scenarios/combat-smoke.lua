-- Combat coverage: menus -> quest 1.1 -> hand the player to the AI and let it
-- fight. Until the input layer existed no scenario could pull a trigger
-- (the game polled love.mouse.isDown, which reads real hardware), so weapons,
-- hits, kills, drops, gore and shell casings had no automated exercise at all.
--
-- The capture lines carry kills/creatures/bullets; a run where those stay at
-- zero means something on the firing path broke.
--
-- The two reports are ten seconds apart and the game clock between them is
-- what proves the fight was still running: first sight of a dropped weapon
-- puts the unlock celebration up, and the game under a UI screen is not
-- updated. This scenario used to spend better than half its length frozen
-- behind one and print the same numbers twice -- passing, and exercising
-- nothing. `dismiss` is the AI doing what a player does with a screen that
-- says "click anywhere to continue".

local play = require("mods.vanilla.game.play")

local seen = {}

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

local function report(tag)
	return function()
		seen[tag] = { t = play.time, shots = play.shots, kills = play.kills }
		print(string.format("[combat] t=%.1f shots=%d hits=%d kills=%d drops=%d hp=%d",
			play.time, play.shots, play.hits, play.kills, #play.drops, play.player.hp))
	end
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 7.5, run = take_over },
	{ t = 14.0, run = report("early") },
	{ t = 24.0, run = report("late") },
	{ t = 24.1, expect = function()
		local a, b = seen.early, seen.late
		if not (a and b) then return false, "the fight never started" end
		if b.shots <= a.shots then
			return false, ("no shots fired between %.1fs and %.1fs"):format(a.t, b.t)
		end
		-- ten scenario seconds apart; a fight that only advanced a couple of
		-- them spent the rest under a screen
		if b.t - a.t < 8 then
			return false, ("fight advanced %.1fs of clock in 10s"):format(b.t - a.t)
		end
		return true, ("fight ran %.1fs, %d shots, %d kills"):format(
			b.t - a.t, b.shots - a.shots, b.kills)
	end },
	captures = { 12.0, 22.0 },
	dismiss = { "WeaponUnlocked", "PerkUnlocked" },
}

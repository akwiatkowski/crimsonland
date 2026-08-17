-- Terrain coverage: the authored ground, one mode at a time, captured early
-- enough that the field is still visible rather than buried under an end
-- screen or a wall of aliens.
--
-- terrains.xml is not just the seven chapters -- it carries an array per
-- endless mode, and each is a different place: RUSH is a beach with a
-- summoning circle burned into it and a web of black trails, BLITZ is chapter
-- 5 with a landing pad, roads and four sets of mech tracks, SURVIVAL is
-- chapter 2 as it looks five quests in. Every one of them used to bake as
-- chapter 1's grass. Rush and Blitz here cover the ops those need -- Clear in
-- its color_ spelling, DrawVoronoi, DrawSingle, FootPrints, DrawTerrain --
-- and the [terrain] lines in the log carry what each bake cost.
--
-- Waves and Nukefism would cover DrawTerrain too but are progression-locked
-- on a fresh save, so a click lands on an inactive button and does nothing.
-- The third leg is quest 1-1 instead, which is the other half of the tier:
-- SetSeeds picking that quest's layout, and quest_number_required holding
-- back the debris and blast marks a first quest has not earned yet.

local function report()
	local g = require("mods.vanilla.game.play")
	print(("[terrain-test] mode=%s chapter=%s quest=%s"):format(
		tostring(g.mode), tostring(g.chapter), tostring(g.quest)))
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.6, click = "Play_RUSH" },
	{ t = 5.2, run = report },

	-- back out and into Blitz: a second bake, and the one that lays roads
	{ t = 9.0, key = "escape" },
	{ t = 10.0, click = "QuitToMenu" },
	{ t = 12.0, click = "PlayMenu" },
	{ t = 13.2, click = "Play_Survival" },
	{ t = 14.4, click = "Play_BLITZ" },
	{ t = 15.0, run = report },

	-- and a first quest, which must bake with none of the later decoration
	{ t = 19.0, key = "escape" },
	{ t = 20.0, click = "QuitToMenu" },
	{ t = 22.0, click = "PlayMenu" },
	{ t = 23.2, click = "Play_Quests" },
	{ t = 24.4, click = "Chapter_1" },
	{ t = 25.6, click = "Quest_1" },
	{ t = 26.2, run = report },

	-- ...and the same chapter's last quest, which is the pair that shows the
	-- gating working: same ground, ten quests of blast marks, debris, stone
	-- rings and a road on top of it. Quest 10 is not reachable by clicking on
	-- a fresh save, so it is started through the same call the menu makes.
	{ t = 29.0, run = function()
		require("mods.vanilla.game.play").start_quest(1, 10, "NORMAL")
		require("src.engine.timeline").begin("Game")
	end },
	{ t = 30.0, run = report },

	captures = { 6.0, 16.0, 27.0, 31.0 },
}

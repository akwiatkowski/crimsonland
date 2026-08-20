-- One chapter's one quest, baked and fingerprinted.
--
--   make test SCENARIO=bake CL_CHAPTER=5 CL_QUEST=7
--
-- 7 chapters x 10 quests is 70 grounds, and terrains.xml gives every one of
-- them its own seed list and its own quest_number_required gating, so they are
-- 70 different pictures rather than one picture seeded 70 ways. The sweep runs
-- them all and diffs the fingerprints; two chapters printing the same numbers
-- is the bug this exists to catch -- every endless mode used to bake as
-- chapter 1's grass, and nothing failed when it did.
--
-- The quest is started through game.start_quest rather than by clicking the
-- grid, which is what terrain-smoke already does for a locked quest: it is the
-- call the menu makes, and it takes a chapter and quest as arguments instead of
-- needing ten plates clicked to reach the tenth.
--
-- A bake is a canvas, so the fingerprint is read off the pixels: mean
-- luminance and how many distinct levels a sample grid lands on. Flat ground
-- means the bake drew nothing -- which is a silent failure otherwise, because
-- a black field renders perfectly well.

local play = require("mods.vanilla.game.play")
local timeline = require("src.engine.timeline")

local CHAPTER = tonumber(os.getenv("CL_CHAPTER") or "1")
local QUEST = tonumber(os.getenv("CL_QUEST") or "1")

-- Sample grid over the baked ground. 32x32 = 1024 reads, enough to tell a
-- painted field from an empty one and cheap next to the newImageData that
-- has to happen anyway.
local GRID = 32

local fingerprint = nil

local function start()
	play.start_quest(CHAPTER, QUEST, "NORMAL")
	timeline.begin("Game")
end

local function measure()
	if not play.terrain then return end
	local data = play.terrain:newImageData()
	local w, h = data:getDimensions()
	local sum, levels, n = 0, {}, 0
	for row = 0, GRID - 1 do
		for col = 0, GRID - 1 do
			local r, g, b = data:getPixel(
				math.floor(col / GRID * (w - 1)),
				math.floor(row / GRID * (h - 1)))
			local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
			sum = sum + lum
			-- quantised, or antialiasing alone would make every pixel distinct
			levels[math.floor(lum * 255)] = true
			n = n + 1
		end
	end
	local distinct = 0
	for _ in pairs(levels) do distinct = distinct + 1 end
	data:release()
	fingerprint = { mean = sum / n, distinct = distinct }
	print(("[bake] chapter=%d quest=%d px=%dx%d lum=%.4f distinct=%d"):format(
		CHAPTER, QUEST, w, h, fingerprint.mean, distinct))
end

return {
	{ t = 2.5, run = start },
	{ t = 3.5, run = measure },
	{ t = 3.6, expect = function()
		if not play.active then
			return false, ("chapter %d quest %d did not start"):format(CHAPTER, QUEST)
		end
		if play.chapter ~= CHAPTER or play.quest ~= QUEST then
			return false, ("asked for %d-%d, running %s-%s"):format(
				CHAPTER, QUEST, tostring(play.chapter), tostring(play.quest))
		end
		return true, ("running %d-%d"):format(CHAPTER, QUEST)
	end },
	{ t = 3.7, expect = function()
		if not fingerprint then return false, "no terrain canvas to measure" end
		-- A bake that drew nothing leaves the clear colour: one level, and
		-- black. Two levels would still be a failure; the bar is deliberately
		-- just above "the canvas exists".
		if fingerprint.distinct < 8 then
			return false, ("%d-%d baked flat ground (%d levels, lum %.4f)"):format(
				CHAPTER, QUEST, fingerprint.distinct, fingerprint.mean)
		end
		return true, ("%d-%d ground has %d levels"):format(
			CHAPTER, QUEST, fingerprint.distinct)
	end },
}

-- Ten quests of one chapter, baked and compared byte for byte.
--
--   make test SCENARIO=bake-variety CL_CHAPTER=3
--
-- bake.lua asks whether a ground got drawn. This asks whether it is that
-- quest's ground: the original pins layouts with SetSeeds, "ten of them, for
-- the ten quests" (terrain.lua's own note), and terrains.xml only carries such
-- a list for CHAPTER_1 and CHAPTER_2. The other five chapters say nothing, and
-- an op list that never reseeds bakes from whatever the generator was last
-- left holding -- so what those five look like is decided entirely by the
-- port's fallback, and a constant fallback means one field for all ten quests,
-- identical on every playthrough.
--
-- The comparison is a hash of the finished canvas rather than a sample of it:
-- a gated op can be two splashes of one bitmap on a 1820x1024 field (chapter
-- 5's summoning circle is exactly that), which a sample grid of a thousand
-- pixels will miss nine times out of ten. Nothing here is sampled -- if a
-- single pixel differs, the hash differs.
--
-- terrain.bake is called directly: this is a question about the bake, and
-- starting ten sessions to ask it ten times would only add the rest of the
-- game to the answer.

local play = require("mods.vanilla.game.play")
local terrain = require("mods.vanilla.game.terrain")

local CHAPTER = tonumber(os.getenv("CL_CHAPTER") or "1")
local QUESTS = 10

-- Density 1 rather than the display's 1.69: the ground art only ships at base
-- resolution, so the extra pixels are interpolation and cost readback time.
local DENSITY = 1

local hashes = {}

local function bake_all()
	local id = ("CHAPTER_%d"):format(CHAPTER)
	for quest = 1, QUESTS do
		local canvas = terrain.bake(id, quest, play.WORLD_W, play.WORLD_H, DENSITY)
		local image = canvas:newImageData()
		hashes[quest] = love.data.encode("string", "hex",
			love.data.hash("md5", image:getString()))
		image:release()
		canvas:release()
	end
	local seen, order = {}, {}
	for quest = 1, QUESTS do
		local h = hashes[quest]
		if not seen[h] then
			seen[h] = {}
			order[#order + 1] = h
		end
		table.insert(seen[h], quest)
	end
	local groups = {}
	for _, h in ipairs(order) do
		groups[#groups + 1] = table.concat(seen[h], ",") .. "=" .. h:sub(1, 8)
	end
	print(("[variety] chapter=%d distinct=%d %s"):format(
		CHAPTER, #order, table.concat(groups, " ")))
	return #order
end

return {
	{ t = 2.0, run = function() hashes.distinct = bake_all() end },
	{ t = 2.1, expect = function()
		local distinct = hashes.distinct or 0
		-- Ten quests, ten grounds. Not "more than one": the chapters that do
		-- carry a seed list carry exactly ten seeds, one per quest, so ten is
		-- what the data asks for wherever it says anything at all -- and a
		-- chapter that says nothing has no reason to be the one chapter whose
		-- ten quests are fought on one field.
		if distinct < QUESTS then
			return false, ("chapter %d baked %d distinct grounds for %d quests"):format(
				CHAPTER, distinct, QUESTS)
		end
		return true, ("chapter %d: %d quests, %d grounds"):format(
			CHAPTER, QUESTS, distinct)
	end },
}

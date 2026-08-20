-- Every creature the game can meet, and nothing it cannot.
--
--   make test SCENARIO=creature-data
--
-- Two files describe a creature and they are not the same list.
-- creatures.xml is the art and sound table -- animations, gibs, shadow, death
-- sounds. creature-variants.xml is what the game spawns: a variant claims a
-- type from that table and gives it health, speed, scale, a weapon.
--
-- So a type with no variant can never appear. There is exactly one, and it is
-- not an oversight: TROOPER is the player. play.lua draws the marine and the
-- marine's shadow out of data.creatures.TROOPER, which is why the pak ships it
-- a full sprite set and no variant claims it.
--
-- Worth asserting because the whole game is data-driven: a variant parse that
-- quietly stopped producing variants for a type would take that creature out of
-- the game and nothing would fail. The matrix sweep spawns one type at a time,
-- so it would find it -- after 30 fights against something that cannot spawn.

local data = require("mods.vanilla.game.data")

-- The player's own type. Anything else without a variant is a hole.
local PLAYER_TYPE = "TROOPER"

local function unspawnable()
	local out = {}
	for id in pairs(data.creatures) do
		if id ~= PLAYER_TYPE and not data.base_variant[id] then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

local function orphan_variants()
	-- the other direction: a variant claiming a type the art table does not
	-- describe would spawn something with no sprite
	local out = {}
	for id, v in pairs(data.variants) do
		if not data.creatures[v.type] then
			out[#out + 1] = ("%s wants %s"):format(id, tostring(v.type))
		end
	end
	table.sort(out)
	return out
end

return {
	{ t = 1.5, run = function()
		data.load_all()
		local types, variants = 0, 0
		for _ in pairs(data.creatures) do types = types + 1 end
		for _ in pairs(data.variants) do variants = variants + 1 end
		print(("[creatures] %d types, %d variants"):format(types, variants))
	end },
	{ t = 1.6, expect = function()
		local holes = unspawnable()
		if #holes > 0 then
			return false, ("no variant can spawn: %s"):format(table.concat(holes, ", "))
		end
		return true, "every creature type but the player has a variant"
	end },
	{ t = 1.7, expect = function()
		local orphans = orphan_variants()
		if #orphans > 0 then
			return false, ("variant with no art: %s"):format(table.concat(orphans, ", "))
		end
		return true, "every variant claims a type the art table describes"
	end },
	{ t = 1.8, expect = function()
		-- the player's sprite is read straight out of the art table, so its
		-- absence would be a marine with no animation rather than a crash
		local p = data.creatures[PLAYER_TYPE]
		if not (p and p.move and p.die) then
			return false, ("%s has no move/die animation"):format(PLAYER_TYPE)
		end
		return true, ("%s (the player) has its sprite set"):format(PLAYER_TYPE)
	end },
}

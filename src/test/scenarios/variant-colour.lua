-- The colours creature-variants.xml gives a creature, as the port reads them.
--
--   make test SCENARIO=variant-colour
--
-- Every one of the 102 variants carries color_base_r/g/b/a. The port read three
-- of the four and drew every creature at full opacity, which for most of them
-- is what the data says anyway -- and for five of them is not:
--
--   Variant_23  ALIEN     alpha 0.05, 5 hp
--   Variant_24  ALIEN     alpha 0.04, 5 hp
--   Variant_78  CRABFLY   alpha 0.25, 1800 hp
--   Variant_14  ALIEN     alpha 0.5
--   Variant_22  ALIEN     alpha 0.5
--
-- A 5 hp alien at four percent opacity is a wisp you are meant to have trouble
-- seeing. All five were solid.
--
-- What this asserts is the parse, not the blend: that the authored alpha
-- survives into data.variants, and that the five that are meant to be faint
-- are exactly the five that are. A dropped field is the failure this guards --
-- it defaults to 1 and every ghost turns solid again with nothing complaining.
-- The draw site is one expression (play.lua draw_creature).

local data = require("mods.vanilla.game.data")

-- Straight out of vendor/assets/creatures/creature-variants.xml. Written down
-- rather than recomputed, so this is a second opinion about the file and not a
-- restatement of whatever the parser happened to do.
local FAINT = {
	Variant_14 = 0.5,
	Variant_22 = 0.5,
	Variant_23 = 0.05,
	Variant_24 = 0.04,
	Variant_78 = 0.25,
}

return {
	{ t = 1.5, run = function()
		data.load_all()
		local n, faint = 0, {}
		for id, v in pairs(data.variants) do
			n = n + 1
			if (v.alpha or 1) < 1 then faint[#faint + 1] = ("%s=%.2f"):format(id, v.alpha) end
		end
		table.sort(faint)
		print(("[colour] %d variants, %d faint: %s"):format(
			n, #faint, table.concat(faint, " ")))
	end },
	{ t = 1.6, expect = function()
		local missing = {}
		for _, v in pairs(data.variants) do
			if v.alpha == nil then missing[#missing + 1] = v.id end
		end
		if #missing > 0 then
			return false, ("%d variants have no alpha parsed at all"):format(#missing)
		end
		return true, "every variant carries an alpha"
	end },
	{ t = 1.7, expect = function()
		local wrong = {}
		for id, want in pairs(FAINT) do
			local v = data.variants[id]
			if not v then
				wrong[#wrong + 1] = id .. " missing"
			elseif math.abs((v.alpha or 1) - want) > 0.001 then
				wrong[#wrong + 1] = ("%s is %.2f, authored %.2f"):format(
					id, v.alpha or 1, want)
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			return false, ("faint variants read wrong: %s"):format(table.concat(wrong, ", "))
		end
		return true, "all five faint variants keep their authored alpha"
	end },
	{ t = 1.8, expect = function()
		-- and nothing else went transparent: a parse that read the wrong
		-- attribute could give every variant a fractional alpha and still pass
		-- the check above
		local extra = {}
		for id, v in pairs(data.variants) do
			if (v.alpha or 1) < 1 and not FAINT[id] then
				extra[#extra + 1] = ("%s=%.2f"):format(id, v.alpha)
			end
		end
		table.sort(extra)
		if #extra > 0 then
			return false, ("unexpected faint variants: %s"):format(table.concat(extra, ", "))
		end
		return true, "the other 97 variants are opaque, as authored"
	end },
}

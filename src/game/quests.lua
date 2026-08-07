-- Quest definitions. The original per-quest setups were compiled into
-- prog.dll, so these are authored to match the game's chapter themes
-- (chapters.xml names) and difficulty curve: each chapter has a creature
-- palette whose members join as the quests progress, pacing that tightens
-- toward quest 10, and a boss encounter at quest 10.
--
-- quests.get(chapter, quest) -> {
--   kills_goal, spawn_interval, max_concurrent,
--   pool = { {type=..., w=...}, ... },        (weighted creature mix)
--   boss = { variant=<variant table>, count=n } or nil
-- }

local data = require("src.game.data")

local quests = {}

-- palette entries: creature type, spawn weight, quest number it appears from.
-- boss: either a creature type (uses its base variant) or an explicit
-- variant id from creature-variants.xml (BossAlien, MegaZombie, ...).
local CHAPTERS = {
	{ -- 1 · Land Hostile: aliens, first spiders; "8-legged Terror"
		palette = {
			{ t = "ALIEN", w = 4 },
			{ t = "ZOMBIE", w = 2, from = 3 },
			{ t = "SPIDER1", w = 2, from = 6 },
		},
		boss = { type = "SPIDER_BOSS", count = 1 },
	},
	{ -- 2 · Red Trail of Mercy: spiders take over
		palette = {
			{ t = "ALIEN", w = 3 },
			{ t = "SPIDER1", w = 3 },
			{ t = "MAGGOT", w = 2, from = 4 },
			{ t = "SPIDER2", w = 2, from = 7 },
		},
		boss = { id = "AlienBrute", count = 1 },
	},
	{ -- 3 · Glorious Combat: the dead walk
		palette = {
			{ t = "ZOMBIE", w = 4 },
			{ t = "SPIDER1", w = 2 },
			{ t = "LIZARD", w = 2, from = 4 },
			{ t = "SPIDER2", w = 2, from = 8 },
		},
		boss = { id = "BossAlien", count = 1 },
	},
	{ -- 4 · Beyond Hope: heavies join
		palette = {
			{ t = "SPIDER2", w = 3 },
			{ t = "LIZARD", w = 3 },
			{ t = "BEETLE", w = 2, from = 3 },
			{ t = "ZOMBIE", w = 2, from = 6 },
		},
		boss = { id = "Variant_44", count = 1 },
	},
	{ -- 5 · Blood and Tears: swarm pressure
		palette = {
			{ t = "MAGGOT", w = 3 },
			{ t = "SPIDER2", w = 3 },
			{ t = "BEETLE", w = 2, from = 4 },
			{ t = "CRABFLY", w = 2, from = 6 },
		},
		boss = { id = "BossAlien", count = 2 },
	},
	{ -- 6 · Unfinished Business: everything at once
		palette = {
			{ t = "LIZARD", w = 3 },
			{ t = "BEETLE", w = 3 },
			{ t = "CRABFLY", w = 2, from = 3 },
			{ t = "SPIDER_BOSS", w = 1, from = 8 },
		},
		boss = { id = "MegaZombie", count = 1 },
	},
	{ -- 7 · Phoenix Calling: the long goodbye
		palette = {
			{ t = "SPIDER2", w = 3 },
			{ t = "CRABFLY", w = 3 },
			{ t = "BEETLE", w = 2, from = 3 },
			{ t = "SPIDER_BOSS", w = 1, from = 5 },
		},
		boss = { id = "Variant_53", count = 1 },
	},
}

-- boss hp on top of quest health scaling; keeps time-to-kill boss-like
-- (~20-30s with era-appropriate weapons) rather than a bullet sponge
quests.BOSS_HP_MUL = 0.5

--- Resolve a boss spec into a variant table with a sensible xp reward
-- (the named boss variants ship without experience_worth).
local function boss_variant(spec)
	local v
	if spec.id then
		v = data.variants[spec.id]
	elseif spec.type then
		v = data.base_variant[spec.type]
	end
	if not v then return nil end
	if (v.xp or 0) <= 10 then
		local copy = {}
		for k, val in pairs(v) do copy[k] = val end
		copy.xp = 450
		v = copy
	end
	return v
end

function quests.get(chapter, quest)
	local ch = CHAPTERS[math.min(chapter, #CHAPTERS)]

	local pool = {}
	for _, e in ipairs(ch.palette) do
		if quest >= (e.from or 1) then
			pool[#pool + 1] = { type = e.t, w = e.w }
		end
	end

	local def = {
		pool = pool,
		kills_goal = 18 + 6 * quest + 8 * (chapter - 1),
		spawn_interval = math.max(0.35, 2.0 - 0.12 * quest - 0.15 * (chapter - 1)),
		max_concurrent = math.min(45, 5 + 2 * quest + 3 * (chapter - 1)),
	}

	if quest >= 10 and ch.boss then
		local v = boss_variant(ch.boss)
		if v then
			def.boss = { variant = v, count = ch.boss.count or 1 }
		end
	end
	return def
end

return quests

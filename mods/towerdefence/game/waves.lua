-- What comes at the base, and when.
--
-- The whole design rests on the player being able to answer "what is coming"
-- with a different weapon (plans/crimsonland.md, 2026-08-18), so a wave is
-- never a generic crowd: it is one or two creature types with a shape. The
-- roster below is the original's own, picked for how differently each one has
-- to be fought:
--
--   ALIEN     fast, weak, many          -> wants spread and rate of fire
--   ZOMBIE    slow, tough, many         -> wants sustained damage
--   SPIDER1   very fast, fragile        -> punishes slow projectiles
--   LIZARD    fast and hits hard        -> wants stopping power
--   BEETLE    slow, armoured            -> wants penetration
--   SPIDER2   fast, tougher             -> mixed
--   Variant_39 ranged plasma spitter    -> must be reached, not waited out
--   DEN_ALIEN a nest that keeps hatching -> must be killed at the source
--
-- Numbers here are deliberately plain. Balance comes later, from a model
-- (/machinations-balance) rather than from guesses layered on guesses; what
-- this table has to get right today is the *shape* of the ramp, so a run has
-- somewhere to go.

local waves = {}

-- Seconds of quiet after a wave is cleared. The shopping window: it is the
-- only time the player can safely walk to the HQ, which is why it exists.
waves.LULL = 12

-- The pattern a wave repeats through, one entry per wave number. Past the end
-- of the list it keeps going by scaling the last entries (endless: there are
-- no levels, only how far you got).
-- Counts and pacing come from the economy model (docs/crimsonland/
-- td-economy-model.md), not from feel. The number that decides a wave is the
-- throughput it demands — average creature health divided by how often one
-- arrives — because that is what a defence has to match to keep the field
-- clear. Waves 1-3 sit *below* what the starting Assault Rifle sustains
-- (8.2 dps), so one competent player alone can hold them and learn the loop;
-- from wave 4 the demand passes any single weapon and towers stop being
-- optional. That crossing is the whole tutorial.
local SCRIPT = {
	{ types = { "ALIEN" }, count = 5 },
	{ types = { "ALIEN" }, count = 8 },
	{ types = { "ZOMBIE" }, count = 8 },
	{ types = { "ALIEN", "ZOMBIE" }, count = 12 },
	{ types = { "SPIDER1" }, count = 12 },
	{ types = { "ZOMBIE", "LIZARD" }, count = 14 },
	{ types = { "BEETLE" }, count = 10 },
	{ types = { "SPIDER1", "SPIDER2" }, count = 16 },
	{ types = { "LIZARD", "BEETLE" }, count = 16 },
	-- the spitter is 200 raw health against the roster's 64-90, so five of
	-- them is already the hardest thing yet; eight was a cliff
	{ types = { "Variant_39" }, count = 5 },
	-- a nest is a set piece, not a rush: it sits, hatches, and has to be gone
	-- and dug out. One is a fight; three was a wall
	{ types = { "DEN_ALIEN" }, count = 1 },
	{ types = { "ALIEN", "SPIDER2", "LIZARD" }, count = 20 },
}

-- Past the script: the same late-game mix, more of it, tougher. Growth is
-- per wave and compounding, so a run ends somewhere rather than plateauing.
local ENDLESS_TYPES = { "ALIEN", "ZOMBIE", "SPIDER1", "SPIDER2", "LIZARD", "BEETLE" }
local ENDLESS_COUNT_STEP = 2 -- extra creatures per wave past the script
local HEALTH_STEP = 0.10 -- +10% creature health per wave
local DAMAGE_STEP = 0.05 -- +5% creature damage per wave

--- The wave's composition and the multipliers it is fought at.
function waves.get(n)
	local s = SCRIPT[n]
	if not s then
		local past = n - #SCRIPT
		s = {
			types = ENDLESS_TYPES,
			count = SCRIPT[#SCRIPT].count + past * ENDLESS_COUNT_STEP,
		}
	end
	return {
		types = s.types,
		count = s.count,
		-- the same base scales vanilla uses for chapter 1, ramped by wave;
		-- creatures.xml stats are late-game values and need scaling down
		health_mul = 0.15 * (1 + (n - 1) * HEALTH_STEP),
		damage_mul = 0.40 * (1 + (n - 1) * DAMAGE_STEP),
		-- How fast the wave arrives. This, with health, is what sets the
		-- throughput a defence must match (avg health / interval): 1.5s at
		-- wave 1 asks 6.8 dps of a player who has 8.2, and the floor of 0.35
		-- is where an endless run finally outruns anything buildable.
		interval = math.max(0.35, 1.6 - n * 0.06),
	}
end

--- What the player is told during the lull. Reading the next wave is the
-- decision the whole mod is built around, so it is never a surprise.
function waves.preview(n)
	local w = waves.get(n)
	local names = {}
	for _, t in ipairs(w.types) do names[#names + 1] = t end
	return ("Wave %d: %d x %s"):format(n, w.count, table.concat(names, ", "))
end

--- Money for surviving wave `n`. Flat plus a slice of the wave's size, so a
-- long run keeps paying for the towers it is going to need.
function waves.clear_bonus(n)
	return 100 + 20 * n
end

return waves

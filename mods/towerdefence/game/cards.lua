-- Perk cards, bought rather than earned.
--
-- Crimsonland hands you a perk every level; this mod sells them, each one
-- dearer than the last, from the same HQ that sells weapons and repairs. That
-- is the third pull on one pile of money: make *me* better, make the
-- perimeter better, or put the walls back up.
--
-- Player only, by design (plans/crimsonland.md). A perk is your handling —
-- your reload, your damage, your legs. Mounts upgrade on their own track, so
-- perk multipliers never stack across eight guns at once.
--
-- THE POOL IS FILTERED BY WHAT THIS MOD ACTUALLY DOES.
--
-- The 55 perks are vanilla's, and vanilla's simulation is not this one: half
-- of them move numbers this field has never heard of (experience levels,
-- powerup drop tables, Reflex Boost, the perk that hands you a random weapon).
-- Offering those would be the worst kind of content — a card that reads well,
-- costs money and does nothing.
--
-- Rather than keep a hand-written list of "perks that work here", which would
-- rot the first time either side changed, each perk is *measured*: apply it to
-- a throwaway copy of the modifier table and see which fields it moved. If
-- every field it touched is one this field reads, the card is honest and goes
-- in the pool. Implement another modifier below and the pool grows by itself.

local perks = require("mods.vanilla.game.perks")

local cards = {}

-- Modifiers this mod's simulation actually reads. Grep them in field.lua and
-- shooter.lua: each one is applied at exactly one site.
local SUPPORTED = {
	dmg = true, -- shooter.fire
	fire = true, -- shooter.update (cooldown)
	reload = true, -- shooter.update
	clip = true, clip_add = true, -- shooter.clip_size
	speed = true, -- update_player
	bullet_speed = true, -- shooter.fire
	taken = true, -- hurt_player
	regen = true, -- update_player
	kill_heal = true, -- kill_creature
	creature_hp = true, creature_speed = true, -- add_creature, update_creatures
	score_mul = true, -- pay_for: in this mod, score is money
}

-- Fields a perk may move without the card lying, because this mod has no such
-- thing and the perk's own text does not promise one either way. `xp` is the
-- whole list: there are no levels here, so an experience multiplier is inert.
local IGNORABLE = { xp = true }

--- Does this perk do something here, and only things it can do here?
local function honest_here(perk)
	local before = perks.fresh_mods()
	local after = perks.fresh_mods()
	-- a sandbox game, so a perk that reaches for the session instead of the
	-- modifiers announces itself by touching this rather than erroring
	local touched_game = false
	local sandbox = setmetatable({}, {
		__index = function() touched_game = true return nil end,
		__newindex = function() touched_game = true end,
	})
	local ok = pcall(perk.apply, after, sandbox)
	if not ok or touched_game then return false end

	local useful = false
	for k, v in pairs(after) do
		if v ~= before[k] then
			if SUPPORTED[k] then useful = true
			elseif not IGNORABLE[k] then return false end
		end
	end
	return useful
end

local pool -- built once: honest_here is cheap but it is still 55 pcalls

--- Every perk this mod can serve, in the original's own order.
function cards.pool()
	if pool then return pool end
	pool = {}
	-- perks.all() is what builds the roster: it reads prog.dll for the names
	-- and descriptions, so it cannot happen at require time
	for _, p in pairs(perks.all()) do
		if p.apply and not p.unimplemented and honest_here(p) then
			pool[#pool + 1] = p
		end
	end
	-- perks.list is keyed by id; sort so a seeded run offers the same cards
	table.sort(pool, function(a, b) return a.index < b.index end)
	local names = {}
	for _, p in ipairs(pool) do names[#names + 1] = p.name end
	print(("[td] %d of the original's perks work in this mod: %s")
		:format(#pool, table.concat(names, ", ")))
	return pool
end

--- `n` cards the player does not own yet, shuffled. A perk gated behind
-- another (the original chains a few) only appears once its prerequisite is
-- owned, the same rule vanilla's own offer uses.
function cards.offer(n, owned)
	local available = {}
	for _, p in ipairs(cards.pool()) do
		if not owned[p.id] and (not p.requires or owned[p.requires]) then
			available[#available + 1] = p
		end
	end
	for i = 1, math.min(n, #available) do
		local j = love.math.random(i, #available)
		available[i], available[j] = available[j], available[i]
	end
	local out = {}
	for i = 1, math.min(n, #available) do out[i] = available[i] end
	return out
end

-- What the next card costs. Each one dearer than the last, so the tenth perk
-- is a campaign's worth of money and the first is one wave's — which is what
-- keeps perks competing with the perimeter instead of replacing it.
cards.FIRST_COST = 500
cards.GROWTH = 1.6

function cards.cost(taken)
	return math.floor(cards.FIRST_COST * cards.GROWTH ^ taken / 10 + 0.5) * 10
end

return cards

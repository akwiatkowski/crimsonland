-- What things cost.
--
-- Every price here comes out of the economy model
-- (docs/crimsonland/td-economy-model.md), and every one of them is computed
-- from the weapon's own numbers rather than typed in: a price list of 38
-- hand-picked values would drift away from the weapons the moment anything
-- about them changed, and there would be no way to tell whether a gun was
-- expensive because it is good or because someone guessed.

local data = require("mods.vanilla.game.data")

local prices = {}

-- A weapon is worth what it can hold: sustained damage per second, reload
-- included, because a three-round clip behind a three-second reload is not
-- the gun its burst says it is (Ion Cannon: 16.7 burst, 8.3 sustained).
--
-- Superlinear, so the top of the arsenal is a commitment rather than a step on
-- a ladder walked automatically. The exponent is what makes a Plasma Rifle
-- (30 dps) cost five times an Assault Rifle (8 dps) rather than four.
local PRICE_COEFF = 40
local PRICE_EXP = 1.3

--- Sustained damage per second: a full clip's damage over the time it takes to
-- empty it and reload it.
function prices.dps(w)
	if not w or not w.clip_size or w.clip_size <= 0 then return 0 end
	local cycle = w.clip_size * w.shoot_interval + w.reload_time
	if cycle <= 0 then return 0 end
	return w.clip_size * w.num_projectiles * w.damage_effective / cycle
end

--- What a weapon costs, rounded to something a shop can print.
function prices.weapon(w)
	local d = prices.dps(w)
	if d <= 0 then return nil end
	return math.floor(PRICE_COEFF * d ^ PRICE_EXP / 10 + 0.5) * 10
end

-- Repairing the base costs a flat amount per point. The model's reason for the
-- number: a wave that leaks around 130 points then costs about a fifth of that
-- wave's income, which is a tax the player feels without a single bad wave
-- ending the run. It is also what turns leakage into a decision — the base is
-- a buffer you can buy back, not a countdown you watch.
prices.REPAIR_PER_HP = 1

function prices.repair(missing)
	return math.floor(missing * prices.REPAIR_PER_HP + 0.5)
end

--- Everything buyable in the armoury, cheapest first. Weapons the port cannot
-- serve (no icon in the pak, so nothing for the armoury's plates to carry) are
-- left out.
function prices.catalogue()
	data.load_all()
	local list = {}
	for _, w in pairs(data.weapon_order) do
		local p = prices.weapon(w)
		if p and w.icon then
			list[#list + 1] = { weapon = w, price = p, dps = prices.dps(w) }
		end
	end
	table.sort(list, function(a, b) return a.price < b.price end)
	return list
end

return prices

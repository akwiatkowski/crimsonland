-- The perk roster.
--
-- Names, descriptions and icon numbers come from the original (game/perktext.lua
-- reads them out of prog.dll, where 10tons left the whole table). What lives
-- here is the half that was compiled C++ and cannot be read back: what each
-- perk actually does. Those are clean-room, written to the description the
-- original ships -- when it says "about 20% more ammo" the number below is
-- 1.2, and when it only says "slightly more damage" the number is a judgement.
--
-- Effects are multipliers, adders and flags on game.mods, consumed by play.lua.
-- The vocabulary, in fresh_mods() order:
--
--   dmg fire reload speed clip clip_add   weapon and movement basics
--   xp score_mul                          scoring
--   taken dodge death_chance regen        staying alive
--   kill_heal heal_mul                    healing
--   reload_guard stand_reload             reload behaviour
--   aura_dmg aura_radius plague melee     hurting what stands next to you
--   poison bullet_speed fire_dmg ion_dmg  per-shot and per-class damage
--   run_ramp stand_ramp                   effects that build while you move/stand
--   powerup_drop bonus_time field_powerup magnet   powerups
--   perk_offer level_cost                 levelling
--   empty_fire freeze_on_hit jinx time_scale bomb_on_pickup
--   angry_reload final_revenge no_random_weapon
--
-- A perk with `unimplemented` is offered to nobody and shows dimmed in the
-- gallery, with the reason on its tooltip. Three need machinery this port does
-- not have; saying so is better than quietly handing out a perk that does
-- nothing, which is the same rule the gallery already follows for the weapons
-- and perks it cannot serve.

local perktext = require("mods.vanilla.game.perktext")

local perks = {}

-- ---------------------------------------------------------------- effects

-- Keyed by the original's perk index, which is also its icon number.
local EFFECTS = {
	-- 1 Bloody Mess: "a 30% better experience ... and gain more points"
	[1] = function(mods) mods.xp = mods.xp * 1.3; mods.score_mul = mods.score_mul * 1.3 end,

	-- 2 Sharpshooter: laser sight, "slightly more damage", "one extra bullet"
	[2] = function(mods) mods.dmg = mods.dmg * 1.15; mods.clip_add = mods.clip_add + 1 end,

	-- 3 Fastloader
	[3] = function(mods) mods.reload = mods.reload * 0.6 end,

	-- 4 Lean Mean Exp Machine
	[4] = function(mods) mods.xp = mods.xp * 1.25 end,

	-- 5 Long Distance Runner: "faster the longer you run without stopping"
	[5] = function(mods) mods.run_ramp = mods.run_ramp + 0.4 end,

	-- 6 Out of Thin Air: powerups appear without blood being spilled
	[6] = function(mods) mods.field_powerup = 9 end, -- seconds between

	-- 7 Instant Winner: "5000 experience points or 10% of your total"
	[7] = function(_, game) game.xp = game.xp + math.max(5000, game.xp * 0.1) end,

	-- 8 Grim Deal: 66% more experience, and it costs you your life. Taken at
	-- face value -- it is a way to cash out a run, not a way to continue one.
	[8] = function(_, game)
		game.xp = game.xp * 1.66
		game.player.hp = 0
	end,

	-- 9 Plaguebearer: contagious, and they build resistance to it
	[9] = function(mods) mods.plague = mods.plague + 7 end,

	-- 10 Eagle Eyes: see NOT_HERE

	-- 11 Ammo Maniac: "about 20% more ammo"
	[11] = function(mods) mods.clip = mods.clip * 1.2 end,

	-- 12 Radioactive: "monsters near you lose health at a constant rate"
	[12] = function(mods)
		mods.aura_dmg = mods.aura_dmg + 8
		mods.aura_radius = math.max(mods.aura_radius, 90)
	end,

	-- 13 Fastshot
	[13] = function(mods) mods.fire = mods.fire * 1.25 end,

	-- 14 Fatal Lottery: "fifty-fifty chance of dying OR gaining 66k"
	[14] = function(_, game)
		if love.math.random() < 0.5 then
			game.player.hp = 0
		else
			game.xp = game.xp + 66000
		end
	end,

	-- 15 Random Weapon: "here, have this weapon"
	[15] = function(_, game) game.give_random_weapon() end,

	-- 16 Mr. Melee: "you hit back. Hard."
	[16] = function(mods) mods.melee = mods.melee + 55 end,

	-- 17 Slow Time, High Damage: quad damage under Reflex, half its duration
	[17] = function(mods)
		mods.reflex_dmg = 4
		mods.reflex_time = mods.reflex_time * 0.5
	end,

	-- 18 Final Revenge
	[18] = function(mods) mods.final_revenge = true end,

	-- 19 Telekinetic: "slowly but steadily move the nearest powerup"
	[19] = function(mods) mods.magnet = math.max(mods.magnet, 150) end,

	-- 20 Perk Expert: one more perk to choose from, and levels come 10% sooner
	[20] = function(mods)
		mods.perk_offer = math.max(mods.perk_offer, 4)
		mods.level_cost = mods.level_cost * 0.9
	end,

	-- 21 Unstoppable: see NOT_HERE

	-- 22 Regression Ammo: fire on an empty clip, at a cost in points
	[22] = function(mods) mods.empty_fire = "points" end,

	-- 23 Infernal Contract: 99% of your health for three more perks
	[23] = function(_, game)
		game.player.hp = math.max(1, game.player.hp * 0.01)
		game.pending_perks = game.pending_perks + 3
	end,

	-- 24 Poison Projectiles
	[24] = function(mods) mods.poison = mods.poison + 5 end,

	-- 25 Dodger
	[25] = function(mods) mods.dodge = mods.dodge + 0.2 end,

	-- 26 Lucky: "lure all kinds of powerups to appear around you more often"
	[26] = function(mods) mods.powerup_drop = mods.powerup_drop * 2 end,

	-- 27 Uranium Filled Bullets
	[27] = function(mods) mods.dmg = mods.dmg * 1.35 end,

	-- 28 Doctor: "slightly more damage", "more out of each medkit"
	[28] = function(mods)
		mods.dmg = mods.dmg * 1.1
		mods.heal_mul = mods.heal_mul * 2
	end,

	-- 29 Hot Tempered: "you need to let it out once in a while"
	[29] = function(mods) mods.temper = 9 end, -- seconds between outbursts

	-- 30 Bonus Economist
	[30] = function(mods) mods.bonus_time = mods.bonus_time * 1.5 end,

	-- 31 Thick Skinned: the one perk whose text the pak also carries, verbatim,
	-- in ui/pick-a-perk.lua -- so its numbers are the original's own
	[31] = function(mods, game)
		mods.taken = mods.taken * (2 / 3)
		game.player.hp = math.max(1, game.player.hp * (2 / 3))
	end,

	-- 32 Barrel Greaser: "more speed, more damage"
	[32] = function(mods)
		mods.bullet_speed = mods.bullet_speed * 1.4
		mods.dmg = mods.dmg * 1.15
	end,

	-- 33 Ammunition Within: an empty clip fires anyway, paid for in health
	[33] = function(mods) mods.empty_fire = "health" end,

	-- 34 Bad Blood: "movement speed slowed down and they have less health"
	[34] = function(mods)
		mods.creature_speed = mods.creature_speed * 0.75
		mods.creature_hp = mods.creature_hp * 0.75
	end,

	-- 35 Highlander: no damage, but "a 5% chance of dying" per attack
	[35] = function(mods)
		mods.taken = 0
		mods.death_chance = 0.05
	end,

	-- 36 Regeneration: "a very slow rate"
	[36] = function(mods) mods.regen = mods.regen + 1.5 end,

	-- 37 Pyromaniac: fire and plasma weapons reach further and hit harder
	[37] = function(mods)
		mods.fire_dmg = mods.fire_dmg * 1.8
		mods.fire_range = mods.fire_range * 1.4
	end,

	-- 38 Ninja: "dodging abilities to the next level"
	[38] = function(mods) mods.dodge = mods.dodge + 0.3 end,

	-- 39 Cold-blooded: everything freezes when something touches you
	[39] = function(mods) mods.freeze_on_hit = 2.5 end, -- seconds

	-- 40 Jinxed: "creatures just drop dead and accidents happen"
	[40] = function(mods) mods.jinx = mods.jinx + 0.06 end, -- kills/sec

	-- 41 Perk Master: six to choose from, levels 30% sooner in total
	[41] = function(mods)
		mods.perk_offer = math.max(mods.perk_offer, 6)
		mods.level_cost = 0.7 -- "lowered by total 30%", not compounded
	end,
	-- (requires Perk Expert -- see REQUIRES below)

	-- 42 Reflex Boosted: "the world seems to go on about 10% slower"
	[42] = function(mods) mods.time_scale = mods.time_scale * 0.9 end,

	-- 43 Greater Regeneration: "faster than ever"
	[43] = function(mods) mods.regen = mods.regen + 4 end,

	-- 44 Breathing Room: 99% of your health to clear the screen
	[44] = function(_, game)
		game.player.hp = math.max(1, game.player.hp * 0.01)
		game.kill_everything()
	end,

	-- 45 Death Clock: "exactly in 30 seconds", "all score gained will be doubled"
	[45] = function(mods, game)
		mods.taken = 0
		mods.score_mul = mods.score_mul * 2
		game.death_clock = 30
	end,

	-- 46 My Favourite Weapon: "+2 clip size, no more random weapon powerups"
	[46] = function(mods)
		mods.clip_add = mods.clip_add + 2
		mods.no_random_weapon = true
	end,

	-- 47 Bandage: "restores you to full health"
	[47] = function(_, game) game.player.hp = game.player.max_hp end,

	-- 48 Angry Reloader
	[48] = function(mods) mods.angry_reload = true end,

	-- 49 Ion Gun Master. Only half of this one lands: ion weapons do more
	-- damage, but the port gives them no blast to widen (its explosions belong
	-- to the rocket class), so "ion blast radius is also increased" is inert.
	[49] = function(mods) mods.ion_dmg = mods.ion_dmg * 1.6 end,

	-- 50 Stationary Reloader: faster standing still, and it may freeze them
	[50] = function(mods)
		mods.stand_reload = 2
		mods.freeze_on_reload = 1.5
	end,

	-- 51 Man Bomb: "each time you pick up a power up, you go boom"
	[51] = function(mods) mods.bomb_on_pickup = true end,

	-- 52 Fire Cough: "a fireball stuck in your throat. Repeatedly."
	[52] = function(mods) mods.cough = 4 end, -- seconds between fireballs

	-- 53 Living Fortress: more damage and less taken the longer you stand still
	[53] = function(mods) mods.stand_ramp = mods.stand_ramp + 0.5 end,

	-- 54 Tough Reloader: "you don't receive ANY damage while you're reloading"
	[54] = function(mods) mods.reload_guard = 0 end,

	-- 55 Lifeline 50-50: see NOT_HERE
}

-- Perks that need a system this port does not have. They are shown, dimmed,
-- with the reason -- a hole in the original's grid would read as a bug, and a
-- perk that silently does nothing is worse than one that says it cannot.
local NOT_HERE = {
	[10] = "Eagle Eyes pulls the camera back. This port draws the playfield at "
		.. "1:1 and maps the aim point through a camera with no zoom, so there "
		.. "is no higher perspective to move to yet.",
	[21] = "Unstoppable ignores the slow from a monster's hit. Nothing in this "
		.. "port slows the player on a hit, so there is nothing to ignore.",
	[55] = "Lifeline 50-50 removes half the wrong answers, which belongs to "
		.. "Typ'o'Shooter -- the typing mode this port does not implement.",
}

-- Perks that only enter the pool once another is owned.
local REQUIRES = {
	[41] = 20, -- Perk Master follows Perk Expert, as its own text says
}

-- ------------------------------------------------------------------ roster

perks.list = {}

local function build()
	if #perks.list > 0 then return end
	local text = perktext.all()
	-- The roster is the original's, so it is as long as the original's table.
	-- With prog.dll unreadable there is no table and no perks; the galleries
	-- and PickAPerk handle an empty roster the same way they handle a short one.
	for index, entry in pairs(text) do
		perks.list[index] = {
			id = index, -- the original's index, which is also its icon number
			index = index,
			abbrev = entry.abbrev,
			name = entry.name,
			desc = entry.desc,
			icon = ("perks/perk_%02d.png"):format(index),
			apply = EFFECTS[index],
			unimplemented = NOT_HERE[index],
			requires = REQUIRES[index],
		}
	end
end

--- The roster, built on first use (it needs the file system, so not at require
-- time -- love.load has not run yet when the module tree is being required).
function perks.all()
	build()
	return perks.list
end

function perks.get(index)
	build()
	return perks.list[index]
end

function perks.fresh_mods()
	return {
		dmg = 1, fire = 1, reload = 1, speed = 1, clip = 1, clip_add = 0,
		xp = 1, score_mul = 1,
		taken = 1, dodge = 0, death_chance = 0, regen = 0,
		kill_heal = 0, heal_mul = 1,
		reload_guard = 1, stand_reload = 1,
		aura_dmg = 0, aura_radius = 0, plague = 0, melee = 0,
		poison = 0, bullet_speed = 1, fire_dmg = 1, fire_range = 1,
		ion_dmg = 1,
		run_ramp = 0, stand_ramp = 0,
		powerup_drop = 1, bonus_time = 1, field_powerup = 0, magnet = 0,
		perk_offer = 3, level_cost = 1,
		creature_speed = 1, creature_hp = 1,
		reflex_dmg = 1, reflex_time = 1,
		temper = 0, cough = 0, jinx = 0, time_scale = 1,
		empty_fire = nil, freeze_on_hit = 0, freeze_on_reload = 0,
		bomb_on_pickup = false, angry_reload = false, final_revenge = false,
		no_random_weapon = false,
	}
end

--- Pick `n` perks the player does not own yet. A perk with a `requires` only
-- enters the pool once its prerequisite is owned, and one this port cannot
-- serve never enters it at all.
function perks.offer(n, owned)
	build()
	local pool = {}
	for _, p in pairs(perks.list) do
		if not owned[p.id] and p.apply and not p.unimplemented
			and (not p.requires or owned[p.requires]) then
			pool[#pool + 1] = p
		end
	end
	-- stable order before shuffling, so a seeded run is reproducible
	table.sort(pool, function(a, b) return a.index < b.index end)
	-- Fisher-Yates prefix shuffle
	for i = 1, math.min(n, #pool) do
		local j = love.math.random(i, #pool)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #pool) do out[i] = pool[i] end
	return out
end

return perks

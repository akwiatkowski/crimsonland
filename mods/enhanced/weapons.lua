-- The sixteen weapons this cartridge adds, in the shape weapons.xml uses.
--
-- They are declared exactly as a pak row is and go through the same builder
-- (data.weapon_overlay -> build_weapon), so each one derives its spread, its
-- projectile family, its bolt size and its brass flag from the same seven
-- numbers the original's own weapons do. Nothing here is a special case in the
-- simulation; what makes them different is the verbs in traits.lua.
--
-- WHY THESE SIXTEEN. Not "more guns" -- the port already had 38 that collapsed
-- to four behaviours, which is what traits.lua was built to answer. Each of
-- these owns one decision nothing else in the arsenal asks for, and the two
-- families are deliberately opposed:
--
--   tesla  you do not aim, you position. Damage goes where the crowd is.
--   rail   you aim exactly and pay for it. Damage goes where the line is.
--
-- That rule is load-bearing: give a tesla weapon precise aiming or a rail
-- weapon auto-targeting and both families collapse back into "point at thing,
-- thing dies", which is the arsenal we already had.
--
-- NUMBERS. `projectile_damage` is authored per round rather than left at 1,
-- because the 1 in the pak means "the C++ engine knew" and the port's
-- replacement for that knowledge is a heuristic off `stat_damage` (data.lua).
-- Authoring it means these weapons are exactly as strong as they say. They are
-- calibrated against the pak's own sustained damage per second -- magazine
-- divided by (clip * interval + reload) -- which runs from the Pistol's 5 to
-- the Blade Gun's 95, with most of the arsenal between 15 and 40. These sit in
-- the upper half, because they arrive at the far end of the weapon pool and a
-- late weapon that felt weaker than an Assault Rifle would just be noise.
--
-- `projectile_range` is multiplied by 4 into world pixels (RANGE_SCALE), and
-- `projectile_speed` by 16 (BULLET_SPEED_SCALE). The playfield is 1820x1024,
-- so the pak's uniform 300 reaches almost across it.
--
-- WHAT THEY DO NOT GET. Pyromaniac and Ion Gun Master are keyed to the
-- original's weapon ids (play.lua), so no weapon here benefits from them. That
-- is left alone on purpose: those perks name the original's guns in their own
-- text, and quietly widening them would change vanilla's balance from a mod.

local traits = require("mods.enhanced.traits")

-- Where this cartridge's weapons sit in weapons.xml's numbering. The pak uses
-- 1..32, then 44..48 and 63; starting at 64 leaves that whole space alone, so
-- `data.weapon_order` stays free of collisions and the gallery plates -- which
-- are addressed by that same numbering -- keep pointing at what they always
-- pointed at.
local FIRST_INDEX = 64

-- Bit 0 of `flags` is "ejects brass" and bit 4 (16) is "draws as a plasma
-- blob"; `type` picks the projectile family, 0 kinetic / 1 flame / 2 rocket /
-- 3 pulse / 4 ion. Named here because a bare 9 in a table row is unreadable.
local BRASS = 1
local KINETIC, FLAME, ROCKET, ION = 0, 1, 2, 4

-- Ammo cells come out of the pak: a tesla weapon burns xenon, a rail slug is a
-- gauss slug, acid is a fuel canister. Sixteen new 64x64 cells would be
-- sixteen pieces of art nobody looks at -- the cell is a 30px HUD readout.
local AMMO_XENON = "weapons/ammo/xenon.png"
local AMMO_GAUSS = "weapons/ammo/gauss.png"
local AMMO_FUEL = "weapons/ammo/fuel.png"
local AMMO_ROCKET = "weapons/ammo/rocket.png"
local AMMO_12G = "weapons/ammo/12gauge.png"
local AMMO_9MM = "weapons/ammo/9mm.png"

-- Ordered as they are offered: `weapon_cap` grows through a run and this list
-- is walked from the front, so the first entries are the ones a player meets
-- first. The tamer weapons lead; the ones that need the whole field to
-- themselves (Rail Cannon, Storm Ring) arrive last.
local WEAPONS = {
	{
		id = "BOUNCER_SMG",
		name = "Bouncer SMG",
		type = KINETIC,
		flags = BRASS,
		clip_size = 34,
		shoot_interval = 0.09,
		reload_time = 1.4,
		num_projectiles = 1,
		projectile_speed = 58,
		projectile_damage = 3.4,
		projectile_range = 225,
		stat_damage = 0.5,
		stat_accuracy = 0.25,
		snd_fire = "sfx/hrpm_fire",
		snd_reload = "sfx/autorifle_reload",
		bm_icon = "enhanced/bouncer-smg.png",
		ammo_icon = AMMO_9MM,
	},
	{
		id = "TESLA_ARC",
		name = "Tesla Arc",
		type = ION,
		flags = 0,
		clip_size = 40,
		shoot_interval = 0.12,
		reload_time = 1.6,
		num_projectiles = 1,
		-- short and immediate: the arc is at the target before you can watch it
		projectile_speed = 150,
		projectile_damage = 6,
		projectile_range = 70,
		stat_damage = 0.62,
		-- the arc locks on, so precision is not what this rating means here;
		-- it only keeps the muzzle line from being perfectly straight
		stat_accuracy = 0.5,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/tesla-arc.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "NAIL_GRENADE",
		name = "Nail Grenade",
		type = ROCKET,
		flags = 0,
		clip_size = 5,
		shoot_interval = 0.8,
		reload_time = 2.0,
		num_projectiles = 1,
		projectile_speed = 55,
		projectile_damage = 8,
		projectile_range = 160,
		stat_damage = 0.72,
		stat_accuracy = 0.7,
		snd_fire = "sfx/rocket_fire",
		snd_reload = "sfx/autorifle_reload",
		bm_icon = "enhanced/nail-grenade.png",
		ammo_icon = AMMO_ROCKET,
	},
	{
		id = "ACID_SPRAYER",
		name = "Acid Sprayer",
		type = FLAME,
		flags = 0,
		clip_size = 60,
		shoot_interval = 0.02,
		reload_time = 2.2,
		num_projectiles = 1,
		projectile_speed = 40,
		projectile_damage = 1.6,
		-- a cone, not a beam: the reach is what makes it a close-range weapon
		projectile_range = 65,
		stat_damage = 0.78,
		stat_accuracy = 0.05,
		snd_fire = "sfx/flamer_fire_01",
		snd_reload = "sfx/autorifle_reload",
		bm_icon = "enhanced/acid-sprayer.png",
		ammo_icon = AMMO_FUEL,
	},
	{
		id = "SNIPER_RAIL",
		name = "Sniper Rail",
		type = KINETIC,
		flags = BRASS,
		clip_size = 5,
		shoot_interval = 0.9,
		reload_time = 2.4,
		num_projectiles = 1,
		projectile_speed = 230,
		projectile_damage = 14,
		projectile_range = 300,
		stat_damage = 0.8,
		stat_accuracy = 0.92,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/sniper-rail.png",
		ammo_icon = AMMO_GAUSS,
	},
	{
		id = "NODE_GUN",
		name = "Node Gun",
		type = ION,
		flags = 0,
		clip_size = 12,
		shoot_interval = 0.35,
		reload_time = 2.0,
		num_projectiles = 1,
		projectile_speed = 60,
		-- deliberately feeble on its own: a dart is an investment, and the
		-- payoff is the network it joins
		projectile_damage = 3,
		projectile_range = 175,
		stat_damage = 0.4,
		stat_accuracy = 0.55,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/node-gun.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "FLAK_CANNON",
		name = "Flak Cannon",
		type = ROCKET,
		flags = BRASS,
		clip_size = 4,
		shoot_interval = 1.0,
		reload_time = 2.4,
		num_projectiles = 1,
		projectile_speed = 50,
		projectile_damage = 6,
		projectile_range = 140,
		stat_damage = 0.85,
		stat_accuracy = 0.6,
		snd_fire = "sfx/shotgun_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/flak-cannon.png",
		ammo_icon = AMMO_12G,
	},
	{
		id = "PRISM_RAIL",
		name = "Prism Rail",
		type = KINETIC,
		flags = BRASS,
		clip_size = 8,
		shoot_interval = 0.55,
		reload_time = 2.0,
		num_projectiles = 1,
		projectile_speed = 200,
		projectile_damage = 16,
		projectile_range = 250,
		stat_damage = 0.82,
		stat_accuracy = 0.9,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/prism-rail.png",
		ammo_icon = AMMO_GAUSS,
	},
	{
		id = "ARC_LASSO",
		name = "Arc Lasso",
		type = ION,
		flags = 0,
		clip_size = 15,
		shoot_interval = 0.4,
		reload_time = 1.8,
		num_projectiles = 1,
		projectile_speed = 70,
		projectile_damage = 5,
		projectile_range = 75,
		stat_damage = 0.55,
		stat_accuracy = 0.3,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/arc-lasso.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "TRACER_RAIL",
		name = "Tracer Rail",
		type = KINETIC,
		flags = BRASS,
		clip_size = 8,
		shoot_interval = 0.6,
		reload_time = 2.0,
		num_projectiles = 1,
		projectile_speed = 190,
		projectile_damage = 12,
		projectile_range = 300,
		stat_damage = 0.8,
		stat_accuracy = 0.9,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/tracer-rail.png",
		ammo_icon = AMMO_GAUSS,
	},
	{
		id = "RAIL_SPIKE",
		name = "Rail Spike",
		type = KINETIC,
		flags = BRASS,
		clip_size = 6,
		-- the interval is what follows the *release*; the wait before a shot is
		-- the charge, and the player sets that
		shoot_interval = 0.2,
		reload_time = 2.2,
		num_projectiles = 1,
		projectile_speed = 215,
		-- what an untouched trigger is worth. A full charge multiplies it (see
		-- traits.lua CHARGE) -- this is the floor, not the weapon
		projectile_damage = 10,
		projectile_range = 300,
		stat_damage = 0.9,
		stat_accuracy = 0.93,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/rail-spike.png",
		ammo_icon = AMMO_GAUSS,
	},
	{
		id = "CAPACITOR_RIFLE",
		name = "Capacitor Rifle",
		type = ION,
		flags = 0,
		clip_size = 20,
		shoot_interval = 0.5,
		reload_time = 1.8,
		num_projectiles = 1,
		projectile_speed = 90,
		projectile_damage = 8,
		projectile_range = 175,
		stat_damage = 0.7,
		stat_accuracy = 0.6,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/capacitor-rifle.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "BALL_LIGHTNING",
		name = "Ball Lightning",
		type = ION,
		flags = 0,
		clip_size = 4,
		shoot_interval = 1.2,
		reload_time = 2.6,
		num_projectiles = 1,
		-- a drift, not a shot: you place it and then live with where it went
		projectile_speed = 8,
		projectile_damage = 20,
		projectile_range = 130,
		stat_damage = 0.86,
		stat_accuracy = 0.45,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/ball-lightning.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "TETHER_RAIL",
		name = "Tether Rail",
		type = KINETIC,
		flags = BRASS,
		clip_size = 10,
		shoot_interval = 0.4,
		reload_time = 1.8,
		num_projectiles = 1,
		projectile_speed = 200,
		projectile_damage = 18,
		projectile_range = 300,
		stat_damage = 0.84,
		stat_accuracy = 0.9,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/tether-rail.png",
		ammo_icon = AMMO_GAUSS,
	},
	{
		id = "STORM_RING",
		name = "Storm Ring",
		type = ION,
		flags = 0,
		-- not rounds: this is the charge the ring spends, drained while the
		-- trigger is held and paid back by a reload
		clip_size = 100,
		shoot_interval = 0.06,
		reload_time = 3.0,
		num_projectiles = 1,
		projectile_speed = 10,
		projectile_damage = 4,
		projectile_range = 100,
		stat_damage = 0.75,
		-- the mouse does nothing at all with this one
		stat_accuracy = 0.5,
		snd_fire = "sfx/shock_fire",
		snd_reload = "sfx/shock_reload",
		bm_icon = "enhanced/storm-ring.png",
		ammo_icon = AMMO_XENON,
	},
	{
		id = "RAIL_CANNON",
		name = "Rail Cannon",
		type = KINETIC,
		flags = BRASS,
		-- two shots and a long wait: the panic-button rail, against the Spike's
		-- committed one
		clip_size = 2,
		shoot_interval = 0.35,
		reload_time = 3.2,
		num_projectiles = 1,
		projectile_speed = 215,
		projectile_damage = 55,
		projectile_range = 300,
		stat_damage = 1.0,
		stat_accuracy = 0.88,
		snd_fire = "sfx/gauss_fire",
		snd_reload = "sfx/shotgun_reload",
		bm_icon = "enhanced/rail-cannon.png",
		ammo_icon = AMMO_GAUSS,
	},
}

-- Numbering and verbs attached here rather than repeated sixteen times: the
-- index is the entry's place in this list, and the verbs are looked up by id
-- in traits.lua, which is the same relationship vanilla's overlay has to
-- weapons.xml.
for i, w in ipairs(WEAPONS) do
	w.index = FIRST_INDEX + i - 1
	w.traits = traits[w.id]
end

return WEAPONS

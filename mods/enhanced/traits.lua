-- What each of this cartridge's weapons *does*, keyed by id.
--
-- Same relationship vanilla's own traits.lua has to weapons.xml: the numbers
-- are in weapons.lua and the verbs are here. Vanilla's nine verbs (pierce,
-- ricochet, homing, accel, blast, split, chain, slow, shrink) are declared as
-- plain data and honoured by vanilla; anything vanilla has no word for is a
-- function on the same table, called through one of the four seams:
--
--   deliver(game, p, shot)      instead of the default spawn loop
--   trigger(game, p, want, dt)  instead of "the trigger is down and it is ready"
--   on_hit(game, b, c)          the moment a round connects, before the hit
--   on_end(game, b)             wherever a round stopped
--
-- WHAT IS DELIBERATELY NOT HERE. Two verbs from the design round did not
-- survive contact with the code, and their absence is the design, not an
-- omission:
--
--   * per-body damage decay on a piercing round. Rail Spike and Rail Cannon
--     were to differ on it; they differ on charge and on how many bodies they
--     go through instead, which is a difference you can see. Implementing the
--     decay meant a verb in vanilla's bullet loop that no vanilla weapon uses.
--   * the Nail Grenade's two-second fuse. At 880 px/s over a 640 px maximum
--     throw the flight is three-quarters of a second, so the fuse can never be
--     what ends the round. A timer that cannot fire is not a mechanic.

local combat = require("mods.enhanced.combat")

local traits = {}

-- ------------------------------------------------------------------ kinetic

-- Every bounce is worth a quarter more, up to three. That makes a corner an
-- asset instead of a wall, which no other weapon in the arsenal says about the
-- edge of the playfield.
local BOUNCE_BONUS = 0.25

traits.BOUNCER_SMG = {
	ricochet = 3,
	on_hit = function(game, b, c)
		local n = b.bounces or 0
		if n > 0 then
			b.damage = b.damage * (1 + BOUNCE_BONUS * n)
			combat.used("bounce_ramp")
		end
	end,
}

-- -------------------------------------------------------------------- tesla
--
-- One rule across the family: you do not aim these, you position yourself.
-- Every one of them is the `chain` verb with a different *origin* -- the
-- muzzle, a stuck dart, a banked charge, a drifting orb, the trooper's own
-- feet -- which is why the family is cheap to build and still varied to hold.

-- Reach of the Tesla Arc's lock. Shorter than the round's own range so the
-- weapon has to be walked into a crowd rather than pointed at one.
local ARC_LOCK = 280

traits.TESLA_ARC = {
	chain = { jumps = 3, range = 140, decay = 0.6 },
	--- Fire at the nearest thing rather than at the cursor. This is the
	-- family's identity in one function: the mouse chooses nothing, and what
	-- the player controls is which crowd they are standing next to.
	deliver = function(game, p, shot)
		local target = combat.nearest(p.x, p.y, ARC_LOCK)
		local angle = shot.angle
		if target then
			angle = math.atan2(target.y - p.y, target.x - p.x)
			combat.used("autolock")
		end
		game.spawn_round(shot, angle, {
			x = p.x + math.cos(angle) * 20,
			y = p.y + math.sin(angle) * 20,
		})
	end,
}

-- What a discharge through the network is worth per body, and what each
-- further body costs it. Generous decay: the point of seeding a crowd is that
-- the back of it still gets hit.
local NODE_DISCHARGE = 0.8
local NODE_DECAY = 0.85

traits.NODE_GUN = {
	--- The dart sticks, and every dart already stuck fires at the same time.
	-- Distance between nodes is not a parameter: reaching across the field is
	-- exactly what the investment bought.
	on_hit = function(game, b, c)
		combat.stick_node(c)
		combat.discharge_nodes(b.damage * NODE_DISCHARGE, NODE_DECAY)
	end,
}

-- A charge every third of a second, five at most, and the sixth goes into you.
local CAP_STEP = 0.33
local CAP_MAX = 5
local CAP_BACKLASH = 14
local CAP_CHAIN = { range = 170, decay = 0.8 }

traits.CAPACITOR_RIFLE = {
	--- Push your luck on every shot: each held third of a second is another
	-- jump on the round, and holding one beat too long dumps the lot into the
	-- trooper. The gamble is the weapon -- released early it is a poor rifle.
	trigger = function(game, p, want, dt)
		if p.reloading > 0 then
			combat.charges, combat.hold_t = 0, 0
			return
		end
		if want.fire then
			combat.hold_t = combat.hold_t + dt
			if combat.hold_t >= CAP_STEP then
				combat.hold_t = 0
				combat.charges = combat.charges + 1
				if combat.charges > CAP_MAX then
					combat.charges = 0
					game.on_attacked(CAP_BACKLASH)
					game.shake(6)
					combat.used("capacitor_backlash")
				end
			end
		elseif combat.charges > 0 and p.cooldown <= 0 then
			local jumps = combat.charges
			combat.charges, combat.hold_t = 0, 0
			combat.used("capacitor")
			game.fire_shot({
				deliver = function(g, pl, shot)
					local b = g.spawn_round(shot, shot.angle
						+ (love.math.random() - 0.5) * 2 * shot.spread)
					-- the round's own table, not the weapon's: how far this
					-- one arcs was decided by how long the trigger was held
					b.traits = { chain = {
						jumps = jumps,
						range = CAP_CHAIN.range,
						decay = CAP_CHAIN.decay,
					} }
				end,
			})
		end
	end,
}

local ORB_LIFE = 4.5
-- Share of the round's damage each arc carries. An orb lives for four and a
-- half seconds and arcs five times a second, so this number is multiplied by
-- twenty before it means anything: at a third it made ball lightning the best
-- weapon in the game by a distance, which is not what "place a hazard" should
-- buy.
local ORB_BITE = 0.24

traits.BALL_LIGHTNING = {
	--- No round at all: what leaves the barrel is a world object, and after
	-- that neither side owns the ground it drifts over. It is the only weapon
	-- here that is dangerous to the player who fired it, which is what makes
	-- placing one a decision rather than an attack.
	deliver = function(game, p, shot)
		combat.add_orb(shot.x, shot.y,
			math.cos(shot.angle), math.sin(shot.angle),
			shot.speed, ORB_LIFE, shot.damage * ORB_BITE)
	end,
}

-- How hard the ring bites, per creature per second, and what a second of
-- uptime costs out of the hundred-unit charge.
--
-- Written down rather than derived from `damage_effective` like everything
-- else here: this weapon has no rounds, so "damage per round" is not a number
-- it has. Deriving it anyway put the ring at four damage a second, which is
-- less than a pistol against one creature while being the shortest-ranged
-- weapon in the arsenal.
local RING_DPS = 26
local RING_TICK = 0.18
local RING_DRAIN = 9 -- charge a second, so eleven seconds of uptime a clip

traits.STORM_RING = {
	--- The mouse does nothing. Holding the trigger closes the ring in and
	-- drains the clip; letting go opens it back out. Uptime and reach are the
	-- same resource, which is the only decision this weapon asks and the whole
	-- reason it exists.
	trigger = function(game, p, want, dt)
		if p.reloading > 0 then return end
		if not want.fire then
			p.ring_tick = 0
			return
		end
		if p.ammo <= 0 then
			-- empty: it reloads like anything else rather than firing on nothing
			p.reloading = p.weapon.reload_time * game.mods.reload
			p.reload_total = p.reloading
			return
		end
		-- closing in is what firing costs, before anything is hurt
		combat.ring_r = math.max(combat.RING_MIN,
			combat.ring_r - dt * (combat.RING_CLOSE + combat.RING_OPEN))
		-- whole units out of the clip, with the remainder carried: the HUD
		-- prints the count through a seven-segment face and 87.4 rounds is not
		-- a thing that face can say
		p.ring_drain = (p.ring_drain or 0) + RING_DRAIN * dt
		local spend = math.floor(p.ring_drain)
		if spend > 0 then
			p.ring_drain = p.ring_drain - spend
			p.ammo = math.max(0, p.ammo - spend)
		end

		p.ring_tick = (p.ring_tick or 0) + dt
		if p.ring_tick < RING_TICK then return end
		local bite = RING_DPS * game.mods.dmg * p.ring_tick
		p.ring_tick = 0
		p.muzzle = 0.05
		combat.used("ring")
		-- A tick is this weapon's shot, and it has to be counted as one. Every
		-- other gun spends `fire_shot`, which does this; the ring never goes
		-- through it, and a weapon that fires no shots cannot be anybody's
		-- Favorite Weapon on the end screen however much of the quest it won.
		game.shots = game.shots + 1
		game.weapon_shots[p.weapon.id] = (game.weapon_shots[p.weapon.id] or 0) + 1
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				local dx, dy = c.x - p.x, c.y - p.y
				if dx * dx + dy * dy < combat.ring_r * combat.ring_r then
					game.arcs[#game.arcs + 1] =
						{ x1 = p.x, y1 = p.y, x2 = c.x, y2 = c.y, t = 0 }
					game.damage_creature(c, bite)
				end
			end
		end
	end,
}

-- How far the lasso drags, and how hard. A shove per hit rather than a pull
-- over time: it has to be legible in one shot or the player cannot tell it
-- from nothing happening.
local LASSO_RANGE = 190
local LASSO_PULL = 13

traits.ARC_LASSO = {
	chain = { jumps = 3, range = 160, decay = 0.8 },
	--- Everything near what was hit is dragged toward it. The lasso barely
	-- kills; what it does is compact a loose crowd into a knot, which is the
	-- shape every other tesla weapon wants and none of them can make.
	on_hit = function(game, b, c)
		combat.lasso(c, LASSO_RANGE, LASSO_PULL)
	end,
}

-- --------------------------------------------------------------------- rail
--
-- The opposite rule: these are aimed exactly and paid for exactly. Each owns
-- one axis nothing else in the family touches -- commitment before the shot,
-- burst capacity, distance to the target, geometry after the first body, how
-- long the path lasts, and where the shot starts.

local RAIL_COLOR = { 0.72, 0.88, 1.0 }

--- The line a rail leaves for a moment. Drawn from the muzzle to wherever the
-- round is headed, because a weapon that fires a near-instant slug otherwise
-- shows the player nothing at all between the trigger and the corpse.
local function rail_flash(shot, angle, reach)
	combat.beam(shot.x, shot.y,
		shot.x + math.cos(angle) * reach, shot.y + math.sin(angle) * reach,
		RAIL_COLOR[1], RAIL_COLOR[2], RAIL_COLOR[3], 3, 0.1)
end

-- Damage at the muzzle and damage across the field, and the distance that
-- counts as "across the field". The playfield is 1820x1024, so 900 px is
-- about half of it -- far enough that the bonus is a position you have to
-- take, near enough that it is reachable in a real fight.
local SNIPER_NEAR = 0.55
local SNIPER_FAR = 3.2
local SNIPER_FULL = 900

traits.SNIPER_RAIL = {
	pierce = 2,
	--- Damage from the distance to the point being aimed at, not from the
	-- distance the round ends up travelling. Both are defensible; this one is
	-- the one the player can *see*, because the crosshair is already there.
	-- The inverse of every other gun in the game, which either does not care
	-- about range or quietly loses to it.
	deliver = function(game, p, shot)
		local _, _, dist = combat.aim_point(p)
		local k = SNIPER_NEAR + (SNIPER_FAR - SNIPER_NEAR)
			* math.min(1, dist / SNIPER_FULL)
		local angle = shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle, { damage = shot.damage * k })
		rail_flash(shot, angle, math.min(dist, shot.range))
		combat.used("distance_scale")
	end,
}

-- Two shots, then three and a bit seconds of nothing. Everything it does is
-- meant to be worth that wait: it goes through eight bodies without losing a
-- point, and it moves what survives.
local CANNON_KNOCKBACK = 26

traits.RAIL_CANNON = {
	pierce = 8,
	deliver = function(game, p, shot)
		local angle = shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle)
		rail_flash(shot, angle, shot.range)
		game.shake(4)
	end,
	--- Shoved back down the lane rather than merely hit. On a weapon that
	-- fires twice and then reloads for three seconds, the yard of ground this
	-- buys is part of what the shot is for.
	on_hit = function(game, b, c)
		c.x = math.max(16, math.min(game.WORLD_W - 16, c.x + b.dx * CANNON_KNOCKBACK))
		c.y = math.max(16, math.min(game.WORLD_H - 16, c.y + b.dy * CANNON_KNOCKBACK))
		combat.used("knockback")
	end,
}

-- What a fully charged spike is worth against a tapped one.
--
-- It has to beat tapping *per second*, not merely per shot, or charging is
-- pure downside and the weapon's whole decision is a trap. Six rounds tapped
-- is 17.6 damage a second; at five and a half this came out at 17.9, which is
-- the same weapon with extra steps. At eight it is 26, so committing to the
-- charge buys about half as much again -- and pays for it with two and a half
-- seconds of not shooting anything while a crowd closes.
local SPIKE_FULL_MUL = 8.0

traits.RAIL_SPIKE = {
	pierce = 4,
	--- Hold to charge, release to fire. The commitment is the weapon: a full
	-- spike is worth five and a half of a tapped one, and the two and a half
	-- seconds are two and a half seconds you are not shooting anything.
	trigger = function(game, p, want, dt)
		if p.reloading > 0 then
			combat.charge_t = 0
			return
		end
		if want.fire then
			combat.charge_t = math.min(combat.CHARGE_FULL, combat.charge_t + dt)
		elseif combat.charge_t > 0 then
			local k = combat.charge_t / combat.CHARGE_FULL
			combat.charge_t = 0
			if p.cooldown <= 0 then
				combat.used("charge")
				game.fire_shot({ damage_mul = 1 + (SPIKE_FULL_MUL - 1) * k })
			end
		end
	end,
	deliver = function(game, p, shot)
		local angle = shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle)
		rail_flash(shot, angle, shot.range)
	end,
}

-- Two children at 24 degrees either side, carrying six tenths each, and
-- reaching a third of the parent's range.
local PRISM_ANGLE = 24
local PRISM_SHARE = 0.6
local PRISM_REACH = 420

traits.PRISM_RAIL = {
	--- The beam breaks at the first body it finds. Where the fan lands is
	-- therefore chosen by which creature you shoot *first*, which is a
	-- placement decision no other weapon in the game offers.
	on_hit = function(game, b, c)
		local base = math.atan2(b.dy, b.dx)
		for _, side in ipairs({ -1, 1 }) do
			local angle = base + side * math.rad(PRISM_ANGLE)
			-- children pierce and go no further than that: given the parent's
			-- own traits they would break at their own first body and one shot
			-- would fill the field
			combat.fork(b, angle, PRISM_SHARE, PRISM_REACH, { pierce = 1 })
			combat.beam(b.x, b.y,
				b.x + math.cos(angle) * 60, b.y + math.sin(angle) * 60,
				RAIL_COLOR[1], RAIL_COLOR[2], RAIL_COLOR[3], 2, 0.1)
		end
		combat.used("prism")
		return false -- the parent stops here; the fan is what carries on
	end,
}

local BURN_LIFE = 2.0
local BURN_DPS = 45
local BURN_WIDTH = 6
local BURN_MIN = 260 -- a line laid at your feet would only ever burn you

traits.TRACER_RAIL = {
	pierce = 1,
	--- The path stays. A rail shot stops being an event and becomes a fence,
	-- so where you fire matters after the shot is over -- which is the one
	-- thing a hitscan weapon normally cannot say.
	deliver = function(game, p, shot)
		local _, _, dist = combat.aim_point(p)
		local reach = math.max(BURN_MIN, math.min(dist, shot.range))
		local angle = shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle)
		combat.add_burn(shot.x, shot.y,
			shot.x + math.cos(angle) * reach, shot.y + math.sin(angle) * reach,
			BURN_LIFE, BURN_DPS, BURN_WIDTH)
	end,
}

-- How long the trigger has to be off before the anchor is abandoned. Long
-- enough to survive a reload, short enough that walking away re-plants.
local TETHER_REPLANT = 0.7

traits.TETHER_RAIL = {
	pierce = 2,
	--- The anchor is planted where you stood when you started firing, and it
	-- is abandoned when you stop for long enough. Every other weapon in the
	-- game assumes a shot starts at the player (play.lua); this is the one
	-- that does not, and what it buys is an angle you are not standing in.
	trigger = function(game, p, want, dt)
		if want.fire then
			combat.idle_t = 0
			if not combat.anchor then
				combat.anchor = { x = p.x, y = p.y }
				combat.used("anchor")
			end
			if p.reloading <= 0 and p.cooldown <= 0 then game.fire_shot() end
		else
			combat.idle_t = combat.idle_t + dt
			if combat.idle_t >= TETHER_REPLANT then combat.anchor = nil end
		end
	end,
	deliver = function(game, p, shot)
		local origin = combat.anchor or p
		local ax, ay = combat.aim_point(p)
		local angle = math.atan2(ay - origin.y, ax - origin.x)
			+ (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle, {
			x = origin.x + math.cos(angle) * 20,
			y = origin.y + math.sin(angle) * 20,
		})
		combat.beam(origin.x, origin.y,
			origin.x + math.cos(angle) * shot.range,
			origin.y + math.sin(angle) * shot.range,
			RAIL_COLOR[1], RAIL_COLOR[2], RAIL_COLOR[3], 3, 0.1)
	end,
}

-- ----------------------------------------------------------------- ordnance
--
-- The two weapons that finally spend the cursor's *distance*. Everything in
-- the pak reads the aim point, takes the angle and throws the rest away
-- (play.lua), so where you are pointing has never meant a place before.

--- Throw a round to the point under the cursor, or as near to it as this
-- weapon reaches. Vanilla's own range check is what resolves it: a round whose
-- reach is exactly the distance to the target dies there, and a round carrying
-- `blast` detonates where it dies. No new machinery, and it means a lobbed
-- shot that meets something on the way goes off against it instead.
local function lob(game, p, shot)
	local ax, ay, dist = combat.aim_point(p)
	local angle = math.atan2(ay - p.y, ax - p.x)
		+ (love.math.random() - 0.5) * 2 * shot.spread
	combat.used("lob")
	return game.spawn_round(shot, angle, { dist_left = math.min(dist, shot.range) })
end

traits.NAIL_GRENADE = {
	blast = { radius = 110, damage = 3.5 },
	deliver = lob,
}

traits.FLAK_CANNON = {
	-- The payload is vanilla's `split` with the spread opened right out: a
	-- shell that breaks into fourteen pieces going everywhere is what a flak
	-- burst is, and the verb for it already existed.
	split = { count = 14, spread = 170, damage = 1.15 },
	deliver = lob,
}

-- One puff in five leaves something on the ground. All of them would pave the
-- field -- the sprayer empties sixty rounds in a little over a second.
local POOL_CHANCE = 0.2
local POOL_RADIUS = 40
local POOL_LIFE = 4.5
local POOL_DPS = 16
local POOL_SLOW = 0.65

traits.ACID_SPRAYER = {
	slow = { factor = 0.8, seconds = 1.0 },
	--- A ragged cone, the way the pak's own flamethrowers spray. The reach is
	-- jittered per puff here rather than by vanilla, because vanilla's jitter
	-- is keyed to the original's three flame weapons by id.
	deliver = function(game, p, shot)
		local angle = shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
		game.spawn_round(shot, angle, {
			dist_left = shot.range * (0.6 + love.math.random() * 0.4),
			-- drawn as a burning puff rather than a bullet; the colour comes
			-- from the flame family it declares in weapons.lua
			flame = true,
		})
	end,
	--- What makes it a weapon about ground rather than a weapon about damage:
	-- what it sprayed over stays expensive to stand in for a few seconds.
	on_end = function(game, b)
		if love.math.random() < POOL_CHANCE then
			combat.add_pool(b.x, b.y, POOL_RADIUS, POOL_LIFE, POOL_DPS, POOL_SLOW)
		end
	end,
}

return traits

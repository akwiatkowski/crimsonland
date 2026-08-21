-- One secondary per weapon family, on the right mouse button.
--
-- Keyed off `proj_art` -- the classification weapons.xml already makes and
-- data.lua already reads, off each weapon's `type` and bit 4 of its `flags` --
-- so every gun in the game has a secondary without a table naming any of them.
-- That includes the pak's own 31: holding an Assault Rifle in this cartridge
-- gets you the kinetic slug, and holding a Plasma Cannon gets you the chill
-- bomb. Sixteen new weapons that alone had a second trigger would have been a
-- feature of the new arsenal; this is a feature of the game.
--
-- WHAT MAKES IT A DECISION. The cost. Every secondary is paid for out of the
-- same clip the primary fires from, at five, ten, two rounds a shot -- so
-- using one is choosing to reload sooner, and a magazine is a budget rather
-- than a countdown. A free secondary is not an alternative to the primary, it
-- is simply a better primary that you would hold down instead.
--
-- Deliberately not per weapon: 47 weapons times a bespoke secondary is 47
-- balance problems and 47 things to explain. Seven families is seven verbs a
-- player learns once and then knows for every gun they pick up.

local combat = require("mods.enhanced.combat")
local data = require("mods.vanilla.game.data")
local particles = require("mods.vanilla.game.particles")
local play = require("mods.vanilla.game.play")

local altfire = {}

-- Its own gap, on top of whatever the primary's cadence is. Without it a
-- minigun's secondary fires twelve times a second and the clip is gone before
-- the player has let go of the button.
local ALT_COOLDOWN = 0.55

local alt_cd = 0
local was_down = false

--- Straight ahead, with the weapon's own wander on it.
local function aimed(shot)
	return shot.angle + (love.math.random() - 0.5) * 2 * shot.spread
end

-- ------------------------------------------------------------ the secondaries

-- A slug: one round's worth of metal spent as five. Piercing is what the
-- extra mass buys -- the kinetic families have nothing else to spend it on.
local SLUG_DAMAGE = 6
local SLUG_PIERCE = 4

local function slug(game, p, shot)
	local b = game.spawn_round(shot, aimed(shot), {
		damage = shot.damage * SLUG_DAMAGE,
		speed = shot.speed * 1.6,
		max_speed = shot.max_speed * 1.6,
		traits = { pierce = SLUG_PIERCE },
	})
	combat.beam(shot.x, shot.y,
		shot.x + b.dx * shot.range, shot.y + b.dy * shot.range,
		1.0, 0.92, 0.7, 2, 0.08)
	game.shake(3)
end

-- Fuel-air: the tank goes out as one cloud and lights where it lands. Lobbed,
-- because a flamethrower's problem is reach and this is what it can do about
-- it once per magazine.
local FUEL_AIR_RANGE = 520
local FUEL_AIR_BLAST = { radius = 150, damage = 4.5 }

local function fuel_air(game, p, shot)
	local ax, ay, dist = combat.aim_point(p)
	local angle = math.atan2(ay - p.y, ax - p.x)
	game.spawn_round(shot, angle, {
		dist_left = math.min(dist, FUEL_AIR_RANGE),
		damage = shot.damage * 8,
		speed = 700,
		max_speed = 700,
		explosive = FUEL_AIR_BLAST,
		flame = true,
	})
end

-- The gravity well, which was designed as weapon 39 and rejected as one: a
-- carried gun that only gathers a crowd is a gun you would never give up your
-- gun for. Two rockets, and the launcher stays in your hands.
local WELL_RANGE = 620
local WELL_LIFE = 1.9
local WELL_RADIUS = 190
local WELL_PULL = 150

local function gravity_well(game, p, shot)
	local ax, ay, dist = combat.aim_point(p)
	local reach = math.min(dist, WELL_RANGE)
	combat.add_well(
		p.x + math.cos(shot.angle) * reach,
		p.y + math.sin(shot.angle) * reach,
		WELL_LIFE, WELL_RADIUS, WELL_PULL, shot.damage * 4)
end

-- Everything the capacitors are holding, dumped down one arc. The ion
-- family's own verb, spent all at once.
local OVERCHARGE = { jumps = 7, range = 210, decay = 0.88 }

local function overcharge(game, p, shot)
	local target = combat.nearest(p.x, p.y, 420)
	local x = target and target.x or (p.x + math.cos(shot.angle) * 200)
	local y = target and target.y or (p.y + math.sin(shot.angle) * 200)
	game.arcs[#game.arcs + 1] = { x1 = p.x, y1 = p.y, x2 = x, y2 = y, t = 0 }
	combat.chain(x, y, shot.damage * 2.2,
		OVERCHARGE.jumps, OVERCHARGE.range, OVERCHARGE.decay)
	if target then game.damage_creature(target, shot.damage * 2.2) end
	game.flash(0.12, 0.4, 0.7, 1)
end

-- Plasma runs cold enough to slow what it touches (vanilla's own reading of
-- the family). The secondary is that, made a place instead of a hit.
local CHILL_RADIUS = 165
local CHILL_SECONDS = 3.5
local CHILL_FACTOR = 0.35

local function chill_bomb(game, p, shot)
	local ax, ay, dist = combat.aim_point(p)
	local reach = math.min(dist, 560)
	local x, y = p.x + math.cos(shot.angle) * reach, p.y + math.sin(shot.angle) * reach
	particles.explosion(x, y, CHILL_RADIUS, data.FAMILY_COLOR.plasma)
	for _, c in ipairs(game.creatures) do
		if not c.dying then
			local dx, dy = c.x - x, c.y - y
			if dx * dx + dy * dy < CHILL_RADIUS * CHILL_RADIUS then
				game.damage_creature(c, shot.damage * 2)
				c.slow_t = CHILL_SECONDS
				c.slow_factor = CHILL_FACTOR
			end
		end
	end
	combat.used("chill")
end

-- A pulse weapon fires a front. Its secondary is that front let go in every
-- direction at once, which is the only thing in the arsenal that buys the
-- player *room* rather than kills.
local SHOCKWAVE_RADIUS = 240
local SHOCKWAVE_PUSH = 90

local function shockwave(game, p, shot)
	game.shake(7)
	particles.explosion(p.x, p.y, SHOCKWAVE_RADIUS, data.FAMILY_COLOR.pulse)
	for _, c in ipairs(game.creatures) do
		if not c.dying then
			local dx, dy = c.x - p.x, c.y - p.y
			local d2 = dx * dx + dy * dy
			if d2 > 1 and d2 < SHOCKWAVE_RADIUS * SHOCKWAVE_RADIUS then
				local d = math.sqrt(d2)
				c.x = math.max(16, math.min(game.WORLD_W - 16, c.x + dx / d * SHOCKWAVE_PUSH))
				c.y = math.max(16, math.min(game.WORLD_H - 16, c.y + dy / d * SHOCKWAVE_PUSH))
				game.damage_creature(c, shot.damage * 1.5)
			end
		end
	end
	combat.used("shockwave")
end

-- A fan of blades, which bounce, because that is what the blade family does.
local FAN_COUNT = 7
local FAN_SPREAD = 55

local function blade_fan(game, p, shot)
	for i = 1, FAN_COUNT do
		local t = (i - 1) / (FAN_COUNT - 1) - 0.5
		game.spawn_round(shot, shot.angle + math.rad(t * 2 * FAN_SPREAD), {
			damage = shot.damage * 1.1,
			traits = { ricochet = 3 },
		})
	end
end

-- Family -> what its second trigger does, and what that takes out of the clip.
-- `proj_art` is data.lua's classification of all 47 weapons; there is no
-- weapon id anywhere in this file on purpose.
local SECONDARY = {
	bullet = { name = "Slug", cost = 5, fire = slug },
	flame = { name = "Fuel-Air Burst", cost = 10, fire = fuel_air },
	rocket = { name = "Gravity Well", cost = 2, fire = gravity_well },
	ion = { name = "Overcharge", cost = 4, fire = overcharge },
	plasma = { name = "Chill Bomb", cost = 3, fire = chill_bomb },
	pulse = { name = "Shockwave", cost = 3, fire = shockwave },
	blade = { name = "Blade Fan", cost = 4, fire = blade_fan },
}

--- Called every live frame from the cartridge's update hook.
--
-- Edge-triggered, unlike the primary: a secondary that fired while the button
-- was held would empty a clip in a fraction of a second, and the cost is the
-- whole design.
function altfire.update(dt)
	alt_cd = math.max(0, alt_cd - dt)
	local p = play.player
	local want = play.intent
	local down = want and want.alt_fire and true or false
	local pressed = down and not was_down
	was_down = down
	if not pressed or not p or not p.weapon then return end
	if p.reloading > 0 or alt_cd > 0 then return end

	local secondary = SECONDARY[p.weapon.proj_art]
	if not secondary then return end
	alt_cd = ALT_COOLDOWN
	combat.used("altfire")
	play.fire_shot({ ammo_cost = secondary.cost, deliver = secondary.fire })
end

--- Forget the button between runs, so a trigger held as one run ended does not
-- fire into the next one.
function altfire.reset()
	alt_cd, was_down = 0, false
end

return altfire

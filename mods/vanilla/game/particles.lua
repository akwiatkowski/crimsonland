-- Gameplay feedback effects: blood, gore, explosions, pickups.
--
-- This used to be a second particle system — its own pool, its own update and
-- draw, drawing plain coloured circles — living alongside the engine's fxs/
-- interpreter. It existed because the pak ships no gameplay effect files: the
-- six in fxs/ are shell casings and UI bursts, and everything in the playfield
-- was drawn from C++. So there was nothing to interpret and the port drew its
-- own circles.
--
-- The art was there the whole time. game/particles.tga is the 256x256 sheet
-- the original drew blood, fire, sparks and smoke from, and once the
-- interpreter could address a rect inside a sheet, these effects could be
-- authored in the DSL like any other. What is left here is the naming: which
-- effect belongs to which moment, and how big.
--
-- Effect files live in mods/vanilla/fxs/ — they are this port's own content,
-- not the pak's, so they belong to the mod.

local fx = require("src.engine.fx")

local particles = {}

-- Everything lands in the world layer: these are things in the playfield, and
-- the game draws that layer inside its camera transform.
local function spawn(path, x, y, rot, scale, count, color)
	fx.spawn(path, x, y, rot or 0,
		{ layer = "world", scale = scale, count = count, color = color })
end

-- ------------------------------------------------------------------ impacts
--
-- What a round leaves where it connects, per weapon family.
--
-- The families are not invented here: `w.proj_art` (data.lua) already sorts
-- all 38 weapons into seven off weapons.xml's own `type` and `flags`, because
-- the projectile sprites needed it. That makes this a table lookup rather than
-- a classification problem.
--
-- Every family draws blood, because every family is hitting flesh -- the
-- family only adds its own signature over it. An effect may reveal a rule the
-- game has; it must not imply one it does not.
local BLOOD = "mods/vanilla/fxs/blood.lua"
local NARROW = "mods/vanilla/fxs/spray-narrow.lua"
local SPARK = "mods/vanilla/fxs/spark.lua"

local IMPACT = {
	-- kinetic and ordnance: blood, nothing else
	bullet = { spray = BLOOD },
	rocket = { spray = BLOOD },
	-- the blade cuts, so the spray follows the edge instead of fanning
	blade = { spray = NARROW },
	-- energy: blood plus sparks in the colour of the bolt that made them
	flame = { spray = BLOOD, extra = SPARK, tint = { 1.0, 0.55, 0.2 } },
	plasma = { spray = BLOOD, extra = SPARK, tint = { 0.55, 0.8, 1.0 } },
	ion = { spray = BLOOD, extra = SPARK, tint = { 0.6, 1.0, 0.65 } },
	pulse = { spray = BLOOD, extra = SPARK, tint = { 1.0, 0.9, 0.5 } },
}

-- The gauss family shares `flags=1` with the plain shotgun and assault rifle,
-- so weapons.xml gives it no identity of its own and it needs naming here.
-- It punches through rather than cutting: same narrow spray as the blade, for
-- the opposite reason.
local PUNCH_THROUGH = {
	GAUSS_GUN = true, GAUSS_SHOTGUN = true, GAUSS_MINIGUN = true,
}

--- How hard a hit reads, from what it actually did. The pistol is the unit,
-- and the ends are clamped: a Gauss slug should look like a Gauss slug, not
-- like forty pistol shots at once.
local BASELINE_DAMAGE = 4.1
local POWER_MIN, POWER_MAX = 0.55, 2.4

function particles.power(damage)
	local p = (damage or BASELINE_DAMAGE) / BASELINE_DAMAGE
	return math.max(POWER_MIN, math.min(POWER_MAX, p))
end

--- A round connecting. `family` is w.proj_art, `dir` the way the shot was
-- going (radians), `power` what particles.power made of its damage.
-- `weapon_id` is only consulted for the punch-through set.
function particles.impact(family, weapon_id, x, y, dir, power)
	power = power or 1
	local f = IMPACT[family] or IMPACT.bullet
	local deg = math.deg(dir or 0)
	local spray = f.spray
	if weapon_id and PUNCH_THROUGH[weapon_id] then spray = NARROW end
	-- power drives both size and count: a bigger hit throws more, further
	spawn(spray, x, y, deg, power, power)
	if f.extra then spawn(f.extra, x, y, deg, power, 1, f.tint) end
end

--- True when this family punches a hole rather than making one, which is what
-- the ground mark and the exit spatter want to know.
function particles.punches_through(family, weapon_id)
	return family == "blade" or (weapon_id and PUNCH_THROUGH[weapon_id]) or false
end

--- Blood spray when a bullet connects; dir = incoming bullet angle (radians).
function particles.blood(x, y, dir, power)
	spawn(BLOOD, x, y, math.deg(dir or 0), power, power)
end

--- The gush on a kill, sized to whatever came apart.
function particles.death_burst(x, y, scale)
	spawn("mods/vanilla/fxs/gore.lua", x, y, 0, scale or 1)
end

--- Rocket-class detonation. `radius` is the blast radius in world pixels; the
-- effect is authored around 80 (a rocket), so smaller blasts scale down.
-- `color` tints the whole blast, which is how the energy weapons detonate in
-- their own light without a second sheet of fireball art.
function particles.explosion(x, y, radius, color)
	fx.spawn("mods/vanilla/fxs/explosion.lua", x, y, 0,
		{ layer = "world", scale = (radius or 80) / 80, color = color })
end

--- Small sparkle when a drop is picked up.
function particles.sparkle(x, y)
	spawn("mods/vanilla/fxs/pickup.lua", x, y)
end

--- The ice coming off a creature that thaws or dies still frozen; `scale`
-- sizes it to whatever was encased.
function particles.ice_shatter(x, y, scale)
	spawn("mods/vanilla/fxs/ice-shatter.lua", x, y, 0, scale or 1)
end

--- A hit on something still encased. Chips off the block rather than blood,
-- so a frozen creature reads as a thing to break instead of a thing to bleed
-- -- which is also the honest picture, since nothing under the ice is moving.
function particles.ice_spall(x, y, dir, power)
	spawn("mods/vanilla/fxs/ice-shatter.lua", x, y, math.deg(dir or 0),
		0.55 * (power or 1), 0.6)
end

-- No update, draw or clear here any more: the engine updates both fx layers
-- every frame, the game already draws the world one inside its camera, and
-- fx.clear("world") already wipes the field between runs.

return particles

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
local function spawn(path, x, y, rot, scale)
	fx.spawn(path, x, y, rot or 0, { layer = "world", scale = scale })
end

--- Blood spray when a bullet connects; dir = incoming bullet angle (radians).
function particles.blood(x, y, dir)
	spawn("mods/vanilla/fxs/blood.lua", x, y, math.deg(dir or 0))
end

--- The gush on a kill, sized to whatever came apart.
function particles.death_burst(x, y, scale)
	spawn("mods/vanilla/fxs/gore.lua", x, y, 0, scale or 1)
end

--- Rocket-class detonation. `radius` is the blast radius in world pixels; the
-- effect is authored around 80 (a rocket), so smaller blasts scale down.
function particles.explosion(x, y, radius)
	spawn("mods/vanilla/fxs/explosion.lua", x, y, 0, (radius or 80) / 80)
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

-- No update, draw or clear here any more: the engine updates both fx layers
-- every frame, the game already draws the world one inside its camera, and
-- fx.clear("world") already wipes the field between runs.

return particles

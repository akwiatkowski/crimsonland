-- Body parts thrown by a death, and the mark they leave.
--
-- creatures.xml gives nine of the thirteen creatures two gib sheets:
-- `bm_gibs_unique` (whatever only this creature is made of -- a head, a
-- claw) and `bm_gibs_common` (the generic meat). Each is a .bms of four
-- frames, and those frames are NOT an animation: they are four different
-- body parts, which is why a gib picks one frame and keeps it while it
-- tumbles. The naming in the pak says so too -- `bodypart-unique-0001`
-- through `-0004`.
--
-- A gib flies out of the kill, spins, slows against the ground and then
-- bakes into the terrain canvas where it stopped -- the same trick the
-- corpse uses (play.lua's update_creatures), so the parts join the blood
-- carpet instead of blinking out of existence.

local bms = require("mods.vanilla.game.bms")

local gibs = {}

-- How many parts a death throws. The unique sheet is the creature's own
-- landmark piece, so one or two of it; the common meat carries the volume.
local UNIQUE_MIN, UNIQUE_MAX = 1, 2
local COMMON_MIN, COMMON_MAX = 2, 4

-- A nuke kills the whole field at once; without a cap that is 90 creatures
-- worth of parts in a single frame, all of them baking a moment later.
local MAX_GIBS = 140

-- Halvings of speed per second, same reading of "mass" the fx interpreter
-- uses: a part is thrown clear of the kill and friction stops it well
-- inside its life, so it bakes where it came to rest rather than mid-flight.
local DRAG = 0.5 ^ 4

local pool = {}

local function throw(seq, x, y, scale, tint, n)
	for _ = 1, n do
		if #pool >= MAX_GIBS then return end
		local a = love.math.random() * math.pi * 2
		local speed = (80 + love.math.random() * 200) * scale
		pool[#pool + 1] = {
			seq = seq,
			-- one of the four parts on the sheet, held for the whole flight
			frame = love.math.random(1, math.max(1, seq.count)),
			x = x,
			y = y,
			dx = math.cos(a) * speed,
			dy = math.sin(a) * speed,
			angle = love.math.random() * math.pi * 2,
			spin = (love.math.random() - 0.5) * 16,
			scale = scale,
			tint = tint,
			age = 0,
			life = 0.45 + love.math.random() * 0.4,
		}
	end
end

--- Throw one creature's parts. Takes the creature because everything needed
-- (which sheets, how big, what colour) already hangs off it. `mul` multiplies
-- how many come off, for a death that was an overkill rather than a kill.
function gibs.spawn(c, mul)
	local def, v = c.def, c.variant
	if not def then return end
	mul = mul or 1
	local scale = c.scale or (v and v.scale) or 1
	-- the same tint the corpse bakes with: a green alien sheds green parts
	local tint = v and { v.r, v.g, v.b } or { 1, 1, 1 }

	local uniq = def.gibs_unique and bms.load(def.gibs_unique)
	if uniq then
		throw(uniq, c.x, c.y, scale, tint,
			math.ceil(love.math.random(UNIQUE_MIN, UNIQUE_MAX) * mul))
	end
	local common = def.gibs_common and bms.load(def.gibs_common)
	if common then
		throw(common, c.x, c.y, scale, tint,
			math.ceil(love.math.random(COMMON_MIN, COMMON_MAX) * mul))
	end
end

--- `terrain` is the session's ground canvas; a part that has stopped is
-- painted into it and forgotten.
function gibs.update(dt, terrain)
	for i = #pool, 1, -1 do
		local g = pool[i]
		g.age = g.age + dt
		if g.age >= g.life then
			if terrain then
				love.graphics.setCanvas(terrain)
				love.graphics.setColor(g.tint[1], g.tint[2], g.tint[3], 1)
				bms.draw(g.seq, g.frame, g.x, g.y, g.angle, g.scale)
				love.graphics.setColor(1, 1, 1, 1)
				love.graphics.setCanvas()
			end
			pool[i] = pool[#pool]
			pool[#pool] = nil
		else
			local keep = DRAG ^ dt
			g.dx, g.dy = g.dx * keep, g.dy * keep
			g.x, g.y = g.x + g.dx * dt, g.y + g.dy * dt
			-- the spin dies with the throw, so a part settles instead of
			-- twitching on the spot until its life runs out
			g.spin = g.spin * keep
			g.angle = g.angle + g.spin * dt
		end
	end
end

--- Draw the parts still in the air. World coordinates: the caller owns the
-- camera transform, exactly like fx.draw("world").
function gibs.draw()
	for _, g in ipairs(pool) do
		love.graphics.setColor(g.tint[1], g.tint[2], g.tint[3], 1)
		bms.draw(g.seq, g.frame, g.x, g.y, g.angle, g.scale)
	end
	love.graphics.setColor(1, 1, 1, 1)
end

function gibs.clear()
	pool = {}
end

--- Parts in flight, for the test harness.
function gibs.count()
	return #pool
end

return gibs

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

-- What the round leaves behind besides a hole.
--
-- A death used to throw its parts in an even ring, which reads as a body
-- exploding on the spot however it died -- the same picture whether it walked
-- into a flame or took a shotgun at point-blank. A round carries momentum, and
-- the body it lands in carries that momentum away: the parts still scatter, but
-- the whole cloud travels downrange, which is the only thing on screen that
-- says which side the shot came from.
--
-- Momentum is damage times the speed the round was actually doing, out of the
-- weapon's own numbers rather than a table of feels-right values per gun. It
-- orders the arsenal the way the arsenal deserves: a flamethrower's stream and
-- a minigun's needles barely nudge a corpse, a pistol shoves it, the Rocket
-- Launcher throws it, and the Gauss Gun -- one 5.4-damage slug at fourteen
-- times a shotgun pellet's speed -- pins the scale on its own.
--
-- PUSH_FULL is where the push stops growing, in world units of damage x
-- pixels/second. 14400 is a little above one full Shotgun blast (12 pellets,
-- ~10900 between them), so buckshot at close range lands near the top of the
-- scale without being the only thing that reaches it.
local PUSH_FULL = 14400
local PUSH_MAX = 260 -- pixels/second added to every part, at PUSH_FULL

-- How long the hits that made a kill stay countable. A shotgun's twelve pellets
-- land in one frame and a minigun's stream inside a fifth of a second, and both
-- of those are one blow as far as the body is concerned; a round that landed
-- two seconds ago is not, and must not still be steering the parts when
-- something else finishes the job.
local PUSH_WINDOW = 0.15

-- A blast has damage but no round to read a speed off, so it needs one to be
-- weighed on the same scale as a bullet. 700 puts a Rocket Launcher's twenty
-- points at the centre of its own explosion just above a full Shotgun blast,
-- which is the right order: the thing you fire at a crowd throws bodies hardest.
gibs.BLAST_SPEED = 700

local pool = {}

local function throw(seq, x, y, scale, tint, n, px, py)
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
			-- the scatter, plus what the round was carrying: every part gets the
			-- same push, so the cloud moves while the parts still fly apart
			dx = math.cos(a) * speed + px,
			dy = math.sin(a) * speed + py,
			angle = love.math.random() * math.pi * 2,
			spin = (love.math.random() - 0.5) * 16,
			scale = scale,
			tint = tint,
			age = 0,
			life = 0.45 + love.math.random() * 0.4,
		}
	end
end

--- Remember a round landing: `dx, dy` is the direction it was travelling (a
-- unit vector) and `momentum` is its damage times its speed.
--
-- Hits inside PUSH_WINDOW of each other add up, which is what makes a shotgun
-- different from the rifle that does the same damage one round at a time: the
-- twelve pellets are one blow, and the body goes with them. Everything the
-- caller needs to know is the direction the round was going -- not where the
-- shooter stood, because a round that curved or was fired from a mount across
-- the field still throws the parts the way *it* was going.
function gibs.push(c, dx, dy, momentum)
	local now = love.timer.getTime()
	if not c.push_t or now - c.push_t > PUSH_WINDOW then
		c.push_p = 0
		c.push_x, c.push_y = 0, 0
	end
	-- summed as momentum (a vector), so two rounds from opposite sides cancel
	-- the way they should rather than throwing the parts twice as hard
	c.push_x = c.push_x + dx * momentum
	c.push_y = c.push_y + dy * momentum
	c.push_t = now
end

--- The velocity the round leaves in the parts: the accumulated momentum, capped,
-- and divided by how much creature there is to move. Nothing if the last round
-- landed too long ago to be what killed it.
local function push_velocity(c, scale)
	if not c.push_t or love.timer.getTime() - c.push_t > PUSH_WINDOW then
		return 0, 0
	end
	local px, py = c.push_x or 0, c.push_y or 0
	local p = math.sqrt(px * px + py * py)
	if p <= 0 then return 0, 0 end
	-- same impulse into more creature moves it less, which is why the big ones
	-- come apart where they stood and the small ones are thrown off their feet
	local speed = PUSH_MAX * math.min(1, p / PUSH_FULL) / scale
	return px / p * speed, py / p * speed
end

--- Throw one creature's parts. Takes the creature because everything needed
-- (which sheets, how big, what colour, and what hit it) already hangs off it.
-- `mul` multiplies how many come off, for a death that was an overkill rather
-- than a kill.
function gibs.spawn(c, mul)
	local def, v = c.def, c.variant
	if not def then return end
	mul = mul or 1
	local scale = c.scale or (v and v.scale) or 1
	-- the same tint the corpse bakes with: a green alien sheds green parts
	local tint = v and { v.r, v.g, v.b } or { 1, 1, 1 }
	local px, py = push_velocity(c, scale)

	local uniq = def.gibs_unique and bms.load(def.gibs_unique)
	if uniq then
		throw(uniq, c.x, c.y, scale, tint,
			math.ceil(love.math.random(UNIQUE_MIN, UNIQUE_MAX) * mul), px, py)
	end
	local common = def.gibs_common and bms.load(def.gibs_common)
	if common then
		throw(common, c.x, c.y, scale, tint,
			math.ceil(love.math.random(COMMON_MIN, COMMON_MAX) * mul), px, py)
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

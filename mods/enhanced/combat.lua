-- The systems this cartridge's verbs need, and nothing else.
--
-- Everything here hangs off four seams in vanilla and adds no simulation of
-- its own to the base game:
--
--   traits.deliver   what leaves the barrel      (the lobs, the cone, the
--                                                 tether's origin, the orb)
--   traits.trigger   when the gun goes off       (charge, capacitor, ring)
--   traits.on_hit    the moment a round connects (nodes, prism, bounce ramp)
--   traits.on_end    where a round stopped       (acid pools)
--   game.on_update   this file's own world
--   game.on_world_draw   ...drawn inside the camera transform
--
-- Rounds are vanilla rounds. A weapon here that fires something ordinary fires
-- it through `game.spawn_round`, so it collides, pierces, ricochets, bleeds,
-- marks the ground and counts towards accuracy exactly as a pak weapon's does.
-- What lives in this file is only what has no equivalent in the base game:
-- things that persist (pools, nodes, orbs, burning lines) and the state a
-- trigger has to carry between frames.

local data = require("mods.vanilla.game.data")
local particles = require("mods.vanilla.game.particles")
local play = require("mods.vanilla.game.play")

local combat = {}

-- Persistent world owned by this cartridge. Lists rather than one soup,
-- because each has its own tick and its own drawing and they never interact.
combat.pools = {} -- corrosive ground: { x, y, r, t, life, dps, slow }
combat.nodes = {} -- stuck chain relays: { c, t, life }
combat.orbs = {} -- ball lightning: { x, y, dx, dy, speed, t, life, damage }
combat.burns = {} -- superheated lines: { x1, y1, x2, y2, t, life, dps, w }
combat.wells = {} -- gravity wells: { x, y, t, life, r, pull, damage }
combat.beams = {} -- purely visual: { x1, y1, x2, y2, t, life, r, g, b, w }

-- What the triggers carry between frames. One player, so one of each.
-- Seconds of held trigger that buy a full Rail Spike. Long enough that firing
-- one is a decision you are stuck with while a crowd closes, short enough that
-- you can take it twice in a lull.
combat.CHARGE_FULL = 2.5
combat.charge_t = 0 -- Rail Spike: seconds the trigger has been held
combat.charges = 0 -- Capacitor Rifle: jumps banked
combat.hold_t = 0 -- Capacitor Rifle: seconds since the last charge was taken
combat.anchor = nil -- Tether Rail: { x, y } or nil
combat.idle_t = 0 -- Tether Rail: seconds since the trigger was last down

-- The Storm Ring is the one weapon whose radius is the resource: it starts
-- wide, closes in while the trigger is held, and opens back out while it is
-- not. So "how long can I keep this on" and "how far does it reach" are the
-- same question, and the mouse is not part of it at all.
combat.RING_MAX = 210
combat.RING_MIN = 34
combat.RING_CLOSE = 150 -- pixels a second while firing
combat.RING_OPEN = 55 -- ...and while not
combat.ring_r = 210 -- current radius

-- How many times each verb has fired this session. Not debug output: it is
-- what an autotest asserts against, because "the Prism Rail split something"
-- is not visible from outside and a verb that silently never runs is exactly
-- the failure a scenario is for.
combat.verbs = {}

local function used(verb)
	combat.verbs[verb] = (combat.verbs[verb] or 0) + 1
end
combat.used = used

--- Everything back to nothing. A new run must not inherit the last one's
-- pools, and the anchor of a trooper who died is not this one's.
function combat.reset()
	for _, list in ipairs({ combat.pools, combat.nodes, combat.orbs,
		combat.burns, combat.beams, combat.wells }) do
		for i = #list, 1, -1 do list[i] = nil end
	end
	combat.charge_t, combat.charges, combat.hold_t = 0, 0, 0
	combat.anchor, combat.idle_t = nil, 0
	combat.ring_r = combat.RING_MAX
end

-- --------------------------------------------------------------- shared bits

--- Nearest living creature to a point, within `range`, skipping a set. The
-- same shape as vanilla's own (play.lua), duplicated rather than exported
-- because it is six lines and exporting it would make a private helper part of
-- vanilla's contract.
function combat.nearest(x, y, range, skip)
	local best, bestd
	for _, c in ipairs(play.creatures or {}) do
		if not c.dying and not (skip and skip[c]) then
			local dx, dy = c.x - x, c.y - y
			local d = dx * dx + dy * dy
			if (not range or d < range * range) and (not bestd or d < bestd) then
				best, bestd = c, d
			end
		end
	end
	return best
end

--- Arc from a point through up to `jumps` creatures, losing bite each jump.
-- Pushes onto `game.arcs`, which vanilla ages and draws for the shock-chain
-- powerup -- so a tesla weapon's web is drawn by code that already exists and
-- always looks like the same electricity.
function combat.chain(x, y, damage, jumps, range, decay, skip)
	skip = skip or {}
	local cx, cy = x, y
	local hit = 0
	for _ = 1, jumps do
		local c = combat.nearest(cx, cy, range, skip)
		if not c then break end
		skip[c] = true
		play.arcs[#play.arcs + 1] = { x1 = cx, y1 = cy, x2 = c.x, y2 = c.y, t = 0 }
		play.damage_creature(c, damage)
		cx, cy = c.x, c.y
		damage = damage * decay
		hit = hit + 1
	end
	return hit
end

--- A line drawn for a moment and then gone: a rail lance, a tether, the flash
-- of a prism splitting. Purely visual -- what does the damage is the round.
function combat.beam(x1, y1, x2, y2, r, g, b, width, life)
	combat.beams[#combat.beams + 1] = {
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		t = 0, life = life or 0.12, r = r, g = g, b = b, w = width or 2,
	}
end

--- Where the player is pointing, and how far away that is. Every weapon in
-- the pak throws this distance away and keeps only the angle (play.lua), which
-- is why nothing before this cartridge could land something *at* a place.
function combat.aim_point(p)
	local ax, ay = p.aim_x or p.x, p.aim_y or p.y
	return ax, ay, math.sqrt((ax - p.x) ^ 2 + (ay - p.y) ^ 2)
end

-- ------------------------------------------------------------------- pools

-- A pool is a disc that hurts and slows what stands in it. Chosen over a
-- damage-over-time status on the creature because a pool is a *place*: it
-- makes ground expensive, which is the decision the Acid Sprayer exists to
-- offer, and a status on the creature would just be slower damage.
local POOL_TICK = 0.25 -- seconds between bites, so the arithmetic is coarse
-- Merge radius. Without this a 50-round magazine leaves fifty overlapping
-- discs on one square metre and the tick cost is fifty times what it looks.
local POOL_MERGE = 26
local POOL_MAX = 40 -- hard ceiling; the oldest goes when the 41st arrives

function combat.add_pool(x, y, r, life, dps, slow)
	for _, pool in ipairs(combat.pools) do
		local dx, dy = pool.x - x, pool.y - y
		if dx * dx + dy * dy < POOL_MERGE * POOL_MERGE then
			-- a second splash on the same ground refreshes and widens it
			pool.t = 0
			pool.r = math.min(pool.r * 1.06, r * 1.8)
			return pool
		end
	end
	if #combat.pools >= POOL_MAX then table.remove(combat.pools, 1) end
	local pool = { x = x, y = y, r = r, t = 0, life = life, dps = dps,
		slow = slow, tick = 0 }
	combat.pools[#combat.pools + 1] = pool
	used("pool")
	return pool
end

local function update_pools(dt)
	for i = #combat.pools, 1, -1 do
		local pool = combat.pools[i]
		pool.t = pool.t + dt
		pool.tick = pool.tick + dt
		if pool.tick >= POOL_TICK then
			local bite = pool.dps * pool.tick
			pool.tick = 0
			for _, c in ipairs(play.creatures or {}) do
				if not c.dying then
					local dx, dy = c.x - pool.x, c.y - pool.y
					if dx * dx + dy * dy < pool.r * pool.r then
						play.damage_creature(c, bite)
						c.slow_t = math.max(c.slow_t or 0, POOL_TICK * 1.5)
						c.slow_factor = pool.slow
					end
				end
			end
		end
		if pool.t >= pool.life then table.remove(combat.pools, i) end
	end
end

-- -------------------------------------------------------------------- nodes
--
-- A dart that sticks to a creature and stays a relay until that creature dies
-- or the dart times out. This is the one weapon in the arsenal with an
-- investment phase: the darts themselves barely hurt, and what they buy is a
-- network that later shots discharge through.

local NODE_LIFE = 9
local NODE_MAX = 8

function combat.stick_node(c, life)
	for _, n in ipairs(combat.nodes) do
		if n.c == c then
			n.t = 0 -- a second dart in the same body just refreshes it
			return
		end
	end
	if #combat.nodes >= NODE_MAX then table.remove(combat.nodes, 1) end
	combat.nodes[#combat.nodes + 1] = { c = c, t = 0, life = life or NODE_LIFE }
	used("nodes")
end

--- Discharge the whole network: every stuck creature arcs to the next,
-- whatever the distance between them. That is the payoff for seeding it, and
-- the reason range is not a parameter here.
function combat.discharge_nodes(damage, decay)
	local prev = nil
	local dealt = 0
	for _, n in ipairs(combat.nodes) do
		if not n.c.dying then
			if prev then
				play.arcs[#play.arcs + 1] =
					{ x1 = prev.x, y1 = prev.y, x2 = n.c.x, y2 = n.c.y, t = 0 }
			end
			play.damage_creature(n.c, damage)
			damage = damage * decay
			dealt = dealt + 1
			prev = n.c
		end
	end
	return dealt
end

local function update_nodes(dt)
	for i = #combat.nodes, 1, -1 do
		local n = combat.nodes[i]
		n.t = n.t + dt
		if n.t >= n.life or n.c.dying then table.remove(combat.nodes, i) end
	end
end

-- --------------------------------------------------------------------- orbs
--
-- Ball lightning: a slow world object that arcs at everything near it, the
-- player included. It is the only thing either side of the fight has to
-- respect, which is what makes placing one a decision rather than an attack.

local ORB_ARC_INTERVAL = 0.22
local ORB_RANGE = 150
local ORB_PLAYER_RANGE = 70 -- it will bite the hand that threw it

function combat.add_orb(x, y, dx, dy, speed, life, damage)
	combat.orbs[#combat.orbs + 1] = {
		x = x, y = y, dx = dx, dy = dy, speed = speed,
		t = 0, life = life, damage = damage, tick = 0,
	}
	used("orb")
end

local function update_orbs(dt)
	local p = play.player
	for i = #combat.orbs, 1, -1 do
		local o = combat.orbs[i]
		o.t = o.t + dt
		o.tick = o.tick + dt
		o.x = o.x + o.dx * o.speed * dt
		o.y = o.y + o.dy * o.speed * dt
		-- it drifts off a wall rather than through it: an orb outside the
		-- playfield is a wasted magazine and reads as a bug
		if o.x < 8 or o.x > play.WORLD_W - 8 then o.dx = -o.dx end
		if o.y < 8 or o.y > play.WORLD_H - 8 then o.dy = -o.dy end
		if o.tick >= ORB_ARC_INTERVAL then
			o.tick = 0
			combat.chain(o.x, o.y, o.damage, 3, ORB_RANGE, 0.7)
			local dx, dy = p.x - o.x, p.y - o.y
			if dx * dx + dy * dy < ORB_PLAYER_RANGE * ORB_PLAYER_RANGE then
				play.arcs[#play.arcs + 1] =
					{ x1 = o.x, y1 = o.y, x2 = p.x, y2 = p.y, t = 0 }
				play.on_attacked(o.damage * 0.5)
			end
		end
		if o.t >= o.life then
			particles.explosion(o.x, o.y, 40, data.FAMILY_COLOR.ion)
			table.remove(combat.orbs, i)
		end
	end
end

-- ---------------------------------------------------------------- burn lines
--
-- The Tracer Rail's superheated path. A line the shot has already been down,
-- which anything crossing it pays for -- so a rail shot stops being an event
-- and becomes a fence you put up.

local BURN_TICK = 0.2

function combat.add_burn(x1, y1, x2, y2, life, dps, width)
	combat.burns[#combat.burns + 1] = {
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		t = 0, life = life, dps = dps, w = width, tick = 0,
	}
	used("trail_burn")
end

--- Distance from a point to a segment. The line is what does the damage, so
-- "is this creature on it" is the whole question.
local function dist_to_segment(px, py, x1, y1, x2, y2)
	local vx, vy = x2 - x1, y2 - y1
	local len2 = vx * vx + vy * vy
	local t = 0
	if len2 > 0 then
		t = ((px - x1) * vx + (py - y1) * vy) / len2
		t = math.max(0, math.min(1, t))
	end
	local dx, dy = px - (x1 + vx * t), py - (y1 + vy * t)
	return math.sqrt(dx * dx + dy * dy)
end

local function update_burns(dt)
	for i = #combat.burns, 1, -1 do
		local burn = combat.burns[i]
		burn.t = burn.t + dt
		burn.tick = burn.tick + dt
		if burn.tick >= BURN_TICK then
			local bite = burn.dps * burn.tick
			burn.tick = 0
			for _, c in ipairs(play.creatures or {}) do
				if not c.dying
					and dist_to_segment(c.x, c.y, burn.x1, burn.y1, burn.x2, burn.y2)
					< burn.w + 12 * c.scale then
					play.damage_creature(c, bite)
				end
			end
		end
		if burn.t >= burn.life then table.remove(combat.burns, i) end
	end
end

-- -------------------------------------------------------------------- wells
--
-- A gravity well drags everything within reach into one point and then pops
-- it. Designed as a weapon and rejected as one: a carried gun that only
-- gathers a crowd fails the single-weapon-slot rule, because you would never
-- give up your gun to hold it. As the rocket family's secondary it costs two
-- rockets and the gun stays in your hands, which is the version that works.

function combat.add_well(x, y, life, r, pull, damage)
	combat.wells[#combat.wells + 1] = {
		x = x, y = y, t = 0, life = life, r = r, pull = pull, damage = damage,
	}
	used("gravity")
end

local function update_wells(dt)
	for i = #combat.wells, 1, -1 do
		local well = combat.wells[i]
		well.t = well.t + dt
		for _, c in ipairs(play.creatures or {}) do
			if not c.dying then
				local dx, dy = well.x - c.x, well.y - c.y
				local d2 = dx * dx + dy * dy
				if d2 > 4 and d2 < well.r * well.r then
					local d = math.sqrt(d2)
					-- harder the closer you already are, so the last stretch
					-- snaps shut and the crowd is genuinely a knot when it pops
					local grip = well.pull * dt * (1.4 - 0.4 * d / well.r)
					c.x = c.x + dx / d * grip
					c.y = c.y + dy / d * grip
				end
			end
		end
		if well.t >= well.life then
			play.explode_at(well.x, well.y, well.damage)
			table.remove(combat.wells, i)
		end
	end
end

-- ------------------------------------------------------------------- update

function combat.update(dt)
	update_pools(dt)
	update_nodes(dt)
	update_orbs(dt)
	update_burns(dt)
	update_wells(dt)
	for i = #combat.beams, 1, -1 do
		local beam = combat.beams[i]
		beam.t = beam.t + dt
		if beam.t >= beam.life then table.remove(combat.beams, i) end
	end
	-- the ring opens back out whenever it is not being closed (traits.lua
	-- closes it while the trigger is held)
	combat.ring_r = math.min(combat.RING_MAX, combat.ring_r + dt * combat.RING_OPEN)
end

--- Drag creatures near `c` toward it, compacting a loose crowd into a knot
-- that chains better. The Arc Lasso's whole verb: it does not kill things, it
-- arranges them for the shot after.
function combat.lasso(c, range, pull, dt)
	local moved = 0
	for _, other in ipairs(play.creatures or {}) do
		if other ~= c and not other.dying then
			local dx, dy = c.x - other.x, c.y - other.y
			local d2 = dx * dx + dy * dy
			if d2 > 4 and d2 < range * range then
				local d = math.sqrt(d2)
				other.x = other.x + dx / d * pull
				other.y = other.y + dy / d * pull
				moved = moved + 1
			end
		end
	end
	if moved > 0 then used("lasso") end
	return moved
end

--- A child round forked off one already in flight, for a verb that turns a
-- round into more rounds on impact. `traits` is given explicitly rather than
-- inherited: a child that kept its parent's `on_hit` would fork again on its
-- own first body, and one shot would fill the field.
function combat.fork(b, angle, damage_mul, reach, traits)
	local child = {
		x = b.x, y = b.y,
		dx = math.cos(angle), dy = math.sin(angle),
		speed = b.speed,
		max_speed = b.max_speed,
		dist_left = reach,
		damage = b.damage * damage_mul,
		art = b.art,
		bolt = b.bolt,
		weapon_id = b.weapon_id,
		traits = traits,
		is_child = true,
	}
	play.bullets[#play.bullets + 1] = child
	return child
end

-- -------------------------------------------------------------------- draw

local ACID = { 0.55, 0.95, 0.25 }

function combat.draw()
	local g = love.graphics

	-- pools first: they are ground, and everything else stands on them
	for _, pool in ipairs(combat.pools) do
		local k = 1 - pool.t / pool.life
		g.setColor(ACID[1], ACID[2], ACID[3], 0.16 + 0.18 * k)
		g.circle("fill", pool.x, pool.y, pool.r)
		g.setColor(ACID[1], ACID[2], ACID[3], 0.30 * k)
		g.circle("line", pool.x, pool.y, pool.r)
	end

	g.setBlendMode("add")

	for _, burn in ipairs(combat.burns) do
		local k = 1 - burn.t / burn.life
		g.setColor(1, 0.55 + 0.3 * k, 0.2, 0.5 * k)
		g.setLineWidth(burn.w * (0.6 + 0.4 * k))
		g.line(burn.x1, burn.y1, burn.x2, burn.y2)
	end

	for _, beam in ipairs(combat.beams) do
		local k = 1 - beam.t / beam.life
		g.setColor(beam.r, beam.g, beam.b, k)
		g.setLineWidth(beam.w * k)
		g.line(beam.x1, beam.y1, beam.x2, beam.y2)
	end

	-- a node is a lit dart in a body, so the network is readable before it is
	-- discharged -- otherwise the investment is invisible until it pays
	local ion = data.FAMILY_COLOR.ion
	for _, n in ipairs(combat.nodes) do
		local k = 1 - n.t / n.life
		g.setColor(ion[1], ion[2], ion[3], 0.4 + 0.5 * k)
		g.circle("fill", n.c.x, n.c.y, 3 + 2 * k)
	end

	-- a well is a dark pull, so it is drawn as rings closing rather than as
	-- something bright: it is the one effect here that is not throwing energy
	for _, well in ipairs(combat.wells) do
		local k = 1 - well.t / well.life
		for ring = 1, 3 do
			local r = well.r * k * (ring / 3)
			g.setColor(0.55, 0.35, 0.9, 0.16 + 0.2 * k)
			g.circle("line", well.x, well.y, r)
		end
	end

	for _, o in ipairs(combat.orbs) do
		local k = 1 - o.t / o.life
		local pulse = 0.75 + 0.25 * math.sin(o.t * 14)
		g.setColor(ion[1], ion[2], ion[3], 0.55 * k)
		g.circle("fill", o.x, o.y, 16 * pulse)
		g.setColor(1, 1, 1, 0.7 * k)
		g.circle("fill", o.x, o.y, 6 * pulse)
	end

	local p = play.player
	local held = p and p.weapon and p.weapon.id

	-- The ring *is* the weapon, so it is drawn whenever it is in hand -- a
	-- radius the player cannot see is a resource they cannot spend.
	if held == "STORM_RING" then
		local k = combat.ring_r / combat.RING_MAX
		g.setColor(ion[1], ion[2], ion[3], 0.25 + 0.35 * (1 - k))
		g.setLineWidth(2 + 3 * (1 - k))
		g.circle("line", p.x, p.y, combat.ring_r)
	end

	-- A charge with nothing to show for it is a gun that feels broken for two
	-- and a half seconds, so it grows at the muzzle where the shot will leave.
	if held == "RAIL_SPIKE" and combat.charge_t > 0 then
		local k = math.min(1, combat.charge_t / combat.CHARGE_FULL)
		local mx = p.x + math.cos(p.angle) * 22
		local my = p.y + math.sin(p.angle) * 22
		g.setColor(0.75, 0.88, 1, 0.35 + 0.5 * k)
		g.circle("fill", mx, my, 2 + 7 * k)
	end

	-- ...and the same for banked capacitor charges, as pips round the trooper
	if held == "CAPACITOR_RIFLE" and combat.charges > 0 then
		for n = 1, combat.charges do
			local a = -math.pi / 2 + (n - 1) * 0.5
			g.setColor(ion[1], ion[2], ion[3], 0.8)
			g.circle("fill", p.x + math.cos(a) * 26, p.y + math.sin(a) * 26, 2.5)
		end
	end

	-- the tether's anchor, and the line back to it: a shot fired from
	-- somewhere the player is not needs both ends drawn or it reads as a bug
	if combat.anchor and p then
		g.setColor(0.9, 0.8, 0.4, 0.5)
		g.setLineWidth(1)
		g.line(p.x, p.y, combat.anchor.x, combat.anchor.y)
		g.circle("line", combat.anchor.x, combat.anchor.y, 7)
	end

	g.setLineWidth(1)
	g.setBlendMode("alpha")
	g.setColor(1, 1, 1, 1)
end

return combat

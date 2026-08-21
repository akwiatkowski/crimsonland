-- Mounts: the eight places a weapon can stand without you holding it.
--
-- A tower here is not a kind of gun. It is a *mount* with one of your weapons
-- bolted to it, firing the same rounds with the same spread, damage, reload
-- and traits it has in your hands (game/shooter.lua is literally the same code
-- with a different brain choosing the angle). That is the mod's central idea:
-- knowing what a weapon does is knowledge that transfers, because there is
-- only one kind of knowing.
--
-- Placement is fixed rather than free — a ring of plots around the base, each
-- bought before it can hold anything. Fixed plots make the decision "which
-- side" instead of "which pixel", need no build cursor and no rules about what
-- may overlap what, and they let the ground itself be scarce: the plots
-- compete with each other for a limited amount of money, which is the same
-- pressure economy buildings will later apply from the other direction.
--
-- Range is what stops a mount being a free kill: capped well below what most
-- weapons reach in the player's hands, so a mount covers an arc rather than
-- the map, and the arc it covers is the thing you chose when you bought it.

local assets = require("src.engine.assets")
local data = require("mods.vanilla.game.data")
local font = require("src.engine.font")
local prices = require("mods.towerdefence.game.prices")
local shooter = require("mods.towerdefence.game.shooter")

local plots = {}

-- Two rings of eight. The inner one is the perimeter you can afford early:
-- close enough that one mount covers a lot of the approach to the base, and
-- cheap. The outer one intercepts further out -- more warning, more time for a
-- wave to be worn down before it arrives -- but it is a longer circumference,
-- so holding it means buying more of it. Extending outward is a commitment to
-- a bigger perimeter, which is the same decision a real defence makes.
local PLOT_COUNT = 8
local INNER_RING = 250 -- world pixels from the base
local OUTER_RING = 430

-- The outer ring opens once the core is actually held. Not an arbitrary gate:
-- a player who extends outward before the inner ring can cover itself ends up
-- with two thin rings instead of one solid one, and finds out four waves later.
plots.OUTER_REQUIRES = 4 -- inner mounts built

-- What a mount reaches. Most weapons carry 1200 pixels of range, which is
-- wider than the screen and would make where a mount stands irrelevant. Flame
-- weapons stay short because their own range is short (shooter.range), so a
-- flamethrower on a mount is exactly the close-in weapon it is in your hands.
local TOWER_MAX_RANGE = 420

-- A mount turns rather than snapping: a heavy gun swinging onto a target that
-- came from the wrong side is time the wave gets for free, and it is why two
-- cheap mounts covering two arcs beat one expensive mount trying to cover both.
local TURN_RATE = 2.6 -- radians per second
local FIRE_CONE = 0.18 -- radians of slop before it will pull the trigger

-- How long a mount's head takes to come back from a shot. Short enough to be a
-- snap rather than a wobble, long enough to survive a frame at any sane rate.
local RECOIL_TIME = 0.12

plots.BUILD_COST = 250
plots.OUTER_BUILD_COST = 400 -- further out, more exposed, more to hold
plots.UPGRADE_COST = 600

--- What building on this plot costs, and whether it can be built on at all.
-- Returns cost, or nil plus the reason it is not available yet.
function plots.build_cost(field, plot)
	if not plot.outer then return plots.BUILD_COST end
	local inner = 0
	for _, p in ipairs(field.plots) do
		if p.built and not p.outer then inner = inner + 1 end
	end
	if inner < plots.OUTER_REQUIRES then
		return nil, ("Hold the inner ring first (%d of %d mounts)")
			:format(inner, plots.OUTER_REQUIRES)
	end
	return plots.OUTER_BUILD_COST
end

-- Tier one holds the light end of the arsenal; anything heavier needs the
-- reinforced mount. This is what stops "buy the best gun, bolt it on
-- everything" being the whole game — the gun is not the only thing you pay for.
plots.TIER1_MAX_DPS = 12

--- The ring, in world coordinates. Index 1 is due north and they run clockwise,
-- which is also the order the HUD lists them in.
function plots.create(base_x, base_y)
	local list = {}
	for i = 1, PLOT_COUNT * 2 do
		local outer = i > PLOT_COUNT
		local n = outer and (i - PLOT_COUNT) or i
		-- the outer ring is offset by half a step, so it covers the gaps the
		-- inner ring leaves rather than hiding behind it
		local a = -math.pi / 2 + (n - 1) * (2 * math.pi / PLOT_COUNT)
			+ (outer and (math.pi / PLOT_COUNT) or 0)
		local ring = outer and OUTER_RING or INNER_RING
		list[i] = {
			index = i,
			outer = outer or nil,
			x = base_x + math.cos(a) * ring,
			y = base_y + math.sin(a) * ring,
			built = false,
			tier = 0,
			-- a mount is a shooter, so it carries a shooter's fields
			weapon = nil, ammo = 0, cooldown = 0, reloading = 0, muzzle = 0,
			angle = a,
		}
	end
	return list
end

--- Can this mount hold that weapon? Tier one is the light end; tier two is
-- everything.
function plots.accepts(plot, w)
	if not plot.built or not w then return false end
	if plot.tier >= 2 then return true end
	return prices.dps(w) <= plots.TIER1_MAX_DPS
end

function plots.range(plot)
	if not plot.weapon then return 0 end
	return math.min(shooter.range(plot.weapon), TOWER_MAX_RANGE)
end

--- Nearest live creature this mount can actually shoot. Nearest rather than
-- weakest or strongest: a mount defends a place, and what matters about a
-- target is how close it is to getting past.
local function target_for(field, plot)
	local range = plots.range(plot)
	local best, bd
	for _, c in ipairs(field.creatures) do
		if not c.dying then
			local dx, dy = c.x - plot.x, c.y - plot.y
			local d = dx * dx + dy * dy
			if d < range * range and (not bd or d < bd) then best, bd = c, d end
		end
	end
	return best
end

--- Shortest turn from `from` towards `to`, capped at `max`.
local function turn_towards(from, to, max)
	local diff = (to - from + math.pi) % (2 * math.pi) - math.pi
	if diff > max then diff = max elseif diff < -max then diff = -max end
	return from + diff
end

--- Where to aim so a round fired now arrives where the target will be.
--
-- A round takes time to cross the field and the thing it was fired at keeps
-- walking. That time is not small here: an Ion Cannon's bolt travels 160
-- pixels a second, so it needs about two and a half seconds to reach the edge
-- of a mount's 420-pixel reach, and a creature covers 200-300 pixels while it
-- is in the air -- ten times its own body. A mount aiming at where a creature
-- *is* therefore hits with the fast half of the arsenal and misses with the
-- slow half, for a reason the player can never see. Leading turns projectile
-- speed into something you can watch happening.
--
-- Solves |P + Vt - S| = speed * t for the smallest t >= 0 -- the round and the
-- creature have to be in one place at one time, which is a quadratic in t.
-- Falls back to the creature's own position when there is no solution: a
-- target outrunning the round cannot be led, and where it stands is the best
-- remaining answer.
local function intercept_time(sx, sy, tx, ty, vx, vy, speed)
	local dx, dy = tx - sx, ty - sy
	if speed <= 0 then return nil end

	local a = vx * vx + vy * vy - speed * speed
	local b = 2 * (dx * vx + dy * vy)
	local c = dx * dx + dy * dy
	local t
	if math.abs(a) < 1e-6 then
		-- the creature is keeping exact pace with the round: no square term
		-- left, and it can only be caught while it is not opening the gap
		if b ~= 0 then t = -c / b end
	else
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local root = math.sqrt(disc)
			local t1, t2 = (-b - root) / (2 * a), (-b + root) / (2 * a)
			-- the earlier meeting is the one the round actually makes
			if t1 < 0 or (t2 >= 0 and t2 < t1) then t1 = t2 end
			t = t1
		end
	end
	if t and t >= 0 then return t end
	return nil
end

local function lead_point(plot, target, speed, lag)
	local vx, vy = target.vx or 0, target.vy or 0
	-- A round under power arrives a fixed moment later than one that left at
	-- speed (shooter.launch_lag). Walking the creature forward by that moment
	-- before solving puts it back into the answer, and the point that comes
	-- out is still measured from where the creature is now.
	local tx, ty = target.x + vx * lag, target.y + vy * lag

	local function solve(sx, sy)
		local t = intercept_time(sx, sy, tx, ty, vx, vy, speed)
		if not t then return target.x, target.y end
		return tx + vx * t, ty + vy * t
	end

	-- Solved twice, because the round does not leave the middle of the plate:
	-- it appears at the end of the barrel, and where the barrel points is the
	-- answer we are working out. The first pass gives the bearing, the second
	-- solves from the muzzle that bearing puts the round at. One correction is
	-- enough -- twenty pixels of head start moves the aim by a fraction of
	-- itself -- and without it a slow round arrives early enough to miss a
	-- walking creature by half its own body.
	local ax, ay = solve(plot.x, plot.y)
	local a = math.atan2(ay - plot.y, ax - plot.x)
	return solve(plot.x + math.cos(a) * shooter.MUZZLE_OFFSET,
		plot.y + math.sin(a) * shooter.MUZZLE_OFFSET)
end

function plots.update(field, dt)
	for _, plot in ipairs(field.plots) do
		if plot.weapon then
			local target = target_for(field, plot)
			local aligned = false
			if target then
				plot.aim_x, plot.aim_y = lead_point(plot, target,
					shooter.bullet_speed(plot), shooter.launch_lag(plot))
				local want = math.atan2(plot.aim_y - plot.y, plot.aim_x - plot.x)
				plot.angle = turn_towards(plot.angle, want, TURN_RATE * dt)
				local off = math.abs((want - plot.angle + math.pi) % (2 * math.pi) - math.pi)
				aligned = off < FIRE_CONE
			else
				plot.aim_x, plot.aim_y = nil, nil
			end
			plot.target = target
			-- kept for the reticle: a mount swinging onto something reads
			-- differently from one that is already on it, and that difference
			-- is most of what the perimeter is telling you
			plot.aligned = aligned
			-- reloads itself in the quiet, which is the only thing a mount does
			-- better than a man: it never forgets
			shooter.update(field, plot, dt, target and aligned, not target)

			-- The kick, for the drawing (below). A fired round is the only
			-- thing that ever pushes `muzzle` up, so watching it rise is the
			-- whole shot detector — and it keeps recoil a property of how a
			-- mount is drawn rather than a field every shooter in the mod has
			-- to carry.
			if plot.muzzle > (plot.last_muzzle or 0) then plot.recoil = 1 end
			plot.last_muzzle = plot.muzzle
			plot.recoil = math.max(0, (plot.recoil or 0) - dt / RECOIL_TIME)
		end
	end
end

-- -------------------------------------------------------------------- draw

-- A mount is drawn as two things, because it is two things: a *pit* that never
-- moves, and a *head* that does nothing but turn. Splitting them is what makes
-- the perimeter legible in motion — the pit carries the mount's identity (which
-- plot, which tier) and stays quiet, and every bit of contrast is spent on the
-- one part whose whole job is pointing somewhere.
--
-- The pit is art (below). The head is not: it is drawn from the weapon's own
-- numbers, for the same reason prices.lua computes a price instead of listing
-- one. Thirty-eight weapons can stand on any of sixteen plots, and a sprite per
-- pairing is both unpaintable and a lie waiting to happen the first time a
-- weapon's stats move.

local BRASS = { 0.85, 0.68, 0.28 }
local BONE = { 0.91, 0.89, 0.84 }
local BLOOD = { 0.70, 0.13, 0.16 }
-- Gun steel, cooler than the pit it stands in and a clear step lighter, so the
-- head reads against the plate as well as against the ground.
local GUN = { 0.29, 0.31, 0.35 }
local GUN_HI = { 0.44, 0.46, 0.51 }
local GUN_LO = { 0.21, 0.23, 0.27 }
-- The head's brass is the pit's brass with the shine taken off. Full BRASS on a
-- muzzle brake or a magazine box reads as a separate bright object stuck to the
-- gun rather than a part of it — the fittings have to sit *under* the steel they
-- are bolted to, and the bright brass stays where it belongs, on the ground.
local FITTING = { 0.47, 0.37, 0.17 }

-- The pit, and the collar a reinforced mount wears over it. This mod's own art,
-- resolved through the mod asset overlay (src/engine/assets.lua looks in
-- mods/<name>/assets/ before the pak), which is what the overlay was built for:
-- the pak ships no buildings, because the original had none. Regenerate with
-- `python3 tools/make_td_art.py` — the geometry constants below are the same
-- ones that script draws to.
local PLATE = "td/mount-plate.png"
local COLLAR = "td/mount-collar.png"
local PLATE_SIZE = 64 -- world pixels the plate image covers
local COLLAR_SIZE = 80
local PIT_R = 30

-- What the head is made of, in world pixels along its own axis: the barrel
-- runs out from the front of the receiver, the counterweight hangs off the back.
local RECEIVER_BACK, RECEIVER_FRONT = -7, 11
local TAIL_BACK = -16
local BRAKE_LEN = 3.5

-- The four numbers a weapon already carries, mapped to the four things about a
-- gun those numbers would really change.
--
-- Barrel length is muzzle velocity, which is what a barrel is *for* — and it is
-- the only reach-shaped number in weapons.xml that says anything: every one of
-- the 38 weapons ships projectile_range="300", while projectile_speed runs from
-- the Ion and Plasma Cannons' 10 to the Gauss Gun's 215. Logarithmic, because
-- twenty of the thirty-eight sit at 45 and a linear scale would flatten all of
-- them against the railgun. So the Gauss Gun has the longest barrel on the
-- field and the cannons the stubbiest, which is both true and the ordering a
-- player already feels: a stubby mount is the one whose rounds have to be led.
-- Even the shortest barrel clears the pit's rim (PIT_R below). Breaking the
-- circle is what makes "which way is this one facing" a glance rather than a
-- study, and a mount whose barrel stopped inside its own plate would be a
-- disc again, which is what this whole drawing exists to stop being.
local BARREL_MIN, BARREL_MAX = 34, 50
local SPEED_SLOW, SPEED_FAST = 10, 215
local BORE_MIN, BORE_MAX = 2.0, 4.6
local DPS_FULL = 24 -- sustained dps at which a barrel is as fat as it gets
local RAPID, VERY_RAPID = 0.12, 0.06 -- seconds between rounds: 2 barrels, then 3
local SPREAD_WIDE = 0.35 -- radians of half-cone at which a choke is as open as it gets

--- The shape of the gun standing on this mount, read off the weapon itself.
--
-- Muzzle velocity becomes barrel length, sustained damage becomes bore, rate of
-- fire becomes a barrel cluster (only something emptying a clip in a second
-- needs three of them), and spread becomes the flare of the muzzle brake — a
-- shotgun's choke is visibly open where a rifle's is tight. None of it is
-- decoration: four stats you would otherwise have to walk over and read are
-- readable from the far side of the field, and they cannot drift from the
-- weapon, because they *are* the weapon.
local function head_geometry(plot)
	local w = plot.weapon
	local speed = math.max(SPEED_SLOW, math.min(SPEED_FAST, w.projectile_speed))
	local fast = math.log(speed / SPEED_SLOW) / math.log(SPEED_FAST / SPEED_SLOW)
	local dps = math.min(1, prices.dps(w) / DPS_FULL)
	return {
		len = BARREL_MIN + (BARREL_MAX - BARREL_MIN) * fast,
		bore = BORE_MIN + (BORE_MAX - BORE_MIN) * dps,
		barrels = (w.shoot_interval <= VERY_RAPID and 3)
			or (w.shoot_interval <= RAPID and 2) or 1,
		flare = 1.0 + 2.4 * math.min(1, (w.spread or 0) / SPREAD_WIDE),
		family = w.proj_art,
		-- the same flag that makes this weapon throw shells (shooter.fire), so
		-- the magazine box is on exactly the guns the brass comes out of
		brass = w.brass and true or false,
		glow = data.FAMILY_COLOR[w.proj_art],
	}
end

--- Where this head's barrels sit, across its axis. Spaced by more than a bore
-- so a cluster never merges back into one slab.
local function barrel_offsets(g)
	local gap = g.bore + 1.6
	if g.barrels >= 3 then return { -2 * gap, 0, 2 * gap } end
	if g.barrels == 2 then return { -gap, gap } end
	return { 0 }
end

--- Half the receiver's width: wide enough to be the thing the barrels come out
-- of, whatever the cluster does.
local function receiver_half(g, offs)
	return math.max(8.5, (offs[#offs] + g.bore) * 0.85)
end

local function set(c, a)
	love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A polygon in the head's own frame — x along the barrel, y across it —
-- rotated onto the world at `a`.
local function head_poly(x, y, a, pts)
	local c, s = math.cos(a), math.sin(a)
	local out = {}
	for i = 1, #pts, 2 do
		out[i] = x + pts[i] * c - pts[i + 1] * s
		out[i + 1] = y + pts[i] * s + pts[i + 1] * c
	end
	love.graphics.polygon("fill", out)
end

local function head_box(x, y, a, x0, x1, hw, oy)
	oy = oy or 0
	head_poly(x, y, a, { x0, oy - hw, x1, oy - hw, x1, oy + hw, x0, oy + hw })
end

--- Everything the head's silhouette is made of, and nothing else.
--
-- The pieces are laid out so that none of them overlap, which is what lets the
-- shadow pass be this same call in flat black: overlapping shapes at one alpha
-- would darken each other and the seams would show.
local function head_shapes(x, y, a, g, body, barrel, trim)
	if g.family == "flame" then
		-- a flamethrower has no barrel worth the name: a flared nozzle, and the
		-- fuel behind it. It reaches the shortest distance on the field and its
		-- silhouette is the only one that says so before it fires.
		set(barrel)
		head_poly(x, y, a, { 9, -4.5, 36, -11, 36, 11, 9, 4.5 })
		set(body)
		head_box(x, y, a, -7, 9, 9)
		set(trim)
		love.graphics.circle("fill", x + math.cos(a) * -14, y + math.sin(a) * -14, 6.5)
		return
	end

	local offs = barrel_offsets(g)
	local hw = receiver_half(g, offs)
	for _, o in ipairs(offs) do
		set(barrel)
		head_box(x, y, a, RECEIVER_FRONT, g.len - BRAKE_LEN, g.bore, o)
		set(trim)
		head_box(x, y, a, g.len - BRAKE_LEN, g.len, g.bore + g.flare, o)
	end
	set(body)
	head_box(x, y, a, RECEIVER_BACK, RECEIVER_FRONT, hw)
	head_box(x, y, a, TAIL_BACK, RECEIVER_BACK, 7.5) -- the counterweight that
	-- makes a head read as turning rather than as a stick pointing
	if g.brass then
		set(trim)
		head_box(x, y, a, -4, 4, 4.5, -(hw + 4.5))
	end
end

local SHADOW_OFF = 3 -- down and right, like the shadows the pak's creatures cast
local SHADE = { 0, 0, 0, 0.32 }

--- The gun, kicked back along its own axis by whatever is left of the last
-- round it fired.
local function draw_head(plot)
	local g = head_geometry(plot)
	local a = plot.angle
	local kick = (2 + g.bore) * (plot.recoil or 0)
	local x = plot.x - math.cos(a) * kick
	local y = plot.y - math.sin(a) * kick

	head_shapes(x + SHADOW_OFF, y + SHADOW_OFF, a, g, SHADE, SHADE, SHADE)
	head_shapes(x, y, a, g, GUN, GUN_LO, FITTING)
	-- the spine: one lit edge down the receiver, which is all the top-down view
	-- of a gun needs to stop being a flat shape
	set(GUN_HI)
	head_box(x, y, a, RECEIVER_BACK, RECEIVER_FRONT, 2.5)

	-- an energy weapon's coil, in the same colour its bolts leave in
	if g.glow and (g.family == "plasma" or g.family == "ion" or g.family == "pulse") then
		set(g.glow, 0.9)
		love.graphics.circle("line", x, y, 6)
		love.graphics.circle("fill", x, y, 2.5)
	end

	-- The flash goes at the end of the barrel, which is now a different place
	-- for every weapon. The round itself still starts at shooter.MUZZLE_OFFSET,
	-- a constant, so a long-barrelled gun flashes a little ahead of where its
	-- round appears. Closing that means letting a shooter name its own muzzle
	-- (`owner.muzzle_offset or shooter.MUZZLE_OFFSET` in shooter.fire) — worth
	-- doing, but it moves the point the intercept solves from, so it belongs
	-- with that code rather than with this drawing.
	if plot.muzzle > 0 then
		local mf = assets.image("game/muzzle-flash.png")
		if mf then
			love.graphics.setBlendMode("add")
			love.graphics.setColor(1, 1, 1, plot.muzzle / 0.05)
			love.graphics.draw(mf, x + math.cos(a) * g.len, y + math.sin(a) * g.len,
				a, 0.32, 0.32, mf:getWidth() / 2, mf:getHeight() / 2)
			love.graphics.setBlendMode("alpha")
		end
	end
end

--- The pit: art if the overlay resolved it, rings if it did not.
local function draw_pit(plot)
	local x, y = plot.x, plot.y
	local plate = assets.image(PLATE)
	love.graphics.setColor(1, 1, 1, 1)
	if plate then
		local s = PLATE_SIZE / plate:getWidth()
		love.graphics.draw(plate, x, y, 0, s, s,
			plate:getWidth() / 2, plate:getHeight() / 2)
	else
		love.graphics.setColor(0.23, 0.24, 0.26, 1)
		love.graphics.circle("fill", x, y, PIT_R)
		set(BRASS, 0.7)
		love.graphics.circle("line", x, y, PIT_R - 1.6)
	end

	if plot.tier >= 2 then
		-- the reinforced mount is a different shape, not a brighter one: four
		-- buttress lugs that are visible at any distance the pit itself is
		local collar = assets.image(COLLAR)
		if collar then
			local s = COLLAR_SIZE / collar:getWidth()
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.draw(collar, x, y, 0, s, s,
				collar:getWidth() / 2, collar:getHeight() / 2)
		else
			set(BRASS, 0.9)
			love.graphics.circle("line", x, y, 33)
		end
	end

	-- The plot's own number, stencilled on the floor where it will be half
	-- covered by the gun standing on it. It is the number the HUD uses when you
	-- are close enough to buy something ("MOUNT 3 — Assault Rifle"), so the ring
	-- on the ground and the list in the HUD are the same eight things.
	local label = tostring(plot.index)
	font.draw("fonts/small.mft", label,
		x - font.measure("fonts/small.mft", label) / 2, y + 13,
		{ BONE[1], BONE[2], BONE[3], 0.28 })
end

local function draw_mount(plot, near)
	local x, y = plot.x, plot.y

	if not plot.built then
		-- an empty plot is a promise, not a thing: faint, and only worth
		-- noticing when you are close enough to buy it
		set(BRASS, near and 0.5 or 0.18)
		love.graphics.circle("line", x, y, 26)
		love.graphics.setColor(1, 1, 1, 1)
		return
	end

	draw_pit(plot)
	if plot.weapon then draw_head(plot) end

	if plot.weapon and plot.reloading > 0 and (plot.reload_total or 0) > 0 then
		-- Reloading is downtime you can see from across the field, because it is
		-- when that arc is open. Swept rather than switched: how much longer the
		-- side is open is the part worth knowing, and a ring that is simply on
		-- cannot say it.
		local k = 1 - plot.reloading / plot.reload_total
		set(BLOOD, 0.85)
		love.graphics.setLineWidth(3)
		love.graphics.arc("line", "open", x, y, PIT_R + 5,
			-math.pi / 2, -math.pi / 2 + 2 * math.pi * k)
		love.graphics.setLineWidth(1)
	end

	-- what this mount covers, while you are standing next to it deciding
	if near and plot.weapon then
		set(BRASS, 0.12)
		love.graphics.circle("line", x, y, plots.range(plot))
	end
	love.graphics.setColor(1, 1, 1, 1)
end

function plots.draw(field)
	for _, plot in ipairs(field.plots) do
		draw_mount(plot, field.near_plot == plot)
	end
end

-- The reticle: a ring on the intercept with four ticks outside it, and a
-- hairline back to the creature it belongs to.
local RETICLE_R = 9
local TICK_IN, TICK_OUT = 3, 6

--- What a mount is aiming at, drawn on the ground it is aiming at rather than
-- on the mount. The lead is the whole point: the line is the distance between
-- where the creature is and where the round is being sent, so a slow weapon
-- visibly throws its aim further ahead than a fast one, and a mount that has
-- lost its target has nothing drawn at all.
local function draw_aim(plot, near)
	local t = plot.target
	if not t or not plot.aim_x or t.dying then return end
	local x, y = plot.aim_x, plot.aim_y

	-- A mount still swinging round is not making a promise yet, so it says so
	-- quietly; the one you are standing at is the one you are asking about.
	local alpha = (plot.aligned and 0.55 or 0.28) * (near and 1.6 or 1)

	love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], alpha * 0.45)
	love.graphics.line(t.x, t.y, x, y)

	love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], alpha)
	love.graphics.circle("line", x, y, RETICLE_R)
	for i = 0, 3 do
		local cx, cy = math.cos(i * math.pi / 2), math.sin(i * math.pi / 2)
		love.graphics.line(x + cx * (RETICLE_R + TICK_IN), y + cy * (RETICLE_R + TICK_IN),
			x + cx * (RETICLE_R + TICK_OUT), y + cy * (RETICLE_R + TICK_OUT))
	end
	love.graphics.setColor(1, 1, 1, 1)
end

--- Second pass, run after the creatures are on screen (game/field.lua). The
-- mounts themselves are furniture and stay under everything alive, but a
-- reticle drawn under the thing it is on is not a reticle.
function plots.draw_aims(field)
	for _, plot in ipairs(field.plots) do
		if plot.weapon then draw_aim(plot, field.near_plot == plot) end
	end
end

--- The plot the player is standing on, if any.
function plots.at(field, x, y, radius)
	for _, plot in ipairs(field.plots) do
		local dx, dy = plot.x - x, plot.y - y
		if dx * dx + dy * dy < radius * radius then return plot end
	end
	return nil
end

return plots

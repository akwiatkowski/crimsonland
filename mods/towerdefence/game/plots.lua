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

function plots.update(field, dt)
	for _, plot in ipairs(field.plots) do
		if plot.weapon then
			local target = target_for(field, plot)
			local aligned = false
			if target then
				local want = math.atan2(target.y - plot.y, target.x - plot.x)
				plot.angle = turn_towards(plot.angle, want, TURN_RATE * dt)
				local off = math.abs((want - plot.angle + math.pi) % (2 * math.pi) - math.pi)
				aligned = off < FIRE_CONE
			end
			plot.target = target
			-- reloads itself in the quiet, which is the only thing a mount does
			-- better than a man: it never forgets
			shooter.update(field, plot, dt, target and aligned, not target)
		end
	end
end

-- -------------------------------------------------------------------- draw

local BRASS = { 0.85, 0.68, 0.28 }

--- The mount, drawn as a plate wearing the weapon's own gallery icon.
--
-- The pak has no turret art in it and this mod owns no art of its own yet, so
-- the honest thing is also the readable one: the icon that means "Plasma
-- Cannon" everywhere else in the game means it here too, and a glance at the
-- perimeter says what is holding which side.
local function draw_mount(plot, near)
	local x, y = plot.x, plot.y

	if not plot.built then
		-- an empty plot is a promise, not a thing: faint, and only worth
		-- noticing when you are close enough to buy it
		love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], near and 0.5 or 0.18)
		love.graphics.circle("line", x, y, 26)
		love.graphics.setColor(1, 1, 1, 1)
		return
	end

	-- the plate
	love.graphics.setColor(0.10, 0.10, 0.11, 0.9)
	love.graphics.circle("fill", x, y, 30)
	love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], plot.tier >= 2 and 1 or 0.6)
	love.graphics.circle("line", x, y, 30)
	if plot.tier >= 2 then love.graphics.circle("line", x, y, 26) end

	if plot.weapon then
		-- the barrel: a line towards whatever it is tracking, which is what
		-- makes a perimeter legible in motion rather than a row of ornaments
		love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 0.9)
		love.graphics.setLineWidth(3)
		love.graphics.line(x, y, x + math.cos(plot.angle) * 34,
			y + math.sin(plot.angle) * 34)
		love.graphics.setLineWidth(1)

		local icon = plot.weapon.icon and assets.image(plot.weapon.icon)
		if icon then
			local s = 44 / math.max(icon:getWidth(), icon:getHeight())
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.draw(icon, x, y, 0, s, s,
				icon:getWidth() / 2, icon:getHeight() / 2)
		end

		if plot.muzzle > 0 then
			local mf = assets.image("game/muzzle-flash.png")
			if mf then
				love.graphics.setBlendMode("add")
				love.graphics.setColor(1, 1, 1, plot.muzzle / 0.05)
				love.graphics.draw(mf, x + math.cos(plot.angle) * 34,
					y + math.sin(plot.angle) * 34, plot.angle, 0.32, 0.32,
					mf:getWidth() / 2, mf:getHeight() / 2)
				love.graphics.setBlendMode("alpha")
			end
		end

		if plot.reloading > 0 then
			-- reloading is downtime you can see from across the field, because
			-- it is when that arc is open
			love.graphics.setColor(0.70, 0.13, 0.16, 0.8)
			love.graphics.circle("line", x, y, 34)
		end
	end

	-- what this mount covers, while you are standing next to it deciding
	if near and plot.weapon then
		love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 0.12)
		love.graphics.circle("line", x, y, plots.range(plot))
	end
	love.graphics.setColor(1, 1, 1, 1)
end

function plots.draw(field)
	for _, plot in ipairs(field.plots) do
		draw_mount(plot, field.near_plot == plot)
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

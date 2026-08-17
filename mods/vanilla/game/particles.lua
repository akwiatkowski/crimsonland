-- Lightweight particle system for gameplay feedback: blood bursts, muzzle
-- smoke, explosions. This is NOT the original fxs/ DSL interpreter (that
-- format describes emitter graphs; still an open item) — it is a compact
-- effect layer producing comparable visuals with plain circles/glows.

local particles = {}

local pool = {} -- live particles

--- Spawn a burst of particles.
-- opts: n, speed (px/s, randomized 50-100%), life (s), size (px),
--       color {r,g,b}, drag (fraction of velocity kept per second),
--       glow (draw additive), dir + spread (radians; omit dir = full circle)
local function burst(x, y, opts)
	for _ = 1, opts.n do
		local ang
		if opts.dir then
			ang = opts.dir + (love.math.random() - 0.5) * (opts.spread or 0.6)
		else
			ang = love.math.random() * math.pi * 2
		end
		local speed = opts.speed * (0.5 + love.math.random() * 0.5)
		local life = opts.life * (0.6 + love.math.random() * 0.6)
		pool[#pool + 1] = {
			x = x,
			y = y,
			dx = math.cos(ang) * speed,
			dy = math.sin(ang) * speed,
			life = life,
			max_life = life,
			size = opts.size * (0.6 + love.math.random() * 0.8),
			r = opts.color[1],
			g = opts.color[2],
			b = opts.color[3],
			drag = opts.drag or 0.05,
			glow = opts.glow or false,
		}
	end
end

--- Blood spray when a bullet connects; dir = incoming bullet angle.
function particles.blood(x, y, dir)
	burst(x, y, { n = 6, speed = 140, life = 0.35, size = 2.5,
		color = { 0.7, 0.05, 0.05 }, dir = dir, spread = 1.2 })
end

--- Bigger gush on a kill.
function particles.death_burst(x, y, scale)
	burst(x, y, { n = 14, speed = 180, life = 0.5, size = 3 * (scale or 1),
		color = { 0.6, 0.04, 0.04 } })
end

--- Rocket/plasma explosion: fireball core + sparks + lingering smoke.
function particles.explosion(x, y, radius)
	burst(x, y, { n = 20, speed = radius * 3.2, life = 0.35, size = 6,
		color = { 1.0, 0.7, 0.2 }, glow = true, drag = 0.02 })
	burst(x, y, { n = 12, speed = radius * 1.2, life = 0.9, size = 9,
		color = { 0.25, 0.22, 0.2 }, drag = 0.1 })
end

--- Small pickup sparkle.
function particles.sparkle(x, y)
	burst(x, y, { n = 10, speed = 90, life = 0.4, size = 2,
		color = { 0.9, 0.9, 0.5 }, glow = true })
end

function particles.update(dt)
	for i = #pool, 1, -1 do
		local p = pool[i]
		p.life = p.life - dt
		if p.life <= 0 then
			pool[i] = pool[#pool]
			pool[#pool] = nil
		else
			-- exponential drag: velocity decays toward zero
			local keep = p.drag ^ dt
			p.dx = p.dx * keep
			p.dy = p.dy * keep
			p.x = p.x + p.dx * dt
			p.y = p.y + p.dy * dt
		end
	end
end

--- Draw inside the world transform (camera already applied).
function particles.draw()
	for _, p in ipairs(pool) do
		local a = p.life / p.max_life
		if p.glow then
			love.graphics.setBlendMode("add")
		end
		love.graphics.setColor(p.r, p.g, p.b, a)
		love.graphics.circle("fill", p.x, p.y, p.size * (0.5 + 0.5 * a))
		if p.glow then
			love.graphics.setBlendMode("alpha")
		end
	end
	love.graphics.setColor(1, 1, 1, 1)
end

function particles.clear()
	pool = {}
end

function particles.count()
	return #pool
end

return particles

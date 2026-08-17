-- Interpreter for the original engine's particle DSL (`fxs/*.lua`).
--
-- An effect file is a plain Lua script that only calls into three functions,
-- so "parsing" it is just running it with those bound:
--
--   FXParm(name, a, b)     parameter of the first emitter; two values mean a
--                          random range, one value means a constant
--   PartFXAddNew()         start another emitter in the same file
--   PartFXParm(name, ...)  parameter of the emitter started last
--
-- `scale_graph` and `alpha_graph` are the exception: each call adds a keyframe
-- (t, value) with t normalized over the particle's life, and the runtime
-- interpolates between them.
--
-- Angles are in degrees, clockwise, 0 = right (screen space, y down).
-- Emitters are spawned by SpawnEmitterFX from the pak's own scripts (the menu
-- trooper's shell casings) and by the gameplay layer.

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local paths = require("src.engine.paths")

local fx = {}

local GRAPH_PARAMS = { scale_graph = true, alpha_graph = true }
-- Per layer. The UI's own emitters are small (1-100 particles), but the world
-- layer now carries the gameplay effects too — a swarm coming apart is a lot of
-- blood on top of the brass — so the cap has room for a busy fight before it
-- starts dropping bursts.
local MAX_PARTICLES = 1500

local cache = {}
-- Two pools because the two callers live in different spaces: UI emitters are
-- placed in reference coordinates and drawn by the engine, gameplay emitters in
-- world coordinates and drawn by the game inside its camera transform.
local pools = { screen = {}, world = {} }

-- ------------------------------------------------------------------ loading

-- Values arrive as varargs rather than (a, b) because `bitmap_rect` needs four
-- of them. Everything the pak's own files use still lands the same way: one
-- number is a constant, two are a random range.
local function param_setter(emitter)
	return function(name, ...)
		local n = select("#", ...)
		local a = ...
		if GRAPH_PARAMS[name] then
			local graph = emitter[name] or {}
			graph[#graph + 1] = { t = a or 0, v = (select(2, ...)) or 0 }
			emitter[name] = graph
		elseif type(a) == "string" then
			emitter[name] = a
		else
			local vals = {}
			for i = 1, math.max(n, 1) do vals[i] = (select(i, ...)) or 0 end
			if n < 2 then vals[2] = vals[1] end -- one value = a zero-width range
			emitter[name] = vals
		end
	end
end

--- Load fxs/<name>.lua as a list of emitter parameter tables.
function fx.load(path)
	if cache[path] ~= nil then return cache[path] or nil end

	-- A mod's own effects live in the mod, because the pak is read-only and
	-- gitignored — so a path that resolves as-is wins over the assets root.
	local file = love.filesystem.getInfo(path) and path
		or (paths.ASSETS .. "/" .. path)
	local chunk = loadfile(file)
	if not chunk then
		print(("[fx] cannot load %s"):format(path))
		cache[path] = false
		return nil
	end

	local emitters = { {} }
	local current = 1
	local env = {
		math = math,
		FXParm = param_setter(emitters[1]),
		PartFXAddNew = function()
			emitters[#emitters + 1] = {}
			current = #emitters
		end,
	}
	-- PartFXParm always targets the emitter PartFXAddNew opened last. Forwards
	-- varargs, not (a, b): truncating here silently gave every emitter past the
	-- first a two-value bitmap_rect, hence a zero-size quad and nothing drawn.
	env.PartFXParm = function(name, ...)
		param_setter(emitters[current])(name, ...)
	end
	setfenv(chunk, env)

	local ok, err = pcall(chunk)
	if not ok then
		print(("[fx] %s: %s"):format(path, tostring(err)))
		cache[path] = false
		return nil
	end
	cache[path] = emitters
	return emitters
end

-- ------------------------------------------------------------------ spawning

local function rand_range(range, default)
	if not range then return default end
	if type(range) ~= "table" then return default end
	local a, b = range[1], range[2]
	if a == b then return a end
	return a + love.math.random() * (b - a)
end

local function sample(graph, t, default)
	if not graph or #graph == 0 then return default end
	if t <= graph[1].t then return graph[1].v end
	for i = 2, #graph do
		local prev, cur = graph[i - 1], graph[i]
		if t <= cur.t then
			local span = cur.t - prev.t
			if span <= 0 then return cur.v end
			return prev.v + (cur.v - prev.v) * ((t - prev.t) / span)
		end
	end
	return graph[#graph].v
end

local function emit(e, x, y, rot, pool, fade, base_scale)
	local n = math.floor(rand_range(e.num_parts, 1))
	local image = e.bitmap and assets.image(e.bitmap)
	if not image then return end
	base_scale = base_scale or 1

	-- `bitmap_rect` (x, y, w, h in reference units) is this port's one addition
	-- to the DSL. The pak's effect files each name a whole file because the
	-- effects it shipped had one; the gameplay effects want game/particles.tga,
	-- which is the 256x256 sheet the C++ side drew blood, fire and smoke from.
	local quad, quad_scale, qw, qh
	if e.bitmap_rect then
		local r = e.bitmap_rect
		quad, quad_scale = assets.quad(image, r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0)
		qw, qh = select(3, quad:getViewport())
	end

	for _ = 1, n do
		if #pool >= MAX_PARTICLES then return end

		-- start position: a disc slice (area_radius/area_angle_spread) and/or
		-- a box (area_box), both centered on the emitter
		local px, py = x, y
		local radius = rand_range(e.area_radius, 0)
		if radius ~= 0 then
			local spread = rand_range(e.area_angle_spread, 360)
			local a = math.rad(rot + (love.math.random() - 0.5) * spread)
			px, py = px + math.cos(a) * radius, py + math.sin(a) * radius
		end
		if e.area_box then
			px = px + (love.math.random() - 0.5) * (e.area_box[1] or 0)
			py = py + (love.math.random() - 0.5) * (e.area_box[2] or 0)
		end

		local life = rand_range(e.age_to_die, 1)
		local move = math.rad(rot + rand_range(e.move_angle, 0)
			+ (love.math.random() - 0.5) * rand_range(e.move_angle_spread, 0))
		local speed = rand_range(e.move_speed, rand_range(e.speed, 0)) * base_scale

		pool[#pool + 1] = {
			image = image,
			quad = quad,
			quad_scale = quad_scale,
			quad_w = qw,
			quad_h = qh,
			base_scale = base_scale,
			additive = e.blend_mode == "ADDITIVE",
			x = px,
			y = py,
			dx = math.cos(move) * speed,
			dy = math.sin(move) * speed,
			-- The engine's own meaning of `mass` is not documented anywhere in
			-- the pak; read here as halvings of speed per second, which makes
			-- the only user of it (shell casings, mass 8) eject ~20px and stop
			-- — what the ejected brass does in the original.
			drag = e.mass and 0.5 ^ rand_range(e.mass, 0) or 1,
			angle = math.rad(rot + rand_range(e.angle, 0)
				+ (love.math.random() - 0.5) * rand_range(e.angle_spread, 0)),
			spin = math.rad(rand_range(e.rot_angle_rps, 0)),
			age = rand_range(e.age, 0),
			life = life,
			alpha = rand_range(e.alpha, 1),
			fade = fade,
			scale_graph = e.scale_graph,
			alpha_graph = e.alpha_graph,
		}
	end

	if e.sound then audio.play_sound(e.sound) end
end

--- Play `path` at x,y. `rot` (degrees) turns the whole effect, so a gameplay
-- caller can eject shells along whatever way the player happens to face.
-- opts:
--   layer = "screen" (default) | "world"
--   fade  = fraction of life spent fading out. The DSL can author that in
--           alpha_graph and mostly does, but shells1.lua holds alpha at 1 to
--           the last frame and then simply stops existing — fine for the
--           trooper scene it was written for, visible litter in gameplay.
--   scale = size and throw multiplier, for one effect serving several sizes
--           (a rocket blast and a bursting creature are the same explosion)
function fx.spawn(path, x, y, rot, opts)
	local emitters = fx.load(path)
	if not emitters then return end
	opts = opts or {}
	local pool = pools[opts.layer or "screen"]
	for _, e in ipairs(emitters) do
		emit(e, x, y, rot or 0, pool, opts.fade, opts.scale)
	end
end

-- ------------------------------------------------------------------ runtime

function fx.update(dt)
	for _, pool in pairs(pools) do
		for i = #pool, 1, -1 do
			local p = pool[i]
			p.age = p.age + dt
			if p.age >= p.life then
				pool[i] = pool[#pool]
				pool[#pool] = nil
			else
				local keep = p.drag ^ dt
				p.dx, p.dy = p.dx * keep, p.dy * keep
				p.x = p.x + p.dx * dt
				p.y = p.y + p.dy * dt
				p.angle = p.angle + p.spin * dt
			end
		end
	end
end

--- Draw one layer; the caller owns whatever transform it belongs in.
function fx.draw(layer)
	for _, p in ipairs(pools[layer or "screen"]) do
		local t = p.age / p.life
		local scale = sample(p.scale_graph, t, 1) * p.base_scale
		local alpha = p.alpha * sample(p.alpha_graph, t, 1)
		if p.fade and t > 1 - p.fade then alpha = alpha * (1 - t) / p.fade end
		love.graphics.setBlendMode(p.additive and "add" or "alpha")
		love.graphics.setColor(1, 1, 1, alpha)
		if p.quad then
			-- a quad addresses texels, so its origin and scale are in texels too
			local s = scale * p.quad_scale
			love.graphics.draw(p.image, p.quad, p.x, p.y, p.angle, s, s,
				p.quad_w / 2, p.quad_h / 2)
		else
			love.graphics.draw(p.image, p.x, p.y, p.angle, scale, scale,
				p.image:getWidth() / 2, p.image:getHeight() / 2)
		end
	end
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
end

function fx.clear(layer)
	if layer then
		pools[layer] = {}
	else
		pools = { screen = {}, world = {} }
	end
end

--- Live particle count, for one layer or (with no argument) both. The split
-- matters to anything watching a UI effect while a game runs behind it — the
-- attract-mode menu is exactly that.
function fx.count(layer)
	if layer then return #pools[layer] end
	return #pools.screen + #pools.world
end

return fx

-- The ground a quest is fought on, baked once from the op list the original
-- authored in terrains/terrains.xml.
--
-- Each `<node>` in a chapter's array is one drawing operation, applied in
-- file order onto a canvas the size of the playfield. The file documents four
-- of the ten actions it uses; the rest are read off the parameters they carry
-- and are marked as inferred where that matters.
--
-- Two things run through all of it:
--
--   * `SetSeeds` gives a chapter a list of seeds -- ten of them, for the ten
--     quests of a chapter -- so quest 3 of chapter 1 always bakes the same
--     ground, and it is not the ground quest 4 gets. Every random choice below
--     comes from that one generator, in op order, which is what makes the bake
--     reproducible.
--   * `quest_number_required` holds an op back until the player is that deep
--     into the chapter. It is on the blast marks, the debris and the roads, so
--     the same field gets visibly more fought-over as the chapter goes on. The
--     port used to ignore it and draw everything from quest 1.

local assets = require("src.engine.assets")
local data = require("mods.vanilla.game.data")

local terrain = {}

-- Terrains with no SetSeeds of their own still have to bake the same way
-- twice; this is the generator they get.
local DEFAULT_SEED = 12345

-- Bakes are expensive and a session holds on to its canvas for the whole run,
-- so only a couple are worth keeping: the one being played and whatever the
-- attract mode drew last. Evicted canvases are released rather than left for
-- the collector -- at render density these are tens of megabytes each.
local CACHE_MAX = 4

-- Ceiling on the canvas density. The window can ask for 3.8 device pixels per
-- reference unit on a large retina display, which for a 1820x1024 playfield is
-- a 107 MB texture -- and buys nothing, because the terrain art only ships at
-- base resolution and the densest thing ever drawn into the canvas afterwards
-- is a creature from the 1080p set.
local MAX_DENSITY = assets.HIRES_SCALE

local cache = {} -- key -> canvas
local cache_order = {} -- keys, oldest first

local function num(v, default)
	local n = tonumber(v)
	if n == nil then return default end
	return n
end

-- ------------------------------------------------------------------- ops

local ops = {}

-- The file spells this two ways: `r/g/b` on four of the nine Clear nodes and
-- `color_r/color_g/color_b` (what the file's own notes document) on the other
-- five. Reading only one spelling left those five chapters starting from the
-- default mud instead of their authored ground colour.
function ops.Clear(ctx, op)
	love.graphics.clear(
		num(op.r or op.color_r, 0.2),
		num(op.g or op.color_g, 0.2),
		num(op.b or op.color_b, 0.1), 1)
end

-- "Fills the whole terrain tiled with given bitmap at random angles" -- the
-- random angle is the file's own wording, and it is what stops a 256px base
-- texture reading as a grid. It is safe because `tile_spacing` is 0.5
-- everywhere it is used: tiles step by half their width, so they overlap and
-- a rotated tile has no seam to break.
function ops.DrawTiled(ctx, op)
	local img = assets.image(op.bm)
	if not img then return end
	local spacing = num(op.tile_spacing, 1)
	local scale = num(op.tile_scale, 1)
	local iw, ih = img:getWidth(), img:getHeight()
	local stepx = math.max(1, iw * spacing * scale)
	local stepy = math.max(1, ih * spacing * scale)
	love.graphics.setColor(1, 1, 1, num(op.alpha, 1))
	local y = 0
	while y <= ctx.h + stepy do
		local x = 0
		while x <= ctx.w + stepx do
			love.graphics.draw(img, x, y, ctx.rng:random() * math.pi * 2,
				scale, scale, iw / 2, ih / 2)
			x = x + stepx
		end
		y = y + stepy
	end
end

-- "Draws given bitmap at random positions". Three modifiers ride along:
-- `angle_stepping` snaps the rotation to a multiple (90 on the stone rings,
-- so they stay square to the world), `min/max_rotation_degrees` pins it to a
-- range instead, and `size_variation` spreads the size. Variation is read
-- geometrically -- 2.0 means anywhere from half size to double -- because
-- that is what makes a field of blast marks look like craters of different
-- ages rather than one crater and some bigger ones.
function ops.DrawSplashes(ctx, op)
	local img = assets.image(op.bm)
	if not img then return end
	local n = num(op.num_splashes, 10)
	local stepping = num(op.angle_stepping, 0)
	local vary = num(op.size_variation, 0)
	local rmin, rmax = num(op.min_rotation_degrees), num(op.max_rotation_degrees)
	local ox, oy = img:getWidth() / 2, img:getHeight() / 2
	love.graphics.setColor(1, 1, 1, num(op.alpha, 1))
	for _ = 1, n do
		local x = ctx.rng:random() * ctx.w
		local y = ctx.rng:random() * ctx.h
		local deg
		if rmin and rmax then
			deg = rmin + ctx.rng:random() * (rmax - rmin)
		else
			deg = ctx.rng:random() * 360
		end
		if stepping > 0 then
			deg = math.floor(deg / stepping + 0.5) * stepping
		end
		local s = 1
		if vary > 1 then s = vary ^ (ctx.rng:random() * 2 - 1) end
		love.graphics.draw(img, x, y, math.rad(deg), s, s, ox, oy)
	end
end

-- "Draws a single bitmap with given parameters" -- the landing pad and the
-- summoning circle, which are placed by hand because they are the thing the
-- level is about.
function ops.DrawSingle(ctx, op)
	local img = assets.image(op.bm)
	if not img then return end
	love.graphics.setColor(1, 1, 1, num(op.alpha, 1))
	love.graphics.draw(img, num(op.x, 0), num(op.y, 0),
		math.rad(num(op.angle_degrees, 0)), num(op.scale, 1), num(op.scale, 1),
		img:getWidth() / 2, img:getHeight() / 2)
end

-- INFERRED (the file documents no parameters for this one).
--
-- Scatter a detail bitmap where a noise field says there should be some.
-- `sampling_step` is the grid walked, `frequency` reads as how many noise
-- features span the field (18 gives roughly hundred-pixel patches of grass,
-- 8 gives broad sweeps), `amplitude` as how far a sample may be pushed off
-- its grid point so the grid never shows, and `alpha_multiplier` as the
-- ceiling on coverage. Only the upper half of the noise range draws, so the
-- detail comes in patches with clean ground between them.
function ops.DrawWithPerlinNoise(ctx, op)
	local img = assets.image(op.bm)
	if not img then return end
	local step = math.max(4, num(op.sampling_step, 32))
	local freq = math.max(0.001, num(op.frequency, 8))
	local amp = num(op.amplitude, 0)
	local mul = num(op.alpha_multiplier, 1)
	local scale = num(op.bitmap_scale, 1)
	local ox, oy = img:getWidth() / 2, img:getHeight() / 2
	-- offset the whole field per bake, so two terrains sharing a bitmap and a
	-- frequency do not put their patches in the same places
	local nx = ctx.rng:random() * 100
	local ny = ctx.rng:random() * 100
	local y = 0
	while y <= ctx.h do
		local x = 0
		while x <= ctx.w do
			local n = love.math.noise(nx + x / ctx.w * freq, ny + y / ctx.h * freq)
			if n > 0.5 then
				local a = (n - 0.5) * 2 * mul
				love.graphics.setColor(1, 1, 1, a)
				love.graphics.draw(img,
					x + (ctx.rng:random() - 0.5) * 2 * amp,
					y + (ctx.rng:random() - 0.5) * 2 * amp,
					ctx.rng:random() * math.pi * 2, scale, scale, ox, oy)
			else
				-- keep the generator in step regardless of the branch, or the
				-- ops after this one shift when the noise does
				ctx.rng:random(); ctx.rng:random(); ctx.rng:random()
			end
			x = x + step
		end
		y = y + step
	end
end

-- INFERRED. `DrawPerlin` carries no parameters at all, so nothing in the data
-- says what it draws. What it can only be is the pass that stops the ground
-- being evenly lit: a low-frequency wash of soft dark patches over everything
-- laid down so far. Kept deliberately faint -- this is shading, and getting it
-- wrong loudly would be worse than not having it.
local PERLIN_GRID = 48 -- noise cells across the field
local PERLIN_MAX_ALPHA = 0.22

function ops.DrawPerlin(ctx)
	local cells_x = PERLIN_GRID
	local cells_y = math.max(1, math.floor(PERLIN_GRID * ctx.h / ctx.w))
	local shade = love.image.newImageData(cells_x, cells_y)
	local ox = ctx.rng:random() * 100
	local oy = ctx.rng:random() * 100
	shade:mapPixel(function(x, y)
		local n = love.math.noise(ox + x / cells_x * 6, oy + y / cells_y * 6)
		-- only the dark half: this darkens hollows, it does not invent light
		return 0, 0, 0, math.max(0, 0.5 - n) * 2 * PERLIN_MAX_ALPHA
	end)
	local img = love.graphics.newImage(shade)
	img:setFilter("linear", "linear") -- the cells must not show as squares
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(img, 0, 0, 0, ctx.w / cells_x, ctx.h / cells_y)
	img:release()
	shade:release()
end

-- INFERRED, but the parameters leave little room: `num_points` sites, a brush
-- bitmap that is a short vertical bar (trail_black/trail_purple), a
-- `thickness`, and an alpha of 0.04-0.07. That is a faint web of trails laid
-- along the boundaries between cells -- the cracked-earth look.
--
-- Finding those boundaries exactly needs a real Voronoi diagram; finding them
-- closely enough needs only the standard trick, which is that a point is on a
-- boundary when its two nearest sites are nearly equidistant. The field is
-- walked at `thickness` and a brush is stamped wherever that holds, turned to
-- lie along the boundary (which runs perpendicular to the line between the
-- two sites).
function ops.DrawVoronoi(ctx, op)
	local img = assets.image(op.bm)
	if not img then return end
	local n = math.floor(num(op.num_points, 100))
	local thickness = math.max(2, num(op.thickness, 8))
	if n < 2 then return end

	local sx, sy = {}, {}
	for i = 1, n do
		sx[i] = ctx.rng:random() * ctx.w
		sy[i] = ctx.rng:random() * ctx.h
	end

	-- Sites go into a grid of roughly one site per cell, so a sample only
	-- measures against its own neighbourhood instead of all 230 of them. The
	-- 5x5 block around a sample reaches about two and a half average spacings,
	-- which holds its two nearest sites except in the sparsest corners -- and
	-- there the fallback below catches it. Without this the pass costs ~200ms.
	local spacing = math.sqrt(ctx.w * ctx.h / n)
	local cols = math.max(1, math.floor(ctx.w / spacing))
	local rows = math.max(1, math.floor(ctx.h / spacing))
	local cell_w, cell_h = ctx.w / cols, ctx.h / rows
	local buckets = {}
	local function bucket(cx, cy)
		local b = buckets[cy * cols + cx]
		if not b then
			b = {}
			buckets[cy * cols + cx] = b
		end
		return b
	end
	for i = 1, n do
		local b = bucket(
			math.min(cols - 1, math.floor(sx[i] / cell_w)),
			math.min(rows - 1, math.floor(sy[i] / cell_h)))
		b[#b + 1] = i
	end

	local ox, oy = img:getWidth() / 2, img:getHeight() / 2
	love.graphics.setColor(1, 1, 1, num(op.alpha, 1))

	-- Nearest two sites to the sample, by squared distance (the square root is
	-- only needed for the two that win). Hoisted out of the sample loop with
	-- its state as upvalues: closing over x,y inside would allocate one of
	-- these per sample, and there are tens of thousands of samples.
	local px, py = 0, 0
	local d1, d2, i1, i2 = math.huge, math.huge, 0, 0
	local function consider(i)
		local dx, dy = px - sx[i], py - sy[i]
		local d = dx * dx + dy * dy
		if d < d1 then
			d2, i2 = d1, i1
			d1, i1 = d, i
		elseif d < d2 then
			d2, i2 = d, i
		end
	end

	local y = 0
	while y <= ctx.h do
		local x = 0
		while x <= ctx.w do
			px, py = x, y
			d1, d2, i1, i2 = math.huge, math.huge, 0, 0
			local cx = math.min(cols - 1, math.floor(x / cell_w))
			local cy = math.min(rows - 1, math.floor(y / cell_h))
			for by = math.max(0, cy - 2), math.min(rows - 1, cy + 2) do
				for bx = math.max(0, cx - 2), math.min(cols - 1, cx + 2) do
					local b = buckets[by * cols + bx]
					if b then
						for k = 1, #b do consider(b[k]) end
					end
				end
			end
			if i2 == 0 then -- empty neighbourhood: pay for the full scan
				for i = 1, n do consider(i) end
			end
			if i2 > 0 and math.sqrt(d2) - math.sqrt(d1) < thickness then
				-- the boundary runs perpendicular to site1->site2, and the
				-- brush is painted along its own vertical axis, so turning it
				-- by that angle lays it on the boundary
				local a = math.atan2(sy[i2] - sy[i1], sx[i2] - sx[i1])
				love.graphics.draw(img, x, y, a, 1, 1, ox, oy)
			end
			x = x + thickness
		end
		y = y + thickness
	end
end

-- INFERRED. A track walked across the field: `bm1`/`bm2`/`bm3` cycle as it
-- steps, `step_length` is the stride, `stride_width` offsets alternate feet to
-- either side of the line (0 for the roads, which are one wide segment per
-- step; 15 for the mech, which has two feet), and `undulation_factor` bends
-- the heading a little at each step so the track wanders instead of ruling a
-- straight line. The road art runs left-to-right within its frame, so a
-- segment is turned by the heading itself.
--
-- One track per node, entering off one edge and crossing the whole field.
function ops.FootPrints(ctx, op)
	local sprites = {}
	for _, key in ipairs({ "bm1", "bm2", "bm3" }) do
		local img = op[key] and assets.image(op[key])
		if img then sprites[#sprites + 1] = img end
	end
	if #sprites == 0 then return end

	local step = math.max(4, num(op.step_length, 60))
	local scale = num(op.scale, 1)
	local stride = num(op.stride_width, 0)
	local undulation = num(op.undulation_factor, 0)
	local additive = op.blend_mode == "NX_BLEND_ADDITIVE"

	if additive then love.graphics.setBlendMode("add") end
	love.graphics.setColor(1, 1, 1, num(op.alpha, 1))

	local angle = ctx.rng:random() * math.pi * 2
	-- start well outside, on the far side of a point in the field, so the
	-- track crosses it rather than beginning in the middle of the ground
	local x = ctx.rng:random() * ctx.w - math.cos(angle) * ctx.w
	local y = ctx.rng:random() * ctx.h - math.sin(angle) * ctx.h
	local margin = 200
	local steps = math.ceil((ctx.w + ctx.h) * 2 / step) + 4

	for i = 1, steps do
		x = x + math.cos(angle) * step
		y = y + math.sin(angle) * step
		angle = angle + (ctx.rng:random() - 0.5) * 2 * undulation
		if x > -margin and x < ctx.w + margin
			and y > -margin and y < ctx.h + margin then
			local side = (i % 2 == 0) and 1 or -1
			local img = sprites[(i % #sprites) + 1]
			love.graphics.draw(img,
				x + math.cos(angle + math.pi / 2) * stride * side,
				y + math.sin(angle + math.pi / 2) * stride * side,
				angle, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
		end
	end

	if additive then love.graphics.setBlendMode("alpha") end
end

-- ---------------------------------------------------------------- baking

local run_ops -- forward declaration: DrawTerrain re-enters it

-- Lay another chapter's ground down first, optionally as it looks at a given
-- quest -- the alien chapters build on the ones they invade.
function ops.DrawTerrain(ctx, op)
	if ctx.depth >= 3 then return end -- authored data has no cycles; be sure
	local nested = data.terrains[op.id]
	if not nested then return end
	run_ops(nested, {
		w = ctx.w,
		h = ctx.h,
		rng = ctx.rng,
		quest = math.floor(num(op.quest_number, ctx.quest)),
		depth = ctx.depth + 1,
	})
end

--- Apply one op list onto whatever canvas is bound.
function run_ops(list, ctx)
	for _, op in ipairs(list) do
		local required = num(op.quest_number_required)
		if not required or ctx.quest >= required then
			-- SetSeeds is not a drawing op: it chooses which of the chapter's
			-- authored seeds this quest bakes from, so it reseeds in place.
			if op.action == "SetSeeds" then
				local seeds = {}
				for s in tostring(op.seeds or ""):gmatch("[^,%s]+") do
					seeds[#seeds + 1] = tonumber(s)
				end
				if #seeds > 0 then
					local i = (math.max(1, ctx.quest) - 1) % #seeds + 1
					ctx.rng:setSeed(seeds[i])
				end
			else
				local fn = ops[op.action or "DrawSplashes"]
				if fn then fn(ctx, op) end
			end
		end
	end
end

local function evict()
	while #cache_order > CACHE_MAX do
		local key = table.remove(cache_order, 1)
		local canvas = cache[key]
		cache[key] = nil
		if canvas then canvas:release() end
	end
end

--- The clean ground for one chapter at one quest number, baked or cached.
local function clean(chapter_id, quest, w, h, density)
	local key = ("%s#%d@%.2f"):format(chapter_id, quest, density)
	if cache[key] then return cache[key] end

	local started = love.timer.getTime()
	local canvas = love.graphics.newCanvas(w, h, { dpiscale = density })
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0.1, 0.1, 0.08, 1)
	run_ops(data.terrains[chapter_id] or data.terrains.CHAPTER_1 or {}, {
		w = w,
		h = h,
		rng = love.math.newRandomGenerator(DEFAULT_SEED),
		quest = quest,
		depth = 0,
	})
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setCanvas()

	cache[key] = canvas
	cache_order[#cache_order + 1] = key
	evict()
	print(("[terrain] baked %s quest %d at %.2fx in %.0f ms"):format(
		chapter_id, quest, density, (love.timer.getTime() - started) * 1000))
	return canvas
end

--- A session's own ground: a copy of the clean bake, because the game draws
-- corpses and body parts into what it gets back.
--
-- `density` is device pixels per reference unit. The terrain art itself only
-- ships at base resolution, so this buys nothing for the ground -- but the
-- creatures baked into it during play come from the 1080p set, and at density
-- 1 a corpse visibly softened the moment it stopped being a sprite.
function terrain.bake(chapter_id, quest, w, h, density)
	density = math.min(MAX_DENSITY, math.max(1, density or 1))
	quest = math.max(0, math.floor(quest or 0))

	local source = clean(chapter_id, quest, w, h, density)
	local session = love.graphics.newCanvas(w, h, { dpiscale = density })
	love.graphics.setCanvas(session)
	love.graphics.clear(0, 0, 0, 1)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(source, 0, 0)
	love.graphics.setCanvas()
	return session
end

return terrain

-- Post-processing on the finished frame.
--
-- Everything the game draws lands on one 960x640 reference canvas (see
-- src/engine/init.lua); this is what happens to that canvas on its way to the
-- window. Three things live here:
--
--   * grade   -- tint, saturation, vignette and a full-screen flash, which is
--                how a game state that changes the whole world (frozen field,
--                slowed time, a nuke going off) is shown without touching a
--                single sprite
--   * bloom   -- the bright parts bleed. The additive effects (muzzle flash,
--                explosions, plasma) are drawn to be bright, and this is what
--                makes them read as light rather than as pale sprites
--   * haze    -- a heat shimmer that bends the frame around a few points, for
--                explosions and the flamethrower
--
-- The original engine had no post-processing at all -- its two shaders are a
-- textured quad and an untextured one (assets/shaders/*.xml) -- so none of
-- this is reconstruction. It is the one place this port deliberately goes
-- past what the 2014 build did, because the canvas is already there and the
-- effects it feeds were being faked with flat quads.

local postfx = {}

-- Up to this many shimmer sources at once; the rest of a busy frame goes
-- unhazed, which nobody can see when four explosions are already bending it.
local MAX_HAZE = 4

-- Bloom works on a quarter-size copy. Big enough to catch a muzzle flash,
-- small enough that the blur is cheap and wide.
local BLOOM_DIV = 4

local shader, bloom_extract, bloom_blur
local bloom_a, bloom_b
local bloom_w, bloom_h = 0, 0

-- Live grade. Anything that wants the frame to change sets these for a frame
-- (postfx.set) and they decay back to neutral on their own if nobody does.
local grade = {
	tint = { 1, 1, 1 },
	tint_amount = 0,
	saturation = 1,
	vignette = 0,
	flash = 0,
	flash_color = { 1, 1, 1 },
	bloom = 0,
}

local haze = {} -- {x, y, radius, strength} in reference units
local clock = 0

-- The frame shader. `uv` is displaced first (haze), then the sample is graded:
-- saturation, tint, vignette, flash -- in that order, because a flash is the
-- last thing that happens to a frame and must not be desaturated by a grade
-- that was meant for the world under it.
local GRADE_SOURCE = [[
extern vec3 tint;
extern number tint_amount;
extern number saturation;
extern number vignette;
extern number flash;
extern vec3 flash_color;
extern vec4 haze[4];
extern number clock;
extern vec2 aspect;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
	vec2 uv = tc;
	for (int i = 0; i < 4; i++) {
		if (haze[i].w > 0.0) {
			vec2 d = (uv - haze[i].xy) * aspect;
			number r = length(d);
			if (r < haze[i].z && r > 0.0001) {
				// a ring travelling outward, fading to nothing at the edge
				number fall = 1.0 - r / haze[i].z;
				number wave = sin(r * 90.0 - clock * 14.0);
				uv += (d / r) * wave * 0.006 * fall * fall * haze[i].w / aspect;
			}
		}
	}

	vec4 c = Texel(tex, uv) * color;

	number lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	c.rgb = mix(vec3(lum), c.rgb, saturation);
	// Tint towards the colour at this pixel's brightness, not towards the
	// pixel times the colour: multiplying a brown field by a cold blue only
	// darkens it, because there is no blue in the ground to bring up. Grading
	// through luminance is what actually turns a frozen field cold.
	c.rgb = mix(c.rgb, vec3(lum) * tint, tint_amount);

	number d = distance(tc, vec2(0.5)) * 1.41421;
	c.rgb *= 1.0 - vignette * d * d;

	c.rgb = mix(c.rgb, flash_color, flash);
	return c;
}
]]

-- Bright pass: keep what is above the knee and drop the rest to black, so the
-- blur below spreads light and not the whole picture.
local EXTRACT_SOURCE = [[
extern number threshold;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
	vec4 c = Texel(tex, tc);
	number lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	number k = max(0.0, lum - threshold) / max(0.0001, 1.0 - threshold);
	return vec4(c.rgb * k, 1.0);
}
]]

-- One axis of a separable gaussian; run twice with `direction` swapped.
local BLUR_SOURCE = [[
extern vec2 direction; // texels to step, already divided by the target size

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
	vec4 sum = Texel(tex, tc) * 0.227027;
	sum += (Texel(tex, tc + direction * 1.384615)
		+ Texel(tex, tc - direction * 1.384615)) * 0.316216;
	sum += (Texel(tex, tc + direction * 3.230769)
		+ Texel(tex, tc - direction * 3.230769)) * 0.070270;
	return vec4(sum.rgb, 1.0);
}
]]

local function ensure_shaders()
	if shader then return end
	shader = love.graphics.newShader(GRADE_SOURCE)
	bloom_extract = love.graphics.newShader(EXTRACT_SOURCE)
	bloom_blur = love.graphics.newShader(BLUR_SOURCE)
end

local function ensure_bloom_targets(canvas)
	local pw, ph = canvas:getPixelDimensions()
	local w = math.max(1, math.floor(pw / BLOOM_DIV))
	local h = math.max(1, math.floor(ph / BLOOM_DIV))
	if bloom_a and bloom_w == w and bloom_h == h then return end
	if bloom_a then bloom_a:release() end
	if bloom_b then bloom_b:release() end
	bloom_w, bloom_h = w, h
	bloom_a = love.graphics.newCanvas(w, h)
	bloom_b = love.graphics.newCanvas(w, h)
	bloom_a:setFilter("linear", "linear")
	bloom_b:setFilter("linear", "linear")
end

--- Set this frame's grade. Any field left out goes back to neutral, so a
-- caller states what it wants rather than having to undo what it set last.
function postfx.set(t)
	t = t or {}
	grade.tint = t.tint or { 1, 1, 1 }
	grade.tint_amount = t.tint_amount or 0
	grade.saturation = t.saturation or 1
	grade.vignette = t.vignette or 0
	grade.flash = t.flash or 0
	grade.flash_color = t.flash_color or { 1, 1, 1 }
	grade.bloom = t.bloom or 0
end

--- Bend the frame around a point for this frame. Reference coordinates, so a
-- world-space caller converts through its own camera first.
function postfx.add_haze(x, y, radius, strength)
	if #haze >= MAX_HAZE then return end
	haze[#haze + 1] = { x, y, radius, strength }
end

function postfx.update(dt)
	clock = clock + dt
end

--- True when the frame needs anything done to it at all. A menu frame does
-- not, and then the blit stays the plain one-to-one copy it has always been.
local function idle()
	return grade.tint_amount <= 0 and grade.saturation == 1
		and grade.vignette <= 0 and grade.flash <= 0
		and grade.bloom <= 0 and #haze == 0
end

--- Draw `canvas` to the window, doing whatever this frame asked for. Called
-- by the engine in place of love.graphics.draw(canvas, ...).
function postfx.draw(canvas, x, y, scale, width, height)
	if idle() then
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(canvas, x, y, 0, scale, scale)
		return
	end

	ensure_shaders()

	-- 1. bloom, built before the grade so the glow comes off the world's own
	-- brightness rather than off a flash that is about to wash everything out
	if grade.bloom > 0 then
		ensure_bloom_targets(canvas)
		love.graphics.setBlendMode("alpha", "premultiplied")
		love.graphics.setColor(1, 1, 1, 1)

		love.graphics.setCanvas(bloom_a)
		love.graphics.clear(0, 0, 0, 1)
		love.graphics.setShader(bloom_extract)
		bloom_extract:send("threshold", 0.72)
		love.graphics.draw(canvas, 0, 0, 0,
			bloom_w / canvas:getPixelWidth(), bloom_h / canvas:getPixelHeight())

		love.graphics.setShader(bloom_blur)
		love.graphics.setCanvas(bloom_b)
		love.graphics.clear(0, 0, 0, 1)
		bloom_blur:send("direction", { 1 / bloom_w, 0 })
		love.graphics.draw(bloom_a, 0, 0)

		love.graphics.setCanvas(bloom_a)
		love.graphics.clear(0, 0, 0, 1)
		bloom_blur:send("direction", { 0, 1 / bloom_h })
		love.graphics.draw(bloom_b, 0, 0)

		love.graphics.setCanvas()
		love.graphics.setShader()
		love.graphics.setBlendMode("alpha")
	end

	-- 2. the graded frame
	love.graphics.setShader(shader)
	shader:send("tint", grade.tint)
	shader:send("tint_amount", grade.tint_amount)
	shader:send("saturation", grade.saturation)
	shader:send("vignette", grade.vignette)
	shader:send("flash", math.min(1, grade.flash))
	shader:send("flash_color", grade.flash_color)
	shader:send("clock", clock)
	-- the canvas is wider than it is tall, so a radius has to be measured in
	-- one of the two or the shimmer comes out as an ellipse
	shader:send("aspect", { 1, height / width })
	-- an array uniform goes in one call, one table per element: sending
	-- "haze[0]" by name is not a thing LÖVE exposes
	local packed = {}
	for i = 1, MAX_HAZE do
		local h = haze[i]
		packed[i] = h
			and { h[1] / width, h[2] / height, h[3] / width, h[4] }
			or { 0, 0, 0, 0 }
	end
	shader:send("haze", packed[1], packed[2], packed[3], packed[4])
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(canvas, x, y, 0, scale, scale)
	love.graphics.setShader()

	-- 3. the glow on top, additively -- it is light, not paint
	if grade.bloom > 0 and bloom_a then
		love.graphics.setBlendMode("add", "premultiplied")
		love.graphics.setColor(grade.bloom, grade.bloom, grade.bloom, 1)
		love.graphics.draw(bloom_a, x, y, 0,
			scale * canvas:getPixelWidth() / bloom_w,
			scale * canvas:getPixelHeight() / bloom_h)
		love.graphics.setBlendMode("alpha")
		love.graphics.setColor(1, 1, 1, 1)
	end
end

--- Clear the per-frame state. The engine calls this after the blit, so a
-- caller that stops asking for a grade stops getting one.
function postfx.frame_done()
	postfx.set(nil)
	for i = #haze, 1, -1 do haze[i] = nil end
end

return postfx

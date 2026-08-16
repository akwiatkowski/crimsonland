-- Text rendering on the original engine's bitmap fonts (.mft, decoded by
-- src/engine/mft.lua). Glyphs are white with coverage in alpha, so tinting is
-- just love.graphics.setColor.
--
-- If a font fails to decode we fall back to LÖVE's built-in vector font at the
-- .mft's nominal line height — the port stays playable on a broken asset.
--
-- Text supports the engine's inline color markup: "|#rrggbb|" starts a
-- colored span.

local assets = require("src.engine.assets")
local mft = require("src.engine.mft")

local font = {}

local SIZE_FALLBACKS = {
	["fonts/small.mft"] = 16,
	["fonts/medium.mft"] = 24,
	["fonts/ammo.mft"] = 32,
}

local font_cache = {}
local render_scale = 1

--- Walk a string as LATIN-1 codepoints, which is what the .mft tables index by.
-- Lua sources here are UTF-8, so a "·" arrives as two bytes and would otherwise
-- print as "Â·"; two-byte sequences that land inside LATIN-1 are folded back,
-- everything else is taken as a raw byte (the original pak scripts are LATIN-1).
local function codepoints(text)
	local out, i, n = {}, 1, #text
	while i <= n do
		local b = text:byte(i)
		local b2 = text:byte(i + 1)
		if b >= 0xC2 and b <= 0xC3 and b2 and b2 >= 0x80 and b2 <= 0xBF then
			out[#out + 1] = (b - 0xC0) * 64 + (b2 - 0x80)
			i = i + 2
		else
			out[#out + 1] = b
			i = i + 1
		end
	end
	return out
end

--- Density of the render target (device pixels per reference unit). Only the
-- fallback vector fonts care — bitmap glyphs come from the 1080p pak instead.
function font.set_render_scale(scale)
	if math.abs(scale - render_scale) < 0.01 then return end
	render_scale = scale
	for path, f in pairs(font_cache) do
		if f.fallback then font_cache[path] = nil end
	end
end

local function fallback_font(path)
	local size = assets.font_size(path) or SIZE_FALLBACKS[path] or 16
	local f = love.graphics.newFont(math.max(8, math.floor(size)), "normal", render_scale)
	return { fallback = f, line_height = f:getHeight(), getHeight = function(self)
		return self.line_height
	end }
end

function font.get(path)
	path = path or "fonts/small.mft"
	local f = font_cache[path]
	if f then return f end
	f = mft.load(path) or fallback_font(path)
	font_cache[path] = f
	return f
end

--- Width of `text` in reference units, ignoring color markup.
local function advance_of(f, text)
	if f.fallback then return f.fallback:getWidth(text) end
	local codes = codepoints(text)
	local w = 0
	for i = 1, #codes do
		local g = f.glyphs[codes[i]]
		if g then
			w = w + g.advance + f:kerning(codes[i], codes[i + 1])
		end
	end
	return w / f.density
end

local function strip_markup(text)
	return (text:gsub("|#%x%x%x%x%x%x|", ""))
end

function font.measure(path, text)
	local f = font.get(path)
	return advance_of(f, strip_markup(text)), f.line_height
end

--- Draw one markup-free run at x,y (y = top of the line box). Returns its width.
local function draw_run(f, text, x, y)
	if f.fallback then
		love.graphics.setFont(f.fallback)
		love.graphics.print(text, x, y)
		return f.fallback:getWidth(text)
	end
	local d = f.density
	local codes = codepoints(text)
	local pen = 0
	for i = 1, #codes do
		local g = f.glyphs[codes[i]]
		if g then
			if g.quad then
				-- quads address texels, so the atlas density comes out of the
				-- scale; y_offset places the glyph inside the line box
				love.graphics.draw(f.image, g.quad,
					x + pen / d, y + g.y_offset / d, 0, 1 / d, 1 / d)
			end
			pen = pen + g.advance + f:kerning(codes[i], codes[i + 1])
		end
	end
	return pen / d
end

--- Draw text with |#rrggbb| markup support. Returns width drawn.
function font.draw(path, text, x, y, color)
	local f = font.get(path)
	color = color or { 1, 1, 1, 1 }
	local cx = x
	local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
	local alpha = color[4] or 1

	local pos = 1
	while pos <= #text do
		local s, e, hex = text:find("|#(%x%x%x%x%x%x)|", pos)
		if s == pos then
			-- markup at cursor: switch color, no text
			r = tonumber(hex:sub(1, 2), 16) / 255
			g = tonumber(hex:sub(3, 4), 16) / 255
			b = tonumber(hex:sub(5, 6), 16) / 255
			pos = e + 1
		else
			local chunk = s and text:sub(pos, s - 1) or text:sub(pos)
			love.graphics.setColor(r, g, b, alpha)
			cx = cx + draw_run(f, chunk, cx, y)
			pos = s or #text + 1
		end
	end
	return cx - x
end

return font

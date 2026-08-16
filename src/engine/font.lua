-- Text rendering. The original uses a custom bitmap-font format
-- ("MEG_Font_v6", .mft) which is not yet decoded — we approximate with
-- LÖVE's built-in font at the .mft's nominal line height.
--
-- Text supports the engine's inline color markup: "|#rrggbb|" starts a
-- colored span.

local assets = require("src.engine.assets")

local font = {}

local SIZE_FALLBACKS = {
	["fonts/small.mft"] = 16,
	["fonts/medium.mft"] = 24,
	["fonts/ammo.mft"] = 32,
}

local font_cache = {}
local render_scale = 1

--- Rasterize glyphs for a render target of this density (device pixels per
-- reference unit). LÖVE keeps font metrics in reference units regardless, so
-- callers and layouts never see the difference — only the texture gets sharper.
function font.set_render_scale(scale)
	if math.abs(scale - render_scale) < 0.01 then return end
	render_scale = scale
	font_cache = {}
end

function font.get(path)
	path = path or "fonts/small.mft"
	if font_cache[path] then return font_cache[path] end
	local size = assets.font_size(path) or SIZE_FALLBACKS[path] or 16
	-- header value is the line height; glyph em is a bit smaller
	local f = love.graphics.newFont(math.max(8, math.floor(size * 1.0)),
		"normal", render_scale)
	font_cache[path] = f
	return f
end

function font.measure(path, text)
	local f = font.get(path)
	-- strip markup for width purposes
	local clean = text:gsub("|#%x%x%x%x%x%x|", "")
	return f:getWidth(clean), f:getHeight()
end

--- Draw text with |#rrggbb| markup support. Returns width drawn.
function font.draw(path, text, x, y, color)
	local f = font.get(path)
	love.graphics.setFont(f)
	color = color or { 1, 1, 1, 1 }
	local cx = x
	local base_r, base_g, base_b = color[1] or 1, color[2] or 1, color[3] or 1
	local alpha = color[4] or 1

	local pos = 1
	while pos <= #text do
		local s, e, hex = text:find("|#(%x%x%x%x%x%x)|", pos)
		local chunk, next_color
		if s == pos then
			-- markup at cursor: switch color, no text
			base_r = tonumber(hex:sub(1, 2), 16) / 255
			base_g = tonumber(hex:sub(3, 4), 16) / 255
			base_b = tonumber(hex:sub(5, 6), 16) / 255
			pos = e + 1
		else
			if s then
				chunk = text:sub(pos, s - 1)
			else
				chunk = text:sub(pos)
			end
			love.graphics.setColor(base_r, base_g, base_b, alpha)
			love.graphics.print(chunk, cx, y)
			cx = cx + f:getWidth(chunk)
			pos = s and s or #text + 1
		end
	end
	return cx - x
end

return font

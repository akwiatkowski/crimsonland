-- MEG_Font_v6 (.mft) decoder — the original engine's bitmap font format.
--
-- Reverse-engineered from the three fonts in the pak (small/medium/ammo); the
-- parser below consumes each file to its exact last byte, which is what proves
-- the layout. Everything is little-endian:
--
--   "MEG_Font_v6\0"     magic (12 bytes)
--   encoding\0          C-string, always "LATIN-1" here
--   u32 line_height     nominal line height in pixels
--   u32 ascent, u32 cell_height   (both 18 for the 16px font, 40 for the 38px)
--   u32 count           glyph slots, always 256 (LATIN-1)
--   count x glyph record, in codepoint order:
--     u32 codepoint     (0 in fonts that carry no encoding table, e.g. ammo)
--     u32 y_offset      top of the glyph box, from the top of the line
--     i16 advance       pen movement, includes the art's padding
--     u8  flag          always 1
--     i8  kern[256]     kerning against the *next* codepoint, mostly -1..-5
--     u16 width, u16 height
--     RGBA8 width*height   white pixels, coverage in alpha; absent when w*h = 0
--
-- Glyphs are pasted into one atlas at load time so a string costs one texture.

local assets = require("src.engine.assets")

local mft = {}

local MAGIC = "MEG_Font_v6\0"
local HEADER_FIELDS = 16 -- 4 u32 after the encoding string
local GLYPH_FIXED = 271 -- record bytes before the pixel payload
local KERN_OFFSET = 11 -- kerning row, within the record
local ATLAS_WIDTH = 1024
local PAD = 1 -- transparent gutter, so filtering can't bleed neighbours

local cache = {}

-- little-endian readers; `at` is a 0-based offset like the format spec
local function u16(d, at)
	local a, b = d:byte(at + 1, at + 2)
	return a + b * 256
end
local function u32(d, at)
	local a, b, c, e = d:byte(at + 1, at + 4)
	return a + b * 256 + c * 65536 + e * 16777216
end
local function i16(d, at)
	local v = u16(d, at)
	return v >= 32768 and v - 65536 or v
end

--- Read every glyph record. Returns the list plus the offset one past the end,
-- which the caller compares against the file size as a format sanity check.
local function parse_glyphs(data, count, at)
	local glyphs = {}
	for i = 0, count - 1 do
		local w, h = u16(data, at + 267), u16(data, at + 269)
		glyphs[i] = {
			y_offset = u32(data, at + 4),
			advance = i16(data, at + 8),
			-- kept as raw bytes: 256 entries x 256 glyphs is a lot of table
			kern = data:sub(at + KERN_OFFSET + 1, at + KERN_OFFSET + 256),
			w = w,
			h = h,
			pixels = at + GLYPH_FIXED,
		}
		at = at + GLYPH_FIXED + w * h * 4
	end
	return glyphs, at
end

--- Pack the glyph bitmaps into a single atlas (shelf rows) and build quads.
local function build_atlas(data, glyphs)
	local x, y, row_h = PAD, PAD, 0
	for _, g in pairs(glyphs) do
		if g.w > 0 then
			if x + g.w + PAD > ATLAS_WIDTH then
				x, y, row_h = PAD, y + row_h + PAD, 0
			end
			g.ax, g.ay = x, y
			x = x + g.w + PAD
			if g.h > row_h then row_h = g.h end
		end
	end
	local height = y + row_h + PAD

	local atlas = love.image.newImageData(ATLAS_WIDTH, height)
	for _, g in pairs(glyphs) do
		if g.w > 0 then
			local raw = data:sub(g.pixels + 1, g.pixels + g.w * g.h * 4)
			local id = love.image.newImageData(g.w, g.h, "rgba8", raw)
			atlas:paste(id, g.ax, g.ay, 0, 0, g.w, g.h)
			g.quad = love.graphics.newQuad(g.ax, g.ay, g.w, g.h, ATLAS_WIDTH, height)
		end
		g.pixels = nil
	end
	return love.graphics.newImage(atlas)
end

local Font = {}
Font.__index = Font

--- Line height in reference units — the shape nx.NX_GetFontHeight expects.
function Font:getHeight()
	return self.line_height
end

--- Kerning between `code` and the glyph that follows it, in font pixels.
function Font:kerning(code, next_code)
	local g = self.glyphs[code]
	if not g or not next_code then return 0 end
	local v = g.kern:byte(next_code + 1)
	if not v then return 0 end
	return v >= 128 and v - 256 or v
end

--- Load fonts/<name>.mft. Returns nil when the file is missing or not a
-- MEG_Font_v6, so callers can fall back to a system font.
function mft.load(path)
	if cache[path] ~= nil then return cache[path] or nil end

	local full, density = assets.resolve(path)
	local data = full and love.filesystem.read(full)
	if not data or data:sub(1, #MAGIC) ~= MAGIC then
		cache[path] = false
		return nil
	end

	-- find() is 1-based, so enc_end is already the 0-based offset of what follows
	local enc_end = data:find("\0", 13, true)
	local line_height = u32(data, enc_end)
	local count = u32(data, enc_end + 12)
	local glyphs, consumed = parse_glyphs(data, count, enc_end + HEADER_FIELDS)
	if consumed ~= #data then
		print(("[mft] %s: parsed %d of %d bytes, ignoring"):format(path, consumed, #data))
		cache[path] = false
		return nil
	end

	local font = setmetatable({
		image = build_atlas(data, glyphs),
		glyphs = glyphs,
		-- the 1080p pak ships the same fonts authored larger; dividing every
		-- metric by that density keeps callers in reference units
		density = density,
		line_height = line_height / density,
	}, Font)
	cache[path] = font
	return font
end

return mft

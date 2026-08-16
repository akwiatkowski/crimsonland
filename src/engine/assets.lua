-- Asset loading with caching. Asset roots:
--   assets/         — bitmaps, fonts, scripts, XML (base resolution)
--   assets-1080p/   — hi-res variants of the bitmaps (see HIRES_SCALE)
--   assets-sfx/     — sound effects (sfx/*.ogg)
--   assets-music/   — music (music/*.ogg)
-- Logical names used by scripts map directly onto these roots.

local assets = {}

local paths = require("src.engine.paths")

local ROOT_MAIN = paths.ASSETS
local ROOT_1080P = paths.ASSETS_1080P
local ROOT_SFX = paths.SFX
local ROOT_MUSIC = paths.MUSIC

-- The 1080p pak is the same art authored for a 1080-tall screen: every bitmap
-- is exactly 1080/640 = 1.6875x its base-resolution twin (measured across the
-- set). LÖVE's per-image dpiscale makes that a drop-in replacement — getWidth()
-- and love.graphics.draw() keep reporting/using *reference* units, only the
-- texture underneath is denser. So no call site needs to know which set is
-- loaded. Quads are the one exception (they address texels and ignore
-- dpiscale) — see assets.quad().
local HIRES_SCALE = 1080 / 640

-- Set by the engine once the render scale is known (src/engine/init.lua).
-- Below 1x reference the hi-res set only costs VRAM, so it stays off.
assets.hires = false

local image_cache = {}
local sound_cache = {}
local missing_logged = {}

local function log_missing(kind, path)
	if not missing_logged[path] then
		missing_logged[path] = true
		print(("[assets] missing %s: %s"):format(kind, path))
	end
end

function assets.exists(path)
	return love.filesystem.getInfo(ROOT_MAIN .. "/" .. path) ~= nil
end

--- Resolve a logical path to a real file plus the pixel density of the variant
-- picked (1 = base art, HIRES_SCALE = 1080p twin). The 1080p pak only carries
-- part of the tree — no terrains/, fxs/, gems/ — so callers always get the base
-- file as fallback. Returns nil when neither set has the file.
function assets.resolve(path)
	if assets.hires then
		local hi = ROOT_1080P .. "/" .. path
		if love.filesystem.getInfo(hi) then return hi, HIRES_SCALE end
	end
	local base = ROOT_MAIN .. "/" .. path
	if love.filesystem.getInfo(base) then return base, 1 end
	return nil
end

--- Load (and cache) a bitmap by logical path, e.g. "ui/gfx/panel-medium.png".
-- The engine magic value "!NONE" means "no bitmap".
-- Prefers the hi-res twin when the game renders above 1x; the returned image
-- measures and draws in reference units either way.
function assets.image(path)
	if path == nil or path == "" or path == "!NONE" then return nil end
	if image_cache[path] then return image_cache[path] end

	local full, density = assets.resolve(path)
	if not full then
		log_missing("image", path)
		image_cache[path] = false
		return nil
	end
	local ok, img = pcall(love.graphics.newImage, full, { dpiscale = density })
	if not ok then
		log_missing("image(unreadable)", path)
		image_cache[path] = false
		return nil
	end
	image_cache[path] = img
	return img
end

--- Quad over a source rect given in *reference* units, plus the draw scale
-- that maps it back to reference units. Quads address raw texels and are drawn
-- at their literal pixel size, so unlike plain draws they have to be told
-- about the image's density:
--   local q, s = assets.quad(img, 0, 0, w, h)
--   love.graphics.draw(img, q, x, y, 0, s, s)
function assets.quad(img, x, y, w, h)
	local d = img:getDPIScale()
	return love.graphics.newQuad(x * d, y * d, w * d, h * d,
		img:getPixelWidth(), img:getPixelHeight()), 1 / d
end

--- Preload only (original engine's NX_LoadBitmap semantics).
function assets.preload_image(path)
	assets.image(path)
end

--- Load a sound by logical name, e.g. "sfx/ui_panel_click" or
-- "music/crimson_theme" (extensionless). kind: "sfx" | "music".
function assets.sound(name, kind)
	if sound_cache[name] then return sound_cache[name] end
	local root = (kind == "music") and ROOT_MUSIC or ROOT_SFX
	local full = root .. "/" .. name .. ".ogg"
	if not love.filesystem.getInfo(full) then
		-- some sounds may live in the main pak
		full = ROOT_MAIN .. "/" .. name .. ".ogg"
		if not love.filesystem.getInfo(full) then
			log_missing("sound", name)
			sound_cache[name] = false
			return nil
		end
	end
	local stype = (kind == "music") and "stream" or "static"
	local ok, src = pcall(love.audio.newSource, full, stype)
	if not ok then
		log_missing("sound(unreadable)", name)
		sound_cache[name] = false
		return nil
	end
	sound_cache[name] = src
	return src
end

--- Extract the nominal pixel size from a MEG_Font_v6 .mft header
-- (first u32 after magic+encoding appears to be the line height).
function assets.font_size(path)
	local full = ROOT_MAIN .. "/" .. path
	local data = love.filesystem.read(full)
	if not data then return nil end
	-- layout: "MEG_Font_v6\0" (12) + encoding C-string + u32 line_height
	local pos = 13
	local zero = data:find("\0", pos, true)
	if not zero then return nil end
	pos = zero + 1
	local b1, b2, b3, b4 = data:byte(pos, pos + 3)
	if not b4 then return nil end
	return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

return assets

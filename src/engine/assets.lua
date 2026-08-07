-- Asset loading with caching. Asset roots:
--   assets/         — bitmaps, fonts, scripts, XML (base resolution)
--   assets-sfx/     — sound effects (sfx/*.ogg)
--   assets-music/   — music (music/*.ogg)
-- Logical names used by scripts map directly onto these roots.

local assets = {}

local paths = require("src.engine.paths")

local ROOT_MAIN = paths.ASSETS
local ROOT_SFX = paths.SFX
local ROOT_MUSIC = paths.MUSIC

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

--- Load (and cache) a bitmap by logical path, e.g. "ui/gfx/panel-medium.png".
-- The engine magic value "!NONE" means "no bitmap".
function assets.image(path)
	if path == nil or path == "" or path == "!NONE" then return nil end
	if image_cache[path] then return image_cache[path] end
	local full = ROOT_MAIN .. "/" .. path
	if not love.filesystem.getInfo(full) then
		log_missing("image", path)
		image_cache[path] = false
		return nil
	end
	local ok, img = pcall(love.graphics.newImage, full)
	if not ok then
		log_missing("image(unreadable)", path)
		image_cache[path] = false
		return nil
	end
	image_cache[path] = img
	return img
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

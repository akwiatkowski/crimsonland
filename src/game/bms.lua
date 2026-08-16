-- NX_Bm_Seq_v1 loader: 10tons bitmap-sequence (animation) format.
--
-- Layout (little-endian):
--   "NX_Bm_Seq_v1\0"  magic (13 bytes)
--   u32               nominal frame size (e.g. 64)
--   "RGBAATLAS\0"     pixel format tag
--   (zero padding to 4-byte alignment)
--   u32 frame_w, u32 frame_h
--   N x 32-byte records: u32 index, f32 pivot_x,
--       f32 left, f32 top, f32 right, f32 bottom  (UVs normalized to atlas),
--       f32 unused, f32 unused
--   PNG atlas (all frames packed, standard PNG stream to EOF)

local assets = require("src.engine.assets")

local bms = {}

local cache = {}

--- Load a .bms file. Returns { image=Image, frames={ {u,v,w,h}, ... } (pixels),
--   quads={Quad,...}, count=N } or nil on failure.
function bms.load(path)
	if cache[path] ~= nil then
		return cache[path] or nil
	end
	-- the 1080p pak carries every .bms; its atlases are denser by `density`,
	-- which bms.draw divides out so callers keep working in reference units
	local full, density = assets.resolve(path)
	local data = full and love.filesystem.read(full)
	if not data then
		cache[path] = false
		return nil
	end
	if data:sub(1, 13) ~= "NX_Bm_Seq_v1\0" then
		cache[path] = false
		return nil
	end

	local png_off = data:find("\137PNG", 1, true)
	if not png_off then
		cache[path] = false
		return nil
	end

	-- locate frame table: after the RGBAATLAS tag + padding, two u32 dims
	local tag = data:find("RGBAATLAS\0", 1, true)
	local p = tag + 10
	while data:byte(p) == 0 do p = p + 1 end
	-- p at frame_w u32
	local function u32(at)
		local b1, b2, b3, b4 = data:byte(at, at + 3)
		return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
	end
	-- string.unpack is Lua 5.3+; LuaJIT needs LÖVE's own unpacker
	local function f32(at)
		local ok, v = pcall(love.data.unpack, "<f", data, at)
		return ok and v or 0
	end
	local fw = u32(p)
	local fh = u32(p + 4)
	p = p + 8
	local n = math.floor((png_off - p) / 32)

	-- atlas
	local png_data = data:sub(png_off)
	local filedata = love.filesystem.newFileData(png_data, path .. ".png")
	local ok, img = pcall(love.graphics.newImage, filedata)
	if not ok then
		cache[path] = false
		return nil
	end
	local aw, ah = img:getWidth(), img:getHeight()

	local frames = {}
	local quads = {}
	for i = 0, n - 1 do
		local base = p + i * 32
		local left = f32(base + 8) * aw
		local top = f32(base + 12) * ah
		local right = f32(base + 16) * aw
		local bottom = f32(base + 20) * ah
		local w = math.max(1, right - left)
		local h = math.max(1, bottom - top)
		frames[i + 1] = { u = left, v = top, w = w, h = h }
		quads[i + 1] = love.graphics.newQuad(left, top, w, h, aw, ah)
	end

	local seq = {
		image = img,
		frames = frames,
		quads = quads,
		count = n,
		frame_w = fw,
		frame_h = fh,
		density = density,
	}
	cache[path] = seq
	return seq
end

--- Draw frame `idx` (1-based, wraps) centered at x,y with rotation and scale.
function bms.draw(seq, idx, x, y, rot, scale)
	if not seq or seq.count == 0 then return end
	idx = ((idx - 1) % seq.count) + 1
	local f = seq.frames[idx]
	-- quads address texels, so the atlas density has to come out of the scale;
	-- the origin stays in texels because that is the quad's own space
	local s = (scale or 1) / seq.density
	love.graphics.draw(seq.image, seq.quads[idx], x, y, rot or 0, s, s,
		f.w / 2, f.h / 2)
end

return bms

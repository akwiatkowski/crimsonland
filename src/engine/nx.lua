-- NX_* low-level engine API: bitmaps, drawing primitives, sound, input,
-- misc. Scripts use these mainly inside OnDraw custom drawing; the C++ side
-- used them for everything else. Unimplemented calls log once and no-op.

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local font = require("src.engine.font")
local platform = require("src.engine.platform")

local nx = {}

local logged = {}
local function log_once(name)
	if not logged[name] then
		logged[name] = true
		print(("[nx] %s not implemented (stub)"):format(name))
	end
end
nx.log_once = log_once

-- state for immediate-mode drawing
local cur_color = { 1, 1, 1, 1 }
local cur_blend = "alpha"

function nx.NX_ClearScreen(r, g, b)
	love.graphics.clear((r or 0) / 255, (g or 0) / 255, (b or 0) / 255, 1)
end

function nx.NX_LoadBitmap(path)
	assets.preload_image(path)
	return path
end

function nx.NX_GetBitmap(path)
	return path -- handles are just paths in this runtime
end

function nx.NX_GetBitmapWidth(bm)
	local img = assets.image(bm)
	return img and img:getWidth() or 0
end

function nx.NX_GetBitmapHeight(bm)
	local img = assets.image(bm)
	return img and img:getHeight() or 0
end

function nx.NX_IsBitmapReady(bm)
	return assets.image(bm) ~= nil
end

function nx.NX_GetNumBitmapFrames(bm) return 1 end
function nx.NX_SetBitmapFrame(bm, frame) end
function nx.NX_SetBitmapCacheMode(mode) end
function nx.NX_ReleaseBitmap(bm) end
function nx.NX_RefreshBitmap(bm) end
function nx.NX_CreateBitmap(w, h) log_once("NX_CreateBitmap") return nil end

function nx.NX_SetColor(r, g, b)
	-- engine colors: floats 0..1 (scripts use both; normalize >1 as 0-255)
	if (r or 0) > 1 or (g or 0) > 1 or (b or 0) > 1 then
		r, g, b = (r or 0) / 255, (g or 0) / 255, (b or 0) / 255
	end
	cur_color[1], cur_color[2], cur_color[3] = r or 1, g or 1, b or 1
end

function nx.NX_SetAlpha(a)
	cur_color[4] = a or 1
end

function nx.NX_SetBlend(mode)
	if mode == "ADDITIVE" or mode == 1 then
		cur_blend = "add"
	else
		cur_blend = "alpha"
	end
end

function nx.NX_SetPixelFilter(on) end

local function apply_state()
	love.graphics.setColor(cur_color)
	love.graphics.setBlendMode(cur_blend)
end

function nx.NX_DrawBitmap(bm, x, y)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	love.graphics.draw(img, x, y)
end

function nx.NX_DrawBitmapS(bm, x, y, scale)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	love.graphics.draw(img, x, y, 0, scale or 1, scale or 1)
end

function nx.NX_DrawBitmapRS(bm, x, y, rot, scale)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	love.graphics.draw(img, x, y, rot or 0, scale or 1, scale or 1,
		img:getWidth() / 2, img:getHeight() / 2)
end

function nx.NX_DrawBitmapMirroredRS(bm, x, y, rot, scale)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	love.graphics.draw(img, x, y, rot or 0, -(scale or 1), scale or 1,
		img:getWidth() / 2, img:getHeight() / 2)
end

function nx.NX_DrawBitmapAligned(bm, x, y, ax, ay)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	love.graphics.draw(img, x - (ax or 0) * img:getWidth(), y - (ay or 0) * img:getHeight())
end

function nx.NX_DrawSubBitmap(bm, x, y, sx, sy, sw, sh)
	local img = assets.image(bm)
	if not img then return end
	apply_state()
	-- scripts speak reference units; assets.quad maps them onto the texels
	local q, s = assets.quad(img, sx, sy, sw, sh)
	love.graphics.draw(img, q, x, y, 0, s, s)
end

function nx.NX_DrawRect(x, y, w, h)
	apply_state()
	love.graphics.rectangle("fill", x, y, w, h)
end

function nx.NX_DrawLine(x1, y1, x2, y2)
	apply_state()
	love.graphics.line(x1, y1, x2, y2)
end

function nx.NX_PushTransform() love.graphics.push() end
function nx.NX_PopTransform() love.graphics.pop() end
function nx.NX_PushTransformTranslation(x, y)
	love.graphics.push()
	love.graphics.translate(x, y)
end
function nx.NX_PushTransformRotation(r)
	love.graphics.push()
	love.graphics.rotate(r)
end
function nx.NX_PushTransformScale(sx, sy)
	love.graphics.push()
	love.graphics.scale(sx, sy or sx)
end
function nx.NX_PushScissorRectangle(x, y, w, h)
	love.graphics.push()
	love.graphics.intersectScissor(x, y, w, h)
end
function nx.NX_PopScissorRectangle() love.graphics.pop() end

-- text
function nx.NX_GetFont(path) return path end
function nx.NX_DrawText(fnt, x, y, text)
	font.draw(fnt, tostring(text or ""), x, y, cur_color)
end
function nx.NX_GetTextWidth(fnt, text)
	return (font.measure(fnt, tostring(text or "")))
end
function nx.NX_GetTextHeight(fnt, text)
	local _, h = font.measure(fnt, tostring(text or ""))
	return h
end
function nx.NX_GetFontHeight(fnt)
	return font.get(fnt):getHeight()
end
function nx.NX_SetTextAlign(align) log_once("NX_SetTextAlign") end
function nx.NX_SetTextboxWidth(w) log_once("NX_SetTextboxWidth") end
function nx.NX_SetTextTransform(...) log_once("NX_SetTextTransform") end

-- audio
function nx.NX_LoadSound(name) assets.sound(name, "sfx") return name end
function nx.NX_GetSound(name) return name end
function nx.NX_PlaySound(name, vol, pan, freq)
	return audio.play_sound(name, vol, pan, freq)
end
function nx.NX_ReleaseSound(name) end
function nx.NX_SetSoundParm(...) log_once("NX_SetSoundParm") end
function nx.NX_SetChannelFrequency(...) log_once("NX_SetChannelFrequency") end
function nx.NX_SetChannelLooping(...) log_once("NX_SetChannelLooping") end
function nx.NX_SetChannelPaused(...) log_once("NX_SetChannelPaused") end
function nx.NX_SlideChannelVolume(...) log_once("NX_SlideChannelVolume") end
function nx.NX_SlideMusicVolume(...) log_once("NX_SlideMusicVolume") end
function nx.NX_StopChannel(...) log_once("NX_StopChannel") end
function nx.NX_AllowMusic(...) end

-- input / misc
function nx.NX_GetKeyState(name) return false end
function nx.NX_GetKeyStateFloat(name) return 0 end
function nx.NX_SetKeyState(...) end
function nx.NX_SetKeyStateFloat(...) end
function nx.NX_SetCursor(name) end
function nx.NX_GetInterface() return "MOUSE" end
function nx.NX_GetTime() return love.timer.getTime() end
function nx.NX_FileExists(path) return assets.exists(path) end
function nx.NX_Popup(...) log_once("NX_Popup") end
function nx.NX_CallExtension(name, cmd)
	return platform.call_extension(name, cmd)
end

return nx

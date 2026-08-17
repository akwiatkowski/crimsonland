-- Options: audio sliders and the windowed checkbox. The layout scripts do the
-- work themselves through the engine API (GetSoundVolume/SetSoundVolume/...);
-- what the port had to supply was slider dragging, which no comp type had.

local function press(x, y)
	return function()
		local screens = require("src.engine.screens")
		local ww, wh = love.graphics.getDimensions()
		local scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
		screens.mousepressed(x * scale + (ww - screens.WIDTH * scale) / 2,
			y * scale + (wh - screens.HEIGHT * scale) / 2, 1)
	end
end

local function report(label)
	return function()
		local audio = require("src.engine.audio")
		local platform = require("src.engine.platform")
		print(("[options] %s sound=%.2f music=%.2f stored=%.2f/%.2f"):format(
			label, audio.sound_volume, audio.music_volume,
			platform.settings.sound_volume, platform.settings.music_volume))
	end
end

local function slider_rect()
	local screens = require("src.engine.screens")
	local comps = require("src.engine.comps")
	local s = screens.top()
	local c = s and s.compmap["VolSound"]
	if not c then
		print("[options] no VolSound slider on " .. (s and s.name or "?"))
		return
	end
	local x, y, w, h = comps.screen_rect(c)
	print(("[options] VolSound at x=%.0f y=%.0f w=%.0f h=%.0f"):format(x, y, w, h))
end

return {
	{ t = 2.5, click = "Options" },
	{ t = 4.0, click = "AudioOptions" },
	{ t = 5.0, run = report("opened") },
	{ t = 5.2, run = slider_rect },
	{ t = 6.0, run = press(550, 250) }, -- ~3/4 along the sound slider
	{ t = 6.5, run = report("after drag") },
	{ t = 7.5, click = "Ok" },
	{ t = 8.5, run = report("after OK") },
	captures = { 5.5, 7.0 },
}

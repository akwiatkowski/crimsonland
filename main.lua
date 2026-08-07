-- Entry point. All engine code lives under src/engine.

-- Debug harness (headless-friendly): tee prints to a log file and render the
-- output canvas as ASCII art at timed intervals, so behavior can be verified
-- from the terminal without a display.
local logfile = io.open("/tmp/crimsonland_port.log", "w")
local real_print = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	local line = table.concat(parts, "\t")
	real_print(line)
	if logfile then
		logfile:write(line .. "\n")
		logfile:flush()
	end
end

local engine = require("src.engine")
engine.start()

-- ASCII-art capture of the reference canvas at fixed times after boot.
local captures = { 2.0, 6.0, 10.0 }
local capture_idx = 1
local elapsed = 0

-- scripted input for headless interaction testing
local screens_mod = require("src.engine.screens")
local actions = {
	{ t = 5.0, fn = function() screens_mod.mousepressed(560 * 1.5, 226 * 1.5, 1) end }, -- Play
	{ t = 9.0, fn = function() screens_mod.keypressed("escape") end }, -- Back
}
local action_idx = 1

local ramp = " .:-=+*#%@"
local function capture_ascii()
	local screens = require("src.engine.screens")
	local info = { "stack:" }
	for i, s in ipairs(screens.stack) do
		info[#info + 1] = string.format("  %d %s phase=%.2f timer=%.1f comps=%d%s",
			i, s.name, s.phase, s.timer, #s.comps, s.leaving and " LEAVING" or "")
	end
	print(table.concat(info, "\n"))
	local comps = require("src.engine.comps")
	local top = screens.top()
	if top then
		for _, c in ipairs(top.comps) do
			if (c.type == "Button" or c.type == "Checkbox") and comps.get(c, "visible") then
				local x, y, w, h = comps.screen_rect(c)
				print(string.format("  hit %-20s x=%.0f y=%.0f w=%.0f h=%.0f", c.name, x, y, w, h))
			end
		end
	end
	local canvas = engine.get_canvas and engine.get_canvas()
	if not canvas then return end
	local data = canvas:newImageData()
	local W, H = data:getDimensions()
	local cols, rows = 96, 32
	local out = { string.format("=== canvas capture %dx%d ===", W, H) }
	for row = 0, rows - 1 do
		local line = {}
		for col = 0, cols - 1 do
			local x = math.floor(col / cols * (W - 1))
			local y = math.floor(row / rows * (H - 1))
			local r, g, b = data:getPixel(x, y)
			local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
			local idx = math.min(#ramp, math.floor(lum * #ramp) + 1)
			line[#line + 1] = ramp:sub(idx, idx)
		end
		out[#out + 1] = table.concat(line)
	end
	print(table.concat(out, "\n"))
end

local base_update = love.update
love.update = function(dt)
	if base_update then base_update(dt) end
	elapsed = elapsed + dt
	if action_idx <= #actions and elapsed >= actions[action_idx].t then
		actions[action_idx].fn()
		action_idx = action_idx + 1
	end
	if capture_idx <= #captures and elapsed >= captures[capture_idx] then
		capture_idx = capture_idx + 1
		capture_ascii()
	end
end

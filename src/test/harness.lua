-- Automated test harness. Loaded ONLY when the game is launched with
-- `--autotest[=scenario]` (make test); a normal `make run` never requires
-- this module.
--
-- Discipline: the harness drives the game exactly like a player would —
-- synthesized mouse/keyboard events through src.engine.screens — and only
-- READS state for captures. No mutating game internals: that fidelity is
-- what caught the PeekScreen stack bug.

local harness = {}

local engine = require("src.engine")
local screens = require("src.engine.screens")
local comps = require("src.engine.comps")

-- ---------------------------------------------------------------- actions

--- Click the center of a named comp on the top screen. The scenario speaks
-- reference coordinates (960x640); screens.mousepressed expects window
-- pixels, so replicate the engine's viewport math in reverse.
function harness.click(name)
	local top = screens.top()
	local comp = top and top.compmap[name]
	if not comp then
		print(("[test] no button '%s' on %s"):format(name, top and top.name or "?"))
		return
	end
	local x, y, w, h = comps.screen_rect(comp)
	local ww, wh = love.graphics.getDimensions()
	local scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
	local ox = (ww - screens.WIDTH * scale) / 2
	local oy = (wh - screens.HEIGHT * scale) / 2
	screens.mousepressed((x + w / 2) * scale + ox, (y + h / 2) * scale + oy, 1)
end

function harness.key(k)
	screens.keypressed(k)
end

-- --------------------------------------------------------------- captures

local ramp = " .:-=+*#%@"
local shot_idx = 0

--- Dump screen stack, game state, clickable rects and an ASCII rendering of
-- the reference canvas — everything needed to verify behavior from a log.
function harness.capture()
	local info = { "stack:" }
	for i, s in ipairs(screens.stack) do
		info[#info + 1] = string.format("  %d %s phase=%.2f timer=%.1f comps=%d%s",
			i, s.name, s.phase, s.timer, #s.comps, s.leaving and " LEAVING" or "")
	end
	print(table.concat(info, "\n"))

	local game = require("src.game.play")
	if game.active then
		print(string.format("  game mode=%s t=%.1f hp=%d kills=%d/%s creatures=%d bullets=%d",
			game.mode or "?", game.time, game.player.hp, game.kills,
			tostring(game.kills_goal or "inf"), #game.creatures, #game.bullets))
	end

	local fx = require("src.engine.fx")
	if fx.count() > 0 then print(("  fx particles=%d"):format(fx.count())) end

	local top = screens.top()
	if top then
		for _, c in ipairs(top.comps) do
			if (c.type == "Button" or c.type == "Checkbox") and comps.get(c, "visible") then
				local x, y, w, h = comps.screen_rect(c)
				print(string.format("  hit %-20s x=%.0f y=%.0f w=%.0f h=%.0f%s",
					c.name, x, y, w, h,
					comps.get(c, "active") and "" or " INACTIVE"))
			end
		end
	end

	local canvas = engine.get_canvas and engine.get_canvas()
	if not canvas then return end
	local data = canvas:newImageData()
	local W, H = data:getDimensions()

	-- ASCII is enough to verify layout and state, but not rendering quality —
	-- dump the frame too (LÖVE save dir) so retina/font work can be eyeballed
	shot_idx = shot_idx + 1
	local shot = string.format("capture-%02d.png", shot_idx)
	data:encode("png", shot)
	print(("  frame -> %s%s"):format(love.filesystem.getSaveDirectory(), "/" .. shot))

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

-- ------------------------------------------------------------ scenario run

--- Wrap love.update to execute a scenario (src/test/scenarios/<name>.lua):
-- a list of timed steps {t=, click=|key=} plus a `captures` time list.
function harness.install(scenario_name)
	local scenario = require("src.test.scenarios." .. scenario_name)
	print(("[test] running scenario '%s'"):format(scenario_name))

	-- keep the test window out of the user's way (best effort)
	pcall(love.window.minimize)
	-- and out of the user's ears: master-mute, game code never notices
	love.audio.setVolume(0)

	local elapsed = 0
	local step_idx = 1
	local capture_idx = 1
	local captures = scenario.captures or {}

	local base_update = love.update
	love.update = function(dt)
		if base_update then base_update(dt) end
		elapsed = elapsed + dt
		local step = scenario[step_idx]
		if step and elapsed >= step.t then
			step_idx = step_idx + 1
			if step.click then harness.click(step.click) end
			if step.key then harness.key(step.key) end
			-- escape hatch for subsystems a player cannot reach from input
			-- alone (the game polls love.mouse.isDown, which cannot be faked)
			if step.run then step.run() end
		end
		if captures[capture_idx] and elapsed >= captures[capture_idx] then
			capture_idx = capture_idx + 1
			harness.capture()
		end
	end
end

return harness

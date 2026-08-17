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

	-- whatever mod is loaded, not vanilla by name: the harness belongs to the
	-- engine and the engine does not know what a quest is
	local game = require("src.engine.mod").current
	game = game and game.game
	if game and game.active then
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

-- --------------------------------------------------------------- the clock
--
-- Scenario time is synthetic. Pacing them on the real frame delta made every
-- run hostage to the host: a minimized LÖVE window is App-Nap/occlusion
-- throttled on macOS to ~5% CPU, so 65 seconds of scenario took 2.5-5 minutes
-- of wall clock and looked exactly like a hang (`caffeinate` does not help —
-- it stops idle sleep, not per-app occlusion throttling). Stepping a fixed dt
-- as fast as the machine manages decouples game time from wall time, and as a
-- bonus makes two runs of the same scenario identical, which real dt never was.

local FIXED_DT = 1 / 60
-- Updates per drawn frame. Presenting is what a throttled window makes slow
-- (measured at ~9 fps minimized), and nothing but a capture ever reads the
-- result, so batching updates behind one draw is where the speedup comes from.
-- Scenario steps still fire on the 1/60 grid inside the batch, and a due
-- capture cuts the batch short — so this trades nothing but window smoothness.
local STEPS_PER_FRAME = 30
-- Fixed seed so creature spawns, drops and perk offers repeat run to run.
-- The value is arbitrary; only its constancy matters.
local RANDOM_SEED = 20140101
-- Scenario seconds to keep running after the last step and capture. A real-time
-- run could be left to idle until the user closed the window; a fast-forward
-- one would spin a core until then, so scenarios now end themselves.
local LINGER = 1.0

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
	-- nothing waits on the display in fast-forward, and vsync would cap the
	-- whole run at the refresh rate
	pcall(love.window.setVSync, 0)
	love.math.setRandomSeed(RANDOM_SEED)

	local elapsed = 0
	local step_idx = 1
	local capture_idx = 1
	local captures = scenario.captures or {}
	-- A capture reads the canvas, which only the next draw refreshes — so it
	-- is requested here and taken by the loop below, after presenting.
	local capture_due = false
	-- love.event.quit only takes effect at the next poll, which is a whole
	-- batch of updates away; without this the scenario ends 30 times over.
	local done = false

	local base_update = love.update
	love.update = function(dt)
		if base_update then base_update(dt) end
		elapsed = elapsed + dt
		-- every step whose time has passed, not one per frame: a long frame
		-- (a terrain bake, a big asset load) otherwise pushes the rest of the
		-- scenario out of step with the screens it expects
		while true do
			local step = scenario[step_idx]
			if not (step and elapsed >= step.t) then break end
			step_idx = step_idx + 1
			if step.click then harness.click(step.click) end
			if step.key then harness.key(step.key) end
			-- escape hatch for subsystems a player cannot reach from input
			-- alone (the game polls love.mouse.isDown, which cannot be faked)
			if step.run then step.run() end
		end
		if captures[capture_idx] and elapsed >= captures[capture_idx] then
			capture_idx = capture_idx + 1
			capture_due = true
		end

		local last = math.max(scenario[#scenario] and scenario[#scenario].t or 0,
			captures[#captures] or 0)
		if not done and step_idx > #scenario and capture_idx > #captures
			and elapsed >= last + LINGER then
			done = true
			print(("[test] scenario '%s' complete (%.1fs)"):format(scenario_name, elapsed))
			love.event.quit(0)
		end
	end

	-- LÖVE's own love.run also owns love.load and the event pump; replacing it
	-- means owning both. Everything here matches the stock loop except the
	-- clock: no love.timer.step, and no sleep.
	function love.run()
		if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

		return function()
			love.event.pump()
			for name, a, b, c, d, e, f in love.event.poll() do
				if name == "quit" then return a or 0 end
				love.handlers[name](a, b, c, d, e, f)
			end

			for _ = 1, STEPS_PER_FRAME do
				love.update(FIXED_DT)
				-- a capture wants a fresh canvas, and a finished scenario has
				-- nothing left to simulate: both end the batch early
				if capture_due or done then break end
			end

			if love.graphics.isActive() then
				love.graphics.origin()
				love.graphics.clear(love.graphics.getBackgroundColor())
				love.draw()
				love.graphics.present()
			end

			if capture_due then
				capture_due = false
				harness.capture()
			end
		end
	end
end

return harness

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
function harness.click_at(rx, ry)
	local ww, wh = love.graphics.getDimensions()
	local scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
	local ox = (ww - screens.WIDTH * scale) / 2
	local oy = (wh - screens.HEIGHT * scale) / 2
	screens.mousepressed(rx * scale + ox, ry * scale + oy, 1)
end

function harness.click(name)
	local top = screens.top()
	local comp = top and top.compmap[name]
	if not comp then
		print(("[test] no button '%s' on %s"):format(name, top and top.name or "?"))
		return
	end
	local x, y, w, h = comps.screen_rect(comp)
	harness.click_at(x + w / 2, y + h / 2)
end

--- Put the pointer on a named comp without pressing anything. Several panels
-- are filled by what the pointer is over rather than by what was clicked --
-- the galleries' details, the achievements' name and description, the survival
-- menu's mode panel -- and none of that was reachable from a scenario before.
function harness.hover(name)
	local top = screens.top()
	local comp = top and top.compmap[name]
	if not comp then
		print(("[test] no comp '%s' to hover on %s"):format(name, top and top.name or "?"))
		return
	end
	local x, y, w, h = comps.screen_rect(comp)
	local ww, wh = love.graphics.getDimensions()
	local scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
	local ox = (ww - screens.WIDTH * scale) / 2
	local oy = (wh - screens.HEIGHT * scale) / 2
	screens.mousemoved((x + w / 2) * scale + ox, (y + h / 2) * scale + oy)
end

function harness.key(k)
	screens.keypressed(k)
end

--- Type, the way love.textinput delivers it: characters, not key names.
function harness.text(s)
	screens.textinput(s)
end

-- --------------------------------------------------------------- captures

local ramp = " .:-=+*#%@"
local shot_idx = 0
-- A backbuffer screenshot is taken at the end of the NEXT drawn frame, and a
-- drawn frame is a whole batch of updates away (STEPS_PER_FRAME below) -- half
-- a second of game time, by which point a fireball or a heat shimmer is long
-- over. Set when a shot is outstanding so the loop runs a single step before
-- presenting again, which lands it beside the canvas dump instead.
local screenshot_pending = false

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

	local music = require("src.engine.audio").current_music
	if music then print(("  music %s"):format(music)) end

	local fx = require("src.engine.fx")
	if fx.count() > 0 then
		print(("  fx particles=%d screen=%d world=%d"):format(
			fx.count(), fx.count("screen"), fx.count("world")))
	end

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

	-- The canvas is the frame BEFORE it reaches the window, so nothing the
	-- post pass does to it is in that PNG — grade, bloom and heat shimmer are
	-- all invisible to a canvas capture, and comparing two of them proves
	-- nothing about any of them. This one is the actual backbuffer, taken at
	-- the end of the next draw, which is the only way to see them.
	local screen = string.format("screen-%02d.png", shot_idx)
	love.graphics.captureScreenshot(screen)
	screenshot_pending = true
	print(("  window -> %s%s"):format(love.filesystem.getSaveDirectory(), "/" .. screen))

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

-- --------------------------------------------------------------- verdicts
--
-- A scenario used to have no way to fail. It drove the game, printed what it
-- saw and always exited 0, so "did that work?" was a human reading captures —
-- which is fine for one scenario and impossible for a few hundred. A step can
-- now carry `expect = function() return ok, why end`, and the run's exit code
-- is the answer: 0 all clear, 1 something failed.
--
-- Deliberately no `expect` that repairs anything, and no tolerance knob. An
-- expectation that a run cannot meet is either a bug in the game or a claim
-- the scenario should not have made.

local failures = {}

local function check(step, index)
	local ok, why = step.expect()
	if ok then
		print(("[test] ok   %s"):format(why or ("expect #" .. index)))
	else
		failures[#failures + 1] = why or ("expect #" .. index)
		print(("[test] FAIL %s"):format(why or ("expect #" .. index)))
	end
end

-- ------------------------------------------------------------ error trapping
--
-- LÖVE's stock handler draws an error screen and keeps the loop alive until
-- somebody closes the window. Under --autotest there is no window to close
-- (conf.lua creates it hidden), so any Lua error used to mean a process
-- spinning a core until it was killed by hand — the one failure mode a matrix
-- run cannot survive. Trade the error screen for a traceback and exit 1.
local function install_errorhandler()
	-- love.errorhandler IS xpcall's message handler, so the stack it asks for
	-- is the one that threw, not this function's own.
	love.errorhandler = function(msg)
		print("[test] ERROR " .. tostring(msg))
		print(debug.traceback("", 2))
		-- os.exit rather than returning nil: returning hands control back to
		-- love.boot, which has its own opinions about what to draw next.
		os.exit(1, true)
	end
	love.errhand = love.errorhandler -- the 0.10 name, still consulted
end

-- ------------------------------------------------------------ scenario run

--- Wrap love.update to execute a scenario (src/test/scenarios/<name>.lua):
-- a list of timed steps {t=, click=|key=|expect=} plus a `captures` time list.
function harness.install(scenario_name)
	local scenario = require("src.test.scenarios." .. scenario_name)
	print(("[test] running scenario '%s'"):format(scenario_name))
	install_errorhandler()

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
	local dismiss = scenario.dismiss or {}
	local dismiss_set = {}
	for _, name in ipairs(dismiss) do dismiss_set[name] = true end
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
			-- {x, y} in reference coords: for screens that answer a click
			-- anywhere rather than a click on a comp (the unlock celebrations)
			if step.click_at then harness.click_at(step.click_at[1], step.click_at[2]) end
			if step.hover then harness.hover(step.hover) end
			if step.key then harness.key(step.key) end
			if step.text then harness.text(step.text) end
			-- escape hatch for subsystems a player cannot reach from input
			-- alone (the game polls love.mouse.isDown, which cannot be faked)
			if step.run then step.run() end
			if step.expect then check(step, step_idx - 1) end
		end
		-- Screens that dismiss on a click anywhere, dismissed. A scenario that
		-- hands the player to the AI otherwise stops exercising the game the
		-- first time it picks up a weapon it has never held: the unlock
		-- celebration goes up, the game underneath stops being updated, and
		-- nothing fails -- combat-smoke was spending better than half its run
		-- frozen behind one, reporting the same numbers twice. A human clicks;
		-- so does this. Named by the scenario because which screens work that
		-- way is the mod's business, not the engine's.
		if dismiss[1] then
			local top = screens.top()
			if top and not top.leaving and dismiss_set[top.name] then
				harness.click_at(screens.WIDTH / 2, screens.HEIGHT / 2)
			end
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
			if #failures > 0 then
				print(("[test] %d FAILED: %s"):format(#failures, table.concat(failures, "; ")))
			end
			love.event.quit(#failures > 0 and 1 or 0)
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

			-- one step while a screenshot is outstanding, so the frame it is
			-- taken from is the one that was just captured rather than half a
			-- second of game time past it
			local steps = screenshot_pending and 1 or STEPS_PER_FRAME
			for _ = 1, steps do
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
				-- present() is where an outstanding screenshot is resolved
				screenshot_pending = false
			end

			if capture_due then
				capture_due = false
				harness.capture()
			end
		end
	end
end

return harness

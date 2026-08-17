-- Screen registry + stack + event dispatch + transitions.
--
-- Each screen owns a Lua environment (layout script + events script +
-- LuaInclude'd helpers all share it), a comp tree, and transition state.
--
-- Semantics discovered from the original scripts:
--  * Events file defaults to "<layout base>-events.lua", UIEvents() overrides.
--  * PopScreen() pops the CALLING screen (used as push-then-pop replace).
--  * Transitions: phase 0 -> 1 over enter_trans_duration on enter,
--    1 -> 0 over leave_trans_duration on leave; removed at 0.

local comps = require("src.engine.comps")

local screens = {}

screens.registry = {} -- name -> { layout=, events= }
screens.stack = {} -- bottom .. top
screens.current = nil -- screen whose script is executing (callback context)
screens.loading = nil -- screen currently running its layout script

local SCRIPT_ROOT = require("src.engine.paths").ASSETS .. "/"

-- ------------------------------------------------------------- registration

function screens.register(name, layout_path, events_path)
	screens.registry[name] = { layout = layout_path, events = events_path }
end

-- CamelCase -> dash-separated: "GameCrimsonland" -> "game-crimsonland"
local function conventional_path(name)
	local dash = name:gsub("(%u)", function(c) return "-" .. c:lower() end):gsub("^-", "")
	return "ui/" .. dash .. ".lua"
end

-- C++-side screens (layout paths embedded in prog.dll) + autoexec ones.
function screens.register_builtin(name)
	local layout = conventional_path(name)
	if love.filesystem.getInfo(SCRIPT_ROOT .. layout) then
		screens.register(name, layout)
		return true
	end
	return false
end

-- --------------------------------------------------------------- lifecycle

local screen_mt = {}
screens.screen_mt = screen_mt

function screens.new(name)
	local def = screens.registry[name]
	local s = {
		name = name,
		env = nil,
		comps = {},
		compmap = {},
		last_comp = nil,
		phase = 0, -- transition phase 0..1
		entering = true,
		leaving = false,
		timer = 0,
		parm = nil,
		messages = {},
		props = {
			enter_trans_duration = 0.4,
			leave_trans_duration = 0.4,
			only_update_when_top_screen = false,
			covers_screen = false,
		},
		entered = false,
	}
	return s
end

-- run a lua file inside a screen env; returns ok, err
function screens.run_script(screen, path)
	local full = SCRIPT_ROOT .. path
	if not love.filesystem.getInfo(full) then
		return false, "not found: " .. path
	end
	local chunk, err = loadfile(full)
	if not chunk then return false, err end
	setfenv(chunk, screen.env)
	local ok, rerr = pcall(chunk)
	if not ok then
		print(("[screens] error in %s: %s"):format(path, rerr))
		return false, rerr
	end
	return true
end

function screens.load(screen)
	local engine = require("src.engine")
	screen.env = engine.new_script_env(screen)
	local prev_loading = screens.loading
	screens.loading = screen
	local def = screens.registry[screen.name]
	if def and def.internal then
		def.internal(screen)
		-- internal screens (Title, GameCrimsonland) are not UI screens:
		-- they stay at phase 0 so GetStackDepthOffset() ignores them
		screen.no_phase = true
		screen.phase = 0
		screens.loading = prev_loading
		screens.call(screen, "OnLoad")
		return screen
	end
	if def and def.layout then
		screens.run_script(screen, def.layout)
		-- events: UIEvents() may have set screen.events_path during layout
		local events = screen.events_path
		if not events and def and def.layout then
			local guess = def.layout:gsub("%.lua$", "-events.lua")
			if love.filesystem.getInfo(SCRIPT_ROOT .. guess) then
				events = guess
			end
		end
		if events then
			screens.run_script(screen, events)
		end
	end
	screens.loading = prev_loading
	-- Layouts are written for every platform 10tons shipped on and gate the
	-- parts that do not apply with `required_features` ("FEATURE" must be
	-- present, "!FEATURE" must be absent, comma-separated). Without this the
	-- Options screen stacks Display and Gameplay on the same spot, and dead
	-- buttons for co-op, in-app purchases and console controls stay clickable.
	local platform = require("src.engine.platform")
	for _, c in ipairs(screen.comps) do
		local req = c.props["required_features"]
		if type(req) == "string" then
			for token in req:gmatch("[^,%s]+") do
				local negated = token:sub(1, 1) == "!"
				local name = negated and token:sub(2) or token
				if platform.feature_exists(name) == negated then
					c.props.visible = false
					break
				end
			end
		end
	end
	-- resolve parent links now that all comps exist
	for _, c in ipairs(screen.comps) do
		if c.parent_name then
			local parent = screen.compmap[c.parent_name]
			if parent then
				c.parent = parent
				table.insert(parent.children, c)
			else
				print(("[screens] %s: parent '%s' of '%s' not found"):format(screen.name, c.parent_name, c.name))
			end
		end
	end
	screens.call(screen, "OnLoad")
	return screen
end

-- call an events callback, resiliently
function screens.call(screen, fname, ...)
	local env = screen.env
	if not env then return nil end
	local fn = env[fname]
	if type(fn) ~= "function" then return nil end
	local prev = screens.current
	screens.current = screen
	local ok, err = pcall(fn, ...)
	if not ok then
		print(("[screens] %s.%s error: %s"):format(screen.name, fname, err))
	end
	screens.current = prev
	return nil
end

function screens.find(name)
	for _, s in ipairs(screens.stack) do
		if s.name == name then return s end
	end
	return nil
end

function screens.top()
	return screens.stack[#screens.stack]
end

function screens.push(name, parm)
	local existing = screens.find(name)
	if existing then return existing end
	local s = screens.new(name)
	s.parm = parm
	screens.load(s)
	table.insert(screens.stack, s)
	s.entered = true
	screens.call(s, "OnEnter")
	-- the C++ side used to fill in state the layout scripts know nothing about
	-- (which quests are unlocked, which mode is available); the mod does it now
	require("src.engine.mod").game_call("on_screen_enter", name, s)
	return s
end

-- pop the calling screen (callback context), or the top screen if called
-- outside any callback
function screens.pop(name)
	local target = name and screens.find(name) or screens.current or screens.top()
	if target then
		target.leaving = true
		target.entering = false
	end
end

function screens.switch(name)
	local top = screens.top()
	if top then top.leaving = true end
	screens.push(name)
end

-- ------------------------------------------------------------ update/draw

function screens.update(dt)
	-- transition phases + timers + OnUpdate
	for i = #screens.stack, 1, -1 do
		local s = screens.stack[i]
		local is_top = (i == #screens.stack)
		if s.no_phase then
			if s.leaving then
				-- internal screens have no transition: remove immediately
				screens.call(s, "OnLeave")
				table.remove(screens.stack, i)
			else
				s.phase = 0
				s.timer = s.timer + dt
				screens.call(s, "OnUpdate", dt)
			end
		elseif s.leaving then
			s.phase = s.phase - dt / math.max(0.001, s.props.leave_trans_duration)
			-- leaving screens still animate: their OnUpdate reads the
			-- decreasing phase to drive the exit motion
			s.timer = s.timer + dt
			screens.call(s, "OnUpdate", dt)
			if s.phase <= 0 then
				screens.call(s, "OnLeave")
				table.remove(screens.stack, i)
			end
		else
			if s.phase < 1 then
				s.phase = math.min(1, s.phase + dt / math.max(0.001, s.props.enter_trans_duration))
			end
			if is_top or not s.props.only_update_when_top_screen then
				s.timer = s.timer + dt
				screens.call(s, "OnUpdate", dt)
			end
		end
	end

	-- Comps with a life of their own. This runs after every OnUpdate above,
	-- because an emitter reads its own resolved position and a script may have
	-- just moved the parent it hangs from.
	for _, s in ipairs(screens.stack) do
		for _, c in ipairs(s.comps) do
			if c.type == "Emitter" then comps.update_emitter(c, dt) end
		end
	end
end

function screens.draw()
	local mod = require("src.engine.mod")
	for _, s in ipairs(screens.stack) do
		for _, c in ipairs(s.comps) do
			if not c.parent then
				comps.draw(c, screens.WIDTH, screens.HEIGHT)
			end
		end
		screens.call(s, "OnDraw")
		-- several pak layouts are just a frame with a Marker where the C++
		-- side painted the contents (high scores, statistics); the mod fills
		-- those in, after the script's own OnDraw
		mod.game_call("on_screen_draw", s.name, s)
	end
end

-- ------------------------------------------------------------------- input

local KEYMAP = {
	escape = "ESCAPE",
	["return"] = "RETURN",
	kpenter = "RETURN",
	space = "SPACE",
	backspace = "BACKSPACE",
	lshift = "SHIFT",
	rshift = "SHIFT",
	lctrl = "CONTROL",
	rctrl = "CONTROL",
	insert = "INSERT",
	delete = "DELETE",
	home = "HOME",
	pageup = "PAGEUP",
	pagedown = "PAGEDOWN",
	up = "UP",
	down = "DOWN",
	left = "LEFT",
	right = "RIGHT",
	tab = "TAB",
}

function screens.keypressed(key)
	local name = KEYMAP[key] or key:upper()
	local top = screens.top()
	if top then screens.call(top, "OnKeyDown", name) end
end

local function to_screen_coords(x, y)
	local engine = require("src.engine")
	return engine.to_reference(x, y)
end

--- Set a slider from a pointer position (reference x), 0..1 across its width.
local function set_slider_from(comp, rx)
	local sx, _, sw = comps.screen_rect(comp)
	if not sw or sw <= 0 then return end
	local v = math.max(0, math.min(1, (rx - sx) / sw))
	comp.props["slider.value"] = v
	-- the layout script applies it (audio-options-events reads the value back
	-- out of the comp on every OnClick), so tell it the slider moved
	screens.call(comp.screen, "OnClick", comp.name)
end

function screens.mousemoved(x, y)
	local rx, ry = to_screen_coords(x, y)
	local top = screens.top()
	if not top then return end

	-- a slider grabbed by mousepressed keeps following the pointer
	if screens.dragging then
		if love.mouse.isDown(1) and screens.dragging.screen == top then
			set_slider_from(screens.dragging, rx)
		else
			screens.dragging = nil
		end
	end
	-- clear hovers on other screens implicitly: only top screen is interactive
	for _, c in ipairs(top.comps) do c.hover = false end
	local hit = nil
	for i = #top.comps, 1, -1 do
		local c = top.comps[i]
		if not c.parent then
			hit = comps.hit(c, screens.WIDTH, screens.HEIGHT, rx, ry)
			if hit then break end
		end
	end
	if hit then
		hit.hover = true
		if top._hover_comp ~= hit then
			local snd = hit.props.snd_over
			if snd and snd ~= "!NONE" then
				require("src.engine.audio").play_ui_sound(snd)
			end
		end
	end
	top._hover_comp = hit
end

function screens.mousereleased(x, y, button)
	if button == 1 then screens.dragging = nil end
end

function screens.mousepressed(x, y, button)
	if button ~= 1 then return end
	local rx, ry = to_screen_coords(x, y)
	local top = screens.top()
	if not top then return end
	for i = #top.comps, 1, -1 do
		local c = top.comps[i]
		if not c.parent then
			local hit = comps.hit(c, screens.WIDTH, screens.HEIGHT, rx, ry)
			if hit then
				local snd = hit.props.snd_press
				if snd and snd ~= "!NONE" then
					require("src.engine.audio").play_ui_sound(snd)
				end
				if hit.type == "Checkbox" then
					local v = hit.props["checkbox.value"]
					hit.props["checkbox.value"] = not (v == true or v == 1)
				elseif hit.type == "Listbox" then
					-- rows are picked in the listbox's own space
					local lx, ly = comps.screen_rect(hit)
					local row = comps.listbox_row(hit, rx - lx, ry - ly)
					if row then hit.props["listbox.selected"] = row end
				elseif hit.type == "Slider" then
					-- sliders are dragged, so remember which one until the
					-- button comes back up (see screens.mousereleased)
					screens.dragging = hit
					set_slider_from(hit, rx)
				end
				screens.call(top, "OnClick", hit.name)
				-- clicks the script's OnClick ignores (Chapter_N, Quest_N —
				-- handled in C++ originally) fall through to the active mod
				require("src.engine.mod").game_call("on_ui_click", top.name, hit.name)
				return
			end
		end
	end
end

screens.WIDTH = 960
screens.HEIGHT = 640

return screens

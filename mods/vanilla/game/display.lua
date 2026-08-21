-- Display Options: the resolution list and Apply.
--
-- The layout ships a Listbox named "Resolutions" and a Windowed checkbox, and
-- its events script handles nothing but Back — populating the list, tracking
-- the selection and applying it were the C++ side's job.

local comps = require("src.engine.comps")
local platform = require("src.engine.platform")

local display = {}

local modes = nil -- descending, deduplicated; index matches the listbox rows

local function label(mode)
	return ("%d x %d"):format(mode.width, mode.height)
end

--- Modes worth offering, largest first.
--
-- macOS reports every scaled variant its compositor will accept — 105 of them
-- here, in steps of 16 pixels (2560x1440, 2544x1431, 2528x1422, ...) — which
-- is a list nobody wants to scroll. Keep the desktop's own aspect ratio, drop
-- anything too small to show the game, and require a real step between
-- entries so the near-duplicates collapse.
local MIN_WIDTH, MIN_HEIGHT = 960, 640
local ASPECT_TOLERANCE = 0.02
local MIN_STEP = 0.08 -- 8% narrower than the last one kept

local function fullscreen_modes()
	if modes then return modes end
	local desktop_w, desktop_h = love.window.getDesktopDimensions()
	local desktop_aspect = desktop_w / desktop_h

	local candidates = {}
	for _, m in ipairs(love.window.getFullscreenModes()) do
		local aspect = m.width / m.height
		if m.width >= MIN_WIDTH and m.height >= MIN_HEIGHT
			and math.abs(aspect - desktop_aspect) / desktop_aspect <= ASPECT_TOLERANCE then
			candidates[#candidates + 1] = m
		end
	end
	table.sort(candidates, function(a, b)
		if a.width == b.width then return a.height > b.height end
		return a.width > b.width
	end)

	modes = {}
	local last = nil
	for _, m in ipairs(candidates) do
		if not last or (last - m.width) / last >= MIN_STEP then
			modes[#modes + 1] = m
			last = m.width
		end
	end
	return modes
end

-- ------------------------------------------------------- keeping the change
--
-- ui/keep-display-settings.lua is the dialog the original put between Apply and
-- living with the result: "Keep Settings?", a Keep Changes button, a Revert
-- button, and a Countdown that reverts on its own. Nothing could push it here,
-- so Apply committed the change outright -- and the case the dialog exists for
-- is the one where that is worst: a mode the display cannot show, leaving the
-- player to find the options screen again on a screen showing nothing.
--
-- The wait is the layout's own number: the Countdown textbox ships storing "7"
-- (keep-display-settings.lua:62).
local KEEP_SECONDS = 7

-- The mode to go back to, captured before Apply changed it. Read off the window
-- rather than off platform.settings, because settings hold what was last saved
-- and this has to restore what was on screen a moment ago.
local previous = nil

local function set_mode(width, height, fullscreen)
	love.window.setMode(width, height, {
		resizable = true,
		fullscreen = fullscreen,
		vsync = 1,
		msaa = 4,
		highdpi = true,
	})
	-- The canvas and the pointer mapping are both sized from the window, and
	-- the engine recomputes them in love.resize -- which the OS fires when the
	-- user drags a window edge, and does not reliably fire for a setMode we
	-- made ourselves. Without this the viewport keeps the old window's scale
	-- and offset, so every click after Apply is mapped to the wrong place:
	-- the confirmation dialog's own buttons could not be clicked, which is how
	-- this was found. love.resize *is* the engine's handler (init.lua assigns
	-- it), so calling it is running the same code the event would have.
	if love.resize then love.resize() end
end

local function commit()
	previous = nil
	require("src.engine.mod").game_call("save_settings")
end

local function revert()
	if previous then
		set_mode(previous.width, previous.height, previous.fullscreen)
		platform.settings.width = previous.width
		platform.settings.height = previous.height
		platform.settings.windowed = not previous.fullscreen
	end
	-- nothing to undo on disk: keeping is what would have written it
	previous = nil
end

--- Count the dialog down, and put the old mode back if nobody answers.
--
-- In the screen's update, not its draw: setMode cannot be called while a canvas
-- is bound, and everything this port draws goes onto one. Doing it from a draw
-- hook threw "love.window.setMode cannot be called while a Canvas is active"
-- the first time a countdown ran out.
--
-- The pak's own OnUpdate is wrapped rather than replaced: it is what runs
-- DoPanelTransitionFlipCenter, and without it the dialog would sit still.
--
-- Driven off the screen's own timer rather than one of its own, so there is no
-- state to reset and no way for the two to drift -- the engine advances
-- screen.timer for every screen on the stack.
local function install_countdown(screen)
	local base = screen.env.OnUpdate
	screen.env.OnUpdate = function(dt)
		if base then base(dt) end
		local left = math.max(0, KEEP_SECONDS - (screen.timer or 0))
		local countdown = screen.compmap["Countdown"]
		if countdown then
			comps.set(countdown, "textbox.text", { tostring(math.ceil(left)) })
		end
		if left <= 0 and not screen.leaving then
			revert()
			require("src.engine.screens").pop("KeepDisplaySettings")
		end
	end
end

function display.prepare(screen_name, screen)
	-- The Options layout stacks Display Options and Gameplay on the same slot
	-- and leaves it to the platform which one survives: Display is gated on
	-- DISPLAY_OPTIONS, Gameplay is not. A desktop build wants both, and the
	-- slot below is free now that Restore Purchases is gated out with the
	-- store, so Gameplay moves down into it.
	if screen_name == "Options" then
		local gameplay = screen.compmap["GameplayOptions"]
		local display_btn = screen.compmap["DisplayOptions"]
		if gameplay and display_btn and comps.get(display_btn, "visible") then
			comps.set(gameplay, "position", { 0, 0.2 })
		end
		return
	end

	if screen_name == "KeepDisplaySettings" then
		install_countdown(screen)
		return
	end

	if screen_name ~= "DisplayOptions" then return end
	local list = screen.compmap["Resolutions"]
	if not list then return end

	local items, selected = {}, 1
	local cur_w, cur_h = love.window.getMode()
	for i, m in ipairs(fullscreen_modes()) do
		items[i] = label(m)
		if m.width == cur_w and m.height == cur_h then selected = i end
	end
	comps.set(list, "listbox.items", { items })
	comps.set(list, "listbox.selected", { selected })

	local windowed = screen.compmap["Windowed"]
	if windowed then
		comps.set(windowed, "checkbox.value", { platform.settings.windowed })
	end

	-- These footnotes explain the original's filtering and mark modes with an
	-- inline image ("|SRC='...ar.png'|"), a text markup this port does not
	-- parse — and the filtering they describe is not what we do anyway.
	for _, name in ipairs({ "HidingModesLargerThanDesktop", "SelectedResolution3", "label" }) do
		local comp = screen.compmap[name]
		if comp then comps.set(comp, "visible", { false }) end
	end
end

--- Apply is the only control the pak's own script does not handle, and the
-- confirmation it now raises is the only other one.
function display.on_click(screen_name, comp_name, screen)
	if screen_name == "KeepDisplaySettings" then
		if comp_name == "Keep" then
			commit()
		elseif comp_name == "Revert" then
			revert()
		else
			return false
		end
		require("src.engine.screens").pop("KeepDisplaySettings")
		return true
	end

	if screen_name ~= "DisplayOptions" or comp_name ~= "Apply" then return false end
	local list = screen and screen.compmap["Resolutions"]
	local mode = list and fullscreen_modes()[comps.num(list, "listbox.selected", 0)]
	local windowed = screen and screen.compmap["Windowed"]
	local want_windowed = windowed == nil or comps.get(windowed, "checkbox.value") == true

	-- what to come back to if this turns out to be unviewable
	local cur_w, cur_h, flags = love.window.getMode()
	previous = { width = cur_w, height = cur_h,
		fullscreen = flags and flags.fullscreen or false }

	if mode then
		set_mode(mode.width, mode.height, not want_windowed)
		platform.settings.width, platform.settings.height = mode.width, mode.height
	end
	platform.settings.windowed = want_windowed
	-- Not written yet: keeping the change is what writes it. Until then the file
	-- on disk still describes a mode known to work.
	require("src.engine.screens").push("KeepDisplaySettings")
	return true
end

return display

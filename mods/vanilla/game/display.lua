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

--- Apply is the only control the pak's own script does not handle.
function display.on_click(screen_name, comp_name, screen)
	if screen_name ~= "DisplayOptions" or comp_name ~= "Apply" then return false end
	local list = screen and screen.compmap["Resolutions"]
	local mode = list and fullscreen_modes()[comps.num(list, "listbox.selected", 0)]
	local windowed = screen and screen.compmap["Windowed"]
	local want_windowed = windowed == nil or comps.get(windowed, "checkbox.value") == true

	if mode then
		love.window.setMode(mode.width, mode.height, {
			resizable = true,
			fullscreen = not want_windowed,
			vsync = 1,
			msaa = 4,
			highdpi = true,
		})
		platform.settings.width, platform.settings.height = mode.width, mode.height
	end
	platform.settings.windowed = want_windowed
	require("src.engine.mod").game_call("save_settings")
	return true
end

return display

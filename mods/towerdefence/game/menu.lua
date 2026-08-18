-- The mod's own front door.
--
-- Until now "Play" on the pak's main menu started a run directly — a
-- placeholder from slice one that skipped past the two things a front door is
-- for: saying what game this is, and saying how the last one went. With no
-- levels and no unlocks, the wave you reached is the entire record, so this is
-- also the only place it is ever shown outside the end panel.
--
-- Built from real comps through the engine's register_internal seam, like the
-- HQ: the pak has no layout for a mode 10tons never shipped, and a screen made
-- of the framework's own comps gets its hit-testing, hover sounds and
-- transitions for free.

local comps = require("src.engine.comps")
local font = require("src.engine.font")
local screens = require("src.engine.screens")

local menu = {}

local SCREEN = "TDMainMenu"

local BONE = { 0.91, 0.89, 0.84 }
local BRASS = { 0.79, 0.64, 0.29 }
local DIM = { 0.45, 0.44, 0.42 }

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

-- the field, injected on open so this module never requires the game back
local field

local function add(screen, ctype, name, template, x, y)
	local c = comps.new(ctype, name, screen)
	c._order = #screen.comps + 1
	table.insert(screen.comps, c)
	screen.compmap[name] = c
	if template then comps.set(c, "inherit", { template }) end
	comps.set(c, "position", { x, y })
	comps.set(c, "align", { "CENTER" })
	return c
end

screens.register_internal(SCREEN, function(screen)
	add(screen, "Image", "panel", "PanelSmall", 0.5, 0.5)
	local title = add(screen, "Textbox", "Title", "LargeTextbox", 0.5, 0.33)
	comps.set(title, "textbox.text", { "TOWER DEFENCE" })
	comps.set(title, "align", { "HCENTER" })

	local play = add(screen, "Button", "NewRun", "WideButton", 0.5, 0.52)
	comps.set(play, "button.text", { "Defend the base" })
	local back = add(screen, "Button", "Back", "WideButton", 0.5, 0.63)
	comps.set(back, "button.text", { "Back" })

	screen.env.OnKeyDown = function(key)
		if key == "ESCAPE" then screens.pop(SCREEN) end
	end
	screen.env.OnDraw = function() end
end)

--- What the last runs came to, under the title. A record with no rows yet says
-- so rather than showing zeroes, because "wave 0" is not a thing that happened.
local function draw_menu(screen)
	local panel = screen.compmap.panel
	if not panel or not field then return end
	local px, py, pw = comps.screen_rect(panel)
	local function line(f, text, y, colour)
		font.draw(f, text, px + (pw - font.measure(f, text)) / 2, y, colour)
	end

	local best = field.progress()
	if best.runs == 0 then
		line(F_SMALL, "Hold the centre. Buy what holds it for you.", py + 118, DIM)
	else
		line(F_MEDIUM, ("Best: wave %d"):format(best.best_wave), py + 112, BRASS)
		line(F_SMALL, ("%d kills on that run  -  %d runs"):format(
			best.best_kills, best.runs), py + 144, BONE)
	end
end

function menu.open(f)
	field = f
	screens.push(SCREEN)
end

function menu.on_screen_draw(screen_name, screen)
	if screen_name == SCREEN then draw_menu(screen) end
end

--- Returns true when the click was the menu's own.
function menu.on_ui_click(screen_name, comp_name, f)
	field = f
	if screen_name ~= SCREEN then return false end
	if comp_name == "NewRun" then
		field.start_run()
		require("src.engine.timeline").begin("Game")
	elseif comp_name == "Back" then
		screens.pop(SCREEN)
	end
	return true
end

return menu

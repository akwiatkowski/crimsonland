-- A gallery for the weapons the pak has no plate for.
--
-- Extras -> Weapons is a grid of exactly thirty plates, authored in
-- ui/weapons.lua, and there is no thirty-first. That is not a shortcoming to
-- work around -- it is the original's own screen for the original's own
-- arsenal, and putting a Rail Cannon in it would be this cartridge writing on
-- something that is not its property. So the sixteen get a grid of their own,
-- built from real comps through `screens.register_internal` (the seam tower
-- defence's HQ opened), laid out to the same geometry as the pak's so the two
-- read as one game: same panel, same plate template, same six columns.
--
-- It does the two jobs the pak's grid does:
--
--   * the collection, reached from a button added to Extras -> Weapons, with
--     the same three plate states -- its own art once you have held it, the
--     shipped lock until then;
--   * the celebration, because `unlocks.saw_weapon` pushes WeaponUnlocked at
--     the weapon's index and index 64 has no plate there. Patched below rather
--     than changed in vanilla: a cartridge's own weapons are the cartridge's
--     own problem.

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")
local font = require("src.engine.font")
local fx = require("src.engine.fx")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")
local unlocks = require("mods.vanilla.game.unlocks")

local arsenal = {}

local SCREEN = "EnhancedArsenal"
local PAK_GALLERY = "Weapons"
local OPEN_BUTTON = "EnhancedArsenalOpen"

local BONE = { 0.88, 0.85, 0.78, 1 }
local BRASS = { 0.85, 0.68, 0.28, 1 }
local DIM = { 0.55, 0.53, 0.5, 1 }
local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

local LOCK_ICON = "ui/gfx/lock-small.png"

-- The pak's own grid geometry, read off ui/weapons.lua rather than invented:
-- six columns at these fractions of the aligner, rows a fifth apart. The grid
-- is centred on the panel, which for a full thirty comes out at the pak's own
-- five rows and for sixteen puts three in the middle.
local COLUMNS = { -0.416667, -0.25, -0.0833333, 0.0833333, 0.25, 0.416667 }
local ROW_STEP = 0.2

-- One line each, in the player's terms rather than the code's: what holding it
-- makes you do differently. A stat line is already on the plate's tooltip in
-- the pak's gallery and it is not what tells these sixteen apart.
local BLURB = {
	BOUNCER_SMG = "Rounds bounce off the arena edge and hit harder for it. "
		.. "Fight near a wall on purpose.",
	TESLA_ARC = "Locks on to whatever is nearest and arcs onward. You do not "
		.. "aim it; you stand somewhere.",
	NAIL_GRENADE = "Thrown to the point under the cursor and goes off there. "
		.. "The first weapon that spends how far away you are pointing.",
	ACID_SPRAYER = "A short cone that leaves corrosive ground behind it. "
		.. "About where they can walk, not about damage.",
	SNIPER_RAIL = "Damage climbs with the distance to what you are aiming at. "
		.. "Devastating across the field, feeble up close.",
	NODE_GUN = "Darts stick where they land and stay a relay. Seed a crowd, "
		.. "then discharge the whole web with the next shot.",
	FLAK_CANNON = "A shell lobbed to the cursor that bursts into fourteen "
		.. "pieces going everywhere.",
	PRISM_RAIL = "The beam breaks at the first body into a fan. Which creature "
		.. "you shoot first is where the fan lands.",
	ARC_LASSO = "Drags what it chains toward each other. It barely kills; it "
		.. "arranges a crowd for the shot after.",
	TRACER_RAIL = "Leaves the path burning for two seconds. A rail shot that "
		.. "is a fence rather than an event.",
	RAIL_SPIKE = "Hold to charge, release to fire. A full spike is worth eight "
		.. "of a tapped one and costs you the seconds it took.",
	CAPACITOR_RIFLE = "Every third of a second held banks another arc. Bank a "
		.. "sixth and it goes into you instead.",
	BALL_LIGHTNING = "Drifts, arcing at everything close by -- you included. "
		.. "A hazard that denies the lane to both sides.",
	TETHER_RAIL = "Plants an anchor where you started firing, and shoots from "
		.. "there. The only gun whose rounds do not start at you.",
	STORM_RING = "A field around you that closes in while you hold the trigger "
		.. "and opens out while you do not. The mouse does nothing.",
	RAIL_CANNON = "Two shots, then three seconds of nothing. Goes through "
		.. "eight bodies without losing a point and shoves what survives.",
}

--- The sixteen, in pool order. Everything past the pak's own run.
local function entries()
	data.load_all()
	local list = {}
	for i = data.last_player_weapon + 1, #data.player_weapons do
		list[#list + 1] = data.player_weapons[i]
	end
	return list
end

--- Which of the sixteen a plate shows, or nil. Public because the picker
-- reads the same grid this screen draws: two answers to "what is plate 9" is
-- one answer too many.
function arsenal.entry_at(index)
	return entries()[index]
end

--- Grid slot of a weapon by its weapons.xml index, or nil if it is not one of
-- ours -- which is exactly the test for "the pak's grid has no plate for this".
function arsenal.slot_of(weapon)
	if not weapon then return nil end
	for i, w in ipairs(entries()) do
		if w.id == weapon.id then return i end
	end
	return nil
end

-- ------------------------------------------------------------ the screen

local function add(screen, ctype, name, template, parent, x, y)
	local c = comps.new(ctype, name, screen)
	c._order = #screen.comps + 1
	table.insert(screen.comps, c)
	screen.compmap[name] = c
	if template then comps.set(c, "inherit", { template }) end
	if parent then
		comps.set(c, "parent", { parent })
	end
	comps.set(c, "position", { x, y })
	return c
end

--- Hang the comps off each other by name.
--
-- `screens.load` does this for a screen built from a pak layout and returns
-- before it for an internal one, so an internal screen has to do it itself.
-- It is not optional dressing: `screens.draw` only draws comps with no parent
-- and lets each draw its own children, so an unlinked plate is positioned
-- against the whole window instead of against the panel -- which for a column
-- at -0.42 means off the left edge of the screen entirely.
local function link_parents(screen)
	for _, c in ipairs(screen.comps) do
		local parent = c.parent_name and screen.compmap[c.parent_name]
		if parent then
			c.parent = parent
			table.insert(parent.children, c)
		end
	end
end

--- The panel slides in and the fader darkens what is behind it, which is what
-- every screen the pak ships does through `DoPanelTransition` in
-- ui/common-ui-funcs.lua. The arithmetic is that function's, minus the depth
-- term (nothing stacks on top of this one) -- reimplemented rather than
-- included because those helpers are defined per screen by `LuaInclude`, and
-- borrowing six lines is cheaper than borrowing a loading convention.
--
-- Without it the panel sits at the alpha it was built with and the fader never
-- darkens, which is only half the problem; see `unpin` below for the other.
local function transition(screen)
	return function()
		local trans = math.sin(0.5 * math.pi * screen.phase)
		local fader, panel = screen.compmap.fader, screen.compmap.panel
		if fader then comps.set(fader, "alpha", { math.min(1, 2 * trans) }) end
		if panel then
			comps.set(panel, "alpha", { trans })
			comps.set(panel, "position_offset.x", { -(1 - trans) * 0.75 })
		end
	end
end

screens.register_internal(SCREEN, function(screen)
	add(screen, "Rectangle", "fader", "FaderRectangle", nil, 0, 0)
	add(screen, "Image", "panel", "PanelMedium", nil, 0.498471, 0.499512)
	local title = add(screen, "Textbox", "TimeTitle", "LargeTextbox", "panel",
		0.0012, -0.42544)
	comps.set(title, "textbox.text", { "Enhanced Arsenal" })
	comps.set(title, "align", { "HCENTER" })

	local grid = add(screen, "Aligner", "grid", nil, "panel", 0.0005, -0.0177)
	comps.set(grid, "scale", { 0.923718 })
	comps.set(grid, "aligner.area_width", { 820.385 })
	comps.set(grid, "aligner.area_height", { 362.228 })

	-- Centred both ways, which for a full 30 comes out at exactly the pak's own
	-- -0.4..0.4 and for sixteen puts three rows in the middle of the panel
	-- instead of hanging them off the top. A short last row is centred too: a
	-- row of four left-aligned under two rows of six reads as a grid that
	-- failed to finish loading.
	local total = #entries()
	local rows = math.ceil(total / #COLUMNS)
	local first_row = -((rows - 1) / 2) * ROW_STEP
	for i = 1, total do
		local row = math.floor((i - 1) / #COLUMNS)
		local in_row = math.min(#COLUMNS, total - row * #COLUMNS)
		local col = (i - 1) % #COLUMNS + 1 + math.floor((#COLUMNS - in_row) / 2)
		add(screen, "Button", "EWeapon_" .. i, "WeaponButton", "grid",
			COLUMNS[col], first_row + row * ROW_STEP)
	end

	local back = add(screen, "Button", "Back", nil, "panel", -0.0002, 0.364379)
	comps.set(back, "button.text", { "Back" })

	link_parents(screen)

	screen.env.OnKeyDown = function(key)
		if key == "ESCAPE" then screens.pop(SCREEN) end
	end
	screen.env.OnDraw = function() end
	screen.env.OnUpdate = transition(screen)
end)

--- Plate art: its own once the profile has held it, the pak's lock until then.
-- Same promise the original's grid makes, so finding a weapon still means
-- something here.
local function fill(screen)
	for i, w in ipairs(entries()) do
		local plate = screen.compmap["EWeapon_" .. i]
		if plate then
			comps.set(plate, "button.bm_icon",
				{ gallery.seen("weapon", w) and w.icon or LOCK_ICON })
		end
	end
end

-- ------------------------------------------------------------ celebration

-- The plate the unlock screen is pointing at, while it is open.
local celebrating = nil

--- Ring the newly-found weapon and throw the pak's own unlock effect at it --
-- which is what fxs/unlocked-weapon.lua exists for, and what WeaponUnlocked
-- would have done if it had a plate to aim at.
local function begin_celebration(screen, slot)
	local plate = screen.compmap["EWeapon_" .. slot]
	if not plate then return end
	local x, y, w, h = comps.screen_rect(plate)
	fx.spawn("fxs/unlocked-weapon.lua", x + w / 2, y + h / 2, 0)
end

-- ------------------------------------------------------------------ hooks

--- A button on the pak's own gallery, because that is where a player goes
-- looking for weapons. Added rather than replacing anything: the original's
-- thirty plates are still the original's thirty plates.
local function add_open_button(screen)
	if screen.compmap[OPEN_BUTTON] then return end
	local back = screen.compmap["Back"]
	if not back then return end
	local button = add(screen, "Button", OPEN_BUTTON, nil, "panel",
		0.30, 0.364379)
	comps.set(button, "button.text", { "Enhanced" })
	-- linked by hand: the screen was built and its parents resolved before
	-- this hook ran, so nothing else is going to do it for a latecomer
	button.parent = back.parent
	if button.parent then table.insert(button.parent.children, button) end
end

--- Let this screen carry a transition phase like any other UI screen.
--
-- `screens.load` pins every internal screen at phase 0 and marks it
-- `no_phase`, because the two the engine ships -- the Title splash and the
-- GameCrimsonland backdrop -- are not UI at all and must not count as depth.
-- This one *is* UI, and the pin has a consequence that is invisible until you
-- look at a rendered frame: `GetStackDepthOffset` sums the transition phase of
-- every screen above a given one, so a screen pinned at zero is a screen
-- nothing below it knows is there. The gallery underneath went on drawing
-- itself at full strength, and thirty plates showed through sixteen.
--
-- Cleared here rather than in the builder because `screens.load` sets the pin
-- *after* calling it.
local function unpin(screen)
	screen.no_phase = false
end

function arsenal.on_screen_enter(screen_name, screen)
	if screen_name == PAK_GALLERY then
		add_open_button(screen)
	elseif screen_name == SCREEN then
		unpin(screen)
		fill(screen)
		-- Opened with a slot number, this screen is a celebration and
		-- dismisses on any click; opened without one it is the collection and
		-- only Back leaves. One field says which, set here and nowhere else,
		-- so leaving by Back cannot strand it in the other mode.
		celebrating = tonumber(screen.parm)
		if celebrating then begin_celebration(screen, celebrating) end
	end
end

local TIP_W = 380
local TIP_PAD = 10

local function wrap(text, width)
	local lines, line = {}, ""
	for word in tostring(text):gmatch("%S+") do
		local try = (line == "") and word or (line .. " " .. word)
		if font.measure(F_SMALL, try) > width and line ~= "" then
			lines[#lines + 1] = line
			line = word
		else
			line = try
		end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

local function tooltip(screen, hovered, title, detail, colour)
	local panel = screen.compmap["panel"]
	if not panel then return end
	local px, py, pw, ph = comps.screen_rect(panel)
	local hx, hy, hw, hh = comps.screen_rect(hovered)
	local lines = wrap(detail, TIP_W - TIP_PAD * 2)
	local h = TIP_PAD * 2 + 26 + #lines * 20
	local x = math.min(hx + hw / 2, px + pw - TIP_W - 20)
	local y = hy + hh + 8
	if y + h > py + ph - 20 then y = hy - h - 8 end
	x = math.max(x, px + 20)

	love.graphics.setColor(0.04, 0.04, 0.05, 0.92)
	love.graphics.rectangle("fill", x, y, TIP_W, h)
	love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 0.5)
	love.graphics.rectangle("line", x, y, TIP_W, h)
	love.graphics.setColor(1, 1, 1, 1)

	font.draw(F_MEDIUM, title, x + TIP_PAD, y + TIP_PAD - 2, colour or BONE)
	local ty = y + TIP_PAD + 26
	for _, line in ipairs(lines) do
		font.draw(F_SMALL, line, x + TIP_PAD, ty, DIM)
		ty = ty + 20
	end
end

-- ASCII only: the .mft faces are LATIN-1, so a UTF-8 dash arrives as its first
-- byte and draws as a stray accented letter.
local UNDISCOVERED = "Undiscovered. Weapons are found in the field - pick this "
	.. "one up and it takes its place here."

function arsenal.on_screen_draw(screen_name, screen)
	if screen_name ~= SCREEN then return end

	local panel = screen.compmap["panel"]
	local list = entries()
	if panel then
		local seen = 0
		for _, w in ipairs(list) do
			if gallery.seen("weapon", w) then seen = seen + 1 end
		end
		local text = ("%d / %d discovered"):format(seen, #list)
		local px, py, pw, ph = comps.screen_rect(panel)
		font.draw(F_SMALL, text, px + (pw - font.measure(F_SMALL, text)) / 2,
			py + ph - 52, DIM)
	end

	local hover = screen._hover_comp
	local n = hover and hover.name:match("^EWeapon_(%d+)$")
	local entry = n and arsenal.entry_at(tonumber(n))
	if not entry then return end
	if not gallery.seen("weapon", entry) then
		tooltip(screen, hover, "???", UNDISCOVERED, DIM)
	else
		tooltip(screen, hover, entry.name, BLURB[entry.id] or "", BRASS)
	end
end

--- Returns true when the click was this screen's own.
function arsenal.on_ui_click(screen_name, comp_name)
	if screen_name == PAK_GALLERY and comp_name == OPEN_BUTTON then
		screens.push(SCREEN)
		return true
	end
	if screen_name ~= SCREEN then return false end
	if comp_name == "Back" or celebrating then
		-- a celebration dismisses on a click anywhere, as the pak's own unlock
		-- screens do; the collection leaves by its button
		celebrating = nil
		screens.pop(SCREEN)
	end
	return true
end

-- --------------------------------------------------------- first sight

--- `unlocks.saw_weapon` pushes WeaponUnlocked at the weapon's own index, and
-- the pak's grid has no plate past thirty. So a weapon of ours celebrates on
-- our own grid instead. Patched here rather than in vanilla for the same
-- reason mods/allweapons patches the unlock predicates: the blast radius is
-- this cartridge's profile, and vanilla keeps behaving as it always did.
local saw_weapon = unlocks.saw_weapon

function arsenal.install()
	unlocks.saw_weapon = function(weapon)
		local slot = arsenal.slot_of(weapon)
		if not slot then return saw_weapon(weapon) end
		if not save.mark_seen("weapons", weapon.id) then return end
		screens.push(SCREEN, slot)
	end
end

return arsenal

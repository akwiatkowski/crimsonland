-- The weapon and perk galleries (Extras -> Weapons / Perks).
--
-- Both layouts are complete grids already: 30 weapon plates and 56 perk
-- plates, each carrying its own `button.bm_icon`. Once the engine draws that
-- property (src/engine/comps.lua) the art appears by itself, and what is left
-- is what the C++ side put underneath — what the thing you are pointing at is.
--
-- The plates ship in their locked state: most carry ui/gfx/lock-small.png,
-- which the C++ side swapped for the real icon as the player unlocked things.
-- The save records first sight of every weapon and perk (game/unlocks.lua, for
-- the celebration screens), so the grid can work that way here too: a plate is
-- its own art once you have met the thing, and the shipped lock until then.
-- Slot index lines up with weapons.xml order exactly (verified against every
-- plate the layout does declare).

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")
local font = require("src.engine.font")
local perks = require("mods.vanilla.game.perks")
local save = require("mods.vanilla.game.save")

local gallery = {}

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

local BONE = { 0.88, 0.85, 0.78, 1 }
local BRASS = { 0.85, 0.68, 0.28, 1 }
local DIM = { 0.55, 0.53, 0.5, 1 }
local UNIMPLEMENTED = { 0.35, 0.35, 0.35, 1 }

--- Entry behind slot `index` of a gallery: the grids are in data order. The
-- unlock screens use the same grids, so this is shared with game/unlocks.
function gallery.entry_at(kind, index)
	if kind == "weapon" then
		data.load_all()
		return data.weapon_order[index]
	end
	return perks.get(index)
end

function gallery.slot_index(comp, prefix)
	local n = comp and comp.name:match("^" .. prefix .. "_(%d+)$")
	return n and tonumber(n) or nil
end

local LOCK_ICON = "ui/gfx/lock-small.png"

--- Has this profile met `entry` yet? First sight is recorded when a weapon is
-- picked up or a perk taken, in any mode (game/unlocks.lua).
function gallery.seen(kind, entry)
	if not entry or entry.id == nil then return false end
	local set = save.game.seen[kind == "weapon" and "weapons" or "perks"]
	return set ~= nil and set[entry.id] == true
end

--- Put every slot into one of three states:
--   seen           its own art, and full details on hover
--   undiscovered   the lock the plate ships with, and no details
--   unimplemented  dimmed, with the reason on its tooltip
--
-- Dimmed rather than hidden, because a hole in the original's grid would read
-- as a bug — and distinct from the lock, because "you have not found this yet"
-- and "this port cannot serve this" are different promises to the player.
function gallery.fill(screen, prefix, kind)
	for _, comp in ipairs(screen.comps) do
		local i = gallery.slot_index(comp, prefix)
		if i then
			local entry = gallery.entry_at(kind, i)
			if entry and entry.unimplemented then
				for _, s in ipairs({ "idle", "over", "pressed" }) do
					comps.set(comp, "button.bitmap_color_" .. s, UNIMPLEMENTED)
				end
				comps.set(comp, "button.bm_icon", { entry.icon })
			elseif not (entry and entry.icon) then
				for _, s in ipairs({ "idle", "over", "pressed" }) do
					comps.set(comp, "button.bitmap_color_" .. s, UNIMPLEMENTED)
				end
			elseif gallery.seen(kind, entry) then
				comps.set(comp, "button.bm_icon", { entry.icon })
			else
				-- set it rather than trust the layout: a few plates ship
				-- carrying their real icon already
				comps.set(comp, "button.bm_icon", { LOCK_ICON })
			end
		end
	end
end

--- "12 / 30 discovered", under the grid. The layouts have no textbox for it —
-- the C++ side drew the whole panel — so it goes on with the panel's own font.
local function draw_progress(screen, prefix, kind)
	local panel = screen.compmap["panel"]
	if not panel then return end
	local seen, total = 0, 0
	for _, comp in ipairs(screen.comps) do
		local i = gallery.slot_index(comp, prefix)
		local entry = i and gallery.entry_at(kind, i)
		-- what this port cannot serve is not part of the count: it can never
		-- be discovered, so counting it would make 100% unreachable
		if entry and entry.icon and not entry.unimplemented then
			total = total + 1
			if gallery.seen(kind, entry) then seen = seen + 1 end
		end
	end
	if total == 0 then return end
	local text = ("%d / %d discovered"):format(seen, total)
	local px, py, pw, ph = comps.screen_rect(panel)
	-- clear of the frame's bottom bar, which the panel rect includes
	font.draw(F_SMALL, text, px + (pw - font.measure(F_SMALL, text)) / 2,
		py + ph - 52, DIM)
end

function gallery.prepare(screen_name, screen)
	if screen_name == "Weapons" then
		gallery.fill(screen, "Weapon", "weapon")
	elseif screen_name == "Perks" then
		gallery.fill(screen, "Perk", "perk")
	end
end

local TIP_W = 380 -- fits the widest perk name in the medium face
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

--- A tooltip beside the plate under the pointer. The grid fills the panel from
-- under the heading down to the Back button, so there is no free band to put a
-- fixed info line in — and a perk description is far too long for one anyway.
local function tooltip(screen, hovered, title, detail, title_color)
	local panel = screen.compmap["panel"]
	if not panel then return end
	local px, py, pw, ph = comps.screen_rect(panel)
	local hx, hy, hw, hh = comps.screen_rect(hovered)

	local lines = wrap(detail, TIP_W - TIP_PAD * 2)
	local h = TIP_PAD * 2 + 26 + #lines * 20
	-- prefer below-right of the plate, but keep the whole tip inside the panel
	local x = math.min(hx + hw / 2, px + pw - TIP_W - 20)
	local y = hy + hh + 8
	if y + h > py + ph - 20 then y = hy - h - 8 end
	x = math.max(x, px + 20)

	love.graphics.setColor(0.04, 0.04, 0.05, 0.92)
	love.graphics.rectangle("fill", x, y, TIP_W, h)
	love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 0.5)
	love.graphics.rectangle("line", x, y, TIP_W, h)
	love.graphics.setColor(1, 1, 1, 1)

	font.draw(F_MEDIUM, title, x + TIP_PAD, y + TIP_PAD - 2, title_color or BONE)
	local ty = y + TIP_PAD + 26
	for _, line in ipairs(lines) do
		font.draw(F_SMALL, line, x + TIP_PAD, ty, DIM)
		ty = ty + 20
	end
end

-- ASCII only: the .mft faces are LATIN-1, so a UTF-8 dash arrives as its
-- first byte and draws as a stray accented letter.
local UNDISCOVERED = {
	weapon = "Undiscovered. Weapons are found in the field - pick this one up "
		.. "and it takes its place here.",
	perk = "Undiscovered. Take this perk on a level-up and it takes its place "
		.. "here.",
}

function gallery.draw(screen_name, screen)
	local prefix, kind
	if screen_name == "Weapons" then
		prefix, kind = "Weapon", "weapon"
	elseif screen_name == "Perks" then
		prefix, kind = "Perk", "perk"
	else
		return
	end
	draw_progress(screen, prefix, kind)

	local hover = screen._hover_comp
	local i = hover and gallery.slot_index(hover, prefix)
	if not i then return end
	local entry = gallery.entry_at(kind, i)

	if not (entry and entry.icon) then
		if kind == "perk" then
			tooltip(screen, hover, "Not in this port",
				"This slot is empty in the original's own perk table.", DIM)
		end
	elseif entry.unimplemented then
		tooltip(screen, hover, entry.name .. " (not in this port)",
			entry.unimplemented, DIM)
	elseif not gallery.seen(kind, entry) then
		-- the name is the reward for finding it, so it stays hidden too
		tooltip(screen, hover, "???", UNDISCOVERED[kind], DIM)
	elseif kind == "weapon" then
		tooltip(screen, hover, entry.name or "?",
			("Damage %.0f, clip %d, %.1f shots/sec, %.1fs reload."):format(
				entry.damage_effective or 0, entry.clip_size or 0,
				entry.shoot_interval > 0 and 1 / entry.shoot_interval or 0,
				entry.reload_time or 0), BRASS)
	else
		tooltip(screen, hover, entry.name, entry.desc or "", BRASS)
	end
end

return gallery

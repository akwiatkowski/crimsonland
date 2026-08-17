-- The weapon and perk galleries (Extras -> Weapons / Perks).
--
-- Both layouts are complete grids already: 30 weapon plates and 56 perk
-- plates, each carrying its own `button.bm_icon`. Once the engine draws that
-- property (src/engine/comps.lua) the art appears by itself, and what is left
-- is what the C++ side put underneath — what the thing you are pointing at is.
--
-- The plates ship in their locked state: most carry ui/gfx/lock-small.png,
-- which the C++ side swapped for the real icon as the player unlocked things.
-- This port has no per-weapon unlock — guns arrive as drops, gated by chapter
-- through game.weapon_cap — so the grid is filled in as a reference instead.
-- Slot index lines up with weapons.xml order exactly (verified against every
-- plate the layout does declare).

local comps = require("src.engine.comps")
local data = require("src.game.data")
local font = require("src.engine.font")
local perks = require("src.game.perks")

local gallery = {}

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

local BONE = { 0.88, 0.85, 0.78, 1 }
local BRASS = { 0.85, 0.68, 0.28, 1 }
local DIM = { 0.55, 0.53, 0.5, 1 }
local UNIMPLEMENTED = { 0.35, 0.35, 0.35, 1 }

--- Entry behind slot `index` of a gallery: the grids are in data order. The
-- unlock screens use the same grids, so this is shared with src/game/unlocks.
function gallery.entry_at(kind, index)
	if kind == "weapon" then
		data.load_all()
		return data.weapon_order[index]
	end
	return perks.list[index]
end

function gallery.slot_index(comp, prefix)
	local n = comp and comp.name:match("^" .. prefix .. "_(%d+)$")
	return n and tonumber(n) or nil
end

--- Put every slot's real art on it, and dim the ones this port cannot serve
-- (the original ships 56 perks; the roster in perks.lua implements 25). Dimmed
-- rather than hidden: a hole in the original's grid would read as a bug.
function gallery.fill(screen, prefix, kind)
	for _, comp in ipairs(screen.comps) do
		local i = gallery.slot_index(comp, prefix)
		if i then
			local entry = gallery.entry_at(kind, i)
			if entry and entry.icon then
				comps.set(comp, "button.bm_icon", { entry.icon })
			else
				for _, s in ipairs({ "idle", "over", "pressed" }) do
					comps.set(comp, "button.bitmap_color_" .. s, UNIMPLEMENTED)
				end
			end
		end
	end
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

function gallery.draw(screen_name, screen)
	local hover = screen._hover_comp
	if not hover then return end

	if screen_name == "Weapons" then
		local i = gallery.slot_index(hover, "Weapon")
		local w = i and gallery.entry_at("weapon", i)
		if not w then return end
		tooltip(screen, hover, w.name or "?",
			("Damage %.0f, clip %d, %.1f shots/sec, %.1fs reload."):format(
				w.damage_effective or 0, w.clip_size or 0,
				w.shoot_interval > 0 and 1 / w.shoot_interval or 0,
				w.reload_time or 0), BRASS)
	elseif screen_name == "Perks" then
		local i = gallery.slot_index(hover, "Perk")
		if not i then return end
		local p = gallery.entry_at("perk", i)
		if p then
			tooltip(screen, hover, p.name, p.desc or "", BRASS)
		else
			tooltip(screen, hover, "Not in this port yet",
				"The original ships 56 perks; this port implements 25.", DIM)
		end
	end
end

return gallery

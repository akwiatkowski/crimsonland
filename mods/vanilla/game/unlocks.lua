-- "New weapon unlocked" / "New perk unlocked" celebrations.
--
-- The pak ships both screens fully laid out and the port never showed them.
-- Each is the same grid the galleries use, plus two comps the C++ side drove:
--   Selector  an Image parented to whichever plate is the new one
--   PartPool  an Emitter whose effect is fxs/unlocked-weapon.lua (or -perk),
--             which is what those effect files were always for
--
-- Trigger is first sight: the first time a weapon is picked up, or a perk is
-- taken, in any mode. The save remembers, so it happens once per profile.

local comps = require("src.engine.comps")
local font = require("src.engine.font")
local fx = require("src.engine.fx")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")

local unlocks = {}

local BRASS = { 0.85, 0.68, 0.28, 1 }
local DIM = { 0.7, 0.7, 0.7, 0.8 }
local F_MEDIUM = "fonts/medium.mft"
local F_SMALL = "fonts/small.mft"
local DISMISS = "Click anywhere to continue"

local SCREENS = {
	WeaponUnlocked = {
		kind = "weapon", prefix = "Weapon", effect = "fxs/unlocked-weapon.lua",
	},
	PerkUnlocked = {
		kind = "perk", prefix = "Perk", effect = "fxs/unlocked-perk.lua",
	},
}

--- Show the screen for `index` in the weapon or perk grid. The index rides on
-- the screen's parm, which is what the engine's push() carries it for.
function unlocks.show(screen_name, index)
	require("src.engine.screens").push(screen_name, index)
end

function unlocks.prepare(screen_name, screen)
	local def = SCREENS[screen_name]
	if not def then return end
	local index = tonumber(screen.parm) or 1

	gallery.fill(screen, def.prefix, def.kind)

	-- point the selector at the new one by re-parenting it, which is how the
	-- layout aims it in the first place (it ships parented to an arbitrary plate)
	local plate = screen.compmap[def.prefix .. "_" .. index]
	local selector = screen.compmap["Selector"]
	if plate and selector then
		if selector.parent then
			for i, c in ipairs(selector.parent.children) do
				if c == selector then table.remove(selector.parent.children, i) break end
			end
		end
		selector.parent = plate
		table.insert(plate.children, selector)
		comps.set(selector, "align", { plate.props.align })
		comps.set(selector, "position", { 0, 0 })
	end

	if plate then
		local x, y, w, h = comps.screen_rect(plate)
		fx.spawn(def.effect, x + w / 2, y + h / 2, 0)
	end
end

--- Name of the thing, under the grid. The layouts have no textbox for it —
-- the C++ side drew it — so it goes on with the panel's own font.
function unlocks.draw(screen_name, screen)
	local def = SCREENS[screen_name]
	if not def then return end
	local entry = gallery.entry_at(def.kind, tonumber(screen.parm) or 1)
	local panel = screen.compmap["panel"]
	if not entry or not panel then return end
	local px, py, pw, ph = comps.screen_rect(panel)
	local name = entry.name or ""
	font.draw(F_MEDIUM, name, px + (pw - font.measure(F_MEDIUM, name)) / 2,
		py + ph - 78, BRASS)
	-- the screen has no button to leave by, so it has to say how you leave
	font.draw(F_SMALL, DISMISS, px + (pw - font.measure(F_SMALL, DISMISS)) / 2,
		py + ph - 50, DIM)
end

--- These screens carry no button at all: any click dismisses.
function unlocks.on_click(screen_name)
	if not SCREENS[screen_name] then return false end
	require("src.engine.screens").pop(screen_name)
	return true
end

-- ------------------------------------------------------------ first sight

--- Record a weapon as seen; shows the screen the first time. Index is the
-- weapon's slot in weapons.xml order, which is what the grid is keyed on.
function unlocks.saw_weapon(weapon)
	if not weapon or not weapon.index then return end
	if save.mark_seen("weapons", weapon.id) then
		unlocks.show("WeaponUnlocked", weapon.index)
	end
end

--- A perk's id is the original's own index for it, which is also its grid slot
-- and its icon number — so there is nothing to look up.
function unlocks.saw_perk(perk)
	if not perk then return end
	if save.mark_seen("perks", perk.id) then
		unlocks.show("PerkUnlocked", perk.index)
	end
end

return unlocks

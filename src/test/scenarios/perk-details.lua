-- Clicking a perk plate opens the screen the pak ships for it.
--
--   make test SCENARIO=perk-details CL_PERK=1
--
-- ui/perk-details.lua holds the whole description at reading size beside the
-- perk's plate-sized icon, and nothing could push it. The grid answered a click
-- with nothing, and the tooltip wrapped a fifty-word perk into a 380-pixel box.
--
-- It is also the only screen that draws perks/large/ -- sixty icons the pak
-- ships and the port never put on screen, because the grids want the small set.
--
-- CL_PERK defaults to 1 and not 28: the layout stores its placeholders as perk
-- 28's own values -- "Doctor", the Doctor's full description, and
-- perks/large/perk_28.png -- so slot 28 passes every check on a screen nothing
-- ever touched.

local comps = require("src.engine.comps")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")

local SLOT = tonumber(os.getenv("CL_PERK") or "1")

local shown = nil

local function meet_it()
	local p = gallery.entry_at("perk", SLOT)
	if p then save.mark_seen("perks", p.id) end
end

local function look()
	local top = screens.top()
	if not top then return end
	local function text(name)
		local c = top.compmap[name]
		local t = c and comps.get(c, "textbox.text")
		if type(t) == "table" then t = t[1] end
		return t and tostring(t) or nil
	end
	local function bitmap(name)
		local c = top.compmap[name]
		local b = c and comps.get(c, "image.bitmap")
		if type(b) == "table" then b = b[1] end
		return b and tostring(b) or nil
	end
	shown = {
		screen = top.name,
		name = text("PerkName"),
		desc = text("PerkDesc"),
		icon = bitmap("PerkIcon"),
	}
	print(("[details] %s name=%q icon=%s desc=%q"):format(
		shown.screen, shown.name or "", tostring(shown.icon),
		(shown.desc or ""):sub(1, 40)))
end

return {
	{ t = 2.0, run = meet_it },
	{ t = 2.5, click = "Extras" },
	{ t = 4.0, click = "Perks" },
	{ t = 5.5, hover = "Perk_" .. SLOT },
	{ t = 6.5, click = "Perk_" .. SLOT },
	{ t = 8.0, run = look },

	{ t = 8.1, expect = function()
		if not shown then return false, "nothing was read" end
		-- The pak's grid is 56 plates and the roster is 55 perks, so the last
		-- plate has nothing behind it. That is the original's own layout and
		-- the gallery already dims it -- so the claim here is the gallery's
		-- rule rather than "every plate opens": a plate with a perk behind it
		-- opens the screen, and a plate without one does nothing at all. The
		-- second half matters as much: an empty details screen is worse than
		-- no details screen.
		local p = gallery.entry_at("perk", SLOT)
		if not (p and p.icon) then
			if shown.screen == "PerkDetails" then
				return false, ("plate %d has no perk and opened details anyway"):format(SLOT)
			end
			return true, ("plate %d is empty in the pak's grid, and stayed shut"):format(SLOT)
		end
		if shown.screen ~= "PerkDetails" then
			return false, ("clicking plate %d left %s on top"):format(SLOT, shown.screen)
		end
		return true, "PerkDetails opened"
	end },
	{ t = 8.2, expect = function()
		local p = gallery.entry_at("perk", SLOT)
		if not (p and p.icon) then
			return true, ("nothing to check for empty plate %d"):format(SLOT)
		end
		if shown.name ~= p.name then
			return false, ("name reads %q, the roster says %q"):format(
				tostring(shown.name), tostring(p.name))
		end
		-- the description may carry the port's "not here" note on the end, so
		-- the roster's own text has to be the start of it and not all of it
		if not (shown.desc and p.desc and shown.desc:sub(1, #p.desc) == p.desc) then
			return false, ("description is not this perk's: %q"):format(
				tostring(shown.desc):sub(1, 50))
		end
		if shown.icon ~= p.icon_large then
			return false, ("icon is %s, wanted %s"):format(
				tostring(shown.icon), tostring(p.icon_large))
		end
		return true, ("%s: %d chars, %s"):format(p.name, #shown.desc, shown.icon)
	end },
	{ t = 8.3, expect = function()
		if shown.screen ~= "PerkDetails" then
			return true, ("no icon to resolve for plate %d"):format(SLOT)
		end
		-- the large art has to exist, or the screen shows an empty frame and
		-- the bitmap name alone would not have noticed
		local img = require("src.engine.assets").image(shown.icon)
		if not img then
			return false, ("%s does not resolve to an image"):format(tostring(shown.icon))
		end
		return true, ("%s is %dx%d"):format(shown.icon, img:getWidth(), img:getHeight())
	end },
}

-- Clicking a weapon plate opens the screen the pak ships for it.
--
--   make test SCENARIO=weapon-details CL_WEAPON=2
--
-- ui/weapon-details.lua is 110 lines of layout -- a name, the ammo cell's own
-- icon, a clip size and four bars -- and nothing in the pak or the port could
-- push it. The grid answered a click with nothing at all.
--
-- Read off the comps rather than off the data: the parse being right says
-- nothing about whether it reaches the screen, which is the whole failure this
-- covers. The plate has to be one the profile has met, because an unmet plate
-- is a lock and a lock has nothing to show -- so the scenario marks the weapon
-- seen first, the way picking one up would.

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")
local details = require("mods.vanilla.game.details")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")

-- The default is deliberately not slot 2. The layout stores its placeholders as
-- the assault rifle's real values -- "Assault Rifle" (line 28), clip "25" (line
-- 79), ammo weapons/ammo/545.png (line 85) -- so slot 2 passes every check on an
-- untouched screen and proves nothing. Slot 12 is the rocket launcher: a
-- different name, a clip of 5 and its own ammo cell, none of them the stored
-- value. Slot 31 is the Shrinkifier, which the 30-plate grid has no plate for
-- and no click can reach.
local SLOT = tonumber(os.getenv("CL_WEAPON") or "12")

local shown = nil

local function meet_it()
	-- first sight is what unlocks a plate; a run would do this by picking the
	-- weapon up (game/unlocks.lua)
	data.load_all()
	local w = data.weapon_order[SLOT]
	if w then save.mark_seen("weapons", w.id) end
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
	local function slider(name)
		local c = top.compmap[name]
		return c and comps.get(c, "slider.value") or nil
	end
	local function bitmap(name)
		local c = top.compmap[name]
		local b = c and comps.get(c, "image.bitmap")
		if type(b) == "table" then b = b[1] end
		return b and tostring(b) or nil
	end
	shown = {
		screen = top.name,
		name = text("WeaponName"),
		clip = text("ClipSize"),
		ammo = bitmap("ammo_type"),
		accuracy = slider("slider_accuracy"),
		damage = slider("slider_damage"),
		fire_rate = slider("slider_fire_rate"),
		reload = slider("slider_reload_time"),
	}
	print(("[details] %s name=%q clip=%s ammo=%s acc=%.2f dmg=%.2f rate=%.2f reload=%.2f"):format(
		shown.screen, shown.name or "", tostring(shown.clip), tostring(shown.ammo),
		shown.accuracy or -1, shown.damage or -1, shown.fire_rate or -1, shown.reload or -1))
end

return {
	{ t = 2.0, run = meet_it },
	{ t = 2.5, click = "Extras" },
	{ t = 4.0, click = "Weapons" },
	-- hovering first, because the tooltip is meant to survive this change:
	-- the grid is read by sweeping it and opened by clicking one
	{ t = 5.5, hover = "Weapon_" .. SLOT },
	{ t = 6.5, click = "Weapon_" .. SLOT },
	{ t = 8.0, run = look },

	{ t = 8.1, expect = function()
		if not shown then return false, "nothing was read" end
		if shown.screen ~= "WeaponDetails" then
			return false, ("clicking plate %d left %s on top"):format(SLOT, shown.screen)
		end
		return true, "WeaponDetails opened"
	end },
	{ t = 8.2, expect = function()
		local w = data.weapon_order[SLOT]
		if not w then return false, ("no weapon in slot %d"):format(SLOT) end
		if shown.name ~= w.name then
			return false, ("name reads %q, the data says %q"):format(
				tostring(shown.name), tostring(w.name))
		end
		if shown.clip ~= tostring(w.clip_size) then
			return false, ("clip reads %s, the data says %d"):format(
				tostring(shown.clip), w.clip_size)
		end
		if shown.ammo ~= w.ammo_icon then
			return false, ("ammo icon is %s, the data says %s"):format(
				tostring(shown.ammo), tostring(w.ammo_icon))
		end
		return true, ("%s: clip %s, ammo %s"):format(w.name, shown.clip, shown.ammo)
	end },
	{ t = 8.3, expect = function()
		local w = data.weapon_order[SLOT]
		local want = details.bars(w)
		local bad = {}
		for comp_name, expected in pairs(want) do
			local got = ({ slider_accuracy = shown.accuracy, slider_damage = shown.damage,
				slider_fire_rate = shown.fire_rate,
				slider_reload_time = shown.reload })[comp_name]
			if not got then
				bad[#bad + 1] = comp_name .. " has no value"
			elseif math.abs(got - expected) > 0.001 then
				bad[#bad + 1] = ("%s is %.3f, wanted %.3f"):format(comp_name, got, expected)
			end
		end
		table.sort(bad)
		if #bad > 0 then return false, table.concat(bad, "; ") end
		-- a bar at zero across the board would pass the comparison above and
		-- still be a screen showing nothing
		if (shown.accuracy + shown.damage + shown.fire_rate + shown.reload) <= 0 then
			return false, "all four bars are empty"
		end
		return true, ("four bars: %.2f %.2f %.2f %.2f"):format(
			shown.accuracy, shown.damage, shown.fire_rate, shown.reload)
	end },
}

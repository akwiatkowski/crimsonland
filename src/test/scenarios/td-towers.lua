-- Mounts, slice three (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-towers
--
-- The whole point of the slice in one run: walk to a plot, build it, bolt a
-- weapon on, walk away, and watch it kill things without you. The last report
-- is the one that matters — mount kills accumulating while the player stands
-- at the base doing nothing is the definition of a tower working.
--
-- It also exercises the tier gate: a light mount is offered the Plasma Rifle
-- and must refuse it (TOO HEAVY in the armoury), because a cannon needs the
-- reinforced mount that costs another $600.

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

--- Park the player somewhere and stop them shooting, so what the mount does is
-- the only thing moving the numbers.
local function stand_at(getpos)
	return function()
		local f = require("mods.towerdefence.game.field")
		local x, y = getpos(f)
		f.player.x, f.player.y = x, y
		require("mods.vanilla.game.input").set_controller(function()
			return { dx = 0, dy = 0, aim_x = f.player.x + 50, aim_y = f.player.y,
				fire = false, reload = false }
		end)
	end
end

local at_plot = stand_at(function(f) return f.plots[1].x, f.plots[1].y end)

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local p = f.plots[1]
		print(string.format(
			"[towers] %-9s $%d built=%s tier=%d weapon=%s ammo=%d target=%s mountkills=%d total=%d",
			tag, f.money, tostring(p.built), p.tier,
			p.weapon and p.weapon.id or "none", p.ammo,
			p.target and "yes" or "no", p.kills or 0, f.kills))
	end
end

return {
	{ t = 2.5, click = "PlayMenu" },
	-- the mod has its own front door now: Play opens it, this starts the run
	{ t = 3.5, click = "NewRun" },
	{ t = 3.0, run = take_over },

	-- three waves of income first: a mount plus a weapon is more than the
	-- opening $250 covers, which is the economy working as modelled
	{ t = 130.0, run = report("earned") },

	{ t = 135.0, run = at_plot },
	{ t = 137.0, key = "e" },
	{ t = 138.0, click = "Build" }, -- $250
	{ t = 139.0, run = report("built") },

	{ t = 140.0, click = "Arm" }, -- into the armoury, in mount mode
	{ t = 141.5, click = "Weapon_9" }, -- Plasma Rifle: refused, too heavy for tier 1
	{ t = 142.5, run = report("refused") },
	{ t = 143.5, click = "Weapon_2" }, -- Assault Rifle: owned already, fits
	{ t = 144.5, run = report("armed") },
	-- leave the mount screen, or the field stays paused under it and the mount
	-- has nothing to shoot at (which is what the first run of this measured)
	{ t = 145.0, click = "Leave" },

	-- Hand the field back to the defender AI: with nobody holding the line at
	-- all the base falls in half a minute and the mount never gets to prove
	-- anything (which is exactly what the first run of this scenario showed).
	-- The mount's own kill count is what separates its work from the AI's.
	{ t = 146.0, run = take_over },
	{ t = 175.0, run = report("working") },
	{ t = 205.0, run = report("working2") },

	-- the other half of the tier gate: $600 turns the light mount into one
	-- that would accept the cannon it refused earlier
	{ t = 206.0, run = at_plot },
	{ t = 208.0, key = "e" },
	{ t = 209.0, click = "Upgrade" },
	{ t = 210.0, run = report("upgraded") },
	{ t = 211.0, click = "Leave" },
	captures = { 139.5, 142.0, 190.0 },
}

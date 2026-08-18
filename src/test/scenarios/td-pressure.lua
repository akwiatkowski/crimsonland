-- Three rules that only exist together (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-pressure
--
--   1. SHOPPING COSTS TIME. A shop screen no longer freezes the field, so
--      standing at the counter mid-wave means nobody is holding the line.
--   2. THE OUTER RING IS EARNED. Building on it is refused until four inner
--      mounts stand, whatever the money says.
--   3. A RUN LEAVES SOMETHING BEHIND — the wave reached, in this mod's own
--      profile (checked by td-cards and by the end panel, not here).

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

--- Park the player somewhere with their hands down.
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

local at_base = stand_at(function(f) return f.base.x, f.base.y end)
-- plots 9..16 are the outer ring
local at_outer = stand_at(function(f) return f.plots[9].x, f.plots[9].y end)

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local built, outer_built = 0, 0
		for _, p in ipairs(f.plots) do
			if p.built then
				built = built + 1
				if p.outer then outer_built = outer_built + 1 end
			end
		end
		print(string.format(
			"[pressure] %-9s t=%.0f wave=%d base=%d $%d mounts=%d(outer %d) screen=%s",
			tag, f.time, f.wave, math.floor(f.base.hp), f.money, built, outer_built,
			(require("src.engine.screens").top() or {}).name or "?"))
	end
end

return {
	{ t = 2.5, click = "PlayMenu" },

	-- RULE 2, checked first: during the opening lull nothing is on the field,
	-- so the player is certainly alive and standing where they were put. The
	-- gate is tested before the price is, so $250 in the till cannot muddy it.
	{ t = 6.0, run = at_outer },
	{ t = 8.0, key = "e" },
	{ t = 9.0, run = report("at-mount") },
	{ t = 10.0, click = "Build" }, -- refused: no inner mounts stand yet
	{ t = 11.0, run = report("refused") },
	{ t = 12.0, click = "Leave" },
	{ t = 13.0, run = take_over },

	-- RULE 1. The proof is `t` itself: before the fix the field's clock stopped
	-- dead under any screen, so these two reports would carry the same time.
	-- Base health moving is a bonus -- that depends on where the wave happens
	-- to be, the clock does not. Twelve seconds, because standing at a counter
	-- during a wave gets the player killed, and dying closes the shop.
	{ t = 40.0, run = at_base },
	{ t = 42.0, key = "e" },
	{ t = 43.0, run = report("shopping") },
	{ t = 55.0, run = report("still-in") },
	{ t = 56.0, click = "Close" },
	{ t = 57.0, run = take_over },
	{ t = 75.0, run = report("back-out") },
	captures = { 9.5, 44.0, 55.5 },
}

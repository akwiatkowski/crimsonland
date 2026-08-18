-- A run that ends, so the thing it leaves behind can be checked (needs
-- MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-fall
--
-- Nobody defends: the player stands on the base with their hands down and the
-- waves take it apart. That is the only cheap way to reach the end of a run,
-- and the end is the point — the wave reached is this mod's entire score, so
-- it has to survive the process that produced it.
--
-- Run it TWICE. The first run writes a best wave; the second must report that
-- number at t=6, before it has played anything, which is the proof the profile
-- was read back rather than started fresh. (The profile is this mod's own:
-- Crimsonland-Test/mods/towerdefence/save.lua.)

local function stand_down()
	local f = require("mods.towerdefence.game.field")
	f.player.x, f.player.y = f.base.x, f.base.y
	require("mods.vanilla.game.input").set_controller(function()
		return { dx = 0, dy = 0, aim_x = f.player.x + 50, aim_y = f.player.y,
			fire = false, reload = false }
	end)
end

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local p = f.progress()
		print(string.format(
			"[fall] %-7s t=%.0f wave=%d base=%d over=%s | profile: best=%d kills=%d runs=%d",
			tag, f.time, f.wave, math.floor(f.base.hp), tostring(f.over),
			p.best_wave, p.best_kills, p.runs))
	end
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, run = stand_down },
	{ t = 6.0, run = report("loaded") }, -- what a previous run left behind
	{ t = 90.0, run = report("losing") },
	{ t = 180.0, run = report("late") },
	{ t = 260.0, run = report("ended") }, -- the base should be gone by here
	captures = { 260.5 },
}

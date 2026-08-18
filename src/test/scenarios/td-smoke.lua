-- Smoke test for the tower-defence mod's first slice (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-smoke
--
-- Play on the main menu starts a run — there is no menu of its own yet. The
-- run opens in a lull, so the first capture must show the wave preview and a
-- full base; by the later ones the wave has arrived, the AI is fighting it,
-- and the [td] lines must show creatures on the field and money going up.
--
-- What a broken run looks like in the log: base HP falling during the lull
-- (creatures spawning too early), money never moving (kills not paying), or
-- wave stuck at 1 with 0 inbound and 0 alive (the clear check never firing).

-- The mod's own defender AI, not vanilla's: vanilla's plays Crimsonland and
-- lets everything it has not aggroed walk past to the base, which measures the
-- AI rather than the balance (mods/towerdefence/game/ai_defender.lua).
local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

local function report()
	local f = require("mods.towerdefence.game.field")
	print(string.format(
		"[td] t=%.1f wave=%d lull=%.1f queue=%d alive=%d base=%d hp=%d $%d kills=%d shots=%d",
		f.time, f.wave, f.lull, f.wave_queue, #f.creatures,
		math.floor(f.base.hp), math.floor(f.player.hp), f.money, f.kills, f.shots))
end

-- Runs long enough to cross the line the economy model draws: waves 1-3 ask
-- less throughput than the starting rifle sustains and should cost the base
-- almost nothing, wave 4 onwards asks more than any one weapon can give and
-- the base must start bleeding. A run where wave 1 already hurts, or where
-- wave 6 does not, means the ramp moved.
return {
	{ t = 2.5, click = "PlayMenu" }, -- starts the run
	{ t = 3.0, run = take_over },
	{ t = 6.0, run = report }, -- the opening lull
	{ t = 30.0, run = report }, -- wave 1
	{ t = 60.0, run = report }, -- wave 2
	{ t = 90.0, run = report }, -- wave 3
	{ t = 120.0, run = report }, -- wave 4: past the crossing
	{ t = 160.0, run = report },
	{ t = 200.0, run = report },
	captures = { 6.0, 30.0, 120.0 },
}

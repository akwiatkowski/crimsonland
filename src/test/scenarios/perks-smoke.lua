-- Perks end to end: the original's roster on the original's screen.
--
-- Names and descriptions come out of prog.dll (game/perktext.lua), the effects
-- from game/perks.lua, and PickAPerk is the pak's own layout — so a capture
-- here shows all three agreeing. Levelling is forced rather than earned: the
-- AI cannot reliably kill enough in a scenario's worth of seconds.

local function play()
	return require("mods.vanilla.game.play")
end

--- Enough experience to trip the level-up check on the next frame.
local function grant_level()
	local g = play()
	g.xp = g.xp + g.xp_next * 4
end

local function report_choices()
	local g = play()
	if not g.perk_choices then
		print("[test] no perk choices on offer")
		return
	end
	for i, p in ipairs(g.perk_choices) do
		print(("[test] offer %d: #%d %s -- %s"):format(
			i, p.index, p.name, (p.desc or ""):sub(1, 60)))
	end
end

local function dismiss_unlocks()
	local screens = require("src.engine.screens")
	local top = screens.top()
	if top then
		require("mods.vanilla.game.unlocks").on_click(top.name)
	end
end

local function report_taken()
	local g = play()
	local owned = {}
	for id in pairs(g.owned_perks) do owned[#owned + 1] = id end
	table.sort(owned)
	local m = g.mods
	print(("[test] owned=[%s] dmg=%.2f fire=%.2f reload=%.2f speed=%.2f "
		.. "clip=%.2f+%d xp=%.2f taken=%.2f offer=%d"):format(
		table.concat(owned, ","), m.dmg, m.fire, m.reload, m.speed,
		m.clip, m.clip_add, m.xp, m.taken, m.perk_offer))
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 9.0, run = grant_level },
	{ t = 9.5, run = report_choices },
	{ t = 10.5, click = "PerkButton_1" },
	{ t = 11.0, run = report_taken },
	-- Taking a perk for the first time earns its unlock celebration, and a
	-- perk that hands you a weapon earns the weapon's too. Those screens carry
	-- no button — any click dismisses — so the scenario dismisses them the way
	-- the game does rather than clicking a comp that is not there.
	{ t = 11.5, run = dismiss_unlocks },
	{ t = 12.0, run = dismiss_unlocks },
	-- a second level, to prove an owned perk is not offered twice and that
	-- two perks stack on the same mods table
	{ t = 13.0, run = grant_level },
	{ t = 13.5, run = report_choices },
	{ t = 14.5, click = "PerkButton_1" },
	{ t = 15.0, run = report_taken },
	captures = { 9.8, 15.2 },
}

-- Emitter comps: a layout attaching a particle effect to a place in the UI.
--
-- SelectChapter ships a "PartPool" Emitter parented to Chapter_1 but never
-- gives it an `emitter.fx`, so nothing in vanilla makes one run. The scenario
-- sets the property the way a screen would and watches the particle count
-- climb on the emitter's own interval, at the emitter's own resolved position
-- (which is also what `static_position` reports).

local screens = require("src.engine.screens")
local comps = require("src.engine.comps")

local function emitter()
	local top = screens.top()
	return top and top.compmap["PartPool"]
end

local function start_emitting()
	local e = emitter()
	if not e then
		print("[test] no PartPool emitter on " .. (screens.top() and screens.top().name or "?"))
		return
	end
	-- the position the layout put it at, resolved to the screen
	print(("[test] PartPool static_position = %.1f, %.1f"):format(
		comps.get(e, "static_position.x"), comps.get(e, "static_position.y")))
	comps.set(e, "emitter.fx", { "fxs/progress_signal.lua" })
	-- shorter than the effect's 0.15-0.25s life, so bursts overlap and the
	-- screen-layer count reads as a steady handful rather than a flickering 1
	comps.set(e, "emitter.time_interval", { 0.05 })
	comps.set(e, "emitter.emitting", { 1 })
end

local function stop_emitting()
	local e = emitter()
	if e then comps.set(e, "emitter.emitting", { 0 }) end
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, run = start_emitting },
	{ t = 7.6, run = stop_emitting },
	-- The screen layer is the one to read: a game runs behind the menu and its
	-- brass lives in the world layer. Expect screen=0 before, several while
	-- emitting, and 0 again a second after it stops.
	captures = { 4.5, 4.8, 7.5, 9.0 },
}

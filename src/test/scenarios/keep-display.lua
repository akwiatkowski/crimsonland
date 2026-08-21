-- Applying a resolution asks whether to keep it.
--
--   make test SCENARIO=keep-display CL_ANSWER=keep|revert|timeout
--
-- ui/keep-display-settings.lua is the dialog the original put between Apply and
-- living with the result: "Keep Settings?", a Keep Changes button, a Revert
-- button, and a Countdown textbox shipping the value 7. Nothing could push it,
-- so Apply committed the change outright -- and the one case the dialog exists
-- for is the one where that is worst: a mode the display cannot show, leaving
-- the player to find the options screen again on a screen showing nothing.
--
-- The three answers are the three ways out, and each has to leave the window
-- somewhere different:
--
--   keep      the new mode stays
--   revert    the old mode comes back
--   timeout   nobody answers, and the old mode comes back by itself
--
-- The scenario picks a resolution that is genuinely not the current one, or
-- reverting would be indistinguishable from keeping and all three cases would
-- pass on a stub.

local comps = require("src.engine.comps")
local screens = require("src.engine.screens")

local ANSWER = (os.getenv("CL_ANSWER") or "keep"):lower()

local before = {}
local applied = {}
local ended = {}
local counts = {}

local function mode()
	local w, h = love.window.getMode()
	return { w = w, h = h }
end

--- Choose a listbox row that is not the one already in effect. The list is
-- built largest-first from the desktop's own aspect ratio (game/display.lua),
-- so row 1 and the last row are the extremes and at least one of them differs
-- from whatever the window is now.
local function pick_other()
	before = mode()
	local top = screens.top()
	local list = top and top.compmap["Resolutions"]
	if not list then return end
	local items = comps.get(list, "listbox.items")
	local n = type(items) == "table" and #items or 0
	local current = comps.num(list, "listbox.selected", 1)
	local want = (current == 1 and n > 1) and n or 1
	comps.set(list, "listbox.selected", { want })
	print(("[keep] window %dx%d, list has %d rows, selected %d -> %d"):format(
		before.w, before.h, n, current, want))
end

local function note_applied()
	applied = mode()
	local top = screens.top()
	print(("[keep] after Apply: %dx%d, top=%s"):format(
		applied.w, applied.h, top and top.name or "?"))
end

local function sample(tag)
	return function()
		local top = screens.top()
		local c = top and top.compmap["Countdown"]
		local t = c and comps.get(c, "textbox.text")
		if type(t) == "table" then t = t[1] end
		counts[tag] = tonumber(t)
		print(("[keep] countdown %s = %s"):format(tag, tostring(t)))
	end
end

local function note_end()
	ended = mode()
	local top = screens.top()
	ended.top = top and top.name or "?"
	print(("[keep] end: %dx%d, top=%s"):format(ended.w, ended.h, ended.top))
end

local steps = {
	{ t = 2.5, click = "Options" },
	{ t = 4.0, click = "DisplayOptions" },
	{ t = 5.5, run = pick_other },
	{ t = 6.0, click = "Apply" },
	{ t = 7.0, run = note_applied },
	{ t = 7.1, expect = function()
		if (screens.top() and screens.top().name) ~= "KeepDisplaySettings" then
			return false, ("Apply left %s on top, not the confirmation"):format(
				screens.top() and screens.top().name or "?")
		end
		return true, "Apply asked whether to keep it"
	end },
	{ t = 7.5, run = sample("early") },
	{ t = 10.5, run = sample("later") },
	{ t = 10.6, expect = function()
		if not (counts.early and counts.later) then
			return false, "the countdown never showed a number"
		end
		if counts.later >= counts.early then
			return false, ("countdown went %d -> %d in three seconds"):format(
				counts.early, counts.later)
		end
		return true, ("countdown ran %d -> %d"):format(counts.early, counts.later)
	end },
}

if ANSWER == "keep" then
	steps[#steps + 1] = { t = 11.0, click = "Keep" }
elseif ANSWER == "revert" then
	steps[#steps + 1] = { t = 11.0, click = "Revert" }
end
-- timeout answers nothing at all: the dialog ships 7 seconds and it was pushed
-- at t=6, so it has to be gone well before this
steps[#steps + 1] = { t = 15.0, run = note_end }

steps[#steps + 1] = { t = 15.1, expect = function()
	if ended.top == "KeepDisplaySettings" then
		return false, ("the dialog is still up after %s"):format(ANSWER)
	end
	return true, ("%s closed the dialog"):format(ANSWER)
end }

steps[#steps + 1] = { t = 15.2, expect = function()
	if applied.w == before.w and applied.h == before.h then
		return false, ("Apply did not change the mode (%dx%d both times), so this "
			.. "scenario cannot tell keeping from reverting"):format(before.w, before.h)
	end
	if ANSWER == "keep" then
		if ended.w ~= applied.w or ended.h ~= applied.h then
			return false, ("kept, but the window is %dx%d and the applied mode was %dx%d")
				:format(ended.w, ended.h, applied.w, applied.h)
		end
		return true, ("kept %dx%d"):format(ended.w, ended.h)
	end
	if ended.w ~= before.w or ended.h ~= before.h then
		return false, ("%s, but the window is %dx%d and it started %dx%d"):format(
			ANSWER, ended.w, ended.h, before.w, before.h)
	end
	return true, ("%s put %dx%d back"):format(ANSWER, before.w, before.h)
end }

return steps

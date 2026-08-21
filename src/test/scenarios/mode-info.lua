-- The survival menu's mode panel says what the pointer is on.
--
--   make test SCENARIO=mode-info
--
-- ui/play-menu-survival.lua ships the panel storing its locked state --
-- "LOCKED" over "Complete more Quests to unlock this game mode." -- and the
-- C++ side replaced it from game-modes/game-modes.xml as the pointer moved.
-- The port never opened that file, so the panel said LOCKED for ever, about
-- modes that were all available.
--
-- Read straight out of the textboxes, because that is the thing that was wrong:
-- the data being parsed says nothing about whether it reaches the panel.

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")
local screens = require("src.engine.screens")

local seen = {}

local function panel()
	local top = screens.top()
	if not top then return nil end
	local function get(name)
		local c = top.compmap[name]
		local t = c and comps.get(c, "textbox.text")
		if type(t) == "table" then t = t[1] end
		return tostring(t)
	end
	return get("Name"), get("Desc")
end

local function look(tag)
	return function()
		local name, desc = panel()
		seen[tag] = { name = name, desc = desc }
		print(("[modeinfo] %-12s name=%q desc=%q"):format(tag, name or "", (desc or ""):sub(1, 44)))
	end
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },

	-- with the pointer on nothing: the resting state, which must not be the
	-- padlock the layout stores
	{ t = 4.4, run = look("resting") },

	-- A second of scenario time between pointing and reading, because the panel
	-- is filled during draw and the harness runs 30 updates per drawn frame:
	-- steps closer together than STEPS_PER_FRAME * FIXED_DT (0.5s) land in the
	-- same batch, and the read then sees the frame before the hover. Spaced too
	-- tightly, this scenario reports every mode one behind.
	{ t = 5.0, hover = "Play_RUSH" },
	{ t = 6.0, run = look("rush") },

	{ t = 7.0, hover = "Play_NUKEFISM" },
	{ t = 8.0, run = look("nukefism") },

	{ t = 9.0, hover = "Play_WAVES" },
	{ t = 10.0, run = look("waves") },

	{ t = 10.2, expect = function()
		if not seen.resting then return false, "the panel was never read" end
		if seen.resting.name == "LOCKED" then
			return false, "the panel still shows the layout's LOCKED placeholder"
		end
		return true, ("resting on %q"):format(seen.resting.name)
	end },
	{ t = 10.3, expect = function()
		data.load_game_modes()
		local bad = {}
		for tag, id in pairs({ rush = "RUSH", nukefism = "NUKEFISM", waves = "WAVES" }) do
			local want = data.game_modes[id]
			local got = seen[tag]
			if not want then
				bad[#bad + 1] = id .. " missing from game-modes.xml"
			elseif not got then
				bad[#bad + 1] = id .. " never hovered"
			elseif got.name ~= want.name then
				bad[#bad + 1] = ("%s showed %q, authored %q"):format(id, got.name, want.name)
			elseif got.desc ~= want.desc then
				bad[#bad + 1] = ("%s description is not the authored one"):format(id)
			end
		end
		table.sort(bad)
		if #bad > 0 then return false, table.concat(bad, "; ") end
		return true, "every hovered mode showed its authored name and description"
	end },
}

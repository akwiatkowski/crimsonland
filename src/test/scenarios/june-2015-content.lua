-- The June 2015 content pack, at all three doors the layouts put on it.
--
--   make test SCENARIO=june-2015-content
--
-- `required_features="ADDITIONAL_CONTENT_JUNE_2015"` appears three times in the
-- pak's layouts, and a comp whose feature is missing is not drawn and not
-- hit-tested -- so one flag in src/engine/platform.lua decided whether three
-- separate pieces of shipped content existed:
--
--   ui/play-menu-survival.lua:69   Play_WAVES    a mode play.lua implements
--   ui/select-chapter.lua:74       Chapter_7     "Phoenix Calling", ten quests
--   ui/fw/achievements.lua:104     ITEM_21       the 22nd achievement's plate
--
-- With the flag off: five mode buttons, six chapter buttons, 21 plates for 22
-- achievements. Nothing failed and nothing logged -- the content was simply not
-- in the menus. This is the test that says otherwise.
--
-- Chapter_7 is checked for presence, not for being clickable: it is
-- progression-locked on a fresh profile, which is the save's business and
-- correct. Present-but-inactive is the pass.

local comps = require("src.engine.comps")
local screens = require("src.engine.screens")

local found = {}

local function visible(name)
	local top = screens.top()
	local comp = top and top.compmap[name]
	return comp ~= nil and comps.get(comp, "visible") == true
end

local function count_visible(prefix)
	local top = screens.top()
	local n = 0
	for _, c in ipairs(top and top.comps or {}) do
		if c.name:match("^" .. prefix) and comps.get(c, "visible") then n = n + 1 end
	end
	return n
end

return {
	-- door one: the survival menu
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.4, run = function() found.waves = visible("Play_WAVES") end },
	{ t = 4.6, click = "Back" },

	-- door two: the chapter grid
	{ t = 6.0, click = "Play_Quests" },
	{ t = 7.4, run = function()
		found.chapter7 = visible("Chapter_7")
		found.chapters = count_visible("Chapter_")
	end },
	{ t = 7.6, click = "Back" },

	-- door three: the achievements grid
	{ t = 9.0, key = "escape" },
	{ t = 10.5, click = "Extras" },
	{ t = 12.0, click = "Achievements" },
	{ t = 13.5, run = function()
		found.plates = count_visible("ITEM_")
		print(("[june2015] waves=%s chapter7=%s chapters=%d plates=%d"):format(
			tostring(found.waves), tostring(found.chapter7),
			found.chapters or -1, found.plates or -1))
	end },

	{ t = 13.6, expect = function()
		if not found.waves then return false, "Play_WAVES is not on the survival menu" end
		return true, "Play_WAVES is there"
	end },
	{ t = 13.7, expect = function()
		if not found.chapter7 then
			return false, ("Chapter_7 is not on the chapter grid (%d chapters shown)"):format(
				found.chapters or -1)
		end
		if (found.chapters or 0) ~= 7 then
			return false, ("%d chapter buttons, the pak lays out 7"):format(found.chapters)
		end
		return true, "all 7 chapters are on the grid"
	end },
	{ t = 13.8, expect = function()
		-- achievements.xml carries 22; the grid has a plate for each, and the
		-- last of them is the one behind the feature gate
		if (found.plates or 0) ~= 22 then
			return false, ("%d achievement plates, achievements.xml has 22"):format(
				found.plates or -1)
		end
		return true, "22 achievement plates for 22 achievements"
	end },
}

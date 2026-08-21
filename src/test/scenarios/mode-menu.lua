-- Reaching an endless mode the way a player does: by clicking it.
--
--   make test SCENARIO=mode-menu CL_MODE=WAVES
--
-- mode.lua starts a mode through game.start_survival, which is the call the
-- menu makes -- and therefore says nothing about whether the menu can make it.
-- Waves could not: ui/play-menu-survival.lua gates the Play_WAVES button on
-- required_features="ADDITIONAL_CONTENT_JUNE_2015", the port declared that
-- feature absent, and a hidden button is not clickable. The mode had a full
-- implementation and no way in.
--
-- Two claims, and the second is the one that matters:
--
--   the button is there   a hidden comp is not in the hit list at all, so the
--                         click lands on nothing and nothing happens
--   the right mode ran    the attract demo behind the menu is itself a live
--                         survival session, so "a game is running" is true
--                         before anything is clicked. Only the mode tells them
--                         apart, and demo has to be false.

local play = require("mods.vanilla.game.play")
local screens = require("src.engine.screens")

-- Button suffix -> the mode string game.start_survival is given for it
-- (play.lua's own MODE_BUTTONS table, in reverse).
local WANT = {
	SURVIVAL = "survival",
	RUSH = "rush",
	BLITZ = "blitz",
	WAVES = "waves",
	NUKEFISM = "nukefism",
	WEAPONPICKER = "weaponpicker",
}

local BUTTON = (os.getenv("CL_MODE") or "WAVES"):upper()

local visible = nil

local function look()
	-- the same question the hit test asks: is this comp on the screen at all
	local top = screens.top()
	local comp = top and top.compmap["Play_" .. BUTTON]
	visible = comp ~= nil and require("src.engine.comps").get(comp, "visible") == true
	print(("[mode-menu] Play_%s present=%s visible=%s"):format(
		BUTTON, tostring(comp ~= nil), tostring(visible)))
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.4, run = look },
	{ t = 4.5, expect = function()
		if not visible then
			return false, ("Play_%s is not on the survival menu"):format(BUTTON)
		end
		return true, ("Play_%s is on the menu"):format(BUTTON)
	end },
	{ t = 5.0, click = "Play_" .. BUTTON },
	{ t = 7.0, expect = function()
		local want = WANT[BUTTON]
		if not want then return false, ("no mode known for Play_%s"):format(BUTTON) end
		if play.demo then
			return false, ("clicking Play_%s left the attract demo running"):format(BUTTON)
		end
		if not play.active then
			return false, ("clicking Play_%s started nothing"):format(BUTTON)
		end
		if play.mode ~= want then
			return false, ("Play_%s started mode %s, wanted %s"):format(
				BUTTON, tostring(play.mode), want)
		end
		return true, ("Play_%s runs %s"):format(BUTTON, play.mode)
	end },
}

-- The panel beside the survival menu's mode list.
--
-- ui/play-menu-survival.lua lays out an Info marker holding an Image ("Pic"), a
-- Name textbox and a Desc textbox, and leaves them storing the locked state:
-- ui/gfx/lock-large, "LOCKED", and "Complete more Quests to unlock this game
-- mode." The C++ side replaced all three as the pointer moved down the list,
-- from game-modes/game-modes.xml -- which is where every mode's real name, its
-- description and its own plate live, and which this port did not open. So the
-- panel sat on its stored contents for ever: a padlock and a line telling the
-- player to unlock a mode that was already there to play.
--
-- The descriptions are authored copy nobody has been reading, and some of it is
-- the game's own voice: Rush is "Can you survive the alien onslaught with your
-- trusty Assault Rifle? (No, you cannot.)"
--
-- What the panel shows with the pointer on nothing is a choice, not a finding:
-- it shows Survival. The screen's own title textbox says "Survival", it is the
-- first button in the list and the mode the others are variations of, and the
-- alternative -- leaving the padlock up until the pointer happens to cross a
-- button -- is the bug this file exists to fix.

local comps = require("src.engine.comps")
local data = require("mods.vanilla.game.data")

local modeinfo = {}

local SCREEN = "PlayMenuSurvival"
local RESTING = "SURVIVAL"

function modeinfo.draw(screen_name, screen)
	if screen_name ~= SCREEN then return end
	data.load_game_modes()

	-- Button names are Play_<id>, and the id is game-modes.xml's own key, so
	-- the hovered button names its entry with no table in between.
	local hover = screen._hover_comp
	local id = hover and hover.name:match("^Play_(%u+)$")
	local mode = data.game_modes[id or RESTING]
	if not mode then return end

	local function put(comp_name, prop, value)
		local comp = screen.compmap[comp_name]
		if comp and value then comps.set(comp, prop, { value }) end
	end
	put("Name", "textbox.text", mode.name)
	put("Desc", "textbox.text", mode.desc)
	put("Pic", "image.bitmap", mode.bm)
end

return modeinfo

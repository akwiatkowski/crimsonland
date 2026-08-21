-- Choosing a weapon before a run, off the grid the pak never had a plate in.
--
--   make test MOD=enhanced SCENARIO=enhanced-pick
--
-- The picker is the answer to a problem this cartridge created for itself: its
-- sixteen weapons sit at the far end of the drop pool on purpose, so a chapter
-- 7 quest reaches five of them and survival needs seventeen minutes to reach
-- the last. That is right for playing and useless for testing, and a mechanism
-- that only exists to be used by hand is exactly the kind that quietly breaks.
--
-- Four things have to hold, and each fails differently:
--
--   * the launch click is *held* rather than starting a run;
--   * the second grid opens off the first, since the pak's has thirty plates
--     and the cartridge's weapons are the thirty-first onwards;
--   * choosing replays the held click, so the run that starts is the chapter
--     and quest that were asked for and not a hardcoded one;
--   * the weapon is in the trooper's hands when it does.
--
-- The picker is switched on here rather than read from CL_PICK so this runs
-- under the plain sweep like every other scenario. That is the same switch a
-- player throws with `make pick`; nothing else about it differs.

local picker = require("mods.enhanced.picker")
local play = require("mods.vanilla.game.play")

local WANT = "RAIL_CANNON"
local SLOT = 16 -- its plate on the cartridge's own grid, last of the sixteen
local CHAPTER, QUEST = 5, 3

local function enable()
	picker.active = true
	picker.install() -- opens the chapters, as CL_PICK does
end

--- A run of the player's own. `play.active` is not the test: the menu
-- backdrop *is* a live game played by an AI (the original's timeline says so),
-- so a session is running the whole time you are standing in the menus. What
-- must not have happened is a real one.
local function playing()
	return play.active and not play.demo
end

local function held()
	if playing() then
		return false, "the run started instead of waiting for a weapon"
	end
	local screens = require("src.engine.screens")
	if not screens.find("Weapons") then
		return false, "the launch click did not open the picker"
	end
	return true, "launch click held, picker up"
end

local function second_grid()
	local screens = require("src.engine.screens")
	if not screens.find("EnhancedArsenal") then
		return false, "the cartridge's own grid did not open off the pak's"
	end
	if playing() then
		return false, "the run started while still choosing"
	end
	return true, "second grid open, run still not started"
end

local function started_with_it()
	if not playing() then
		return false, "choosing a weapon did not start a run of the player's own"
	end
	local w = play.player and play.player.weapon
	if not w or w.id ~= WANT then
		return false, ("started holding %s, wanted %s"):format(
			w and w.id or "nothing", WANT)
	end
	-- the replayed click has to be the one that was held, or the picker is
	-- quietly starting some other quest than the one that was asked for
	if play.mode ~= "quest" or play.chapter ~= CHAPTER or play.quest ~= QUEST then
		return false, ("started %s %s-%s, wanted quest %d-%d"):format(
			tostring(play.mode), tostring(play.chapter), tostring(play.quest),
			CHAPTER, QUEST)
	end
	if (play.player.ammo or 0) <= 0 then
		return false, ("started holding %s with an empty clip"):format(WANT)
	end
	return true, ("quest %d-%d started holding %s, %d rounds"):format(
		CHAPTER, QUEST, WANT, play.player.ammo)
end

return {
	{ t = 1.0, run = enable },
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	-- a chapter no fresh profile could reach: the picker opens them, and a
	-- run that starts here proves it
	{ t = 4.6, click = "Chapter_" .. CHAPTER },
	{ t = 5.8, click = "Quest_" .. QUEST },
	{ t = 7.0, expect = held },
	{ t = 7.6, click = "EnhancedArsenalOpen" },
	{ t = 8.8, expect = second_grid },
	{ t = 9.4, click = "EWeapon_" .. SLOT },
	{ t = 11.0, expect = started_with_it },
	captures = { 7.2, 9.0, 12.0 },
}

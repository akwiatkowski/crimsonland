-- The menu backdrop is one of the five scenes 10tons authored for it.
--
--   make test SCENARIO=attract-demos
--
-- The original's timeline pushes GameCrimsonland behind the main menu with
-- parm_demo="MENU_COMBAT_1".."MENU_COMBAT_5", and demos.xml says what each of
-- those is: a terrain, a duration, a spawn set, and a position and weapon for
-- every trooper in it.
--
--   MENU_COMBAT_1  CHAPTER_2  10s  MEAN_MINIGUN    @1620,990  ALIENS_AROUND
--   MENU_COMBAT_2  CHAPTER_3  12s  SUBMACHINE_GUN  @512,512   LIZARDS
--   MENU_COMBAT_3  CHAPTER_2   7s  (no trooper)               ZOMBIES_RANDOM
--   MENU_COMBAT_4  CHAPTER_1  12s  SHOTGUN         @512,512   ALIENS
--   MENU_COMBAT_5  CHAPTER_2  12s  PLASMA_MINIGUN  @412,512   ZOMBIES_BELOW
--
-- The port used to roll a chapter and a gun of its own, so the backdrop was a
-- different fight every time and never one of those five.
--
-- Nothing is clicked here: the attract mode is what the game does when left
-- alone at the menu, so leaving it alone is the test. Thirty-eight seconds is
-- past the sum of the first three durations, which is what makes the rotation
-- observable.

local data = require("mods.vanilla.game.data")
local play = require("mods.vanilla.game.play")

local seen = {}
local order = {}
local bad = {}

local function sample()
	if not (play.demo and play.demo_id) then return end
	local id = play.demo_id
	if not seen[id] then
		seen[id] = true
		order[#order + 1] = id
		-- check the scene against its own node the moment it starts, because
		-- the ramp and the AI both move things afterwards
		local d = data.demos[id]
		if not d then
			bad[#bad + 1] = id .. " is not a demos.xml node"
			return
		end
		local want_ch = tonumber(tostring(d.terrain_id):match("CHAPTER_(%d+)"))
		if want_ch and play.chapter ~= want_ch then
			bad[#bad + 1] = ("%s: on chapter %s, authored %s"):format(
				id, tostring(play.chapter), want_ch)
		end
		if d.trooper_1_weapon then
			local got = play.player and play.player.weapon and play.player.weapon.id
			if got ~= d.trooper_1_weapon then
				bad[#bad + 1] = ("%s: carrying %s, authored %s"):format(
					id, tostring(got), d.trooper_1_weapon)
			end
		end
		print(("[attract] %s chapter=%s weapon=%s pool=%s"):format(
			id, tostring(play.chapter),
			play.player and play.player.weapon and play.player.weapon.id or "none",
			play.demo_pool and play.demo_pool[1].type or "ramp"))
	end
end

return {
	-- the menu comes up on its own and the demo is already running behind it
	{ t = 2.0, run = sample },
	{ t = 4.0, run = sample }, { t = 6.0, run = sample },
	{ t = 8.0, run = sample }, { t = 10.0, run = sample },
	{ t = 12.0, run = sample }, { t = 14.0, run = sample },
	{ t = 16.0, run = sample }, { t = 18.0, run = sample },
	{ t = 20.0, run = sample }, { t = 22.0, run = sample },
	{ t = 24.0, run = sample }, { t = 26.0, run = sample },
	{ t = 28.0, run = sample }, { t = 30.0, run = sample },
	{ t = 32.0, run = sample }, { t = 34.0, run = sample },
	{ t = 36.0, run = sample }, { t = 38.0, run = sample },
	{ t = 38.1, expect = function()
		if #order == 0 then
			return false, "no authored demo ran at all"
		end
		return true, ("ran %s"):format(table.concat(order, " -> "))
	end },
	{ t = 38.2, expect = function()
		if #bad > 0 then
			return false, table.concat(bad, "; ")
		end
		return true, "every scene matched its demos.xml node"
	end },
	{ t = 38.3, expect = function()
		-- the durations are 10, 12 and 7 seconds, so a 38-second watch has to
		-- see more than one scene or the rotation is not rotating
		if #order < 2 then
			return false, ("only %s ran in 36s of attract mode"):format(order[1])
		end
		return true, ("%d scenes in 36s"):format(#order)
	end },
}

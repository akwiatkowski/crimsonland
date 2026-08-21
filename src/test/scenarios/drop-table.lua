-- Everything a mode may drop must be a weapon a player can hold.
--
--   make test SCENARIO=drop-table
--
-- weapons.xml is not a list, it is an indexed array with holes: the 31 player
-- weapons are 1..31, and then it jumps -- 32 BUBBLEGUN, 44 SPIDER_PLASMA,
-- 45 FIRE_BULLETS, 46 PLASMA_OVERLOAD, 47 MONSTER_PLASMA, 48 MEGALASER,
-- 63 UNKNOWN. Those are what creatures shoot with, what the fire-bullets
-- powerup swaps in, and cut content; the last five have no icon at all.
--
-- play.lua picks a drop by walking `data.player_weapons` from 2 to
-- game.weapon_cap. That pool is built as the leading run of indices carrying an
-- icon plus whatever the active cartridge added, which is what keeps creature
-- guns and cut content out of it structurally rather than by arithmetic. The
-- arithmetic is what failed before: the custom-quest site capped at
-- `#data.weapon_order`, a length taken over a sparse table -- undefined by the
-- language, and whatever it answers is not 31.
--
-- So this asserts the invariant rather than the numbers: whatever the cap is,
-- every slot the drop roll can reach must exist and must be a weapon with an
-- icon. A weapon with no icon is drawn as an empty pickup and carried as an
-- empty HUD slot -- assets.image(nil) returns nil and every draw site checks,
-- so it is not a crash, which is exactly why nothing had noticed.
--
-- Deliberately no upper bound on the cap written down here: a mod may extend
-- the pool (data.weapon_overlay), and a test that hardcoded 31 would report a
-- cartridge's own arsenal as cut content.

local data = require("mods.vanilla.game.data")
local customquests = require("mods.vanilla.game.customquests")
local play = require("mods.vanilla.game.play")
local timeline = require("src.engine.timeline")

local function candidates()
	local bad = {}
	-- the range play.lua's own drop roll walks (game.spawn_drop, and the
	-- weaponpicker field spawn) -- read the cap off the live game rather than
	-- recomputing it, so the test follows the game and not a copy of it
	for idx = 2, (play.weapon_cap or 0) do
		local w = data.player_weapons[idx]
		if not w then
			bad[#bad + 1] = ("%d=(empty slot)"):format(idx)
		elseif not w.icon then
			bad[#bad + 1] = ("%d=%s (no icon)"):format(idx, w.id)
		end
	end
	return bad
end

local function check(label)
	return function()
		local bad = candidates()
		if #bad > 0 then
			return false, ("%s: cap %s reaches %s"):format(
				label, tostring(play.weapon_cap), table.concat(bad, ", "))
		end
		return true, ("%s: cap %s is all player weapons"):format(
			label, tostring(play.weapon_cap))
	end
end

return {
	-- the deepest chapter, where the hand-written cap is at its highest
	{ t = 2.5, run = function()
		play.start_quest(7, 10, "NORMAL")
		timeline.begin("Game")
	end },
	{ t = 3.0, expect = check("quest 7-10") },

	-- and an authored quest, whose cap is the sparse length
	{ t = 4.0, run = function()
		local q = customquests.all()[1]
		if q then
			play.start_custom(q)
			timeline.begin("Game")
		end
	end },
	{ t = 4.5, expect = function()
		if not play.custom then return false, "no authored quest to start" end
		return check("custom quest")()
	end },
}

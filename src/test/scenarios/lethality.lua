-- One weapon against the weakest creature in the game, for fifteen seconds.
--
--   make test MOD=allweapons SCENARIO=lethality CL_WEAPON=8
--
-- The matrix says whether a weapon fires and whether a creature spawns. It
-- does not say whether the gun works, and three of the thirty did not: across
-- 390 fights the blow torch landed 1491 hits and got one kill, the flamethrower
-- 360 hits and two, the HR flamer 409 hits and one. Every other weapon killed
-- between twenty and fifty.
--
-- So this asks the one question that has only one acceptable answer, against
-- the creature the answer matters most for: the base variant of the type the
-- pool of chapter 1 quest 1 is made of -- the first enemy in the game, the one
-- every weapon is expected to beat. Not the weakest variant in the file, which
-- is a 5 hp alien whelp that dies to anything and let all three flame weapons
-- through. The claim is in two parts, because they fail for different reasons:
--
--   no hits at all      the gun cannot reach anything the AI lets it near --
--                       a range or a projectile problem
--   hits but no kills   the gun reaches and does not matter -- a damage problem
--
-- Fifteen seconds against the weakest thing in the game is not a demanding bar
-- for a weapon a player is meant to be pleased to find.

local data = require("mods.vanilla.game.data")
local input = require("mods.vanilla.game.input")
local play = require("mods.vanilla.game.play")

local SLOT = tonumber(os.getenv("CL_WEAPON") or "1")
local TYPE = os.getenv("CL_CREATURE") or "ALIEN"

local target = nil

--- The standard creature of a type: the variant the game reaches for when a
-- pool names the type rather than a variant (data.base_variant, lowest
-- legacy index). For ALIEN that is what quest 1-1 spawns.
local function baseline()
	return data.base_variant[TYPE]
end

local function setup()
	if not (play.active and play.player) then return end
	data.load_all()
	target = baseline()
	play.kills_goal = nil
	play.no_perks = true
	-- or the AI loots a better gun and the answer is about that one instead
	play.no_weapon_drops = true
	play.pool = { { type = TYPE, w = 1 } }
	-- a thicker field than a quest would give: the point is contact, and the
	-- AI backs away from anything close, so give it plenty to back into
	play.spawn_interval = 0.6
	play.max_concurrent = 12
	input.set_controller(require("mods.vanilla.game.ai_player").controller())
	print(("[lethality] %s vs %s (%s, %d hp)"):format(
		play.player.weapon and play.player.weapon.id or "NONE",
		target.id, target.type, target.health))
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 9.0, click = "Weapon_" .. SLOT },
	{ t = 10.0, run = setup },
	{ t = 25.0, run = function()
		print(("[lethality] %-20s t=%.1f shots=%d hits=%d kills=%d"):format(
			play.player and play.player.weapon and play.player.weapon.id or "NONE",
			play.time or -1, play.shots or -1, play.hits or -1, play.kills or -1))
	end },
	{ t = 25.1, expect = function()
		local w = data.weapon_order[SLOT]
		local id = w and w.id or ("slot " .. SLOT)
		if not play.active then return false, ("%s: the run ended early"):format(id) end
		if (play.hits or 0) <= 0 then
			return false, ("%s landed no hits at all in 15s"):format(id)
		end
		if (play.kills or 0) <= 0 then
			return false, ("%s landed %d hits on %s and killed nothing"):format(
				id, play.hits, target and target.id or "?")
		end
		return true, ("%s: %d hits, %d kills"):format(id, play.hits, play.kills)
	end },
	dismiss = { "WeaponUnlocked", "PerkUnlocked" },
}

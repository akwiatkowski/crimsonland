-- One of the cartridge's weapons against the first enemy in the game.
--
--   make test MOD=enhanced SCENARIO=enhanced-lethality CL_WEAPON=RAIL_CANNON
--
-- The same question src/test/scenarios/lethality.lua asks of the pak's thirty,
-- and the same reason for asking it: the matrix says a weapon fires and a
-- creature spawns, and says nothing about whether the gun works. Three of the
-- original's thirty turned out not to -- 2234 hits and five kills between them
-- -- and nothing before that sweep had noticed, because a weapon that does no
-- damage looks exactly like a weapon you are using badly.
--
-- Sixteen new weapons whose damage nobody has ever felt is precisely the
-- situation that produced that bug. Fifteen seconds against an ALIEN is not a
-- demanding bar.
--
-- TWO DIFFERENCES from the vanilla version, both forced by what these weapons
-- are:
--
--   * the weapon is put in the trooper's hands directly rather than picked off
--     a gallery plate. mods/allweapons drives its picker off the pak's grid,
--     which has thirty plates and no thirty-first.
--   * the trigger is released for a moment every few seconds. Four of these
--     weapons are about the release -- a Rail Spike in the hands of something
--     that never lets go never fires at all -- and the attract-mode AI holds
--     the trigger for as long as a target is in range. Every weapon in the
--     sweep gets the same cycle, so they are still measured against each other
--     fairly; they are simply all measured with a finger that lets go.

local data = require("mods.vanilla.game.data")
local input = require("mods.vanilla.game.input")
local play = require("mods.vanilla.game.play")

local WEAPON = os.getenv("CL_WEAPON") or "TESLA_ARC"
local TYPE = os.getenv("CL_CREATURE") or "ALIEN"

-- Long enough to charge a Rail Spike fully, and a gap long enough to be seen.
local FIRE_HOLD, FIRE_GAP = 2.7, 0.3

local target = nil
local clock = 0

--- The attract-mode AI, with the trigger cycled on top of it. Everything else
-- about how it plays -- where it walks, what it aims at, when it backs off --
-- is the AI's, so this measures the same fight the vanilla sweep does.
local function driver()
	local ai = require("mods.vanilla.game.ai_player").controller()
	return function(game, dt)
		clock = clock + dt
		local want = ai(game, dt)
		want.fire = want.fire and (clock % (FIRE_HOLD + FIRE_GAP)) < FIRE_HOLD
		return want
	end
end

local function setup()
	if not (play.active and play.player) then return end
	data.load_all()
	local w = data.weapons[WEAPON]
	if w then
		play.player.weapon = w
		play.player.reloading = 0
		play.player.cooldown = 0
		play.player.ammo = play.clip_size()
	end
	target = data.base_variant[TYPE]
	play.kills_goal = nil
	play.no_perks = true
	-- or the AI loots something else and the answer is about that weapon
	play.no_weapon_drops = true
	play.pool = { { type = TYPE, w = 1 } }
	play.spawn_interval = 0.6
	play.max_concurrent = 12
	input.set_controller(driver())
	print(("[enhanced-lethality] %s vs %s (%d hp)"):format(
		play.player.weapon and play.player.weapon.id or "NONE",
		target and target.id or "?", target and target.health or -1))
end

local function verdict()
	if not data.weapons[WEAPON] then
		return false, ("no weapon called %s"):format(WEAPON)
	end
	if not play.active then
		return false, ("%s: the run ended early"):format(WEAPON)
	end
	if (play.shots or 0) <= 0 then
		return false, ("%s never fired a shot"):format(WEAPON)
	end
	-- Deliberately kills and not hits, unlike the vanilla sweep's two-part
	-- claim: half of these weapons do their damage somewhere other than the
	-- round -- an arc, a pool, a burst, a well -- and `game.hits` only counts
	-- rounds that touched a body. A Storm Ring can kill a field without ever
	-- registering a hit, so hits are reported and kills are the verdict.
	if (play.kills or 0) <= 0 then
		return false, ("%s: %d shots, %d round hits, killed nothing in 15s"):format(
			WEAPON, play.shots, play.hits or 0)
	end
	return true, ("%s: %d shots, %d round hits, %d kills"):format(
		WEAPON, play.shots, play.hits or 0, play.kills)
end

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, click = "Chapter_1" },
	{ t = 5.8, click = "Quest_1" },
	{ t = 7.5, run = setup },
	{ t = 22.5, run = function()
		print(("[enhanced-lethality] %-17s t=%.1f shots=%d hits=%d kills=%d"):format(
			WEAPON, play.time or -1, play.shots or -1, play.hits or -1,
			play.kills or -1))
	end },
	{ t = 22.6, expect = verdict },
	dismiss = { "EnhancedArsenal", "WeaponUnlocked", "PerkUnlocked" },
}

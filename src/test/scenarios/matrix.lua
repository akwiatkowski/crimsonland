-- The weapon x creature matrix: one weapon, one creature type, one fight.
--
--   make test MOD=allweapons SCENARIO=matrix CL_WEAPON=7 CL_CREATURE=SPIDER_BOSS
--
-- Parameterised rather than generated: 30 weapons against 13 creature types
-- (and against any of the 69 variants by id) is 390 fights, and 390 near
-- identical files in src/test/scenarios would be a worse way to say the same
-- thing than one file the driver calls 390 times. tools/sweep.sh is the driver.
--
-- It must be the allweapons cartridge, or the picker never appears and the
-- weapon click bounces off a locked chapter.
--
-- What is being exercised is the pair, not the pieces: which projectile art a
-- gun throws, which gibs a creature comes apart into, whether that creature
-- freezes, shrinks or burns, and whose death animation plays. That is why the
-- cross product is worth running even though a broken fire path would show up
-- against any target.
--
-- Three settings are pushed into the run at the start, all of them states the
-- game gives itself elsewhere -- no field here is invented for the test:
--
--   pool         one entry, the creature under test. This is exactly what
--                waves mode does per wave (play.lua update_waves_mode).
--   kills_goal   nil, so a fight is not cut short by winning quest 1.1 in
--                four seconds with a minigun. The endless modes run this way.
--   no_perks     true, so a level-up cannot push PickAPerk over the fight and
--                stall it -- the attract demo sets this for the same reason.

local data = require("mods.vanilla.game.data")
local input = require("mods.vanilla.game.input")
local play = require("mods.vanilla.game.play")

local SLOT = tonumber(os.getenv("CL_WEAPON") or "1")
local CREATURE = os.getenv("CL_CREATURE") or "ALIEN"

-- What the run saw, sampled: asserting on the live creature list at one
-- instant would call a fight a failure for ending early -- a cleared field, a
-- dead player and a completed quest all leave nothing standing.
local seen_type = false
local peak_alive = 0
local start_hp = 0

local start_clock = 0

local function setup()
	if not (play.active and play.player) then return end
	start_hp = play.player.hp
	start_clock = play.time
	play.kills_goal = nil
	play.no_perks = true
	-- The AI loots, and a fight that hands it a better gun half way through is
	-- no longer a measurement of the weapon this run is named after: the first
	-- pass of the matrix reported nineteen runs for the submachine gun and nine
	-- for the ion cannon, out of thirteen each, because the numbers followed
	-- whatever was in hand at the end. The mode flag that turns weapon drops
	-- off is nukefism's own.
	play.no_weapon_drops = true
	play.pool = { { type = CREATURE, w = 1 } }
	input.set_controller(require("mods.vanilla.game.ai_player").controller())
	print(("[matrix] weapon=%s creature=%s"):format(
		play.player.weapon and play.player.weapon.id or "NONE", CREATURE))
end

local function sample()
	local alive = 0
	for _, c in ipairs(play.creatures or {}) do
		if not c.dying then alive = alive + 1 end
		-- the pool holds one entry, so anything that spawned is either the
		-- creature under test or something a den of it spawned
		if c.variant and (c.variant.type == CREATURE or c.variant.id == CREATURE) then
			seen_type = true
		end
	end
	if alive > peak_alive then peak_alive = alive end
end

local function report()
	-- the pair leads the line: 390 of these are read as a table, and a row
	-- that does not say what it is has to be traced back to its log
	print(("[matrix] %-20s %-12s t=%.1f shots=%d hits=%d kills=%d peak=%d hp=%d/%d drops=%d fx=%d"):format(
		play.player and play.player.weapon and play.player.weapon.id or "NONE",
		CREATURE, play.time or -1, play.shots or -1, play.hits or -1,
		play.kills or -1, peak_alive, play.player and play.player.hp or -1,
		start_hp, #(play.drops or {}), require("src.engine.fx").count()))
end

-- The fight window: from the setup step to the report, in scenario seconds.
-- The game clock has to keep up with it, because a UI screen over the field
-- stops the field being updated and nothing else here would notice -- the
-- numbers would simply be the ones from whenever it froze.
local FIGHT_FROM, FIGHT_TO = 10.0, 20.1
local CLOCK_SLACK = 1.5 -- one screen transition's worth of grace

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" }, -- held by the picker
	{ t = 9.0, click = "Weapon_" .. SLOT }, -- and this starts the run with it
	{ t = 10.0, run = setup },
	{ t = 10.1, expect = function()
		local want = data.weapon_order[SLOT]
		local got = play.active and play.player and play.player.weapon
		if not got then return false, "no run started for weapon slot " .. SLOT end
		if not (want and got.id == want.id) then
			return false, ("slot %d gave %s, wanted %s"):format(
				SLOT, tostring(got.id), tostring(want and want.id))
		end
		return true, ("slot %d is %s"):format(SLOT, got.id)
	end },
	{ t = 12.0, run = sample },
	{ t = 14.0, run = sample },
	{ t = 16.0, run = sample },
	{ t = 18.0, run = sample },
	{ t = 20.0, run = sample },
	{ t = 20.1, run = report },
	{ t = 20.2, expect = function()
		if not seen_type then
			return false, ("no %s ever spawned"):format(CREATURE)
		end
		return true, ("%s spawned (peak %d alive)"):format(CREATURE, peak_alive)
	end },
	{ t = 20.3, expect = function()
		if (play.shots or 0) <= 0 then
			return false, ("%s never fired a shot"):format(
				data.weapon_order[SLOT] and data.weapon_order[SLOT].id or SLOT)
		end
		return true, ("fired %d shots"):format(play.shots)
	end },
	{ t = 20.4, expect = function()
		local ran = (play.time or 0) - start_clock
		local want = FIGHT_TO - FIGHT_FROM - CLOCK_SLACK
		-- a run that ended is allowed to have stopped its clock: losing the
		-- fight is a result, not a freeze
		if not play.active or play.outcome then
			return true, ("run ended after %.1fs of fight (%s)"):format(
				ran, tostring(play.outcome))
		end
		if ran < want then
			return false, ("fight froze: %.1fs of game clock in %.1fs of scenario"):format(
				ran, FIGHT_TO - FIGHT_FROM)
		end
		return true, ("clock advanced %.1fs"):format(ran)
	end },
	-- the celebrations are the screens an AI run walks into: first sight of a
	-- weapon puts one up, and the game under it stops until somebody clicks
	dismiss = { "WeaponUnlocked", "PerkUnlocked" },
}

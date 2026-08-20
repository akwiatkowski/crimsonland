-- One endless mode, played by the AI, checked against its own rule.
--
--   make test SCENARIO=mode CL_MODE=nukefism
--
-- The six modes are not six names for survival: rush takes the drops and the
-- levelling away, nukefism takes the gun away, waves spawns one type at a time
-- and will not move on until the field is clear, weaponpicker keeps putting a
-- new gun on the ground. Each of those is a rule that can quietly stop being
-- true -- so each mode asserts its own here, rather than every mode asserting
-- that a run started.
--
-- Started through game.start_survival, the call the menu button makes: Waves
-- and Nukefism are progression-locked on a fresh profile, so clicking them on
-- the survival screen does nothing at all (terrain-smoke says so too), and the
-- allweapons cartridge cannot be the way around it here -- its picker would
-- put a weapon in the hands of the mode whose whole rule is not having one.

local input = require("mods.vanilla.game.input")
local play = require("mods.vanilla.game.play")
local timeline = require("src.engine.timeline")

local MODE = os.getenv("CL_MODE") or "survival"

-- sampled across the run, because a rule about drops or waves is a claim
-- about the whole fight and not about the instant it ended
local peak_drops = 0
local peak_wave = 0
local peak_pool = 0
local ever_armed = false

local function start()
	play.start_survival(MODE)
	timeline.begin("Game")
	input.set_controller(require("mods.vanilla.game.ai_player").controller())
end

local function sample()
	peak_drops = math.max(peak_drops, #(play.drops or {}))
	peak_wave = math.max(peak_wave, play.wave or 0)
	peak_pool = math.max(peak_pool, #(play.pool or {}))
	if play.player and play.player.weapon then ever_armed = true end
end

local function report()
	print(("[mode] %s t=%.1f kills=%d peak_drops=%d peak_wave=%d pool=%d armed=%s"):format(
		MODE, play.time or -1, play.kills or -1, peak_drops, peak_wave,
		peak_pool, tostring(ever_armed)))
end

-- Each mode's own promise, as play.lua's start_survival writes it.
local RULES = {
	survival = function()
		-- the ramp adds creature types as the clock runs; a survival run that
		-- never grows its pool is a ramp that stopped being called
		if peak_pool < 2 then
			return false, ("survival pool never grew past %d types"):format(peak_pool)
		end
		return true, ("survival pool reached %d types"):format(peak_pool)
	end,
	blitz = function()
		if peak_pool < 2 then
			return false, ("blitz pool never grew past %d types"):format(peak_pool)
		end
		return true, ("blitz pool reached %d types"):format(peak_pool)
	end,
	rush = function()
		if peak_drops > 0 then
			return false, ("rush dropped %d pickups; it has no drops"):format(peak_drops)
		end
		if not (play.player and play.player.weapon
			and play.player.weapon.id == "ASSAULT_RIFLE") then
			return false, ("rush armed %s, not the assault rifle"):format(
				play.player and play.player.weapon and play.player.weapon.id or "nothing")
		end
		return true, "rush: one rifle, no drops"
	end,
	waves = function()
		if peak_wave < 1 then
			return false, "waves never reached wave 1"
		end
		return true, ("waves reached wave %d"):format(peak_wave)
	end,
	nukefism = function()
		if ever_armed then
			return false, "nukefism handed the player a weapon"
		end
		return true, "nukefism stayed unarmed"
	end,
	weaponpicker = function()
		-- the mode seeds a weapon on the field every few seconds; the AI walks
		-- to loot, so a run either has one on the ground or has picked one up
		if peak_drops == 0 and not ever_armed then
			return false, "weaponpicker never put a weapon on the field"
		end
		return true, ("weaponpicker seeded %d drops, armed=%s"):format(
			peak_drops, tostring(ever_armed))
	end,
}

return {
	{ t = 2.5, run = start },
	{ t = 3.0, expect = function()
		if not play.active then return false, ("mode %s did not start"):format(MODE) end
		if play.mode ~= MODE then
			return false, ("asked for %s, running %s"):format(MODE, tostring(play.mode))
		end
		return true, ("%s started"):format(MODE)
	end },
	{ t = 6.0, run = sample },
	{ t = 10.0, run = sample },
	{ t = 14.0, run = sample },
	{ t = 18.0, run = sample },
	{ t = 22.0, run = sample },
	{ t = 26.0, run = sample },
	{ t = 30.0, run = sample },
	{ t = 30.1, run = report },
	{ t = 30.2, expect = function()
		local rule = RULES[MODE]
		if not rule then return false, ("no rule written for mode '%s'"):format(MODE) end
		return rule()
	end },
}

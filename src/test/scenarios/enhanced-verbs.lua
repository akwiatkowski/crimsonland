-- Every verb the enhanced cartridge added, fired at least once against real
-- creatures.
--
--   make test MOD=enhanced SCENARIO=enhanced-verbs
--
-- A weapon's numbers can be checked from outside (enhanced-arsenal does), but
-- what a weapon *does* cannot: `deliver`, `trigger`, `on_hit` and `on_end` are
-- functions vanilla calls, and a verb whose hook is never reached looks
-- exactly like a verb that works. combat.lua counts each one as it fires, and
-- this asserts against those counters.
--
-- WHY NOT THE ATTRACT-MODE AI. It would drive this badly for one specific
-- reason: it holds the trigger while a target is in range and releases when
-- there is not one, and four of these weapons are about the release. A Rail
-- Spike in the hands of something that never lets go never fires at all. So
-- the driver here is scripted rather than intelligent -- it stands still,
-- points at whatever is nearest, and cycles the trigger and the second trigger
-- on fixed clocks. That makes every verb reachable and the run repeatable,
-- which is what a verdict needs.
--
-- TWO TIERS, on purpose. A verb that fires on the trigger alone is required; a
-- verb that needs a round to *connect* -- and, for the bounce ramp, to connect
-- after bouncing off a wall -- is reported and not asserted. A claim gets the
-- assertion it can actually support, and an expectation that depends on where
-- the aliens happened to walk is a flake with a test around it.

local combat = require("mods.enhanced.combat")
local data = require("mods.vanilla.game.data")
local input = require("mods.vanilla.game.input")
local play = require("mods.vanilla.game.play")

-- The order weapons are picked up, and how long each is held.
local ORDER = {
	"TESLA_ARC", "NODE_GUN", "CAPACITOR_RIFLE", "BALL_LIGHTNING",
	"STORM_RING", "ARC_LASSO",
	"SNIPER_RAIL", "RAIL_CANNON", "RAIL_SPIKE", "PRISM_RAIL",
	"TRACER_RAIL", "TETHER_RAIL",
	"NAIL_GRENADE", "FLAK_CANNON", "BOUNCER_SMG", "ACID_SPRAYER",
}
local HOLD = 4.0
local START = 8.0

-- Fires on the trigger alone, so a run that does not show these is broken
-- rather than unlucky.
local REQUIRED = {
	"lob", "distance_scale", "trail_burn", "anchor", "orb", "charge",
	"ring", "altfire", "gravity",
}
-- Needs a round to connect, or a wall, or a crowd. Printed, never asserted.
local CONTINGENT = {
	"autolock", "nodes", "prism", "knockback", "pool", "lasso",
	"bounce_ramp", "capacitor", "capacitor_backlash", "chill", "shockwave",
}

-- Trigger cycles. The hold has to outlast a full Rail Spike charge (2.5s) or
-- the charge verb can only ever fire half-cocked; the gap has to be long
-- enough that the release is seen on a frame.
local FIRE_HOLD, FIRE_GAP = 2.7, 0.3
local ALT_PERIOD, ALT_PRESS = 2.0, 0.12

local clock = 0

--- Stand still, point at the nearest thing, and work both triggers on a
-- metronome. Deliberately not clever: what is being tested is the weapons.
local function driver(game, dt)
	clock = clock + dt
	local p = game.player
	local target = combat.nearest(p.x, p.y, 900)
	local ax, ay = p.x + 400, p.y
	if target then ax, ay = target.x, target.y end
	local phase = clock % (FIRE_HOLD + FIRE_GAP)
	return {
		dx = 0, dy = 0,
		aim_x = ax, aim_y = ay,
		fire = phase < FIRE_HOLD,
		alt_fire = (clock % ALT_PERIOD) < ALT_PRESS,
		reload = false,
	}
end

local function setup()
	if not (play.active and play.player) then return end
	data.load_all()
	-- endless contact: the point is that every verb gets something to happen
	-- against, and a quest that clears parks the run on an end screen
	play.kills_goal = nil
	play.no_perks = true
	play.no_weapon_drops = true
	play.pool = { { type = "ALIEN", w = 1 } }
	play.spawn_interval = 0.6
	play.max_concurrent = 14
	-- A driver that stands still in a crowd of fourteen dies in seconds, and a
	-- dead trooper takes the rest of the schedule with it. This run is about
	-- whether the verbs fire, so the trooper is given more health than the
	-- fight can spend rather than being given a brain.
	play.player.max_hp = 1e6
	play.player.hp = play.player.max_hp
	input.set_controller(driver)
end

local function take(id)
	return function()
		local w = data.weapons[id]
		if not (w and play.player) then
			print(("[verbs] cannot take %s"):format(id))
			return
		end
		play.player.weapon = w
		play.player.reloading = 0
		play.player.cooldown = 0
		play.player.ammo = play.clip_size()
		play.player.hp = play.player.max_hp
		print(("[verbs] holding %-17s t=%.1f kills=%d"):format(id, play.time, play.kills))
	end
end

local function tally()
	local seen = {}
	for verb, n in pairs(combat.verbs) do seen[#seen + 1] = ("%s=%d"):format(verb, n) end
	table.sort(seen)
	print("[verbs] fired: " .. table.concat(seen, " "))
	local missing = {}
	for _, verb in ipairs(CONTINGENT) do
		if not combat.verbs[verb] then missing[#missing + 1] = verb end
	end
	if #missing > 0 then
		print("[verbs] not reached this run (contact-dependent, not a failure): "
			.. table.concat(missing, ", "))
	end
end

local function all_required()
	local missing = {}
	for _, verb in ipairs(REQUIRED) do
		if not combat.verbs[verb] then missing[#missing + 1] = verb end
	end
	if #missing > 0 then
		return false, ("verbs that never fired: %s"):format(table.concat(missing, ", "))
	end
	return true, ("all %d trigger-driven verbs fired"):format(#REQUIRED)
end

--- The cartridge's own world has to be emptying itself. Pools, nodes, orbs and
-- burning lines all expire; a list that only grows is a leak that a long run
-- would eventually feel, and nothing else would ever notice it.
local function world_bounded()
	local counts = {
		pools = #combat.pools, nodes = #combat.nodes, orbs = #combat.orbs,
		burns = #combat.burns, beams = #combat.beams, wells = #combat.wells,
	}
	local parts = {}
	for k, v in pairs(counts) do parts[#parts + 1] = ("%s=%d"):format(k, v) end
	table.sort(parts)
	for k, v in pairs(counts) do
		if v > 200 then
			return false, ("%s has %d live entries -- nothing is expiring"):format(k, v)
		end
	end
	return true, "cartridge world stays bounded: " .. table.concat(parts, " ")
end

local steps = {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, click = "Chapter_1" },
	{ t = 5.8, click = "Quest_1" },
	{ t = 7.5, run = setup },
}

for i, id in ipairs(ORDER) do
	steps[#steps + 1] = { t = START + (i - 1) * HOLD, run = take(id) }
end

local END = START + #ORDER * HOLD + 1.0
steps[#steps + 1] = { t = END, run = tally }
steps[#steps + 1] = { t = END + 0.1, expect = all_required }
steps[#steps + 1] = { t = END + 0.2, expect = world_bounded }

steps.captures = { START + 4 * HOLD, START + 10 * HOLD, END }
-- an unlock celebration for a weapon nobody has held before is the expected
-- state of this run, sixteen times over
steps.dismiss = { "EnhancedArsenal", "WeaponUnlocked", "PerkUnlocked" }

return steps

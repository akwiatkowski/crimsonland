-- A defender, for measuring balance with.
--
-- Vanilla's ai_player.lua plays Crimsonland: it kites, it keeps its distance,
-- it shoots whatever is closest to *itself*. Pointed at this mod it produces a
-- meaningless reading — creatures it has not aggroed walk straight past to the
-- base while it dances, so every wave leaks almost entirely and the numbers
-- say the game is impossible when what is actually being measured is a bad
-- defender.
--
-- This one plays the mod's own game: it stays on the base, faces whatever is
-- closest to *the base*, and puts itself between the two. It is not a good
-- player — no kiting, no target priority beyond distance, no retreat — which
-- is the point. It is the floor: what a competent player who understands the
-- objective would manage without trying. Balance targets read against it are
-- conservative by construction.
--
-- It is also a preview of a tower's brain (see the plan's "generalise the
-- shooter"): pick the nearest threat, aim, hold the trigger.

local defender = {}

-- How far from the base it will step to meet something. Beyond this it goes
-- home: chasing one straggler across the map is how a base gets eaten.
local PICKET = 130

--- Nearest live creature to the base, which in this mod is the same thing as
-- "the most urgent one" — everything walks at the base, so closest is soonest.
local function nearest_threat(field)
	local best, bd
	for _, c in ipairs(field.creatures) do
		if not c.dying then
			local dx, dy = c.x - field.base.x, c.y - field.base.y
			local d = dx * dx + dy * dy
			if not bd or d < bd then best, bd = c, d end
		end
	end
	return best, bd and math.sqrt(bd) or nil
end

--- Install as the game's input controller: same contract as a human's
-- (mods/vanilla/game/input.lua) — movement axes, a world-space aim point,
-- and whether the trigger and reload are held.
function defender.controller()
	return function(field, dt)
		local p, b = field.player, field.base
		local threat, tdist = nearest_threat(field)

		-- where it wants to stand: on the line from the base to the threat, at
		-- the picket distance, so the threat has to come through it
		local gx, gy = b.x, b.y + 90
		if threat then
			local ang = math.atan2(threat.y - b.y, threat.x - b.x)
			local reach = math.min(PICKET, (tdist or PICKET) - 40)
			gx = b.x + math.cos(ang) * math.max(40, reach)
			gy = b.y + math.sin(ang) * math.max(40, reach)
		end

		local dx, dy = gx - p.x, gy - p.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist < 12 then dx, dy = 0, 0 else dx, dy = dx / dist, dy / dist end

		local aim_x, aim_y = p.x + math.cos(p.angle) * 100, p.y + math.sin(p.angle) * 100
		local fire = false
		if threat then
			aim_x, aim_y = threat.x, threat.y
			-- fire when roughly on target; the weapon's own spread does the rest
			local want = math.atan2(threat.y - p.y, threat.x - p.x)
			local off = math.abs((want - p.angle + math.pi) % (2 * math.pi) - math.pi)
			fire = off < 0.25
		end

		return {
			dx = dx, dy = dy,
			aim_x = aim_x, aim_y = aim_y,
			fire = fire,
			-- reload in the gaps rather than mid-fight, which is most of what
			-- separates a player who holds a line from one who does not
			reload = (not threat) or (tdist and tdist > 400),
		}
	end
end

return defender

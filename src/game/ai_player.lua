-- An AI that plays the game through the same intent interface a human uses
-- (src/game/input.lua), so it is a player rather than a script poking state.
--
-- Two users: the attract-mode demo behind the main menu — the original's
-- timeline says the menu backdrop IS the game (`parm_demo="MENU_COMBAT_1..5"`)
-- — and the autotest, which otherwise cannot fire a shot.
--
-- The behaviour is deliberately simple and readable: shoot the nearest thing,
-- keep it at arm's length, back away from the edges, grab loot when nothing is
-- breathing down your neck.

local ai = {}

-- Distances in world pixels, chosen to read well on a 960x640 screen.
local ENGAGE = 460 -- open fire on anything closer than this
local COMFORT = 200 -- retreat from whatever comes closer than this
local LOOT = 300 -- detour for a drop within this
local LOOT_SAFE = 130 -- ...as long as nothing is nearer to us than this
local EDGE = 140 -- steer back inside once this close to the world edge

local function nearest(list, x, y, max_dist)
	local best, best_d2 = nil, (max_dist or math.huge) ^ 2
	for _, e in ipairs(list or {}) do
		local dx, dy = e.x - x, e.y - y
		local d2 = dx * dx + dy * dy
		if d2 < best_d2 then
			best, best_d2 = e, d2
		end
	end
	return best, math.sqrt(best_d2)
end

--- Aim slightly ahead of a mover, so the AI does not look like a turret
-- locked to a point. Creatures walk at the player, so leading along their own
-- heading is enough.
local function lead(target, px, py)
	local dx, dy = px - target.x, py - target.y
	local len = math.max(1, math.sqrt(dx * dx + dy * dy))
	local ahead = math.min(40, len * 0.15)
	return target.x + dx / len * ahead, target.y + dy / len * ahead
end

--- Build a controller for `game`. Returns function(game) -> intent.
function ai.controller()
	local jitter_t, jitter_x, jitter_y = 0, 0, 0

	return function(game)
		local p = game.player
		local world = game.WORLD

		local target, dist = nearest(game.creatures, p.x, p.y, ENGAGE)
		local threat, threat_d = nearest(game.creatures, p.x, p.y, COMFORT)

		-- aim: at the lead point of the current target, with a slow wander so
		-- the crosshair drifts like a hand rather than snapping
		jitter_t = jitter_t - love.timer.getDelta()
		if jitter_t <= 0 then
			jitter_t = 0.25 + love.math.random() * 0.35
			jitter_x = (love.math.random() - 0.5) * 26
			jitter_y = (love.math.random() - 0.5) * 26
		end
		local aim_x, aim_y = p.x + math.cos(p.angle) * 200, p.y + math.sin(p.angle) * 200
		if target then
			aim_x, aim_y = lead(target, p.x, p.y)
			aim_x, aim_y = aim_x + jitter_x, aim_y + jitter_y
		end

		-- loot first: a drop is worth walking to unless something is right on
		-- top of us, and a weapon upgrade is the difference between the demo
		-- looking like a fight and looking like a losing one
		local drop = nearest(game.drops, p.x, p.y, LOOT)
		local can_loot = drop and (not threat or threat_d > LOOT_SAFE)

		local dx, dy = 0, 0
		if can_loot then
			local ax, ay = drop.x - p.x, drop.y - p.y
			local len = math.max(1, math.sqrt(ax * ax + ay * ay))
			dx, dy = ax / len, ay / len
		elseif threat then
			-- back off along the threat's bearing, sliding sideways so the
			-- retreat curves instead of running in a straight line
			local ax, ay = p.x - threat.x, p.y - threat.y
			local len = math.max(1, math.sqrt(ax * ax + ay * ay))
			dx, dy = ax / len, ay / len
			dx, dy = dx - ay / len * 0.7, dy + ax / len * 0.7
			-- the closer it is, the less interest there is in anything else
			local urgency = 1 - math.min(1, threat_d / COMFORT)
			dx, dy = dx * (0.4 + urgency), dy * (0.4 + urgency)
		elseif target then
			-- hold the range: close in on anything dawdling out of reach
			local ax, ay = target.x - p.x, target.y - p.y
			local len = math.max(1, math.sqrt(ax * ax + ay * ay))
			if len > ENGAGE * 0.75 then dx, dy = ax / len, ay / len end
		end

		-- edges: the world is bounded, and a cornered AI reads as a stuck one
		if p.x < EDGE then dx = dx + 1 elseif p.x > world - EDGE then dx = dx - 1 end
		if p.y < EDGE then dy = dy + 1 elseif p.y > world - EDGE then dy = dy - 1 end

		local clip = game.clip_size and game.clip_size() or 0
		return {
			dx = dx,
			dy = dy,
			aim_x = aim_x,
			aim_y = aim_y,
			fire = target ~= nil and dist <= ENGAGE,
			-- top up between fights rather than running dry mid-swarm
			reload = threat == nil and clip > 0 and p.ammo < clip * 0.35,
		}
	end
end

return ai

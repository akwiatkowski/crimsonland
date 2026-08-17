-- Player intent, one frame at a time.
--
-- The game used to poll love.keyboard/love.mouse inline, which meant the only
-- thing that could ever play it was a human at this machine: love.mouse.isDown
-- reads real hardware, so the autotest harness could walk the menus but never
-- pull a trigger, and the original's attract-mode demo had nowhere to plug in.
--
-- Everything the player can express is now one table, produced either by the
-- keyboard and mouse or by a controller the game installs (AI demo, tests):
--
--   { dx, dy,          movement axes, unnormalized (-1..1)
--     aim_x, aim_y,    aim point in WORLD coordinates
--     fire, reload }   held, not edge-triggered — same as the keys they replace

local input = {}

--- function(game) -> intent. nil means the human at the keyboard.
input.controller = nil

local function human(game)
	local dx, dy = 0, 0
	if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
	if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
	if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
	if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end

	local engine = require("src.engine")
	local rx, ry = engine.to_reference(love.mouse.getPosition())
	local camx, camy = game.camera()

	return {
		dx = dx,
		dy = dy,
		aim_x = rx + camx,
		aim_y = ry + camy,
		fire = love.mouse.isDown(1),
		reload = love.keyboard.isDown("r"),
	}
end

--- Install a controller (or nil to hand the game back to the human).
function input.set_controller(fn)
	input.controller = fn
end

function input.intent(game)
	return (input.controller or human)(game)
end

return input

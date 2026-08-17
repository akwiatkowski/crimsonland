-- Exercises the fxs/ DSL interpreter (src/engine/fx.lua) on the main menu:
-- every effect file the pak ships, spawned in screen space where the capture
-- can see it. Gameplay firing cannot be driven from here — the game polls
-- love.mouse.isDown — so shell casings are spawned directly instead.

local fx = require("src.engine.fx")

local function spawn(path, x, y, rot)
	return function() fx.spawn(path, x, y, rot) end
end

return {
	{ t = 2.0, run = spawn("fxs/shells1.lua", 300, 320, 0) },
	{ t = 2.1, run = spawn("fxs/shells1.lua", 300, 320, 90) },
	{ t = 2.2, run = spawn("fxs/shells2.lua", 400, 320, 180) },
	{ t = 2.5, run = spawn("fxs/unlocked-perk.lua", 640, 300, 0) },
	{ t = 3.5, run = spawn("fxs/unlocked-weapon.lua", 640, 300, 0) },
	{ t = 4.5, run = spawn("fxs/unlocked-chapter.lua", 480, 400, 0) },
	{ t = 5.0, run = spawn("fxs/progress_signal.lua", 200, 200, 0) },
	captures = { 2.3, 2.7, 3.7, 4.7, 6.0 },
}

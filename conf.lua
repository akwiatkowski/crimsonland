-- LÖVE configuration for the Crimsonland macOS port.
-- Reference resolution of the original engine: 960x640 (see prog.xml).
-- We render the game world at 960x640 onto a canvas and scale to the window.
--
-- highdpi: without it macOS hands LÖVE a 1x backing store and upscales the
-- whole window itself, so everything arrives on a retina panel blurred twice
-- (canvas upscale + OS upscale). With it we own every device pixel; the
-- canvas is then allocated at the real pixel density (src/engine/init.lua).

function love.conf(t)
	t.identity = "crimsonland-mac"
	t.version = "11.5"
	t.console = false

	t.window.title = "Crimsonland"
	t.window.width = 1440 -- 1.5x reference
	t.window.height = 960
	t.window.resizable = true
	t.window.vsync = 1
	t.window.msaa = 4
	t.window.highdpi = true

	t.modules.physics = false
	t.modules.joystick = true
	t.modules.video = false
	t.modules.thread = false
end

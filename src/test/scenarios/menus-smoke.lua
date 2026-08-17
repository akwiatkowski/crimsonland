-- Walks the screens that carry no data of their own and are filled in by the
-- game: the weapon and perk galleries (icons + hover tooltip), and Statistics.
-- Captures show the panels; a run where they come out empty means the
-- on_screen_enter / on_screen_draw wiring broke.

--- Move the pointer like a player would; the scenario speaks reference
-- coordinates, screens.mousemoved expects window pixels.
local function hover(x, y)
	return function()
		local screens = require("src.engine.screens")
		local ww, wh = love.graphics.getDimensions()
		local scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
		screens.mousemoved(x * scale + (ww - screens.WIDTH * scale) / 2,
			y * scale + (wh - screens.HEIGHT * scale) / 2)
	end
end

return {
	{ t = 2.5, click = "Extras" },
	{ t = 4.0, click = "Weapons" },
	{ t = 5.5, run = hover(137, 165) }, -- first weapon plate
	{ t = 7.0, click = "Back" },
	{ t = 9.0, click = "Perks" },
	{ t = 10.5, run = hover(139, 168) }, -- first perk plate
	{ t = 12.0, click = "Back" },
	{ t = 14.0, click = "Achievements" },
	{ t = 15.5, click = "Statistics" },
	captures = { 6.0, 11.0, 16.5 },
}

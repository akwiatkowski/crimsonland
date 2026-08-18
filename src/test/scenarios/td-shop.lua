-- The HQ, slice two (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-shop
--
-- Walks the whole spending loop from the field: stand on the base, press E,
-- read the prices, buy, come back out. The defender AI holds the line either
-- side of the shopping so the run is a real one rather than a menu test — the
-- point of the HQ being a place is that leaving the perimeter costs something.
--
-- What each report has to show, in order:
--   1. opening lull, $250, base full, one weapon owned
--   2. inside the HQ after a repair (money down, base back up) — the repair is
--      forced by letting wave 1 through first
--   3. in the armoury: a weapon bought (owned = 2) and in hand
--   4. back on the field with the new gun firing

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

--- Park the player on the base so E reaches the HQ, and stop shooting while
-- the shop is open (a controller that keeps firing would empty the clip into
-- the menu).
local function stand_on_base()
	local f = require("mods.towerdefence.game.field")
	require("mods.vanilla.game.input").set_controller(function()
		return { dx = 0, dy = 0, aim_x = f.player.x + 50, aim_y = f.player.y,
			fire = false, reload = false }
	end)
	f.player.x, f.player.y = f.base.x, f.base.y + 40
end

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local owned = 0
		for _ in pairs(f.owned) do owned = owned + 1 end
		local screens = require("src.engine.screens")
		local top = screens.top()
		print(string.format(
			"[shop] %-9s wave=%d base=%d $%d owned=%d hand=%s screen=%s",
			tag, f.wave, math.floor(f.base.hp), f.money, owned,
			f.player.weapon and f.player.weapon.id or "none",
			top and top.name or "?"))
	end
end

-- The shopping happens after wave 3, not before, because that is when there is
-- money: the model's own headline is that repair is all the HQ can sell early,
-- and the run bears it out — at wave 1 the cheapest weapon in the shop is
-- three waves away and the base is what needs the money.
return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 3.0, run = take_over },
	{ t = 6.0, run = report("start") },

	-- three waves of being defended, badly, by one man
	{ t = 60.0, run = report("wave2") },
	{ t = 130.0, run = report("wave3") },

	{ t = 140.0, run = stand_on_base },
	{ t = 142.0, key = "e" }, -- the HQ opens
	{ t = 143.0, run = report("in-hq") },
	{ t = 144.0, click = "Armoury" },
	{ t = 145.5, click = "Weapon_9" }, -- Plasma Rifle at $3320: still out of reach
	{ t = 146.5, run = report("refused") },
	{ t = 147.5, click = "Weapon_3" }, -- Shotgun at $940: the first real upgrade
	{ t = 148.5, run = report("bought") },
	{ t = 149.5, click = "Back" },
	{ t = 150.5, click = "Repair" }, -- whatever is left goes into the walls
	{ t = 151.5, run = report("repaired") },
	{ t = 152.5, click = "Close" },

	{ t = 153.0, run = take_over }, -- back to defending, with the new gun
	{ t = 175.0, run = report("fighting") },
	captures = { 143.5, 147.0, 175.0 },
}

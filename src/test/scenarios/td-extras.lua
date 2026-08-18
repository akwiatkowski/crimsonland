-- The mod's front door, its own art, salvage on the ground, and a wider card
-- pool (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-extras
--
-- Four things at once, because they are cheap to check together and each is
-- one line of evidence:
--
--   MENU     Play on the pak's main menu opens TDMainMenu, not a run. The run
--            starts from "Defend the base", and the menu shows the record.
--   ART      the mount plate resolves out of mods/towerdefence/assets/, which
--            is the mod asset overlay working end to end (the capture is the
--            proof; the log line only says it resolved).
--   SALVAGE  kills leave money on the ground that the player has to walk over,
--            so `drops` is non-empty during a fight and collecting one moves
--            the money on a frame where nothing died.
--   CARDS    the perk pool grew: implementing aura, melee, poison and dodge
--            should push the printed count past the ten it was.

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local assets = require("src.engine.assets")
		local plate = assets.resolve("td/mount-plate.png")
		print(string.format(
			"[extras] %-8s t=%.0f wave=%d $%d kills=%d salvage=%d plate=%s",
			tag, f.active and f.time or -1, f.wave or 0, f.money or 0,
			f.kills or 0, f.drops and #f.drops or -1,
			plate or "MISSING"))
	end
end

local function menu_report()
	local screens = require("src.engine.screens")
	print(("[extras] menu     top=%s"):format((screens.top() or {}).name or "?"))
end

return {
	{ t = 2.5, click = "PlayMenu" }, -- must open the mod's menu, not a run
	{ t = 4.0, run = menu_report },
	{ t = 5.0, click = "NewRun" }, -- this is what starts it
	{ t = 6.0, run = take_over },
	{ t = 6.5, run = report("started") },

	-- a fight, so there are corpses and therefore salvage
	{ t = 40.0, run = report("fighting") },
	{ t = 70.0, run = report("later") },
	{ t = 110.0, run = report("wave2") },
	captures = { 4.5, 40.5, 70.5 },
}

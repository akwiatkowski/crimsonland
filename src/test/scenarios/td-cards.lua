-- Perk cards, slice four (needs MOD=towerdefence):
--
--   make test MOD=towerdefence SCENARIO=td-cards
--
-- Buys training twice and checks the three things that make cards a decision
-- rather than a reward:
--
--   1. the pool is only perks this mod can actually serve — the [td] line
--      printed on first use says how many of the original's 55 survived the
--      filter, and a card that changed nothing would mean the filter is wrong
--   2. taking one moves a modifier the simulation reads (the report prints
--      the player's own damage/fire/reload/speed multipliers)
--   3. the second card costs 1.6x the first, so the sink keeps competing with
--      the perimeter instead of being cleared once

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.towerdefence.game.ai_defender").controller())
end

local function stand_at_base()
	local f = require("mods.towerdefence.game.field")
	f.player.x, f.player.y = f.base.x, f.base.y
	require("mods.vanilla.game.input").set_controller(function()
		return { dx = 0, dy = 0, aim_x = f.player.x + 50, aim_y = f.player.y,
			fire = false, reload = false }
	end)
end

local function report(tag)
	return function()
		local f = require("mods.towerdefence.game.field")
		local m = f.mods
		local cards = require("mods.towerdefence.game.cards")
		local offer = {}
		for _, p in ipairs(f.card_offer or {}) do offer[#offer + 1] = p.name end
		print(string.format(
			"[cards] %-8s $%d taken=%d next=$%d dmg=%.2f fire=%.2f reload=%.2f regen=%.1f chp=%.2f | %s",
			tag, f.money, f.cards_taken, cards.cost(f.cards_taken),
			m.dmg, m.fire, m.reload, m.regen, m.creature_hp,
			#offer > 0 and table.concat(offer, ", ") or "-"))
	end
end

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 3.0, run = take_over },

	-- four waves of income: a card is $500 and the perimeter wants the money too
	{ t = 170.0, run = report("earned") },
	{ t = 172.0, run = stand_at_base },
	{ t = 174.0, key = "e" },
	{ t = 175.0, click = "Cards" },
	{ t = 176.0, run = report("offered") },
	{ t = 177.0, click = "PerkButton_1" },
	{ t = 178.0, run = report("taken") },

	-- The second card costs 1.6x the first, which at this point in a run is
	-- more than what is in the till: go and earn it. That refusal is the sink
	-- working, and the first run of this scenario measured it by accident.
	{ t = 179.0, click = "Close" },
	{ t = 180.0, run = take_over },
	{ t = 260.0, run = report("earned2") },
	{ t = 262.0, run = stand_at_base },
	{ t = 264.0, key = "e" },
	{ t = 265.0, click = "Cards" },
	{ t = 266.0, run = report("offered2") },
	{ t = 267.0, click = "PerkButton_1" },
	{ t = 268.0, run = report("taken2") },
	{ t = 269.0, click = "Close" },
	{ t = 270.0, run = take_over },
	{ t = 290.0, run = report("fighting") },
	captures = { 176.5, 266.5 },
}

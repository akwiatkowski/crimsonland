-- Projectile traits: the verbs that make 38 weapons more than one decision.
--
-- Two things are checked. First that the mod-side overlay actually reaches the
-- parsed weapons — `data.load_weapons` merges `game/traits.lua` by id, and a
-- typo in an id would silently leave a weapon with no traits and no error.
-- Second that the verbs survive contact with a live fight: Weapon Picker rains
-- a fresh gun onto the field every few seconds and the AI keeps firing, so
-- homing, piercing, ricochet, splitting, chaining, slowing and shrinking all
-- run against real creatures rather than against a unit test's fixture.
--
-- `give_random_weapon` (the Random Weapon perk's own entry point) rerolls the
-- gun every few seconds, so the run walks a good part of the roster rather
-- than whichever weapon it happened to start with.

--- Chapter 6, quest 1. The chapter is the point: `weapon_cap` is
-- `6 + 5 * (chapter - 1)`, so a late chapter unlocks nearly the whole roster,
-- and the trait weapons (splitter, blade, shrinkifier, ion cannon) all live
-- high up it — out of reach of an early quest or a short survival run.
-- A quest also keeps spawning, which a custom quest does not: the authored
-- ones clear in seconds and park the run on an end screen.
local function start_late_quest()
	require("mods.vanilla.game.play").start_quest(6, 1, "NORMAL")
	require("src.engine.timeline").begin("Game")
end

local function take_over()
	require("mods.vanilla.game.input").set_controller(
		require("mods.vanilla.game.ai_player").controller())
end

--- The overlay landed on the weapons it names, and on no others by accident.
local function check_overlay()
	local data = require("mods.vanilla.game.data")
	local traits = require("mods.vanilla.game.traits")
	local named, merged, missing = 0, 0, {}
	for id in pairs(traits) do
		named = named + 1
		local w = data.weapons[id]
		if w and w.traits then
			merged = merged + 1
		else
			missing[#missing + 1] = id
		end
	end
	local verbs = {}
	for _, w in pairs(data.weapons) do
		for verb in pairs(w.traits or {}) do
			verbs[verb] = (verbs[verb] or 0) + 1
		end
	end
	local list = {}
	for verb, n in pairs(verbs) do list[#list + 1] = ("%s=%d"):format(verb, n) end
	table.sort(list)
	print(("[traits] overlay %d/%d merged, verbs in play: %s"):format(
		merged, named, table.concat(list, " ")))
	if #missing > 0 then
		-- an id in traits.lua that no weapon answers to: a typo, not a feature
		print("[traits] NOT MERGED (bad id?): " .. table.concat(missing, ", "))
	end
end

--- Reach further up the roster than the picker's own drops manage.
local function reroll_weapon()
	require("mods.vanilla.game.play").give_random_weapon()
end

--- Answer whatever is blocking, on a tick. Gameplay pauses under any UI
-- screen and the AI cannot dismiss one, so without this the run stops at the
-- first level-up and every later report reads the same frozen state. Same
-- routine quest-win uses, for the same reason.
local function answer_whatever_blocks()
	local screens = require("src.engine.screens")
	local harness = require("src.test.harness")
	local top = screens.top()
	if not top then return end
	if top.name == "PickAPerk" then
		harness.click("PerkButton_1")
	elseif top.name == "WeaponUnlocked" or top.name == "PerkUnlocked" then
		harness.click_at(60, 600)
	end
end

local seen = {}

local function report()
	local g = require("mods.vanilla.game.play")
	local w = g.player.weapon
	if w then seen[w.id] = (w.traits ~= nil) end
	local traited = {}
	for id, has in pairs(seen) do
		if has then traited[#traited + 1] = id end
	end
	table.sort(traited)
	print(("[traits] t=%.1f weapon=%s traits=%s kills=%d bullets=%d | with traits so far: %s"):format(
		g.time, w and w.id or "none", tostring(w and w.traits ~= nil),
		g.kills, #g.bullets, table.concat(traited, ",")))
end

local steps = {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, run = start_late_quest },
	{ t = 5.0, run = take_over },
	{ t = 5.2, run = check_overlay },
}

-- answer blockers on a coarse tick, reroll the weapon and report between them
for t = 6, 46, 2 do
	steps[#steps + 1] = { t = t, run = answer_whatever_blocks }
end
for t = 9, 45, 6 do
	steps[#steps + 1] = { t = t + 0.1, run = reroll_weapon }
	steps[#steps + 1] = { t = t + 1.0, run = report }
end
table.sort(steps, function(a, b) return a.t < b.t end)

steps.captures = { 20.0, 34.0, 46.0 }

return steps

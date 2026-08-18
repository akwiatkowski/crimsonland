-- The two rules this cartridge removes, and nothing else.
--
-- It is vanilla's game table with three hooks wrapped, so everything the base
-- game does — modes, perks, end screens, the attract demo — still happens in
-- mods/vanilla/game/play.lua. What changes:
--
--   1. Nothing is locked. Chapter and quest gating is answered by vanilla's
--      save module, which play.lua asks directly, so that is where it is
--      answered differently (see UNLOCK ALL below).
--   2. A run starts with the weapon you point at. Any click that would start
--      a game is held, the weapon gallery is pushed as a picker, and the very
--      same click is replayed once a plate is chosen. Replaying it means this
--      file never has to know what a chapter, a difficulty or an endless mode
--      is: vanilla still starts the run from its own menu state, and the only
--      thing done afterwards is putting the chosen weapon in the player's
--      hands.
--
-- Deliberately NOT changed: drop tables, ammo, damage, difficulty. A weapon
-- has to behave here exactly as it behaves in the game, or testing it here
-- would prove nothing about the game.

local data = require("mods.vanilla.game.data")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")
local vanilla = require("mods.vanilla.game.play")

-- UNLOCK ALL: the debug cartridge's whole point is reaching any map at once.
-- Its profile is its own directory (src/engine/mod.lua), so nothing cleared
-- here can open anything on the profile the base game reads.
save.is_chapter_unlocked = function() return true end
save.is_quest_unlocked = function() return true end

-- Extras -> Weapons: 30 plates, each already carrying its own icon, hover
-- details and a Back button. It is the picker; building a second grid that
-- looked worse would be the only alternative.
local PICKER = "Weapons"
local PICKER_TITLE = "Start with which weapon?"

-- Clicks that start a run, per screen. Everything else is vanilla's.
local LAUNCHES = {
	PlayMenuQuests = { "^Quest_%d+$" },
	PlayMenuCustomQuests = { "^Quest_%d+$" },
	PlayMenuSurvival = { "^Play_%u+$" },
	LevelCompleted = { "^PlayNext$", "^Retry$" },
	LevelFailed = { "^PlayAgain$" },
	SurvivalOver = { "^PlayAgain$" },
}

local function is_launch(screen_name, comp_name)
	for _, pattern in ipairs(LAUNCHES[screen_name] or {}) do
		if comp_name:match(pattern) then return true end
	end
	return false
end

-- the click waiting for a weapon, as { screen, comp }
local pending = nil

--- vanilla's game table, with the hooks below in front of it.
local picker = setmetatable({}, { __index = vanilla })

--- Every weapon shows its own art here: the grid's locked plates mean "not
-- found yet", and in this mod everything is found. Marking them seen in the
-- profile (rather than teaching the gallery a second mode) also keeps the
-- "new weapon unlocked" celebration from firing on every pickup, which in a
-- debugging session is noise.
local function mark_all_seen()
	data.load_all()
	-- pairs, not ipairs: weapon_order is keyed by weapons.xml's own index
	for _, w in pairs(data.weapon_order) do
		if w.id ~= nil then save.game.seen.weapons[w.id] = true end
	end
end

--- Put the picker up for the click now held in `pending`.
--
-- A screen dismissed with Back is still on the stack for the length of its
-- exit transition (0.4s), and screens.push() would hand that dying instance
-- straight back — a launch click in that window would be swallowed. Reversing
-- the exit is what reopening it means, so say so.
local function open_picker()
	local existing = screens.find(PICKER)
	if existing and existing.leaving then
		existing.leaving, existing.entering = false, true
		return existing
	end
	return screens.push(PICKER)
end

--- Replay the held click, then hand the player the weapon they picked.
local function launch_with(entry)
	local click = pending
	pending = nil
	vanilla.on_ui_click(click.screen, click.comp)
	-- A run that did start took the whole screen stack with it (timeline
	-- "Game"), so the picker only needs dismissing when nothing started — an
	-- unimplemented mode button, which vanilla answers by staying put.
	-- The find() is not defensive tidiness: screens.pop(name) falls back to
	-- the top screen when that name is gone, so popping a picker that the
	-- timeline already discarded pops GameCrimsonland instead and the run
	-- starts with no screen to update it.
	if screens.find(PICKER) then screens.pop(PICKER) end
	if not (vanilla.active and vanilla.player) then return end
	vanilla.player.weapon = entry
	vanilla.player.ammo = vanilla.clip_size()
	print(("[allweapons] started with %s"):format(entry.id))
end

function picker.on_ui_click(screen_name, comp_name)
	if screen_name == PICKER then
		local slot = comp_name:match("^Weapon_(%d+)$")
		local entry = pending and slot and gallery.entry_at("weapon", tonumber(slot))
		-- a plate with no art behind it is an empty slot in the data, not a
		-- weapon anyone can be given
		if entry and entry.icon and not entry.unimplemented then
			launch_with(entry)
			return true
		end
		-- leaving the picker abandons the run it was opened for; the pop
		-- itself is vanilla's Back handling, below
		if comp_name == "Back" then pending = nil end
	elseif is_launch(screen_name, comp_name) then
		-- no guard against an already-pending click: the newest one is the one
		-- the player means, and the replay in launch_with calls vanilla
		-- directly, so a started run can never come back through here
		pending = { screen = screen_name, comp = comp_name }
		open_picker()
		return true
	end
	return vanilla.on_ui_click(screen_name, comp_name)
end

function picker.on_screen_enter(screen_name, screen)
	-- before vanilla's hook: it is gallery.fill that reads the seen set
	if screen_name == PICKER then mark_all_seen() end
	vanilla.on_screen_enter(screen_name, screen)
	if screen_name == PICKER and pending and screen.compmap.TimeTitle then
		require("src.engine.comps").set(screen.compmap.TimeTitle,
			"textbox.text", { PICKER_TITLE })
	end
end

return picker

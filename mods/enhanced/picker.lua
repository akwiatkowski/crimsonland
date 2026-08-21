-- Start a run holding whichever weapon you want to try.
--
--   CL_PICK=1 make run MOD=enhanced
--
-- Off unless that variable is set, and that is the whole design decision here.
-- This cartridge's weapons sit at the far end of the drop pool on purpose --
-- `weapon_cap` grows through a run, so arriving last means arriving late --
-- and a picker that was always on would delete the loop that arrival is part
-- of. Every run would begin with the gun you already wanted.
--
-- But that same ordering makes the sixteen almost untestable by hand. A
-- chapter 7 quest reaches pool slot 36, which is five of them; survival needs
-- eleven minutes to reach the first and seventeen for the last; chapter 6
-- reaches none at all. Wanting to feel what a Rail Spike is like should not
-- cost an hour.
--
-- So: the same trick mods/allweapons plays, against both grids. Any click that
-- would start a run is held, the weapon gallery is pushed as a picker, and the
-- very same click is replayed once a plate is chosen. Replaying it is what
-- keeps this file from ever having to know what a chapter, a difficulty or an
-- endless mode is -- vanilla still starts the run from its own menu state, and
-- all that happens afterwards is putting the chosen weapon in the player's
-- hands.
--
-- Two grids rather than one, because there is no thirty-first plate in the
-- pak's: the original's thirty are the first page and the Enhanced button
-- already on that screen (game/arsenal.lua) opens the cartridge's sixteen as
-- the second.

local arsenal = require("mods.enhanced.arsenal")
local data = require("mods.vanilla.game.data")
local gallery = require("mods.vanilla.game.gallery")
local save = require("mods.vanilla.game.save")
local screens = require("src.engine.screens")
local vanilla = require("mods.vanilla.game.play")

local picker = {}

--- Off by default. Read once, here, so nothing downstream has to keep asking.
picker.active = (os.getenv("CL_PICK") or "") ~= ""

local PAK_GRID = "Weapons"
local OWN_GRID = "EnhancedArsenal"
local TITLE = "Start with which weapon?"

-- Clicks that start a run, per screen. Everything else is vanilla's. Same
-- table mods/allweapons keeps, for the same reason: these are the only six
-- screens in the game with a button that begins a fight.
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

--- Every weapon shows its own art while picking: a locked plate means "not
-- found yet", and nothing is unfound when you are choosing from the shelf.
-- Marking them seen in the profile rather than teaching two galleries a second
-- mode also stops the "new weapon unlocked" celebration firing on every
-- pickup, which while testing is noise.
local function mark_all_seen()
	data.load_all()
	-- pairs, not ipairs: weapon_order is keyed by weapons.xml's own index, and
	-- this cartridge's sixteen are up at 64..79
	for _, w in pairs(data.weapon_order) do
		if w.id ~= nil then save.game.seen.weapons[w.id] = true end
	end
end

--- Put the picker up for the click now held in `pending`.
--
-- A screen dismissed with Back is still on the stack for the length of its
-- exit transition, and screens.push() would hand that dying instance straight
-- back -- a launch click in that window would be swallowed. Reversing the exit
-- is what reopening it means, so say so.
local function open_picker()
	local existing = screens.find(PAK_GRID)
	if existing and existing.leaving then
		existing.leaving, existing.entering = false, true
		return existing
	end
	return screens.push(PAK_GRID)
end

--- Replay the held click, then hand the player the weapon they picked.
local function launch_with(entry)
	local click = pending
	pending = nil
	vanilla.on_ui_click(click.screen, click.comp)
	-- A run that did start took the whole screen stack with it (timeline
	-- "Game"), so the grids only need dismissing when nothing started -- an
	-- unimplemented mode button, which vanilla answers by staying put. The
	-- find() is not defensive tidiness: screens.pop(name) falls back to the top
	-- screen when that name is gone, so popping a grid the timeline already
	-- discarded pops GameCrimsonland instead and the run starts with no screen
	-- to update it.
	for _, name in ipairs({ OWN_GRID, PAK_GRID }) do
		if screens.find(name) then screens.pop(name) end
	end
	if not (vanilla.active and vanilla.player) then return end
	vanilla.player.weapon = entry
	vanilla.player.ammo = vanilla.clip_size()
	vanilla.player.reloading = 0
	print(("[picker] started with %s"):format(entry.id))
end

--- First refusal on every click, ahead of the arsenal screen's own handling --
-- which swallows clicks on its grid, because outside a pick a plate there is
-- something to read rather than something to press.
--
-- Returns true when the click was the picker's.
function picker.on_ui_click(screen_name, comp_name)
	if not picker.active then return false end

	if pending and screen_name == PAK_GRID then
		local slot = comp_name:match("^Weapon_(%d+)$")
		local entry = slot and gallery.entry_at("weapon", tonumber(slot))
		-- a plate with no art behind it is an empty slot in the data, not a
		-- weapon anyone can be given
		if entry and entry.icon and not entry.unimplemented then
			launch_with(entry)
			return true
		end
		-- leaving the picker abandons the run it was opened for; the pop itself
		-- is vanilla's Back handling
		if comp_name == "Back" then pending = nil end
		return false -- the Enhanced button is the arsenal screen's own
	end

	if pending and screen_name == OWN_GRID then
		local slot = comp_name:match("^EWeapon_(%d+)$")
		local entry = slot and arsenal.entry_at(tonumber(slot))
		if entry then
			launch_with(entry)
			return true
		end
		if comp_name == "Back" then return false end
		return true -- swallow stray clicks rather than dismissing mid-pick
	end

	if is_launch(screen_name, comp_name) then
		-- no guard against an already-pending click: the newest one is the one
		-- the player means, and the replay in launch_with calls vanilla
		-- directly, so a started run can never come back through here
		pending = { screen = screen_name, comp = comp_name }
		mark_all_seen()
		open_picker()
		return true
	end
	return false
end

--- The grid says what it is for while it is being used as a picker.
function picker.on_screen_enter(screen_name, screen)
	if not (picker.active and pending) then return end
	if screen_name == PAK_GRID and screen.compmap.TimeTitle then
		require("src.engine.comps").set(screen.compmap.TimeTitle,
			"textbox.text", { TITLE })
	end
end

--- Everything unlocked while picking, for the same reason the picker exists:
-- testing a Rail Cannon in chapter five should not cost five chapters. Only
-- under CL_PICK, and this cartridge's profile is its own directory
-- (src/engine/mod.lua), so nothing opened here shows up in the base game.
function picker.install()
	if not picker.active then return end
	save.is_chapter_unlocked = function() return true end
	save.is_quest_unlocked = function() return true end
	print("[picker] CL_PICK: every chapter open, weapon chosen before each run")
end

return picker

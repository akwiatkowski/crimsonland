-- "Enhanced" — vanilla Crimsonland with an arsenal it never had.
--
-- Everything the base game does still happens in mods/vanilla/game/: the
-- chapters, the quests, the endless modes, the 55 perks, the attract demo, the
-- end screens. This cartridge adds two things to it and changes nothing else:
--
--   1. Sixteen weapons at the far end of the weapon pool, each one owning a
--      decision nothing in the original's 31 asks for (mods/enhanced/weapons.lua,
--      and what they do in traits.lua).
--   2. A second trigger for every weapon in the game, the pak's included, paid
--      for out of the same clip (altfire.lua).
--
-- It is a layer, not a fork — the same relationship mods/allweapons has. What
-- makes that possible is six seams in vanilla, none of which any vanilla
-- weapon uses: `data.weapon_overlay`, `traits.deliver`, `traits.trigger`,
-- `traits.on_hit`, `traits.on_end`, and the `game.on_update` /
-- `game.on_world_draw` slots this file fills in below.
--
-- The engine gives every cartridge its own profile directory
-- (src/engine/mod.lua), so a chapter cleared here with a Rail Cannon unlocks
-- nothing on the profile the base game reads, and the weapons discovered here
-- stay in this cartridge's gallery.
--
-- ORDERING. The weapon overlay is registered first, before anything is asked
-- for a weapon. `data.load_weapons` reads `data.weapon_overlay` when it parses
-- — which is the first time a session starts, long after this — but requiring
-- weapons.lua is what pulls in traits.lua and combat.lua, and putting it first
-- means the order of the lines below is not something to think about again.
-- (There is a lesson in this repo about a module-load-time capture that made
-- assignment order load-bearing; this is that lesson applied.)

local data = require("mods.vanilla.game.data")

for _, weapon in ipairs(require("mods.enhanced.weapons")) do
	data.weapon_overlay[#data.weapon_overlay + 1] = weapon
end

local altfire = require("mods.enhanced.altfire")
local arsenal = require("mods.enhanced.arsenal")
local combat = require("mods.enhanced.combat")
local picker = require("mods.enhanced.picker")
local play = require("mods.vanilla.game.play")

arsenal.install()
picker.install() -- no-op unless CL_PICK is set

-- A run's own world. The session clock going backwards is what says a new run
-- started: cheaper than wrapping the six `start_*` functions, and it cannot be
-- forgotten when vanilla gains a seventh mode.
local last_time = 0

play.on_update = function(dt)
	local now = play.time or 0
	if now < last_time then
		combat.reset()
		altfire.reset()
	end
	last_time = now
	combat.update(dt)
	altfire.update(dt)
end

play.on_world_draw = combat.draw

-- Vanilla's game table with three screen hooks in front of it, the way
-- mods/allweapons layers over the same module. Everything not named here falls
-- through to vanilla, which is the point: this cartridge never learns what a
-- chapter, a difficulty or an endless mode is.
local game = setmetatable({}, { __index = play })

function game.on_screen_enter(screen_name, screen)
	play.on_screen_enter(screen_name, screen)
	arsenal.on_screen_enter(screen_name, screen)
	-- last: it retitles a grid the two above have just filled
	picker.on_screen_enter(screen_name, screen)
end

function game.on_screen_draw(screen_name, screen)
	play.on_screen_draw(screen_name, screen)
	arsenal.on_screen_draw(screen_name, screen)
end

function game.on_ui_click(screen_name, comp_name)
	-- picker first: it is choosing off grids the arsenal screen otherwise owns
	-- every click on, and it is a no-op entirely unless CL_PICK is set
	if picker.on_ui_click(screen_name, comp_name) then return true end
	if arsenal.on_ui_click(screen_name, comp_name) then return true end
	return play.on_ui_click(screen_name, comp_name)
end

return {
	name = "enhanced",
	game = game,
	save = require("mods.vanilla.game.save"), -- same format, own directory
}

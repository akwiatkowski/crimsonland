-- Mod loader: the engine is the console, a mod is the cartridge.
--
-- A mod is a directory `mods/<name>/` whose `init.lua` returns a descriptor:
--   {
--     name  = "vanilla",
--     game  = { update(dt), draw(), pause(), unpause(), to_main_menu(),
--               on_ui_click(screen_name, comp_name),
--               on_screen_enter(screen_name, screen) },  -- all optional
--     save  = { load(), flush() },                       -- optional
--     paths = { ASSETS=..., SFX=..., MUSIC=... },        -- optional overrides
--   }
--
-- ORDERING: mod.select() must run before src.engine (or anything that
-- requires src.engine.assets/screens) is loaded — engine modules capture
-- their asset roots from src.engine.paths at require time, and a mod's
-- `paths` overrides are applied by mutating that shared table in place.
-- Consequently a mod that overrides `paths` must not require engine-coupled
-- modules at descriptor load time (return game/save tables whose functions
-- require lazily, or put the overrides first in init.lua).

local mod = {}

mod.current = nil -- the active mod descriptor

function mod.select(name)
	name = name or "vanilla"
	local def = require("mods." .. name)
	assert(type(def) == "table", ("mod '%s' did not return a table"):format(name))
	def.name = def.name or name
	def.game = def.game or {}
	def.save = def.save or {}
	if def.paths then
		local paths = require("src.engine.paths")
		for k, v in pairs(def.paths) do paths[k] = v end
	end
	mod.current = def
	print(("[mod] active: %s"):format(def.name))
	return def
end

--- Call an optional hook on the active mod's game table.
function mod.game_call(fn, ...)
	local m = mod.current
	local f = m and m.game[fn]
	if f then return f(...) end
end

return mod

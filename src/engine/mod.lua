-- Mod loader: the engine is the console, a mod is the cartridge.
--
-- A mod is a directory `mods/<name>/` whose `init.lua` returns a descriptor:
--   {
--     name  = "vanilla",
--     game  = { update(dt), draw(), pause(), unpause(), to_main_menu(),
--               on_ui_click(screen_name, comp_name),
--               on_screen_enter(screen_name, screen),
--               on_screen_draw(screen_name, screen),
--               save_settings() },                       -- all optional
--     save  = { load(), flush() },                       -- optional
--     paths = { ASSETS=..., SFX=..., MUSIC=... },        -- optional overrides
--   }
--
-- PROFILES: a mod's saved state is its own. `paths.USER` is set to
-- APP/mods/<name> before the descriptor loads, so two mods never share a save
-- file, an achievement set or a statistics page.
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
	-- Each cartridge writes to its own room: `paths.USER` becomes
	-- APP/mods/<name>, so saves, achievements and statistics can never leak
	-- from one mod into another's profile. This happens BEFORE the descriptor
	-- is required, because a mod's save module reads paths.USER at require
	-- time (mods/vanilla/game/save.lua does) — same ordering reason as the
	-- asset roots below.
	local paths = require("src.engine.paths")
	paths.USER = paths.APP .. "/mods/" .. name
	-- ...and where its own art lives, searched before the pak by
	-- assets.resolve: `mods/<name>/assets/` mirrors the vendor tree, with an
	-- optional `assets-1080p/` beside it for hi-res twins.
	paths.MOD = "mods/" .. name

	local def = require("mods." .. name)
	assert(type(def) == "table", ("mod '%s' did not return a table"):format(name))
	def.name = def.name or name
	def.game = def.game or {}
	def.save = def.save or {}
	if def.paths then
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

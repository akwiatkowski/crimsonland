-- Game entry point. Engine lives in src/engine; game content is a mod
-- (mods/<name>/, default "vanilla" = the clean-room Crimsonland).
--
-- `--mod=<name>` selects the mod. `--autotest[=scenario]` (make test)
-- additionally loads the automated test harness from src/test — a normal
-- launch never loads any test code.

-- tee prints to a log file: cheap, and makes bug reports self-serving
local logfile = io.open("/tmp/crimsonland_port.log", "w")
local real_print = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	local line = table.concat(parts, "\t")
	real_print(line)
	if logfile then
		logfile:write(line .. "\n")
		logfile:flush()
	end
end

local scenario, modname
for _, a in ipairs(arg or {}) do
	local s = a:match("^%-%-autotest=?(.*)$")
	if s then scenario = (s ~= "" and s or "quest-smoke") end
	modname = a:match("^%-%-mod=(.+)$") or modname
end

-- mod selection must precede loading the engine: a mod's path overrides
-- apply before engine modules capture their asset roots (see engine/mod.lua)
require("src.engine.mod").select(modname or "vanilla")
require("src.engine").start()

if scenario then
	require("src.test.harness").install(scenario)
end

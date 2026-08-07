-- Game entry point. Engine lives in src/engine, gameplay in src/game.
--
-- `--autotest[=scenario]` (make test) additionally loads the automated test
-- harness from src/test — a normal launch never loads any test code.

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

require("src.engine").start()

local scenario
for _, a in ipairs(arg or {}) do
	local m = a:match("^%-%-autotest=?(.*)$")
	if m then scenario = (m ~= "" and m or "quest-smoke") end
end
if scenario then
	require("src.test.harness").install(scenario)
end

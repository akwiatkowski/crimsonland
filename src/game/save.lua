-- Persistence: profiles/statistics/settings (engine platform state) plus
-- gameplay progress (completed quests, survival best) saved as a Lua table
-- in LÖVE's save directory (identity "crimsonland-mac", file "save.lua").

local platform = require("src.engine.platform")

local save = {}

local FILE = "save.lua"

-- gameplay progress with defaults; load() replaces the contents in place
save.game = {
	quests_completed = {}, -- ["chapter.quest"] = true
	survival_best = { score = 0, time = 0, kills = 0 },
}

-- ------------------------------------------------------------- serializer

local function serialize(v, indent)
	local t = type(v)
	if t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "table" then
		local pad = indent .. "\t"
		local parts = {}
		for k, val in pairs(v) do
			local vt = type(val)
			if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
				local key
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					key = k
				else
					key = "[" .. serialize(k, pad) .. "]"
				end
				parts[#parts + 1] = pad .. key .. " = " .. serialize(val, pad)
			end
		end
		return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
	end
	return "nil"
end

-- ------------------------------------------------------------ load / save

function save.load()
	if not love.filesystem.getInfo(FILE) then return end
	local chunk, err = love.filesystem.load(FILE)
	if not chunk then
		print("[save] unreadable save file: " .. tostring(err))
		return
	end
	setfenv(chunk, {}) -- data only: no access to any globals
	local ok, state = pcall(chunk)
	if not ok or type(state) ~= "table" then
		print("[save] corrupt save file: " .. tostring(state))
		return
	end
	if state.platform then platform.import_state(state.platform) end
	if type(state.game) == "table" then
		save.game.quests_completed = state.game.quests_completed or {}
		save.game.survival_best = state.game.survival_best
			or { score = 0, time = 0, kills = 0 }
	end
	print("[save] loaded")
end

function save.flush()
	local state = {
		platform = platform.export_state(),
		game = save.game,
	}
	local ok, err = pcall(love.filesystem.write, FILE,
		"return " .. serialize(state, ""))
	if not ok then print("[save] write failed: " .. tostring(err)) end
end

-- ----------------------------------------------------------- game helpers

function save.mark_quest_completed(chapter, quest)
	save.game.quests_completed[chapter .. "." .. quest] = true
	save.flush()
end

--- Record a survival run; returns true when it is a new best score.
function save.record_survival(score, time, kills)
	local best = save.game.survival_best
	local is_best = score > (best.score or 0)
	if is_best then
		best.score, best.time, best.kills = score, time, kills
	end
	save.flush()
	return is_best
end

return save

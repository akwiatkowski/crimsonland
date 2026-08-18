-- Persistence: profiles/statistics/settings (engine platform state) plus
-- gameplay progress (completed quests, survival best) saved as a Lua table
-- in the active mod's own directory (src/engine/paths.lua: USER, which on
-- macOS is ~/Library/Application Support/Crimsonland/mods/<mod>, and a
-- separate tree under test).
--
-- That directory is outside the LÖVE filesystem sandbox, so this is the one
-- module in the port that reads and writes with plain `io`.

local platform = require("src.engine.platform")
local paths = require("src.engine.paths")

local save = {}

local FILE = paths.USER .. "/save.lua"
-- Older homes of this same file, newest first. Each is read once, as a
-- fallback; the next flush lands the state in the current home and the old
-- copy is never consulted again.
--   APP/save.lua      before profiles were split per mod (engine/mod.lua)
--   LÖVE save dir     before the file moved out of the LÖVE sandbox
-- Both are the base game's profile, so they are only adopted when this module
-- is running as vanilla: a mod that reuses it (mods/allweapons) shares the
-- format, not the progress, and must start on an empty profile. LÖVE's save
-- directory is not split per environment the way paths.APP is either, so a
-- test run must not adopt that one at all.
local IS_BASE = paths.USER == paths.APP .. "/mods/vanilla"
local LEGACY_FILE = IS_BASE and (paths.APP .. "/save.lua") or nil
local LEGACY_LOVE_FILE = (IS_BASE and not paths.TESTING) and "save.lua" or nil

-- gameplay progress with defaults; load() replaces the contents in place
save.game = {
	quests_completed = {}, -- ["chapter.quest"] = true
	survival_best = { score = 0, time = 0, kills = 0 }, -- kept: pre-bests saves
	bests = {}, -- [mode] = { score, time, kills } for every endless mode
	seen = { weapons = {}, perks = {} }, -- first sight drives the unlock screens
	quests_by_difficulty = {}, -- [difficulty]["chapter.quest"] = true
	quests_flawless = {}, -- cleared without taking a scratch
	awarded = {}, -- achievement id -> true
	stats = { -- lifetime totals, the Statistics screen's whole content
		kills = 0,
		shots = 0,
		hits = 0,
		deaths = 0,
		quests_won = 0,
		runs = 0,
		play_time = 0,
		blowtorches = 0, -- Smart Pack Rat counts them
		dens = 0, -- Home Wrecker counts nests destroyed
	},
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

--- The save text and where it came from, or nil when this profile is new.
local function read_save()
	-- a nil LEGACY_FILE simply shortens the list (trailing nil, so #t == 1)
	for _, path in ipairs({ FILE, LEGACY_FILE }) do
		local f = io.open(path, "r")
		if f then
			local text = f:read("*a")
			f:close()
			return text, path
		end
	end
	if LEGACY_LOVE_FILE and love.filesystem.getInfo(LEGACY_LOVE_FILE) then
		return love.filesystem.read(LEGACY_LOVE_FILE),
			love.filesystem.getSaveDirectory() .. "/" .. LEGACY_LOVE_FILE
	end
end

function save.load()
	local text, from = read_save()
	if not text then return end
	local chunk, err = loadstring(text, "@" .. from)
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
		save.game.bests = state.game.bests or {}
		save.game.quests_by_difficulty = state.game.quests_by_difficulty or {}
		save.game.quests_flawless = state.game.quests_flawless or {}
		save.game.awarded = state.game.awarded or {}
		local seen = state.game.seen or {}
		save.game.seen.weapons = seen.weapons or {}
		save.game.seen.perks = seen.perks or {}
		for k, v in pairs(state.game.stats or {}) do save.game.stats[k] = v end
		-- saves written before per-mode bests existed only knew survival
		if not save.game.bests.survival and save.game.survival_best.score > 0 then
			save.game.bests.survival = save.game.survival_best
		end
	end
	print("[save] loaded from " .. from)
	-- Finish the move now rather than at whatever the first flush turns out to
	-- be, so a profile read from the old location exists in the new one even if
	-- this session ends without playing anything.
	if from ~= FILE then save.flush() end
end

-- The save directory is absolute, so love.filesystem cannot create it and
-- there is no mkdir in the Lua standard library. Once per process is enough.
local dir_ready = false
local function ensure_dir()
	if dir_ready then return end
	dir_ready = true
	os.execute(("mkdir -p '%s'"):format(paths.USER))
end

function save.flush()
	local state = {
		platform = platform.export_state(),
		game = save.game,
	}
	ensure_dir()
	local f, err = io.open(FILE, "w")
	if not f then
		print("[save] write failed: " .. tostring(err))
		return
	end
	f:write("return " .. serialize(state, ""))
	f:close()
end

-- ----------------------------------------------------------- game helpers

--- Record a cleared quest. Difficulty and "took no damage" are kept as their
-- own sets because two achievements ask about them (Club Hardcore, Grim
-- Reaper, Not a Scratch) and the plain completed set drives unlock gating.
function save.mark_quest_completed(chapter, quest, difficulty, flawless)
	local key = chapter .. "." .. quest
	save.game.quests_completed[key] = true
	if difficulty and difficulty ~= "NORMAL" then
		save.game.quests_by_difficulty[difficulty] =
			save.game.quests_by_difficulty[difficulty] or {}
		save.game.quests_by_difficulty[difficulty][key] = true
	end
	if flawless then save.game.quests_flawless[key] = true end
	save.flush()
end

-- ------------------------------------------------------------- progression

--- Quests per chapter — the quest grid in ui/play-menu-quests.lua has ten
-- buttons and quests.lua puts the boss on the tenth.
save.QUESTS_PER_CHAPTER = 10

function save.is_quest_completed(chapter, quest)
	return save.game.quests_completed[chapter .. "." .. quest] == true
end

--- A chapter opens once the previous chapter's boss quest is cleared; the
-- first one is always open.
function save.is_chapter_unlocked(chapter)
	if chapter <= 1 then return true end
	return save.is_quest_completed(chapter - 1, save.QUESTS_PER_CHAPTER)
end

--- Within an open chapter, a quest opens once the one before it is cleared.
function save.is_quest_unlocked(chapter, quest)
	if not save.is_chapter_unlocked(chapter) then return false end
	if quest <= 1 then return true end
	return save.is_quest_completed(chapter, quest - 1)
end

-- --------------------------------------------------------- scores and stats

--- Endless modes the High Scores screen lists, in menu order.
save.ENDLESS_MODES = {
	{ id = "survival", label = "Survival" },
	{ id = "rush", label = "Rush" },
	{ id = "blitz", label = "Blitz" },
	{ id = "waves", label = "Waves" },
	{ id = "nukefism", label = "Nukefism" },
	{ id = "weaponpicker", label = "Weapon Picker" },
}

function save.best(mode)
	return save.game.bests[mode]
end

--- First sight of a weapon or perk, per profile. Returns true the first time,
-- which is when the unlock screens are worth showing.
function save.mark_seen(kind, id)
	local set = save.game.seen[kind]
	if not set or id == nil or set[id] then return false end
	set[id] = true
	save.flush()
	return true
end

--- Record an endless run; returns true when it beats that mode's best score.
function save.record_run(mode, score, time, kills)
	local best = save.game.bests[mode]
	local is_best = not best or score > (best.score or 0)
	if is_best then
		save.game.bests[mode] = { score = score, time = time, kills = kills }
		if mode == "survival" then save.game.survival_best = save.game.bests[mode] end
	end
	save.flush()
	return is_best
end

--- Fold a finished session into the lifetime totals the Statistics screen shows.
function save.record_session(game)
	local s = save.game.stats
	s.runs = s.runs + 1
	s.kills = s.kills + (game.kills or 0)
	s.shots = s.shots + (game.shots or 0)
	s.hits = s.hits + (game.hits or 0)
	s.play_time = s.play_time + (game.time or 0)
	if game.outcome == "lost" then s.deaths = s.deaths + 1 end
	if game.outcome == "won" and game.mode == "quest" then
		s.quests_won = s.quests_won + 1
	end
	save.flush()
end

return save

-- Achievements: the pak ships them in achievements.xml with art, names, point
-- values and both phrasings of each description, and nothing ever awarded one.
--
-- 22 are active — a 23rd (co-op's Friend in Need) is commented out in the
-- shipped data, which is exactly why the screen has 22 plates for it.
--
-- The XML is the definition; the *conditions* lived in the C++ side, so the
-- rules below are read off each achievement's own description text. Two ask
-- about things this port does not have (the Shock Chain powerup, gib counting)
-- and are listed with no rule — shown on the screen, never awarded, rather
-- than quietly dropped.

local comps = require("src.engine.comps")
local save = require("mods.vanilla.game.save")
local xml = require("src.xml")

local paths = require("src.engine.paths")

local achievements = {}

local LOCKED = { 0.32, 0.32, 0.34, 1 }

achievements.list = {} -- ordered as the XML declares them
achievements.by_id = {}

local function quests_cleared(chapter, set)
	for q = 1, save.QUESTS_PER_CHAPTER do
		if not set[chapter .. "." .. q] then return false end
	end
	return true
end

local function all_chapters(set)
	for c = 1, 7 do
		if not quests_cleared(c, set) then return false end
	end
	return true
end

local function score_at_least(mode, points)
	return function()
		local best = save.best(mode)
		return best ~= nil and (best.score or 0) >= points
	end
end

local function chapter_done(chapter)
	return function() return quests_cleared(chapter, save.game.quests_completed) end
end

-- Conditions, read from each achievement's own description. `session` is the
-- finished game table when one just ended, so per-run conditions can be asked.
local RULES = {
	CHAPTER_1 = chapter_done(1),
	CHAPTER_2 = chapter_done(2),
	CHAPTER_3 = chapter_done(3),
	CHAPTER_4 = chapter_done(4),
	CHAPTER_5 = chapter_done(5),
	CHAPTER_6 = chapter_done(6),
	CHAPTER_7 = chapter_done(7),

	HARDCORE = function()
		return all_chapters(save.game.quests_by_difficulty.HARDCORE or {})
	end,
	GRIM = function()
		return all_chapters(save.game.quests_by_difficulty.GRIM or {})
	end,
	NOT_A_SCRATCH = function()
		return all_chapters(save.game.quests_flawless)
	end,

	SURVIVOR_1 = score_at_least("survival", 250000),
	SURVIVOR_2 = score_at_least("survival", 500000),
	ARMS_RACE = score_at_least("weaponpicker", 100000),
	RUSH = score_at_least("rush", 50000),
	BLITZ = score_at_least("blitz", 250000),
	NUKEFISM = score_at_least("nukefism", 75000),

	--- "Unlock all Perks" — against the roster this port implements.
	PERKY = function()
		for _, p in ipairs(require("mods.vanilla.game.perks").list) do
			if not save.game.seen.perks[p.id] then return false end
		end
		return true
	end,

	PACK_RAT = function() return save.game.stats.blowtorches >= 50 end,
	HOME_WRECKER = function() return save.game.stats.dens >= 500 end,

	--- "Get 100 percent hit accuracy in Chapter 2 Quest 5" — a run condition.
	IMPALER = function(session)
		return session ~= nil and session.mode == "quest" and session.chapter == 2
			and session.outcome == "won" and (session.shots or 0) > 0
			and session.hits == session.shots
	end,

	-- No rule, and honestly so:
	--   GIBBER          gibbing is not counted separately from kills
	--   CHAIN_MASTER    the Shock Chain powerup does not exist in this port
}

-- ------------------------------------------------------------------ loading

function achievements.load()
	if #achievements.list > 0 then return achievements.list end
	local text = love.filesystem.read(paths.ASSETS .. "/achievements/achievements.xml")
	if not text then return achievements.list end
	local root = xml.parse(text)
	local arr = xml.array(root, "ACHIEVEMENTS") or root
	for _, node in ipairs(arr and arr.children or {}) do
		local a = node.attrs
		if a and a.id and a.name then
			local entry = {
				id = a.id,
				name = a.name,
				icon = a.icon,
				points = tonumber(a.points) or 0,
				-- desc_pre is "how to get it", desc_post "what you did"
				desc = a.desc_pre or "",
				desc_done = a.desc_post or a.desc_pre or "",
				rule = RULES[a.id],
			}
			achievements.list[#achievements.list + 1] = entry
			achievements.by_id[a.id] = entry
		end
	end
	return achievements.list
end

-- ------------------------------------------------------------------ awarding

function achievements.is_awarded(id)
	return save.game.awarded[id] == true
end

--- Check every rule; returns the entries awarded by this call. `session` is a
-- finished game table when one just ended (nil elsewhere).
function achievements.evaluate(session)
	achievements.load()
	local won = {}
	for _, a in ipairs(achievements.list) do
		if a.rule and not achievements.is_awarded(a.id) then
			local ok, got = pcall(a.rule, session)
			if ok and got then
				save.game.awarded[a.id] = true
				won[#won + 1] = a
				print(("[achievement] %s — %s"):format(a.name, a.desc))
			end
		end
	end
	if #won > 0 then save.flush() end
	return won
end

--- "n of m unlocked, p points" — what the screen says when nothing is hovered.
function achievements.summary()
	achievements.load()
	local got, points = 0, 0
	for _, a in ipairs(achievements.list) do
		if achievements.is_awarded(a.id) then
			got = got + 1
			points = points + a.points
		end
	end
	return ("%d of %d unlocked"):format(got, #achievements.list),
		("%d points"):format(points)
end

-- ------------------------------------------------------------------- screen

--- ITEM_0..ITEM_21 is the grid the C++ side filled, one plate per active
-- achievement, in XML order.
function achievements.prepare(screen_name, screen)
	if screen_name ~= "Achievements" then return end
	achievements.load()
	local shown = 0
	for i, a in ipairs(achievements.list) do
		local comp = screen.compmap["ITEM_" .. (i - 1)]
		if comp then
			shown = shown + 1
			if a.icon then comps.set(comp, "button.bm_icon", { a.icon }) end
			if not achievements.is_awarded(a.id) then
				for _, s in ipairs({ "idle", "over", "pressed" }) do
					comps.set(comp, "button.bitmap_color_" .. s, LOCKED)
				end
			end
		end
	end
	if shown < #achievements.list then
		print(("[achievements] %d of %d fit the screen's grid")
			:format(shown, #achievements.list))
	end
end

--- The layout carries ItemName and ItemDesc textboxes that the C++ side filled
-- as the pointer moved over the grid; with nothing hovered they show the score.
function achievements.draw(screen_name, screen)
	if screen_name ~= "Achievements" then return end
	local name, desc = achievements.summary()

	local hover = screen._hover_comp
	local n = hover and hover.name:match("^ITEM_(%d+)$")
	local a = n and achievements.list[tonumber(n) + 1]
	if a then
		local awarded = achievements.is_awarded(a.id)
		name = ("%s (%d pts)"):format(a.name, a.points)
		desc = awarded and a.desc_done or a.desc
		if not a.rule then desc = desc .. " [not tracked by this port]" end
	end

	local function put(comp_name, text)
		local comp = screen.compmap[comp_name]
		if comp then comps.set(comp, "textbox.text", { text }) end
	end
	put("ItemName", name)
	put("ItemDesc", desc)
end

return achievements

-- Contents for the screens the pak ships as empty frames.
--
-- ui/high-scores.lua and ui/statistics.lua lay out a panel, a title and a
-- Marker — the C++ side painted the actual rows inside that marker, so the
-- layout scripts carry no data at all. The save file has had the numbers all
-- along; this draws them inside the panel.

local comps = require("src.engine.comps")
local font = require("src.engine.font")
local save = require("mods.vanilla.game.save")

local records = {}

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

local BONE = { 0.88, 0.85, 0.78, 1 }
local BRASS = { 0.85, 0.68, 0.28, 1 }
local DIM = { 0.55, 0.53, 0.5, 1 }

local ROW_H = 26

--- mm:ss — runs are minutes long, so hours would be noise.
local function clock(seconds)
	local s = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function commas(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

--- Content box in reference coordinates, measured from the screen's panel art.
--
-- These layouts do carry a Marker where the C++ side anchored its drawing, but
-- comps.screen_rect ignores ancestor alignment (it says so), and for these
-- markers it reports a box running off the panel and past the bottom of the
-- screen. The panel Image is unambiguous, so inset that instead: clear of the
-- frame on both sides and below the title.
local PANEL_INSET_X = 70
local PANEL_INSET_TOP = 100
local PANEL_INSET_BOTTOM = 130 -- leaves the Back button alone

local function content_box(screen)
	local panel = screen.compmap["panel"]
	if not panel then return nil end
	local x, y, w, h = comps.screen_rect(panel)
	if w < 100 or h < 100 then return nil end
	return x + PANEL_INSET_X, y + PANEL_INSET_TOP,
		w - PANEL_INSET_X * 2, h - PANEL_INSET_TOP - PANEL_INSET_BOTTOM
end

local function row(label, value, x, y, w, value_color)
	font.draw(F_SMALL, label, x, y, DIM)
	local vw = font.measure(F_SMALL, value)
	font.draw(F_SMALL, value, x + w - vw, y, value_color or BONE)
end

-- --------------------------------------------------------------- high scores

function records.draw_high_scores(screen)
	local x, y, w = content_box(screen)
	if not x then return end

	font.draw(F_SMALL, "MODE", x, y, DIM)
	local head = "SCORE"
	font.draw(F_SMALL, head, x + w - font.measure(F_SMALL, head), y, DIM)
	y = y + ROW_H

	for _, mode in ipairs(save.ENDLESS_MODES) do
		local best = save.best(mode.id)
		if best then
			font.draw(F_SMALL, mode.label, x, y, BONE)
			local detail = ("%s   %d kills"):format(clock(best.time), best.kills or 0)
			font.draw(F_SMALL, detail, x + 170, y, DIM)
			local score = commas(best.score)
			font.draw(F_MEDIUM, score, x + w - font.measure(F_MEDIUM, score), y - 4, BRASS)
		else
			font.draw(F_SMALL, mode.label, x, y, DIM)
			local none = "not played"
			font.draw(F_SMALL, none, x + w - font.measure(F_SMALL, none), y, DIM)
		end
		y = y + ROW_H + 6
	end
end

-- ---------------------------------------------------------------- statistics

function records.draw_statistics(screen)
	local x, y, w = content_box(screen)
	if not x then return end

	local s = save.game.stats
	local completed = 0
	for _ in pairs(save.game.quests_completed) do completed = completed + 1 end
	local total = save.QUESTS_PER_CHAPTER * 7 -- chapters in chapters.xml
	local accuracy = s.shots > 0 and (s.hits / s.shots * 100) or 0

	row("Rounds played", commas(s.runs), x, y, w); y = y + ROW_H
	row("Time played", clock(s.play_time), x, y, w); y = y + ROW_H
	row("Quests completed", ("%d / %d"):format(completed, total), x, y, w)
	y = y + ROW_H
	row("Creatures killed", commas(s.kills), x, y, w, BRASS); y = y + ROW_H
	row("Shots fired", commas(s.shots), x, y, w); y = y + ROW_H
	row("Accuracy", ("%.1f%%"):format(accuracy), x, y, w); y = y + ROW_H
	row("Deaths", commas(s.deaths), x, y, w); y = y + ROW_H

	local best = save.best("survival")
	if best then
		y = y + 8
		row("Best survival", commas(best.score), x, y, w, BRASS)
	end
end

-- Controls on high-scores.lua that belong to features this port does not have:
-- online leaderboards, per-mode filtering (we list every mode at once) and the
-- co-op player selector. Left visible they would be dead buttons.
-- Hiding an aligner takes its children with it (comps.draw stops at invisible).
local HIGH_SCORE_UNUSED = {
	"GameMode", "Filter", "ShowGlobalHighscores", "Details", "Players", "Play",
	"Panel_GameMode", "Panel_Filter", "Panel_Players",
	"aligner_game_mode", "aligner_filter", "aligner_players",
	-- gamepad hint textboxes: their text is button-glyph markup we do not parse,
	-- so they render as raw "|FFFFFF SRC='GAMEPAD..." across the top
	"gamepad_help1", "gamepad_help2",
}

--- Called on screen entry, before anything is drawn.
function records.prepare(screen_name, screen)
	if screen_name ~= "HighScores" then return end
	for _, name in ipairs(HIGH_SCORE_UNUSED) do
		local comp = screen.compmap[name]
		if comp then comps.set(comp, "visible", { false }) end
	end
	local title = screen.compmap["CategoryTitle"]
	if title then comps.set(title, "textbox.text", { "High Scores - Local" }) end
end

function records.draw(screen_name, screen)
	if screen_name == "HighScores" then
		records.draw_high_scores(screen)
	elseif screen_name == "Statistics" then
		records.draw_statistics(screen)
	end
end

return records

-- In-game HUD, reassembled from the original 2014 art that ships in the
-- pak: health pie (game/health_pie_*.png), aim circle/dot crosshair set,
-- progress-bar XP strip, level-up ring, white vignette. The design rule:
-- state without reading — the crosshair cluster carries reload feedback so
-- the eyes never leave the fight.
--
-- Palette (from the game's own art):
--   bone   #E8E2D5  primary text
--   blood  #B3202A  health, danger
--   brass  #C9A24B  ammo and score numerals
--   toxic  #7FB94F  powerup timers
--   smoke  black @ 0.55  text backings

local assets = require("src.engine.assets")
local font = require("src.engine.font")

local hud = {}

local W, H = 960, 640

local BONE = { 0.91, 0.89, 0.84 }
local BLOOD = { 0.70, 0.13, 0.16 }
local BRASS = { 0.79, 0.64, 0.29 }
local TOXIC = { 0.50, 0.73, 0.31 }

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"
local F_AMMO = "fonts/ammo.mft"

-- Below this half-angle (radians, ~2.9 degrees) a weapon gets the tight aim
-- ring: pistol, gauss family, blade gun and the rifles, but not the miniguns
-- or any shotgun.
local TIGHT_SPREAD = 0.05

local function set(c, a)
	love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- text helpers: font.draw is left-aligned; measure to center/right-align
local function text_center(path, str, cx, y, color)
	local w = font.measure(path, str)
	font.draw(path, str, cx - w / 2, y, color)
end

local function text_right(path, str, rx, y, color)
	local w = font.measure(path, str)
	font.draw(path, str, rx - w, y, color)
end

-- ------------------------------------------------------------- crosshair

--- Crosshair at the mouse (reference coords): the original aim circle and
-- dot; while reloading the dot swaps and an arc sweeps the circle closed.
function hud.draw_cursor(game)
	-- a UI screen over the session owns the pointer: the OS cursor is back
	-- (play.game.draw) and this one would only sit frozen where aiming stopped
	if game.ui_screen() then return end
	local p = game.player
	-- follow the aim point rather than the mouse: whoever is playing (human,
	-- AI demo, test) moves the crosshair
	local camx, camy = game.camera()
	local mx, my = (p.aim_x or p.x) - camx, (p.aim_y or p.y) - camy

	-- Two aim rings ship, and the difference between them is accuracy: the
	-- tight one for a gun that puts its round where the crosshair is, the wide
	-- one for a gun that throws a fan. `w.spread` (data.lua) is the same cone
	-- the shot actually leaves in, so the crosshair stops being decoration and
	-- starts telling you what this weapon will do.
	local tight = p.weapon and p.weapon.spread and p.weapon.spread < TIGHT_SPREAD
	local circle = assets.image(tight and "game/aim_small_circle.png"
		or "game/aim_circle.png")
	local reloading = p.reloading and p.reloading > 0
	local dot = assets.image(reloading and "game/aim_dot_reloading.png"
		or "game/aim_dot.png")

	love.graphics.setColor(1, 1, 1, 0.9)
	if circle then
		love.graphics.draw(circle, mx, my, 0, 1, 1,
			circle:getWidth() / 2, circle:getHeight() / 2)
	end
	if dot then
		love.graphics.draw(dot, mx, my, 0, 1, 1,
			dot:getWidth() / 2, dot:getHeight() / 2)
	end

	-- reload sweep: an arc closing clockwise as the reload completes
	if reloading and p.reload_total and p.reload_total > 0 then
		local frac = 1 - (p.reloading / p.reload_total)
		local r = (circle and circle:getWidth() / 2 or 16) + 4
		set(BRASS, 0.9)
		love.graphics.setLineWidth(3)
		love.graphics.arc("line", "open", mx, my,
			r, -math.pi / 2, -math.pi / 2 + frac * math.pi * 2, 24)
		love.graphics.setLineWidth(1)
	end
	love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------ components

local function draw_health(game)
	local p = game.player
	local cx, cy, r = 52, H - 74, 30
	local frac = math.max(0, p.hp / p.max_hp)

	local bg = assets.image("game/health_pie_1.png")
	if bg then
		love.graphics.setColor(1, 1, 1, 0.9)
		local s = (r * 2 + 8) / bg:getWidth()
		love.graphics.draw(bg, cx, cy, 0, s, s, bg:getWidth() / 2, bg:getHeight() / 2)
	else
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.circle("fill", cx, cy, r + 3)
	end

	-- health as a pie wedge, draining clockwise from 12 o'clock
	if frac > 0 then
		set(BLOOD, 0.92)
		love.graphics.arc("fill", "pie", cx, cy, r,
			-math.pi / 2, -math.pi / 2 + frac * math.pi * 2, 32)
	end

	-- Shield runs on a timer and until now said so only as a chip above the
	-- dial. health_pie_2 is the smooth twin of the segmented ring behind the
	-- health -- a second gauge for a second number, which is what it looks
	-- like -- so the shield drains its own ring around the same dial.
	local shield = game.effects.SHIELD
	if shield then
		local def
		for _, pu in ipairs(game.POWERUPS or {}) do
			if pu.id == "SHIELD" then def = pu break end
		end
		local frac = def and def.dur > 0 and math.min(1, shield / def.dur) or 1
		local ring = assets.image("game/health_pie_2.png")
		if ring then
			love.graphics.setColor(0.45, 0.8, 1, 0.9)
			local s = (r * 2 + 20) / ring:getWidth()
			love.graphics.draw(ring, cx, cy, 0, s, s,
				ring:getWidth() / 2, ring:getHeight() / 2)
		end
		-- and the time left as an arc over it
		love.graphics.setColor(0.45, 0.8, 1, 0.95)
		love.graphics.setLineWidth(3)
		love.graphics.arc("line", "open", cx, cy, r + 10,
			-math.pi / 2, -math.pi / 2 + frac * math.pi * 2, 32)
		love.graphics.setLineWidth(1)
	end

	local _, fh = font.measure(F_MEDIUM, "0")
	text_center(F_MEDIUM, tostring(math.max(0, math.floor(p.hp))),
		cx, cy - fh / 2, BONE)
end

-- The announcement banner: two halves of one plate, each fading at one end,
-- butted together with the text across the seam.
local BANNER_TIME = 1.6

local function draw_banner(game)
	local b = game.banner
	if not b then return end
	-- up fast, hold, then out
	local k = math.min(1, b.t / 0.15) * math.min(1, (BANNER_TIME - b.t) / 0.45)
	if k <= 0 then return end

	local plate = assets.image("game/bonus_text_holder.png")
	local mirror = assets.image("game/bonus_text_holder_mirror.png")
	local cy = H * 0.26
	local tw = font.measure(F_MEDIUM, b.text)
	if plate and mirror then
		local pw, ph = plate:getWidth(), plate:getHeight()
		-- stretch the pair to whatever the line needs, so a long announcement
		-- does not hang off the ends of its own plate
		local sx = math.max(1, (tw + 70) / (pw * 2))
		love.graphics.setColor(1, 1, 1, 0.85 * k)
		-- Each half is solid at one end and fades at the other, and the solid
		-- ends are the ones that have to meet: butted the other way the banner
		-- has a hole exactly where the text sits. Plate left, mirror right.
		love.graphics.draw(plate, W / 2 - pw * sx, cy - ph / 2, 0, sx, 1)
		love.graphics.draw(mirror, W / 2, cy - ph / 2, 0, sx, 1)
	end
	local _, fh = font.measure(F_MEDIUM, b.text)
	font.draw(F_MEDIUM, b.text, W / 2 - tw / 2, cy - fh / 2, BONE)
	love.graphics.setColor(1, 1, 1, 1)
end

local function draw_weapon(game)
	local p = game.player
	local rx, by = W - 16, H - 40

	if not p.weapon then
		text_right(F_MEDIUM, "BARE HANDS", rx, by - 30, BONE)
		return
	end

	-- ammo.mft is a 7-segment display: digits carry their own unlit plate, and
	-- there is no '/' in it, so the magazine size rides alongside in the small
	-- font instead of inside the counter.
	local clip_str = ("/%d"):format(game.clip_size())
	local clip_w = font.measure(F_SMALL, clip_str)
	font.draw(F_SMALL, clip_str, rx - clip_w, by - 24, BONE)
	local ammo_str = ("%d"):format(p.ammo)
	text_right(F_AMMO, ammo_str, rx - clip_w - 4, by - 34, BRASS)
	text_right(F_SMALL, p.weapon.name or p.weapon.id, rx, by - 52, BONE)

	local icon = assets.image(p.weapon.icon)
	if icon then
		love.graphics.setColor(1, 1, 1, 0.95)
		local s = math.min(1, 40 / icon:getHeight())
		love.graphics.draw(icon,
			rx - clip_w - font.measure(F_AMMO, ammo_str) - 18 - icon:getWidth() * s,
			by - 36, 0, s, s)
	end

	if p.reloading > 0 then
		text_right(F_SMALL, "RELOADING", rx, by - 8, BLOOD)
	end
end

local function draw_score(game)
	font.draw(F_SMALL, "SCORE", 16, 10, BONE)
	font.draw(F_MEDIUM, tostring(math.floor(game.score)), 16, 26, BRASS)
	if game.kills_goal then
		font.draw(F_SMALL, ("KILLS %d / %d"):format(game.kills, game.kills_goal),
			16, 56, BONE)
	else
		font.draw(F_SMALL, ("KILLS %d"):format(game.kills), 16, 56, BONE)
	end
end

local function draw_mode_tag(game)
	local tag
	if game.mode == "quest" then
		local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }
		-- the .mft fonts are LATIN-1 and carry no middle dot, so use a dash
		tag = ("%s - %d   %s"):format(ROMAN[game.chapter] or game.chapter,
			game.quest, game.difficulty)
	else
		local label = game.mode:upper()
		if game.mode == "waves" then
			label = ("WAVE %d"):format(math.max(1, game.wave or 1))
		end
		tag = ("%s  %d:%02d"):format(label,
			math.floor(game.time / 60), math.floor(game.time % 60))
	end
	text_right(F_SMALL, tag, W - 16, 10, BONE)
end

-- the Death Clock perk: an unmissable center-top countdown
local function draw_death_clock(game)
	if not game.death_clock then return end
	text_center(F_MEDIUM, ("DEATH CLOCK  %.1f"):format(math.max(0, game.death_clock)),
		W / 2, 12, BLOOD)
end

-- XP toward the next perk: the shipped progress-bar art along the bottom
-- edge, level numeral at its right end
local function draw_xp(game)
	local bw, bh = 320, 10
	local x, y = (W - bw) / 2, H - 18
	local frac = math.min(1, game.xp / game.xp_next)

	local empty = assets.image("game/progress-bar-empty.png")
	local full = assets.image("game/progress-bar-full.png")
	if empty and full then
		love.graphics.setColor(1, 1, 1, 0.85)
		love.graphics.draw(empty, x, y, 0, bw / empty:getWidth(), bh / empty:getHeight())
		if frac > 0 then
			-- crop the fill image to the earned fraction (HUD draws at
			-- identity transform, so scissor coords equal canvas coords)
			love.graphics.setScissor(x, y, math.max(1, bw * frac), bh)
			love.graphics.draw(full, x, y, 0, bw / full:getWidth(), bh / full:getHeight())
			love.graphics.setScissor()
		end
	else
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", x, y, bw, bh)
		set(BLOOD)
		love.graphics.rectangle("fill", x, y, bw * frac, bh)
	end
	font.draw(F_SMALL, ("LV %d"):format(game.level), x + bw + 10, y - 4, BONE)
end

-- active powerups: icon + a toxic-green time sliver, stacked above health
local function draw_effects(game)
	local x, y = 96, H - 96
	for id, left in pairs(game.effects) do
		local def
		for _, pu in ipairs(game.POWERUPS or {}) do
			if pu.id == id then def = pu break end
		end
		local icon = def and assets.image(def.icon)
		if icon then
			love.graphics.setColor(1, 1, 1, 0.95)
			local s = 28 / icon:getHeight()
			love.graphics.draw(icon, x, y, 0, s, s)
			local frac = def.dur > 0 and math.min(1, left / def.dur) or 1
			set(TOXIC)
			love.graphics.rectangle("fill", x, y + 30, 28 * frac, 3)
		else
			font.draw(F_SMALL, ("%s %ds"):format(id, math.ceil(left)), x, y, TOXIC)
		end
		x = x + 36
	end
	love.graphics.setColor(1, 1, 1, 1)
end

-- low health: the shipped vignette tinted blood, breathing slowly —
-- intensity ramps as hp falls below 35%
local function draw_danger(game)
	local p = game.player
	local frac = p.hp / p.max_hp
	if frac >= 0.35 or game.outcome == "won" then return end
	local danger = 1 - frac / 0.35
	local breath = 0.75 + 0.25 * math.sin(game.time * 2.4)
	local vin = assets.image("game/white-vignette.png")
	if vin then
		love.graphics.setColor(BLOOD[1], BLOOD[2] * 0.5, BLOOD[3] * 0.5,
			0.45 * danger * breath)
		love.graphics.draw(vin, 0, 0, 0, W / vin:getWidth(), H / vin:getHeight())
		love.graphics.setColor(1, 1, 1, 1)
	end
end

local function draw_outcome(game)
	if not game.outcome then return end
	local msg = game.outcome == "won" and "QUEST COMPLETED" or "YOU DIED"
	local y = H / 2 - 24
	love.graphics.setColor(0, 0, 0, 0.55)
	love.graphics.rectangle("fill", 0, y - 14, W, 62)
	text_center(F_AMMO, msg, W / 2, y,
		game.outcome == "won" and BONE or BLOOD)
end

--- Level-up ring: expands from the player for ~0.8s (world coords, so it
-- is drawn from play.lua inside the camera transform).
function hud.draw_levelup_ring(game, px, py)
	local age = game.levelup_t and (game.time - game.levelup_t) or nil
	if not age or age > 0.8 then return end
	local ring = assets.image("game/levelup-ring.png")
	if not ring then return end
	local s = 0.3 + age * 2.2
	love.graphics.setBlendMode("add")
	love.graphics.setColor(1, 1, 1, 1 - age / 0.8)
	love.graphics.draw(ring, px, py, 0, s, s,
		ring:getWidth() / 2, ring:getHeight() / 2)
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
end

--- Shield bubble: the ring the pak ships as game/shield_pie.png, turning
-- slowly around the player while SHIELD runs. World coords, so play.lua
-- draws it inside the camera transform like the level-up ring.
function hud.draw_shield(game, px, py)
	local left = game.effects.SHIELD
	if not left then return end
	local ring = assets.image("game/shield_pie.png")
	if not ring then return end
	-- steady while it holds, flickering through the last second so the loss
	-- is seen coming rather than noticed by being bitten
	local a = (left < 1) and (0.35 + 0.45 * math.abs(math.sin(game.time * 18))) or 0.85
	-- the ring art is 55px and the trooper about 40 of his 64px frame, so it
	-- has to be scaled well past both to read as a barrier around him rather
	-- than a belt he is wearing
	local s = (92 / ring:getWidth()) * (1 + 0.04 * math.sin(game.time * 4))
	love.graphics.setBlendMode("add")
	love.graphics.setColor(1, 1, 1, a)
	love.graphics.draw(ring, px, py, game.time * 0.5, s, s,
		ring:getWidth() / 2, ring:getHeight() / 2)
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------------ main

--- Screen-space HUD; call after the camera transform is popped.
function hud.draw(game)
	draw_danger(game)
	draw_health(game)
	draw_weapon(game)
	draw_score(game)
	draw_mode_tag(game)
	draw_death_clock(game)
	draw_xp(game)
	draw_effects(game)
	draw_banner(game)
	hud.draw_cursor(game)
	draw_outcome(game)
	love.graphics.setColor(1, 1, 1, 1)
end

return hud

-- The tower-defence HUD.
--
-- It answers four questions, in the order they matter here: how is the base,
-- what is coming, what can I afford, and how am I. Note that the player's own
-- health is *last* — this mod's fail state is the base, and the HUD has to say
-- so or the player will keep playing Crimsonland.
--
-- The wave readout is not decoration. The design's whole loop is "read what is
-- coming during the lull, then decide what to hold it with", so the next
-- wave's composition and the time left to act on it are permanent fixtures,
-- not a banner that flashes past.
--
-- Same palette and fonts as vanilla's HUD (mods/vanilla/game/hud.lua), because
-- this is the same game's furniture.

local font = require("src.engine.font")
local waves = require("mods.towerdefence.game.waves")

local hud = {}

local W, H = 960, 640

local BONE = { 0.91, 0.89, 0.84 }
local BLOOD = { 0.70, 0.13, 0.16 }
local BRASS = { 0.79, 0.64, 0.29 }
local TOXIC = { 0.50, 0.73, 0.31 }
local DIM = { 0.45, 0.44, 0.42 }

local F_SMALL = "fonts/small.mft"
local F_MEDIUM = "fonts/medium.mft"

local function set(c, a)
	love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function text_center(path, str, cx, y, color)
	font.draw(path, str, cx - font.measure(path, str) / 2, y, color)
end

local function text_right(path, str, rx, y, color)
	font.draw(path, str, rx - font.measure(path, str), y, color)
end

--- A labelled bar. Used for the two healths, which are the only two numbers
-- that can end a run.
local function bar(x, y, w, h, k, color, label)
	k = math.max(0, math.min(1, k))
	love.graphics.setColor(0, 0, 0, 0.55)
	love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
	set(color, 0.25)
	love.graphics.rectangle("fill", x, y, w, h)
	set(color, 1)
	love.graphics.rectangle("fill", x, y, w * k, h)
	if label then font.draw(F_SMALL, label, x, y - 18, BONE) end
	love.graphics.setColor(1, 1, 1, 1)
end

function hud.draw(field, camx, camy)
	local p = field.player

	-- 1. the base: top centre, the widest thing on screen, because it is the
	-- only thing whose loss ends the run
	local bw = 360
	bar(W / 2 - bw / 2, 18, bw, 14, field.base.hp / field.base.max_hp, BLOOD,
		("BASE  %d"):format(math.max(0, math.floor(field.base.hp))))

	-- 2. what is coming, top left
	if field.lull > 0 then
		font.draw(F_MEDIUM, ("NEXT IN %ds"):format(math.ceil(field.lull)), 16, 16, TOXIC)
		font.draw(F_SMALL, waves.preview(field.wave), 16, 44, BONE)
		font.draw(F_SMALL, "Spend at the HQ while it is quiet", 16, 64, BRASS)
	else
		font.draw(F_MEDIUM, ("WAVE %d"):format(field.wave), 16, 16, BONE)
		local left = field.wave_queue
		local alive = #field.creatures
		font.draw(F_SMALL, ("%d inbound, %d on the field"):format(left, alive),
			16, 44, BONE)
	end

	-- 3. money, top right
	text_right(F_MEDIUM, ("$%d"):format(field.money), W - 16, 16, BRASS)

	-- 4. the player, bottom left: health, and what is in their hands
	if p.dead_t then
		text_center(F_MEDIUM, ("DOWN - BACK IN %ds"):format(math.ceil(p.dead_t)),
			W / 2, H / 2 - 20, BLOOD)
	else
		bar(16, H - 34, 200, 12, p.hp / p.max_hp, BLOOD, "YOU")
	end

	local w = p.weapon
	if w then
		local ammo = p.reloading > 0 and "RELOADING"
			or ("%d / %d"):format(p.ammo, w.clip_size)
		text_right(F_SMALL, w.name or w.id, W - 16, H - 52, BONE)
		text_right(F_MEDIUM, ammo, W - 16, H - 36,
			p.reloading > 0 and BLOOD or BRASS)
	end

	-- Standing on the HQ: the one place money becomes anything. Only while the
	-- field is what you are looking at — the prompt telling you to open a
	-- screen you already have open is how a HUD starts lying.
	local on_field = (require("src.engine.screens").top() or {}).name == "GameCrimsonland"
	if on_field and not p.dead_t and not field.over then
		if field.near_hq then
			text_center(F_MEDIUM, "E  -  HEADQUARTERS", W / 2, H - 96, TOXIC)
		elseif field.near_plot then
			local plot = field.near_plot
			local what = (not plot.built) and "BUILD A MOUNT"
				or (plot.weapon and ("MOUNT %d  -  %s"):format(plot.index,
					plot.weapon.name or plot.weapon.id)
				or ("MOUNT %d  -  EMPTY"):format(plot.index))
			text_center(F_MEDIUM, ("E  -  %s"):format(what), W / 2, H - 96, TOXIC)
		end
	end

	-- crosshair: the aim point in screen space
	if p.aim_x and not p.dead_t then
		local cx, cy = p.aim_x - camx, p.aim_y - camy
		set(BONE, 0.9)
		love.graphics.circle("line", cx, cy, 10)
		love.graphics.line(cx - 3, cy, cx + 3, cy)
		love.graphics.line(cx, cy - 3, cx, cy + 3)
		love.graphics.setColor(1, 1, 1, 1)
	end

	-- an off-screen wave is still a wave: a tick on the screen edge for every
	-- creature outside the view, so a side going quiet is visible before it
	-- becomes a hole in the base
	set(BLOOD, 0.7)
	for _, c in ipairs(field.creatures) do
		if not c.dying then
			local sx, sy = c.x - camx, c.y - camy
			if sx < 0 or sx > W or sy < 0 or sy > H then
				love.graphics.circle("fill",
					math.max(4, math.min(W - 4, sx)),
					math.max(4, math.min(H - 4, sy)), 3)
			end
		end
	end
	love.graphics.setColor(1, 1, 1, 1)

	if field.banner and field.banner_t > 0 then
		text_center(F_MEDIUM, field.banner, W / 2, 92, BONE)
	end

	if field.over then
		love.graphics.setColor(0, 0, 0, 0.6)
		love.graphics.rectangle("fill", 0, H / 2 - 80, W, 170)
		text_center(F_MEDIUM, "THE BASE HAS FALLEN", W / 2, H / 2 - 50, BLOOD)
		text_center(F_SMALL, ("Wave %d  -  %d kills"):format(field.wave, field.kills),
			W / 2, H / 2 - 14, BONE)
		-- The wave you reached is the whole score: no levels, no unlocks, just
		-- how far. So the run has to end by saying whether it was your furthest.
		local best = field.progress()
		if field.new_best then
			text_center(F_SMALL, "A NEW BEST", W / 2, H / 2 + 12, TOXIC)
		else
			text_center(F_SMALL, ("Best: wave %d"):format(best.best_wave),
				W / 2, H / 2 + 12, DIM)
		end
		text_center(F_SMALL, "Click to return to the menu", W / 2, H / 2 + 44, BRASS)
		love.graphics.setColor(1, 1, 1, 1)
	end
end

return hud

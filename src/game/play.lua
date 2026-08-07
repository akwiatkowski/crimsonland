-- Gameplay: quest mode reimplementation on the original data.
-- The original game logic was compiled C++; this is a clean-room
-- reimplementation driven by the original XML datasets (weapons.xml,
-- creature-variants.xml, creatures.xml, terrains.xml).

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local bms = require("src.game.bms")
local data = require("src.game.data")

local game = {}

game.active = false

local WORLD = 2048 -- world size in pixels (square)
local SCREEN_W, SCREEN_H = 960, 640

-- unit conversions (original engine units -> pixels; tuned by feel)
local SPEED_SCALE = 60 -- creature speed 2.7 -> 162 px/s
local BULLET_SPEED_SCALE = 16 -- projectile_speed 55 -> 880 px/s
local RANGE_SCALE = 4 -- projectile_range 300 -> 1200 px

-- per-chapter creature unlock table (quest generator approximation)
local CHAPTER_CREATURES = {
	{ "ALIEN", "ZOMBIE" },
	{ "ALIEN", "ZOMBIE", "SPIDER1" },
	{ "ZOMBIE", "SPIDER1", "LIZARD" },
	{ "SPIDER1", "SPIDER2", "LIZARD", "BEETLE" },
	{ "SPIDER2", "LIZARD", "BEETLE", "MAGGOT" },
	{ "SPIDER2", "LIZARD", "BEETLE", "MAGGOT", "CRABFLY" },
	{ "SPIDER2", "BEETLE", "CRABFLY", "SPIDER_BOSS" },
}

local DIFFICULTY = { NORMAL = 1.0, HARDCORE = 1.5, GRIM = 2.0 }

-- ------------------------------------------------------------ terrain bake

local function bake_terrain(chapter_id)
	local ops = data.terrains[chapter_id] or data.terrains.CHAPTER_1
	local rng = love.math.newRandomGenerator(12345)
	local canvas = love.graphics.newCanvas(WORLD, WORLD)
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0.1, 0.1, 0.08, 1)
	for _, op in ipairs(ops or {}) do
		local action = op.action
		if action == "Clear" then
			love.graphics.clear(tonumber(op.r) or 0.2, tonumber(op.g) or 0.2, tonumber(op.b) or 0.1, 1)
		elseif action == "DrawTiled" then
			local img = assets.image(op.bm)
			if img then
				local spacing = tonumber(op.tile_spacing) or 1
				local scale = tonumber(op.tile_scale) or 1
				love.graphics.setColor(1, 1, 1, tonumber(op.alpha) or 1)
				local stepx = img:getWidth() * spacing * scale
				local stepy = img:getHeight() * spacing * scale
				local y = 0
				while y < WORLD do
					local x = 0
					while x < WORLD do
						love.graphics.draw(img, x, y, 0, scale, scale)
						x = x + stepx
					end
					y = y + stepy
				end
			end
		elseif action == "DrawSplashes" then
			local img = assets.image(op.bm)
			if img then
				local n = tonumber(op.num_splashes) or 10
				love.graphics.setColor(1, 1, 1, tonumber(op.alpha) or 1)
				for _ = 1, n do
					local x = rng:random() * WORLD
					local y = rng:random() * WORLD
					local rot = rng:random() * math.pi * 2
					love.graphics.draw(img, x, y, rot, 1, 1,
						img:getWidth() / 2, img:getHeight() / 2)
				end
			end
		end
		-- DrawWithPerlinNoise / DrawPerlin / FootPrints: skipped (polish)
	end
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setCanvas()
	return canvas
end

-- ------------------------------------------------------------ quest setup

function game.start_quest(chapter, quest, difficulty)
	data.load_all() -- idempotent-ish (cheap enough)
	difficulty = difficulty or "NORMAL"
	local diff_mul = DIFFICULTY[difficulty] or 1

	game.chapter = chapter
	game.quest = quest
	game.difficulty = difficulty
	game.terrain = bake_terrain("CHAPTER_" .. chapter)

	game.player = {
		x = WORLD / 2,
		y = WORLD / 2,
		angle = 0,
		hp = 100,
		max_hp = 100,
		speed = 220,
		anim_t = 0,
		moving = false,
		weapon = data.weapons.PISTOL or data.weapon_order[1],
		ammo = 0,
		reloading = 0,
		cooldown = 0,
		muzzle = 0,
	}
	game.player.ammo = game.player.weapon and game.player.weapon.clip_size or 0

	game.creatures = {}
	game.bullets = {}
	game.gore = {} -- dying creature animations
	game.score = 0
	game.xp = 0
	game.level = 1
	game.xp_next = 150
	game.kills = 0
	game.kills_goal = 15 + 10 * quest + 5 * (chapter - 1) * 10
	game.spawn_timer = 0
	game.spawn_interval = math.max(0.4, 2.2 - 0.15 * quest - 0.2 * (chapter - 1))
	game.max_concurrent = math.min(40, 4 + 2 * quest + 3 * (chapter - 1))
	game.diff_mul = diff_mul
	game.outcome = nil -- "won" | "lost"
	game.end_timer = nil
	game.time = 0

	-- creature type pool for this chapter
	game.pool = CHAPTER_CREATURES[math.min(chapter, #CHAPTER_CREATURES)]

	game.active = true
	audio.switch_music("music/crimsonquest", 0, 1)
end

--- Quit the running quest (escape key) and return to the main menu.
function game.abort()
	if not game.active then return end
	game.active = false
	print("[game] quest aborted")
	local timeline = require("src.engine.timeline")
	timeline.begin("MainMenu")
end

-- ------------------------------------------------------------ spawning

local function spawn_creature(game)
	local types = game.pool
	local ctype = types[love.math.random(#types)]
	local variant = data.base_variant[ctype]
	if not variant then return end

	-- spawn on a ring around the player, clamped into the world
	local ang = love.math.random() * math.pi * 2
	local dist = 550 + love.math.random() * 300
	local x = math.max(32, math.min(WORLD - 32, game.player.x + math.cos(ang) * dist))
	local y = math.max(32, math.min(WORLD - 32, game.player.y + math.sin(ang) * dist))

	game.creatures[#game.creatures + 1] = {
		variant = variant,
		def = data.creatures[ctype],
		x = x,
		y = y,
		hp = variant.health * game.diff_mul,
		anim_t = love.math.random() * 2,
		attack_cd = 0,
	}
end

-- ------------------------------------------------------------ update

local function update_player(game, dt)
	local p = game.player
	local dx, dy = 0, 0
	if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
	if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
	if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
	if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end
	p.moving = (dx ~= 0 or dy ~= 0)
	if p.moving then
		local len = math.sqrt(dx * dx + dy * dy)
		p.x = math.max(16, math.min(WORLD - 16, p.x + dx / len * p.speed * dt))
		p.y = math.max(16, math.min(WORLD - 16, p.y + dy / len * p.speed * dt))
		p.anim_t = p.anim_t + dt
	end

	-- aim at mouse (world coords)
	local mx, my = love.mouse.getPosition()
	local engine = require("src.engine")
	local rx, ry = engine.to_reference(mx, my)
	local camx, camy = game.camera()
	p.angle = math.atan2(ry + camy - p.y, rx + camx - p.x)

	-- weapon
	p.cooldown = math.max(0, p.cooldown - dt)
	p.muzzle = math.max(0, p.muzzle - dt)
	if p.reloading > 0 then
		p.reloading = p.reloading - dt
		if p.reloading <= 0 then
			p.ammo = p.weapon.clip_size
		end
	elseif love.keyboard.isDown("r") and p.ammo < p.weapon.clip_size then
		p.reloading = p.weapon.reload_time
		audio.play_sound(p.weapon.snd_reload)
	end

	if love.mouse.isDown(1) and p.reloading <= 0 and p.cooldown <= 0 then
		if p.ammo <= 0 then
			p.reloading = p.weapon.reload_time
			audio.play_sound(p.weapon.snd_reload)
		else
			p.cooldown = p.weapon.shoot_interval
			p.ammo = p.ammo - 1
			p.muzzle = 0.05
			audio.play_sound(p.weapon.snd_fire, 1, 0, 1 + (love.math.random() - 0.5) / 6)
			for _ = 1, p.weapon.num_projectiles do
				local spread = (love.math.random() - 0.5) * p.weapon.recoil * 2
				local a = p.angle + spread
				game.bullets[#game.bullets + 1] = {
					x = p.x + math.cos(p.angle) * 20,
					y = p.y + math.sin(p.angle) * 20,
					dx = math.cos(a),
					dy = math.sin(a),
					speed = p.weapon.projectile_speed * BULLET_SPEED_SCALE,
					dist_left = p.weapon.projectile_range * RANGE_SCALE,
					damage = p.weapon.projectile_damage,
				}
			end
		end
	end
end

local function update_bullets(game, dt)
	for i = #game.bullets, 1, -1 do
		local b = game.bullets[i]
		local step = b.speed * dt
		b.x = b.x + b.dx * step
		b.y = b.y + b.dy * step
		b.dist_left = b.dist_left - step
		local dead = b.dist_left <= 0
		-- collide with creatures (circle radius ~16*scale)
		if not dead then
			for _, c in ipairs(game.creatures) do
				local r = 16 * c.variant.scale + 6
				local ddx, ddy = c.x - b.x, c.y - b.y
				if ddx * ddx + ddy * ddy < r * r then
					c.hp = c.hp - b.damage
					dead = true
					if c.hp <= 0 and not c.dying then
						c.dying = true
						c.die_t = 0
						game.kills = game.kills + 1
						game.score = game.score + c.variant.xp
						game.xp = game.xp + c.variant.xp
						local snd = c.def and c.def.sounds
						if snd then
							local picks = {}
							for k, v in pairs(snd) do
								if k:match("^snd_die") and v ~= "!NONE" then picks[#picks + 1] = v end
							end
							if #picks > 0 then audio.play_sound(picks[love.math.random(#picks)]) end
						end
					end
					break
				end
			end
		end
		if dead then
			table.remove(game.bullets, i)
		end
	end
end

local function update_creatures(game, dt)
	local p = game.player
	for i = #game.creatures, 1, -1 do
		local c = game.creatures[i]
		if c.dying then
			c.die_t = c.die_t + dt
			local def = c.def
			local speed = def and def.die_speed or 1
			local seq = def and def.die and bms.load(def.die)
			local frames = seq and seq.count or 24
			if c.die_t * 24 * speed >= frames then
				table.remove(game.creatures, i)
			end
		else
			c.anim_t = c.anim_t + dt
			c.attack_cd = math.max(0, c.attack_cd - dt)
			-- CLASSIC AI: seek the player
			local dx, dy = p.x - c.x, p.y - c.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local speed = c.variant.speed * SPEED_SCALE
			if dist > 1 then
				c.x = c.x + dx / dist * speed * dt
				c.y = c.y + dy / dist * speed * dt
			end
			-- contact damage
			local touch = 16 * c.variant.scale + 14
			if dist < touch and c.attack_cd <= 0 then
				c.attack_cd = 0.8
				p.hp = p.hp - c.variant.damage * game.diff_mul
				local snd = c.def and c.def.sounds and c.def.sounds.snd_attack_01
				if snd and snd ~= "!NONE" then audio.play_sound(snd) end
			end
		end
	end
end

function game.update(dt)
	if not game.active then return end
	game.time = game.time + dt

	if game.outcome then
		game.end_timer = game.end_timer - dt
		-- let gore finish, then hand control back to the menus
		update_creatures(game, dt)
		if game.end_timer <= 0 then
			game.active = false
			local timeline = require("src.engine.timeline")
			timeline.begin("MainMenu")
		end
		return
	end

	update_player(game, dt)
	update_bullets(game, dt)
	update_creatures(game, dt)

	-- spawner
	game.spawn_timer = game.spawn_timer - dt
	if game.spawn_timer <= 0 and #game.creatures < game.max_concurrent
		and game.kills + #game.creatures < game.kills_goal + game.max_concurrent then
		game.spawn_timer = game.spawn_interval
		spawn_creature(game)
	end

	-- level ups (perk choice is not implemented yet; heal a bit instead)
	if game.xp >= game.xp_next then
		game.xp = game.xp - game.xp_next
		game.level = game.level + 1
		game.xp_next = math.floor(game.xp_next * 1.4)
		game.player.hp = math.min(game.player.max_hp, game.player.hp + 25)
		print(("[game] level up! now level %d"):format(game.level))
	end

	-- win/lose
	if game.kills >= game.kills_goal then
		game.outcome = "won"
		game.end_timer = 1.2
		print("[game] quest completed!")
	elseif game.player.hp <= 0 then
		game.outcome = "lost"
		game.end_timer = 1.6
		print("[game] you died")
	end
end

-- ------------------------------------------------------------ camera/draw

function game.camera()
	local p = game.player
	local cx = math.max(0, math.min(WORLD - SCREEN_W, p.x - SCREEN_W / 2))
	local cy = math.max(0, math.min(WORLD - SCREEN_H, p.y - SCREEN_H / 2))
	return cx, cy
end

function game.draw()
	if not game.active then
		-- menu backdrop
		love.graphics.setColor(0.05, 0.02, 0.03, 1)
		love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
		local img = assets.image("scene/background.jpg")
		if img then
			love.graphics.setColor(0.5, 0.5, 0.5, 1)
			love.graphics.draw(img, 0, 0, 0,
				SCREEN_W / img:getWidth(), SCREEN_H / img:getHeight())
		end
		return
	end

	local camx, camy = game.camera()
	love.graphics.push()
	love.graphics.translate(-camx, -camy)

	-- terrain
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(game.terrain, 0, 0)

	-- creatures (shadow under, then body)
	for _, c in ipairs(game.creatures) do
		local def = c.def
		local v = c.variant
		love.graphics.setColor(v.r, v.g, v.b, 1)
		if c.dying then
			local seq = def and def.die and bms.load(def.die)
			if seq then
				local speed = def.die_speed or 1
				local frame = math.min(seq.count, math.floor(c.die_t * 24 * speed) + 1)
				bms.draw(seq, frame, c.x, c.y, 0, v.scale)
			end
		else
			local seq = def and def.move and bms.load(def.move)
			if seq then
				local speed = def.move_speed or 1
				local frame = math.floor(c.anim_t * 24 * speed) + 1
				local rot = math.atan2(game.player.y - c.y, game.player.x - c.x)
				bms.draw(seq, frame, c.x, c.y, rot + math.pi / 2, v.scale)
			else
				love.graphics.circle("fill", c.x, c.y, 14 * v.scale)
			end
		end
	end

	-- player
	local p = game.player
	local tdef = data.creatures.TROOPER
	if p.hp > 0 then
		local legs = tdef and tdef.move_legs and bms.load(tdef.move_legs)
		local torso = tdef and tdef.move and bms.load(tdef.move)
		love.graphics.setColor(1, 1, 1, 1)
		if legs then
			local frame = p.moving and (math.floor(p.anim_t * 24 * (tdef.move_speed or 1)) + 1) or 1
			bms.draw(legs, frame, p.x, p.y, p.angle + math.pi / 2, 1)
		end
		if torso then
			bms.draw(torso, 1, p.x, p.y, p.angle + math.pi / 2, 1)
		else
			love.graphics.circle("fill", p.x, p.y, 12)
		end
		-- muzzle flash
		if p.muzzle > 0 then
			local mf = assets.image("game/muzzle-flash.png")
			if mf then
				love.graphics.setBlendMode("add")
				love.graphics.setColor(1, 1, 1, p.muzzle / 0.05)
				love.graphics.draw(mf, p.x + math.cos(p.angle) * 28, p.y + math.sin(p.angle) * 28,
					p.angle, 0.5, 0.5, mf:getWidth() / 2, mf:getHeight() / 2)
				love.graphics.setBlendMode("alpha")
			end
		end
	end

	-- bullets
	love.graphics.setColor(1, 1, 0.6, 1)
	for _, b in ipairs(game.bullets) do
		love.graphics.circle("fill", b.x, b.y, 2.5)
	end

	love.graphics.pop()

	-- HUD (screen space)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf(string.format("HP %d", math.max(0, math.floor(p.hp))), 10, 10, 200, "left")
	love.graphics.printf(string.format("AMMO %d/%d%s", p.ammo, p.weapon.clip_size,
		p.reloading > 0 and " (reloading)" or ""), 10, 30, 300, "left")
	love.graphics.printf(string.format("KILLS %d/%d   SCORE %d   LEVEL %d",
		game.kills, game.kills_goal, game.score, game.level), 10, 50, 600, "left")
	love.graphics.printf(string.format("QUEST %d.%d (%s)", game.chapter, game.quest, game.difficulty),
		SCREEN_W - 210, 10, 200, "right")
	if game.outcome then
		love.graphics.printf(game.outcome == "won" and "QUEST COMPLETED!" or "YOU DIED",
			0, SCREEN_H / 2 - 40, SCREEN_W, "center")
	end
end

-- ------------------------------------------------------ UI click routing

local selected_chapter = 1
local selected_difficulty = "NORMAL"

-- called by the screen manager after a screen's own OnClick
function game.on_ui_click(screen_name, comp_name)
	if screen_name == "SelectChapter" then
		local ch = comp_name:match("^Chapter_(%d+)$")
		if ch then
			selected_chapter = tonumber(ch)
			local screens = require("src.engine.screens")
			screens.push("PlayMenuQuests")
			return true
		end
		local diff = comp_name:match("^Difficulty_(%u+)$")
		if diff then
			selected_difficulty = diff
			return true
		end
	elseif screen_name == "PlayMenuQuests" then
		local q = comp_name:match("^Quest_(%d+)$")
		if q then
			local timeline = require("src.engine.timeline")
			game.start_quest(selected_chapter, tonumber(q), selected_difficulty)
			timeline.begin("Game")
			return true
		end
	end
	return false
end

function game.selected_chapter() return selected_chapter end

return game

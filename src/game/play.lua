-- Gameplay: quest mode reimplementation on the original data.
-- The original game logic was compiled C++; this is a clean-room
-- reimplementation driven by the original XML datasets (weapons.xml,
-- creature-variants.xml, creatures.xml, terrains.xml).

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local bms = require("src.game.bms")
local data = require("src.game.data")
local particles = require("src.game.particles")
local perks = require("src.game.perks")

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

-- The XML variant stats are late-game values; the original scaled them per
-- quest via defs compiled into prog.dll. Approximate the intended feel:
-- chapter-1 basics die to 2-4 pistol shots (4.1 dmg vs ALIEN 68 hp raw) and
-- a touch chips ~5 hp (raw damage is 12-35), both ramping with progress.
local HEALTH_SCALE_BASE = 0.15
local DAMAGE_SCALE_BASE = 0.4

local function progression_muls(chapter, quest, diff_mul)
	local ramp = 1 + 0.15 * (quest - 1) + 0.5 * (chapter - 1)
	return HEALTH_SCALE_BASE * ramp * diff_mul,
		DAMAGE_SCALE_BASE * ramp * diff_mul
end

-- weapon behavior classes (the XML flags don't encode these cleanly)
local EXPLOSIVE = {
	ROCKET_LAUNCHER = true, SEEKER_ROCKETS = true, MINI_ROCKET_SWARMERS = true,
	ROCKET_MINIGUN = true, PULSE_GUN = true,
}
local FLAME = { FLAMETHROWER = true, BLOW_TORCH = true, HR_FLAMER = true }

local DROP_WEAPON_CHANCE = 0.08
local DROP_HEALTH_CHANCE = 0.06
local PICKUP_RADIUS = 26
local HEALTH_PACK_HEAL = 25

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

-- state shared by every game mode
local function init_session(terrain_chapter)
	data.load_all() -- idempotent-ish (cheap enough)
	game.terrain = bake_terrain("CHAPTER_" .. terrain_chapter)

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

	game.creatures = {}
	game.bullets = {}
	game.drops = {}
	game.mods = perks.fresh_mods()
	game.owned_perks = {}
	game.perk_choices = nil
	particles.clear()
	game.score = 0
	game.xp = 0
	game.level = 1
	game.xp_next = 500 -- variant xp worth is 50-450; first level ~4 kills
	game.kills = 0
	game.shots = 0
	game.hits = 0
	game.spawn_timer = 0
	game.outcome = nil -- "won" | "lost"
	game.end_timer = nil
	game.end_screen_pushed = nil
	game.time = 0
	game.player.ammo = game.player.weapon and game.player.weapon.clip_size or 0
end

function game.start_quest(chapter, quest, difficulty)
	difficulty = difficulty or "NORMAL"
	local diff_mul = DIFFICULTY[difficulty] or 1

	game.mode = "quest"
	game.chapter = chapter
	game.quest = quest
	game.difficulty = difficulty
	init_session(chapter)

	-- highest weapon index that may drop; grows with chapter progress
	game.weapon_cap = math.min(30, 6 + 5 * (chapter - 1))
	game.kills_goal = 15 + 10 * quest + 5 * (chapter - 1) * 10
	game.spawn_interval = math.max(0.4, 2.2 - 0.15 * quest - 0.2 * (chapter - 1))
	game.max_concurrent = math.min(40, 4 + 2 * quest + 3 * (chapter - 1))
	game.diff_mul = diff_mul
	game.health_mul, game.damage_mul = progression_muls(chapter, quest, diff_mul)

	-- creature type pool for this chapter
	game.pool = CHAPTER_CREATURES[math.min(chapter, #CHAPTER_CREATURES)]

	game.active = true
	audio.switch_music("music/crimsonquest", 0, 1)
end

-- survival: creature types join the pool over time
local SURVIVAL_WAVES = {
	{ t = 0, "ALIEN", "ZOMBIE" },
	{ t = 30, "SPIDER1" },
	{ t = 60, "LIZARD" },
	{ t = 90, "SPIDER2" },
	{ t = 120, "BEETLE" },
	{ t = 150, "MAGGOT" },
	{ t = 180, "CRABFLY" },
	{ t = 240, "SPIDER_BOSS" },
}

function game.start_survival()
	game.mode = "survival"
	game.chapter = 1
	game.quest = 0
	game.difficulty = "NORMAL"
	init_session(1)

	game.kills_goal = nil -- endless: it ends when you do
	game.diff_mul = 1
	game.weapon_cap = 6
	game.spawn_interval = 1.8
	game.max_concurrent = 6
	game.health_mul, game.damage_mul = HEALTH_SCALE_BASE, DAMAGE_SCALE_BASE
	game.pool = { "ALIEN", "ZOMBIE" }

	game.active = true
	audio.switch_music("music/crimsonquest", 0, 1)
end

-- difficulty/pool ramp, recomputed from elapsed time every frame
local function update_survival_ramp(game)
	local t = game.time
	game.spawn_interval = math.max(0.3, 1.8 - t * 0.02)
	game.max_concurrent = math.min(60, 6 + math.floor(t * 0.4))
	game.weapon_cap = math.min(30, 6 + math.floor(t / 25))
	game.health_mul = HEALTH_SCALE_BASE * (1 + t / 90)
	game.damage_mul = DAMAGE_SCALE_BASE * (1 + t / 180)
	local pool = {}
	for _, wave in ipairs(SURVIVAL_WAVES) do
		if t >= wave.t then
			for _, ctype in ipairs(wave) do pool[#pool + 1] = ctype end
		end
	end
	game.pool = pool
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
		hp = variant.health * game.health_mul,
		anim_t = love.math.random() * 2,
		attack_cd = 0,
	}
end

-- --------------------------------------------------------- perk choosing

--- effective clip size with perk modifiers
function game.clip_size()
	return math.floor(game.player.weapon.clip_size * game.mods.clip + 0.5)
end

local function set_perk_desc(screen, perk)
	local comps = require("src.engine.comps")
	if screen.compmap.PerkName then
		comps.set(screen.compmap.PerkName, "textbox.text", { perk.name })
	end
	if screen.compmap.PerkDesc then
		comps.set(screen.compmap.PerkDesc, "textbox.text", { perk.desc })
	end
end

--- Push the original PickAPerk screen and fill its comps with our choices.
-- The C++ engine populated these; we do the same from the game layer.
local function open_perk_screen(game)
	local choices = perks.offer(3, game.owned_perks)
	if #choices == 0 then -- all perks owned: fall back to a heal
		game.player.hp = math.min(game.player.max_hp, game.player.hp + 25)
		return
	end
	game.perk_choices = choices
	audio.play_sound("sfx/unlock_perk")
	local screens = require("src.engine.screens")
	local comps = require("src.engine.comps")
	local s = screens.push("PickAPerk")
	if s.compmap.Title then
		comps.set(s.compmap.Title, "textbox.text",
			{ ("Level %d - Pick a Perk"):format(game.level) })
	end
	for i = 1, 5 do
		local b = s.compmap["PerkButton_" .. i]
		if b then
			if choices[i] then
				comps.set(b, "button.text", { choices[i].name })
				comps.set(b, "visible", { true })
			else
				comps.set(b, "visible", { false })
			end
		end
	end
	set_perk_desc(s, choices[1])
end

-- while the perk screen is open, hovering a button previews its description
local function update_perk_hover(screen)
	local hover = screen._hover_comp
	local n = hover and hover.name:match("^PerkButton_(%d+)$")
	local perk = n and game.perk_choices and game.perk_choices[tonumber(n)]
	if perk then set_perk_desc(screen, perk) end
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
		local speed = p.speed * game.mods.speed
		p.x = math.max(16, math.min(WORLD - 16, p.x + dx / len * speed * dt))
		p.y = math.max(16, math.min(WORLD - 16, p.y + dy / len * speed * dt))
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
			p.ammo = game.clip_size()
		end
	elseif love.keyboard.isDown("r") and p.ammo < game.clip_size() then
		p.reloading = p.weapon.reload_time * game.mods.reload
		audio.play_sound(p.weapon.snd_reload)
	end

	if love.mouse.isDown(1) and p.reloading <= 0 and p.cooldown <= 0 then
		if p.ammo <= 0 then
			p.reloading = p.weapon.reload_time * game.mods.reload
			audio.play_sound(p.weapon.snd_reload)
		else
			p.cooldown = p.weapon.shoot_interval / game.mods.fire
			p.ammo = p.ammo - 1
			p.muzzle = 0.05
			audio.play_sound(p.weapon.snd_fire, 1, 0, 1 + (love.math.random() - 0.5) / 6)
			local w = p.weapon
			game.shots = game.shots + 1
			-- flame weapons are short-ranged sprays; everything else uses
			-- the XML range (rockets detonate when they run out)
			local range = w.projectile_range * RANGE_SCALE
			if FLAME[w.id] then range = range * 0.18 end
			for _ = 1, w.num_projectiles do
				local spread = (love.math.random() - 0.5) * w.recoil * 2
				local a = p.angle + spread
				game.bullets[#game.bullets + 1] = {
					x = p.x + math.cos(p.angle) * 20,
					y = p.y + math.sin(p.angle) * 20,
					dx = math.cos(a),
					dy = math.sin(a),
					speed = w.projectile_speed * BULLET_SPEED_SCALE,
					dist_left = range * (FLAME[w.id] and (0.6 + love.math.random() * 0.4) or 1),
					damage = w.damage_effective * game.mods.dmg,
					explosive = EXPLOSIVE[w.id] or nil,
					flame = FLAME[w.id] or nil,
				}
			end
		end
	end
end

-- roll the powerup table where a creature died
local function try_drop(game, x, y)
	local roll = love.math.random()
	if roll < DROP_WEAPON_CHANCE then
		-- random weapon up to the current cap, never the one in hand
		local pool = {}
		for idx = 2, game.weapon_cap do
			local w = data.weapon_order[idx]
			if w and w ~= game.player.weapon then pool[#pool + 1] = w end
		end
		if #pool > 0 then
			game.drops[#game.drops + 1] =
				{ kind = "weapon", weapon = pool[love.math.random(#pool)], x = x, y = y, t = 0 }
		end
	elseif roll < DROP_WEAPON_CHANCE + DROP_HEALTH_CHANCE then
		game.drops[#game.drops + 1] = { kind = "health", x = x, y = y, t = 0 }
	end
end

--- Apply damage to a creature; handles the kill (gore, score, xp, drops).
local function damage_creature(game, c, dmg)
	if c.dying then return end
	c.hp = c.hp - dmg
	if c.hp <= 0 then
		c.dying = true
		c.die_t = 0
		-- freeze facing so the gore anim + baked corpse keep it
		c.rot = math.atan2(game.player.y - c.y, game.player.x - c.x) + math.pi / 2
		particles.death_burst(c.x, c.y, c.variant.scale)
		game.kills = game.kills + 1
		game.score = game.score + c.variant.xp
		game.xp = game.xp + c.variant.xp * game.mods.xp
		if game.mods.kill_heal > 0 then
			game.player.hp = math.min(game.player.max_hp,
				game.player.hp + game.mods.kill_heal)
		end
		try_drop(game, c.x, c.y)
		local snd = c.def and c.def.sounds
		if snd then
			local picks = {}
			for k, v in pairs(snd) do
				if k:match("^snd_die") and v ~= "!NONE" then picks[#picks + 1] = v end
			end
			if #picks > 0 then audio.play_sound(picks[love.math.random(#picks)]) end
		end
	end
end

--- Rocket-class detonation: area damage with linear falloff to the edge.
local function explode(game, x, y, base_damage)
	local radius = 80
	particles.explosion(x, y, radius)
	audio.play_sound("sfx/explosion_medium")
	for _, c in ipairs(game.creatures) do
		local ddx, ddy = c.x - x, c.y - y
		local dist = math.sqrt(ddx * ddx + ddy * ddy)
		local reach = radius + 16 * c.variant.scale
		if dist < reach then
			local falloff = 1 - 0.7 * (dist / reach)
			damage_creature(game, c, base_damage * 2 * falloff)
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
		-- rockets that reach max range detonate instead of fizzling
		if dead and b.explosive then
			explode(game, b.x, b.y, b.damage)
		end
		-- collide with creatures (circle radius ~16*scale)
		if not dead then
			for _, c in ipairs(game.creatures) do
				if not c.dying then
					local r = 16 * c.variant.scale + 6
					local ddx, ddy = c.x - b.x, c.y - b.y
					if ddx * ddx + ddy * ddy < r * r then
						dead = true
						game.hits = game.hits + 1
						if b.explosive then
							explode(game, b.x, b.y, b.damage)
						else
							particles.blood(b.x, b.y, math.atan2(b.dy, b.dx))
							damage_creature(game, c, b.damage)
						end
						break
					end
				end
			end
		end
		if dead then
			table.remove(game.bullets, i)
		end
	end
end

local function update_drops(game, dt)
	local p = game.player
	for i = #game.drops, 1, -1 do
		local d = game.drops[i]
		d.t = d.t + dt
		local ddx, ddy = p.x - d.x, p.y - d.y
		if ddx * ddx + ddy * ddy < PICKUP_RADIUS * PICKUP_RADIUS then
			if d.kind == "weapon" then
				p.weapon = d.weapon
				p.reloading = 0
				p.cooldown = 0
				p.ammo = game.clip_size()
				audio.play_sound("sfx/unlock_weapon")
			else
				p.hp = math.min(p.max_hp,
					p.hp + HEALTH_PACK_HEAL * game.mods.heal_mul)
				audio.play_sound("sfx/ui_clink_01")
			end
			particles.sparkle(d.x, d.y)
			table.remove(game.drops, i)
		elseif d.t > 30 then
			table.remove(game.drops, i) -- despawn eventually
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
				-- bake the corpse (final gore frame) into the terrain so the
				-- battlefield accumulates the classic Crimsonland blood carpet
				if seq then
					love.graphics.setCanvas(game.terrain)
					local v = c.variant
					love.graphics.setColor(v.r, v.g, v.b, 1)
					bms.draw(seq, seq.count, c.x, c.y, c.rot or 0, v.scale)
					love.graphics.setColor(1, 1, 1, 1)
					love.graphics.setCanvas()
				end
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
			-- contact damage (perks: Thick Skinned, Tough Reloader, Radioactive)
			local touch = 16 * c.variant.scale + 14
			if dist < touch then
				if c.attack_cd <= 0 then
					c.attack_cd = 0.8
					local taken = game.mods.taken
					if p.reloading > 0 then taken = taken * game.mods.reload_guard end
					p.hp = p.hp - c.variant.damage * game.damage_mul * taken
					local snd = c.def and c.def.sounds and c.def.sounds.snd_attack_01
					if snd and snd ~= "!NONE" then audio.play_sound(snd) end
				end
				if game.mods.touch_burn > 0 then
					damage_creature(game, c, game.mods.touch_burn * dt)
				end
			end
		end
	end
end

function game.update(dt)
	if not game.active then return end

	-- gameplay pauses whenever a UI screen overlays the game
	-- (PickAPerk, LevelCompleted, ...); keep the perk preview live
	local screens = require("src.engine.screens")
	local top = screens.top()
	if top and top.name ~= "GameCrimsonland" then
		if top.name == "PickAPerk" then update_perk_hover(top) end
		return
	end

	game.time = game.time + dt

	if game.outcome then
		game.end_timer = game.end_timer - dt
		-- let the gore finish, then hand over to the original end screens
		update_creatures(game, dt)
		particles.update(dt)
		if game.end_timer <= 0 and not game.end_screen_pushed then
			game.end_screen_pushed = true
			game.open_end_screen()
		end
		return
	end

	if game.mode == "survival" then
		update_survival_ramp(game)
	end

	update_player(game, dt)
	update_bullets(game, dt)
	update_creatures(game, dt)
	update_drops(game, dt)
	particles.update(dt)

	-- spawner (quest mode stops spawning once enough kills are in flight)
	game.spawn_timer = game.spawn_timer - dt
	local under_goal = not game.kills_goal
		or game.kills + #game.creatures < game.kills_goal + game.max_concurrent
	if game.spawn_timer <= 0 and #game.creatures < game.max_concurrent and under_goal then
		game.spawn_timer = game.spawn_interval
		spawn_creature(game)
	end

	-- level up -> pick a perk (gameplay pauses under the screen)
	if game.xp >= game.xp_next then
		game.xp = game.xp - game.xp_next
		game.level = game.level + 1
		game.xp_next = math.floor(game.xp_next * 1.5)
		print(("[game] level up! now level %d"):format(game.level))
		open_perk_screen(game)
		return
	end

	-- perk-driven regeneration
	local mods = game.mods
	if mods.regen > 0 then
		game.player.hp = math.min(game.player.max_hp, game.player.hp + mods.regen * dt)
	end

	-- win/lose (survival has no win condition)
	if game.kills_goal and game.kills >= game.kills_goal then
		game.outcome = "won"
		game.end_timer = 1.2
		print("[game] quest completed!")
	elseif game.player.hp <= 0 then
		game.outcome = "lost"
		game.end_timer = 1.6
		print("[game] you died")
	end
end

--- Push the appropriate original end screen for the finished round.
function game.open_end_screen()
	local screens = require("src.engine.screens")
	local comps = require("src.engine.comps")
	if game.mode == "survival" then
		local s = screens.push("SurvivalOver")
		-- fill the stats the layout displays (C++ did this originally)
		local function put(name, text)
			if s.compmap[name] then
				comps.set(s.compmap[name], "textbox.text", { tostring(text) })
			end
		end
		put("Score", string.format("%d", game.score))
		put("Time", string.format("%d:%02d", math.floor(game.time / 60),
			math.floor(game.time % 60)))
		put("Kills", string.format("%d", game.kills))
		put("Accuracy", string.format("%d%%",
			game.shots > 0 and math.floor(game.hits / game.shots * 100 + 0.5) or 0))
		put("WeaponName", game.player.weapon.name or game.player.weapon.id)
		if s.compmap.NewLocalHighscore then
			comps.set(s.compmap.NewLocalHighscore, "visible",
				{ game.new_highscore == true })
		end
	elseif game.outcome == "won" then
		screens.push("LevelCompleted")
	else
		screens.push("LevelFailed")
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

	-- powerup drops (under everything alive)
	local base_img = assets.image("powerups/base.png")
	for _, d in ipairs(game.drops) do
		local bob = math.sin(d.t * 3) * 3
		local alpha = (d.t > 25) and (0.4 + 0.6 * math.abs(math.sin(d.t * 8))) or 1
		love.graphics.setColor(1, 1, 1, alpha)
		if base_img then
			love.graphics.draw(base_img, d.x, d.y, 0, 0.7, 0.7,
				base_img:getWidth() / 2, base_img:getHeight() / 2)
		end
		local icon = assets.image(d.kind == "weapon" and d.weapon.icon
			or "powerups/powerup-medikit.png")
		if icon then
			love.graphics.draw(icon, d.x, d.y - 4 + bob, 0, 0.5, 0.5,
				icon:getWidth() / 2, icon:getHeight() / 2)
		end
	end

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
				bms.draw(seq, frame, c.x, c.y, c.rot or 0, v.scale)
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

	-- bullets (flame projectiles draw as fading fireballs)
	for _, b in ipairs(game.bullets) do
		if b.flame then
			love.graphics.setBlendMode("add")
			love.graphics.setColor(1, 0.55, 0.15, 0.8)
			love.graphics.circle("fill", b.x, b.y, 5 + love.math.random() * 3)
			love.graphics.setBlendMode("alpha")
		else
			love.graphics.setColor(1, 1, 0.6, 1)
			love.graphics.circle("fill", b.x, b.y, 2.5)
		end
	end

	particles.draw()

	love.graphics.pop()

	-- HUD (screen space)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf(string.format("HP %d", math.max(0, math.floor(p.hp))), 10, 10, 200, "left")
	love.graphics.printf(string.format("%s  %d/%d%s", p.weapon.name or p.weapon.id,
		p.ammo, game.clip_size(),
		p.reloading > 0 and " (reloading)" or ""), 10, 30, 400, "left")
	if game.mode == "survival" then
		love.graphics.printf(string.format("KILLS %d   SCORE %d   LEVEL %d",
			game.kills, game.score, game.level), 10, 50, 600, "left")
		love.graphics.printf(string.format("SURVIVAL  %d:%02d",
			math.floor(game.time / 60), math.floor(game.time % 60)),
			SCREEN_W - 210, 10, 200, "right")
	else
		love.graphics.printf(string.format("KILLS %d/%d   SCORE %d   LEVEL %d",
			game.kills, game.kills_goal, game.score, game.level), 10, 50, 600, "left")
		love.graphics.printf(string.format("QUEST %d.%d (%s)", game.chapter, game.quest, game.difficulty),
			SCREEN_W - 210, 10, 200, "right")
	end
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
	elseif screen_name == "PickAPerk" then
		local n = comp_name:match("^PerkButton_(%d+)$")
		local perk = n and game.perk_choices and game.perk_choices[tonumber(n)]
		if perk then
			game.owned_perks[perk.id] = true
			perk.apply(game.mods, game)
			game.perk_choices = nil
			audio.play_sound("sfx/unlocked")
			print(("[game] perk chosen: %s"):format(perk.name))
			local screens = require("src.engine.screens")
			screens.pop("PickAPerk")
			return true
		end
	elseif screen_name == "PlayMenuSurvival" then
		if comp_name == "Play_SURVIVAL" then
			game.start_survival()
			require("src.engine.timeline").begin("Game")
			return true
		elseif comp_name:match("^Play_") then
			print(("[game] mode %s not implemented yet"):format(comp_name))
			return true
		end
	elseif screen_name == "LevelCompleted" then
		if comp_name == "PlayNext" then
			local chapter, quest = game.chapter, game.quest + 1
			if quest > 10 then chapter, quest = chapter + 1, 1 end
			if chapter > #CHAPTER_CREATURES then
				game.to_main_menu()
			else
				game.start_quest(chapter, quest, game.difficulty)
				require("src.engine.timeline").begin("Game")
			end
			return true
		elseif comp_name == "Retry" then
			game.start_quest(game.chapter, game.quest, game.difficulty)
			require("src.engine.timeline").begin("Game")
			return true
		elseif comp_name == "PlayMenu" or comp_name == "PlayCustomQuestsMenu" then
			game.to_main_menu()
			return true
		end
	elseif screen_name == "LevelFailed" then
		if comp_name == "PlayAgain" then
			game.start_quest(game.chapter, game.quest, game.difficulty)
			require("src.engine.timeline").begin("Game")
			return true
		elseif comp_name == "PlayMenu" then
			game.to_main_menu()
			return true
		end
	elseif screen_name == "SurvivalOver" then
		if comp_name == "PlayAgain" then
			game.start_survival()
			require("src.engine.timeline").begin("Game")
			return true
		elseif comp_name == "PlayMenu" or comp_name == "HighScores" then
			game.to_main_menu()
			return true
		end
	end
	return false
end

--- Leave gameplay entirely and return to the menu timeline.
function game.to_main_menu()
	game.active = false
	require("src.engine.timeline").begin("MainMenu")
end

function game.selected_chapter() return selected_chapter end

return game

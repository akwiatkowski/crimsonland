-- Gameplay: quest mode reimplementation on the original data.
-- The original game logic was compiled C++; this is a clean-room
-- reimplementation driven by the original XML datasets (weapons.xml,
-- creature-variants.xml, creatures.xml, terrains.xml).

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local bms = require("src.game.bms")
local data = require("src.game.data")
local fx = require("src.engine.fx")
local hud = require("src.game.hud")
local particles = require("src.game.particles")
local perks = require("src.game.perks")
local quests = require("src.game.quests")

local game = {}

game.active = false

local WORLD = 2048 -- world size in pixels (square)
local SCREEN_W, SCREEN_H = 960, 640

-- unit conversions (original engine units -> pixels; tuned by feel —
-- lowered ~25% after the first playtest read "too fast")
local SPEED_SCALE = 45 -- creature speed 2.7 -> 122 px/s
local BULLET_SPEED_SCALE = 16 -- projectile_speed 55 -> 880 px/s
local RANGE_SCALE = 4 -- projectile_range 300 -> 1200 px

local NUM_CHAPTERS = 7

-- ranged creatures close to this distance, then hold and shoot
local SHOOTER_STANDOFF = 260
local SHOOTER_RANGE = 700 -- don't fire from way offscreen
local MAX_CREATURES = 90 -- hard cap so den spawners can't flood the world

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
local DROP_POWERUP_CHANCE = 0.05
local PICKUP_RADIUS = 26
local HEALTH_PACK_HEAL = 25

-- timed/instant powerups (art ships in powerups/); durations in seconds
local POWERUPS = {
	{ id = "NUKE", icon = "powerups/powerup-nuke.png", dur = 0, snd = "sfx/explosion_nuke" },
	{ id = "FREEZE", icon = "powerups/powerup-freeze.png", dur = 6, snd = "sfx/freeze" },
	{ id = "SHIELD", icon = "powerups/powerup-shield.png", dur = 8, snd = "sfx/unlocked" },
	{ id = "DOUBLE_POINTS", icon = "powerups/powerup-double-points.png", dur = 12, snd = "sfx/unlocked" },
	{ id = "SPEED", icon = "powerups/powerup-move-speed.png", dur = 8, snd = "sfx/unlocked" },
	{ id = "FIRE_BULLETS", icon = "powerups/powerup-fire-bullets.png", dur = 10, snd = "sfx/unlocked" },
}
local POWERUP_BY_ID = {}
for _, pu in ipairs(POWERUPS) do POWERUP_BY_ID[pu.id] = pu end
game.POWERUPS = POWERUPS -- the HUD reads icons/durations for effect timers

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
		speed = 180, -- px/s (was 220; playtest: too fast)
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
	game.ebullets = {} -- creature projectiles (plasma shooter spiders)
	game.drops = {}
	game.effects = {} -- active timed powerups: id -> seconds left
	game.mods = perks.fresh_mods()
	game.owned_perks = {}
	game.perk_choices = nil
	game.pending_perks = 0 -- extra picks queued by Instant Winner & friends
	game.death_clock = nil -- seconds left once the Death Clock perk is taken
	particles.clear()
	fx.clear("world") -- brass from the previous run must not follow the player
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

	local def = quests.get(chapter, quest)
	-- highest weapon index that may drop; grows with chapter progress
	game.weapon_cap = math.min(30, 6 + 5 * (chapter - 1))
	game.kills_goal = def.kills_goal
	game.spawn_interval = def.spawn_interval
	game.max_concurrent = def.max_concurrent
	game.pool = def.pool
	game.diff_mul = diff_mul
	game.health_mul, game.damage_mul = progression_muls(chapter, quest, diff_mul)

	-- boss encounter: spawns at 60% of the kill goal, must die to win
	game.boss_pending = def.boss and def.boss.count or 0
	game.boss_variant = def.boss and def.boss.variant or nil
	game.bosses_alive = 0

	game.active = true
	audio.switch_music("music/crimsonquest", 0, 1)
end

-- survival: creature types join the pool over time ("Variant_39" is the
-- plasma-shooter spider; DEN_ALIEN hatches aliens until it is destroyed)
local SURVIVAL_WAVES = {
	{ t = 0, "ALIEN", "ZOMBIE" },
	{ t = 30, "SPIDER1" },
	{ t = 60, "LIZARD" },
	{ t = 90, "SPIDER2" },
	{ t = 120, "BEETLE" },
	{ t = 150, "MAGGOT" },
	{ t = 180, "CRABFLY", "Variant_39" },
	{ t = 210, "DEN_ALIEN" },
	{ t = 240, "SPIDER_BOSS" },
}

--- Start any endless mode ("survival" default; "blitz" is survival at
-- 2.5x ramp speed; "rush", "waves", "nukefism", "weaponpicker" have their
-- own rules). Mode rules are clean-room recreations of the originals.
function game.start_survival(mode)
	game.mode = mode or "survival"
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
	game.pool = { { type = "ALIEN", w = 1 }, { type = "ZOMBIE", w = 1 } }
	game.boss_pending = 0
	game.boss_variant = nil
	game.bosses_alive = 0
	game.no_drops = nil
	game.no_perks = nil
	game.no_weapon_drops = nil
	game.field_spawn_cd = nil

	if game.mode == "rush" then
		-- one rifle, no pickups, no perks; just you and the swarm
		game.player.weapon = data.weapons.ASSAULT_RIFLE or game.player.weapon
		game.player.ammo = game.player.weapon.clip_size
		game.no_drops = true
		game.no_perks = true
		game.pool = { { type = "ALIEN", w = 1 } }
		game.spawn_interval = 0.9
		game.max_concurrent = 12
	elseif game.mode == "waves" then
		game.wave = 0
		game.wave_queue = 0
		game.max_concurrent = 0 -- generic spawner off; waves spawn directly
	elseif game.mode == "nukefism" then
		-- no gun, ever: survive on the powerups seeding the field
		game.player.weapon = nil
		game.no_weapon_drops = true
		game.field_spawn_cd = 1.5
	elseif game.mode == "weaponpicker" then
		-- a fresh weapon lands nearby every few seconds; grabbing one scores
		game.field_spawn_cd = 4
	end

	game.active = true
	audio.switch_music("music/crimsonquest", 0, 1)
end

-- difficulty/pool ramp, recomputed from elapsed time every frame
-- (blitz is survival with the clock running 2.5x faster)
local function update_survival_ramp(game)
	local t = game.time * (game.mode == "blitz" and 2.5 or 1)
	game.spawn_interval = math.max(0.3, 1.8 - t * 0.02)
	game.max_concurrent = math.min(60, 6 + math.floor(t * 0.4))
	game.weapon_cap = math.min(30, 6 + math.floor(t / 25))
	game.health_mul = HEALTH_SCALE_BASE * (1 + t / 90)
	game.damage_mul = DAMAGE_SCALE_BASE * (1 + t / 180)
	local pool = {}
	for _, wave in ipairs(SURVIVAL_WAVES) do
		if t >= wave.t then
			for _, ctype in ipairs(wave) do
				pool[#pool + 1] = { type = ctype, w = 1 }
			end
		end
	end
	game.pool = pool
end

-- rush: an accelerating wall of aliens, nothing else
local function update_rush_ramp(game)
	local t = game.time
	game.spawn_interval = math.max(0.12, 0.9 - t * 0.015)
	game.max_concurrent = math.min(MAX_CREATURES - 10, 12 + math.floor(t * 0.8))
	game.health_mul = HEALTH_SCALE_BASE * (1 + t / 120)
	game.damage_mul = DAMAGE_SCALE_BASE * (1 + t / 240)
end

-- (waves/field-spawn updates live below the spawning section they use)

--- Escape during gameplay: open the pause screen (gameplay pauses
-- automatically while any screen overlays GameCrimsonland).
function game.pause()
	if not game.active or game.outcome then return end
	require("src.engine.screens").push("GamePause")
end

function game.unpause()
	require("src.engine.screens").pop("GamePause")
end

-- ------------------------------------------------------------ spawning

-- weighted pick from the pool ({type=, w=} entries)
local function pick_type(pool)
	local total = 0
	for _, e in ipairs(pool) do total = total + e.w end
	local roll = love.math.random() * total
	for _, e in ipairs(pool) do
		roll = roll - e.w
		if roll <= 0 then return e.type end
	end
	return pool[#pool].type
end

-- a pool/wave id is either a creature type ("ALIEN" -> its base variant)
-- or an explicit variant id ("Variant_39" -> the plasma-shooter spider)
local function resolve_variant(id)
	return data.variants[id] or data.base_variant[id]
end

--- Instantiate a creature of `variant` at a world position. Behavior state
-- (shooter cooldowns, den spawn timers, wander headings) is derived from
-- the variant fields parsed out of creature-variants.xml.
local function add_creature(game, variant, x, y, is_boss)
	local c = {
		variant = variant,
		def = data.creatures[variant.type],
		x = x,
		y = y,
		hp = variant.health * game.health_mul * (is_boss and quests.BOSS_HP_MUL or 1),
		anim_t = love.math.random() * 2,
		attack_cd = 0,
		is_boss = is_boss or nil,
	}
	if variant.weapon_id then
		c.fire_cd = variant.fire_interval
			+ love.math.random() * variant.fire_interval_random
	end
	if variant.spawn_variant then
		c.spawn_cd = variant.spawn_interval
		c.spawned = 0
		-- nests don't chase; keep whatever facing they spawned with
		c.fixed_rot = love.math.random() * math.pi * 2
	end
	game.creatures[#game.creatures + 1] = c
	return c
end

--- Spawn a creature on a ring around the player. Passing a variant makes
-- it a boss (separate hp scaling, tracked for the win condition).
local function spawn_creature(game, boss_var)
	local variant
	if boss_var then
		variant = boss_var
	else
		variant = resolve_variant(pick_type(game.pool))
	end
	if not variant then return end

	-- spawn on a ring around the player, clamped into the world
	local ang = love.math.random() * math.pi * 2
	local dist = 550 + love.math.random() * 300
	local x = math.max(32, math.min(WORLD - 32, game.player.x + math.cos(ang) * dist))
	local y = math.max(32, math.min(WORLD - 32, game.player.y + math.sin(ang) * dist))

	add_creature(game, variant, x, y, boss_var and true or nil)
	if boss_var then
		game.bosses_alive = game.bosses_alive + 1
		audio.play_sound("sfx/unlocked")
		print(("[game] boss incoming: %s"):format(variant.id))
	end
end

-- waves mode: one creature type at a time, growing packs, field must clear
local WAVE_TYPES = {
	"ALIEN", "ZOMBIE", "SPIDER1", "LIZARD", "SPIDER2",
	"BEETLE", "MAGGOT", "CRABFLY",
}

local function update_waves_mode(game, dt)
	game.health_mul = HEALTH_SCALE_BASE * (1 + (game.wave - 1) * 0.12)
	game.damage_mul = DAMAGE_SCALE_BASE * (1 + (game.wave - 1) * 0.06)
	game.weapon_cap = math.min(30, 6 + game.wave * 2)
	if game.wave_queue > 0 then
		game.wave_spawn_cd = (game.wave_spawn_cd or 0) - dt
		if game.wave_spawn_cd <= 0 and #game.creatures < MAX_CREATURES then
			game.wave_spawn_cd = 0.25
			game.wave_queue = game.wave_queue - 1
			local saved = game.pool
			game.pool = { { type = game.wave_type, w = 1 } }
			spawn_creature(game)
			game.pool = saved
		end
	else
		-- field clear (gore may still be playing) -> brief breather, next wave
		local alive = 0
		for _, c in ipairs(game.creatures) do
			if not c.dying then alive = alive + 1 end
		end
		if alive == 0 then
			game.wave_pause = (game.wave_pause or 2) - dt
			if game.wave_pause <= 0 then
				game.wave_pause = nil
				game.wave = game.wave + 1
				game.wave_type = WAVE_TYPES[(game.wave - 1) % #WAVE_TYPES + 1]
				game.wave_queue = 5 + game.wave * 3
				audio.play_sound("sfx/unlocked")
				print(("[game] wave %d: %s x%d"):format(
					game.wave, game.wave_type, game.wave_queue))
			end
		end
	end
end

-- nukefism/weaponpicker: goodies materialize on the field on a timer
local function update_field_spawns(game, dt)
	game.field_spawn_cd = game.field_spawn_cd - dt
	if game.field_spawn_cd > 0 then return end
	local ang = love.math.random() * math.pi * 2
	local dist = 120 + love.math.random() * 260
	local x = math.max(32, math.min(WORLD - 32, game.player.x + math.cos(ang) * dist))
	local y = math.max(32, math.min(WORLD - 32, game.player.y + math.sin(ang) * dist))
	if game.mode == "nukefism" then
		game.field_spawn_cd = 3.5
		local pu = POWERUPS[love.math.random(#POWERUPS)]
		game.drops[#game.drops + 1] = { kind = "powerup", powerup = pu, x = x, y = y, t = 0 }
	else -- weaponpicker
		game.field_spawn_cd = 5
		local w = data.weapon_order[love.math.random(2, game.weapon_cap)]
		if w then
			game.drops[#game.drops + 1] = { kind = "weapon", weapon = w, x = x, y = y, t = 0 }
		end
	end
end

-- --------------------------------------------------------- perk choosing

--- effective clip size with perk modifiers (0 when unarmed: nukefism)
function game.clip_size()
	local w = game.player.weapon
	return w and math.floor(w.clip_size * game.mods.clip + 0.5) or 0
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
	local choices = perks.offer(game.mods.perk_offer, game.owned_perks)
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
			* (game.effects.SPEED and 1.5 or 1)
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

	-- weapon (nukefism plays unarmed)
	if not p.weapon then return end
	p.cooldown = math.max(0, p.cooldown - dt)
	p.muzzle = math.max(0, p.muzzle - dt)
	if p.reloading > 0 then
		-- Stationary Reloader: hands work faster while standing still
		local rate = p.moving and 1 or game.mods.stand_reload
		p.reloading = p.reloading - dt * rate
		if p.reloading <= 0 then
			p.ammo = game.clip_size()
		end
		-- Angry Reloader: spit fireballs in random directions meanwhile
		if game.mods.angry_reload then
			p.angry_cd = (p.angry_cd or 0) - dt
			if p.angry_cd <= 0 then
				p.angry_cd = 0.2
				local a = love.math.random() * math.pi * 2
				game.bullets[#game.bullets + 1] = {
					x = p.x + math.cos(a) * 20,
					y = p.y + math.sin(a) * 20,
					dx = math.cos(a),
					dy = math.sin(a),
					speed = 500,
					dist_left = 220 + love.math.random() * 80,
					damage = 12 * game.mods.dmg,
					fire = true,
				}
			end
		end
	elseif love.keyboard.isDown("r") and p.ammo < game.clip_size() then
		p.reloading = p.weapon.reload_time * game.mods.reload
		p.reload_total = p.reloading -- HUD sweeps the crosshair arc from this
		audio.play_sound(p.weapon.snd_reload)
	end

	if love.mouse.isDown(1) and p.reloading <= 0 and p.cooldown <= 0 then
		if p.ammo <= 0 then
			p.reloading = p.weapon.reload_time * game.mods.reload
			p.reload_total = p.reloading
			audio.play_sound(p.weapon.snd_reload)
		else
			p.cooldown = p.weapon.shoot_interval / game.mods.fire
			p.ammo = p.ammo - 1
			p.muzzle = 0.05
			audio.play_sound(p.weapon.snd_fire, 1, 0, 1 + (love.math.random() - 0.5) / 6)
			-- brass, on the original's own emitter parameters and shell art
			fx.spawn("fxs/shells1.lua", p.x + math.cos(p.angle) * 14,
				p.y + math.sin(p.angle) * 14, math.deg(p.angle), "world")
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
					damage = w.damage_effective * game.mods.dmg
						* (game.effects.FIRE_BULLETS and 2 or 1),
					explosive = EXPLOSIVE[w.id] or nil,
					flame = FLAME[w.id] or nil,
					fire = game.effects.FIRE_BULLETS and true or nil,
				}
			end
		end
	end
end

local damage_creature -- forward declaration: nuke pickups kill via drops code

-- roll the drop table where a creature died
local function try_drop(game, x, y)
	if game.no_drops then return end -- rush: no help is coming
	local roll = love.math.random()
	if roll < DROP_WEAPON_CHANCE and not game.no_weapon_drops then
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
	elseif roll < DROP_WEAPON_CHANCE + DROP_HEALTH_CHANCE
		+ DROP_POWERUP_CHANCE * game.mods.powerup_drop then -- Bonus Magnet
		local pu = POWERUPS[love.math.random(#POWERUPS)]
		game.drops[#game.drops + 1] = { kind = "powerup", powerup = pu, x = x, y = y, t = 0 }
	end
end

--- Activate a picked-up powerup: instant effect or timed buff.
local function activate_powerup(game, pu)
	audio.play_sound(pu.snd)
	print(("[game] powerup: %s"):format(pu.id))
	if pu.id == "NUKE" then
		-- wipe everything alive; each death pays out normally
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				particles.explosion(c.x, c.y, 60)
				damage_creature(game, c, 1e6)
			end
		end
	else
		-- Bonus Economist stretches every timed effect
		game.effects[pu.id] = pu.dur * game.mods.bonus_time
	end
end

--- Apply damage to a creature; handles the kill (gore, score, xp, drops).
function damage_creature(game, c, dmg)
	if c.dying then return end
	c.hp = c.hp - dmg
	if c.hp <= 0 then
		c.dying = true
		c.die_t = 0
		-- freeze facing so the gore anim + baked corpse keep it
		c.rot = c.fixed_rot
			or math.atan2(game.player.y - c.y, game.player.x - c.x) + math.pi / 2
		particles.death_burst(c.x, c.y, c.variant.scale)
		game.kills = game.kills + 1
		if c.is_boss then
			game.bosses_alive = game.bosses_alive - 1
			print("[game] boss down!")
		end
		local points_mul = game.effects.DOUBLE_POINTS and 2 or 1
		game.score = game.score + c.variant.xp * points_mul
		if not game.no_perks then -- rush: score only, no levelling
			game.xp = game.xp + c.variant.xp * game.mods.xp * points_mul
		end
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
							if game.mods.poison > 0 then
								c.poison_t = 4 -- refreshed on every hit
							end
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
		-- Telekinetic: pickups within reach crawl toward the player
		local magnet = game.mods.magnet
		if magnet > 0 then
			local dist2 = ddx * ddx + ddy * ddy
			if dist2 < magnet * magnet and dist2 > 1 then
				local dist = math.sqrt(dist2)
				d.x = d.x + ddx / dist * 130 * dt
				d.y = d.y + ddy / dist * 130 * dt
				ddx, ddy = p.x - d.x, p.y - d.y
			end
		end
		if ddx * ddx + ddy * ddy < PICKUP_RADIUS * PICKUP_RADIUS then
			if d.kind == "weapon" then
				p.weapon = d.weapon
				p.reloading = 0
				p.cooldown = 0
				p.ammo = game.clip_size()
				audio.play_sound("sfx/unlock_weapon")
				if game.mode == "weaponpicker" then
					game.score = game.score + 500 -- that's the point
				end
			elseif d.kind == "powerup" then
				activate_powerup(game, d.powerup)
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
		elseif game.effects.FREEZE then
			-- frozen solid: no movement, attacks or animation
			c.attack_cd = math.max(c.attack_cd, 0.5)
		else
			c.anim_t = c.anim_t + dt
			c.attack_cd = math.max(0, c.attack_cd - dt)
			-- Poison Bullets: damage-over-time after being shot
			if c.poison_t then
				c.poison_t = c.poison_t - dt
				damage_creature(game, c, game.mods.poison * dt)
				if c.poison_t <= 0 then c.poison_t = nil end
			end
			local v = c.variant
			local dx, dy = p.x - c.x, p.y - c.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local speed = v.speed * SPEED_SCALE

			-- movement by XML ai type. Dens/nests are stationary spawners
			-- regardless of their nominal ai; IDLE stands its ground;
			-- WANDERER drifts on a random heading; everything else
			-- (CLASSIC, SIMPLECLASSIC, SIMPLE, RUSH) seeks the player —
			-- but ranged attackers hold a standoff distance while firing.
			if c.spawn_cd or v.ai == "IDLE" then
				-- no movement
			elseif v.ai == "WANDERER" then
				c.wander_t = (c.wander_t or 0) - dt
				if c.wander_t <= 0 then
					c.wander_t = 1 + love.math.random() * 2
					c.wander_a = love.math.random() * math.pi * 2
				end
				c.x = math.max(32, math.min(WORLD - 32, c.x + math.cos(c.wander_a) * speed * dt))
				c.y = math.max(32, math.min(WORLD - 32, c.y + math.sin(c.wander_a) * speed * dt))
			elseif dist > 1 and not (c.fire_cd and dist < SHOOTER_STANDOFF) then
				c.x = c.x + dx / dist * speed * dt
				c.y = c.y + dy / dist * speed * dt
			end

			-- ranged attack: fire the variant's weapon at the player
			if c.fire_cd and dist < SHOOTER_RANGE then
				c.fire_cd = c.fire_cd - dt
				if c.fire_cd <= 0 then
					c.fire_cd = v.fire_interval
						+ love.math.random() * v.fire_interval_random
					local w = data.weapons[v.weapon_id]
					local a = math.atan2(dy, dx)
					game.ebullets[#game.ebullets + 1] = {
						x = c.x + math.cos(a) * 14 * v.scale,
						y = c.y + math.sin(a) * 14 * v.scale,
						dx = math.cos(a),
						dy = math.sin(a),
						speed = (w and w.projectile_speed or 10) * BULLET_SPEED_SCALE,
						dist_left = (w and w.projectile_range or 300) * RANGE_SCALE,
						-- the variant's damage stat is the authored "how much
						-- this creature hurts" knob (weapon XML damage is 5
						-- across the board), so scale it like contact damage
						damage = v.damage * game.damage_mul,
					}
				end
			end

			-- den spawner: hatch minions until the authored cap
			if c.spawn_cd then
				c.spawn_cd = c.spawn_cd - dt
				if c.spawn_cd <= 0 and c.spawned < v.spawn_max
					and #game.creatures < MAX_CREATURES then
					c.spawn_cd = v.spawn_interval
					c.spawned = c.spawned + 1
					local mv = data.variants[v.spawn_variant]
					if mv then
						local a = love.math.random() * math.pi * 2
						add_creature(game, mv,
							math.max(32, math.min(WORLD - 32, c.x + math.cos(a) * 30)),
							math.max(32, math.min(WORLD - 32, c.y + math.sin(a) * 30)))
					end
				end
			end

			-- contact damage (perks: Thick Skinned, Tough Reloader, Radioactive)
			local touch = 16 * v.scale + 14
			if dist < touch then
				if c.attack_cd <= 0 and not game.effects.SHIELD
					and v.damage > 0 then
					c.attack_cd = 0.8
					local taken = game.mods.taken
					if p.reloading > 0 then taken = taken * game.mods.reload_guard end
					-- Dodger: chance the bite misses entirely
					if love.math.random() < game.mods.dodge then taken = 0 end
					p.hp = p.hp - v.damage * game.damage_mul * taken
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

--- Creature projectiles: fly straight, hit the player, blocked by SHIELD.
local function update_ebullets(game, dt)
	local p = game.player
	for i = #game.ebullets, 1, -1 do
		local b = game.ebullets[i]
		local step = b.speed * dt
		b.x = b.x + b.dx * step
		b.y = b.y + b.dy * step
		b.dist_left = b.dist_left - step
		local dead = b.dist_left <= 0
		if not dead then
			local ddx, ddy = p.x - b.x, p.y - b.y
			if ddx * ddx + ddy * ddy < 14 * 14 then
				dead = true
				if not game.effects.SHIELD
					and love.math.random() >= game.mods.dodge then
					p.hp = p.hp - b.damage * game.mods.taken
					particles.blood(b.x, b.y, math.atan2(b.dy, b.dx))
				end
			end
		end
		if dead then table.remove(game.ebullets, i) end
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

	if game.mode == "rush" then
		update_rush_ramp(game)
	elseif game.mode == "waves" then
		update_waves_mode(game, dt)
	elseif game.mode ~= "quest" then
		update_survival_ramp(game) -- survival, blitz, nukefism, weaponpicker
	end
	if game.field_spawn_cd then
		update_field_spawns(game, dt)
	end

	-- timed powerup effects tick down
	for id, left in pairs(game.effects) do
		left = left - dt
		game.effects[id] = (left > 0) and left or nil
	end

	update_player(game, dt)
	update_bullets(game, dt)
	update_creatures(game, dt)
	update_ebullets(game, dt)
	update_drops(game, dt)
	particles.update(dt)

	-- boss entrance at 60% of the kill goal
	if game.boss_pending > 0 and game.kills_goal
		and game.kills >= game.kills_goal * 0.6 then
		game.boss_pending = game.boss_pending - 1
		spawn_creature(game, game.boss_variant)
	end

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
		game.levelup_t = game.time -- HUD flashes the level-up ring
		open_perk_screen(game)
		return
	end

	-- perk-driven regeneration
	local mods = game.mods
	if mods.regen > 0 then
		game.player.hp = math.min(game.player.max_hp, game.player.hp + mods.regen * dt)
	end

	-- Death Clock: invulnerable, but the countdown always wins
	if game.death_clock then
		game.death_clock = game.death_clock - dt
		if game.death_clock <= 0 then
			game.death_clock = nil
			game.player.hp = 0
		end
	end

	-- win/lose (survival has no win condition; bosses must die to win)
	if game.kills_goal and game.kills >= game.kills_goal
		and game.boss_pending == 0 and game.bosses_alive == 0 then
		game.outcome = "won"
		game.end_timer = 1.2
		print("[game] quest completed!")
		require("src.game.save").mark_quest_completed(game.chapter, game.quest)
	elseif game.player.hp <= 0 then
		game.outcome = "lost"
		game.end_timer = 1.6
		print("[game] you died")
		-- Final Revenge: take everyone with you (score still counts)
		if mods.final_revenge then
			for _, c in ipairs(game.creatures) do
				if not c.dying then
					particles.explosion(c.x, c.y, 60)
					damage_creature(game, c, 1e6)
				end
			end
			audio.play_sound("sfx/explosion_nuke")
		end
		if game.mode == "survival" then
			game.new_highscore = require("src.game.save").record_survival(
				game.score, game.time, game.kills)
			if game.new_highscore then print("[game] new local high score!") end
		end
	end
end

--- Push the appropriate original end screen for the finished round.
function game.open_end_screen()
	local screens = require("src.engine.screens")
	local comps = require("src.engine.comps")
	if game.mode ~= "quest" then -- every endless mode ends on this screen
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
		local w = game.player.weapon
		put("WeaponName", w and (w.name or w.id) or "Bare Hands")
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
	-- the crosshair replaces the OS cursor while a session runs
	love.mouse.setVisible(not game.active)
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
			or d.kind == "powerup" and d.powerup.icon
			or "powerups/powerup-medikit.png")
		if icon then
			love.graphics.draw(icon, d.x, d.y - 4 + bob, 0, 0.5, 0.5,
				icon:getWidth() / 2, icon:getHeight() / 2)
		end
	end

	-- creatures (shadow under, then body; frozen ones tint ice-blue)
	local frozen = game.effects.FREEZE
	for _, c in ipairs(game.creatures) do
		local def = c.def
		local v = c.variant
		if frozen and not c.dying then
			love.graphics.setColor(v.r * 0.5, v.g * 0.7, math.min(1, v.b + 0.5), 1)
		elseif c.poison_t and not c.dying then
			love.graphics.setColor(v.r * 0.6, math.min(1, v.g + 0.4), v.b * 0.6, 1)
		else
			love.graphics.setColor(v.r, v.g, v.b, 1)
		end
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
				local rot = c.fixed_rot -- dens/nests don't track the player
					or math.atan2(game.player.y - c.y, game.player.x - c.x) + math.pi / 2
				bms.draw(seq, frame, c.x, c.y, rot, v.scale)
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

	-- bullets (flame projectiles and fire-bullet rounds draw as fireballs)
	for _, b in ipairs(game.bullets) do
		if b.flame or b.fire then
			love.graphics.setBlendMode("add")
			love.graphics.setColor(1, 0.55, 0.15, 0.8)
			love.graphics.circle("fill", b.x, b.y,
				(b.flame and 5 or 3) + love.math.random() * 2)
			love.graphics.setBlendMode("alpha")
		else
			love.graphics.setColor(1, 1, 0.6, 1)
			love.graphics.circle("fill", b.x, b.y, 2.5)
		end
	end

	-- creature plasma bolts (green, additive glow)
	love.graphics.setBlendMode("add")
	for _, b in ipairs(game.ebullets) do
		love.graphics.setColor(0.3, 1, 0.4, 0.9)
		love.graphics.circle("fill", b.x, b.y, 4 + love.math.random() * 1.5)
	end
	love.graphics.setBlendMode("alpha")

	hud.draw_levelup_ring(game, game.player.x, game.player.y)
	particles.draw()
	fx.draw("world") -- inside the camera transform: spent brass on the ground

	love.graphics.pop()

	-- HUD (screen space): original 2014 art — health pie, crosshair with
	-- reload sweep, XP strip, effect timers (src/game/hud.lua)
	hud.draw(game)
end

-- ------------------------------------------------------ UI click routing

local selected_chapter = 1
local selected_difficulty = "NORMAL"

-- ----------------------------------------------------------- progression UI

--- Hang the pak's lock art on a button. Giving the overlay the button's own
-- align and a zero position puts both anchors on the same point, so the lock
-- lands on the button whatever alignment the layout script chose.
local function attach_lock(comp, comps, bitmap)
	if comp.lock_overlay then return end
	-- comps.set takes the script bridge's packed varargs, so scalars are wrapped
	local lock = comps.new("Image", comp.name .. "_lock", comp.screen)
	comps.set(lock, "image.bitmap", { bitmap })
	comps.set(lock, "align", { comp.props.align })
	comps.set(lock, "position", { 0, 0 })
	comps.set(lock, "position.z", { 10 })
	lock.parent = comp
	table.insert(comp.children, lock)
	comp.lock_overlay = lock
end

--- Paint one quest/chapter button according to its progress state. The C++
-- engine did this from the same save data; the layout scripts only lay the
-- grid out. Locked buttons go inactive, so comps.hit ignores them, and wear
-- the lock over a dimmed plate.
local function mark_button(comp, comps, state, lock_bitmap)
	comps.set(comp, "active", { state ~= "locked" })
	if state == "locked" then
		comps.set(comp, "button.text", { "" })
		attach_lock(comp, comps, lock_bitmap)
	elseif comp.lock_overlay then
		comps.set(comp.lock_overlay, "visible", { false })
	end
	-- cleared ground reads dimmer than the next quest waiting to be played
	local shade = { 1, 1, 1, 1 }
	if state == "done" then shade = { 0.55, 0.55, 0.55, 1 } end
	if state == "locked" then shade = { 0.4, 0.4, 0.4, 1 } end
	for _, s in ipairs({ "idle", "over", "pressed", "disabled" }) do
		comps.set(comp, "button.bitmap_color_" .. s, shade)
	end
end

local function decorate_quest_screen(screen)
	local comps = require("src.engine.comps")
	local save = require("src.game.save")
	for i = 1, save.QUESTS_PER_CHAPTER do
		local comp = screen.compmap["Quest_" .. i]
		if comp then
			local state = "open"
			if not save.is_quest_unlocked(selected_chapter, i) then
				state = "locked"
			elseif save.is_quest_completed(selected_chapter, i) then
				state = "done"
			end
			mark_button(comp, comps, state, "ui/gfx/quest-lock.png")
		end
	end
end

local function decorate_chapter_screen(screen)
	local comps = require("src.engine.comps")
	local save = require("src.game.save")
	local chapter = 1
	while screen.compmap["Chapter_" .. chapter] do
		local comp = screen.compmap["Chapter_" .. chapter]
		local state = "open"
		if not save.is_chapter_unlocked(chapter) then
			state = "locked"
		elseif save.is_quest_completed(chapter, save.QUESTS_PER_CHAPTER) then
			state = "done"
		end
		mark_button(comp, comps, state, "ui/gfx/lock-small.png")
		chapter = chapter + 1
	end
end

--- Screens the engine pushes carry no progress state of their own.
function game.on_screen_enter(screen_name, screen)
	if screen_name == "SelectChapter" then
		decorate_chapter_screen(screen)
	elseif screen_name == "PlayMenuQuests" then
		decorate_quest_screen(screen)
	end
end

-- called by the screen manager after a screen's own OnClick
function game.on_ui_click(screen_name, comp_name)
	if screen_name == "SelectChapter" then
		local ch = comp_name:match("^Chapter_(%d+)$")
		if ch then
			if not require("src.game.save").is_chapter_unlocked(tonumber(ch)) then
				return true -- locked: the button is inactive, this is the backstop
			end
			selected_chapter = tonumber(ch)
			local screens = require("src.engine.screens")
			local comps = require("src.engine.comps")
			local s = screens.push("PlayMenuQuests")
			-- fill the header the C++ engine used to populate
			data.load_chapters()
			local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }
			local info = data.chapters[selected_chapter]
			local function put(name, text)
				if s.compmap[name] then
					comps.set(s.compmap[name], "textbox.text", { text })
				end
			end
			put("ChapterName", ("%s - %s"):format(
				ROMAN[selected_chapter] or selected_chapter,
				info and info.name or ""))
			put("Difficulty", selected_difficulty:sub(1, 1)
				.. selected_difficulty:sub(2):lower())
			put("QuestName", "")
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
			if not require("src.game.save").is_quest_unlocked(selected_chapter, tonumber(q)) then
				return true
			end
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
			-- Instant Winner / Fatal Lottery queue further picks (unless
			-- the lottery just killed the player)
			if game.pending_perks > 0 and game.player.hp > 0 then
				game.pending_perks = game.pending_perks - 1
				open_perk_screen(game)
			end
			return true
		end
	elseif screen_name == "PlayMenuSurvival" then
		local MODE_BUTTONS = {
			Play_SURVIVAL = "survival", Play_RUSH = "rush",
			Play_BLITZ = "blitz", Play_WAVES = "waves",
			Play_NUKEFISM = "nukefism", Play_WEAPONPICKER = "weaponpicker",
		}
		local m = MODE_BUTTONS[comp_name]
		if m then
			game.start_survival(m)
			require("src.engine.timeline").begin("Game")
			return true
		elseif comp_name:match("^Play_") then
			-- Typ'o'Shooter: locked in the original menu too
			print(("[game] mode %s not implemented yet"):format(comp_name))
			return true
		end
	elseif screen_name == "LevelCompleted" then
		if comp_name == "PlayNext" then
			local chapter, quest = game.chapter, game.quest + 1
			if quest > 10 then chapter, quest = chapter + 1, 1 end
			if chapter > NUM_CHAPTERS then
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
			game.start_survival(game.mode)
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

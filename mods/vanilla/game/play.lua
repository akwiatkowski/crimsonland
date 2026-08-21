-- Gameplay: quest mode reimplementation on the original data.
-- The original game logic was compiled C++; this is a clean-room
-- reimplementation driven by the original XML datasets (weapons.xml,
-- creature-variants.xml, creatures.xml, terrains.xml).

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local bms = require("mods.vanilla.game.bms")
local data = require("mods.vanilla.game.data")
local fx = require("src.engine.fx")
local gibs = require("mods.vanilla.game.gibs")
local hud = require("mods.vanilla.game.hud")
local ai_player = require("mods.vanilla.game.ai_player")
local input = require("mods.vanilla.game.input")
local particles = require("mods.vanilla.game.particles")
local perks = require("mods.vanilla.game.perks")
local quests = require("mods.vanilla.game.quests")
local terrain = require("mods.vanilla.game.terrain")
local customquests = require("mods.vanilla.game.customquests")

local game = {}

game.active = false

-- Playfield size. The pak documents it in the custom-quest format's own
-- comments ("The game area is 0..1820" / "0..1024"), which is also why the
-- spawn coordinates in custom-quests/myset/*.xml stay inside that box.
local WORLD_W, WORLD_H = 1820, 1024
game.WORLD_W, game.WORLD_H = WORLD_W, WORLD_H
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

-- Seconds of unbroken running (or standing) at which a ramping perk reaches
-- its full value. Long enough that it is a commitment, short enough to feel.
local RAMP_FULL = 6

-- The pak ships eight music files and prog.dll names seven of them, in one
-- fixed table of 20-byte slots (offset 1151836, ending exactly where the sfx
-- strings begin). Two of the seven have a documented home in the shipped
-- scripts: crimson_theme is the main menu's (ui/fw/main-menu-events.lua) and
-- shortie_monk the trooper scene's. What is left is the in-game set, and gt1's
-- own filename says which job that is. The eighth file, intro.ogg, is in no
-- table and belongs to the intro video this port does not play.
--
-- Every quest and every endless run used to open crimsonquest alone.
local INGAME_MUSIC = {
	"music/crimsonquest",
	"music/gt1_ingame",
	"music/gt2_harppen",
	"music/gt3_3cwonder",
	"music/gt4_claddon01",
}

local endless_track = 0

--- Track for a run. A quest picks deterministically from (chapter, quest), so
-- a level always sounds like itself and a retry does not reshuffle; the
-- endless modes have no such identity, so they walk the set run by run.
local function ingame_music(chapter, quest)
	if chapter then
		return INGAME_MUSIC[(chapter * 10 + quest) % #INGAME_MUSIC + 1]
	end
	endless_track = endless_track % #INGAME_MUSIC + 1
	return INGAME_MUSIC[endless_track]
end

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

-- weapon behavior classes (the XML flags don't encode these cleanly).
-- Which rounds detonate is not one of these any more: it is the `blast` trait,
-- read off the weapon itself (game/traits.lua), so the list of ordnance and
-- the size of the bang live in one place instead of two.
local FLAME = { FLAMETHROWER = true, BLOW_TORCH = true, HR_FLAMER = true }

-- Two perks name a weapon class rather than a stat: Pyromaniac buffs "fire and
-- plasma based weapons", Ion Gun Master "ion weapons". The rosters come
-- straight off the weapon ids in weapons.xml.
local PLASMA = {
	PLASMA_RIFLE = true, MULTI_PLASMA = true, PLASMA_MINIGUN = true,
	PLASMA_SHOTGUN = true, PLASMA_CANNON = true, PULSE_GUN = true,
}
local ION = {
	ION_RIFLE = true, ION_MINIGUN = true, ION_CANNON = true,
	ION_SHOTGUN = true, MULTI_ION = true,
}

-- Cost of a shot fired on an empty clip (Regression Ammo pays points,
-- Ammunition Within pays health -- "drawn from your health").
local EMPTY_FIRE_POINTS = 250
local EMPTY_FIRE_HP = 2

-- How close an infected creature has to be to pass Plaguebearer's disease on.
local PLAGUE_SPREAD = 70

-- How long the gun you just swapped out stays on the ground, and how long it
-- takes to settle before it can be picked back up. Long enough to change your
-- mind, short enough that the field does not fill with old guns.
local DROPPED_WEAPON_LIFE = 8
local DROPPED_WEAPON_ARM = 0.6

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
	-- "You get more time to react as the game slows down" (prog.dll's own
	-- powerup table). Added with the perks, because Slow Time, High Damage
	-- exists only to be paired with it.
	{ id = "REFLEX_BOOST", icon = "powerups/powerup-reflex-boost.png", dur = 8, snd = "sfx/unlocked" },
	-- Three the original had and this port did not. The art ships, the sounds
	-- ship (sfx/firespinner, sfx/shockwave), and ui/survival-over.lua already
	-- counts them on the end screen -- it was drawing tallies for powerups that
	-- could never be collected.
	{ id = "FIREBLAST", icon = "powerups/powerup-fireblast.png", dur = 0, snd = "sfx/explosion_large" },
	{ id = "SHOCK_CHAIN", icon = "powerups/powerup-shock-chain.png", dur = 0, snd = "sfx/shockwave" },
	{ id = "FIRE_SPINNER", icon = "powerups/powerup-fire-spinner.png", dur = 7, snd = "sfx/firespinner" },
}

-- Fireblast clears the ground you are standing on: everything inside this
-- goes up at once, with the same falloff a rocket has.
local FIREBLAST_RADIUS = 210
local FIREBLAST_DAMAGE = 60
-- Shock Chain earns its name from the jumps, so the damage per link is modest
-- and the reach is what makes it worth picking up.
local SHOCK_JUMPS = 7
local SHOCK_RANGE = 260
local SHOCK_DAMAGE = 34
local SHOCK_DECAY = 0.82 -- per jump
local SHOCK_ARC_LIFE = 0.22
-- The spinner throws one flame round per interval, turning as it goes, so it
-- writes a spiral outward from the player for as long as it runs.
local SPINNER_INTERVAL = 0.045
local SPINNER_TURN = 2.9 -- radians per second
local POWERUP_BY_ID = {}
for _, pu in ipairs(POWERUPS) do POWERUP_BY_ID[pu.id] = pu end
game.POWERUPS = POWERUPS -- the HUD reads icons/durations for effect timers

-- ------------------------------------------------------------ terrain bake

-- Endless modes have no quest number to decorate the ground from. They read
-- best as places that have been fought over for a while, so they take the
-- last quest's worth of blast marks and debris.
local ENDLESS_TERRAIN_QUEST = 10

--- The session's ground. `quest` decides how scarred it is and, through the
-- chapter's authored seed list, which of the ten layouts it is.
local function bake_terrain(terrain_id, quest)
	-- Deferred require: the engine is what loads the mod, so the game layer
	-- must not hold a load-time reference back into it.
	local density = require("src.engine").render_scale()
	return terrain.bake(terrain_id, quest or ENDLESS_TERRAIN_QUEST,
		WORLD_W, WORLD_H, density)
end

--- Which authored terrain a session is fought on.
--
-- terrains.xml does not stop at the seven chapters: it carries an array for
-- each endless mode too, and they are not decoration. SURVIVAL is chapter 2
-- as it looks at quest 5, WAVES is chapter 7 at quest 5, RUSH is a beach with
-- a summoning circle burned into it, BLITZ is chapter 5 with a landing pad,
-- two roads and four sets of mech tracks. The port used to fight every one of
-- them on chapter 1's grass.
local function terrain_for(mode, chapter)
	local named = mode and data.terrains[mode:upper()]
	if named then return mode:upper() end
	return "CHAPTER_" .. (chapter or 1)
end

-- ------------------------------------------------------------ quest setup

-- state shared by every game mode. The terrain is resolved here rather than
-- by the caller because terrain_for reads data.terrains, which the load below
-- is what fills.
local function init_session(mode, chapter, quest, terrain_override)
	data.load_all() -- parses once, then returns immediately
	-- The outgoing session's ground is a texture of its own, tens of megabytes
	-- of it, and nothing else holds a reference: the attract mode starts a new
	-- session every time its AI dies, so waiting for the collector piles them
	-- up. (The cached clean bakes it was copied from are not touched.)
	if game.terrain then game.terrain:release() end
	game.terrain = bake_terrain(terrain_override or terrain_for(mode, chapter), quest)

	-- Whatever attract scene was up belongs to that scene. start_demo sets
	-- these again after this returns; a real run must not inherit a demo's
	-- creature set or its countdown.
	game.demo_id, game.demo_left, game.demo_pool = nil, nil, nil

	game.player = {
		x = WORLD_W / 2,
		y = WORLD_H / 2,
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
	game.hazes = {} -- blasts still bending the air over themselves
	game.arcs = {} -- shock-chain links still on screen
	game.banner = nil
	game.spinner_a, game.spinner_cd = 0, 0
	game.decals = {} -- blood waiting to be stamped into the ground
	game.shake_t, game.shake_mag = 0, 0
	game.shake_x, game.shake_y = 0, 0
	game.flash_t, game.flash_amount = 0, 0
	game.mods = perks.fresh_mods()
	game.owned_perks = {}
	game.perk_choices = nil
	game.pending_perks = 0 -- extra picks queued by Instant Winner & friends
	game.death_clock = nil -- seconds left once the Death Clock perk is taken
	game.custom = nil -- the authored quest being played, if any
	game.custom_next = 1
	-- brass, blood and smoke from the previous run must not follow the player,
	-- and neither may body parts still in the air when it ended
	fx.clear("world")
	gibs.clear()
	game.score = 0
	game.xp = 0
	game.level = 1
	game.xp_next = 500 -- variant xp worth is 50-450; first level ~4 kills
	game.kills = 0
	game.shots = 0
	game.hits = 0
	game.weapon_shots = {} -- weapon id -> shots; the end screens' favorite weapon
	game.powerups_taken = {} -- powerup id -> count, tallied on the survival panel
	game.walked = 0 -- world pixels covered on foot, shown as "Steps Taken"
	game.hurt = false -- "Not a Scratch" asks whether anything ever landed
	game.spawn_timer = 0
	game.outcome = nil -- "won" | "lost"
	game.end_timer = nil
	game.end_screen_pushed = nil
	game.time = 0
	game.player.ammo = game.player.weapon and game.player.weapon.clip_size or 0
end

function game.start_quest(chapter, quest, difficulty)
	game.demo = false
	input.set_controller(nil)
	audio.duck = 1
	difficulty = difficulty or "NORMAL"
	local diff_mul = DIFFICULTY[difficulty] or 1

	game.mode = "quest"
	game.chapter = chapter
	game.quest = quest
	game.difficulty = difficulty
	init_session("quest", chapter, quest)

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
	audio.switch_music(ingame_music(chapter, quest), 0, 1)
end

--- An authored quest from custom-quests/ (game/customquests.lua).
--
-- Nothing is generated here: the spawn list is the whole level. There is no
-- kill goal to reach and no palette to draw from — you win by clearing what
-- the author placed, which is why this mode can be a five-creature puzzle or a
-- boss arena and the endless modes cannot.
function game.start_custom(quest)
	game.demo = false
	input.set_controller(nil)
	audio.duck = 1

	game.mode = "custom"
	game.chapter = 1
	game.quest = 0
	game.difficulty = "NORMAL"
	init_session("custom", 1)

	game.custom = quest
	game.custom_next = 1 -- index into quest.spawns
	game.kills_goal = nil -- the spawn list decides when it is over
	game.diff_mul = 1
	-- an authored quest has no chapter to gate its drops, so every weapon a
	-- player can hold is in -- and nothing above that: `#weapon_order` is a
	-- length over a sparse array and answers 48, which put the spider's own
	-- plasma gun and the boss's in the drop table (see data.last_player_weapon)
	game.weapon_cap = data.last_player_weapon
	game.spawn_interval = math.huge -- the generic spawner stays out of this
	game.max_concurrent = 0
	game.health_mul, game.damage_mul = HEALTH_SCALE_BASE, DAMAGE_SCALE_BASE

	-- "weapon" in the file's INFO array: the author picks what you fight with
	local w = quest.weapon and data.weapons[quest.weapon]
	if w then
		game.player.weapon = w
		game.player.ammo = game.clip_size()
	end

	game.active = true
	audio.switch_music(ingame_music(), 0, 1)
	print(("[custom] %s by %s (%d spawn nodes)"):format(
		quest.name, quest.author, #quest.spawns))
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
-- Attract mode: the original's timeline says the menu backdrop IS the game
-- ("MainMenu" pushes GameCrimsonland with parm_demo="MENU_COMBAT_1..5"), so
-- the menu sits over a session an AI is playing rather than over a still.
--- Which MENU_COMBAT scene comes next. The five are a rotation rather than a
-- roll: the original names them in order and each is a different picture, so
-- cycling shows all five where random repeats and skips.
local demo_next = 0

-- The spawn sets demos.xml names are not defined anywhere in the pak -- the
-- C++ side held them -- but the creature is legible from the name, which is
-- the half worth honouring. What the suffix meant (AROUND, BELOW, RANDOM) was
-- a placement pattern and is not recoverable, so the ring spawn stands in.
local DEMO_SPAWNS = {
	ALIENS = "ALIEN",
	LIZARDS = "LIZARD",
	ZOMBIES = "ZOMBIE",
	SPIDERS = "SPIDER1",
	DENS = "DEN_ALIEN",
	BOSS = "SPIDER_BOSS",
}

local function demo_pool(spawns)
	local head = tostring(spawns or ""):match("^([A-Z]+)")
	local ctype = head and DEMO_SPAWNS[head]
	if not ctype then return nil end
	return { { type = ctype, w = 1 } }
end

function game.start_demo()
	data.load_all()
	-- The five scenes 10tons authored for this: demos.xml gives each a terrain,
	-- a duration, a spawn set, and a position and weapon for its trooper. The
	-- port used to roll a chapter and a gun instead, which was a different
	-- picture every time and none of the intended ones.
	local demo = data.menu_demos[demo_next % math.max(1, #data.menu_demos) + 1]
	demo_next = demo_next + 1

	-- The terrain has to be chosen before the session starts: baking survival's
	-- ground first and throwing it away cost a full bake on every restart, and
	-- the attract mode restarts every time its AI dies.
	local terrain = demo and demo.terrain_id or
		("CHAPTER_" .. love.math.random(1, NUM_CHAPTERS))
	game.start_survival("survival", true, terrain)
	game.chapter = tonumber(terrain:match("CHAPTER_(%d+)")) or 1
	game.no_perks = true -- nothing may interrupt with a UI screen
	game.spawn_interval = 1.2
	game.max_concurrent = 10

	-- how long this scene runs before the next one, per the node's own duration
	game.demo_id = demo and demo.id or nil
	game.demo_left = demo and tonumber(demo.duration) or nil

	-- The scene's own creatures, held apart from game.pool because the survival
	-- ramp rebuilds that from the clock on every frame and would have replaced
	-- them before the first one spawned.
	game.demo_pool = demo and demo_pool(demo.spawns)
	if game.demo_pool then game.pool = game.demo_pool end

	-- MENU_COMBAT_3 authors no trooper at all, so the starting pistol stands --
	-- and the survival ramp will hand it something better soon enough.
	local w = demo and demo.trooper_1_weapon and data.weapons[demo.trooper_1_weapon]
	if w then
		game.player.weapon = w
		game.player.ammo = w.clip_size
	end
	local px, py = tostring(demo and demo.trooper_1_position or ""):match("^(%d+),(%d+)$")
	if px then
		game.player.x = math.max(32, math.min(WORLD_W - 32, tonumber(px)))
		game.player.y = math.max(32, math.min(WORLD_H - 32, tonumber(py)))
	end
	if demo then
		print(("[demo] %s on %s, %s, %ss"):format(demo.id, terrain,
			tostring(demo.trooper_1_weapon or "pistol"), tostring(demo.duration)))
	end
	input.set_controller(ai_player.controller())
	-- gunfire belongs under the menu music, not over it; ducking is separate
	-- from the player's own volume setting, which the options screen reads
	audio.duck = 0.25
end

--- `terrain_override` names an authored terrain to bake instead of the
-- mode's own -- the attract mode uses it to fight on a chapter.
function game.start_survival(mode, demo, terrain_override)
	game.demo = demo or false
	input.set_controller(nil)
	audio.duck = 1
	game.mode = mode or "survival"
	game.chapter = 1
	game.quest = 0
	game.difficulty = "NORMAL"
	init_session(game.mode, 1, nil, terrain_override)

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
	-- The attract demo is scenery behind a menu that owns its own music
	-- (ui/fw/main-menu-events.lua switches to crimson_theme on entry). Taking
	-- the music over is a real run's privilege — starting the demo after that
	-- OnEnter is why the theme was never heard.
	if not game.demo then audio.switch_music(ingame_music(), 0, 1) end
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
	-- An attract scene names its own creatures (demos.xml `spawns`), and this
	-- runs every frame: without the guard the authored set would be replaced
	-- before the first of them spawned.
	if not game.demo_pool then game.pool = pool end
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
		-- Bad Blood leaves them with less health to spend
		hp = variant.health * game.health_mul * game.mods.creature_hp
			* (is_boss and quests.BOSS_HP_MUL or 1),
		-- its own copy: Shrinkifier rounds scale a creature down, and the
		-- variant table is shared by every creature of that variant
		scale = variant.scale,
		anim_t = love.math.random() * 2,
		attack_cd = 0,
		is_boss = is_boss or nil,
		-- which of the four ice blocks encases this one when it freezes, so a
		-- frozen crowd is not four identical cubes repeated
		ice_frame = love.math.random(1, 4),
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
	local x = math.max(32, math.min(WORLD_W - 32, game.player.x + math.cos(ang) * dist))
	local y = math.max(32, math.min(WORLD_H - 32, game.player.y + math.sin(ang) * dist))

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

--- Run an authored quest's spawn list.
--
-- The format's own comment says a node "can spawn earlier if no other
-- creatures are alive", so a cleared field pulls the next node forward rather
-- than leaving the player waiting out a timer they have already beaten. That
-- one line is what lets an author write a paced fight instead of a schedule.
local function update_custom(game)
	local q = game.custom
	if not q then return end
	local node = q.spawns[game.custom_next]
	if not node then return end

	if game.time < node.time and #game.creatures > 0 then return end

	game.custom_next = game.custom_next + 1
	local variant = customquests.variant(node)
	if not variant then
		print(("[custom] unknown creature type '%s'"):format(tostring(node.type)))
		return
	end
	for i = 1, node.count do
		local x, y = customquests.place(node, i)
		add_creature(game, variant,
			math.max(32, math.min(WORLD_W - 32, x)),
			math.max(32, math.min(WORLD_H - 32, y)))
	end
end

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
	local x = math.max(32, math.min(WORLD_W - 32, game.player.x + math.cos(ang) * dist))
	local y = math.max(32, math.min(WORLD_H - 32, game.player.y + math.sin(ang) * dist))
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

--- effective clip size with perk modifiers (0 when unarmed: nukefism).
-- Ammo Maniac scales it; Sharpshooter and My Favourite Weapon add flat rounds.
function game.clip_size()
	local w = game.player.weapon
	if not w then return 0 end
	return math.max(1,
		math.floor(w.clip_size * game.mods.clip + 0.5) + game.mods.clip_add)
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
	-- Six plates, because the layout ships six — which is Perk Master's "you
	-- can now select between SIX perks", and why the port's old five was wrong.
	for i = 1, 6 do
		local b = s.compmap["PerkButton_" .. i]
		if b then
			if choices[i] then
				-- icon only: the name and description belong to the pair of
				-- textboxes below, which follow the pointer. Writing the name
				-- onto the plate as well was survivable while the names were
				-- invented and short, and unreadable once they were the
				-- original's ("Lean Mean Exp Machine" across a 60px plate).
				comps.set(b, "button.bm_icon", { choices[i].icon })
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

--- Point the custom-quest screen's two detail textboxes at one quest.
local function set_custom_quest_details(screen, q)
	local comps = require("src.engine.comps")
	if screen.compmap.QuestName then
		comps.set(screen.compmap.QuestName, "textbox.text", { q and q.name or "" })
	end
	if screen.compmap.QuestAuthor then
		comps.set(screen.compmap.QuestAuthor, "textbox.text",
			{ q and ("By " .. q.author) or "" })
	end
end

-- the same idea on the custom-quest list: the two textboxes follow the pointer
local function update_custom_quest_hover(screen)
	local hover = screen._hover_comp
	local n = hover and hover.name:match("^Quest_(%d+)$")
	local q = n and customquests.all()[tonumber(n) + 1]
	if q then set_custom_quest_details(screen, q) end
end

-- ------------------------------------------------------------ update

local function update_player(game, dt)
	local p = game.player
	local want = input.intent(game, dt)
	local dx, dy = want.dx, want.dy
	p.moving = (dx ~= 0 or dy ~= 0)

	-- Two perks build while you keep doing the same thing: Long Distance Runner
	-- ("faster the longer you run without stopping") and Living Fortress ("more
	-- damage and take in less damage the longer you stand still"). Each timer
	-- resets the other, and both saturate at RAMP_FULL seconds.
	if p.moving then
		p.run_t = math.min(RAMP_FULL, (p.run_t or 0) + dt)
		p.still_t = 0
	else
		p.still_t = math.min(RAMP_FULL, (p.still_t or 0) + dt)
		p.run_t = 0
	end

	if p.moving then
		local len = math.sqrt(dx * dx + dy * dy)
		local speed = p.speed * game.mods.speed
			* (1 + game.mods.run_ramp * (p.run_t / RAMP_FULL))
			* (game.effects.SPEED and 1.5 or 1)
		local ox, oy = p.x, p.y
		p.x = math.max(16, math.min(WORLD_W - 16, p.x + dx / len * speed * dt))
		p.y = math.max(16, math.min(WORLD_H - 16, p.y + dy / len * speed * dt))
		-- measured after the clamp, so walking into the world edge stops
		-- adding steps the trooper is not taking
		game.walked = game.walked + math.sqrt((p.x - ox) ^ 2 + (p.y - oy) ^ 2)
		p.anim_t = p.anim_t + dt
	end

	-- aim point is world-space, so the HUD crosshair can follow whoever is
	-- playing — mouse, AI demo or a test
	p.aim_x, p.aim_y = want.aim_x, want.aim_y
	p.angle = math.atan2(p.aim_y - p.y, p.aim_x - p.x)

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
	elseif want.reload and p.ammo < game.clip_size() then
		p.reloading = p.weapon.reload_time * game.mods.reload
		p.reload_total = p.reloading -- HUD sweeps the crosshair arc from this
		audio.play_sound(p.weapon.snd_reload)
		-- Stationary Reloader: "monsters around you may also freeze when you
		-- start reloading"
		if game.mods.freeze_on_reload > 0 and love.math.random() < 0.5 then
			game.effects.FREEZE = math.max(game.effects.FREEZE or 0,
				game.mods.freeze_on_reload)
		end
	end

	if want.fire and p.reloading <= 0 and p.cooldown <= 0 then
		-- Regression Ammo and Ammunition Within both fire on an empty clip;
		-- they differ only in what the shot costs you.
		local dry = p.ammo <= 0
		if dry and not game.mods.empty_fire then
			p.reloading = p.weapon.reload_time * game.mods.reload
			p.reload_total = p.reloading
			audio.play_sound(p.weapon.snd_reload)
		else
			if dry then
				if game.mods.empty_fire == "health" then
					p.hp = p.hp - EMPTY_FIRE_HP
				else
					game.score = math.max(0, game.score - EMPTY_FIRE_POINTS)
				end
			end
			p.cooldown = p.weapon.shoot_interval / game.mods.fire
			p.ammo = math.max(0, p.ammo - 1)
			p.muzzle = 0.05
			audio.play_sound(p.weapon.snd_fire, 1, 0, 1 + (love.math.random() - 0.5) / 6)
			-- Brass, on the original's own emitter parameters and shell art --
			-- but only from the weapons that have a case to eject. weapons.xml
			-- says which in bit 0 of `flags` (data.lua), and firing it
			-- unconditionally had the flamethrower, the blade gun and the
			-- bubblegun all dropping shells.
			if p.weapon.brass then
				fx.spawn("fxs/shells1.lua", p.x + math.cos(p.angle) * 14,
					p.y + math.sin(p.angle) * 14, math.deg(p.angle),
					{ layer = "world", fade = 0.25 })
			end
			local w = p.weapon
			game.shots = game.shots + 1
			game.weapon_shots[w.id] = (game.weapon_shots[w.id] or 0) + 1
			-- flame weapons are short-ranged sprays; everything else uses
			-- the XML range (rockets detonate when they run out)
			local range = w.projectile_range * RANGE_SCALE
			if FLAME[w.id] then range = range * 0.18 end
			-- Pyromaniac and Ion Gun Master are per-class: they only touch the
			-- weapons their text names, so the class tables decide who benefits
			local class_dmg, class_range = 1, 1
			if FLAME[w.id] or PLASMA[w.id] then
				class_dmg, class_range = game.mods.fire_dmg, game.mods.fire_range
			elseif ION[w.id] then
				class_dmg = game.mods.ion_dmg
			end
			range = range * class_range
			-- Slow Time, High Damage pays off only while Reflex is running
			local reflex_dmg = game.effects.REFLEX_BOOST and game.mods.reflex_dmg or 1
			-- Living Fortress: "you do more damage ... the longer you stand still"
			local stand_dmg = 1 + game.mods.stand_ramp * ((p.still_t or 0) / RAMP_FULL)
			-- Barrel Greaser: "more speed, more damage". A round with a motor
			-- leaves the barrel below that and builds up to it, so a rocket
			-- launch is something you watch happen (game/traits.lua).
			local rated = w.projectile_speed * BULLET_SPEED_SCALE * game.mods.bullet_speed
			local accel = w.traits and w.traits.accel
			local launch = accel and rated * accel.from or rated
			for _ = 1, w.num_projectiles do
				-- somewhere in the cone this gun's accuracy rating earns it
				-- (game/data.lua), which for a pellet gun is where the fan
				-- comes from and for a rifle is a barely visible wander
				local a = p.angle + (love.math.random() - 0.5) * 2 * w.spread
				game.bullets[#game.bullets + 1] = {
					x = p.x + math.cos(p.angle) * 20,
					y = p.y + math.sin(p.angle) * 20,
					dx = math.cos(a),
					dy = math.sin(a),
					speed = launch,
					accel = accel and accel.rate or nil,
					max_speed = rated,
					dist_left = range * (FLAME[w.id] and (0.6 + love.math.random() * 0.4) or 1),
					damage = w.damage_effective * game.mods.dmg
						* class_dmg * reflex_dmg * stand_dmg
						* (game.effects.FIRE_BULLETS and 2 or 1),
					explosive = w.traits and w.traits.blast or nil,
					flame = FLAME[w.id] or nil,
					fire = game.effects.FIRE_BULLETS and true or nil,
					-- which sprite off game/projs.tga this round wears, and the
					-- gun it left, which is the only way to tell a gauss round
					-- from any other kinetic one
					art = w.proj_art,
					-- how big this gun's bolt is drawn, for the energy
					-- families that are drawn as one (nil for everything else)
					bolt = w.proj_scale,
					weapon_id = w.id,
					-- what this round *does*: see game/traits.lua
					traits = w.traits,
				}
			end
		end
	end
end

local damage_creature -- forward declaration: nuke pickups kill via drops code

-- roll the drop table where a creature died
--- Put a random powerup on the ground. Shared by the kill drop table and by
-- Out of Thin Air, which conjures them with nothing having died.
local function drop_powerup(game, x, y)
	local pu = POWERUPS[love.math.random(#POWERUPS)]
	game.drops[#game.drops + 1] = { kind = "powerup", powerup = pu, x = x, y = y, t = 0 }
end

local function try_drop(game, x, y)
	if game.no_drops then return end -- rush: no help is coming
	local roll = love.math.random()
	-- One roll across one table, so closing a band must leave a hole rather
	-- than shift the ones behind it: My Favourite Weapon ("no more random
	-- weapon powerups") and nukefism otherwise hand the weapon band's 8% to
	-- the medkits, more than doubling how often health drops.
	if roll < DROP_WEAPON_CHANCE then
		if game.no_weapon_drops or game.mods.no_random_weapon then return end
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
		+ DROP_POWERUP_CHANCE * game.mods.powerup_drop then -- Lucky
		drop_powerup(game, x, y)
	end
end

--- Shock Chain: hop from the player to the nearest creature and on to the
-- nearest one after that, losing bite at every jump. Each link is remembered
-- for a moment so the draw can put the arc on screen.
function game.shock_chain(x, y)
	local damage = SHOCK_DAMAGE
	local hit = {}
	local cx, cy = x, y
	for _ = 1, SHOCK_JUMPS do
		local best, bestd
		for _, c in ipairs(game.creatures) do
			if not c.dying and not hit[c] then
				local dx, dy = c.x - cx, c.y - cy
				local d = dx * dx + dy * dy
				if d < SHOCK_RANGE * SHOCK_RANGE and (not bestd or d < bestd) then
					best, bestd = c, d
				end
			end
		end
		if not best then break end
		hit[best] = true
		game.arcs[#game.arcs + 1] =
			{ x1 = cx, y1 = cy, x2 = best.x, y2 = best.y, t = 0 }
		damage_creature(game, best, damage)
		cx, cy = best.x, best.y
		damage = damage * SHOCK_DECAY
	end
end

--- Activate a picked-up powerup: instant effect or timed buff.
local function activate_powerup(game, pu)
	audio.play_sound(pu.snd)
	print(("[game] powerup: %s"):format(pu.id))
	game.powerups_taken[pu.id] = (game.powerups_taken[pu.id] or 0) + 1
	game.announce(pu.id:gsub("_", " "))
	if pu.id == "NUKE" then
		-- the whole field goes at once, and the frame should say so
		game.flash(0.85, 1, 0.95, 0.85)
		game.shake(12)
		-- wipe everything alive; each death pays out normally
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				particles.explosion(c.x, c.y, 60)
				damage_creature(game, c, 1e6)
			end
		end
	elseif pu.id == "FIREBLAST" then
		-- the ground you are standing on, cleared
		game.flash(0.45, 1, 0.72, 0.35)
		game.shake(8)
		game.add_haze(game.player.x, game.player.y, FIREBLAST_RADIUS * 0.6)
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				local dx, dy = c.x - game.player.x, c.y - game.player.y
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist < FIREBLAST_RADIUS then
					particles.explosion(c.x, c.y, 45)
					damage_creature(game, c,
						FIREBLAST_DAMAGE * (1 - 0.6 * dist / FIREBLAST_RADIUS))
				end
			end
		end
	elseif pu.id == "SHOCK_CHAIN" then
		game.shock_chain(game.player.x, game.player.y)
	else
		-- Bonus Economist stretches every timed effect; Slow Time, High Damage
		-- pays for its quad damage by halving Reflex Boost specifically
		local dur = pu.dur * game.mods.bonus_time
		if pu.id == "REFLEX_BOOST" then dur = dur * game.mods.reflex_time end
		game.effects[pu.id] = dur
	end

	-- Man Bomb: "each time you pick up a power up, you go boom"
	if game.mods.bomb_on_pickup then
		game.explode_at(game.player.x, game.player.y, 30)
	end
end

-- Seconds a creature stays lit after being hit. Short enough to read as an
-- impact rather than a state, long enough to survive a frame at 60fps -- which
-- is what makes the pellets of a shotgun blast countable.
local HIT_FLASH = 0.06

--- Apply damage to a creature; handles the kill (gore, score, xp, drops).
-- Returns true when this was the blow that killed it, so the caller can throw
-- the killing hit harder than the ones it survived.
function damage_creature(game, c, dmg)
	if c.dying then return false end
	local before = c.hp
	c.hp = c.hp - dmg
	-- every hit lands visibly on whatever survives it
	c.flash_t = HIT_FLASH
	if c.hp <= 0 then
		-- Overkill: a blow worth twice what was left does not knock a creature
		-- over, it takes it apart -- so it skips the death animation and the
		-- corpse bake and throws the parts instead. Safe to remove immediately:
		-- everything that walks, attacks, collides or can be shot already tests
		-- `not c.dying`, so a corpse is inert for every frame it exists.
		c.overkill = (dmg >= before * 2) or nil
		c.dying = true
		c.die_t = 0
		-- freeze facing so the gore anim + baked corpse keep it
		c.rot = c.fixed_rot
			or math.atan2(game.player.y - c.y, game.player.x - c.x)
		particles.death_burst(c.x, c.y, c.scale)
		-- what it emptied onto the ground, under where it came apart
		for _ = 1, 3 do
			game.blood_decal(
				c.x + (love.math.random() - 0.5) * 26 * c.scale,
				c.y + (love.math.random() - 0.5) * 26 * c.scale,
				(0.7 + love.math.random() * 0.7) * c.scale,
				0.35 + love.math.random() * 0.3)
		end
		-- the parts creatures.xml says this creature is made of
		gibs.spawn(c, c.overkill and 2.5 or 1)
		-- something killed while encased sheds its ice with the rest of it
		if game.effects.FREEZE then
			particles.ice_shatter(c.x, c.y, c.scale)
		end
		game.kills = game.kills + 1
		-- Home Wrecker counts nests: a den is a creature that hatches others
		if c.spawn_cd and not game.demo then
			local st = require("mods.vanilla.game.save").game.stats
			st.dens = st.dens + 1
		end
		if c.is_boss then
			game.shake(8)
			game.bosses_alive = game.bosses_alive - 1
			print("[game] boss down!")
		end
		-- Bloody Mess pays more points, Death Clock doubles them while it runs
		local points_mul = (game.effects.DOUBLE_POINTS and 2 or 1) * game.mods.score_mul
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
		return true
	end
	return false
end

-- ------------------------------------------------------------------ impact
--
-- What a hit does to the frame rather than to the world: the camera jolts, the
-- screen flashes, the air over a blast bends. None of it touches gameplay --
-- no hit-stop, deliberately. Freezing the game for a few frames on a kill
-- reads as weight in a game with one enemy at a time; here twenty things die a
-- second and it would stutter from start to finish.

-- Seconds a jolt takes to die. Short: this is a punch, not a wobble.
local SHAKE_TIME = 0.3
-- Hard ceiling on the offset, in reference pixels. Past this the playfield
-- stops reading as a camera and starts reading as a bug.
local SHAKE_MAX = 14
-- How long a blast keeps bending the air over it.
local HAZE_TIME = 0.45

--- Jolt the camera. `mag` is in reference pixels at the moment of the hit.
function game.shake(mag)
	game.shake_mag = math.min(SHAKE_MAX, math.max(game.shake_mag or 0, mag))
	game.shake_t = SHAKE_TIME
end

--- Wash the frame towards a colour and fade back out of it.
function game.flash(amount, r, g, b)
	if (game.flash_amount or 0) > amount then return end
	game.flash_amount = amount
	game.flash_t = 0.35
	game.flash_dur = 0.35
	game.flash_rgb = { r or 1, g or 1, b or 1 }
end

--- Put a line of text across the middle of the screen for a moment.
--
-- The pak ships game/bonus_text_holder.png and its mirror: two halves of one
-- wide plate, each fading out at one end, meant to butt together into a
-- banner. That is what it is for -- not a per-kill "+50" floater, which is
-- what the name suggests until you look at the art.
function game.announce(text)
	game.banner = { text = tostring(text), t = 0 }
end

--- Bend the air over a point in the world for a moment.
function game.add_haze(x, y, radius)
	local list = game.hazes
	if not list then return end
	list[#list + 1] = { x = x, y = y, radius = radius, t = 0 }
end

-- How long a banner stays up, and how long a shock arc is on screen.
local BANNER_TIME = 1.6

local function update_impact(game, dt)
	if game.banner then
		game.banner.t = game.banner.t + dt
		if game.banner.t >= BANNER_TIME then game.banner = nil end
	end
	for i = #game.arcs, 1, -1 do
		local a = game.arcs[i]
		a.t = a.t + dt
		if a.t >= SHOCK_ARC_LIFE then table.remove(game.arcs, i) end
	end
	-- Fire Spinner: a flame round every interval, the heading turning as it
	-- goes, which writes a spiral outward from wherever the player is standing.
	if game.effects.FIRE_SPINNER and game.player.hp > 0 then
		game.spinner_a = (game.spinner_a or 0) + SPINNER_TURN * dt
		game.spinner_cd = (game.spinner_cd or 0) - dt
		if game.spinner_cd <= 0 then
			game.spinner_cd = SPINNER_INTERVAL
			local a = game.spinner_a
			game.bullets[#game.bullets + 1] = {
				x = game.player.x + math.cos(a) * 18,
				y = game.player.y + math.sin(a) * 18,
				dx = math.cos(a), dy = math.sin(a),
				speed = 430,
				dist_left = 300,
				damage = 9 * game.mods.dmg,
				flame = true,
				art = "flame",
			}
		end
	end
	if game.shake_t and game.shake_t > 0 then
		game.shake_t = game.shake_t - dt
		-- squared falloff, so it lands hard and settles fast
		local k = math.max(0, game.shake_t / SHAKE_TIME)
		local m = (game.shake_mag or 0) * k * k
		-- one offset per frame, not one per call: game.camera() is read by the
		-- draw and again by the crosshair, and they have to agree
		game.shake_x = (love.math.random() * 2 - 1) * m
		game.shake_y = (love.math.random() * 2 - 1) * m
	else
		game.shake_x, game.shake_y = 0, 0
		-- and the magnitude with it: game.shake keeps the loudest request so a
		-- small jolt cannot cut a big one short, which without this reset also
		-- meant every later jolt inherited the largest one the run ever had
		game.shake_mag = 0
	end

	if game.flash_t and game.flash_t > 0 then
		game.flash_t = game.flash_t - dt
	else
		game.flash_amount = 0 -- same reason as the shake above
	end

	for i = #game.hazes, 1, -1 do
		local h = game.hazes[i]
		h.t = h.t + dt
		if h.t >= HAZE_TIME then table.remove(game.hazes, i) end
	end
end

-- What a weapon family looks like, on its ground drop's plate. The colours
-- themselves are read off the original's own icons in game/data.lua; every
-- other place a family shows itself takes them from there too, so a family
-- reads the same whether it is being fired, exploding, or lying in the grass.
local FAMILY_TINT = data.FAMILY_COLOR

-- What colour a blast burns. The fireball art is painted for ordnance, so a
-- rocket takes it as it is; the energy weapons tint it towards their own bolt
-- rather than asking for a second sheet of hand-painted fire.
local BLAST_TINT = {
	plasma = FAMILY_TINT.plasma,
	ion = FAMILY_TINT.ion,
	pulse = FAMILY_TINT.pulse,
}

-- ------------------------------------------------------------------ decals
--
-- Blood that stays. The spray off a hit is particles and particles fade, so a
-- field fought over for a minute looked exactly like a clean one -- and the
-- floor going red as a wave comes apart is the thing Crimsonland is
-- remembered for. A share of the hits stamp a splat into the terrain canvas,
-- where the corpses and the body parts already go.
--
-- Stamps queue and flush once a frame: stamping at the call site would switch
-- render target once per round of a minigun.

-- What a family of weapon leaves on the ground where it connects. All four
-- rects are on game/particles.tga, the sheet everything else is drawn from:
-- the blood splat, and the smoke and glow sprites standing in for soot and a
-- burn. Colour and stretch do the rest, which is why this needs no new art.
--
-- Kinetic and ordnance stain red. Flame chars black. The energy families burn
-- a pale ring in their own colour -- so a field fought over with ion weapons
-- reads differently from one fought over with a shotgun, which is the whole
-- point of keeping the marks.
local MARK_SPLAT = { 65, 1, 30, 30 }
local MARK_SOOT = { 198, 66, 52, 60 }
local MARK_BURN = { 138, 74, 44, 44 }

local MARK = {
	bullet = { rect = MARK_SPLAT, color = { 1, 1, 1 }, alpha = 0.55 },
	rocket = { rect = MARK_SPLAT, color = { 1, 1, 1 }, alpha = 0.55 },
	blade = { rect = MARK_SPLAT, color = { 1, 1, 1 }, alpha = 0.6 },
	flame = { rect = MARK_SOOT, color = { 0.12, 0.1, 0.1 }, alpha = 0.5 },
	plasma = { rect = MARK_BURN, color = FAMILY_TINT.plasma, alpha = 0.28 },
	ion = { rect = MARK_BURN, color = FAMILY_TINT.ion, alpha = 0.28 },
	pulse = { rect = MARK_BURN, color = FAMILY_TINT.pulse, alpha = 0.28 },
}

local DECAL_HIT_CHANCE = 0.35
-- A round that hit nothing marks the ground this often. Low: misses vastly
-- outnumber hits with an automatic weapon.
local MISS_MARK_CHANCE = 0.14
-- A wave dying at once is a lot of stamps; past this they are dropped rather
-- than queued, because the ground is already red by then.
local DECAL_MAX_QUEUED = 64

local mark_quads = {}

--- The sheet plus a cached quad for one mark rect. Quads address texels, so
-- the scale that maps back to reference units comes along with it.
local function mark_sprite(rect)
	local img = assets.image("game/particles.tga")
	if not img then return nil end
	local key = rect[1] * 1000 + rect[2]
	local q = mark_quads[key]
	if not q then
		local quad, qscale = assets.quad(img, rect[1], rect[2], rect[3], rect[4])
		local _, _, qw, qh = quad:getViewport()
		q = { quad = quad, scale = qscale, w = qw, h = qh }
		mark_quads[key] = q
	end
	return img, q
end

--- Queue a mark on the ground. `opts` carries the family look (rect, color,
-- alpha) and the shape of this particular one: `rot` to lie it along a
-- direction, `stretch` to draw it as a streak rather than a blot.
function game.ground_mark(x, y, scale, opts)
	local q = game.decals
	if not q or #q >= DECAL_MAX_QUEUED then return end
	opts = opts or {}
	local m = MARK[opts.family or "bullet"] or MARK.bullet
	q[#q + 1] = {
		x = x, y = y,
		rect = m.rect,
		color = opts.color or m.color,
		alpha = opts.alpha or m.alpha,
		scale = scale or 1,
		stretch = opts.stretch or 1,
		rot = opts.rot or (love.math.random() * math.pi * 2),
	}
end

--- The plain red stain, for everything that is just blood hitting dirt.
function game.blood_decal(x, y, scale, alpha)
	game.ground_mark(x, y, scale, { family = "bullet", alpha = alpha })
end

local function flush_decals(game)
	local q = game.decals
	if not q or #q == 0 then return end
	love.graphics.setCanvas(game.terrain)
	for _, d in ipairs(q) do
		local img, sp = mark_sprite(d.rect)
		if img then
			local c = d.color
			love.graphics.setColor(c[1], c[2], c[3], d.alpha)
			local sc = d.scale * sp.scale
			-- stretch runs along the mark's own x, which `rot` has already
			-- pointed the way the shot was going
			love.graphics.draw(img, sp.quad, d.x, d.y, d.rot,
				sc * d.stretch, sc, sp.w / 2, sp.h / 2)
		end
	end
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setCanvas()
	for i = #q, 1, -1 do q[i] = nil end
end

-- Spatter thrown past whatever was hit, baked where it lands.
--
-- This is the part that makes a shotgun at point-blank range look like a
-- shotgun at point-blank range: the drops carry on along the shot and stain
-- the ground behind the body, so the field remembers where the shooting
-- happened and from which direction. A weapon that punches through (the
-- gauss family, the blade) throws it further and in a tighter line.
local EXIT_MIN, EXIT_MAX = 14, 46

local function exit_spatter(game, family, weapon_id, x, y, dir, power, count)
	local far = particles.punches_through(family, weapon_id)
	for _ = 1, count do
		local reach = (EXIT_MIN + love.math.random() * (EXIT_MAX - EXIT_MIN))
			* power * (far and 1.8 or 1)
		local spread = far and 0.12 or 0.5
		local a = dir + (love.math.random() - 0.5) * spread
		game.ground_mark(x + math.cos(a) * reach, y + math.sin(a) * reach,
			(0.35 + love.math.random() * 0.35) * power, {
				family = family,
				rot = a,
				-- a drop that flew reads as a streak, not a blot
				stretch = far and 2.2 or 1.4,
				alpha = (far and 0.4 or 0.3) + love.math.random() * 0.2,
			})
	end
end

--- Rocket-class detonation: area damage with linear falloff to the edge.
-- `blast` is the round's own trait table (game/traits.lua); the defaults are
-- the numbers this was written with, so a round carrying no sizes still goes
-- off the way the port has always made them go off.
local function explode(game, x, y, base_damage, art, blast)
	local radius = (blast and blast.radius) or 80
	local power = (blast and blast.damage) or 2
	particles.explosion(x, y, radius, art and BLAST_TINT[art])
	audio.play_sound("sfx/explosion_medium")
	game.shake(5)
	game.add_haze(x, y, radius)
	for _, c in ipairs(game.creatures) do
		local ddx, ddy = c.x - x, c.y - y
		local dist = math.sqrt(ddx * ddx + ddy * ddy)
		local reach = radius + 16 * c.scale
		if dist < reach then
			local falloff = 1 - 0.7 * (dist / reach)
			local dmg = base_damage * power * falloff
			-- thrown away from the blast rather than along a round's line: an
			-- explosion has no direction of its own, only an outside
			gibs.push(c, ddx / math.max(dist, 1e-6), ddy / math.max(dist, 1e-6),
				dmg * gibs.BLAST_SPEED)
			damage_creature(game, c, dmg)
		end
	end
end

--- How fast the world runs relative to the player. Reflex Boosted (the perk)
-- and Reflex Boost (the powerup) both slow everything but you, which is what
-- "you get more time to react" means from the inside.
local function world_rate(game)
	return game.mods.time_scale * (game.effects.REFLEX_BOOST and 0.55 or 1)
end

-- ------------------------------------------------------- perk-driven actions
--
-- Several perks do something once, at the moment they are taken, rather than
-- setting a modifier. They reach the game through these.

--- A blast at a point, for perks rather than ordnance (Man Bomb, Hot Tempered).
function game.explode_at(x, y, damage)
	explode(game, x, y, damage)
end

--- One attack landing on the player. Six perks meet here, so they meet in one
-- place rather than at each of the two call sites (a bite and a projectile).
-- Returns true if it actually cost health, which is what draws blood.
function game.on_attacked(raw)
	local mods, p = game.mods, game.player

	-- Dodger and Ninja: the hit simply misses
	if love.math.random() < mods.dodge then return false end

	-- Cold-blooded: "everyone around you gets frozen solid whenever a monster
	-- scratches or bites you" — it triggers on the attack, dodged or not
	if mods.freeze_on_hit > 0 then
		game.effects.FREEZE = math.max(game.effects.FREEZE or 0, mods.freeze_on_hit)
	end

	-- Highlander: no damage ever, but each attack is a roll against dying
	if mods.death_chance > 0 then
		if love.math.random() < mods.death_chance then
			p.hp = 0
			game.hurt = true
			return true
		end
		return false
	end

	local taken = mods.taken
	-- Tough Reloader takes nothing while reloading
	if p.reloading > 0 then taken = taken * mods.reload_guard end
	-- Living Fortress: the longer you have stood still, the less it hurts
	if mods.stand_ramp > 0 then
		taken = taken * (1 - mods.stand_ramp * ((p.still_t or 0) / RAMP_FULL))
	end
	if taken <= 0 then return false end

	p.hp = p.hp - raw * taken
	-- "Not a Scratch" is about being touched, not about the health bar: a
	-- medkit picked up afterwards must not undo it
	game.hurt = true
	-- being bitten has to be felt without looking at the health pie
	game.shake(2 + math.min(5, raw * taken * 0.3))
	return true
end

--- Random Weapon: "here, have this weapon. No questions asked."
function game.give_random_weapon()
	local order = data.weapon_order
	local cap = math.min(#order, game.weapon_cap or #order)
	local w = order[love.math.random(1, math.max(1, cap))]
	if not w then return end
	game.player.weapon = w
	game.player.ammo = game.clip_size()
	game.player.reloading = 0
	require("mods.vanilla.game.unlocks").saw_weapon(w)
end

--- Breathing Room: "the killing of every single creature on the screen"
function game.kill_everything()
	game.flash(0.6, 1, 0.9, 0.8)
	game.shake(9)
	for _, c in ipairs(game.creatures) do
		if not c.dying then
			particles.explosion(c.x, c.y, 50)
			damage_creature(game, c, 1e6)
		end
	end
	audio.play_sound("sfx/explosion_nuke")
end

--- Everything a perk does on a timer or in a radius, once per frame.
local function update_perks(game, dt)
	local mods, p = game.mods, game.player
	local aura = math.max(mods.aura_radius, mods.plague > 0 and 110 or 0)

	if aura > 0 and (mods.aura_dmg > 0 or mods.plague > 0) then
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				local ddx, ddy = c.x - p.x, c.y - p.y
				if ddx * ddx + ddy * ddy < aura * aura then
					-- Radioactive burns what stands near you...
					if mods.aura_dmg > 0 then
						damage_creature(game, c, mods.aura_dmg * dt)
					end
					-- ...Plaguebearer infects it, and infection travels
					if mods.plague > 0 then c.infected = true end
				end
			end
		end
	end

	-- Plaguebearer's contagion. The original notes that monsters build
	-- resistance "once in a while"; this port has no such state, so the
	-- infection simply persists -- a simplification, not a reading of the text.
	if mods.plague > 0 then
		for _, c in ipairs(game.creatures) do
			if c.infected and not c.dying then
				damage_creature(game, c, mods.plague * dt)
				for _, o in ipairs(game.creatures) do
					if not o.infected and not o.dying then
						local ddx, ddy = o.x - c.x, o.y - c.y
						if ddx * ddx + ddy * ddy < PLAGUE_SPREAD * PLAGUE_SPREAD then
							o.infected = true
						end
					end
				end
			end
		end
	end

	-- Jinxed: "creatures just drop dead and accidents happen"
	if mods.jinx > 0 and #game.creatures > 0 then
		game.jinx_t = (game.jinx_t or 0) + dt * mods.jinx
		while game.jinx_t >= 1 do
			game.jinx_t = game.jinx_t - 1
			local c = game.creatures[love.math.random(1, #game.creatures)]
			if c and not c.dying then
				particles.death_burst(c.x, c.y, c.scale)
				damage_creature(game, c, 1e6)
			end
		end
	end

	-- Hot Tempered: "you need to let it out once in a while"
	if mods.temper > 0 then
		game.temper_t = (game.temper_t or mods.temper) - dt
		if game.temper_t <= 0 then
			game.temper_t = mods.temper
			game.explode_at(p.x, p.y, 26)
		end
	end

	-- Fire Cough: "a fireball stuck in your throat. Repeatedly."
	if mods.cough > 0 then
		game.cough_t = (game.cough_t or mods.cough) - dt
		if game.cough_t <= 0 then
			game.cough_t = mods.cough
			game.bullets[#game.bullets + 1] = {
				x = p.x + math.cos(p.angle) * 20,
				y = p.y + math.sin(p.angle) * 20,
				dx = math.cos(p.angle),
				dy = math.sin(p.angle),
				speed = 460,
				dist_left = 420,
				damage = 30 * mods.dmg,
				fire = true,
			}
		end
	end

	-- Out of Thin Air: powerups turn up "even without blood being spilled"
	if mods.field_powerup > 0 and not game.no_drops then
		game.thin_air_t = (game.thin_air_t or mods.field_powerup) - dt
		if game.thin_air_t <= 0 then
			game.thin_air_t = mods.field_powerup
			drop_powerup(game,
				love.math.random(80, WORLD_W - 80),
				love.math.random(80, WORLD_H - 80))
		end
	end
end

-- ------------------------------------------------------------------ traits
--
-- The verbs a projectile can have (game/traits.lua). Each is a small change to
-- what a straight line already does, and weapons are recombinations of them --
-- which is the alternative to giving 38 weapons one decision between them
-- ("is the number bigger?").

--- Nearest living creature to a point, optionally within a range and skipping
-- ones already dealt with. Used by homing and by chaining.
local function nearest_creature(game, x, y, range, skip)
	local best, bestd
	for _, c in ipairs(game.creatures) do
		if not c.dying and not (skip and skip[c]) then
			local dx, dy = c.x - x, c.y - y
			local d = dx * dx + dy * dy
			if (not range or d < range * range) and (not bestd or d < bestd) then
				best, bestd = c, d
			end
		end
	end
	return best
end

-- How far a homing round looks for something to steer at. Beyond this it flies
-- straight, so a seeker fired at nothing does not curl around the field.
local HOMING_SIGHT = 420

--- Steer a round toward the nearest creature at its own turn rate. A rate
-- rather than a snap: a missile that turns instantly makes dodging pointless,
-- and the point of a seeker is that it corrects, not that it cannot be beaten.
local function steer_homing(game, b, dt)
	local target = nearest_creature(game, b.x, b.y, HOMING_SIGHT)
	if not target then return end
	local want = math.atan2(target.y - b.y, target.x - b.x)
	local cur = math.atan2(b.dy, b.dx)
	-- shortest way round the circle
	local diff = ((want - cur + math.pi) % (2 * math.pi)) - math.pi
	local turn = math.rad(b.traits.homing) * dt
	local a = cur + math.max(-turn, math.min(turn, diff))
	b.dx, b.dy = math.cos(a), math.sin(a)
end

--- Bounce a round off the edge of the playfield. Returns true while it still
-- has bounces left, false when it has run out and should die at the wall.
local function bounce(b)
	local left = b.traits.ricochet - (b.bounces or 0)
	if left <= 0 then return false end
	local hit = false
	if b.x < 0 or b.x > WORLD_W then
		b.dx = -b.dx
		b.x = math.max(0, math.min(WORLD_W, b.x))
		hit = true
	end
	if b.y < 0 or b.y > WORLD_H then
		b.dy = -b.dy
		b.y = math.max(0, math.min(WORLD_H, b.y))
		hit = true
	end
	if hit then
		b.bounces = (b.bounces or 0) + 1
		-- a bounce costs the round some of its reach, so a ricochet weapon is
		-- about angles rather than about lasting forever
		b.dist_left = math.max(b.dist_left, 160)
	end
	return true
end

--- Break a round into children when it stops. They carry the parent's family
-- and a share of its damage, so splitting buys reach, not free damage.
local function split_bullet(game, b)
	local sp = b.traits and b.traits.split
	if not sp or b.is_child then return end
	local base = math.atan2(b.dy, b.dx)
	local n = math.max(1, math.floor(sp.count))
	for k = 1, n do
		local t = (n == 1) and 0 or ((k - 1) / (n - 1) - 0.5) * 2
		local a = base + math.rad(t * sp.spread)
		game.bullets[#game.bullets + 1] = {
			x = b.x, y = b.y,
			dx = math.cos(a), dy = math.sin(a),
			speed = b.speed * 0.85,
			dist_left = 220,
			damage = b.damage * (sp.damage or 0.5),
			art = b.art,
			weapon_id = b.weapon_id,
			-- children do not split again, or one shot fills the field
			is_child = true,
		}
	end
end

--- Arc on from the creature just hit to further ones, losing bite each jump.
-- Reuses the shock-chain arc list, so it draws itself.
local function chain_from(game, b, c)
	local ch = b.traits.chain
	local skip = { [c] = true }
	local cx, cy = c.x, c.y
	local damage = b.damage * ch.decay
	for _ = 1, ch.jumps do
		local next_c = nearest_creature(game, cx, cy, ch.range, skip)
		if not next_c then break end
		skip[next_c] = true
		game.arcs[#game.arcs + 1] =
			{ x1 = cx, y1 = cy, x2 = next_c.x, y2 = next_c.y, t = 0 }
		damage_creature(game, next_c, damage)
		cx, cy = next_c.x, next_c.y
		damage = damage * ch.decay
	end
end

-- A creature cannot be shrunk away to nothing: below this it stops changing.
local MIN_CREATURE_SCALE = 0.4

--- Traits that land on the creature rather than on the round.
local function apply_on_hit(game, b, c)
	local tr = b.traits
	if not tr then return end
	if tr.chain then chain_from(game, b, c) end
	if tr.slow then
		c.slow_t = tr.slow.seconds
		c.slow_factor = tr.slow.factor
	end
	if tr.shrink then
		-- c.scale is the creature's own copy, so this cannot leak into every
		-- other creature sharing the variant. It shrinks the sprite, the hitbox
		-- and the reach of its bite together, because they all read c.scale.
		c.scale = math.max(MIN_CREATURE_SCALE, c.scale * tr.shrink)
	end
end

--- One round connecting with one creature: what it throws, what it leaves on
-- the ground, and what it does to the creature.
local function hit_creature(game, b, c)
	local dir = math.atan2(b.dy, b.dx)
	local power = particles.power(b.damage)
	local family = b.art or "bullet"

	-- Something still encased is not bleeding: chip the ice instead. Nothing
	-- under it has moved since it froze, so blood would be the wrong picture.
	local frozen = game.effects.FREEZE ~= nil
	if frozen then
		particles.ice_spall(b.x, b.y, dir, power)
	else
		particles.impact(family, b.weapon_id, b.x, b.y, dir, power)
		if love.math.random() < DECAL_HIT_CHANCE then
			exit_spatter(game, family, b.weapon_id, b.x, b.y, dir, power, 1)
		end
	end

	if game.mods.poison > 0 then
		c.poison_t = 4 -- refreshed on every hit
	end

	-- What the round carries, handed to the body before the body is asked
	-- whether it survived: if this is the hit that kills, the parts leave along
	-- the round's own line instead of in an even ring (game/gibs.lua).
	gibs.push(c, b.dx, b.dy, b.damage * b.speed)

	local killed = damage_creature(game, c, b.damage)
	-- The killing blow throws harder than the hits it survived, so the moment a
	-- creature breaks is seen rather than inferred from it falling over.
	if killed and not frozen then
		particles.impact(family, b.weapon_id, b.x, b.y, dir, power * 1.5)
		exit_spatter(game, family, b.weapon_id, b.x, b.y, dir, power * 1.3, 2)
	end
end

local function update_bullets(game, dt)
	for i = #game.bullets, 1, -1 do
		local b = game.bullets[i]
		local tr = b.traits

		-- a rocket is under power: it leaves the barrel slow and builds to the
		-- speed the weapon table gives it (game/traits.lua)
		if b.accel then b.speed = math.min(b.max_speed, b.speed + b.accel * dt) end
		if tr and tr.homing then steer_homing(game, b, dt) end

		local step = b.speed * dt
		b.x = b.x + b.dx * step
		b.y = b.y + b.dy * step
		b.dist_left = b.dist_left - step
		local dead = b.dist_left <= 0

		-- off the edge: bounce if this round bounces, otherwise let it run out
		if not dead and (b.x < 0 or b.x > WORLD_W or b.y < 0 or b.y > WORLD_H) then
			if not (tr and tr.ricochet and bounce(b)) then dead = true end
		end

		-- rockets that reach max range detonate instead of fizzling
		if dead and b.explosive then
			explode(game, b.x, b.y, b.damage, b.art, b.explosive)
		elseif dead and not b.hit and love.math.random() < MISS_MARK_CHANCE then
			-- A round that hit nothing still went somewhere. Marking where it
			-- landed is what makes a spray legible: the ground shows the shape
			-- of what you did, not just the hits you got. Faint and occasional,
			-- or a minigun paves the field.
			game.ground_mark(b.x, b.y, 0.3 + love.math.random() * 0.2, {
				family = b.art or "bullet",
				rot = math.atan2(b.dy, b.dx),
				stretch = 1.8,
				alpha = 0.12 + love.math.random() * 0.1,
			})
		end

		-- collide with creatures (circle radius ~16*scale)
		if not dead then
			for _, c in ipairs(game.creatures) do
				if not c.dying and not (b.hit and b.hit[c]) then
					local r = 16 * c.scale + 6
					local ddx, ddy = c.x - b.x, c.y - b.y
					if ddx * ddx + ddy * ddy < r * r then
						game.hits = game.hits + 1
						if b.explosive then
							explode(game, b.x, b.y, b.damage, b.art, b.explosive)
							dead = true
						else
							hit_creature(game, b, c)
							apply_on_hit(game, b, c)
							-- pierce: through this many bodies before stopping.
							-- The hit set is what stops one round scoring twice
							-- on the same creature as it passes through it.
							b.hit = b.hit or {}
							b.hit[c] = true
							b.pierced = (b.pierced or 0) + 1
							if b.pierced > (tr and tr.pierce or 0) then dead = true end
						end
						if dead then break end
					end
				end
			end
		end

		if dead then
			split_bullet(game, b)
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
		-- a gun just dropped cannot be walked back onto until it settles
		if d.arm_t then
			d.arm_t = d.arm_t - dt
			if d.arm_t <= 0 then d.arm_t = nil end
		end
		if d.arm_t == nil
			and ddx * ddx + ddy * ddy < PICKUP_RADIUS * PICKUP_RADIUS then
			if d.kind == "weapon" then
				-- The gun you were holding goes on the ground rather than being
				-- overwritten. That is what turns walking over a weapon from a
				-- thing that happens to you into a decision: the swap is
				-- reversible for a few seconds, and standing on the spot to undo
				-- it costs you the ground you were holding.
				if p.weapon and p.weapon ~= d.weapon then
					game.drops[#game.drops + 1] = {
						kind = "weapon", weapon = p.weapon,
						x = d.x, y = d.y, t = 0,
						-- short-lived, and it must not be picked up on the same
						-- step that dropped it
						life = DROPPED_WEAPON_LIFE,
						arm_t = DROPPED_WEAPON_ARM,
					}
				end
				p.weapon = d.weapon
				p.reloading = 0
				p.cooldown = 0
				p.ammo = game.clip_size()
				audio.play_sound("sfx/unlock_weapon")
				-- first time this profile has held it: the pak has a screen
				-- for that (attract mode does not get to unlock anything)
				if not game.demo then
					require("mods.vanilla.game.unlocks").saw_weapon(d.weapon)
					if d.weapon.id == "BLOW_TORCH" then
						local st = require("mods.vanilla.game.save").game.stats
						st.blowtorches = st.blowtorches + 1
					end
				end
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
		elseif d.t > (d.life or 30) then
			table.remove(game.drops, i) -- despawn eventually
		end
	end
end

local function update_creatures(game, dt)
	local p = game.player
	for i = #game.creatures, 1, -1 do
		local c = game.creatures[i]
		-- the lit frame after a hit, whatever else the creature is doing
		if c.flash_t then
			c.flash_t = c.flash_t - dt
			if c.flash_t <= 0 then c.flash_t = nil end
		end
		if c.overkill then
			-- it came apart rather than fell over: there is no animation left to
			-- play and no corpse to bake, the parts are already in the air
			table.remove(game.creatures, i)
		elseif c.dying then
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
					bms.draw(seq, seq.count, c.x, c.y, c.rot or 0, c.scale)
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
			-- Bad Blood slows them; Reflex Boost (perk or powerup) slows the
			-- whole world, which for a creature is the same thing
			-- Plasma leaves what it hits moving slower; the effect wears off.
			if c.slow_t then
				c.slow_t = c.slow_t - dt
				if c.slow_t <= 0 then c.slow_t, c.slow_factor = nil, nil end
			end
			local speed = v.speed * SPEED_SCALE * game.mods.creature_speed
				* world_rate(game) * (c.slow_factor or 1)

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
				c.x = math.max(32, math.min(WORLD_W - 32, c.x + math.cos(c.wander_a) * speed * dt))
				c.y = math.max(32, math.min(WORLD_H - 32, c.y + math.sin(c.wander_a) * speed * dt))
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
						x = c.x + math.cos(a) * 14 * c.scale,
						y = c.y + math.sin(a) * 14 * c.scale,
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
							math.max(32, math.min(WORLD_W - 32, c.x + math.cos(a) * 30)),
							math.max(32, math.min(WORLD_H - 32, c.y + math.sin(a) * 30)))
					end
				end
			end

			-- contact damage (Thick Skinned, Tough Reloader, Dodger, Highlander,
			-- Cold-blooded, Living Fortress, Mr. Melee)
			local touch = 16 * c.scale + 14
			if dist < touch then
				if c.attack_cd <= 0 and not game.effects.SHIELD
					and v.damage > 0 then
					c.attack_cd = 0.8
					-- a shrunk creature bites for less: c.scale carries the
					-- Shrinkifier's effect, and it is the whole point of a weapon
					-- whose damage rating is otherwise the worst in the game
					game.on_attacked(v.damage * game.damage_mul
						* (c.scale / v.scale))
					local snd = c.def and c.def.sounds and c.def.sounds.snd_attack_01
					if snd and snd ~= "!NONE" then audio.play_sound(snd) end
				end
				-- Mr. Melee: "you don't just stand still. You hit back. Hard."
				if game.mods.melee > 0 then
					damage_creature(game, c, game.mods.melee * dt)
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
				if not game.effects.SHIELD then
					if game.on_attacked(b.damage) then
						particles.blood(b.x, b.y, math.atan2(b.dy, b.dx))
					end
				end
			end
		end
		if dead then table.remove(game.ebullets, i) end
	end
end

--- The UI screen sitting over a live session, if any (PickAPerk, PerkUnlocked,
-- LevelCompleted, ...). While one is up the pointer belongs to the UI rather
-- than to the gun, which is what pauses gameplay, stands the crosshair down and
-- hands the OS cursor back. The demo is the thing menus are drawn ON, so it is
-- never "under" a screen in this sense.
function game.ui_screen()
	if game.demo then return nil end
	local top = require("src.engine.screens").top()
	if top and top.name ~= "GameCrimsonland" then return top end
	return nil
end

function game.update(dt)
	if not game.active then return end

	-- gameplay pauses whenever a UI screen overlays the game
	-- (PickAPerk, LevelCompleted, ...); keep the perk preview live
	local top = game.ui_screen()
	if top then
		if top.name == "PickAPerk" then
			update_perk_hover(top)
		elseif top.name == "PlayMenuCustomQuests" then
			update_custom_quest_hover(top)
		end
		return
	end

	game.time = game.time + dt

	-- the demo never ends: a dead AI just starts another fight
	if game.demo and game.outcome then
		game.start_demo()
		return
	end

	-- ...and a scene that has had its authored run moves on to the next of the
	-- five. demos.xml gives each a duration -- 7 to 12 seconds -- which is what
	-- makes the backdrop a rotation of five pictures rather than one fight held
	-- until its AI dies.
	if game.demo and game.demo_left then
		game.demo_left = game.demo_left - dt
		if game.demo_left <= 0 then
			game.start_demo()
			return
		end
	end

	if game.outcome then
		game.end_timer = game.end_timer - dt
		-- let the gore finish, then hand over to the original end screens
		update_creatures(game, dt)
		gibs.update(dt, game.terrain)
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
	elseif game.mode == "custom" then
		update_custom(game) -- an authored list, not a ramp
	elseif game.mode ~= "quest" then
		update_survival_ramp(game) -- survival, blitz, nukefism, weaponpicker
	end
	if game.field_spawn_cd then
		update_field_spawns(game, dt)
	end

	-- timed powerup effects tick down
	local was_frozen = game.effects.FREEZE
	for id, left in pairs(game.effects) do
		left = left - dt
		game.effects[id] = (left > 0) and left or nil
	end
	-- the field thaws all at once, so every creature still standing sheds its
	-- cube in the same frame
	if was_frozen and not game.effects.FREEZE then
		for _, c in ipairs(game.creatures) do
			if not c.dying then
				particles.ice_shatter(c.x, c.y, c.scale)
			end
		end
	end

	update_player(game, dt)
	update_bullets(game, dt)
	update_creatures(game, dt)
	update_ebullets(game, dt)
	update_drops(game, dt)
	-- parts in flight settle into the ground they land on
	gibs.update(dt, game.terrain)
	update_impact(game, dt)
	flush_decals(game)

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
	-- Perk Expert and Perk Master lower what a level costs, so they earn
	-- themselves back in more perks
	local needed = game.xp_next * game.mods.level_cost
	if game.xp >= needed then
		game.xp = game.xp - needed
		game.level = game.level + 1
		game.xp_next = math.floor(game.xp_next * 1.5)
		print(("[game] level up! now level %d"):format(game.level))
		game.levelup_t = game.time -- HUD flashes the level-up ring
		game.announce(("LEVEL %d"):format(game.level))
		open_perk_screen(game)
		return
	end

	update_perks(game, dt)

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

	-- An authored quest is won by clearing what the author placed: the spawn
	-- list run out, and nothing of it left standing.
	local custom_cleared = game.mode == "custom" and game.custom
		and game.custom_next > #game.custom.spawns and #game.creatures == 0

	-- win/lose (survival has no win condition; bosses must die to win)
	if custom_cleared then
		game.outcome = "won"
		game.end_timer = 1.2
		print(("[custom] cleared: %s"):format(game.custom.name))
		if not game.demo then
			require("mods.vanilla.game.save").record_session(game)
			require("mods.vanilla.game.achievements").evaluate(game)
		end
	elseif game.kills_goal and game.kills >= game.kills_goal
		and game.boss_pending == 0 and game.bosses_alive == 0 then
		game.outcome = "won"
		game.end_timer = 1.2
		print("[game] quest completed!")
		require("mods.vanilla.game.save").mark_quest_completed(game.chapter, game.quest,
			game.difficulty, not game.hurt)
		if not game.demo then
			require("mods.vanilla.game.save").record_session(game)
			require("mods.vanilla.game.achievements").evaluate(game)
		end
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
		-- the AI's attract-mode runs are nobody's score and nobody's statistics
		if not game.demo then
			local save = require("mods.vanilla.game.save")
			-- every endless mode keeps its own best, not just survival
			if game.mode ~= "quest" then
				game.new_highscore = save.record_run(game.mode, game.score,
					game.time, game.kills)
				if game.new_highscore then print("[game] new local high score!") end
			end
			save.record_session(game)
			require("mods.vanilla.game.achievements").evaluate(game)
		end
	end
end

--- The weapon this round was fought with: the one that fired the most shots,
-- which is what "Favorite Weapon" means on both end screens. Nukefism has no
-- weapon at all, and a round can end before a single trigger pull.
function game.favorite_weapon()
	local best, best_shots = nil, 0
	for id, shots in pairs(game.weapon_shots) do
		if shots > best_shots then best, best_shots = data.weapons[id], shots end
	end
	return best
end

-- Pixels per footstep. The trooper is 36 px from shoulder to boot on his 64 px
-- sprite; read as a 1.8 m human that puts the world at ~5 cm per pixel, so an
-- ordinary 1 m walking stride is 20 px. The layout's own sample round checks
-- it: level-completed.lua ships "560" steps against a time of "01:17", and 77 s
-- of running at the trooper's 180 px/s covers 13 860 px — 693 steps at 20 px
-- each, which is the authored number once the standing still is taken out.
-- Nothing but the "Steps Taken" readout depends on this.
local STEP_LENGTH = 20

-- The six tallies down the side of the survival panel, comp name -> powerup.
-- The layout names them in its own spelling and parents each to the matching
-- icon (ui/survival-over.lua), which is what identifies FIRERING as the
-- fireblast; the other five are their own names with the underscore gone.
local SURVIVAL_TALLIES = {
	POWERUP_NUKE = "NUKE",
	POWERUP_FIRERING = "FIREBLAST",
	POWERUP_FIRESPINNER = "FIRE_SPINNER",
	POWERUP_FREEZE = "FREEZE",
	POWERUP_SHOCKCHAIN = "SHOCK_CHAIN",
	POWERUP_SPEED = "SPEED",
}

--- Push the appropriate original end screen for the finished round.
--
-- The layouts ship with a designer's sample round baked into every textbox
-- ("57" kills, "01:17", a Blade Gun) — the C++ engine overwrote them all on
-- entry, and any field left alone here shows that sample as if it were the
-- player's own result.
function game.open_end_screen()
	local screens = require("src.engine.screens")
	local comps = require("src.engine.comps")

	local s
	local function put(name, text)
		if s.compmap[name] then
			comps.set(s.compmap[name], "textbox.text", { tostring(text) })
		end
	end
	local function show(name, visible)
		if s.compmap[name] then
			comps.set(s.compmap[name], "visible", { visible == true })
		end
	end
	local function put_favorite_weapon()
		local w = game.favorite_weapon()
		put("WeaponName", w and (w.name or w.id) or "Bare Hands")
		-- the end screens use the big portrait of the weapon, not the HUD icon
		if s.compmap.WeaponIcon and w and w.icon then
			comps.set(s.compmap.WeaponIcon, "image.bitmap",
				{ (w.icon:gsub("^weapons/", "weapons/large/")) })
		end
	end
	local function accuracy()
		return string.format("%d%%",
			game.shots > 0 and math.floor(game.hits / game.shots * 100 + 0.5) or 0)
	end
	local function clock()
		return string.format("%d:%02d", math.floor(game.time / 60),
			math.floor(game.time % 60))
	end

	if game.mode ~= "quest" then -- every endless mode ends on this screen
		s = screens.push("SurvivalOver")
		put("Score", string.format("%d", game.score))
		put("Time", clock())
		put("Kills", string.format("%d", game.kills))
		put("Accuracy", accuracy())
		put_favorite_weapon()
		for comp, id in pairs(SURVIVAL_TALLIES) do
			put(comp, string.format("%d", game.powerups_taken[id] or 0))
		end
		show("NewLocalHighscore", game.new_highscore)
	elseif game.outcome == "won" then
		s = screens.push("LevelCompleted")
		put("Time", clock())
		put("Frags", string.format("%d", game.kills))
		-- kills per minute, the panel's own headline stat
		put("KillsPerMinute", string.format("%.2f",
			game.time > 0 and game.kills / (game.time / 60) or 0))
		put("Shots", string.format("%d", game.shots))
		put("Footsteps", string.format("%d", math.floor(game.walked / STEP_LENGTH)))
		put("Accuracy", accuracy())
		put_favorite_weapon()
		show("Unharmed", not game.hurt)
		-- co-op leftovers: there is no second trooper to compare kills with
		show("TrooperComparisonGroup", false)
	else
		screens.push("LevelFailed")
	end
end

-- ------------------------------------------------------------ camera/draw

function game.camera()
	local p = game.player
	local cx = math.max(0, math.min(WORLD_W - SCREEN_W, p.x - SCREEN_W / 2))
	local cy = math.max(0, math.min(WORLD_H - SCREEN_H, p.y - SCREEN_H / 2))
	-- The jolt is added and then clamped again: at the edges of the world it
	-- gets damped on that side rather than pulling the view off the baked
	-- ground and showing the black behind it.
	cx = math.max(0, math.min(WORLD_W - SCREEN_W, cx + (game.shake_x or 0)))
	cy = math.max(0, math.min(WORLD_H - SCREEN_H, cy + (game.shake_y or 0)))
	return cx, cy
end

-- Every creature in creatures.xml names a `bm_shadow` (a soft dark blob,
-- circle or ellipse) and the trooper names one too. Drawn at the creature's
-- own scale, under everything alive, which is what stops the sprites reading
-- as stickers laid on the ground.
local SHADOW_ALPHA = 0.5

-- Seconds a dying creature's shadow takes to go. Without the fade it blinks
-- out on the frame the death starts, while the body is still body-shaped.
local SHADOW_FADE = 0.6

local function draw_shadow(def, x, y, scale, fade)
	local img = def and def.shadow and assets.image(def.shadow)
	if not img then return end
	local a = SHADOW_ALPHA * (fade or 1)
	if a <= 0 then return end
	love.graphics.setColor(1, 1, 1, a)
	love.graphics.draw(img, x, y, 0, scale, scale,
		img:getWidth() / 2, img:getHeight() / 2)
end

--- A creature whose whole body has changed colour: frozen solid, or rotting
-- from Poison Bullets. Returns nil when the creature is its normal self.
-- Three return values rather than a table: this runs per creature per frame.
local function state_tint(game, c)
	if c.dying then return nil end
	local v = c.variant
	if game.effects.FREEZE then
		return v.r * 0.5, v.g * 0.7, math.min(1, v.b + 0.5)
	end
	if c.poison_t then
		return v.r * 0.6, math.min(1, v.g + 0.4), v.b * 0.6
	end
	return nil
end

--- One creature: its body, in its variant's colour, wearing ice if the field
-- is frozen.
--
-- On the variant colour, and why it multiplies the whole sprite: seven of the
-- creatures pair their animation with a `*-stencil.bms` -- the same frames,
-- but only a small region opaque, in grey, and inside that region the base's
-- luma and the stencil's grey agree to ~12/255. That reads like a mask for
-- recolouring, so this port tried it: body untinted, stencil over it in the
-- variant colour. Rendered out against the real variant colours it is plainly
-- worse. The region is a couple of stripes along the back, so every variant
-- comes out the same pale creature with differently coloured piping, and the
-- colour coding that tells a player which alien is the dangerous one is gone.
-- Multiplying the whole sprite is what makes a blue one read as a different
-- creature from a green one, so that is what stays. What the stencils are
-- actually for is still unknown. A hit flash was the other plausible reading
-- and it was tried too: masking the flash below to the stencil lights a couple
-- of stripes without changing the silhouette, so the eye never registers a hit
-- at all. Two independent experiments, both worse than not using them --
-- data.lua parses them, nothing draws them.
local function draw_creature(game, c)
	local def, v = c.def, c.variant
	local seq, frame, rot

	if c.dying then
		seq = def and def.die and bms.load(def.die)
		if seq then
			frame = math.min(seq.count,
				math.floor(c.die_t * 24 * (def.die_speed or 1)) + 1)
		end
		rot = c.rot or 0
	else
		seq = def and def.move and bms.load(def.move)
		if seq then
			frame = math.floor(c.anim_t * 24 * (def.move_speed or 1)) + 1
		end
		-- Creature art faces +X (the lizard's snout, the spider's mandibles and
		-- the zombie's arms all point right in their frames), so the angle to
		-- the player is the rotation as-is. The quarter turn the player wears
		-- (game.draw) is the trooper's own convention: that art faces -Y.
		rot = c.fixed_rot -- dens/nests don't track the player
			or math.atan2(game.player.y - c.y, game.player.x - c.x)
	end

	local tr, tg, tb = state_tint(game, c)
	if not tr then tr, tg, tb = v.r, v.g, v.b end
	-- The variant's own alpha (creature-variants.xml color_base_a). A frozen or
	-- burning creature keeps it: the state tint says what colour it is, not how
	-- solid, and a wisp that froze should still be a wisp. The hit flash below
	-- deliberately does not -- being told you connected is worth more than the
	-- half-frame of visibility it costs.
	love.graphics.setColor(tr, tg, tb, v.alpha or 1)

	if not seq then
		love.graphics.circle("fill", c.x, c.y, 14 * c.scale)
		return
	end
	bms.draw(seq, frame, c.x, c.y, rot, c.scale)

	-- The lit frame after a hit: the same frame again, additively, so the shape
	-- that flashes is exactly the creature's own. This is what makes the
	-- pellets of a shotgun blast countable -- without it a hit is only visible
	-- as blood, which says something was hit but not what or how often.
	if c.flash_t then
		local k = math.max(0, c.flash_t / HIT_FLASH) * 0.85
		love.graphics.setBlendMode("add")
		love.graphics.setColor(k, k, k, 1)
		bms.draw(seq, frame, c.x, c.y, rot, c.scale)
		love.graphics.setBlendMode("alpha")
	end

	-- Encased: game/ice-cube.bms is four blocks rather than an animation, so
	-- each creature holds the one it was given. The block is a 64px frame, the
	-- same as the creature it covers, and drawn at its own size it swallows
	-- the thing whole -- a frozen enemy you cannot identify is still a target
	-- you have to shoot. At 0.8 the legs and antennae stay outside the ice.
	if game.effects.FREEZE and not c.dying then
		local ice = bms.load("game/ice-cube.bms")
		if ice then
			love.graphics.setColor(1, 1, 1, 0.7)
			bms.draw(ice, c.ice_frame or 1, c.x, c.y, 0, c.scale * 0.8)
		end
	end
end

-- How much glow the frame carries during play. The additive effects -- muzzle
-- flash, explosions, plasma, the level-up ring -- are drawn to be bright, and
-- this is what makes them read as light falling on the field rather than as
-- pale sprites sitting on it. Low: the art is 2003 hand-painted work and it
-- does not want to be a bloom demo.
local BLOOM = 0.30

--- Ask the engine's post pass for whatever this frame's state calls for.
--
-- Grading the finished canvas grades the UI drawn on it too, so this only runs
-- when the game owns the whole frame: not under a menu, and never in the
-- attract demo, where a frozen field would turn the main menu blue.
local function grade_frame(game, camx, camy)
	local screens = require("src.engine.screens")
	local postfx = require("src.engine.postfx")
	local top = screens.top()
	if not top or top.name ~= "GameCrimsonland" then return end

	local g = { bloom = BLOOM }

	-- The field is frozen solid: cold light, and the colour drains with it.
	if game.effects.FREEZE then
		g.tint = { 0.55, 0.78, 1.25 }
		g.tint_amount = 0.55
		g.saturation = 0.7
	end

	-- Reflex Boost slows everything but the player. Draining some colour and
	-- closing the edges in is what makes that read as *their* perception
	-- changing rather than the game running badly.
	--
	-- Only the powerup, which runs for eight seconds -- not the Reflex Boosted
	-- perk, which slows time for the rest of the run and would therefore grade
	-- the rest of the run. A permanent vignette does not read as a power, it
	-- reads as a broken renderer.
	--
	-- 0.72 rather than the 0.45 this started at: at 0.45 the world drained,
	-- but so did the fireballs, and an explosion that comes out grey is a
	-- worse trade than a slightly less obvious slow-motion.
	if game.effects.REFLEX_BOOST then
		g.saturation = math.min(g.saturation or 1, 0.72)
		g.vignette = 0.3
	end

	if (game.flash_t or 0) > 0 and game.flash_dur then
		local k = game.flash_t / game.flash_dur
		g.flash = (game.flash_amount or 0) * k * k
		g.flash_color = game.flash_rgb
	end

	postfx.set(g)

	-- Blasts bend the air over themselves. World coordinates come through the
	-- camera first, because the post pass works on the finished screen.
	for _, h in ipairs(game.hazes) do
		local k = 1 - h.t / HAZE_TIME
		postfx.add_haze(h.x - camx, h.y - camy, h.radius * 2.2, k)
	end
	-- a flamethrower's own barrel shimmer, while it is actually burning
	local p = game.player
	if p.weapon and FLAME[p.weapon.id] and p.muzzle > 0 then
		postfx.add_haze(p.x - camx + math.cos(p.angle) * 40,
			p.y - camy + math.sin(p.angle) * 40, 70, 0.7)
	end
end

-- game/projs.tga is the projectile sheet the original drew rounds from: a
-- 128x128 image with four sprites on it, located by scanning it for opaque
-- regions. Which weapon wears which is data (data.lua's projectile_art
-- reads weapons.xml's own type/flags). The fourth sprite -- a wide white
-- dome at (5,26,55,27) -- matches nothing this port fires, so it is left
-- alone rather than guessed into service.
-- How thick a kinetic round's trail is. How *long* it is no longer lives here:
-- a fixed 22 pixels drew the Gauss Gun's hypervelocity slug with the same smear
-- as a pistol round, so length comes off the round's own speed now
-- (data.tracer). The width stays a constant, because a tracer is a line
-- whatever is drawing it.
local BULLET_TRAIL_W = 3

local PROJ_SHEET = "game/projs.tga"
-- An energy bolt's size rides on the round (game/data.lua computes it per
-- weapon); this is only what to draw when something fires one without a
-- weapon behind it, and how much wider the light under a bolt is than the
-- bolt itself.
local BOLT_FALLBACK = 0.55
local BOLT_LIGHT = 2.9

local PROJ_RECT = {
	rocket = { 104, 5, 16, 20 },
	glow = { 69, 5, 22, 22 },
	blade = { 66, 34, 29, 29 },
	-- The fourth sprite, and the last one on the sheet to be placed: a bright
	-- arc fading behind itself, which is a wave front seen from above. The pulse
	-- gun is the only weapon that fires one (weapons.xml type=3, its own family)
	-- and the pak ships sfx/shockwave.ogg next to it.
	wave = { 5, 26, 55, 27 },
}
local proj_cache = {}

--- Draw one sheet sprite centered at x,y. Quads address texels, so the
-- origin is in texels too and the draw scale carries the atlas density out
-- (assets.quad's second return) -- the same dance fx.draw does.
local function draw_proj(name, x, y, rot, scale, r, g, b, a, additive)
	local img = assets.image(PROJ_SHEET)
	if not img then return false end
	local s = proj_cache[name]
	if not s then
		local rect = PROJ_RECT[name]
		local quad, qs = assets.quad(img, rect[1], rect[2], rect[3], rect[4])
		local _, _, qw, qh = quad:getViewport()
		s = { quad = quad, scale = qs, w = qw, h = qh }
		proj_cache[name] = s
	end
	if additive then love.graphics.setBlendMode("add") end
	love.graphics.setColor(r, g, b, a)
	local draw_scale = scale * s.scale
	love.graphics.draw(img, s.quad, x, y, rot, draw_scale, draw_scale,
		s.w / 2, s.h / 2)
	if additive then love.graphics.setBlendMode("alpha") end
	return true
end

-- Light on the ground.
--
-- Not a lighting system: the same additive glow sprite the energy bolts are
-- drawn with, laid on the terrain under whatever is emitting, before anything
-- alive is drawn over it. That is enough for a muzzle flash to light the grass
-- in front of the player and a blast to wash the field around it -- which is
-- what the additive sprites above the ground were missing. They were bright
-- against the dark, but nothing under them ever got brighter.
local function draw_lights(game)
	local p = game.player

	if p.hp > 0 and p.muzzle > 0 then
		local k = math.min(1, p.muzzle / 0.05)
		draw_proj("glow", p.x + math.cos(p.angle) * 30, p.y + math.sin(p.angle) * 30,
			0, 3.4, 1, 0.85, 0.5, 0.45 * k, true)
	end

	-- blasts: the light goes out faster than the smoke does
	for _, h in ipairs(game.hazes) do
		local k = 1 - h.t / HAZE_TIME
		if k > 0 then
			draw_proj("glow", h.x, h.y, 0, (h.radius / 22) * 3.2,
				1, 0.72, 0.38, 0.7 * k * k, true)
		end
	end

	for _, b in ipairs(game.bullets) do
		if b.flame or b.fire then
			draw_proj("glow", b.x, b.y, 0, 1.8, 1, 0.5, 0.15, 0.22, true)
		elseif b.art == "plasma" or b.art == "ion" then
			-- the light a bolt throws is the bolt, three times over: a cannon
			-- ball lights the ground it crosses, a shotgun pellet barely does
			local c = FAMILY_TINT[b.art]
			draw_proj("glow", b.x, b.y, 0, (b.bolt or BOLT_FALLBACK) * BOLT_LIGHT,
				c[1], c[2], c[3], 0.2, true)
		elseif b.art == "pulse" then
			draw_proj("glow", b.x, b.y, 0, 2.0, 1, 0.9, 0.5, 0.22, true)
		end
	end

	for _, b in ipairs(game.ebullets) do
		draw_proj("glow", b.x, b.y, 0, 1.5, 0.3, 1, 0.4, 0.2, true)
	end
end

function game.draw()
	-- the crosshair replaces the OS cursor while a session runs; the demo is
	-- not being played by the person holding the mouse, so they keep theirs.
	-- A UI screen over the session (PickAPerk, PerkUnlocked, ...) gives the
	-- pointer back too: without it there is nothing to aim the click with.
	love.mouse.setVisible(not game.active or game.demo or game.ui_screen() ~= nil)
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

	-- what the bright things are throwing onto it
	draw_lights(game)

	-- Drops, under everything alive. A weapon drop wears its own icon and its
	-- family's colour on the plate, so what is lying there can be read from
	-- across the field instead of discovered by standing on it -- which matters
	-- now that stepping on one puts the gun in your hands and yours on the
	-- ground.
	local base_img = assets.image("powerups/base.png")
	for _, d in ipairs(game.drops) do
		local bob = math.sin(d.t * 3) * 3
		local life = d.life or 30
		local alpha = (d.t > life - 5)
			and (0.4 + 0.6 * math.abs(math.sin(d.t * 8))) or 1
		local tint = d.kind == "weapon" and d.weapon
			and FAMILY_TINT[d.weapon.proj_art] or nil
		if tint then
			love.graphics.setColor(tint[1], tint[2], tint[3], alpha)
		else
			love.graphics.setColor(1, 1, 1, alpha)
		end
		if base_img then
			love.graphics.draw(base_img, d.x, d.y, 0, 0.7, 0.7,
				base_img:getWidth() / 2, base_img:getHeight() / 2)
		end
		love.graphics.setColor(1, 1, 1, alpha)
		local icon = assets.image(d.kind == "weapon" and d.weapon.icon
			or d.kind == "powerup" and d.powerup.icon
			or "powerups/powerup-medikit.png")
		if icon then
			love.graphics.draw(icon, d.x, d.y - 4 + bob, 0, 0.5, 0.5,
				icon:getWidth() / 2, icon:getHeight() / 2)
		end
	end

	-- shadows first, all of them, then the bodies: a shadow belongs to the
	-- ground, so it must not fall across the neighbour standing next to it
	for _, c in ipairs(game.creatures) do
		local fade = c.dying
			and math.max(0, 1 - (c.die_t or 0) / SHADOW_FADE)
			or 1
		draw_shadow(c.def, c.x, c.y, c.scale, fade)
	end
	if game.player.hp > 0 then
		draw_shadow(data.creatures.TROOPER, game.player.x, game.player.y, 1)
	end

	-- body parts still in the air from a kill, under the living
	gibs.draw()

	for _, c in ipairs(game.creatures) do
		draw_creature(game, c)
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
		-- Muzzle flash, sized by what actually left the barrel: the shot's whole
		-- damage output against the pistol's. A shotgun throwing twelve pellets
		-- lights the field; a pistol does not. Same measure the spatter uses, so
		-- the flash and the blood a shot causes agree with each other.
		if p.muzzle > 0 then
			local mf = assets.image("game/muzzle-flash.png")
			if mf then
				local w = p.weapon
				local power = w and particles.power(
					w.damage_effective * math.max(1, w.num_projectiles)) or 1
				local s = 0.36 * power
				love.graphics.setBlendMode("add")
				love.graphics.setColor(1, 1, 1, p.muzzle / 0.05)
				love.graphics.draw(mf, p.x + math.cos(p.angle) * 28, p.y + math.sin(p.angle) * 28,
					p.angle, s, s, mf:getWidth() / 2, mf:getHeight() / 2)
				love.graphics.setBlendMode("alpha")
			end
		end
	end

	-- bullets: the sprite its weapon's family calls for. Fire and flame keep
	-- flickering because the flame IS the flicker; the rest are steady art.
	local bullet_img = assets.image("game/bullet16.tga")
	local trail_img = assets.image("game/bulletTrail.tga")
	for _, b in ipairs(game.bullets) do
		local rot = math.atan2(b.dy, b.dx)
		if b.flame or b.fire then
			-- Flicker from the clock and the round's own position, NOT from
			-- love.math.random: draw runs a variable number of times per second
			-- (it depends on the machine, and in the test harness on how many
			-- updates are batched behind a frame), so drawing from the shared
			-- generator feeds gameplay a different stream on every run. That is
			-- what the seeded harness means when it promises two runs agree.
			draw_proj("glow", b.x, b.y, rot, (b.flame and 0.66 or 0.46)
				+ math.sin(game.time * 37 + b.x * 0.13) * 0.06,
				1, 0.55, 0.15, 0.85, true)
		elseif b.art == "rocket" then
			-- the sprite is painted nose-up, so it needs a quarter turn to fly
			draw_proj("rocket", b.x, b.y, rot + math.pi / 2, 1, 1, 1, 1, 1, false)
		elseif b.art == "blade" then
			-- a thrown blade spins on its own axis, not along its path
			draw_proj("blade", b.x, b.y, game.time * 16, 1, 1, 1, 1, 1, false)
		elseif b.art == "plasma" or b.art == "ion" then
			-- one sprite, two families: the colour and the size are the
			-- weapon's own (game/data.lua), which is what makes an ion cannon's
			-- slow blue ball and a plasma shotgun's amber spark the same art
			local c = FAMILY_TINT[b.art]
			draw_proj("glow", b.x, b.y, rot, b.bolt or BOLT_FALLBACK,
				c[1], c[2], c[3], 0.9, true)
		elseif b.art == "pulse" then
			-- the bright edge of the arc has to lead, and the sprite is painted
			-- with it along the top, so the wave turns a quarter past its heading
			draw_proj("wave", b.x, b.y, rot + math.pi / 2, 0.7, 1, 0.92, 0.6, 0.9, true)
		elseif bullet_img then
			-- kinetic: the trail is drawn from its own right edge, so it lies
			-- behind the round along the way it came. Its length and colour are
			-- the round's own speed (game/data.lua), which is the whole of what
			-- makes the Gauss Gun a railgun rather than a fast bullet.
			if trail_img then
				local len, tr, tg, tb, ta = data.tracer(b.speed)
				love.graphics.setBlendMode("add")
				love.graphics.setColor(tr, tg, tb, ta)
				love.graphics.draw(trail_img, b.x, b.y, rot,
					len / trail_img:getWidth(), BULLET_TRAIL_W / trail_img:getHeight(),
					trail_img:getWidth(), trail_img:getHeight() / 2)
				love.graphics.setBlendMode("alpha")
			end
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.draw(bullet_img, b.x, b.y, rot + math.pi / 2, 0.6, 0.6,
				bullet_img:getWidth() / 2, bullet_img:getHeight() / 2)
		else
			love.graphics.setColor(1, 1, 0.6, 1)
			love.graphics.circle("fill", b.x, b.y, 2.5)
		end
	end

	-- creature plasma bolts: the same glow the player's energy weapons use,
	-- in the green that says "this one is coming at you"
	for _, b in ipairs(game.ebullets) do
		if not draw_proj("glow", b.x, b.y, 0, 0.5, 0.3, 1, 0.4, 0.9, true) then
			love.graphics.setBlendMode("add")
			love.graphics.setColor(0.3, 1, 0.4, 0.9)
			love.graphics.circle("fill", b.x, b.y,
				4.75 + math.sin(game.time * 31 + b.y * 0.11) * 0.75)
			love.graphics.setBlendMode("alpha")
		end
	end

	-- shock-chain links: bright, thin and gone almost at once
	if #game.arcs > 0 then
		love.graphics.setBlendMode("add")
		for _, a in ipairs(game.arcs) do
			local k = 1 - a.t / SHOCK_ARC_LIFE
			love.graphics.setColor(0.6, 0.85, 1, k)
			love.graphics.setLineWidth(1 + 2 * k)
			love.graphics.line(a.x1, a.y1, a.x2, a.y2)
		end
		love.graphics.setLineWidth(1)
		love.graphics.setBlendMode("alpha")
	end

	hud.draw_shield(game, game.player.x, game.player.y)
	hud.draw_levelup_ring(game, game.player.x, game.player.y)
	-- inside the camera transform: brass, blood, fire and smoke on the ground
	fx.draw("world")

	love.graphics.pop()

	if game.demo then
		-- menu panels have to stay readable over a firefight
		love.graphics.setColor(0.03, 0.01, 0.02, 0.45)
		love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
		love.graphics.setColor(1, 1, 1, 1)
		return -- no HUD: it is a backdrop, not a session the player owns
	end

	grade_frame(game, camx, camy)

	-- HUD (screen space): original 2014 art — health pie, crosshair with
	-- reload sweep, XP strip, effect timers (game/hud.lua)
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

--- The play menu ships a handler for a button it does not declare.
--
-- ui/play-menu-events.lua answers a click on "Play_CustomQuests" by pushing
-- PlayMenuCustomQuests — the code is right there in the pak, and only the
-- layout omits the comp, so the mode has been reachable-in-principle and
-- unreachable-in-fact all along. Creating the button is the whole fix: the
-- original's own script handles the click.
--
-- It goes under the Quests/Survival pair rather than beside them, because the
-- aligner those two hang from is sized for two.
local function add_custom_quests_button(screen)
	if screen.compmap.Play_CustomQuests then return end
	if #customquests.all() == 0 then return end -- nothing authored to play
	local comps = require("src.engine.comps")
	local panel = screen.compmap.panel
	if not panel then return end

	local c = comps.new("Button", "Play_CustomQuests", screen)
	c._order = #screen.comps + 1
	table.insert(screen.comps, c)
	screen.compmap[c.name] = c
	c.parent = panel
	table.insert(panel.children, c)
	comps.set(c, "inherit", { "SmallButton" })
	comps.set(c, "align", { "HCENTER" })
	comps.set(c, "position", { 0, 0.29 })
	comps.set(c, "localize", { 0 })
	comps.set(c, "button.text", { "Custom Quests" })
end

--- Fill the authored-quest list. The layout ships six Quest_N plates carrying
-- the sample set's names as placeholders, plus QuestName/QuestAuthor textboxes
-- the C++ side pointed at whichever one you were on.
local function decorate_custom_quest_screen(screen)
	local comps = require("src.engine.comps")
	local list = customquests.all()
	for i = 0, 5 do
		local comp = screen.compmap["Quest_" .. i]
		if comp then
			local q = list[i + 1]
			comps.set(comp, "visible", { q ~= nil })
			if q then comps.set(comp, "button.text", { q.name }) end
		end
	end
	set_custom_quest_details(screen, list[1])
end

local function decorate_quest_screen(screen)
	local comps = require("src.engine.comps")
	local save = require("mods.vanilla.game.save")
	-- The layout ships this textbox reading "1.10 8-legged Terror" — a
	-- designer's sample, which the C++ engine overwrote on entry and which this
	-- port showed to anyone who reached the screen by any route other than
	-- clicking a chapter button. The original's quest names were compiled into
	-- prog.dll and are not in the pak, so there is nothing true to put here:
	-- blank beats a name that belongs to a different quest.
	if screen.compmap.QuestName then
		comps.set(screen.compmap.QuestName, "textbox.text", { "" })
	end
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
	local save = require("mods.vanilla.game.save")
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

--- Frames the pak ships empty (high scores, statistics) get their contents
-- painted from the save file.
function game.on_screen_draw(screen_name, screen)
	require("mods.vanilla.game.records").draw(screen_name, screen)
	require("mods.vanilla.game.gallery").draw(screen_name, screen)
	require("mods.vanilla.game.unlocks").draw(screen_name, screen)
	require("mods.vanilla.game.achievements").draw(screen_name, screen)
	require("mods.vanilla.game.modeinfo").draw(screen_name, screen)
end

--- Screens the engine pushes carry no progress state of their own.
function game.on_screen_enter(screen_name, screen)
	require("mods.vanilla.game.records").prepare(screen_name, screen)
	require("mods.vanilla.game.gallery").prepare(screen_name, screen)
	require("mods.vanilla.game.unlocks").prepare(screen_name, screen)
	require("mods.vanilla.game.achievements").prepare(screen_name, screen)
	require("mods.vanilla.game.display").prepare(screen_name, screen)
	if screen_name == "MainMenu" then
		-- reaching the menu with nothing running means attract mode
		if not game.active then game.start_demo() end
	elseif screen_name == "SelectChapter" then
		decorate_chapter_screen(screen)
	elseif screen_name == "PlayMenuQuests" then
		decorate_quest_screen(screen)
	elseif screen_name == "PlayMenu" then
		add_custom_quests_button(screen)
	elseif screen_name == "PlayMenuCustomQuests" then
		decorate_custom_quest_screen(screen)
	end
end

-- called by the screen manager after a screen's own OnClick
function game.on_ui_click(screen_name, comp_name)
	-- Back is a framework convention: several pak layouts ship the button and
	-- no handler for it, because the C++ side popped the screen. Skip screens
	-- whose own script already started leaving, or they would pop twice.
	-- the unlock celebrations have no button on them at all: any click closes
	if require("mods.vanilla.game.unlocks").on_click(screen_name) then return true end
	if require("mods.vanilla.game.display").on_click(screen_name, comp_name,
		require("src.engine.screens").find(screen_name)) then return true end

	if comp_name == "Back" then
		local screens = require("src.engine.screens")
		local s = screens.find(screen_name)
		if s and not s.leaving then screens.pop(screen_name) end
		return true
	end
	if screen_name == "SelectChapter" then
		local ch = comp_name:match("^Chapter_(%d+)$")
		if ch then
			if not require("mods.vanilla.game.save").is_chapter_unlocked(tonumber(ch)) then
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
			if not require("mods.vanilla.game.save").is_quest_unlocked(selected_chapter, tonumber(q)) then
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
			if not game.demo then require("mods.vanilla.game.unlocks").saw_perk(perk) end
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
	elseif screen_name == "PlayMenuCustomQuests" then
		-- the plates are Quest_0..Quest_5, unlike every other screen's 1-based
		-- grid, so the index is the list position directly
		local n = comp_name:match("^Quest_(%d+)$")
		local q = n and customquests.all()[tonumber(n) + 1]
		if q then
			game.start_custom(q)
			require("src.engine.timeline").begin("Game")
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
		elseif comp_name == "HighScores" then
			-- the screen ships the button but no handler; the C++ side had it
			require("src.engine.screens").push("HighScores")
			return true
		elseif comp_name == "PlayMenu" then
			game.to_main_menu()
			return true
		end
	end
	return false
end

--- Leave gameplay entirely and return to the menu timeline, which brings the
-- attract-mode demo back up behind it.
function game.to_main_menu()
	game.active = false
	game.demo = false
	input.set_controller(nil)
	require("src.engine.timeline").begin("MainMenu")
end

function game.selected_chapter() return selected_chapter end

--- The engine asks for this when a settings screen applies something.
function game.save_settings()
	require("mods.vanilla.game.save").flush()
end

return game

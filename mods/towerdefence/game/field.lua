-- The field: a base in the middle, waves walking in from every edge, and a
-- player who is one of the things defending it.
--
-- SLICE ONE of the tower-defence mod (design: plans/crimsonland.md,
-- 2026-08-18). There are deliberately no towers, no shop and no perks yet:
-- this exists to answer whether defending a *thing* — rather than surviving
-- yourself — is any fun in this engine, before anything is built on top of it.
--
-- Why this is a fork of vanilla's play.lua rather than a layer on it: the
-- simulation vanilla runs (`update_bullets`, `update_creatures`,
-- `damage_creature`) is made of file-locals, so no other mod can call into it,
-- and the one rule that has to change — what a creature walks towards — lives
-- in the middle of it. What is NOT forked is everything that reads the pak:
-- data, animations, terrain, particles and gibs are vanilla's modules,
-- required and used unchanged.
--
-- Everything here that carries a number vanilla also carries (unit scales,
-- creature stat scaling) uses vanilla's value, so a weapon that feels a
-- certain way over there feels the same way here. That is a requirement, not
-- a coincidence: the whole mod is about knowing what your weapons do.

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local bms = require("mods.vanilla.game.bms")
local data = require("mods.vanilla.game.data")
local fx = require("src.engine.fx")
local gibs = require("mods.vanilla.game.gibs")
local input = require("mods.vanilla.game.input")
local particles = require("mods.vanilla.game.particles")
local perks = require("mods.vanilla.game.perks")
local terrain = require("mods.vanilla.game.terrain")
local cards = require("mods.towerdefence.game.cards")
local hq = require("mods.towerdefence.game.hq")
local plots = require("mods.towerdefence.game.plots")
local hud = require("mods.towerdefence.game.hud")
local prices = require("mods.towerdefence.game.prices")
local shooter = require("mods.towerdefence.game.shooter")
local waves = require("mods.towerdefence.game.waves")

local field = {}

field.active = false

-- Same playfield and unit conversions as vanilla (see play.lua's comments for
-- where each number comes from) — a weapon must behave identically in both.
local WORLD_W, WORLD_H = 1820, 1024
field.WORLD_W, field.WORLD_H = WORLD_W, WORLD_H
local SCREEN_W, SCREEN_H = 960, 640
local SPEED_SCALE = 45
local BULLET_SPEED_SCALE = 16
local RANGE_SCALE = 4

-- The base sits dead centre; the HQ is the same structure until the shop
-- exists (slice two), so the player already walks to the middle to trade.
local BASE_X, BASE_Y = WORLD_W / 2, WORLD_H / 2
local BASE_RADIUS = 70 -- what creatures have to reach to start hitting it
-- Sized from the economy model (docs/crimsonland/td-economy-model.md): a wave
-- that leaks entirely early on must cost around a sixth of the base, so a bad
-- wave is a bill to pay rather than a run ending. 2000 with the bite below.
local BASE_HP = 2000

-- A creature walking to the base ignores the player until the player is in
-- its way. Standing between the wave and the base is therefore a decision
-- with a cost, which is what makes a body worth having on the field at all.
local AGGRO_RADIUS = 150

-- Contact damage cadence, shared by both things a creature can chew on.
local ATTACK_INTERVAL = 0.8
-- A building is a bigger target than a man but a far tougher one: claws that
-- open a trooper in seventeen bites do much less against masonry. At 2.0 the
-- model said four creatures at the wall ate a 1000 hp base in twenty seconds,
-- which makes any leak fatal and a leak is supposed to be affordable.
local BASE_ATTACK_MUL = 0.6

local SHOOTER_STANDOFF = 260
local SHOOTER_RANGE = 700
local MAX_CREATURES = 90

local HIT_FLASH = 0.08
local RESPAWN_TIME = 6 -- seconds you are off the field after dying

local START_MONEY = 250
local START_WEAPON = "ASSAULT_RIFLE"

-- How close to the base the player has to be to trade. Wider than the base
-- itself, so walking in works, but not so wide that the HQ can be used from
-- the firing line.
local HQ_RADIUS = 110
-- How close to a plot you have to stand to build on it or change what it
-- holds. Small: which mount you are working on must never be ambiguous.
local PLOT_REACH = 60

-- ---------------------------------------------------------------- session

local function bake_terrain()
	local density = require("src.engine").render_scale()
	-- SURVIVAL's ground: an endless mode's terrain, which is what this is
	return terrain.bake("SURVIVAL", 5, WORLD_W, WORLD_H, density)
end

--- Begin a run. There is only one, and it ends when the base does.
function field.start_run()
	data.load_all()
	input.set_controller(nil)
	if field.terrain then field.terrain:release() end
	field.terrain = bake_terrain()

	field.base = { x = BASE_X, y = BASE_Y, hp = BASE_HP, max_hp = BASE_HP }
	field.player = {
		x = BASE_X, y = BASE_Y + 120,
		angle = 0,
		hp = 100, max_hp = 100,
		speed = 180,
		anim_t = 0, moving = false,
		weapon = data.weapons[START_WEAPON],
		ammo = 0, reloading = 0, reload_total = 0, cooldown = 0, muzzle = 0,
		dead_t = nil, -- counting down to respawn
	}
	field.player.ammo = field.player.weapon and field.player.weapon.clip_size or 0

	field.creatures = {}
	field.bullets = {}
	field.ebullets = {}
	field.money = START_MONEY
	-- The arsenal. Weapons are objects you own, not a tier you have reached:
	-- what is in your hands is one of them, and from slice three the rest are
	-- what the mounts hold.
	field.owned = { [START_WEAPON] = true }
	-- Perks are the player's own handling, so the modifier table lives on the
	-- player: game/shooter.lua reads `owner.mods`, and a mount has none.
	field.mods = perks.fresh_mods()
	field.player.mods = field.mods
	field.owned_perks = {}
	field.cards_taken = 0
	field.card_offer = nil
	field.plots = plots.create(BASE_X, BASE_Y)
	field.near_hq = false
	field.near_plot = nil
	field.kills = 0
	field.shots = 0
	field.time = 0
	field.over = false

	-- wave state: the run opens in a lull, so the first thing the player does
	-- is read what is coming rather than react to it
	field.wave = 1
	field.wave_queue = 0
	field.spawn_cd = 0
	field.lull = waves.LULL
	field.banner, field.banner_t = nil, 0

	fx.clear("world")
	gibs.clear()

	field.active = true
	audio.switch_music("music/gt1_ingame", 0, 1)
	print("[td] run started")
end

local function announce(text)
	field.banner, field.banner_t = text, 3.5
end

-- ---------------------------------------------------------------- creatures

local function resolve_variant(id)
	return data.variants[id] or data.base_variant[id]
end

local function add_creature(variant, x, y)
	local w = waves.get(field.wave)
	local c = {
		variant = variant,
		def = data.creatures[variant.type],
		x = x, y = y,
		hp = variant.health * w.health_mul * field.mods.creature_hp,
		scale = variant.scale,
		anim_t = love.math.random() * 2,
		attack_cd = 0,
		ice_frame = love.math.random(1, 4),
	}
	if variant.weapon_id then
		c.fire_cd = variant.fire_interval
			+ love.math.random() * variant.fire_interval_random
	end
	if variant.spawn_variant then
		c.spawn_cd = variant.spawn_interval
		c.spawned = 0
		c.fixed_rot = love.math.random() * math.pi * 2
	end
	field.creatures[#field.creatures + 1] = c
	return c
end

--- Creatures arrive from outside, not from a ring around the player: this is
-- a siege, and where a wave comes from is information the player acts on.
local function spawn_edge(variant)
	local edge = love.math.random(1, 4)
	local x, y
	if edge == 1 then x, y = love.math.random(0, WORLD_W), 40
	elseif edge == 2 then x, y = love.math.random(0, WORLD_W), WORLD_H - 40
	elseif edge == 3 then x, y = 40, love.math.random(0, WORLD_H)
	else x, y = WORLD_W - 40, love.math.random(0, WORLD_H)
	end
	add_creature(variant, x, y)
end

-- What a kill pays. `experience_worth` is the original's own rating of what
-- killing a thing was worth, so it is the measure used here — but capped,
-- because the ratings span two orders of magnitude: an alien nest is rated
-- 3000 against a spider's 138, and one kill worth twenty others turns the wave
-- it appears in into a lottery ticket that pays for the next three.
local KILL_PAY_DIVISOR = 10
local KILL_PAY_MAX = 60

local function pay_for(c)
	local pay = math.floor(c.variant.xp / KILL_PAY_DIVISOR)
	pay = math.max(1, math.min(KILL_PAY_MAX, pay))
	-- the original's "more points" perks pay in the only currency this mod has
	field.money = field.money + math.floor(pay * field.mods.score_mul)
end

local function kill_creature(c, overkill)
	c.overkill = overkill or nil
	c.dying = true
	c.die_t = 0
	c.rot = c.fixed_rot or math.atan2(field.player.y - c.y, field.player.x - c.x)
	particles.death_burst(c.x, c.y, c.scale)
	gibs.spawn(c, overkill and 2.5 or 1)
	field.kills = field.kills + 1
	pay_for(c)
	if field.mods.kill_heal > 0 and not field.player.dead_t then
		field.player.hp = math.min(field.player.max_hp,
			field.player.hp + field.mods.kill_heal)
	end
	local snd = c.def and c.def.sounds
	if snd then
		local picks = {}
		for k, v in pairs(snd) do
			if k:match("^snd_die") and v ~= "!NONE" then picks[#picks + 1] = v end
		end
		if #picks > 0 then audio.play_sound(picks[love.math.random(#picks)]) end
	end
end

local function damage_creature(c, dmg)
	if c.dying then return false end
	local before = c.hp
	c.hp = c.hp - dmg
	c.flash_t = HIT_FLASH
	if c.hp <= 0 then
		kill_creature(c, dmg >= before * 2)
		return true
	end
	return false
end

-- --------------------------------------------------------------- shooting
--
-- The firing itself lives in game/shooter.lua, shared with the towers: the
-- player and a mount are the same object with different brains, and this is
-- the brain-free half. What stays here is only the two names vanilla's AI
-- reads off a game table.

--- Vanilla's AI controller (used by the autotest harness) reads `clip_size()`
-- and `drops` off the game table, so this mod answers to the same names. Two
-- lines to make every scripted-play test in src/test/ available here.
function field.clip_size() return shooter.clip_size(field.player) end
field.drops = {} -- nothing drops yet; the AI checks it for pickups

-- ------------------------------------------------------------------ buying
--
-- Every purchase goes through here, because money is the game's only currency
-- and the field is what owns it. The HQ screens ask; they never deduct.

--- Buy back the base's health, or as much of it as the money covers. Partial
-- is deliberate: being unable to afford a full repair should still leave you
-- something to do with what you have, and the choice of how much to spend on
-- walls versus guns is the decision the economy is built on.
function field.repair()
	local missing = field.base.max_hp - field.base.hp
	if missing <= 0 or field.money <= 0 then return false end
	local cost = prices.repair(missing)
	if cost > field.money then
		-- buy what the money reaches
		missing = field.money / prices.REPAIR_PER_HP
		cost = prices.repair(missing)
	end
	field.money = field.money - cost
	field.base.hp = math.min(field.base.max_hp, field.base.hp + missing)
	audio.play_sound("sfx/unlocked")
	announce(("Repaired %d for $%d"):format(math.floor(missing), cost))
	return true
end

--- Buy a weapon, or take one already owned into your hands. Owning is what
-- costs; holding is free and reversible, which is what makes an arsenal worth
-- having rather than a single upgrade path.
function field.buy_weapon(w)
	if not w then return false end
	if not field.owned[w.id] then
		local price = prices.weapon(w)
		if not price or price > field.money then
			audio.play_sound("sfx/locked") -- the pak's own "you cannot have this"
			return false
		end
		field.money = field.money - price
		field.owned[w.id] = true
		announce(("Bought %s for $%d"):format(w.name or w.id, price))
	end
	field.player.weapon = w
	field.player.ammo = w.clip_size
	field.player.reloading = 0
	audio.play_sound(w.snd_reload)
	return true
end

--- Buy the ground: a plot becomes a mount that can hold something.
function field.buy_plot(plot)
	if plot.built or plots.BUILD_COST > field.money then
		audio.play_sound("sfx/locked")
		return false
	end
	field.money = field.money - plots.BUILD_COST
	plot.built = true
	plot.tier = 1
	audio.play_sound("sfx/unlocked")
	announce(("Mount built  -$%d"):format(plots.BUILD_COST))
	return true
end

--- Reinforce a mount so it can hold the heavy end of the arsenal. This is the
-- second half of what a big gun costs, and the reason buying one does not
-- immediately mean eight of them.
function field.upgrade_plot(plot)
	if not plot.built or plot.tier >= 2 or plots.UPGRADE_COST > field.money then
		audio.play_sound("sfx/locked")
		return false
	end
	field.money = field.money - plots.UPGRADE_COST
	plot.tier = 2
	audio.play_sound("sfx/unlocked")
	announce(("Mount reinforced  -$%d"):format(plots.UPGRADE_COST))
	return true
end

--- Bolt a weapon on, buying it first if it is not owned. The mount holds its
-- own copy: what is on a mount is not in your hands, which is what makes the
-- perimeter a set of decisions rather than a display of everything you own.
function field.mount_weapon(plot, w)
	if not plots.accepts(plot, w) then
		audio.play_sound("sfx/locked")
		return false
	end
	if not field.owned[w.id] then
		local price = prices.weapon(w)
		if not price or price > field.money then
			audio.play_sound("sfx/locked")
			return false
		end
		field.money = field.money - price
		field.owned[w.id] = true
		announce(("Bought %s for $%d"):format(w.name or w.id, price))
	end
	plot.weapon = w
	plot.ammo = w.clip_size
	plot.reloading = 0
	plot.cooldown = 0
	audio.play_sound(w.snd_reload)
	return true
end

--- Take the weapon off a mount. Free, and reversible: rearranging what you own
-- as the waves change shape is the play, so it must never cost anything.
function field.strip_plot(plot)
	plot.weapon = nil
	plot.target = nil
	return true
end

--- Pay for a look at three cards. The money buys the *offer*, not the pick, so
-- an offer full of things you do not want is a real outcome and the price of
-- the next one still goes up.
function field.buy_cards()
	local cost = cards.cost(field.cards_taken)
	if cost > field.money then
		audio.play_sound("sfx/locked")
		return false
	end
	local offer = cards.offer(3, field.owned_perks)
	if #offer == 0 then
		announce("Nothing left to learn")
		return false
	end
	field.money = field.money - cost
	field.card_paid = (field.card_paid or 0) + cost
	field.card_offer = offer
	audio.play_sound("sfx/unlock_perk")
	return true
end

--- Take one. The modifiers land on the player's own table, which is what makes
-- perks player-only: a mount has no `mods`, so shooter.lua treats it neutrally.
function field.take_card(perk)
	if not perk or field.owned_perks[perk.id] then return false end
	field.owned_perks[perk.id] = true
	field.cards_taken = field.cards_taken + 1
	perk.apply(field.mods, field)
	field.card_offer = nil
	-- a bigger clip is only bigger once it is filled
	field.player.ammo = math.min(shooter.clip_size(field.player), field.player.ammo)
	announce(("%s"):format(perk.name))
	print(("[td] perk taken: %s"):format(perk.name))
	return true
end

-- ----------------------------------------------------------------- player

local function update_player(dt)
	local p = field.player

	if p.dead_t then
		p.dead_t = p.dead_t - dt
		if p.dead_t <= 0 then
			-- back on your feet at the base, which is also the only place worth
			-- respawning: it is the thing you are here to stand in front of
			p.dead_t = nil
			p.hp = p.max_hp
			p.x, p.y = field.base.x, field.base.y + 60
			p.ammo = shooter.clip_size(p)
			p.reloading = 0
		end
		return
	end

	if field.mods.regen > 0 then
		p.hp = math.min(p.max_hp, p.hp + field.mods.regen * dt)
	end

	local want = input.intent(field, dt)
	p.moving = (want.dx ~= 0 or want.dy ~= 0)
	if p.moving then
		local len = math.sqrt(want.dx * want.dx + want.dy * want.dy)
		local speed = p.speed * field.mods.speed
		p.x = math.max(16, math.min(WORLD_W - 16, p.x + want.dx / len * speed * dt))
		p.y = math.max(16, math.min(WORLD_H - 16, p.y + want.dy / len * speed * dt))
		p.anim_t = p.anim_t + dt
	end
	p.aim_x, p.aim_y = want.aim_x, want.aim_y
	p.angle = math.atan2(p.aim_y - p.y, p.aim_x - p.x)

	-- close enough to trade: the HUD says so, and E opens the door
	local bdx, bdy = field.base.x - p.x, field.base.y - p.y
	field.near_hq = (bdx * bdx + bdy * bdy) < HQ_RADIUS * HQ_RADIUS
	-- and close enough to work on a mount, which is the other thing E does
	field.near_plot = not field.near_hq and plots.at(field, p.x, p.y, PLOT_REACH) or nil

	shooter.update(field, p, dt, want.fire, want.reload)
end

local function hurt_player(dmg)
	local p = field.player
	if p.dead_t then return end
	-- Thick Skinned and its family: what actually lands on you
	p.hp = p.hp - dmg * field.mods.taken
	if p.hp <= 0 then
		p.hp = 0
		p.dead_t = RESPAWN_TIME
		particles.blood(p.x, p.y, love.math.random() * math.pi * 2, 1.5)
		announce("You are down - respawning")
	end
end

local function hurt_base(dmg)
	local b = field.base
	if field.over then return end
	b.hp = b.hp - dmg
	if b.hp <= 0 then
		b.hp = 0
		field.over = true
		announce(("The base has fallen - wave %d"):format(field.wave))
		print(("[td] run over at wave %d, %d kills"):format(field.wave, field.kills))
	end
end

-- ---------------------------------------------------------------- bullets

local function update_bullets(dt)
	for i = #field.bullets, 1, -1 do
		local b = field.bullets[i]
		local step = b.speed * dt
		b.x = b.x + b.dx * step
		b.y = b.y + b.dy * step
		b.dist_left = b.dist_left - step
		local dead = b.dist_left <= 0
			or b.x < 0 or b.x > WORLD_W or b.y < 0 or b.y > WORLD_H

		if not dead then
			for _, c in ipairs(field.creatures) do
				if not c.dying then
					local r = 16 * c.scale + 6
					local ddx, ddy = c.x - b.x, c.y - b.y
					if ddx * ddx + ddy * ddy < r * r then
						local dir = math.atan2(b.dy, b.dx)
						local power = particles.power(b.damage)
						particles.impact(b.art or "bullet", b.weapon_id,
							b.x, b.y, dir, power)
						if damage_creature(c, b.damage) then
							particles.impact(b.art or "bullet", b.weapon_id,
								b.x, b.y, dir, power * 1.5)
							if b.owner then
								b.owner.kills = (b.owner.kills or 0) + 1
							end
						end
						dead = true
						break
					end
				end
			end
		end
		if dead then table.remove(field.bullets, i) end
	end
end

--- Creature projectiles. They aim at whatever their shooter was aiming at, so
-- a spitter that has chosen the base can hurt it from range.
local function update_ebullets(dt)
	local p = field.player
	for i = #field.ebullets, 1, -1 do
		local b = field.ebullets[i]
		local step = b.speed * dt
		b.x = b.x + b.dx * step
		b.y = b.y + b.dy * step
		b.dist_left = b.dist_left - step
		local dead = b.dist_left <= 0

		if not dead and not p.dead_t then
			local ddx, ddy = p.x - b.x, p.y - b.y
			if ddx * ddx + ddy * ddy < 18 * 18 then
				hurt_player(b.damage)
				dead = true
			end
		end
		if not dead then
			local ddx, ddy = field.base.x - b.x, field.base.y - b.y
			if ddx * ddx + ddy * ddy < BASE_RADIUS * BASE_RADIUS then
				hurt_base(b.damage * BASE_ATTACK_MUL)
				dead = true
			end
		end
		if dead then table.remove(field.ebullets, i) end
	end
end

-- -------------------------------------------------------------- creatures

--- What this creature is walking at right now: the base, unless the player has
-- put themselves close enough to be the nearer problem.
local function target_of(c)
	local p = field.player
	if not p.dead_t then
		local dx, dy = p.x - c.x, p.y - c.y
		if dx * dx + dy * dy < AGGRO_RADIUS * AGGRO_RADIUS then
			return p.x, p.y, "player"
		end
	end
	return field.base.x, field.base.y, "base"
end

local function update_creatures(dt)
	local w = waves.get(field.wave)
	for i = #field.creatures, 1, -1 do
		local c = field.creatures[i]
		if c.flash_t then
			c.flash_t = c.flash_t - dt
			if c.flash_t <= 0 then c.flash_t = nil end
		end

		if c.overkill then
			table.remove(field.creatures, i)
		elseif c.dying then
			c.die_t = c.die_t + dt
			local def = c.def
			local seq = def and def.die and bms.load(def.die)
			local frames = seq and seq.count or 24
			if c.die_t * 24 * (def and def.die_speed or 1) >= frames then
				-- the corpse goes into the ground, the same trick vanilla uses
				-- to let a battlefield accumulate without holding entities
				if seq then
					love.graphics.setCanvas(field.terrain)
					local v = c.variant
					love.graphics.setColor(v.r, v.g, v.b, 1)
					bms.draw(seq, seq.count, c.x, c.y, c.rot or 0, c.scale)
					love.graphics.setColor(1, 1, 1, 1)
					love.graphics.setCanvas()
				end
				table.remove(field.creatures, i)
			end
		else
			c.anim_t = c.anim_t + dt
			c.attack_cd = math.max(0, c.attack_cd - dt)

			local v = c.variant
			local tx, ty, what = target_of(c)
			local dx, dy = tx - c.x, ty - c.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local speed = v.speed * SPEED_SCALE * field.mods.creature_speed

			-- the reach of the thing being walked at: a man is a point, the
			-- base is seventy pixels of wall
			local reach = (what == "base") and BASE_RADIUS or (16 * c.scale + 14)

			if c.spawn_cd or v.ai == "IDLE" then
				-- nests stand where they landed
			elseif v.ai == "WANDERER" then
				c.wander_t = (c.wander_t or 0) - dt
				if c.wander_t <= 0 then
					c.wander_t = 1 + love.math.random() * 2
					c.wander_a = love.math.random() * math.pi * 2
				end
				c.x = math.max(32, math.min(WORLD_W - 32, c.x + math.cos(c.wander_a) * speed * dt))
				c.y = math.max(32, math.min(WORLD_H - 32, c.y + math.sin(c.wander_a) * speed * dt))
			elseif dist > reach and not (c.fire_cd and dist < SHOOTER_STANDOFF) then
				c.x = c.x + dx / dist * speed * dt
				c.y = c.y + dy / dist * speed * dt
			end

			if c.fire_cd and dist < SHOOTER_RANGE then
				c.fire_cd = c.fire_cd - dt
				if c.fire_cd <= 0 then
					c.fire_cd = v.fire_interval
						+ love.math.random() * v.fire_interval_random
					local wep = data.weapons[v.weapon_id]
					local a = math.atan2(dy, dx)
					field.ebullets[#field.ebullets + 1] = {
						x = c.x + math.cos(a) * 14 * c.scale,
						y = c.y + math.sin(a) * 14 * c.scale,
						dx = math.cos(a), dy = math.sin(a),
						speed = (wep and wep.projectile_speed or 10) * BULLET_SPEED_SCALE,
						dist_left = (wep and wep.projectile_range or 300) * RANGE_SCALE,
						damage = v.damage * w.damage_mul,
					}
				end
			end

			if c.spawn_cd then
				c.spawn_cd = c.spawn_cd - dt
				if c.spawn_cd <= 0 and c.spawned < v.spawn_max
					and #field.creatures < MAX_CREATURES then
					c.spawn_cd = v.spawn_interval
					c.spawned = c.spawned + 1
					local mv = data.variants[v.spawn_variant]
					if mv then
						local a = love.math.random() * math.pi * 2
						add_creature(mv, c.x + math.cos(a) * 30, c.y + math.sin(a) * 30)
					end
				end
			end

			-- contact damage, against whichever of the two it reached
			if dist < reach and c.attack_cd <= 0 and v.damage > 0 then
				c.attack_cd = ATTACK_INTERVAL
				if what == "base" then
					hurt_base(v.damage * w.damage_mul * BASE_ATTACK_MUL)
				else
					hurt_player(v.damage * w.damage_mul)
				end
			end
		end
	end
end

-- ------------------------------------------------------------------ waves

local function living_count()
	local n = 0
	for _, c in ipairs(field.creatures) do
		if not c.dying then n = n + 1 end
	end
	return n
end

local function update_waves(dt)
	local w = waves.get(field.wave)

	if field.lull > 0 then
		field.lull = field.lull - dt
		if field.lull <= 0 then
			field.lull = 0
			field.wave_queue = w.count
			announce(waves.preview(field.wave))
		end
		return
	end

	if field.wave_queue > 0 then
		field.spawn_cd = field.spawn_cd - dt
		if field.spawn_cd <= 0 and #field.creatures < MAX_CREATURES then
			field.spawn_cd = w.interval
			field.wave_queue = field.wave_queue - 1
			local id = w.types[love.math.random(#w.types)]
			local variant = resolve_variant(id)
			if variant then spawn_edge(variant) end
		end
		return
	end

	-- wave cleared: pay for it and open the shopping window
	if living_count() == 0 then
		local bonus = waves.clear_bonus(field.wave)
		field.money = field.money + bonus
		announce(("Wave %d cleared  +%d"):format(field.wave, bonus))
		audio.play_sound("sfx/unlocked")
		field.wave = field.wave + 1
		field.lull = waves.LULL
	end
end

-- ----------------------------------------------------------------- update

function field.update(dt)
	if not field.active then return end
	-- any UI screen over the field pauses it, the same rule vanilla uses
	local screens = require("src.engine.screens")
	local top = screens.top()
	if top and top.name ~= "GameCrimsonland" then return end

	field.time = field.time + dt
	if field.banner_t > 0 then field.banner_t = field.banner_t - dt end

	if not field.over then
		update_player(dt)
		plots.update(field, dt) -- the mounts fight whether you are there or not
		update_waves(dt)
		update_creatures(dt)
	end
	update_bullets(dt)
	update_ebullets(dt)
	-- fx.update is the engine's (src/engine/init.lua); calling it here too
	-- would run every particle at double speed
	gibs.update(dt, field.terrain)
end

-- ------------------------------------------------------------------- draw

--- The view follows the player and stops at the world's edges.
function field.camera()
	local p = field.player
	local cx = math.max(0, math.min(WORLD_W - SCREEN_W, p.x - SCREEN_W / 2))
	local cy = math.max(0, math.min(WORLD_H - SCREEN_H, p.y - SCREEN_H / 2))
	return cx, cy
end

-- Placeholder base art: the pak has no buildings in it, and mod-owned assets
-- are not built yet (plans/crimsonland.md). Rings rather than a sprite, in the
-- HUD's own bone/brass palette so it does not read as a bug.
local function draw_base()
	local b = field.base
	local k = b.hp / b.max_hp
	love.graphics.setColor(0.10, 0.10, 0.11, 0.85)
	love.graphics.circle("fill", b.x, b.y, BASE_RADIUS)
	love.graphics.setColor(0.85, 0.68, 0.28, 0.9)
	love.graphics.circle("line", b.x, b.y, BASE_RADIUS)
	love.graphics.setColor(0.85, 0.68, 0.28, 0.25 + 0.35 * k)
	love.graphics.circle("fill", b.x, b.y, BASE_RADIUS * 0.45 * (0.6 + 0.4 * k))
	-- the perimeter the wave has to cross to touch it
	love.graphics.setColor(0.85, 0.68, 0.28, 0.10)
	love.graphics.circle("line", b.x, b.y, AGGRO_RADIUS)
	love.graphics.setColor(1, 1, 1, 1)
end

local function draw_creature(c)
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
		if seq then frame = math.floor(c.anim_t * 24 * (def.move_speed or 1)) + 1 end
		-- facing is where it is going, which here is usually the base
		local tx, ty = target_of(c)
		rot = c.fixed_rot or math.atan2(ty - c.y, tx - c.x)
	end
	love.graphics.setColor(v.r, v.g, v.b, 1)
	if not seq then
		love.graphics.circle("fill", c.x, c.y, 14 * c.scale)
		return
	end
	bms.draw(seq, frame, c.x, c.y, rot, c.scale)
	if c.flash_t then
		local k = math.max(0, c.flash_t / HIT_FLASH) * 0.85
		love.graphics.setBlendMode("add")
		love.graphics.setColor(k, k, k, 1)
		bms.draw(seq, frame, c.x, c.y, rot, c.scale)
		love.graphics.setBlendMode("alpha")
	end
end

local function draw_shadow(def, x, y, scale)
	local img = def and def.shadow and assets.image(def.shadow)
	if not img then return end
	love.graphics.setColor(1, 1, 1, 0.5)
	love.graphics.draw(img, x, y, 0, scale, scale,
		img:getWidth() / 2, img:getHeight() / 2)
	love.graphics.setColor(1, 1, 1, 1)
end

local function draw_bullets()
	local bullet_img = assets.image("game/bullet16.tga")
	for _, b in ipairs(field.bullets) do
		local rot = math.atan2(b.dy, b.dx)
		if b.art == "plasma" or b.art == "ion" then
			local c = data.FAMILY_COLOR[b.art]
			local img = assets.image("game/projs.tga")
			if img then
				-- the glow sprite, same rect vanilla uses for an energy bolt
				local quad, qs = assets.quad(img, 69, 5, 22, 22)
				local s = (b.bolt or 0.55) * qs
				love.graphics.setBlendMode("add")
				love.graphics.setColor(c[1], c[2], c[3], 0.9)
				love.graphics.draw(img, quad, b.x, b.y, rot, s, s, 11, 11)
				love.graphics.setBlendMode("alpha")
				love.graphics.setColor(1, 1, 1, 1)
			end
		elseif bullet_img then
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.draw(bullet_img, b.x, b.y, rot + math.pi / 2, 0.6, 0.6,
				bullet_img:getWidth() / 2, bullet_img:getHeight() / 2)
		end
	end
	for _, b in ipairs(field.ebullets) do
		love.graphics.setBlendMode("add")
		love.graphics.setColor(0.3, 1, 0.4, 0.9)
		love.graphics.circle("fill", b.x, b.y, 5)
		love.graphics.setBlendMode("alpha")
		love.graphics.setColor(1, 1, 1, 1)
	end
end

function field.draw()
	if not field.active then return end
	local camx, camy = field.camera()
	love.graphics.push()
	love.graphics.translate(-camx, -camy)

	if field.terrain then
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(field.terrain, 0, 0)
	end
	draw_base()
	plots.draw(field) -- under everything alive: they are furniture, not actors

	for _, c in ipairs(field.creatures) do
		if not c.dying then draw_shadow(c.def, c.x, c.y, c.scale) end
	end
	local p = field.player
	if not p.dead_t then draw_shadow(data.creatures.TROOPER, p.x, p.y, 1) end

	gibs.draw()
	for _, c in ipairs(field.creatures) do draw_creature(c) end

	-- player: legs animate, torso points where the mouse does (vanilla's
	-- trooper art faces -Y, hence the quarter turn)
	if not p.dead_t then
		local tdef = data.creatures.TROOPER
		local legs = tdef and tdef.move_legs and bms.load(tdef.move_legs)
		local torso = tdef and tdef.move and bms.load(tdef.move)
		love.graphics.setColor(1, 1, 1, 1)
		if legs then
			local frame = p.moving
				and (math.floor(p.anim_t * 24 * (tdef.move_speed or 1)) + 1) or 1
			bms.draw(legs, frame, p.x, p.y, p.angle + math.pi / 2, 1)
		end
		if torso then
			bms.draw(torso, 1, p.x, p.y, p.angle + math.pi / 2, 1)
		else
			love.graphics.circle("fill", p.x, p.y, 12)
		end
		if p.muzzle > 0 then
			local mf = assets.image("game/muzzle-flash.png")
			if mf then
				love.graphics.setBlendMode("add")
				love.graphics.setColor(1, 1, 1, p.muzzle / 0.05)
				love.graphics.draw(mf, p.x + math.cos(p.angle) * 28,
					p.y + math.sin(p.angle) * 28, p.angle, 0.4, 0.4,
					mf:getWidth() / 2, mf:getHeight() / 2)
				love.graphics.setBlendMode("alpha")
			end
		end
	end

	draw_bullets()
	fx.draw("world")
	love.graphics.pop()

	hud.draw(field, camx, camy)
end

-- ------------------------------------------------------------ mod hooks

function field.pause()
	if not field.active or field.over then return end
	require("src.engine.screens").push("GamePause")
end

function field.unpause()
	require("src.engine.screens").pop("GamePause")
end

--- The engine asks for this when an options screen applies something.
function field.save_settings()
	require("mods.vanilla.game.save").flush()
end

function field.to_main_menu()
	field.active = false
	input.set_controller(nil)
	require("src.engine.timeline").begin("MainMenu")
end

--- Keys the field itself answers to. Escape is the engine's (it pauses);
-- everything else arrives here (src/engine/init.lua).
function field.keypressed(key)
	if not field.active or field.over then return end
	if field.player.dead_t then return end
	if key == "E" then
		-- one key, two doors: the base trades, a plot builds. They can never
		-- both be in reach (near_plot is only set away from the base).
		if field.near_hq then
			hq.open(field)
		elseif field.near_plot then
			hq.open_mount(field, field.near_plot)
		end
	end
end

--- There is still no menu of this mod's own: Play on the pak's main menu
-- starts a run, and a click on the field once the base is gone goes back to
-- it. The HQ screens, though, are real now — anything they own is theirs.
function field.on_ui_click(screen_name, comp_name)
	if hq.on_ui_click(screen_name, comp_name, field) then return true end
	if screen_name == "MainMenu" and comp_name == "PlayMenu" then
		field.start_run()
		require("src.engine.timeline").begin("Game")
		return true
	end
	if screen_name == "GameCrimsonland" and field.over then
		field.to_main_menu()
		return true
	end
	return false
end

function field.on_screen_enter(screen_name, screen)
	hq.on_screen_enter(screen_name, screen)
end

function field.on_screen_draw(screen_name, screen)
	hq.on_screen_draw(screen_name, screen)
end

return field

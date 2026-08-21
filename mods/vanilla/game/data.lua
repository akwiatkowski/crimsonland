-- Game data: loads the original XML datasets into Lua tables.

local xml = require("src.xml")
local paths = require("src.engine.paths")
-- What a round does, as opposed to how big its numbers are. Mod-side, because
-- the pak is read-only: see mods/vanilla/game/traits.lua.
local traits = require("mods.vanilla.game.traits")

local data = {}

-- Which datasets have been parsed. The pak is read-only, so a second parse can
-- only rebuild the tables it built the first time -- and callers treat loading
-- as free: the tower defence armoury asks for a weapon entry once per plate on
-- every frame, which was 30 full parses of ~100KB of XML per frame (11ms a
-- call, measured) and dropped the shop to a slideshow. Each loader sets its
-- flag once it has finished, so a read that throws part-way is retried rather
-- than remembered as done.
local loaded = {}

local function read_xml(path)
	local text = love.filesystem.read(paths.ASSETS .. "/" .. path)
	if not text then return nil end
	return xml.parse(text)
end

local function to_num(v, default)
	local n = tonumber(v)
	if n == nil then return default end
	return n
end

-- ------------------------------------------------------------ weapons

data.weapons = {} -- id -> table
data.weapon_order = {} -- by numeric index

-- What colour a weapon family burns, taken off the original's own art rather
-- than chosen: the pak paints one ammo cell per family and every gun icon in
-- the family in the same hue, so the answer was already in vendor/assets.
-- Measured as the mean of the most saturated tenth of each icon's pixels:
--
--   weapons/ammo/plasma.png  rgb(251,192,  1)  hue  46 deg   amber
--   plasma-{rifle,cannon,minigun,shotgun,multi}.png          hue  40-44 deg
--   weapons/ammo/xenon.png   rgb( 12,135,214)  hue 203 deg   blue
--   ion-{rifle,cannon,minigun,shotgun}, multi-ion.png        hue 215-217 deg
--
-- Plasma is the warm family and ion the cold one -- this port had them the
-- other way round, and ion in a green the original uses nowhere. The pulse gun
-- feeds off the plasma cell too (weapons.xml ammo_icon), which is why it is
-- warm as well; its own arc-shaped sprite is what tells the two apart.
--
-- One table because a family has to read the same everywhere: the bolt in the
-- air, the light it throws on the ground, the sparks off the hit, the mark it
-- burns, the blast, and the plate it lies on as a drop. Two copies of these
-- numbers is what let the bolt and the drop plate disagree before.
data.FAMILY_COLOR = {
	bullet = { 0.85, 0.8, 0.6 },
	rocket = { 1.0, 0.6, 0.35 },
	flame = { 1.0, 0.55, 0.2 },
	plasma = { 1.0, 0.76, 0.15 },
	ion = { 0.2, 0.6, 1.0 },
	pulse = { 1.0, 0.9, 0.5 },
	blade = { 0.8, 0.85, 0.9 },
}

-- How big an energy bolt is drawn, from the two numbers weapons.xml gives per
-- round: how much damage it carries and how fast it travels. Slow and heavy
-- draws big -- the two cannons fire the game's slowest, hardest-hitting round
-- (speed 10, damage 28 and 16.7) and are meant to look like it, while a plasma
-- shotgun's fourteen pellets are specks. It also puts the ion family above the
-- plasma one at equal damage, which is the original's read of it: every ion
-- gun fires at half its plasma counterpart's speed (rifle 15 vs 30, minigun
-- 20 vs 35).
--
-- sqrt because the sprite is a disc: what a round carries reads as the area
-- lit, not the radius. Calibrated on the family's two reference guns -- the
-- plasma minigun's round stays the size it has been (0.48) and the plasma
-- cannon's comes out three times its area (1.50).
local BOLT_BASE = 0.31 -- floor, so a pellet is still visible
local BOLT_GROWTH = 0.13
local BOLT_REF_SPEED = 30 -- the plasma rifle's projectile_speed
local function bolt_scale(damage, speed)
	return BOLT_BASE + BOLT_GROWTH
		* math.sqrt(damage * BOLT_REF_SPEED / math.max(1, speed))
end

-- The streak a kinetic round leaves behind it.
--
-- weapons.xml says nothing about a railgun. The Gauss Gun is type 0, flags 1 --
-- the same kinetic round as the Assault Rifle and the Shotgun -- and the single
-- thing that separates it in the whole file is projectile_speed="215", against
-- 10 to 60 for the other thirty-seven. That outlier *is* the railgun, and a
-- port that draws every kinetic round as the same little sprite throws the only
-- evidence away: the slug reads as a bullet in a hurry rather than a ray.
--
-- So the trail is motion blur, which is what a tracer is: the round's own speed
-- times a shutter time. A pistol round smears twenty pixels and still reads as
-- a bullet; the Gauss Gun smears eighty and reads as a line drawn across the
-- field. No weapon is named anywhere in here -- the effect belongs to the
-- number, so a perk that speeds rounds up lengthens their tracers too.
local TRACER_EXPOSURE = 1 / 45 -- seconds of shutter
-- World pixels per second at which a round is as ionised as it gets. The Gauss
-- Gun does 3440 and is the only thing near it; the rest of the arsenal sits
-- between 160 and 960, down in the warm end.
local TRACER_HYPER = 2400
local TRACER_SLOW = { 1.00, 0.90, 0.60 } -- a burning tracer
local TRACER_FAST = { 0.72, 0.88, 1.00 } -- air that has been ionised, not lit
-- Brightness at the reference streak, and the length it refers to. A frame
-- catches the same light however far the round smeared it, so a longer streak
-- is a fainter one -- strictly that is 1/length, which leaves the Gauss Gun at
-- a tenth of an alpha and effectively invisible on a dark field. The square
-- root splits the difference: still visibly dimmer for being longer, still
-- there.
local TRACER_ALPHA = 0.34
local TRACER_REF = 22

--- How long a kinetic round's tracer is, and what colour, for a round doing
-- `speed` world pixels a second. Returns length, r, g, b, alpha.
function data.tracer(speed)
	-- Never shorter than the gap the round leaves between two frames, or a fast
	-- round draws a dashed line instead of a ray. This is the same reason a real
	-- shutter blurs: the streak has to cover the distance the frame missed.
	local exposure = math.max(TRACER_EXPOSURE, love.timer.getDelta())
	local len = math.max(1, speed * exposure)
	local k = math.min(1, speed / TRACER_HYPER)
	return len,
		TRACER_SLOW[1] + (TRACER_FAST[1] - TRACER_SLOW[1]) * k,
		TRACER_SLOW[2] + (TRACER_FAST[2] - TRACER_SLOW[2]) * k,
		TRACER_SLOW[3] + (TRACER_FAST[3] - TRACER_SLOW[3]) * k,
		-- capped, so the reference streak is the brightest one there is: a short
		-- smear being *brighter* than the old constant would be the trade
		-- running the wrong way, and nothing here is meant to add light
		math.min(TRACER_ALPHA, TRACER_ALPHA * math.sqrt(TRACER_REF / len))
end

-- Which sprite off game/projs.tga a weapon's rounds are drawn with.
--
-- weapons.xml carries the answer in two attributes nothing else in this port
-- reads yet. `type` separates the projectile families cleanly across all 38
-- entries -- 0 kinetic, 1 flame, 2 rocket, 3 pulse, 4 ion -- and bit 16 of
-- `flags` is set on exactly the plasma weapons (plus the shrinkifier and the
-- spider's spit, which fire the same energy blob). The blade gun is the one
-- weapon nothing in the XML distinguishes, so it goes by id: the sheet has a
-- spinning blade on it and only one weapon throws blades.
local PLASMA_FLAG = 16
-- Bit 0 of the same field is "ejects brass". Dumping id/type/flags across all
-- 38 weapons puts it on exactly the cased-ammunition guns -- pistol, rifles,
-- shotguns, the gauss family, the jackhammer -- and off every flamethrower,
-- rocket, energy weapon, the blade gun and the bubblegun, which is the split
-- a casing makes physical sense for.
local BRASS_FLAG = 1

-- Widest half-angle a shot leaves the barrel at, in degrees, for a weapon with
-- an accuracy rating of zero: what a single round wanders by, and the much
-- wider fan a pellet gun lays its shot across. Everything in between falls out
-- of the weapon's own stat_accuracy (see spread_of), which puts the Gauss Gun
-- at 0.1 degrees, the Pistol at 1.6, the Assault Rifle at 4.9, the Mean
-- Minigun at 8.1, the Shotgun's 12 pellets across a 36-degree cone and the
-- Sawed-off's across 50 -- the original's own ordering of its guns.
local AIM_WANDER_DEG = 10
local PELLET_CONE_DEG = 28

--- Half-angle of a weapon's spread cone, in radians.
--
-- The XML ships two numbers that look like they could drive this and only one
-- that does. `recoil` is the kick -- it tracks how much gun there is (Ion
-- Cannon 0.68, Plasma Cannon 0.6, Gauss Gun 0.42, Pulse Gun 0), so firing
-- along it made the railgun and the pistol the least accurate weapons in the
-- game and the sawed-off shotgun tighter than the full one. `stat_accuracy` is
-- the precision rating -- the bar the weapon gallery draws -- and it orders the
-- guns the way playing them does: Gauss Gun 0.9, Blade Gun 0.89, Pistol 0.6,
-- Assault Rifle 0.3, Mean Minigun 0.1, Sawed-off 0.05.
--
-- Squaring what is missing from that rating keeps the top of the range sharp
-- (a 0.9 gun is effectively hitscan-accurate) while the bottom sprays, and
-- spreads the shotguns apart: 0.2 and 0.05 are close as ratings and far apart
-- as cones, which is what tells the two of them apart in the hand.
local function spread_of(w)
	local miss = (1 - math.max(0, math.min(1, w.stat_accuracy))) ^ 2
	local widest = w.num_projectiles > 1 and PELLET_CONE_DEG or AIM_WANDER_DEG
	return math.rad(widest * miss)
end

local function projectile_art(id, wtype, flags)
	if id == "BLADE_GUN" then return "blade" end
	if wtype == 1 then return "flame" end
	if wtype == 2 then return "rocket" end
	if wtype == 3 then return "pulse" end
	if wtype == 4 then return "ion" end
	if math.floor(flags / PLASMA_FLAG) % 2 == 1 then return "plasma" end
	return "bullet"
end

function data.load_weapons()
	if loaded.weapons then return end
	local root = read_xml("weapons/weapons.xml")
	local arr = xml.array(root, "WEAPONS")
	for _, node in ipairs(arr.children) do
		local a = node.attrs
		local w = {
			id = a.id,
			index = to_num(a.index, 0),
			name = a.name,
			clip_size = to_num(a.clip_size, 10),
			snd_fire = a.snd_fire,
			snd_reload = a.snd_reload,
			shoot_interval = to_num(a.shoot_interval, 0.5),
			reload_time = to_num(a.reload_time, 1),
			num_projectiles = to_num(a.num_projectiles, 1),
			projectile_speed = to_num(a.projectile_speed, 50),
			projectile_damage = to_num(a.projectile_damage, 1),
			projectile_range = to_num(a.projectile_range, 300),
			stat_damage = to_num(a.stat_damage, 0.3),
			stat_accuracy = to_num(a.stat_accuracy, 0.3),
			icon = a.bm_icon and ("weapons/" .. a.bm_icon) or nil,
			ammo_icon = a.ammo_icon,
		}
		-- Effective per-projectile damage. Most weapons ship
		-- projectile_damage="1" (real DPS was computed in the C++ engine);
		-- only a few carry hand-authored values (pistol 4.1, plasma rifle
		-- 10, ...). Derive the rest from the stat_damage rating, calibrated
		-- so the pistol's derived DPS matches its authored value:
		-- pistol dps = 4.1 / 0.7117 = 5.76 at stat 0.3 -> dps = 19.2 * stat.
		--
		-- That derivation was per *shot interval*, which reads the weapon as
		-- if it fired for ever: a gun that shoots twice as fast got half the
		-- damage a shot and came out even. A magazine is what a player
		-- actually spends, and it is not the same trade -- the flamethrower's
		-- 30 rounds leave in a quarter of a second and then it reloads for
		-- two, so 19.2 * stat * 0.0081 put 3.7 damage in a full magazine
		-- where the pistol's held 49 and the minigun's 111. Landing every
		-- round of it on one 68 hp alien would not kill it, which is what the
		-- matrix sweep found: across 12 fights each, the three flame weapons
		-- managed 5 kills between them off 2234 hits, where no other weapon
		-- needed more than 33 hits for a kill.
		--
		-- So the rate that matters is the sustained one, reload included:
		-- a magazine costs `clip * shoot_interval + reload_time` seconds
		-- whatever order those go in. Calibrated on the same weapon as before
		-- -- the pistol's authored 4.1 over a 12-round, 9.54-second cycle is
		-- 5.16 dps at stat 0.3, so 17.2 dps per unit of stat_damage.
		--
		-- Still a heuristic: stat_damage is the rating the gallery draws, not
		-- a damage coefficient, and against the nine weapons that do carry an
		-- authored value it lands within 16.9x either way (the interval form
		-- was 35.2x, and low by a geometric mean of 0.54 where this is 0.77).
		-- Better calibrated, not correct -- and it leaves all nine of those
		-- weapons exactly as authored.
		local MAGAZINE_DPS_PER_STAT = 17.2
		if w.projectile_damage > 1.5 then
			w.damage_effective = w.projectile_damage
		else
			local cycle = w.clip_size * w.shoot_interval + w.reload_time
			w.damage_effective = MAGAZINE_DPS_PER_STAT * w.stat_damage * cycle
				/ math.max(1, w.clip_size) / math.max(1, w.num_projectiles)
		end
		w.spread = spread_of(w)
		local flags = to_num(a.flags, 0)
		w.proj_art = projectile_art(w.id, to_num(a.type, 0), flags)
		-- only the two families drawn as a glowing blob have a size to set;
		-- rockets, blades and the pulse arc are their own sprites at their own
		-- size, and a kinetic round is a bullet
		if w.proj_art == "plasma" or w.proj_art == "ion" then
			w.proj_scale = bolt_scale(w.damage_effective, w.projectile_speed)
		end
		w.brass = math.floor(flags / BRASS_FLAG) % 2 == 1
		w.traits = traits[w.id]
		data.weapons[w.id] = w
		data.weapon_order[w.index] = w
	end

	-- The highest index a player may be handed, which is not the same as the
	-- highest index in the file. weapons.xml runs 1..32 and then jumps to 44,
	-- 45, 46, 47, 48, 63: creature guns (SPIDER_PLASMA, MONSTER_PLASMA), the
	-- fire-bullets powerup, and cut content nobody ever held (BUBBLEGUN,
	-- MEGALASER, UNKNOWN). The player weapons are the leading run that carries
	-- an icon -- 1..31, ending at the Shrinkifier -- so read that off the data
	-- rather than writing 31 down, and the answer follows the file if it ever
	-- changes. `#weapon_order` cannot be used for this: the array is sparse, so
	-- the length operator is free to answer anything, and it answers 48.
	data.last_player_weapon = 0
	while true do
		local w = data.weapon_order[data.last_player_weapon + 1]
		if not (w and w.icon) then break end
		data.last_player_weapon = data.last_player_weapon + 1
	end

	loaded.weapons = true
end

-- ------------------------------------------------------------ creatures

-- visual/audio defs from creatures.xml
data.creatures = {} -- type -> table

function data.load_creatures()
	if loaded.creatures then return end
	local root = read_xml("creatures/creatures.xml")
	for _, arr in ipairs(root.children) do
		if arr.tag == "array" then
			local c = { id = arr.id, sounds = {} }
			for _, node in ipairs(arr.children) do
				local k, v = node.attrs.id, node.attrs.value
				if k == "bm_move" then c.move = v
				elseif k == "bm_move_legs" then c.move_legs = v
				elseif k == "bm_die" then c.die = v
				elseif k == "bm_shadow" then c.shadow = v
				-- A stencil is a second .bms over the same frames with only a
				-- small region opaque, in grey. Nothing draws them yet: the
				-- obvious reading (mask for the variant colour) was tried and
				-- looks worse than tinting the whole sprite -- see the note on
				-- play.lua's draw_creature. The gib sheets are four separate
				-- body parts each, not an animation.
				elseif k == "bm_move_stencil" then c.move_stencil = v
				elseif k == "bm_die_stencil" then c.die_stencil = v
				elseif k == "bm_gibs_unique" then c.gibs_unique = v
				elseif k == "bm_gibs_common" then c.gibs_common = v
				elseif k == "move_animation_playback_speed" then c.move_speed = to_num(v, 1)
				elseif k == "die_animation_playback_speed" then c.die_speed = to_num(v, 1)
				elseif k and k:match("^snd_") then c.sounds[k] = v
				end
			end
			data.creatures[c.id] = c
		end
	end
	loaded.creatures = true
end

-- gameplay variants from creature-variants.xml
data.variants = {} -- variant id -> table
data.base_variant = {} -- creature type -> lowest-index variant

function data.load_variants()
	if loaded.variants then return end
	local root = read_xml("creatures/creature-variants.xml")
	local arr = xml.array(root, "VARIANTS")
	for _, node in ipairs(arr.children) do
		local a = node.attrs
		local v = {
			id = a.id,
			legacy_index = to_num(a.legacy_variant_index, 9999),
			type = a.type,
			ai = a.ai or "CLASSIC", -- CLASSIC/SIMPLECLASSIC/SIMPLE/RUSH/WANDERER/IDLE
			xp = to_num(a.experience_worth, 10),
			damage = to_num(a.damage, 5),
			health = to_num(a.health, 10),
			speed = to_num(a.speed, 1),
			scale = to_num(a.scale, 1),
			r = to_num(a.color_base_r, 1),
			g = to_num(a.color_base_g, 1),
			b = to_num(a.color_base_b, 1),
			-- Every variant carries a base alpha and five of them mean it:
			-- Variant_23 and Variant_24 are 5 hp aliens at 0.05 and 0.04, which
			-- is a wisp you are meant to have trouble seeing, and Variant_78 is
			-- a 1800 hp crabfly at 0.25. The other 97 are 1, so reading this
			-- changes nothing for them and everything for those.
			-- (`alpha`, not `a`: `a` is the attribute table two lines up.)
			alpha = to_num(a.color_base_a, 1),
			-- ranged attackers (e.g. SpiderPlasmaShooter) carry a weapon ref
			weapon_id = a.weapon_id,
			fire_interval = to_num(a.weapon_fire_interval, 1),
			fire_interval_random = to_num(a.weapon_fire_interval_random, 0),
			-- den/nest variants spawn other variants over time
			spawn_max = to_num(a.spawner_max_creatures_to_spawn, 0),
			spawn_interval = to_num(a.spawner_spawn_interval, 0),
			spawn_variant = a.spawner_creature_variant_to_spawn,
		}
		data.variants[v.id] = v
		local cur = data.base_variant[v.type]
		if not cur or v.legacy_index < cur.legacy_index then
			data.base_variant[v.type] = v
		end
	end
	loaded.variants = true
end

-- ------------------------------------------------------------ terrains

data.terrains = {} -- chapter id -> ops list

function data.load_terrains()
	if loaded.terrains then return end
	local root = read_xml("terrains/terrains.xml")
	for _, arr in ipairs(root.children) do
		if arr.tag == "array" then
			local ops = {}
			for _, node in ipairs(arr.children) do
				ops[#ops + 1] = node.attrs
			end
			data.terrains[arr.id] = ops
		end
	end
	loaded.terrains = true
end

-- ------------------------------------------------------------ demos

-- The authored scenes an attract mode plays: demos.xml gives each one a
-- terrain, a duration, a spawn set and a position and weapon for every trooper
-- in it. MENU_COMBAT_1..5 are the menu backdrop; the TRIAL_* nodes belong to a
-- trial build's upsell screens and have no home here.
data.demos = {} -- id -> attrs
data.menu_demos = {} -- MENU_COMBAT_* in file order

function data.load_demos()
	if loaded.demos then return end
	local root = read_xml("demos.xml")
	local arr = root and xml.array(root, "DEMOS")
	for _, node in ipairs(arr and arr.children or {}) do
		local a = node.attrs
		if a.id then
			data.demos[a.id] = a
			if a.id:match("^MENU_COMBAT") then
				data.menu_demos[#data.menu_demos + 1] = a
			end
		end
	end
	loaded.demos = true
end

-- ------------------------------------------------------------ game modes

-- What each endless mode is called and what it says about itself. The survival
-- menu's layout carries a Name and a Desc textbox and an Image for the panel
-- beside the buttons, and the C++ side filled all three from here as the
-- pointer moved over the list.
data.game_modes = {} -- id -> { name, desc, bm }

function data.load_game_modes()
	if loaded.game_modes then return end
	local root = read_xml("game-modes/game-modes.xml")
	local arr = root and xml.array(root, "GAMEMODES")
	for _, node in ipairs(arr and arr.children or {}) do
		local a = node.attrs
		if a.id then
			data.game_modes[a.id] = { name = a.name, desc = a.desc, bm = a.bm }
		end
	end
	loaded.game_modes = true
end

-- ------------------------------------------------------------ chapters

data.chapters = {}

function data.load_chapters()
	if loaded.chapters then return end
	local root = read_xml("chapters.xml")
	local arr = xml.array(root, "CHAPTERS")
	for _, node in ipairs(arr.children) do
		data.chapters[#data.chapters + 1] = { id = node.attrs.id, name = node.attrs.name }
	end
	loaded.chapters = true
end

function data.load_all()
	data.load_weapons()
	data.load_creatures()
	data.load_variants()
	data.load_terrains()
	data.load_demos()
	data.load_game_modes()
	data.load_chapters()
end

return data

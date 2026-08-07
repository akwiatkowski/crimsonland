-- Game data: loads the original XML datasets into Lua tables.

local xml = require("src.xml")
local paths = require("src.engine.paths")

local data = {}

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

function data.load_weapons()
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
			recoil = to_num(a.recoil, 0.1),
			num_projectiles = to_num(a.num_projectiles, 1),
			projectile_speed = to_num(a.projectile_speed, 50),
			projectile_damage = to_num(a.projectile_damage, 1),
			projectile_range = to_num(a.projectile_range, 300),
			icon = a.bm_icon and ("weapons/" .. a.bm_icon) or nil,
			ammo_icon = a.ammo_icon,
		}
		data.weapons[w.id] = w
		data.weapon_order[w.index] = w
	end
end

-- ------------------------------------------------------------ creatures

-- visual/audio defs from creatures.xml
data.creatures = {} -- type -> table

function data.load_creatures()
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
				elseif k == "move_animation_playback_speed" then c.move_speed = to_num(v, 1)
				elseif k == "die_animation_playback_speed" then c.die_speed = to_num(v, 1)
				elseif k and k:match("^snd_") then c.sounds[k] = v
				end
			end
			data.creatures[c.id] = c
		end
	end
end

-- gameplay variants from creature-variants.xml
data.variants = {} -- variant id -> table
data.base_variant = {} -- creature type -> lowest-index variant

function data.load_variants()
	local root = read_xml("creatures/creature-variants.xml")
	local arr = xml.array(root, "VARIANTS")
	for _, node in ipairs(arr.children) do
		local a = node.attrs
		local v = {
			id = a.id,
			legacy_index = to_num(a.legacy_variant_index, 9999),
			type = a.type,
			xp = to_num(a.experience_worth, 10),
			damage = to_num(a.damage, 5),
			health = to_num(a.health, 10),
			speed = to_num(a.speed, 1),
			scale = to_num(a.scale, 1),
			r = to_num(a.color_base_r, 1),
			g = to_num(a.color_base_g, 1),
			b = to_num(a.color_base_b, 1),
		}
		data.variants[v.id] = v
		local cur = data.base_variant[v.type]
		if not cur or v.legacy_index < cur.legacy_index then
			data.base_variant[v.type] = v
		end
	end
end

-- ------------------------------------------------------------ terrains

data.terrains = {} -- chapter id -> ops list

function data.load_terrains()
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
end

-- ------------------------------------------------------------ chapters

data.chapters = {}

function data.load_chapters()
	local root = read_xml("chapters.xml")
	local arr = xml.array(root, "CHAPTERS")
	for _, node in ipairs(arr.children) do
		data.chapters[#data.chapters + 1] = { id = node.attrs.id, name = node.attrs.name }
	end
end

function data.load_all()
	data.load_weapons()
	data.load_creatures()
	data.load_variants()
	data.load_terrains()
	data.load_chapters()
end

return data

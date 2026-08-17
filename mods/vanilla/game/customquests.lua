-- Authored quests: the one part of the game's content 10tons left in a format
-- meant to be written by hand, and documented in the file itself.
--
-- custom-quests/<set>/quest-N.xml, and quest-1.xml opens with the whole spec
-- in a comment:
--
--   type            Creature type reference to creature-variants.xml id.
--   x               The x position. The game area is 0..1820
--   y               The y position. The game area is 0..1024
--   angle           Spawn angle in degrees.
--   time            Spawn time in milliseconds. Can spawn earlier if no other
--                   creatures are alive.
--   num_spawned     Number of creatures to spawn.
--   formation       Either LINE or CIRCLE.
--
-- (That comment is also where the playfield's real size came from -- the port
-- had been guessing at a square 2048 until it was read.)
--
-- Two things the spec says that are easy to miss, and that are what make an
-- authored quest feel authored rather than scripted:
--
--   * "Can spawn earlier if no other creatures are alive" -- the timeline is a
--     ceiling, not a schedule. Clear the field and the next wave comes at once,
--     so a good player sets the pace.
--   * The attribute is spelled `spawn_formation` in the shipped files while the
--     comment calls it `formation`; both are accepted here. `spawn_radius` is
--     used by the files and not mentioned in the comment at all.

local data = require("mods.vanilla.game.data")
local paths = require("src.engine.paths")
local xml = require("src.xml")

local customquests = {}

local ROOT = "custom-quests"
local DEFAULT_RADIUS = 300 -- when a formation is asked for without a radius

local function to_num(v, default)
	return tonumber(v) or default
end

--- Pull { id -> value } out of an <array id="INFO"> of <node id= value= />.
local function info_map(root)
	local out = {}
	local arr = xml.array(root, "INFO")
	if not arr then return out end
	for _, node in ipairs(arr.children) do
		local a = node.attrs
		if a.id then out[a.id] = a.value end
	end
	return out
end

local function spawn_list(root)
	local out = {}
	local arr = xml.array(root, "SPAWN_LIST")
	if not arr then return out end
	for _, node in ipairs(arr.children) do
		local a = node.attrs
		out[#out + 1] = {
			type = a.type,
			x = to_num(a.x, 910),
			y = to_num(a.y, 512),
			angle = to_num(a.angle, 0),
			-- milliseconds in the file, seconds everywhere in this port
			time = to_num(a.time, 0) / 1000,
			count = math.max(1, math.floor(to_num(a.num_spawned, 1))),
			formation = (a.spawn_formation or a.formation or "LINE"):upper(),
			radius = to_num(a.spawn_radius, DEFAULT_RADIUS),
		}
	end
	table.sort(out, function(p, q) return p.time < q.time end)
	return out
end

local function read_quest(set, file)
	local text = love.filesystem.read(("%s/%s/%s/%s"):format(paths.ASSETS, ROOT, set, file))
	if not text then return nil end
	local ok, root = pcall(xml.parse, text)
	if not ok or not root then
		print(("[custom] %s/%s: unparseable"):format(set, file))
		return nil
	end
	local info = info_map(root)
	local spawns = spawn_list(root)
	if #spawns == 0 then
		print(("[custom] %s/%s: no SPAWN_LIST entries"):format(set, file))
		return nil
	end
	return {
		set = set,
		file = file,
		name = info.name or file:gsub("%.xml$", ""),
		author = info.author or "unknown",
		weapon = info.weapon,
		spawns = spawns,
	}
end

local cache

--- Every quest in every set under custom-quests/, in set then file order.
-- The pak ships one set ("myset") with two quests; a player dropping another
-- folder in beside it is exactly what the format is for.
function customquests.all()
	if cache then return cache end
	cache = {}
	local dir = paths.ASSETS .. "/" .. ROOT
	for _, set in ipairs(love.filesystem.getDirectoryItems(dir)) do
		local info = love.filesystem.getInfo(dir .. "/" .. set)
		if info and info.type == "directory" then
			local files = love.filesystem.getDirectoryItems(dir .. "/" .. set)
			table.sort(files)
			for _, file in ipairs(files) do
				if file:match("%.xml$") then
					local q = read_quest(set, file)
					if q then cache[#cache + 1] = q end
				end
			end
		end
	end
	print(("[custom] %d authored quest(s) found"):format(#cache))
	return cache
end

--- Where the Nth creature of a spawn node goes. LINE lays them along the
-- node's own angle so a row walks in together; CIRCLE rings the point, which
-- is how the shipped boss fight surrounds you.
function customquests.place(node, i)
	local n = node.count
	if n <= 1 then return node.x, node.y end
	if node.formation == "CIRCLE" then
		local a = (i - 1) / n * math.pi * 2
		return node.x + math.cos(a) * node.radius,
			node.y + math.sin(a) * node.radius
	end
	-- LINE: centred on the point, laid across the node's facing
	local a = math.rad(node.angle) + math.pi / 2
	local spacing = node.radius / math.max(1, n - 1)
	local offset = (i - 1 - (n - 1) / 2) * spacing
	return node.x + math.cos(a) * offset, node.y + math.sin(a) * offset
end

--- Resolve a spawn node's `type` against creature-variants.xml / creatures.xml.
function customquests.variant(node)
	return data.variants[node.type] or data.base_variant[node.type]
end

return customquests

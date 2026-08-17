-- Custom Quests: menus -> the authored-quest list -> play one.
--
-- The pak ships one set, custom-quests/myset, with two quests. quest-1 is
-- "Spider Boss Dodge Fight" — 16 Variant_39 in a 400px ring and 5 SpiderBoss
-- in a 600px ring, both centred on the middle of the playfield — so a capture
-- of it is also a check that CIRCLE formations and spawn_radius are read.
--
-- The route matters as much as the mode: the Custom Quests button does not
-- exist in the pak's play-menu layout, only in its events script, so a run
-- where the click does nothing means the button the game adds went missing.

local function report_list()
	local list = require("mods.vanilla.game.customquests").all()
	for i, q in ipairs(list) do
		print(("[test] quest %d: %q by %s, weapon=%s, %d node(s)"):format(
			i, q.name, q.author, tostring(q.weapon), #q.spawns))
	end
end

local function report_run()
	local g = require("mods.vanilla.game.play")
	print(("[test] mode=%s quest=%s weapon=%s creatures=%d node=%d/%d"):format(
		tostring(g.mode), g.custom and g.custom.name or "-",
		g.player.weapon and g.player.weapon.id or "-",
		#g.creatures, g.custom_next, g.custom and #g.custom.spawns or 0))
end

--- CIRCLE formations put their creatures on a ring of `spawn_radius` around
-- the node's point, so the check is how far each one is from that point --
-- both of quest-1's nodes are centred on 910,512 with radii 400 and 600.
-- Measured as soon after the spawn as possible: they walk inward from there.
local function report_rings()
	local g = require("mods.vanilla.game.play")
	if #g.creatures == 0 then
		print("[test] no creatures placed")
		return
	end
	local buckets = {}
	for _, c in ipairs(g.creatures) do
		local dx, dy = c.x - 910, c.y - 512
		local d = math.floor(math.sqrt(dx * dx + dy * dy) / 50 + 0.5) * 50
		buckets[d] = (buckets[d] or 0) + 1
	end
	local keys = {}
	for d in pairs(buckets) do keys[#keys + 1] = d end
	table.sort(keys)
	local parts = {}
	for _, d in ipairs(keys) do
		parts[#parts + 1] = ("%dx@~%d"):format(buckets[d], d)
	end
	print(("[test] %d creatures, distance from 910,512: %s"):format(
		#g.creatures, table.concat(parts, " ")))
end

return {
	{ t = 2.0, run = report_list },
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_CustomQuests" },
	{ t = 5.5, click = "Quest_0" },
	-- the quest starts at 5.5; node 1 fires at once (an empty field pulls it
	-- forward), node 2 on its own 1000ms mark, so 6.6 catches both freshly placed
	{ t = 6.6, run = report_rings },
	{ t = 7.5, run = report_run },
	{ t = 14.0, run = report_run },
	captures = { 5.2, 6.7 },
}

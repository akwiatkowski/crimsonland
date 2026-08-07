-- Timeline runner: the game's top-level state machine (assets/timeline.xml).
-- Nodes list the screen stack to build; EndTimelineEvent() advances to the
-- next node in file order; BeginTimelineEvent(id) jumps; JUMP nodes loop.

local xml = require("src.xml")
local screens = require("src.engine.screens")

local timeline = {}

timeline.nodes = {}
timeline.order = {}
timeline.current = nil -- node id

function timeline.load()
	local data = love.filesystem.read("assets/timeline.xml")
	local root = xml.parse(data)
	local arr = xml.array(root, "timeline")
	for _, node in ipairs(arr.children) do
		if node.tag == "node" then
			timeline.nodes[node.id] = node.attrs
			table.insert(timeline.order, node.id)
		end
	end
end

local function split_list(s)
	local out = {}
	for part in tostring(s or ""):gmatch("[^,]+") do
		out[#out + 1] = part:match("^%s*(.-)%s*$")
	end
	return out
end

function timeline.begin(id, transition)
	local node = timeline.nodes[id]
	if not node then
		print(("[timeline] unknown event '%s'"):format(tostring(id)))
		return
	end
	timeline.current = id

	local ntype = node.type
	if ntype == "JUMP" then
		-- 'event' attribute selects target; missing = first node
		timeline.begin(node.event or timeline.order[1])
		return
	elseif ntype == "DELAY" then
		timeline._delay = tonumber(node.delay) or 1
		return
	end

	-- build the target stack, reusing live screen instances where possible
	local wanted = split_list(node.screens or node.screen)
	local new_stack = {}
	for _, name in ipairs(wanted) do
		name = name:gsub("^&", "")
		local s = screens.find(name)
		if not s then
			s = screens.push(name)
			s.stack_pos = nil
		end
		table.insert(new_stack, s)
	end
	-- mark screens not wanted anymore as leaving
	for _, s in ipairs(screens.stack) do
		local keep = false
		for _, ns in ipairs(new_stack) do
			if ns == s then keep = true break end
		end
		if not keep then
			s.leaving = true
			s.entering = false
		end
	end
	screens.stack = new_stack

	-- forward parm_* to the key screen
	local key = node.key_screen
	if key then
		local ks = screens.find(key)
		if ks then
			for k, v in pairs(node) do
				if type(k) == "string" and k:sub(1, 5) == "parm_" then
					ks.messages[k:sub(6)] = v
					screens.call(ks, "OnScreenMessage", k:sub(6), v)
				end
			end
		end
	end
end

function timeline.end_event()
	-- advance to next node in file order
	for i, id in ipairs(timeline.order) do
		if id == timeline.current then
			local next_id = timeline.order[i + 1]
			if next_id then timeline.begin(next_id) end
			return
		end
	end
end

function timeline.update(dt)
	if timeline._delay then
		timeline._delay = timeline._delay - dt
		if timeline._delay <= 0 then
			timeline._delay = nil
			timeline.end_event()
		end
	end
end

return timeline

-- Minimal XML parser for the 10tons data format (root/array/node trees).
-- Handles: <?xml?> prolog, <!-- comments -->, self-closing tags, attributes,
-- nested elements. Text content is mostly unused by this game's data files.
--
-- Returns a tree of tables:
--   { tag = "array", id = "timeline", attrs = {...}, children = {...} }

local xml = {}

local function parse_attrs(s)
	local attrs = {}
	for k, v in s:gmatch('([%w_%.%-:]+)%s*=%s*"([^"]*)"') do
		attrs[k] = v
	end
	-- single-quoted attributes
	for k, v in s:gmatch("([%w_%.%-:]+)%s*=%s*'([^']*)'") do
		attrs[k] = v
	end
	return attrs
end

function xml.parse(text)
	-- strip prolog and comments
	text = text:gsub("<%?xml.-%?>", "")
	text = text:gsub("<!%-%-.-%-%->", "")

	local pos = 1
	local stack = {}
	local root = nil

	while true do
		local s, e = text:find("<", pos, true)
		if not s then break end
		local closing = text:sub(s + 1, s + 1) == "/"
		if closing then
			local gt = text:find(">", e, true)
			table.remove(stack)
			pos = gt + 1
		else
			local gt = text:find(">", e, true)
			local inside = text:sub(s + 1, gt - 1)
			local selfclose = inside:sub(-1) == "/"
			if selfclose then inside = inside:sub(1, -2) end
			local tag = inside:match("^([%w_%.%-:]+)")
			local rest = inside:sub(#tag + 1)
			local node = {
				tag = tag,
				attrs = parse_attrs(rest),
				children = {},
			}
			node.id = node.attrs.id
			local parent = stack[#stack]
			if parent then
				table.insert(parent.children, node)
			else
				root = node
			end
			if not selfclose then
				table.insert(stack, node)
			end
			pos = gt + 1
		end
	end
	return root
end

-- Find first child array with given id.
function xml.array(root, id)
	for _, c in ipairs(root.children) do
		if c.tag == "array" and c.id == id then return c end
	end
	return nil
end

return xml

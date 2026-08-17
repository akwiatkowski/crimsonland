-- The original perk roster, read out of prog.dll.
--
-- The perks are the one dataset 10tons did not ship as XML: the pak carries
-- only numbered icons (perks/perk_01.png .. perk_59.png), and the names,
-- descriptions and two-letter abbreviations live in the executable. They are
-- there in full, in one contiguous run of C strings, and the port had been
-- guessing at them -- a clean-room roster of 25 with invented names, invented
-- descriptions and icons assigned in the wrong order.
--
-- The run is a sequence of records, each:
--
--     [abbreviation]  "Bm"            optional -- four perks have none
--     name            "Bloody Mess"
--     description     "The more the merrier. ..."
--
-- It starts at the "AntiPerk" sentinel (the perk the randomizer hands back when
-- it fails -- its description is "You shouldn't be seeing this..") and ends at
-- the icon format string "perks/perk_%.2d.png", which is what the whole table
-- is indexed for. Between those two anchors are exactly 55 perks, and record N
-- is icon perk_NN.png -- checked against the art: 1 is a blood splat (Bloody
-- Mess), 2 a crosshair (Sharpshooter), 5 a running man (Long Distance Runner),
-- 12 the radiation trefoil (Radioactive), 45 a clock face (Death Clock), 47
-- crossed plasters (Bandage), 50 a stop sign (Stationary Reloader).
--
-- Read at runtime rather than copied into this repo: the text is 10tons', the
-- same as the XML and the art, and vendor/ is where their work stays.

local paths = require("src.engine.paths")

local perktext = {}

local START = "AntiPerk"
local END = "perks/perk_%.2d.png"

--- Split a byte range into its non-empty null-terminated strings, in order.
local function strings_in(data, from, to)
	local out, pos = {}, from
	while pos <= to do
		local z = data:find("\0", pos, true)
		if not z or z > to then break end
		local s = data:sub(pos, z - 1)
		if s:match("%S") then out[#out + 1] = s end
		pos = z + 1
	end
	return out
end

--- Parse the table. Returns an array of { index, abbrev, name, desc }, or nil
-- plus a reason when the executable is not there to read.
local function parse()
	local data = love.filesystem.read(paths.PROG)
	if not data then
		return nil, "prog.dll not found at " .. paths.PROG
	end

	local from = data:find(START, 1, true)
	local to = data:find(END, 1, true)
	if not from or not to or to <= from then
		return nil, "perk table anchors not found in prog.dll"
	end

	local strs = strings_in(data, from, to - 1)
	local list, abbrev, name = {}, nil, nil
	for _, s in ipairs(strs) do
		if #s <= 3 and s:match("^%a+$") and name == nil then
			-- a short all-letters string before a name is its abbreviation;
			-- the four perks that lack one simply go straight to the name
			abbrev = s
		elseif name == nil then
			name = s
		else
			list[#list + 1] = {
				index = #list, -- AntiPerk is record 0, so real perks start at 1
				abbrev = abbrev,
				name = name,
				desc = s,
			}
			abbrev, name = nil, nil
		end
	end

	-- drop the sentinel; it is not a perk anyone may be offered
	table.remove(list, 1)
	if #list == 0 then return nil, "perk table parsed empty" end
	return list
end

local cache

--- index -> { index, abbrev, name, desc }. Empty when prog.dll is unreadable,
-- which leaves the perks working but nameless rather than crashing: `make
-- clean` removes vendor/extracted while leaving the extracted assets in place.
function perktext.all()
	if cache then return cache end
	local list, err = parse()
	if not list then
		print(("[perks] %s -- perk names and descriptions unavailable"):format(err))
		cache = {}
		return cache
	end
	cache = {}
	for _, p in ipairs(list) do cache[p.index] = p end
	print(("[perks] %d perk definitions read from prog.dll"):format(#list))
	return cache
end

return perktext

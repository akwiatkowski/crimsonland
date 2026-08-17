-- The Editbox comp, driven through the screen it was written for.
--
-- ui/fw/new-profile.lua is the pak's only Editbox: a "Name" field, max 14
-- chars, with OK and Cancel. Its events script focuses the field from OnUpdate
-- and reads GetProperty("Name:editbox.text") when OK is clicked, so typing
-- into it exercises focus, input, the max_chars clamp and the read-back path
-- the original used.
--
-- The screen is pushed directly because vanilla gates it out: the Profiles
-- button carries required_features="!SINGLE_PROFILE" and this build sets
-- SINGLE_PROFILE, so there is no route to it from the menus.

local screens = require("src.engine.screens")

local function push_new_profile()
	screens.push("NewProfile")
end

local function report(label)
	return function()
		local top = screens.top()
		local comp = top and top.compmap["Name"]
		local comps = require("src.engine.comps")
		print(("[test] %s: screen=%s text=%q focused=%s"):format(
			label, top and top.name or "?",
			comp and tostring(comp.props["editbox.text"]) or "<no comp>",
			comps.focused and comps.focused.name or "none"))
	end
end

local function report_profiles(label)
	return function()
		local names = {}
		for _, p in ipairs(require("src.engine.platform").profiles()) do
			names[#names + 1] = p.name
		end
		print(("[test] profiles %s: %s"):format(label, table.concat(names, ", ")))
	end
end

--- The harness shares the player's save directory, so a scenario that creates
-- a profile has to take it back out again — otherwise every run leaves another
-- "Ripl0123456789" behind in a real save file.
local function forget_test_profile()
	local profiles = require("src.engine.platform").profiles()
	for i = #profiles, 2, -1 do
		if profiles[i].name:match("^Ripl") then table.remove(profiles, i) end
	end
end

return {
	{ t = 2.0, run = push_new_profile },
	{ t = 3.0, text = "Ripley" },
	{ t = 3.2, run = report("typed") },
	-- backspace is an editing key: the field must eat it, not the screen
	{ t = 3.4, key = "backspace" },
	{ t = 3.5, key = "backspace" },
	{ t = 3.6, run = report("after backspace") },
	-- max_chars is 14 on this field; this pushes well past it
	{ t = 4.0, text = "0123456789012345678901234567890" },
	{ t = 4.2, run = report("clamped") },
	{ t = 5.0, click = "Ok" },
	{ t = 6.0, run = report_profiles("after OK") },
	{ t = 6.5, run = forget_test_profile },
	{ t = 6.6, run = report_profiles("after cleanup") },
	captures = { 3.3, 4.3, 6.2 },
}

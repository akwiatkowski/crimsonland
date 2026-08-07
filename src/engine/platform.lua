-- Platform / product / profile / statistics stubs.
-- The desktop port behaves like the full GOG version: no ads, no IAP,
-- no trial, no account management. Features mirror prog.xml plus the
-- desktop-relevant extras the scripts query.

local platform = {}

local FEATURES = {
	ACHIEVEMENTS = true,
	LEADERBOARDS = true,
	WINDOWED_TOGGLE = true,
	EXIT_DIALOG_ON_ESC = true,
	NO_TRIAL_TEXTS = true, -- full version: no trial nag texts
	SHOWLOGO = true,
	-- explicitly absent: ADS, MOREGAMES, ANNOUNCEMENTS, ACCOUNT_MANAGEMENT,
	-- VIRTUAL_CONTROLS, EXTERNAL_HELP, TROPHIES, AUTOMATIC_PROFILE_NAMING,
	-- NO_FORCE_FEEDBACK, ADDITIONAL_CONTENT_JUNE_2015
}

function platform.feature_exists(name)
	return FEATURES[name] == true
end

local product_values = {
	game_id = "crimsonland",
	-- url_more_games, feedback_token, housead_link intentionally nil
}

function platform.product_value(key)
	return product_values[key]
end

-- ---------------------------------------------------------------- profiles

local profiles = {
	{ name = "Player", values = {} },
}
platform.current_profile = 1

local stats = {} -- statistics registry (PLAYS_QUESTS etc.)
local globals = {} -- string-valued global registry (CONTROLLER_VIBRATION etc.)

function platform.get_stat(key) return stats[key] or 0 end
function platform.set_stat(key, v) stats[key] = v end
function platform.change_stat(key, d) stats[key] = (stats[key] or 0) + d end

function platform.get_global(key) return globals[key] end
function platform.set_global(key, v) globals[key] = v end

function platform.profiles() return profiles end
function platform.current()
	return profiles[platform.current_profile]
end

-- ------------------------------------------------------------- extensions

local extensions = {}

function platform.register_extension(name, fn)
	extensions[name] = fn
end

platform.register_extension("PlatformInfo", function(cmd)
	if cmd == "PlatformId" then return "MACOS" end
	if cmd == "ScreenSizeId" then return "LARGE" end
	return nil
end)

platform.register_extension("ProgramInfo", function(cmd)
	if cmd == "ProgramId" then return "Crimsonland" end
	return nil
end)

platform.register_extension("OpenURL", function(url)
	love.system.openURL(url)
	return nil
end)

function platform.call_extension(name, cmd)
	local ext = extensions[name]
	if not ext then
		-- unknown extensions (ADS_*, GameCenter, Accounts, RateApp, ...) no-op
		return nil
	end
	return ext(cmd)
end

return platform

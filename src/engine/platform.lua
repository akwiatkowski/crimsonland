-- Platform / product / profile / statistics stubs.
-- The desktop port behaves like the full GOG version: no ads, no IAP,
-- no trial, no account management. Features mirror prog.xml plus the
-- desktop-relevant extras the scripts query.

local platform = {}

-- What this build is. The layouts gate their contents on these through
-- `required_features` (see screens.load), so the list decides which of the
-- original's platform variations show up: a desktop copy with display and
-- control options, no store, no console services, and none of the modes or
-- game types this port has not implemented.
local FEATURES = {
	ACHIEVEMENTS = true,
	LEADERBOARDS = true,
	WINDOWED_TOGGLE = true,
	DISPLAY_OPTIONS = true,
	PC_CONTROLS = true,
	EXIT_DIALOG_ON_ESC = true,
	NO_TRIAL_TEXTS = true, -- full version: no trial nag texts
	SHOWLOGO = true,
	SINGLE_PROFILE = true, -- one local profile; no profile picker
	NO_COOP = true, -- no second trooper, so co-op controls stay hidden
	HIDE_HIGHSCORES_FILTER_BUTTON = true, -- local scores only: nothing to filter
	-- The June 2015 content pack, which this copy has and this port implements:
	-- the pak ships chapter 7 "Phoenix Calling" and Waves mode, and both are
	-- built here. Two places gate on it -- chapters.xml:14 on CHAPTER_7, and
	-- ui/play-menu-survival.lua on the Play_WAVES button -- and with the
	-- feature absent the port answered them differently: it never reads the
	-- chapter gate, so chapter 7 was playable, while the layout's own gate hid
	-- the Waves button, so a mode with a full implementation behind it
	-- (update_waves_mode) could not be chosen. Granting the feature answers
	-- both the same way, through the original's own mechanism.
	ADDITIONAL_CONTENT_JUNE_2015 = true,
	-- explicitly absent: ADS, MOREGAMES, ANNOUNCEMENTS, ACCOUNT_MANAGEMENT,
	-- VIRTUAL_CONTROLS, EXTERNAL_HELP, TROPHIES, AUTOMATIC_PROFILE_NAMING,
	-- NO_FORCE_FEEDBACK, DEVELOPER_MODE,
	-- RESTORE_PURCHASES_BUTTON, GAME_CENTER, GOOGLE_PLAY_GAMES,
	-- PS4_CONTROLS, PS_VITA_CONTROLS, LEADERBOARDS_SELECTOR,
	-- SHOW_SEPARATE_GLOBAL_HIGHSCORES, HIGHSCORES_DETAILS_BUTTON,
	-- TYPOSHOOTER (the typing mode is not implemented)
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

-- state snapshot for the save system (the mod's save module)
-- Settings the options screens change. The original kept these in the profile
-- blob; here they are their own table so the audio module can be pointed at
-- them on load without digging through profile values.
platform.settings = {
	sound_volume = 1,
	music_volume = 1,
	windowed = true,
}

function platform.export_state()
	return {
		profiles = profiles,
		current_profile = platform.current_profile,
		stats = stats,
		globals = globals,
		settings = platform.settings,
	}
end

function platform.import_state(state)
	if type(state.profiles) == "table" and #state.profiles > 0 then
		profiles = state.profiles
	end
	platform.current_profile = state.current_profile or 1
	if profiles[platform.current_profile] == nil then platform.current_profile = 1 end
	if type(state.stats) == "table" then stats = state.stats end
	if type(state.globals) == "table" then globals = state.globals end
	for k, v in pairs(state.settings or {}) do platform.settings[k] = v end
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

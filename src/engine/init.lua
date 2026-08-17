-- Engine bootstrap + script API assembly.
--
-- Script environments: every screen (plus templates/autoexec) gets a fresh
-- env table with __index falling back to engine.API then _G (stdlib).
-- Contextual functions (SetProperty etc.) recover the calling env via
-- getfenv(2), which carries the owning screen and last-created comp.

local assets = require("src.engine.assets")
local audio = require("src.engine.audio")
local comps = require("src.engine.comps")
local font = require("src.engine.font")
local fx = require("src.engine.fx")
local mod = require("src.engine.mod")
local nx = require("src.engine.nx")
local paths = require("src.engine.paths")
local platform = require("src.engine.platform")
local screens = require("src.engine.screens")
local timeline = require("src.engine.timeline")

local engine = {}

local API = {}
engine.API = API

local logged_stubs = {}
local function stub(name)
	return function(...)
		if not logged_stubs[name] then
			logged_stubs[name] = true
			print(("[api] %s stubbed"):format(name))
		end
		return nil
	end
end

-- ------------------------------------------------------------- script envs

function engine.new_script_env(screen)
	local env = { __screen = screen, __last_comp = nil, __templates_mode = false }
	setmetatable(env, {
		__index = function(_, k)
			local v = API[k]
			if v ~= nil then return v end
			return _G[k]
		end,
	})
	return env
end

-- Contextual API functions recover the calling script's env via getfenv(2)
-- inline at each call site (helper indirection would shift stack levels).

-- ------------------------------------------------------------------ basics

API.Print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	print(table.concat(parts, "\t"):gsub("%\n", "\n"))
end

API.LuaInclude = function(path)
	local env = getfenv(2)
	local chunk, err = loadfile(paths.ASSETS .. "/" .. path)
	if not chunk then
		print(("[api] LuaInclude failed: %s: %s"):format(path, err))
		return
	end
	setfenv(chunk, env)
	local ok, rerr = pcall(chunk)
	if not ok then print(("[api] LuaInclude %s error: %s"):format(path, rerr)) end
end

-- localization is identity: localized-texts.xml ships empty in this build
function _G.Localize(text) return text end
API.Localize = _G.Localize
API.LocalizeNumber = function(n) return tostring(n) end
API.LocalizeTime = function(n) return tostring(n) end
API.LocalizeNewLine = function() return "\n" end

-- --------------------------------------------------------------- comp API

API.CreateComp = function(ctype, name)
	local env = getfenv(2)
	if env.__templates_mode then
		local comp = comps.new(ctype, name, nil)
		comps.templates[name] = comp.props
		env.__last_comp = comp
		return
	end
	local screen = env.__screen
	if not screen then return end
	local comp = comps.new(ctype, name, screen)
	comp._order = #screen.comps + 1
	table.insert(screen.comps, comp)
	screen.compmap[name] = comp
	env.__last_comp = comp
end

API.SetProperty = function(path, ...)
	local env = getfenv(2)
	local values = { ... }
	local name, prop = tostring(path):match("^(.-):(.*)$")
	if name then
		if name == "/" then
			local screen = env.__screen
			if screen then
				screen.props[prop] = values[1]
			end
			return
		end
		local screen = env.__screen
		local comp = screen and screen.compmap[name]
		if comp then
			comps.set(comp, prop, values)
		end
		return
	end
	-- implicit target: last created comp
	local comp = env.__last_comp
	if comp then
		comps.set(comp, tostring(path), values)
	end
end

API.GetProperty = function(path)
	local env = getfenv(2)
	local name, prop = tostring(path):match("^(.-):(.*)$")
	local comp
	if name then
		local screen = env.__screen
		comp = screen and screen.compmap[name]
	else
		comp = env.__last_comp
		prop = tostring(path)
	end
	if not comp then return nil end
	return comps.get(comp, prop)
end

API.DoesCompExist = function(name)
	local env = getfenv(2)
	local screen = env.__screen
	return screen ~= nil and screen.compmap[name] ~= nil
end

API.IsCompVisible = function(name)
	local env = getfenv(2)
	local screen = env.__screen
	local comp = screen and screen.compmap[name]
	return comp ~= nil and comps.get(comp, "visible") == true
end

API.SetUIFocus = stub("SetUIFocus")
API.GetComps = stub("GetComps")
API.GetNumberOfComps = stub("GetNumberOfComps")
API.GetCompNameByIndex = stub("GetCompNameByIndex")
API.GetActiveCompName = stub("GetActiveCompName")
API.CompExists = API.DoesCompExist
API.EventExists = function() return true end

-- -------------------------------------------------------------- screen API

API.CreateScreen = function(name, layout)
	screens.register(name, layout)
end

API.UIEvents = function(path)
	local env = getfenv(2)
	local screen = env.__screen or screens.loading
	if screen then screen.events_path = path end
end

API.PushScreen = function(name, parm) screens.push(name, parm) end
API.PopScreen = function() screens.pop() end
API.SwitchScreen = function(name) screens.switch(name) end
API.PopAllScreens = function()
	for _, s in ipairs(screens.stack) do s.leaving = true end
end

-- peek from the TOP of the stack: i=0 is the topmost screen. The scripts'
-- GetStackDepthOffset() depends on this to push covered panels down/away.
API.PeekScreen = function(i)
	local s = screens.stack[#screens.stack - (i or 0)]
	return s and s.name or nil
end
API.GetNumberOfScreensInStack = function() return #screens.stack end
API.GetActiveScreenName = function()
	local s = screens.current or screens.top()
	return s and s.name or ""
end
API.IsScreenInStack = function(name) return screens.find(name) ~= nil end
API.IsScreenLeaving = function(name)
	local s = screens.find(name)
	return s ~= nil and s.leaving == true
end
API.IsTopScreen = function(name)
	local top = screens.top()
	return top ~= nil and top.name == name
end

API.GetActiveScreenTransPhase = function()
	local s = screens.current or screens.top()
	return s and s.phase or 1
end
API.GetScreenTransPhase = function(name)
	local s = screens.find(name)
	return s and s.phase or 0
end
API.GetActiveScreenTimer = function()
	local s = screens.current or screens.top()
	return s and s.timer or 0
end
API.GetActiveScreenAnimKey = API.GetActiveScreenTimer
API.SetActiveScreenProperty = function(k, v)
	local s = screens.current or screens.top()
	if s then s.props[k] = v end
end

API.SendScreenMessage = function(name, key, value)
	local s = screens.find(name)
	if not s then return end
	s.messages[key] = value
	screens.call(s, "OnScreenMessage", key, value)
end
API.GetScreenMessage = function(key)
	local s = screens.current or screens.top()
	return s and s.messages[key] or nil
end
API.PopupClosed = stub("PopupClosed")
API.ShowPopupMessage = stub("ShowPopupMessage")

-- ------------------------------------------------------------- timeline API

API.BeginTimelineEvent = function(id, transition) timeline.begin(id, transition) end
API.EndTimelineEvent = function() timeline.end_event() end
API.RestartTimelineEvent = function(id) timeline.begin(id or timeline.current) end
API.ResumeSavedTimelineEvent = stub("ResumeSavedTimelineEvent")
API.SavedTimelineEventExists = function() return false end
API.SaveAtNextTimelineEvent = stub("SaveAtNextTimelineEvent")
API.GetCurrentTimelineEvent = function() return timeline.current end
API.GetCurrentTimelineEventType = function() return "SCREEN" end
API.GetActiveTimeline = function() return "timeline" end
API.SetActiveTimeline = stub("SetActiveTimeline")
API.LoadGameState = stub("LoadGameState")

-- ---------------------------------------------------------------- game API

API.GetActiveGame = function() return "Crimsonland" end
API.SetActiveGame = stub("SetActiveGame")
API.GetGameNameByIndex = function(i) return i == 0 and "Crimsonland" or nil end
API.GetNumberOfGames = function() return 1 end
API.InitGameLevel = stub("InitGameLevel")
API.DropCoopPlayers = stub("DropCoopPlayers")
API.SetSeeds = stub("SetSeeds")
API.SaveGameState = stub("SaveGameState")
API.SaveGameExists = function() return false end
API.DeleteGameState = stub("DeleteGameState")

-- ---------------------------------------------------------------- audio API

API.SwitchMusic = function(name, fo, fi) audio.switch_music(name, fo, fi) end
API.StopMusic = function() audio.stop_music() end
API.PlaySound = function(name) audio.play_sound(name) end
API.PlaySoundDelayed = function(name, delay) audio.play_sound_delayed(name, delay) end
API.CacheSound = function(name) assets.sound(name, "sfx") end
API.SetMusicVolume = function(v) audio.set_music_volume(v or 1) end
API.GetMusicVolume = function() return audio.music_volume end
API.SetSoundVolume = function(v) audio.sound_volume = v or 1 end
API.GetSoundVolume = function() return audio.sound_volume end
API.GetCurrentMusicAsString = function() return audio.current_music or "" end
API.PlaySoundWithMusicVolume = function(name) audio.play_sound(name, audio.music_volume) end
API.SetMusicLooping = stub("SetMusicLooping")
API.SlideMusicVolume = stub("SlideMusicVolume")
API.SuppressMusicForDuration = stub("SuppressMusicForDuration")

-- -------------------------------------------------------------- profile API

API.LoadProfiles = function() end
API.SaveProfiles = function() end
API.GetProfile = function() return platform.current().name end
API.SetProfile = function(name)
	for i, p in ipairs(platform.profiles()) do
		if p.name == name then platform.current_profile = i return end
	end
end
API.GetNumberOfProfiles = function() return #platform.profiles() end
API.GetProfileNameByIndex = function(i)
	local p = platform.profiles()[(i or 0) + 1]
	return p and p.name or nil
end
API.IsProfileNameValid = function(name)
	return type(name) == "string" and name ~= "" and #name <= 32
end
API.AddProfile = function(name)
	if API.IsProfileNameValid(name) then
		table.insert(platform.profiles(), { name = name, values = {} })
	end
end
API.DeleteProfile = function(name)
	for i, p in ipairs(platform.profiles()) do
		if p.name == name and #platform.profiles() > 1 then
			table.remove(platform.profiles(), i)
			platform.current_profile = 1
			return
		end
	end
end
API.GetProfileValue = function(category, key, field)
	local p = platform.current()
	local cat = p.values[category]
	local node = cat and cat[key]
	return node and node[field] or nil
end
API.SetProfileValue = function(category, key, field, value)
	local p = platform.current()
	p.values[category] = p.values[category] or {}
	p.values[category][key] = p.values[category][key] or {}
	p.values[category][key][field] = value
end
API.ProfileValueExists = function(cat, key, field)
	return API.GetProfileValue(cat, key, field) ~= nil
end
API.ProfileValueEquals = function(cat, key, field, value)
	return API.GetProfileValue(cat, key, field) == value
end
API.RemoveProfileValue = stub("RemoveProfileValue")
API.AddProfileTag = stub("AddProfileTag")
API.RemoveProfileTag = stub("RemoveProfileTag")
API.ProfileTagExists = function() return false end
API.RemoveProfileCategory = stub("RemoveProfileCategory")
API.IsProfileValueAcknowledged = function() return true end
API.SetProfileValueAcknowledged = stub("SetProfileValueAcknowledged")

-- ------------------------------------------------------ stats/globals API

API.GetStatisticsInt = function(key) return platform.get_stat(key) end
API.SetStatisticsInt = function(key, v) platform.set_stat(key, v) end
API.ChangeStatisticsInt = function(key, d) platform.change_stat(key, d or 1) end
API.GetGlobalValue = function(key) return platform.get_global(key) end
API.SetGlobalValue = function(key, v) platform.set_global(key, v) end
API.GetValueNameByIndex = stub("GetValueNameByIndex")
API.GetNumberOfValuesInCategory = function() return 0 end

-- ----------------------------------------------------------- platform API

API.FM_ProductFeatureExists = function(name) return platform.feature_exists(name) end
API.FM_GetProductValue = function(key) return platform.product_value(key) end
API.FM_IsControlInterfaceSupported = function(name)
	return name == "MOUSE" or name == "KEYBOARD" or name == "GAMEPAD"
end
API.FM_GetPrimaryControllerInterface = function() return "MOUSE" end
API.FM_UsesPackage = function() return true end

API.IsDeveloperModeActive = function() return false end
API.IsInterstitialAdsEnabled = function() return false end
API.GetVersionString = function() return "1.2.3.0-macOS-port" end
API.GetScreenWidth = function() return screens.WIDTH end
API.GetScreenHeight = function() return screens.HEIGHT end
API.GetScreenReferenceWidth = function() return screens.WIDTH end
API.GetScreenReferenceHeight = function() return screens.HEIGHT end
API.GetScreenReferenceScaleX = function() return 1 end
API.GetScreenReferenceScaleY = function() return 1 end
API.GetScreenPosX = function() return 0 end
API.GetScreenPosY = function() return 0 end
API.IsScreenWindowed = function() return not love.window.getFullscreen() end
API.SetScreenWindowed = function(windowed)
	love.window.setFullscreen(not (windowed == true or windowed == 1))
end
API.GetMaximumTextureSize = function() return 8192 end
API.GetOverlayZoom = function() return 1 end
API.SetOverlayZoom = stub("SetOverlayZoom")
API.GetOverscan = function() return 0 end
API.SetOverscan = stub("SetOverscan")
API.NexusShutdown = function() love.event.quit() end
API.NexusReInit = stub("NexusReInit")
API.GetPlayerOnlineName = function() return "Player" end
API.GetRegion = function() return "EU" end
API.ChangeLanguage = stub("ChangeLanguage")
API.GetCurrentPackageId = function() return "data" end

API.Trial_IsFullVersionUnlocked = function() return true end
API.Trial_IsTrialExpired = function() return false end
API.Trial_GetUnlockPrice = function() return "" end
API.Trial_UnlockFullVersion = stub("Trial_UnlockFullVersion")
API.IsFullVersionUnlocked = API.Trial_IsFullVersionUnlocked
API.IsTrialExpired = API.Trial_IsTrialExpired
API.GetUnlockPrice = API.Trial_GetUnlockPrice

-- IAP / achievements / leaderboards / analytics: full game, all unlocked
API.IAP_GetItemName = function() return "" end
API.IAP_GetItemPrice = function() return "" end
API.IAP_GetItemDescription = function() return "" end
API.IAP_IsItemPurchased = function() return true end
API.IAP_PurchaseItem = stub("IAP_PurchaseItem")
API.IAP_RestorePurchases = stub("IAP_RestorePurchases")
API.IAP_AnyItemsPurchased = function() return true end
API.IAP_GetNumberOfItems = function() return 0 end
API.IAP_IsAvailable = function() return false end
API.IAP_RequestItemData = stub("IAP_RequestItemData")
API.IAP_SetTrial_IAP = stub("IAP_SetTrial_IAP")
API.IAP_GetItemIdByIndex = function() return nil end

API.AM_UnlockAchievement = stub("AM_UnlockAchievement")
API.AM_IsAchievementUnlocked = function() return false end
API.AM_ShowAchievements = stub("AM_ShowAchievements")

API.Analyst_LogEvent = function() end
API.Analyst_LogEventWithKeyValue = function() end
API.Analyst_LogEventWithKeysAndValues = function() end
API.Analyst_LogEventLevelTime = function() end

-- database (creatures/weapons XML model) — implemented with gameplay
API.DM_GetValue = stub("DM_GetValue")
API.DM_SetValue = stub("DM_SetValue")
API.DM_GetArrayId = stub("DM_GetArrayId")
API.DM_GetArraySize = function() return 0 end
API.DM_GetNodeIndexById = stub("DM_GetNodeIndexById")
API.DM_GetNumberOfArrays = function() return 0 end
API.DM_SaveDatabase = stub("DM_SaveDatabase")

-- virtual currency
API.VC_AddVirtualCurrency = stub("VC_AddVirtualCurrency")
API.VC_CanSpendVirtualCurrency = function() return true end
API.VC_GetAmountOfVirtualCurrency = function() return 0 end
API.VC_SpendVirtualCurrency = function() return true end

-- touch / virtual controls: desktop has none
API.HideVirtualControls = function() end
API.SetMoveAndAimControlsAtTouchPosition = function() end
API.SetTouchfieldZoomPos = function() end
API.ZoomTouchfieldTo = function() end
API.AutoMoveTouchfieldTo = function() end

-- listbox (basic behavior added when a screen needs it)
API.AddListboxLine = stub("AddListboxLine")
API.ClearListbox = stub("ClearListbox")
API.ScrollListboxUp = stub("ScrollListboxUp")
API.ScrollListboxDown = stub("ScrollListboxDown")
API.SetListboxLineBitmap = stub("SetListboxLineBitmap")
API.SetListboxLineTextRight = stub("SetListboxLineTextRight")

-- misc
API.GetFormattedTime = function(sec)
	sec = math.floor(sec or 0)
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
API.IsIntervalElapsed = function() return true end
API.IsCursorOver = function() return false end
API.IsCursorFocusOver = function() return false end
API.IsCursorLockedTo = function() return false end
API.IsPointOverExpandedArea = function() return false end
API.IsEditModeActive = function() return false end
API.Console_AddCommand = stub("Console_AddCommand")
API.ReloadFxs = stub("ReloadFxs")
API.ResetEmitter = stub("ResetEmitter")
API.SetEmitterParticlePoolSize = stub("SetEmitterParticlePoolSize")
API.GetPathPointAt = function() return 0, 0 end
API.AddFX = stub("AddFX")
API.CacheFX = stub("CacheFX")
API.SpawnFX = stub("SpawnFX")
-- scripts name their emitters ("shells_1") for reuse; we spawn per call, so
-- the name is only of interest to the C++ pooling we do not have
API.SpawnEmitterFX = function(_name, path, x, y, rot)
	fx.spawn(path, x or 0, y or 0, rot or 0)
end
API.PartBurstParm = stub("PartBurstParm")
API.LoadUI = stub("LoadUI")
API.EnableIdleTimer = function() end
API.DisableIdleTimer = function() end
API.ResetTutorial = function() end
API.UpdateLiveTile = function() end
API.UpdateRichPresence = function() end
API.RefreshMemUsageEstimates = function() end
API.OpenFileDialog = function() return nil end
API.IsAvailable = function() return false end
API.Authenticate = function() return false end
API.Connect = function() return false end
API.CloudRestore = function() return false end

-- dead shared-framework calls seen in scripts (log-and-no-op)
API.SetVar = stub("SetVar")
API.LM_ShowLeaderboards = stub("LM_ShowLeaderboards")
API.IAP_GetNumberOfCredits = function() return 0 end
API.IAP_OpenOffers = stub("IAP_OpenOffers")

-- FX DSL (fxs/*.lua) is interpreted by src/engine/fx.lua, which binds these
-- three inside the effect file's own environment; at UI-script scope they are
-- meaningless, so they stay no-ops here.
API.FXParm = function(...) end
API.PartFXParm = function(...) end
API.PartFXAddNew = function(...) end

-- install NX_* into API
for k, v in pairs(nx) do
	if k:sub(1, 3) == "NX_" then API[k] = v end
end
API.NX_BLEND_ADDITIVE = "ADDITIVE"

-- ------------------------------------------------------------ boot process

local function load_templates()
	local env = engine.new_script_env(nil)
	env.__templates_mode = true
	local chunk = assert(loadfile(paths.ASSETS .. "/ui/templates.lua"))
	setfenv(chunk, env)
	local ok, err = pcall(chunk)
	if not ok then print("[boot] templates.lua error: " .. tostring(err)) end
end

local function load_autoexec()
	local env = engine.new_script_env(nil)
	local chunk = assert(loadfile(paths.ASSETS .. "/ui/autoexec.lua"))
	setfenv(chunk, env)
	local ok, err = pcall(chunk)
	if not ok then print("[boot] autoexec.lua error: " .. tostring(err)) end
end

-- internal (non-Lua) screens: Title splash and the GameCrimsonland backdrop
local function register_internal_screens()
	screens.registry["Title"] = {
		internal = function(screen)
			screen.props.covers_screen = true
			screen.env.OnUpdate = function(dt)
				if screen.timer > 1.2 then
					timeline.end_event()
				end
			end
			screen.env.OnDraw = function() end
		end,
	}
	screens.registry["GameCrimsonland"] = {
		internal = function(screen)
			screen.props.covers_screen = true
			screen.env.OnUpdate = function(dt) mod.game_call("update", dt) end
			screen.env.OnKeyDown = function(key)
				-- the mod's pause() guards against inactive/ended sessions
				if key == "ESCAPE" then mod.game_call("pause") end
			end
			screen.env.OnDraw = function() end
		end,
	}
	-- In-game pause: no original screen ships (it was C++-side), so build a
	-- minimal one from real comps — that way hit-testing, hover sounds and
	-- click routing work exactly like every other screen.
	screens.registry["GamePause"] = {
		internal = function(screen)
			local function button(name, text, y)
				local c = comps.new("Button", name, screen)
				c._order = #screen.comps + 1
				table.insert(screen.comps, c)
				screen.compmap[name] = c
				comps.set(c, "inherit", { "WideButton" })
				comps.set(c, "position", { 0.5, y })
				comps.set(c, "align", { "CENTER" })
				comps.set(c, "button.text", { text })
			end
			button("Resume", "Resume", 0.46)
			button("QuitToMenu", "Quit to Menu", 0.58)
			screen.env.OnKeyDown = function(key)
				if key == "ESCAPE" then mod.game_call("unpause") end
			end
			screen.env.OnClick = function(name)
				if name == "Resume" then
					mod.game_call("unpause")
				elseif name == "QuitToMenu" then
					mod.game_call("to_main_menu")
				end
			end
			screen.env.OnDraw = function() end
		end,
	}
end

-- C++-registered screens that have Lua layouts in the pak
local BUILTIN_SCREENS = {
	"SelectChapter", "PlayMenuQuests", "PlayMenuCustomQuests", "PlayMenuSurvival",
	"HighScores", "Statistics", "Weapons", "Perks", "PickAPerk",
	"LevelCompleted", "LevelFailed", "SurvivalOver", "ScoreAnalyzer",
	"TrialUnlock", "UnlockOptions", "KeepDisplaySettings", "Gembine", "Scene",
	"TerrainTester", "DisplayOptions", "GameplayOptions", "ControlPanel",
	"Credits", "WeaponDetails", "PerkDetails", "WeaponUnlocked", "PerkUnlocked",
	"GameModeUnlocked",
}

local EXPLICIT_SCREENS = {
	Loading = "ui/fw/loading.lua",
	Timeline = "ui/fw/timeline.lua",
	TimelineTransition = "ui/fw/timeline-transition.lua",
	ScreenTransition = "ui/fw/screen-transition.lua",
	ScreenBrowser = "ui/fw/screen-browser.lua",
	Achievements = "ui/fw/achievements.lua",
}

local function register_builtin_screens()
	for _, name in ipairs(BUILTIN_SCREENS) do
		if not screens.registry[name] then
			screens.register_builtin(name)
		end
	end
	for name, path in pairs(EXPLICIT_SCREENS) do
		if not screens.registry[name] then
			screens.register(name, path)
		end
	end
end

-- special draw for internal screens, called from love.draw before comps
local function draw_internal(screen)
	if screen.name == "Title" then
		love.graphics.setColor(0, 0, 0, 1)
		love.graphics.rectangle("fill", 0, 0, screens.WIDTH, screens.HEIGHT)
		local img = assets.image("10tons/10tons-logo-white.png")
		if img then
			love.graphics.setColor(1, 1, 1, math.min(1, screen.timer * 2))
			love.graphics.draw(img, (screens.WIDTH - img:getWidth()) / 2,
				(screens.HEIGHT - img:getHeight()) / 2)
		end
	elseif screen.name == "GameCrimsonland" then
		-- gameplay when a session is active, menu backdrop otherwise
		mod.game_call("draw")
	elseif screen.name == "GamePause" then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", 0, 0, screens.WIDTH, screens.HEIGHT)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.printf("PAUSED", 0, screens.HEIGHT * 0.3, screens.WIDTH, "center")
	end
end
engine.draw_internal = draw_internal

-- -------------------------------------------------------------- love glue

local canvas = nil
local canvas_scale, canvas_ox, canvas_oy = 1, 0, 0
local render_scale = 0 -- reference unit -> device pixel

--- Size the letterboxed viewport and (re)allocate the render target.
--
-- Everything above this line draws in 960x640 reference units. What changes
-- with the display is only how many device pixels one reference unit is worth:
-- window scale (letterbox fit) x OS backing scale (2 on retina). Allocating
-- the canvas with that as its dpiscale makes LÖVE rasterize at the exact final
-- pixel count while still accepting reference coordinates — so the blit below
-- is 1:1 and nothing is ever resampled.
local function compute_viewport()
	local ww, wh = love.graphics.getDimensions() -- window units, not pixels
	canvas_scale = math.min(ww / screens.WIDTH, wh / screens.HEIGHT)
	canvas_ox = (ww - screens.WIDTH * canvas_scale) / 2
	canvas_oy = (wh - screens.HEIGHT * canvas_scale) / 2

	local wanted = canvas_scale * love.window.getDPIScale()
	if math.abs(wanted - render_scale) > 0.01 then
		render_scale = wanted
		canvas = love.graphics.newCanvas(screens.WIDTH, screens.HEIGHT,
			{ dpiscale = render_scale })
		font.set_render_scale(render_scale) -- rasterize glyphs at device size
	end
end

--- Device pixels per reference unit, for anything that rasterizes its own art.
function engine.render_scale()
	return render_scale
end

function engine.to_reference(x, y)
	return (x - canvas_ox) / canvas_scale, (y - canvas_oy) / canvas_scale
end

function engine.get_canvas()
	return canvas
end

function engine.start()
	-- Lua 5.1 compat: scripts use math.mod
	math.mod = math.fmod

	love.load = function()
		love.graphics.setDefaultFilter("linear", "linear", 4)
		compute_viewport()
		-- above 1x the 1080p art set is worth its VRAM; below it only costs
		assets.hires = render_scale > 1.05

		if mod.current == nil then mod.select("vanilla") end
		if mod.current.save.load then mod.current.save.load() end
		load_templates()
		load_autoexec()
		register_internal_screens()
		register_builtin_screens()

		timeline.load()
		timeline.begin(timeline.order[1]) -- "Title"
	end

	love.quit = function()
		if mod.current and mod.current.save.flush then mod.current.save.flush() end
		return false
	end

	love.update = function(dt)
		dt = math.min(dt, 0.1) -- clamp huge frames
		audio.update(dt)
		timeline.update(dt)
		screens.update(dt)
		fx.update(dt)
	end

	love.draw = function()
		love.graphics.setCanvas(canvas)
		love.graphics.clear(0, 0, 0, 1)
		-- internal screens paint under their comps
		for _, s in ipairs(screens.stack) do
			if screens.registry[s.name] and screens.registry[s.name].internal then
				draw_internal(s)
			end
		end
		screens.draw()
		fx.draw() -- screen-space emitters (menu shell casings, unlock bursts)
		love.graphics.setCanvas()
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(canvas, canvas_ox, canvas_oy, 0, canvas_scale, canvas_scale)
	end

	love.resize = compute_viewport

	love.keypressed = function(key)
		if key == "f1" then
			engine.debug = not engine.debug
			return
		end
		screens.keypressed(key)
	end

	love.mousemoved = function(x, y) screens.mousemoved(x, y) end
	love.mousepressed = function(x, y, button) screens.mousepressed(x, y, button) end

	-- debug overlay drawn last
	local base_draw = love.draw
	love.draw = function()
		base_draw()
		if engine.debug then
			love.graphics.setColor(0, 1, 0, 1)
			local lines = { "stack:" }
			for i, s in ipairs(screens.stack) do
				lines[#lines + 1] = string.format("  %d %s phase=%.2f timer=%.1f%s",
					i, s.name, s.phase, s.timer, s.leaving and " LEAVING" or "")
			end
			love.graphics.print(table.concat(lines, "\n"), 10, 10)
		end
	end
end

return engine

-- Smoke test: menus -> chapter 1 -> quest 1.1 -> observe gameplay -> abort.
-- Pure data; executed by src/test/harness.lua.

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_1" },
	{ t = 7.0, click = "Quest_1" },
	{ t = 21.0, key = "escape" }, -- opens the pause screen
	{ t = 22.0, click = "QuitToMenu" },
	captures = { 2.0, 6.0, 10.0, 14.0, 18.0, 21.5, 23.5 },
}

-- Smoke test for the allweapons mod (run it with MOD=allweapons, or the
-- picker never appears and the chapter click bounces off a locked button):
--
--   make test MOD=allweapons SCENARIO=allweapons-smoke
--
-- Proves both of the mod's rules at once. Chapter 4 is locked on a fresh
-- vanilla profile, so reaching its quest 7 at all is the unlock rule; the
-- weapon gallery opening instead of the game is the picker rule; and the
-- capture after the plate click must show a running quest — with the picked
-- weapon in the HUD, which is what the screenshot beside it is for.

return {
	{ t = 2.5, click = "PlayMenu" },
	{ t = 4.0, click = "Play_Quests" },
	{ t = 5.5, click = "Chapter_4" },
	{ t = 7.0, click = "Quest_7" }, -- holds the launch, pushes the picker
	{ t = 9.0, click = "Weapon_20" }, -- and this starts the run with it
	{ t = 16.0, key = "escape" },
	{ t = 17.0, click = "QuitToMenu" },
	captures = { 6.0, 8.5, 10.5, 15.0, 18.0 },
}

-- Rush mode: menus -> survival submenu -> Rush. Exercises the mode
-- selection table and the no-drops/no-perks rules; a passive player is
-- overrun by the alien wall and must land on the SurvivalOver screen.

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Survival" },
	{ t = 4.6, click = "Play_RUSH" },
	captures = { 8.0, 25.0, 40.0 },
}

-- Fast dev iteration: same flow as quest-smoke but compressed (~10s),
-- to minimize the window's interference with whoever is at the machine.

return {
	{ t = 2.2, click = "PlayMenu" },
	{ t = 3.4, click = "Play_Quests" },
	{ t = 4.6, click = "Chapter_1" },
	{ t = 5.8, click = "Quest_1" },
	{ t = 11.0, key = "escape" },
	captures = { 7.0, 10.0 },
}

--!strict
-- Index / Codex completion milestones. Claimed from the Index menu.
--
-- Each zone (fish) and each treasure category has milestones at the listed percentages.
-- Rewards: coins × coinScale[zone index] (treasure categories use their deepest pool zone)
-- and, at 100%, a permanent luck bonus. Global milestones cover the whole Index.
-- Event exclusives count toward the category/global totals but not toward zone totals.

export type Milestone = {
	percent: number,
	coins: number,
	luck: number?, -- permanent luck bonus (0.01 = +1%)
}

return {
	zoneMilestones = {
		{ percent = 25, coins = 150 },
		{ percent = 50, coins = 400 },
		{ percent = 75, coins = 1000 },
		{ percent = 100, coins = 3000, luck = 0.02 },
	} :: { Milestone },
	categoryMilestones = {
		{ percent = 25, coins = 150 },
		{ percent = 50, coins = 400 },
		{ percent = 75, coins = 1000 },
		{ percent = 100, coins = 3000, luck = 0.02 },
	} :: { Milestone },
	globalMilestones = {
		{ percent = 10, coins = 500 },
		{ percent = 25, coins = 2000 },
		{ percent = 50, coins = 10000, luck = 0.03 },
		{ percent = 75, coins = 50000, luck = 0.04 },
		{ percent = 100, coins = 250000, luck = 0.1 },
	} :: { Milestone },
	coinScale = { 1, 4, 15, 60, 240, 1000 },
	-- Secret entries are counted but hidden until found. Set false to exclude them from %.
	secretsCountTowardCompletion = true,
}

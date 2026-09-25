--!strict
-- 7-day login streak calendar. Claim once per UTC day. Missing a full day resets the streak
-- to day 1; after day 7 the calendar loops back to day 1 (the streak counter keeps growing).
--
-- reward fields: coins (× coinScale of your deepest zone), boost (personal boost id from
-- Game.Boosts), consumable ({ key, amount }) and tokens (only once you've rebirthed).

export type DailyReward = {
	day: number,
	label: string,
	coins: number?,
	boost: string?,
	consumable: { key: string, amount: number }?,
	tokens: number?,
}

local rewards: { DailyReward } = {
	{ day = 1, label = "Coins", coins = 150 },
	{ day = 2, label = "Coins", coins = 300 },
	{ day = 3, label = "Luck Boost", boost = "Luck", coins = 200 },
	{ day = 4, label = "Coins + Oxygen Refill", coins = 600, consumable = { key = "OxygenRefill", amount = 1 } },
	{ day = 5, label = "Sell Boost", boost = "Sell", coins = 400 },
	{ day = 6, label = "Coins + Hull Repair", coins = 1000, consumable = { key = "HullRepair", amount = 1 } },
	{ day = 7, label = "Jackpot!", coins = 2500, boost = "Luck", consumable = { key = "CargoInsurance", amount = 1 }, tokens = 1 },
}

return {
	rewards = rewards,
	coinScale = { 1, 4, 15, 60, 240, 1000 },
}

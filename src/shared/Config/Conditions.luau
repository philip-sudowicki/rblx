--!strict
-- Treasure condition, rolled at salvage time.
-- Flawless uses an exact 1-in-N roll (× luck^Game.Luck.ConditionExponent) checked first; the
-- other conditions are picked by weight, and luck boosts the weights of Intact and Pristine.

export type Condition = {
	id: string,
	index: number,
	name: string,
	multiplier: number,
	weight: number,
	odds: number?, -- exact roll instead of weight
	luckBoosted: boolean,
	color: Color3,
}

local list: { Condition } = {
	{
		id = "Corroded",
		index = 1,
		name = "Corroded",
		multiplier = 0.5,
		weight = 35,
		luckBoosted = false,
		color = Color3.fromRGB(150, 130, 100),
	},
	{
		id = "Worn",
		index = 2,
		name = "Worn",
		multiplier = 1,
		weight = 40,
		luckBoosted = false,
		color = Color3.fromRGB(200, 200, 200),
	},
	{
		id = "Intact",
		index = 3,
		name = "Intact",
		multiplier = 2,
		weight = 18,
		luckBoosted = true,
		color = Color3.fromRGB(110, 230, 140),
	},
	{
		id = "Pristine",
		index = 4,
		name = "Pristine",
		multiplier = 5,
		weight = 6.9,
		luckBoosted = true,
		color = Color3.fromRGB(110, 200, 255),
	},
	{
		id = "Flawless",
		index = 5,
		name = "Flawless",
		multiplier = 15,
		weight = 0,
		odds = 1000,
		luckBoosted = true,
		color = Color3.fromRGB(255, 230, 120),
	},
}

local byId: { [string]: Condition } = {}
for _, condition in list do
	byId[condition.id] = condition
end

return {
	list = list,
	byId = byId,
}

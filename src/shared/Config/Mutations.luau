--!strict
-- Fish mutations. Rolled separately at catch time, rarest first; at most one per catch.
-- Chance = 1/odds × luck^Game.Luck.MutationExponent × event multiplier.
-- eventOnly mutations can only roll while one of the listed events is active.

export type Mutation = {
	id: string,
	name: string,
	odds: number,
	multiplier: number,
	color: Color3,
	visual: string, -- ModelBuilder visual treatment
	eventOnly: { string }?,
	order: number, -- display order (1 = most common)
}

local list: { Mutation } = {
	{
		id = "Shiny",
		name = "Shiny",
		odds = 50,
		multiplier = 2,
		color = Color3.fromRGB(255, 255, 210),
		visual = "sparkle",
		order = 1,
	},
	{
		id = "Albino",
		name = "Albino",
		odds = 200,
		multiplier = 3,
		color = Color3.fromRGB(255, 225, 235),
		visual = "albino",
		order = 2,
	},
	{
		id = "Glowing",
		name = "Glowing",
		odds = 500,
		multiplier = 5,
		color = Color3.fromRGB(120, 255, 220),
		visual = "glow",
		order = 3,
	},
	{
		id = "Golden",
		name = "Golden",
		odds = 2000,
		multiplier = 10,
		color = Color3.fromRGB(255, 205, 60),
		visual = "golden",
		order = 4,
	},
	{
		id = "Shadow",
		name = "Shadow",
		odds = 5000,
		multiplier = 20,
		color = Color3.fromRGB(140, 110, 190),
		visual = "shadow",
		order = 5,
	},
	{
		id = "Prismatic",
		name = "Prismatic",
		odds = 25000,
		multiplier = 50,
		color = Color3.fromRGB(255, 140, 240),
		visual = "prismatic",
		order = 6,
	},
	{
		id = "Voidtouched",
		name = "Voidtouched",
		odds = 5000,
		multiplier = 100,
		color = Color3.fromRGB(60, 255, 255),
		visual = "void",
		eventOnly = { "BloodMoon" },
		order = 7,
	},
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
end

-- Roll order: rarest (largest odds) first so a lucky roll never gets shadowed by Shiny.
local rollOrder = table.clone(list)
table.sort(rollOrder, function(a, b)
	if a.odds == b.odds then
		return a.multiplier > b.multiplier
	end
	return a.odds > b.odds
end)

return {
	list = list,
	byId = byId,
	rollOrder = rollOrder,
}

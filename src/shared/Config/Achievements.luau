--!strict
-- Achievements are awarded automatically when a stat reaches its target.
-- stat: a PlayerStats key, or "Rebirths" / "SetsCompleted" / "IndexPercent" (computed).
-- reward: skin id and/or coins (coins × coinScale of your deepest zone when unlocked).

export type AchievementDef = {
	id: string,
	name: string,
	desc: string,
	stat: string,
	target: number,
	skin: string?,
	coins: number?,
}

export type Achievement = AchievementDef & { order: number }

local defs: { AchievementDef } = {
	{ id = "FirstCatch", name = "First Catch", desc = "Catch your first fish.", stat = "FishCaught", target = 1, coins = 50 },
	{ id = "Angler50", name = "Getting Hooked", desc = "Catch 50 fish.", stat = "FishCaught", target = 50, coins = 300 },
	{ id = "Angler100", name = "Reef Regular", desc = "Catch 100 fish.", stat = "FishCaught", target = 100, skin = "CoralCruiser" },
	{ id = "Angler1000", name = "Master Angler", desc = "Catch 1,000 fish.", stat = "FishCaught", target = 1000, coins = 5000 },
	{ id = "Angler10000", name = "Living Legend", desc = "Catch 10,000 fish.", stat = "FishCaught", target = 10000, coins = 50000 },
	{ id = "FirstSalvage", name = "Finders Keepers", desc = "Salvage your first treasure.", stat = "TreasureSalvaged", target = 1, coins = 50 },
	{ id = "Salvager100", name = "Scrap Collector", desc = "Salvage 100 treasures.", stat = "TreasureSalvaged", target = 100, skin = "Salvager" },
	{ id = "Salvager1000", name = "Treasure Hunter", desc = "Salvage 1,000 treasures.", stat = "TreasureSalvaged", target = 1000, coins = 8000 },
	{ id = "Perfect100", name = "Precision Diver", desc = "Land 100 PERFECT catches.", stat = "PerfectCatches", target = 100, skin = "Precision" },
	{ id = "Depth1000", name = "Into the Dark", desc = "Reach 1,000m.", stat = "DeepestMeters", target = 1000, coins = 500 },
	{ id = "Depth3000", name = "Abyss Walker", desc = "Reach the Wreck Graveyard (3,000m).", stat = "DeepestMeters", target = 3000, skin = "AbyssWalker" },
	{ id = "Depth6000", name = "Trench Crawler", desc = "Reach the Hadal Maw (6,000m).", stat = "DeepestMeters", target = 6000, skin = "TrenchCrawler" },
	{ id = "Rift", name = "Through the Seal", desc = "Enter The Rift.", stat = "RiftVisits", target = 1, skin = "RiftRunner" },
	{ id = "Golden", name = "Midas Touch", desc = "Catch a Golden fish.", stat = "GoldenCatches", target = 1, skin = "GoldenHauler" },
	{ id = "Mutant25", name = "Mutant Collector", desc = "Catch 25 mutated fish.", stat = "MutatedCatches", target = 25, coins = 1500 },
	{ id = "Mythic", name = "Mythbreaker", desc = "Catch a Mythic or rarer fish.", stat = "MythicPlus", target = 1, skin = "Mythbreaker" },
	{ id = "Secret", name = "Legend of the Deep", desc = "Find a Secret.", stat = "Secrets", target = 1, skin = "Legend" },
	{ id = "Sets3", name = "The Curator", desc = "Complete 3 collection sets.", stat = "SetsCompleted", target = 3, skin = "Curator" },
	{ id = "Events10", name = "Festival Goer", desc = "Collect 10 event-exclusive items.", stat = "EventItems", target = 10, skin = "Festival" },
	{ id = "Rebirth1", name = "Resurfaced", desc = "Resurface for the first time.", stat = "Rebirths", target = 1, coins = 2000 },
	{ id = "Rebirth5", name = "Tidebreaker", desc = "Resurface 5 times.", stat = "Rebirths", target = 5, coins = 20000 },
	{ id = "Dives100", name = "Frequent Diver", desc = "Surface safely from 100 dives.", stat = "CleanDives", target = 100, coins = 3000 },
	{ id = "Index50", name = "Marine Biologist", desc = "Discover 50% of the Index.", stat = "IndexPercent", target = 50, coins = 4000 },
	{ id = "Index100", name = "Walking Encyclopedia", desc = "Discover 100% of the Index.", stat = "IndexPercent", target = 100, coins = 100000 },
}

local byId: { [string]: Achievement } = {}
local list: { Achievement } = {}
for index, def in defs do
	local achievement: Achievement = table.clone(def) :: any
	achievement.order = index
	table.insert(list, achievement)
	byId[achievement.id] = achievement
end

return {
	list = list,
	byId = byId,
	coinScale = { 1, 2, 4, 8, 15, 30, 60, 120, 240, 1000 },
}

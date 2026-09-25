--!strict
-- Daily (3) and weekly (3) quests.
--
-- Quests are drawn from these templates when the day/week rolls over (UTC). The player's
-- progress tier is the deepest zone index they have ever reached (1..10); each template lists
-- a target per tier so quests stay relevant from minute one to hour one hundred.
--
-- kind:
--   catch            catch n fish
--   catchRarity      catch n fish of `rarity` or rarer
--   catchMutated     catch n fish with any mutation
--   catchZone        catch n fish in your deepest zone (or deeper)
--   perfect          land n PERFECT catches
--   salvage          salvage n treasures
--   salvageCondition salvage n treasures of `condition` or better
--   salvageCategory  salvage n treasures of `category`
--   earn             earn n coins from selling (n is multiplied by coinScale)
--   depth            reach n metres in one dive
--   sonar            ping sonar n times
--   cleanDive        finish n dives by surfacing (no blackout)
-- Rewards: coins = reward × coinScale[tier] (× weeklyRewardMultiplier for weekly quests).

export type QuestTier = {
	n: number,
	rarity: string?,
	category: string?,
	condition: string?,
}

export type QuestTemplate = {
	id: string,
	kind: string,
	text: string,
	reward: number,
	daily: { QuestTier }?,
	weekly: { QuestTier }?,
	weight: number,
}

local templates: { QuestTemplate } = {
	{
		id = "CatchFish",
		kind = "catch",
		text = "Catch {n} fish",
		reward = 120,
		weight = 3,
		daily = { { n = 12 }, { n = 12 }, { n = 15 }, { n = 15 }, { n = 18 }, { n = 18 }, { n = 20 }, { n = 20 }, { n = 20 }, { n = 20 } },
		weekly = { { n = 120 }, { n = 120 }, { n = 150 }, { n = 150 }, { n = 180 }, { n = 180 }, { n = 200 }, { n = 200 }, { n = 200 }, { n = 200 } },
	},
	{
		id = "CatchRarity",
		kind = "catchRarity",
		text = "Catch {n} {rarity}+ fish",
		reward = 220,
		weight = 3,
		daily = {
			{ n = 3, rarity = "Rare" },
			{ n = 3, rarity = "Rare" },
			{ n = 4, rarity = "Rare" },
			{ n = 4, rarity = "Rare" },
			{ n = 2, rarity = "Epic" },
			{ n = 2, rarity = "Epic" },
			{ n = 3, rarity = "Epic" },
			{ n = 3, rarity = "Epic" },
			{ n = 5, rarity = "Epic" },
			{ n = 1, rarity = "Legendary" },
		},
		weekly = {
			{ n = 3, rarity = "Epic" },
			{ n = 3, rarity = "Epic" },
			{ n = 6, rarity = "Epic" },
			{ n = 6, rarity = "Epic" },
			{ n = 1, rarity = "Legendary" },
			{ n = 1, rarity = "Legendary" },
			{ n = 2, rarity = "Legendary" },
			{ n = 2, rarity = "Legendary" },
			{ n = 3, rarity = "Legendary" },
			{ n = 1, rarity = "Mythic" },
		},
	},
	{
		id = "CatchMutated",
		kind = "catchMutated",
		text = "Catch {n} mutated fish",
		reward = 200,
		weight = 2,
		daily = { { n = 1 }, { n = 1 }, { n = 1 }, { n = 1 }, { n = 2 }, { n = 2 }, { n = 2 }, { n = 2 }, { n = 3 }, { n = 3 } },
		weekly = { { n = 5 }, { n = 5 }, { n = 6 }, { n = 6 }, { n = 8 }, { n = 8 }, { n = 10 }, { n = 10 }, { n = 12 }, { n = 12 } },
	},
	{
		id = "CatchZone",
		kind = "catchZone",
		text = "Catch {n} fish in the {zone} or deeper",
		reward = 160,
		weight = 2,
		daily = { { n = 10 }, { n = 10 }, { n = 12 }, { n = 12 }, { n = 14 }, { n = 14 }, { n = 15 }, { n = 15 }, { n = 15 }, { n = 15 } },
		weekly = { { n = 80 }, { n = 80 }, { n = 100 }, { n = 100 }, { n = 110 }, { n = 110 }, { n = 120 }, { n = 120 }, { n = 120 }, { n = 120 } },
	},
	{
		id = "Perfect",
		kind = "perfect",
		text = "Land {n} PERFECT catches",
		reward = 180,
		weight = 2,
		daily = { { n = 3 }, { n = 3 }, { n = 4 }, { n = 4 }, { n = 5 }, { n = 5 }, { n = 6 }, { n = 6 }, { n = 6 }, { n = 6 } },
		weekly = { { n = 25 }, { n = 25 }, { n = 30 }, { n = 30 }, { n = 35 }, { n = 35 }, { n = 40 }, { n = 40 }, { n = 40 }, { n = 40 } },
	},
	{
		id = "Salvage",
		kind = "salvage",
		text = "Salvage {n} treasures",
		reward = 140,
		weight = 3,
		daily = { { n = 5 }, { n = 5 }, { n = 6 }, { n = 6 }, { n = 8 }, { n = 8 }, { n = 8 }, { n = 8 }, { n = 10 }, { n = 10 } },
		weekly = { { n = 40 }, { n = 40 }, { n = 50 }, { n = 50 }, { n = 60 }, { n = 60 }, { n = 70 }, { n = 70 }, { n = 80 }, { n = 80 } },
	},
	{
		id = "SalvageCondition",
		kind = "salvageCondition",
		text = "Salvage {n} {condition}+ treasure",
		reward = 240,
		weight = 2,
		daily = {
			{ n = 2, condition = "Intact" },
			{ n = 2, condition = "Intact" },
			{ n = 3, condition = "Intact" },
			{ n = 3, condition = "Intact" },
			{ n = 1, condition = "Pristine" },
			{ n = 1, condition = "Pristine" },
			{ n = 1, condition = "Pristine" },
			{ n = 1, condition = "Pristine" },
			{ n = 2, condition = "Pristine" },
			{ n = 2, condition = "Pristine" },
		},
		weekly = {
			{ n = 3, condition = "Pristine" },
			{ n = 3, condition = "Pristine" },
			{ n = 4, condition = "Pristine" },
			{ n = 4, condition = "Pristine" },
			{ n = 5, condition = "Pristine" },
			{ n = 5, condition = "Pristine" },
			{ n = 6, condition = "Pristine" },
			{ n = 6, condition = "Pristine" },
			{ n = 8, condition = "Pristine" },
			{ n = 8, condition = "Pristine" },
		},
	},
	{
		id = "SalvageRelics",
		kind = "salvageCategory",
		text = "Salvage {n} {category}",
		reward = 180,
		weight = 1,
		daily = {
			{ n = 2, category = "Relics" },
			{ n = 2, category = "Relics" },
			{ n = 2, category = "Relics" },
			{ n = 2, category = "Relics" },
			{ n = 2, category = "Cursed" },
			{ n = 2, category = "Cursed" },
			{ n = 2, category = "Tech" },
			{ n = 2, category = "Tech" },
			{ n = 3, category = "Tech" },
			{ n = 3, category = "Cursed" },
		},
		weekly = {
			{ n = 10, category = "Jewelry" },
			{ n = 10, category = "Jewelry" },
			{ n = 12, category = "Salvage" },
			{ n = 12, category = "Salvage" },
			{ n = 10, category = "Cursed" },
			{ n = 10, category = "Cursed" },
			{ n = 12, category = "Tech" },
			{ n = 12, category = "Tech" },
			{ n = 15, category = "Tech" },
			{ n = 15, category = "Cursed" },
		},
	},
	{
		id = "Earn",
		kind = "earn",
		text = "Earn {n} coins from selling",
		reward = 150,
		weight = 2,
		daily = { { n = 600 }, { n = 600 }, { n = 700 }, { n = 700 }, { n = 800 }, { n = 800 }, { n = 900 }, { n = 900 }, { n = 1000 }, { n = 1000 } },
		weekly = { { n = 6000 }, { n = 6000 }, { n = 7000 }, { n = 7000 }, { n = 8000 }, { n = 8000 }, { n = 9000 }, { n = 9000 }, { n = 10000 }, { n = 10000 } },
	},
	{
		id = "Sonar",
		kind = "sonar",
		text = "Ping your sonar {n} times",
		reward = 90,
		weight = 1,
		daily = { { n = 8 }, { n = 8 }, { n = 10 }, { n = 10 }, { n = 12 }, { n = 12 }, { n = 12 }, { n = 12 }, { n = 12 }, { n = 12 } },
		weekly = nil,
	},
	{
		id = "CleanDive",
		kind = "cleanDive",
		text = "Surface safely from {n} dives",
		reward = 130,
		weight = 2,
		daily = { { n = 4 }, { n = 4 }, { n = 5 }, { n = 5 }, { n = 5 }, { n = 5 }, { n = 6 }, { n = 6 }, { n = 6 }, { n = 6 } },
		weekly = { { n = 30 }, { n = 30 }, { n = 35 }, { n = 35 }, { n = 40 }, { n = 40 }, { n = 40 }, { n = 40 }, { n = 40 }, { n = 40 } },
	},
}

local byId: { [string]: QuestTemplate } = {}
for _, template in templates do
	byId[template.id] = template
end

return {
	templates = templates,
	byId = byId,
	dailyCount = 3,
	weeklyCount = 3,
	weeklyRewardMultiplier = 6,
	weeklyTokens = 1, -- extra rebirth token per weekly quest once you have rebirthed
	weeklyBoost = "Luck", -- personal boost granted by each weekly quest
	coinScale = { 1, 2, 4, 8, 15, 30, 60, 120, 240, 1000 },
	-- Weekly quests reset Monday 00:00 UTC
	weekStartOffsetDays = 3, -- unix day 0 was a Thursday; +3 makes weeks start on Monday
}

--!strict
-- Quest generation, progress rules and display text. Pure (randomness passed in) so the server
-- and unit tests share one implementation; the client uses text() and the progress rules.

local Config = script.Parent.Parent.Config
local Quests = require(Config.Quests)
local Rarities = require(Config.Rarities)
local Conditions = require(Config.Conditions)
local Treasure = require(Config.Treasure)
local TreasureCategories = require(Config.TreasureCategories)
local Zones = require(Config.Zones)
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Types)

local QuestMath = {}

export type Period = "daily" | "weekly"

local function tiersFor(template: Quests.QuestTemplate, period: Period): { Quests.QuestTier }?
	return if period == "daily" then template.daily else template.weekly
end

-- Draws `count` different quests (weighted, without replacement) for a progress tier (deepest
-- zone index 1..6).
function QuestMath.generate(rng: () -> number, period: Period, tier: number, count: number, rebirths: number): { Types.QuestState }
	local candidates: { Quests.QuestTemplate } = {}
	for _, template in Quests.templates do
		if tiersFor(template, period) then
			table.insert(candidates, template)
		end
	end
	local scale = Quests.coinScale[math.clamp(tier, 1, #Quests.coinScale)]
	local out: { Types.QuestState } = {}
	for _ = 1, math.min(count, #candidates) do
		local total = 0
		for _, template in candidates do
			total += template.weight
		end
		local roll = rng() * total
		local pick = #candidates
		for index, template in candidates do
			roll -= template.weight
			if roll < 0 then
				pick = index
				break
			end
		end
		local template = table.remove(candidates, pick) :: Quests.QuestTemplate
		local tiers = tiersFor(template, period) :: { Quests.QuestTier }
		local spec = tiers[math.clamp(tier, 1, #tiers)]
		local quest: Types.QuestState = {
			id = template.id,
			target = if template.kind == "earn" then spec.n * scale else spec.n,
			progress = 0,
			claimed = false,
			reward = template.reward * scale * (if period == "weekly" then Quests.weeklyRewardMultiplier else 1),
		}
		if spec.rarity then
			quest.rarity = Rarities.byId[spec.rarity].index
		end
		if spec.condition then
			quest.condition = Conditions.byId[spec.condition].index
		end
		if spec.category then
			quest.category = spec.category
		end
		if template.kind == "catchZone" then
			quest.zone = math.clamp(tier, 1, Zones.count)
		end
		if period == "weekly" then
			quest.boost = Quests.weeklyBoost
			if rebirths > 0 then
				quest.tokens = Quests.weeklyTokens
			end
		end
		table.insert(out, quest)
	end
	return out
end

function QuestMath.kind(quest: Types.QuestState): string
	local template = Quests.byId[quest.id]
	return if template then template.kind else ""
end

-- How far an obtained fish / treasure advances a quest (0 or 1).
function QuestMath.itemProgress(quest: Types.QuestState, item: Types.Item, zoneIndex: number): number
	local kind = QuestMath.kind(quest)
	if item.k == "F" then
		if kind == "catch" then
			return 1
		elseif kind == "catchRarity" then
			return if item.r >= (quest.rarity or 1) then 1 else 0
		elseif kind == "catchMutated" then
			return if item.m then 1 else 0
		elseif kind == "catchZone" then
			return if zoneIndex >= (quest.zone or 1) then 1 else 0
		elseif kind == "perfect" then
			return if item.p then 1 else 0
		end
	elseif item.k == "T" then
		if kind == "salvage" then
			return 1
		elseif kind == "salvageCondition" then
			local condition = if item.c then Conditions.byId[item.c] else nil
			return if condition and condition.index >= (quest.condition or 1) then 1 else 0
		elseif kind == "salvageCategory" then
			local def = Treasure.byId[item.i]
			return if def and def.category == quest.category then 1 else 0
		end
	end
	return 0
end

function QuestMath.complete(quest: Types.QuestState): boolean
	return quest.progress >= quest.target
end

function QuestMath.text(quest: Types.QuestState): string
	local template = Quests.byId[quest.id]
	if not template then
		return quest.id
	end
	local text = template.text
	text = (text:gsub("{n}", Format.commas(quest.target)))
	if quest.rarity and Rarities.list[quest.rarity] then
		text = (text:gsub("{rarity}", Rarities.list[quest.rarity].name))
	end
	if quest.condition and Conditions.list[quest.condition] then
		text = (text:gsub("{condition}", Conditions.list[quest.condition].name))
	end
	if quest.category and TreasureCategories.byId[quest.category] then
		text = (text:gsub("{category}", TreasureCategories.byId[quest.category].name))
	end
	if quest.zone and Zones.list[quest.zone] then
		text = (text:gsub("{zone}", Zones.list[quest.zone].name))
	end
	return text
end

return QuestMath

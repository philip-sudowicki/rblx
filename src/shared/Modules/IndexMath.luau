--!strict
-- Index (codex) completion maths and milestone keys, shared by server (rewards) and client (UI).
--
-- Milestone keys:  "Z<zoneIndex>_<percent>"   fish of a zone (no event fish)
--                  "C_<categoryId>_<percent>" treasure of a category (event items included)
--                  "G_<percent>"              whole Index

local Config = script.Parent.Parent.Config
local Fish = require(Config.Fish)
local Treasure = require(Config.Treasure)
local Zones = require(Config.Zones)
local Rarities = require(Config.Rarities)
local TreasureCategories = require(Config.TreasureCategories)
local IndexRewards = require(Config.IndexRewards)

export type Progress = { found: number, total: number }
export type Completion = {
	zones: { [number]: Progress },
	categories: { [string]: Progress },
	global: Progress,
}
export type Discovered = { Fish: { [string]: any }, Treasure: { [string]: any } }

local IndexMath = {}

local function counts(rarityId: string): boolean
	if IndexRewards.secretsCountTowardCompletion then
		return true
	end
	return not Rarities.byId[rarityId].hidden
end

function IndexMath.completion(discovered: Discovered): Completion
	local zones: { [number]: Progress } = {}
	local categories: { [string]: Progress } = {}
	local global: Progress = { found = 0, total = 0 }
	for _, zone in Zones.list do
		zones[zone.index] = { found = 0, total = 0 }
	end
	for _, category in TreasureCategories.list do
		categories[category.id] = { found = 0, total = 0 }
	end
	for _, fish in Fish.list do
		if counts(fish.rarity) then
			local found = discovered.Fish[fish.id] ~= nil
			global.total += 1
			if found then
				global.found += 1
			end
			if fish.zone then
				local progress = zones[Zones.byId[fish.zone].index]
				progress.total += 1
				if found then
					progress.found += 1
				end
			end
		end
	end
	for _, treasure in Treasure.list do
		if counts(treasure.rarity) then
			local found = discovered.Treasure[treasure.id] ~= nil
			global.total += 1
			if found then
				global.found += 1
			end
			local progress = categories[treasure.category]
			progress.total += 1
			if found then
				progress.found += 1
			end
		end
	end
	return { zones = zones, categories = categories, global = global }
end

function IndexMath.percent(progress: Progress): number
	if progress.total <= 0 then
		return 0
	end
	return math.floor(progress.found / progress.total * 1000 + 0.5) / 10
end

export type MilestoneInfo = {
	key: string,
	label: string,
	percent: number,
	coins: number,
	luck: number,
	scaleIndex: number, -- coinScale index used for the coin reward
	reached: boolean,
}

local function categoryScaleIndex(categoryId: string): number
	local deepest = 1
	for _, treasure in Treasure.list do
		if treasure.category == categoryId and treasure.zone then
			deepest = math.max(deepest, Zones.byId[treasure.zone].index)
		end
	end
	-- Rewards scale with the middle of the category's pool, not the very bottom
	return math.max(1, math.ceil(deepest / 2))
end

function IndexMath.milestones(completion: Completion): { MilestoneInfo }
	local out: { MilestoneInfo } = {}
	for _, zone in Zones.list do
		local pct = IndexMath.percent(completion.zones[zone.index])
		for _, m in IndexRewards.zoneMilestones do
			table.insert(out, {
				key = string.format("Z%d_%d", zone.index, m.percent),
				label = string.format("%s %d%%", zone.name, m.percent),
				percent = m.percent,
				coins = m.coins,
				luck = m.luck or 0,
				scaleIndex = zone.index,
				reached = pct >= m.percent,
			})
		end
	end
	for _, category in TreasureCategories.list do
		local pct = IndexMath.percent(completion.categories[category.id])
		for _, m in IndexRewards.categoryMilestones do
			table.insert(out, {
				key = string.format("C_%s_%d", category.id, m.percent),
				label = string.format("%s %d%%", category.name, m.percent),
				percent = m.percent,
				coins = m.coins,
				luck = m.luck or 0,
				scaleIndex = categoryScaleIndex(category.id),
				reached = pct >= m.percent,
			})
		end
	end
	local globalPct = IndexMath.percent(completion.global)
	for _, m in IndexRewards.globalMilestones do
		table.insert(out, {
			key = string.format("G_%d", m.percent),
			label = string.format("Whole Index %d%%", m.percent),
			percent = m.percent,
			coins = m.coins,
			luck = m.luck or 0,
			scaleIndex = 3,
			reached = globalPct >= m.percent,
		})
	end
	return out
end

-- Permanent luck from claimed milestones.
function IndexMath.luckFromClaimed(claimed: { [string]: boolean }): number
	local total = 0
	local function add(key: string, milestone: { luck: number? })
		if claimed[key] and milestone.luck then
			total += milestone.luck
		end
	end
	for _, zone in Zones.list do
		for _, m in IndexRewards.zoneMilestones do
			add(string.format("Z%d_%d", zone.index, m.percent), m)
		end
	end
	for _, category in TreasureCategories.list do
		for _, m in IndexRewards.categoryMilestones do
			add(string.format("C_%s_%d", category.id, m.percent), m)
		end
	end
	for _, m in IndexRewards.globalMilestones do
		add(string.format("G_%d", m.percent), m)
	end
	return total
end

return IndexMath

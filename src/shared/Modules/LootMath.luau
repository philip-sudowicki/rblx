--!strict
-- Pure loot maths. All randomness comes in through an `rng: () -> number` argument so the
-- server can use a fresh Random and tests can use a seeded one.

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Sizes = require(Config.Sizes)
local Conditions = require(Config.Conditions)
local Game = require(Config.Game)

export type Rng = () -> number

export type TierModifiers = {
	luck: number,
	zoneBonus: number,
	tierMult: { [string]: number }?,
}

export type PoolEntry = {
	id: string,
	tier: number,
	weight: number,
}

local LootMath = {}

-- Chance of each rarity tier (index 1..8). Rarer tiers are filled first; if the total would
-- exceed MaxNonCommonChance the least-rare tiers are squeezed so luck never lowers the
-- chance of a rarer tier. Common gets whatever is left.
function LootMath.tierChances(mods: TierModifiers): { number }
	local chances = table.create(Rarities.count, 0)
	local cap = Game.Luck.MaxNonCommonChance
	local total = 0
	for index = Rarities.count, 2, -1 do
		local rarity = Rarities.list[index]
		local mult = mods.luck * mods.zoneBonus
		if mods.tierMult and mods.tierMult[rarity.id] then
			mult *= mods.tierMult[rarity.id]
		end
		local p = math.max(0, mult / rarity.odds)
		p = math.min(p, cap - total)
		chances[index] = p
		total += p
	end
	chances[1] = math.max(0, 1 - total)
	return chances
end

function LootMath.rollTier(roll: number, chances: { number }): number
	local acc = 0
	for index = #chances, 2, -1 do
		acc += chances[index]
		if roll < acc then
			return index
		end
	end
	return 1
end

-- Weighted pick of an entry with exactly `tier`. If the pool has nothing at that tier, falls
-- back to the next lower tier (then upward) so every roll yields something.
function LootMath.pickFromPool(rng: Rng, pool: { PoolEntry }, tier: number): PoolEntry?
	if #pool == 0 then
		return nil
	end
	local function pickAt(t: number): PoolEntry?
		local total = 0
		for _, entry in pool do
			if entry.tier == t then
				total += entry.weight
			end
		end
		if total <= 0 then
			return nil
		end
		local roll = rng() * total
		local last: PoolEntry? = nil
		for _, entry in pool do
			if entry.tier == t then
				roll -= entry.weight
				last = entry
				if roll < 0 then
					return entry
				end
			end
		end
		return last
	end
	for t = tier, 1, -1 do
		local entry = pickAt(t)
		if entry then
			return entry
		end
	end
	for t = tier + 1, Rarities.count do
		local entry = pickAt(t)
		if entry then
			return entry
		end
	end
	return nil
end

export type MutationModifiers = {
	luck: number,
	mult: { [string]: number }?,
	enabled: { [string]: boolean }?, -- event-only mutations currently allowed
}

function LootMath.mutationChance(mutation: Mutations.Mutation, mods: MutationModifiers): number
	if mutation.eventOnly and not (mods.enabled and mods.enabled[mutation.id]) then
		return 0
	end
	local chance = (1 / mutation.odds) * math.max(1, mods.luck) ^ Game.Luck.MutationExponent
	if mods.mult and mods.mult[mutation.id] then
		chance *= mods.mult[mutation.id]
	end
	return math.min(chance, 0.9)
end

-- Rolls at most one mutation, rarest first.
function LootMath.rollMutation(rng: Rng, mods: MutationModifiers): string?
	for _, mutation in Mutations.rollOrder do
		local chance = LootMath.mutationChance(mutation, mods)
		if chance > 0 and rng() < chance then
			return mutation.id
		end
	end
	return nil
end

export type SizeRoll = {
	weight: number,
	colossal: boolean,
	valueMult: number,
	modelScale: number,
	t: number, -- 0..1 position in the weight range (1 for Colossal)
}

local function roundWeight(w: number): number
	if w >= 100 then
		return math.floor(w + 0.5)
	elseif w >= 1 then
		return math.floor(w * 10 + 0.5) / 10
	end
	return math.max(0.01, math.floor(w * 100 + 0.5) / 100)
end

function LootMath.rollSize(rng: Rng, minWeight: number, maxWeight: number, luck: number): SizeRoll
	local luckFactor = math.max(1, luck)
	local colossalChance = (1 / Sizes.colossal.odds) * luckFactor ^ Game.Luck.ColossalExponent
	if rng() < colossalChance then
		local f = Sizes.colossal.weightMin + (Sizes.colossal.weightMax - Sizes.colossal.weightMin) * rng()
		return {
			weight = roundWeight(maxWeight * f),
			colossal = true,
			valueMult = Sizes.colossal.valueMultiplier,
			modelScale = Sizes.colossal.modelScale,
			t = 1,
		}
	end
	local exponent = math.max(Sizes.minExponent, Sizes.curveExponent / luckFactor ^ Sizes.luckExponent)
	local t = rng() ^ exponent
	return {
		weight = roundWeight(minWeight + (maxWeight - minWeight) * t),
		colossal = false,
		valueMult = Sizes.valueAtMin + (Sizes.valueAtMax - Sizes.valueAtMin) * t,
		modelScale = Sizes.modelScaleAtMin + (Sizes.modelScaleAtMax - Sizes.modelScaleAtMin) * t,
		t = t,
	}
end

-- Size multiplier from a stored weight (used when a fish is re-displayed later).
function LootMath.sizeT(weight: number, minWeight: number, maxWeight: number): number
	if maxWeight <= minWeight then
		return 0.5
	end
	return math.clamp((weight - minWeight) / (maxWeight - minWeight), 0, 1)
end

function LootMath.modelScaleFor(weight: number, minWeight: number, maxWeight: number, colossal: boolean?): number
	if colossal then
		return Sizes.colossal.modelScale
	end
	local t = LootMath.sizeT(weight, minWeight, maxWeight)
	return Sizes.modelScaleAtMin + (Sizes.modelScaleAtMax - Sizes.modelScaleAtMin) * t
end

function LootMath.fishValue(base: number, sizeMult: number, mutationId: string?, perfect: boolean): number
	local mult = sizeMult
	if mutationId then
		local mutation = Mutations.byId[mutationId]
		if mutation then
			mult *= mutation.multiplier
		end
	end
	if perfect then
		mult *= Game.Catch.PerfectBonus
	end
	return math.max(1, math.floor(base * mult + 0.5))
end

-- Returns the condition index (1..#Conditions.list).
function LootMath.rollCondition(rng: Rng, luck: number): number
	local luckFactor = math.max(1, luck) ^ Game.Luck.ConditionExponent
	-- exact-odds conditions first (rarest first)
	for index = #Conditions.list, 1, -1 do
		local condition = Conditions.list[index]
		if condition.odds then
			local chance = (1 / condition.odds) * (if condition.luckBoosted then luckFactor else 1)
			if rng() < chance then
				return index
			end
		end
	end
	local total = 0
	for _, condition in Conditions.list do
		if not condition.odds then
			total += condition.weight * (if condition.luckBoosted then luckFactor else 1)
		end
	end
	local roll = rng() * total
	for index, condition in Conditions.list do
		if not condition.odds then
			roll -= condition.weight * (if condition.luckBoosted then luckFactor else 1)
			if roll < 0 then
				return index
			end
		end
	end
	return 2
end

function LootMath.treasureValue(base: number, conditionIndex: number): number
	local condition = Conditions.list[conditionIndex] or Conditions.list[2]
	return math.max(1, math.floor(base * condition.multiplier + 0.5))
end

-- "Rarest catch" score: 1000 × log10(1 / combined base odds). Luck is ignored so scores are
-- comparable between players.
function LootMath.rarityScore(tierIndex: number, mutationId: string?, colossal: boolean?, conditionIndex: number?): number
	local rarity = Rarities.list[tierIndex] or Rarities.list[1]
	local odds = rarity.odds
	if mutationId and Mutations.byId[mutationId] then
		odds *= Mutations.byId[mutationId].odds
	end
	if colossal then
		odds *= Sizes.colossal.odds
	end
	if conditionIndex then
		local condition = Conditions.list[conditionIndex]
		if condition and condition.odds then
			odds *= condition.odds
		end
	end
	return math.floor(math.log10(odds) * 1000)
end

-- Leaderboard encoding: score and the item packed in one integer so boards can show which
-- catch earned the spot. kindOffset = 0 for fish, 5000 for treasure; order < 5000.
function LootMath.encodeBoardScore(score: number, mutationIndex: number, isTreasure: boolean, order: number): number
	return score * 100000 + math.clamp(mutationIndex, 0, 9) * 10000 + (if isTreasure then 5000 else 0) + math.clamp(order, 0, 4999)
end

function LootMath.decodeBoardScore(value: number): (number, number, boolean, number)
	value = math.floor(value)
	local score = value // 100000
	local rest = value % 100000
	local mutationIndex = rest // 10000
	local code = rest % 10000
	local isTreasure = code >= 5000
	local order = if isTreasure then code - 5000 else code
	return score, mutationIndex, isTreasure, order
end

return LootMath

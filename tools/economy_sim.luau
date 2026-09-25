-- DEEP HAUL economy simulator.
--
--   python3 tools/bundle_tests.py --script tools/economy_sim.luau && luau build/script_bundle.luau
--
-- Simulates a player diving, catching and upgrading using the REAL config and loot maths
-- (Stats, LootMath, Config/*). Each catch rolls real rarities, species, weights, mutations and
-- conditions. A simple behaviour model stands in for the player:
--   * dives into the deepest zone their hull handles comfortably,
--   * for fish, picks the rarest of the few fish in view (selection bias), may miss the minigame,
--   * for treasure, salvages the best piece their claw tier allows,
--   * surfaces when cargo is full or oxygen runs low, sells everything,
--   * spends coins greedily on upgrades weighted by usefulness, then saves up to rebirth.
-- Prints the median time of each progression milestone over many seeds. See BALANCING.md.

local Config = Shared.Config
local Zones = require(Config.Zones)
local Fish = require(Config.Fish)
local Treasure = require(Config.Treasure)
local Rarities = require(Config.Rarities)
local Upgrades = require(Config.Upgrades)
local Game = require(Config.Game)
local Stats = require(Shared.Modules.Stats)
local LootMath = require(Shared.Modules.LootMath)
local Hash = require(Shared.Modules.Hash)
local Format = require(Shared.Modules.Format)
local DepthMath = require(Shared.Modules.DepthMath)

local RUNS = 24
local MAX_HOURS = 60
local FISH_SHARE = 0.68 -- fraction of catches that are fish (the rest treasure)
local FISH_CANDIDATES = 3 -- fish in view to choose from
local TREASURE_CANDIDATES = 2
local SUCCESS = { 0.97, 0.95, 0.9, 0.85, 0.75, 0.65, 0.55, 0.5 } -- minigame success per try
local PERFECT_RATE = 0.2
local DOCK_OVERHEAD = 25 -- seconds per dive spent selling / walking / boarding

-- Build pools
local fishPools, treasurePools = {}, {}
for _, zone in Zones.list do
	fishPools[zone.index] = {}
	treasurePools[zone.index] = {}
end
for _, f in Fish.list do
	if f.zone then
		table.insert(fishPools[Zones.byId[f.zone].index], { id = f.id, tier = Rarities.byId[f.rarity].index, weight = 1 })
	end
end
for _, t in Treasure.list do
	if t.zone then
		table.insert(treasurePools[Zones.byId[t.zone].index], { id = t.id, tier = Rarities.byId[t.rarity].index, weight = 1 })
	end
end

local function pickZone(stats)
	local best = 1
	for _, zone in Zones.list do
		if not zone.requiresRebirth then
			local span = zone.meters[2] - zone.meters[1]
			if stats.maxDepth >= zone.meters[1] + 0.3 * span then
				best = zone.index
			end
		end
	end
	return best
end

ZONE_TIME, ZONE_COINS, ZONE_ITEMS = {}, {}, {}
local function simulate(seed)
	local rng = Hash.rng(seed)
	local upgrades = {}
	for _, u in Upgrades.list do
		upgrades[u.id] = 1
	end
	local coins = 0
	local lifetime = 0
	local t = 0
	local diveTime = 0
	local foundLegendary = false
	local milestones = {}
	local spentOnUpgrades = 0
	local function mark(key)
		if milestones[key] == nil then
			milestones[key] = t
		end
	end

	local function ctx()
		return {
			upgrades = upgrades,
			perks = {},
			rebirths = 0,
			passes = {},
			sets = {},
			indexLuck = 0,
			boosts = {},
			now = 0,
			serverLuck = 1,
			eventLuck = 1,
			eventSell = 1,
		}
	end

	while t < MAX_HOURS * 3600 do
		local stats = Stats.compute(ctx())
		local zoneIndex = pickZone(stats)
		local zone = Zones.list[zoneIndex]
		mark("dive_" .. zone.id)
		if stats.maxDepth >= 6000 then
			mark("reach_Hadal")
		end
		if stats.maxDepth >= 3000 then
			mark("reach_Abyssal")
		end
		if stats.maxDepth >= 1000 then
			mark("reach_Midnight")
		end
		if stats.maxDepth >= 200 then
			mark("reach_Twilight")
		end

		local chances = LootMath.tierChances({ luck = stats.luck, zoneBonus = zone.rarityBonus })
		local floorTop = DepthMath.floorTopY(zoneIndex)
		local targetY = (zone.topY + floorTop) / 2
		local descent = math.abs(targetY) * 1.25 / (stats.speed * 0.8)
		local oxygenSeconds = stats.oxygen / zone.oxygenDrain
		local search = 8 * (28 / stats.speed) ^ 0.5
		if zone.dark then
			search *= (90 / stats.lightRadius) ^ 0.3
		end
		search *= (100 / stats.sonarRange) ^ 0.15

		local available = oxygenSeconds - descent - 4
		local items = 0
		local haul = 0
		local diveElapsed = descent
		while items < stats.cargo and available > 0 do
			local isFish = rng() < FISH_SHARE
			local value = 0
			local cost = search
			if isFish then
				local best
				for _ = 1, FISH_CANDIDATES do
					local tier = LootMath.rollTier(rng(), chances)
					if not foundLegendary and diveTime + diveElapsed >= Game.Spawns.FirstLegendaryGuaranteeMinutes * 60 then
						tier = math.max(tier, 5)
					end
					local entry = LootMath.pickFromPool(rng, fishPools[zoneIndex], tier)
					if entry and (best == nil or entry.tier > best.tier) then
						best = entry
					end
				end
				local fish = Fish.byId[best.id]
				local caught = false
				for _ = 1, 2 do
					cost += 3
					if rng() < SUCCESS[best.tier] then
						caught = true
						break
					end
					cost += 3
				end
				if not caught then
					-- settle for a common from the pool
					best = LootMath.pickFromPool(rng, fishPools[zoneIndex], 1)
					fish = Fish.byId[best.id]
					cost += 3
				end
				local size = LootMath.rollSize(rng, fish.weight[1], fish.weight[2], stats.luck)
				local mutation = LootMath.rollMutation(rng, { luck = stats.luck })
				value = LootMath.fishValue(fish.value, size.valueMult, mutation, rng() < PERFECT_RATE)
				if best.tier >= 5 then
					foundLegendary = true
					mark("first_legendary")
				end
			else
				local best
				for _ = 1, TREASURE_CANDIDATES + 2 do
					local tier = LootMath.rollTier(rng(), chances)
					local entry = LootMath.pickFromPool(rng, treasurePools[zoneIndex], tier)
					if entry then
						local def = Treasure.byId[entry.id]
						local need = def.clawTier or Rarities.list[entry.tier].clawTier
						if need <= stats.clawTier and (best == nil or entry.tier > best.tier) then
							best = entry
						end
					end
				end
				if best == nil then
					best = LootMath.pickFromPool(rng, treasurePools[zoneIndex], 1)
				end
				cost += Rarities.list[best.tier].salvageTime / stats.clawSpeed
				local condition = LootMath.rollCondition(rng, stats.luck)
				value = LootMath.treasureValue(Treasure.byId[best.id].value, condition)
				if best.tier >= 5 then
					foundLegendary = true
					mark("first_legendary")
				end
			end
			if cost > available then
				break
			end
			available -= cost
			diveElapsed += cost
			items += 1
			haul += value
		end
		if items == 0 then
			-- can't do anything in this zone: shouldn't happen, but avoid infinite loops
			t += 60
		end
		local duration = diveElapsed + 3 + DOCK_OVERHEAD
		local earned = haul * stats.sellMult
		coins += earned
		lifetime += earned
		t += duration
		ZONE_TIME[zoneIndex] = (ZONE_TIME[zoneIndex] or 0) + duration
		ZONE_COINS[zoneIndex] = (ZONE_COINS[zoneIndex] or 0) + earned
		ZONE_ITEMS[zoneIndex] = (ZONE_ITEMS[zoneIndex] or 0) + items
		diveTime += diveElapsed

		-- Spend
		local reachedHadal = stats.maxDepth >= 6000
		local rebirthCost = Stats.rebirthCost(0)
		if reachedHadal and coins >= rebirthCost then
			mark("rebirth")
			break
		end
		while true do
			local bestId, bestScore, bestCost = nil, math.huge, 0
			for _, u in Upgrades.list do
				local level = upgrades[u.id]
				if level < #u.values then
					local cost = Stats.upgradeCost(u.id, level + 1)
					local weight = ({ Hull = 1.6, Cargo = 1.3, Oxygen = 1.0, Engine = 0.9, Luck = 1.1, Claw = 1.0, Lights = 0.5, Sonar = 0.4 })[u.id]
					if u.id == "Hull" then
						local nextStats = table.clone(upgrades)
						nextStats.Hull = level + 1
						local nz = pickZone({ maxDepth = Stats.upgradeValue("Hull", level + 1) })
						if nz > zoneIndex then
							weight = 3
						end
					end
					if u.id == "Oxygen" and oxygenSeconds - descent < stats.cargo * search * 1.2 then
						weight = 2.2 -- oxygen is the bottleneck
					end
					if u.id == "Lights" and zone.dark then
						weight = 0.9
					end
					local score = cost / weight
					if score < bestScore then
						bestId, bestScore, bestCost = u.id, score, cost
					end
				end
			end
			if bestId == nil then
				break
			end
			local budget = coins
			if reachedHadal then
				budget = coins * 0.15 -- saving for the rebirth now
			end
			if bestCost > budget then
				break
			end
			coins -= bestCost
			spentOnUpgrades += bestCost
			upgrades[bestId] += 1
		end
	end
	milestones.lifetime = lifetime
	milestones.upgrades = upgrades
	milestones.spent = spentOnUpgrades
	return milestones
end

local keys = {
	"first_legendary",
	"reach_Twilight",
	"dive_Twilight",
	"reach_Midnight",
	"dive_Midnight",
	"reach_Abyssal",
	"dive_Abyssal",
	"reach_Hadal",
	"dive_Hadal",
	"rebirth",
}
local results = {}
for _, key in keys do
	results[key] = {}
end
local lastUpgrades
for run = 1, RUNS do
	local m = simulate(run * 7919)
	for _, key in keys do
		table.insert(results[key], m[key] or math.huge)
	end
	lastUpgrades = m.upgrades
end

local function hours(s)
	if s == math.huge then
		return "never"
	end
	if s < 3600 then
		return string.format("%5.1f min", s / 60)
	end
	return string.format("%5.1f h", s / 3600)
end

print("DEEP HAUL economy simulation (" .. RUNS .. " runs, no passes, no events)")
print(string.format("%-18s %12s %12s %12s", "milestone", "p10", "median", "p90"))
for _, key in keys do
	local list = results[key]
	table.sort(list)
	local function pct(p)
		return list[math.clamp(math.floor(#list * p + 0.5), 1, #list)]
	end
	print(string.format("%-18s %12s %12s %12s", key, hours(pct(0.1)), hours(pct(0.5)), hours(pct(0.9))))
end
local levels = {}
for _, u in Upgrades.list do
	table.insert(levels, u.id .. "=" .. lastUpgrades[u.id])
end
print("upgrade levels at the end of the last run: " .. table.concat(levels, " "))

print("zone        hours   coins/h   items/min")
for i = 1, 6 do
	if ZONE_TIME[i] then
		print(string.format("%-10s %6.2f %10s %8.2f", Zones.list[i].id, ZONE_TIME[i] / 3600 / RUNS, Format.short(ZONE_COINS[i] / (ZONE_TIME[i] / 3600)), ZONE_ITEMS[i] / (ZONE_TIME[i] / 60)))
	end
end

--!strict
-- What spawns where. Pure functions (randomness passed in) so they are unit tested.
--
-- Fish and treasure rarity is rolled at SPAWN time (so rare loot is visible, glows and can
-- flee). Event exclusives are mixed in with the event's exclusiveChance. The first-Legendary
-- guarantee forces tier 5 when asked to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Zones = require(Shared.Config.Zones)
local Rarities = require(Shared.Config.Rarities)
local LootMath = require(Shared.Modules.LootMath)

export type Rng = () -> number

export type RollMods = {
	luck: number,
	tierMult: { [string]: number }?,
	exclusive: { { id: string, chance: number } }?,
	categoryWeight: { [string]: number }?,
	minTier: number?, -- force at least this tier (guarantee, galleon)
	onlyEvent: string?, -- only this event's exclusives (e.g. galleon hold)
	exclusiveBoost: number?, -- multiplies exclusive chances (galleon / tremor / wake)
}

export type Roll = { id: string, tier: number, event: string? }

local LootPools = {}

local fishByZone: { [number]: { LootMath.PoolEntry } } = {}
local treasureByZone: { [number]: { { id: string, tier: number, weight: number, category: string } } } = {}

for _, zone in Zones.list do
	fishByZone[zone.index] = {}
	treasureByZone[zone.index] = {}
end
for _, fish in Fish.list do
	if fish.zone and not fish.event then
		table.insert(fishByZone[Zones.byId[fish.zone].index], { id = fish.id, tier = Rarities.byId[fish.rarity].index, weight = 1 })
	end
end
for _, treasure in Treasure.list do
	if treasure.zone and not treasure.event then
		table.insert(treasureByZone[Zones.byId[treasure.zone].index], {
			id = treasure.id,
			tier = Rarities.byId[treasure.rarity].index,
			weight = 1,
			category = treasure.category,
		})
	end
end

local function allowedInZone(zones: { number }?, zoneIndex: number): boolean
	if not zones then
		return true
	end
	return table.find(zones, zoneIndex) ~= nil
end

function LootPools.fishPool(zoneIndex: number): { LootMath.PoolEntry }
	return fishByZone[zoneIndex] or {}
end

function LootPools.eventFishPool(eventId: string, zoneIndex: number): { LootMath.PoolEntry }
	local out = {}
	local list = Fish.byEvent[eventId]
	if list then
		for _, fish in list do
			if allowedInZone(fish.zones, zoneIndex) then
				table.insert(out, { id = fish.id, tier = Rarities.byId[fish.rarity].index, weight = 1 })
			end
		end
	end
	return out
end

function LootPools.treasurePool(zoneIndex: number, categoryWeight: { [string]: number }?): { LootMath.PoolEntry }
	local out = {}
	local zoneEntries = treasureByZone[zoneIndex]
	if not zoneEntries then
		return out
	end
	for _, entry in zoneEntries do
		local weight = entry.weight
		if categoryWeight and categoryWeight[entry.category] then
			weight *= categoryWeight[entry.category]
		end
		table.insert(out, { id = entry.id, tier = entry.tier, weight = weight })
	end
	-- Deep Tremor style events can surface categories that don't normally live in this zone:
	-- borrow them from the nearest deeper zone that has them.
	if categoryWeight then
		for category, weight in categoryWeight do
			if weight > 1 then
				local has = false
				for _, entry in out do
					if Treasure.byId[entry.id].category == category then
						has = true
						break
					end
				end
				if not has then
					for deeper = zoneIndex + 1, Zones.count - 1 do
						local found = false
						for _, entry in treasureByZone[deeper] do
							if entry.category == category and entry.tier <= 4 then
								table.insert(out, { id = entry.id, tier = entry.tier, weight = weight * 0.5 })
								found = true
							end
						end
						if found then
							break
						end
					end
				end
			end
		end
	end
	return out
end

function LootPools.eventTreasurePool(eventId: string, zoneIndex: number): { LootMath.PoolEntry }
	local out = {}
	local list = Treasure.byEvent[eventId]
	if list then
		for _, treasure in list do
			if allowedInZone(treasure.zones, zoneIndex) then
				table.insert(out, { id = treasure.id, tier = Rarities.byId[treasure.rarity].index, weight = 1 })
			end
		end
	end
	return out
end

local function rollTier(rng: Rng, zoneIndex: number, mods: RollMods): number
	local zone = Zones.list[zoneIndex]
	local chances = LootMath.tierChances({ luck = mods.luck, zoneBonus = zone.rarityBonus, tierMult = mods.tierMult })
	local tier = LootMath.rollTier(rng(), chances)
	if mods.minTier and tier < mods.minTier then
		tier = mods.minTier
	end
	return tier
end

local function tryExclusive(rng: Rng, zoneIndex: number, mods: RollMods, poolFor: (string, number) -> { LootMath.PoolEntry }): Roll?
	local exclusive = mods.exclusive
	if not exclusive then
		return nil
	end
	for _, entry in exclusive do
		if not mods.onlyEvent or mods.onlyEvent == entry.id then
			local chance = entry.chance * (mods.exclusiveBoost or 1)
			if rng() < chance then
				local pool = poolFor(entry.id, zoneIndex)
				if #pool > 0 then
					local tier = rollTier(rng, zoneIndex, mods)
					local picked = LootMath.pickFromPool(rng, pool, tier)
					if picked then
						return { id = picked.id, tier = picked.tier, event = entry.id }
					end
				end
			end
		end
	end
	return nil
end

function LootPools.rollFish(rng: Rng, zoneIndex: number, mods: RollMods): Roll?
	local exclusive = tryExclusive(rng, zoneIndex, mods, LootPools.eventFishPool)
	if exclusive then
		return exclusive
	end
	local pool = LootPools.fishPool(zoneIndex)
	local tier = rollTier(rng, zoneIndex, mods)
	local picked = LootMath.pickFromPool(rng, pool, tier)
	if not picked then
		return nil
	end
	return { id = picked.id, tier = picked.tier }
end

function LootPools.rollTreasure(rng: Rng, zoneIndex: number, mods: RollMods): Roll?
	local exclusive = tryExclusive(rng, zoneIndex, mods, LootPools.eventTreasurePool)
	if exclusive then
		return exclusive
	end
	local pool = LootPools.treasurePool(zoneIndex, mods.categoryWeight)
	local tier = rollTier(rng, zoneIndex, mods)
	local picked = LootMath.pickFromPool(rng, pool, tier)
	if not picked then
		return nil
	end
	return { id = picked.id, tier = picked.tier }
end

return LootPools

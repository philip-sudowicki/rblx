--!strict
-- Turns a caught fish / salvaged treasure entity into an owned item: rolls weight + Colossal,
-- mutation, condition and value on the server, records discovery and stats, sends the reveal,
-- and announces big catches to the server (Mythic+) or every server (Secret).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Conditions = require(Shared.Config.Conditions)
local Zones = require(Shared.Config.Zones)
local Events = require(Shared.Config.Events)
local LootMath = require(Shared.Modules.LootMath)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local StatsService = require(script.Parent.StatsService)
local EventService = require(script.Parent.EventService)
local AnnounceService = require(script.Parent.AnnounceService)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)

local LootService = {}

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local function eventTag(entityEvent: string?): string?
	if entityEvent then
		return entityEvent
	end
	local active = EventService.activeIds()
	return active[1]
end

local function recordBest(data: Types.PlayerData, item: Types.Item, score: number)
	if score > data.Stats.BestScore then
		data.Stats.BestScore = score
		data.Stats.BestItem = item.i
		data.Stats.BestMutation = item.m or ""
		data.Stats.BestKind = item.k
	end
end

local function announce(player: Player, item: Types.Item, displayName: string)
	local rarity = Rarities.list[item.r]
	local mutation = item.m and Mutations.byId[item.m]
	local bigMutation = mutation ~= nil and mutation.odds >= 5000
	local colossalBig = item.x == true and item.r >= Rarities.legendaryIndex
	if rarity.announce == "none" and not bigMutation and not colossalBig then
		return
	end
	local parts = {}
	if item.x then
		table.insert(parts, "COLOSSAL")
	end
	if mutation then
		table.insert(parts, mutation.name:upper())
	end
	if item.c then
		local condition = Conditions.byId[item.c]
		if condition and condition.odds then
			table.insert(parts, condition.name:upper())
		end
	end
	table.insert(parts, rarity.name:upper())
	table.insert(parts, displayName)
	local verb = if item.k == "F" then "caught" else "salvaged"
	local text = string.format("%s %s a %s!", player.DisplayName, verb, table.concat(parts, " "))
	if rarity.announce == "global" then
		AnnounceService.global("🌟 " .. text, rarity.color)
	else
		AnnounceService.chat("✨ " .. text, if mutation then mutation.color else rarity.color)
	end
end

local function commonStats(player: Player, data: Types.PlayerData, item: Types.Item, isEventItem: boolean)
	local stats = data.Stats
	if item.r >= Rarities.mythicIndex then
		stats.MythicPlus += 1
	end
	if item.r >= Rarities.count then
		stats.Secrets += 1
	end
	if isEventItem then
		stats.EventItems += 1
	end
	if item.r >= Rarities.legendaryIndex and not data.Flags.FoundLegendary then
		data.Flags.FoundLegendary = true
		DataService.replicate(player, "Flags")
	end
end

-- entity fields used: fishId, tier, zone, event
function LootService.grantFish(player: Player, entity: { fishId: string, tier: number, zone: number, event: string? }, perfect: boolean): Types.Item?
	local data = DataService.get(player)
	local def = Fish.byId[entity.fishId]
	if not data or not def then
		return nil
	end
	local stats = StatsService.get(player)
	local mods = EventService.modifiers()
	local size = LootMath.rollSize(roll, def.weight[1], def.weight[2], stats.luck)
	local mutation = LootMath.rollMutation(roll, { luck = stats.luck, mult = mods.mutationMult, enabled = mods.enabledMutations })
	local zone = Zones.list[entity.zone] or Zones.list[1]
	local base = def.value * (if def.event then zone.valueScale else 1)
	local value = LootMath.fishValue(base, size.valueMult, mutation, perfect)
	local item: Types.Item = {
		u = 0,
		k = "F",
		i = def.id,
		r = entity.tier,
		v = value,
		z = entity.zone,
		t = os.time(),
		w = size.weight,
		m = mutation,
		x = if size.colossal then true else nil,
		e = eventTag(entity.event),
		p = if perfect then true else nil,
	}
	local added = InventoryService.add(player, item, true)
	if not added then
		return nil
	end

	local discovery = data.Discovered.Fish[def.id]
	local isNew = discovery == nil
	if not discovery then
		discovery = { n = 0, bw = 0, m = {} }
		data.Discovered.Fish[def.id] = discovery
	end
	discovery.n += 1
	discovery.bw = math.max(discovery.bw, size.weight)
	if mutation then
		discovery.m[mutation] = true
	end
	if size.colossal then
		discovery.x = true
	end
	local s = data.Stats
	s.FishCaught += 1
	if perfect then
		s.PerfectCatches += 1
	end
	if mutation then
		s.MutatedCatches += 1
		if mutation == "Golden" then
			s.GoldenCatches += 1
		end
	end
	commonStats(player, data, added, def.event ~= nil)
	local mutationIndex = if mutation then Mutations.byId[mutation].order else 0
	local score = LootMath.rarityScore(entity.tier, mutation, size.colossal)
	recordBest(data, added, score)
	s.BestBoardValue = math.max(s.BestBoardValue, LootMath.encodeBoardScore(score, mutationIndex, false, def.order))
	DataService.replicate(player, "Discovered")
	DataService.replicate(player, "Stats")

	Remotes.fire(player, "Reveal", { item = added, isNew = isNew, modelScale = size.modelScale })
	ServerSignals.ItemObtained:Fire(player, added, { source = "Catch", zone = entity.zone, perfect = perfect, events = EventService.activeIds() })
	announce(player, added, def.name)
	return added
end

-- entity fields used: treasureId, tier, zone, event, source
function LootService.grantTreasure(player: Player, entity: { treasureId: string, tier: number, zone: number, event: string?, source: string? }): Types.Item?
	local data = DataService.get(player)
	local def = Treasure.byId[entity.treasureId]
	if not data or not def then
		return nil
	end
	local stats = StatsService.get(player)
	local luck = stats.luck
	if entity.source == "Galleon" then
		luck *= Events.galleon.luck
	elseif entity.source == "Tremor" then
		luck *= Events.tremor.luck
	end
	local conditionIndex = LootMath.rollCondition(roll, luck)
	local zone = Zones.list[entity.zone] or Zones.list[1]
	local base = def.value * (if def.event then zone.valueScale else 1)
	local value = LootMath.treasureValue(base, conditionIndex)
	local condition = Conditions.list[conditionIndex]
	local item: Types.Item = {
		u = 0,
		k = "T",
		i = def.id,
		r = entity.tier,
		v = value,
		z = entity.zone,
		t = os.time(),
		c = condition.id,
		e = eventTag(entity.event),
	}
	local added = InventoryService.add(player, item, true)
	if not added then
		return nil
	end
	local discovery = data.Discovered.Treasure[def.id]
	local isNew = discovery == nil
	if not discovery then
		discovery = { n = 0, bc = 0 }
		data.Discovered.Treasure[def.id] = discovery
	end
	discovery.n += 1
	discovery.bc = math.max(discovery.bc, conditionIndex)
	data.Stats.TreasureSalvaged += 1
	commonStats(player, data, added, def.event ~= nil)
	local score = LootMath.rarityScore(entity.tier, nil, false, conditionIndex)
	recordBest(data, added, score)
	data.Stats.BestBoardValue = math.max(data.Stats.BestBoardValue, LootMath.encodeBoardScore(score, 0, true, def.order))
	DataService.replicate(player, "Discovered")
	DataService.replicate(player, "Stats")

	Remotes.fire(player, "Reveal", { item = added, isNew = isNew, modelScale = 1 })
	ServerSignals.ItemObtained:Fire(player, added, { source = "Salvage", zone = entity.zone, events = EventService.activeIds() })
	announce(player, added, def.name)
	return added
end

return LootService

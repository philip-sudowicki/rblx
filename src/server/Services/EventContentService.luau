--!strict
-- World content for the special events:
--   Leviathan Migration  the Leviathan laps the Abyssal Plains (LeviathanPath, rendered by every
--                        client); loot drops in its wake while a diver is close enough to follow
--   Sunken Galleon       a treasure galleon settles on the floor of a random zone, packed with
--                        rare treasure; ReplicatedStorage attributes drive the HUD marker
--   Deep Tremor          glowing trenches crack open in the deep zones, holding treasure
--                        weighted to Ancient Tech and Cursed Items
-- Everything is removed when its event ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Zones = require(Shared.Config.Zones)
local Rarities = require(Shared.Config.Rarities)
local LeviathanPath = require(Shared.Modules.LeviathanPath)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local DepthMath = require(Shared.Modules.DepthMath)
local Format = require(Shared.Modules.Format)
local LootPools = require(script.Parent.Parent.Pure.LootPools)
local EventModels = require(script.Parent.Parent.World.EventModels)
local EventService = require(script.Parent.EventService)
local BoostService = require(script.Parent.BoostService)
local SpawnService = require(script.Parent.SpawnService)
local PlayerState = require(script.Parent.PlayerState)
local WorldService = require(script.Parent.WorldService)
local AnnounceService = require(script.Parent.AnnounceService)
local ServerSignals = require(script.Parent.ServerSignals)

local EventContentService = {}

type Content = { models: { Model }, entities: { number } }

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local leviathan = { active = false, startedAt = 0, wake = {} :: { number } }
local galleon: Content? = nil
local tremor: Content? = nil

local function entryFor(id: string): EventService.ActiveEvent?
	for _, entry in EventService.activeEvents() do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function worldLuck(): number
	return EventService.modifiers().luck * BoostService.serverLuck()
end

-- Real floor height under (x, z): raycast against terrain, falling back to the analytic floor.
local function floorAt(zoneIndex: number, x: number, z: number): number
	local top = WorldGeometry.ceilingY(zoneIndex, x, z) - 2
	local bottom = Zones.list[zoneIndex].bottomY
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, bottom - top, 0), params)
	return if hit then hit.Position.Y else WorldGeometry.floorY(zoneIndex, x, z)
end

-- A random floor point in a zone, clear of the hole to the next zone and the outer wall.
local function floorPoint(zoneIndex: number, random: Random, wallMargin: number, holeMargin: number): Vector3
	local zone = Zones.list[zoneIndex]
	for _ = 1, 80 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(random:NextNumber()) * (zone.radius - wallMargin)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if not WorldGeometry.inHole(zoneIndex, x, z, -holeMargin) then
			local y = floorAt(zoneIndex, x, z)
			if WorldGeometry.ceilingY(zoneIndex, x, z) - y > 50 then
				return Vector3.new(x, y, z)
			end
		end
	end
	local x = (zone.radius - wallMargin) * 0.6
	return Vector3.new(x, floorAt(zoneIndex, x, 0), 0)
end

local function spawnTreasure(zoneIndex: number, position: Vector3, source: string, mods: LootPools.RollMods): number?
	local result = LootPools.rollTreasure(roll, zoneIndex, mods)
	if not result then
		return nil
	end
	local entity = SpawnService.spawnTreasure(zoneIndex, position, result.id, result.tier, {
		event = result.event,
		source = source,
		persistent = true,
		lifetime = Events.schedule.durationSeconds + 60,
	})
	return if entity then entity.id else nil
end

local function clear(content: Content?)
	if not content then
		return
	end
	for _, id in content.entities do
		if SpawnService.treasure[id] then
			SpawnService.remove(id)
		end
	end
	for _, model in content.models do
		model:Destroy()
	end
end

---------------------------------------------------------------- Leviathan

local function dropWake()
	local params = Events.leviathan
	local elapsed = workspace:GetServerTimeNow() - leviathan.startedAt - params.wakeDelay
	if elapsed < 0 then
		return
	end
	local position = LeviathanPath.position(elapsed)
	local following = false
	for _, state in PlayerState.all() do
		local dive = state.dive
		if dive and (dive.root.Position - position).Magnitude <= params.followRadius then
			following = true
			break
		end
	end
	if not following then
		return
	end
	for i = #leviathan.wake, 1, -1 do
		if not SpawnService.treasure[leviathan.wake[i]] then
			table.remove(leviathan.wake, i)
		end
	end
	if #leviathan.wake >= params.maxWakeEntities then
		return
	end
	local mods = EventService.modifiers()
	local jitter = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-5, 5), rng:NextNumber(-8, 8))
	local spot = WorldGeometry.clampInside(position + jitter, 8)
	local result = LootPools.rollTreasure(roll, params.zone, {
		luck = worldLuck() * params.wakeLuck,
		tierMult = mods.tierMult,
		exclusive = { { id = "Leviathan", chance = Events.byId.Leviathan.modifiers.exclusiveChance or 0.08 } },
		onlyEvent = "Leviathan",
		exclusiveBoost = 2,
	})
	if not result then
		return
	end
	local entity = SpawnService.spawnTreasure(params.zone, spot, result.id, result.tier, { event = result.event, source = "Wake", lifetime = 120 })
	if entity then
		table.insert(leviathan.wake, entity.id)
	end
end

---------------------------------------------------------------- Galleon

local function startGalleon(entry: EventService.ActiveEvent)
	local config = Events.galleon
	local random = Random.new(entry.startedAt)
	local zoneIndex = config.zones[random:NextInteger(1, #config.zones)]
	local floor = floorPoint(zoneIndex, random, 70, 40)
	local base = CFrame.new(floor) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local built = EventModels.galleon(WorldService.eventFolder, base, random)
	local content: Content = { models = { built.model }, entities = {} }
	local minTier = Rarities.byId[config.minRarity].index
	for i = 1, math.min(config.treasureCount, #built.spots) do
		local id = spawnTreasure(zoneIndex, built.spots[i], "Galleon", {
			luck = worldLuck() * config.luck,
			minTier = minTier,
			exclusive = { { id = "Galleon", chance = config.exclusiveChance } },
			onlyEvent = "Galleon",
		})
		if id then
			table.insert(content.entities, id)
		end
	end
	galleon = content
	ReplicatedStorage:SetAttribute("GalleonZone", zoneIndex)
	ReplicatedStorage:SetAttribute("GalleonPosition", floor)
	local zone = Zones.list[zoneIndex]
	AnnounceService.chat(
		string.format("🏴‍☠️ The treasure galleon has settled in the %s at %s! Follow the golden beacon, first come first served!", zone.name, Format.meters(DepthMath.metersAtY(floor.Y))),
		Events.byId.Galleon.color
	)
end

local function stopGalleon()
	clear(galleon)
	galleon = nil
	ReplicatedStorage:SetAttribute("GalleonZone", 0)
	ReplicatedStorage:SetAttribute("GalleonPosition", nil)
end

---------------------------------------------------------------- Tremor

local function startTremor(entry: EventService.ActiveEvent)
	local config = Events.tremor
	local random = Random.new(entry.startedAt + 7)
	local content: Content = { models = {}, entities = {} }
	local mods = EventService.modifiers()
	for _, zoneIndex in config.zones do
		for _ = 1, config.trenchesPerZone do
			local floor = floorPoint(zoneIndex, random, 60, 30)
			local base = CFrame.new(floor) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			local built = EventModels.trench(WorldService.eventFolder, base, random:NextNumber(50, 70), config.treasurePerTrench, random)
			table.insert(content.models, built.model)
			for _, spot in built.spots do
				local id = spawnTreasure(zoneIndex, spot, "Tremor", {
					luck = worldLuck() * config.luck,
					categoryWeight = mods.categoryWeight,
					exclusive = { { id = "DeepTremor", chance = config.exclusiveChance } },
					onlyEvent = "DeepTremor",
				})
				if id then
					table.insert(content.entities, id)
				end
			end
		end
	end
	tremor = content
end

local function stopTremor()
	clear(tremor)
	tremor = nil
end

---------------------------------------------------------------- lifecycle

local function sync()
	local levEntry = entryFor("Leviathan")
	if levEntry and not leviathan.active then
		leviathan.active = true
		leviathan.startedAt = levEntry.startedAt
		leviathan.wake = {}
	elseif not levEntry and leviathan.active then
		leviathan.active = false
	end

	local galleonEntry = entryFor("Galleon")
	if galleonEntry and not galleon then
		startGalleon(galleonEntry)
	elseif not galleonEntry and galleon then
		stopGalleon()
	end

	local tremorEntry = entryFor("DeepTremor")
	if tremorEntry and not tremor then
		startTremor(tremorEntry)
	elseif not tremorEntry and tremor then
		stopTremor()
	end
end

function EventContentService.Start()
	ReplicatedStorage:SetAttribute("GalleonZone", 0)
	ServerSignals.EventsChanged:Connect(function()
		local ok, err = pcall(sync :: (...any) -> ...any)
		if not ok then
			warn("[DeepHaul] event content: " .. tostring(err))
		end
	end)
	task.defer(function()
		pcall(sync :: (...any) -> ...any)
	end)
	task.spawn(function()
		while true do
			task.wait(Events.leviathan.wakeInterval)
			if leviathan.active then
				local ok, err = pcall(dropWake :: (...any) -> ...any)
				if not ok then
					warn("[DeepHaul] leviathan wake: " .. tostring(err))
				end
			end
		end
	end)
end

return EventContentService

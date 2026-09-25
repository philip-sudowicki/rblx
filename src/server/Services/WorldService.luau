--!strict
-- Builds the whole world from code at server start and answers spatial questions:
-- treasure spots, open-water spawn points, obstacles, dock prompts, plots and boards.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local World = script.Parent.Parent.World
local TerrainGen = require(World.TerrainGen)
local Decor = require(World.Decor)
local Dock = require(World.Dock)
local Build = require(World.Build)

export type Spot = {
	id: number,
	position: Vector3,
	zone: number,
	special: string?,
}

local WorldService = {}

WorldService.ready = false
WorldService.spots = {} :: { [number]: { Spot } }
WorldService.spotsById = {} :: { [number]: Spot }
WorldService.dock = (nil :: any) :: Dock.DockResult
WorldService.folder = (nil :: any) :: Folder
WorldService.eventFolder = (nil :: any) :: Folder

local nextSpotId = 0

local GROUPS = { "Characters", "Barrier", "Subs", "Passengers" }

local function setupCollisionGroups()
	for _, name in GROUPS do
		PhysicsService:RegisterCollisionGroup(name)
	end
	-- Barrier only stops walking/swimming characters
	PhysicsService:CollisionGroupSetCollidable("Barrier", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("Barrier", "Subs", false)
	PhysicsService:CollisionGroupSetCollidable("Barrier", "Passengers", false)
	PhysicsService:CollisionGroupSetCollidable("Barrier", "Characters", true)
	-- Subs never collide with other subs or people (no griefing)
	PhysicsService:CollisionGroupSetCollidable("Subs", "Subs", false)
	PhysicsService:CollisionGroupSetCollidable("Subs", "Characters", false)
	-- Seated pilots collide with nothing
	for _, name in { "Default", "Characters", "Barrier", "Subs", "Passengers" } do
		PhysicsService:CollisionGroupSetCollidable("Passengers", name, false)
	end
end

local function addSpot(position: Vector3, zone: number, special: string?)
	nextSpotId += 1
	local spot: Spot = { id = nextSpotId, position = position, zone = zone, special = special }
	local list = WorldService.spots[zone]
	if not list then
		list = {}
		WorldService.spots[zone] = list
	end
	table.insert(list, spot)
	WorldService.spotsById[spot.id] = spot
end

local function generateSpots(zoneIndex: number, rng: Random, count: number)
	local zone = Zones.list[zoneIndex]
	local found = 0
	local attempts = 0
	while found < count and attempts < count * 6 do
		attempts += 1
		local r = (zone.radius - 22) * math.sqrt(rng:NextNumber())
		local theta = rng:NextNumber(0, math.pi * 2)
		local x, z = math.cos(theta) * r, math.sin(theta) * r
		if not WorldGeometry.inHole(zoneIndex, x, z, -8) then
			local ground = Decor.groundAt(zoneIndex, x, z)
			if ground and ground.Y > zone.bottomY and ground.Y < zone.topY then
				addSpot(ground + Vector3.new(0, 0.8, 0), zoneIndex, nil)
				found += 1
			end
		end
	end
end

-- Is `pos` clear of the terrain obstacles we placed (boulders, mounds, ledges, floaters)?
function WorldService.clearOfObstacles(zoneIndex: number, pos: Vector3, margin: number): boolean
	local list = TerrainGen.obstacles[zoneIndex]
	if not list then
		return true
	end
	for _, obstacle in list do
		if (obstacle.center - pos).Magnitude < obstacle.radius + margin then
			return false
		end
	end
	return true
end

-- A random open-water point in a zone between minDist and maxDist from `near`.
function WorldService.randomSwimPoint(zoneIndex: number, near: Vector3, minDist: number, maxDist: number, rng: Random): Vector3?
	local zone = Zones.list[zoneIndex]
	local margin = Game.Spawns.WallMargin
	for _ = 1, 12 do
		local direction = rng:NextUnitVector()
		direction = Vector3.new(direction.X, direction.Y * 0.45, direction.Z)
		if direction.Magnitude > 0.01 then
			local candidate = near + direction.Unit * rng:NextNumber(minDist, maxDist)
			-- keep it in this zone's band
			local floorY = WorldGeometry.floorY(zoneIndex, candidate.X, candidate.Z) + Game.Spawns.FloorMargin
			local ceilingY = WorldGeometry.ceilingY(zoneIndex, candidate.X, candidate.Z) - Game.Spawns.CeilingMargin
			if zoneIndex == 1 then
				ceilingY = math.min(ceilingY, -12)
			end
			local y = math.clamp(candidate.Y, math.min(floorY, ceilingY), math.max(floorY, ceilingY))
			candidate = Vector3.new(candidate.X, y, candidate.Z)
			if WorldGeometry.radius(candidate.X, candidate.Z) <= zone.radius - margin and y > zone.bottomY and y < zone.topY then
				if WorldService.clearOfObstacles(zoneIndex, candidate, 8) then
					return candidate
				end
			end
		end
	end
	return nil
end

-- Treasure spots of a zone within `radius` of `pos`.
function WorldService.spotsNear(zoneIndex: number, pos: Vector3, radius: number): { Spot }
	local out = {}
	local list = WorldService.spots[zoneIndex]
	if not list then
		return out
	end
	for _, spot in list do
		if (spot.position - pos).Magnitude <= radius then
			table.insert(out, spot)
		end
	end
	return out
end

function WorldService.nearestSpot(zoneIndex: number, pos: Vector3): Spot?
	local best: Spot? = nil
	local bestDist = math.huge
	local list = WorldService.spots[zoneIndex]
	if not list then
		return nil
	end
	for _, spot in list do
		local d = (spot.position - pos).Magnitude
		if d < bestDist then
			best, bestDist = spot, d
		end
	end
	return best
end

local function setCharacterGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Characters"
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.CollisionGroup == "Default" then
			descendant.CollisionGroup = "Characters"
		end
	end)
end

function WorldService.Init()
	setupCollisionGroups()
	local folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = workspace
	WorldService.folder = folder
	local eventFolder = Instance.new("Folder")
	eventFolder.Name = "EventContent"
	eventFolder.Parent = workspace
	WorldService.eventFolder = eventFolder

	local started = os.clock()
	WorldService.dock = Dock.build(folder)
	TerrainGen.build()
	local zonesFolder = Build.folder(folder, "Zones")
	local rng = Random.new(424242)
	for index = 1, Zones.count do
		task.wait() -- keep each step short (the world is big)
		local special = Decor.build(index, zonesFolder, rng)
		for _, spot in special do
			addSpot(spot.position, spot.zone, spot.special)
		end
	end
	local spotRng = Random.new(99)
	for index = 1, Zones.count do
		generateSpots(index, spotRng, 150)
	end
	for _, ledge in TerrainGen.ledges do
		local ground = Decor.groundAt(ledge.zone, ledge.top.X, ledge.top.Z)
		if ground and math.abs(ground.Y - ledge.top.Y) < 12 then
			addSpot(ground + Vector3.new(0, 0.8, 0), ledge.zone, "Ledge")
		end
	end
	WorldService.ready = true
	game:GetService("ReplicatedStorage"):SetAttribute("WorldReady", true)
	print(string.format("[DeepHaul] world built in %.2fs", os.clock() - started))
end

function WorldService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(setCharacterGroup)
		if player.Character then
			setCharacterGroup(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return WorldService

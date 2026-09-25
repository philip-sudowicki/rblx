--!strict
-- Procedural terrain for the Blue Hole: atoll ring, dock island, terraced Lagoon, zone walls,
-- floors with offset holes, ceiling rings, boulders, ledges, arches and the thin surface water.
-- Everything is deterministic (fixed seed) so every server has the same map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldGeometry = require(Shared.Modules.WorldGeometry)

export type Obstacle = { center: Vector3, radius: number }
export type Ledge = { top: Vector3, zone: number, normal: Vector3 }
export type Floater = { center: Vector3, radius: number, zone: number }

local TerrainGen = {}

local terrain = workspace.Terrain
local AIR = Enum.Material.Air

-- Building the whole map in one go can run longer than Roblox's script time limit, so every
-- terrain operation goes through these wrappers, which yield briefly every ~50 ms.
local sliceStart = os.clock()
local function pace()
	if os.clock() - sliceStart > 0.05 then
		task.wait()
		sliceStart = os.clock()
	end
end

local function fillBall(center: Vector3, radius: number, material: Enum.Material)
	terrain:FillBall(center, radius, material)
	pace()
end

local function fillBlock(cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
	pace()
end

local function fillCylinder(cf: CFrame, height: number, radius: number, material: Enum.Material)
	terrain:FillCylinder(cf, height, radius, material)
	pace()
end

-- Spherical obstacles per zone (fish spawns avoid them)
TerrainGen.obstacles = {} :: { [number]: { Obstacle } }
TerrainGen.ledges = {} :: { Ledge }
TerrainGen.floaters = {} :: { Floater }
TerrainGen.arches = {} :: { Vector3 }

local function addObstacle(zoneIndex: number, center: Vector3, radius: number)
	local list = TerrainGen.obstacles[zoneIndex]
	if not list then
		list = {}
		TerrainGen.obstacles[zoneIndex] = list
	end
	table.insert(list, { center = center, radius = radius })
end

local function disc(cx: number, cz: number, y0: number, y1: number, radius: number, material: Enum.Material)
	fillCylinder(CFrame.new(cx, (y0 + y1) / 2, cz), y1 - y0, radius, material)
end

-- A ring wall made of straight blocks (inner face at innerR).
local function ring(innerR: number, thickness: number, y0: number, y1: number, material: Enum.Material, segments: number)
	local rc = innerR + thickness / 2
	local arc = 2 * math.pi * rc / segments * 1.2
	local height = y1 - y0
	local cy = (y0 + y1) / 2
	for i = 0, segments - 1 do
		local theta = (i / segments) * math.pi * 2
		local pos = Vector3.new(math.cos(theta) * rc, cy, math.sin(theta) * rc)
		fillBlock(CFrame.lookAt(pos, Vector3.new(0, cy, 0)), Vector3.new(arc, height, thickness), material)
	end
end

local function randomInDisc(rng: Random, radius: number): (number, number)
	local r = radius * math.sqrt(rng:NextNumber())
	local theta = rng:NextNumber(0, math.pi * 2)
	return math.cos(theta) * r, math.sin(theta) * r
end

local function wallBoulders(zoneIndex: number, rng: Random, count: number, material: Enum.Material, minY: number, maxY: number)
	local zone = Zones.list[zoneIndex]
	for _ = 1, count do
		local theta = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(14, 34)
		local r = zone.radius + radius * 0.35
		local y = rng:NextNumber(minY, maxY)
		local center = Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r)
		fillBall(center, radius, material)
		addObstacle(zoneIndex, center, radius)
	end
end

local function floorMounds(zoneIndex: number, rng: Random, count: number, material: Enum.Material, maxRadius: number)
	local zone = Zones.list[zoneIndex]
	for _ = 1, count do
		local x, z = randomInDisc(rng, zone.radius - 25)
		if not WorldGeometry.inHole(zoneIndex, x, z, -(maxRadius + 6)) then
			local y = WorldGeometry.floorY(zoneIndex, x, z)
			local radius = rng:NextNumber(6, maxRadius)
			local center = Vector3.new(x, y - radius * 0.55, z)
			fillBall(center, radius, material)
			addObstacle(zoneIndex, center, radius)
		end
	end
end

local function ledges(zoneIndex: number, rng: Random, count: number, material: Enum.Material)
	local zone = Zones.list[zoneIndex]
	local floorTop = zone.bottomY + zone.floorThickness
	local top = WorldGeometry.ceilingY(zoneIndex, zone.radius, 0)
	for _ = 1, count do
		local theta = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(floorTop + 45, top - 60)
		local depth = rng:NextNumber(26, 40)
		local width = rng:NextNumber(30, 50)
		local thick = rng:NextNumber(8, 14)
		local rc = zone.radius - depth / 2 + 6
		local pos = Vector3.new(math.cos(theta) * rc, y, math.sin(theta) * rc)
		local cf = CFrame.lookAt(pos, Vector3.new(0, y, 0))
		fillBlock(cf, Vector3.new(width, thick, depth + 12), material)
		fillBall(pos + Vector3.new(0, -thick * 0.6, 0) + cf.LookVector * -4, thick * 1.1, material)
		local topPoint = pos + Vector3.new(0, thick / 2, 0) + cf.LookVector * (depth * 0.15)
		table.insert(TerrainGen.ledges, { top = topPoint, zone = zoneIndex, normal = cf.LookVector })
		addObstacle(zoneIndex, pos, math.max(width, depth) / 2 + thick)
	end
end

local function arches(zoneIndex: number, rng: Random, count: number, material: Enum.Material)
	local zone = Zones.list[zoneIndex]
	for _ = 1, count do
		local x, z = randomInDisc(rng, zone.radius - 80)
		if not WorldGeometry.inHole(zoneIndex, x, z, -40) then
			local floor = WorldGeometry.floorY(zoneIndex, x, z)
			local yaw = rng:NextNumber(0, math.pi * 2)
			local base = CFrame.new(x, floor, z) * CFrame.Angles(0, yaw, 0)
			local height = rng:NextNumber(40, 60)
			local span = rng:NextNumber(26, 36)
			fillBlock(base * CFrame.new(-span / 2, height / 2, 0), Vector3.new(9, height, 9), material)
			fillBlock(base * CFrame.new(span / 2, height / 2, 0), Vector3.new(9, height, 9), material)
			fillBlock(base * CFrame.new(0, height, 0), Vector3.new(span + 12, 10, 10), material)
			fillBall((base * CFrame.new(0, height + 2, 0)).Position, 9, material)
			table.insert(TerrainGen.arches, (base * CFrame.new(0, 0, 0)).Position)
			addObstacle(zoneIndex, (base * CFrame.new(0, height / 2, 0)).Position, span / 2 + height / 2)
		end
	end
end

local function floaters(zoneIndex: number, rng: Random, count: number, material: Enum.Material)
	local zone = Zones.list[zoneIndex]
	local floorTop = zone.bottomY + zone.floorThickness
	for _ = 1, count do
		local x, z = randomInDisc(rng, zone.radius - 90)
		local y = rng:NextNumber(floorTop + 60, zone.topY - 90)
		local radius = rng:NextNumber(10, 20)
		local center = Vector3.new(x, y, z)
		fillBall(center, radius, material)
		fillBall(center + Vector3.new(rng:NextNumber(-6, 6), -radius * 0.6, rng:NextNumber(-6, 6)), radius * 0.7, material)
		table.insert(TerrainGen.floaters, { center = center, radius = radius, zone = zoneIndex })
		addObstacle(zoneIndex, center, radius + 6)
	end
end

local function colors()
	for _, zone in Zones.list do
		terrain:SetMaterialColor(zone.materials.floor, zone.materialColors.floor)
		terrain:SetMaterialColor(zone.materials.wall, zone.materialColors.wall)
		terrain:SetMaterialColor(zone.materials.accent, zone.materialColors.accent)
	end
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(110, 175, 80))
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(100, 165, 75))
	terrain:SetMaterialColor(Enum.Material.Sand, Zones.list[1].materialColors.floor)
	-- natural sea water: deep teal-blue, clear near the shore, darkening with depth
	terrain.WaterColor = Color3.fromRGB(14, 78, 96)
	terrain.WaterTransparency = 0.45
	terrain.WaterReflectance = 0.5
	terrain.WaterWaveSize = 0.14
	terrain.WaterWaveSpeed = 7
	terrain.Decoration = true -- animated grass blades on the island
end

local function buildLagoon(rng: Random)
	local zone = Zones.list[1]
	local world = Zones.world
	local outer = world.atollOuterRadius
	-- Atoll ring: limestone reef wall topped with sand, rising just above the water
	ring(zone.radius, outer - zone.radius, zone.bottomY, -12, zone.materials.wall, 56)
	ring(zone.radius, outer - zone.radius, -12, world.atollTopY, Enum.Material.Sand, 56)
	-- Terraced floor
	disc(0, 0, zone.bottomY, (zone.terraces :: any)[1].y, zone.radius + 12, zone.materials.floor)
	local terraces = zone.terraces :: { { r: number, y: number } }
	for i = 2, #terraces do
		disc(0, 0, terraces[i].y, terraces[i - 1].y, terraces[i].r, AIR)
	end
	local hole = zone.hole :: { x: number, z: number, r: number }
	disc(hole.x, hole.z, zone.bottomY - 2, terraces[#terraces].y + 1, hole.r, AIR)
	-- Soften terrace lips with rocks
	for i = 2, #terraces do
		local r = terraces[i].r
		local count = math.floor(r / 12)
		for j = 1, count do
			local theta = (j / count) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
			local radius = rng:NextNumber(5, 11)
			local center = Vector3.new(math.cos(theta) * (r + 2), terraces[i - 1].y - radius * 0.4, math.sin(theta) * (r + 2))
			fillBall(center, radius, if rng:NextNumber() < 0.5 then zone.materials.accent else zone.materials.wall)
		end
	end
	floorMounds(1, rng, 55, zone.materials.floor, 16)
	floorMounds(1, rng, 25, zone.materials.accent, 10)
	wallBoulders(1, rng, 40, zone.materials.wall, zone.bottomY + 40, -20)

end

-- The home island: a sandy beach that slopes gently into the sea on every side (so anyone who
-- ends up in the water can walk back out), a grassy middle, and a few rocky outcrops.
local function beachIsland(rng: Random)
	local world = Zones.world
	local dock = world.dockCenter
	local R = world.dockRadius
	local top = world.atollTopY
	-- rings from the outside in: each higher disc overwrites the middle of the one below
	-- heights sit on (or below) the 4-stud voxel grid: terrain rounds partial voxels up
	local rings = {
		{ r = R + 44, y = -20 },
		{ r = R + 34, y = -12 },
		{ r = R + 24, y = -8 },
		{ r = R + 14, y = -4 },
		{ r = R + 4, y = 0 },
		{ r = R - 8, y = 2 },
		{ r = R - 20, y = top },
	}
	for _, ring in rings do
		disc(dock.X, dock.Z, -36, ring.y, ring.r, Enum.Material.Sand)
	end
	-- grassy dunes in the middle of the island (south of the plaza)
	for _ = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(20, R - 80)
		local x, z = dock.X + math.cos(angle) * r, dock.Z - 30 + math.sin(angle) * r * 0.6
		if z < world.plazaCenter.Z - 70 then
			fillCylinder(CFrame.new(x, top - 2, z), 4, rng:NextNumber(16, 30), Enum.Material.Grass)
		end
	end
	-- rocky outcrops at the waterline
	for i = 1, 14 do
		local angle = (i / 14) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local r = R + rng:NextNumber(4, 18)
		local center = Vector3.new(dock.X + math.cos(angle) * r, rng:NextNumber(-4, 0), dock.Z + math.sin(angle) * r)
		if center.Z < world.plazaCenter.Z - 40 then
			fillBall(center, rng:NextNumber(4, 8), Enum.Material.Sandstone)
			fillBall(center + Vector3.new(rng:NextNumber(-4, 4), -1, rng:NextNumber(-4, 4)), rng:NextNumber(3, 5), Enum.Material.Limestone)
		end
	end
	-- keep the Blue Hole's rim clean where the island meets the atoll
	fillCylinder(CFrame.new(0, -17, 0), 58, Zones.list[1].radius - 2, AIR)
	-- shave anything above the land level (rotated atoll blocks and rounded voxels poke up
	-- through the dock deck otherwise)
	fillCylinder(CFrame.new(0, top + 16, 0), 32, world.atollOuterRadius + 12, AIR)
	fillBlock(CFrame.new(dock.X, top + 16, dock.Z), Vector3.new(2 * R + 120, 32, 2 * R + 120), AIR)
end

-- A sandy seabed under the open sea around the atoll, so the water is turquoise instead of a
-- sheet over the void. Filled in cells, skipping the Blue Hole inside the atoll.
local SEA_EXTENT = 3000
local SEABED_TOP = -24
local function seabed()
	local world = Zones.world
	local blueHole = Zones.list[1].radius + 10
	-- Visits square cells covering the sea, splitting cells that come closer than `minR` to the
	-- centre (down to 32 studs) so the Blue Hole inside the atoll is never touched.
	local function cells(minR: number, visit: (cx: number, cz: number, size: number) -> ())
		local function cell(cx: number, cz: number, size: number)
			local nearestX = math.max(math.abs(cx) - size / 2, 0)
			local nearestZ = math.max(math.abs(cz) - size / 2, 0)
			if math.sqrt(nearestX * nearestX + nearestZ * nearestZ) >= minR then
				visit(cx, cz, size)
			elseif size > 32 then
				local quarter = size / 4
				for dx = -1, 1, 2 do
					for dz = -1, 1, 2 do
						cell(cx + dx * quarter, cz + dz * quarter, size / 2)
					end
				end
			end
		end
		local size = 256
		local x = -SEA_EXTENT
		while x < SEA_EXTENT do
			local z = -SEA_EXTENT
			while z < SEA_EXTENT do
				cell(x + size / 2, z + size / 2, size)
				z += size
			end
			x += size
		end
	end
	-- sandy floor ~24 studs down, beyond the atoll's outer wall
	cells(world.atollOuterRadius - 30, function(cx, cz, size)
		fillBlock(CFrame.new(cx, SEABED_TOP - 12, cz), Vector3.new(size, 24, size), Enum.Material.Sand)
	end)
	-- deep water above it (only replaces air, so the atoll rock and island stay)
	cells(blueHole, function(cx, cz, size)
		local region = Region3.new(Vector3.new(cx - size / 2, SEABED_TOP, cz - size / 2), Vector3.new(cx + size / 2, -world.waterDepth, cz + size / 2))
		terrain:ReplaceMaterial(region:ExpandToGrid(4), 4, AIR, Enum.Material.Water)
		pace()
	end)
end

local function buildZone(index: number, rng: Random)
	local zone = Zones.list[index]
	local world = Zones.world
	local mats = zone.materials
	-- Walls
	ring(zone.radius, world.wallThickness, zone.bottomY, zone.topY, mats.wall, 48)
	-- Floor slab with its hole
	disc(0, 0, zone.bottomY, zone.bottomY + zone.floorThickness, zone.radius + 30, mats.floor)
	local hole = zone.hole
	if hole then
		disc(hole.x, hole.z, zone.bottomY - 1, zone.bottomY + zone.floorThickness + 1, hole.r, AIR)
	end
	-- Ceiling ring where this zone is wider than the one above
	if WorldGeometry.hasCeilingRing(index) then
		local ceilingTop = zone.topY
		local ceilingBottom = zone.topY - world.ceilingThickness
		disc(0, 0, ceilingBottom, ceilingTop, zone.radius + 30, mats.wall)
		disc(0, 0, ceilingBottom - 1, ceilingTop, WorldGeometry.ceilingRingInner(index), AIR)
	end
	local floorTop = zone.bottomY + zone.floorThickness
	wallBoulders(index, rng, zone.decor.rocks or 40, mats.wall, floorTop - 10, zone.topY - 20)
	floorMounds(index, rng, 45, mats.floor, 18)
	floorMounds(index, rng, 20, mats.accent, 12)
	if zone.decor.ledges then
		ledges(index, rng, zone.decor.ledges, mats.wall)
	end
	if zone.decor.arches then
		arches(index, rng, zone.decor.arches, mats.wall)
	end
	if zone.decor.floaters then
		floaters(index, rng, zone.decor.floaters, mats.accent)
	end
end

local function water()
	-- Turn the air in the surface slab into water (never overwrites land).
	local world = Zones.world
	local y0 = -world.waterDepth
	local minX, maxX = -SEA_EXTENT, SEA_EXTENT
	local minZ, maxZ = -SEA_EXTENT, SEA_EXTENT
	local step = 512
	local x = minX
	while x < maxX do
		local z = minZ
		while z < maxZ do
			local region = Region3.new(Vector3.new(x, y0, z), Vector3.new(math.min(x + step, maxX), 0, math.min(z + step, maxZ)))
			terrain:ReplaceMaterial(region:ExpandToGrid(4), 4, AIR, Enum.Material.Water)
			pace()
			z += step
		end
		x += step
	end
end

-- Each stage is isolated so one failure can't leave the whole map missing.
local function stage(name: string, fn: () -> ())
	local ok, err = pcall(fn :: (...any) -> ...any)
	if not ok then
		warn(string.format("[DeepHaul] terrain stage %s failed: %s", name, tostring(err)))
	end
end

function TerrainGen.build()
	local rng = Random.new(20240601)
	sliceStart = os.clock()
	stage("colors", colors)
	stage("lagoon", function()
		buildLagoon(rng)
	end)
	stage("seabed", seabed)
	stage("island", function()
		beachIsland(rng)
	end)
	-- the surface water goes in early so the dock is surrounded by sea as soon as possible
	stage("water", water)
	for index = 2, Zones.count do
		stage("zone " .. index, function()
			buildZone(index, rng)
		end)
	end
end

return TerrainGen

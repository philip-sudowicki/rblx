--!strict
-- Beach dressing for the home island: leaning palms, striped umbrellas with towels and loungers,
-- tiki torches, surfboards, sandcastles, starfish and shells, a lifeguard tower facing the sea,
-- a boardwalk to the Resurface shrine and a welcome arch over the pier walkway.
-- Props are scattered deterministically and never placed on top of the dock buildings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Build = require(script.Parent.Build)

local Beach = {}

local rgb = Color3.fromRGB
local WOOD = rgb(150, 108, 70)
local WOOD_DARK = rgb(105, 74, 48)
local NAVY = rgb(20, 40, 70)
local CYAN = rgb(0, 214, 255)
local STRIPES = {
	{ rgb(240, 80, 70), rgb(250, 245, 235) },
	{ rgb(40, 150, 230), rgb(250, 245, 235) },
	{ rgb(255, 190, 40), rgb(255, 120, 60) },
	{ rgb(90, 200, 140), rgb(250, 245, 235) },
	{ rgb(200, 90, 200), rgb(255, 210, 90) },
}

type Rect = { x0: number, x1: number, z0: number, z1: number }
type Circle = { x: number, z: number, r: number }

local world = Zones.world
local dock = world.dockCenter

-- Areas kept clear (buildings, walkways, plots).
local RECTS: { Rect } = {
	{ x0 = -68, x1 = 68, z0 = -636, z1 = -508 }, -- plaza and leaderboards
	{ x0 = -84, x1 = 84, z0 = -542, z1 = -500 }, -- market and workshop
	{ x0 = 62, x1 = 96, z0 = -604, z1 = -572 }, -- shop kiosk
	{ x0 = -96, x1 = -58, z0 = -604, z1 = -572 }, -- quest board
	{ x0 = -172, x1 = -84, z0 = -766, z1 = -552 }, -- aquarium plots
	{ x0 = -14, x1 = 14, z0 = -534, z1 = -455 }, -- pier walkway
	{ x0 = -8, x1 = 8, z0 = -690, z1 = -630 }, -- boardwalk to the shrine
}
local CIRCLES: { Circle } = {
	{ x = 0, z = -700, r = 26 }, -- shrine
	{ x = 150, z = -775, r = 16 }, -- lighthouse
	{ x = 0, z = -836, r = 14 }, -- lifeguard tower
}

local taken: { Circle } = {}

local function free(x: number, z: number, radius: number): boolean
	for _, rect in RECTS do
		if x > rect.x0 - radius and x < rect.x1 + radius and z > rect.z0 - radius and z < rect.z1 + radius then
			return false
		end
	end
	for _, circle in CIRCLES do
		local dx, dz = x - circle.x, z - circle.z
		if dx * dx + dz * dz < (circle.r + radius) ^ 2 then
			return false
		end
	end
	for _, circle in taken do
		local dx, dz = x - circle.x, z - circle.z
		if dx * dx + dz * dz < (circle.r + radius) ^ 2 then
			return false
		end
	end
	return true
end

local function claim(x: number, z: number, radius: number)
	table.insert(taken, { x = x, z = z, r = radius })
end

-- Approximate sand height (matches the island rings in TerrainGen.beachIsland).
local function groundY(x: number, z: number): number
	local r = math.sqrt((x - dock.X) ^ 2 + (z - dock.Z) ^ 2)
	local R = world.dockRadius
	local profile = {
		{ r = R - 40, y = world.atollTopY },
		{ r = R - 28, y = world.atollTopY - 0.5 },
		{ r = R - 16, y = 3.5 },
		{ r = R - 8, y = 2 },
		{ r = R, y = 0 },
		{ r = R + 8, y = -2.5 },
	}
	if r <= profile[1].r then
		return profile[1].y
	end
	for i = 2, #profile do
		local a, b = profile[i - 1], profile[i]
		if r <= b.r then
			return a.y + (b.y - a.y) * (r - a.r) / (b.r - a.r)
		end
	end
	return -4
end

local function point(rng: Random, minR: number, maxR: number, radius: number): Vector3?
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(minR, maxR)
		local x, z = dock.X + math.cos(angle) * r, dock.Z + math.sin(angle) * r
		if free(x, z, radius) then
			claim(x, z, radius)
			return Vector3.new(x, groundY(x, z), z)
		end
	end
	return nil
end

-- Yaw that faces away from the island centre (towards the sea).
local function seaward(position: Vector3): number
	return math.atan2(-(position.X - dock.X), -(position.Z - dock.Z)) + math.pi
end

---------------------------------------------------------------- props

function Beach.palm(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "Palm")
	local lean = rng:NextNumber(0.12, 0.32)
	local cf = CFrame.new(base - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local segments = 8
	local height = rng:NextNumber(2.2, 2.8)
	for i = 1, segments do
		local seg = cf * CFrame.Angles(lean * (i / segments) ^ 1.5, 0, 0) * CFrame.new(0, height / 2, 0)
		local width = 1.9 - i * 0.1
		Build.cylinder(model, height + 0.3, width, seg * CFrame.Angles(0, 0, math.pi / 2), if i % 2 == 0 then rgb(150, 112, 74) else rgb(128, 94, 62), Enum.Material.Wood)
		cf = seg * CFrame.new(0, height / 2, 0)
	end
	local top = cf.Position
	local leaves = rng:NextInteger(7, 9)
	for leaf = 1, leaves do
		local angle = leaf / leaves * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local green = rgb(58, 150, 62):Lerp(rgb(128, 196, 84), rng:NextNumber())
		local base0 = CFrame.new(top) * CFrame.Angles(0, angle, 0)
		-- two-part fronds that droop towards the tips
		Build.soft(Build.part(model, Vector3.new(2.4, 0.2, 5), base0 * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 0, -2.4), green, Enum.Material.Grass))
		Build.soft(Build.part(model, Vector3.new(1.6, 0.2, 5), base0 * CFrame.Angles(-0.25, 0, 0) * CFrame.new(0, 0, -4.8) * CFrame.Angles(0.55, 0, 0) * CFrame.new(0, 0, -2.3), green:Lerp(rgb(40, 110, 50), 0.3), Enum.Material.Grass))
	end
	for c = 1, rng:NextInteger(2, 4) do
		Build.soft(Build.ball(model, 1, top + Vector3.new(math.cos(c * 2.1) * 0.9, -0.9, math.sin(c * 2.1) * 0.9), rgb(96, 70, 38), Enum.Material.SmoothPlastic))
	end
end

local function umbrellaSet(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "BeachUmbrella")
	local colors = STRIPES[rng:NextInteger(1, #STRIPES)]
	local yaw = seaward(base)
	local origin = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	local tilt = rng:NextNumber(-0.15, 0.15)
	local poleTop = origin * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 8, 0)
	Build.cylinder(model, 8.6, 0.35, origin * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 3.8, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(235, 235, 235), Enum.Material.Metal)
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		local panel = poleTop * CFrame.Angles(0, angle, 0) * CFrame.Angles(0.32, 0, 0) * CFrame.new(0, -0.6, -2.3)
		Build.soft(Build.part(model, Vector3.new(1.55, 0.15, 4.8), panel, colors[(i % 2) + 1], Enum.Material.Fabric))
	end
	Build.soft(Build.ball(model, 0.6, poleTop.Position + Vector3.new(0, 0.3, 0), colors[1], Enum.Material.SmoothPlastic))
	-- towels and a lounger in its shade
	for side = -1, 1, 2 do
		local towel = origin * CFrame.new(side * 2.4, 0.1, 1.5) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0)
		local towelColors = STRIPES[rng:NextInteger(1, #STRIPES)]
		Build.soft(Build.part(model, Vector3.new(2.6, 0.12, 5.4), towel, towelColors[1], Enum.Material.Fabric))
		Build.soft(Build.part(model, Vector3.new(2.62, 0.13, 0.7), towel * CFrame.new(0, 0, -1.6), towelColors[2], Enum.Material.Fabric))
		Build.soft(Build.part(model, Vector3.new(2.62, 0.13, 0.7), towel * CFrame.new(0, 0, 1.6), towelColors[2], Enum.Material.Fabric))
	end
	if rng:NextNumber() < 0.6 then
		local lounger = origin * CFrame.new(5.5, 0, -1) * CFrame.Angles(0, 0.4, 0)
		Build.part(model, Vector3.new(2.4, 0.3, 5), lounger * CFrame.new(0, 1.2, 0.6), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		Build.part(model, Vector3.new(2.4, 0.3, 2.4), lounger * CFrame.new(0, 2, -2.5) * CFrame.Angles(0.7, 0, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		for lx = -1, 1, 2 do
			for lz = -1, 1, 2 do
				Build.part(model, Vector3.new(0.25, 1.1, 0.25), lounger * CFrame.new(lx * 1, 0.55, lz * 2.2), rgb(200, 200, 205), Enum.Material.Metal)
			end
		end
	end
	-- a cooler
	if rng:NextNumber() < 0.5 then
		local cooler = origin * CFrame.new(-4.8, 0.8, -1.5)
		Build.part(model, Vector3.new(2.2, 1.6, 1.4), cooler, colors[1], Enum.Material.SmoothPlastic)
		Build.part(model, Vector3.new(2.3, 0.3, 1.5), cooler * CFrame.new(0, 0.9, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
	end
end

local function tikiTorch(parent: Instance, base: Vector3)
	local model = Build.model(parent, "TikiTorch")
	Build.pillar(model, 6.5, 0.5, base - Vector3.new(0, 0.5, 0), rgb(170, 140, 80), Enum.Material.Wood)
	for ring = 1, 3 do
		Build.pillar(model, 0.2, 0.6, base + Vector3.new(0, ring * 1.6 - 0.5, 0), rgb(110, 80, 40), Enum.Material.Wood)
	end
	local bowl = Build.soft(Build.part(model, Vector3.new(1.2, 1, 1.2), CFrame.new(base + Vector3.new(0, 6.3, 0)), rgb(90, 60, 30), Enum.Material.Wood))
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = rgb(255, 140, 40)
	fire.SecondaryColor = rgb(255, 220, 90)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 160, 70)
	light.Range = 16
	light.Brightness = 1.4
	light.Parent = bowl
end

local function surfboard(parent: Instance, base: Vector3, rng: Random)
	local board = Build.part(parent, Vector3.new(2, 7.5, 0.45), CFrame.new(base + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.25, 0.25)), STRIPES[rng:NextInteger(1, #STRIPES)][1], Enum.Material.SmoothPlastic)
	board.Name = "Surfboard"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = board
	local stripe = Build.soft(Build.part(parent, Vector3.new(0.3, 7, 0.5), board.CFrame, rgb(250, 250, 250), Enum.Material.SmoothPlastic))
	local stripeMesh = Instance.new("SpecialMesh")
	stripeMesh.MeshType = Enum.MeshType.Sphere
	stripeMesh.Parent = stripe
end

local function sandcastle(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "Sandcastle")
	local color = rgb(222, 196, 140)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local origin = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	Build.part(model, Vector3.new(5, 1.4, 5), origin * CFrame.new(0, 0.5, 0), color, Enum.Material.Sand)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			Build.pillar(model, 2.6, 1.3, (origin * CFrame.new(x * 2, 1, z * 2)).Position, color, Enum.Material.Sand)
		end
	end
	Build.pillar(model, 3.4, 2, (origin * CFrame.new(0, 1, 0)).Position, color, Enum.Material.Sand)
	Build.soft(Build.part(model, Vector3.new(0.1, 1.2, 0.8), origin * CFrame.new(0.3, 5.2, 0), rgb(240, 80, 70), Enum.Material.Fabric))
	Build.soft(Build.part(model, Vector3.new(0.12, 1.8, 0.12), origin * CFrame.new(0, 4.9, 0), rgb(120, 90, 50), Enum.Material.Wood))
end

local function starfish(parent: Instance, base: Vector3, rng: Random)
	local color = ({ rgb(255, 130, 80), rgb(255, 170, 60), rgb(230, 90, 120) })[rng:NextInteger(1, 3)]
	local origin = CFrame.new(base + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for arm = 1, 5 do
		Build.soft(Build.part(parent, Vector3.new(0.5, 0.2, 1.2), origin * CFrame.Angles(0, arm / 5 * math.pi * 2, 0) * CFrame.new(0, 0, -0.55), color, Enum.Material.SmoothPlastic))
	end
end

local function driftwood(parent: Instance, base: Vector3, rng: Random)
	local cf = CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	Build.cylinder(parent, rng:NextNumber(6, 10), rng:NextNumber(0.9, 1.4), cf * CFrame.Angles(0, 0, rng:NextNumber(-0.1, 0.1)), rgb(170, 150, 120), Enum.Material.Wood)
	Build.cylinder(parent, 3, 0.5, cf * CFrame.new(1.5, 0.3, 0.8) * CFrame.Angles(0, 0.8, 0.3), rgb(160, 140, 110), Enum.Material.Wood)
end

local function lifeguardTower(parent: Instance, base: Vector3)
	local model = Build.model(parent, "LifeguardTower")
	local origin = CFrame.new(base) * CFrame.Angles(0, seaward(base), 0)
	local white = rgb(245, 245, 240)
	local red = rgb(225, 60, 55)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			Build.part(model, Vector3.new(0.8, 9, 0.8), origin * CFrame.new(x * 3.2, 4, z * 3.2) * CFrame.Angles(z * 0.08, 0, -x * 0.08), white, Enum.Material.Wood)
		end
	end
	Build.part(model, Vector3.new(8.5, 0.6, 8.5), origin * CFrame.new(0, 8.6, 0), WOOD, Enum.Material.WoodPlanks)
	Build.part(model, Vector3.new(7, 5, 0.4), origin * CFrame.new(0, 11.4, 3.3), red, Enum.Material.WoodPlanks)
	for x = -1, 1, 2 do
		Build.part(model, Vector3.new(0.4, 5, 7), origin * CFrame.new(x * 3.3, 11.4, 0), red, Enum.Material.WoodPlanks)
	end
	Build.part(model, Vector3.new(7, 1.4, 0.3), origin * CFrame.new(0, 9.6, -3.3), white, Enum.Material.WoodPlanks)
	Build.wedge(model, Vector3.new(9, 2, 4.8), origin * CFrame.new(0, 14.9, -2.3), white, Enum.Material.WoodPlanks)
	Build.wedge(model, Vector3.new(9, 2, 4.8), origin * CFrame.new(0, 14.9, 2.3) * CFrame.Angles(0, math.pi, 0), white, Enum.Material.WoodPlanks)
	-- ladder at the back
	for step = 1, 7 do
		Build.part(model, Vector3.new(2.4, 0.3, 0.4), origin * CFrame.new(0, step * 1.2, 5.2), WOOD_DARK, Enum.Material.Wood)
	end
	for x = -1, 1, 2 do
		Build.part(model, Vector3.new(0.3, 9, 0.3), origin * CFrame.new(x * 1.3, 4.5, 5.3), WOOD_DARK, Enum.Material.Wood)
	end
	-- flag and life ring
	Build.part(model, Vector3.new(0.25, 6, 0.25), origin * CFrame.new(3.6, 18, 3.6), white, Enum.Material.Metal)
	Build.soft(Build.part(model, Vector3.new(0.1, 1.6, 2.6), origin * CFrame.new(3.6, 20.2, 2.3), red, Enum.Material.Fabric))
	local ring = Build.soft(Build.cylinder(model, 0.5, 2.4, origin * CFrame.new(0, 11.4, 3.6) * CFrame.Angles(0, math.pi / 2, 0), rgb(250, 120, 40), Enum.Material.SmoothPlastic))
	ring.Name = "LifeRing"
end

local function boardwalk(parent: Instance)
	local model = Build.model(parent, "Boardwalk")
	local z = -630
	while z > -688 do
		Build.part(model, Vector3.new(8, 0.6, 3.6), CFrame.new(0, world.atollTopY + 0.3, z), if math.floor(z) % 2 == 0 then WOOD else rgb(160, 118, 78), Enum.Material.WoodPlanks)
		z -= 4
	end
	for zz = -634, -684, -12 do
		for side = -1, 1, 2 do
			Build.part(model, Vector3.new(0.6, 2.6, 0.6), CFrame.new(side * 4.4, world.atollTopY + 1.3, zz), WOOD_DARK, Enum.Material.Wood)
		end
	end
end

local function welcomeArch(parent: Instance)
	local model = Build.model(parent, "WelcomeArch")
	local z = -532
	local y = world.atollTopY + 1
	for side = -1, 1, 2 do
		Build.cylinder(model, 16, 2.2, CFrame.new(side * 10, y + 8, z) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, Enum.Material.Wood)
		Build.soft(Build.ball(model, 2.6, Vector3.new(side * 10, y + 16.5, z), rgb(255, 200, 70), Enum.Material.Neon))
		tikiTorch(model, Vector3.new(side * 14, y, z + 3))
	end
	Build.part(model, Vector3.new(24, 1.4, 2.4), CFrame.new(0, y + 15.2, z), WOOD, Enum.Material.WoodPlanks)
	local signPos = Vector3.new(0, y + 12.6, z)
	Build.sign(model, Vector3.new(18, 3.6, 0.6), CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, -10)), "⚓ DIVE THE BLUE HOLE", NAVY, CYAN, Enum.Material.SmoothPlastic)
end

function Beach.build(parent: Instance)
	local folder = Build.folder(parent, "Beach")
	local rng = Random.new(1606)
	table.clear(taken)
	boardwalk(folder)
	welcomeArch(folder)
	lifeguardTower(folder, Vector3.new(0, groundY(0, -836), -836))
	-- palms: a ring near the shore and a few inland
	for _ = 1, 26 do
		local p = point(rng, 120, 182, 7)
		if p then
			Beach.palm(folder, p, rng)
		end
	end
	for _ = 1, 10 do
		local p = point(rng, 40, 120, 8)
		if p then
			Beach.palm(folder, p, rng)
		end
	end
	for _ = 1, 9 do
		local p = point(rng, 150, 184, 9)
		if p then
			umbrellaSet(folder, p, rng)
		end
	end
	for _ = 1, 7 do
		local p = point(rng, 150, 186, 3)
		if p then
			surfboard(folder, p, rng)
		end
	end
	for _ = 1, 5 do
		local p = point(rng, 160, 190, 5)
		if p then
			sandcastle(folder, p, rng)
		end
	end
	for _ = 1, 6 do
		local p = point(rng, 150, 192, 6)
		if p then
			driftwood(folder, p, rng)
		end
	end
	for _ = 1, 22 do
		local p = point(rng, 170, 198, 1)
		if p then
			starfish(folder, p, rng)
		end
	end
	-- torches line the plaza edge and the boardwalk
	for i = 0, 5 do
		tikiTorch(folder, Vector3.new(if i % 2 == 0 then -6.5 else 6.5, world.atollTopY + 0.4, -636 - math.floor(i / 2) * 16))
	end
	for _, x in { -68, 68 } do
		for _, z in { -512, -630 } do
			tikiTorch(folder, Vector3.new(x, world.atollTopY + 0.4, z))
		end
	end
end

return Beach

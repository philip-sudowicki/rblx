--!strict
-- The dock hub on the atoll island: pier + launch bay, market, workshop, shop, quest board,
-- daily chest, leaderboards, lighthouse, palms, lamps and
-- the invisible character barriers. Interactive spots are ProximityPrompts carrying a
-- "DeepHaulAction" attribute; the client opens UI and the server validates the action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local Build = require(script.Parent.Build)
local Beach = require(script.Parent.Beach)
local SubModel = require(Shared.Models.SubModel)

export type DockResult = {
	folder: Folder,
	prompts: { [string]: ProximityPrompt },
	boards: { [string]: Part },
	spawnPoints: { Vector3 },
	barrierParts: { BasePart },
}

local Dock = {}

local rgb = Color3.fromRGB
local WOOD = rgb(176, 132, 88)
local WOOD_DARK = rgb(120, 86, 56)
local ROPE = rgb(210, 190, 150)
local NAVY = rgb(20, 40, 70)
local CYAN = rgb(0, 214, 255)

local function prompt(parent: BasePart, action: string, actionText: string, objectText: string, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 14
	p.RequiresLineOfSight = false
	p:SetAttribute("DeepHaulAction", action)
	p.Parent = parent
	return p
end

local function anchor(parent: Instance, name: string, position: Vector3): Part
	local p = Build.part(parent, Vector3.new(1, 1, 1), CFrame.new(position), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
	Build.soft(p)
	p.Name = name
	return p
end

-- Face a building toward a point (its LookVector / local -Z becomes the front).
local function facing(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	return CFrame.lookAt(position, flatTarget)
end

local function lamp(parent: Instance, base: Vector3)
	-- a wooden post with a small warm lantern (not a bright white orb)
	Build.pillar(parent, 8, 0.7, base, rgb(92, 66, 44), Enum.Material.Wood)
	Build.part(parent, Vector3.new(1.6, 0.3, 1.6), CFrame.new(base + Vector3.new(0, 8.1, 0)), rgb(50, 44, 40), Enum.Material.Metal)
	local bulb = Build.soft(Build.part(parent, Vector3.new(1, 1.3, 1), CFrame.new(base + Vector3.new(0, 8.9, 0)), rgb(255, 190, 110), Enum.Material.Neon, { Transparency = 0.15 }))
	Build.part(parent, Vector3.new(1.5, 0.4, 1.5), CFrame.new(base + Vector3.new(0, 9.75, 0)), rgb(50, 44, 40), Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 190, 120)
	light.Range = 16
	light.Brightness = 0.9
	light.Parent = bulb
end

local function crate(parent: Instance, position: Vector3, yaw: number, size: number)
	Build.part(parent, Vector3.new(size, size, size), CFrame.new(position + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, yaw, 0), WOOD_DARK, Enum.Material.WoodPlanks)
end

local function barrel(parent: Instance, position: Vector3)
	Build.pillar(parent, 3.2, 2.4, position, rgb(130, 90, 55), Enum.Material.Wood)
end

---------------------------------------------------------------- buildings
local function launchBay(folder: Folder, prompts: { [string]: ProximityPrompt })
	local world = Zones.world
	local model = Build.model(folder, "LaunchBay")
	local pierY = world.pierEnd.Y - 0.5
	-- walkway from the plaza to the pier
	-- (walkway, pier and platform butt together end to end: no overlapping, flickering planks)
	local plazaEdge = world.plazaCenter.Z + 54
	local walkLength = world.pierStart.Z + 2 - plazaEdge
	Build.part(model, Vector3.new(16, 1, walkLength), CFrame.new(0, pierY, plazaEdge + walkLength / 2), WOOD, Enum.Material.WoodPlanks)
	-- pier
	local pierFrom = world.pierStart.Z + 2
	local pierTo = world.pierEnd.Z - 9 -- where the launch platform begins
	local pierLength = pierTo - pierFrom
	local pierMidZ = (pierFrom + pierTo) / 2
	Build.part(model, Vector3.new(22, 1, pierLength), CFrame.new(0, pierY, pierMidZ), WOOD, Enum.Material.WoodPlanks)
	for z = world.pierStart.Z + 2, world.pierEnd.Z - 2, 10 do
		for side = -1, 1, 2 do
			Build.pillar(model, 22, 1.4, Vector3.new(side * 10, -16, z), WOOD_DARK, Enum.Material.Wood)
			Build.part(model, Vector3.new(0.5, 3, 0.5), CFrame.new(side * 10.8, pierY + 2, z), WOOD_DARK, Enum.Material.Wood)
		end
	end
	for side = -1, 1, 2 do
		Build.part(model, Vector3.new(0.4, 0.4, pierLength), CFrame.new(side * 10.8, pierY + 3.4, pierMidZ), ROPE, Enum.Material.Fabric)
	end
	-- launch platform
	local platformZ = world.pierEnd.Z
	Build.part(model, Vector3.new(38, 1, 18), CFrame.new(0, pierY, platformZ), rgb(200, 160, 110), Enum.Material.WoodPlanks)
	for side = -1, 1, 2 do
		-- steps down into the water on both sides
		for step = 1, 4 do
			Build.part(model, Vector3.new(4, 1, 6), CFrame.new(side * (19 + step * 3), pierY - step * 1.6, platformZ), WOOD_DARK, Enum.Material.WoodPlanks)
		end
		Build.part(model, Vector3.new(2, 16, 2), CFrame.new(side * 16, pierY + 8.5, platformZ + 6), rgb(230, 190, 40), Enum.Material.Metal)
	end
	Build.part(model, Vector3.new(34, 2.4, 2.4), CFrame.new(0, pierY + 16.5, platformZ + 6), rgb(230, 190, 40), Enum.Material.Metal)
	local signPos = Vector3.new(0, pierY + 16.5, platformZ + 4.6)
	Build.sign(model, Vector3.new(22, 4, 0.5), facing(signPos, signPos + Vector3.new(0, 0, -10)), "LAUNCH BAY", NAVY, CYAN, Enum.Material.SmoothPlastic)
	-- console
	local console = Build.part(model, Vector3.new(3, 3.6, 2), CFrame.new(9, pierY + 2.3, platformZ - 4), rgb(50, 56, 66), Enum.Material.Metal)
	Build.soft(Build.part(model, Vector3.new(2.4, 1.4, 0.2), console.CFrame * CFrame.new(0, 0.9, -1.05), CYAN, Enum.Material.Neon))
	-- the launch prompt sits in the middle of the platform
	local launchAnchor = anchor(model, "LaunchPrompt", Vector3.new(0, pierY + 3, platformZ))
	prompts.Launch = prompt(launchAnchor, "Launch", "Dive!", "Launch Bay", Game.Dock.BoardRange)
	-- glowing launch ring on the water
	local ring = Build.soft(Build.cylinder(model, 0.4, 22, CFrame.new(world.launchPoint.X, -0.3, world.launchPoint.Z) * CFrame.Angles(0, 0, math.pi / 2), CYAN, Enum.Material.Neon, { Transparency = 0.55 }))
	ring.Name = "LaunchRing"
	Build.tag(ring, "LaunchRing")
	-- buoys marking the dive area
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local pos = Vector3.new(world.launchPoint.X + math.cos(angle) * 30, -0.4, world.launchPoint.Z + math.sin(angle) * 30)
		local buoy = Build.model(model, "Buoy")
		Build.soft(Build.ball(buoy, 2.4, pos, if i % 2 == 0 then rgb(255, 80, 70) else rgb(250, 250, 250), Enum.Material.SmoothPlastic))
		Build.soft(Build.part(buoy, Vector3.new(0.3, 3, 0.3), CFrame.new(pos + Vector3.new(0, 2, 0)), rgb(60, 60, 60), Enum.Material.Metal))
		Build.tag(buoy, "Buoy")
	end
	-- launch crane: your sub hangs from the hook over the dive area (the client draws it) and is
	-- dropped into the water when you launch
	local yellow = rgb(240, 190, 30)
	local mastBase = Vector3.new(-17, pierY, platformZ + 4)
	local boomY = pierY + 28
	Build.part(model, Vector3.new(4, 1, 4), CFrame.new(mastBase + Vector3.new(0, 0.5, 0)), rgb(60, 64, 72), Enum.Material.DiamondPlate)
	Build.part(model, Vector3.new(2.2, 28, 2.2), CFrame.new(mastBase + Vector3.new(0, 14, 0)), yellow, Enum.Material.Metal)
	for i = 1, 6 do
		Build.part(model, Vector3.new(2.4, 0.3, 2.4), CFrame.new(mastBase + Vector3.new(0, i * 4, 0)), rgb(40, 40, 44), Enum.Material.Metal)
	end
	local hang = world.launchHang
	local tip = Vector3.new(hang.X, boomY, hang.Z)
	local root = mastBase + Vector3.new(0, 28, 0)
	local boomLength = (tip - root).Magnitude + 6
	local boomCf = CFrame.lookAt((root + tip) / 2, tip) * CFrame.new(0, 0, -2)
	Build.part(model, Vector3.new(1.8, 1.8, boomLength), boomCf, yellow, Enum.Material.Metal)
	Build.part(model, Vector3.new(3, 3, 3), CFrame.lookAt(root, tip) * CFrame.new(0, 0, 3), rgb(60, 64, 72), Enum.Material.Metal) -- counterweight
	Build.part(model, Vector3.new(2, 1.2, 2), CFrame.new(tip - Vector3.new(0, 1.2, 0)), rgb(40, 40, 44), Enum.Material.Metal)
	local cableTop = tip - Vector3.new(0, 1.8, 0)
	local cableBottom = hang + Vector3.new(0, 4, 0)
	Build.soft(Build.part(model, Vector3.new(0.25, (cableTop - cableBottom).Magnitude, 0.25), CFrame.new((cableTop + cableBottom) / 2), rgb(30, 30, 34), Enum.Material.Metal))
	local hook = Build.soft(Build.part(model, Vector3.new(1.4, 1, 1.4), CFrame.new(cableBottom), yellow, Enum.Material.Metal))
	hook.Name = "CraneHook"
	local warning = Build.soft(Build.ball(model, 0.8, root + Vector3.new(0, 1.8, 0), rgb(255, 120, 40), Enum.Material.Neon))
	local beacon = Instance.new("PointLight")
	beacon.Color = rgb(255, 140, 50)
	beacon.Range = 14
	beacon.Parent = warning
end

local function market(folder: Folder, prompts: { [string]: ProximityPrompt }, origin: CFrame)
	local model = Build.model(folder, "Market")
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		return Build.part(model, size, origin * offset, color, material)
	end
	add(Vector3.new(24, 1, 16), CFrame.new(0, 0.5, 0), WOOD, Enum.Material.WoodPlanks)
	add(Vector3.new(24, 10, 1), CFrame.new(0, 5.5, 7.5), WOOD_DARK, Enum.Material.WoodPlanks)
	add(Vector3.new(1, 10, 16), CFrame.new(-11.5, 5.5, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	add(Vector3.new(1, 10, 16), CFrame.new(11.5, 5.5, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	local counter = add(Vector3.new(20, 3.5, 2.5), CFrame.new(0, 2.75, -5.5), rgb(90, 140, 190), Enum.Material.WoodPlanks)
	add(Vector3.new(26, 1, 18), CFrame.new(0, 11, 0), WOOD_DARK, Enum.Material.WoodPlanks)
	for i = 0, 5 do
		local x = -10 + i * 4
		local color = if i % 2 == 0 then rgb(230, 70, 70) else rgb(250, 250, 250)
		Build.wedge(model, Vector3.new(4, 2, 5), origin * CFrame.new(x, 10.5, -10.5) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Fabric)
	end
	local signPos = (origin * CFrame.new(0, 13.8, -8)).Position
	Build.sign(model, Vector3.new(16, 3.4, 0.6), CFrame.lookAt(signPos, signPos + origin.LookVector), "FISH MARKET", NAVY, rgb(255, 210, 90), Enum.Material.SmoothPlastic)
	-- fish on ice
	local ice = add(Vector3.new(14, 0.6, 1.8), CFrame.new(0, 4.8, -5.5), rgb(220, 240, 255), Enum.Material.Ice)
	for i = 1, 6 do
		local color = ({ rgb(255, 150, 80), rgb(120, 190, 255), rgb(255, 220, 90), rgb(190, 120, 255) })[(i % 4) + 1]
		Build.soft(Build.ball(model, 1.2, (ice.CFrame * CFrame.new(-6 + i * 2, 0.7, 0)).Position, color, Enum.Material.SmoothPlastic))
	end
	crate(model, (origin * CFrame.new(-8, 1, 3)).Position, 0.3, 3)
	crate(model, (origin * CFrame.new(-4.5, 1, 4)).Position, -0.2, 2.5)
	barrel(model, (origin * CFrame.new(8, 1, 3)).Position)
	local anchorPart = anchor(model, "SellPrompt", (counter.CFrame * CFrame.new(0, 1.5, -1.5)).Position)
	prompts.Sell = prompt(anchorPart, "Sell", "Sell Haul", "Fish Market")
end

local function workshop(folder: Folder, prompts: { [string]: ProximityPrompt }, origin: CFrame)
	-- A steel-framed hangar: open front with a rolled-up shutter, a real sub on a cradle under a
	-- chain hoist, a tool wall, and the upgrade terminal at the front counter.
	local model = Build.model(folder, "Workshop")
	local steel = rgb(58, 64, 74)
	local panel = rgb(34, 88, 120)
	local yellow = rgb(255, 196, 40)
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		return Build.part(model, size, origin * offset, color, material)
	end
	local W, D, H = 30, 24, 15
	-- floor with a hazard edge
	add(Vector3.new(W, 1, D), CFrame.new(0, 0.5, 0), rgb(130, 132, 136), Enum.Material.Concrete)
	for i = 0, 9 do
		add(Vector3.new(W / 10, 0.12, 1), CFrame.new(-W / 2 + W / 20 + i * W / 10, 1.06, -D / 2 + 0.5), if i % 2 == 0 then yellow else rgb(30, 30, 34), Enum.Material.SmoothPlastic)
	end
	-- steel columns and header beam
	for _, x in { -W / 2 + 0.6, W / 2 - 0.6 } do
		for _, z in { -D / 2 + 0.6, 0, D / 2 - 0.6 } do
			add(Vector3.new(1.2, H, 1.2), CFrame.new(x, H / 2 + 1, z), steel, Enum.Material.Metal)
		end
	end
	add(Vector3.new(W, 1.6, 1.4), CFrame.new(0, H + 0.4, -D / 2 + 0.6), steel, Enum.Material.Metal)
	for i = 0, 11 do
		add(Vector3.new(W / 12, 0.6, 0.2), CFrame.new(-W / 2 + W / 24 + i * W / 12, H - 0.7, -D / 2 - 0.1), if i % 2 == 0 then yellow else rgb(30, 30, 34), Enum.Material.SmoothPlastic)
	end
	-- rolled-up shutter
	Build.cylinder(model, W - 2, 2.4, origin * CFrame.new(0, H - 2.2, -D / 2 + 1.6), rgb(150, 156, 164), Enum.Material.DiamondPlate)
	-- walls (diamond-plate panels with a trim line)
	add(Vector3.new(W, H, 0.6), CFrame.new(0, H / 2 + 1, D / 2 - 0.3), panel, Enum.Material.DiamondPlate)
	for side = -1, 1, 2 do
		add(Vector3.new(0.6, H, D), CFrame.new(side * (W / 2 - 0.3), H / 2 + 1, 0), panel, Enum.Material.DiamondPlate)
		-- a porthole window in each side wall
		local window = add(Vector3.new(0.7, 3.4, 3.4), CFrame.new(side * (W / 2 - 0.3), H / 2 + 2, 2), rgb(160, 220, 255), Enum.Material.Glass)
		window.Transparency = 0.4
		window.Shape = Enum.PartType.Cylinder
	end
	-- neon trim around the outside of the walls (strips, not a slab through the room)
	Build.soft(add(Vector3.new(W + 0.4, 0.35, 0.2), CFrame.new(0, 3.2, D / 2 + 0.1), CYAN, Enum.Material.Neon))
	for side = -1, 1, 2 do
		Build.soft(add(Vector3.new(0.2, 0.35, D + 0.4), CFrame.new(side * (W / 2 + 0.1), 3.2, 0), CYAN, Enum.Material.Neon))
	end
	-- roof: two slopes and a ridge, with neon trim along the front
	Build.wedge(model, Vector3.new(D + 1, 4, W / 2 + 0.5), origin * CFrame.new(-W / 4, H + 3.2, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(24, 44, 70), Enum.Material.Metal)
	Build.wedge(model, Vector3.new(D + 1, 4, W / 2 + 0.5), origin * CFrame.new(W / 4, H + 3.2, 0) * CFrame.Angles(0, -math.pi / 2, 0), rgb(24, 44, 70), Enum.Material.Metal)
	add(Vector3.new(1.2, 0.6, D + 1.2), CFrame.new(0, H + 5.3, 0), steel, Enum.Material.Metal)
	Build.soft(add(Vector3.new(W + 1, 0.3, 0.3), CFrame.new(0, H + 1.3, -D / 2 - 0.4), CYAN, Enum.Material.Neon))
	-- the sub on its cradle, under a chain hoist
	local subCf = origin * CFrame.new(-3, 5.4, 3) * CFrame.Angles(0, math.pi / 2, 0)
	local sub = SubModel.display("Default", subCf)
	sub.Parent = model
	for _, dz in { -4, 4 } do
		add(Vector3.new(6.5, 2.4, 1), CFrame.new(-3, 2.2, 3 + dz), yellow, Enum.Material.Metal)
	end
	add(Vector3.new(1, 1, 18), CFrame.new(-3, H - 0.2, 3), steel, Enum.Material.Metal)
	Build.soft(add(Vector3.new(0.3, 5.2, 0.3), CFrame.new(-3, H - 3.2, 3), rgb(80, 80, 86), Enum.Material.Metal))
	add(Vector3.new(1.6, 1.2, 1.2), CFrame.new(-3, H - 6, 3), yellow, Enum.Material.Metal)
	local sparks = Build.soft(add(Vector3.new(0.4, 0.4, 0.4), CFrame.new(1.2, 5.4, 3), rgb(255, 220, 140), Enum.Material.Neon))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(rgb(255, 230, 150), rgb(255, 140, 40))
	emitter.LightEmission = 1
	emitter.Rate = 18
	emitter.Lifetime = NumberRange.new(0.2, 0.5)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Parent = sparks
	-- tool wall and workbench along the back
	add(Vector3.new(12, 6, 0.3), CFrame.new(7, 8, D / 2 - 0.8), rgb(90, 70, 52), Enum.Material.Wood)
	local toolColors = { rgb(220, 60, 50), rgb(60, 130, 220), rgb(200, 200, 205), rgb(255, 196, 40) }
	for i = 1, 8 do
		local long = i % 3 == 0
		add(Vector3.new(0.4, if long then 3 else 2, 0.3), CFrame.new(2 + i * 1.25, 8 + (if i % 2 == 0 then 0.8 else -0.6), D / 2 - 1.1), toolColors[(i % 4) + 1], Enum.Material.Metal)
	end
	add(Vector3.new(12, 0.6, 3.4), CFrame.new(7, 3.8, D / 2 - 2.4), rgb(120, 86, 56), Enum.Material.WoodPlanks)
	add(Vector3.new(11.4, 2.8, 3), CFrame.new(7, 2.2, D / 2 - 2.4), rgb(70, 74, 82), Enum.Material.Metal)
	add(Vector3.new(2.6, 1.6, 1.6), CFrame.new(10, 4.9, D / 2 - 2.4), rgb(210, 50, 45), Enum.Material.Metal)
	barrel(model, (origin * CFrame.new(W / 2 - 2.5, 1, -D / 2 + 3)).Position)
	barrel(model, (origin * CFrame.new(W / 2 - 5.2, 1, -D / 2 + 2.6)).Position)
	-- hanging lamps
	for _, x in { -8, 0, 8 } do
		Build.soft(add(Vector3.new(0.2, 2, 0.2), CFrame.new(x, H - 1, -1), rgb(40, 40, 44), Enum.Material.Metal))
		Build.soft(add(Vector3.new(2.2, 0.6, 2.2), CFrame.new(x, H - 2.2, -1), rgb(40, 40, 44), Enum.Material.Metal))
		local bulb = Build.soft(Build.ball(model, 0.9, (origin * CFrame.new(x, H - 2.7, -1)).Position, rgb(255, 236, 190), Enum.Material.Neon))
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 230, 190)
		light.Range = 18
		light.Brightness = 1.3
		light.Parent = bulb
	end
	-- upgrade terminal at the front counter
	local counter = add(Vector3.new(9, 3.6, 3), CFrame.new(8, 2.8, -6), rgb(40, 48, 60), Enum.Material.Metal)
	Build.soft(add(Vector3.new(9.2, 0.3, 3.2), CFrame.new(8, 4.7, -6), CYAN, Enum.Material.Neon))
	local screen = add(Vector3.new(4.6, 2.8, 0.3), CFrame.new(8, 6.6, -5.2) * CFrame.Angles(-0.2, 0, 0), rgb(10, 20, 34), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = screen
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = CYAN
	text.Text = "SUB\nUPGRADES"
	text.Parent = gui
	local signPos = (origin * CFrame.new(0, H + 2.6, -D / 2 - 0.9)).Position
	Build.sign(model, Vector3.new(16, 3.4, 0.6), CFrame.lookAt(signPos, signPos + origin.LookVector), "🛠 WORKSHOP", NAVY, CYAN, Enum.Material.SmoothPlastic)
	local anchorPart = anchor(model, "UpgradePrompt", (counter.CFrame * CFrame.new(0, 1.4, -2.2)).Position)
	prompts.Upgrades = prompt(anchorPart, "Upgrades", "Upgrade Sub", "Workshop")
end

local function kiosk(folder: Folder, prompts: { [string]: ProximityPrompt }, origin: CFrame)
	-- a beach stall: wooden counter, striped coral/white awning, colourful goods on shelves
	local model = Build.model(folder, "ShopKiosk")
	local coral = rgb(236, 110, 90)
	local teal = rgb(40, 170, 170)
	Build.part(model, Vector3.new(14, 1, 9), origin * CFrame.new(0, 0.5, 1.5), WOOD, Enum.Material.WoodPlanks)
	local counter = Build.part(model, Vector3.new(11, 3.6, 3), origin * CFrame.new(0, 2.8, -1), teal, Enum.Material.WoodPlanks)
	Build.part(model, Vector3.new(11.4, 0.4, 3.4), origin * CFrame.new(0, 4.8, -1), WOOD, Enum.Material.WoodPlanks)
	Build.part(model, Vector3.new(12, 7, 0.6), origin * CFrame.new(0, 4.5, 5.6), WOOD_DARK, Enum.Material.WoodPlanks)
	for shelf = 0, 1 do
		Build.part(model, Vector3.new(10, 0.3, 1.4), origin * CFrame.new(0, 3.6 + shelf * 2.4, 4.8), WOOD, Enum.Material.Wood)
		for i = 0, 5 do
			local colors = { coral, teal, rgb(255, 200, 70), rgb(120, 160, 240), rgb(160, 220, 120), rgb(240, 150, 200) }
			Build.soft(Build.part(model, Vector3.new(1.1, 1.2, 1), origin * CFrame.new(-4.2 + i * 1.7, 4.4 + shelf * 2.4, 4.8), colors[(i + shelf * 2) % 6 + 1], Enum.Material.SmoothPlastic))
		end
	end
	for side = -1, 1, 2 do
		for _, z in { -2.4, 5.4 } do
			Build.part(model, Vector3.new(0.6, 9, 0.6), origin * CFrame.new(side * 6.4, 5, z), rgb(245, 243, 236), Enum.Material.Wood)
		end
	end
	for i = 0, 6 do
		local x = -6 + i * 2
		Build.wedge(model, Vector3.new(2, 1.6, 9.6), origin * CFrame.new(x, 10.2, 1.5) * CFrame.Angles(0, math.pi, 0), if i % 2 == 0 then coral else rgb(250, 245, 235), Enum.Material.Fabric)
	end
	local signPos = (origin * CFrame.new(0, 12.2, -1)).Position
	Build.sign(model, Vector3.new(9, 2.6, 0.5), CFrame.lookAt(signPos, signPos + origin.LookVector), "SHOP", NAVY, rgb(255, 210, 90), Enum.Material.SmoothPlastic)
	local anchorPart = anchor(model, "ShopPrompt", (counter.CFrame * CFrame.new(0, 1.8, -2.5)).Position)
	prompts.Shop = prompt(anchorPart, "Shop", "Open Shop", "Supply Kiosk")
end

local function questBoard(folder: Folder, prompts: { [string]: ProximityPrompt }, origin: CFrame)
	local model = Build.model(folder, "QuestBoard")
	for side = -1, 1, 2 do
		Build.part(model, Vector3.new(0.8, 10, 0.8), origin * CFrame.new(side * 6, 5, 0), WOOD_DARK, Enum.Material.Wood)
	end
	local board = Build.part(model, Vector3.new(11, 6.5, 0.6), origin * CFrame.new(0, 6.5, 0), rgb(150, 110, 70), Enum.Material.WoodPlanks)
	for i = 1, 6 do
		Build.soft(Build.part(model, Vector3.new(2.2, 2.4, 0.1), board.CFrame * CFrame.new(-3.8 + ((i - 1) % 3) * 3.8, if i <= 3 then 1.4 else -1.6, -0.35), rgb(245, 235, 210), Enum.Material.SmoothPlastic))
	end
	local signPos = (origin * CFrame.new(0, 11, -0.2)).Position
	Build.sign(model, Vector3.new(9, 2.4, 0.5), CFrame.lookAt(signPos, signPos + origin.LookVector), "QUESTS", NAVY, rgb(120, 255, 170), Enum.Material.SmoothPlastic)
	local anchorPart = anchor(model, "QuestPrompt", (board.CFrame * CFrame.new(0, -2.5, -2)).Position)
	prompts.Quests = prompt(anchorPart, "Quests", "View Quests", "Quest Board")
	-- daily reward chest beside the board
	local chest = Build.part(model, Vector3.new(4, 2.6, 3), origin * CFrame.new(9, 1.3, -1), rgb(140, 90, 40), Enum.Material.WoodPlanks)
	Build.part(model, Vector3.new(4.2, 1.2, 3.2), origin * CFrame.new(9, 3.2, -1), rgb(120, 76, 34), Enum.Material.WoodPlanks)
	Build.soft(Build.part(model, Vector3.new(4.3, 0.4, 0.4), origin * CFrame.new(9, 2.6, -2.6), rgb(255, 210, 70), Enum.Material.Neon))
	prompts.Daily = prompt(chest, "Daily", "Daily Reward", "Treasure Chest")
end

local BOARD_IDS = { "DeepestDive", "RarestCatch", "TotalHaul", "Rebirths" }
local BOARD_COLORS = { rgb(80, 190, 255), rgb(190, 120, 255), rgb(255, 200, 70), rgb(90, 225, 200) }

local function leaderboards(folder: Folder, boards: { [string]: Part })
	local model = Build.model(folder, "Leaderboards")
	local plaza = Zones.world.plazaCenter
	for i, id in BOARD_IDS do
		local accent = BOARD_COLORS[i]
		local x = -57 + (i - 1) * 38
		local base = Vector3.new(x, plaza.Y, plaza.Z - 58)
		-- stone plinth, two painted posts, the board and a glowing accent strip on top
		Build.part(model, Vector3.new(36, 2, 4), CFrame.new(base + Vector3.new(0, 0.6, 0)), rgb(150, 144, 132), Enum.Material.Cobblestone)
		for side = -1, 1, 2 do
			Build.part(model, Vector3.new(1.6, 27, 1.6), CFrame.new(base + Vector3.new(side * 16.6, 14, 0)), accent:Lerp(rgb(40, 50, 64), 0.45), Enum.Material.SmoothPlastic)
			Build.soft(Build.ball(model, 2.2, base + Vector3.new(side * 16.6, 28.2, 0), accent, Enum.Material.Neon))
		end
		local center = base + Vector3.new(0, 16, 0)
		local frame = Build.part(model, Vector3.new(33.4, 25.4, 0.8), CFrame.new(center + Vector3.new(0, 0, -0.2)), accent:Lerp(rgb(40, 50, 64), 0.3), Enum.Material.SmoothPlastic)
		frame.Name = "Frame_" .. id
		local board = Build.part(model, Vector3.new(32, 24, 1), CFrame.lookAt(center, center + Vector3.new(0, 0, 10)), rgb(16, 32, 54), Enum.Material.SmoothPlastic)
		board.Name = "Board_" .. id
		Build.soft(Build.part(model, Vector3.new(33.4, 0.5, 1.2), CFrame.new(center + Vector3.new(0, 12.9, 0)), accent, Enum.Material.Neon, { Transparency = 0.2 }))
		boards[id] = board
	end
end

local function lighthouse(folder: Folder, base: Vector3)
	local model = Build.model(folder, "Lighthouse", true)
	Build.pillar(model, 6, 16, base, rgb(120, 120, 126), Enum.Material.Cobblestone)
	local y = base.Y + 6
	for i = 1, 6 do
		Build.pillar(model, 6, 11 - i * 0.6, Vector3.new(base.X, y, base.Z), if i % 2 == 0 then rgb(245, 245, 245) else rgb(220, 60, 60), Enum.Material.SmoothPlastic)
		y += 6
	end
	Build.pillar(model, 1, 9, Vector3.new(base.X, y, base.Z), rgb(40, 40, 46), Enum.Material.Metal)
	Build.pillar(model, 4.5, 6, Vector3.new(base.X, y + 1, base.Z), rgb(200, 230, 255), Enum.Material.Glass, { Transparency = 0.5 })
	local lamp = Build.soft(Build.ball(model, 3, Vector3.new(base.X, y + 3.2, base.Z), rgb(255, 240, 180), Enum.Material.Neon))
	lamp.Name = "Lamp"
	local beam = Instance.new("SpotLight")
	beam.Range = 60
	beam.Angle = 25
	beam.Brightness = 4
	beam.Color = rgb(255, 240, 200)
	beam.Face = Enum.NormalId.Front
	beam.Parent = lamp
	Build.ball(model, 7, Vector3.new(base.X, y + 6.2, base.Z), rgb(220, 60, 60), Enum.Material.SmoothPlastic)
	Build.tag(lamp, "LighthouseLamp")
end

local function barriers(folder: Folder): { BasePart }
	local world = Zones.world
	local parts: { BasePart } = {}
	local halfX = world.boundaryHalfX
	local minZ, maxZ = world.boundaryMinZ, world.boundaryMaxZ
	local midZ = (minZ + maxZ) / 2
	local depthZ = maxZ - minZ
	local function barrier(size: Vector3, cf: CFrame)
		local p = Build.part(folder, size, cf, rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CollisionGroup = "Barrier"
		p.Name = "CharacterBarrier"
		table.insert(parts, p)
	end
	barrier(Vector3.new(halfX * 2, 1, depthZ), CFrame.new(0, world.characterBarrierY - 0.5, midZ))
	barrier(Vector3.new(2, 300, depthZ), CFrame.new(halfX, 140, midZ))
	barrier(Vector3.new(2, 300, depthZ), CFrame.new(-halfX, 140, midZ))
	barrier(Vector3.new(halfX * 2, 300, 2), CFrame.new(0, 140, minZ))
	barrier(Vector3.new(halfX * 2, 300, 2), CFrame.new(0, 140, maxZ))
	return parts
end

function Dock.build(parent: Instance): DockResult
	local world = Zones.world
	local folder = Build.folder(parent, "Dock")
	local prompts: { [string]: ProximityPrompt } = {}
	local boards: { [string]: Part } = {}
	local rng = Random.new(777)
	local plaza = world.plazaCenter

	-- plaza deck
	-- the plaza deck reaches every station (market, workshop, shop, quest board) so none of them
	-- stand on bare sand; a stone kerb finishes the edge
	Build.part(folder, Vector3.new(184, 1, 106), CFrame.new(plaza.X, plaza.Y + 0.5, plaza.Z + 1), rgb(196, 156, 108), Enum.Material.WoodPlanks)
	Build.part(folder, Vector3.new(186, 1.6, 108), CFrame.new(plaza.X, plaza.Y - 0.3, plaza.Z + 1), rgb(150, 144, 132), Enum.Material.Cobblestone)
	Build.soft(Build.cylinder(folder, 0.3, 18, CFrame.new(plaza.X, plaza.Y + 1.1, plaza.Z) * CFrame.Angles(0, 0, math.pi / 2), CYAN, Enum.Material.Neon, { Transparency = 0.4 }))
	local spawnPoints = {}
	for i = -1, 1 do
		local spawn = Instance.new("SpawnLocation")
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.CFrame = CFrame.new(plaza.X + i * 12, plaza.Y + 1, plaza.Z - 10) * CFrame.Angles(0, math.pi, 0)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Color = rgb(40, 150, 200)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Transparency = 0.3
		spawn.Parent = folder
		table.insert(spawnPoints, spawn.Position + Vector3.new(0, 3, 0))
	end

	launchBay(folder, prompts)
	market(folder, prompts, facing(Vector3.new(-60, plaza.Y + 1, plaza.Z + 42), plaza))
	workshop(folder, prompts, facing(Vector3.new(60, plaza.Y + 1, plaza.Z + 42), plaza))
	kiosk(folder, prompts, facing(Vector3.new(78, plaza.Y + 1, plaza.Z - 24), plaza))
	questBoard(folder, prompts, facing(Vector3.new(-76, plaza.Y + 1, plaza.Z - 24), plaza))
	leaderboards(folder, boards)
	lighthouse(folder, Vector3.new(175, plaza.Y - 1.5, -800))

	-- decoration
	for i = 1, 8 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		lamp(folder, Vector3.new(plaza.X + math.cos(angle) * 52, plaza.Y + 1, plaza.Z - 4 + math.sin(angle) * 44))
	end
	Beach.build(folder)
	for i = 1, 6 do
		crate(folder, Vector3.new(rng:NextNumber(14, 22) * (if i % 2 == 0 then 1 else -1), plaza.Y, -480 + rng:NextNumber(-10, 10)), rng:NextNumber(0, 1), rng:NextNumber(2, 3.4))
	end

	return {
		folder = folder,
		prompts = prompts,
		boards = boards,
		spawnPoints = spawnPoints,
		barrierParts = barriers(folder),
	}
end

Dock.BOARD_IDS = BOARD_IDS

return Dock

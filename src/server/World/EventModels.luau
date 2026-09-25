--!strict
-- Part-built models for event content: the sunken treasure galleon and the glowing Deep Tremor
-- trenches. Each builder returns the model plus the world positions where treasure goes.

local Build = require(script.Parent.Build)

local EventModels = {}

local rgb = Color3.fromRGB

export type Built = { model: Model, spots: { Vector3 } }

local WOOD = rgb(92, 64, 42)
local WOOD_DARK = rgb(58, 40, 28)
local GOLD = rgb(255, 200, 70)

-- A listing, broken galleon (~64 long) resting on the floor at `base` (y = floor surface).
function EventModels.galleon(parent: Instance, base: CFrame, rng: Random): Built
	local model = Build.model(parent, "SunkenGalleon")
	-- sink a little into the silt and list to one side
	local cf = base * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(12))
	local hull = Build.part(model, Vector3.new(18, 10, 50), cf * CFrame.new(0, 5, 0), WOOD, Enum.Material.WoodPlanks)
	hull.Name = "Hull"
	-- bow and stern taper
	Build.wedge(model, Vector3.new(18, 10, 12), cf * CFrame.new(0, 5, -31) * CFrame.Angles(0, math.pi, 0), WOOD, Enum.Material.WoodPlanks)
	Build.part(model, Vector3.new(18, 8, 10), cf * CFrame.new(0, 14, 20), WOOD_DARK, Enum.Material.WoodPlanks) -- stern castle
	Build.part(model, Vector3.new(19, 1, 51), cf * CFrame.new(0, 10.5, 0), WOOD_DARK, Enum.Material.Wood) -- deck
	-- rails
	for side = -1, 1, 2 do
		Build.part(model, Vector3.new(1, 2, 50), cf * CFrame.new(side * 9, 12, 0), WOOD_DARK, Enum.Material.Wood)
	end
	-- masts, one snapped
	Build.cylinder(model, 34, 2, cf * CFrame.new(0, 28, -8) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, Enum.Material.Wood)
	Build.cylinder(model, 16, 2, cf * CFrame.new(0, 19, 10) * CFrame.Angles(0, 0, math.pi / 2), WOOD_DARK, Enum.Material.Wood)
	Build.cylinder(model, 18, 1.6, cf * CFrame.new(7, 13, 14) * CFrame.Angles(0.3, 0, 1.2), WOOD_DARK, Enum.Material.Wood)
	-- tattered sail and flag
	Build.soft(Build.part(model, Vector3.new(0.3, 12, 16), cf * CFrame.new(0.8, 30, -8), rgb(200, 190, 160), Enum.Material.Fabric, { Transparency = 0.2 }))
	Build.soft(Build.part(model, Vector3.new(0.2, 4, 6), cf * CFrame.new(0, 43, -8) * CFrame.new(0, 0, 3), rgb(20, 20, 24), Enum.Material.Fabric))
	-- cargo hatch glowing with gold
	local hatch = Build.soft(Build.part(model, Vector3.new(8, 0.4, 10), cf * CFrame.new(0, 11.1, -4), GOLD, Enum.Material.Neon, { Transparency = 0.2 }))
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 40
	light.Brightness = 3
	light.Parent = hatch
	-- lanterns
	for _, offset in { Vector3.new(8, 13, -20), Vector3.new(-8, 13, 18), Vector3.new(0, 19, 25) } do
		local lantern = Build.soft(Build.ball(model, 1.6, (cf * CFrame.new(offset)).Position, rgb(255, 180, 80), Enum.Material.Neon))
		local glow = Instance.new("PointLight")
		glow.Color = rgb(255, 170, 70)
		glow.Range = 18
		glow.Parent = lantern
	end
	-- beacon: a tall shimmering column so divers can spot the wreck
	local beacon = Build.soft(Build.cylinder(model, 160, 6, cf * CFrame.new(0, 90, -4) * CFrame.Angles(0, 0, math.pi / 2), GOLD, Enum.Material.Neon, { Transparency = 0.75 }))
	beacon.Name = "Beacon"
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(GOLD)
	bubbles.LightEmission = 1
	bubbles.Rate = 12
	bubbles.Lifetime = NumberRange.new(4, 7)
	bubbles.Speed = NumberRange.new(6, 12)
	bubbles.Size = NumberSequence.new(0.8)
	bubbles.EmissionDirection = Enum.NormalId.Right
	bubbles.Parent = hatch

	-- treasure spots: on deck, in the hold opening, and scattered on the floor around the wreck
	local spots: { Vector3 } = {}
	for i = 1, 10 do
		table.insert(spots, (cf * CFrame.new(rng:NextNumber(-6, 6), 12.5, rng:NextNumber(-20, 20))).Position)
	end
	for i = 1, 20 do
		local angle = (i / 20) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = rng:NextNumber(20, 34)
		table.insert(spots, (base * CFrame.new(math.cos(angle) * radius * 0.7, 1.5, math.sin(angle) * radius)).Position)
	end
	return { model = model, spots = spots }
end

-- A glowing crack in the sea floor with broken rock plates on both sides. `base` sits on the
-- floor surface; the trench runs along its LookVector.
function EventModels.trench(parent: Instance, base: CFrame, length: number, count: number, rng: Random): Built
	local model = Build.model(parent, "TremorTrench")
	local rock = rgb(40, 34, 32)
	local lava = rgb(255, 110, 40)
	local glow = Build.soft(Build.part(model, Vector3.new(3, 0.6, length), base * CFrame.new(0, 0.2, 0), lava, Enum.Material.Neon))
	local light = Instance.new("PointLight")
	light.Color = lava
	light.Range = 30
	light.Brightness = 2
	light.Parent = glow
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(255, 140, 70), rgb(60, 40, 40))
	smoke.LightEmission = 0.6
	smoke.Rate = 10
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(3, 6)
	smoke.Size = NumberSequence.new(3, 8)
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Parent = glow
	local segments = math.max(3, math.floor(length / 10))
	for side = -1, 1, 2 do
		for i = 1, segments do
			local z = -length / 2 + (i - 0.5) * length / segments
			local size = Vector3.new(rng:NextNumber(5, 8), rng:NextNumber(2, 4), length / segments + 1)
			Build.part(model, size, base * CFrame.new(side * (1.5 + size.X / 2), size.Y / 2 - 0.5, z) * CFrame.Angles(0, 0, side * math.rad(rng:NextNumber(8, 22))), rock, Enum.Material.Basalt)
		end
	end
	local spots: { Vector3 } = {}
	for i = 1, count do
		local z = -length / 2 + (i - 0.5) * length / count
		table.insert(spots, (base * CFrame.new(0, 1.5, z)).Position)
	end
	return { model = model, spots = spots }
end

return EventModels

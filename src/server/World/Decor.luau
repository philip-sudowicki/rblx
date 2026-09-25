--!strict
-- Part-built decorations for each zone: kelp, coral, anemones, shells, light shafts, vents,
-- shipwrecks, whale bones, ruins, broken pillars and crystals, tinted by each zone's `style`.
-- Returns "special" treasure spots (wreck decks, ruin altars) with a rarity bias.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local Build = require(script.Parent.Build)
local TerrainGen = require(script.Parent.TerrainGen)

export type Spot = { position: Vector3, zone: number, special: string? }

local Decor = {}

local rgb = Color3.fromRGB
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }

-- Find the real terrain surface near (x, z) in a zone. Returns nil over holes/walls.
local function groundAt(zoneIndex: number, x: number, z: number): (Vector3?, Vector3?)
	local floor = WorldGeometry.floorY(zoneIndex, x, z)
	local origin = Vector3.new(x, floor + 40, z)
	local result = workspace:Raycast(origin, Vector3.new(0, -90, 0), terrainParams)
	if result and result.Normal.Y > 0.5 then
		return result.Position, result.Normal
	end
	return nil, nil
end
Decor.groundAt = groundAt

local function randomFloorPoint(zoneIndex: number, rng: Random, edgeMargin: number, holeMargin: number): (Vector3?, Vector3?)
	local zone = Zones.list[zoneIndex]
	for _ = 1, 8 do
		local r = (zone.radius - edgeMargin) * math.sqrt(rng:NextNumber())
		local theta = rng:NextNumber(0, math.pi * 2)
		local x, z = math.cos(theta) * r, math.sin(theta) * r
		if not WorldGeometry.inHole(zoneIndex, x, z, -holeMargin) then
			local pos, normal = groundAt(zoneIndex, x, z)
			if pos then
				return pos, normal
			end
		end
	end
	return nil, nil
end
Decor.randomFloorPoint = randomFloorPoint

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

---------------------------------------------------------------- small decor
local function kelp(parent: Instance, base: Vector3, rng: Random, tint: Color3, height: number)
	local model = Build.model(parent, "Kelp")
	local segments = math.floor(rng:NextInteger(4, 7) * height)
	local yaw = rng:NextNumber(0, math.pi * 2)
	for k = 1, segments do
		local t = (k - 1) / segments
		local color = tint:Lerp(rgb(150, 200, 90), t * 0.6)
		local p = Build.part(
			model,
			Vector3.new(1.1 - t * 0.4, 5, 0.25),
			CFrame.new(base + Vector3.new(0, 2.5 + (k - 1) * 4.6, 0)) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), yaw + k * 0.3, rng:NextNumber(-0.08, 0.08)),
			color,
			Enum.Material.SmoothPlastic
		)
		Build.soft(p)
		p.Name = "Seg" .. k
	end
	Build.tag(model, "Kelp")
end

local CORAL_COLORS = {
	rgb(255, 120, 150),
	rgb(255, 160, 80),
	rgb(190, 110, 255),
	rgb(255, 220, 90),
	rgb(90, 220, 200),
	rgb(255, 90, 90),
	rgb(120, 170, 255),
}
local GLOW_COLORS = {
	rgb(80, 240, 255),
	rgb(190, 90, 255),
	rgb(90, 255, 160),
	rgb(255, 90, 220),
}

local function coral(parent: Instance, base: Vector3, rng: Random, glow: boolean, palette: { Color3 }?)
	local model = Build.model(parent, "Coral")
	local color = if palette then pick(rng, palette) elseif glow then pick(rng, GLOW_COLORS) else pick(rng, CORAL_COLORS)
	local material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local kind = rng:NextInteger(1, 5)
	local scale = rng:NextNumber(0.8, 1.6)
	if kind == 1 then -- branching
		Build.soft(Build.ball(model, 1.6 * scale, base + Vector3.new(0, 0.4, 0), color, material))
		for b = 1, 5 do
			local yaw = b / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local tilt = rng:NextNumber(0.3, 0.7)
			local length = rng:NextNumber(2.5, 4.5) * scale
			local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2 - tilt) * CFrame.new(length / 2, 0, 0)
			Build.soft(Build.cylinder(model, length, 0.7 * scale, cf, color, material))
		end
	elseif kind == 2 then -- brain
		Build.soft(Build.ball(model, rng:NextNumber(3, 5) * scale, base, color:Lerp(rgb(255, 255, 255), 0.1), material))
	elseif kind == 3 then -- fan
		local yaw = rng:NextNumber(0, math.pi * 2)
		Build.soft(
			Build.part(
				model,
				Vector3.new(4.5 * scale, 4 * scale, 0.25),
				CFrame.new(base + Vector3.new(0, 2 * scale, 0)) * CFrame.Angles(0, yaw, rng:NextNumber(-0.2, 0.2)),
				color,
				material
			)
		)
	elseif kind == 4 then -- tubes
		for tube = 1, 3 do
			local h = rng:NextNumber(1.5, 4) * scale
			local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			Build.soft(Build.pillar(model, h * (1 - tube * 0.15), 1.1 * scale, base + offset + Vector3.new(0, -0.3, 0), color, material))
		end
	else -- table
		Build.soft(Build.pillar(model, 2 * scale, 0.8 * scale, base, color, material))
		Build.soft(Build.cylinder(model, 0.5, 6 * scale, CFrame.new(base + Vector3.new(0, 2.2 * scale, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, material))
	end
	if glow and rng:NextNumber() < 0.18 then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = model:FindFirstChildWhichIsA("BasePart")
	end
	if glow then
		Build.tag(model, "GlowCoral")
	end
end

local function anemone(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "Anemone")
	local color = pick(rng, { rgb(255, 120, 200), rgb(190, 120, 255), rgb(255, 170, 110), rgb(120, 230, 200) })
	Build.soft(Build.pillar(model, 1, 2.6, base + Vector3.new(0, -0.2, 0), color:Lerp(rgb(80, 40, 60), 0.4), Enum.Material.SmoothPlastic))
	for i = 1, 7 do
		local yaw = i / 7 * math.pi * 2
		local cf = CFrame.new(base + Vector3.new(math.cos(yaw) * 0.8, 1.9, math.sin(yaw) * 0.8)) * CFrame.Angles(math.sin(yaw) * 0.35, 0, -math.cos(yaw) * 0.35)
		Build.soft(Build.part(model, Vector3.new(0.3, 2.4, 0.3), cf, color, Enum.Material.SmoothPlastic))
	end
	Build.tag(model, "Anemone")
end

local function shell(parent: Instance, base: Vector3, rng: Random)
	local color = pick(rng, { rgb(250, 230, 210), rgb(255, 200, 190), rgb(230, 200, 160), rgb(255, 240, 240) })
	if rng:NextNumber() < 0.5 then
		Build.soft(Build.wedge(parent, Vector3.new(1.2, 0.5, 1.4), CFrame.new(base + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), color, Enum.Material.SmoothPlastic))
	else
		Build.soft(Build.ball(parent, 1, base, color, Enum.Material.SmoothPlastic))
	end
end

local function lightShaft(parent: Instance, x: number, z: number, topY: number, maxLength: number, color: Color3, rng: Random)
	local length = math.min(rng:NextNumber(120, 200), maxLength)
	local width = rng:NextNumber(8, 16)
	local cf = CFrame.new(x, topY - length / 2, z) * CFrame.Angles(rng:NextNumber(-0.18, 0.18), rng:NextNumber(0, 6.28), rng:NextNumber(-0.18, 0.18))
	local p = Build.part(parent, Vector3.new(width, length, width), cf, color, Enum.Material.SmoothPlastic, { Transparency = 0.9 })
	Build.soft(p)
	p.Name = "LightShaft"
	Build.tag(p, "LightShaft")
end

local function vent(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "Vent")
	local dark = rgb(40, 34, 32)
	local h1 = rng:NextNumber(5, 8)
	local h2 = rng:NextNumber(4, 6)
	Build.pillar(model, h1, 6, base + Vector3.new(0, -1, 0), dark, Enum.Material.Basalt)
	Build.pillar(model, h2, 4, base + Vector3.new(0, h1 - 1, 0), dark, Enum.Material.Basalt)
	local top = base + Vector3.new(0, h1 + h2 - 1, 0)
	local lip = Build.soft(Build.cylinder(model, 0.6, 3.4, CFrame.new(top) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 120, 40), Enum.Material.Neon))
	local attachment = Instance.new("Attachment")
	attachment.Parent = lip
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(rgb(90, 80, 80), rgb(200, 200, 210))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.LightEmission = 0.1
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 130, 60)
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = lip
	Build.tag(model, "Vent")
end

---------------------------------------------------------------- big set pieces
local WOOD = rgb(74, 52, 36)
local WOOD_DARK = rgb(54, 38, 28)

local function wreck(parent: Instance, base: Vector3, rng: Random, spots: { Spot }, zoneIndex: number)
	local model = Build.model(parent, "Shipwreck", true)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local roll = rng:NextNumber(-0.22, 0.22)
	local length = rng:NextNumber(44, 60)
	local origin = CFrame.new(base + Vector3.new(0, -2.5, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, roll)
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		return Build.part(model, size, origin * offset, color, material or Enum.Material.WoodPlanks)
	end
	add(Vector3.new(4, 3, length), CFrame.new(0, 1.5, 0), WOOD_DARK, Enum.Material.Wood)
	add(Vector3.new(1.4, 10, length * 0.92), CFrame.new(-6, 6, 0) * CFrame.Angles(0, 0, -0.26), WOOD)
	add(Vector3.new(1.4, 10, length * 0.92), CFrame.new(6, 6, 0) * CFrame.Angles(0, 0, 0.26), WOOD)
	local bow = Build.wedge(model, Vector3.new(14, 10, 12), origin * CFrame.new(0, 6, length / 2 + 5) * CFrame.Angles(0, math.pi, 0), WOOD, Enum.Material.WoodPlanks)
	bow.Name = "Bow"
	add(Vector3.new(14, 9, 1.4), CFrame.new(0, 6, -length / 2), WOOD_DARK)
	-- broken deck in three pieces
	local deckLength = length / 3 - 2
	local decks = {}
	for i = -1, 1 do
		local piece = add(
			Vector3.new(12, 1, deckLength),
			CFrame.new(0, 10.5 + rng:NextNumber(-0.6, 0.2), i * (deckLength + 2)) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.05, 0.05)),
			rgb(96, 70, 48)
		)
		table.insert(decks, piece)
	end
	local cabin = add(Vector3.new(10, 7, 11), CFrame.new(0, 14.5, -length / 2 + 8), WOOD)
	add(Vector3.new(11, 0.8, 12), CFrame.new(0, 18.3, -length / 2 + 8), WOOD_DARK)
	-- broken mast
	local mastHeight = rng:NextNumber(14, 24)
	Build.cylinder(model, mastHeight, 1.8, origin * CFrame.new(0, 10 + mastHeight / 2, 4) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, math.pi / 2 + rng:NextNumber(-0.2, 0.2)), WOOD_DARK, Enum.Material.Wood)
	-- cannons
	for side = -1, 1, 2 do
		Build.cylinder(model, 4, 1.2, origin * CFrame.new(side * 7.4, 7, rng:NextNumber(-8, 8)) * CFrame.Angles(0, 0, 0), rgb(40, 40, 44), Enum.Material.CorrodedMetal)
	end
	for _, piece in decks do
		table.insert(spots, { position = (piece.CFrame * CFrame.new(0, piece.Size.Y / 2 + 0.6, 0)).Position, zone = zoneIndex, special = "Wreck" })
	end
	table.insert(spots, { position = (cabin.CFrame * CFrame.new(0, cabin.Size.Y / 2 + 1.4, 0)).Position, zone = zoneIndex, special = "Wreck" })
	Build.tag(model, "Wreck")
end

local function bones(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "WhaleBones", true)
	local bone = rgb(226, 220, 200)
	local origin = CFrame.new(base + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	Build.soft(Build.part(model, Vector3.new(6, 4, 9), origin * CFrame.new(0, 2, 22), bone, Enum.Material.SmoothPlastic))
	for side = -1, 1, 2 do
		Build.soft(Build.part(model, Vector3.new(0.8, 0.8, 12), origin * CFrame.new(side * 2.6, 0.6, 30) * CFrame.Angles(0, side * 0.2, 0), bone, Enum.Material.SmoothPlastic))
	end
	for i = 0, 13 do
		local z = 16 - i * 3
		Build.soft(Build.part(model, Vector3.new(1.6, 1.6, 2.4), origin * CFrame.new(0, 1.6 + math.sin(i / 13 * math.pi) * 1.5, z), bone, Enum.Material.SmoothPlastic))
		if i >= 1 and i <= 8 then
			for side = -1, 1, 2 do
				local ribLength = 9 - math.abs(i - 4) * 0.8
				Build.soft(Build.part(model, Vector3.new(0.6, ribLength, 0.6), origin * CFrame.new(side * 3.2, ribLength / 2 + 0.5, z) * CFrame.Angles(0, 0, side * 0.55), bone, Enum.Material.SmoothPlastic))
			end
		end
	end
end

local STONE = rgb(78, 74, 70)
local STONE_DARK = rgb(52, 50, 48)
local GLYPH = rgb(60, 240, 200)

local function ruin(parent: Instance, base: Vector3, rng: Random, spots: { Spot }, zoneIndex: number)
	local model = Build.model(parent, "Ruin", true)
	local origin = CFrame.new(base + Vector3.new(0, -1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local size = rng:NextNumber(26, 34)
	for step = 0, 2 do
		local s = size - step * 6
		Build.part(model, Vector3.new(s, 2, s), origin * CFrame.new(0, 1 + step * 2, 0), if step % 2 == 0 then STONE else STONE_DARK, Enum.Material.Cobblestone)
	end
	local topY = 6
	local ring = size / 2 - 3
	local pillars = rng:NextInteger(5, 8)
	for i = 1, pillars do
		local angle = i / pillars * math.pi * 2
		local p = origin * CFrame.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		local roll = rng:NextNumber()
		if roll < 0.2 then
			-- toppled pillar lying on the platform
			Build.cylinder(model, 14, 2.6, p * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, angle, 0), STONE, Enum.Material.Slate)
		else
			local height = if roll < 0.5 then rng:NextNumber(5, 9) else rng:NextNumber(14, 20)
			Build.pillar(model, height, 2.6, (p * CFrame.new(0, 2, 0)).Position, STONE, Enum.Material.Slate)
			if height > 12 and rng:NextNumber() < 0.5 then
				Build.soft(Build.part(model, Vector3.new(0.3, height * 0.6, 0.3), p * CFrame.new(1.35, 2 + height * 0.5, 0), GLYPH, Enum.Material.Neon))
			end
		end
	end
	-- lintel across two pillars
	Build.part(model, Vector3.new(ring * 1.6, 2, 3), origin * CFrame.new(0, 21, ring * 0.7) * CFrame.Angles(0, 0, rng:NextNumber(-0.12, 0.12)), STONE_DARK, Enum.Material.Slate)
	local altar = Build.part(model, Vector3.new(5, 3, 4), origin * CFrame.new(0, topY + 1.5, 0), STONE_DARK, Enum.Material.Marble)
	Build.soft(Build.part(model, Vector3.new(5.2, 0.3, 0.4), origin * CFrame.new(0, topY + 2.2, 2.05), GLYPH, Enum.Material.Neon))
	local light = Instance.new("PointLight")
	light.Color = GLYPH
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = altar
	table.insert(spots, { position = (altar.CFrame * CFrame.new(0, 2.2, 0)).Position, zone = zoneIndex, special = "Ruin" })
	for corner = 1, 2 do
		local c = origin * CFrame.new((corner == 1 and -1 or 1) * (size / 2 - 7), 6.6, (corner == 1 and 1 or -1) * (size / 2 - 7))
		table.insert(spots, { position = c.Position, zone = zoneIndex, special = "Ruin" })
	end
	Build.tag(model, "Ruin")
end

local function brokenPillar(parent: Instance, base: Vector3, rng: Random)
	local model = Build.model(parent, "Pillar")
	local height = rng:NextNumber(6, 22)
	Build.pillar(model, height, rng:NextNumber(2.2, 3.4), base + Vector3.new(0, -1, 0), STONE, Enum.Material.Slate)
	if rng:NextNumber() < 0.5 then
		Build.cylinder(model, rng:NextNumber(4, 8), 2.6, CFrame.new(base + Vector3.new(rng:NextNumber(-4, 4), 0.8, rng:NextNumber(-4, 4))) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), STONE_DARK, Enum.Material.Slate)
	end
end

local CRYSTAL_COLORS = { rgb(190, 90, 255), rgb(90, 240, 255), rgb(255, 110, 220), rgb(140, 120, 255) }

local function crystal(parent: Instance, base: Vector3, rng: Random, big: boolean, palette: { Color3 }?)
	local model = Build.model(parent, "Crystal")
	local color = pick(rng, palette or CRYSTAL_COLORS)
	local count = rng:NextInteger(3, 5)
	local scale = if big then rng:NextNumber(2.5, 4) else rng:NextNumber(0.8, 1.6)
	for i = 1, count do
		local h = rng:NextNumber(4, 11) * scale
		local w = rng:NextNumber(1.2, 2.6) * scale
		local cf = CFrame.new(base) * CFrame.Angles(0, i * 1.7, 0) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)) * CFrame.new(0, h / 2 - 0.5, 0)
		local neon = rng:NextNumber() < 0.6
		local p = Build.part(model, Vector3.new(w, h, w), cf * CFrame.Angles(0, math.pi / 4, 0), color, if neon then Enum.Material.Neon else Enum.Material.Glass, { Transparency = if neon then 0 else 0.25 })
		if not big then
			Build.soft(p)
		end
	end
	if rng:NextNumber() < 0.18 or big then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = if big then 30 else 14
		light.Brightness = 1.4
		light.Parent = model:FindFirstChildWhichIsA("BasePart")
	end
	Build.tag(model, "Crystal")
end

---------------------------------------------------------------- per-zone
function Decor.build(zoneIndex: number, parent: Instance, rng: Random): { Spot }
	local zone = Zones.list[zoneIndex]
	local decor = zone.decor
	local folder = Build.folder(parent, zone.id)
	local spots: { Spot } = {}

	local function scatter(count: number?, fn: (Vector3) -> (), edge: number?, hole: number?)
		for _ = 1, count or 0 do
			local pos = randomFloorPoint(zoneIndex, rng, edge or 30, hole or 10)
			if pos then
				fn(pos)
			end
		end
	end

	local style = zone.style
	local kelpTint = style.kelp or rgb(40, 100, 70)
	local kelpHeight = style.kelpHeight or 1
	scatter(decor.kelp, function(pos)
		kelp(folder, pos, rng, kelpTint, kelpHeight)
	end)
	scatter(decor.coral, function(pos)
		coral(folder, pos, rng, false)
	end)
	scatter(decor.glowCoral, function(pos)
		coral(folder, pos, rng, true, style.glow)
	end)
	scatter(decor.anemones, function(pos)
		anemone(folder, pos, rng)
	end)
	scatter(decor.shells, function(pos)
		shell(folder, pos, rng)
	end)
	scatter(decor.vents, function(pos)
		vent(folder, pos, rng)
	end, 60, 20)
	scatter(decor.wrecks, function(pos)
		wreck(folder, pos, rng, spots, zoneIndex)
	end, 70, 40)
	scatter(decor.bones, function(pos)
		bones(folder, pos, rng)
	end, 60, 30)
	scatter(decor.ruins, function(pos)
		ruin(folder, pos, rng, spots, zoneIndex)
	end, 50, 30)
	scatter(decor.pillars, function(pos)
		brokenPillar(folder, pos, rng)
	end, 30, 12)
	scatter(decor.crystals, function(pos)
		crystal(folder, pos, rng, false, style.crystals)
	end)
	scatter(decor.spires, function(pos)
		crystal(folder, pos, rng, true, style.crystals)
	end, 70, 20)

	if decor.lightShafts then
		-- beams fall from the zone's ceiling (the sea surface in the Lagoon)
		local top = WorldGeometry.ceilingY(zoneIndex, 0, 0)
		local floorTop = zone.bottomY + zone.floorThickness
		local shaftColor = style.shaft or rgb(210, 245, 255)
		for _ = 1, decor.lightShafts do
			local r = (zone.radius - 30) * math.sqrt(rng:NextNumber())
			local theta = rng:NextNumber(0, math.pi * 2)
			lightShaft(folder, math.cos(theta) * r, math.sin(theta) * r, top, top - floorTop, shaftColor, rng)
		end
	end
	-- crystals grow on top of the floating rocks
	for _, floater in TerrainGen.floaters do
		if floater.zone == zoneIndex then
			for _ = 1, 2 do
				crystal(folder, floater.center + Vector3.new(rng:NextNumber(-4, 4), floater.radius * 0.85, rng:NextNumber(-4, 4)), rng, false, style.crystals)
			end
		end
	end
	return spots
end

Decor.SPARKLE = SPARKLE
Decor.SMOKE = SMOKE

return Decor

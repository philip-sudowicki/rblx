--!strict
-- Builds treasure from primitive parts (31 shapes). Models sit on y = 0 at the origin. A
-- rarity-coloured glow ring and light make rare pieces easy to spot on the seafloor.

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)

export type Look = {
	shape: string,
	primary: Color3,
	secondary: Color3,
	glow: boolean?,
	size: number?,
}

export type Options = {
	rarity: number?,
	scale: number?,
	simple: boolean?, -- no ring, particles or lights
}

export type Built = {
	model: Model,
	root: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
}

local TreasureModel = {}

local rgb = Color3.fromRGB

function TreasureModel.build(look: Look, options: Options?): Built
	local opts: Options = options or {}
	local rarity = Rarities.list[opts.rarity or 1] or Rarities.list[1]
	local s = 1.6 * (look.size or 1) * (opts.scale or 1) * (1 + (rarity.index - 1) * 0.06)
	local primary, secondary = look.primary, look.secondary
	local glowMat = if look.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local model = Instance.new("Model")
	model.Name = "Treasure"
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}

	local function add(className: string, shape: Enum.PartType?, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
		local part = Instance.new(className) :: BasePart
		if shape and part:IsA("Part") then
			part.Shape = shape
		end
		part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
		part.CFrame = cf
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		table.insert(parts, part)
		table.insert(offsets, cf)
		return part
	end
	local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
		return add("Part", nil, size * s, cf.Rotation + cf.Position * s, color, material)
	end
	local function ball(d: number, pos: Vector3, color: Color3, material: Enum.Material?): BasePart
		return add("Part", Enum.PartType.Ball, Vector3.new(d, d, d) * s, CFrame.new(pos * s), color, material)
	end
	-- cylinder standing up (axis Y)
	local function disc(height: number, d: number, pos: Vector3, color: Color3, material: Enum.Material?, tilt: CFrame?): BasePart
		return add("Part", Enum.PartType.Cylinder, Vector3.new(height, d, d) * s, CFrame.new(pos * s) * (tilt or CFrame.identity) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	end
	-- cylinder lying along X
	local function rod(length: number, d: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
		return add("Part", Enum.PartType.Cylinder, Vector3.new(length, d, d) * s, cf.Rotation + cf.Position * s, color, material)
	end
	local function wedge(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
		return add("WedgePart", nil, size * s, cf.Rotation + cf.Position * s, color, material)
	end

	local shape = look.shape
	local metal = Enum.Material.Metal
	if shape == "Coin" then
		disc(0.15, 1, Vector3.new(0, 0.55, 0), primary, metal, CFrame.Angles(math.rad(75), 0, 0))
		disc(0.17, 0.6, Vector3.new(0, 0.55, 0), secondary, glowMat, CFrame.Angles(math.rad(75), 0, 0))
	elseif shape == "CoinPile" then
		block(Vector3.new(1.1, 0.8, 0.9), CFrame.new(0, 0.4, 0), primary, Enum.Material.Fabric)
		for i = 1, 5 do
			disc(0.1, 0.45, Vector3.new(math.cos(i) * 0.5, 0.05 + i * 0.04, math.sin(i) * 0.5), secondary, metal)
		end
		ball(0.35, Vector3.new(0, 0.9, 0), primary, Enum.Material.Fabric)
	elseif shape == "Bar" then
		block(Vector3.new(1.2, 0.35, 0.5), CFrame.new(0, 0.18, 0), primary, metal)
		block(Vector3.new(1, 0.35, 0.4), CFrame.new(0.1, 0.53, 0.05) * CFrame.Angles(0, 0.3, 0), primary, metal)
	elseif shape == "Chest" then
		block(Vector3.new(1.4, 0.8, 0.9), CFrame.new(0, 0.4, 0), primary, Enum.Material.WoodPlanks)
		rod(1.42, 0.9, CFrame.new(0, 0.85, 0), primary, Enum.Material.WoodPlanks)
		block(Vector3.new(1.45, 0.12, 0.95), CFrame.new(0, 0.55, 0), secondary, metal)
		block(Vector3.new(0.2, 0.25, 0.08), CFrame.new(0, 0.7, -0.48), secondary, glowMat)
		if look.glow then
			ball(0.4, Vector3.new(0, 1.1, 0), secondary, Enum.Material.Neon).Transparency = 0.3
		end
	elseif shape == "Ring" then
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			block(Vector3.new(0.18, 0.18, 0.3), CFrame.new(math.cos(a) * 0.4, 0.5 + math.sin(a) * 0.4, 0) * CFrame.Angles(0, 0, a), primary, metal)
		end
		block(Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.95, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), secondary, glowMat)
	elseif shape == "Crown" then
		disc(0.45, 1.2, Vector3.new(0, 0.25, 0), primary, metal)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			wedge(Vector3.new(0.2, 0.5, 0.3), CFrame.new(math.cos(a) * 0.5, 0.7, math.sin(a) * 0.5) * CFrame.Angles(0, -a, 0), primary, metal)
			ball(0.16, Vector3.new(math.cos(a) * 0.62, 0.25, math.sin(a) * 0.62), secondary, glowMat)
		end
	elseif shape == "Gem" then
		block(Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), primary, Enum.Material.Glass).Transparency = 0.15
		block(Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), secondary, Enum.Material.Neon)
	elseif shape == "Shard" then
		block(Vector3.new(0.4, 1.6, 0.25), CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, 0.3), primary, glowMat)
		block(Vector3.new(0.3, 1, 0.2), CFrame.new(0.35, 0.45, 0.1) * CFrame.Angles(0, 0.5, -0.4), secondary, Enum.Material.Glass)
	elseif shape == "Idol" then
		block(Vector3.new(0.7, 0.3, 0.7), CFrame.new(0, 0.15, 0), primary, Enum.Material.Slate)
		block(Vector3.new(0.5, 0.8, 0.45), CFrame.new(0, 0.7, 0), primary, Enum.Material.Slate)
		ball(0.55, Vector3.new(0, 1.35, 0), primary, Enum.Material.Slate)
		for side = -1, 1, 2 do
			ball(0.12, Vector3.new(side * 0.12, 1.4, -0.24), secondary, Enum.Material.Neon)
		end
	elseif shape == "Statue" then
		block(Vector3.new(0.8, 0.25, 0.8), CFrame.new(0, 0.12, 0), secondary, Enum.Material.Marble)
		block(Vector3.new(0.45, 1.2, 0.35), CFrame.new(0, 0.85, 0), primary, Enum.Material.Marble)
		ball(0.4, Vector3.new(0, 1.65, 0), primary, Enum.Material.Marble)
	elseif shape == "Tablet" then
		block(Vector3.new(1, 1.3, 0.2), CFrame.new(0, 0.62, 0) * CFrame.Angles(-0.2, 0, 0), primary, Enum.Material.Slate)
		for i = 1, 3 do
			block(Vector3.new(0.7, 0.06, 0.05), CFrame.new(0, 0.3 + i * 0.25, -0.12) * CFrame.Angles(-0.2, 0, 0), secondary, glowMat)
		end
	elseif shape == "Obelisk" then
		block(Vector3.new(0.6, 2, 0.6), CFrame.new(0, 1, 0), primary, Enum.Material.Slate)
		wedge(Vector3.new(0.6, 0.4, 0.3), CFrame.new(0, 2.2, -0.15), primary, Enum.Material.Slate)
		wedge(Vector3.new(0.6, 0.4, 0.3), CFrame.new(0, 2.2, 0.15) * CFrame.Angles(0, math.pi, 0), primary, Enum.Material.Slate)
		for i = 1, 4 do
			block(Vector3.new(0.62, 0.05, 0.62), CFrame.new(0, 0.3 + i * 0.35, 0), secondary, Enum.Material.Neon)
		end
	elseif shape == "Mask" then
		block(Vector3.new(0.9, 1.1, 0.2), CFrame.new(0, 0.6, 0) * CFrame.Angles(-0.35, 0, 0), primary, Enum.Material.SmoothPlastic)
		for side = -1, 1, 2 do
			ball(0.2, Vector3.new(side * 0.2, 0.75, -0.12), secondary, Enum.Material.Neon)
		end
		block(Vector3.new(0.3, 0.06, 0.05), CFrame.new(0, 0.35, -0.2) * CFrame.Angles(-0.35, 0, 0), secondary, glowMat)
	elseif shape == "Anchor" then
		block(Vector3.new(0.18, 1.5, 0.18), CFrame.new(0, 0.85, 0), primary, Enum.Material.CorrodedMetal)
		block(Vector3.new(0.8, 0.15, 0.15), CFrame.new(0, 1.4, 0), primary, Enum.Material.CorrodedMetal)
		for side = -1, 1, 2 do
			block(Vector3.new(0.65, 0.18, 0.18), CFrame.new(side * 0.28, 0.25, 0) * CFrame.Angles(0, 0, side * 0.6), primary, Enum.Material.CorrodedMetal)
			wedge(Vector3.new(0.15, 0.3, 0.2), CFrame.new(side * 0.55, 0.45, 0), secondary, Enum.Material.CorrodedMetal)
		end
		disc(0.12, 0.35, Vector3.new(0, 1.7, 0), secondary, Enum.Material.CorrodedMetal, CFrame.Angles(math.pi / 2, 0, 0))
	elseif shape == "Compass" then
		disc(0.25, 1, Vector3.new(0, 0.15, 0), primary, metal)
		disc(0.05, 0.8, Vector3.new(0, 0.3, 0), secondary, Enum.Material.Glass)
		block(Vector3.new(0.08, 0.04, 0.6), CFrame.new(0, 0.34, 0) * CFrame.Angles(0, 0.6, 0), rgb(220, 40, 40), Enum.Material.Neon)
	elseif shape == "Sextant" then
		for i = 0, 5 do
			local a = math.rad(-40 + i * 16)
			block(Vector3.new(0.12, 0.12, 0.3), CFrame.new(math.sin(a) * 0.7, 0.2 + math.cos(a) * 0.1, math.cos(a) * 0.1), primary, metal)
		end
		block(Vector3.new(0.1, 1.1, 0.1), CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, 0.35), primary, metal)
		block(Vector3.new(0.1, 1.1, 0.1), CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, -0.35), primary, metal)
		rod(0.5, 0.15, CFrame.new(0, 1.2, 0), secondary, Enum.Material.Glass)
	elseif shape == "Bell" then
		disc(0.8, 0.9, Vector3.new(0, 0.6, 0), primary, metal)
		disc(0.25, 1.2, Vector3.new(0, 0.12, 0), primary, metal)
		ball(0.35, Vector3.new(0, 1.05, 0), secondary, metal)
	elseif shape == "Porthole" then
		disc(0.25, 1.3, Vector3.new(0, 0.7, 0), primary, metal, CFrame.Angles(math.pi / 2, 0, 0))
		disc(0.27, 0.9, Vector3.new(0, 0.7, 0), secondary, Enum.Material.Glass, CFrame.Angles(math.pi / 2, 0, 0)).Transparency = 0.3
	elseif shape == "Figurehead" then
		block(Vector3.new(0.5, 1.6, 0.4), CFrame.new(0, 0.8, 0) * CFrame.Angles(0.3, 0, 0), primary, Enum.Material.Wood)
		ball(0.5, Vector3.new(0, 1.75, -0.3), primary, Enum.Material.Wood)
		wedge(Vector3.new(0.9, 0.9, 0.2), CFrame.new(0, 1.1, 0.25) * CFrame.Angles(0, math.pi, 0), secondary, glowMat)
	elseif shape == "Cannonball" then
		ball(0.9, Vector3.new(0, 0.45, 0), primary, Enum.Material.CorrodedMetal)
		ball(0.6, Vector3.new(0.6, 0.3, 0.2), primary, Enum.Material.CorrodedMetal)
	elseif shape == "Goblet" then
		disc(0.12, 0.6, Vector3.new(0, 0.06, 0), primary, metal)
		disc(0.6, 0.15, Vector3.new(0, 0.4, 0), primary, metal)
		disc(0.5, 0.7, Vector3.new(0, 0.9, 0), primary, metal)
		ball(0.2, Vector3.new(0.3, 0.9, 0), secondary, glowMat)
	elseif shape == "Lyre" then
		for side = -1, 1, 2 do
			block(Vector3.new(0.15, 1.3, 0.15), CFrame.new(side * 0.35, 0.8, 0) * CFrame.Angles(0, 0, side * -0.25), primary, metal)
		end
		block(Vector3.new(0.9, 0.12, 0.15), CFrame.new(0, 1.4, 0), primary, metal)
		for i = -1, 1 do
			block(Vector3.new(0.03, 1.1, 0.03), CFrame.new(i * 0.14, 0.85, 0), secondary, Enum.Material.Neon)
		end
		block(Vector3.new(0.7, 0.2, 0.3), CFrame.new(0, 0.2, 0), primary, metal)
	elseif shape == "Scepter" then
		block(Vector3.new(0.12, 1.8, 0.12), CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, 0.5), primary, metal)
		ball(0.35, Vector3.new(-0.78, 1.7, 0), secondary, glowMat)
	elseif shape == "Comb" then
		block(Vector3.new(1.1, 0.25, 0.15), CFrame.new(0, 0.7, 0), primary, Enum.Material.SmoothPlastic)
		for i = -4, 4 do
			block(Vector3.new(0.05, 0.5, 0.08), CFrame.new(i * 0.12, 0.35, 0), primary, Enum.Material.SmoothPlastic)
		end
		ball(0.18, Vector3.new(0, 0.9, 0), secondary, glowMat)
	elseif shape == "Lantern" then
		disc(0.15, 0.8, Vector3.new(0, 0.08, 0), primary, metal)
		disc(0.9, 0.6, Vector3.new(0, 0.6, 0), secondary, Enum.Material.Neon).Transparency = 0.2
		disc(0.15, 0.8, Vector3.new(0, 1.1, 0), primary, metal)
		block(Vector3.new(0.08, 0.35, 0.08), CFrame.new(0, 1.35, 0), primary, metal)
	elseif shape == "Spyglass" then
		rod(1.3, 0.3, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0.4, 0), primary, metal)
		rod(0.6, 0.38, CFrame.new(0.45, 0.22, -0.2) * CFrame.Angles(0, 0.4, 0), secondary, Enum.Material.Leather)
	elseif shape == "Book" then
		block(Vector3.new(0.9, 0.25, 1.2), CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0.3, 0), primary, Enum.Material.Leather)
		block(Vector3.new(0.85, 0.2, 1.1), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0.3, 0), rgb(240, 230, 205), Enum.Material.SmoothPlastic)
		block(Vector3.new(0.3, 0.05, 0.3), CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0.3, 0), secondary, glowMat)
	elseif shape == "Device" then
		block(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 0.45, 0), primary, metal)
		ball(0.5, Vector3.new(0, 1.05, 0), secondary, Enum.Material.Neon)
		for side = -1, 1, 2 do
			block(Vector3.new(0.1, 0.7, 0.92), CFrame.new(side * 0.4, 0.45, 0), secondary, Enum.Material.Neon)
		end
	elseif shape == "Coil" then
		for i = 0, 4 do
			disc(0.12, 0.9 - i * 0.08, Vector3.new(0, 0.15 + i * 0.25, 0), if i % 2 == 0 then primary else secondary, if i % 2 == 0 then metal else Enum.Material.Neon)
		end
		ball(0.3, Vector3.new(0, 1.4, 0), secondary, Enum.Material.Neon)
	elseif shape == "Orb" then
		ball(0.9, Vector3.new(0, 0.6, 0), primary, glowMat)
		ball(0.55, Vector3.new(0, 0.6, 0), secondary, Enum.Material.Neon).Transparency = 0.2
	elseif shape == "Cog" then
		disc(0.25, 1, Vector3.new(0, 0.6, 0), primary, metal, CFrame.Angles(math.pi / 2, 0, 0))
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			block(Vector3.new(0.22, 0.22, 0.25), CFrame.new(math.cos(a) * 0.55, 0.6 + math.sin(a) * 0.55, 0) * CFrame.Angles(0, 0, a), primary, metal)
		end
		disc(0.27, 0.35, Vector3.new(0, 0.6, 0), secondary, Enum.Material.Neon, CFrame.Angles(math.pi / 2, 0, 0))
	else
		ball(0.8, Vector3.new(0, 0.4, 0), primary, glowMat)
	end

	local root = parts[1]
	model.PrimaryPart = root

	if not opts.simple then
		-- rarity ring on the ground
		if rarity.index >= 2 then
			local ring = add("Part", Enum.PartType.Cylinder, Vector3.new(0.08, 2.4 * s, 2.4 * s), CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.pi / 2), rarity.color, Enum.Material.Neon)
			ring.Transparency = 0.55
			ring.Name = "RarityRing"
		end
		if look.glow or rarity.index >= 3 then
			local light = Instance.new("PointLight")
			light.Color = if look.glow then secondary else rarity.color
			light.Range = 8 + rarity.index * 2
			light.Brightness = 1 + rarity.index * 0.25
			light.Shadows = false
			light.Parent = root
		end
		if rarity.particles then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Rate = 3 + rarity.index * 2
			emitter.Lifetime = NumberRange.new(1, 1.6)
			emitter.Speed = NumberRange.new(0.5, 1.5)
			emitter.SpreadAngle = Vector2.new(40, 40)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * s), NumberSequenceKeypoint.new(1, 0) })
			emitter.LightEmission = 1
			emitter.Color = if rarity.style == "rainbow" then Rarities.rainbow else ColorSequence.new(rarity.color)
			emitter.Parent = root
		end
	end
	if rarity.style == "rainbow" then
		root:SetAttribute("Tint", "rainbow")
	elseif rarity.style == "pulse" then
		root:SetAttribute("Tint", "pulse")
	end
	return { model = model, root = root, parts = parts, offsets = offsets }
end

-- Positions every part of a built model at `cf` (models are built around the origin).
-- inWorld = true uses BulkMoveTo (fast); otherwise CFrames are set directly (viewports).
function TreasureModel.place(built: Built, cf: CFrame, inWorld: boolean?)
	if inWorld then
		local cframes = table.create(#built.parts)
		for i, offset in built.offsets do
			cframes[i] = cf * offset
		end
		workspace:BulkMoveTo(built.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for i, part in built.parts do
			part.CFrame = cf * built.offsets[i]
		end
	end
end

return TreasureModel

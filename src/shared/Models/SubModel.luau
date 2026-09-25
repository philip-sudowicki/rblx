--!strict
-- Builds a player submarine from parts. The root is an invisible collision box; every visual
-- part is massless, non-colliding and welded to it. The propeller hangs on a Weld so the
-- owning client can spin it locally.

local Config = script.Parent.Parent.Config
local Skins = require(Config.Skins)

local SubModel = {}

SubModel.ROOT_SIZE = Vector3.new(6, 6, 14)

local function weldTo(root: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

local function visual(model: Model, root: BasePart, className: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new(className) :: BasePart
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	part.Parent = model
	weldTo(root, part)
	return part
end

local function shaped(model: Model, root: BasePart, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = visual(model, root, "Part", size, offset, color, material) :: Part
	part.Shape = shape
	return part
end

-- Builds the sub at `cframe` (LookVector = forward). Returns the model; root is model.PrimaryPart.
function SubModel.build(skinId: string, cframe: CFrame): Model
	local skin = Skins.byId[skinId] or Skins.byId[Skins.default]
	local model = Instance.new("Model")
	model.Name = "Submarine"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = SubModel.ROOT_SIZE
	root.CFrame = cframe
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CastShadow = false
	root.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.1, 1, 1)
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local body, accent, trim, glass, glow, material = skin.body, skin.accent, skin.trim, skin.glass, skin.glow, skin.material
	local Z = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along Z

	shaped(model, root, Enum.PartType.Cylinder, Vector3.new(10, 5.8, 5.8), Z, body, material).Name = "Hull"
	shaped(model, root, Enum.PartType.Ball, Vector3.new(5.8, 5.8, 5.8), CFrame.new(0, 0, -5), body, material).Name = "Nose"
	shaped(model, root, Enum.PartType.Ball, Vector3.new(5.2, 5.2, 5.2), CFrame.new(0, 0, 5), body, material).Name = "Tail"
	shaped(model, root, Enum.PartType.Cylinder, Vector3.new(0.7, 6, 6), CFrame.new(0, 0, 1.6) * Z, accent, Enum.Material.SmoothPlastic)
	shaped(model, root, Enum.PartType.Cylinder, Vector3.new(0.5, 6, 6), CFrame.new(0, 0, -2.8) * Z, accent, Enum.Material.SmoothPlastic)
	local dome = shaped(model, root, Enum.PartType.Ball, Vector3.new(4.8, 4.8, 4.8), CFrame.new(0, 2.3, -2.4), glass, Enum.Material.Glass)
	dome.Transparency = 0.4
	dome.Name = "Dome"
	shaped(model, root, Enum.PartType.Cylinder, Vector3.new(0.5, 5.2, 5.2), CFrame.new(0, 1.4, -2.4) * CFrame.Angles(0, 0, math.pi / 2), trim, Enum.Material.Metal)

	-- fins
	for side = -1, 1, 2 do
		visual(model, root, "WedgePart", Vector3.new(0.5, 1.6, 3.2), CFrame.new(side * 3.2, -0.4, 4.2) * CFrame.Angles(0, 0, side * math.rad(80)), trim, Enum.Material.SmoothPlastic)
	end
	visual(model, root, "WedgePart", Vector3.new(0.5, 2.4, 3.2), CFrame.new(0, 3, 4.6), trim, Enum.Material.SmoothPlastic)
	visual(model, root, "WedgePart", Vector3.new(0.5, 1.8, 2.6), CFrame.new(0, -2.8, 4.8) * CFrame.Angles(0, 0, math.pi), trim, Enum.Material.SmoothPlastic)

	-- neon stripes
	if skin.neonStripes then
		for side = -1, 1, 2 do
			visual(model, root, "Part", Vector3.new(0.2, 0.35, 8.5), CFrame.new(side * 2.95, 0.4, 0), glow, Enum.Material.Neon)
		end
	end

	-- headlights
	for side = -1, 1, 2 do
		shaped(model, root, Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), CFrame.new(side * 1.5, -0.9, -7.3), glow, Enum.Material.Neon)
	end
	local lightAttachment = Instance.new("Attachment")
	lightAttachment.Name = "Headlight"
	lightAttachment.Position = Vector3.new(0, -0.5, -7.5)
	lightAttachment.Parent = root
	local spot = Instance.new("SpotLight")
	spot.Name = "Headlamp"
	spot.Range = 60
	spot.Angle = 75
	spot.Brightness = 3
	spot.Color = glow
	spot.Shadows = false
	spot.Face = Enum.NormalId.Front
	spot.Parent = lightAttachment
	local glowLight = Instance.new("PointLight")
	glowLight.Name = "Glow"
	glowLight.Range = 16
	glowLight.Brightness = 0.9
	glowLight.Color = glow
	glowLight.Shadows = false
	glowLight.Parent = root

	-- propeller on a Weld (so the owning client can spin it)
	local hub = shaped(model, root, Enum.PartType.Cylinder, Vector3.new(1.2, 1.4, 1.4), CFrame.new(0, 0, 8) * Z, trim, Enum.Material.Metal)
	hub.Name = "PropHub"
	local hubConstraint = hub:FindFirstChildOfClass("WeldConstraint")
	if hubConstraint then
		hubConstraint:Destroy()
	end
	local propWeld = Instance.new("Weld")
	propWeld.Name = "PropWeld"
	propWeld.Part0 = root
	propWeld.Part1 = hub
	propWeld.C0 = CFrame.new(0, 0, 8) * Z
	propWeld.Parent = hub
	for blade = 1, 3 do
		local bladePart = Instance.new("Part")
		bladePart.Size = Vector3.new(0.3, 2.6, 0.9)
		bladePart.CFrame = hub.CFrame * CFrame.Angles(blade * math.pi * 2 / 3, 0, 0) * CFrame.new(0, 1.3, 0)
		bladePart.Color = trim
		bladePart.Material = Enum.Material.Metal
		bladePart.CanCollide = false
		bladePart.CanQuery = false
		bladePart.CanTouch = false
		bladePart.Massless = true
		bladePart.CastShadow = false
		bladePart.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = bladePart
		weld.Parent = bladePart
	end

	-- bubbles behind the propeller (rate driven by the client)
	local bubbleAttachment = Instance.new("Attachment")
	bubbleAttachment.Name = "Bubbles"
	bubbleAttachment.Position = Vector3.new(0, 0, 9)
	bubbleAttachment.Parent = root
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "BubbleTrail"
	bubbles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(1.2, 2)
	bubbles.Speed = NumberRange.new(2, 4)
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.Acceleration = Vector3.new(0, 6, 0)
	bubbles.EmissionDirection = Enum.NormalId.Back
	bubbles.Rate = 0
	bubbles.LightEmission = 0.2
	bubbles.Parent = bubbleAttachment

	-- pilot seat inside the dome
	local seat = Instance.new("Seat")
	seat.Name = "PilotSeat"
	seat.Size = Vector3.new(1.6, 0.4, 1.6)
	seat.CFrame = root.CFrame * CFrame.new(0, -0.2, -2.4)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	seat.Parent = model
	weldTo(root, seat)

	-- physics controllers (driven by the owning client)
	local centre = Instance.new("Attachment")
	centre.Name = "Centre"
	centre.Parent = root
	local linear = Instance.new("LinearVelocity")
	linear.Name = "Drive"
	linear.Attachment0 = centre
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = 1e7
	linear.VectorVelocity = Vector3.zero
	linear.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "Steer"
	align.Attachment0 = centre
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.MaxTorque = 1e7
	align.MaxAngularVelocity = 6
	align.Responsiveness = 18
	align.CFrame = cframe.Rotation
	align.Parent = root

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Subs"
		end
	end
	return model
end

-- A static copy for decoration (the workshop cradle, the Launch Bay crane): no seat, no
-- physics controllers, every part anchored and non-colliding.
function SubModel.display(skinId: string, cframe: CFrame): Model
	local model = SubModel.build(skinId, cframe)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("LinearVelocity") or descendant:IsA("AlignOrientation") or descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			descendant:Destroy()
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	model.Name = "DisplaySub"
	return model
end

return SubModel

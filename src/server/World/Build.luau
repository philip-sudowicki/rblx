--!strict
-- Small helpers for building anchored part geometry in code.

local CollectionService = game:GetService("CollectionService")

export type Props = { [string]: any }

local Build = {}

local function apply(inst: Instance, props: Props?)
	if props then
		for key, value in props do
			(inst :: any)[key] = value
		end
	end
end

local function finish(p: BasePart, color: Color3, material: Enum.Material, props: Props?)
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	apply(p, props)
end

function Build.part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, props: Props?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	return p
end

function Build.wedge(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, props: Props?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	return p
end

-- Cylinder whose axis runs along the given CFrame's X axis (Roblox cylinder convention).
function Build.cylinder(parent: Instance, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material, props: Props?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cframe
	finish(p, color, material, props)
	p.Parent = parent
	return p
end

-- Vertical cylinder standing on its base centre.
function Build.pillar(parent: Instance, height: number, diameter: number, base: Vector3, color: Color3, material: Enum.Material, props: Props?): Part
	return Build.cylinder(
		parent,
		height,
		diameter,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		props
	)
end

function Build.ball(parent: Instance, diameter: number, position: Vector3, color: Color3, material: Enum.Material, props: Props?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(position)
	finish(p, color, material, props)
	p.Parent = parent
	return p
end

-- Decorative part: no collision, no queries, no touch, no shadow (cheap).
function Build.soft(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

function Build.model(parent: Instance, name: string, atomic: boolean?): Model
	local m = Instance.new("Model")
	m.Name = name
	if atomic then
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	m.Parent = parent
	return m
end

function Build.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Build.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- A sign: a part with a SurfaceGui text label on its front face.
function Build.sign(parent: Instance, size: Vector3, cframe: CFrame, text: string, color: Color3, textColor: Color3, material: Enum.Material?): Part
	local board = Build.part(parent, size, cframe, color, material or Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 30, 45)
	stroke.Parent = label
	return board
end

return Build

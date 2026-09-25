--!strict
-- Client-only world life: swaying kelp, spinning trinkets, bobbing buoys, the lighthouse beam,
-- shimmering light shafts, vent smoke (off on Low graphics) and the Rift Seal, which is a
-- client-side barrier for players who haven't rebirthed yet (the server also clamps depth).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Rebirth = require(Shared.Config.Rebirth)
local ClientState = require(script.Parent.ClientState)

local WorldFXController = {}

type Kelp = { model: Model, parts: { BasePart }, base: { CFrame }, phase: number, center: Vector3 }
type Spinner = { part: BasePart?, model: Model?, base: CFrame, speed: number }

local kelps: { [Model]: Kelp } = {}
local spinners: { [Instance]: Spinner } = {}
local buoys: { [Model]: { parts: { BasePart }, base: { CFrame }, phase: number } } = {}
local lamps: { [BasePart]: CFrame } = {}
local shafts: { [BasePart]: number } = {}
local seal: Part? = nil
local sealLabel: TextLabel? = nil

local function lowGraphics(): boolean
	return ClientState.data ~= nil and ClientState.data.Settings.Graphics == "Low"
end

local function track(tag: string, onAdd: (Instance) -> (), onRemove: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(onAdd, inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdd)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemove)
end

local function addKelp(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local parts: { BasePart } = {}
	for _, child in inst:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	if #parts == 0 then
		return
	end
	local base = {}
	for i, part in parts do
		base[i] = part.CFrame
	end
	kelps[inst] = { model = inst, parts = parts, base = base, phase = math.random() * 6.28, center = parts[1].Position }
end

local function addSpinner(inst: Instance)
	if inst:IsA("BasePart") then
		spinners[inst] = { part = inst, model = nil, base = inst.CFrame, speed = 1.2 }
	elseif inst:IsA("Model") then
		spinners[inst] = { part = nil, model = inst, base = inst:GetPivot(), speed = 0.5 }
	end
end

local function addBuoy(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local parts: { BasePart } = {}
	local base = {}
	for _, child in inst:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
			table.insert(base, child.CFrame)
		end
	end
	buoys[inst] = { parts = parts, base = base, phase = math.random() * 6.28 }
end

local function addVent(inst: Instance)
	for _, emitter in inst:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = not lowGraphics()
		end
	end
end

local function buildSeal()
	local hadal = Zones.list[Zones.count - 1]
	local hole = hadal.hole
	if not hole then
		return
	end
	local part = Instance.new("Part")
	part.Name = "RiftSeal"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(4, hole.r * 2 + 4, hole.r * 2 + 4)
	part.CFrame = CFrame.new(hole.x, Zones.world.riftSealY + 3, hole.z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Anchored = true
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(200, 90, 255)
	part.CastShadow = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 90, 255)
	light.Range = 50
	light.Brightness = 2
	light.Parent = part
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(320, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	billboard.MaxDistance = 140
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(230, 170, 255)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	seal = part
	sealLabel = label
end

local function refreshSeal()
	if not seal or not sealLabel then
		return
	end
	local unlocked = ClientState.data ~= nil and ClientState.data.Rebirths >= Rebirth.riftUnlockRebirths
	seal.CanCollide = not unlocked
	seal.Transparency = if unlocked then 0.75 else 0.15
	sealLabel.Text = if unlocked then "🔱 THE RIFT - the Seal answers you 🔱" else "🔒 THE RIFT SEAL\nResurface once to open it"
end

local accumulator = 0

local function step(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	accumulator = 0
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local low = lowGraphics()

	if not low then
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for _, kelp in kelps do
			if (kelp.center - camPos).Magnitude < 170 then
				local sway = math.sin(t * 0.9 + kelp.phase)
				local sway2 = math.cos(t * 0.7 + kelp.phase * 1.3)
				for i, part in kelp.parts do
					local k = i - 1
					local bend = k ^ 1.4
					table.insert(parts, part)
					table.insert(cframes, kelp.base[i] + Vector3.new(sway * bend * 0.35, 0, sway2 * bend * 0.25))
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	for _, spinner in spinners do
		local angle = t * spinner.speed
		if spinner.part then
			spinner.part.CFrame = spinner.base * CFrame.Angles(0, angle, 0)
		elseif spinner.model then
			spinner.model:PivotTo(spinner.base * CFrame.Angles(0, angle, 0))
		end
	end

	for _, buoy in buoys do
		local bob = math.sin(t * 1.4 + buoy.phase) * 0.35
		local tilt = math.sin(t * 1.1 + buoy.phase) * 0.06
		for i, part in buoy.parts do
			part.CFrame = buoy.base[i] * CFrame.new(0, bob, 0) * CFrame.Angles(tilt, 0, tilt * 0.5)
		end
	end

	for lamp, base in lamps do
		lamp.CFrame = base * CFrame.Angles(0, t * 0.8, 0)
	end

	for shaft, phase in shafts do
		shaft.Transparency = 0.88 + math.sin(t * 0.6 + phase) * 0.04
	end
end

function WorldFXController.Start()
	track("Kelp", addKelp, function(inst)
		if inst:IsA("Model") then
			kelps[inst] = nil
		end
	end)
	track("Spin", addSpinner, function(inst)
		spinners[inst] = nil
	end)
	track("Buoy", addBuoy, function(inst)
		if inst:IsA("Model") then
			buoys[inst] = nil
		end
	end)
	track("LighthouseLamp", function(inst)
		if inst:IsA("BasePart") then
			lamps[inst] = inst.CFrame
		end
	end, function(inst)
		if inst:IsA("BasePart") then
			lamps[inst] = nil
		end
	end)
	track("LightShaft", function(inst)
		if inst:IsA("BasePart") then
			shafts[inst] = math.random() * 6.28
		end
	end, function(inst)
		if inst:IsA("BasePart") then
			shafts[inst] = nil
		end
	end)
	track("Vent", addVent, function() end)

	buildSeal()
	ClientState.Changed:Connect(function(key)
		if key == "*" or key == "Rebirths" then
			refreshSeal()
		end
		if key == "*" or key == "Settings" then
			for _, vent in CollectionService:GetTagged("Vent") do
				addVent(vent)
			end
		end
	end)
	refreshSeal()
	RunService.RenderStepped:Connect(step)
end

return WorldFXController

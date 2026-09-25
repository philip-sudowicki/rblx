--!strict
-- Aquarium tanks: builds the displayed fish or treasure inside every tank from the tank's
-- replicated attributes (Kind, ItemId, Mutation, Colossal, Locked). Fish swim a slow figure
-- eight behind the glass and treasure turns on the sand. Models are local to this client and
-- only animated near the camera; a nameplate shows what's inside when you walk past.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Theme = require(Shared.Config.Theme)
local FishModel = require(Shared.Models.FishModel)
local TreasureModel = require(Shared.Models.TreasureModel)
local FishAnimator = require(script.Parent.Parent.Render.FishAnimator)
local ClientState = require(script.Parent.ClientState)

local AquariumRenderer = {}

local TAG = "AquariumTank"
local ANIMATE_RADIUS = 120
local SCAN_INTERVAL = 0.5
-- Water volume inside a tank, relative to its Glass part (see World/Dock.luau tank()):
-- glass is 4.8 × 4.4 × 3.8 and the sand top sits 1.9 studs below the glass centre.
local INNER = Vector3.new(4.2, 3.6, 3.2)
local SAND_OFFSET = -1.9

type View = {
	tank: Model,
	glass: BasePart,
	key: string,
	fish: FishModel.Built?,
	treasure: TreasureModel.Built?,
	-- treasure: offset that puts the model's footprint centre on the sand
	footing: CFrame,
	length: number,
	halfTravel: number,
	phase: number,
	speed: number,
	label: BillboardGui,
}

local views: { [Model]: View } = {}
local folder: Folder
local parts: { BasePart } = {}
local frames: { CFrame } = {}

local function tankKey(tank: Model): string
	local kind = tank:GetAttribute("Kind")
	local itemId = tank:GetAttribute("ItemId")
	if tank:GetAttribute("Locked") == true or typeof(kind) ~= "string" or kind == "" or typeof(itemId) ~= "string" or itemId == "" then
		return ""
	end
	local mutation = tank:GetAttribute("Mutation")
	return string.format("%s|%s|%s|%s", kind, itemId, if typeof(mutation) == "string" then mutation else "", tostring(tank:GetAttribute("Colossal") == true))
end

local function destroyView(view: View)
	if view.fish then
		view.fish.model:Destroy()
	end
	if view.treasure then
		view.treasure.model:Destroy()
	end
	view.label:Destroy()
	views[view.tank] = nil
end

local function nameplate(glass: BasePart, title: string, rarity: Rarities.Rarity): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "DH_TankLabel"
	gui.Adornee = glass
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffset = Vector3.new(0, 3.3, 0)
	gui.MaxDistance = 26
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.6)
	name.Font = Theme.FontBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = title
	name.Parent = gui
	local tier = Instance.new("TextLabel")
	tier.BackgroundTransparency = 1
	tier.Position = UDim2.fromScale(0, 0.6)
	tier.Size = UDim2.fromScale(1, 0.4)
	tier.Font = Theme.FontBold
	tier.TextScaled = true
	tier.TextColor3 = rarity.color
	tier.Text = rarity.name
	tier.Parent = gui
	for _, label in { name, tier } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Parent = label
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- World-axis bounding box of freshly built parts (models are built around the origin).
local function bounds(builtParts: { BasePart }): (Vector3, Vector3)
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for _, part in builtParts do
		local cf = part.CFrame
		local half = part.Size / 2
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local extent = Vector3.new(
			math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
			math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
			math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
		)
		low = low:Min(cf.Position - extent)
		high = high:Max(cf.Position + extent)
	end
	return low, high
end

local function seedOf(tank: Model): number
	local plot = tank:GetAttribute("PlotIndex")
	local index = tank:GetAttribute("TankIndex")
	return (if typeof(plot) == "number" then plot else 0) * 31 + (if typeof(index) == "number" then index else 0) * 7
end

local function buildView(tank: Model, glass: BasePart, key: string): View?
	local kind = tank:GetAttribute("Kind")
	local itemId = tank:GetAttribute("ItemId")
	if typeof(kind) ~= "string" or typeof(itemId) ~= "string" then
		return nil
	end
	local lowGraphics = ClientState.data ~= nil and ClientState.data.Settings.Graphics == "Low"
	local seed = seedOf(tank)
	if kind == "F" then
		local def = Fish.byId[itemId]
		if not def then
			return nil
		end
		local rarity = Rarities.byId[def.rarity]
		local colossal = tank:GetAttribute("Colossal") == true
		local target = if colossal then 3.4 else 2.4
		local scale = math.clamp(target / def.model.length, 0.08, if colossal then 1.8 else 1.2)
		local mutationAttr = tank:GetAttribute("Mutation")
		local mutation = if typeof(mutationAttr) == "string" and Mutations.byId[mutationAttr] then mutationAttr else nil
		local built = FishModel.build(def.model, { rarity = rarity.index, mutation = mutation, scale = scale, simple = lowGraphics })
		built.model.Name = "Tank" .. seed
		built.model.Parent = folder
		local length = def.model.length * scale
		local title = (if mutation then Mutations.byId[mutation].name .. " " else "") .. (if colossal then "Colossal " else "") .. def.name
		return {
			tank = tank,
			glass = glass,
			key = key,
			fish = built,
			treasure = nil,
			footing = CFrame.identity,
			length = length,
			halfTravel = math.max(0, INNER.X / 2 - length / 2 - 0.1),
			phase = (seed % 628) / 100,
			speed = 0.42 + (seed % 5) * 0.05,
			label = nameplate(glass, title, rarity),
		}
	elseif kind == "T" then
		local def = Treasure.byId[itemId]
		if not def then
			return nil
		end
		local rarity = Rarities.byId[def.rarity]
		-- measure at scale 1, then rebuild to fit inside the glass
		local probe = TreasureModel.build(def.model, { rarity = rarity.index, simple = true })
		local probeLow, probeHigh = bounds(probe.parts)
		probe.model:Destroy()
		local extents = probeHigh - probeLow
		local fit = math.min(1, 2.7 / math.max(extents.X, extents.Z, 0.1), (INNER.Y - 0.6) / math.max(extents.Y, 0.1))
		local built = TreasureModel.build(def.model, { rarity = rarity.index, scale = fit, simple = lowGraphics })
		built.model.Name = "Tank" .. seed
		built.model.Parent = folder
		local low, high = bounds(built.parts)
		local centre = (low + high) / 2
		local footing = CFrame.new(-centre.X, -low.Y + 0.05, -centre.Z)
		return {
			tank = tank,
			glass = glass,
			key = key,
			fish = nil,
			treasure = built,
			footing = footing,
			length = 0,
			halfTravel = 0,
			phase = (seed % 628) / 100,
			speed = 0.35,
			label = nameplate(glass, def.name, rarity),
		}
	end
	return nil
end

local function pose(view: View, t: number)
	local glassCf = view.glass.CFrame
	local fish = view.fish
	if fish then
		local u = t * view.speed + view.phase
		local x = math.sin(u) * view.halfTravel
		local z = math.sin(u * 2) * 0.45
		local y = 0.15 + math.sin(u * 1.3) * 0.35
		local velocity = glassCf:VectorToWorldSpace(Vector3.new(math.cos(u) * view.halfTravel, 0, math.cos(u * 2) * 0.9))
		local position = glassCf * Vector3.new(x, y, z)
		if velocity.Magnitude < 1e-3 then
			velocity = glassCf.RightVector
		end
		local cf = CFrame.lookAt(position, position + velocity)
		FishAnimator.append(fish, cf, t, view.phase, view.length, 0.6 + view.speed, parts, frames)
		FishAnimator.tint(fish, t)
		return
	end
	local treasure = view.treasure
	if treasure then
		local base = glassCf * CFrame.new(0, SAND_OFFSET, 0) * CFrame.Angles(0, t * view.speed + view.phase, 0) * view.footing
		for i, part in treasure.parts do
			table.insert(parts, part)
			table.insert(frames, base * treasure.offsets[i])
		end
		FishAnimator.tint(treasure, t)
	end
end

local function flush()
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	table.clear(parts)
	table.clear(frames)
end

local function scan()
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("Model") then
			local glass = instance:FindFirstChild("Glass")
			local glassPart = if glass and glass:IsA("BasePart") then glass else nil
			local key = if glassPart then tankKey(instance) else ""
			local view: View? = views[instance]
			if view and (view.key ~= key or view.glass ~= glassPart) then
				destroyView(view)
				view = nil
			end
			if not view and key ~= "" and glassPart then
				local built = buildView(instance, glassPart, key)
				if built then
					views[instance] = built
					pose(built, os.clock())
				end
			end
		end
	end
	for tank, view in views do
		if not tank:IsDescendantOf(workspace) or not view.glass:IsDescendantOf(workspace) then
			destroyView(view)
		end
	end
	flush()
end

function AquariumRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "DH_AquariumLocal"
	folder.Parent = workspace
end

function AquariumRenderer.Start()
	local graphics = ""
	ClientState.Changed:Connect(function(key)
		local data = ClientState.data
		if (key == "Settings" or key == "*") and data and data.Settings.Graphics ~= graphics then
			graphics = data.Settings.Graphics
			-- rebuild at the new graphics level on the next scan
			for _, view in views do
				view.key = "rebuild"
			end
		end
	end)
	task.spawn(function()
		while true do
			scan()
			task.wait(SCAN_INTERVAL)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		local t = os.clock()
		for _, view in views do
			if (view.glass.Position - camPos).Magnitude < ANIMATE_RADIUS then
				pose(view, t)
			end
		end
		flush()
	end)
end

return AquariumRenderer

--!strict
-- A ViewportFrame showing a fish or treasure model (optionally spinning, optionally as a black
-- silhouette for undiscovered Index entries). One shared RenderStepped loop spins all of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local FishModel = require(Shared.Models.FishModel)
local TreasureModel = require(Shared.Models.TreasureModel)

export type ViewOptions = {
	mutation: string?,
	colossal: boolean?,
	silhouette: boolean?,
	spin: boolean?,
}

export type ItemView = {
	frame: ViewportFrame,
	set: (kind: string, id: string, options: ViewOptions?) -> (),
	clear: () -> (),
	destroy: () -> (),
}

local ItemViewport = {}

type Entry = { built: any, isFish: boolean, spin: boolean, angle: number, frame: ViewportFrame, center: CFrame }
local active: { [ViewportFrame]: Entry } = {}

local function place(entry: Entry)
	local cf = entry.center * CFrame.Angles(0, entry.angle, 0)
	if entry.isFish then
		FishModel.place(entry.built, cf * CFrame.Angles(0, math.pi / 2, 0))
	else
		TreasureModel.place(entry.built, cf)
	end
end

function ItemViewport.new(parent: Instance, size: UDim2, position: UDim2?): ItemView
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.Ambient = Color3.fromRGB(170, 180, 200)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-1, -1.5, -1)
	frame.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera

	local function clear()
		local entry = active[frame]
		if entry then
			entry.built.model:Destroy()
			active[frame] = nil
		end
	end

	local function set(kind: string, id: string, options: ViewOptions?)
		clear()
		local opts: ViewOptions = options or {}
		local built: any
		local isFish = kind == "F"
		if isFish then
			local def = Fish.byId[id]
			if not def then
				return
			end
			built = FishModel.build(def.model, {
				rarity = Rarities.byId[def.rarity].index,
				mutation = opts.mutation,
				simple = true,
			})
		else
			local def = Treasure.byId[id]
			if not def then
				return
			end
			built = TreasureModel.build(def.model, { rarity = Rarities.byId[def.rarity].index, simple = true })
		end
		built.model.Parent = frame
		local entry: Entry = { built = built, isFish = isFish, spin = opts.spin ~= false, angle = 0, frame = frame, center = CFrame.identity }
		place(entry)
		local extents = built.model:GetExtentsSize()
		local radius = math.max(extents.X, extents.Y, extents.Z) * 0.62
		local centre = built.model:GetBoundingBox().Position
		entry.center = CFrame.new(-centre)
		place(entry)
		camera.CFrame = CFrame.lookAt(Vector3.new(radius * 1.2, radius * 0.7, radius * 2.4), Vector3.zero)
		frame.ImageColor3 = if opts.silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		active[frame] = entry
	end

	return {
		frame = frame,
		set = set,
		clear = clear,
		destroy = function()
			clear()
			frame:Destroy()
		end,
	}
end

RunService.RenderStepped:Connect(function(dt: number)
	for frame, entry in active do
		if not frame.Parent then
			active[frame] = nil
		elseif entry.spin and frame.Visible then
			entry.angle += dt * 0.9
			place(entry)
		end
	end
end)

return ItemViewport

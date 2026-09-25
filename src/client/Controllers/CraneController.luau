--!strict
-- Your submarine, in your equipped skin, hanging from the Launch Bay crane and swaying gently in
-- the breeze. Local to this client; it disappears while you dive (the real sub drops from the
-- same hook) and comes back when you surface or change skin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local SubModel = require(Shared.Models.SubModel)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)

local CraneController = {}

local display: Model? = nil
local displaySkin = ""
local offsets: { { part: BasePart, offset: CFrame } } = {}
local baseCf = CFrame.identity

local function remove()
	if display then
		display:Destroy()
		display = nil
	end
	table.clear(offsets)
	displaySkin = ""
end

local function refresh()
	local data = ClientState.data
	if not data or SubController.isDiving() then
		remove()
		return
	end
	local skin = data.Skins.Equipped
	if display and displaySkin == skin then
		return
	end
	remove()
	local world = Zones.world
	local hang = world.launchHang
	baseCf = CFrame.lookAt(hang, Vector3.new(world.launchLook.X, hang.Y, world.launchLook.Z))
	local model = SubModel.display(skin, baseCf)
	model.Name = "CraneSub"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(offsets, { part = part, offset = baseCf:ToObjectSpace(part.CFrame) })
		end
	end
	model.Parent = workspace
	display = model
	displaySkin = skin
end

function CraneController.Start()
	ClientState.waitReady()
	refresh()
	ClientState.Changed:Connect(function(key)
		if key == "Skins" or key == "*" then
			refresh()
		end
	end)
	SubController.Started:Connect(remove)
	SubController.Ended:Connect(function()
		task.delay(1, refresh)
	end)
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	RunService.Heartbeat:Connect(function()
		if not display or #offsets == 0 then
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - baseCf.Position).Magnitude > 300 then
			return
		end
		local t = os.clock()
		local sway = baseCf * CFrame.new(0, 3.5, 0) * CFrame.Angles(math.sin(t * 0.8) * 0.03, math.sin(t * 0.5) * 0.05, math.sin(t * 1.1) * 0.04) * CFrame.new(0, -3.5, 0)
		table.clear(parts)
		table.clear(frames)
		for _, entry in offsets do
			table.insert(parts, entry.part)
			table.insert(frames, sway * entry.offset)
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return CraneController

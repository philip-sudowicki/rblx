--!strict
-- Overhead nametags with the rebirth badge and VIP tag, plus player attributes that clients use
-- for chat tags.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rebirth = require(Shared.Config.Rebirth)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local ServerSignals = require(script.Parent.ServerSignals)

local NametagService = {}

function NametagService.badgeFor(rebirths: number): (string?, Color3?)
	local best: { at: number, text: string, color: Color3 }? = nil
	for _, badge in Rebirth.badges do
		if rebirths >= badge.at then
			best = badge
		end
	end
	if best then
		return best.text, best.color
	end
	return nil, nil
end

local function build(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not head or not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local existing = head:FindFirstChild("DeepHaulTag")
	if existing then
		existing:Destroy()
	end
	local data = DataService.get(player)
	local state = PlayerState.get(player)
	local rebirths = if data then data.Rebirths else 0
	local vip = state ~= nil and state.passes.VIP == true
	local gui = Instance.new("BillboardGui")
	gui.Name = "DeepHaulTag"
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = head
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.RichText = true
	name.Text = if vip then '<font color="#FFD24A">[VIP]</font> ' .. player.DisplayName else player.DisplayName
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = name
	local text, color = NametagService.badgeFor(rebirths)
	if text then
		local badge = Instance.new("TextLabel")
		badge.BackgroundTransparency = 1
		badge.Position = UDim2.fromScale(0, 0.58)
		badge.Size = UDim2.new(1, 0, 0.42, 0)
		badge.Font = Enum.Font.GothamBold
		badge.TextScaled = true
		badge.TextColor3 = color :: Color3
		badge.Text = string.format("%s Resurfaced ×%d", text, rebirths)
		badge.Parent = gui
		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Thickness = 1.5
		badgeStroke.Parent = badge
	end
	gui.Parent = head
	player:SetAttribute("Rebirths", rebirths)
	player:SetAttribute("VIP", vip)
end

function NametagService.refresh(player: Player)
	build(player)
end

function NametagService.Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 5)
			build(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	DataService.onLoaded(build)
	ServerSignals.Rebirthed:Connect(build)
	ServerSignals.StatsDirty:Connect(function(player)
		local state = PlayerState.get(player)
		if state and (player:GetAttribute("VIP") == true) ~= (state.passes.VIP == true) then
			build(player)
		end
	end)
end

return NametagService

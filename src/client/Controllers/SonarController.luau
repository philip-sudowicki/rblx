--!strict
-- Sonar ping (F / Y / SONAR button): an expanding wave around the sub, then markers on every
-- fish, treasure and predator in range for a few seconds (BillboardGuis, not Highlights, so
-- there is no 31-highlight limit). The server applies the cooldown and stuns predators.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Rarities = require(Shared.Config.Rarities)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local EntityRenderer = require(script.Parent.EntityRenderer)
local AudioController = require(script.Parent.AudioController)
local HUDController = require(script.Parent.HUDController)

local SonarController = {}

local player = Players.LocalPlayer
local readyAt = 0
local indicator: TextLabel
local markers: { BillboardGui } = {}

local function clearMarkers()
	for _, gui in markers do
		gui:Destroy()
	end
	table.clear(markers)
end

local function markerAt(adornee: Instance, text: string, color: Color3, distance: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(70, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1000
	gui.Adornee = adornee
	local dot = Instance.new("TextLabel")
	dot.BackgroundTransparency = 1
	dot.Size = UDim2.fromScale(1, 0.6)
	dot.Font = Enum.Font.FredokaOne
	dot.TextScaled = true
	dot.Text = text
	dot.TextColor3 = color
	dot.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = dot
	local range = Instance.new("TextLabel")
	range.BackgroundTransparency = 1
	range.Position = UDim2.fromScale(0, 0.6)
	range.Size = UDim2.fromScale(1, 0.4)
	range.Font = Enum.Font.GothamBold
	range.TextScaled = true
	range.Text = string.format("%dm", math.floor(distance))
	range.TextColor3 = Color3.new(1, 1, 1)
	range.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	table.insert(markers, gui)
end

local function wave(origin: Vector3, radius: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.ForceField
	part.Color = Theme.Accent
	part.Size = Vector3.new(4, 4, 4)
	part.Position = origin
	part.Transparency = 0.2
	part.Parent = workspace
	local tween = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		part:Destroy()
	end)
end

local function ping()
	if not SubController.isDiving() then
		return
	end
	local root = SubController.root
	if not root then
		return
	end
	local now = os.clock()
	if now < readyAt then
		AudioController.play("UIError")
		return
	end
	local stats = ClientState.stats()
	readyAt = now + stats.sonarCooldown
	Net.event("Sonar"):FireServer()
	AudioController.play("SonarPing")
	local origin = root.Position
	wave(origin, stats.sonarRange)
	clearMarkers()
	task.delay(0.35, function()
		local entries: { { adornee: Instance, d: number, text: string, color: Color3 } } = {}
		for id, view in EntityRenderer.fish do
			local d = (view.position - origin).Magnitude
			if d <= stats.sonarRange then
				local rarity = Rarities.list[view.tier]
				local built = view.built
				local adornee: Instance = if built then built.root else EntityRenderer.anchorFor(id, view.position)
				table.insert(entries, { adornee = adornee, d = d, text = if rarity.index >= 4 then "✦🐟" else "🐟", color = rarity.color })
			end
		end
		for id, view in EntityRenderer.treasure do
			local d = (view.position - origin).Magnitude
			if d <= stats.sonarRange then
				local rarity = Rarities.list[view.tier]
				local built = view.built
				local adornee: Instance = if built then built.root else EntityRenderer.anchorFor(id, view.position)
				table.insert(entries, { adornee = adornee, d = d, text = "💎", color = rarity.color })
			end
		end
		for _, view in EntityRenderer.predators do
			local d = (view.position - origin).Magnitude
			if d <= stats.sonarRange then
				local adornee: Instance = view.built.root
				table.insert(entries, { adornee = adornee, d = d, text = "⚠", color = Theme.Bad })
			end
		end
		table.sort(entries, function(a, b)
			return a.d < b.d
		end)
		for i = 1, math.min(#entries, Game.Sonar.MaxMarkers) do
			local e = entries[i]
			markerAt(e.adornee, e.text, e.color, e.d)
			if i <= 6 then
				task.delay(i * 0.08, function()
					AudioController.play("SonarBlip", 1 + i * 0.03, 0.6)
				end)
			end
		end
		task.delay(Game.Sonar.MarkerSeconds, clearMarkers)
	end)
end

function SonarController.Init()
	indicator = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(220, 24),
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = HUDController.diveRoot,
	})
	UIKit.scaled(indicator)
	UIKit.textStroke(1.5).Parent = indicator
end

function SonarController.Start()
	InputController.Sonar:Connect(ping)
	Net.event("Effect").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.kind == "SonarAck" and (payload.stunned or 0) > 0 then
			HUDController.toast(string.format("Sonar stunned %d predator%s!", payload.stunned, if payload.stunned == 1 then "" else "s"), "good", "📡")
		end
	end)
	SubController.Ended:Connect(clearMarkers)
	RunService.RenderStepped:Connect(function()
		if not SubController.isDiving() then
			return
		end
		local remaining = readyAt - os.clock()
		local key = if InputController.mode == "Gamepad" then "Y" elseif InputController.mode == "Touch" then "SONAR" else "F"
		if remaining > 0 then
			indicator.Text = string.format("📡 Sonar %.0fs", math.ceil(remaining))
			indicator.TextColor3 = Theme.TextMuted
		else
			indicator.Text = string.format("📡 Sonar ready [%s]", key)
			indicator.TextColor3 = Theme.Accent
		end
	end)
end

return SonarController

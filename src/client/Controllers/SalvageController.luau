--!strict
-- Hold-to-salvage feedback: a segmented progress ring filling while you hold Action near
-- treasure. The server times the salvage; this only draws it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local HUDController = require(script.Parent.HUDController)

local SalvageController = {}

SalvageController.active = false

local SEGMENTS = 32
local gui: ScreenGui
local ring: Frame
local segments: { Frame } = {}
local label: TextLabel
local startedAt = 0
local duration = 1
local sessionId = 0

local function hide()
	SalvageController.active = false
	SubController.damping = 1
	AudioController.loop("SalvageLoop", false)
	gui.Enabled = false
end

local function step()
	if not SalvageController.active then
		return
	end
	local progress = math.clamp((os.clock() - startedAt) / duration, 0, 1)
	local lit = math.floor(progress * SEGMENTS + 0.5)
	for i, seg in segments do
		seg.BackgroundColor3 = if i <= lit then Theme.Accent else Theme.PanelDark
		seg.BackgroundTransparency = if i <= lit then 0 else 0.4
	end
	label.Text = string.format("SALVAGING %d%%", math.floor(progress * 100))
end

function SalvageController.Init()
	gui = UIKit.screen("DeepHaulSalvage", 24)
	gui.Enabled = false
	ring = UIKit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(170, 170),
		Parent = gui,
	})
	UIKit.scaled(ring)
	for i = 1, SEGMENTS do
		local angle = (i - 1) / SEGMENTS * math.pi * 2 - math.pi / 2
		local seg = UIKit.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * 72, 0.5, math.sin(angle) * 72),
			Size = UDim2.fromOffset(10, 16),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = Theme.PanelDark,
			Parent = ring,
		})
		UIKit.corner(UDim.new(1, 0)).Parent = seg
		segments[i] = seg
	end
	label = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 30),
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = ring,
	})
	UIKit.textStroke(1.5).Parent = label
end

function SalvageController.Start()
	Net.event("SalvageState").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.state == "start" then
			sessionId = payload.id
			startedAt = os.clock()
			duration = math.max(0.2, payload.duration)
			SalvageController.active = true
			SubController.damping = 0.35
			gui.Enabled = true
			AudioController.loop("SalvageLoop", true)
		elseif payload.id == sessionId then
			hide()
			if payload.state == "done" then
				AudioController.play("SalvageDone")
			elseif payload.reason == "moved" then
				HUDController.toast("Stay close to the treasure while salvaging!", "warn", "🧲")
			end
		end
	end)
	SubController.Ended:Connect(hide)
	RunService.RenderStepped:Connect(step)
end

return SalvageController

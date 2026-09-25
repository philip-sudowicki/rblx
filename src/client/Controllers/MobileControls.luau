--!strict
-- Big, thumb-friendly touch buttons for dives, grouped in one bottom-right cluster so they
-- scale together and never overlap: ACTION (large), UP / DOWN, SONAR, SURFACE (hold) and SLOW.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)

local MobileControls = {}

local cluster: Frame
local actionButton: TextButton
local actionLabel: TextLabel
local actionEnabled = true
local slowButton: TextButton

local function circleButton(parent: Instance, text: string, size: number, position: UDim2, color: Color3): TextButton
	local button = UIKit.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	}) :: TextButton
	UIKit.corner(UDim.new(1, 0)).Parent = button
	UIKit.stroke(Color3.new(1, 1, 1), 3, 0.5).Parent = button
	local label = UIKit.label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontDisplay,
		TextSize = math.floor(size * 0.24),
		TextWrapped = true,
		Parent = button,
	})
	label.Name = "Label"
	UIKit.textStroke(2).Parent = label
	return button
end

local function onHold(button: TextButton, down: () -> (), up: () -> ())
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			UIKit.tween(button, { Size = button.Size - UDim2.fromOffset(6, 6) }, 0.08)
			down()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			UIKit.tween(button, { Size = button.Size + UDim2.fromOffset(6, 6) }, 0.1)
			up()
		end
	end)
end

-- Context label for the ACTION button (set by the interaction system)
function MobileControls.setAction(text: string, enabled: boolean, color: Color3?)
	if not actionLabel then
		return
	end
	actionLabel.Text = text
	actionEnabled = enabled
	actionButton.BackgroundColor3 = color or (if enabled then Theme.Accent else Theme.PanelLight)
	actionButton.BackgroundTransparency = if enabled then 0.1 else 0.45
end

local function refreshVisibility()
	cluster.Visible = SubController.isDiving() and InputController.mode == "Touch"
end

function MobileControls.Init()
	local gui = UIKit.screen("DeepHaulTouch", 8)
	cluster = UIKit.frame({
		Name = "Cluster",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(400, 330),
		Visible = false,
		Parent = gui,
	})
	UIKit.scaled(cluster)
	-- layout inside the 400×330 cluster (centres)
	actionButton = circleButton(cluster, "ACTION", 150, UDim2.fromOffset(318, 248), Theme.Accent)
	actionLabel = actionButton:FindFirstChild("Label") :: TextLabel
	local up = circleButton(cluster, "▲\nUP", 84, UDim2.fromOffset(186, 190), Theme.PanelLight)
	local down = circleButton(cluster, "▼\nDOWN", 84, UDim2.fromOffset(186, 284), Theme.PanelLight)
	local sonar = circleButton(cluster, "📡\nSONAR", 84, UDim2.fromOffset(330, 116), Theme.PanelLight)
	local surface = circleButton(cluster, "🚨\nHOLD", 72, UDim2.fromOffset(222, 70), Color3.fromRGB(150, 70, 30))
	slowButton = circleButton(cluster, "🤫\nSLOW", 72, UDim2.fromOffset(62, 250), Theme.PanelLight)

	onHold(actionButton, function()
		if actionEnabled then
			InputController.pressAction(true)
		end
	end, function()
		InputController.pressAction(false)
	end)
	onHold(up, function()
		InputController.setTouchVertical(1)
	end, function()
		InputController.setTouchVertical(0)
	end)
	onHold(down, function()
		InputController.setTouchVertical(-1)
	end, function()
		InputController.setTouchVertical(0)
	end)
	onHold(sonar, function()
		InputController.Sonar:Fire()
	end, function() end)
	onHold(surface, function()
		InputController.beginEmergency()
	end, function()
		InputController.endEmergency()
	end)
	onHold(slowButton, function()
		InputController.setSilent(not InputController.silent)
	end, function() end)
	InputController.SilentChanged:Connect(function(silent)
		slowButton.BackgroundColor3 = if silent then Theme.Accent else Theme.PanelLight
	end)
end

function MobileControls.Start()
	InputController.ModeChanged:Connect(refreshVisibility)
	SubController.Started:Connect(refreshVisibility)
	SubController.Ended:Connect(function()
		refreshVisibility()
		InputController.setTouchVertical(0)
	end)
	refreshVisibility()
end

return MobileControls

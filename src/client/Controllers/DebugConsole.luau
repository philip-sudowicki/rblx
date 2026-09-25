--!strict
-- Studio-only debug console: press F8 to open a one-line command box (see server DebugService).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local DebugConsole = {}

function DebugConsole.Start()
	if not RunService:IsStudio() then
		return
	end
	local gui = UIKit.screen("DeepHaulDebug", 90)
	local box = UIKit.new("TextBox", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(560, 40),
		BackgroundColor3 = Theme.PanelDark,
		TextColor3 = Theme.Text,
		PlaceholderText = "debug: coins 1e6 · maxupgrades · depth 6000 · event Leviathan 300 · event stop · tutorial reset",
		PlaceholderColor3 = Theme.TextMuted,
		Font = Theme.FontBold,
		TextSize = 15,
		ClearTextOnFocus = true,
		Visible = false,
		Parent = gui,
	}) :: TextBox
	UIKit.corner(Theme.CornerSmall).Parent = box
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.F8 and not processed then
			box.Visible = not box.Visible
			if box.Visible then
				box:CaptureFocus()
			end
		end
	end)
	box.FocusLost:Connect(function(enter)
		if enter and #box.Text > 0 then
			Net.event("DebugCommand"):FireServer(box.Text)
		end
		box.Visible = false
	end)
end

return DebugConsole

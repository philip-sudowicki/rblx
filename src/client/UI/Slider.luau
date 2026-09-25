--!strict
-- A horizontal 0..1 slider: drag with mouse or touch, or select it with a gamepad and use
-- left / right on the D-pad or stick. `onChange` fires while dragging; `onCommit` once released.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local UIKit = require(script.Parent.UIKit)

export type Slider = {
	frame: Frame,
	knob: TextButton,
	set: (value: number) -> (),
	get: () -> number,
}

local Slider = {}

local STEP = 0.05

function Slider.new(parent: Instance, position: UDim2, width: number, initial: number, onChange: (number) -> (), onCommit: ((number) -> ())?): Slider
	local frame = UIKit.frame({ BackgroundTransparency = 1, Position = position, Size = UDim2.fromOffset(width, 30), Parent = parent })
	local track = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 10), Parent = frame })
	UIKit.corner(UDim.new(1, 0)).Parent = track
	UIKit.stroke(Theme.Stroke, 1.5, 0.3).Parent = track
	local fill = UIKit.frame({ BackgroundColor3 = Theme.Accent, Size = UDim2.fromScale(initial, 1), Parent = track })
	UIKit.corner(UDim.new(1, 0)).Parent = fill
	local knob = UIKit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(initial, 0.5),
		Size = UDim2.fromOffset(26, 26),
		Selectable = true,
		Parent = frame,
	}) :: TextButton
	UIKit.corner(UDim.new(1, 0)).Parent = knob
	UIKit.stroke(Theme.Accent, 3, 0).Parent = knob
	-- left / right adjust the value instead of moving the gamepad selection sideways
	knob.NextSelectionLeft = knob
	knob.NextSelectionRight = knob

	local value = math.clamp(initial, 0, 1)
	local dragging = false

	local function set(v: number)
		value = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
	end

	local function fromScreenX(x: number)
		local left = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		set((x - left) / w)
		onChange(value)
	end

	local function commit()
		if onCommit then
			onCommit(value)
		end
	end

	local function begin(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromScreenX(input.Position.X)
		end
	end
	knob.InputBegan:Connect(begin)
	track.InputBegan:Connect(begin)
	track.Active = true
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			commit()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if GuiService.SelectedObject ~= knob then
			return
		end
		local delta = 0
		if input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			delta = -STEP
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			delta = STEP
		end
		if delta ~= 0 then
			set(value + delta)
			onChange(value)
			commit()
		end
	end)
	knob.SelectionGained:Connect(function()
		UIKit.tween(knob, { Size = UDim2.fromOffset(32, 32) }, 0.1)
	end)
	knob.SelectionLost:Connect(function()
		UIKit.tween(knob, { Size = UDim2.fromOffset(26, 26) }, 0.1)
	end)

	return {
		frame = frame,
		knob = knob,
		set = set,
		get = function()
			return value
		end,
	}
end

return Slider

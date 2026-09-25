--!strict
-- Tiny UI toolkit: instance builder, themed components, tweens and responsive scaling.
-- Everything is designed at a 1280×720 reference size; UIScale objects registered with
-- UIKit.scaled() are kept in step with the viewport (bigger on touch screens).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local Signal = require(Shared.Modules.Signal)

export type Props = { [string]: any }

local UIKit = {}

UIKit.Theme = Theme
UIKit.clickSound = nil :: (() -> ())?
UIKit.hoverSound = nil :: (() -> ())?
-- (scale) fired whenever the responsive scale factor may have changed
UIKit.ScaleChanged = Signal.new() :: Signal.Signal<number>

local player = Players.LocalPlayer

function UIKit.new(className: string, props: Props?, children: { Instance }?): Instance
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(radius: UDim?): UICorner
	return UIKit.new("UICorner", { CornerRadius = radius or Theme.Corner }) :: UICorner
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
end

function UIKit.textStroke(thickness: number?, color: Color3?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Color3.fromRGB(4, 10, 20),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}) :: UIStroke
end

function UIKit.padding(top: number, right: number?, bottom: number?, left: number?): UIPadding
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	}) :: UIPadding
end

function UIKit.list(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
end

function UIKit.grid(cell: UDim2, padding: UDim2?): UIGridLayout
	return UIKit.new("UIGridLayout", {
		CellSize = cell,
		CellPadding = padding or UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}) :: UIGridLayout
end

function UIKit.gradient(color: ColorSequence, rotation: number?, transparency: NumberSequence?): UIGradient
	return UIKit.new("UIGradient", {
		Color = color,
		Rotation = rotation or 90,
		Transparency = transparency or NumberSequence.new(0),
	}) :: UIGradient
end

function UIKit.frame(props: Props?, children: { Instance }?): Frame
	local base: Props = { BackgroundColor3 = Theme.Panel, BorderSizePixel = 0 }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return UIKit.new("Frame", base, children) :: Frame
end

function UIKit.panel(props: Props?, children: { Instance }?): Frame
	local frame = UIKit.frame(props, children)
	UIKit.corner().Parent = frame
	UIKit.stroke(Theme.Stroke, 2, 0.2).Parent = frame
	UIKit.gradient(ColorSequence.new(Theme.PanelLight, Theme.Panel), 90).Parent = frame
	return frame
end

function UIKit.label(props: Props?): TextLabel
	local base: Props = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 24),
		TextWrapped = true,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return UIKit.new("TextLabel", base) :: TextLabel
end

function UIKit.tween(inst: Instance, props: Props, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time or Theme.TweenMedium, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- A themed button. `color` defaults to the accent. Returns the button; onClick receives no args.
function UIKit.button(props: Props?, onClick: (() -> ())?, color: Color3?): TextButton
	local base: Props = {
		BackgroundColor3 = color or Theme.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.FontBold,
		TextColor3 = if color and color ~= Theme.Accent then Theme.Text else Theme.TextDark,
		TextSize = 18,
		Text = "",
		Size = UDim2.fromOffset(140, 44),
		RichText = true,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local button = UIKit.new("TextButton", base) :: TextButton
	UIKit.corner(Theme.CornerSmall).Parent = button
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button }) :: UIScale
	-- Hover brightens through an overlay, so code is free to recolour the button at any time.
	local glow = UIKit.frame({
		Name = "HoverGlow",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	})
	UIKit.corner(Theme.CornerSmall).Parent = glow
	local function hover(on: boolean)
		UIKit.tween(glow, { BackgroundTransparency = if on then 0.86 else 1 }, Theme.TweenFast)
		UIKit.tween(scale, { Scale = if on then 1.04 else 1 }, Theme.TweenFast)
	end
	button.MouseEnter:Connect(function()
		hover(true)
		if UIKit.hoverSound then
			UIKit.hoverSound()
		end
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, { Scale = 0.95 }, 0.08)
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, { Scale = 1 }, 0.12, Enum.EasingStyle.Back)
	end)
	if onClick then
		button.Activated:Connect(function()
			if UIKit.clickSound then
				UIKit.clickSound()
			end
			onClick()
		end)
	end
	return button
end

-- Re-colour a button made by UIKit.button (keeps hover tweens consistent).
function UIKit.recolor(button: TextButton, color: Color3)
	button.BackgroundColor3 = color
end

export type Bar = {
	frame: Frame,
	fill: Frame,
	label: TextLabel,
	set: (value: number, text: string?) -> (),
}

function UIKit.bar(props: Props?, fillColor: Color3): Bar
	local frame = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, Size = UDim2.fromOffset(240, 18) })
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	UIKit.corner(UDim.new(1, 0)).Parent = frame
	UIKit.stroke(Theme.Stroke, 1.5, 0.3).Parent = frame
	local fill = UIKit.frame({ BackgroundColor3 = fillColor, Size = UDim2.fromScale(1, 1), Parent = frame })
	UIKit.corner(UDim.new(1, 0)).Parent = fill
	UIKit.gradient(ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), 90).Parent = fill
	local label = UIKit.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.FontBold,
		TextSize = 13,
		ZIndex = 3,
		Parent = frame,
	})
	UIKit.textStroke(1.5).Parent = label
	local current = 1
	local function set(value: number, text: string?)
		value = math.clamp(value, 0, 1)
		if math.abs(value - current) > 0.001 then
			current = value
			UIKit.tween(fill, { Size = UDim2.fromScale(value, 1) }, 0.2)
		end
		if text then
			label.Text = text
		end
	end
	return { frame = frame, fill = fill, label = label, set = set }
end

---------------------------------------------------------------- rarity styling
function UIKit.rarityColor(index: number): Color3
	local rarity = Rarities.list[index] or Rarities.list[1]
	return rarity.color
end

-- Applies a rarity's look to a GuiObject (animated gradient for Mythic, pulse for Abyssal,
-- rainbow for Secret). Returns the UIGradient if one was created.
function UIKit.rarityGradient(parent: GuiObject, index: number): UIGradient?
	local rarity = Rarities.list[index] or Rarities.list[1]
	if rarity.style == "gradient" then
		local g = UIKit.gradient(ColorSequence.new(rarity.color, rarity.accent), 0)
		g.Parent = parent
		g:SetAttribute("Animate", "spin")
		return g
	elseif rarity.style == "pulse" then
		local g = UIKit.gradient(ColorSequence.new({ ColorSequenceKeypoint.new(0, rarity.accent), ColorSequenceKeypoint.new(0.5, rarity.color), ColorSequenceKeypoint.new(1, rarity.accent) }), 0)
		g.Parent = parent
		g:SetAttribute("Animate", "pulse")
		return g
	elseif rarity.style == "rainbow" then
		local g = UIKit.gradient(Rarities.rainbow, 0)
		g.Parent = parent
		g:SetAttribute("Animate", "spin")
		return g
	end
	return nil
end

---------------------------------------------------------------- screens and scaling
local scales: { UIScale } = {}
local touchBoost = 1.15

function UIKit.scaleFactor(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local s = math.min(viewport.X / 1280, viewport.Y / 720)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		s *= touchBoost
	end
	return math.clamp(s, 0.5, 1.6)
end

local function refreshScales()
	local s = UIKit.scaleFactor()
	task.defer(function()
		UIKit.ScaleChanged:Fire(s)
	end)
	for i = #scales, 1, -1 do
		local scale = scales[i]
		if scale.Parent then
			local multiplier = scale:GetAttribute("Multiplier")
			scale.Scale = s * (if typeof(multiplier) == "number" then multiplier else 1)
		else
			table.remove(scales, i)
		end
	end
end

-- Adds a responsive UIScale to `inst` (multiplier tweaks the global factor for this element).
function UIKit.scaled(inst: GuiObject, multiplier: number?): UIScale
	local scale = UIKit.new("UIScale", { Parent = inst }) :: UIScale
	scale:SetAttribute("Multiplier", multiplier or 1)
	table.insert(scales, scale)
	scale.Scale = UIKit.scaleFactor() * (multiplier or 1)
	return scale
end

function UIKit.screen(name: string, displayOrder: number?): ScreenGui
	local gui = UIKit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	return gui
end

function UIKit.Init()
	local function hook()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
		end
		refreshScales()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
	UserInputService.LastInputTypeChanged:Connect(refreshScales)
end

return UIKit

--!strict
-- Settings: music / sound volume, graphics quality, camera shake and purchase suggestions (all
-- applied instantly and saved), a code redemption box, and a controls reference for keyboard,
-- gamepad and touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local Slider = require(script.Parent.Parent.UI.Slider)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)

local SettingsMenu = {}

local window: Window.Window
local sliders: { [string]: Slider.Slider } = {}
local toggles: { [string]: { button: TextButton, render: () -> () } } = {}
local codeBox: TextBox
local codeResult: TextLabel
local redeeming = false

local function row(parent: Instance, order: number, icon: string, title: string, desc: string): Frame
	local frame = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, Size = UDim2.new(1, -10, 0, 62), LayoutOrder = order, Parent = parent })
	UIKit.corner(Theme.CornerSmall).Parent = frame
	UIKit.label({ Text = icon, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 62), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	UIKit.label({ Text = title, Position = UDim2.fromOffset(58, 8), Size = UDim2.fromOffset(360, 24), Font = Theme.FontBold, TextSize = 17, Parent = frame })
	UIKit.label({ Text = desc, Position = UDim2.fromOffset(58, 32), Size = UDim2.fromOffset(420, 22), TextSize = 13, TextColor3 = Theme.TextMuted, Parent = frame })
	return frame
end

local function addSlider(parent: Instance, order: number, key: string, icon: string, title: string, desc: string)
	local frame = row(parent, order, icon, title, desc)
	local initial = if ClientState.data then (ClientState.data.Settings :: any)[key] else 0.7
	local percent = UIKit.label({ Text = "", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(56, 30), Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
	local slider = Slider.new(frame, UDim2.new(1, -330, 0.5, -15), 250, if typeof(initial) == "number" then initial else 0.7, function(value)
		percent.Text = string.format("%d%%", math.floor(value * 100 + 0.5))
		ClientState.setSetting(key, math.floor(value * 100 + 0.5) / 100)
	end, function()
		if key == "SFX" then
			AudioController.play("UIClick")
		end
	end)
	percent.Text = string.format("%d%%", math.floor(slider.get() * 100 + 0.5))
	sliders[key] = slider
end

local function addToggle(parent: Instance, order: number, key: string, icon: string, title: string, desc: string, labels: { string }, values: { any })
	local frame = row(parent, order, icon, title, desc)
	local button: TextButton
	local function current(): any
		return if ClientState.data then (ClientState.data.Settings :: any)[key] else values[1]
	end
	local function render()
		local value = current()
		local index = table.find(values, value) or 1
		button.Text = labels[index]
		button.BackgroundColor3 = if index == 1 then Theme.Good else Theme.PanelLight
	end
	button = UIKit.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(150, 40), TextSize = 16, Parent = frame }, function()
		local index = table.find(values, current()) or 1
		local nextValue = values[index % #values + 1]
		ClientState.setSetting(key, nextValue)
		render()
	end, Theme.Good)
	toggles[key] = { button = button, render = render }
	render()
end

local function buildSettings(page: Frame)
	local list = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 8).Parent = list
	addSlider(list, 1, "Music", "🎵", "Music", "Soundtrack volume for each zone and event.")
	addSlider(list, 2, "SFX", "🔊", "Sound effects", "Catches, sonar, alarms, ambience and menus.")
	addToggle(list, 3, "Graphics", "🖥️", "Graphics quality", "Low turns off particles, blur, extra lights and marine snow.", { "High", "Low" }, { "High", "Low" })
	addToggle(list, 4, "CameraShake", "📳", "Camera shake", "Shake on impacts, tremors and huge catches.", { "On", "Off" }, { true, false })
	addToggle(list, 5, "Offers", "🛒", "Shop suggestions", "Occasional, skippable reminders about helpful items (never mid-catch).", { "On", "Off" }, { true, false })
end

local function redeem()
	if redeeming then
		return
	end
	local text = codeBox.Text
	if #text == 0 then
		codeResult.Text = "Type a code first."
		codeResult.TextColor3 = Theme.Warn
		return
	end
	redeeming = true
	codeResult.Text = "Checking…"
	codeResult.TextColor3 = Theme.TextMuted
	local ok, response = pcall(function()
		return Net.func("RedeemCode"):InvokeServer(text)
	end)
	redeeming = false
	if ok and typeof(response) == "table" and typeof(response.message) == "string" then
		codeResult.Text = response.message
		codeResult.TextColor3 = if response.ok then Theme.Good else Theme.Bad
		if response.ok then
			codeBox.Text = ""
			AudioController.play("Purchase")
			EffectsController.flash(Theme.Good, 0.25, 0.5)
		else
			AudioController.play("UIError")
		end
	else
		codeResult.Text = "Couldn't reach the server. Try again."
		codeResult.TextColor3 = Theme.Bad
	end
end

local function buildCodes(page: Frame)
	UIKit.label({ Text = "🎟️ Redeem a code", Font = Theme.FontDisplay, TextSize = 26, TextColor3 = Theme.Accent, Size = UDim2.new(1, 0, 0, 34), Parent = page })
	UIKit.label({
		Text = "Codes are shared on our group and social pages for updates and milestones. Each code works once per player.",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		Parent = page,
	})
	codeBox = UIKit.new("TextBox", {
		PlaceholderText = "Enter code",
		Text = "",
		ClearTextOnFocus = false,
		Font = Theme.FontBold,
		TextSize = 22,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.TextMuted,
		BackgroundColor3 = Theme.PanelDark,
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, -200, 0, 50),
		Parent = page,
	}) :: TextBox
	UIKit.corner(Theme.CornerSmall).Parent = codeBox
	UIKit.stroke(Theme.Stroke, 2, 0.1).Parent = codeBox
	codeBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)
	UIKit.button({ Text = "REDEEM", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 96), Size = UDim2.fromOffset(186, 50), Font = Theme.FontDisplay, TextSize = 22, Parent = page }, function()
		task.spawn(redeem)
	end, Theme.Good)
	codeResult = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 156), Size = UDim2.new(1, 0, 0, 60), TextSize = 17, Font = Theme.FontBold, TextYAlignment = Enum.TextYAlignment.Top, Parent = page })
end

local CONTROLS: { { string } } = {
	{ "", "⌨️ Keyboard & mouse", "🎮 Gamepad", "📱 Touch" },
	{ "Steer", "WASD + mouse", "Left stick + right stick", "Joystick + drag" },
	{ "Rise / sink", "Space / Shift", "R2 / L2", "▲ UP / ▼ DOWN" },
	{ "Catch / salvage", "Click / hold click", "A / hold A", "ACTION / hold" },
	{ "Sonar ping", "F", "Y", "📡 SONAR" },
	{ "Silent running", "Ctrl or C", "L3", "🤫 SLOW" },
	{ "Emergency surface", "Hold R", "Hold X", "Hold 🚨" },
	{ "Free the cursor", "Alt", "—", "—" },
	{ "Menus", "M", "Select / View", "Side bar" },
	{ "Dock interact", "E", "X", "Tap the prompt" },
}

local function buildControls(page: Frame)
	local columns = { 0, 0.22, 0.46, 0.73 }
	local widths = { 0.22, 0.24, 0.27, 0.27 }
	for rowIndex, entry in CONTROLS do
		local y = (rowIndex - 1) * 40
		local background = UIKit.frame({ BackgroundColor3 = if rowIndex == 1 then Theme.PanelLight else Theme.PanelDark, BackgroundTransparency = if rowIndex % 2 == 0 then 0.2 else 0.45, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 36), Parent = page })
		UIKit.corner(UDim.new(0, 6)).Parent = background
		for column, text in entry do
			UIKit.label({
				Text = text,
				Position = UDim2.new(columns[column], 10, 0, 0),
				Size = UDim2.new(widths[column], -12, 1, 0),
				TextSize = if rowIndex == 1 then 15 else 14,
				Font = if rowIndex == 1 or column == 1 then Theme.FontBold else Theme.Font,
				TextColor3 = if column == 1 then Theme.Accent else Theme.Text,
				Parent = background,
			})
		end
	end
end

local function refresh()
	local data = ClientState.data
	if not data then
		return
	end
	for key, slider in sliders do
		local value = (data.Settings :: any)[key]
		if typeof(value) == "number" then
			slider.set(value)
		end
	end
	for _, toggle in toggles do
		toggle.render()
	end
end

function SettingsMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Settings", "⚙️", { "Settings", "Codes", "Controls" }, close)
	buildSettings(window.pages.Settings)
	buildCodes(window.pages.Codes)
	buildControls(window.pages.Controls)
	return window
end

function SettingsMenu.onOpen()
	refresh()
	codeResult.Text = ""
end

return SettingsMenu

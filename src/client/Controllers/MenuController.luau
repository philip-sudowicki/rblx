--!strict
-- Menus: the dock side bar, one window open at a time with smooth tweens and a background blur,
-- gamepad selection + B to close, and dock prompts routed to the right menu/tab.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Signal = require(Shared.Modules.Signal)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local PromptRouter = require(script.Parent.PromptRouter)
local AudioController = require(script.Parent.AudioController)
local LaunchPanel = require(script.Parent.Parent.Menus.LaunchPanel)

export type MenuModule = {
	build: (parent: Instance, close: () -> ()) -> Window.Window,
	onOpen: ((tab: string?, context: any?) -> ())?,
	onClose: (() -> ())?,
	badge: (() -> boolean)?, -- true shows a red dot on the menu bar (something to claim)
}

type Entry = { name: string, icon: string, label: string, module: MenuModule, window: Window.Window?, order: number, button: TextButton?, dot: Frame? }

local MenuController = {}

MenuController.current = nil :: string?
MenuController.Opened = Signal.new() :: Signal.Signal<string>
MenuController.Closed = Signal.new() :: Signal.Signal<string>

local gui: ScreenGui
local dim: Frame
local bar: Frame
local blur: BlurEffect
local entries: { [string]: Entry } = {}
local ordered: { Entry } = {}

local function windowFor(entry: Entry): Window.Window
	local window = entry.window
	if window then
		return window
	end
	local built = entry.module.build(gui, function()
		MenuController.close()
	end)
	entry.window = built
	return built
end

function MenuController.register(name: string, icon: string, label: string, module: MenuModule, order: number)
	local entry: Entry = { name = name, icon = icon, label = label, module = module, window = nil, order = order, button = nil, dot = nil }
	entries[name] = entry
	table.insert(ordered, entry)
	table.sort(ordered, function(a, b)
		return a.order < b.order
	end)
end

function MenuController.close()
	local name = MenuController.current
	if not name then
		return
	end
	local entry = entries[name]
	MenuController.current = nil
	ContextActionService:UnbindAction("DH_MenuBack")
	local window = entry.window
	if window then
		local root = window.root
		UIKit.tween(root, { Position = UDim2.fromScale(0.5, 0.56) }, 0.18)
		UIKit.tween(dim, { BackgroundTransparency = 1 }, 0.18)
		task.delay(0.18, function()
			if MenuController.current ~= name then
				root.Visible = false
				if MenuController.current == nil then
					dim.Visible = false
				end
			end
		end)
	end
	UIKit.tween(blur, { Size = 0 }, 0.2)
	if entry.module.onClose then
		entry.module.onClose()
	end
	InputController.setMenuOpen(false)
	GuiService.SelectedObject = nil
	AudioController.play("UIClose")
	MenuController.Closed:Fire(name)
end

function MenuController.open(name: string, tab: string?, context: any?)
	local entry = entries[name]
	if not entry then
		return
	end
	if MenuController.current and MenuController.current ~= name then
		local previous = entries[MenuController.current]
		if previous and previous.window then
			previous.window.root.Visible = false
		end
		if previous and previous.module.onClose then
			previous.module.onClose()
		end
	end
	local window = windowFor(entry)
	MenuController.current = name
	if tab and window.pages[tab] then
		window.setTab(tab)
	end
	if entry.module.onOpen then
		entry.module.onOpen(tab, context)
	end
	dim.Visible = true
	dim.BackgroundTransparency = 1
	UIKit.tween(dim, { BackgroundTransparency = 0.55 }, 0.2)
	window.root.Visible = true
	window.root.Position = UDim2.fromScale(0.5, 0.58)
	UIKit.tween(window.root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.28, Enum.EasingStyle.Back)
	local graphicsLow = ClientState.data and ClientState.data.Settings.Graphics == "Low"
	UIKit.tween(blur, { Size = if graphicsLow then 0 else 14 }, 0.25)
	InputController.setMenuOpen(true)
	ContextActionService:BindActionAtPriority("DH_MenuBack", function(_, state)
		if state == Enum.UserInputState.Begin then
			MenuController.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 70, Enum.KeyCode.ButtonB)
	if InputController.mode == "Gamepad" then
		local first = next(window.tabButtons)
		GuiService.SelectedObject = if first then window.tabButtons[first] else window.closeButton
	end
	AudioController.play("UIOpen")
	MenuController.Opened:Fire(name)
end

function MenuController.toggle(name: string, tab: string?)
	if MenuController.current == name then
		MenuController.close()
	else
		MenuController.open(name, tab)
	end
end

local function refreshBar()
	bar.Visible = not SubController.isDiving() and ClientState.ready and not LaunchPanel.isOpen
end

local badgeQueued = false
local function refreshBadges()
	if badgeQueued then
		return
	end
	badgeQueued = true
	task.defer(function()
		badgeQueued = false
		if not ClientState.ready then
			return
		end
		for _, entry in ordered do
			local dot = entry.dot
			local badge = entry.module.badge
			if dot and badge then
				local ok, show = pcall(badge)
				dot.Visible = ok and show == true
			end
		end
	end)
end

local function buildBar()
	-- A hotbar centred along the bottom of the screen (the top corners belong to Roblox's chat
	-- and player list, and the bottom corners to the touch controls).
	bar = UIKit.frame({
		Name = "MenuBar",
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.35,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(#ordered * 70 + 12, 66),
		Visible = false,
		Parent = gui,
	})
	UIKit.corner(UDim.new(0, 16)).Parent = bar
	UIKit.scaled(bar)
	UIKit.padding(4, 6, 4, 6).Parent = bar
	UIKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = bar
	for index, entry in ordered do
		local button = UIKit.button({
			Size = UDim2.fromOffset(64, 58),
			LayoutOrder = index,
			Text = "",
			BackgroundTransparency = 1,
			Parent = bar,
		}, function()
			MenuController.toggle(entry.name)
		end, Theme.Panel)
		UIKit.label({ Text = entry.icon, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 2), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Parent = button })
		UIKit.label({ Text = entry.label, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 38), TextSize = 12, Font = Theme.FontBold, TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, Parent = button })
		local dot = UIKit.frame({ BackgroundColor3 = Theme.Bad, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(12, 12), Visible = false, ZIndex = 5, Parent = button })
		UIKit.corner(UDim.new(1, 0)).Parent = dot
		UIKit.stroke(Color3.new(1, 1, 1), 2, 0).Parent = dot
		entry.button = button
		entry.dot = dot
	end
end

function MenuController.Init()
	gui = UIKit.screen("DeepHaulMenus", 15)
	dim = UIKit.frame({ BackgroundColor3 = Color3.fromRGB(2, 8, 16), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	local dimButton = UIKit.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), Parent = dim }) :: TextButton
	dimButton.Activated:Connect(function()
		MenuController.close()
	end)
	blur = Instance.new("BlurEffect")
	blur.Name = "DH_MenuBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

function MenuController.Start()
	local Menus = script.Parent.Parent.Menus
	local specs: { { name: string, icon: string, label: string } } = {
		{ name = "Inventory", icon = "🎒", label = "Items" },
		{ name = "Index", icon = "📖", label = "Index" },
		{ name = "Upgrades", icon = "🛠️", label = "Upgrade" },
		{ name = "Shop", icon = "🛒", label = "Shop" },
		{ name = "Quests", icon = "📜", label = "Quests" },
	}
	for order, spec in specs do
		local moduleScript = Menus:FindFirstChild(spec.name .. "Menu")
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local module = (require :: any)(moduleScript)
			MenuController.register(spec.name, spec.icon, spec.label, module, order)
		end
	end
	buildBar()
	refreshBar()
	refreshBadges()
	ClientState.Ready:Connect(function()
		refreshBar()
		refreshBadges()
	end)
	ClientState.Changed:Connect(function(key)
		if key == "*" then
			refreshBar()
		end
		refreshBadges()
	end)
	ClientState.EventsChanged:Connect(refreshBadges)
	SubController.Started:Connect(function()
		MenuController.close()
		refreshBar()
	end)
	SubController.Ended:Connect(refreshBar)
	LaunchPanel.Opened:Connect(function()
		MenuController.close()
		refreshBar()
	end)
	LaunchPanel.Closed:Connect(refreshBar)
	InputController.MenuToggle:Connect(function()
		if MenuController.current then
			MenuController.close()
		elseif InputController.mode == "Gamepad" and bar.Visible then
			local first = ordered[1]
			if first and first.button then
				GuiService.SelectedObject = first.button
			end
		elseif not SubController.isDiving() then
			MenuController.open("Inventory")
		end
	end)
	PromptRouter.on("Sell", function(prompt)
		local anchor = prompt.Parent
		MenuController.open("Inventory", "Fish", { sellAt = if anchor and anchor:IsA("BasePart") then anchor.Position else nil })
	end)
	PromptRouter.on("Upgrades", function()
		MenuController.open("Upgrades", "Upgrades")
	end)
	PromptRouter.on("Shop", function()
		MenuController.open("Shop", "Passes")
	end)
	PromptRouter.on("Quests", function()
		MenuController.open("Quests", "Daily")
	end)
	PromptRouter.on("Daily", function()
		MenuController.open("Quests", "Login")
	end)
end

return MenuController

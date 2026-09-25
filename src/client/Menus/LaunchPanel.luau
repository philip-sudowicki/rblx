--!strict
-- Pre-dive panel at the Launch Bay: sub stats at a glance, optional Cargo Insurance toggle
-- (if you own any), a storage warning, and one big DIVE button (E / A / tap again to launch).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MarketController = require(script.Parent.Parent.Controllers.MarketController)
local Products = require(Shared.Config.Products)

local LaunchPanel = {}

LaunchPanel.Opened = Signal.new() :: Signal.Signal<()>
LaunchPanel.Closed = Signal.new() :: Signal.Signal<()>
LaunchPanel.isOpen = false

local gui: ScreenGui
local window: Frame
local statsLabel: TextLabel
local insureButton: TextButton
local warningLabel: TextLabel
local diveButton: TextButton
local insure = false

local function refresh()
	local data = ClientState.data
	if not data then
		return
	end
	local stats = ClientState.stats()
	statsLabel.Text = string.format(
		"🛡️ Max depth <b>%s</b>    💨 Oxygen <b>%ds</b>\n⚡ Speed <b>%d</b>    📦 Cargo <b>%d</b>    🧲 Claw <b>T%d</b>",
		Format.meters(stats.maxDepth),
		math.floor(stats.oxygen),
		math.floor(stats.speed),
		stats.cargo,
		stats.clawTier
	)
	local owned = data.Consumables.CargoInsurance or 0
	-- no insurance left: deep divers (who have something to lose) see an optional way to get one
	local offer = owned == 0
		and data.Settings.Offers
		and stats.maxDepth >= Products.offers.insuranceMinDepth
		and MarketController.available("CargoInsurance")
	insureButton.Visible = owned > 0 or offer
	if owned > 0 then
		insureButton.Text = if insure then string.format("🛡️ Insured (%d left)", owned) else string.format("🛡️ Use Cargo Insurance (%d)", owned)
		insureButton.BackgroundColor3 = if insure then Theme.Good else Theme.PanelLight
	else
		insure = false
		insureButton.Text = "🛡️ Get Cargo Insurance · " .. MarketController.priceText("CargoInsurance")
		insureButton.BackgroundColor3 = Theme.PanelLight
	end
	local storage = ClientState.storageCount()
	if storage >= Game.Economy.StorageCap then
		warningLabel.Text = string.format("Storage full (%d/%d). Sell at the Fish Market first!", storage, Game.Economy.StorageCap)
		warningLabel.Visible = true
	elseif storage >= Game.Economy.StorageCap * 0.85 then
		warningLabel.Text = string.format("Storage almost full (%d/%d)", storage, Game.Economy.StorageCap)
		warningLabel.Visible = true
	else
		warningLabel.Visible = false
	end
end

function LaunchPanel.close()
	if not LaunchPanel.isOpen then
		return
	end
	LaunchPanel.isOpen = false
	ContextActionService:UnbindAction("DH_LaunchConfirm")
	UIKit.tween(window, { Position = UDim2.new(0.5, 0, 1.4, 0) }, 0.25)
	task.delay(0.25, function()
		if not LaunchPanel.isOpen then
			gui.Enabled = false
		end
	end)
	InputController.setMenuOpen(false)
	LaunchPanel.Closed:Fire()
end

local function launch()
	Net.event("Dive"):FireServer({ insure = insure })
	insure = false
	LaunchPanel.close()
end

function LaunchPanel.open()
	if LaunchPanel.isOpen then
		launch()
		return
	end
	LaunchPanel.isOpen = true
	insure = false
	refresh()
	gui.Enabled = true
	window.Position = UDim2.new(0.5, 0, 1.4, 0)
	UIKit.tween(window, { Position = UDim2.new(0.5, 0, 1, -24) }, 0.35, Enum.EasingStyle.Back)
	InputController.setMenuOpen(true)
	ContextActionService:BindActionAtPriority("DH_LaunchConfirm", function(_, state)
		if state == Enum.UserInputState.Begin then
			launch()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 60, Enum.KeyCode.ButtonA, Enum.KeyCode.Return)
	if InputController.mode == "Gamepad" then
		GuiService.SelectedObject = diveButton
	end
	LaunchPanel.Opened:Fire()
end

function LaunchPanel.Init()
	gui = UIKit.screen("DeepHaulLaunch", 20)
	gui.Enabled = false
	window = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1.4, 0),
		Size = UDim2.fromOffset(520, 250),
		Parent = gui,
	})
	UIKit.scaled(window)
	UIKit.label({
		Text = "LAUNCH BAY",
		Font = Theme.FontDisplay,
		TextSize = 30,
		TextColor3 = Theme.Accent,
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -40, 0, 34),
		Parent = window,
	})
	statsLabel = UIKit.label({
		Text = "",
		TextSize = 17,
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -40, 0, 50),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = window,
	})
	insureButton = UIKit.button({
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.fromOffset(300, 38),
		TextSize = 16,
		Parent = window,
	}, function()
		local data = ClientState.data
		if data and (data.Consumables.CargoInsurance or 0) == 0 then
			MarketController.prompt("CargoInsurance")
			return
		end
		insure = not insure
		refresh()
	end, Theme.PanelLight)
	warningLabel = UIKit.label({
		Text = "",
		TextColor3 = Theme.Warn,
		TextSize = 15,
		Font = Theme.FontBold,
		Position = UDim2.fromOffset(20, 150),
		Size = UDim2.new(1, -40, 0, 22),
		Visible = false,
		Parent = window,
	})
	diveButton = UIKit.button({
		Text = "DIVE!",
		Font = Theme.FontDisplay,
		TextSize = 32,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -18),
		Size = UDim2.fromOffset(220, 62),
		Parent = window,
	}, launch)
	UIKit.button({
		Text = "Not yet",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.fromOffset(130, 44),
		TextSize = 16,
		Parent = window,
	}, LaunchPanel.close, Theme.PanelLight)
end

function LaunchPanel.Start()
	ClientState.Changed:Connect(function()
		if LaunchPanel.isOpen then
			refresh()
		end
	end)
end

return LaunchPanel

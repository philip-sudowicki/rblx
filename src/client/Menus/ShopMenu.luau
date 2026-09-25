--!strict
-- Shop: game passes, dive items and boosts, and coin packs, with live Robux prices. Nothing
-- here sells fish or treasure; every item can also be earned by playing. The one random item
-- (Skip Event Timer) lists its exact odds and is hidden where paid random items are restricted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Products = require(Shared.Config.Products)
local Events = require(Shared.Config.Events)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local MarketController = require(script.Parent.Parent.Controllers.MarketController)

local ShopMenu = {}

local CARD = Vector2.new(264, 196)

local window: Window.Window
local isOpen = false
local grids: { [string]: ScrollingFrame } = {}

local function clearGrid(grid: ScrollingFrame)
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function card(grid: ScrollingFrame, order: number, icon: string, name: string, desc: string, buttonText: string, buttonColor: Color3, onBuy: (() -> ())?, note: string?)
	local frame = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.15, Size = UDim2.fromOffset(CARD.X, CARD.Y), LayoutOrder = order, Parent = grid })
	UIKit.corner(Theme.CornerSmall).Parent = frame
	UIKit.stroke(Theme.Stroke, 1.5, 0.1).Parent = frame
	UIKit.label({ Text = icon, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(44, 44), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Parent = frame })
	UIKit.label({ Text = name, Position = UDim2.fromOffset(60, 10), Size = UDim2.new(1, -70, 0, 40), Font = Theme.FontBold, TextSize = 18, Parent = frame })
	UIKit.label({ Text = desc, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 70), TextSize = 13, TextColor3 = Theme.TextMuted, TextYAlignment = Enum.TextYAlignment.Top, Parent = frame })
	if note then
		UIKit.label({ Text = note, Position = UDim2.fromOffset(12, 124), Size = UDim2.new(1, -24, 0, 18), TextSize = 12, Font = Theme.FontBold, TextColor3 = Theme.Accent, Parent = frame })
	end
	UIKit.button({ Text = buttonText, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 42), TextSize = 18, Font = Theme.FontDisplay, Parent = frame }, onBuy, buttonColor)
end

local function buyButton(key: string): (string, Color3, (() -> ())?)
	if MarketController.ownsPass(key) then
		return "Owned ✓", Theme.PanelLight, nil
	end
	if not MarketController.available(key) then
		return "Coming soon", Theme.PanelLight, nil
	end
	return MarketController.priceText(key), Theme.Good, function()
		MarketController.prompt(key)
	end
end

local function refreshPasses()
	local grid = grids.Passes
	clearGrid(grid)
	for _, pass in Products.passes do
		local text, color, onBuy = buyButton(pass.key)
		card(grid, pass.order, pass.icon, pass.name, pass.desc, text, color, onBuy)
	end
end

local function skipEventOdds(): string
	local count = #Events.list
	return string.format("Odds: each of the %d events 1 in %d (%s)", count, count, Format.percent(1 / count, 1))
end

local function refreshItems()
	local grid = grids.Items
	clearGrid(grid)
	local data = ClientState.data
	for _, product in Products.products do
		if not product.coins then
			if product.randomOutcome and MarketController.randomRestricted() then
				continue
			end
			local text, color, onBuy = buyButton(product.key)
			local note: string? = nil
			if data and data.Consumables[product.key] then
				note = string.format("You have %d", data.Consumables[product.key])
			end
			if product.key == "ServerLuck" then
				local untilTime = ReplicatedStorage:GetAttribute("ServerLuckUntil")
				local remaining = if typeof(untilTime) == "number" then untilTime - ClientState.serverTime() else 0
				if remaining > 0 then
					note = "Active: " .. Format.clock(remaining) .. " left (buying adds time)"
				end
			elseif product.key == "SkipEvent" then
				local odds = skipEventOdds()
				local queued = ReplicatedStorage:GetAttribute("LocalEventQueued")
				note = if typeof(queued) == "number" and queued > 0 then string.format("%d queued · %s", queued, odds) else odds
			end
			card(grid, product.order, product.icon, product.name, product.desc, text, color, onBuy, note :: any)
		end
	end
end

local function refreshCoins()
	local grid = grids.Coins
	clearGrid(grid)
	local data = ClientState.data
	local zone = if data then DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters) else 1
	for _, product in Products.products do
		local base = product.coins
		if base then
			local coins = base * Stats.coinScale(Products.coinScale, zone)
			local text, color, onBuy = buyButton(product.key)
			card(grid, product.order, product.icon, string.format("%s\n💰 %s", product.name, Format.short(coins)), product.desc, text, color, onBuy)
		end
	end
end

local function refresh()
	if not isOpen then
		return
	end
	if window.tab == "Passes" then
		refreshPasses()
	elseif window.tab == "Items" then
		refreshItems()
	else
		refreshCoins()
	end
end

local function makeGrid(page: Frame): ScrollingFrame
	local grid = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.grid(UDim2.fromOffset(CARD.X, CARD.Y), UDim2.fromOffset(12, 12)).Parent = grid
	UIKit.label({
		Text = "Everything in DEEP HAUL can be earned by playing. Fish and treasure are never sold.",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 13,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = page,
	})
	return grid
end

function ShopMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Shop", "🛒", { "Passes", "Items", "Coins" }, close)
	grids.Passes = makeGrid(window.pages.Passes)
	grids.Items = makeGrid(window.pages.Items)
	grids.Coins = makeGrid(window.pages.Coins)
	window.TabChanged:Connect(refresh)
	MarketController.PricesUpdated:Connect(refresh)
	ClientState.Changed:Connect(function(key)
		if key == "Consumables" or key == "Stats" or key == "*" then
			refresh()
		end
	end)
	ClientState.player.AttributeChanged:Connect(function(attribute: string)
		if string.sub(attribute, 1, 5) == "Pass_" or attribute == "PaidRandomRestricted" then
			refresh()
		end
	end)
	return window
end

function ShopMenu.onOpen()
	isOpen = true
	refresh()
end

function ShopMenu.onClose()
	isOpen = false
end

return ShopMenu

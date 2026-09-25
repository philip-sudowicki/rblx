--!strict
-- Occasional, skippable purchase suggestions. Rules (Config/Products.offers): never in the first
-- minutes of a session, at most one offer per cooldown, never during a catch or salvage, never
-- if the player turned "Shop suggestions" off, and only for items that would actually help right
-- now (low oxygen or hull mid-dive with none in stock). A small card that slides away by itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Products = require(Shared.Config.Products)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)
local MarketController = require(script.Parent.MarketController)
local MinigameController = require(script.Parent.MinigameController)
local SalvageController = require(script.Parent.SalvageController)
local TutorialController = require(script.Parent.TutorialController)

local OfferController = {}

local SHOW_SECONDS = 8

local card: Frame
local title: TextLabel
local buyButton: TextButton
local sessionStart = os.clock()
local lastOfferAt = -math.huge
local showing = false
local currentKey = ""

local function hide()
	if not showing then
		return
	end
	showing = false
	UIKit.tween(card, { Position = UDim2.new(0.5, 0, 0, -120) }, 0.25)
end

local function show(key: string, text: string)
	currentKey = key
	showing = true
	lastOfferAt = os.clock()
	title.Text = text
	buyButton.Text = MarketController.priceText(key)
	card.Position = UDim2.new(0.5, 0, 0, -120)
	UIKit.tween(card, { Position = UDim2.new(0.5, 0, 0, 176) }, 0.35, Enum.EasingStyle.Back)
	task.delay(SHOW_SECONDS, function()
		if currentKey == key then
			hide()
		end
	end)
end

local function allowed(): boolean
	local data = ClientState.data
	if not data or not data.Settings.Offers or showing then
		return false
	end
	if os.clock() - sessionStart < Products.offers.firstOfferAfterSeconds then
		return false
	end
	if os.clock() - lastOfferAt < Products.offers.cooldownSeconds then
		return false
	end
	return not MinigameController.active and not SalvageController.active and not TutorialController.active
end

local function check()
	if not SubController.isDiving() or not allowed() then
		return
	end
	local data = ClientState.data
	local player = ClientState.player
	local oxygen = player:GetAttribute("DiveO2")
	local hull = player:GetAttribute("DiveHull")
	local maxOxygen = ClientState.stats().oxygen
	if typeof(oxygen) == "number" and maxOxygen > 0 and oxygen / maxOxygen < 0.2 and (data.Consumables.OxygenRefill or 0) == 0 and MarketController.available("OxygenRefill") then
		show("OxygenRefill", "🫧 Oxygen low! Refill it instantly?")
	elseif typeof(hull) == "number" and hull < 25 and (data.Consumables.HullRepair or 0) == 0 and MarketController.available("HullRepair") then
		show("HullRepair", "🔧 Hull cracking! Repair it instantly?")
	end
end

function OfferController.Init()
	local gui = UIKit.screen("DeepHaulOffers", 14)
	card = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -120), Size = UDim2.fromOffset(440, 58), Parent = gui })
	UIKit.scaled(card)
	title = UIKit.label({ Text = "", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -210, 1, 0), Font = Theme.FontBold, TextSize = 16, Parent = card })
	buyButton = UIKit.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.fromOffset(130, 40), TextSize = 17, Parent = card }, function()
		MarketController.prompt(currentKey)
		hide()
	end, Theme.Good)
	UIKit.button({ Text = "✕", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(36, 36), TextSize = 16, Parent = card }, hide, Theme.PanelLight)
end

function OfferController.Start()
	SubController.Ended:Connect(hide)
	task.spawn(function()
		while true do
			task.wait(1)
			check()
		end
	end)
end

return OfferController

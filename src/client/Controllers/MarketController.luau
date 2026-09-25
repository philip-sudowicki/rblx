--!strict
-- Store helper: live Robux prices (GetProductInfo, cached), availability (configured id, and the
-- PolicyService flag for the one random product) and purchase prompts, which are requested from
-- the server so it can apply the same rules.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local MarketController = {}

MarketController.PricesUpdated = Signal.new() :: Signal.Signal<()>

local prices: { [string]: number } = {}

function MarketController.price(key: string): number?
	return prices[key]
end

function MarketController.priceText(key: string): string
	local price = prices[key]
	return if price then "R$ " .. tostring(price) else "…"
end

function MarketController.randomRestricted(): boolean
	-- restricted until the server's PolicyService check says otherwise
	return Players.LocalPlayer:GetAttribute("PaidRandomRestricted") ~= false
end

function MarketController.available(key: string): boolean
	local product = Products.productsByKey[key]
	if product then
		return product.id ~= 0 and not (product.randomOutcome and MarketController.randomRestricted())
	end
	local pass = Products.passesByKey[key]
	return pass ~= nil and pass.id ~= 0
end

function MarketController.ownsPass(key: string): boolean
	return ClientState.hasPass(key)
end

function MarketController.prompt(key: string)
	if not MarketController.available(key) or MarketController.ownsPass(key) then
		AudioController.play("UIError")
		return
	end
	Net.event("PromptPurchase"):FireServer(key)
end

local function fetchPrices()
	for _, pass in Products.passes do
		if pass.id ~= 0 and not prices[pass.key] then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(pass.id, Enum.InfoType.GamePass)
			end)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				prices[pass.key] = info.PriceInRobux
			end
		end
	end
	for _, product in Products.products do
		if product.id ~= 0 and not prices[product.key] then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
			end)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				prices[product.key] = info.PriceInRobux
			end
		end
	end
	MarketController.PricesUpdated:Fire()
end

function MarketController.Start()
	task.spawn(fetchPrices)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		if userId == Players.LocalPlayer.UserId and purchased then
			AudioController.play("Purchase")
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if player == Players.LocalPlayer and purchased then
			AudioController.play("Purchase")
		end
	end)
end

return MarketController

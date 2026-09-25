--!strict
-- Developer products and purchase prompts.
--
-- ProcessReceipt is idempotent: each PurchaseId is recorded in the player's profile (a rolling
-- cache) before the product is granted, and the receipt is only confirmed to Roblox once a save
-- containing that PurchaseId has completed. A receipt that arrives twice is never granted twice;
-- a server crash before the save means Roblox retries and the player still gets the product.
--
-- PolicyService: players for whom paid random items are restricted never see or get prompted for
-- the one random product (Skip Event Timer).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local SubService = require(script.Parent.SubService)
local BoostService = require(script.Parent.BoostService)
local EventService = require(script.Parent.EventService)

local MonetizationService = {}

local SAVE_WAIT_TIMEOUT = 60

-- Grants a product's effect. Runs exactly once per PurchaseId.
local function grant(player: Player, product: Products.DevProduct)
	local key = product.key
	if key == "OxygenRefill" then
		if not SubService.refillOxygen(player) then
			DataService.addConsumable(player, key, 1)
			Remotes.notify(player, "Oxygen Refill saved for your next dive (use it from the dive HUD).", "good", product.icon)
			return
		end
	elseif key == "HullRepair" then
		if not SubService.repairHull(player) then
			DataService.addConsumable(player, key, 1)
			Remotes.notify(player, "Hull Repair saved for your next dive (use it from the dive HUD).", "good", product.icon)
			return
		end
	elseif key == "CargoInsurance" then
		if not SubService.insureCurrent(player) then
			DataService.addConsumable(player, key, 1)
			Remotes.notify(player, "Cargo Insurance saved. Toggle it on in the Launch Bay before a dive.", "good", product.icon)
			return
		end
	elseif key == "ServerLuck" then
		BoostService.addServerLuck(Products.serverLuck.seconds, player.DisplayName)
	elseif key == "SkipEvent" then
		EventService.purchaseLocal(player.DisplayName)
	elseif product.coins then
		local data = DataService.get(player)
		local zone = if data then DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters) else 1
		local coins = product.coins * Stats.coinScale(Products.coinScale, zone)
		DataService.addCoins(player, coins, "Purchase")
		Remotes.fire(player, "Effect", { kind = "Coins", coins = coins })
		Remotes.notify(player, string.format("+%s coins. Thanks for supporting DEEP HAUL!", Format.short(coins)), "good", product.icon)
		return
	end
	Remotes.notify(player, string.format("%s activated. Thanks for supporting DEEP HAUL!", product.name), "good", product.icon)
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = Products.productsById[receipt.ProductId]
	if not player or not product then
		-- the player left (Roblox retries when they rejoin) or the product isn't configured
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player, 30)
	local profile = DataService.profile(player)
	if not data or not profile or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if not DataService.hasPurchase(player, purchaseId) then
		DataService.recordPurchase(player, purchaseId)
		local ok, err = pcall(grant :: (...any) -> ...any, player, product)
		if not ok then
			warn(string.format("[DeepHaul] granting %s to %s failed: %s", product.key, player.Name, tostring(err)))
		end
	end
	-- confirm only once a save containing this purchase id has landed
	local function saved(): boolean
		local last = profile.LastSavedData
		return typeof(last) == "table" and typeof(last.Purchases) == "table" and table.find(last.Purchases, purchaseId) ~= nil
	end
	if saved() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local done = false
	local connection = profile.OnAfterSave:Connect(function()
		if saved() then
			done = true
		end
	end)
	profile:Save()
	local deadline = os.clock() + SAVE_WAIT_TIMEOUT
	while not done and profile:IsActive() and os.clock() < deadline do
		task.wait(0.1)
	end
	connection:Disconnect()
	return if done or saved() then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function checkPolicy(player: Player)
	local state = PlayerState.get(player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- if the check fails we stay restricted (the safe default)
	local restricted = not ok or typeof(info) ~= "table" or info.ArePaidRandomItemsRestricted ~= false
	if state then
		state.paidRandomRestricted = restricted
	end
	player:SetAttribute("PaidRandomRestricted", restricted)
end

function MonetizationService.canPrompt(player: Player, key: string): boolean
	local product = Products.productsByKey[key]
	if product then
		if product.id == 0 then
			return false
		end
		local state = PlayerState.get(player)
		if product.randomOutcome and (not state or state.paidRandomRestricted) then
			return false
		end
		return true
	end
	local pass = Products.passesByKey[key]
	return pass ~= nil and pass.id ~= 0
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	Players.PlayerAdded:Connect(checkPolicy)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPolicy, player)
	end
	Remotes.on("PromptPurchase", 1, 3, function(player, key)
		if typeof(key) ~= "string" or #key > 32 or not MonetizationService.canPrompt(player, key) then
			return
		end
		local product = Products.productsByKey[key]
		if product then
			MarketplaceService:PromptProductPurchase(player, product.id)
			return
		end
		local pass = Products.passesByKey[key]
		local state = PlayerState.get(player)
		if pass and state and not state.passes[key] then
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end
	end)
end

return MonetizationService

--!strict
-- Buying submarine upgrades (at the dock, never mid-dive).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local Validate = require(script.Parent.Validate)

local UpgradeService = {}

function UpgradeService.buy(player: Player, upgradeId: string): boolean
	local data = DataService.get(player)
	local state = PlayerState.get(player)
	local upgrade = Upgrades.byId[upgradeId]
	if not data or not state or not upgrade then
		return false
	end
	if state.dive then
		Remotes.notify(player, "Upgrades are installed at the dock. Surface first!", "warn", "🛠️")
		return false
	end
	local level = Stats.level(data.Upgrades, upgradeId)
	if level >= #upgrade.values then
		return false
	end
	local cost = Stats.upgradeCost(upgradeId, level + 1)
	if not DataService.spendCoins(player, cost) then
		Remotes.notify(player, string.format("You need %s more coins.", Format.short(cost - data.Coins)), "warn", "🪙")
		return false
	end
	data.Upgrades[upgradeId] = level + 1
	DataService.replicate(player, "Upgrades")
	ServerSignals.UpgradeBought:Fire(player, upgradeId, level + 1)
	Remotes.fire(player, "Effect", { kind = "Upgrade", id = upgradeId, level = level + 1 })
	return true
end

function UpgradeService.Start()
	Remotes.on("BuyUpgrade", 5, 8, function(player, upgradeId)
		if Validate.oneOf(upgradeId, Upgrades.byId) then
			UpgradeService.buy(player, upgradeId)
		end
	end)
end

return UpgradeService

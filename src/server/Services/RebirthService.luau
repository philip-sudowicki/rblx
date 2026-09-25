--!strict
-- Resurface (rebirth): reset coins and upgrades for a permanent sell multiplier, rebirth
-- tokens, access to The Rift and a nametag badge. Also the token perk shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rebirth = require(Shared.Config.Rebirth)
local Upgrades = require(Shared.Config.Upgrades)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local AnnounceService = require(script.Parent.AnnounceService)
local Validate = require(script.Parent.Validate)

local RebirthService = {}

function RebirthService.canRebirth(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if not data then
		return false, "Not loaded"
	end
	if data.Stats.DeepestMeters < Rebirth.minDeepestMeters then
		return false, string.format("Reach %s first (the Hadal Maw).", Format.meters(Rebirth.minDeepestMeters))
	end
	local cost = Stats.rebirthCost(data.Rebirths)
	if data.Coins < cost then
		return false, string.format("You need %s coins.", Format.short(cost))
	end
	return true, nil
end

function RebirthService.rebirth(player: Player): boolean
	local data = DataService.get(player)
	local state = PlayerState.get(player)
	if not data or not state then
		return false
	end
	if state.dive then
		Remotes.notify(player, "Surface before you Resurface.", "warn")
		return false
	end
	local ok, reason = RebirthService.canRebirth(player)
	if not ok then
		Remotes.notify(player, reason or "Not yet.", "warn", "🔱")
		return false
	end
	local newCount = data.Rebirths + 1
	local tokens = Stats.rebirthTokens(newCount)
	data.Coins = 0
	for _, upgrade in Upgrades.list do
		data.Upgrades[upgrade.id] = Stats.startLevel(data.Perks, upgrade.id)
	end
	data.Rebirths = newCount
	data.Tokens += tokens
	for _, key in { "Coins", "Upgrades", "Rebirths", "Tokens" } do
		DataService.replicate(player, key)
	end
	ServerSignals.Rebirthed:Fire(player, newCount)
	Remotes.fire(player, "Effect", { kind = "Rebirth", count = newCount, tokens = tokens, riftUnlocked = newCount == Rebirth.riftUnlockRebirths })
	AnnounceService.chat(
		string.format("🔱 %s has RESURFACED! Rebirth #%d - now x%s sell value!", player.DisplayName, newCount, tostring(1 + newCount * Rebirth.sellMultiplierPerRebirth)),
		Color3.fromRGB(150, 240, 255)
	)
	DataService.save(player)
	return true
end

function RebirthService.buyPerk(player: Player, perkId: string): boolean
	local data = DataService.get(player)
	local perk = Rebirth.perksById[perkId]
	if not data or not perk then
		return false
	end
	local level = data.Perks[perkId] or 0
	if level >= #perk.costs then
		return false
	end
	local cost = perk.costs[level + 1]
	if data.Tokens < cost then
		Remotes.notify(player, string.format("You need %d rebirth tokens.", cost), "warn", "💠")
		return false
	end
	data.Tokens -= cost
	data.Perks[perkId] = level + 1
	if perk.skin then
		data.Skins.Owned[perk.skin] = true
		DataService.replicate(player, "Skins")
	end
	DataService.replicate(player, "Tokens")
	DataService.replicate(player, "Perks")
	ServerSignals.StatsDirty:Fire(player)
	Remotes.notify(player, string.format("%s %s is now level %d!", perk.icon, perk.name, level + 1), "good", perk.icon)
	return true
end

function RebirthService.Start()
	Remotes.on("Rebirth", 0.5, 1, function(player)
		RebirthService.rebirth(player)
	end)
	Remotes.on("BuyPerk", 3, 4, function(player, perkId)
		if Validate.oneOf(perkId, Rebirth.perksById) then
			RebirthService.buyPerk(player, perkId)
		end
	end)
end

return RebirthService

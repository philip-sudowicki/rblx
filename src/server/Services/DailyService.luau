--!strict
-- Daily login rewards: a 7-day streak calendar claimed once per UTC day at the treasure chest
-- (or from the Quests menu). Missing a whole day restarts the streak at day 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyRewards = require(Shared.Config.DailyRewards)
local Game = require(Shared.Config.Game)
local Calendar = require(Shared.Modules.Calendar)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)

local DailyService = {}

function DailyService.claim(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local now = os.time()
	local state = Calendar.dailyState(data.Daily, now)
	if not state.canClaim then
		Remotes.notify(player, string.format("Come back in %s for your next daily reward!", Format.duration(Calendar.nextDayAt(now) - now)), "info", "🎁")
		return false
	end
	local reward = DailyRewards.rewards[state.slot]
	data.Daily.LastDay = Calendar.day(now)
	data.Daily.Streak = state.streak
	data.Daily.Claimed += 1
	DataService.replicate(player, "Daily")

	local parts = {}
	local zone = DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters)
	if reward.coins then
		local coins = reward.coins * Stats.coinScale(DailyRewards.coinScale, zone)
		DataService.addCoins(player, coins, "Daily")
		table.insert(parts, Format.short(coins) .. " coins")
		Remotes.fire(player, "Effect", { kind = "Coins", coins = coins })
	end
	if reward.boost then
		local boost = Game.Boosts[reward.boost]
		if boost then
			DataService.addBoost(player, reward.boost, boost.seconds)
			table.insert(parts, string.format("%s (%d min)", boost.name, math.floor(boost.seconds / 60)))
		end
	end
	local consumable = reward.consumable
	if consumable then
		DataService.addConsumable(player, consumable.key, consumable.amount)
		table.insert(parts, string.format("%d× %s", consumable.amount, (consumable.key:gsub("(%l)(%u)", "%1 %2"))))
	end
	if reward.tokens and data.Rebirths > 0 then
		DataService.addTokens(player, reward.tokens)
		table.insert(parts, string.format("%d rebirth token", reward.tokens))
	end
	Remotes.fire(player, "Effect", { kind = "Daily", slot = state.slot, streak = state.streak })
	Remotes.notify(player, string.format("Day %d reward: %s!", state.slot, table.concat(parts, ", ")), "good", "🎁")
	return true
end

function DailyService.Start()
	Remotes.on("ClaimDaily", 1, 2, function(player)
		DailyService.claim(player)
	end)
end

return DailyService

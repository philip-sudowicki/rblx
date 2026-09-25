--!strict
-- Achievements: unlocked automatically when a tracked stat reaches its target. Rewards are
-- coins (scaled to the deepest zone reached) and sub skins. Also awards the milestone Roblox
-- badges from Config/Badges (each at most once per player).

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Badges = require(Shared.Config.Badges)
local Skins = require(Shared.Config.Skins)
local Zones = require(Shared.Config.Zones)
local IndexMath = require(Shared.Modules.IndexMath)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local CosmeticService = require(script.Parent.CosmeticService)

local AchievementService = {}

local queued: { [Player]: boolean } = {}

function AchievementService.statValue(data: Types.PlayerData, stat: string): number
	if stat == "Rebirths" then
		return data.Rebirths
	elseif stat == "SetsCompleted" then
		local count = 0
		for _ in data.Sets do
			count += 1
		end
		return count
	elseif stat == "IndexPercent" then
		return IndexMath.percent(IndexMath.completion(data.Discovered).global)
	end
	local value = (data.Stats :: any)[stat]
	return if typeof(value) == "number" then value else 0
end

-- Awards a Roblox badge once (remembered in Flags so BadgeService isn't asked again).
function AchievementService.badge(player: Player, key: string)
	local data = DataService.get(player)
	local id = Badges[key]
	local flag = "Badge_" .. key
	if not data or not id or id == 0 or data.Flags[flag] then
		return
	end
	data.Flags[flag] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadge(player.UserId, id)
			end
		end)
		if not ok then
			-- try again next session
			local current = DataService.get(player)
			if current then
				current.Flags[flag] = nil
			end
			warn(string.format("[DeepHaul] badge %s failed: %s", key, tostring(err)))
		end
	end)
end

local function milestoneBadges(player: Player, data: Types.PlayerData)
	AchievementService.badge(player, "Welcome")
	if data.Flags.FoundLegendary then
		AchievementService.badge(player, "FirstLegendary")
	end
	if data.Stats.MythicPlus > 0 then
		AchievementService.badge(player, "FirstMythic")
	end
	if data.Stats.Secrets > 0 then
		AchievementService.badge(player, "FirstSecret")
	end
	if data.Stats.DeepestMeters >= Zones.byId.Hadal.meters[1] then
		AchievementService.badge(player, "ReachHadal")
	end
	if data.Stats.RiftVisits > 0 then
		AchievementService.badge(player, "EnterRift")
	end
	if data.Rebirths > 0 then
		AchievementService.badge(player, "FirstRebirth")
	end
end

function AchievementService.check(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local changed = false
	for _, achievement in Achievements.list do
		if not data.Achievements[achievement.id] and AchievementService.statValue(data, achievement.stat) >= achievement.target then
			data.Achievements[achievement.id] = true
			changed = true
			local rewards = {}
			if achievement.coins then
				local coins = achievement.coins * Stats.coinScale(Achievements.coinScale, DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters))
				DataService.addCoins(player, coins, "Achievement")
				table.insert(rewards, Format.short(coins) .. " coins")
			end
			if achievement.skin and Skins.byId[achievement.skin] then
				CosmeticService.grantSkin(player, achievement.skin, false)
				table.insert(rewards, "the " .. Skins.byId[achievement.skin].name .. " sub skin")
			end
			Remotes.fire(player, "Effect", { kind = "Achievement", id = achievement.id })
			Remotes.notify(player, string.format("Achievement: %s! %s", achievement.name, if #rewards > 0 then "You got " .. table.concat(rewards, " and ") .. "." else ""), "good", "🏅")
		end
	end
	if changed then
		DataService.replicate(player, "Achievements")
	end
	milestoneBadges(player, data)
end

-- Batches checks: many stats change at once when a fish is caught.
local function queue(player: Player)
	if queued[player] then
		return
	end
	queued[player] = true
	task.defer(function()
		queued[player] = nil
		if player.Parent then
			AchievementService.check(player)
		end
	end)
end

function AchievementService.Start()
	DataService.onLoaded(queue)
	ServerSignals.ItemObtained:Connect(queue)
	ServerSignals.DiveEnded:Connect(queue)
	ServerSignals.DepthReached:Connect(queue)
	ServerSignals.ZoneEntered:Connect(queue)
	ServerSignals.Rebirthed:Connect(queue)
	ServerSignals.SetCompleted:Connect(queue)
	ServerSignals.PlayerLeaving:Connect(function(player)
		queued[player] = nil
	end)
end

return AchievementService

--!strict
-- Index / Codex rewards and collection sets. Discovery itself is recorded by LootService;
-- this service completes sets (permanent bonuses + badges) and pays out milestone rewards.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectionSets = require(Shared.Config.CollectionSets)
local IndexRewards = require(Shared.Config.IndexRewards)
local Badges = require(Shared.Config.Badges)
local IndexMath = require(Shared.Modules.IndexMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local AnnounceService = require(script.Parent.AnnounceService)
local Validate = require(script.Parent.Validate)

local IndexService = {}

function IndexService.awardBadge(player: Player, key: string)
	local id = Badges[key]
	if not id or id == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
				BadgeService:AwardBadge(player.UserId, id)
			end
		end)
		if not ok then
			warn("[DeepHaul] badge " .. key .. " failed: " .. tostring(err))
		end
	end)
end

local function checkSets(player: Player, onlyFor: string?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local changed = false
	local candidates: { string }? = nil
	if onlyFor then
		candidates = CollectionSets.setsForItem[onlyFor]
		if not candidates then
			return
		end
	end
	local function consider(set: CollectionSets.CollectionSet)
		if data.Sets[set.id] then
			return
		end
		for _, itemId in set.items do
			if not data.Discovered.Treasure[itemId] then
				return
			end
		end
		data.Sets[set.id] = true
		changed = true
		ServerSignals.SetCompleted:Fire(player, set.id)
		IndexService.awardBadge(player, set.badge)
		local bonus = if set.bonus.stat == "cargo"
			then string.format("+%d cargo slots", set.bonus.amount)
			else string.format("+%d%% %s", math.floor(set.bonus.amount * 100 + 0.5), set.bonus.stat)
		Remotes.notify(player, string.format("Set complete: %s! Permanent bonus: %s", set.name, bonus), "good", "🏆")
		Remotes.fire(player, "Effect", { kind = "SetComplete", id = set.id })
		AnnounceService.chat(string.format("🏆 %s completed the collection set %s!", player.DisplayName, set.name), set.color)
	end
	if candidates then
		for _, setId in candidates do
			consider(CollectionSets.byId[setId])
		end
	else
		for _, set in CollectionSets.list do
			consider(set)
		end
	end
	if changed then
		DataService.replicate(player, "Sets")
	end
end

-- Claims one milestone, or every reached and unclaimed milestone when key is "*".
-- Returns the coins paid out.
function IndexService.claim(player: Player, key: string): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local completion = IndexMath.completion(data.Discovered)
	local coins, luck, count = 0, 0, 0
	local label = ""
	for _, milestone in IndexMath.milestones(completion) do
		if (key == "*" or milestone.key == key) and milestone.reached and not data.IndexClaimed[milestone.key] then
			data.IndexClaimed[milestone.key] = true
			coins += milestone.coins * Stats.coinScale(IndexRewards.coinScale, milestone.scaleIndex)
			luck += milestone.luck
			count += 1
			label = milestone.label
		end
	end
	if count == 0 then
		return 0
	end
	DataService.addCoins(player, coins, "Index")
	DataService.replicate(player, "IndexClaimed")
	if luck > 0 then
		ServerSignals.StatsDirty:Fire(player)
	end
	local luckText = if luck > 0 then string.format(" and +%d%% permanent luck", math.floor(luck * 100 + 0.5)) else ""
	local what = if count == 1 then label .. " reward" else string.format("%d Index rewards", count)
	Remotes.notify(player, string.format("%s: %s coins%s!", what, Format.short(coins), luckText), "good", "📖")
	Remotes.fire(player, "Effect", { kind = "Coins", coins = coins })
	return coins
end

function IndexService.Start()
	ServerSignals.ItemObtained:Connect(function(player, item)
		if item.k == "T" then
			checkSets(player, item.i)
		end
	end)
	DataService.onLoaded(function(player)
		checkSets(player, nil)
	end)
	Remotes.on("ClaimIndex", 4, 6, function(player, key)
		if Validate.string(key, 32) then
			IndexService.claim(player, key)
		end
	end)
end

return IndexService

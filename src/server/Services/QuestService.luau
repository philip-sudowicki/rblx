--!strict
-- Daily (3) and weekly (3) quests. New quests are drawn when the UTC day / week rolls over,
-- sized to the deepest zone the player has reached, and seeded per player so rejoining can't
-- reroll them. Progress comes from gameplay signals; rewards are claimed from the Quests menu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Game = require(Shared.Config.Game)
local Calendar = require(Shared.Modules.Calendar)
local QuestMath = require(Shared.Modules.QuestMath)
local DepthMath = require(Shared.Modules.DepthMath)
local Hash = require(Shared.Modules.Hash)
local Format = require(Shared.Modules.Format)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local Validate = require(script.Parent.Validate)

local QuestService = {}

-- A clean dive only counts for quests if it was a real dive (not launch-and-surface farming).
local MIN_QUEST_DIVE_SECONDS = 25

local pending: { [Player]: boolean } = {}

local function tierOf(data: Types.PlayerData): number
	return DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters)
end

-- Rolls over daily / weekly quests if their period changed. Returns true if anything changed.
function QuestService.refresh(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local now = os.time()
	local changed = false
	local day = Calendar.day(now)
	local week = Calendar.week(now)
	if data.Quests.DailyKey ~= day then
		data.Quests.DailyKey = day
		data.Quests.Daily = QuestMath.generate(Hash.rng(Hash.combine(player.UserId, day)), "daily", tierOf(data), Quests.dailyCount, data.Rebirths)
		changed = true
	end
	if data.Quests.WeeklyKey ~= week then
		data.Quests.WeeklyKey = week
		data.Quests.Weekly = QuestMath.generate(Hash.rng(Hash.combine(Hash.combine(player.UserId, week), 0x5EED)), "weekly", tierOf(data), Quests.weeklyCount, data.Rebirths)
		changed = true
	end
	if changed then
		DataService.replicate(player, "Quests")
	end
	return changed
end

local function flush(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent then
			DataService.replicate(player, "Quests")
		end
	end)
end

-- Adds progress to every unclaimed quest `amountFor` returns > 0 for.
local function advance(player: Player, amountFor: (Types.QuestState) -> number, absolute: boolean?)
	local data = DataService.get(player)
	if not data then
		return
	end
	QuestService.refresh(player)
	local touched = false
	local lists: { { Types.QuestState } } = { data.Quests.Daily, data.Quests.Weekly }
	for _, list in lists do
		for _, quest in list do
			if not quest.claimed and quest.progress < quest.target then
				local amount = amountFor(quest)
				if amount > 0 then
					local before = quest.progress
					quest.progress = math.min(quest.target, if absolute then math.max(quest.progress, amount) else quest.progress + amount)
					if quest.progress ~= before then
						touched = true
						if quest.progress >= quest.target then
							Remotes.fire(player, "Effect", { kind = "QuestComplete" })
							Remotes.notify(player, string.format("Quest complete: %s! Claim it in Quests.", QuestMath.text(quest)), "good", "📜")
						end
					end
				end
			end
		end
	end
	if touched then
		flush(player)
	end
end

function QuestService.claim(player: Player, period: string, index: number): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	QuestService.refresh(player)
	local list: { Types.QuestState } = if period == "Weekly" then data.Quests.Weekly else data.Quests.Daily
	local quest = list[index]
	if not quest or quest.claimed or quest.progress < quest.target then
		return false
	end
	quest.claimed = true
	local parts = { Format.short(quest.reward) .. " coins" }
	DataService.addCoins(player, quest.reward, "Quest")
	if quest.tokens and quest.tokens > 0 then
		DataService.addTokens(player, quest.tokens)
		table.insert(parts, string.format("%d rebirth token", quest.tokens))
	end
	if quest.boost then
		local boost = Game.Boosts[quest.boost]
		if boost then
			DataService.addBoost(player, quest.boost, boost.seconds)
			table.insert(parts, boost.name)
		end
	end
	DataService.replicate(player, "Quests")
	Remotes.fire(player, "Effect", { kind = "Coins", coins = quest.reward })
	Remotes.notify(player, "Quest reward: " .. table.concat(parts, " + ") .. "!", "good", "📜")
	return true
end

function QuestService.Start()
	DataService.onLoaded(function(player)
		QuestService.refresh(player)
	end)
	ServerSignals.ItemObtained:Connect(function(player, item, context)
		advance(player, function(quest)
			return QuestMath.itemProgress(quest, item, context.zone)
		end)
	end)
	ServerSignals.ItemsSold:Connect(function(player, _count, coins)
		advance(player, function(quest)
			return if QuestMath.kind(quest) == "earn" then coins else 0
		end)
	end)
	ServerSignals.SonarUsed:Connect(function(player)
		advance(player, function(quest)
			return if QuestMath.kind(quest) == "sonar" then 1 else 0
		end)
	end)
	ServerSignals.DiveEnded:Connect(function(player, _reason, clean, seconds)
		if clean and seconds >= MIN_QUEST_DIVE_SECONDS then
			advance(player, function(quest)
				return if QuestMath.kind(quest) == "cleanDive" then 1 else 0
			end)
		end
	end)
	ServerSignals.DepthReached:Connect(function(player, meters)
		advance(player, function(quest)
			return if QuestMath.kind(quest) == "depth" then math.floor(meters) else 0
		end, true)
	end)
	ServerSignals.PlayerLeaving:Connect(function(player)
		pending[player] = nil
	end)
	Remotes.on("ClaimQuest", 4, 6, function(player, period, index)
		if (period == "Daily" or period == "Weekly") and Validate.integer(index, 1, 10) then
			QuestService.claim(player, period, index)
		end
	end)
	-- roll quests over at midnight for everyone who stays online
	task.spawn(function()
		while true do
			task.wait(30)
			for _, state in PlayerState.all() do
				if state.ready then
					QuestService.refresh(state.player)
				end
			end
		end
	end)
end

return QuestService

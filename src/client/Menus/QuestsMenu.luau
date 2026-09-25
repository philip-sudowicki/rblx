--!strict
-- Quests: 3 daily and 3 weekly quests with progress and rewards, the 7-day login calendar and
-- the achievements list. Resets are shown as live countdowns (UTC midnight / Monday).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local DailyRewards = require(Shared.Config.DailyRewards)
local Achievements = require(Shared.Config.Achievements)
local Skins = require(Shared.Config.Skins)
local Calendar = require(Shared.Modules.Calendar)
local QuestMath = require(Shared.Modules.QuestMath)
local IndexMath = require(Shared.Modules.IndexMath)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local Types = require(Shared.Modules.Types)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local QuestsMenu = {}

type QuestPage = { list: Frame, timer: TextLabel }

local window: Window.Window
local isOpen = false
local pages: { [string]: QuestPage } = {}
local login: { tiles: { Frame }, claim: TextButton, streak: TextLabel, timer: TextLabel }
local achievementList: ScrollingFrame

local function now(): number
	return math.floor(ClientState.serverTime())
end

local function zoneTier(): number
	local data = ClientState.data
	return if data then DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters) else 1
end

---------------------------------------------------------------- quests

local function rewardText(quest: Types.QuestState): string
	local parts = { "💰 " .. Format.short(quest.reward) }
	if quest.tokens and quest.tokens > 0 then
		table.insert(parts, string.format("🔱 %d", quest.tokens))
	end
	if quest.boost and Game.Boosts[quest.boost] then
		table.insert(parts, Game.Boosts[quest.boost].icon .. " " .. Game.Boosts[quest.boost].name)
	end
	return table.concat(parts, "  +  ")
end

local function refreshQuests(period: string)
	local data = ClientState.data
	local page = pages[period]
	if not data or not page then
		return
	end
	for _, child in page.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list: { Types.QuestState } = if period == "Weekly" then data.Quests.Weekly else data.Quests.Daily
	local current = if period == "Weekly" then data.Quests.WeeklyKey == Calendar.week(now()) else data.Quests.DailyKey == Calendar.day(now())
	if not current or #list == 0 then
		UIKit.label({ Text = "New quests are on their way…", Size = UDim2.new(1, 0, 0, 40), TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, Parent = page.list })
		return
	end
	for index, quest in list do
		local complete = QuestMath.complete(quest)
		local card = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = index, Parent = page.list })
		UIKit.corner(Theme.CornerSmall).Parent = card
		UIKit.stroke(if quest.claimed then Theme.Stroke elseif complete then Theme.Good else Theme.Stroke, if complete and not quest.claimed then 2.5 else 1, 0).Parent = card
		UIKit.label({ Text = (if quest.claimed then "✅ " else "") .. QuestMath.text(quest), Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -220, 0, 28), Font = Theme.FontBold, TextSize = 19, TextColor3 = if quest.claimed then Theme.TextMuted else Theme.Text, Parent = card })
		UIKit.label({ Text = rewardText(quest), Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -220, 0, 22), TextSize = 15, TextColor3 = Theme.Coin, Parent = card })
		local bar = UIKit.bar({ Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -220, 0, 18), Parent = card }, if complete then Theme.Good else Theme.Accent)
		local shown = if QuestMath.kind(quest) == "earn" then Format.short(quest.progress) .. " / " .. Format.short(quest.target) else string.format("%s / %s", Format.commas(quest.progress), Format.commas(quest.target))
		bar.set(quest.progress / math.max(quest.target, 1), shown)
		UIKit.button({
			Text = if quest.claimed then "Claimed" elseif complete then "CLAIM" else string.format("%d%%", math.floor(quest.progress / math.max(quest.target, 1) * 100)),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(170, 50),
			Font = Theme.FontDisplay,
			TextSize = 22,
			Parent = card,
		}, function()
			if complete and not quest.claimed then
				Net.event("ClaimQuest"):FireServer(period, index)
			end
		end, if complete and not quest.claimed then Theme.Good else Theme.PanelLight)
	end
end

local function buildQuestPage(page: Frame, period: string)
	local timer = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 26), TextSize = 16, TextColor3 = Theme.TextMuted, Parent = page })
	local list = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), Parent = page })
	UIKit.list(Enum.FillDirection.Vertical, 10).Parent = list
	pages[period] = { list = list, timer = timer }
end

---------------------------------------------------------------- login calendar

local function tileReward(reward: DailyRewards.DailyReward): string
	local lines = {}
	if reward.coins then
		table.insert(lines, "💰 " .. Format.short(reward.coins * Stats.coinScale(DailyRewards.coinScale, zoneTier())))
	end
	if reward.boost and Game.Boosts[reward.boost] then
		table.insert(lines, Game.Boosts[reward.boost].icon .. " " .. Game.Boosts[reward.boost].name)
	end
	if reward.consumable then
		table.insert(lines, string.format("%d× %s", reward.consumable.amount, (reward.consumable.key:gsub("(%l)(%u)", "%1 %2"))))
	end
	if reward.tokens and ClientState.data and ClientState.data.Rebirths > 0 then
		table.insert(lines, string.format("🔱 %d token", reward.tokens))
	end
	return table.concat(lines, "\n")
end

local function refreshLogin()
	local data = ClientState.data
	if not data then
		return
	end
	local state = Calendar.dailyState(data.Daily, now())
	local cycle = #DailyRewards.rewards
	-- slots already claimed in the current 7-day cycle
	local doneCount = if state.canClaim then state.slot - 1 elseif state.slot == 1 then cycle else state.slot - 1
	for slot, tile in login.tiles do
		for _, child in tile:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local reward = DailyRewards.rewards[slot]
		local done = slot <= doneCount
		local isNext = slot == state.slot and not done
		tile.BackgroundColor3 = if isNext and state.canClaim then Theme.Good elseif done then Theme.PanelLight else Theme.PanelDark
		UIKit.label({ Text = "DAY " .. slot, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), Font = Theme.FontDisplay, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if isNext and state.canClaim then Theme.TextDark else Theme.Accent, Parent = tile })
		UIKit.label({ Text = if done then "✅" elseif slot == cycle then "🎁" else "📦", Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 44), TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center, Parent = tile })
		UIKit.label({ Text = tileReward(reward), Position = UDim2.fromOffset(6, 80), Size = UDim2.new(1, -12, 0, 80), TextSize = 13, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = if isNext and state.canClaim then Theme.TextDark else Theme.Text, Parent = tile })
	end
	if state.canClaim then
		login.claim.Text = string.format("🎁 CLAIM DAY %d", state.slot)
		login.claim.BackgroundColor3 = Theme.Good
	else
		login.claim.Text = "Claimed today ✅"
		login.claim.BackgroundColor3 = Theme.PanelLight
	end
	local streak = if state.canClaim then state.streak - 1 else data.Daily.Streak
	login.streak.Text = if state.broken
		then "💔 You missed a day, so your streak restarts. Log in every day to keep it going!"
		else string.format("🔥 Login streak: <b>%d day%s</b>  ·  %d rewards claimed in total", streak, if streak == 1 then "" else "s", data.Daily.Claimed)
end

local function buildLogin(page: Frame)
	UIKit.label({ Text = "Log in every day for bigger rewards. Day 7 is the jackpot!", Size = UDim2.new(1, 0, 0, 26), TextSize = 16, TextColor3 = Theme.TextMuted, Parent = page })
	local row = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 170), Parent = page })
	UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = row
	local tiles = {}
	for slot = 1, #DailyRewards.rewards do
		local tile = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, Size = UDim2.fromOffset(112, 166), LayoutOrder = slot, Parent = row })
		UIKit.corner(Theme.CornerSmall).Parent = tile
		UIKit.stroke(Theme.Stroke, 1.5, 0.1).Parent = tile
		tiles[slot] = tile
	end
	local streak = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 214), Size = UDim2.new(1, 0, 0, 28), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Parent = page })
	local claim = UIKit.button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 254), Size = UDim2.fromOffset(320, 60), Font = Theme.FontDisplay, TextSize = 26, Parent = page }, function()
		local data = ClientState.data
		if data and Calendar.dailyState(data.Daily, now()).canClaim then
			Net.event("ClaimDaily"):FireServer()
		end
	end, Theme.Good)
	local timer = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 324), Size = UDim2.new(1, 0, 0, 24), TextSize = 15, TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, Parent = page })
	login = { tiles = tiles, claim = claim, streak = streak, timer = timer }
end

---------------------------------------------------------------- achievements

local function refreshAchievements()
	local data = ClientState.data
	if not data then
		return
	end
	for _, child in achievementList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local indexPercent = IndexMath.percent(IndexMath.completion(data.Discovered).global)
	for _, achievement in Achievements.list do
		local unlocked = data.Achievements[achievement.id] == true
		local value: number
		if achievement.stat == "Rebirths" then
			value = data.Rebirths
		elseif achievement.stat == "SetsCompleted" then
			value = 0
			for _ in data.Sets do
				value += 1
			end
		elseif achievement.stat == "IndexPercent" then
			value = indexPercent
		else
			local raw = (data.Stats :: any)[achievement.stat]
			value = if typeof(raw) == "number" then raw else 0
		end
		local row = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = if unlocked then 0.1 else 0.35, Size = UDim2.new(1, -10, 0, 58), LayoutOrder = (if unlocked then 1000 else 0) + achievement.order, Parent = achievementList })
		UIKit.corner(Theme.CornerSmall).Parent = row
		if unlocked then
			UIKit.stroke(Theme.Good, 1.5, 0.2).Parent = row
		end
		UIKit.label({ Text = if unlocked then "🏅" else "🔒", Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 58), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		UIKit.label({ Text = achievement.name, Position = UDim2.fromOffset(54, 6), Size = UDim2.fromOffset(300, 24), Font = Theme.FontBold, TextSize = 17, TextColor3 = if unlocked then Theme.Good else Theme.Text, Parent = row })
		UIKit.label({ Text = achievement.desc, Position = UDim2.fromOffset(54, 30), Size = UDim2.fromOffset(300, 20), TextSize = 13, TextColor3 = Theme.TextMuted, Parent = row })
		local reward = if achievement.skin and Skins.byId[achievement.skin]
			then "🎨 " .. Skins.byId[achievement.skin].name .. " skin"
			elseif achievement.coins then "💰 " .. Format.short(achievement.coins * Stats.coinScale(Achievements.coinScale, zoneTier()))
			else ""
		UIKit.label({ Text = reward, Position = UDim2.fromOffset(360, 0), Size = UDim2.fromOffset(200, 58), TextSize = 14, TextColor3 = Theme.Coin, Parent = row })
		local bar = UIKit.bar({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(220, 20), Parent = row }, if unlocked then Theme.Good else Theme.Accent)
		local shown = math.min(value, achievement.target)
		bar.set(shown / achievement.target, if unlocked then "Unlocked!" else string.format("%s / %s", Format.short(math.floor(shown)), Format.short(achievement.target)))
	end
end

---------------------------------------------------------------- window

local function refreshTimers()
	local t = now()
	if pages.Daily then
		pages.Daily.timer.Text = "⏳ New daily quests in " .. Format.duration(Calendar.nextDayAt(t) - t)
	end
	if pages.Weekly then
		pages.Weekly.timer.Text = "⏳ New weekly quests in " .. Format.duration(Calendar.nextWeekAt(t) - t) .. "  ·  weekly quests pay 6× and grant a Luck Boost"
	end
	if login then
		login.timer.Text = "Next reward in " .. Format.duration(Calendar.nextDayAt(t) - t) .. " (resets at 00:00 UTC)"
	end
end

local function refresh()
	if not isOpen then
		return
	end
	refreshTimers()
	local tab = window.tab
	if tab == "Daily" or tab == "Weekly" then
		refreshQuests(tab)
	elseif tab == "Login" then
		refreshLogin()
	else
		refreshAchievements()
	end
end

-- Red dot: a finished quest or today's login reward waiting to be claimed.
function QuestsMenu.badge(): boolean
	local data = ClientState.data
	if not data then
		return false
	end
	if Calendar.dailyState(data.Daily, now()).canClaim then
		return true
	end
	local lists: { { Types.QuestState } } = { data.Quests.Daily, data.Quests.Weekly }
	for _, list in lists do
		for _, quest in list do
			if not quest.claimed and QuestMath.complete(quest) then
				return true
			end
		end
	end
	return false
end

function QuestsMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Quests", "📜", { "Daily", "Weekly", "Login", "Achievements" }, close)
	buildQuestPage(window.pages.Daily, "Daily")
	buildQuestPage(window.pages.Weekly, "Weekly")
	buildLogin(window.pages.Login)
	achievementList = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window.pages.Achievements,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = achievementList
	window.TabChanged:Connect(refresh)
	ClientState.Changed:Connect(function(key)
		if key == "Quests" or key == "Daily" or key == "Achievements" or key == "Stats" or key == "*" then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				refreshTimers()
			end
		end
	end)
	return window
end

function QuestsMenu.onOpen()
	isOpen = true
	refresh()
end

function QuestsMenu.onClose()
	isOpen = false
end

return QuestsMenu

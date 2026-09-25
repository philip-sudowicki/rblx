--!strict
-- Index: every fish and treasure in the game. Undiscovered entries are black silhouettes and
-- hidden Secrets stay "???" until found. Completion per zone and category, your personal odds
-- with your current luck and active events, collection sets, and milestone rewards (coins and
-- permanent luck) to claim one by one or all at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Zones = require(Shared.Config.Zones)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Conditions = require(Shared.Config.Conditions)
local Events = require(Shared.Config.Events)
local TreasureCategories = require(Shared.Config.TreasureCategories)
local CollectionSets = require(Shared.Config.CollectionSets)
local IndexRewards = require(Shared.Config.IndexRewards)
local IndexMath = require(Shared.Modules.IndexMath)
local LootMath = require(Shared.Modules.LootMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local Types = require(Shared.Modules.Types)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ItemViewport = require(script.Parent.Parent.UI.ItemViewport)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local IndexMenu = {}

local CARD = Vector2.new(100, 124)
local EVENT_GROUP = "Event"
-- Base tier chances with no luck (Common gets what the rarer tiers leave).
local BASE_CHANCES = LootMath.tierChances({ luck = 1, zoneBonus = 1 })

type Entry = {
	kind: string, -- "F" | "T"
	id: string,
	name: string,
	rarity: number,
	desc: string,
	value: number,
	zone: number?, -- home zone index (nil for event exclusives)
	event: string?,
	category: string?,
	clawTier: number,
	order: number,
}

type Group = { key: string, label: string, color: Color3, entries: { Entry } }

type Detail = {
	view: ItemViewport.ItemView,
	mystery: TextLabel,
	name: TextLabel,
	tags: TextLabel,
	desc: TextLabel,
	odds: TextLabel,
	stats: TextLabel,
	chips: Frame,
}

type Browser = {
	kind: string,
	groups: { Group },
	groupKey: string,
	selected: Entry?,
	chips: { [string]: TextButton },
	grid: ScrollingFrame,
	detail: Detail,
	builtFor: string, -- group key the grid was last built for ("" = dirty)
}

local window: Window.Window
local isOpen = false
local browsers: { [string]: Browser } = {}
local setsList: ScrollingFrame
local rewards: { overall: UIKit.Bar, claimAll: TextButton, list: ScrollingFrame }

---------------------------------------------------------------- entries

local fishGroups: { Group } = {}
local treasureGroups: { Group } = {}
-- Number of same-tier species in each zone's normal pool, for personal odds.
local tierCounts: { [string]: { [number]: { [number]: number } } } = { F = {}, T = {} }

local function addTierCount(kind: string, zone: number, tier: number)
	local byZone = tierCounts[kind]
	byZone[zone] = byZone[zone] or {}
	byZone[zone][tier] = (byZone[zone][tier] or 0) + 1
end

do
	local byZone: { [number]: Group } = {}
	for _, zone in Zones.list do
		local group: Group = { key = tostring(zone.index), label = zone.name, color = zone.color, entries = {} }
		byZone[zone.index] = group
		table.insert(fishGroups, group)
	end
	local eventFish: Group = { key = EVENT_GROUP, label = "Event Exclusives", color = Theme.Accent, entries = {} }
	table.insert(fishGroups, eventFish)
	for _, def in Fish.list do
		local rarity = Rarities.byId[def.rarity]
		local zoneIndex = if def.zone then Zones.byId[def.zone].index else nil
		local entry: Entry = {
			kind = "F",
			id = def.id,
			name = def.name,
			rarity = rarity.index,
			desc = def.desc,
			value = def.value,
			zone = zoneIndex,
			event = def.event,
			category = nil,
			clawTier = rarity.clawTier,
			order = def.order,
		}
		if zoneIndex and not def.event then
			table.insert(byZone[zoneIndex].entries, entry)
			addTierCount("F", zoneIndex, rarity.index)
		else
			table.insert(eventFish.entries, entry)
		end
	end

	local byCategory: { [string]: Group } = {}
	for _, category in TreasureCategories.list do
		local group: Group = { key = category.id, label = category.icon .. " " .. category.name, color = category.color, entries = {} }
		byCategory[category.id] = group
		table.insert(treasureGroups, group)
	end
	local eventTreasure: Group = { key = EVENT_GROUP, label = "🎉 Event Exclusives", color = Theme.Accent, entries = {} }
	table.insert(treasureGroups, eventTreasure)
	for _, def in Treasure.list do
		local rarity = Rarities.byId[def.rarity]
		local zoneIndex = if def.zone then Zones.byId[def.zone].index else nil
		local entry: Entry = {
			kind = "T",
			id = def.id,
			name = def.name,
			rarity = rarity.index,
			desc = def.desc,
			value = def.value,
			zone = zoneIndex,
			event = def.event,
			category = def.category,
			clawTier = def.clawTier or rarity.clawTier,
			order = def.order,
		}
		if def.event then
			table.insert(eventTreasure.entries, entry)
		else
			table.insert(byCategory[def.category].entries, entry)
			if zoneIndex then
				addTierCount("T", zoneIndex, rarity.index)
			end
		end
	end
	local function sortEntries(groups: { Group })
		for _, group in groups do
			table.sort(group.entries, function(a, b)
				if a.rarity ~= b.rarity then
					return a.rarity < b.rarity
				end
				if (a.zone or 99) ~= (b.zone or 99) then
					return (a.zone or 99) < (b.zone or 99)
				end
				return a.order < b.order
			end)
		end
	end
	sortEntries(fishGroups)
	sortEntries(treasureGroups)
end

local function discovered(entry: Entry): any
	local data = ClientState.data
	if not data then
		return nil
	end
	if entry.kind == "F" then
		return data.Discovered.Fish[entry.id]
	end
	return data.Discovered.Treasure[entry.id]
end

local function isHidden(entry: Entry): boolean
	return Rarities.list[entry.rarity].hidden and discovered(entry) == nil
end

local function groupProgress(group: Group): (number, number)
	local found = 0
	for _, entry in group.entries do
		if discovered(entry) ~= nil then
			found += 1
		end
	end
	return found, #group.entries
end

-- Chance that a spawn in the entry's home zone is this exact species, with the player's
-- current luck (upgrades, sets, perks, Index, boosts, server luck and events).
local function personalChance(entry: Entry): number?
	local zoneIndex = entry.zone
	if not zoneIndex or entry.event then
		return nil
	end
	local sameTier = tierCounts[entry.kind][zoneIndex] and tierCounts[entry.kind][zoneIndex][entry.rarity] or 0
	if sameTier <= 0 then
		return nil
	end
	local tierMult: { [string]: number } = {}
	local events = ClientState.events
	if events and events.active then
		for _, active in events.active do
			local def = Events.byId[active.id]
			local mult = def and def.modifiers.tierMult
			if mult then
				for tier, value in mult do
					tierMult[tier] = (tierMult[tier] or 1) * value
				end
			end
		end
	end
	local chances = LootMath.tierChances({ luck = ClientState.stats().luck, zoneBonus = Zones.list[zoneIndex].rarityBonus, tierMult = tierMult })
	local p = chances[entry.rarity] / sameTier
	if p <= 0 then
		return nil
	end
	return p
end

---------------------------------------------------------------- detail pane

local function setsFor(entry: Entry): { string }
	local names = {}
	local ids = CollectionSets.setsForItem[entry.id]
	if ids then
		for _, id in ids do
			table.insert(names, CollectionSets.byId[id].name)
		end
	end
	return names
end

local function mutationChips(parent: Frame, seen: { [string]: boolean }?)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, mutation in Mutations.list do
		local has = seen ~= nil and seen[mutation.id] == true
		local chip = UIKit.label({
			Text = if has then string.format("%s x%d", mutation.name, mutation.multiplier) else "?",
			Size = UDim2.fromOffset(if has then 86 else 28, 22),
			TextSize = 11,
			Font = Theme.FontBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = if has then mutation.color else Theme.PanelLight,
			TextColor3 = if has then Theme.TextDark else Theme.TextMuted,
			LayoutOrder = index,
			Parent = parent,
		})
		UIKit.corner(UDim.new(0, 6)).Parent = chip
	end
end

local function showDetail(browser: Browser)
	local d = browser.detail
	local entry = browser.selected
	for _, child in d.chips:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not entry then
		d.view.clear()
		d.mystery.Visible = false
		d.name.Text = "Select an entry"
		d.name.TextColor3 = Theme.TextMuted
		d.tags.Text = ""
		d.desc.Text = "Tap any card to see where it lives, your odds of finding it and your best catch."
		d.odds.Text = ""
		d.stats.Text = ""
		return
	end
	local rarity = Rarities.list[entry.rarity]
	local found = discovered(entry)
	local hidden = isHidden(entry)
	local zone = if entry.zone then Zones.list[entry.zone] else nil
	local event = if entry.event then Events.byId[entry.event] else nil

	d.mystery.Visible = hidden
	if hidden then
		d.view.clear()
	else
		d.view.set(entry.kind, entry.id, { silhouette = found == nil, spin = true })
	end

	d.name.Text = if found then entry.name elseif hidden then "???" else "Undiscovered"
	d.name.TextColor3 = if found or not hidden then rarity.color else Theme.TextMuted
	local where = if event then string.format("%s %s only", event.icon, event.name)
		elseif zone then zone.name
		else "Unknown waters"
	d.tags.Text = string.format(
		'<font color="#%s"><b>%s</b></font>  ·  %s',
		(if hidden then Theme.TextMuted else rarity.color):ToHex(),
		if hidden then "???" else rarity.name,
		where
	)

	if found then
		d.desc.Text = entry.desc
	elseif hidden then
		d.desc.Text = string.format("Something no one talks about lurks in %s. Only the luckiest divers have seen it.", if zone then zone.name else "the deep")
	elseif event then
		d.desc.Text = string.format("Appears only during %s. Watch the event timer at the top of the screen.", event.name)
	else
		d.desc.Text = string.format("Not discovered yet. Look in %s.", if zone then zone.name else "the deep")
	end

	local oddsLines = {}
	if not hidden then
		table.insert(oddsLines, string.format("Rarity odds: <b>%s</b> per spawn", Format.odds(BASE_CHANCES[entry.rarity])))
		local mine = personalChance(entry)
		if mine then
			table.insert(oddsLines, string.format('Your odds for this %s: <font color="#50E68C"><b>%s</b></font>', if entry.kind == "F" then "fish" else "treasure", Format.odds(mine)))
		end
		table.insert(oddsLines, string.format("Needs Claw Tier %d · base value 💰 %s", entry.clawTier, Format.commas(entry.value)))
	end
	d.odds.Text = table.concat(oddsLines, "\n")

	if entry.kind == "F" then
		local info = found :: Types.FishDiscovery?
		if info then
			d.stats.Text = string.format("Caught <b>%s</b>×  ·  best %s%s", Format.commas(info.n), Format.weight(info.bw), if info.x then "  ·  👑 Colossal" else "")
			mutationChips(d.chips, info.m)
		else
			d.stats.Text = "Mutations you catch on this species are recorded here."
			mutationChips(d.chips, nil)
		end
	else
		local info = found :: Types.TreasureDiscovery?
		local lines = {}
		if info then
			local condition = Conditions.list[info.bc] or Conditions.list[1]
			table.insert(lines, string.format('Salvaged <b>%s</b>×  ·  best <font color="#%s"><b>%s</b></font>', Format.commas(info.n), condition.color:ToHex(), condition.name))
		end
		local sets = setsFor(entry)
		if #sets > 0 then
			table.insert(lines, "Part of: " .. table.concat(sets, ", "))
		end
		local def = Treasure.byId[entry.id]
		if def and def.cursed then
			table.insert(lines, string.format('<font color="#FF6A6A">Cursed: +%d%% oxygen drain while in cargo</font>', math.floor(def.cursed * 100 + 0.5)))
		end
		d.stats.Text = table.concat(lines, "\n")
	end
end

---------------------------------------------------------------- grid

local function groupByKey(browser: Browser, key: string): Group
	for _, group in browser.groups do
		if group.key == key then
			return group
		end
	end
	return browser.groups[1]
end

local function buildCard(browser: Browser, entry: Entry, layoutOrder: number)
	local rarity = Rarities.list[entry.rarity]
	local found = discovered(entry)
	local hidden = isHidden(entry)
	local card = UIKit.button({
		Text = "",
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		LayoutOrder = layoutOrder,
		Parent = browser.grid,
	}, function()
		browser.selected = entry
		showDetail(browser)
	end, Theme.PanelDark)
	UIKit.stroke(if found then rarity.color else Theme.Stroke, if found then 2 else 1, if found then 0 else 0.4).Parent = card
	if found then
		UIKit.rarityGradient(card, entry.rarity)
	end
	if hidden then
		UIKit.label({ Text = "❓", Size = UDim2.new(1, 0, 0, 74), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	else
		local view = ItemViewport.new(card, UDim2.new(1, -8, 0, 70), UDim2.fromOffset(4, 4))
		view.set(entry.kind, entry.id, { silhouette = found == nil, spin = false })
	end
	UIKit.label({
		Text = if found then entry.name elseif hidden then "???" else "?????",
		Position = UDim2.fromOffset(4, 76),
		Size = UDim2.new(1, -8, 0, 28),
		TextSize = 12,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if found then Theme.Text else Theme.TextMuted,
		Parent = card,
	})
	local footer = if hidden then "???"
		elseif found and entry.kind == "F" then string.format("%s · ×%s", rarity.name, Format.short((found :: Types.FishDiscovery).n))
		elseif found then string.format("%s · %s", rarity.name, (Conditions.list[(found :: Types.TreasureDiscovery).bc] or Conditions.list[1]).name)
		else rarity.name
	UIKit.label({
		Text = footer,
		Position = UDim2.fromOffset(4, 104),
		Size = UDim2.new(1, -8, 0, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if hidden then Theme.TextMuted else rarity.color,
		Parent = card,
	})
	if found and entry.kind == "F" and (found :: Types.FishDiscovery).x then
		UIKit.label({ Text = "👑", Position = UDim2.fromOffset(CARD.X - 24, 2), Size = UDim2.fromOffset(22, 22), TextSize = 16, Parent = card })
	end
end

local function refreshBrowser(browser: Browser)
	local data = ClientState.data
	if not data then
		return
	end
	for key, chip in browser.chips do
		local group = groupByKey(browser, key)
		local found, total = groupProgress(group)
		local selected = key == browser.groupKey
		chip.BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight
		chip.TextColor3 = if selected then Theme.TextDark else Theme.Text
		chip.Text = string.format("%s\n<font size=\"12\">%d / %d%s</font>", group.label, found, total, if found == total and total > 0 then "  ✅" else "")
	end
	for _, child in browser.grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local group = groupByKey(browser, browser.groupKey)
	for index, entry in group.entries do
		buildCard(browser, entry, index)
	end
	browser.builtFor = browser.groupKey
	if browser.selected and table.find(group.entries, browser.selected) == nil then
		browser.selected = nil
	end
	showDetail(browser)
end

local function buildBrowser(page: Frame, kind: string, groups: { Group }): Browser
	local chipColumn = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 160, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = chipColumn
	local grid = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(168, 0),
		Size = UDim2.new(1, -168 - 278, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.grid(UDim2.fromOffset(CARD.X, CARD.Y), UDim2.fromOffset(6, 6)).Parent = grid
	UIKit.padding(2).Parent = grid

	local pane = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 270, 1, 0), Parent = page })
	UIKit.corner(Theme.CornerSmall).Parent = pane
	local view = ItemViewport.new(pane, UDim2.new(1, -20, 0, 130), UDim2.fromOffset(10, 6))
	local mystery = UIKit.label({ Text = "❓", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 130), TextSize = 72, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, Parent = pane })
	local name = UIKit.label({ Text = "", Position = UDim2.fromOffset(12, 138), Size = UDim2.new(1, -24, 0, 26), Font = Theme.FontDisplay, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })
	local tags = UIKit.label({ Text = "", Position = UDim2.fromOffset(12, 164), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })
	local desc = UIKit.label({ Text = "", Position = UDim2.fromOffset(12, 186), Size = UDim2.new(1, -24, 0, 50), TextSize = 13, TextColor3 = Theme.TextMuted, TextYAlignment = Enum.TextYAlignment.Top, Parent = pane })
	local odds = UIKit.label({ Text = "", Position = UDim2.fromOffset(12, 238), Size = UDim2.new(1, -24, 0, 54), TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top, Parent = pane })
	local statsLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(12, 294), Size = UDim2.new(1, -24, 0, 54), TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top, Parent = pane })
	local chips = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 350), Size = UDim2.new(1, -24, 0, 74), Parent = pane })
	local chipLayout = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(78, 22), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }) :: UIGridLayout
	chipLayout.Parent = chips

	local browser: Browser = {
		kind = kind,
		groups = groups,
		groupKey = groups[1].key,
		selected = nil,
		chips = {},
		grid = grid,
		detail = { view = view, mystery = mystery, name = name, tags = tags, desc = desc, odds = odds, stats = statsLabel, chips = chips },
		builtFor = "",
	}
	for index, group in groups do
		local chip = UIKit.button({
			Text = group.label,
			Size = UDim2.new(1, -6, 0, 38),
			TextSize = 14,
			LayoutOrder = index,
			Parent = chipColumn,
		}, function()
			browser.groupKey = group.key
			browser.selected = nil
			refreshBrowser(browser)
		end, Theme.PanelLight)
		chip.RichText = true
		chip.TextWrapped = true
		browser.chips[group.key] = chip
	end
	return browser
end

---------------------------------------------------------------- sets

local function refreshSets()
	local data = ClientState.data
	if not data then
		return
	end
	for _, child in setsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, set in CollectionSets.list do
		local complete = data.Sets[set.id] == true
		local have = 0
		for _, itemId in set.items do
			if data.Discovered.Treasure[itemId] then
				have += 1
			end
		end
		local row = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.2, Size = UDim2.new(1, -10, 0, 92), LayoutOrder = (if complete then 100 else 0) + index, Parent = setsList })
		UIKit.corner(Theme.CornerSmall).Parent = row
		UIKit.stroke(if complete then set.color else Theme.Stroke, if complete then 2.5 else 1, 0).Parent = row
		UIKit.label({ Text = set.name, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -200, 0, 24), Font = Theme.FontBold, TextSize = 17, TextColor3 = set.color, Parent = row })
		UIKit.label({ Text = set.desc, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -200, 0, 18), TextSize = 12, TextColor3 = Theme.TextMuted, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = row })
		local bonus = if set.bonus.stat == "cargo"
			then string.format("+%d cargo slots", set.bonus.amount)
			else string.format("+%d%% %s", math.floor(set.bonus.amount * 100 + 0.5), set.bonus.stat)
		UIKit.label({
			Text = if complete then "✅ COMPLETE\n" .. bonus else string.format("%d / %d\nReward: %s", have, #set.items, bonus),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(180, 40),
			TextSize = 14,
			Font = Theme.FontBold,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if complete then Theme.Good else Theme.Text,
			Parent = row,
		})
		local items = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 30), Parent = row })
		UIKit.list(Enum.FillDirection.Horizontal, 6).Parent = items
		for itemIndex, itemId in set.items do
			local def = Treasure.byId[itemId]
			local has = data.Discovered.Treasure[itemId] ~= nil
			local rarity = Rarities.byId[def.rarity]
			local chip = UIKit.label({
				Text = if has then "✅ " .. def.name else "? " .. (if rarity.hidden then "???" else rarity.name .. " " .. (TreasureCategories.byId[def.category].name:match("^%S+") or "item")),
				Size = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = 12,
				Font = Theme.FontBold,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundTransparency = 0,
				BackgroundColor3 = if has then Theme.PanelLight else Theme.Panel,
				TextColor3 = if has then rarity.color else Theme.TextMuted,
				LayoutOrder = itemIndex,
				Parent = items,
			})
			UIKit.corner(UDim.new(0, 6)).Parent = chip
			UIKit.padding(0, 8, 0, 8).Parent = chip
		end
	end
end

---------------------------------------------------------------- milestone rewards

local function rewardText(milestone: IndexMath.MilestoneInfo): string
	local coins = milestone.coins * Stats.coinScale(IndexRewards.coinScale, milestone.scaleIndex)
	local text = "💰 " .. Format.short(coins)
	if milestone.luck > 0 then
		text ..= string.format(" + %d%% luck", math.floor(milestone.luck * 100 + 0.5))
	end
	return text
end

local function claimable(): number
	local data = ClientState.data
	if not data then
		return 0
	end
	local count = 0
	for _, milestone in IndexMath.milestones(IndexMath.completion(data.Discovered)) do
		if milestone.reached and not data.IndexClaimed[milestone.key] then
			count += 1
		end
	end
	return count
end

local function refreshRewards()
	local data = ClientState.data
	if not data then
		return
	end
	local completion = IndexMath.completion(data.Discovered)
	rewards.overall.set(completion.global.found / math.max(completion.global.total, 1), string.format("Whole Index  %s%%  ·  %d / %d", tostring(IndexMath.percent(completion.global)), completion.global.found, completion.global.total))
	for _, child in rewards.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local ready = 0
	local order = 0
	local function header(text: string)
		order += 1
		UIKit.label({ Text = text, Size = UDim2.new(1, -10, 0, 26), Font = Theme.FontDisplay, TextSize = 18, TextColor3 = Theme.Accent, LayoutOrder = order, Parent = rewards.list })
	end
	local lastSection = ""
	for _, milestone in IndexMath.milestones(completion) do
		local section = milestone.key:sub(1, 1)
		if section ~= lastSection then
			lastSection = section
			header(if section == "Z" then "🐟 Fish by zone" elseif section == "C" then "💰 Treasure by category" else "📖 Whole Index")
		end
		local progress: IndexMath.Progress
		if section == "Z" then
			progress = completion.zones[tonumber(milestone.key:match("^Z(%d+)_")) or 1]
		elseif section == "C" then
			progress = completion.categories[milestone.key:match("^C_(.-)_%d+$") or ""] or completion.global
		else
			progress = completion.global
		end
		local claimed = data.IndexClaimed[milestone.key] == true
		if milestone.reached and not claimed then
			ready += 1
		end
		order += 1
		local row = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, Size = UDim2.new(1, -10, 0, 42), LayoutOrder = order, Parent = rewards.list })
		UIKit.corner(Theme.CornerSmall).Parent = row
		UIKit.label({ Text = milestone.label, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(240, 42), TextSize = 15, Font = Theme.FontBold, Parent = row })
		local bar = UIKit.bar({ Position = UDim2.fromOffset(256, 12), Size = UDim2.fromOffset(200, 18), Parent = row }, if milestone.reached then Theme.Good else Theme.Accent)
		local pct = IndexMath.percent(progress)
		bar.set(math.min(pct / milestone.percent, 1), string.format("%s%% / %d%%", tostring(math.min(pct, milestone.percent)), milestone.percent))
		UIKit.label({ Text = rewardText(milestone), Position = UDim2.fromOffset(470, 0), Size = UDim2.fromOffset(190, 42), TextSize = 14, TextColor3 = Theme.Coin, Parent = row })
		UIKit.button({
			Text = if claimed then "Claimed ✅" elseif milestone.reached then "CLAIM" else "🔒",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(120, 32),
			TextSize = 15,
			Parent = row,
		}, function()
			if milestone.reached and not claimed then
				Net.event("ClaimIndex"):FireServer(milestone.key)
			end
		end, if milestone.reached and not claimed then Theme.Good else Theme.PanelLight)
	end
	rewards.claimAll.Text = if ready > 0 then string.format("CLAIM ALL (%d)", ready) else "Nothing to claim"
	rewards.claimAll.BackgroundColor3 = if ready > 0 then Theme.Good else Theme.PanelLight
end

local function buildRewards(page: Frame)
	local overall = UIKit.bar({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -220, 0, 28), Parent = page }, Theme.Accent)
	overall.label.TextSize = 15
	local claimAll = UIKit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(200, 36), TextSize = 16, Parent = page }, function()
		if claimable() > 0 then
			Net.event("ClaimIndex"):FireServer("*")
		end
	end, Theme.Good)
	local list = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 5).Parent = list
	rewards = { overall = overall, claimAll = claimAll, list = list }
end

---------------------------------------------------------------- window

local function refreshTitle()
	local data = ClientState.data
	if not data then
		return
	end
	local completion = IndexMath.completion(data.Discovered)
	window.title.Text = string.format("📖  INDEX  ·  %s%%", tostring(IndexMath.percent(completion.global)))
end

local function refresh()
	if not isOpen then
		return
	end
	refreshTitle()
	local tab = window.tab
	if tab == "Fish" then
		refreshBrowser(browsers.F)
	elseif tab == "Treasure" then
		refreshBrowser(browsers.T)
	elseif tab == "Sets" then
		refreshSets()
	else
		refreshRewards()
	end
end

-- Red dot on the menu bar while milestone rewards are waiting.
function IndexMenu.badge(): boolean
	return claimable() > 0
end

function IndexMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Index", "📖", { "Fish", "Treasure", "Sets", "Rewards" }, close)
	browsers.F = buildBrowser(window.pages.Fish, "F", fishGroups)
	browsers.T = buildBrowser(window.pages.Treasure, "T", treasureGroups)
	setsList = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window.pages.Sets,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = setsList
	buildRewards(window.pages.Rewards)
	window.TabChanged:Connect(refresh)
	ClientState.Changed:Connect(function(key)
		if key == "Discovered" or key == "IndexClaimed" or key == "Sets" or key == "Derived" or key == "*" then
			refresh()
		end
	end)
	ClientState.EventsChanged:Connect(function()
		if isOpen and (window.tab == "Fish" or window.tab == "Treasure") then
			local browser = if window.tab == "Fish" then browsers.F else browsers.T
			showDetail(browser)
		end
	end)
	return window
end

function IndexMenu.onOpen(_tab: string?, context: any?)
	if typeof(context) == "table" and typeof(context.kind) == "string" and typeof(context.id) == "string" then
		-- Jump straight to an entry (e.g. "View in Index" from a reveal)
		local browser = browsers[context.kind]
		if browser then
			for _, group in browser.groups do
				for _, entry in group.entries do
					if entry.id == context.id then
						browser.groupKey = group.key
						browser.selected = entry
					end
				end
			end
			window.setTab(if context.kind == "F" then "Fish" else "Treasure")
		end
	end
	isOpen = true
	refresh()
end

function IndexMenu.onClose()
	isOpen = false
end

return IndexMenu

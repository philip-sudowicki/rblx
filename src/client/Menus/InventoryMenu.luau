--!strict
-- Inventory: Fish / Treasure / Aquarium tabs. Sort (rarity, value, zone, category, newest),
-- filter chips, paged grid, a detail pane with a 3D preview, favourite / display / sell, and
-- Sell All that keeps favourites, displayed items and everything at or above your keep rarity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Rarities = require(Shared.Config.Rarities)
local Zones = require(Shared.Config.Zones)
local Treasure = require(Shared.Config.Treasure)
local Mutations = require(Shared.Config.Mutations)
local Conditions = require(Shared.Config.Conditions)
local Events = require(Shared.Config.Events)
local TreasureCategories = require(Shared.Config.TreasureCategories)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local Types = require(Shared.Modules.Types)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local ItemViewport = require(script.Parent.Parent.UI.ItemViewport)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local SubController = require(script.Parent.Parent.Controllers.SubController)

local InventoryMenu = {}

local PAGE_SIZE = 30
local SORTS: { [string]: { string } } = { F = { "Rarity", "Value", "Zone", "Newest", "Name" }, T = { "Rarity", "Value", "Category", "Newest", "Name" } }
local FILTERS = { "All", "⭐ Favourites", "🐠 Displayed", "🎉 Event", "✨ Mutated" }

type Page = {
	kind: string,
	grid: ScrollingFrame,
	sortButton: TextButton,
	filterButtons: { [string]: TextButton },
	setPager: (number, number) -> (),
	detail: {
		viewport: ItemViewport.ItemView,
		name: TextLabel,
		tags: TextLabel,
		stat: TextLabel,
		value: TextLabel,
		meta: TextLabel,
		favorite: TextButton,
		display: TextButton,
		sell: TextButton,
		empty: TextLabel,
	},
	storage: TextLabel,
	keepButton: TextButton,
	sellAll: TextButton,
	hint: TextLabel,
}

local window: Window.Window
local pages: { [string]: Page } = {}
local sortIndex: { [string]: number } = { F = 1, T = 1 }
local filter: { [string]: string } = { F = "All", T = "All" }
local pageIndex: { [string]: number } = { F = 1, T = 1 }
local selected: { [string]: number? } = { F = nil, T = nil }
local sellAt: Vector3? = nil
local isOpen = false

-- aquarium tab
local aquariumHeader: TextLabel
local aquariumIncome: TextLabel
local collectButton: TextButton
local tankGrid: Frame
local aquariumHint: TextLabel

local function canSell(): (boolean, string)
	if SubController.isDiving() then
		return false, "Surface first to sell."
	end
	if ClientState.hasPass("AutoSell") then
		return true, "Auto-Sell: you can sell anywhere on the dock."
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if sellAt and root and root:IsA("BasePart") and (root.Position - sellAt).Magnitude <= Game.Dock.SellRange then
		return true, "At the Fish Market."
	end
	return false, "Visit the Fish Market on the dock to sell."
end

local function priceOf(item: Types.Item): number
	return math.max(1, math.floor(item.v * ClientState.stats().sellMult + 0.5))
end

local function keepLabel(keep: number): string
	if keep > Rarities.count then
		return "Keep: nothing"
	end
	return string.format("Keep: %s+", Rarities.list[keep].name)
end

local function categoryOrder(item: Types.Item): number
	local def = Treasure.byId[item.i]
	local category = def and TreasureCategories.byId[def.category]
	return if category then category.order else 99
end

local function sortedItems(kind: string): { Types.Item }
	local out = {}
	local f = filter[kind]
	for _, item in ClientState.items() do
		if item.k == kind then
			local keep = f == "All"
				or (f == "⭐ Favourites" and item.f == true)
				or (f == "🐠 Displayed" and item.d ~= nil)
				or (f == "🎉 Event" and item.e ~= nil)
				or (f == "✨ Mutated" and item.m ~= nil)
			if keep then
				table.insert(out, item)
			end
		end
	end
	local mode = SORTS[kind][sortIndex[kind]]
	table.sort(out, function(a, b)
		if mode == "Value" then
			if a.v ~= b.v then
				return a.v > b.v
			end
		elseif mode == "Zone" then
			if a.z ~= b.z then
				return a.z < b.z
			end
		elseif mode == "Category" then
			local ca, cb = categoryOrder(a), categoryOrder(b)
			if ca ~= cb then
				return ca < cb
			end
		elseif mode == "Newest" then
			if a.t ~= b.t then
				return a.t > b.t
			end
		elseif mode == "Name" then
			local na, nb = ItemCard.name(a), ItemCard.name(b)
			if na ~= nb then
				return na < nb
			end
		end
		if a.r ~= b.r then
			return a.r > b.r
		end
		if a.v ~= b.v then
			return a.v > b.v
		end
		return a.u > b.u
	end)
	return out
end

local function showDetail(page: Page, item: Types.Item?)
	local d = page.detail
	local visible = item ~= nil
	local guis: { GuiObject } = { d.name, d.tags, d.stat, d.value, d.meta, d.favorite, d.display, d.sell }
	for _, gui in guis do
		gui.Visible = visible
	end
	d.viewport.frame.Visible = visible
	d.empty.Visible = not visible
	if not item then
		d.viewport.clear()
		return
	end
	local rarity = Rarities.list[item.r] or Rarities.list[1]
	d.viewport.set(item.k, item.i, { mutation = item.m, colossal = item.x })
	d.name.Text = ItemCard.name(item)
	d.name.TextColor3 = rarity.color
	local tags = { string.format('<font color="#%s">%s</font>', rarity.color:ToHex(), rarity.name) }
	if item.m and Mutations.byId[item.m] then
		local mutation = Mutations.byId[item.m]
		table.insert(tags, string.format('<font color="#%s">%s ×%d</font>', mutation.color:ToHex(), mutation.name, mutation.multiplier))
	end
	if item.x then
		table.insert(tags, '<font color="#FF9F43">Colossal ×5</font>')
	end
	if item.p then
		table.insert(tags, '<font color="#FFD24A">Perfect</font>')
	end
	d.tags.Text = table.concat(tags, " · ")
	if item.k == "F" then
		d.stat.Text = "⚖️ " .. Format.weight(item.w or 0)
	else
		local condition = Conditions.byId[item.c or "Worn"]
		local def = Treasure.byId[item.i]
		local category = def and TreasureCategories.byId[def.category]
		local cursed = if def and def.cursed then string.format('  <font color="#C77DFF">☠️ +%d%% O₂ drain</font>', math.floor(def.cursed * 100)) else ""
		d.stat.Text = string.format('%s %s · <font color="#%s">%s</font>%s', if category then category.icon else "", if category then category.name else "", condition.color:ToHex(), condition.name, cursed)
	end
	d.value.Text = "🪙 " .. Format.commas(priceOf(item))
	local zone = Zones.list[item.z]
	local event = item.e and Events.byId[item.e]
	d.meta.Text = string.format("From the %s%s\n%s", if zone then zone.name else "deep", if event then string.format(' · <font color="#%s">%s %s</font>', event.color:ToHex(), event.icon, event.name) else "", DateTime.fromUnixTimestamp(item.t):FormatLocalTime("ll", "en-us"))
	d.favorite.Text = if item.f then "⭐ Unfavourite" else "☆ Favourite"
	d.display.Text = if item.d then "Remove from Aquarium" else "🐠 Display"
	d.display.Visible = not item.g
	local sellOk = canSell()
	local sellable = sellOk and not item.f and item.d == nil and not item.g
	d.sell.Text = string.format("Sell · 🪙 %s", Format.short(priceOf(item)))
	d.sell.BackgroundColor3 = if sellable then Theme.Good else Theme.PanelLight
	d.sell.AutoButtonColor = sellable
end

local function refreshPage(kind: string)
	local page = pages[kind]
	if not page or not ClientState.data then
		return
	end
	local items = sortedItems(kind)
	local count = #items
	local totalPages = math.max(1, math.ceil(count / PAGE_SIZE))
	pageIndex[kind] = math.clamp(pageIndex[kind], 1, totalPages)
	page.setPager(pageIndex[kind], totalPages)
	for _, child in page.grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local first = (pageIndex[kind] - 1) * PAGE_SIZE + 1
	local selectedItem: Types.Item? = nil
	for i = first, math.min(count, first + PAGE_SIZE - 1) do
		local item = items[i]
		local card = ItemCard.new(item, priceOf(item), function()
			selected[kind] = item.u
			refreshPage(kind)
		end)
		card.LayoutOrder = i
		card.Parent = page.grid
		if selected[kind] == item.u then
			selectedItem = item
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.Accent
				stroke.Thickness = 4
			end
		end
	end
	if not selectedItem and selected[kind] then
		local data = ClientState.data
		local item = data.Inventory[tostring(selected[kind])]
		if item and item.k == kind then
			selectedItem = item
		else
			selected[kind] = nil
		end
	end
	showDetail(page, selectedItem)
	page.sortButton.Text = "Sort: " .. SORTS[kind][sortIndex[kind]] .. " ▾"
	for name, button in page.filterButtons do
		local active = filter[kind] == name
		button.BackgroundColor3 = if active then Theme.Accent else Theme.PanelLight
		button.TextColor3 = if active then Theme.TextDark else Theme.Text
	end
	local storage = ClientState.storageCount()
	page.storage.Text = string.format("Storage %d/%d", storage, Game.Economy.StorageCap)
	page.storage.TextColor3 = if storage >= Game.Economy.StorageCap then Theme.Bad elseif storage >= Game.Economy.StorageCap * 0.85 then Theme.Warn else Theme.TextMuted
	local keep = ClientState.data.Settings.SellKeep
	page.keepButton.Text = keepLabel(keep) .. " ▾"
	local sellCount, sellCoins = 0, 0
	for _, item in ClientState.items() do
		if not item.f and item.d == nil and not item.g and item.r < keep then
			sellCount += 1
			sellCoins += priceOf(item)
		end
	end
	local ok, hint = canSell()
	page.sellAll.Text = if sellCount > 0 then string.format("SELL ALL · %d · 🪙 %s", sellCount, Format.short(sellCoins)) else "Nothing to sell"
	page.sellAll.BackgroundColor3 = if ok and sellCount > 0 then Theme.Good else Theme.PanelLight
	page.hint.Text = hint
	page.hint.TextColor3 = if ok then Theme.Good else Theme.Warn
end

local function buildItemsPage(parentPage: Frame, kind: string)
	local toolbar = UIKit.frame({ BackgroundTransparency = 1, Size = UDim2.new(0, 560, 0, 34), Parent = parentPage })
	UIKit.list(Enum.FillDirection.Horizontal, 6).Parent = toolbar
	local page: Page
	local sortButton = UIKit.button({ Size = UDim2.fromOffset(130, 32), TextSize = 14, LayoutOrder = 0, Parent = toolbar }, function()
		sortIndex[kind] = sortIndex[kind] % #SORTS[kind] + 1
		refreshPage(kind)
	end, Theme.PanelLight)
	local filterButtons: { [string]: TextButton } = {}
	for index, name in FILTERS do
		filterButtons[name] = UIKit.button({ Text = name, Size = UDim2.fromOffset(if index == 1 then 44 else 88, 32), TextSize = 12, LayoutOrder = index, Parent = toolbar }, function()
			filter[kind] = name
			pageIndex[kind] = 1
			refreshPage(kind)
		end, Theme.PanelLight)
	end
	local grid = UIKit.new("ScrollingFrame", {
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.fromOffset(560, 300),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parentPage,
	}) :: ScrollingFrame
	UIKit.corner(Theme.CornerSmall).Parent = grid
	UIKit.padding(8).Parent = grid
	UIKit.grid(ItemCard.SIZE, UDim2.fromOffset(9, 9)).Parent = grid
	local _, setPager = Window.pager(parentPage, UDim2.fromOffset(170, 346), function(delta)
		pageIndex[kind] += delta
		refreshPage(kind)
	end)

	-- detail pane
	local pane = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.3, Position = UDim2.fromOffset(572, 0), Size = UDim2.new(1, -572, 0, 380), Parent = parentPage })
	UIKit.corner(Theme.CornerSmall).Parent = pane
	local viewport = ItemViewport.new(pane, UDim2.new(1, -20, 0, 130), UDim2.fromOffset(10, 6))
	local name = UIKit.label({ Text = "", Position = UDim2.fromOffset(10, 138), Size = UDim2.new(1, -20, 0, 28), Font = Theme.FontDisplay, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Parent = pane })
	local tags = UIKit.label({ Text = "", Position = UDim2.fromOffset(10, 166), Size = UDim2.new(1, -20, 0, 20), Font = Theme.FontBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })
	local stat = UIKit.label({ Text = "", Position = UDim2.fromOffset(10, 188), Size = UDim2.new(1, -20, 0, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })
	local value = UIKit.label({ Text = "", Position = UDim2.fromOffset(10, 210), Size = UDim2.new(1, -20, 0, 30), Font = Theme.FontDisplay, TextSize = 26, TextColor3 = Theme.Coin, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })
	local meta = UIKit.label({ Text = "", Position = UDim2.fromOffset(10, 240), Size = UDim2.new(1, -20, 0, 36), TextSize = 12, TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Parent = pane })
	local favorite = UIKit.button({ Position = UDim2.fromOffset(10, 280), Size = UDim2.new(0.5, -14, 0, 38), TextSize = 14, Parent = pane }, function()
		local uid = selected[kind]
		local item = uid and ClientState.data.Inventory[tostring(uid)]
		if item then
			Net.event("Favorite"):FireServer(item.u, not item.f)
		end
	end, Theme.PanelLight)
	local display = UIKit.button({ Position = UDim2.new(0.5, 4, 0, 280), Size = UDim2.new(0.5, -14, 0, 38), TextSize = 14, Parent = pane }, function()
		local uid = selected[kind]
		local item = uid and ClientState.data.Inventory[tostring(uid)]
		if item then
			Net.event(if item.d then "Undisplay" else "Display"):FireServer(item.u)
		end
	end, Theme.PanelLight)
	local sell = UIKit.button({ Position = UDim2.fromOffset(10, 326), Size = UDim2.new(1, -20, 0, 44), TextSize = 17, Parent = pane }, function()
		local uid = selected[kind]
		local item = uid and ClientState.data.Inventory[tostring(uid)]
		if item and canSell() and not item.f and item.d == nil and not item.g then
			Net.event("Sell"):FireServer({ item.u })
			selected[kind] = nil
		end
	end, Theme.Good)
	local empty = UIKit.label({ Text = "Select an item to see it up close.", Position = UDim2.fromOffset(10, 150), Size = UDim2.new(1, -20, 0, 60), TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, Parent = pane })

	-- bottom bar
	local storage = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 390), Size = UDim2.fromOffset(160, 36), Font = Theme.FontBold, TextSize = 15, Parent = parentPage })
	local keepButton = UIKit.button({ Position = UDim2.fromOffset(170, 390), Size = UDim2.fromOffset(180, 36), TextSize = 14, Parent = parentPage }, function()
		local data = ClientState.data
		local keep = data.Settings.SellKeep + 1
		if keep > Rarities.count + 1 then
			keep = 2
		end
		ClientState.setSetting("SellKeep", keep)
		refreshPage(kind)
	end, Theme.PanelLight)
	local sellAll = UIKit.button({ Position = UDim2.fromOffset(360, 390), Size = UDim2.fromOffset(300, 36), TextSize = 15, Parent = parentPage }, function()
		local ok = canSell()
		if ok then
			Net.event("SellAll"):FireServer(ClientState.data.Settings.SellKeep)
		end
	end, Theme.Good)
	local hint = UIKit.label({ Text = "", Position = UDim2.fromOffset(670, 390), Size = UDim2.new(1, -670, 0, 36), TextSize = 13, TextWrapped = true, Parent = parentPage })

	page = {
		kind = kind,
		grid = grid,
		sortButton = sortButton,
		filterButtons = filterButtons,
		setPager = setPager,
		detail = { viewport = viewport, name = name, tags = tags, stat = stat, value = value, meta = meta, favorite = favorite, display = display, sell = sell, empty = empty },
		storage = storage,
		keepButton = keepButton,
		sellAll = sellAll,
		hint = hint,
	}
	pages[kind] = page
end

local function refreshAquarium()
	local data = ClientState.data
	if not data then
		return
	end
	local stats = ClientState.stats()
	local plot = Players.LocalPlayer:GetAttribute("PlotIndex")
	aquariumHeader.Text = if typeof(plot) == "number" and plot > 0 then string.format("🐠 Your Aquarium · Plot #%d", plot) else "🐠 Your Aquarium"
	local perMinute = 0
	for slot, uid in data.Aquarium.Slots do
		local item = data.Inventory[tostring(uid)]
		if item and (tonumber(slot) or 99) <= stats.displaySlots then
			perMinute += item.v * Game.Aquarium.IncomePerMinute
		end
	end
	aquariumIncome.Text = string.format("Earning 🪙 %s / hour  ·  %s ready to collect", Format.short(perMinute * 60), Format.short(math.floor(data.Aquarium.Pending)))
	collectButton.Text = string.format("Collect 🪙 %s", Format.short(math.floor(data.Aquarium.Pending)))
	for _, child in tankGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index = 1, 14 do
		local uid = data.Aquarium.Slots[tostring(index)]
		local item = if uid then data.Inventory[tostring(uid)] else nil
		if index > stats.displaySlots then
			local locked = UIKit.label({ Text = "🔒\nLocked", Size = ItemCard.SIZE, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.TextMuted, BackgroundTransparency = 0.3, BackgroundColor3 = Theme.PanelDark, LayoutOrder = index, Parent = tankGrid })
			UIKit.corner(Theme.CornerSmall).Parent = locked
		elseif item then
			local card = ItemCard.new(item, math.floor(item.v * Game.Aquarium.IncomePerMinute * 60), function()
				Net.event("Undisplay"):FireServer(item.u)
			end)
			card.LayoutOrder = index
			card.Parent = tankGrid
		else
			local empty = UIKit.label({ Text = "Empty tank", Size = ItemCard.SIZE, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.TextMuted, BackgroundTransparency = 0.5, BackgroundColor3 = Theme.PanelDark, LayoutOrder = index, Parent = tankGrid })
			UIKit.corner(Theme.CornerSmall).Parent = empty
		end
	end
	aquariumHint.Text = string.format(
		"Display fish or treasure from the other tabs (🐠 Display). Each earns %s%% of its value per minute, even while you're offline (up to %dh). Click a tank to take its item back. Tanks: %d/14 - more with the Extra Aquarium Tanks pass or the Bigger Aquarium perk.",
		tostring(Game.Aquarium.IncomePerMinute * 100),
		Game.Aquarium.OfflineCapHours,
		stats.displaySlots
	)
end

local function buildAquariumPage(page: Frame)
	aquariumHeader = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Font = Theme.FontDisplay, TextSize = 24, Parent = page })
	aquariumIncome = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -240, 0, 24), TextSize = 16, TextColor3 = Theme.Coin, Parent = page })
	collectButton = UIKit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(220, 44), TextSize = 17, Parent = page }, function()
		Net.event("CollectAquarium"):FireServer()
	end, Theme.Good)
	tankGrid = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 250), Parent = page })
	UIKit.grid(ItemCard.SIZE, UDim2.fromOffset(9, 9)).Parent = tankGrid
	aquariumHint = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 320), Size = UDim2.new(1, 0, 0, 70), TextSize = 14, TextColor3 = Theme.TextMuted, TextYAlignment = Enum.TextYAlignment.Top, Parent = page })
end

local function refreshAll()
	if not isOpen then
		return
	end
	if window.tab == "Fish" then
		refreshPage("F")
	elseif window.tab == "Treasure" then
		refreshPage("T")
	else
		refreshAquarium()
	end
end

function InventoryMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Inventory", "🎒", { "Fish", "Treasure", "Aquarium" }, close)
	buildItemsPage(window.pages.Fish, "F")
	buildItemsPage(window.pages.Treasure, "T")
	buildAquariumPage(window.pages.Aquarium)
	window.TabChanged:Connect(refreshAll)
	ClientState.InventoryChanged:Connect(refreshAll)
	ClientState.Changed:Connect(function(key)
		if key == "Aquarium" or key == "Derived" or key == "Settings" or key == "*" then
			refreshAll()
		end
	end)
	return window
end

function InventoryMenu.onOpen(_tab: string?, context: any?)
	isOpen = true
	if typeof(context) == "table" and typeof(context.sellAt) == "Vector3" then
		sellAt = context.sellAt
	end
	refreshAll()
end

function InventoryMenu.onClose()
	isOpen = false
	for _, page in pages do
		page.detail.viewport.clear()
	end
end

return InventoryMenu

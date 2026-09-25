--!strict
-- Upgrades: buy the 8 sub upgrades (clear before » after stats), pick skins in the Hangar, and
-- Resurface (rebirth) with its requirement checklist, rewards and token perk shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Upgrades = require(Shared.Config.Upgrades)
local Rebirth = require(Shared.Config.Rebirth)
local Skins = require(Shared.Config.Skins)
local Achievements = require(Shared.Config.Achievements)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local SubController = require(script.Parent.Parent.Controllers.SubController)

local UpgradesMenu = {}

local window: Window.Window
local isOpen = false
local rows: { [string]: { level: TextLabel, stat: TextLabel, buy: TextButton } } = {}
local skinGrid: ScrollingFrame
local resurface: {
	requirements: TextLabel,
	rewards: TextLabel,
	button: TextButton,
	tokens: TextLabel,
	perkList: ScrollingFrame,
}

local function formatStat(upgrade: Upgrades.Upgrade, level: number): string
	local value = Stats.upgradeValue(upgrade.id, level)
	if upgrade.id == "Hull" then
		return Format.meters(value)
	elseif upgrade.id == "Oxygen" then
		return string.format("%ds", value)
	elseif upgrade.id == "Engine" then
		return string.format("%d spd", value)
	elseif upgrade.id == "Lights" then
		return string.format("%d studs", value)
	elseif upgrade.id == "Sonar" then
		local cooldown = (upgrade.cooldown :: { number })[level]
		return string.format("%d studs / %ds", value, cooldown)
	elseif upgrade.id == "Cargo" then
		return string.format("%d slots", value)
	elseif upgrade.id == "Claw" then
		local speed = (upgrade.speed :: { number })[level]
		return string.format("Tier %d · %.2fx", value, speed)
	elseif upgrade.id == "Luck" then
		return string.format("+%d%%", value)
	end
	return tostring(value)
end

local function refreshUpgrades()
	local data = ClientState.data
	if not data then
		return
	end
	local diving = SubController.isDiving()
	for _, upgrade in Upgrades.list do
		local row = rows[upgrade.id]
		local level = Stats.level(data.Upgrades, upgrade.id)
		local max = #upgrade.values
		row.level.Text = string.format("Lv %d/%d", level, max)
		if level >= max then
			row.stat.Text = formatStat(upgrade, level) .. "  (MAX)"
			row.buy.Text = "MAXED"
			row.buy.BackgroundColor3 = Theme.PanelLight
		else
			row.stat.Text = string.format('%s  »  <font color="#50E68C"><b>%s</b></font>', formatStat(upgrade, level), formatStat(upgrade, level + 1))
			local cost = Stats.upgradeCost(upgrade.id, level + 1)
			local affordable = data.Coins >= cost and not diving
			row.buy.Text = "💰 " .. Format.short(cost)
			row.buy.BackgroundColor3 = if affordable then Theme.Good else Theme.PanelLight
		end
	end
end

local function buildUpgrades(page: Frame)
	local list = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = list
	for index, upgrade in Upgrades.list do
		local row = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, Size = UDim2.new(1, -10, 0, 50), LayoutOrder = index, Parent = list })
		UIKit.corner(Theme.CornerSmall).Parent = row
		UIKit.label({ Text = upgrade.icon, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 50), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		UIKit.label({ Text = upgrade.name, Position = UDim2.fromOffset(54, 4), Size = UDim2.fromOffset(200, 22), Font = Theme.FontBold, TextSize = 17, Parent = row })
		UIKit.label({ Text = upgrade.desc, Position = UDim2.fromOffset(54, 26), Size = UDim2.fromOffset(330, 20), TextSize = 12, TextColor3 = Theme.TextMuted, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = row })
		local level = UIKit.label({ Text = "", Position = UDim2.fromOffset(390, 0), Size = UDim2.fromOffset(80, 50), Font = Theme.FontBold, TextSize = 15, TextColor3 = Theme.Accent, Parent = row })
		local stat = UIKit.label({ Text = "", Position = UDim2.fromOffset(470, 0), Size = UDim2.fromOffset(230, 50), TextSize = 15, Parent = row })
		local buy = UIKit.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(140, 38), TextSize = 16, Parent = row }, function()
			Net.event("BuyUpgrade"):FireServer(upgrade.id)
		end, Theme.Good)
		rows[upgrade.id] = { level = level, stat = stat, buy = buy }
	end
end

local function skinRequirement(skin: Skins.Skin): string
	if skin.source == "pass" then
		return "VIP game pass"
	elseif skin.source == "rebirth" then
		return "Resurface shop"
	end
	for _, achievement in Achievements.list do
		if achievement.skin == skin.id then
			return achievement.desc
		end
	end
	return skin.desc
end

local function refreshSkins()
	local data = ClientState.data
	if not data then
		return
	end
	for _, child in skinGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, skin in Skins.list do
		local owned = data.Skins.Owned[skin.id] == true
		local equipped = data.Skins.Equipped == skin.id
		local card = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.2, Size = UDim2.fromOffset(200, 150), LayoutOrder = skin.order, Parent = skinGrid })
		UIKit.corner(Theme.CornerSmall).Parent = card
		UIKit.stroke(if equipped then Theme.Accent else Theme.Stroke, if equipped then 3 else 1.5, 0).Parent = card
		local swatches = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 50), Parent = card })
		UIKit.list(Enum.FillDirection.Horizontal, 4).Parent = swatches
		for i, color in { skin.body, skin.accent, skin.trim, skin.glow } do
			local swatch = UIKit.frame({ BackgroundColor3 = color, Size = UDim2.fromOffset(if i == 1 then 70 else 30, 50), LayoutOrder = i, Parent = swatches })
			UIKit.corner(UDim.new(0, 8)).Parent = swatch
		end
		UIKit.label({ Text = skin.name, Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 22), Font = Theme.FontBold, TextSize = 16, Parent = card })
		UIKit.label({ Text = if owned then "Unlocked" else "🔒 " .. skinRequirement(skin), Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 0, 20), TextSize = 12, TextColor3 = if owned then Theme.Good else Theme.TextMuted, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = card })
		UIKit.button({
			Text = if equipped then "Equipped" elseif owned then "Equip" else "Locked",
			Position = UDim2.fromOffset(10, 110),
			Size = UDim2.new(1, -20, 0, 32),
			TextSize = 15,
			Parent = card,
		}, function()
			if owned and not equipped then
				Net.event("EquipSkin"):FireServer(skin.id)
			end
		end, if owned and not equipped then Theme.Accent else Theme.PanelLight)
	end
end

local function refreshResurface()
	local data = ClientState.data
	if not data then
		return
	end
	local cost = Stats.rebirthCost(data.Rebirths)
	local depthOk = data.Stats.DeepestMeters >= Rebirth.minDeepestMeters
	local coinsOk = data.Coins >= cost
	resurface.requirements.Text = string.format(
		"%s Reach the Hadal Trench (%s)  ·  deepest: %s\n%s Hold %s coins  ·  you have %s",
		if depthOk then "✅" else "🔲",
		Format.meters(Rebirth.minDeepestMeters),
		Format.meters(data.Stats.DeepestMeters),
		if coinsOk then "✅" else "🔲",
		Format.short(cost),
		Format.short(data.Coins)
	)
	local nextCount = data.Rebirths + 1
	resurface.rewards.Text = string.format(
		"Resets coins and upgrades. Keeps items, Index, aquarium, skins and quests.\nRewards: sell value x%s » <b>x%s</b> · <b>+%d</b> rebirth tokens%s · a rebirth badge on your nametag",
		tostring(1 + data.Rebirths * Rebirth.sellMultiplierPerRebirth),
		tostring(1 + nextCount * Rebirth.sellMultiplierPerRebirth),
		Stats.rebirthTokens(nextCount),
		if data.Rebirths < Rebirth.riftUnlockRebirths then " · <b>opens The Rift</b>" else ""
	)
	local ready = depthOk and coinsOk and not SubController.isDiving()
	resurface.button.BackgroundColor3 = if ready then Theme.Accent else Theme.PanelLight
	resurface.button.Text = if ready then "🔱 RESURFACE" else "Not ready yet"
	resurface.tokens.Text = string.format("🔱 %d rebirth tokens", data.Tokens)
	for _, child in resurface.perkList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, perk in Rebirth.perks do
		local level = data.Perks[perk.id] or 0
		local max = #perk.costs
		local row = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.25, Size = UDim2.new(1, -10, 0, 46), LayoutOrder = index, Parent = resurface.perkList })
		UIKit.corner(Theme.CornerSmall).Parent = row
		UIKit.label({ Text = perk.icon, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(34, 46), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		UIKit.label({ Text = string.format("<b>%s</b>  Lv %d/%d", perk.name, level, max), Position = UDim2.fromOffset(44, 2), Size = UDim2.new(1, -170, 0, 22), TextSize = 15, Parent = row })
		UIKit.label({ Text = perk.desc, Position = UDim2.fromOffset(44, 23), Size = UDim2.new(1, -170, 0, 20), TextSize = 12, TextColor3 = Theme.TextMuted, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = row })
		local maxed = level >= max
		local perkCost = if maxed then 0 else perk.costs[level + 1]
		UIKit.button({
			Text = if maxed then "MAX" else string.format("🔱 %d", perkCost),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(110, 34),
			TextSize = 15,
			Parent = row,
		}, function()
			if not maxed then
				Net.event("BuyPerk"):FireServer(perk.id)
			end
		end, if not maxed and data.Tokens >= perkCost then Theme.Accent else Theme.PanelLight)
	end
end

local function buildResurface(page: Frame)
	local left = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.3, Size = UDim2.new(0.5, -6, 1, 0), Parent = page })
	UIKit.corner(Theme.CornerSmall).Parent = left
	UIKit.padding(12).Parent = left
	UIKit.label({ Text = "🔱 RESURFACE", Font = Theme.FontDisplay, TextSize = 26, TextColor3 = Theme.Token, Size = UDim2.new(1, 0, 0, 32), Parent = left })
	local requirements = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 64), TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top, Parent = left })
	local rewards = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 130), TextSize = 14, TextColor3 = Theme.TextMuted, TextYAlignment = Enum.TextYAlignment.Top, Parent = left })
	local button = UIKit.button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 56), Font = Theme.FontDisplay, TextSize = 26, Parent = left }, function()
		local data = ClientState.data
		if not data then
			return
		end
		Window.confirm(page, "Resurface?", string.format("You'll lose your coins and upgrades (Lv 1 again), and gain x%s sell value and %d tokens forever. Ready?", tostring(1 + (data.Rebirths + 1) * Rebirth.sellMultiplierPerRebirth), Stats.rebirthTokens(data.Rebirths + 1)), "RESURFACE", function()
			Net.event("Rebirth"):FireServer()
		end)
	end, Theme.Accent)
	local right = UIKit.frame({ BackgroundTransparency = 1, Position = UDim2.new(0.5, 6, 0, 0), Size = UDim2.new(0.5, -6, 1, 0), Parent = page })
	local tokens = UIKit.label({ Text = "", Size = UDim2.new(1, 0, 0, 28), Font = Theme.FontDisplay, TextSize = 22, TextColor3 = Theme.Token, Parent = right })
	local perkList = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = right,
	}) :: ScrollingFrame
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = perkList
	resurface = { requirements = requirements, rewards = rewards, button = button, tokens = tokens, perkList = perkList }
end

local function refresh()
	if not isOpen then
		return
	end
	if window.tab == "Upgrades" then
		refreshUpgrades()
	elseif window.tab == "Hangar" then
		refreshSkins()
	else
		refreshResurface()
	end
end

function UpgradesMenu.build(parent: Instance, close: () -> ()): Window.Window
	window = Window.new(parent, "Upgrades", "🛠️", { "Upgrades", "Hangar", "Resurface" }, close)
	buildUpgrades(window.pages.Upgrades)
	skinGrid = UIKit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window.pages.Hangar,
	}) :: ScrollingFrame
	UIKit.grid(UDim2.fromOffset(200, 150), UDim2.fromOffset(10, 10)).Parent = skinGrid
	buildResurface(window.pages.Resurface)
	window.TabChanged:Connect(refresh)
	ClientState.Changed:Connect(refresh)
	return window
end

function UpgradesMenu.onOpen()
	isOpen = true
	refresh()
end

function UpgradesMenu.onClose()
	isOpen = false
end

return UpgradesMenu

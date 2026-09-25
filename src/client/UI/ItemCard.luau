--!strict
-- A compact inventory card: rarity-coloured frame, glyph, name, value and small badges
-- (favourite, on display, in cargo, event, mutation).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Mutations = require(Shared.Config.Mutations)
local TreasureCategories = require(Shared.Config.TreasureCategories)
local Format = require(Shared.Modules.Format)
local Types = require(Shared.Modules.Types)
local UIKit = require(script.Parent.UIKit)

local ItemCard = {}

ItemCard.SIZE = UDim2.fromOffset(96, 116)

function ItemCard.glyph(item: Types.Item): string
	if item.k == "F" then
		local def = Fish.byId[item.i]
		local shape = if def then def.model.shape else "Classic"
		if shape == "Jelly" then
			return "🎐"
		elseif shape == "Squid" then
			return "🦑"
		elseif shape == "Crab" then
			return "🦀"
		elseif shape == "Shark" then
			return "🦈"
		elseif shape == "Whale" then
			return "🐋"
		elseif shape == "Puffer" then
			return "🐡"
		elseif shape == "Flat" or shape == "Tall" then
			return "🐠"
		elseif shape == "Eel" or shape == "Seahorse" then
			return "🐍"
		elseif shape == "Crystal" then
			return "💠"
		elseif shape == "Duck" then
			return "🦆"
		end
		return "🐟"
	end
	local def = Treasure.byId[item.i]
	local category = def and TreasureCategories.byId[def.category]
	return if category then category.icon else "💎"
end

function ItemCard.name(item: Types.Item): string
	local def: any = if item.k == "F" then Fish.byId[item.i] else Treasure.byId[item.i]
	return if def then def.name else item.i
end

function ItemCard.new(item: Types.Item, price: number, onClick: (() -> ())?): TextButton
	local rarity = Rarities.list[item.r] or Rarities.list[1]
	local card = UIKit.new("TextButton", {
		Size = ItemCard.SIZE,
		BackgroundColor3 = Theme.PanelDark,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}) :: TextButton
	UIKit.corner(Theme.CornerSmall).Parent = card
	local stroke = UIKit.stroke(rarity.color, 2, 0.1)
	stroke.Parent = card
	local band = UIKit.frame({ BackgroundColor3 = rarity.color, BackgroundTransparency = 0.55, Size = UDim2.new(1, 0, 0, 70), Parent = card })
	UIKit.corner(Theme.CornerSmall).Parent = band
	UIKit.rarityGradient(band, rarity.index)
	UIKit.label({ Text = ItemCard.glyph(item), Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 6), TextSize = 38, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	local name = UIKit.label({
		Text = ItemCard.name(item),
		Position = UDim2.fromOffset(4, 70),
		Size = UDim2.new(1, -8, 0, 24),
		TextSize = 12,
		Font = Theme.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		Parent = card,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 14, Parent = name })
	UIKit.label({ Text = "💰 " .. Format.short(price), Position = UDim2.fromOffset(4, 94), Size = UDim2.new(1, -8, 0, 18), TextSize = 13, Font = Theme.FontBold, TextColor3 = Theme.Coin, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	local badges = {}
	if item.f then
		table.insert(badges, "⭐")
	end
	if item.g then
		table.insert(badges, "📦")
	end
	if item.e then
		table.insert(badges, "🎉")
	end
	if #badges > 0 then
		UIKit.label({ Text = table.concat(badges, ""), Position = UDim2.fromOffset(4, 2), Size = UDim2.new(1, -8, 0, 18), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	end
	if item.m and Mutations.byId[item.m] then
		local mutation = Mutations.byId[item.m]
		local tag = UIKit.label({
			Text = mutation.name:upper(),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 3),
			Size = UDim2.fromOffset(60, 14),
			TextSize = 10,
			Font = Theme.FontBold,
			TextColor3 = Theme.TextDark,
			BackgroundColor3 = mutation.color,
			BackgroundTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = card,
		})
		UIKit.corner(UDim.new(0, 4)).Parent = tag
	end
	if item.x then
		UIKit.label({ Text = "COLOSSAL", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), TextSize = 10, Font = Theme.FontBold, TextColor3 = Color3.fromRGB(255, 160, 70), TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	card.MouseEnter:Connect(function()
		stroke.Thickness = 3
	end)
	card.MouseLeave:Connect(function()
		stroke.Thickness = 2
	end)
	card.SelectionGained:Connect(function()
		stroke.Thickness = 3
	end)
	card.SelectionLost:Connect(function()
		stroke.Thickness = 2
	end)
	return card
end

return ItemCard

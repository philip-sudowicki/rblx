--!strict
-- Treasure categories. `icon` is an emoji glyph (renders on every platform, no uploads needed).
-- deepOnly categories only appear from `minZone` down.

export type Category = {
	id: string,
	name: string,
	icon: string,
	color: Color3,
	desc: string,
	minZone: number,
	order: number,
}

local list: { Category } = {
	{
		id = "Coins",
		name = "Coins & Currency",
		icon = "💰",
		color = Color3.fromRGB(255, 205, 80),
		desc = "Doubloons, ancient mint coins and forgotten fortunes.",
		minZone = 1,
		order = 1,
	},
	{
		id = "Jewelry",
		name = "Jewelry & Gems",
		icon = "💎",
		color = Color3.fromRGB(110, 220, 255),
		desc = "Rings, crowns and raw gemstones.",
		minZone = 1,
		order = 2,
	},
	{
		id = "Relics",
		name = "Relics & Artifacts",
		icon = "🗿",
		color = Color3.fromRGB(210, 170, 120),
		desc = "Idols, statues and tablets of drowned cultures.",
		minZone = 1,
		order = 3,
	},
	{
		id = "Salvage",
		name = "Ship Salvage",
		icon = "⚓",
		color = Color3.fromRGB(160, 190, 210),
		desc = "Anchors, compasses and figureheads from lost ships.",
		minZone = 1,
		order = 4,
	},
	{
		id = "Tech",
		name = "Ancient Tech",
		icon = "⚙️",
		color = Color3.fromRGB(90, 255, 200),
		desc = "Strange devices from lost civilizations. Deep zones only.",
		minZone = 4,
		order = 5,
	},
	{
		id = "Cursed",
		name = "Cursed Items",
		icon = "☠️",
		color = Color3.fromRGB(190, 80, 255),
		desc = "Worth a fortune, but carrying them drains your oxygen faster.",
		minZone = 3,
		order = 6,
	},
}

local byId: { [string]: Category } = {}
for _, category in list do
	byId[category.id] = category
end

return {
	list = list,
	byId = byId,
}

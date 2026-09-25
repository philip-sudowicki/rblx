--!strict
-- Rebirth ("Resurface").
--
-- Requirements: have reached minDeepestMeters at least once AND hold coinsBase × coinsGrowth^n
-- coins, where n = rebirths already done. Resurfacing resets coins and upgrades (to level 1 +
-- any Reinforced perks) and keeps inventory, index, aquarium, skins, quests and stats.
-- Rewards: permanent sell multiplier, tokens for the Resurface shop, The Rift (first rebirth),
-- a rebirth badge on your nametag and in chat.

export type Perk = {
	id: string,
	name: string,
	icon: string,
	desc: string,
	stat: string, -- luck | sell | oxygen | clawSpeed | minigame | tanks | sonar | startLevels | skin
	perLevel: number,
	costs: { number }, -- token cost per level (#costs = max level)
	skin: string?,
}

local perks: { Perk } = {
	{
		id = "LuckyCharm",
		name = "Lucky Charm",
		icon = "🍀",
		desc = "+5% luck per level, forever.",
		stat = "luck",
		perLevel = 0.05,
		costs = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
	},
	{
		id = "SilverTongue",
		name = "Silver Tongue",
		icon = "💰",
		desc = "+5% sell value per level.",
		stat = "sell",
		perLevel = 0.05,
		costs = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 },
	},
	{
		id = "ReinforcedFrame",
		name = "Reinforced Frame",
		icon = "🛠️",
		desc = "After each rebirth, every upgrade starts 1 level higher per level of this perk.",
		stat = "startLevels",
		perLevel = 1,
		costs = { 2, 3, 4, 5, 6 },
	},
	{
		id = "DeepLungs",
		name = "Deep Lungs",
		icon = "💨",
		desc = "+8% oxygen capacity per level.",
		stat = "oxygen",
		perLevel = 0.08,
		costs = { 1, 2, 2, 3, 3 },
	},
	{
		id = "SteadyHands",
		name = "Steady Hands",
		icon = "🎯",
		desc = "+6% wider green zone in the catch minigame per level.",
		stat = "minigame",
		perLevel = 0.06,
		costs = { 1, 2, 2, 3, 3 },
	},
	{
		id = "QuickClaw",
		name = "Quick Claw",
		icon = "🧲",
		desc = "+8% salvage speed per level.",
		stat = "clawSpeed",
		perLevel = 0.08,
		costs = { 1, 2, 2, 3, 3 },
	},
	{
		id = "BigTanks",
		name = "Bigger Aquarium",
		icon = "🐠",
		desc = "+1 aquarium tank per level.",
		stat = "tanks",
		perLevel = 1,
		costs = { 2, 3, 4, 5 },
	},
	{
		id = "EchoSense",
		name = "Echo Sense",
		icon = "📡",
		desc = "+10% sonar range per level.",
		stat = "sonar",
		perLevel = 0.10,
		costs = { 1, 2, 2, 3, 3 },
	},
	{
		id = "PhoenixSkin",
		name = "Phoenix Hull",
		icon = "🔥",
		desc = "Unlocks the Phoenix submarine skin.",
		stat = "skin",
		perLevel = 1,
		costs = { 5 },
		skin = "Phoenix",
	},
}

local perksById: { [string]: Perk } = {}
for _, perk in perks do
	perksById[perk.id] = perk
end

return {
	minDeepestMeters = 6000, -- must have reached the Hadal Trench
	coinsBase = 60000000, -- coins required for the first rebirth
	coinsGrowth = 3, -- each rebirth costs 3× the previous one
	sellMultiplierPerRebirth = 0.5, -- +50% sell value per rebirth (additive: 1.5×, 2×, 2.5×…)
	baseTokens = 3, -- tokens awarded per rebirth = baseTokens + rebirthNumber
	riftUnlockRebirths = 1,
	perks = perks,
	perksById = perksById,
	-- Nametag badge shown at rebirth counts (highest matching entry wins)
	badges = {
		{ at = 1, text = "⭐", color = Color3.fromRGB(120, 220, 255) },
		{ at = 3, text = "⭐⭐", color = Color3.fromRGB(150, 255, 170) },
		{ at = 5, text = "⭐⭐⭐", color = Color3.fromRGB(255, 210, 80) },
		{ at = 10, text = "💠", color = Color3.fromRGB(255, 110, 220) },
		{ at = 25, text = "💠💠", color = Color3.fromRGB(255, 80, 80) },
	},
}

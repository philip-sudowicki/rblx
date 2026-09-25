--!strict
-- Monetization IDs.
--
-- HOW TO FILL THESE IN (full walkthrough in README.md, "Monetization"):
--   1. Publish the place. In the Creator Dashboard open your experience » Monetization.
--   2. Passes: create each game pass below and paste its numeric Pass ID into `id`.
--   3. Developer Products: create each product below and paste its numeric Product ID into `id`.
--   4. Prices are set in the dashboard; the shop reads them live with GetProductInfo.
-- An id of 0 means "not configured": the shop shows the item as unavailable and never prompts.
--
-- Rules the game enforces: no fish or treasure can be bought; every item is obtainable by
-- playing; the only random paid item (Skip Event Timer) shows its exact odds and is hidden for
-- players where PolicyService says paid random items are restricted.

export type GamePass = {
	key: string,
	id: number,
	name: string,
	icon: string,
	desc: string,
	order: number,
}

export type DevProduct = {
	key: string,
	id: number,
	name: string,
	icon: string,
	desc: string,
	order: number,
	randomOutcome: boolean,
	requiresDive: boolean?, -- only purchasable during a dive (UI) - still stored if bought otherwise
	coins: number?, -- coin packs: base amount before progression scaling
}

local passes: { GamePass } = {
	{
		key = "VIP",
		id = 0, -- paste VIP game pass id
		name = "VIP",
		icon = "👑",
		desc = "+20% sell value, a golden [VIP] chat tag and the exclusive Gilded submarine skin.",
		order = 1,
	},
	{
		key = "DoubleCargo",
		id = 0, -- paste 2x Cargo Hold game pass id
		name = "2x Cargo Hold",
		icon = "📦",
		desc = "Double your cargo capacity on every dive.",
		order = 2,
	},
	{
		key = "AutoSell",
		id = 0, -- paste Auto-Sell game pass id
		name = "Auto-Sell",
		icon = "💸",
		desc = "Your haul sells itself the moment you surface (favourites and your keep-rarity are protected), and you can sell from anywhere on the dock.",
		order = 3,
	},
	{
		key = "LuckyDiver",
		id = 0, -- paste Lucky Diver game pass id
		name = "Lucky Diver",
		icon = "🍀",
		desc = "Permanent +25% luck.",
		order = 4,
	},
	{
		key = "TurboEngine",
		id = 0, -- paste Turbo Engine game pass id
		name = "Turbo Engine",
		icon = "🚀",
		desc = "+30% submarine speed.",
		order = 5,
	},
}

local products: { DevProduct } = {
	{
		key = "OxygenRefill",
		id = 0, -- paste Oxygen Refill product id
		name = "Oxygen Refill",
		icon = "💨",
		desc = "Instantly refill your oxygen mid-dive. Bought at the dock? It's saved for your next dive.",
		order = 1,
		randomOutcome = false,
		requiresDive = true,
	},
	{
		key = "HullRepair",
		id = 0, -- paste Hull Repair product id
		name = "Hull Repair",
		icon = "🔧",
		desc = "Instantly repair your hull to 100% mid-dive. Bought at the dock? It's saved for later.",
		order = 2,
		randomOutcome = false,
		requiresDive = true,
	},
	{
		key = "CargoInsurance",
		id = 0, -- paste Cargo Insurance product id
		name = "Cargo Insurance",
		icon = "🛡️",
		desc = "Covers one dive: keep 100% of your cargo if you black out.",
		order = 3,
		randomOutcome = false,
	},
	{
		key = "ServerLuck",
		id = 0, -- paste Server Luck Boost product id
		name = "Server Luck Boost",
		icon = "🌟",
		desc = "2x luck for EVERYONE in this server for 15 minutes. Your name is announced to the server. Stacks time.",
		order = 4,
		randomOutcome = false,
	},
	{
		key = "CoinsSmall",
		id = 0, -- paste small coin pack product id
		name = "Pouch of Coins",
		icon = "💰",
		desc = "A pouch of coins. Scales with the deepest zone you've reached.",
		order = 5,
		randomOutcome = false,
		coins = 1500,
	},
	{
		key = "CoinsMedium",
		id = 0, -- paste medium coin pack product id
		name = "Chest of Coins",
		icon = "💰",
		desc = "A chest of coins. Scales with the deepest zone you've reached.",
		order = 6,
		randomOutcome = false,
		coins = 6000,
	},
	{
		key = "CoinsLarge",
		id = 0, -- paste large coin pack product id
		name = "Vault of Coins",
		icon = "🏦",
		desc = "A vault of coins. Scales with the deepest zone you've reached.",
		order = 7,
		randomOutcome = false,
		coins = 20000,
	},
	{
		key = "SkipEvent",
		id = 0, -- paste Skip Event Timer product id
		name = "Skip Event Timer",
		icon = "⏩",
		desc = "Starts a random event in THIS server right now for 10 minutes. Each event has an equal chance.",
		order = 8,
		randomOutcome = true,
	},
}

local passesByKey: { [string]: GamePass } = {}
local passesById: { [number]: GamePass } = {}
for _, pass in passes do
	passesByKey[pass.key] = pass
	if pass.id ~= 0 then
		passesById[pass.id] = pass
	end
end

local productsByKey: { [string]: DevProduct } = {}
local productsById: { [number]: DevProduct } = {}
for _, product in products do
	productsByKey[product.key] = product
	if product.id ~= 0 then
		productsById[product.id] = product
	end
end

return {
	passes = passes,
	products = products,
	passesByKey = passesByKey,
	passesById = passesById,
	productsByKey = productsByKey,
	productsById = productsById,

	-- Pass effects
	vipSellBonus = 0.20,
	luckyDiverLuck = 0.25,
	turboSpeed = 0.30,
	vipSkin = "Gilded",

	serverLuck = { multiplier = 2, seconds = 15 * 60, maxStackSeconds = 2 * 60 * 60 },
	-- Coin packs: coins × coinScale[deepest zone index reached]
	coinScale = { 1, 4, 15, 60, 240, 1000 },

	-- Tasteful offer rules (PromptController)
	offers = {
		insuranceMinDepth = 1000, -- only offer insurance to divers whose hull reaches this deep
		cooldownSeconds = 25 * 60, -- at most one offer of any kind per this many seconds
		firstOfferAfterSeconds = 10 * 60, -- never offer anything in the first 10 minutes of a session
	},
}

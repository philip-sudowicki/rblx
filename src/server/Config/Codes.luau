--!strict
-- Redeemable codes. This file lives in ServerScriptService and is never replicated, so players
-- (and exploiters) can't read the list. Codes are case-insensitive (typed in Shop » Codes); each works once per player.
--
-- expires     : unix time after which the code stops working (nil = never)
-- minRebirths : optional requirement
-- rewards     : coins (× coinScale of the player's deepest zone), boosts { [Game.Boosts id] = seconds },
--               consumables { [key] = amount }, tokens (rebirth tokens), skin (Config/Skins id)

export type CodeRewards = {
	coins: number?,
	boosts: { [string]: number }?,
	consumables: { [string]: number }?,
	tokens: number?,
	skin: string?,
}

export type Code = {
	code: string,
	rewards: CodeRewards,
	expires: number?,
	minRebirths: number?,
}

local codes: { Code } = {
	{ code = "DEEPHAUL", rewards = { coins = 250, boosts = { Luck = 600 } } },
	{ code = "BUBBLES", rewards = { consumables = { OxygenRefill = 1, HullRepair = 1 } } },
	{ code = "LUCKYTIDE", rewards = { boosts = { Luck = 900, Sell = 600 } } },
	{ code = "SUBMARINE", rewards = { coins = 500, consumables = { CargoInsurance = 1 } } },
	-- launch-season code: expires 1 Jan 2027 00:00 UTC
	{ code = "LAUNCHWEEK", rewards = { coins = 1000, boosts = { Luck = 1800 } }, expires = 1798761600 },
	{ code = "RESURFACED", rewards = { tokens = 2, boosts = { Luck = 1200 } }, minRebirths = 1 },
}

return codes

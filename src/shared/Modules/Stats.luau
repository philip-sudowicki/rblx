--!strict
-- Derived gameplay stats. The single source of truth for "what does this player's sub do":
-- the server uses it for validation and rewards, the client for movement and UI previews.

local Config = script.Parent.Parent.Config
local Upgrades = require(Config.Upgrades)
local Rebirth = require(Config.Rebirth)
local CollectionSets = require(Config.CollectionSets)
local Products = require(Config.Products)
local Game = require(Config.Game)
local Types = require(script.Parent.Types)

export type Context = {
	upgrades: { [string]: number },
	perks: { [string]: number },
	rebirths: number,
	passes: { [string]: boolean },
	sets: { [string]: boolean },
	indexLuck: number, -- permanent luck from Index milestones
	boosts: { [string]: number }, -- boost id → expiry (unix seconds)
	now: number,
	serverLuck: number, -- active server luck multiplier (1 if none)
	eventLuck: number, -- events + weekend luck multiplier
	eventSell: number, -- events sell multiplier
}

export type Bonuses = {
	luck: number,
	sell: number,
	oxygen: number,
	clawSpeed: number,
	speed: number,
	sonar: number,
	cargo: number,
	minigame: number,
	tanks: number,
	startLevels: number,
}

local Stats = {}

local function emptyBonuses(): Bonuses
	return {
		luck = 0,
		sell = 0,
		oxygen = 0,
		clawSpeed = 0,
		speed = 0,
		sonar = 0,
		cargo = 0,
		minigame = 0,
		tanks = 0,
		startLevels = 0,
	}
end

function Stats.setBonuses(sets: { [string]: boolean }): Bonuses
	local bonuses = emptyBonuses()
	for _, set in CollectionSets.list do
		if sets[set.id] then
			local stat = set.bonus.stat
			local current = (bonuses :: any)[stat]
			if current ~= nil then
				(bonuses :: any)[stat] = current + set.bonus.amount
			end
		end
	end
	return bonuses
end

function Stats.perkBonuses(perks: { [string]: number }): Bonuses
	local bonuses = emptyBonuses()
	for _, perk in Rebirth.perks do
		local level = perks[perk.id] or 0
		if level > 0 then
			local current = (bonuses :: any)[perk.stat]
			if current ~= nil then
				(bonuses :: any)[perk.stat] = current + perk.perLevel * level
			end
		end
	end
	return bonuses
end

function Stats.maxLevel(upgradeId: string): number
	return #Upgrades.byId[upgradeId].values
end

function Stats.level(upgrades: { [string]: number }, upgradeId: string): number
	local level = upgrades[upgradeId] or 1
	return math.clamp(math.floor(level), 1, Stats.maxLevel(upgradeId))
end

function Stats.upgradeValue(upgradeId: string, level: number): number
	local upgrade = Upgrades.byId[upgradeId]
	return upgrade.values[math.clamp(level, 1, #upgrade.values)]
end

local function nice(n: number): number
	if n < 100 then
		return math.floor(n + 0.5)
	end
	local digits = math.floor(math.log10(n)) + 1
	local factor = 10 ^ (digits - 2)
	return math.floor(n / factor + 0.5) * factor
end
Stats.nice = nice

-- Price of buying `level` (from level - 1). Level 1 is free.
function Stats.upgradeCost(upgradeId: string, level: number): number
	local upgrade = Upgrades.byId[upgradeId]
	if level <= 1 then
		return 0
	end
	local overrides = upgrade.cost.overrides
	if overrides and overrides[level] then
		return overrides[level]
	end
	local raw = upgrade.cost.base * upgrade.cost.growth ^ (level - 2)
	return nice(nice(raw) * Game.Economy.UpgradeCostMultiplier)
end

function Stats.boostMultiplier(boosts: { [string]: number }, boostId: string, now: number): number
	local expiry = boosts[boostId]
	if expiry and expiry > now then
		local def = (Game.Boosts :: any)[boostId]
		if def then
			return def.multiplier
		end
	end
	return 1
end

function Stats.compute(ctx: Context): Types.DerivedStats
	local sets = Stats.setBonuses(ctx.sets)
	local perks = Stats.perkBonuses(ctx.perks)
	local passes = ctx.passes

	local function lvl(id: string): number
		return Stats.level(ctx.upgrades, id)
	end

	local luckBase = 1 + Stats.upgradeValue("Luck", lvl("Luck")) / 100
	local luckPass = if passes.LuckyDiver then Products.luckyDiverLuck else 0
	local luck = luckBase
		* (1 + luckPass)
		* (1 + sets.luck + perks.luck + ctx.indexLuck)
		* Stats.boostMultiplier(ctx.boosts, "Luck", ctx.now)
		* ctx.serverLuck
		* ctx.eventLuck

	local sell = (1 + ctx.rebirths * Rebirth.sellMultiplierPerRebirth)
		* (1 + (if passes.VIP then Products.vipSellBonus else 0) + sets.sell + perks.sell)
		* Stats.boostMultiplier(ctx.boosts, "Sell", ctx.now)
		* ctx.eventSell

	local cargo = Stats.upgradeValue("Cargo", lvl("Cargo")) + sets.cargo
	if passes.DoubleCargo then
		cargo *= 2
	end

	local sonarLevel = lvl("Sonar")
	local sonarUpgrade = Upgrades.byId.Sonar
	local clawLevel = lvl("Claw")
	local clawUpgrade = Upgrades.byId.Claw

	return {
		maxDepth = Stats.upgradeValue("Hull", lvl("Hull")),
		oxygen = Stats.upgradeValue("Oxygen", lvl("Oxygen")) * (1 + sets.oxygen + perks.oxygen),
		speed = Stats.upgradeValue("Engine", lvl("Engine"))
			* (1 + (if passes.TurboEngine then Products.turboSpeed else 0) + sets.speed),
		lightRadius = Stats.upgradeValue("Lights", lvl("Lights")),
		sonarRange = Stats.upgradeValue("Sonar", sonarLevel) * (1 + sets.sonar + perks.sonar),
		sonarCooldown = (sonarUpgrade.cooldown :: { number })[sonarLevel],
		cargo = math.floor(cargo),
		clawTier = Stats.upgradeValue("Claw", clawLevel),
		clawSpeed = (clawUpgrade.speed :: { number })[clawLevel] * (1 + sets.clawSpeed + perks.clawSpeed),
		luck = luck,
		sellMult = sell,
		displaySlots = Game.Aquarium.BaseTanks
			+ (if passes.ExtraTanks then Products.extraTanks else 0)
			+ math.floor(perks.tanks),
		minigameWidth = 1 + perks.minigame,
		oxygenEfficiency = 1,
	}
end

function Stats.rebirthCost(rebirths: number): number
	return nice(Rebirth.coinsBase * Rebirth.coinsGrowth ^ rebirths)
end

function Stats.rebirthTokens(newRebirthNumber: number): number
	return Rebirth.baseTokens + newRebirthNumber
end

-- Upgrade level that upgrades reset to after a rebirth (Reinforced Frame perk).
function Stats.startLevel(perks: { [string]: number }, upgradeId: string): number
	local bonuses = Stats.perkBonuses(perks)
	return math.clamp(1 + math.floor(bonuses.startLevels), 1, Stats.maxLevel(upgradeId))
end

-- Coins scaling for rewards: index = deepest zone reached (1..6)
function Stats.coinScale(scaleTable: { number }, zoneIndex: number): number
	return scaleTable[math.clamp(zoneIndex, 1, #scaleTable)]
end

return Stats

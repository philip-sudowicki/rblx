--!strict
-- Player data schema: the default template, versioned migrations and the sanitiser that repairs
-- a loaded profile. Pure (no services) so it is unit tested in tests/data.spec.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Modules.Types)
local Game = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Skins = require(Shared.Config.Skins)
local Rarities = require(Shared.Config.Rarities)
local Rebirth = require(Shared.Config.Rebirth)
local Quests = require(Shared.Config.Quests)
local Achievements = require(Shared.Config.Achievements)

local DataSchema = {}

DataSchema.PURCHASE_CACHE = 100


local function defaultUpgrades(): { [string]: number }
	local out = {}
	for _, upgrade in Upgrades.list do
		out[upgrade.id] = 1
	end
	return out
end

local function defaultStats(): Types.PlayerStats
	return {
		FishCaught = 0,
		TreasureSalvaged = 0,
		CoinsEarned = 0,
		ItemsSold = 0,
		DeepestMeters = 0,
		Dives = 0,
		Blackouts = 0,
		PerfectCatches = 0,
		MythicPlus = 0,
		Secrets = 0,
		GoldenCatches = 0,
		MutatedCatches = 0,
		EventItems = 0,
		SonarPings = 0,
		BestScore = 0,
		BestItem = "",
		BestMutation = "",
		BestKind = "",
		BestBoardValue = 0,
		RiftVisits = 0,
		CleanDives = 0,
		PlaySeconds = 0,
		DiveSeconds = 0,
		PassiveCoins = 0,
	}
end

local TEMPLATE: Types.PlayerData = {
	Version = Game.DataVersion,
	Coins = Game.Economy.StartingCoins,
	Tokens = 0,
	Rebirths = 0,
	Upgrades = defaultUpgrades(),
	Perks = {},
	Inventory = {},
	NextUid = 1,
	Discovered = { Fish = {}, Treasure = {} },
	IndexClaimed = {},
	Sets = {},
	Stats = defaultStats(),
	Achievements = {},
	Skins = { Owned = { [Skins.default] = true }, Equipped = Skins.default },
	Daily = { LastDay = 0, Streak = 0, Claimed = 0 },
	Quests = { DailyKey = 0, Daily = {}, WeeklyKey = 0, Weekly = {} },
	Codes = {},
	Aquarium = { Slots = {}, Pending = 0, LastTick = 0 },
	Consumables = { OxygenRefill = 0, HullRepair = 0, CargoInsurance = 0 },
	Boosts = {},
	Settings = {
		Music = 0.6,
		SFX = 0.8,
		Graphics = "High",
		SellKeep = Game.Economy.DefaultSellKeep,
		Offers = true,
		CameraShake = true,
	},
	Tutorial = { Done = false, Step = 1 },
	Purchases = {},
	LastOnline = 0,
	Flags = {},
}
DataSchema.TEMPLATE = TEMPLATE

-- Migrations: MIGRATIONS[v] upgrades data from version v to v + 1. Add a function here whenever
-- Game.DataVersion is bumped; Reconcile() already fills in brand-new keys automatically.
local MIGRATIONS: { [number]: (any) -> () } = {}
DataSchema.MIGRATIONS = MIGRATIONS


local function finite(n: any, fallback: number): number
	if typeof(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

function DataSchema.migrate(data: any)
	local version = finite(data.Version, 0)
	if version < 1 then
		version = 1
	end
	while version < Game.DataVersion do
		local step = MIGRATIONS[version]
		if step then
			step(data)
		end
		version += 1
	end
	data.Version = version
end

-- Repairs anything invalid (bad numbers, removed config ids, dangling references) so the rest
-- of the game can trust the data. Items whose config entry was removed are sold for their
-- stored value instead of being deleted.
function DataSchema.sanitize(data: Types.PlayerData): number
	local refunded = 0
	data.Coins = math.max(0, math.floor(finite(data.Coins, 0)))
	data.Tokens = math.max(0, math.floor(finite(data.Tokens, 0)))
	data.Rebirths = math.max(0, math.floor(finite(data.Rebirths, 0)))
	for _, upgrade in Upgrades.list do
		local level = math.floor(finite(data.Upgrades[upgrade.id], 1))
		data.Upgrades[upgrade.id] = math.clamp(level, 1, #upgrade.values)
	end
	for key in data.Upgrades do
		if not Upgrades.byId[key] then
			data.Upgrades[key] = nil
		end
	end
	for id, level in data.Perks do
		local perk = Rebirth.perksById[id]
		if not perk then
			data.Perks[id] = nil
		else
			data.Perks[id] = math.clamp(math.floor(finite(level, 0)), 0, #perk.costs)
		end
	end
	local maxUid = 0
	for key, item in data.Inventory do
		local valid = typeof(item) == "table"
			and typeof(item.u) == "number"
			and tostring(item.u) == key
			and (item.k == "F" and Fish.byId[item.i] ~= nil or item.k == "T" and Treasure.byId[item.i] ~= nil)
		if not valid then
			if typeof(item) == "table" and typeof(item.v) == "number" then
				refunded += math.max(0, math.floor(finite(item.v, 0)))
			end
			data.Inventory[key] = nil
		else
			item.v = math.max(1, math.floor(finite(item.v, 1)))
			item.r = math.clamp(math.floor(finite(item.r, 1)), 1, Rarities.count)
			-- Items still flagged as cargo mean the last dive never finished (disconnect or
			-- server crash). Secure them: no one loses a haul to a crash.
			item.g = nil
			maxUid = math.max(maxUid, item.u)
		end
	end
	data.NextUid = math.max(math.floor(finite(data.NextUid, 1)), maxUid + 1)
	data.Coins += refunded
	-- Aquarium slots must point at owned items, and flags must agree with slots
	local slotted: { [number]: string } = {}
	for slot, uid in data.Aquarium.Slots do
		local item = data.Inventory[tostring(uid)]
		if not item or slotted[uid] then
			data.Aquarium.Slots[slot] = nil
		else
			slotted[uid] = slot
			item.d = tonumber(slot)
		end
	end
	for _, item in data.Inventory do
		if item.d and not slotted[item.u] then
			item.d = nil
		end
	end
	data.Aquarium.Pending = math.max(0, finite(data.Aquarium.Pending, 0))
	-- Skins
	for id in data.Skins.Owned do
		if not Skins.byId[id] then
			data.Skins.Owned[id] = nil
		end
	end
	data.Skins.Owned[Skins.default] = true
	if not data.Skins.Owned[data.Skins.Equipped] then
		data.Skins.Equipped = Skins.default
	end
	-- Settings
	local settings = data.Settings
	settings.Music = math.clamp(finite(settings.Music, 0.6), 0, 1)
	settings.SFX = math.clamp(finite(settings.SFX, 0.8), 0, 1)
	if settings.Graphics ~= "High" and settings.Graphics ~= "Low" then
		settings.Graphics = "High"
	end
	settings.SellKeep = math.clamp(math.floor(finite(settings.SellKeep, Game.Economy.DefaultSellKeep)), 2, Rarities.count + 1)
	-- Consumables and boosts
	for key, count in data.Consumables do
		data.Consumables[key] = math.max(0, math.floor(finite(count, 0)))
	end
	local now = os.time()
	for key, expiry in data.Boosts do
		if finite(expiry, 0) <= now then
			data.Boosts[key] = nil
		end
	end
	-- Quests: a list with a removed template or bad numbers is regenerated on the next refresh
	for _, period in { "Daily", "Weekly" } do
		local quests = data.Quests :: any
		local list = quests[period]
		local valid = typeof(list) == "table"
		if valid then
			for _, quest in list do
				if typeof(quest) ~= "table" or not Quests.byId[quest.id] or finite(quest.target, 0) <= 0 then
					valid = false
					break
				end
				quest.progress = math.clamp(finite(quest.progress, 0), 0, quest.target)
				quest.reward = math.max(0, math.floor(finite(quest.reward, 0)))
			end
		end
		if not valid then
			quests[period] = {}
			quests[period .. "Key"] = 0
		end
	end
	data.Daily.LastDay = math.max(0, math.floor(finite(data.Daily.LastDay, 0)))
	data.Daily.Streak = math.max(0, math.floor(finite(data.Daily.Streak, 0)))
	data.Daily.Claimed = math.max(0, math.floor(finite(data.Daily.Claimed, 0)))
	data.Tutorial.Step = math.max(1, math.floor(finite(data.Tutorial.Step, 1)))
	for id in data.Achievements do
		if not Achievements.byId[id] then
			data.Achievements[id] = nil
		end
	end
	-- Purchase id cache
	if typeof(data.Purchases) ~= "table" then
		data.Purchases = {}
	end
	while #data.Purchases > DataSchema.PURCHASE_CACHE do
		table.remove(data.Purchases, 1)
	end
	return refunded
end

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = deepCopy(v)
	end
	return out :: any
end
DataSchema.deepCopy = deepCopy


return DataSchema

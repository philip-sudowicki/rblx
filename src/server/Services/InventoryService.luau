--!strict
-- Owned items: cargo (unsecured, this dive) vs storage (secured), favourites, selling,
-- blackout losses and Auto-Sell. All mutations replicate as small deltas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Modules.Types)
local Game = require(Shared.Config.Game)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local WorldService = require(script.Parent.WorldService)
local Validate = require(script.Parent.Validate)

export type DiveSummary = {
	lost: number,
	lostValue: number,
	secured: number,
	autoSold: number,
	autoCoins: number,
}

local InventoryService = {}

function InventoryService.get(player: Player, uid: number): Types.Item?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	return data.Inventory[tostring(uid)]
end

-- Adds an item (uid assigned here). inCargo marks it unsecured until the dive ends.
function InventoryService.add(player: Player, item: Types.Item, inCargo: boolean): Types.Item?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	item.u = data.NextUid
	data.NextUid += 1
	item.g = if inCargo then true else nil
	data.Inventory[tostring(item.u)] = item
	Remotes.fire(player, "InvAdd", { item })
	return item
end

function InventoryService.removeMany(player: Player, uids: { number })
	local data = DataService.get(player)
	if not data or #uids == 0 then
		return
	end
	for _, uid in uids do
		data.Inventory[tostring(uid)] = nil
	end
	Remotes.fire(player, "InvRemove", uids)
end

function InventoryService.changed(player: Player, items: { Types.Item })
	if #items > 0 then
		Remotes.fire(player, "InvUpdate", items)
	end
end

function InventoryService.cargo(player: Player): { Types.Item }
	local data = DataService.get(player)
	local out = {}
	if not data then
		return out
	end
	for _, item in data.Inventory do
		if item.g then
			table.insert(out, item)
		end
	end
	return out
end

function InventoryService.cargoCount(player: Player): number
	return #InventoryService.cargo(player)
end

function InventoryService.storageCount(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local count = 0
	for _, item in data.Inventory do
		if not item.g then
			count += 1
		end
	end
	return count
end

function InventoryService.hasCargoSpace(player: Player): boolean
	return InventoryService.cargoCount(player) < StatsService.get(player).cargo
end

-- Extra oxygen drain fraction from cursed items in cargo.
function InventoryService.cursedDrain(player: Player): number
	local total = 0
	for _, item in InventoryService.cargo(player) do
		if item.k == "T" then
			local def = Treasure.byId[item.i]
			if def and def.cursed then
				total += def.cursed
			end
		end
	end
	return math.min(total, Game.Dive.CursedDrainCap)
end

function InventoryService.sellPrice(player: Player, item: Types.Item): number
	return math.max(1, math.floor(item.v * StatsService.get(player).sellMult + 0.5))
end

local function sellable(item: Types.Item?): boolean
	return item ~= nil and not item.f and not item.g
end

-- Sells the given uids (skipping favourites, displayed and cargo items). Returns count, coins.
function InventoryService.sell(player: Player, uids: { number }): (number, number)
	local data = DataService.get(player)
	if not data then
		return 0, 0
	end
	local mult = StatsService.get(player).sellMult
	local sold = {}
	local coins = 0
	for _, uid in uids do
		local item = data.Inventory[tostring(uid)]
		if item and sellable(item) then
			coins += math.max(1, math.floor(item.v * mult + 0.5))
			table.insert(sold, uid)
		end
	end
	if #sold == 0 then
		return 0, 0
	end
	InventoryService.removeMany(player, sold)
	DataService.addCoins(player, coins, "Sell")
	data.Stats.CoinsEarned += coins
	data.Stats.ItemsSold += #sold
	DataService.replicate(player, "Stats")
	ServerSignals.ItemsSold:Fire(player, #sold, coins)
	Remotes.fire(player, "Effect", { kind = "Sold", coins = coins, count = #sold })
	return #sold, coins
end

-- Everything sellable below `keepRarity` (rarity index; items at or above it are kept).
function InventoryService.sellAll(player: Player, keepRarity: number): (number, number)
	local data = DataService.get(player)
	if not data then
		return 0, 0
	end
	local uids = {}
	for _, item in data.Inventory do
		if sellable(item) and item.r < keepRarity then
			table.insert(uids, item.u)
		end
	end
	return InventoryService.sell(player, uids)
end

-- Can this player sell right now? (at the Market, or anywhere on the dock with Auto-Sell)
function InventoryService.canSell(player: Player): boolean
	local state = PlayerState.get(player)
	if not state or state.dive then
		return false
	end
	if state.passes.AutoSell then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local prompt = WorldService.dock and WorldService.dock.prompts.Sell
	if not root or not prompt then
		return false
	end
	local anchor = prompt.Parent :: BasePart
	return (root.Position - anchor.Position).Magnitude <= Game.Dock.SellRange
end

-- Ends the cargo side of a dive: blackout losses, securing, and Auto-Sell. Never yields.
function InventoryService.finishDive(player: Player, reason: string, insured: boolean): DiveSummary
	local summary: DiveSummary = { lost = 0, lostValue = 0, secured = 0, autoSold = 0, autoCoins = 0 }
	local data = DataService.get(player)
	if not data then
		return summary
	end
	local cargo = InventoryService.cargo(player)
	if reason == "Blackout" and not insured and #cargo > 0 then
		-- lose a random half
		for i = #cargo, 2, -1 do
			local j = math.random(1, i)
			cargo[i], cargo[j] = cargo[j], cargo[i]
		end
		local loseCount = math.floor(#cargo * Game.Economy.BlackoutCargoLoss)
		local lostUids = {}
		for i = 1, loseCount do
			local item = cargo[i]
			summary.lostValue += item.v
			table.insert(lostUids, item.u)
		end
		summary.lost = loseCount
		InventoryService.removeMany(player, lostUids)
		local kept = {}
		for i = loseCount + 1, #cargo do
			table.insert(kept, cargo[i])
		end
		cargo = kept
	end
	local secured = {}
	for _, item in cargo do
		item.g = nil
		table.insert(secured, item)
	end
	summary.secured = #secured
	InventoryService.changed(player, secured)
	local state = PlayerState.get(player)
	if reason ~= "Left" and state and state.passes.AutoSell and #secured > 0 then
		local keep = data.Settings.SellKeep
		local uids = {}
		for _, item in secured do
			if not item.f and item.r < keep then
				table.insert(uids, item.u)
			end
		end
		summary.autoSold, summary.autoCoins = InventoryService.sell(player, uids)
	end
	return summary
end

function InventoryService.Start()
	Remotes.on("Sell", 4, 6, function(player, uids)
		if not Validate.intArray(uids, 500, 1, 1e12) then
			return
		end
		if not InventoryService.canSell(player) then
			Remotes.notify(player, "Visit the Fish Market to sell (or get Auto-Sell).", "warn")
			return
		end
		InventoryService.sell(player, uids)
	end)
	Remotes.on("SellAll", 1, 2, function(player, keep)
		if not Validate.integer(keep, 2, Rarities.count + 1) then
			return
		end
		if not InventoryService.canSell(player) then
			Remotes.notify(player, "Visit the Fish Market to sell (or get Auto-Sell).", "warn")
			return
		end
		local count = InventoryService.sellAll(player, keep)
		if count == 0 then
			Remotes.notify(player, "Nothing to sell with your current keep settings.", "info")
		end
	end)
	Remotes.on("Favorite", 8, 12, function(player, uid, value)
		if not Validate.integer(uid, 1, 1e12) or not Validate.boolean(value) then
			return
		end
		local item = InventoryService.get(player, uid)
		if item then
			item.f = if value then true else nil
			InventoryService.changed(player, { item })
		end
	end)
end

return InventoryService

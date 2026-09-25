--!strict
-- Player data: ProfileStore (session locked, autosave, BindToClose), versioned migrations,
-- sanitising on load, and replication of a read-only copy to the owning client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Modules.Types)
local Game = require(Shared.Config.Game)
local DataSchema = require(script.Parent.Parent.Pure.DataSchema)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)

local DataService = {}

local STORE_NAME = "DeepHaul_PlayerData_v1"

local TEMPLATE = DataSchema.TEMPLATE
DataService.TEMPLATE = TEMPLATE
local deepCopy = DataSchema.deepCopy
DataService.deepCopy = deepCopy

local store = ProfileStore.New(STORE_NAME, TEMPLATE)
local profiles: { [Player]: any } = {}

local function finite(n: any, fallback: number): number
	if typeof(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

local function snapshot(data: Types.PlayerData): any
	local copy = deepCopy(data) :: any
	copy.Purchases = nil
	copy.Codes = nil
	return copy
end

function DataService.get(player: Player): Types.PlayerData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function DataService.profile(player: Player): any
	return profiles[player]
end

function DataService.isLoaded(player: Player): boolean
	return DataService.get(player) ~= nil
end

-- Yields until the profile is loaded (or the player leaves). Returns nil if they left.
function DataService.waitFor(player: Player, timeout: number?): Types.PlayerData?
	local deadline = os.clock() + (timeout or 60)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.2)
	end
	return DataService.get(player)
end

-- Sends the current value of a top-level key to the client.
function DataService.replicate(player: Player, key: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	if key == "Purchases" or key == "Codes" then
		return
	end
	Remotes.fire(player, "DataSet", key, deepCopy((data :: any)[key]))
end

function DataService.addCoins(player: Player, amount: number, reason: string?): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	amount = math.floor(finite(amount, 0))
	if amount <= 0 then
		return data.Coins
	end
	data.Coins += amount
	DataService.replicate(player, "Coins")
	if reason and reason ~= "Sell" then
		ServerSignals.CoinsGranted:Fire(player, amount, reason)
	end
	return data.Coins
end

function DataService.spendCoins(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	amount = math.floor(finite(amount, math.huge))
	if amount < 0 or amount == math.huge or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	DataService.replicate(player, "Coins")
	return true
end

function DataService.addTokens(player: Player, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Tokens += math.max(0, math.floor(finite(amount, 0)))
	DataService.replicate(player, "Tokens")
end

function DataService.addConsumable(player: Player, key: string, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Consumables[key] = (data.Consumables[key] or 0) + math.max(0, math.floor(amount))
	DataService.replicate(player, "Consumables")
end

-- Extends a personal boost (Game.Boosts id) by `seconds`, capped at MaxStackSeconds ahead.
function DataService.addBoost(player: Player, boostId: string, seconds: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local current = math.max(now, data.Boosts[boostId] or 0)
	data.Boosts[boostId] = math.min(current + seconds, now + Game.Boosts.MaxStackSeconds)
	DataService.replicate(player, "Boosts")
	ServerSignals.StatsDirty:Fire(player)
end

-- Purchase receipt cache (see MonetizationService)
function DataService.hasPurchase(player: Player, purchaseId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and table.find(data.Purchases, purchaseId) ~= nil
end

function DataService.recordPurchase(player: Player, purchaseId: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	while #data.Purchases >= DataSchema.PURCHASE_CACHE do
		table.remove(data.Purchases, 1)
	end
	table.insert(data.Purchases, purchaseId)
end

function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

-- Fires `fn(player)` once the player's profile is loaded (immediately if it already is).
function DataService.onLoaded(fn: (Player) -> ())
	ServerSignals.ProfileLoaded:Connect(fn)
	for player in profiles do
		task.spawn(fn, player)
	end
end

local function onPlayerAdded(player: Player)
	local state = PlayerState.add(player)
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick("DEEP HAUL couldn't load your save right now. Please rejoin in a moment - your progress is safe.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	DataSchema.migrate(profile.Data)
	local refunded = DataSchema.sanitize(profile.Data)
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	state.ready = true
	Remotes.fire(player, "DataInit", snapshot(profile.Data))
	if refunded > 0 then
		Remotes.notify(player, string.format("Some retired items were auto-sold for %d coins.", refunded), "info")
	end
	ServerSignals.ProfileLoaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	ServerSignals.PlayerLeaving:Fire(player)
	local profile = profiles[player]
	if profile then
		if profile:IsActive() then
			profile.Data.LastOnline = os.time()
		end
		profile:EndSession()
		profiles[player] = nil
	end
	PlayerState.remove(player)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService

--!strict
-- Personal aquariums at the dock. Each player gets a plot; displayed fish and treasure appear in
-- the tanks for everyone to see and earn passive coins (collected at the plot or from the
-- menu). Offline earnings (capped) are granted on join with a "Welcome back" popup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Format = require(Shared.Modules.Format)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local InventoryService = require(script.Parent.InventoryService)
local WorldService = require(script.Parent.WorldService)
local Validate = require(script.Parent.Validate)

local AquariumService = {}

local plotOwners: { [number]: Player } = {}
local playerPlot: { [Player]: number } = {}

-- Coins per second from displayed items (only tanks within your slot count earn).
function AquariumService.incomePerSecond(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local slots = StatsService.get(player).displaySlots
	local total = 0
	for slot, uid in data.Aquarium.Slots do
		local index = tonumber(slot) or 0
		local item = data.Inventory[tostring(uid)]
		if item and index >= 1 and index <= slots then
			total += item.v * Game.Aquarium.IncomePerMinute / 60
		end
	end
	return total
end

function AquariumService.plotOf(player: Player): number?
	return playerPlot[player]
end

local function plotRecord(index: number)
	return WorldService.dock.plots[index]
end

function AquariumService.refreshPlot(player: Player)
	local index = playerPlot[player]
	local data = DataService.get(player)
	if not index or not data then
		return
	end
	local plot = plotRecord(index)
	local slots = StatsService.get(player).displaySlots
	plot.sign.Text = player.DisplayName .. "'s Aquarium"
	plot.model:SetAttribute("OwnerUserId", player.UserId)
	for tankIndex, tank in plot.tanks do
		local uid = data.Aquarium.Slots[tostring(tankIndex)]
		local item = if uid then data.Inventory[tostring(uid)] else nil
		local locked = tankIndex > slots
		tank:SetAttribute("Locked", locked)
		local glass = tank:FindFirstChild("Glass")
		if glass and glass:IsA("BasePart") then
			glass.Transparency = if locked then 0.35 else 0.7
			glass.Color = if locked then Color3.fromRGB(40, 50, 64) else Color3.fromRGB(170, 230, 255)
		end
		if item and not locked then
			tank:SetAttribute("Kind", item.k)
			tank:SetAttribute("ItemId", item.i)
			tank:SetAttribute("Mutation", item.m or "")
			tank:SetAttribute("Colossal", item.x == true)
			tank:SetAttribute("Weight", item.w or 0)
		else
			tank:SetAttribute("Kind", "")
			tank:SetAttribute("ItemId", "")
		end
	end
	local pending = math.floor(data.Aquarium.Pending)
	plot.pending.Text = if pending > 0 then "🪙 " .. Format.short(pending) .. " ready" else ""
end

local function clearPlot(index: number)
	local plot = plotRecord(index)
	plot.sign.Text = "Empty Aquarium"
	plot.pending.Text = ""
	plot.model:SetAttribute("OwnerUserId", 0)
	for _, tank in plot.tanks do
		tank:SetAttribute("Kind", "")
		tank:SetAttribute("ItemId", "")
		tank:SetAttribute("Locked", false)
		local glass = tank:FindFirstChild("Glass")
		if glass and glass:IsA("BasePart") then
			glass.Transparency = 0.7
			glass.Color = Color3.fromRGB(170, 230, 255)
		end
	end
end

local function assign(player: Player)
	for index = 1, #WorldService.dock.plots do
		if not plotOwners[index] then
			plotOwners[index] = player
			playerPlot[player] = index
			player:SetAttribute("PlotIndex", index)
			AquariumService.refreshPlot(player)
			return
		end
	end
	player:SetAttribute("PlotIndex", 0)
end

local function release(player: Player)
	local index = playerPlot[player]
	if index then
		plotOwners[index] = nil
		playerPlot[player] = nil
		clearPlot(index)
	end
end

function AquariumService.collect(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local coins = math.floor(data.Aquarium.Pending)
	if coins <= 0 then
		return 0
	end
	data.Aquarium.Pending -= coins
	data.Stats.PassiveCoins += coins
	DataService.addCoins(player, coins, "Aquarium")
	DataService.replicate(player, "Aquarium")
	DataService.replicate(player, "Stats")
	Remotes.fire(player, "Effect", { kind = "Coins", coins = coins })
	AquariumService.refreshPlot(player)
	return coins
end

function AquariumService.display(player: Player, uid: number): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local item = InventoryService.get(player, uid)
	if not item or item.g or item.d then
		return false
	end
	local slots = StatsService.get(player).displaySlots
	for index = 1, slots do
		local key = tostring(index)
		if not data.Aquarium.Slots[key] then
			data.Aquarium.Slots[key] = uid
			item.d = index
			InventoryService.changed(player, { item })
			DataService.replicate(player, "Aquarium")
			AquariumService.refreshPlot(player)
			Remotes.notify(player, "Now on display in your aquarium!", "good", "🐠")
			return true
		end
	end
	Remotes.notify(player, "All your tanks are full. Remove something first, or get more tanks.", "warn", "🐠")
	return false
end

function AquariumService.undisplay(player: Player, uid: number): boolean
	local data = DataService.get(player)
	local item = InventoryService.get(player, uid)
	if not data or not item or not item.d then
		return false
	end
	data.Aquarium.Slots[tostring(item.d)] = nil
	item.d = nil
	InventoryService.changed(player, { item })
	DataService.replicate(player, "Aquarium")
	AquariumService.refreshPlot(player)
	return true
end

local function grantOffline(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local last = data.LastOnline
	data.Aquarium.LastTick = now
	if last <= 0 or last > now then
		data.LastOnline = now
		return
	end
	local seconds = math.min(now - last, Game.Aquarium.OfflineCapHours * 3600)
	data.LastOnline = now
	local coins = math.floor(AquariumService.incomePerSecond(player) * seconds * Game.Aquarium.OfflineRate)
	if seconds >= 60 then
		if coins > 0 then
			data.Stats.PassiveCoins += coins
			DataService.addCoins(player, coins, "Offline")
			DataService.replicate(player, "Stats")
		end
		Remotes.fire(player, "WelcomeBack", { coins = coins, seconds = seconds, capped = now - last > Game.Aquarium.OfflineCapHours * 3600 })
	end
end

local function tick()
	local now = os.time()
	for _, state in PlayerState.all() do
		local player = state.player
		local data = DataService.get(player)
		if data then
			local elapsed = math.clamp(now - data.Aquarium.LastTick, 0, Game.Aquarium.TickSeconds * 4)
			data.Aquarium.LastTick = now
			data.LastOnline = now
			local rate = AquariumService.incomePerSecond(player)
			local cap = rate * Game.Aquarium.PendingCapHours * 3600
			data.Aquarium.Pending = math.min(data.Aquarium.Pending + rate * elapsed, math.max(cap, data.Aquarium.Pending))
			DataService.replicate(player, "Aquarium")
			AquariumService.refreshPlot(player)
		end
	end
end

function AquariumService.Start()
	DataService.onLoaded(function(player)
		assign(player)
		grantOffline(player)
	end)
	ServerSignals.PlayerLeaving:Connect(release)
	ServerSignals.StatsDirty:Connect(function(player)
		AquariumService.refreshPlot(player)
	end)
	ServerSignals.Rebirthed:Connect(function(player)
		AquariumService.refreshPlot(player)
	end)
	Remotes.on("Display", 4, 6, function(player, uid)
		if Validate.integer(uid, 1, 1e12) then
			AquariumService.display(player, uid)
		end
	end)
	Remotes.on("Undisplay", 4, 6, function(player, uid)
		if Validate.integer(uid, 1, 1e12) then
			AquariumService.undisplay(player, uid)
		end
	end)
	Remotes.on("CollectAquarium", 1, 2, function(player)
		local state = PlayerState.get(player)
		if state and state.dive then
			return
		end
		if AquariumService.collect(player) == 0 then
			Remotes.notify(player, "Nothing to collect yet. Display fish to earn coins over time.", "info", "🐠")
		end
	end)
	-- the collector prompt at your plot
	for _, plot in WorldService.dock.plots do
		plot.prompt.Triggered:Connect(function(player: Player)
			if playerPlot[player] == plot.index and player.Parent == Players then
				if AquariumService.collect(player) == 0 then
					Remotes.notify(player, "Nothing to collect yet.", "info", "🐠")
				end
			elseif player.Parent == Players then
				Remotes.notify(player, "That's someone else's aquarium - yours has your name on the sign!", "info", "🐠")
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(Game.Aquarium.TickSeconds)
			tick()
		end
	end)
end

return AquariumService

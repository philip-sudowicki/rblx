--!strict
-- Read-only mirror of this player's data, derived stats and event state, kept in sync by the
-- server's DataInit / DataSet / Inv* / EventState remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Stats = require(Shared.Modules.Stats)
local Types = require(Shared.Modules.Types)

local ClientState = {}

ClientState.player = Players.LocalPlayer
ClientState.data = (nil :: any) :: Types.PlayerData
ClientState.derived = (nil :: any) :: Types.DerivedStats
ClientState.events = nil :: any
ClientState.eventsReceivedAt = 0
ClientState.ready = false

ClientState.Changed = Signal.new() :: Signal.Signal<string>
ClientState.InventoryChanged = Signal.new() :: Signal.Signal<()>
ClientState.ItemsAdded = Signal.new() :: Signal.Signal<{ Types.Item }>
ClientState.EventsChanged = Signal.new() :: Signal.Signal<()>
ClientState.Ready = Signal.new() :: Signal.Signal<()>

function ClientState.serverTime(): number
	return workspace:GetServerTimeNow()
end

-- Stats with a safe fallback before the server's first "Derived" arrives.
function ClientState.stats(): Types.DerivedStats
	if ClientState.derived then
		return ClientState.derived
	end
	return Stats.compute({
		upgrades = if ClientState.data then ClientState.data.Upgrades else {},
		perks = if ClientState.data then ClientState.data.Perks else {},
		rebirths = if ClientState.data then ClientState.data.Rebirths else 0,
		passes = {},
		sets = if ClientState.data then ClientState.data.Sets else {},
		indexLuck = 0,
		boosts = {},
		now = os.time(),
		serverLuck = 1,
		eventLuck = 1,
		eventSell = 1,
	})
end

function ClientState.waitReady()
	if not ClientState.ready then
		ClientState.Ready:Wait()
	end
end

function ClientState.hasPass(key: string): boolean
	return ClientState.player:GetAttribute("Pass_" .. key) == true
end

function ClientState.items(): { Types.Item }
	local out = {}
	if ClientState.data then
		for _, item in ClientState.data.Inventory do
			table.insert(out, item)
		end
	end
	return out
end

function ClientState.cargoCount(): number
	local count = 0
	if ClientState.data then
		for _, item in ClientState.data.Inventory do
			if item.g then
				count += 1
			end
		end
	end
	return count
end

function ClientState.storageCount(): number
	local count = 0
	if ClientState.data then
		for _, item in ClientState.data.Inventory do
			if not item.g then
				count += 1
			end
		end
	end
	return count
end

-- Deepest zone index ever reached (for reward scaling previews)
function ClientState.deepestZone(): number
	local DepthMath = require(Shared.Modules.DepthMath)
	if not ClientState.data then
		return 1
	end
	return DepthMath.zoneIndexAtMeters(ClientState.data.Stats.DeepestMeters)
end

function ClientState.Init()
	Net.event("DataInit").OnClientEvent:Connect(function(snapshot)
		ClientState.data = snapshot
		if not ClientState.ready then
			ClientState.ready = true
			ClientState.Ready:Fire()
		end
		ClientState.Changed:Fire("*")
		ClientState.InventoryChanged:Fire()
	end)
	Net.event("DataSet").OnClientEvent:Connect(function(key: string, value: any)
		if key == "Derived" then
			ClientState.derived = value
			ClientState.Changed:Fire("Derived")
			return
		end
		if not ClientState.data then
			return
		end
		(ClientState.data :: any)[key] = value
		ClientState.Changed:Fire(key)
	end)
	Net.event("InvAdd").OnClientEvent:Connect(function(items: { Types.Item })
		if not ClientState.data then
			return
		end
		for _, item in items do
			ClientState.data.Inventory[tostring(item.u)] = item
		end
		ClientState.ItemsAdded:Fire(items)
		ClientState.InventoryChanged:Fire()
	end)
	Net.event("InvRemove").OnClientEvent:Connect(function(uids: { number })
		if not ClientState.data then
			return
		end
		for _, uid in uids do
			ClientState.data.Inventory[tostring(uid)] = nil
		end
		ClientState.InventoryChanged:Fire()
	end)
	Net.event("InvUpdate").OnClientEvent:Connect(function(items: { Types.Item })
		if not ClientState.data then
			return
		end
		for _, item in items do
			ClientState.data.Inventory[tostring(item.u)] = item
		end
		ClientState.InventoryChanged:Fire()
	end)
	Net.event("EventState").OnClientEvent:Connect(function(payload)
		ClientState.events = payload
		ClientState.eventsReceivedAt = os.clock()
		ClientState.EventsChanged:Fire()
	end)
end

return ClientState

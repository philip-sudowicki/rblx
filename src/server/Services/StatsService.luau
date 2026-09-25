--!strict
-- Derived stats per player (Shared/Modules/Stats), cached and pushed to the client whenever
-- anything that affects them changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stats = require(Shared.Modules.Stats)
local IndexMath = require(Shared.Modules.IndexMath)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local BoostService = require(script.Parent.BoostService)
local EventService = require(script.Parent.EventService)

local StatsService = {}

function StatsService.context(player: Player): Stats.Context?
	local data = DataService.get(player)
	local state = PlayerState.get(player)
	if not data or not state then
		return nil
	end
	local mods = EventService.modifiers()
	return {
		upgrades = data.Upgrades,
		perks = data.Perks,
		rebirths = data.Rebirths,
		passes = state.passes,
		sets = data.Sets,
		indexLuck = IndexMath.luckFromClaimed(data.IndexClaimed),
		boosts = data.Boosts,
		now = os.time(),
		serverLuck = BoostService.serverLuck(),
		eventLuck = mods.luck,
		eventSell = mods.sellMult,
	}
end

local function same(a: Types.DerivedStats?, b: Types.DerivedStats): boolean
	if not a then
		return false
	end
	for key, value in b :: any do
		if (a :: any)[key] ~= value then
			return false
		end
	end
	return true
end

function StatsService.refresh(player: Player): Types.DerivedStats?
	local state = PlayerState.get(player)
	local ctx = StatsService.context(player)
	if not state or not ctx then
		return nil
	end
	local stats = Stats.compute(ctx)
	if not same(state.stats, stats) then
		state.stats = stats
		Remotes.fire(player, "DataSet", "Derived", stats)
	end
	return stats
end

-- Always returns stats (computing on demand). Falls back to level-1 stats for unloaded players.
function StatsService.get(player: Player): Types.DerivedStats
	local state = PlayerState.get(player)
	if state and state.stats then
		return state.stats
	end
	local stats = StatsService.refresh(player)
	if stats then
		return stats
	end
	return Stats.compute({
		upgrades = {},
		perks = {},
		rebirths = 0,
		passes = {},
		sets = {},
		indexLuck = 0,
		boosts = {},
		now = os.time(),
		serverLuck = 1,
		eventLuck = 1,
		eventSell = 1,
	})
end

function StatsService.Start()
	DataService.onLoaded(function(player)
		StatsService.refresh(player)
	end)
	ServerSignals.StatsDirty:Connect(function(player)
		StatsService.refresh(player)
	end)
	ServerSignals.UpgradeBought:Connect(function(player)
		StatsService.refresh(player)
	end)
	ServerSignals.Rebirthed:Connect(function(player)
		StatsService.refresh(player)
	end)
	ServerSignals.SetCompleted:Connect(function(player)
		StatsService.refresh(player)
	end)
	ServerSignals.EventsChanged:Connect(function()
		for _, state in PlayerState.all() do
			StatsService.refresh(state.player)
		end
	end)
	-- personal boosts expire on their own; re-check regularly
	task.spawn(function()
		while true do
			task.wait(5)
			for _, state in PlayerState.all() do
				if state.ready then
					StatsService.refresh(state.player)
				end
			end
		end
	end)
end

return StatsService

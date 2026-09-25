--!strict
-- Server-wide events. Lower-level services fire these; higher-level services listen, so the
-- dependency graph between services stays acyclic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Modules.Signal)
local Types = require(Shared.Modules.Types)

export type ObtainContext = {
	source: string, -- "Catch" | "Salvage"
	zone: number,
	perfect: boolean?,
	events: { string },
}

return {
	-- (player) profile loaded and replicated
	ProfileLoaded = Signal.new() :: Signal.Signal<Player>,
	-- (player) fired first thing in PlayerRemoving, before the profile session ends
	PlayerLeaving = Signal.new() :: Signal.Signal<Player>,
	-- (player, item, context) a fish or treasure was added to cargo
	ItemObtained = Signal.new() :: Signal.Signal<Player, Types.Item, ObtainContext>,
	-- (player, itemCount, coins) items were sold
	ItemsSold = Signal.new() :: Signal.Signal<Player, number, number>,
	-- (player) dive started
	DiveStarted = Signal.new() :: Signal.Signal<Player>,
	-- (player, reason, clean, seconds, deepestMetres) dive ended.
	-- reason = "Surface" | "Emergency" | "Blackout" | "Left"; clean = ended by surfacing
	DiveEnded = Signal.new() :: Signal.Signal<Player, string, boolean, number, number>,
	-- (player, metres) new deepest depth this dive (fired in steps)
	DepthReached = Signal.new() :: Signal.Signal<Player, number>,
	-- (player, zoneIndex) entered a zone during a dive
	ZoneEntered = Signal.new() :: Signal.Signal<Player, number>,
	-- (player) sonar pinged
	SonarUsed = Signal.new() :: Signal.Signal<Player>,
	-- (player, upgradeId, newLevel)
	UpgradeBought = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, rebirthCount)
	Rebirthed = Signal.new() :: Signal.Signal<Player, number>,
	-- (player) something that affects derived stats changed (passes, boosts, sets, perks…)
	StatsDirty = Signal.new() :: Signal.Signal<Player>,
	-- (player, fishId) a minigame was failed
	CatchFailed = Signal.new() :: Signal.Signal<Player, string>,
	-- () active events changed (scheduled or local)
	EventsChanged = Signal.new() :: Signal.Signal<()>,
	-- (player, setId) a collection set was completed
	SetCompleted = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, coins) coins granted from any source (quests, daily, codes …) for stat tracking
	CoinsGranted = Signal.new() :: Signal.Signal<Player, number, string>,
}

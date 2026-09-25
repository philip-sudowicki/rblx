--!strict
-- Runtime (unsaved) per-player state: dive state, active minigame/salvage session, cooldowns,
-- cached derived stats and game pass ownership.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Modules.Types)

export type Dive = {
	sub: Model,
	root: BasePart,
	startedAt: number,
	oxygen: number,
	maxOxygen: number,
	hull: number, -- 0..100
	insured: boolean,
	zone: number,
	deepest: number, -- deepest metres this dive
	lastValid: Vector3,
	lastPos: Vector3,
	lastTime: number,
	velocity: Vector3,
	speed: number, -- smoothed speed (studs/s)
	strikes: { number },
	allowanceUntil: number, -- extra movement allowance (knockback, teleports) until this time
	ending: boolean,
	riftVisited: boolean,
	cursedDrain: number, -- extra oxygen drain fraction from cursed cargo
	lastDepthSignal: number,
	pressure: boolean,
	surfaceArmedAt: number, -- surfacing only ends the dive after this time
}

export type Session = {
	kind: string, -- "Catch" | "Salvage"
	id: number,
	entityId: number,
	startedAt: number,
	endsAt: number,
	-- catch
	zoneStart: number?,
	zoneWidth: number?,
	sweeps: number?,
	resolved: boolean,
	-- salvage
	duration: number?,
}

export type State = {
	player: Player,
	joinedAt: number,
	ready: boolean, -- profile loaded
	passes: { [string]: boolean },
	stats: Types.DerivedStats?,
	dive: Dive?,
	session: Session?,
	sonarReadyAt: number,
	catchReadyAt: number,
	paidRandomRestricted: boolean,
	lastSpawnTick: number,
	diveSeconds: number, -- dive time this session (for the first-legendary guarantee)
	lastOfferAt: number,
	streak: number, -- catches/salvages in a row this dive, each within Game.Catch.StreakWindow
	lastLootAt: number,
}

local PlayerState = {}

local states: { [Player]: State } = {}

function PlayerState.add(player: Player): State
	local existing = states[player]
	if existing then
		return existing
	end
	local state: State = {
		player = player,
		joinedAt = os.clock(),
		ready = false,
		passes = {},
		stats = nil,
		dive = nil,
		session = nil,
		sonarReadyAt = 0,
		catchReadyAt = 0,
		paidRandomRestricted = true, -- until PolicyService says otherwise
		lastSpawnTick = 0,
		diveSeconds = 0,
		lastOfferAt = 0,
		streak = 0,
		lastLootAt = 0,
	}
	states[player] = state
	return state
end

function PlayerState.get(player: Player): State?
	return states[player]
end

function PlayerState.remove(player: Player)
	states[player] = nil
end

function PlayerState.all(): { State }
	local out = {}
	for _, state in states do
		table.insert(out, state)
	end
	return out
end

function PlayerState.divers(): { State }
	local out = {}
	for _, state in states do
		if state.dive and not state.dive.ending then
			table.insert(out, state)
		end
	end
	return out
end

return PlayerState

--!strict
-- Fish and treasure streaming. Loot spawns around each diver up to per-zone density targets and
-- server caps, despawns when nobody is near, and is sent only to clients within the interest
-- radius. Fish swim on deterministic paths (FishPath) the clients animate; the server only
-- evaluates a path when validating a catch or a flee. Skittish fish flee from fast subs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local Rarities = require(Shared.Config.Rarities)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local DepthMath = require(Shared.Modules.DepthMath)
local FishPath = require(Shared.Modules.FishPath)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local LootPools = require(script.Parent.Parent.Pure.LootPools)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local StatsService = require(script.Parent.StatsService)
local EventService = require(script.Parent.EventService)
local WorldService = require(script.Parent.WorldService)
local SubService = require(script.Parent.SubService)
local ServerSignals = require(script.Parent.ServerSignals)

export type FishEntity = {
	id: number,
	fishId: string,
	tier: number,
	zone: number,
	home: Vector3,
	seed: number,
	t0: number,
	speed: number,
	prevHome: Vector3?,
	fleeAt: number?,
	spawnedAt: number,
	expiresAt: number,
	event: string?,
	owner: number,
	engagedBy: Player?,
	frozenPos: Vector3?,
	waryUntil: number,
	tutorial: boolean?,
	source: string?,
}

export type TreasureEntity = {
	id: number,
	treasureId: string,
	tier: number,
	zone: number,
	position: Vector3,
	spawnedAt: number,
	expiresAt: number,
	event: string?,
	engagedBy: Player?,
	spotId: number?,
	source: string?,
	persistent: boolean?, -- event content removes it itself
}

local SpawnService = {}

SpawnService.fish = {} :: { [number]: FishEntity }
SpawnService.treasure = {} :: { [number]: TreasureEntity }

local nextId = 0
local fishCount = 0
local treasureCount = 0
local known: { [Player]: { [number]: boolean } } = {}
local occupiedSpots: { [number]: number } = {}
local guaranteeReadyAt: { [Player]: number } = {}
local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end
SpawnService.serverNow = serverNow

local function newId(): number
	nextId += 1
	return nextId
end

---------------------------------------------------------------- records
local function fishRecord(e: FishEntity): any
	return {
		id = e.id,
		f = e.fishId,
		h = e.home,
		s = e.seed,
		t0 = e.t0,
		sp = e.speed,
		ph = e.prevHome,
		tf = e.fleeAt,
		e = e.event,
		w = e.waryUntil,
		g = if e.engagedBy then true else nil,
		fz = e.frozenPos,
		tu = e.tutorial,
	}
end

local function treasureRecord(e: TreasureEntity): any
	return {
		id = e.id,
		i = e.treasureId,
		p = e.position,
		e = e.event,
		src = e.source,
		g = if e.engagedBy then true else nil,
	}
end

function SpawnService.fishPosition(e: FishEntity, now: number?): Vector3
	if e.frozenPos then
		return e.frozenPos
	end
	return FishPath.position(e.home, e.seed, e.t0, now or serverNow(), e.speed, e.prevHome, e.fleeAt)
end

-- Tell every client that knows about `id` something changed.
local function broadcastUpdate(id: number, record: any, isFish: boolean)
	for player, set in known do
		if set[id] then
			Remotes.fire(player, "Entities", { u = if isFish then { record } else nil, tu = if isFish then nil else { record } })
		end
	end
end

function SpawnService.updated(e: FishEntity)
	broadcastUpdate(e.id, fishRecord(e), true)
end

function SpawnService.treasureUpdated(e: TreasureEntity)
	broadcastUpdate(e.id, treasureRecord(e), false)
end

function SpawnService.remove(id: number)
	local fish = SpawnService.fish[id]
	if fish then
		SpawnService.fish[id] = nil
		fishCount -= 1
	end
	local treasure = SpawnService.treasure[id]
	if treasure then
		SpawnService.treasure[id] = nil
		treasureCount -= 1
		if treasure.spotId and occupiedSpots[treasure.spotId] == id then
			occupiedSpots[treasure.spotId] = nil
		end
	end
	for player, set in known do
		if set[id] then
			set[id] = nil
			Remotes.fire(player, "Entities", { r = { id } })
		end
	end
end

---------------------------------------------------------------- spawning
export type FishOptions = {
	fishId: string?,
	event: string?,
	tutorial: boolean?,
	source: string?,
	lifetime: number?,
}

function SpawnService.spawnFish(ownerUserId: number, zoneIndex: number, position: Vector3, fishId: string, tier: number, opts: FishOptions?): FishEntity?
	if fishCount >= Game.Spawns.FishCap then
		return nil
	end
	local options: FishOptions = opts or {}
	local now = serverNow()
	local lifetime = options.lifetime or rng:NextNumber(Game.Spawns.FishLifetime[1], Game.Spawns.FishLifetime[2])
	local entity: FishEntity = {
		id = newId(),
		fishId = fishId,
		tier = tier,
		zone = zoneIndex,
		home = position,
		seed = rng:NextInteger(1, 2 ^ 30),
		t0 = now,
		speed = FishPath.speedFor(tier) * (if options.tutorial then 0.4 else 1),
		prevHome = nil,
		fleeAt = nil,
		spawnedAt = now,
		expiresAt = now + lifetime,
		event = options.event,
		owner = ownerUserId,
		engagedBy = nil,
		frozenPos = nil,
		waryUntil = 0,
		tutorial = options.tutorial,
		source = options.source,
	}
	SpawnService.fish[entity.id] = entity
	fishCount += 1
	return entity
end

export type TreasureOptions = {
	event: string?,
	source: string?,
	spotId: number?,
	lifetime: number?,
	persistent: boolean?,
}

function SpawnService.spawnTreasure(zoneIndex: number, position: Vector3, treasureId: string, tier: number, opts: TreasureOptions?): TreasureEntity?
	local options: TreasureOptions = opts or {}
	if treasureCount >= Game.Spawns.TreasureCap and not options.persistent then
		return nil
	end
	if options.spotId and occupiedSpots[options.spotId] then
		return nil
	end
	local now = serverNow()
	local lifetime = options.lifetime or rng:NextNumber(Game.Spawns.TreasureLifetime[1], Game.Spawns.TreasureLifetime[2])
	local entity: TreasureEntity = {
		id = newId(),
		treasureId = treasureId,
		tier = tier,
		zone = zoneIndex,
		position = position,
		spawnedAt = now,
		expiresAt = now + lifetime,
		event = options.event,
		engagedBy = nil,
		spotId = options.spotId,
		source = options.source,
		persistent = options.persistent,
	}
	SpawnService.treasure[entity.id] = entity
	treasureCount += 1
	if options.spotId then
		occupiedSpots[options.spotId] = entity.id
	end
	return entity
end

-- Roll modifiers for loot spawned "for" a player.
local function rollMods(player: Player, zoneIndex: number): LootPools.RollMods
	local stats = StatsService.get(player)
	local mods = EventService.modifiers()
	local _ = zoneIndex
	return {
		luck = stats.luck,
		tierMult = mods.tierMult,
		exclusive = mods.exclusive,
		categoryWeight = mods.categoryWeight,
	}
end

local function foundLegendary(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return true
	end
	return data.Flags.FoundLegendary == true
end

local function guaranteeDue(state: PlayerState.State): boolean
	local player = state.player
	if foundLegendary(player) then
		return false
	end
	local data = DataService.get(player)
	local dive = state.dive
	if not data or not dive then
		return false
	end
	local diveMinutes = (data.Stats.DiveSeconds + (os.clock() - dive.startedAt)) / 60
	if diveMinutes < Game.Spawns.FirstLegendaryGuaranteeMinutes then
		return false
	end
	return os.clock() >= (guaranteeReadyAt[player] or 0)
end

local function spawnFishFor(state: PlayerState.State, zoneIndex: number, near: Vector3): FishEntity?
	local point = WorldService.randomSwimPoint(zoneIndex, near, Game.Spawns.FishSpawnMinDistance, Game.Spawns.FishSpawnMaxDistance, rng)
	if not point then
		return nil
	end
	local mods = rollMods(state.player, zoneIndex)
	if guaranteeDue(state) then
		mods.minTier = Rarities.legendaryIndex
		mods.exclusive = nil
		guaranteeReadyAt[state.player] = os.clock() + 300
	end
	local result = LootPools.rollFish(roll, zoneIndex, mods)
	if not result then
		return nil
	end
	return SpawnService.spawnFish(state.player.UserId, zoneIndex, point, result.id, result.tier, { event = result.event })
end

local function spawnTreasureFor(state: PlayerState.State, zoneIndex: number, near: Vector3): TreasureEntity?
	local spots = WorldService.spotsNear(zoneIndex, near, Game.Spawns.TreasureRadius)
	local free = {}
	for _, spot in spots do
		if not occupiedSpots[spot.id] then
			table.insert(free, spot)
		end
	end
	if #free == 0 then
		return nil
	end
	local spot = free[rng:NextInteger(1, #free)]
	local mods = rollMods(state.player, zoneIndex)
	if spot.special then
		mods.luck *= 1.5 -- wreck decks, ruin altars and ledges hide better loot
	end
	local result = LootPools.rollTreasure(roll, zoneIndex, mods)
	if not result then
		return nil
	end
	return SpawnService.spawnTreasure(zoneIndex, spot.position, result.id, result.tier, { event = result.event, spotId = spot.id })
end

function SpawnService.spawnTutorialFish(player: Player): FishEntity?
	local dive = SubService.dive(player)
	if not dive then
		return nil
	end
	local look = dive.root.CFrame.LookVector
	local target = dive.root.Position + Vector3.new(look.X, 0, look.Z).Unit * 22
	target = WorldGeometry.clampInside(target, 20)
	local zoneIndex = DepthMath.zoneIndexAtY(target.Y)
	local pool = LootPools.fishPool(zoneIndex)
	local commons = {}
	for _, entry in pool do
		if entry.tier == 1 then
			table.insert(commons, entry)
		end
	end
	local pick = commons[rng:NextInteger(1, math.max(1, #commons))] or pool[1]
	return SpawnService.spawnFish(player.UserId, zoneIndex, target, pick.id, 1, { tutorial = true, lifetime = 300 })
end

function SpawnService.spawnTutorialTreasure(player: Player): TreasureEntity?
	local position = SubService.position(player)
	if not position then
		return nil
	end
	local zoneIndex = DepthMath.zoneIndexAtY(position.Y)
	local best, bestDist = nil, math.huge
	local zoneSpots = WorldService.spots[zoneIndex]
	if not zoneSpots then
		return nil
	end
	for _, spot in zoneSpots do
		if not occupiedSpots[spot.id] then
			local d = (spot.position - position).Magnitude
			if d < bestDist then
				best, bestDist = spot, d
			end
		end
	end
	if not best then
		return nil
	end
	return SpawnService.spawnTreasure(zoneIndex, best.position, "TarnishedDoubloon", 1, { spotId = best.id, source = "Tutorial", lifetime = 600 })
end

---------------------------------------------------------------- flee
function SpawnService.flee(e: FishEntity, from: Vector3, distance: number)
	local now = serverNow()
	local current = SpawnService.fishPosition(e, now)
	local away = current - from
	away = Vector3.new(away.X, away.Y * 0.3, away.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	end
	local blendedHome = e.home
	if e.prevHome and e.fleeAt then
		local alpha = math.clamp((now - e.fleeAt) / FishPath.FLEE_BLEND, 0, 1)
		blendedHome = e.prevHome:Lerp(e.home, alpha * alpha * (3 - 2 * alpha))
	end
	local target = WorldGeometry.clampInside(blendedHome + away.Unit * distance, Game.Spawns.WallMargin)
	if not WorldService.clearOfObstacles(e.zone, target, 6) then
		target = WorldGeometry.clampInside(blendedHome - away.Unit * distance * 0.5, Game.Spawns.WallMargin)
	end
	e.prevHome = blendedHome
	e.home = target
	e.fleeAt = now
	e.frozenPos = nil
	e.waryUntil = math.max(e.waryUntil, now + 1.5)
	SpawnService.updated(e)
end

local function fleeTick()
	local now = serverNow()
	local divers = PlayerState.divers()
	if #divers == 0 then
		return
	end
	for _, e in SpawnService.fish do
		local rarity = Rarities.list[e.tier]
		local flee = rarity.flee
		if flee and not e.engagedBy and now >= e.waryUntil and not e.tutorial then
			local fishPos: Vector3? = nil
			for _, state in divers do
				local dive = state.dive
				if dive and dive.speed > flee.speedThreshold then
					local subPos = dive.root.Position
					if (subPos - e.home).Magnitude < flee.detectRadius + 32 then
						fishPos = fishPos or SpawnService.fishPosition(e, now)
						if (subPos - (fishPos :: Vector3)).Magnitude < flee.detectRadius then
							SpawnService.flee(e, subPos, flee.distance)
							break
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- interest + spawn ticks
local function interestTick()
	local divers = PlayerState.divers()
	local diverSet: { [Player]: boolean } = {}
	for _, state in divers do
		local player = state.player
		diverSet[player] = true
		local dive = state.dive
		if dive then
			local pos = dive.root.Position
			local set = known[player]
			if not set then
				set = {}
				known[player] = set
			end
			local radius = Game.Spawns.InterestRadius
			local addFish, addTreasure, removed = {}, {}, {}
			local inRange: { [number]: boolean } = {}
			for id, e in SpawnService.fish do
				if (e.home - pos).Magnitude <= radius then
					inRange[id] = true
					if not set[id] then
						set[id] = true
						table.insert(addFish, fishRecord(e))
					end
				end
			end
			for id, e in SpawnService.treasure do
				if (e.position - pos).Magnitude <= radius then
					inRange[id] = true
					if not set[id] then
						set[id] = true
						table.insert(addTreasure, treasureRecord(e))
					end
				end
			end
			for id in set do
				if not inRange[id] then
					set[id] = nil
					table.insert(removed, id)
				end
			end
			if #addFish > 0 or #addTreasure > 0 or #removed > 0 then
				Remotes.fire(player, "Entities", {
					f = if #addFish > 0 then addFish else nil,
					t = if #addTreasure > 0 then addTreasure else nil,
					r = if #removed > 0 then removed else nil,
				})
			end
		end
	end
	for player in known do
		if not diverSet[player] then
			known[player] = nil
		end
	end
end

local function spawnTick()
	local now = serverNow()
	local divers = PlayerState.divers()
	local positions: { Vector3 } = {}
	for _, state in divers do
		local dive = state.dive
		if dive then
			table.insert(positions, dive.root.Position)
		end
	end

	-- despawn
	local despawnDistance = Game.Spawns.DespawnDistance
	local function nearAnyone(pos: Vector3, radius: number): boolean
		for _, p in positions do
			if (p - pos).Magnitude <= radius then
				return true
			end
		end
		return false
	end
	local toRemove = {}
	for id, e in SpawnService.fish do
		if not e.engagedBy and (now > e.expiresAt or not nearAnyone(e.home, despawnDistance)) then
			table.insert(toRemove, id)
		end
	end
	for id, e in SpawnService.treasure do
		if not e.engagedBy and not e.persistent and (now > e.expiresAt or not nearAnyone(e.position, despawnDistance)) then
			table.insert(toRemove, id)
		end
	end
	for _, id in toRemove do
		SpawnService.remove(id)
	end

	-- spawn around each diver
	for _, state in divers do
		local dive = state.dive
		if dive then
			local pos = dive.root.Position
			local zoneIndex = DepthMath.zoneIndexAtY(pos.Y)
			local zone = Zones.list[zoneIndex]
			if zone.requiresRebirth and not SubService.riftUnlocked(state.player) then
				continue
			end
			local fishNear = 0
			for _, e in SpawnService.fish do
				if e.zone == zoneIndex and (e.home - pos).Magnitude <= Game.Spawns.DensityRadius then
					fishNear += 1
				end
			end
			local spawned = 0
			while fishNear < zone.fishDensity and spawned < Game.Spawns.MaxSpawnsPerTick do
				spawned += 1
				if spawnFishFor(state, zoneIndex, pos) then
					fishNear += 1
				end
			end
			local treasureNear = 0
			for _, e in SpawnService.treasure do
				if e.zone == zoneIndex and (e.position - pos).Magnitude <= Game.Spawns.TreasureRadius then
					treasureNear += 1
				end
			end
			local tries = 0
			while treasureNear < zone.treasureDensity and tries < 2 do
				tries += 1
				if spawnTreasureFor(state, zoneIndex, pos) then
					treasureNear += 1
				end
			end
		end
	end
end

function SpawnService.release(player: Player)
	for _, e in SpawnService.fish do
		if e.engagedBy == player then
			e.engagedBy = nil
			e.frozenPos = nil
			SpawnService.updated(e)
		end
	end
	for _, e in SpawnService.treasure do
		if e.engagedBy == player then
			e.engagedBy = nil
			SpawnService.treasureUpdated(e)
		end
	end
end

-- All fish/treasure definitions exist? (defensive: config edits while a server runs)
function SpawnService.isValidFish(id: string): boolean
	return Fish.byId[id] ~= nil
end

function SpawnService.isValidTreasure(id: string): boolean
	return Treasure.byId[id] ~= nil
end

function SpawnService.Start()
	ServerSignals.DiveEnded:Connect(function(player)
		SpawnService.release(player)
		known[player] = nil
	end)
	ServerSignals.PlayerLeaving:Connect(function(player)
		SpawnService.release(player)
		known[player] = nil
		guaranteeReadyAt[player] = nil
	end)
	local interestAcc, spawnAcc, fleeAcc = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		interestAcc += dt
		spawnAcc += dt
		fleeAcc += dt
		if fleeAcc >= 0.25 then
			fleeAcc = 0
			local ok, err = pcall(fleeTick :: (...any) -> ...any)
			if not ok then
				warn("[DeepHaul] flee tick: " .. tostring(err))
			end
		end
		if spawnAcc >= Game.Spawns.SpawnInterval then
			spawnAcc = 0
			local ok, err = pcall(spawnTick :: (...any) -> ...any)
			if not ok then
				warn("[DeepHaul] spawn tick: " .. tostring(err))
			end
		end
		if interestAcc >= Game.Spawns.UpdateInterval then
			interestAcc = 0
			local ok, err = pcall(interestTick :: (...any) -> ...any)
			if not ok then
				warn("[DeepHaul] interest tick: " .. tostring(err))
			end
		end
	end)
end

return SpawnService

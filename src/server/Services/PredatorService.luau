--!strict
-- Predators are simulated on the server so damage is authoritative. They patrol, chase divers
-- inside their aggro radius, bump the sub (hull damage + knockback), then retreat. A sonar ping
-- stuns them. Clients get 10 Hz snapshots over an UnreliableRemoteEvent and interpolate.
-- Also handles the Sonar remote (cooldown, stun, stats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local Predators = require(Shared.Config.Predators)
local DepthMath = require(Shared.Modules.DepthMath)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local EventService = require(script.Parent.EventService)
local WorldService = require(script.Parent.WorldService)
local SubService = require(script.Parent.SubService)

type Predator = {
	id: number,
	typeId: string,
	zone: number,
	pos: Vector3,
	vel: Vector3,
	home: Vector3,
	state: string, -- "patrol" | "chase" | "retreat" | "stunned"
	target: Player?,
	stateUntil: number,
	cooldownUntil: number,
	wander: Vector3,
	lonelySince: number,
}

local PredatorService = {}

local predators: { [number]: Predator } = {}
local count = 0
local nextId = 0
local rng = Random.new()
local MAX_PREDATORS = 60
local SNAPSHOT_RADIUS = 320

-- Snapshot codes (clients decode with the same tables)
local STATE_CODE = { patrol = 1, chase = 2, retreat = 3, stunned = 4 }
local TYPE_INDEX: { [string]: number } = {}
for index, def in Predators.list do
	TYPE_INDEX[def.id] = index
end

local function newWander(p: Predator): Vector3
	local offset = Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(-20, 20), rng:NextNumber(-60, 60))
	return WorldGeometry.clampInside(p.home + offset, 50)
end

local function spawnNear(state: PlayerState.State, zoneIndex: number, near: Vector3)
	local zone = Zones.list[zoneIndex]
	if #zone.predators == 0 or count >= MAX_PREDATORS then
		return
	end
	local point = WorldService.randomSwimPoint(zoneIndex, near, 110, 220, rng)
	if not point then
		return
	end
	nextId += 1
	local typeId = zone.predators[rng:NextInteger(1, #zone.predators)]
	local p: Predator = {
		id = nextId,
		typeId = typeId,
		zone = zoneIndex,
		pos = point,
		vel = Vector3.zero,
		home = point,
		state = "patrol",
		target = nil,
		stateUntil = 0,
		cooldownUntil = os.clock() + 3,
		wander = point,
		lonelySince = 0,
	}
	p.wander = newWander(p)
	predators[p.id] = p
	count += 1
	local _ = state
end

local function steer(p: Predator, target: Vector3, speed: number, dt: number)
	local delta = target - p.pos
	local desired = if delta.Magnitude > 0.5 then delta.Unit * speed else Vector3.zero
	p.vel = p.vel:Lerp(desired, math.clamp(dt * 3, 0, 1))
	local nextPos = p.pos + p.vel * dt
	p.pos = WorldGeometry.clampInside(nextPos, 30)
end

-- Stun every predator within radius of pos.
function PredatorService.stun(pos: Vector3, radius: number, seconds: number): number
	local now = os.clock()
	local stunned = 0
	for _, p in predators do
		if (p.pos - pos).Magnitude <= radius then
			p.state = "stunned"
			p.stateUntil = now + seconds
			p.target = nil
			p.cooldownUntil = now + seconds + 2
			stunned += 1
		end
	end
	return stunned
end

local function tick(dt: number)
	local now = os.clock()
	local mods = EventService.modifiers()
	local divers = PlayerState.divers()

	-- spawn up to density around divers
	for _, state in divers do
		local dive = state.dive
		if dive then
			local pos = dive.root.Position
			local zoneIndex = DepthMath.zoneIndexAtY(pos.Y)
			local zone = Zones.list[zoneIndex]
			local target = math.floor(zone.predatorDensity * mods.predatorDensity + 0.5)
			local data = DataService.get(state.player)
			if data and not data.Tutorial.Done then
				target = 0 -- no predators while learning
			end
			if target > 0 then
				local near = 0
				for _, p in predators do
					if p.zone == zoneIndex and (p.pos - pos).Magnitude < 260 then
						near += 1
					end
				end
				if near < target and rng:NextNumber() < 0.15 then
					spawnNear(state, zoneIndex, pos)
				end
			end
		end
	end

	local removeIds = {}
	for id, p in predators do
		local def = Predators.byId[p.typeId]
		local aggro = def.aggroRadius * mods.predatorAggro
		local chaseSpeed = def.chaseSpeed * math.min(mods.predatorAggro, 1.4)
		-- nearest diver
		local nearest: PlayerState.State? = nil
		local nearestDist = math.huge
		for _, state in divers do
			local dive = state.dive
			if dive then
				local d = (dive.root.Position - p.pos).Magnitude
				if d < nearestDist then
					nearest, nearestDist = state, d
				end
			end
		end
		if nearestDist > Game.Spawns.DespawnDistance then
			if p.lonelySince == 0 then
				p.lonelySince = now
			elseif now - p.lonelySince > 15 then
				table.insert(removeIds, id)
				continue
			end
		else
			p.lonelySince = 0
		end

		if p.state == "stunned" then
			p.vel = p.vel:Lerp(Vector3.zero, math.clamp(dt * 4, 0, 1))
			p.pos = WorldGeometry.clampInside(p.pos + p.vel * dt, 30)
			if now >= p.stateUntil then
				p.state = "patrol"
			end
		elseif p.state == "retreat" then
			local away = p.vel.Unit
			local target = p.target
			local subPos = target and SubService.position(target)
			if subPos then
				local diff = p.pos - subPos
				if diff.Magnitude > 0.1 then
					away = diff.Unit
				end
			end
			steer(p, p.pos + away * 30, def.chaseSpeed * 0.8, dt)
			if now >= p.stateUntil then
				p.state = "patrol"
				p.target = nil
				p.wander = newWander(p)
			end
		elseif p.state == "chase" then
			local target = p.target
			local subPos = target and SubService.position(target)
			if not target or not subPos or (subPos - p.pos).Magnitude > aggro * 1.7 then
				p.state = "patrol"
				p.target = nil
			else
				steer(p, subPos, chaseSpeed, dt)
				if (subPos - p.pos).Magnitude <= def.bumpRadius + 4 then
					local direction = (subPos - p.pos)
					SubService.damage(target, def.damage, def.name, direction, def.knockback)
					p.state = "retreat"
					p.stateUntil = now + def.retreatSeconds
					p.cooldownUntil = now + def.retreatSeconds + def.cooldownSeconds
					Remotes.fire(target, "Effect", { kind = "PredatorHit", name = def.name })
				end
			end
		else -- patrol
			if (p.wander - p.pos).Magnitude < 6 then
				p.wander = newWander(p)
			end
			steer(p, p.wander, def.patrolSpeed, dt)
			if nearest and nearestDist <= aggro and now >= p.cooldownUntil then
				p.state = "chase"
				p.target = nearest.player
				Remotes.fire(nearest.player, "Effect", { kind = "PredatorAggro", name = def.name, id = p.id })
			end
		end
	end
	for _, id in removeIds do
		predators[id] = nil
		count -= 1
	end

	-- snapshots (compact: UnreliableRemoteEvent payloads must stay under ~1 KB)
	for _, state in divers do
		local dive = state.dive
		if dive then
			local pos = dive.root.Position
			local nearby = {}
			for _, p in predators do
				local d = (p.pos - pos).Magnitude
				if d <= SNAPSHOT_RADIUS then
					table.insert(nearby, { p = p, d = d })
				end
			end
			table.sort(nearby, function(a, b)
				return a.d < b.d
			end)
			local list: { any } = {}
			for i = 1, math.min(#nearby, 10) do
				local p = nearby[i].p
				local entry: { any } = { p.id, TYPE_INDEX[p.typeId], p.pos, p.vel, STATE_CODE[p.state] }
				table.insert(list, entry)
			end
			Remotes.unreliable(state.player, "Predators", workspace:GetServerTimeNow(), list)
		end
	end
end

local function sonar(player: Player)
	local state = PlayerState.get(player)
	local position = SubService.position(player)
	if not state or not position then
		return
	end
	local now = os.clock()
	if now < state.sonarReadyAt then
		return
	end
	local stats = StatsService.get(player)
	state.sonarReadyAt = now + stats.sonarCooldown - 0.25 -- small latency allowance
	local stunned = PredatorService.stun(position, Game.Sonar.StunRadius, Game.Sonar.StunSeconds)
	local data = DataService.get(player)
	if data then
		data.Stats.SonarPings += 1
	end
	ServerSignals.SonarUsed:Fire(player)
	Remotes.fire(player, "Effect", { kind = "SonarAck", stunned = stunned, cooldown = stats.sonarCooldown })
end

function PredatorService.Start()
	Remotes.on("Sonar", 1, 2, sonar)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		local ok, err = pcall(tick :: (...any) -> ...any, step)
		if not ok then
			warn("[DeepHaul] predator tick: " .. tostring(err))
		end
	end)
end

return PredatorService

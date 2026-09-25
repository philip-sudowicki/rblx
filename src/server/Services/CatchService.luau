--!strict
-- The catch minigame, fully server-authoritative. The server picks the green zone and marker
-- speed, the client animates the same formula, and the client's tap time is validated against
-- the server clock (clamped to a small latency window) before the catch is rolled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Rarities = require(Shared.Config.Rarities)
local MinigameMath = require(Shared.Modules.MinigameMath)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local SubService = require(script.Parent.SubService)
local SpawnService = require(script.Parent.SpawnService)
local InventoryService = require(script.Parent.InventoryService)
local LootService = require(script.Parent.LootService)
local Validate = require(script.Parent.Validate)

local CatchService = {}

local rng = Random.new()
local nextSession = 0

local function resolve(player: Player, session: PlayerState.Session, success: boolean, perfect: boolean)
	local state = PlayerState.get(player)
	if session.resolved then
		return
	end
	session.resolved = true
	if state and state.session == session then
		state.session = nil
		state.catchReadyAt = os.clock() + Game.Catch.Cooldown
	end
	local entity = SpawnService.fish[session.entityId]
	if not entity then
		Remotes.fire(player, "CatchResult", { id = session.id, ok = false, gone = true })
		return
	end
	entity.engagedBy = nil
	entity.frozenPos = nil
	if success and SubService.isDiving(player) then
		local item = LootService.grantFish(player, entity, perfect)
		SpawnService.remove(entity.id)
		Remotes.fire(player, "CatchResult", { id = session.id, ok = item ~= nil, perfect = perfect, entityId = entity.id })
	else
		local rarity = Rarities.list[entity.tier]
		local from = SubService.position(player) or SpawnService.fishPosition(entity)
		SpawnService.flee(entity, from, if rarity.flee then rarity.flee.distance else 30)
		entity.waryUntil = SpawnService.serverNow() + Game.Catch.WarySeconds
		SpawnService.updated(entity)
		Remotes.fire(player, "CatchResult", { id = session.id, ok = false, entityId = entity.id })
		ServerSignals.CatchFailed:Fire(player, entity.fishId)
	end
end

local function start(player: Player, entityId: number)
	local state = PlayerState.get(player)
	if not state or state.session or os.clock() < state.catchReadyAt then
		return
	end
	local position = SubService.position(player)
	if not position then
		return
	end
	local entity = SpawnService.fish[entityId]
	if not entity or entity.engagedBy then
		return
	end
	local now = SpawnService.serverNow()
	if now < entity.waryUntil then
		Remotes.notify(player, "It's spooked! Give it a moment.", "warn", "💨")
		return
	end
	local fishPos = SpawnService.fishPosition(entity, now)
	if (fishPos - position).Magnitude > Game.Catch.Range + Game.Catch.Tolerance then
		Remotes.notify(player, "Get a little closer!", "info")
		return
	end
	if not InventoryService.hasCargoSpace(player) then
		Remotes.notify(player, "Cargo hold full! Surface (hold R) to secure your haul.", "warn", "📦")
		return
	end
	local rarity = Rarities.list[entity.tier]
	local stats = StatsService.get(player)
	local width = rarity.minigame.zoneWidth * stats.minigameWidth
	local sweeps = rarity.minigame.sweeps
	if entity.tutorial then
		width = Game.Catch.TutorialZoneWidth
		sweeps = Game.Catch.TutorialSweeps
	end
	width = math.clamp(width, 0.04, 0.6)
	local zoneStart = rng:NextNumber(0.14, 0.94 - width)
	nextSession += 1
	local startsAt = now + Game.Catch.LeadIn
	local session: PlayerState.Session = {
		kind = "Catch",
		id = nextSession,
		entityId = entity.id,
		startedAt = startsAt,
		endsAt = startsAt + Game.Catch.Duration,
		zoneStart = zoneStart,
		zoneWidth = width,
		sweeps = sweeps,
		resolved = false,
	}
	state.session = session
	entity.engagedBy = player
	entity.frozenPos = fishPos
	SpawnService.updated(entity)
	Remotes.fire(player, "Minigame", {
		id = session.id,
		entityId = entity.id,
		fishId = entity.fishId,
		tier = entity.tier,
		startsAt = startsAt,
		duration = Game.Catch.Duration,
		zoneStart = zoneStart,
		zoneWidth = width,
		sweeps = sweeps,
	})
	task.delay(Game.Catch.LeadIn + Game.Catch.Duration + 0.5, function()
		if not session.resolved then
			resolve(player, session, false, false)
		end
	end)
end

local function tap(player: Player, sessionId: number, tapTime: number)
	local state = PlayerState.get(player)
	local session = state and state.session
	if not session or session.kind ~= "Catch" or session.id ~= sessionId or session.resolved then
		return
	end
	local now = SpawnService.serverNow()
	local t = math.clamp(tapTime, now - Game.Catch.TapWindow, now)
	if t > (session.endsAt :: number) then
		resolve(player, session, false, false)
		return
	end
	local marker = MinigameMath.marker(t - session.startedAt, session.sweeps :: number)
	local zoneStart = session.zoneStart :: number
	local width = session.zoneWidth :: number
	local success = t >= session.startedAt and MinigameMath.inZone(marker, zoneStart, width)
	local perfect = success and MinigameMath.isPerfect(marker, zoneStart, width, Game.Catch.PerfectFraction)
	resolve(player, session, success, perfect)
end

function CatchService.cancel(player: Player)
	local state = PlayerState.get(player)
	if not state then
		return
	end
	local session = state.session
	if session and session.kind == "Catch" and not session.resolved then
		session.resolved = true
		state.session = nil
		local entity = SpawnService.fish[session.entityId]
		if entity and entity.engagedBy == player then
			entity.engagedBy = nil
			entity.frozenPos = nil
			SpawnService.updated(entity)
		end
	end
end

function CatchService.Start()
	Remotes.on("CatchStart", 4, 6, function(player, entityId)
		if Validate.integer(entityId, 1, 2 ^ 40) then
			start(player, entityId)
		end
	end)
	Remotes.on("CatchTap", 6, 8, function(player, sessionId, tapTime)
		if Validate.integer(sessionId, 1, 2 ^ 40) and Validate.number(tapTime, 0, 1e12) then
			tap(player, sessionId, tapTime)
		end
	end)
	ServerSignals.DiveEnded:Connect(CatchService.cancel)
	ServerSignals.PlayerLeaving:Connect(CatchService.cancel)
end

return CatchService

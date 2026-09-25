--!strict
-- Hold-to-salvage. The server times the salvage (rarer = longer, faster with Claw speed), keeps
-- checking the sub stays in range, and enforces the Claw tier each treasure needs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Rarities = require(Shared.Config.Rarities)
local Treasure = require(Shared.Config.Treasure)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local SubService = require(script.Parent.SubService)
local SpawnService = require(script.Parent.SpawnService)
local InventoryService = require(script.Parent.InventoryService)
local LootService = require(script.Parent.LootService)
local Validate = require(script.Parent.Validate)

local SalvageService = {}

local nextSession = 0

function SalvageService.requiredTier(treasureId: string, tier: number): number
	local def = Treasure.byId[treasureId]
	if def and def.clawTier then
		return def.clawTier
	end
	return Rarities.list[tier].clawTier
end

local function finish(player: Player, session: PlayerState.Session, completed: boolean, reason: string?)
	if session.resolved then
		return
	end
	session.resolved = true
	local state = PlayerState.get(player)
	if state and state.session == session then
		state.session = nil
	end
	local entity = SpawnService.treasure[session.entityId]
	if entity and entity.engagedBy == player then
		entity.engagedBy = nil
	end
	if completed and entity and SubService.isDiving(player) then
		local item = LootService.grantTreasure(player, entity)
		SpawnService.remove(entity.id)
		Remotes.fire(player, "SalvageState", { state = "done", id = session.id, ok = item ~= nil })
	else
		if entity then
			SpawnService.treasureUpdated(entity)
		end
		Remotes.fire(player, "SalvageState", { state = "cancel", id = session.id, reason = reason })
	end
end

local function start(player: Player, entityId: number)
	local state = PlayerState.get(player)
	if not state or state.session then
		return
	end
	local position = SubService.position(player)
	if not position then
		return
	end
	local entity = SpawnService.treasure[entityId]
	if not entity or entity.engagedBy then
		return
	end
	if (entity.position - position).Magnitude > Game.Salvage.Range + Game.Salvage.Tolerance then
		Remotes.notify(player, "Get closer to salvage that.", "info")
		return
	end
	local stats = StatsService.get(player)
	local required = SalvageService.requiredTier(entity.treasureId, entity.tier)
	if stats.clawTier < required then
		Remotes.notify(player, string.format("Requires Claw Tier %d (yours: %d). Upgrade at the Workshop!", required, stats.clawTier), "warn", "🧲")
		return
	end
	if not InventoryService.hasCargoSpace(player) then
		Remotes.notify(player, "Cargo hold full! Surface (hold R) to secure your haul.", "warn", "📦")
		return
	end
	local rarity = Rarities.list[entity.tier]
	local duration = rarity.salvageTime / math.max(0.1, stats.clawSpeed)
	if entity.source == "Tutorial" then
		duration = 1
	end
	nextSession += 1
	local session: PlayerState.Session = {
		kind = "Salvage",
		id = nextSession,
		entityId = entity.id,
		startedAt = os.clock(),
		endsAt = os.clock() + duration,
		duration = duration,
		resolved = false,
	}
	state.session = session
	entity.engagedBy = player
	SpawnService.treasureUpdated(entity)
	Remotes.fire(player, "SalvageState", { state = "start", id = session.id, entityId = entity.id, duration = duration })
	task.spawn(function()
		while not session.resolved do
			task.wait(Game.Salvage.CheckInterval)
			if session.resolved then
				return
			end
			local pos = SubService.position(player)
			local current = SpawnService.treasure[session.entityId]
			if not pos or not current then
				finish(player, session, false, "gone")
				return
			end
			if (current.position - pos).Magnitude > Game.Salvage.Range + Game.Salvage.Tolerance + 6 then
				finish(player, session, false, "moved")
				return
			end
			if os.clock() >= session.endsAt then
				finish(player, session, true)
				return
			end
		end
	end)
end

function SalvageService.cancel(player: Player)
	local state = PlayerState.get(player)
	local session = state and state.session
	if session and session.kind == "Salvage" then
		finish(player, session, false, "released")
	end
end

function SalvageService.Start()
	Remotes.on("SalvageStart", 3, 5, function(player, entityId)
		if Validate.integer(entityId, 1, 2 ^ 40) then
			start(player, entityId)
		end
	end)
	Remotes.on("SalvageCancel", 4, 6, function(player)
		SalvageService.cancel(player)
	end)
	ServerSignals.DiveEnded:Connect(SalvageService.cancel)
	ServerSignals.PlayerLeaving:Connect(SalvageService.cancel)
end

return SalvageService

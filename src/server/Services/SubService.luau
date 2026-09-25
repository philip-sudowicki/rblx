--!strict
-- Dives. Launching seats the player's character in a freshly built submarine whose physics the
-- player's client owns (for responsive, weighty movement). The server simulates oxygen, hull
-- and pressure, validates every movement step (speed, teleports, bounds, the Rift Seal), and
-- ends the dive on surfacing, emergency surface or blackout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local Rebirth = require(Shared.Config.Rebirth)
local DepthMath = require(Shared.Modules.DepthMath)
local WorldGeometry = require(Shared.Modules.WorldGeometry)
local SubModel = require(Shared.Models.SubModel)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local StatsService = require(script.Parent.StatsService)
local InventoryService = require(script.Parent.InventoryService)
local WorldService = require(script.Parent.WorldService)
local Validate = require(script.Parent.Validate)

local SubService = {}

local subsFolder: Folder
local characterDefaults: { [Player]: { jumpHeight: number, jumpPower: number } } = {}

function SubService.dive(player: Player): PlayerState.Dive?
	local state = PlayerState.get(player)
	if state and state.dive and not state.dive.ending then
		return state.dive
	end
	return nil
end

function SubService.isDiving(player: Player): boolean
	return SubService.dive(player) ~= nil
end

function SubService.position(player: Player): Vector3?
	local dive = SubService.dive(player)
	if dive and dive.root.Parent then
		return dive.root.Position
	end
	return nil
end

function SubService.riftUnlocked(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and data.Rebirths >= Rebirth.riftUnlockRebirths
end

local function humanoidOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function setAttributes(player: Player, dive: PlayerState.Dive?)
	if dive then
		player:SetAttribute("Diving", true)
		player:SetAttribute("DiveO2", math.floor(dive.oxygen * 10) / 10)
		player:SetAttribute("DiveO2Max", dive.maxOxygen)
		player:SetAttribute("DiveHull", math.floor(dive.hull * 10) / 10)
		player:SetAttribute("DiveInsured", dive.insured)
	else
		player:SetAttribute("Diving", false)
		player:SetAttribute("DivePressure", 0)
	end
end

local function setPassenger(character: Model, passenger: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = if passenger then "Passengers" else "Characters"
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Massless = passenger
			end
		end
	end
end

local function dockCFrame(): CFrame
	local world = Zones.world
	local position = world.pierStart + Vector3.new(math.random(-5, 5), 3, math.random(-4, 0))
	return CFrame.lookAt(position, Vector3.new(world.plazaCenter.X, position.Y, world.plazaCenter.Z))
end

-- Ends the dive. reason: "Surface" | "Emergency" | "Blackout" | "Left"
function SubService.endDive(player: Player, reason: string)
	local state = PlayerState.get(player)
	local dive = state and state.dive
	if not state or not dive or dive.ending then
		return
	end
	dive.ending = true
	local data = DataService.get(player)
	local summary = InventoryService.finishDive(player, reason, dive.insured)
	local clean = reason ~= "Blackout"
	local elapsed = os.clock() - dive.startedAt
	state.diveSeconds += elapsed
	if data then
		data.Stats.Dives += 1
		data.Stats.DiveSeconds += math.floor(elapsed)
		if clean then
			data.Stats.CleanDives += 1
		else
			data.Stats.Blackouts += 1
		end
		DataService.replicate(player, "Stats")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
	local seat = dive.sub:FindFirstChild("PilotSeat")
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	dive.sub:Destroy()
	if character and humanoid and reason ~= "Left" then
		setPassenger(character, false)
		local defaults = characterDefaults[player]
		if defaults then
			humanoid.JumpHeight = defaults.jumpHeight
			humanoid.JumpPower = defaults.jumpPower
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		if humanoid.Health > 0 then
			character:PivotTo(dockCFrame())
		end
	end
	state.dive = nil
	setAttributes(player, nil)
	ServerSignals.DiveEnded:Fire(player, reason, clean)
	Remotes.fire(player, "DiveEvent", {
		type = "Ended",
		reason = reason,
		lost = summary.lost,
		lostValue = summary.lostValue,
		secured = summary.secured,
		autoSold = summary.autoSold,
		autoCoins = summary.autoCoins,
		insured = dive.insured,
	})
end

local function startDive(player: Player, insure: boolean)
	local state = PlayerState.get(player)
	local data = DataService.get(player)
	if not state or not data or state.dive then
		return
	end
	local character, humanoid, root = humanoidOf(player)
	if not character or not humanoid or not root then
		return
	end
	local prompt = WorldService.dock.prompts.Launch
	local anchor = prompt.Parent :: BasePart
	if (root.Position - anchor.Position).Magnitude > Game.Dock.BoardRange + 10 then
		Remotes.notify(player, "Walk to the Launch Bay to dive.", "warn")
		return
	end
	if Game.Dive.StorageBlocksDive and InventoryService.storageCount(player) >= Game.Economy.StorageCap then
		Remotes.notify(player, string.format("Your storage is full (%d items). Sell or release some before diving!", Game.Economy.StorageCap), "bad")
		return
	end
	local insured = false
	if insure and (data.Consumables.CargoInsurance or 0) > 0 then
		data.Consumables.CargoInsurance -= 1
		insured = true
		DataService.replicate(player, "Consumables")
	end

	local stats = StatsService.get(player)
	local world = Zones.world
	local offset = Vector3.new(math.random(-16, 16), math.random(-3, 3), math.random(-6, 6))
	local startPos = world.launchPoint + offset
	local cf = CFrame.lookAt(startPos, world.launchLook + offset)
	local sub = SubModel.build(data.Skins.Equipped, cf)
	sub.Name = "Sub_" .. player.UserId
	sub:SetAttribute("OwnerUserId", player.UserId)
	sub.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	sub.Parent = subsFolder
	sub:AddPersistentPlayer(player)
	local subRoot = sub.PrimaryPart :: BasePart
	local seat = sub:FindFirstChild("PilotSeat") :: Seat

	characterDefaults[player] = { jumpHeight = humanoid.JumpHeight, jumpPower = humanoid.JumpPower }
	setPassenger(character, true)
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	character:PivotTo(seat.CFrame * CFrame.new(0, 2, 0))
	seat:Sit(humanoid)
	subRoot:SetNetworkOwner(player)

	local now = os.clock()
	local dive: PlayerState.Dive = {
		sub = sub,
		root = subRoot,
		startedAt = now,
		oxygen = stats.oxygen,
		maxOxygen = stats.oxygen,
		hull = 100,
		insured = insured,
		zone = 1,
		deepest = 0,
		lastValid = startPos,
		lastPos = startPos,
		lastTime = now,
		velocity = Vector3.zero,
		speed = 0,
		strikes = {},
		allowanceUntil = now + 2,
		ending = false,
		riftVisited = false,
		cursedDrain = 0,
		lastDepthSignal = 0,
		pressure = false,
		surfaceArmedAt = now + Game.Dive.LaunchGraceSeconds,
	}
	state.dive = dive
	setAttributes(player, dive)

	-- if the pilot gets out of the seat (exploit or glitch) put them back once, else end the dive
	local reseats = 0
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if dive.ending or seat.Occupant == humanoid then
			return
		end
		task.delay(0.1, function()
			if dive.ending or seat.Occupant == humanoid or not seat.Parent then
				return
			end
			reseats += 1
			if reseats <= 2 and humanoid.Health > 0 then
				seat:Sit(humanoid)
			else
				SubService.endDive(player, "Emergency")
			end
		end)
	end)
	humanoid.Died:Once(function()
		SubService.endDive(player, "Blackout")
	end)

	ServerSignals.DiveStarted:Fire(player)
	Remotes.fire(player, "DiveEvent", {
		type = "Started",
		name = sub.Name,
		oxygen = dive.oxygen,
		maxOxygen = dive.maxOxygen,
		insured = insured,
	})
end

function SubService.damage(player: Player, amount: number, source: string, direction: Vector3?, knockback: number?)
	local dive = SubService.dive(player)
	if not dive then
		return
	end
	dive.hull = math.max(0, dive.hull - amount)
	local impulse = if direction and knockback and direction.Magnitude > 0 then direction.Unit * knockback else nil
	if impulse then
		dive.allowanceUntil = os.clock() + 1.5
	end
	player:SetAttribute("DiveHull", math.floor(dive.hull * 10) / 10)
	Remotes.fire(player, "DiveEvent", { type = "Damage", amount = amount, source = source, impulse = impulse })
	if dive.hull <= 0 then
		SubService.endDive(player, "Blackout")
	end
end

function SubService.refillOxygen(player: Player): boolean
	local dive = SubService.dive(player)
	if not dive then
		return false
	end
	dive.oxygen = dive.maxOxygen
	player:SetAttribute("DiveO2", dive.oxygen)
	Remotes.fire(player, "DiveEvent", { type = "Refill", what = "Oxygen" })
	return true
end

function SubService.repairHull(player: Player): boolean
	local dive = SubService.dive(player)
	if not dive then
		return false
	end
	dive.hull = 100
	player:SetAttribute("DiveHull", 100)
	Remotes.fire(player, "DiveEvent", { type = "Refill", what = "Hull" })
	return true
end

function SubService.insureCurrent(player: Player): boolean
	local dive = SubService.dive(player)
	if not dive or dive.insured then
		return false
	end
	dive.insured = true
	player:SetAttribute("DiveInsured", true)
	Remotes.fire(player, "DiveEvent", { type = "Refill", what = "Insurance" })
	return true
end

-- Moves the sub somewhere on purpose (events, tutorial) without tripping validation.
function SubService.teleport(player: Player, position: Vector3)
	local dive = SubService.dive(player)
	if not dive then
		return
	end
	dive.allowanceUntil = os.clock() + 2
	dive.root.CFrame = CFrame.new(position) * dive.root.CFrame.Rotation
	dive.lastValid = position
	dive.lastPos = position
	Remotes.fire(player, "DiveEvent", { type = "Snap", position = position })
end

local function strike(dive: PlayerState.Dive, now: number): number
	table.insert(dive.strikes, now)
	for i = #dive.strikes, 1, -1 do
		if now - dive.strikes[i] > 60 then
			table.remove(dive.strikes, i)
		end
	end
	return #dive.strikes
end

local function snapBack(player: Player, dive: PlayerState.Dive, target: Vector3, now: number)
	dive.root.CFrame = CFrame.new(target) * dive.root.CFrame.Rotation
	dive.root.AssemblyLinearVelocity = Vector3.zero
	dive.lastPos = target
	dive.lastValid = target
	Remotes.fire(player, "DiveEvent", { type = "Snap", position = target })
	if strike(dive, now) > Game.Dive.MaxStrikesPerMinute then
		warn(string.format("[DeepHaul] %s exceeded movement strikes; ending dive", player.Name))
		SubService.endDive(player, "Emergency")
	end
end

local function tickDive(state: PlayerState.State, dt: number)
	local player = state.player
	local dive = state.dive
	if not dive or dive.ending then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local _, humanoid = humanoidOf(player)
	if not humanoid or not dive.root.Parent then
		SubService.endDive(player, "Blackout")
		return
	end
	local stats = StatsService.get(player)
	local now = os.clock()
	local pos = dive.root.Position

	-- movement validation
	local stepTime = math.max(now - dive.lastTime, 1 / 60)
	local allowedSpeed = stats.speed * Game.Dive.SpeedTolerance + Game.Dive.SpeedToleranceFlat
	if now < dive.allowanceUntil then
		allowedSpeed += 140
	end
	local moved = (pos - dive.lastPos).Magnitude
	if pos ~= pos or moved > allowedSpeed * stepTime + 8 then
		snapBack(player, dive, dive.lastValid, now)
		dive.lastTime = now
		return
	end
	if not WorldGeometry.subAllowed(pos, Game.Dive.BoundsMargin) then
		snapBack(player, dive, dive.lastValid, now)
		dive.lastTime = now
		return
	end
	if pos.Y < Zones.world.riftSealY and not SubService.riftUnlocked(player) then
		local target = Vector3.new(pos.X, Zones.world.riftSealY + 6, pos.Z)
		snapBack(player, dive, target, now)
		Remotes.notify(player, "The Rift Seal won't budge. Only the Resurfaced may pass.", "warn", "🔒")
		dive.lastTime = now
		return
	end
	local velocity = (pos - dive.lastPos) / stepTime
	dive.velocity = dive.velocity:Lerp(velocity, 0.5)
	dive.speed = dive.velocity.Magnitude
	dive.lastPos = pos
	dive.lastValid = pos
	dive.lastTime = now

	-- depth, zones, records
	local meters = DepthMath.metersAtY(pos.Y)
	local zoneIndex = DepthMath.zoneIndexAtY(pos.Y)
	if zoneIndex ~= dive.zone then
		dive.zone = zoneIndex
		ServerSignals.ZoneEntered:Fire(player, zoneIndex)
		if zoneIndex == Zones.count and not dive.riftVisited then
			dive.riftVisited = true
			data.Stats.RiftVisits += 1
			DataService.replicate(player, "Stats")
		end
	end
	if meters > dive.deepest then
		dive.deepest = meters
		if meters > data.Stats.DeepestMeters + 1 then
			data.Stats.DeepestMeters = math.floor(meters)
			if meters - dive.lastDepthSignal >= 25 then
				DataService.replicate(player, "Stats")
			end
		end
		if meters - dive.lastDepthSignal >= 25 then
			dive.lastDepthSignal = meters
			ServerSignals.DepthReached:Fire(player, meters)
		end
	end

	-- oxygen
	local zone = Zones.list[zoneIndex]
	local drain = zone.oxygenDrain * (1 + dive.cursedDrain) * stats.oxygenEfficiency
	if not data.Tutorial.Done then
		drain *= 0.4
	end
	dive.oxygen = math.max(0, dive.oxygen - drain * dt)

	-- pressure
	local pressureLevel = 0
	if meters > stats.maxDepth then
		pressureLevel = 2
		local excess = meters - stats.maxDepth
		local damage = (Game.Dive.PressureDamagePerSecond + excess / 100 * Game.Dive.PressureDamagePer100m) * dt
		dive.hull = math.max(0, dive.hull - damage)
	elseif meters > stats.maxDepth - Game.Dive.PressureWarningMeters then
		pressureLevel = 1
	end
	if player:GetAttribute("DivePressure") ~= pressureLevel then
		player:SetAttribute("DivePressure", pressureLevel)
	end
	setAttributes(player, dive)

	if dive.oxygen <= 0 or dive.hull <= 0 then
		SubService.endDive(player, "Blackout")
		return
	end
	if pos.Y > Game.Dive.SurfaceY and now >= dive.surfaceArmedAt then
		SubService.endDive(player, "Surface")
	end
end

function SubService.Init()
	subsFolder = Instance.new("Folder")
	subsFolder.Name = "Subs"
	subsFolder.Parent = workspace
end

function SubService.Start()
	Remotes.on("Dive", 1, 2, function(player, options)
		local insure = typeof(options) == "table" and options.insure == true
		startDive(player, insure)
	end)
	Remotes.on("EmergencySurface", 1, 2, function(player)
		if SubService.isDiving(player) then
			SubService.endDive(player, "Emergency")
		end
	end)
	Remotes.on("UseConsumable", 2, 3, function(player, key)
		if not Validate.oneOf(key, { OxygenRefill = true, HullRepair = true, CargoInsurance = true }) then
			return
		end
		local data = DataService.get(player)
		if not data or (data.Consumables[key] or 0) <= 0 then
			return
		end
		if not SubService.isDiving(player) then
			Remotes.notify(player, "Use that during a dive.", "info")
			return
		end
		local used = false
		if key == "OxygenRefill" then
			used = SubService.refillOxygen(player)
		elseif key == "HullRepair" then
			used = SubService.repairHull(player)
		elseif key == "CargoInsurance" then
			used = SubService.insureCurrent(player)
		end
		if used then
			data.Consumables[key] -= 1
			DataService.replicate(player, "Consumables")
		end
	end)

	ServerSignals.ItemObtained:Connect(function(player)
		local dive = SubService.dive(player)
		if dive then
			dive.cursedDrain = InventoryService.cursedDrain(player)
		end
	end)
	ServerSignals.PlayerLeaving:Connect(function(player)
		SubService.endDive(player, "Left")
		characterDefaults[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			if SubService.isDiving(player) then
				SubService.endDive(player, "Blackout")
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			if SubService.isDiving(player) then
				SubService.endDive(player, "Blackout")
			end
		end)
	end

	local accumulator = 0
	local interval = 1 / Game.Dive.TickRate
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < interval then
			return
		end
		local step = accumulator
		accumulator = 0
		for _, state in PlayerState.divers() do
			local ok, err = pcall(tickDive :: (...any) -> ...any, state, step)
			if not ok then
				warn("[DeepHaul] dive tick failed for " .. state.player.Name .. ": " .. tostring(err))
			end
		end
	end)
end

return SubService

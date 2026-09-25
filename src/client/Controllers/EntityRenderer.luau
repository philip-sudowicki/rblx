--!strict
-- Draws every wild fish, treasure and predator the server streams to this client.
-- * Fish follow the deterministic FishPath (same maths the server validates against), with
--   tail wag, body waves and colour animation, all moved with one BulkMoveTo per frame.
-- * Models are pooled per species and only exist while visible. In dark zones only loot inside
--   your Floodlights radius is drawn; bioluminescent fish show a glow further out.
-- * Epic+ spawns trigger a "nearby!" alert and carry a marker you can follow.
-- * Predators are interpolated from 10 Hz server snapshots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local Zones = require(Shared.Config.Zones)
local Predators = require(Shared.Config.Predators)
local FishPath = require(Shared.Modules.FishPath)
local DepthMath = require(Shared.Modules.DepthMath)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local FishModel = require(Shared.Models.FishModel)
local TreasureModel = require(Shared.Models.TreasureModel)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local HUDController = require(script.Parent.HUDController)
local EffectsController = require(script.Parent.EffectsController)
local FishAnimator = require(script.Parent.Parent.Render.FishAnimator)

export type FishView = {
	id: number,
	fishId: string,
	tier: number,
	record: any,
	built: FishModel.Built?,
	position: Vector3,
	phase: number,
	length: number,
	glowDot: BillboardGui?,
	marker: BillboardGui?,
	glow: boolean,
}

export type TreasureView = {
	id: number,
	treasureId: string,
	tier: number,
	record: any,
	built: TreasureModel.Built?,
	position: Vector3,
	phase: number,
	marker: BillboardGui?,
}

export type PredatorView = {
	id: number,
	typeId: string,
	built: FishModel.Built,
	from: Vector3,
	to: Vector3,
	velocity: Vector3,
	fromTime: number,
	toTime: number,
	state: number,
	position: Vector3,
	lastSeen: number,
}

local EntityRenderer = {}

EntityRenderer.fish = {} :: { [number]: FishView }
EntityRenderer.treasure = {} :: { [number]: TreasureView }
EntityRenderer.predators = {} :: { [number]: PredatorView }
EntityRenderer.FishRemoved = Signal.new() :: Signal.Signal<number>

local player = Players.LocalPlayer
local folder: Folder
local fishPool: { [string]: { FishModel.Built } } = {}
local treasurePool: { [string]: { TreasureModel.Built } } = {}
local PREDATOR_TYPES: { string } = {}
for index, def in Predators.list do
	PREDATOR_TYPES[index] = def.id
end
local MAX_VISIBLE_FISH = 40

local function lowGraphics(): boolean
	return ClientState.data ~= nil and ClientState.data.Settings.Graphics == "Low"
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------- pooling
local function acquireFish(view: FishView): FishModel.Built
	local pool = fishPool[view.fishId]
	if pool and #pool > 0 then
		local built = table.remove(pool) :: FishModel.Built
		built.model.Parent = folder
		return built
	end
	local def = Fish.byId[view.fishId]
	local built = FishModel.build(def.model, { rarity = view.tier, simple = lowGraphics() })
	built.model.Parent = folder
	return built
end

local function releaseFish(view: FishView)
	local built = view.built
	if built then
		built.model.Parent = nil
		local pool = fishPool[view.fishId]
		if not pool then
			pool = {}
			fishPool[view.fishId] = pool
		end
		if #pool < 6 then
			table.insert(pool, built)
		else
			built.model:Destroy()
		end
		view.built = nil
	end
end

local function acquireTreasure(view: TreasureView): TreasureModel.Built
	local pool = treasurePool[view.treasureId]
	if pool and #pool > 0 then
		local built = table.remove(pool) :: TreasureModel.Built
		built.model.Parent = folder
		return built
	end
	local def = Treasure.byId[view.treasureId]
	local built = TreasureModel.build(def.model, { rarity = view.tier, simple = lowGraphics() })
	built.model.Parent = folder
	return built
end

local function releaseTreasure(view: TreasureView)
	local built = view.built
	if built then
		built.model.Parent = nil
		local pool = treasurePool[view.treasureId]
		if not pool then
			pool = {}
			treasurePool[view.treasureId] = pool
		end
		if #pool < 4 then
			table.insert(pool, built)
		else
			built.model:Destroy()
		end
		view.built = nil
	end
end

---------------------------------------------------------------- markers
local function marker(adornee: Instance, text: string, color: Color3, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	gui.Adornee = adornee
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end
EntityRenderer.marker = marker

local anchorParts: { [number]: Part } = {}
-- Invisible anchor part at a world position (for billboards on loot that isn't drawn yet).
local function anchorFor(id: number, position: Vector3): Part
	local existing = anchorParts[id]
	if existing then
		existing.Position = position
		return existing
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = folder
	anchorParts[id] = part
	return part
end
EntityRenderer.anchorFor = anchorFor

local function dropAnchor(id: number)
	local part = anchorParts[id]
	if part then
		part:Destroy()
		anchorParts[id] = nil
	end
end

local lastAlert = 0
local function alertFor(view: FishView)
	local rarity = Rarities.list[view.tier]
	if not rarity.alert then
		return
	end
	local def = Fish.byId[view.fishId]
	view.marker = marker(anchorFor(view.id, view.position), "✦ " .. rarity.name:upper() .. " ✦", rarity.color, if rarity.index >= 5 then 400 else 180)
	if os.clock() - lastAlert > 4 then
		lastAlert = os.clock()
		local name = if rarity.hidden then "???" else def.name
		HUDController.toast(string.format("✦ A %s %s is nearby!", rarity.name:upper(), name), if rarity.index >= 5 then "warn" else "info", "🐟")
		AudioController.play("RareNearby", 1 + (rarity.index - 4) * 0.05)
	end
end

---------------------------------------------------------------- network
local function addFish(record: any)
	local def = Fish.byId[record.f]
	if not def or EntityRenderer.fish[record.id] then
		return
	end
	local view: FishView = {
		id = record.id,
		fishId = record.f,
		tier = Rarities.byId[def.rarity].index,
		record = record,
		built = nil,
		position = record.h,
		phase = math.random() * 6.28,
		length = def.model.length,
		glowDot = nil,
		marker = nil,
		glow = def.model.glow == true,
	}
	EntityRenderer.fish[record.id] = view
	alertFor(view)
end

local function removeFish(id: number)
	local view = EntityRenderer.fish[id]
	if not view then
		return
	end
	releaseFish(view)
	if view.glowDot then
		view.glowDot:Destroy()
	end
	if view.marker then
		view.marker:Destroy()
	end
	dropAnchor(id)
	EntityRenderer.fish[id] = nil
	EntityRenderer.FishRemoved:Fire(id)
end

local function addTreasure(record: any)
	local def = Treasure.byId[record.i]
	if not def or EntityRenderer.treasure[record.id] then
		return
	end
	local tier = Rarities.byId[def.rarity].index
	local view: TreasureView = {
		id = record.id,
		treasureId = record.i,
		tier = tier,
		record = record,
		built = nil,
		position = record.p,
		phase = math.random() * 6.28,
		marker = nil,
	}
	EntityRenderer.treasure[record.id] = view
	if record.src == "Galleon" or record.src == "Wake" then
		view.marker = marker(anchorFor(record.id, record.p), "✦", Rarities.list[tier].color, 260)
	end
end

local function removeTreasure(id: number)
	local view = EntityRenderer.treasure[id]
	if not view then
		return
	end
	releaseTreasure(view)
	if view.marker then
		view.marker:Destroy()
	end
	dropAnchor(id)
	EntityRenderer.treasure[id] = nil
end

function EntityRenderer.clear()
	for id in EntityRenderer.fish do
		removeFish(id)
	end
	for id in EntityRenderer.treasure do
		removeTreasure(id)
	end
	for id, view in EntityRenderer.predators do
		view.built.model:Destroy()
		EntityRenderer.predators[id] = nil
	end
end

local function onEntities(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.f then
		for _, record in payload.f do
			addFish(record)
		end
	end
	if payload.t then
		for _, record in payload.t do
			addTreasure(record)
		end
	end
	if payload.u then
		for _, record in payload.u do
			local view = EntityRenderer.fish[record.id]
			if view then
				view.record = record
			end
		end
	end
	if payload.tu then
		for _, record in payload.tu do
			local view = EntityRenderer.treasure[record.id]
			if view then
				view.record = record
			end
		end
	end
	if payload.r then
		for _, id in payload.r do
			removeFish(id)
			removeTreasure(id)
		end
	end
end

local function onPredators(serverTime: number, list: any)
	if typeof(list) ~= "table" or not SubController.isDiving() then
		return
	end
	local now = os.clock()
	local seen: { [number]: boolean } = {}
	for _, entry in list do
		local id, typeIndex, position, velocity, state = entry[1], entry[2], entry[3], entry[4], entry[5]
		local typeId = PREDATOR_TYPES[typeIndex]
		if typeof(id) == "number" and typeId and typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
			seen[id] = true
			local view = EntityRenderer.predators[id]
			if not view then
				local def = Predators.byId[typeId]
				local built = FishModel.build({ shape = def.shape, length = def.length, primary = def.primary, secondary = def.secondary, pattern = "belly" }, { predator = true, simple = lowGraphics() })
				built.model.Name = "Predator"
				built.model.Parent = folder
				view = {
					id = id,
					typeId = typeId,
					built = built,
					from = position,
					to = position,
					velocity = velocity,
					fromTime = serverTime,
					toTime = serverTime,
					state = state,
					position = position,
					lastSeen = now,
				}
				EntityRenderer.predators[id] = view
			else
				view.from = view.position
				view.to = position
				view.fromTime = serverNow()
				view.toTime = serverNow() + 0.12
				view.velocity = velocity
				view.state = state
				view.lastSeen = now
			end
		end
	end
	for id, view in EntityRenderer.predators do
		if not seen[id] and now - view.lastSeen > 1.5 then
			view.built.model:Destroy()
			EntityRenderer.predators[id] = nil
		end
	end
end

---------------------------------------------------------------- rendering
local fishParts: { BasePart } = {}
local fishFrames: { CFrame } = {}

local function place(built: FishModel.Built, cf: CFrame, t: number, phase: number, length: number, speed: number)
	FishAnimator.append(built, cf, t, phase, length, speed, fishParts, fishFrames)
end

local tint = FishAnimator.tint

local function glowDotFor(view: FishView)
	if view.glowDot then
		return
	end
	local def = Fish.byId[view.fishId]
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(18, 18)
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = def.model.secondary
	dot.BackgroundTransparency = 0.2
	dot.BorderSizePixel = 0
	dot.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	gui.Adornee = anchorFor(view.id, view.position)
	gui.Parent = player:WaitForChild("PlayerGui")
	view.glowDot = gui
end

local elapsed = 0
local function step(dt: number)
	if not SubController.isDiving() then
		return
	end
	local camera = workspace.CurrentCamera
	local root = SubController.root
	if not camera or not root then
		return
	end
	elapsed += dt * EffectsController.timeScale
	local now = serverNow()
	local t = elapsed
	local camPos = camera.CFrame.Position
	local zone = Zones.list[DepthMath.zoneIndexAtY(camPos.Y)]
	local lightRadius = ClientState.stats().lightRadius
	local drawRadius = if zone.dark then lightRadius + 12 else 260
	local glowRadius = if zone.dark then math.max(lightRadius * 2.6, 140) else 260
	local low = lowGraphics()

	table.clear(fishParts)
	table.clear(fishFrames)
	local visibleCount = 0
	for _, view in EntityRenderer.fish do
		local r = view.record
		local position: Vector3
		if r.fz and r.g then
			position = (r.fz :: Vector3) + Vector3.new(math.sin(t * 17) * 0.25, math.sin(t * 13) * 0.2, 0)
		else
			position = FishPath.position(r.h, r.s, r.t0, now, r.sp or 1, r.ph, r.tf)
		end
		local moved = position - view.position
		view.position = position
		local distance = (position - camPos).Magnitude
		local visible = distance <= drawRadius and visibleCount < MAX_VISIBLE_FISH
		if visible then
			visibleCount += 1
			if not view.built then
				view.built = acquireFish(view)
			end
			local velocity = FishPath.velocity(r.s, now - r.t0, r.sp or 1)
			if moved.Magnitude > 0.05 and moved.Magnitude < 20 then
				velocity = moved
			end
			local forward = if velocity.Magnitude > 0.01 then velocity.Unit else Vector3.new(0, 0, -1)
			local cf = CFrame.lookAt(position, position + forward)
			local built = view.built :: FishModel.Built
			if low and distance > 80 then
				built.model:PivotTo(cf)
			else
				place(built, cf, t, view.phase, view.length, 1)
			end
			tint(built, t)
		elseif view.built then
			releaseFish(view)
		end
		-- bioluminescent glow beyond your lights
		if view.glow and zone.dark and distance > drawRadius and distance < glowRadius then
			glowDotFor(view)
			anchorFor(view.id, position)
		elseif view.glowDot then
			view.glowDot:Destroy()
			view.glowDot = nil
		end
		if view.marker then
			anchorFor(view.id, position)
		end
	end
	if #fishParts > 0 then
		workspace:BulkMoveTo(fishParts, fishFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	for _, view in EntityRenderer.treasure do
		local distance = (view.position - camPos).Magnitude
		local rarity = Rarities.list[view.tier]
		local radius = if zone.dark then (if rarity.index >= 3 then lightRadius * 1.8 else drawRadius) else 240
		if distance <= radius then
			if not view.built then
				view.built = acquireTreasure(view)
			end
			local bob = math.sin(t * 1.6 + view.phase) * 0.25
			local cf = CFrame.new(view.position + Vector3.new(0, bob + 0.3, 0)) * CFrame.Angles(0, t * 0.6 + view.phase, 0)
			TreasureModel.place(view.built :: TreasureModel.Built, cf, true)
			tint(view.built :: any, t)
		elseif view.built then
			releaseTreasure(view)
		end
	end

	for _, view in EntityRenderer.predators do
		local span = math.max(view.toTime - view.fromTime, 0.05)
		local alpha = math.clamp((now - view.fromTime) / span, 0, 1.5)
		local position = view.from:Lerp(view.to, math.min(alpha, 1)) + view.velocity * math.max(0, alpha - 1) * span
		view.position = position
		local forward = if view.velocity.Magnitude > 0.5 then view.velocity.Unit else Vector3.new(0, 0, -1)
		local cf = CFrame.lookAt(position, position + forward)
		if view.state == 4 then
			cf = cf * CFrame.Angles(0, 0, math.sin(t * 10) * 0.4)
		end
		local def = Predators.byId[view.typeId]
		view.built.model:SetAttribute("State", view.state)
		table.clear(fishParts)
		table.clear(fishFrames)
		place(view.built, cf, t * (if view.state == 2 then 1.6 else 1), 0, def.length, 1)
		workspace:BulkMoveTo(fishParts, fishFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EntityRenderer.fishPosition(id: number): Vector3?
	local view = EntityRenderer.fish[id]
	return view and view.position
end

function EntityRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientLoot"
	folder.Parent = workspace
end

function EntityRenderer.Start()
	Net.event("Entities").OnClientEvent:Connect(onEntities)
	Net.unreliable("Predators").OnClientEvent:Connect(onPredators)
	SubController.Ended:Connect(EntityRenderer.clear)
	RunService.RenderStepped:Connect(step)
end

return EntityRenderer

--!strict
-- Automated events on screen and in the world:
--   * an event widget: live events with time left (Super events and Weekend Luck included), or
--     the next event and its countdown; it sits top-centre at the dock and top-left while diving
--   * a big countdown banner for the last 60 seconds before an event, with start / end sounds
--   * the Leviathan: rendered from the shared LeviathanPath, with a follow marker and its call
--   * the Sunken Galleon marker, Deep Tremor camera shakes and rumbles, the Blood Moon night sky

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Events = require(Shared.Config.Events)
local Zones = require(Shared.Config.Zones)
local LeviathanPath = require(Shared.Modules.LeviathanPath)
local DepthMath = require(Shared.Modules.DepthMath)
local Format = require(Shared.Modules.Format)
local FishModel = require(Shared.Models.FishModel)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local FishAnimator = require(script.Parent.Parent.Render.FishAnimator)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)

local EventController = {}

local LEVIATHAN_DRAW_RADIUS = 900
local LEVIATHAN_CALL_RADIUS = 450

local widget: Frame
local rows: Frame
local countdown: TextLabel
local countdownSub: TextLabel
local leviathanMarker: BillboardGui
local leviathanMarkerText: TextLabel
local galleonMarker: BillboardGui
local galleonMarkerText: TextLabel
local markerAnchor: Part
local galleonAnchor: Part
local leviathan: FishModel.Built? = nil
local leviathanParts: { BasePart } = {}
local leviathanFrames: { CFrame } = {}
local sky: Sky
local lastActiveKey = ""
local lastCountdownSecond = -1
local nextCallAt = 0
local nextTremorAt = 0

local function now(): number
	return ClientState.serverTime()
end

local function activeList(): { any }
	local state = ClientState.events
	if state and typeof(state.active) == "table" then
		return state.active
	end
	return {}
end

local function activeEntry(id: string): any
	for _, entry in activeList() do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function isWeekend(): boolean
	local state = ClientState.events
	return state ~= nil and state.weekend == true
end

---------------------------------------------------------------- widget

local function addRow(text: string, color: Color3, order: number, big: boolean?)
	local label = UIKit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, if big then 26 else 20),
		TextSize = if big then 18 else 14,
		Font = if big then Theme.FontDisplay else Theme.FontBold,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order,
		Parent = rows,
	})
	UIKit.textStroke(1.5).Parent = label
end

local function refreshWidget()
	for _, child in rows:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local t = now()
	local active = activeList()
	local order = 0
	if #active >= 2 then
		order += 1
		addRow("⚡ SUPER EVENT ⚡", Theme.Coin, order, true)
	end
	for _, entry in active do
		local def = Events.byId[entry.id]
		if def then
			order += 1
			local suffix = if entry.source == "local" then "  (this server)" else ""
			addRow(string.format("%s %s  ·  %s left%s", def.icon, def.name, Format.clock(math.max(0, entry.endsAt - t)), suffix), def.color, order, #active < 2)
		end
	end
	local galleonZone = ReplicatedStorage:GetAttribute("GalleonZone")
	if typeof(galleonZone) == "number" and galleonZone > 0 and Zones.list[galleonZone] then
		order += 1
		addRow("🏴‍☠️ Galleon wreck in the " .. Zones.list[galleonZone].name, Events.byId.Galleon.color, order)
	end
	if #active == 0 then
		local state = ClientState.events
		if state and typeof(state.nextStartsAt) == "number" and typeof(state.nextEvents) == "table" then
			local names = {}
			for _, id in state.nextEvents do
				local def = Events.byId[id]
				if def then
					table.insert(names, def.icon .. " " .. def.short)
				end
			end
			order += 1
			addRow(string.format("Next event%s: %s in %s", if state.nextSuper then " (SUPER)" else "", table.concat(names, " + "), Format.clock(math.max(0, state.nextStartsAt - t))), Theme.TextMuted, order)
		end
	end
	if isWeekend() then
		order += 1
		addRow(string.format("🍀 %s: x%s luck", Events.weekend.name, tostring(Events.weekend.luck)), Theme.Good, order)
	end
	widget.Visible = order > 0 and ClientState.ready
end

local function placeWidget()
	local inset = GuiService.TopbarInset.Height
	if SubController.isDiving() then
		widget.AnchorPoint = Vector2.new(0, 0)
		widget.Position = UDim2.fromOffset(16, inset + 140)
	else
		widget.AnchorPoint = Vector2.new(0.5, 0)
		widget.Position = UDim2.new(0.5, 0, 0, inset + 8)
	end
end

---------------------------------------------------------------- countdown

local function refreshCountdown()
	local state = ClientState.events
	local t = now()
	if not state or #activeList() > 0 or typeof(state.nextStartsAt) ~= "number" then
		countdown.Visible = false
		countdownSub.Visible = false
		return
	end
	local remaining = state.nextStartsAt - t
	if remaining > Events.schedule.countdownSeconds or remaining < 0 then
		countdown.Visible = false
		countdownSub.Visible = false
		lastCountdownSecond = -1
		return
	end
	local first = Events.byId[state.nextEvents[1]]
	if not first then
		return
	end
	local names = {}
	for _, id in state.nextEvents do
		local def = Events.byId[id]
		if def then
			table.insert(names, def.name:upper())
		end
	end
	countdown.Visible = true
	countdownSub.Visible = true
	countdown.Text = string.format("%s%s %s", if state.nextSuper then "⚡ SUPER EVENT: " else "", first.icon, table.concat(names, " + "))
	countdown.TextColor3 = first.color
	local second = math.ceil(remaining)
	countdownSub.Text = string.format("starts in %s", Format.clock(second))
	countdown.TextTransparency = 0.15 * (1 + math.sin(os.clock() * 5)) / 2
	if second ~= lastCountdownSecond then
		lastCountdownSecond = second
		if second == 60 or second == 30 or second == 10 or (second <= 3 and second >= 1) then
			AudioController.play("EventCountdown", if second <= 3 then 1.3 else 1)
		end
	end
end

local function onEventsChanged()
	local keyParts = {}
	for _, entry in activeList() do
		table.insert(keyParts, entry.id)
	end
	table.sort(keyParts)
	local key = table.concat(keyParts, ",")
	if key ~= lastActiveKey then
		local started = #key > #lastActiveKey
		lastActiveKey = key
		if key ~= "" and started then
			AudioController.play("EventStart")
		elseif key == "" then
			AudioController.play("EventEnd")
		end
	end
	refreshWidget()
end

---------------------------------------------------------------- Leviathan

local function ensureLeviathan(): FishModel.Built
	local built = leviathan
	if built then
		return built
	end
	local model = FishModel.build({
		shape = "Eel",
		length = 110,
		primary = Color3.fromRGB(18, 52, 96),
		secondary = Color3.fromRGB(90, 230, 255),
		pattern = "spots",
		glow = true,
		neon = true,
	}, { rarity = 7, simple = ClientState.data ~= nil and ClientState.data.Settings.Graphics == "Low" })
	model.model.Name = "Leviathan"
	model.model.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 220, 255)
	light.Range = 60
	light.Brightness = 2
	light.Parent = model.root
	leviathan = model
	return model
end

local function removeLeviathan()
	local built = leviathan
	if built then
		built.model:Destroy()
		leviathan = nil
	end
	leviathanMarker.Enabled = false
end

local function stepLeviathan(camPos: Vector3)
	local entry = activeEntry("Leviathan")
	if not entry or not SubController.isDiving() then
		removeLeviathan()
		return
	end
	local elapsed = now() - entry.startedAt
	local cf = LeviathanPath.cframe(elapsed)
	local distance = (cf.Position - camPos).Magnitude
	-- the follow marker shows from the zone above down, so divers can find it
	local zoneIndex = DepthMath.zoneIndexAtY(camPos.Y)
	markerAnchor.CFrame = CFrame.new(cf.Position)
	leviathanMarker.Enabled = zoneIndex >= LeviathanPath.zone - 1 and zoneIndex <= LeviathanPath.zone
	leviathanMarkerText.Text = string.format("🐋 Leviathan · %s", Format.meters(math.floor(distance)))
	if distance > LEVIATHAN_DRAW_RADIUS then
		local built = leviathan
		if built then
			built.model:Destroy()
			leviathan = nil
		end
		return
	end
	local built = ensureLeviathan()
	table.clear(leviathanParts)
	table.clear(leviathanFrames)
	FishAnimator.append(built, cf, os.clock(), 0, 110, 0.35, leviathanParts, leviathanFrames)
	FishAnimator.tint(built, os.clock())
	workspace:BulkMoveTo(leviathanParts, leviathanFrames, Enum.BulkMoveMode.FireCFrameChanged)
	if distance < LEVIATHAN_CALL_RADIUS and os.clock() >= nextCallAt then
		nextCallAt = os.clock() + math.random(18, 30)
		AudioController.play("LeviathanCall", 0.8 + math.random() * 0.2, 1 - distance / LEVIATHAN_CALL_RADIUS * 0.6)
		SubController.shake(0.25, 1.2)
	end
end

---------------------------------------------------------------- Galleon / Tremor / Blood Moon

local function stepGalleon(camPos: Vector3)
	local zone = ReplicatedStorage:GetAttribute("GalleonZone")
	local position = ReplicatedStorage:GetAttribute("GalleonPosition")
	if not SubController.isDiving() or typeof(zone) ~= "number" or zone <= 0 or typeof(position) ~= "Vector3" then
		galleonMarker.Enabled = false
		return
	end
	galleonAnchor.CFrame = CFrame.new(position + Vector3.new(0, 30, 0))
	galleonMarker.Enabled = true
	local here = DepthMath.zoneIndexAtY(camPos.Y)
	galleonMarkerText.Text = if here == zone
		then string.format("🏴‍☠️ Galleon · %s", Format.meters(math.floor((position - camPos).Magnitude)))
		else string.format("🏴‍☠️ Galleon · %s", Zones.list[zone].name)
end

local function stepTremor(camPos: Vector3)
	if not activeEntry("DeepTremor") or not SubController.isDiving() then
		return
	end
	local zoneIndex = DepthMath.zoneIndexAtY(camPos.Y)
	if table.find(Events.tremor.zones, zoneIndex) == nil then
		return
	end
	local clock = os.clock()
	if nextTremorAt == 0 then
		nextTremorAt = clock + math.random(4, 10)
	elseif clock >= nextTremorAt then
		nextTremorAt = clock + math.random(14, 22)
		AudioController.play("TremorRumble", 0.9 + math.random() * 0.2)
		SubController.shake(0.9, 1.8)
	end
end

local function stepBloodMoon(camPos: Vector3)
	local night = activeEntry("BloodMoon") ~= nil and camPos.Y > -2
	local clock = if night then 23.6 else Zones.surface.clockTime
	if Lighting.ClockTime ~= clock then
		Lighting.ClockTime = clock
	end
	sky.MoonAngularSize = if night then 40 else 11
end

---------------------------------------------------------------- setup

local function marker(anchor: BasePart, color: Color3): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(220, 34)
	gui.Enabled = false
	gui.ResetOnSpawn = false
	local label = UIKit.label({ Text = "", Size = UDim2.fromScale(1, 1), TextSize = 18, Font = Theme.FontDisplay, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Parent = gui })
	UIKit.textStroke(2).Parent = label
	gui.Parent = ClientState.player:WaitForChild("PlayerGui")
	return gui, label
end

local function anchorPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = workspace
	return part
end

function EventController.Init()
	local gui = UIKit.screen("DeepHaulEvents", 11)
	widget = UIKit.frame({ Name = "EventWidget", BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.35, Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = gui })
	UIKit.corner(Theme.CornerSmall).Parent = widget
	UIKit.padding(6, 10, 6, 10).Parent = widget
	UIKit.scaled(widget)
	rows = UIKit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = widget })
	UIKit.list(Enum.FillDirection.Vertical, 2).Parent = rows
	countdown = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(900, 50),
		Font = Theme.FontDisplay,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	UIKit.textStroke(3).Parent = countdown
	UIKit.scaled(countdown)
	countdownSub = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.2, 40),
		Size = UDim2.fromOffset(600, 30),
		Font = Theme.FontBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	UIKit.textStroke(2).Parent = countdownSub
	UIKit.scaled(countdownSub)
	markerAnchor = anchorPart("DH_LeviathanMarker")
	galleonAnchor = anchorPart("DH_GalleonMarker")
	leviathanMarker, leviathanMarkerText = marker(markerAnchor, Events.byId.Leviathan.color)
	galleonMarker, galleonMarkerText = marker(galleonAnchor, Events.byId.Galleon.color)
	local existing = Lighting:FindFirstChildOfClass("Sky")
	if existing then
		sky = existing
	else
		sky = Instance.new("Sky")
		sky.Name = "DH_Sky"
		sky.Parent = Lighting
	end
end

function EventController.Start()
	ClientState.EventsChanged:Connect(onEventsChanged)
	ClientState.Ready:Connect(refreshWidget)
	SubController.Started:Connect(placeWidget)
	SubController.Ended:Connect(placeWidget)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeWidget)
	ReplicatedStorage:GetAttributeChangedSignal("GalleonZone"):Connect(refreshWidget)
	placeWidget()
	task.spawn(function()
		while true do
			task.wait(1)
			refreshWidget()
		end
	end)
	RunService.RenderStepped:Connect(function()
		refreshCountdown()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		stepLeviathan(camPos)
		stepGalleon(camPos)
		stepTremor(camPos)
		stepBloodMoon(camPos)
	end)
end

return EventController

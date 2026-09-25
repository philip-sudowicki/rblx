--!strict
-- The heads-up display. Minimal during dives: oxygen + hull bars (pulsing red when low), cargo,
-- a depth meter with zone bands and your max-depth line, crosshair, emergency-surface hold bar,
-- pressure warnings with screen cracks and a red vignette, zone banners and toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local Theme = require(Shared.Config.Theme)
local Format = require(Shared.Modules.Format)
local DepthMath = require(Shared.Modules.DepthMath)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local ZoneController = require(script.Parent.ZoneController)

local HUDController = {}

local player = Players.LocalPlayer

HUDController.gui = (nil :: any) :: ScreenGui
HUDController.diveRoot = (nil :: any) :: Frame
HUDController.dockRoot = (nil :: any) :: Frame
HUDController.topLeft = (nil :: any) :: Frame

local coinLabel: TextLabel
local tokenPill: Frame
local tokenLabel: TextLabel
local boostRow: Frame
local oxygenBar: UIKit.Bar
local hullBar: UIKit.Bar
local cargoLabel: TextLabel
local insuredLabel: TextLabel
local silentLabel: TextLabel
local depthLabel: TextLabel
local compactDepth: TextLabel
local depthMeter: Frame
local zoneLabel: TextLabel
local depthMarker: Frame
local maxDepthLine: Frame
local crosshair: Frame
local emergencyFrame: Frame
local emergencyBar: UIKit.Bar
local pressureLabel: TextLabel
local cracks: { Frame } = {}
local vignette: { Frame } = {}
local zoneBanner: TextLabel
local zoneSubBanner: TextLabel
local toastHolder: Frame
local consumableRow: Frame
local consumableButtons: { [string]: TextButton } = {}

local SEGMENT_HEIGHT = 50

local function pill(parent: Instance, icon: string, color: Color3, order: number): (Frame, TextLabel)
	local frame = UIKit.frame({
		Size = UDim2.fromOffset(190, 38),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.corner(UDim.new(1, 0)).Parent = frame
	UIKit.stroke(color, 2, 0.35).Parent = frame
	UIKit.label({
		Text = icon,
		Size = UDim2.fromOffset(34, 38),
		Position = UDim2.fromOffset(6, 0),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local label = UIKit.label({
		Text = "0",
		Size = UDim2.new(1, -48, 1, 0),
		Position = UDim2.fromOffset(42, 0),
		Font = Theme.FontDisplay,
		TextSize = 22,
		TextColor3 = color,
		Parent = frame,
	})
	UIKit.textStroke(1.5).Parent = label
	return frame, label
end

local function buildTopLeft(gui: ScreenGui)
	local holder = UIKit.frame({
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 200),
		Position = UDim2.fromOffset(16, 16),
		Parent = gui,
	})
	UIKit.scaled(holder)
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = holder
	local _, coins = pill(holder, "🪙", Theme.Coin, 1)
	coinLabel = coins
	local tokens, tokenText = pill(holder, "✦", Theme.Token, 2)
	tokenPill = tokens
	tokenLabel = tokenText
	tokenPill.Visible = false
	boostRow = UIKit.frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 30), LayoutOrder = 3, Parent = holder })
	UIKit.list(Enum.FillDirection.Horizontal, 4).Parent = boostRow
	HUDController.topLeft = holder
end

local function buildVitals(root: Frame)
	local vitals = UIKit.panel({
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(470, 74),
		BackgroundTransparency = 0.12,
		Parent = root,
	})
	UIKit.scaled(vitals)
	UIKit.label({ Text = "🫧", Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(26, 24), TextSize = 20, Parent = vitals })
	oxygenBar = UIKit.bar({ Position = UDim2.fromOffset(40, 10), Size = UDim2.fromOffset(300, 20), Parent = vitals }, Theme.Oxygen)
	UIKit.label({ Text = "🛡️", Position = UDim2.fromOffset(10, 40), Size = UDim2.fromOffset(26, 24), TextSize = 18, Parent = vitals })
	hullBar = UIKit.bar({ Position = UDim2.fromOffset(40, 42), Size = UDim2.fromOffset(300, 20), Parent = vitals }, Theme.Hull)
	local cargo = UIKit.frame({
		BackgroundColor3 = Theme.PanelDark,
		Position = UDim2.fromOffset(352, 8),
		Size = UDim2.fromOffset(108, 58),
		Parent = vitals,
	})
	UIKit.corner(Theme.CornerSmall).Parent = cargo
	UIKit.label({ Text = "📦 CARGO", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 4), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.TextMuted, Parent = cargo })
	cargoLabel = UIKit.label({ Text = "0/10", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 24), TextSize = 24, Font = Theme.FontDisplay, TextXAlignment = Enum.TextXAlignment.Center, Parent = cargo })
	UIKit.textStroke(1.5).Parent = cargoLabel
	insuredLabel = UIKit.label({
		Text = "🛡️ INSURED",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(200, 20),
		TextSize = 14,
		Font = Theme.FontBold,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = vitals,
	})
	UIKit.textStroke(1.5).Parent = insuredLabel
	compactDepth = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 44),
		Size = UDim2.fromOffset(360, 26),
		TextSize = 20,
		Font = Theme.FontDisplay,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = vitals,
	})
	UIKit.textStroke(2).Parent = compactDepth
	silentLabel = UIKit.label({
		Text = "🤫 SILENT RUNNING",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 24),
		Size = UDim2.fromOffset(240, 20),
		TextSize = 14,
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = vitals,
	})
	UIKit.textStroke(1.5).Parent = silentLabel
end

local function buildDepthMeter(root: Frame)
	local meter = UIKit.frame({
		Name = "DepthMeter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 96),
		Size = UDim2.fromOffset(150, 60 + SEGMENT_HEIGHT * Zones.count),
		Parent = root,
	})
	UIKit.scaled(meter)
	depthMeter = meter
	depthLabel = UIKit.label({
		Text = "0m",
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.FontDisplay,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = meter,
	})
	UIKit.textStroke(2).Parent = depthLabel
	zoneLabel = UIKit.label({
		Text = "Sunlit Shallows",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.FontBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = meter,
	})
	UIKit.textStroke(1.5).Parent = zoneLabel
	local track = UIKit.frame({
		BackgroundColor3 = Theme.PanelDark,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 58),
		Size = UDim2.fromOffset(18, SEGMENT_HEIGHT * Zones.count),
		Parent = meter,
	})
	UIKit.corner(UDim.new(0, 6)).Parent = track
	UIKit.stroke(Theme.Stroke, 1.5, 0.2).Parent = track
	track.ClipsDescendants = true
	for index, zone in Zones.list do
		local seg = UIKit.frame({
			BackgroundColor3 = zone.color,
			BackgroundTransparency = 0.35,
			Position = UDim2.fromOffset(0, (index - 1) * SEGMENT_HEIGHT),
			Size = UDim2.new(1, 0, 0, SEGMENT_HEIGHT - 1),
			Parent = track,
		})
		local _ = seg
		UIKit.label({
			Text = zone.short,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -24, 0, 58 + (index - 0.5) * SEGMENT_HEIGHT),
			Size = UDim2.fromOffset(100, 16),
			TextSize = 12,
			TextColor3 = zone.color,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.FontBold,
			Parent = meter,
		})
	end
	maxDepthLine = UIKit.frame({
		BackgroundColor3 = Theme.Bad,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 8, 0, 3),
		Position = UDim2.new(0, -4, 0, 0),
		ZIndex = 3,
		Parent = track,
	})
	track.ClipsDescendants = false
	depthMarker = UIKit.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 8),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 4,
		Parent = track,
	})
	UIKit.corner(UDim.new(1, 0)).Parent = depthMarker
	UIKit.stroke(Theme.Background, 2).Parent = depthMarker
end

-- Position (0..1) of a depth on the meter, where each zone takes an equal band.
local function meterFraction(meters: number): number
	local index = DepthMath.zoneIndexAtMeters(meters)
	local zone = Zones.list[index]
	local t = math.clamp((meters - zone.meters[1]) / (zone.meters[2] - zone.meters[1]), 0, 1)
	return ((index - 1) + t) / Zones.count
end

local function buildCenter(root: Frame)
	crosshair = UIKit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.25,
		Parent = root,
	})
	UIKit.corner(UDim.new(1, 0)).Parent = crosshair
	emergencyFrame = UIKit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 60),
		Size = UDim2.fromOffset(260, 44),
		Visible = false,
		Parent = root,
	})
	UIKit.scaled(emergencyFrame)
	local label = UIKit.label({ Text = "🚨 EMERGENCY SURFACE", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Warn, Parent = emergencyFrame })
	UIKit.textStroke(1.5).Parent = label
	emergencyBar = UIKit.bar({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14), Parent = emergencyFrame }, Theme.Warn)
	pressureLabel = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(520, 30),
		Font = Theme.FontDisplay,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Bad,
		Visible = false,
		Parent = root,
	})
	UIKit.scaled(pressureLabel)
	UIKit.textStroke(2).Parent = pressureLabel
end

local function buildCracks(root: Frame)
	-- three procedural crack patterns radiating from the corners, revealed as the hull fails
	local rng = Random.new(5)
	local origins = { Vector2.new(0.02, 0.05), Vector2.new(0.97, 0.9), Vector2.new(0.9, 0.08) }
	for index, origin in origins do
		local pattern = UIKit.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = root })
		local function branch(start: Vector2, angle: number, length: number, depth: number)
			local finish = start + Vector2.new(math.cos(angle), math.sin(angle)) * length
			local mid = (start + finish) / 2
			local segment = UIKit.frame({
				BackgroundColor3 = Color3.fromRGB(220, 240, 255),
				BackgroundTransparency = 0.25,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(mid.X, mid.Y),
				Size = UDim2.new(length, 0, 0, math.max(1, 3 - depth)),
				Rotation = math.deg(angle),
				ZIndex = 20,
				Parent = pattern,
			})
			local _ = segment
			if depth < 3 then
				for _ = 1, 2 do
					branch(finish, angle + rng:NextNumber(-0.7, 0.7), length * rng:NextNumber(0.5, 0.8), depth + 1)
				end
			end
		end
		local baseAngle = math.atan2(0.5 - origin.Y, 0.5 - origin.X)
		for _ = 1, 3 do
			branch(origin, baseAngle + rng:NextNumber(-0.6, 0.6), rng:NextNumber(0.12, 0.2), 0)
		end
		cracks[index] = pattern
	end
end

local function buildVignette(root: Frame)
	local specs = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.22), rot = 90 },
		{ pos = UDim2.fromScale(0, 0.78), size = UDim2.fromScale(1, 0.22), rot = 270 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.18, 1), rot = 0 },
		{ pos = UDim2.fromScale(0.82, 0), size = UDim2.fromScale(0.18, 1), rot = 180 },
	}
	for _, spec in specs do
		local edge = UIKit.frame({
			BackgroundColor3 = Theme.Bad,
			BackgroundTransparency = 1,
			Position = spec.pos,
			Size = spec.size,
			ZIndex = 19,
			Parent = root,
		})
		UIKit.gradient(ColorSequence.new(Color3.new(1, 1, 1)), spec.rot, NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })).Parent = edge
		table.insert(vignette, edge)
	end
end

local function setVignette(alpha: number)
	for _, edge in vignette do
		edge.BackgroundTransparency = 1 - alpha
	end
end

local function buildBanner(gui: ScreenGui)
	zoneBanner = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 70),
		Font = Theme.FontDisplay,
		TextSize = 56,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		Parent = gui,
	})
	UIKit.scaled(zoneBanner)
	UIKit.textStroke(3).Parent = zoneBanner
	zoneSubBanner = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 50),
		Size = UDim2.fromOffset(900, 30),
		Font = Theme.FontBold,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		Parent = gui,
	})
	UIKit.scaled(zoneSubBanner)
	UIKit.textStroke(2).Parent = zoneSubBanner
end

local bannerToken = 0
function HUDController.banner(title: string, subtitle: string?, color: Color3?, seconds: number?)
	bannerToken += 1
	local token = bannerToken
	zoneBanner.Text = title
	zoneBanner.TextColor3 = color or Theme.Text
	zoneSubBanner.Text = subtitle or ""
	zoneBanner.TextTransparency = 1
	zoneSubBanner.TextTransparency = 1
	UIKit.tween(zoneBanner, { TextTransparency = 0 }, 0.4)
	UIKit.tween(zoneSubBanner, { TextTransparency = 0 }, 0.6)
	task.delay(seconds or 2.6, function()
		if token == bannerToken then
			UIKit.tween(zoneBanner, { TextTransparency = 1 }, 0.8)
			UIKit.tween(zoneSubBanner, { TextTransparency = 1 }, 0.8)
		end
	end)
end

local TOAST_COLORS = { info = Theme.Accent, good = Theme.Good, warn = Theme.Warn, bad = Theme.Bad }

function HUDController.toast(text: string, kind: string?, icon: string?)
	local color = TOAST_COLORS[kind or "info"] or Theme.Accent
	local toast = UIKit.panel({
		Size = UDim2.fromOffset(340, 50),
		BackgroundTransparency = 0.1,
		Parent = toastHolder,
	})
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	UIKit.label({ Text = icon or "•", Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(30, 50), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Parent = toast })
	UIKit.label({ Text = text, Position = UDim2.fromOffset(44, 4), Size = UDim2.new(1, -54, 1, -8), TextSize = 15, Parent = toast })
	local scale = UIKit.new("UIScale", { Scale = 0.6, Parent = toast }) :: UIScale
	UIKit.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	task.delay(4, function()
		UIKit.tween(scale, { Scale = 0 }, 0.25)
		task.wait(0.3)
		toast:Destroy()
	end)
	local count = 0
	for _, child in toastHolder:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, child in toastHolder:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
end

local function buildConsumables(root: Frame)
	consumableRow = UIKit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 158),
		Size = UDim2.fromOffset(360, 40),
		Parent = root,
	})
	UIKit.scaled(consumableRow)
	UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = consumableRow
	for index, spec in { { key = "OxygenRefill", icon = "🫧" }, { key = "HullRepair", icon = "🔧" }, { key = "CargoInsurance", icon = "🛡️" } } do
		local button = UIKit.button({
			Size = UDim2.fromOffset(96, 36),
			LayoutOrder = index,
			TextSize = 16,
			Visible = false,
			Parent = consumableRow,
		}, function()
			Net.event("UseConsumable"):FireServer(spec.key)
		end, Theme.PanelLight)
		button:SetAttribute("Icon", spec.icon)
		consumableButtons[spec.key] = button
	end
end

local function refreshConsumables()
	local data = ClientState.data
	if not data then
		return
	end
	for key, button in consumableButtons do
		local count = data.Consumables[key] or 0
		local insured = player:GetAttribute("DiveInsured") == true
		button.Visible = count > 0 and not (key == "CargoInsurance" and insured)
		button.Text = string.format("%s x%d", tostring(button:GetAttribute("Icon")), count)
	end
end

local function refreshCoins()
	local data = ClientState.data
	if not data then
		return
	end
	coinLabel.Text = Format.short(data.Coins)
	tokenPill.Visible = data.Tokens > 0 or data.Rebirths > 0
	tokenLabel.Text = Format.commas(data.Tokens)
end

local function refreshBoosts()
	for _, child in boostRow:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local data = ClientState.data
	if not data then
		return
	end
	local now = os.time()
	local function add(text: string, color: Color3)
		local label = UIKit.label({
			Text = text,
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 14,
			Font = Theme.FontBold,
			TextColor3 = color,
			BackgroundTransparency = 0.3,
			BackgroundColor3 = Theme.PanelDark,
			Parent = boostRow,
		})
		UIKit.corner(UDim.new(1, 0)).Parent = label
		UIKit.padding(2, 8).Parent = label
	end
	for id, expiry in data.Boosts do
		local def = (Game.Boosts :: any)[id]
		if def and expiry > now then
			add(string.format("%s %s", def.icon, Format.clock(expiry - now)), Theme.Good)
		end
	end
	local serverLuck = ReplicatedStorage:GetAttribute("ServerLuckUntil")
	if typeof(serverLuck) == "number" and serverLuck > now then
		add(string.format("🌟 Server x%s %s", tostring(ReplicatedStorage:GetAttribute("ServerLuckMult") or 2), Format.clock(serverLuck - now)), Theme.Coin)
	end
end

local lastPulse = 0
local lastHull = 100
local function stepDive()
	local diving = SubController.isDiving()
	HUDController.diveRoot.Visible = diving
	if not diving then
		setVignette(0)
		return
	end
	local stats = ClientState.stats()
	local o2 = player:GetAttribute("DiveO2")
	local o2max = player:GetAttribute("DiveO2Max")
	local hull = player:GetAttribute("DiveHull")
	local oxygen = if typeof(o2) == "number" then o2 else stats.oxygen
	local maxOxygen = if typeof(o2max) == "number" and o2max > 0 then o2max else stats.oxygen
	local hullValue = if typeof(hull) == "number" then hull else 100
	local o2Fraction = oxygen / maxOxygen
	local hullFraction = hullValue / 100
	oxygenBar.set(o2Fraction, string.format("OXYGEN %ds", math.ceil(oxygen)))
	hullBar.set(hullFraction, string.format("HULL %d%%", math.ceil(hullValue)))
	local t = os.clock()
	local pulse = (math.sin(t * 8) + 1) / 2
	local lowO2 = o2Fraction < Game.Dive.LowOxygenFraction
	local lowHull = hullFraction < Game.Dive.LowHullFraction
	oxygenBar.fill.BackgroundColor3 = if lowO2 then Theme.Oxygen:Lerp(Theme.Bad, pulse) else Theme.Oxygen
	hullBar.fill.BackgroundColor3 = if lowHull then Theme.Hull:Lerp(Theme.Bad, pulse) else Theme.Hull
	local cargo = ClientState.cargoCount()
	cargoLabel.Text = string.format("%d/%d", cargo, stats.cargo)
	cargoLabel.TextColor3 = if cargo >= stats.cargo then Theme.Warn else Theme.Text
	insuredLabel.Visible = player:GetAttribute("DiveInsured") == true
	silentLabel.Visible = InputController.silent

	local root = SubController.root
	if root then
		local meters = DepthMath.metersAtY(root.Position.Y)
		depthLabel.Text = Format.meters(math.floor(meters))
		local zone = Zones.list[DepthMath.zoneIndexAtY(root.Position.Y)]
		zoneLabel.Text = zone.name
		zoneLabel.TextColor3 = zone.color
		depthMarker.Position = UDim2.new(0.5, 0, meterFraction(meters), 0)
		local touch = InputController.mode == "Touch"
		depthMeter.Visible = not touch
		compactDepth.Visible = touch
		if touch then
			compactDepth.Text = string.format("%s  ·  %s", Format.meters(math.floor(meters)), zone.name)
			compactDepth.TextColor3 = zone.color
		end
		maxDepthLine.Position = UDim2.new(0, -4, meterFraction(stats.maxDepth), 0)
	end
	crosshair.Visible = InputController.mode == "KeyboardMouse" and not InputController.cursorFree

	local progress = InputController.emergencyProgress()
	emergencyFrame.Visible = progress > 0
	emergencyBar.set(progress, string.format("%.1fs", (1 - progress) * Game.Dive.EmergencyHoldSeconds))

	local pressure = player:GetAttribute("DivePressure")
	if pressure == 2 then
		pressureLabel.Visible = true
		pressureLabel.Text = "⚠ CRUSH DEPTH! HULL FAILING - ASCEND!"
		pressureLabel.TextTransparency = pulse * 0.5
	elseif pressure == 1 then
		pressureLabel.Visible = true
		pressureLabel.Text = "Approaching max depth"
		pressureLabel.TextTransparency = 0.2
		pressureLabel.TextColor3 = Theme.Warn
	elseif lowO2 then
		pressureLabel.Visible = true
		pressureLabel.Text = "⚠ LOW OXYGEN - SURFACE SOON!"
		pressureLabel.TextColor3 = Theme.Bad
		pressureLabel.TextTransparency = pulse * 0.5
	else
		pressureLabel.Visible = false
	end
	if pressure == 2 then
		pressureLabel.TextColor3 = Theme.Bad
	end

	cracks[1].Visible = hullFraction < 0.6 or pressure == 2
	cracks[2].Visible = hullFraction < 0.35
	cracks[3].Visible = hullFraction < 0.15
	local danger = 0
	if pressure == 2 or lowHull then
		danger = math.max(danger, 0.35 + pulse * 0.25)
	end
	if lowO2 then
		danger = math.max(danger, 0.25 + pulse * 0.2)
	end
	if hullValue < lastHull - 0.5 then
		lastPulse = t
	end
	lastHull = hullValue
	local hit = math.clamp(1 - (t - lastPulse) / 0.5, 0, 1) * 0.55
	setVignette(math.max(danger, hit))
end

function HUDController.Init()
	local gui = UIKit.screen("DeepHaulHUD", 5)
	HUDController.gui = gui
	buildTopLeft(gui)
	local diveRoot = UIKit.frame({ Name = "Dive", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	HUDController.diveRoot = diveRoot
	local dockRoot = UIKit.frame({ Name = "Dock", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	HUDController.dockRoot = dockRoot
	buildVignette(diveRoot)
	buildCracks(diveRoot)
	buildVitals(diveRoot)
	buildDepthMeter(diveRoot)
	buildCenter(diveRoot)
	buildConsumables(diveRoot)
	buildBanner(gui)
	toastHolder = UIKit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -150),
		Size = UDim2.fromOffset(340, 300),
		Parent = gui,
	})
	UIKit.scaled(toastHolder)
	local toastLayout = UIKit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	toastLayout.Parent = toastHolder
end

function HUDController.Start()
	ClientState.Changed:Connect(function(key)
		if key == "*" or key == "Coins" or key == "Tokens" or key == "Rebirths" then
			refreshCoins()
		end
		if key == "*" or key == "Consumables" then
			refreshConsumables()
		end
		if key == "*" or key == "Boosts" then
			refreshBoosts()
		end
	end)
	player:GetAttributeChangedSignal("DiveInsured"):Connect(refreshConsumables)
	Net.event("Notify").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.text) == "string" then
			HUDController.toast(payload.text, payload.kind, payload.icon)
		end
	end)
	ZoneController.ZoneChanged:Connect(function(index)
		if index > 0 and SubController.isDiving() then
			local zone = Zones.list[index]
			HUDController.banner(zone.name:upper(), string.format("%s - %s", Format.meters(zone.meters[1]), zone.hazard), zone.color, 3)
		end
	end)
	SubController.Started:Connect(function()
		lastHull = 100
		refreshConsumables()
	end)
	RunService.RenderStepped:Connect(stepDive)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshBoosts()
		end
	end)
end

return HUDController

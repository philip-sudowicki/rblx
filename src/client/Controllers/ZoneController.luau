--!strict
-- Per-zone underwater look: fog, ambient light, colour correction and bloom, blended smoothly
-- across zone boundaries and toward the surface. In dark zones visibility is set by your
-- Floodlights upgrade. Active events tint the ocean. Also emits "marine snow" around the camera.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Events = require(Shared.Config.Events)
local DepthMath = require(Shared.Modules.DepthMath)
local Signal = require(Shared.Modules.Signal)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)

local ZoneController = {}

ZoneController.zoneIndex = 0 -- 0 = at the surface / dock
ZoneController.ZoneChanged = Signal.new() :: Signal.Signal<number>
ZoneController.underwater = false

type Preset = {
	fogColor: Color3,
	fogStart: number,
	fogEnd: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	tint: Color3,
	saturation: number,
	contrast: number,
	ccBrightness: number,
	bloom: number,
}

local color: ColorCorrectionEffect
local bloom: BloomEffect
local clouds: Clouds
local sunRays: SunRaysEffect
local current: Preset? = nil
local snowPart: Part? = nil
local snow: ParticleEmitter? = nil

local function surfacePreset(): Preset
	local s = Zones.surface
	return {
		fogColor = s.fogColor,
		fogStart = s.fogStart,
		fogEnd = s.fogEnd,
		ambient = s.ambient,
		outdoorAmbient = s.outdoorAmbient,
		brightness = s.brightness,
		tint = s.tint,
		saturation = s.saturation,
		contrast = s.contrast,
		ccBrightness = s.ccBrightness,
		bloom = s.bloom,
	}
end

local function zonePreset(index: number): Preset
	local zone = Zones.list[index]
	local l = zone.lighting
	local preset: Preset = {
		fogColor = l.fogColor,
		fogStart = l.fogStart,
		fogEnd = l.fogEnd,
		ambient = l.ambient,
		outdoorAmbient = l.outdoorAmbient,
		brightness = l.brightness,
		tint = l.tint,
		saturation = l.saturation,
		contrast = l.contrast,
		ccBrightness = l.ccBrightness,
		bloom = l.bloom,
	}
	if zone.dark then
		local radius = ClientState.stats().lightRadius
		preset.fogEnd = radius + 8
		preset.fogStart = radius * 0.12
	end
	return preset
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpPreset(a: Preset, b: Preset, t: number): Preset
	return {
		fogColor = a.fogColor:Lerp(b.fogColor, t),
		fogStart = lerpNumber(a.fogStart, b.fogStart, t),
		fogEnd = lerpNumber(a.fogEnd, b.fogEnd, t),
		ambient = a.ambient:Lerp(b.ambient, t),
		outdoorAmbient = a.outdoorAmbient:Lerp(b.outdoorAmbient, t),
		brightness = lerpNumber(a.brightness, b.brightness, t),
		tint = a.tint:Lerp(b.tint, t),
		saturation = lerpNumber(a.saturation, b.saturation, t),
		contrast = lerpNumber(a.contrast, b.contrast, t),
		ccBrightness = lerpNumber(a.ccBrightness, b.ccBrightness, t),
		bloom = lerpNumber(a.bloom, b.bloom, t),
	}
end

local BLEND = 45

local function presetAt(y: number): Preset
	if y > -2 then
		return surfacePreset()
	end
	local index = DepthMath.zoneIndexAtY(y)
	local zone = Zones.list[index]
	local preset = zonePreset(index)
	local fromTop = zone.topY - y
	local fromBottom = y - zone.bottomY
	if index == 1 and fromTop < 12 then
		preset = lerpPreset(surfacePreset(), preset, math.clamp(fromTop / 12, 0, 1))
	elseif index > 1 and fromTop < BLEND then
		preset = lerpPreset(zonePreset(index - 1), preset, 0.5 + 0.5 * fromTop / BLEND)
	elseif index < Zones.count and fromBottom < BLEND then
		preset = lerpPreset(zonePreset(index + 1), preset, 0.5 + 0.5 * fromBottom / BLEND)
	end
	return preset
end

local function applyEvents(preset: Preset): Preset
	local state = ClientState.events
	if not state or not state.active then
		return preset
	end
	local out = preset
	for _, entry in state.active do
		local def = Events.byId[entry.id]
		if def then
			local v = def.visual
			out = table.clone(out)
			out.fogColor = out.fogColor:Lerp(v.fogTint, 0.35)
			out.ambient = Color3.new(
				math.min(1, out.ambient.R + v.ambientBoost.R * 0.6),
				math.min(1, out.ambient.G + v.ambientBoost.G * 0.6),
				math.min(1, out.ambient.B + v.ambientBoost.B * 0.6)
			)
			out.tint = out.tint:Lerp(v.tint, 0.5)
			if entry.id == "Bloom" then
				out.fogEnd = math.max(out.fogEnd, 170)
				out.bloom += 0.6
			end
		end
	end
	return out
end

local function apply(p: Preset)
	Lighting.FogColor = p.fogColor
	Lighting.FogStart = p.fogStart
	Lighting.FogEnd = p.fogEnd
	Lighting.Ambient = p.ambient
	Lighting.OutdoorAmbient = p.outdoorAmbient
	Lighting.Brightness = p.brightness
	color.TintColor = p.tint
	color.Saturation = p.saturation
	color.Contrast = p.contrast
	color.Brightness = p.ccBrightness
	bloom.Intensity = p.bloom
end

local function eventParticleColor(): Color3?
	local state = ClientState.events
	if not state or not state.active then
		return nil
	end
	for _, entry in state.active do
		local def = Events.byId[entry.id]
		if def and def.visual.particles then
			return def.visual.particles
		end
	end
	return nil
end

local function setupSnow()
	local part = Instance.new("Part")
	part.Name = "MarineSnow"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(90, 50, 90)
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Speed = NumberRange.new(0.2, 0.8)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1) })
	emitter.Acceleration = Vector3.new(0, -0.3, 0)
	emitter.LightEmission = 0.6
	emitter.Parent = part
	snowPart = part
	snow = emitter
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local y = camera.CFrame.Position.Y
	local target = applyEvents(presetAt(y))
	local now = current
	if now == nil then
		current = target
	else
		current = lerpPreset(now, target, 1 - math.exp(-4 * dt))
	end
	apply(current :: Preset)

	local subRoot = SubController.root
	local probeY = if subRoot then subRoot.Position.Y else y
	local index = if probeY > -2 then 0 else DepthMath.zoneIndexAtY(probeY)
	ZoneController.underwater = y < -2
	if index ~= ZoneController.zoneIndex then
		ZoneController.zoneIndex = index
		ZoneController.ZoneChanged:Fire(index)
	end

	local nearSurface = y > -40
	if clouds.Enabled ~= nearSurface then
		clouds.Enabled = nearSurface
		sunRays.Enabled = nearSurface
	end

	if snowPart and snow then
		snowPart.CFrame = CFrame.new(camera.CFrame.Position)
		local graphicsLow = ClientState.data and ClientState.data.Settings.Graphics == "Low"
		local eventColor = eventParticleColor()
		if y < -2 and not graphicsLow then
			snow.Rate = if eventColor then 40 else 16
			snow.Color = ColorSequence.new(eventColor or Color3.fromRGB(220, 235, 255))
			snow.LightEmission = if eventColor then 1 else 0.4
		else
			snow.Rate = 0
		end
	end
end

function ZoneController.Init()
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			child.Parent = nil -- Atmosphere overrides fog; this game drives fog itself
		end
	end
	color = Instance.new("ColorCorrectionEffect")
	color.Name = "DH_Color"
	color.Parent = Lighting
	bloom = Instance.new("BloomEffect")
	bloom.Name = "DH_Bloom"
	bloom.Threshold = 0.95
	bloom.Size = 30
	bloom.Parent = Lighting
	Lighting.ClockTime = Zones.surface.clockTime
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	-- fluffy clouds and soft sun rays at the surface (hidden once you're deep underwater)
	clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = workspace.Terrain
	sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "DH_SunRays"
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.8
	sunRays.Parent = Lighting
	setupSnow()
end

function ZoneController.Start()
	RunService.RenderStepped:Connect(step)
end

return ZoneController

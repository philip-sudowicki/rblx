--!strict
-- All sound playback. Sounds come from Config/Sounds (placeholder ids are skipped or use a
-- built-in fallback). Music and ambience crossfade per zone / dock / event. Volume sliders map
-- to three SoundGroups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Zones = require(Shared.Config.Zones)
local Events = require(Shared.Config.Events)
local ClientState = require(script.Parent.ClientState)
local ZoneController = require(script.Parent.ZoneController)

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
local cache: { [string]: Sound } = {}
local loops: { [string]: Sound } = {}
local currentMusic: Sound? = nil
local currentMusicKey = ""
local currentAmbient: Sound? = nil
local currentAmbientKey = ""

local function resolveId(def: Sounds.SoundDef): string?
	if def.id ~= "" and def.id ~= Sounds.placeholder then
		return def.id
	end
	return def.fallback
end

local function makeSound(key: string): Sound?
	local def = Sounds.sounds[key]
	if not def then
		return nil
	end
	local id = resolveId(def)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = id
	sound.Volume = def.volume
	sound.Looped = def.looped == true
	sound.PlaybackSpeed = def.pitch or 1
	sound.SoundGroup = groups[def.group]
	sound.Parent = SoundService
	return sound
end

-- One-shot. pitch/volume scale are optional multipliers.
local missing: { [string]: boolean } = {}
function AudioController.play(key: string, pitch: number?, volumeScale: number?)
	if missing[key] then
		return
	end
	local base = cache[key]
	if not base then
		local made = makeSound(key)
		if not made then
			missing[key] = true
			return
		end
		base = made
		cache[key] = made
	end
	local def = Sounds.sounds[key]
	local sound = (base :: Sound):Clone()
	sound.PlaybackSpeed = (def.pitch or 1) * (pitch or 1)
	sound.Volume = def.volume * (volumeScale or 1)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(12, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Looping effect on/off (engine hum, alarms, salvage whir …)
function AudioController.loop(key: string, on: boolean, volumeScale: number?, pitch: number?)
	local sound = loops[key]
	if on then
		if not sound then
			local made = makeSound(key)
			if not made then
				return
			end
			loops[key] = made
			sound = made
		end
		local s = sound :: Sound
		local def = Sounds.sounds[key]
		s.Volume = def.volume * (volumeScale or 1)
		s.PlaybackSpeed = (def.pitch or 1) * (pitch or 1)
		if not s.IsPlaying then
			s:Play()
		end
	elseif sound and sound.IsPlaying then
		sound:Stop()
	end
end

local function crossfade(current: Sound?, key: string, isMusic: boolean): Sound?
	if current then
		local old = current
		local tween = TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 })
		tween:Play()
		tween.Completed:Once(function()
			old:Destroy()
		end)
	end
	local sound = makeSound(key)
	if not sound then
		return nil
	end
	local target = sound.Volume
	sound.Volume = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(if isMusic then 2 else 1.5), { Volume = target }):Play()
	return sound
end

local function refreshBeds()
	local index = ZoneController.zoneIndex
	local musicKey = "MusicDock"
	local ambientKey = "AmbientDock"
	if index > 0 then
		musicKey = Zones.list[index].music
		ambientKey = Zones.list[index].ambient
	end
	local events = ClientState.events
	if events and events.active and #events.active > 0 then
		local def = Events.byId[events.active[1].id]
		if def then
			musicKey = def.music
		end
	end
	if musicKey ~= currentMusicKey then
		currentMusicKey = musicKey
		currentMusic = crossfade(currentMusic, musicKey, true)
	end
	if ambientKey ~= currentAmbientKey then
		currentAmbientKey = ambientKey
		currentAmbient = crossfade(currentAmbient, ambientKey, false)
	end
end

local function applyVolumes()
	local data = ClientState.data
	if not data then
		return
	end
	groups.Music.Volume = data.Settings.Music
	groups.SFX.Volume = data.Settings.SFX
	groups.Ambient.Volume = data.Settings.SFX * 0.9
end

function AudioController.Init()
	for _, name in { "Music", "SFX", "Ambient" } do
		local group = Instance.new("SoundGroup")
		group.Name = "DH_" .. name
		group.Volume = if name == "Music" then 0.6 else 0.8
		group.Parent = SoundService
		groups[name] = group
	end
end

function AudioController.Start()
	ZoneController.ZoneChanged:Connect(refreshBeds)
	ClientState.EventsChanged:Connect(refreshBeds)
	ClientState.Changed:Connect(function(key)
		if key == "*" or key == "Settings" then
			applyVolumes()
		end
	end)
	applyVolumes()
	refreshBeds()
	-- occasional whale song and pressure creaks while diving
	task.spawn(function()
		while true do
			task.wait(math.random(25, 60))
			if ZoneController.zoneIndex >= 2 then
				AudioController.play("WhaleCall", 0.8 + math.random() * 0.4, 0.8)
			end
		end
	end)
end

return AudioController

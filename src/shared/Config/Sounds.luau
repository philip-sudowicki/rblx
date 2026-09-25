--!strict
-- Every sound slot in the game. Replace "rbxassetid://0" with real audio ids (see SOUNDS.md).
-- A slot left at rbxassetid://0 plays its `fallback` (a sound built into the Roblox client) if
-- it has one, and is silently skipped otherwise, so the game never errors on missing audio.
--
-- group: "SFX" | "Music" | "Ambient" (volume sliders in Settings)

export type SoundDef = {
	id: string,
	volume: number,
	group: string,
	looped: boolean?,
	pitch: number?,
	fallback: string?,
}

local PLACEHOLDER = "rbxassetid://0"

local sounds: { [string]: SoundDef } = {
	-- UI
	UIClick = { id = PLACEHOLDER, volume = 0.5, group = "SFX" },
	UIHover = { id = PLACEHOLDER, volume = 0.25, group = "SFX" },
	UIOpen = { id = PLACEHOLDER, volume = 0.45, group = "SFX" },
	UIClose = { id = PLACEHOLDER, volume = 0.4, group = "SFX" },
	UIError = { id = PLACEHOLDER, volume = 0.5, group = "SFX" },
	Notify = { id = PLACEHOLDER, volume = 0.45, group = "SFX" },
	Purchase = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	Upgrade = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	CoinGain = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	CoinBurst = { id = PLACEHOLDER, volume = 0.75, group = "SFX" },
	QuestComplete = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	DailyClaim = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	Achievement = { id = PLACEHOLDER, volume = 0.75, group = "SFX" },
	Rebirth = { id = PLACEHOLDER, volume = 0.9, group = "SFX" },

	-- Submarine
	SubLaunch = { id = PLACEHOLDER, volume = 0.7, group = "SFX", fallback = "rbxasset://sounds/impact_water.mp3" },
	SubSurface = { id = PLACEHOLDER, volume = 0.7, group = "SFX", fallback = "rbxasset://sounds/impact_water.mp3" },
	EngineHum = { id = PLACEHOLDER, volume = 0.25, group = "SFX", looped = true },
	Bubbles = { id = PLACEHOLDER, volume = 0.2, group = "SFX", looped = true, fallback = "rbxasset://sounds/action_swim.mp3" },
	SonarPing = { id = PLACEHOLDER, volume = 0.7, group = "SFX", fallback = "rbxasset://sounds/electronicpingshort.wav" },
	SonarBlip = { id = PLACEHOLDER, volume = 0.35, group = "SFX", pitch = 1.4, fallback = "rbxasset://sounds/electronicpingshort.wav" },
	PressureCreak = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	HullCrack = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	Alarm = { id = PLACEHOLDER, volume = 0.45, group = "SFX", looped = true },
	OxygenLow = { id = PLACEHOLDER, volume = 0.45, group = "SFX", looped = true },
	Impact = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	PredatorGrowl = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	Emergency = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	Blackout = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	Refill = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },

	-- Catching and salvage
	MinigameStart = { id = PLACEHOLDER, volume = 0.5, group = "SFX" },
	CatchSuccess = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	CatchPerfect = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	CatchFail = { id = PLACEHOLDER, volume = 0.7, group = "SFX", fallback = "rbxasset://sounds/impact_water.mp3" },
	SalvageLoop = { id = PLACEHOLDER, volume = 0.4, group = "SFX", looped = true },
	SalvageDone = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	RareNearby = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },

	-- Reveal stingers, escalating by rarity
	RevealCommon = { id = PLACEHOLDER, volume = 0.5, group = "SFX" },
	RevealUncommon = { id = PLACEHOLDER, volume = 0.55, group = "SFX" },
	RevealRare = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	RevealEpic = { id = PLACEHOLDER, volume = 0.7, group = "SFX" },
	RevealLegendary = { id = PLACEHOLDER, volume = 0.8, group = "SFX" },
	RevealMythic = { id = PLACEHOLDER, volume = 0.9, group = "SFX" },
	RevealAbyssal = { id = PLACEHOLDER, volume = 0.95, group = "SFX" },
	RevealSecret = { id = PLACEHOLDER, volume = 1, group = "SFX" },

	-- Events
	EventCountdown = { id = PLACEHOLDER, volume = 0.5, group = "SFX" },
	EventStart = { id = PLACEHOLDER, volume = 0.85, group = "SFX" },
	EventEnd = { id = PLACEHOLDER, volume = 0.6, group = "SFX" },
	TremorRumble = { id = PLACEHOLDER, volume = 0.9, group = "SFX" },
	LeviathanCall = { id = PLACEHOLDER, volume = 0.9, group = "Ambient" },
	WhaleCall = { id = PLACEHOLDER, volume = 0.5, group = "Ambient" },

	-- Ambience (looped beds per zone)
	AmbientDock = { id = PLACEHOLDER, volume = 0.4, group = "Ambient", looped = true },
	AmbientShallows = { id = PLACEHOLDER, volume = 0.4, group = "Ambient", looped = true },
	AmbientTwilight = { id = PLACEHOLDER, volume = 0.4, group = "Ambient", looped = true },
	AmbientMidnight = { id = PLACEHOLDER, volume = 0.45, group = "Ambient", looped = true },
	AmbientAbyssal = { id = PLACEHOLDER, volume = 0.45, group = "Ambient", looped = true },
	AmbientHadal = { id = PLACEHOLDER, volume = 0.5, group = "Ambient", looped = true },
	AmbientRift = { id = PLACEHOLDER, volume = 0.5, group = "Ambient", looped = true },

	-- Music (looped)
	MusicDock = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicShallows = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicTwilight = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicMidnight = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicAbyssal = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicHadal = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicRift = { id = PLACEHOLDER, volume = 0.35, group = "Music", looped = true },
	MusicBloom = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
	MusicLeviathan = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
	MusicGalleon = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
	MusicGolden = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
	MusicTremor = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
	MusicBloodMoon = { id = PLACEHOLDER, volume = 0.4, group = "Music", looped = true },
}

return {
	sounds = sounds,
	placeholder = PLACEHOLDER,
}

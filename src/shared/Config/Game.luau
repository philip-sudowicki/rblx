--!strict
-- Global tuning knobs. Distances are studs, times are seconds unless noted.

return {
	DataVersion = 1,

	Economy = {
		StartingCoins = 0,
		UpgradeCostMultiplier = 1, -- scales every upgrade price
		StorageCap = 400, -- secured items you can hold (cargo doesn't count); diving is blocked above this
		DefaultSellKeep = 5, -- Sell All keeps this rarity index and above by default (5 = Legendary)
		BlackoutCargoLoss = 0.5, -- fraction of cargo lost when you black out without insurance
		TutorialBonusCoins = 150, -- granted on the tutorial's "sell" step so the first upgrade is affordable
		TutorialFinishCoins = 250,
	},

	Luck = {
		MutationExponent = 0.5, -- mutation chance × luck^this
		ColossalExponent = 0.5,
		ConditionExponent = 0.35,
		MaxNonCommonChance = 0.95, -- total chance of Uncommon+ is capped here
	},

	Dive = {
		SurfaceY = -4, -- rising above this ends the dive (cargo secured)
		LaunchGraceSeconds = 4, -- the dive can't end by surfacing right after launch
		TickRate = 5, -- oxygen / hull simulation ticks per second
		PressureDamagePerSecond = 3, -- hull % per second just below max depth
		PressureDamagePer100m = 1.2, -- extra hull % per second for every 100 m beyond max depth
		PressureWarningMeters = 60, -- warn when this close to max depth
		LowOxygenFraction = 0.25,
		LowHullFraction = 0.3,
		EmergencyHoldSeconds = 2,
		SilentRunningSpeed = 9, -- speed cap while Silent Running is on
		BoostSpeedMultiplier = 1.55, -- thrusters (hold Q / RB / BOOST): top speed ×
		BoostDrainMultiplier = 2.5, -- …at the cost of this much faster oxygen use
		LaunchDropSpeed = 38, -- studs/s the sub drops from the Launch Bay crane into the water
		CursedDrainCap = 2.0, -- max extra oxygen drain from cursed cargo (+200%)
		StorageBlocksDive = true,
		-- Server movement validation
		SpeedTolerance = 1.6, -- allowed speed = stats.speed × this + SpeedToleranceFlat
		SpeedToleranceFlat = 30,
		MaxStrikesPerMinute = 25, -- after this many snaps in a minute the dive is ended
		BoundsMargin = 25,
	},

	Movement = {
		Acceleration = 2.4, -- how fast velocity approaches the target (per second)
		Drag = 1.1, -- how fast the sub coasts to a stop with no input
		VerticalFactor = 0.8, -- ascend/descend speed as a fraction of top speed
		TurnResponsiveness = 3.5,
		BankAngle = 20, -- degrees of roll when turning hard
		PitchAngle = 14, -- degrees of nose pitch when climbing/diving
		BobAmplitude = 0.35,
		BobFrequency = 0.55,
	},

	Camera = {
		Distance = 20,
		Height = 6,
		Smoothing = 9,
		FOV = 70,
		SpeedFOV = 9, -- extra FOV at top speed
		MinPitch = -70,
		MaxPitch = 55,
		MouseSensitivity = 0.22,
		GamepadSensitivity = 190, -- degrees / second at full stick
		TouchSensitivity = 0.3,
	},

	Catch = {
		Range = 18,
		Tolerance = 10, -- extra server-side range allowance for latency
		Duration = 3.0, -- the minigame never lasts longer than this
		LeadIn = 0.45, -- time between the bar appearing and the marker moving
		TapWindow = 0.45, -- how far in the past a client tap timestamp may be
		PerfectFraction = 0.3, -- centre fraction of the green zone that counts as PERFECT
		PerfectBonus = 1.1, -- value multiplier for PERFECT catches
		WarySeconds = 3, -- after escaping, a fish can't be targeted for this long
		Cooldown = 0.4,
		TutorialZoneWidth = 0.45,
		TutorialSweeps = 0.6,
	},

	Salvage = {
		Range = 16,
		Tolerance = 10,
		CheckInterval = 0.2,
	},

	Sonar = {
		MarkerSeconds = 6,
		StunRadius = 45,
		StunSeconds = 5,
		MaxMarkers = 40,
	},

	Spawns = {
		InterestRadius = 340, -- entities within this of a diver are sent to their client
		DensityRadius = 200, -- fish density is measured within this radius
		TreasureRadius = 260,
		FishSpawnMinDistance = 45,
		FishSpawnMaxDistance = 170,
		FishLifetime = { 90, 150 },
		TreasureLifetime = { 240, 360 },
		FishCap = 450, -- per server
		TreasureCap = 220, -- per server
		UpdateInterval = 0.5, -- interest management tick
		SpawnInterval = 1.0,
		MaxSpawnsPerTick = 4, -- per diver per spawn tick
		WallMargin = 70, -- fish stay this far inside the zone's walls
		FloorMargin = 14,
		CeilingMargin = 12,
		FirstLegendaryGuaranteeMinutes = 45, -- dive minutes without any Legendary+ before one is guaranteed
		DespawnDistance = 460,
	},

	Aquarium = {
		BaseTanks = 6,
		IncomePerMinute = 0.002, -- fraction of a displayed item's value earned per minute
		OfflineCapHours = 8,
		OfflineRate = 1.0, -- offline earnings rate relative to online
		PendingCapHours = 8, -- uncollected income stops growing after this much
		TickSeconds = 30,
		Plots = 12, -- aquarium plots at the dock (set the place's Max Players to at most this)
	},

	-- Personal boosts granted by daily rewards, quests and codes (never sold).
	Boosts = {
		Luck = { name = "Luck Boost", icon = "🍀", multiplier = 2, seconds = 10 * 60, stat = "luck" },
		Sell = { name = "Sell Boost", icon = "💰", multiplier = 1.5, seconds = 10 * 60, stat = "sell" },
		MaxStackSeconds = 2 * 60 * 60,
	},

	Leaderboards = {
		RefreshSeconds = 180,
		WriteSeconds = 150,
		Top = 10,
	},

	Dock = {
		SellRange = 26, -- how close to the Market you must be to sell (unless you own Auto-Sell)
		BoardRange = 18,
	},

	Chat = {
		AnnounceCooldown = 1,
	},

	-- Studio-only debug commands (/coins, /zone, /event …). Also allowed for these user ids live.
	Debug = {
		AllowedUserIds = {} :: { number },
	},
}

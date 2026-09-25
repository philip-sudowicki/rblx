--!strict
-- Automated events.
--
-- Schedule: UTC time is cut into cycles of `cycleSeconds`. Cycle k starts at
-- epochOffset + k × cycleSeconds and its event runs for `durationSeconds`. A 60 s countdown
-- banner shows before each start. The event(s) for cycle k are picked by hashing k with `salt`,
-- so every server in the world picks the same event at the same moment. With `superChance` a
-- cycle becomes a Super Event running two different events at once.
--
-- Modifiers (all optional):
--   luck            multiplies everyone's luck
--   tierMult        { [rarityId] = multiplier } on that tier's chance
--   mutationMult    { [mutationId] = multiplier }
--   enableMutations { mutationId } event-only mutations allowed during this event
--   sellMult        multiplies sell prices
--   exclusiveChance chance a spawn is drawn from this event's exclusive pool
--   predatorAggro   multiplies predator aggro radius and chase speed
--   predatorDensity multiplies predator counts
--   categoryWeight  { [categoryId] = weight multiplier } for treasure picks
--   special         "Leviathan" | "Galleon" | "Tremor" (extra world content)

export type EventDef = {
	id: string,
	name: string,
	short: string,
	desc: string,
	color: Color3,
	icon: string,
	music: string,
	modifiers: {
		luck: number?,
		tierMult: { [string]: number }?,
		mutationMult: { [string]: number }?,
		enableMutations: { string }?,
		sellMult: number?,
		exclusiveChance: number?,
		predatorAggro: number?,
		predatorDensity: number?,
		categoryWeight: { [string]: number }?,
		special: string?,
	},
	visual: {
		fogTint: Color3,
		ambientBoost: Color3,
		tint: Color3,
		particles: Color3?,
		skyMoon: Color3?,
	},
}

local rgb = Color3.fromRGB

local list: { EventDef } = {
	{
		id = "Bloom",
		name = "Bioluminescent Bloom",
		short = "Bloom",
		desc = "The whole ocean glows! Glowing mutations are 10x more likely and glowing exclusives appear.",
		color = rgb(80, 255, 210),
		icon = "✨",
		music = "MusicBloom",
		modifiers = {
			mutationMult = { Glowing = 10 },
			exclusiveChance = 0.12,
		},
		visual = {
			fogTint = rgb(20, 120, 110),
			ambientBoost = rgb(40, 110, 100),
			tint = rgb(200, 255, 240),
			particles = rgb(90, 255, 210),
		},
	},
	{
		id = "Leviathan",
		name = "Leviathan Migration",
		short = "Leviathan",
		desc = "A colossal Leviathan swims through the Abyssal Plains. Follow it: rare loot falls in its wake.",
		color = rgb(60, 200, 255),
		icon = "🐋",
		music = "MusicLeviathan",
		modifiers = {
			exclusiveChance = 0.08,
			special = "Leviathan",
		},
		visual = {
			fogTint = rgb(10, 40, 70),
			ambientBoost = rgb(10, 30, 50),
			tint = rgb(210, 235, 255),
			particles = rgb(120, 220, 255),
		},
	},
	{
		id = "Galleon",
		name = "Sunken Galleon Surfaces",
		short = "Galleon",
		desc = "A treasure galleon has appeared somewhere in the depths, packed with rare treasure. First come, first served!",
		color = rgb(255, 190, 70),
		icon = "🏴‍☠️",
		music = "MusicGalleon",
		modifiers = {
			special = "Galleon",
		},
		visual = {
			fogTint = rgb(60, 50, 20),
			ambientBoost = rgb(40, 30, 10),
			tint = rgb(255, 240, 210),
			particles = rgb(255, 210, 90),
		},
	},
	{
		id = "GoldenTide",
		name = "Golden Tide",
		short = "Golden Tide",
		desc = "The sea turns to gold. Golden mutations are 5x more likely and sell prices are +50%!",
		color = rgb(255, 205, 60),
		icon = "🌊",
		music = "MusicGolden",
		modifiers = {
			mutationMult = { Golden = 5 },
			sellMult = 1.5,
			exclusiveChance = 0.1,
		},
		visual = {
			fogTint = rgb(90, 70, 10),
			ambientBoost = rgb(60, 45, 5),
			tint = rgb(255, 235, 180),
			particles = rgb(255, 215, 80),
		},
	},
	{
		id = "DeepTremor",
		name = "Deep Tremor",
		short = "Tremor",
		desc = "The seafloor cracks open! Fresh trenches expose Ancient Tech and Cursed Items.",
		color = rgb(255, 120, 50),
		icon = "🌋",
		music = "MusicTremor",
		modifiers = {
			categoryWeight = { Tech = 6, Cursed = 6 },
			exclusiveChance = 0.1,
			special = "Tremor",
		},
		visual = {
			fogTint = rgb(60, 20, 8),
			ambientBoost = rgb(50, 18, 5),
			tint = rgb(255, 220, 200),
			particles = rgb(255, 130, 50),
		},
	},
	{
		id = "BloodMoon",
		name = "Blood Moon Tide",
		short = "Blood Moon",
		desc = "Predators are aggressive, but Mythic+ odds are 3x and Voidtouched mutations can appear!",
		color = rgb(255, 40, 60),
		icon = "🌕",
		music = "MusicBloodMoon",
		modifiers = {
			tierMult = { Mythic = 3, Abyssal = 3, Secret = 3 },
			enableMutations = { "Voidtouched" },
			predatorAggro = 1.8,
			predatorDensity = 2,
			exclusiveChance = 0.08,
		},
		visual = {
			fogTint = rgb(70, 6, 12),
			ambientBoost = rgb(60, 5, 10),
			tint = rgb(255, 200, 200),
			particles = rgb(255, 60, 70),
			skyMoon = rgb(255, 40, 40),
		},
	},
}

local byId: { [string]: EventDef } = {}
for _, event in list do
	byId[event.id] = event
end

return {
	list = list,
	byId = byId,
	schedule = {
		cycleSeconds = 45 * 60,
		durationSeconds = 10 * 60,
		countdownSeconds = 60,
		epochOffset = 0, -- shift the whole schedule (seconds) if you want events at other minutes
		superChance = 0.05,
		salt = "DeepHaul-Events-v1",
	},
	weekend = {
		enabled = true,
		luck = 1.5, -- everyone's luck on Saturday and Sunday (UTC)
		eventLuck = 1.25, -- extra luck during events on weekends
		name = "Weekend Luck",
	},
	-- "Skip Event Timer" developer product: starts a random event in one server only.
	localEvent = {
		durationSeconds = 10 * 60,
		cooldownSeconds = 20 * 60, -- per-server cooldown between purchased events
	},
	leviathan = {
		zone = 4,
		radius = 300, -- path radius around the shaft centre
		lapSeconds = 300, -- time for one full lap
		bobHeight = 60,
		wakeInterval = 3, -- seconds between wake drops
		wakeDelay = 2.5, -- wake loot appears where the Leviathan was this many seconds ago
		wakeLuck = 4, -- luck multiplier on wake drops
		maxWakeEntities = 30,
		followRadius = 90, -- players within this distance of the wake get the drops
	},
	galleon = {
		zones = { 1, 2, 3, 4, 5 },
		treasureCount = 26,
		minRarity = "Rare",
		luck = 6,
		exclusiveChance = 0.35,
	},
	tremor = {
		zones = { 3, 4, 5 },
		trenchesPerZone = 3,
		treasurePerTrench = 7,
		exclusiveChance = 0.3,
		luck = 2,
	},
}

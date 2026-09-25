--!strict
-- Shared type definitions for DEEP HAUL. Saved data uses short keys to keep profiles small.

export type ItemKind = "F" | "T"

-- One owned fish or treasure. Stored in PlayerData.Inventory keyed by tostring(u).
export type Item = {
	u: number, -- unique id within the owner's inventory
	k: ItemKind, -- "F" fish, "T" treasure
	i: string, -- config id (Fish.byId / Treasure.byId)
	r: number, -- rarity index when obtained (1 = Common … 8 = Secret)
	v: number, -- frozen base value (before sell multipliers)
	z: number, -- zone index where it was obtained
	t: number, -- unix time obtained
	w: number?, -- weight in kg (fish)
	m: string?, -- mutation id (fish)
	x: boolean?, -- Colossal size roll (fish)
	c: string?, -- condition id (treasure)
	e: string?, -- event id this item was obtained during
	p: boolean?, -- PERFECT catch
	f: boolean?, -- favourite / locked (never sold by Sell All or auto-sell)
	g: boolean?, -- currently in the sub's cargo hold (unsecured)
	d: number?, -- aquarium tank index it is displayed in
}

export type FishDiscovery = {
	n: number, -- times caught
	bw: number, -- best weight
	m: { [string]: boolean }, -- mutations seen on this species
	x: boolean?, -- ever caught Colossal
}

export type TreasureDiscovery = {
	n: number, -- times salvaged
	bc: number, -- best condition index
}

export type QuestState = {
	id: string, -- template id
	target: number,
	progress: number,
	claimed: boolean,
	rarity: number?, -- minimum rarity index filter
	zone: number?, -- zone filter
	category: string?, -- treasure category filter
	condition: number?, -- minimum condition index filter
	reward: number, -- coins
	tokens: number?, -- rebirth tokens (weekly, after first rebirth)
	boost: string?, -- boost id granted on claim
}

export type PlayerStats = {
	FishCaught: number,
	TreasureSalvaged: number,
	CoinsEarned: number, -- lifetime coins from selling (Total Haul Value)
	ItemsSold: number,
	DeepestMeters: number,
	Dives: number,
	Blackouts: number,
	PerfectCatches: number,
	MythicPlus: number,
	Secrets: number,
	GoldenCatches: number,
	MutatedCatches: number,
	EventItems: number,
	SonarPings: number,
	BestScore: number, -- rarest catch score (see LootMath.rarityScore)
	BestItem: string, -- config id of the rarest catch
	BestMutation: string, -- mutation of the rarest catch ("" if none)
	RiftVisits: number,
	CleanDives: number, -- dives that ended by surfacing (not blackout)
	PlaySeconds: number,
	DiveSeconds: number,
	PassiveCoins: number,
}

export type Settings = {
	Music: number, -- 0..1
	SFX: number, -- 0..1
	Graphics: string, -- "High" | "Low"
	SellKeep: number, -- Sell All keeps this rarity index and above
	Offers: boolean, -- show occasional purchase offers
	CameraShake: boolean,
}

export type PlayerData = {
	Version: number,
	Coins: number,
	Tokens: number,
	Rebirths: number,
	Upgrades: { [string]: number },
	Perks: { [string]: number },
	Inventory: { [string]: Item },
	NextUid: number,
	Discovered: { Fish: { [string]: FishDiscovery }, Treasure: { [string]: TreasureDiscovery } },
	IndexClaimed: { [string]: boolean },
	Sets: { [string]: boolean },
	Stats: PlayerStats,
	Achievements: { [string]: boolean },
	Skins: { Owned: { [string]: boolean }, Equipped: string },
	Daily: { LastDay: number, Streak: number, Claimed: number },
	Quests: { DailyKey: number, Daily: { QuestState }, WeeklyKey: number, Weekly: { QuestState } },
	Codes: { [string]: boolean },
	Aquarium: { Slots: { [string]: number }, Pending: number, LastTick: number },
	Consumables: { [string]: number },
	Boosts: { [string]: number },
	Settings: Settings,
	Tutorial: { Done: boolean, Step: number },
	Purchases: { string },
	LastOnline: number,
	Flags: { [string]: boolean },
}

-- Derived gameplay stats (Stats.compute)
export type DerivedStats = {
	maxDepth: number, -- metres
	oxygen: number, -- oxygen units (seconds at 1x drain)
	speed: number, -- studs / second
	lightRadius: number, -- studs of visibility in dark zones
	sonarRange: number,
	sonarCooldown: number,
	cargo: number, -- cargo slots
	clawTier: number,
	clawSpeed: number,
	luck: number, -- multiplier (1 = base)
	sellMult: number, -- multiplier on sell price
	displaySlots: number, -- aquarium tanks
	minigameWidth: number, -- multiplier on green-zone width
	oxygenEfficiency: number, -- multiplier on oxygen drain (lower is better)
}

-- Live wild entity data sent to clients
export type FishEntity = {
	id: number,
	f: string, -- fish config id
	h: Vector3, -- home point
	s: number, -- path seed
	t0: number, -- server time the current path started
	ph: Vector3?, -- previous home (for smooth flee blending)
	tf: number?, -- flee start time
	e: string?, -- event id if event-exclusive spawn
	own: number?, -- userId the spawn was rolled for
}

export type TreasureEntity = {
	id: number,
	i: string, -- treasure config id
	p: Vector3,
	e: string?,
	src: string?, -- "Galleon" | "Tremor" | "Wake" | "Tutorial"
}

return {}

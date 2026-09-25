--!strict
-- Rarity tiers shared by fish and treasure.
--
-- odds          : exact "1 in N" base chance of a spawn rolling this tier (Common takes whatever
--                 probability is left). Multiplied by luck, zone rarity bonus and events.
-- minigame      : zoneWidth = fraction of the bar that is green, sweeps = full bar traversals per
--                 second. The minigame always ends after Game.Minigame.Duration seconds.
-- clawTier      : Claw tier needed to salvage treasure of this rarity (items can override).
-- salvageTime   : seconds to salvage at claw speed 1.0.
-- flee          : skittish fish swim away from subs moving faster than speedThreshold studs/s
--                 inside detectRadius.
-- reveal        : "normal" | "big" (sparkles) | "epic" (flash + shake + slow-mo + server chat)
-- announce      : "none" | "server" (chat in this server) | "global" (every server, MessagingService)

export type Rarity = {
	id: string,
	index: number,
	name: string,
	odds: number,
	color: Color3,
	accent: Color3,
	style: string, -- "plain" | "glow" | "gradient" | "pulse" | "rainbow"
	glow: boolean,
	particles: boolean,
	minigame: { zoneWidth: number, sweeps: number },
	clawTier: number,
	salvageTime: number,
	flee: { detectRadius: number, speedThreshold: number, distance: number }?,
	reveal: string,
	announce: string,
	alert: boolean, -- "X is nearby!" alert when one spawns near you
	hidden: boolean, -- hidden in the Index until discovered (no silhouette)
	sound: string, -- Sounds key played on reveal
}

local list: { Rarity } = {
	{
		id = "Common",
		index = 1,
		name = "Common",
		odds = 2,
		color = Color3.fromRGB(176, 184, 196),
		accent = Color3.fromRGB(120, 128, 140),
		style = "plain",
		glow = false,
		particles = false,
		minigame = { zoneWidth = 0.32, sweeps = 0.8 },
		clawTier = 1,
		salvageTime = 1.2,
		flee = nil,
		reveal = "normal",
		announce = "none",
		alert = false,
		hidden = false,
		sound = "RevealCommon",
	},
	{
		id = "Uncommon",
		index = 2,
		name = "Uncommon",
		odds = 5,
		color = Color3.fromRGB(92, 222, 116),
		accent = Color3.fromRGB(40, 150, 70),
		style = "plain",
		glow = false,
		particles = false,
		minigame = { zoneWidth = 0.27, sweeps = 0.9 },
		clawTier = 1,
		salvageTime = 1.6,
		flee = nil,
		reveal = "normal",
		announce = "none",
		alert = false,
		hidden = false,
		sound = "RevealUncommon",
	},
	{
		id = "Rare",
		index = 3,
		name = "Rare",
		odds = 25,
		color = Color3.fromRGB(70, 160, 255),
		accent = Color3.fromRGB(30, 90, 200),
		style = "glow",
		glow = true,
		particles = false,
		minigame = { zoneWidth = 0.22, sweeps = 1.0 },
		clawTier = 2,
		salvageTime = 2.2,
		flee = { detectRadius = 32, speedThreshold = 20, distance = 45 },
		reveal = "normal",
		announce = "none",
		alert = false,
		hidden = false,
		sound = "RevealRare",
	},
	{
		id = "Epic",
		index = 4,
		name = "Epic",
		odds = 150,
		color = Color3.fromRGB(178, 96, 255),
		accent = Color3.fromRGB(110, 40, 200),
		style = "glow",
		glow = true,
		particles = true,
		minigame = { zoneWidth = 0.17, sweeps = 1.1 },
		clawTier = 3,
		salvageTime = 3.0,
		flee = { detectRadius = 36, speedThreshold = 16, distance = 55 },
		reveal = "big",
		announce = "none",
		alert = true,
		hidden = false,
		sound = "RevealEpic",
	},
	{
		id = "Legendary",
		index = 5,
		name = "Legendary",
		odds = 1000,
		color = Color3.fromRGB(255, 200, 48),
		accent = Color3.fromRGB(230, 140, 20),
		style = "glow",
		glow = true,
		particles = true,
		minigame = { zoneWidth = 0.13, sweeps = 1.25 },
		clawTier = 4,
		salvageTime = 4.0,
		flee = { detectRadius = 40, speedThreshold = 13, distance = 65 },
		reveal = "big",
		announce = "none",
		alert = true,
		hidden = false,
		sound = "RevealLegendary",
	},
	{
		id = "Mythic",
		index = 6,
		name = "Mythic",
		odds = 10000,
		color = Color3.fromRGB(255, 64, 80),
		accent = Color3.fromRGB(255, 150, 60),
		style = "gradient",
		glow = true,
		particles = true,
		minigame = { zoneWidth = 0.11, sweeps = 1.35 },
		clawTier = 5,
		salvageTime = 5.0,
		flee = { detectRadius = 44, speedThreshold = 11, distance = 75 },
		reveal = "epic",
		announce = "server",
		alert = true,
		hidden = false,
		sound = "RevealMythic",
	},
	{
		id = "Abyssal",
		index = 7,
		name = "Abyssal",
		odds = 100000,
		color = Color3.fromRGB(40, 240, 255),
		accent = Color3.fromRGB(6, 10, 18),
		style = "pulse",
		glow = true,
		particles = true,
		minigame = { zoneWidth = 0.10, sweeps = 1.4 },
		clawTier = 6,
		salvageTime = 6.0,
		flee = { detectRadius = 48, speedThreshold = 10, distance = 85 },
		reveal = "epic",
		announce = "server",
		alert = true,
		hidden = false,
		sound = "RevealAbyssal",
	},
	{
		id = "Secret",
		index = 8,
		name = "Secret",
		odds = 1000000,
		color = Color3.fromRGB(255, 255, 255),
		accent = Color3.fromRGB(255, 120, 220),
		style = "rainbow",
		glow = true,
		particles = true,
		minigame = { zoneWidth = 0.09, sweeps = 1.45 },
		clawTier = 7,
		salvageTime = 7.0,
		flee = { detectRadius = 52, speedThreshold = 9.5, distance = 90 },
		reveal = "epic",
		announce = "global",
		alert = true,
		hidden = true,
		sound = "RevealSecret",
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

-- Rainbow keypoints used for the "rainbow" style (Secret) and Prismatic mutation.
local rainbow = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(170, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 200)),
})

return {
	list = list,
	byId = byId,
	count = #list,
	rainbow = rainbow,
	-- Rarity index at which a catch counts as "Mythic+" for quests, stats and announcements.
	mythicIndex = 6,
	legendaryIndex = 5,
}

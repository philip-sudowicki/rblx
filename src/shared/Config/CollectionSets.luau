--!strict
-- Treasure collection sets. A set completes once every listed treasure has been salvaged at
-- least once (it stays complete forever, even if you sell the items).
--
-- bonus.stat : "luck" | "sell" | "oxygen" | "clawSpeed" | "speed" | "sonar" (fractions, 0.05 = +5%)
--              | "cargo" (flat extra cargo slots)
-- badge      : key into Config/Badges for an optional Roblox badge

export type CollectionSet = {
	id: string,
	name: string,
	desc: string,
	items: { string },
	bonus: { stat: string, amount: number },
	badge: string,
	color: Color3,
}

local rgb = Color3.fromRGB

local list: { CollectionSet } = {
	{
		id = "DrownedRegalia",
		name = "The Drowned King's Regalia",
		desc = "Crown, scepter, ring and amulet of a king who ruled beneath the waves.",
		items = { "DrownedCrown", "TideboundScepter", "DrownedSignet", "AmuletOfBrine" },
		bonus = { stat = "luck", amount = 0.05 },
		badge = "SetDrownedRegalia",
		color = rgb(255, 205, 60),
	},
	{
		id = "PiratesFortune",
		name = "Pirate's Fortune",
		desc = "A little of every coin a pirate ever buried.",
		items = { "TarnishedDoubloon", "PieceOfEight", "SmugglersLockbox", "WaterloggedPurse" },
		bonus = { stat = "sell", amount = 0.10 },
		badge = "SetPiratesFortune",
		color = rgb(230, 180, 70),
	},
	{
		id = "MarinersKit",
		name = "Mariner's Kit",
		desc = "Everything a sailor needs to find their way home.",
		items = { "BarnacledCompass", "ShipsBell", "BrassSextant", "LanternOfTheLost" },
		bonus = { stat = "oxygen", amount = 0.10 },
		badge = "SetMarinersKit",
		color = rgb(160, 200, 230),
	},
	{
		id = "TideCult",
		name = "Relics of the Tide Cult",
		desc = "Sacred objects of the reef folk who worshipped the tides.",
		items = { "TideIdol", "ShellMask", "TideTablet", "CoralGoblet" },
		bonus = { stat = "clawSpeed", amount = 0.10 },
		badge = "SetTideCult",
		color = rgb(80, 200, 180),
	},
	{
		id = "GemsOfTheDeep",
		name = "Gems of the Deep",
		desc = "A gemstone from every depth, from sea glass to star-stuff.",
		items = { "SeaGlass", "ClamPearl", "AbyssalSapphire", "TrenchRuby", "RiftDiamond" },
		bonus = { stat = "cargo", amount = 2 },
		badge = "SetGemsOfTheDeep",
		color = rgb(110, 200, 255),
	},
	{
		id = "GraveyardSalvage",
		name = "Graveyard Salvage",
		desc = "Pieces of the great ships that rest on the Abyssal Plains.",
		items = { "IronCannonball", "FigureheadFragment", "MermaidFigurehead", "RustyAnchor" },
		bonus = { stat = "speed", amount = 0.08 },
		badge = "SetGraveyardSalvage",
		color = rgb(140, 170, 190),
	},
	{
		id = "LostEngineering",
		name = "Lost Engineering",
		desc = "The working parts of a machine no one alive understands.",
		items = { "PressureCore", "GyroLens", "HarmonicCoil", "DataObelisk", "HummingShard" },
		bonus = { stat = "sonar", amount = 0.15 },
		badge = "SetLostEngineering",
		color = rgb(80, 255, 210),
	},
	{
		id = "CursedCoffer",
		name = "The Cursed Coffer",
		desc = "Every one of these was thrown overboard on purpose.",
		items = { "HexedDoubloon", "WeepingMask", "BoneChalice", "HeartOfTheTrench" },
		bonus = { stat = "sell", amount = 0.15 },
		badge = "SetCursedCoffer",
		color = rgb(190, 80, 255),
	},
	{
		id = "SunkenEmpire",
		name = "The Sunken Empire",
		desc = "Treasures of the empire that built the trench ruins.",
		items = { "AncientMintCoin", "RuinMosaic", "DeepOneIdol", "SunkenEmpireCrown", "AncientChronometer" },
		bonus = { stat = "luck", amount = 0.08 },
		badge = "SetSunkenEmpire",
		color = rgb(60, 180, 130),
	},
	{
		id = "Riftborn",
		name = "Riftborn Artifacts",
		desc = "Objects that fell through the Rift from somewhere else entirely.",
		items = { "RiftScrip", "VoidPebble", "GlyphTablet", "SingingCrystal", "StarmetalCog", "RiftbornMask" },
		bonus = { stat = "luck", amount = 0.10 },
		badge = "SetRiftborn",
		color = rgb(210, 110, 255),
	},
	{
		id = "LeviathansWake",
		name = "Leviathan's Wake",
		desc = "Gifts left behind by the great Leviathan on its migration.",
		items = { "LeviathanScale", "MigrationPearl" },
		bonus = { stat = "oxygen", amount = 0.05 },
		badge = "SetLeviathansWake",
		color = rgb(80, 220, 255),
	},
	{
		id = "GalleonsBounty",
		name = "The Galleon's Bounty",
		desc = "Plunder from the Sunken Galleon, for the fastest divers only.",
		items = { "GalleonDoubloonChest", "AdmiralsSpyglass", "MarigoldLog" },
		bonus = { stat = "sell", amount = 0.10 },
		badge = "SetGalleonsBounty",
		color = rgb(255, 190, 70),
	},
	{
		id = "Faultlines",
		name = "Faultlines",
		desc = "Things the Deep Tremor shook loose, and one that was sealed away.",
		items = { "TremorCore", "FaultlineRelic", "BloodMoonIdol", "GoldenTideIdol" },
		bonus = { stat = "clawSpeed", amount = 0.08 },
		badge = "SetFaultlines",
		color = rgb(255, 120, 50),
	},
}

local byId: { [string]: CollectionSet } = {}
local setsForItem: { [string]: { string } } = {}
for _, set in list do
	byId[set.id] = set
	for _, itemId in set.items do
		setsForItem[itemId] = setsForItem[itemId] or {}
		table.insert(setsForItem[itemId], set.id)
	end
end

return {
	list = list,
	byId = byId,
	setsForItem = setsForItem,
}

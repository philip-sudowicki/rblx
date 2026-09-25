--!strict
-- Submarine upgrades. Every upgrade starts at level 1 (free) and has #values levels.
--
-- values : stat at each level (index = level)
-- cost   : price to buy level L (L >= 2) = base × growth^(L - 2), rounded to 2 significant
--          digits, then × Game.Economy.UpgradeCostMultiplier. `overrides[L]` pins an exact price
--          (Hull uses a full price table because its levels gate the zones).
-- Secondary stats (Claw speed, Sonar cooldown) live in their own arrays.
-- See BALANCING.md for how these curves were chosen and the simulator that checks them.

export type Upgrade = {
	id: string,
	name: string,
	icon: string,
	desc: string,
	stat: string,
	unit: string,
	values: { number },
	cost: { base: number, growth: number, overrides: { [number]: number }? },
	order: number,
	-- optional secondary stat arrays
	speed: { number }?,
	cooldown: { number }?,
}

local list: { Upgrade } = {
	{
		id = "Hull",
		name = "Hull Plating",
		icon = "🛡️",
		desc = "Maximum safe depth. Any deeper and the pressure starts crushing your hull.",
		stat = "maxDepth",
		unit = "m",
		values = { 250, 450, 700, 1000, 1500, 2100, 3000, 3800, 4800, 6000, 7200, 8600, 10000, 11000, 14000 },
		cost = {
			base = 150,
			growth = 3,
			overrides = {
				[2] = 400,
				[3] = 1600,
				[4] = 5500,
				[5] = 20000,
				[6] = 70000,
				[7] = 250000,
				[8] = 600000,
				[9] = 1400000,
				[10] = 22000000,
				[11] = 60000000,
				[12] = 150000000,
				[13] = 600000000,
				[14] = 2000000000,
				[15] = 8000000000,
			},
		},
		order = 1,
	},
	{
		id = "Oxygen",
		name = "Oxygen Tank",
		icon = "💨",
		desc = "How long you can stay down. Oxygen drains faster the deeper you go.",
		stat = "oxygen",
		unit = "s",
		values = { 120, 150, 180, 215, 255, 300, 350, 405, 465, 530, 600, 680, 770, 870, 1000 },
		cost = { base = 100, growth = 3.0 },
		order = 2,
	},
	{
		id = "Engine",
		name = "Engine",
		icon = "⚡",
		desc = "Top speed of your submarine.",
		stat = "speed",
		unit = "studs/s",
		values = { 28, 32, 36, 40, 45, 50, 55, 60, 66, 72, 78, 84, 90, 96, 104 },
		cost = { base = 90, growth = 3.0 },
		order = 3,
	},
	{
		id = "Lights",
		name = "Floodlights",
		icon = "💡",
		desc = "How far you can see in the dark zones. Loot beyond your lights stays hidden.",
		stat = "lightRadius",
		unit = "studs",
		values = { 45, 60, 75, 90, 105, 120, 140, 160, 180, 200, 220, 245, 270, 300, 330 },
		cost = { base = 120, growth = 3.0 },
		order = 4,
	},
	{
		id = "Sonar",
		name = "Sonar",
		icon = "📡",
		desc = "Sonar ping range and cooldown. Pings reveal loot and stun predators.",
		stat = "sonarRange",
		unit = "studs",
		values = { 80, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 320, 340, 360, 380 },
		cooldown = { 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6 },
		cost = { base = 110, growth = 2.9 },
		order = 5,
	},
	{
		id = "Cargo",
		name = "Cargo Hold",
		icon = "📦",
		desc = "How many fish and treasures you can carry in a single dive.",
		stat = "cargo",
		unit = "slots",
		values = { 10, 12, 14, 16, 19, 22, 25, 28, 32, 36, 40, 45, 50, 55, 60 },
		cost = { base = 80, growth = 3.05 },
		order = 6,
	},
	{
		id = "Claw",
		name = "Salvage Claw",
		icon = "🧲",
		desc = "Claw tier unlocks rarer treasure; claw speed makes salvaging faster.",
		stat = "clawTier",
		unit = "tier",
		values = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7 },
		speed = { 1.0, 1.15, 1.3, 1.45, 1.6, 1.75, 1.9, 2.05, 2.2, 2.35, 2.5, 2.65, 2.8, 2.95, 3.2 },
		cost = { base = 110, growth = 3.0 },
		order = 7,
	},
	{
		id = "Luck",
		name = "Luck Module",
		icon = "🍀",
		desc = "Improves the odds of rare fish, rare treasure, mutations and better conditions.",
		stat = "luck",
		unit = "%",
		values = { 0, 5, 10, 16, 23, 31, 40, 50, 62, 75, 90, 106, 124, 144, 170 },
		cost = { base = 160, growth = 3.05 },
		order = 8,
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	byId[upgrade.id] = upgrade
end

return {
	list = list,
	byId = byId,
}

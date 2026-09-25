--!strict
-- Predators are simulated on the server (authoritative damage) and drawn by clients.
-- damage is a percentage of hull integrity per bump. Speeds are studs/second.
-- A sonar ping within Game.Sonar.StunRadius stuns predators for Game.Sonar.StunSeconds.

export type Predator = {
	id: string,
	name: string,
	shape: string, -- ModelBuilder fish shape used to draw it
	length: number,
	primary: Color3,
	secondary: Color3,
	patrolSpeed: number,
	chaseSpeed: number,
	aggroRadius: number,
	bumpRadius: number,
	damage: number,
	knockback: number,
	retreatSeconds: number,
	cooldownSeconds: number,
}

local rgb = Color3.fromRGB

local list: { Predator } = {
	{
		id = "ReefBarracuda",
		name = "Reef Barracuda",
		shape = "Shark",
		length = 5,
		primary = rgb(140, 150, 160),
		secondary = rgb(40, 50, 60),
		patrolSpeed = 12,
		chaseSpeed = 26,
		aggroRadius = 45,
		bumpRadius = 6,
		damage = 8,
		knockback = 55,
		retreatSeconds = 3,
		cooldownSeconds = 4,
	},
	{
		id = "GulperEel",
		name = "Gulper Eel",
		shape = "Eel",
		length = 8,
		primary = rgb(20, 20, 26),
		secondary = rgb(255, 60, 80),
		patrolSpeed = 11,
		chaseSpeed = 30,
		aggroRadius = 50,
		bumpRadius = 7,
		damage = 11,
		knockback = 60,
		retreatSeconds = 3,
		cooldownSeconds = 4,
	},
	{
		id = "AbyssalShark",
		name = "Abyssal Shark",
		shape = "Shark",
		length = 9,
		primary = rgb(24, 28, 36),
		secondary = rgb(200, 210, 220),
		patrolSpeed = 14,
		chaseSpeed = 36,
		aggroRadius = 60,
		bumpRadius = 8,
		damage = 14,
		knockback = 70,
		retreatSeconds = 3.5,
		cooldownSeconds = 4,
	},
	{
		id = "TrenchKraken",
		name = "Trench Kraken",
		shape = "Squid",
		length = 16,
		primary = rgb(110, 20, 30),
		secondary = rgb(255, 200, 120),
		patrolSpeed = 10,
		chaseSpeed = 34,
		aggroRadius = 55,
		bumpRadius = 11,
		damage = 18,
		knockback = 90,
		retreatSeconds = 4,
		cooldownSeconds = 5,
	},
	{
		id = "RiftStalker",
		name = "Rift Stalker",
		shape = "Crystal",
		length = 10,
		primary = rgb(30, 10, 50),
		secondary = rgb(255, 60, 220),
		patrolSpeed = 16,
		chaseSpeed = 44,
		aggroRadius = 65,
		bumpRadius = 8,
		damage = 20,
		knockback = 80,
		retreatSeconds = 3,
		cooldownSeconds = 3.5,
	},
}

local byId: { [string]: Predator } = {}
for _, predator in list do
	byId[predator.id] = predator
end

return {
	list = list,
	byId = byId,
}

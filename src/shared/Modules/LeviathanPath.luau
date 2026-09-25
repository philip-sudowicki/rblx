--!strict
-- The Leviathan's route during a Leviathan Migration: slow laps around the Wreck Graveyard at a
-- fixed radius, rising and falling three times per lap. A pure function of the seconds since
-- the event started, so the server (wake drops) and every client (rendering) agree with no
-- networking at all.

local Config = script.Parent.Parent.Config
local Events = require(Config.Events)
local Zones = require(Config.Zones)

local LeviathanPath = {}

local params = Events.leviathan
local zone = Zones.list[params.zone]
local BASE_Y = (zone.bottomY + zone.floorThickness + zone.topY) / 2
local OMEGA = 2 * math.pi / params.lapSeconds

LeviathanPath.zone = params.zone
LeviathanPath.speed = params.radius * OMEGA

function LeviathanPath.position(elapsed: number): Vector3
	local theta = elapsed * OMEGA
	return Vector3.new(math.cos(theta) * params.radius, BASE_Y + math.sin(theta * 3) * params.bobHeight, math.sin(theta) * params.radius)
end

function LeviathanPath.velocity(elapsed: number): Vector3
	local theta = elapsed * OMEGA
	return Vector3.new(
		-math.sin(theta) * params.radius * OMEGA,
		math.cos(theta * 3) * 3 * params.bobHeight * OMEGA,
		math.cos(theta) * params.radius * OMEGA
	)
end

-- Pose for a model that faces -Z (LookVector forward).
function LeviathanPath.cframe(elapsed: number): CFrame
	local position = LeviathanPath.position(elapsed)
	return CFrame.lookAt(position, position + LeviathanPath.velocity(elapsed))
end

return LeviathanPath

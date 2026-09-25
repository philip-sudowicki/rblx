--!strict
-- Converts between world Y (studs) and displayed depth (metres), and finds zones.
-- Each zone maps its stud band [bottomY, topY] linearly onto its metre band.

local Config = script.Parent.Parent.Config
local Zones = require(Config.Zones)

local DepthMath = {}

-- Zone index containing world height y. Above the surface counts as zone 1.
function DepthMath.zoneIndexAtY(y: number): number
	for _, zone in Zones.list do
		if y > zone.bottomY then
			return zone.index
		end
	end
	return Zones.count
end

function DepthMath.zoneAtY(y: number): Zones.Zone
	return Zones.list[DepthMath.zoneIndexAtY(y)]
end

function DepthMath.metersAtY(y: number): number
	if y >= 0 then
		return 0
	end
	local zone = DepthMath.zoneAtY(y)
	local span = zone.topY - zone.bottomY
	local t = math.clamp((zone.topY - y) / span, 0, 1)
	return zone.meters[1] + (zone.meters[2] - zone.meters[1]) * t
end

function DepthMath.zoneIndexAtMeters(meters: number): number
	for _, zone in Zones.list do
		if meters < zone.meters[2] then
			return zone.index
		end
	end
	return Zones.count
end

function DepthMath.yAtMeters(meters: number): number
	if meters <= 0 then
		return 0
	end
	local zone = Zones.list[DepthMath.zoneIndexAtMeters(meters)]
	local t = math.clamp((meters - zone.meters[1]) / (zone.meters[2] - zone.meters[1]), 0, 1)
	return zone.topY - (zone.topY - zone.bottomY) * t
end

-- Top of the floor slab of a zone (studs)
function DepthMath.floorTopY(zoneIndex: number): number
	local zone = Zones.list[zoneIndex]
	return zone.bottomY + zone.floorThickness
end

return DepthMath

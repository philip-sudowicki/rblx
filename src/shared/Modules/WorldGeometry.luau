--!strict
-- Analytic description of the procedural world's open water, shared by the world builder,
-- the spawner (where fish can swim) and movement validation (where subs can be).

local Config = script.Parent.Parent.Config
local Zones = require(Config.Zones)
local DepthMath = require(script.Parent.DepthMath)

local WorldGeometry = {}

function WorldGeometry.radius(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

function WorldGeometry.inHole(zoneIndex: number, x: number, z: number, margin: number?): boolean
	local zone = Zones.list[zoneIndex]
	local hole = zone.hole
	if not hole then
		return false
	end
	local dx, dz = x - hole.x, z - hole.z
	return math.sqrt(dx * dx + dz * dz) <= hole.r - (margin or 0)
end

-- Height of the floor surface under (x, z) in a zone (decoration bumps not included).
-- Over the zone's hole the "floor" is the bottom of the band (the throat to the next zone).
function WorldGeometry.floorY(zoneIndex: number, x: number, z: number): number
	local zone = Zones.list[zoneIndex]
	if WorldGeometry.inHole(zoneIndex, x, z) then
		return zone.bottomY
	end
	local terraces = zone.terraces
	if terraces then
		local r = WorldGeometry.radius(x, z)
		-- terraces are listed from the outside in; the innermost one that still contains r wins
		local y = zone.bottomY + zone.floorThickness
		for _, terrace in terraces do
			if r <= terrace.r then
				y = terrace.y
			end
		end
		return y
	end
	return zone.bottomY + zone.floorThickness
end

-- Does this zone have a rock ceiling ring (it is wider than the zone above)?
function WorldGeometry.hasCeilingRing(zoneIndex: number): boolean
	if zoneIndex <= 1 then
		return false
	end
	local zone = Zones.list[zoneIndex]
	local above = Zones.list[zoneIndex - 1]
	return zone.radius > above.radius - 5
end

function WorldGeometry.ceilingRingInner(zoneIndex: number): number
	return Zones.list[zoneIndex - 1].radius - 5
end

-- Height of the ceiling over (x, z) in a zone.
function WorldGeometry.ceilingY(zoneIndex: number, x: number, z: number): number
	local zone = Zones.list[zoneIndex]
	if zoneIndex == 1 then
		return Zones.surfaceY
	end
	if WorldGeometry.hasCeilingRing(zoneIndex) and WorldGeometry.radius(x, z) > WorldGeometry.ceilingRingInner(zoneIndex) then
		return zone.topY - Zones.world.ceilingThickness
	end
	return zone.topY
end

-- Is `pos` in open water with at least `margin` studs from walls, floor and ceiling?
function WorldGeometry.isOpenWater(pos: Vector3, margin: number): boolean
	local zoneIndex = DepthMath.zoneIndexAtY(pos.Y)
	local zone = Zones.list[zoneIndex]
	if pos.Y > Zones.surfaceY or pos.Y < Zones.bottomY + 2 then
		return false
	end
	if WorldGeometry.radius(pos.X, pos.Z) > zone.radius - margin then
		return false
	end
	if pos.Y < WorldGeometry.floorY(zoneIndex, pos.X, pos.Z) + margin then
		return false
	end
	if pos.Y > WorldGeometry.ceilingY(zoneIndex, pos.X, pos.Z) - margin then
		return false
	end
	return true
end

-- Is `pos` somewhere a submarine could legitimately be (inside the shaft, allowing `slack`)?
function WorldGeometry.subAllowed(pos: Vector3, slack: number): boolean
	if pos.Y > 30 or pos.Y < Zones.bottomY - slack then
		return false
	end
	local zone = Zones.list[DepthMath.zoneIndexAtY(pos.Y)]
	-- Near a zone boundary the wider neighbour counts, so subs can pass through throats.
	local radius = zone.radius
	if zone.index > 1 then
		local above = Zones.list[zone.index - 1]
		if pos.Y > zone.topY - 40 then
			radius = math.max(radius, above.radius)
		end
	end
	if zone.index < Zones.count then
		local below = Zones.list[zone.index + 1]
		if pos.Y < zone.bottomY + zone.floorThickness + 40 then
			radius = math.max(radius, below.radius)
		end
	end
	return WorldGeometry.radius(pos.X, pos.Z) <= radius + slack
end

-- Pull a point back inside open water of its zone.
function WorldGeometry.clampInside(pos: Vector3, margin: number): Vector3
	local zoneIndex = DepthMath.zoneIndexAtY(pos.Y)
	local zone = Zones.list[zoneIndex]
	local x, z = pos.X, pos.Z
	local r = WorldGeometry.radius(x, z)
	local maxR = zone.radius - margin
	if r > maxR and r > 0 then
		x, z = x / r * maxR, z / r * maxR
	end
	local minY = WorldGeometry.floorY(zoneIndex, x, z) + margin
	local maxY = WorldGeometry.ceilingY(zoneIndex, x, z) - margin
	local y = pos.Y
	if minY < maxY then
		y = math.clamp(y, minY, maxY)
	end
	return Vector3.new(x, y, z)
end

-- Usable vertical band of a zone (conservative): floor top … ceiling
function WorldGeometry.band(zoneIndex: number): (number, number)
	local zone = Zones.list[zoneIndex]
	local bottom = zone.bottomY + zone.floorThickness
	if zone.terraces then
		bottom = zone.bottomY + zone.floorThickness
	end
	local top = if zoneIndex == 1 then Zones.surfaceY else zone.topY
	return bottom, top
end

return WorldGeometry

--!strict
-- The catch minigame marker, shared by server (validation) and client (animation).

local MinigameMath = {}

-- Marker position (0..1) `elapsed` seconds after it starts moving: a triangle wave doing
-- `sweeps` full traversals of the bar per second.
function MinigameMath.marker(elapsed: number, sweeps: number): number
	local x = math.max(0, elapsed) * sweeps
	local phase = x % 2
	return if phase <= 1 then phase else 2 - phase
end

function MinigameMath.inZone(marker: number, zoneStart: number, zoneWidth: number): boolean
	return marker >= zoneStart and marker <= zoneStart + zoneWidth
end

function MinigameMath.isPerfect(marker: number, zoneStart: number, zoneWidth: number, perfectFraction: number): boolean
	local centre = zoneStart + zoneWidth / 2
	return math.abs(marker - centre) <= zoneWidth * perfectFraction / 2
end

return MinigameMath

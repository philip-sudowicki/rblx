--!strict
-- Deterministic fish swimming. A fish wanders on a smooth Lissajous loop around its home point.
-- Clients animate it every frame; the server evaluates the same function only when it needs to
-- validate a catch, so fish AI costs the server nothing per frame.
--
-- After a flee the home point moves; `blend` returns a smooth transition from the old path
-- to the new one over FLEE_BLEND seconds.

local Hash = require(script.Parent.Hash)

export type Params = {
	ax: number,
	ay: number,
	az: number,
	wx: number,
	wy: number,
	wz: number,
	px: number,
	py: number,
	pz: number,
}

local FishPath = {}

FishPath.FLEE_BLEND = 1.4
FishPath.MAX_RADIUS = 30 -- fish never wander further than this from home (horizontal)

local cache: { [number]: Params } = {}
local cacheSize = 0

function FishPath.params(seed: number): Params
	local cached = cache[seed]
	if cached then
		return cached
	end
	local rng = Hash.rng(seed)
	local params: Params = {
		ax = 10 + 18 * rng(),
		ay = 2 + 5 * rng(),
		az = 10 + 18 * rng(),
		wx = 0.12 + 0.16 * rng(),
		wy = 0.25 + 0.2 * rng(),
		wz = 0.12 + 0.16 * rng(),
		px = math.pi * 2 * rng(),
		py = math.pi * 2 * rng(),
		pz = math.pi * 2 * rng(),
	}
	if cacheSize > 4000 then
		table.clear(cache)
		cacheSize = 0
	end
	cache[seed] = params
	cacheSize += 1
	return params
end

-- Offset from home at time t (seconds since the path started), speed multiplier `speed`.
function FishPath.offset(seed: number, t: number, speed: number): Vector3
	local p = FishPath.params(seed)
	local s = t * speed
	return Vector3.new(p.ax * math.sin(p.wx * s + p.px), p.ay * math.sin(p.wy * s + p.py), p.az * math.cos(p.wz * s + p.pz))
end

-- Velocity (derivative of offset) — used to face the fish along its path.
function FishPath.velocity(seed: number, t: number, speed: number): Vector3
	local p = FishPath.params(seed)
	local s = t * speed
	return Vector3.new(
		p.ax * p.wx * speed * math.cos(p.wx * s + p.px),
		p.ay * p.wy * speed * math.cos(p.wy * s + p.py),
		-p.az * p.wz * speed * math.sin(p.wz * s + p.pz)
	)
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Position of a fish entity at server time `now`.
--   home, t0          current home and the time its path started
--   prevHome, fleeAt  previous home and the flee time (optional)
function FishPath.position(
	home: Vector3,
	seed: number,
	t0: number,
	now: number,
	speed: number,
	prevHome: Vector3?,
	fleeAt: number?
): Vector3
	local current = home + FishPath.offset(seed, now - t0, speed)
	if prevHome and fleeAt then
		local alpha = smoothstep((now - fleeAt) / FishPath.FLEE_BLEND)
		if alpha < 1 then
			local previous = prevHome + FishPath.offset(seed, now - t0, speed)
			return previous:Lerp(current, alpha)
		end
	end
	return current
end

-- Speed multiplier by rarity index: rarer fish dart about a little faster.
function FishPath.speedFor(rarityIndex: number): number
	return 1 + 0.08 * (rarityIndex - 1)
end

return FishPath

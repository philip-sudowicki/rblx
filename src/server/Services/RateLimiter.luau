--!strict
-- Token-bucket rate limiting per player per key.

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

-- Allows `burst` calls at once, refilling at `rate` calls per second.
function RateLimiter.allow(player: Player, key: string, rate: number, burst: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.clear(player: Player)
	buckets[player] = nil
end

function RateLimiter.Init()
	Players.PlayerRemoving:Connect(function(player)
		task.defer(RateLimiter.clear, player)
	end)
end

return RateLimiter

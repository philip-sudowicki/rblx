--!strict
-- Deterministic 32-bit hashing and seeded random numbers.
-- Pure integer maths via bit32, so every server (and client) gets identical results. This is
-- what keeps UTC-scheduled events and fish swim paths in sync without any networking.

local Hash = {}

local TWO32 = 4294967296

local function u32(x: number): number
	return math.floor(x) % TWO32
end

-- 32-bit multiply without losing precision in doubles.
local function mul32(a: number, b: number): number
	a = u32(a)
	b = u32(b)
	local bLo = b % 65536
	local bHi = (b - bLo) / 65536
	return (a * bLo + ((a * bHi) % 65536) * 65536) % TWO32
end
Hash.mul32 = mul32

-- MurmurHash3 finaliser: good avalanche for sequential inputs.
function Hash.mix(h: number): number
	h = u32(h)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- FNV-1a over a string.
function Hash.string(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return Hash.mix(h)
end

-- Combine a hash with another integer (order-dependent).
function Hash.combine(a: number, b: number): number
	local x = bit32.bxor(u32(a), mul32(u32(b) + 0x9E3779B9, 0x85EBCA6B))
	return Hash.mix(x)
end

-- Hash » float in [0, 1)
function Hash.float(h: number): number
	return u32(h) / TWO32
end

-- Seeded PRNG (mulberry32). Returns a function producing floats in [0, 1).
function Hash.rng(seed: number): () -> number
	local state = u32(seed)
	return function(): number
		state = (state + 0x6D2B79F5) % TWO32
		local t = state
		t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
	end
end

return Hash

--!strict
-- Procedural fish animation shared by the wild-fish renderer and the aquarium tanks: tails and
-- fins wag around their pivots, eel/tentacle segments carry a travelling wave, and rainbow /
-- pulse tints cycle colour. Output is appended to part/CFrame arrays for one BulkMoveTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishModel = require(Shared.Models.FishModel)

local FishAnimator = {}

type Anim = { wag: { number }, wave: { number }, tint: string? }
local cache: { [any]: Anim } = setmetatable({}, { __mode = "k" }) :: any

local function animFor(built: FishModel.Built): Anim
	local cached = cache[built]
	if cached then
		return cached
	end
	local wag, wave = {}, {}
	for i, part in built.parts do
		local w = part:GetAttribute("Wag")
		local v = part:GetAttribute("Wave")
		wag[i] = if typeof(w) == "number" then w else 0
		wave[i] = if typeof(v) == "number" then v else -1
	end
	local mode = built.root:GetAttribute("Tint")
	local anim: Anim = { wag = wag, wave = wave, tint = if typeof(mode) == "string" then mode else nil }
	cache[built] = anim
	return anim
end

-- Appends every part of `built` posed at `cf` for time `t`. `length` is the model length in
-- studs and `speed` scales the tail beat (faster swimming = faster wag).
function FishAnimator.append(built: FishModel.Built, cf: CFrame, t: number, phase: number, length: number, speed: number, parts: { BasePart }, frames: { CFrame })
	local anim = animFor(built)
	for i, part in built.parts do
		local offset = built.offsets[i]
		local wag = anim.wag[i]
		local wave = anim.wave[i]
		local final: CFrame
		if wag > 0 then
			final = cf * offset * CFrame.Angles(0, math.sin(t * 9 * speed + phase) * wag, 0)
		elseif wave >= 0 then
			final = cf * CFrame.new(math.sin(t * 5 * speed - wave * 0.8 + phase) * length * 0.035 * wave, 0, 0) * offset
		else
			final = cf * offset
		end
		table.insert(parts, part)
		table.insert(frames, final)
	end
end

function FishAnimator.tint(built: FishModel.Built, t: number)
	local mode = animFor(built).tint
	if mode == "rainbow" then
		built.root.Color = Color3.fromHSV((t * 0.25) % 1, 0.7, 1)
	elseif mode == "pulse" then
		local p = (math.sin(t * 4) + 1) / 2
		built.root.Color = Color3.fromRGB(6, 10, 18):Lerp(Color3.fromRGB(40, 240, 255), p)
	end
end

return FishAnimator

--!strict
-- Builds fish (and predators) from primitive parts: 15 body plans with patterns, eyes, fins,
-- rarity glow/particles and mutation looks. Models face -Z (LookVector = forward) and are built
-- around the origin; the renderer moves them with BulkMoveTo using the recorded part offsets.
--
-- Part attributes used by the renderer:
--   Wag = n   tail/fin: swings around its own pivot, amplitude n radians
--   Wave = i  eel/tentacle segment index for travelling waves
--   Tint = "rainbow" | "pulse"  colour animation

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)

export type Look = {
	shape: string,
	length: number,
	primary: Color3,
	secondary: Color3,
	pattern: string?,
	glow: boolean?,
	neon: boolean?,
	hat: boolean?,
}

export type Options = {
	rarity: number?, -- rarity index (adds glow/particles for rare fish)
	mutation: string?,
	scale: number?,
	predator: boolean?, -- red glowing eyes
	simple: boolean?, -- skip particles and lights (low graphics / tiny thumbnails)
}

export type Built = {
	model: Model,
	root: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
}

local FishModel = {}

local rgb = Color3.fromRGB
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function applyMutation(look: Look, mutation: string?): (Color3, Color3, Enum.Material, boolean)
	local primary, secondary = look.primary, look.secondary
	local material = if look.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local glow = look.glow == true
	if mutation == "Albino" then
		primary, secondary = rgb(248, 244, 242), rgb(255, 214, 222)
		material = Enum.Material.SmoothPlastic
	elseif mutation == "Glowing" then
		material = Enum.Material.Neon
		glow = true
	elseif mutation == "Golden" then
		primary, secondary = rgb(255, 200, 50), rgb(255, 240, 170)
		material = Enum.Material.Foil
		glow = true
	elseif mutation == "Shadow" then
		primary, secondary = rgb(26, 18, 36), rgb(120, 60, 200)
		material = Enum.Material.SmoothPlastic
	elseif mutation == "Prismatic" then
		primary, secondary = rgb(255, 120, 220), rgb(120, 220, 255)
		material = Enum.Material.SmoothPlastic
		glow = true
	elseif mutation == "Voidtouched" then
		primary, secondary = rgb(6, 6, 12), rgb(40, 255, 255)
		material = Enum.Material.SmoothPlastic
		glow = true
	end
	return primary, secondary, material, glow
end

function FishModel.build(look: Look, options: Options?): Built
	local opts: Options = options or {}
	local L = look.length * (opts.scale or 1)
	local primary, secondary, material, glow = applyMutation(look, opts.mutation)
	local model = Instance.new("Model")
	model.Name = "Fish"
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local root: BasePart? = nil

	local function add(className: string, shape: Enum.PartType?, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material?): BasePart
		local part = Instance.new(className) :: BasePart
		if shape and part:IsA("Part") then
			part.Shape = shape
		end
		part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
		part.CFrame = offset
		part.Color = color
		part.Material = mat or material
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		table.insert(parts, part)
		table.insert(offsets, offset)
		if not root then
			root = part
		end
		return part
	end
	local function ball(d: number, pos: Vector3, color: Color3, mat: Enum.Material?): BasePart
		return add("Part", Enum.PartType.Ball, Vector3.new(d, d, d), CFrame.new(pos), color, mat)
	end
	-- cylinder along Z (body axis)
	local function capsule(length: number, d: number, pos: Vector3, color: Color3, mat: Enum.Material?): BasePart
		return add("Part", Enum.PartType.Cylinder, Vector3.new(length, d, d), CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0), color, mat)
	end
	local function block(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
		return add("Part", nil, size, cf, color, mat)
	end
	local function wedge(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
		return add("WedgePart", nil, size, cf, color, mat)
	end
	local function eyes(z: number, x: number, y: number, d: number)
		local eyeColor = if opts.predator or opts.mutation == "Albino" then rgb(255, 40, 40) elseif opts.mutation == "Shadow" then rgb(200, 90, 255) else rgb(15, 15, 20)
		local eyeMat = if opts.predator or opts.mutation == "Shadow" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		for side = -1, 1, 2 do
			ball(d * 1.3, Vector3.new(side * x, y, z), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
			ball(d * 0.75, Vector3.new(side * (x + d * 0.35), y, z - d * 0.1), eyeColor, eyeMat)
		end
	end
	local function tailFin(z: number, height: number, depth: number, color: Color3, amplitude: number)
		local upper = wedge(Vector3.new(L * 0.04, height, depth), CFrame.new(0, height * 0.35, z) * CFrame.Angles(math.rad(35), 0, 0), color)
		upper:SetAttribute("Wag", amplitude)
		local lower = wedge(Vector3.new(L * 0.04, height, depth), CFrame.new(0, -height * 0.35, z) * CFrame.Angles(math.rad(145), 0, 0), color)
		lower:SetAttribute("Wag", amplitude)
	end
	local function dorsal(z: number, height: number, depth: number, y: number, color: Color3)
		wedge(Vector3.new(L * 0.03, height, depth), CFrame.new(0, y + height / 2, z), color)
	end
	local function pectorals(z: number, y: number, size: number, color: Color3)
		for side = -1, 1, 2 do
			local fin = wedge(Vector3.new(L * 0.03, size, size * 1.2), CFrame.new(side * L * 0.14, y, z) * CFrame.Angles(0, 0, side * math.rad(70)), color)
			fin:SetAttribute("Wag", 0.25)
		end
	end
	local function pattern(bodyLength: number, bodyD: number, centerZ: number)
		if look.pattern == "stripes" then
			for i = -1, 1 do
				capsule(bodyD * 0.08, bodyD * 1.02, Vector3.new(0, 0, centerZ + i * bodyLength * 0.25), secondary)
			end
		elseif look.pattern == "spots" then
			for i = 1, 6 do
				local a = i * 1.9
				ball(bodyD * 0.18, Vector3.new(math.cos(a) * bodyD * 0.46, math.sin(a) * bodyD * 0.46, centerZ + (i - 3.5) * bodyLength * 0.13), secondary)
			end
		elseif look.pattern == "belly" then
			capsule(bodyLength * 0.9, bodyD * 0.8, Vector3.new(0, -bodyD * 0.16, centerZ), secondary)
		end
	end

	local shape = look.shape
	if shape == "Classic" or shape == "Slim" then
		local d = if shape == "Slim" then L * 0.24 else L * 0.36
		local body = capsule(L * 0.5, d, Vector3.new(0, 0, 0), primary)
		body.Name = "Body"
		ball(d, Vector3.new(0, 0, -L * 0.25), primary)
		ball(d * 0.85, Vector3.new(0, 0, L * 0.25), primary)
		pattern(L * 0.5, d, 0)
		eyes(-L * 0.32, d * 0.32, d * 0.12, d * 0.18)
		tailFin(L * 0.42, d * 0.9, L * 0.2, secondary, 0.35)
		dorsal(-L * 0.02, d * 0.55, L * 0.26, d * 0.4, secondary)
		pectorals(-L * 0.12, -d * 0.1, d * 0.5, secondary)
	elseif shape == "Tall" then
		local d = L * 0.72
		local body = add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.2, d, d), CFrame.identity, primary)
		body.Name = "Body"
		if look.pattern == "stripes" then
			for i = -1, 1 do
				block(Vector3.new(L * 0.21, d * 0.85, L * 0.06), CFrame.new(0, 0, i * d * 0.25), secondary)
			end
		elseif look.pattern == "belly" then
			add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.21, d * 0.6, d * 0.6), CFrame.new(0, -d * 0.18, 0), secondary)
		elseif look.pattern == "spots" then
			for i = 1, 5 do
				ball(d * 0.12, Vector3.new(L * 0.1, math.sin(i) * d * 0.3, math.cos(i * 1.7) * d * 0.3), secondary)
			end
		end
		eyes(-d * 0.3, L * 0.09, d * 0.1, d * 0.1)
		wedge(Vector3.new(L * 0.03, d * 0.6, L * 0.3), CFrame.new(0, d * 0.55, L * 0.08) * CFrame.Angles(math.rad(-20), 0, 0), secondary)
		wedge(Vector3.new(L * 0.03, d * 0.6, L * 0.3), CFrame.new(0, -d * 0.55, L * 0.08) * CFrame.Angles(math.rad(200), 0, 0), secondary)
		tailFin(d * 0.55, d * 0.5, L * 0.22, secondary, 0.3)
	elseif shape == "Flat" then
		local body = add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.1, L * 0.7, L * 0.7), CFrame.Angles(0, 0, math.pi / 2), primary)
		body.Name = "Body"
		for side = -1, 1, 2 do
			local wing = wedge(Vector3.new(L * 0.05, L * 0.4, L * 0.5), CFrame.new(side * L * 0.42, 0, 0) * CFrame.Angles(0, 0, side * math.rad(90)) * CFrame.Angles(math.rad(90), 0, 0), primary)
			wing:SetAttribute("Wag", 0.3)
		end
		if look.pattern == "spots" or look.pattern == "stripes" then
			for i = 1, 6 do
				local a = i * 1.05
				add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.11, L * 0.08, L * 0.08), CFrame.new(math.cos(a) * L * 0.2, 0, math.sin(a) * L * 0.2) * CFrame.Angles(0, 0, math.pi / 2), secondary)
			end
		end
		eyes(-L * 0.28, L * 0.1, L * 0.05, L * 0.05)
		local tail = capsule(L * 0.7, L * 0.04, Vector3.new(0, 0, L * 0.65), secondary)
		tail:SetAttribute("Wag", 0.15)
	elseif shape == "Eel" or shape == "Crystal" and L > 6 then
		local segments = 7
		local d = L * 0.11
		for i = 0, segments - 1 do
			local t = i / (segments - 1)
			local segD = d * (1 - t * 0.55)
			local seg: BasePart
			if shape == "Crystal" then
				seg = block(Vector3.new(segD, segD, segD), CFrame.new(0, 0, -L * 0.45 + t * L * 0.9) * CFrame.Angles(math.rad(45), 0, math.rad(45)), if i % 2 == 0 then primary else secondary, Enum.Material.Neon)
			else
				seg = ball(segD * 1.25, Vector3.new(0, 0, -L * 0.45 + t * L * 0.9), if look.pattern == "stripes" and i % 2 == 1 then secondary else primary)
			end
			seg:SetAttribute("Wave", i)
			if i == 0 then
				seg.Name = "Body"
			end
		end
		if look.pattern == "spots" then
			for i = 1, 5 do
				local s = ball(d * 0.35, Vector3.new(0, d * 0.5, -L * 0.4 + i * L * 0.15), secondary)
				s:SetAttribute("Wave", i)
			end
		end
		eyes(-L * 0.5, d * 0.35, d * 0.2, d * 0.22)
		local fin = wedge(Vector3.new(L * 0.02, d * 0.8, L * 0.12), CFrame.new(0, 0, L * 0.5), secondary)
		fin:SetAttribute("Wave", segments - 1)
	elseif shape == "Puffer" then
		local d = L * 0.8
		local body = ball(d, Vector3.zero, primary)
		body.Name = "Body"
		ball(d * 0.7, Vector3.new(0, -d * 0.18, -d * 0.05), secondary)
		for i = 1, 14 do
			local a = i * 2.4
			local b = (i / 14) * math.pi
			local dir = Vector3.new(math.sin(b) * math.cos(a), math.cos(b), math.sin(b) * math.sin(a))
			wedge(Vector3.new(d * 0.05, d * 0.14, d * 0.08), CFrame.lookAt(dir * d * 0.5, dir * d) * CFrame.Angles(math.rad(-90), 0, 0), secondary)
		end
		eyes(-d * 0.38, d * 0.22, d * 0.12, d * 0.12)
		tailFin(d * 0.52, d * 0.4, d * 0.25, secondary, 0.4)
		pectorals(-d * 0.05, 0, d * 0.25, secondary)
	elseif shape == "Jelly" then
		local d = L * 0.75
		local bellMat = if look.neon or glow then Enum.Material.Neon else Enum.Material.Glass
		local bell = ball(d, Vector3.new(0, d * 0.1, 0), primary, bellMat)
		bell.Transparency = if bellMat == Enum.Material.Glass then 0.35 else 0.25
		bell.Name = "Body"
		add("Part", Enum.PartType.Cylinder, Vector3.new(d * 0.1, d * 0.9, d * 0.9), CFrame.new(0, -d * 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), secondary, Enum.Material.Neon)
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			local tentacle = block(Vector3.new(L * 0.03, L * 0.8, L * 0.03), CFrame.new(math.cos(a) * d * 0.3, -d * 0.2 - L * 0.4, math.sin(a) * d * 0.3), secondary, Enum.Material.Neon)
			tentacle.Transparency = 0.2
			tentacle:SetAttribute("Wave", i)
		end
	elseif shape == "Angler" then
		local d = L * 0.55
		local body = ball(d, Vector3.new(0, 0, -L * 0.05), primary)
		body.Name = "Body"
		capsule(L * 0.35, d * 0.65, Vector3.new(0, 0, L * 0.2), primary)
		wedge(Vector3.new(d * 0.8, d * 0.25, d * 0.5), CFrame.new(0, -d * 0.28, -L * 0.28), secondary)
		for i = -2, 2 do
			wedge(Vector3.new(d * 0.05, d * 0.14, d * 0.05), CFrame.new(i * d * 0.12, -d * 0.1, -L * 0.34) * CFrame.Angles(math.rad(180), 0, 0), rgb(240, 240, 235), Enum.Material.SmoothPlastic)
		end
		eyes(-L * 0.2, d * 0.3, d * 0.22, d * 0.1)
		local rod = block(Vector3.new(L * 0.02, L * 0.02, L * 0.4), CFrame.new(0, d * 0.62, -L * 0.28) * CFrame.Angles(math.rad(-35), 0, 0), primary)
		local _ = rod
		local lure = ball(L * 0.12, Vector3.new(0, d * 0.78, -L * 0.48), secondary, Enum.Material.Neon)
		lure.Name = "Lure"
		if not opts.simple then
			local light = Instance.new("PointLight")
			light.Color = secondary
			light.Range = 10
			light.Brightness = 2
			light.Parent = lure
		end
		tailFin(L * 0.42, d * 0.5, L * 0.18, secondary, 0.35)
	elseif shape == "Shark" then
		local d = L * 0.22
		local body = capsule(L * 0.6, d, Vector3.zero, primary)
		body.Name = "Body"
		ball(d, Vector3.new(0, 0, -L * 0.3), primary)
		wedge(Vector3.new(d * 0.9, d * 0.6, L * 0.14), CFrame.new(0, 0, -L * 0.4) * CFrame.Angles(0, math.pi, 0), primary)
		ball(d * 0.8, Vector3.new(0, 0, L * 0.3), primary)
		pattern(L * 0.6, d, 0)
		eyes(-L * 0.34, d * 0.35, d * 0.12, d * 0.13)
		dorsal(-L * 0.02, d * 1.1, L * 0.22, d * 0.4, primary)
		pectorals(-L * 0.12, -d * 0.25, d * 0.9, primary)
		tailFin(L * 0.44, d * 1.6, L * 0.16, primary, 0.3)
		if opts.predator then
			for i = -2, 2 do
				wedge(Vector3.new(d * 0.06, d * 0.12, d * 0.06), CFrame.new(i * d * 0.14, -d * 0.25, -L * 0.42) * CFrame.Angles(math.rad(180), 0, 0), rgb(245, 245, 240), Enum.Material.SmoothPlastic)
			end
		end
	elseif shape == "Squid" then
		local d = L * 0.24
		local mantle = capsule(L * 0.45, d, Vector3.new(0, 0, L * 0.1), primary)
		mantle.Name = "Body"
		wedge(Vector3.new(d * 1.4, d * 0.1, L * 0.14), CFrame.new(0, 0, L * 0.38), secondary)
		ball(d * 1.1, Vector3.new(0, 0, -L * 0.15), primary)
		pattern(L * 0.45, d, L * 0.1)
		eyes(-L * 0.18, d * 0.42, d * 0.05, d * 0.2)
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			local tentacle = capsule(L * 0.42, d * 0.12, Vector3.new(math.cos(a) * d * 0.28, math.sin(a) * d * 0.28, -L * 0.42), if i % 2 == 0 then secondary else primary)
			tentacle:SetAttribute("Wave", i)
		end
	elseif shape == "Seahorse" then
		local d = L * 0.22
		local body = ball(d * 1.4, Vector3.new(0, 0, 0), primary)
		body.Name = "Body"
		ball(d * 1.2, Vector3.new(0, d * 0.9, -d * 0.2), primary)
		ball(d * 1.1, Vector3.new(0, d * 1.7, -d * 0.1), primary)
		capsule(d * 1.2, d * 0.35, Vector3.new(0, d * 1.75, -d * 0.9), secondary)
		for i = 1, 5 do
			local a = i * 0.9
			local tail = ball(d * (1 - i * 0.15), Vector3.new(0, -d * 0.4 - i * d * 0.45, d * 0.2 + math.sin(a) * d * 0.5), primary)
			tail:SetAttribute("Wave", i)
		end
		local fin = wedge(Vector3.new(L * 0.02, d * 0.9, d * 0.8), CFrame.new(0, d * 0.4, d * 0.75), secondary)
		fin:SetAttribute("Wag", 0.5)
		eyes(-d * 0.35, d * 0.32, d * 1.8, d * 0.14)
	elseif shape == "Crab" then
		local d = L * 0.55
		local body = add("Part", Enum.PartType.Cylinder, Vector3.new(d * 0.35, d, d), CFrame.Angles(0, 0, math.pi / 2), primary)
		body.Name = "Body"
		add("Part", Enum.PartType.Cylinder, Vector3.new(d * 0.36, d * 0.7, d * 0.7), CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.pi / 2), secondary)
		for side = -1, 1, 2 do
			for leg = 1, 3 do
				local legPart = block(Vector3.new(d * 0.55, d * 0.07, d * 0.07), CFrame.new(side * d * 0.6, -d * 0.1, (leg - 2) * d * 0.25) * CFrame.Angles(0, 0, side * -0.5), primary)
				legPart:SetAttribute("Wag", 0.3)
			end
			local claw = ball(d * 0.32, Vector3.new(side * d * 0.55, 0, -d * 0.55), secondary)
			local _ = claw
			wedge(Vector3.new(d * 0.12, d * 0.08, d * 0.3), CFrame.new(side * d * 0.55, d * 0.08, -d * 0.78), secondary)
			ball(d * 0.12, Vector3.new(side * d * 0.15, d * 0.32, -d * 0.35), rgb(20, 20, 20))
		end
	elseif shape == "Whale" then
		local d = L * 0.26
		local body = capsule(L * 0.6, d, Vector3.zero, primary)
		body.Name = "Body"
		ball(d, Vector3.new(0, 0, -L * 0.3), primary)
		ball(d * 0.75, Vector3.new(0, 0, L * 0.32), primary)
		capsule(L * 0.55, d * 0.8, Vector3.new(0, -d * 0.18, -L * 0.02), secondary)
		if look.pattern == "stripes" or look.pattern == "spots" then
			for i = 1, 5 do
				ball(d * 0.16, Vector3.new(0, d * 0.46, -L * 0.25 + i * L * 0.1), secondary, Enum.Material.Neon)
			end
		end
		eyes(-L * 0.28, d * 0.42, -d * 0.05, d * 0.08)
		for side = -1, 1, 2 do
			local fluke = wedge(Vector3.new(d * 1.1, d * 0.08, L * 0.14), CFrame.new(side * d * 0.5, 0, L * 0.45) * CFrame.Angles(0, side * 0.3, 0), primary)
			fluke:SetAttribute("Wag", 0.18)
			local fin = wedge(Vector3.new(d * 0.08, d * 0.5, L * 0.12), CFrame.new(side * d * 0.55, -d * 0.2, -L * 0.1) * CFrame.Angles(0, 0, side * math.rad(60)), primary)
			fin:SetAttribute("Wag", 0.2)
		end
	elseif shape == "Crystal" then
		local d = L * 0.45
		local body = block(Vector3.new(d * 0.7, d * 0.7, d * 0.7), CFrame.Angles(math.rad(45), 0, math.rad(45)), primary, Enum.Material.Neon)
		body.Name = "Body"
		block(Vector3.new(d * 0.5, d * 0.5, d * 0.5), CFrame.new(0, 0, d * 0.45) * CFrame.Angles(math.rad(45), 0, math.rad(45)), secondary, Enum.Material.Glass).Transparency = 0.2
		block(Vector3.new(d * 0.3, d * 0.3, d * 0.3), CFrame.new(0, 0, -d * 0.5) * CFrame.Angles(math.rad(45), 0, math.rad(45)), secondary, Enum.Material.Neon)
		local tail = wedge(Vector3.new(d * 0.08, d * 0.6, d * 0.5), CFrame.new(0, 0, d * 0.8), secondary, Enum.Material.Neon)
		tail:SetAttribute("Wag", 0.3)
		eyes(-d * 0.4, d * 0.2, d * 0.1, d * 0.08)
	elseif shape == "Duck" then
		local d = L * 0.55
		local body = ball(d, Vector3.new(0, 0, 0), primary)
		body.Name = "Body"
		ball(d * 0.62, Vector3.new(0, d * 0.5, -d * 0.3), primary)
		wedge(Vector3.new(d * 0.35, d * 0.14, d * 0.35), CFrame.new(0, d * 0.45, -d * 0.72) * CFrame.Angles(0, math.pi, 0), secondary)
		local tail = wedge(Vector3.new(d * 0.3, d * 0.3, d * 0.3), CFrame.new(0, d * 0.2, d * 0.52), primary)
		tail:SetAttribute("Wag", 0.4)
		for side = -1, 1, 2 do
			ball(d * 0.12, Vector3.new(side * d * 0.2, d * 0.62, -d * 0.5), rgb(20, 20, 25))
		end
	else
		local body = capsule(L * 0.6, L * 0.3, Vector3.zero, primary)
		body.Name = "Body"
		tailFin(L * 0.4, L * 0.3, L * 0.2, secondary, 0.3)
	end

	if look.hat then
		local top = L * 0.35
		add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.03, L * 0.36, L * 0.36), CFrame.new(0, top, -L * 0.15) * CFrame.Angles(0, 0, math.pi / 2), rgb(20, 20, 24), Enum.Material.SmoothPlastic)
		add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.22, L * 0.22, L * 0.22), CFrame.new(0, top + L * 0.12, -L * 0.15) * CFrame.Angles(0, 0, math.pi / 2), rgb(20, 20, 24), Enum.Material.SmoothPlastic)
		add("Part", Enum.PartType.Cylinder, Vector3.new(L * 0.05, L * 0.23, L * 0.23), CFrame.new(0, top + L * 0.05, -L * 0.15) * CFrame.Angles(0, 0, math.pi / 2), rgb(200, 30, 40), Enum.Material.SmoothPlastic)
	end

	local mainPart = root :: BasePart
	model.PrimaryPart = mainPart

	-- rarity and mutation effects
	local rarity = Rarities.list[opts.rarity or 1] or Rarities.list[1]
	if not opts.simple then
		local wantsLight = glow or rarity.glow or opts.mutation ~= nil
		if wantsLight then
			local light = Instance.new("PointLight")
			light.Color = if glow then secondary else rarity.color
			light.Range = math.clamp(L * 2.5, 8, 26)
			light.Brightness = if rarity.index >= 5 then 2.2 else 1.2
			light.Shadows = false
			light.Parent = mainPart
		end
		local sparkle = opts.mutation == "Shiny" or opts.mutation == "Golden" or opts.mutation == "Prismatic" or rarity.particles
		if sparkle then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = SPARKLE
			emitter.Rate = if rarity.index >= 6 then 14 else 6
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Speed = NumberRange.new(0.5, 1.5)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.clamp(L * 0.12, 0.2, 1.2)), NumberSequenceKeypoint.new(1, 0) })
			emitter.LightEmission = 1
			local sparkleColor = if opts.mutation == "Golden" then rgb(255, 220, 90) elseif opts.mutation == "Shiny" then rgb(255, 255, 230) else rarity.color
			emitter.Color = if opts.mutation == "Prismatic" or rarity.style == "rainbow" then Rarities.rainbow else ColorSequence.new(sparkleColor)
			emitter.Parent = mainPart
		end
		if opts.mutation == "Shadow" or opts.mutation == "Voidtouched" then
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = SMOKE
			smoke.Rate = 8
			smoke.Lifetime = NumberRange.new(1, 2)
			smoke.Speed = NumberRange.new(0.2, 0.6)
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, L * 0.3), NumberSequenceKeypoint.new(1, L * 0.6) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			smoke.Color = ColorSequence.new(if opts.mutation == "Voidtouched" then rgb(40, 255, 255) else rgb(60, 20, 90))
			smoke.LightEmission = if opts.mutation == "Voidtouched" then 0.8 else 0
			smoke.Parent = mainPart
		end
	end
	if opts.mutation == "Prismatic" or rarity.style == "rainbow" then
		mainPart:SetAttribute("Tint", "rainbow")
	elseif rarity.style == "pulse" or opts.mutation == "Voidtouched" then
		mainPart:SetAttribute("Tint", "pulse")
	end
	model:SetAttribute("Length", L)
	return { model = model, root = mainPart, parts = parts, offsets = offsets }
end

-- Positions every part at `cf` (models are built around the origin). Works outside workspace
-- (ViewportFrames) because it sets CFrames directly.
function FishModel.place(built: Built, cf: CFrame)
	for i, part in built.parts do
		part.CFrame = cf * built.offsets[i]
	end
end

return FishModel

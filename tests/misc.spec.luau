local Hash = require(Shared.Modules.Hash)
local Format = require(Shared.Modules.Format)
local DepthMath = require(Shared.Modules.DepthMath)
local FishPath = require(Shared.Modules.FishPath)
local IndexMath = require(Shared.Modules.IndexMath)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)

test("mul32 matches exact arithmetic", function()
	eq(Hash.mul32(123456, 789), 123456 * 789)
	eq(Hash.mul32(4294967295, 2), 4294967294)
	eq(Hash.mul32(65536, 65536), 0)
end)

test("rng is deterministic and uniform", function()
	local a, b = Hash.rng(42), Hash.rng(42)
	local total = 0
	for _ = 1, 20000 do
		local x = a()
		eq(x, b())
		ok(x >= 0 and x < 1, "range")
		total += x
	end
	near(total / 20000, 0.5, 0.01, "mean")
	ok(Hash.string("abc") ~= Hash.string("abd"), "string hash differs")
	eq(Hash.string("DeepHaul"), Hash.string("DeepHaul"))
end)

test("format helpers", function()
	eq(Format.short(950), "950")
	eq(Format.short(1234), "1.23K")
	eq(Format.short(45678), "45.6K")
	eq(Format.short(100000), "100K")
	eq(Format.short(1000000000), "1B")
	eq(Format.short(1500000), "1.5M")
	eq(Format.commas(1234567), "1,234,567")
	eq(Format.commas(12), "12")
	eq(Format.odds(0.001), "1 in 1,000")
	eq(Format.odds(1 / 2500000), "1 in 2.5M")
	eq(Format.clock(65), "1:05")
	eq(Format.clock(3725), "1:02:05")
	eq(Format.duration(29000), "8h 3m")
	eq(Format.weight(0.05), "0.05 kg")
	eq(Format.weight(1500), "1.50 t")
end)

test("depth mapping", function()
	eq(DepthMath.metersAtY(10), 0)
	near(DepthMath.metersAtY(-300), 200, 1e-9)
	near(DepthMath.metersAtY(-700), 1000, 1e-9)
	near(DepthMath.metersAtY(-1500), 6000, 1e-9)
	near(DepthMath.metersAtY(-1900), 11000, 1e-9)
	eq(DepthMath.zoneIndexAtY(-10), 1)
	eq(DepthMath.zoneIndexAtY(-301), 2)
	eq(DepthMath.zoneIndexAtY(-2299), 6)
	for _, m in { 50, 450, 2500, 4000, 9000, 12000 } do
		near(DepthMath.metersAtY(DepthMath.yAtMeters(m)), m, 1e-6, "roundtrip " .. m)
	end
	eq(DepthMath.zoneIndexAtMeters(6000), 5)
end)

test("fish paths are deterministic, bounded and blend after fleeing", function()
	local home = Vector3.new(10, -100, 20)
	for seed = 1, 200 do
		for t = 0, 120, 7 do
			local p = FishPath.position(home, seed, 0, t, 1)
			local q = FishPath.position(home, seed, 0, t, 1)
			ok(p == q, "deterministic")
			local d = p - home
			ok(math.abs(d.X) <= 28.01 and math.abs(d.Z) <= 28.01 and math.abs(d.Y) <= 7.01, "bounded")
		end
	end
	local prev = Vector3.new(0, -100, 0)
	local atFlee = FishPath.position(home, 5, 0, 50, 1, prev, 50)
	local oldPath = FishPath.position(prev, 5, 0, 50, 1)
	ok(atFlee:FuzzyEq(oldPath, 1e-6), "starts on the old path")
	local after = FishPath.position(home, 5, 0, 60, 1, prev, 50)
	ok(after:FuzzyEq(FishPath.position(home, 5, 0, 60, 1), 1e-6), "ends on the new path")
end)

test("index completion counts everything", function()
	local empty = IndexMath.completion({ Fish = {}, Treasure = {} })
	eq(empty.global.found, 0)
	eq(empty.global.total, #Fish.list + #Treasure.list)
	local all = { Fish = {}, Treasure = {} }
	for _, f in Fish.list do
		all.Fish[f.id] = { n = 1 }
	end
	for _, t in Treasure.list do
		all.Treasure[t.id] = { n = 1 }
	end
	local full = IndexMath.completion(all)
	eq(IndexMath.percent(full.global), 100)
	for _, progress in full.zones do
		eq(progress.found, progress.total)
	end
	local milestones = IndexMath.milestones(full)
	local claimed = {}
	for _, m in milestones do
		ok(m.reached, m.key)
		claimed[m.key] = true
	end
	ok(IndexMath.luckFromClaimed(claimed) > 0.2, "full index luck")
	eq(IndexMath.luckFromClaimed({}), 0)
end)

test("world geometry: terraces, holes, ceilings and open water", function()
	local WorldGeometry = require(Shared.Modules.WorldGeometry)
	eq(WorldGeometry.floorY(1, 420, 0), -70, "outer terrace")
	eq(WorldGeometry.floorY(1, 350, 0), -120)
	eq(WorldGeometry.floorY(1, 260, 0), -180)
	eq(WorldGeometry.floorY(1, 200, 0), -240, "inner terrace")
	eq(WorldGeometry.floorY(1, 0, 0), -300, "over the hole")
	ok(WorldGeometry.inHole(2, 110, -60), "twilight hole centre")
	eq(WorldGeometry.floorY(2, 0, 200), -640)
	ok(WorldGeometry.hasCeilingRing(4), "abyssal is wider than midnight")
	ok(not WorldGeometry.hasCeilingRing(5), "hadal is narrower")
	eq(WorldGeometry.ceilingY(4, 400, 0), -1130)
	eq(WorldGeometry.ceilingY(4, 0, 0), -1100)
	ok(WorldGeometry.isOpenWater(Vector3.new(0, -500, 0), 20), "twilight open water")
	ok(not WorldGeometry.isOpenWater(Vector3.new(0, -660, 200), 20), "inside the twilight floor")
	ok(not WorldGeometry.isOpenWater(Vector3.new(370, -500, 0), 20), "too close to the wall")
	ok(WorldGeometry.subAllowed(Vector3.new(0, -14, -380), 25), "launch point allowed")
	ok(not WorldGeometry.subAllowed(Vector3.new(0, -500, 700), 25), "outside the shaft")
	local clamped = WorldGeometry.clampInside(Vector3.new(1000, -500, 0), 30)
	near(clamped.X, 350, 1e-6)
end)

test("minigame marker sweeps as a triangle wave", function()
	local M = require(Shared.Modules.MinigameMath)
	eq(M.marker(-1, 1), 0, "before start")
	near(M.marker(0.5, 1), 0.5, 1e-9)
	near(M.marker(1, 1), 1, 1e-9, "far end")
	near(M.marker(1.5, 1), 0.5, 1e-9, "coming back")
	near(M.marker(2, 1), 0, 1e-9)
	near(M.marker(0.25, 2), 0.5, 1e-9, "faster sweeps")
	ok(M.inZone(0.5, 0.4, 0.2))
	ok(not M.inZone(0.61, 0.4, 0.2))
	ok(M.isPerfect(0.5, 0.4, 0.2, 0.3))
	ok(not M.isPerfect(0.44, 0.4, 0.2, 0.3))
	-- every rarity's minigame fits inside 3 s with several chances to hit the zone
	local Rarities = require(Shared.Config.Rarities)
	local Game = require(Shared.Config.Game)
	for _, rarity in Rarities.list do
		local passes = Game.Catch.Duration * rarity.minigame.sweeps
		ok(passes >= 2, rarity.id .. " gives at least two passes")
	end
end)

test("leviathan path stays inside the Abyssal Plains and matches its velocity", function()
	local LeviathanPath = require(Shared.Modules.LeviathanPath)
	local WorldGeometry = require(Shared.Modules.WorldGeometry)
	local Zones = require(Shared.Config.Zones)
	local zone = Zones.list[LeviathanPath.zone]
	for t = 0, 600, 7 do
		local p = LeviathanPath.position(t)
		ok(WorldGeometry.isOpenWater(p, 30), "open water at t=" .. t)
		ok(p.Y < zone.topY and p.Y > zone.bottomY + zone.floorThickness, "inside the zone band")
		local numeric = (LeviathanPath.position(t + 0.01) - LeviathanPath.position(t - 0.01)) / 0.02
		near((numeric - LeviathanPath.velocity(t)).Magnitude, 0, 0.05, "velocity is the derivative")
	end
end)

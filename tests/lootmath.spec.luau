local LootMath = require(Shared.Modules.LootMath)
local Hash = require(Shared.Modules.Hash)
local Rarities = require(Shared.Config.Rarities)

local function sum(t)
	local s = 0
	for _, v in t do
		s += v
	end
	return s
end

test("base tier chances are exact 1-in-N and sum to 1", function()
	local c = LootMath.tierChances({ luck = 1, zoneBonus = 1 })
	near(sum(c), 1, 1e-9, "sum")
	near(c[5], 1 / 1000, 1e-12, "legendary")
	near(c[8], 1 / 1000000, 1e-15, "secret")
	near(c[3], 1 / 25, 1e-12, "rare")
	ok(c[1] > 0.7, "common remainder")
end)

test("luck multiplies rare tiers and the cap squeezes least-rare tiers first", function()
	local c = LootMath.tierChances({ luck = 50, zoneBonus = 4 })
	near(sum(c), 1, 1e-9, "sum")
	near(c[5], 200 / 1000, 1e-9, "legendary untouched by cap")
	ok(c[1] >= 0.05 - 1e-9, "common keeps the uncapped remainder")
	local rareish = 0
	for i = 2, #c do
		rareish += c[i]
	end
	ok(rareish <= 0.95 + 1e-9, "cap respected")
end)

test("event tier multipliers apply", function()
	local c = LootMath.tierChances({ luck = 1, zoneBonus = 1, tierMult = { Mythic = 3 } })
	near(c[6], 3 / 10000, 1e-12, "mythic x3")
end)

test("rollTier matches probabilities", function()
	local rng = Hash.rng(12345)
	local c = LootMath.tierChances({ luck = 1, zoneBonus = 1 })
	local counts = table.create(8, 0)
	local n = 200000
	for _ = 1, n do
		local tier = LootMath.rollTier(rng(), c)
		counts[tier] += 1
	end
	near(counts[3] / n, 0.04, 0.003, "rare frequency")
	near(counts[2] / n, 0.2, 0.006, "uncommon frequency")
	near(counts[4] / n, 1 / 150, 0.0012, "epic frequency")
end)

test("mutation roll frequencies", function()
	local rng = Hash.rng(99)
	local shiny, total = 0, 100000
	for _ = 1, total do
		if LootMath.rollMutation(rng, { luck = 1 }) == "Shiny" then
			shiny += 1
		end
	end
	near(shiny / total, 1 / 50, 0.002, "shiny")
	local void = 0
	for _ = 1, 20000 do
		if LootMath.rollMutation(rng, { luck = 1 }) == "Voidtouched" then
			void += 1
		end
	end
	eq(void, 0, "Voidtouched can't roll without its event")
	local chance = LootMath.mutationChance(require(Shared.Config.Mutations).byId.Voidtouched, { luck = 1, enabled = { Voidtouched = true } })
	near(chance, 1 / 5000, 1e-12, "voidtouched enabled")
	local glow = LootMath.mutationChance(require(Shared.Config.Mutations).byId.Glowing, { luck = 4, mult = { Glowing = 10 } })
	near(glow, (1 / 500) * 2 * 10, 1e-12, "glowing with luck 4 (sqrt) and x10")
end)

test("size rolls stay in range and Colossal is ~1 in 500", function()
	local rng = Hash.rng(7)
	local colossal, n = 0, 200000
	for _ = 1, n do
		local roll = LootMath.rollSize(rng, 2, 8, 1)
		if roll.colossal then
			colossal += 1
			ok(roll.weight >= 8 * 1.6 - 0.1 and roll.weight <= 8 * 2.4 + 0.1, "colossal weight")
			eq(roll.valueMult, 5, "colossal value")
			eq(roll.modelScale, 3, "colossal scale")
		else
			ok(roll.weight >= 2 - 0.05 and roll.weight <= 8 + 0.05, "weight in range " .. roll.weight)
			ok(roll.valueMult >= 0.6 - 1e-9 and roll.valueMult <= 1.5 + 1e-9, "value mult")
		end
	end
	near(colossal / n, 1 / 500, 0.0004, "colossal frequency")
end)

test("fish and treasure values", function()
	eq(LootMath.fishValue(100, 1, nil, false), 100)
	eq(LootMath.fishValue(100, 1, "Golden", false), 1000)
	eq(LootMath.fishValue(100, 1, "Shiny", true), 220)
	eq(LootMath.fishValue(0.1, 0.6, nil, false), 1, "minimum 1 coin")
	eq(LootMath.treasureValue(100, 5), 1500, "flawless x15")
	eq(LootMath.treasureValue(100, 1), 50, "corroded x0.5")
end)

test("condition distribution", function()
	local rng = Hash.rng(2024)
	local counts = table.create(5, 0)
	local n = 300000
	for _ = 1, n do
		local c = LootMath.rollCondition(rng, 1)
		counts[c] += 1
	end
	near(counts[5] / n, 1 / 1000, 0.0003, "flawless")
	near(counts[1] / n, 0.35, 0.01, "corroded")
	near(counts[4] / n, 0.069, 0.005, "pristine")
end)

test("rarity score and board encoding", function()
	eq(LootMath.rarityScore(5, nil, false), 3000, "legendary")
	eq(LootMath.rarityScore(5, "Shiny", false), math.floor(math.log10(50000) * 1000))
	local encoded = LootMath.encodeBoardScore(4698, 1, true, 42)
	local score, mutation, isTreasure, order = LootMath.decodeBoardScore(encoded)
	eq(score, 4698)
	eq(mutation, 1)
	eq(isTreasure, true)
	eq(order, 42)
	local e2 = LootMath.encodeBoardScore(13100, 6, false, 77)
	local s2, m2, t2, o2 = LootMath.decodeBoardScore(e2)
	eq(s2, 13100)
	eq(m2, 6)
	eq(t2, false)
	eq(o2, 77)
	ok(e2 > encoded, "higher score sorts higher")
end)

test("pickFromPool falls back to lower tiers", function()
	local rng = Hash.rng(1)
	local pool = {
		{ id = "a", tier = 1, weight = 1 },
		{ id = "b", tier = 3, weight = 1 },
	}
	eq(LootMath.pickFromPool(rng, pool, 3).id, "b")
	eq(LootMath.pickFromPool(rng, pool, 2).id, "a", "no tier 2 -> tier 1")
	eq(LootMath.pickFromPool(rng, pool, 8).id, "b", "no tier 8 -> highest lower tier")
	eq(LootMath.pickFromPool(rng, {}, 1), nil)
	local weighted = { { id = "x", tier = 1, weight = 9 }, { id = "y", tier = 1, weight = 1 } }
	local xs = 0
	for _ = 1, 10000 do
		if LootMath.pickFromPool(rng, weighted, 1).id == "x" then
			xs += 1
		end
	end
	near(xs / 10000, 0.9, 0.02, "weights")
end)

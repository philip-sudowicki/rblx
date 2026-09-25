local Stats = require(Shared.Modules.Stats)

local function ctx(overrides)
	local c = {
		upgrades = {},
		perks = {},
		rebirths = 0,
		passes = {},
		sets = {},
		indexLuck = 0,
		boosts = {},
		now = 1000,
		serverLuck = 1,
		eventLuck = 1,
		eventSell = 1,
	}
	for k, v in overrides or {} do
		c[k] = v
	end
	return c
end

test("level 1 stats", function()
	local s = Stats.compute(ctx())
	eq(s.maxDepth, 250)
	eq(s.oxygen, 120)
	eq(s.cargo, 10)
	eq(s.speed, 28)
	eq(s.luck, 1)
	eq(s.sellMult, 1)
	eq(s.clawTier, 1)
	eq(s.sonarCooldown, 20)
end)

test("passes, rebirths, boosts and sets", function()
	local s = Stats.compute(ctx({ passes = { DoubleCargo = true, TurboEngine = true, VIP = true, LuckyDiver = true } }))
	eq(s.cargo, 20)
	near(s.speed, 28 * 1.3, 1e-9)
	near(s.sellMult, 1.2, 1e-9)
	near(s.luck, 1.25, 1e-9)
	local r = Stats.compute(ctx({ rebirths = 2 }))
	near(r.sellMult, 2, 1e-9)
	local b = Stats.compute(ctx({ boosts = { Luck = 2000, Sell = 500 } }))
	near(b.luck, 2, 1e-9, "active luck boost")
	near(b.sellMult, 1, 1e-9, "expired sell boost")
	local sets = Stats.compute(ctx({ sets = { GemsOfTheDeep = true, DrownedRegalia = true } }))
	eq(sets.cargo, 12)
	near(sets.luck, 1.05, 1e-9)
	local server = Stats.compute(ctx({ serverLuck = 2, eventLuck = 1.5 }))
	near(server.luck, 3, 1e-9)
end)

test("upgrade costs are nice round numbers", function()
	for _, id in { "Hull", "Oxygen", "Engine", "Lights", "Sonar", "Cargo", "Claw", "Luck" } do
		eq(Stats.upgradeCost(id, 1), 0)
		for level = 2, Stats.maxLevel(id) do
			local c = Stats.upgradeCost(id, level)
			if c >= 100 then
				local digits = math.floor(math.log10(c)) + 1
				local factor = 10 ^ (digits - 2)
				eq(c % factor, 0, id .. " level " .. level .. " cost " .. c)
			end
		end
	end
	eq(Stats.nice(1234), 1200)
	eq(Stats.nice(56789), 57000)
	eq(Stats.nice(99), 99)
end)

test("rebirth cost and tokens", function()
	eq(Stats.rebirthCost(0), 60000000)
	eq(Stats.rebirthCost(1), 180000000)
	eq(Stats.rebirthTokens(1), 4)
	eq(Stats.startLevel({ ReinforcedFrame = 2 }, "Hull"), 3)
	eq(Stats.startLevel({}, "Hull"), 1)
end)

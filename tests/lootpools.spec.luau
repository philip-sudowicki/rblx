local LootPools = require(ServerPure.LootPools)
local Hash = require(Shared.Modules.Hash)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Zones = require(Shared.Config.Zones)

test("zone pools only contain that zone's regular loot", function()
	for _, zone in Zones.list do
		for _, entry in LootPools.fishPool(zone.index) do
			local fish = Fish.byId[entry.id]
			eq(fish.zone, zone.id, entry.id)
			eq(fish.event, nil, entry.id)
		end
		for _, entry in LootPools.treasurePool(zone.index) do
			local treasure = Treasure.byId[entry.id]
			eq(treasure.zone, zone.id, entry.id)
		end
	end
end)

test("event exclusives only appear when their event is active", function()
	local rng = Hash.rng(3)
	for _ = 1, 3000 do
		local roll = LootPools.rollFish(rng, 1, { luck = 1 })
		ok(roll ~= nil and roll.event == nil, "no event fish without an event")
	end
	local seen = 0
	for _ = 1, 3000 do
		local roll = LootPools.rollFish(rng, 1, { luck = 1, exclusive = { { id = "Bloom", chance = 0.12 } } })
		if roll and roll.event == "Bloom" then
			seen += 1
			eq(Fish.byId[roll.id].event, "Bloom")
		end
	end
	near(seen / 3000, 0.12, 0.03, "bloom exclusive rate")
end)

test("zone-restricted exclusives respect their zones", function()
	eq(#LootPools.eventFishPool("Leviathan", 1), 0, "wake remora only in the wreck graveyard")
	ok(#LootPools.eventFishPool("Leviathan", 7) > 0)
	eq(#LootPools.eventTreasurePool("DeepTremor", 1), 0)
	ok(#LootPools.eventTreasurePool("DeepTremor", 7) > 0)
end)

test("minTier forces the guarantee", function()
	local rng = Hash.rng(11)
	for _ = 1, 200 do
		local roll = LootPools.rollFish(rng, 1, { luck = 1, minTier = 5 })
		ok(roll ~= nil and roll.tier >= 5, "legendary or better")
	end
end)

test("category weights bias treasure and can borrow deeper categories", function()
	local rng = Hash.rng(21)
	local tech = 0
	for _ = 1, 4000 do
		local roll = LootPools.rollTreasure(rng, 3, { luck = 1, categoryWeight = { Tech = 6, Cursed = 6 } })
		if roll and Treasure.byId[roll.id].category == "Tech" then
			tech += 1
		end
	end
	ok(tech > 0, "tremor borrows ancient tech into the midnight zone")
	local plain = 0
	for _ = 1, 4000 do
		local roll = LootPools.rollTreasure(rng, 3, { luck = 1 })
		if roll and Treasure.byId[roll.id].category == "Tech" then
			plain += 1
		end
	end
	eq(plain, 0, "no ancient tech in the midnight zone normally")
end)

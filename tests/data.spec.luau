local DataSchema = require(ServerPure.DataSchema)

local function fresh()
	return DataSchema.deepCopy(DataSchema.TEMPLATE)
end

test("template sanitises cleanly", function()
	local data = fresh()
	eq(DataSchema.sanitize(data), 0)
	eq(data.Upgrades.Hull, 1)
	eq(data.Skins.Equipped, "Default")
	eq(data.NextUid, 1)
end)

test("bad numbers and levels are repaired", function()
	local data = fresh()
	data.Coins = 0 / 0
	data.Upgrades.Hull = 999
	data.Upgrades.Engine = -3
	data.Upgrades.Bogus = 4
	data.Settings.Music = 7
	data.Settings.Graphics = "Ultra"
	DataSchema.sanitize(data)
	eq(data.Coins, 0)
	eq(data.Upgrades.Hull, 15)
	eq(data.Upgrades.Engine, 1)
	eq(data.Upgrades.Bogus, nil)
	eq(data.Settings.Music, 1)
	eq(data.Settings.Graphics, "High")
end)

test("unknown items are refunded, cargo is secured, uids repaired", function()
	local data = fresh()
	data.Inventory["5"] = { u = 5, k = "F", i = "SandyMinnow", r = 1, v = 6, z = 1, t = 0, g = true }
	data.Inventory["9"] = { u = 9, k = "F", i = "RemovedFish", r = 3, v = 120, z = 1, t = 0 }
	data.Inventory["bad"] = { u = 2, k = "T", i = "SeaGlass", r = 1, v = 30, z = 1, t = 0 }
	local refunded = DataSchema.sanitize(data)
	eq(refunded, 150)
	eq(data.Coins, 150)
	ok(data.Inventory["5"] ~= nil, "valid item kept")
	eq(data.Inventory["5"].g, nil, "cargo flag cleared")
	eq(data.Inventory["9"], nil, "unknown item removed")
	eq(data.Inventory["bad"], nil, "mismatched key removed")
	eq(data.NextUid, 6)
end)

test("aquarium slots must reference owned items", function()
	local data = fresh()
	data.Inventory["3"] = { u = 3, k = "F", i = "Clownfin", r = 3, v = 80, z = 1, t = 0, d = 2 }
	data.Inventory["4"] = { u = 4, k = "F", i = "Clownfin", r = 3, v = 80, z = 1, t = 0, d = 7 }
	data.Aquarium.Slots["1"] = 3
	data.Aquarium.Slots["2"] = 99
	DataSchema.sanitize(data)
	eq(data.Aquarium.Slots["1"], 3)
	eq(data.Aquarium.Slots["2"], nil)
	eq(data.Inventory["3"].d, 1, "flag follows the slot")
	eq(data.Inventory["4"].d, nil, "orphan display flag cleared")
end)

test("skins, boosts and purchase cache", function()
	local data = fresh()
	data.Skins.Owned.Nope = true
	data.Skins.Equipped = "Gilded"
	data.Boosts.Luck = 1
	for i = 1, 150 do
		table.insert(data.Purchases, tostring(i))
	end
	DataSchema.sanitize(data)
	eq(data.Skins.Owned.Nope, nil)
	eq(data.Skins.Equipped, "Default", "can't equip an unowned skin")
	eq(data.Boosts.Luck, nil, "expired boost dropped")
	eq(#data.Purchases, 100)
	eq(data.Purchases[1], "51", "oldest receipts dropped first")
end)

test("migrations run in order up to the current version", function()
	local data = fresh()
	data.Version = 0
	DataSchema.migrate(data)
	eq(data.Version, require(Shared.Config.Game).DataVersion)
end)

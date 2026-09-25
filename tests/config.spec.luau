-- Config integrity: every piece of content references valid data.
local Config = Shared.Config
local Fish = require(Config.Fish)
local Treasure = require(Config.Treasure)
local Zones = require(Config.Zones)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Categories = require(Config.TreasureCategories)
local Sets = require(Config.CollectionSets)
local Upgrades = require(Config.Upgrades)
local Events = require(Config.Events)
local Quests = require(Config.Quests)
local Achievements = require(Config.Achievements)
local Skins = require(Config.Skins)
local Products = require(Config.Products)
local Sounds = require(Config.Sounds)
local Predators = require(Config.Predators)
local Rebirth = require(Config.Rebirth)
local Daily = require(Config.DailyRewards)
local Conditions = require(Config.Conditions)
local Badges = require(Config.Badges)
local Stats = require(Shared.Modules.Stats)

local FISH_SHAPES = {
	Classic = true, Slim = true, Tall = true, Flat = true, Eel = true, Puffer = true, Jelly = true,
	Angler = true, Shark = true, Squid = true, Seahorse = true, Crab = true, Whale = true,
	Crystal = true, Duck = true,
}
local TREASURE_SHAPES = {
	Coin = true, CoinPile = true, Bar = true, Chest = true, Ring = true, Crown = true, Gem = true,
	Shard = true, Idol = true, Statue = true, Tablet = true, Obelisk = true, Mask = true,
	Anchor = true, Compass = true, Sextant = true, Bell = true, Porthole = true, Figurehead = true,
	Cannonball = true, Goblet = true, Lyre = true, Scepter = true, Comb = true, Lantern = true,
	Spyglass = true, Book = true, Device = true, Coil = true, Orb = true, Cog = true,
}

test("at least 60 regular fish and 50 regular treasures", function()
	local fish, treasure = 0, 0
	for _, f in Fish.list do
		if not f.event then
			fish += 1
		end
	end
	for _, t in Treasure.list do
		if not t.event then
			treasure += 1
		end
	end
	ok(fish >= 60, "regular fish: " .. fish)
	ok(treasure >= 50, "regular treasure: " .. treasure)
end)

test("fish entries are valid and unique", function()
	local seen = {}
	for _, f in Fish.list do
		ok(not seen[f.id], "duplicate fish id " .. f.id)
		seen[f.id] = true
		ok(Rarities.byId[f.rarity] ~= nil, f.id .. " rarity")
		ok(f.zone == nil or Zones.byId[f.zone] ~= nil, f.id .. " zone")
		ok(f.zone ~= nil or f.event ~= nil, f.id .. " needs a zone or an event")
		ok(f.event == nil or Events.byId[f.event] ~= nil, f.id .. " event")
		ok(f.value > 0, f.id .. " value")
		ok(#f.weight == 2 and f.weight[1] > 0 and f.weight[1] < f.weight[2], f.id .. " weight range")
		ok(#f.desc > 10, f.id .. " description")
		ok(FISH_SHAPES[f.model.shape], f.id .. " shape " .. tostring(f.model.shape))
		ok(f.model.length > 0, f.id .. " length")
		ok(Treasure.byId[f.id] == nil, f.id .. " id collides with a treasure id")
	end
end)

test("treasure entries are valid and unique", function()
	local seen = {}
	for _, t in Treasure.list do
		ok(not seen[t.id], "duplicate treasure id " .. t.id)
		seen[t.id] = true
		ok(Rarities.byId[t.rarity] ~= nil, t.id .. " rarity")
		ok(Categories.byId[t.category] ~= nil, t.id .. " category")
		ok(t.zone == nil or Zones.byId[t.zone] ~= nil, t.id .. " zone")
		ok(t.zone ~= nil or t.event ~= nil, t.id .. " needs a zone or an event")
		ok(t.event == nil or Events.byId[t.event] ~= nil, t.id .. " event")
		ok(t.value > 0, t.id .. " value")
		ok(TREASURE_SHAPES[t.model.shape], t.id .. " shape " .. tostring(t.model.shape))
		ok(#t.desc > 10, t.id .. " description")
		if t.zone then
			local category = Categories.byId[t.category]
			ok(Zones.byId[t.zone].index >= category.minZone, t.id .. " is shallower than its category allows")
		end
		if t.cursed then
			ok(t.category == "Cursed", t.id .. " has a curse but isn't Cursed")
		end
		if t.category == "Cursed" then
			ok((t.cursed or 0) > 0, t.id .. " is Cursed but has no oxygen drain")
		end
	end
end)

test("every zone has a full fish pool and a treasure pool", function()
	for _, zone in Zones.list do
		local tiers = {}
		for _, f in Fish.byZone[zone.id] or {} do
			tiers[f.rarity] = true
		end
		for _, id in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" } do
			ok(tiers[id], zone.id .. " has no " .. id .. " fish")
		end
		local tTiers = {}
		for _, t in Treasure.byZone[zone.id] or {} do
			tTiers[t.rarity] = true
		end
		for _, id in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
			ok(tTiers[id], zone.id .. " has no " .. id .. " treasure")
		end
	end
end)

test("every event has at least 3 exclusives", function()
	for _, event in Events.list do
		local n = #(Fish.byEvent[event.id] or {}) + #(Treasure.byEvent[event.id] or {})
		ok(n >= 3, event.id .. " has " .. n .. " exclusives")
	end
	ok(#Events.list >= 6, "at least 6 events")
end)

test("collection sets reference real treasure and badges", function()
	for _, set in Sets.list do
		ok(#set.items >= 2, set.id .. " size")
		for _, itemId in set.items do
			ok(Treasure.byId[itemId] ~= nil, set.id .. " item " .. itemId)
		end
		ok(Badges[set.badge] ~= nil, set.id .. " badge key " .. set.badge)
		local stat = set.bonus.stat
		ok(stat == "luck" or stat == "sell" or stat == "oxygen" or stat == "clawSpeed" or stat == "speed" or stat == "sonar" or stat == "cargo", set.id .. " bonus stat")
	end
end)

test("upgrades have 10+ levels and monotonic curves", function()
	ok(#Upgrades.list == 8, "8 upgrades")
	for _, upgrade in Upgrades.list do
		ok(#upgrade.values >= 10, upgrade.id .. " levels")
		for level = 2, #upgrade.values do
			ok(upgrade.values[level] >= upgrade.values[level - 1], upgrade.id .. " value decreases at " .. level)
			local cost = Stats.upgradeCost(upgrade.id, level)
			ok(cost > 0, upgrade.id .. " cost at " .. level)
			if level > 2 then
				ok(cost > Stats.upgradeCost(upgrade.id, level - 1), upgrade.id .. " cost not increasing at " .. level)
			end
		end
		if upgrade.speed then
			ok(#upgrade.speed == #upgrade.values, upgrade.id .. " speed array length")
		end
		if upgrade.cooldown then
			ok(#upgrade.cooldown == #upgrade.values, upgrade.id .. " cooldown array length")
		end
	end
	-- Claw tiers must reach the highest rarity requirement
	local maxTier = Upgrades.byId.Claw.values[#Upgrades.byId.Claw.values]
	for _, rarity in Rarities.list do
		ok(rarity.clawTier <= maxTier, "claw can't reach tier " .. rarity.clawTier)
	end
	-- Hull must reach the bottom of the world
	ok(Upgrades.byId.Hull.values[#Upgrades.byId.Hull.values] >= Zones.list[#Zones.list].meters[2], "hull reaches bottom")
end)

test("zones are contiguous and holes fit inside the next zone", function()
	for i, zone in Zones.list do
		ok(zone.index == i, zone.id .. " index")
		ok(zone.topY > zone.bottomY, zone.id .. " band")
		if i > 1 then
			local above = Zones.list[i - 1]
			ok(above.bottomY == zone.topY, zone.id .. " stud band gap")
			ok(above.meters[2] == zone.meters[1], zone.id .. " metre band gap")
			local hole = above.hole
			ok(hole ~= nil, above.id .. " needs a hole to reach " .. zone.id)
			if hole then
				local reach = math.sqrt(hole.x * hole.x + hole.z * hole.z) + hole.r
				ok(reach < zone.radius - 20, above.id .. " hole pokes into " .. zone.id .. " walls")
				ok(reach < above.radius - 20, above.id .. " hole pokes into its own walls")
			end
		end
		for _, predatorId in zone.predators do
			ok(Predators.byId[predatorId] ~= nil, zone.id .. " predator " .. predatorId)
		end
		ok(Sounds.sounds[zone.ambient] ~= nil, zone.id .. " ambient sound")
		ok(Sounds.sounds[zone.music] ~= nil, zone.id .. " music")
	end
end)

test("zones that share a terrain material give it the same colour", function()
	local seen: { [Enum.Material]: { color: Color3, zone: string } } = {}
	for _, zone in Zones.list do
		for _, slot in { "floor", "wall", "accent" } do
			local material = (zone.materials :: any)[slot]
			local color = (zone.materialColors :: any)[slot]
			local previous = seen[material]
			if previous then
				ok(previous.color == color, string.format("%s %s colour clashes with %s (%s)", zone.id, slot, previous.zone, tostring(material)))
			else
				seen[material] = { color = color, zone = zone.id }
			end
		end
	end
end)

test("sound keys referenced by config exist", function()
	for _, rarity in Rarities.list do
		ok(Sounds.sounds[rarity.sound] ~= nil, rarity.id .. " reveal sound")
	end
	for _, event in Events.list do
		ok(Sounds.sounds[event.music] ~= nil, event.id .. " music")
	end
	for key, def in Sounds.sounds do
		ok(def.group == "SFX" or def.group == "Music" or def.group == "Ambient", key .. " group")
		ok(type(def.id) == "string" and def.id:sub(1, 13) == "rbxassetid://", key .. " id format")
	end
end)

test("quests, achievements, daily rewards and skins are consistent", function()
	for _, template in Quests.templates do
		for _, tiers in { template.daily, template.weekly } do
			if tiers then
				ok(#tiers == Zones.count, template.id .. " needs one tier per zone")
				for _, tier in tiers do
					ok(tier.n > 0, template.id .. " target")
					ok(tier.rarity == nil or Rarities.byId[tier.rarity] ~= nil, template.id .. " rarity")
					ok(tier.category == nil or Categories.byId[tier.category] ~= nil, template.id .. " category")
					ok(tier.condition == nil or Conditions.byId[tier.condition] ~= nil, template.id .. " condition")
				end
			end
		end
	end
	local statKeys = {
		FishCaught = true, TreasureSalvaged = true, PerfectCatches = true, DeepestMeters = true,
		RiftVisits = true, GoldenCatches = true, MutatedCatches = true, MythicPlus = true,
		Secrets = true, SetsCompleted = true, EventItems = true, Rebirths = true, CleanDives = true,
		IndexPercent = true,
	}
	for _, a in Achievements.list do
		ok(statKeys[a.stat], a.id .. " stat " .. a.stat)
		ok(a.skin == nil or Skins.byId[a.skin] ~= nil, a.id .. " skin")
		ok(a.skin ~= nil or (a.coins or 0) > 0, a.id .. " has no reward")
	end
	for _, reward in Daily.rewards do
		ok(reward.boost == nil or reward.boost == "Luck" or reward.boost == "Sell", "daily boost")
		ok(reward.consumable == nil or Products.productsByKey[reward.consumable.key] ~= nil, "daily consumable")
	end
	ok(#Daily.rewards == 7, "7-day calendar")
	ok(Skins.byId[Products.vipSkin] ~= nil, "VIP skin exists")
	for _, perk in Rebirth.perks do
		ok(#perk.costs >= 1, perk.id .. " costs")
		ok(perk.skin == nil or Skins.byId[perk.skin] ~= nil, perk.id .. " skin")
	end
	-- every non-default skin is obtainable somewhere
	for _, skin in Skins.list do
		if skin.source ~= "default" then
			local obtainable = skin.id == Products.vipSkin
			for _, a in Achievements.list do
				obtainable = obtainable or a.skin == skin.id
			end
			for _, perk in Rebirth.perks do
				obtainable = obtainable or perk.skin == skin.id
			end
			ok(obtainable, skin.id .. " can't be unlocked")
		end
	end
end)

test("mutations and products", function()
	for _, m in Mutations.list do
		ok(m.odds > 1 and m.multiplier > 1, m.id)
		if m.eventOnly then
			for _, eventId in m.eventOnly do
				ok(Events.byId[eventId] ~= nil, m.id .. " event " .. eventId)
			end
		end
	end
	local keys = {}
	for _, p in Products.passes do
		ok(not keys[p.key], "duplicate key " .. p.key)
		keys[p.key] = true
	end
	for _, p in Products.products do
		ok(not keys[p.key], "duplicate key " .. p.key)
		keys[p.key] = true
	end
	for _, event in Events.list do
		for _, mutationId in event.modifiers.enableMutations or {} do
			ok(Mutations.byId[mutationId] ~= nil, event.id .. " mutation")
		end
		for mutationId in event.modifiers.mutationMult or {} do
			ok(Mutations.byId[mutationId] ~= nil, event.id .. " mutation mult")
		end
		for tier in event.modifiers.tierMult or {} do
			ok(Rarities.byId[tier] ~= nil, event.id .. " tier mult")
		end
		for category in event.modifiers.categoryWeight or {} do
			ok(Categories.byId[category] ~= nil, event.id .. " category weight")
		end
	end
end)

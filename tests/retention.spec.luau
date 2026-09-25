local Calendar = require(Shared.Modules.Calendar)
local QuestMath = require(Shared.Modules.QuestMath)
local Hash = require(Shared.Modules.Hash)
local Quests = require(Shared.Config.Quests)
local DailyRewards = require(Shared.Config.DailyRewards)

local DAY = 86400
-- 2024-06-03 00:00 UTC was a Monday
local MONDAY = 1717372800

test("calendar days and weeks roll over at UTC midnight / Monday", function()
	eq(Calendar.day(MONDAY), MONDAY // DAY)
	eq(Calendar.week(MONDAY), Calendar.week(MONDAY + 6 * DAY + DAY - 1))
	ok(Calendar.week(MONDAY) ~= Calendar.week(MONDAY - 1), "Sunday 23:59 is the previous week")
	eq(Calendar.nextDayAt(MONDAY + 5), MONDAY + DAY)
	eq(Calendar.nextWeekAt(MONDAY + 3 * DAY), MONDAY + 7 * DAY)
	eq(Calendar.nextWeekAt(MONDAY), MONDAY + 7 * DAY)
end)

test("daily streak continues, loops after 7 and resets on a missed day", function()
	local today = Calendar.day(MONDAY)
	local fresh = Calendar.dailyState({ LastDay = 0, Streak = 0, Claimed = 0 }, MONDAY)
	ok(fresh.canClaim, "first claim")
	eq(fresh.slot, 1)
	eq(fresh.broken, false)

	local continued = Calendar.dailyState({ LastDay = today - 1, Streak = 3, Claimed = 3 }, MONDAY)
	eq(continued.slot, 4)
	eq(continued.streak, 4)

	local looped = Calendar.dailyState({ LastDay = today - 1, Streak = #DailyRewards.rewards, Claimed = 7 }, MONDAY)
	eq(looped.slot, 1)
	eq(looped.streak, #DailyRewards.rewards + 1)

	local missed = Calendar.dailyState({ LastDay = today - 2, Streak = 5, Claimed = 5 }, MONDAY)
	ok(missed.canClaim)
	eq(missed.slot, 1)
	eq(missed.broken, true)

	local claimed = Calendar.dailyState({ LastDay = today, Streak = 2, Claimed = 2 }, MONDAY)
	eq(claimed.canClaim, false)
	eq(claimed.slot, 3)
end)

test("quest generation draws distinct templates with tiered targets", function()
	for tier = 1, 6 do
		for seed = 1, 40 do
			local rng = Hash.rng(seed * 7 + tier)
			local daily = QuestMath.generate(rng, "daily", tier, Quests.dailyCount, 0)
			eq(#daily, Quests.dailyCount)
			local seen = {}
			for _, quest in daily do
				ok(not seen[quest.id], "duplicate daily quest " .. quest.id)
				seen[quest.id] = true
				ok(quest.target > 0 and quest.reward > 0, "target and reward")
				eq(quest.progress, 0)
				ok(not QuestMath.text(quest):find("{"), "all placeholders filled: " .. QuestMath.text(quest))
			end
			local weekly = QuestMath.generate(rng, "weekly", tier, Quests.weeklyCount, 1)
			eq(#weekly, Quests.weeklyCount)
			for _, quest in weekly do
				ok(Quests.byId[quest.id].weekly ~= nil, "weekly template")
				eq(quest.tokens, Quests.weeklyTokens)
				eq(quest.boost, Quests.weeklyBoost)
				ok(not QuestMath.text(quest):find("{"), "weekly placeholders filled")
			end
		end
	end
	local noRebirth = QuestMath.generate(Hash.rng(3), "weekly", 1, 3, 0)
	eq(noRebirth[1].tokens, nil)
end)

test("quest progress rules match items", function()
	local catchRare = { id = "CatchRarity", target = 3, progress = 0, claimed = false, reward = 1, rarity = 3 }
	eq(QuestMath.itemProgress(catchRare, { u = 1, k = "F", i = "SandyMinnow", r = 3, v = 1, z = 1, t = 0 }, 1), 1)
	eq(QuestMath.itemProgress(catchRare, { u = 1, k = "F", i = "SandyMinnow", r = 2, v = 1, z = 1, t = 0 }, 1), 0)
	eq(QuestMath.itemProgress(catchRare, { u = 1, k = "T", i = "TarnishedDoubloon", r = 5, v = 1, z = 1, t = 0 }, 1), 0)
	local zoneQuest = { id = "CatchZone", target = 3, progress = 0, claimed = false, reward = 1, zone = 2 }
	eq(QuestMath.itemProgress(zoneQuest, { u = 1, k = "F", i = "SandyMinnow", r = 1, v = 1, z = 1, t = 0 }, 1), 0)
	eq(QuestMath.itemProgress(zoneQuest, { u = 1, k = "F", i = "SandyMinnow", r = 1, v = 1, z = 3, t = 0 }, 3), 1)
	local condition = { id = "SalvageCondition", target = 2, progress = 0, claimed = false, reward = 1, condition = 4 }
	eq(QuestMath.itemProgress(condition, { u = 1, k = "T", i = "TarnishedDoubloon", r = 1, v = 1, z = 1, t = 0, c = "Pristine" }, 1), 1)
	eq(QuestMath.itemProgress(condition, { u = 1, k = "T", i = "TarnishedDoubloon", r = 1, v = 1, z = 1, t = 0, c = "Worn" }, 1), 0)
	local category = { id = "SalvageRelics", target = 2, progress = 0, claimed = false, reward = 1, category = "Coins" }
	eq(QuestMath.itemProgress(category, { u = 1, k = "T", i = "TarnishedDoubloon", r = 1, v = 1, z = 1, t = 0, c = "Worn" }, 1), 1)
	local perfect = { id = "Perfect", target = 2, progress = 0, claimed = false, reward = 1 }
	eq(QuestMath.itemProgress(perfect, { u = 1, k = "F", i = "SandyMinnow", r = 1, v = 1, z = 1, t = 0, p = true }, 1), 1)
	eq(QuestMath.itemProgress(perfect, { u = 1, k = "F", i = "SandyMinnow", r = 1, v = 1, z = 1, t = 0 }, 1), 0)
end)

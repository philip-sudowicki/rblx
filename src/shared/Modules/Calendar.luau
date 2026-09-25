--!strict
-- UTC day / week keys and the login-streak rules, shared by the server (rewards) and the client
-- (calendar UI and countdowns). Days roll over at 00:00 UTC, weeks on Monday 00:00 UTC.

local Config = script.Parent.Parent.Config
local Quests = require(Config.Quests)
local DailyRewards = require(Config.DailyRewards)

local Calendar = {}

local DAY = 86400

function Calendar.day(now: number): number
	return now // DAY
end

function Calendar.week(now: number): number
	return (Calendar.day(now) + Quests.weekStartOffsetDays) // 7
end

-- Unix time of the next 00:00 UTC.
function Calendar.nextDayAt(now: number): number
	return (Calendar.day(now) + 1) * DAY
end

-- Unix time of the next Monday 00:00 UTC.
function Calendar.nextWeekAt(now: number): number
	return ((Calendar.week(now) + 1) * 7 - Quests.weekStartOffsetDays) * DAY
end

export type DailyData = { LastDay: number, Streak: number, Claimed: number }

export type DailyState = {
	canClaim: boolean,
	slot: number, -- calendar slot (1..7) claimable now, or the next one if already claimed today
	streak: number, -- streak after the next claim
	broken: boolean, -- a day was missed, so the streak restarts
}

function Calendar.dailyState(daily: DailyData, now: number): DailyState
	local today = Calendar.day(now)
	local cycle = #DailyRewards.rewards
	if daily.LastDay >= today then
		-- already claimed today: preview tomorrow's slot
		return { canClaim = false, slot = daily.Streak % cycle + 1, streak = daily.Streak + 1, broken = false }
	end
	local continues = daily.LastDay == today - 1 and daily.Streak > 0
	local streak = if continues then daily.Streak + 1 else 1
	return { canClaim = true, slot = (streak - 1) % cycle + 1, streak = streak, broken = not continues and daily.Streak > 0 }
end

return Calendar

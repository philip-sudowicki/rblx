local EventSchedule = require(Shared.Modules.EventSchedule)
local Events = require(Shared.Config.Events)

test("same cycle always gives the same events", function()
	for index = 1000, 1100 do
		local a = EventSchedule.cycle(index)
		local b = EventSchedule.cycle(index)
		eq(#a.events, #b.events)
		for i, id in a.events do
			eq(b.events[i], id)
			ok(Events.byId[id] ~= nil, "valid event")
		end
		if a.super then
			eq(#a.events, 2)
			ok(a.events[1] ~= a.events[2], "super events are distinct")
		else
			eq(#a.events, 1)
		end
	end
end)

test("events are evenly spread and super events are ~5%", function()
	local counts = {}
	local supers = 0
	local n = 12000
	for index = 1, n do
		local c = EventSchedule.cycle(index)
		counts[c.events[1]] = (counts[c.events[1]] or 0) + 1
		if c.super then
			supers += 1
		end
	end
	for _, event in Events.list do
		near((counts[event.id] or 0) / n, 1 / #Events.list, 0.02, event.id)
	end
	near(supers / n, Events.schedule.superChance, 0.01, "super chance")
end)

test("state windows: active, ended, countdown", function()
	local cycle = EventSchedule.cycle(EventSchedule.cycleIndexAt(1790294400))
	local s1 = EventSchedule.state(cycle.startsAt + 5)
	eq(#s1.active, #cycle.events, "active at start")
	eq(s1.activeEndsAt, cycle.startsAt + Events.schedule.durationSeconds)
	local s2 = EventSchedule.state(cycle.startsAt + Events.schedule.durationSeconds + 1)
	eq(#s2.active, 0, "ended after duration")
	eq(s2.countdown, false)
	local s3 = EventSchedule.state(cycle.startsAt + Events.schedule.cycleSeconds - 30)
	eq(s3.countdown, true, "countdown in the last minute")
	eq(s3.nextCycle.index, cycle.index + 1)
	local up = EventSchedule.upcoming(cycle.startsAt + 5, 3)
	eq(up[1].index, cycle.index + 1, "upcoming skips the running cycle")
end)

test("weekday and weekend in UTC", function()
	eq(EventSchedule.weekday(1790294400), 5, "2026-09-25 is a Friday")
	eq(EventSchedule.isWeekend(1790294400), false)
	eq(EventSchedule.isWeekend(1790380800 + 3600), true, "Saturday")
	eq(EventSchedule.isWeekend(1790553600 + 60), false, "Monday")
	eq(EventSchedule.isWeekend(1790553600 - 60), true, "Sunday night")
end)

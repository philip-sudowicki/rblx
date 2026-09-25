--!strict
-- Pure, deterministic event schedule derived from UTC time.
-- Every server computes the same answer for the same timestamp, with no coordination.

local Config = script.Parent.Parent.Config
local Events = require(Config.Events)
local Hash = require(script.Parent.Hash)

export type Cycle = {
	index: number,
	startsAt: number,
	endsAt: number,
	events: { string },
	super: boolean,
}

export type State = {
	now: number,
	current: Cycle, -- the cycle containing `now` (its event may already be over)
	active: { string }, -- scheduled events running right now
	activeEndsAt: number,
	nextCycle: Cycle, -- the next cycle whose event hasn't started yet
	countdown: boolean, -- true during the countdown window before nextCycle starts
	weekend: boolean,
}

local EventSchedule = {}

local schedule = Events.schedule
local saltHash = Hash.string(schedule.salt)

function EventSchedule.cycleIndexAt(t: number): number
	return math.floor((t - schedule.epochOffset) / schedule.cycleSeconds)
end

function EventSchedule.cycle(index: number): Cycle
	local h = Hash.combine(saltHash, index)
	local count = #Events.list
	local first = (h % count) + 1
	local events = { Events.list[first].id }
	local super = Hash.float(Hash.combine(h, 0x5E5E)) < schedule.superChance
	if super and count > 1 then
		local offset = (Hash.combine(h, 0xB0B) % (count - 1)) + 1
		local second = ((first - 1 + offset) % count) + 1
		table.insert(events, Events.list[second].id)
	end
	local startsAt = schedule.epochOffset + index * schedule.cycleSeconds
	return {
		index = index,
		startsAt = startsAt,
		endsAt = startsAt + schedule.durationSeconds,
		events = events,
		super = super,
	}
end

-- Day of week for a unix timestamp: 0 = Sunday … 6 = Saturday (UTC). Unix day 0 was a Thursday.
function EventSchedule.weekday(t: number): number
	return (math.floor(t / 86400) + 4) % 7
end

function EventSchedule.isWeekend(t: number): boolean
	if not Events.weekend.enabled then
		return false
	end
	local day = EventSchedule.weekday(t)
	return day == 0 or day == 6
end

function EventSchedule.state(t: number): State
	local index = EventSchedule.cycleIndexAt(t)
	local current = EventSchedule.cycle(index)
	local running = t >= current.startsAt and t < current.endsAt
	local nextCycle = EventSchedule.cycle(index + 1)
	return {
		now = t,
		current = current,
		active = if running then current.events else {},
		activeEndsAt = if running then current.endsAt else 0,
		nextCycle = nextCycle,
		countdown = (nextCycle.startsAt - t) <= schedule.countdownSeconds,
		weekend = EventSchedule.isWeekend(t),
	}
end

-- Next `count` cycles from time t (for "upcoming events" UI).
function EventSchedule.upcoming(t: number, count: number): { Cycle }
	local out = {}
	local index = EventSchedule.cycleIndexAt(t)
	if t >= EventSchedule.cycle(index).startsAt then
		index += 1
	end
	for i = 0, count - 1 do
		table.insert(out, EventSchedule.cycle(index + i))
	end
	return out
end

return EventSchedule

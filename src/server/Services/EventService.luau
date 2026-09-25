--!strict
-- Automated events. Scheduled events come from the UTC-seeded EventSchedule, so every server
-- runs the same event at the same moment. Purchased "Skip Event Timer" events run locally in
-- one server. This service aggregates the active modifiers and replicates state to clients;
-- special world content (Leviathan, Galleon, Tremor) listens to ServerSignals.EventsChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local EventSchedule = require(Shared.Modules.EventSchedule)
local Remotes = require(script.Parent.Remotes)
local AnnounceService = require(script.Parent.AnnounceService)
local ServerSignals = require(script.Parent.ServerSignals)

export type ActiveEvent = { id: string, endsAt: number, source: string, startedAt: number }

export type Modifiers = {
	luck: number,
	tierMult: { [string]: number },
	mutationMult: { [string]: number },
	enabledMutations: { [string]: boolean },
	sellMult: number,
	exclusive: { { id: string, chance: number } },
	predatorAggro: number,
	predatorDensity: number,
	categoryWeight: { [string]: number },
}

local EventService = {}

local localEvents: { ActiveEvent } = {}
local queuedLocal = 0
local pendingBuyers: { string } = {}
local localCooldownUntil = 0
local debugEvents: { ActiveEvent } = {}
local active: { ActiveEvent } = {}
local activeKey = ""
local weekendNow = false
local countdownCycle = -1
local modifiers: Modifiers

local function emptyModifiers(): Modifiers
	return {
		luck = 1,
		tierMult = {},
		mutationMult = {},
		enabledMutations = {},
		sellMult = 1,
		exclusive = {},
		predatorAggro = 1,
		predatorDensity = 1,
		categoryWeight = {},
	}
end
modifiers = emptyModifiers()

local function rebuildModifiers()
	local m = emptyModifiers()
	for _, entry in active do
		local def = Events.byId[entry.id]
		if def then
			local mods = def.modifiers
			m.luck *= mods.luck or 1
			local tierMult = mods.tierMult
			if tierMult then
				for tier, mult in tierMult do
					m.tierMult[tier] = (m.tierMult[tier] or 1) * mult
				end
			end
			local mutationMult = mods.mutationMult
			if mutationMult then
				for mutation, mult in mutationMult do
					m.mutationMult[mutation] = (m.mutationMult[mutation] or 1) * mult
				end
			end
			local enable = mods.enableMutations
			if enable then
				for _, mutation in enable do
					m.enabledMutations[mutation] = true
				end
			end
			m.sellMult *= mods.sellMult or 1
			if mods.exclusiveChance then
				table.insert(m.exclusive, { id = def.id, chance = mods.exclusiveChance })
			end
			m.predatorAggro = math.max(m.predatorAggro, mods.predatorAggro or 1)
			m.predatorDensity = math.max(m.predatorDensity, mods.predatorDensity or 1)
			local categoryWeight = mods.categoryWeight
			if categoryWeight then
				for category, weight in categoryWeight do
					m.categoryWeight[category] = (m.categoryWeight[category] or 1) * weight
				end
			end
		end
	end
	if weekendNow then
		m.luck *= Events.weekend.luck
		if #active > 0 then
			m.luck *= Events.weekend.eventLuck
		end
	end
	modifiers = m
end

function EventService.modifiers(): Modifiers
	return modifiers
end

function EventService.activeEvents(): { ActiveEvent }
	return active
end

function EventService.isActive(id: string): boolean
	for _, entry in active do
		if entry.id == id then
			return true
		end
	end
	return false
end

function EventService.activeIds(): { string }
	local ids = {}
	for _, entry in active do
		table.insert(ids, entry.id)
	end
	return ids
end

function EventService.isWeekend(): boolean
	return weekendNow
end

function EventService.localCooldownUntil(): number
	return localCooldownUntil
end

local function statePayload(now: number): any
	local schedule = EventSchedule.state(now)
	local list = {}
	for _, entry in active do
		table.insert(list, { id = entry.id, endsAt = entry.endsAt, source = entry.source, startedAt = entry.startedAt })
	end
	return {
		serverTime = now,
		active = list,
		nextStartsAt = schedule.nextCycle.startsAt,
		nextEvents = schedule.nextCycle.events,
		nextSuper = schedule.nextCycle.super,
		weekend = weekendNow,
		localCooldownUntil = localCooldownUntil,
		queued = queuedLocal,
		countdown = schedule.countdown,
	}
end

function EventService.sendState(player: Player?)
	local payload = statePayload(os.time())
	if player then
		Remotes.fire(player, "EventState", payload)
	else
		Remotes.fireAll("EventState", payload)
	end
end

local function eventNames(ids: { string }): string
	local names = {}
	for _, id in ids do
		local def = Events.byId[id]
		table.insert(names, if def then def.name else id)
	end
	return table.concat(names, " + ")
end

local function startLocal(now: number, buyer: string?)
	local candidates = {}
	for _, def in Events.list do
		if not EventService.isActive(def.id) then
			table.insert(candidates, def.id)
		end
	end
	if #candidates == 0 then
		for _, def in Events.list do
			table.insert(candidates, def.id)
		end
	end
	local id = candidates[math.random(1, #candidates)]
	table.insert(localEvents, { id = id, startedAt = now, endsAt = now + Events.localEvent.durationSeconds, source = "local" })
	localCooldownUntil = now + Events.localEvent.cooldownSeconds
	ReplicatedStorage:SetAttribute("LocalEventCooldownUntil", localCooldownUntil)
	local def = Events.byId[id]
	local text = if buyer
		then string.format("⏩ %s skipped the event timer! %s %s starts NOW in this server!", buyer, def.icon, def.name)
		else string.format("%s %s starts NOW in this server!", def.icon, def.name)
	AnnounceService.chat(text, def.color)
end

-- Called by MonetizationService for a Skip Event Timer purchase. Never refuses: if the
-- per-server cooldown is running, the event is queued and starts when the cooldown ends.
function EventService.purchaseLocal(buyer: string)
	queuedLocal += 1
	ReplicatedStorage:SetAttribute("LocalEventQueued", queuedLocal)
	table.insert(pendingBuyers, buyer)
	EventService.tick()
end

-- Studio / debug: force an event on for `seconds`.
function EventService.debugStart(id: string, seconds: number)
	if not Events.byId[id] then
		return
	end
	local now = os.time()
	table.insert(debugEvents, { id = id, startedAt = now, endsAt = now + seconds, source = "debug" })
	EventService.tick()
end

function EventService.debugStop()
	table.clear(debugEvents)
	table.clear(localEvents)
	EventService.tick()
end

local function prune(list: { ActiveEvent }, now: number)
	for i = #list, 1, -1 do
		if list[i].endsAt <= now then
			table.remove(list, i)
		end
	end
end

function EventService.tick()
	local now = os.time()
	local schedule = EventSchedule.state(now)
	prune(localEvents, now)
	prune(debugEvents, now)
	if queuedLocal > 0 and now >= localCooldownUntil and #localEvents == 0 then
		queuedLocal -= 1
		ReplicatedStorage:SetAttribute("LocalEventQueued", queuedLocal)
		local buyer = table.remove(pendingBuyers, 1)
		startLocal(now, buyer)
	end

	local merged: { [string]: ActiveEvent } = {}
	local function add(entry: ActiveEvent)
		local existing = merged[entry.id]
		if not existing or existing.endsAt < entry.endsAt then
			merged[entry.id] = entry
		end
	end
	for _, id in schedule.active do
		add({ id = id, endsAt = schedule.activeEndsAt, source = "scheduled", startedAt = schedule.current.startsAt })
	end
	for _, entry in localEvents do
		add(entry)
	end
	for _, entry in debugEvents do
		add(entry)
	end
	local list = {}
	for _, entry in merged do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local keyParts = {}
	for _, entry in list do
		table.insert(keyParts, entry.id)
	end
	local key = table.concat(keyParts, ",")
	local weekendChanged = schedule.weekend ~= weekendNow
	weekendNow = schedule.weekend

	if key ~= activeKey then
		local previous = {}
		for _, entry in active do
			previous[entry.id] = true
		end
		local started = {}
		for _, entry in list do
			if not previous[entry.id] then
				table.insert(started, entry.id)
			end
			previous[entry.id] = nil
		end
		active = list
		activeKey = key
		rebuildModifiers()
		if #started > 0 then
			local isSuper = #started >= 2 and schedule.current.super
			local first = Events.byId[started[1]]
			local label = if isSuper then "⚡ SUPER EVENT! " else ""
			AnnounceService.banner(label .. eventNames(started) .. " has begun!", first.color, 7)
			AnnounceService.chat(string.format("%s%s %s has begun! %s", label, first.icon, eventNames(started), first.desc), first.color)
		end
		for endedId in previous do
			local def = Events.byId[endedId]
			if def then
				AnnounceService.chat(string.format("%s %s has ended.", def.icon, def.name), def.color)
			end
		end
		ServerSignals.EventsChanged:Fire()
		EventService.sendState(nil)
	elseif weekendChanged then
		rebuildModifiers()
		ServerSignals.EventsChanged:Fire()
		EventService.sendState(nil)
	end

	if schedule.countdown and countdownCycle ~= schedule.nextCycle.index then
		countdownCycle = schedule.nextCycle.index
		local def = Events.byId[schedule.nextCycle.events[1]]
		local label = if schedule.nextCycle.super then "⚡ SUPER EVENT: " else ""
		AnnounceService.chat(
			string.format("⏳ %s%s starts in %d seconds!", label, eventNames(schedule.nextCycle.events), math.max(0, schedule.nextCycle.startsAt - now)),
			def.color
		)
		EventService.sendState(nil)
	end
end

function EventService.Start()
	ReplicatedStorage:SetAttribute("LocalEventCooldownUntil", 0)
	ReplicatedStorage:SetAttribute("LocalEventQueued", 0)
	EventService.tick()
	Players.PlayerAdded:Connect(function(player)
		task.defer(EventService.sendState, player)
	end)
	task.spawn(function()
		local sinceSync = 0
		while true do
			task.wait(1)
			EventService.tick()
			sinceSync += 1
			if sinceSync >= 30 then
				sinceSync = 0
				EventService.sendState(nil)
			end
		end
	end)
end

return EventService

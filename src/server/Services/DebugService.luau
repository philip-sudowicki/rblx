--!strict
-- Developer commands for testing in Studio (never available in live servers, except to the
-- experience owner). Sent from the client debug console (F8 in Studio) as one text line:
--   coins <n>              add coins            tokens <n>          add rebirth tokens
--   maxupgrades            max every upgrade    depth <metres>      set your deepest depth
--   event <id> [seconds]   start an event       event stop          stop debug/local events
--   tutorial reset|done    restart or finish    save                save your profile now

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Events = require(Shared.Config.Events)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local EventService = require(script.Parent.EventService)
local ServerSignals = require(script.Parent.ServerSignals)

local DebugService = {}

function DebugService.allowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function run(player: Player, line: string): string
	local args = string.split(line, " ")
	local command = string.lower(args[1] or "")
	local data = DataService.get(player)
	if not data then
		return "no data"
	end
	if command == "coins" then
		DataService.addCoins(player, tonumber(args[2]) or 1000000, "Debug")
		return "coins added"
	elseif command == "tokens" then
		DataService.addTokens(player, tonumber(args[2]) or 10)
		return "tokens added"
	elseif command == "maxupgrades" then
		for _, upgrade in Upgrades.list do
			data.Upgrades[upgrade.id] = #upgrade.values
		end
		DataService.replicate(player, "Upgrades")
		ServerSignals.StatsDirty:Fire(player)
		return "upgrades maxed"
	elseif command == "depth" then
		data.Stats.DeepestMeters = math.max(0, tonumber(args[2]) or 6000)
		DataService.replicate(player, "Stats")
		return "deepest set"
	elseif command == "event" then
		if string.lower(args[2] or "") == "stop" then
			EventService.debugStop()
			return "events stopped"
		end
		local id = args[2] or ""
		if not Events.byId[id] then
			local ids = {}
			for _, def in Events.list do
				table.insert(ids, def.id)
			end
			return "unknown event; try " .. table.concat(ids, ", ")
		end
		EventService.debugStart(id, tonumber(args[3]) or 300)
		return id .. " started"
	elseif command == "tutorial" then
		if args[2] == "reset" then
			data.Tutorial.Done = false
			data.Tutorial.Step = 1
		else
			data.Tutorial.Done = true
		end
		DataService.replicate(player, "Tutorial")
		return "tutorial " .. (args[2] or "done") .. " (rejoin to apply)"
	elseif command == "save" then
		DataService.save(player)
		return "saved"
	end
	return "unknown command"
end

function DebugService.Start()
	Remotes.on("DebugCommand", 2, 4, function(player, line)
		if typeof(line) ~= "string" or #line > 80 or not DebugService.allowed(player) then
			return
		end
		Remotes.notify(player, "[debug] " .. run(player, line), "info", "🛠️")
	end)
end

return DebugService

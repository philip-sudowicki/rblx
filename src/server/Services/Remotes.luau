--!strict
-- Every client » server remote is bound here with a rate limit. Handlers only run for players
-- whose profile has loaded, and run protected so a bad payload can never break the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)
local PlayerState = require(script.Parent.PlayerState)
local RateLimiter = require(script.Parent.RateLimiter)

local Remotes = {}

local bound: { [string]: boolean } = {}

function Remotes.Init()
	Net.createAll()
end

local function ready(player: Player): boolean
	local state = PlayerState.get(player)
	return state ~= nil and state.ready and player.Parent == Players
end

-- rate: sustained calls per second, burst: calls allowed at once
function Remotes.on(name: string, rate: number, burst: number, handler: (Player, ...any) -> (), allowBeforeReady: boolean?)
	assert(not bound[name], "remote bound twice: " .. name)
	bound[name] = true
	local remote = Net.event(name)
	assert(remote, "unknown remote " .. name)
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not RateLimiter.allow(player, name, rate, burst) then
			return
		end
		if not allowBeforeReady and not ready(player) then
			return
		end
		local ok, err = pcall(handler :: (...any) -> ...any, player, ...)
		if not ok then
			warn(string.format("[DeepHaul] remote %s from %s failed: %s", name, player.Name, tostring(err)))
		end
	end)
end

function Remotes.invoke(name: string, rate: number, burst: number, handler: (Player, ...any) -> any)
	assert(not bound[name], "remote bound twice: " .. name)
	bound[name] = true
	local remote = Net.func(name)
	remote.OnServerInvoke = function(player: Player, ...: any): any
		if not RateLimiter.allow(player, name, rate, burst) or not ready(player) then
			return { ok = false, message = "Slow down!" }
		end
		local ok, result = pcall(handler :: (...any) -> ...any, player, ...)
		if not ok then
			warn(string.format("[DeepHaul] invoke %s from %s failed: %s", name, player.Name, tostring(result)))
			return { ok = false, message = "Something went wrong." }
		end
		return result
	end
end

function Remotes.fire(player: Player, name: string, ...: any)
	if player.Parent == Players then
		Net.event(name):FireClient(player, ...)
	end
end

function Remotes.fireAll(name: string, ...: any)
	Net.event(name):FireAllClients(...)
end

function Remotes.fireList(players: { Player }, name: string, ...: any)
	local remote = Net.event(name)
	for _, player in players do
		if player.Parent == Players then
			remote:FireClient(player, ...)
		end
	end
end

function Remotes.unreliable(player: Player, name: string, ...: any)
	if player.Parent == Players then
		Net.unreliable(name):FireClient(player, ...)
	end
end

-- Toast notification helper. kind: "info" | "good" | "warn" | "bad"
function Remotes.notify(player: Player, text: string, kind: string?, icon: string?)
	Remotes.fire(player, "Notify", { text = text, kind = kind or "info", icon = icon })
end

return Remotes

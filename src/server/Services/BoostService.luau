--!strict
-- Server-wide luck boost (developer product). Personal boosts live in player data (DataService).
-- State is mirrored on ReplicatedStorage attributes for clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local AnnounceService = require(script.Parent.AnnounceService)
local ServerSignals = require(script.Parent.ServerSignals)
local PlayerState = require(script.Parent.PlayerState)

local BoostService = {}

local serverLuckUntil = 0

function BoostService.serverLuck(): number
	if os.time() < serverLuckUntil then
		return Products.serverLuck.multiplier
	end
	return 1
end

function BoostService.serverLuckUntil(): number
	return serverLuckUntil
end

local function dirtyAll()
	for _, state in PlayerState.all() do
		ServerSignals.StatsDirty:Fire(state.player)
	end
end

function BoostService.addServerLuck(seconds: number, buyerName: string?)
	local now = os.time()
	local current = math.max(now, serverLuckUntil)
	serverLuckUntil = math.min(current + seconds, now + Products.serverLuck.maxStackSeconds)
	ReplicatedStorage:SetAttribute("ServerLuckUntil", serverLuckUntil)
	ReplicatedStorage:SetAttribute("ServerLuckMult", Products.serverLuck.multiplier)
	if buyerName then
		AnnounceService.chat(
			string.format("🌟 %s activated a SERVER LUCK BOOST! Everyone gets %dx luck for %d minutes!", buyerName, Products.serverLuck.multiplier, math.floor(seconds / 60)),
			Color3.fromRGB(255, 220, 90)
		)
		AnnounceService.banner(string.format("🌟 %s boosted everyone's luck x%d!", buyerName, Products.serverLuck.multiplier), Color3.fromRGB(255, 220, 90), 6)
	end
	dirtyAll()
end

function BoostService.Start()
	ReplicatedStorage:SetAttribute("ServerLuckUntil", 0)
	ReplicatedStorage:SetAttribute("ServerLuckMult", Products.serverLuck.multiplier)
	-- refresh stats once when the boost runs out
	task.spawn(function()
		local wasActive = false
		while true do
			task.wait(2)
			local active = os.time() < serverLuckUntil
			if wasActive and not active then
				dirtyAll()
			end
			wasActive = active
		end
	end)
end

return BoostService

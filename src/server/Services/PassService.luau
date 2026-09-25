--!strict
-- Game pass ownership. Checked on join and updated live when a pass is bought in-game.
-- Ownership is mirrored to player attributes ("Pass_<Key>") so clients can read it.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local PlayerState = require(script.Parent.PlayerState)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)

local PassService = {}

local function grantPerks(player: Player, key: string)
	if key == "VIP" then
		local data = DataService.get(player)
		if data and not data.Skins.Owned[Products.vipSkin] then
			data.Skins.Owned[Products.vipSkin] = true
			DataService.replicate(player, "Skins")
		end
	end
end

function PassService.set(player: Player, key: string, owned: boolean)
	local state = PlayerState.get(player)
	if not state then
		return
	end
	local changed = (state.passes[key] == true) ~= owned
	state.passes[key] = owned
	player:SetAttribute("Pass_" .. key, owned)
	if owned then
		grantPerks(player, key)
	end
	if changed then
		ServerSignals.StatsDirty:Fire(player)
	end
end

function PassService.owns(player: Player, key: string): boolean
	local state = PlayerState.get(player)
	return state ~= nil and state.passes[key] == true
end

local function check(player: Player)
	for _, pass in Products.passes do
		if pass.id ~= 0 then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owned then
				PassService.set(player, pass.key, true)
			elseif not ok then
				warn(string.format("[DeepHaul] pass check failed for %s (%s): %s", player.Name, pass.key, tostring(owned)))
			end
		end
	end
end

function PassService.Start()
	DataService.onLoaded(check)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = Products.passesById[passId]
		if pass and player.Parent == Players then
			PassService.set(player, pass.key, true)
			Remotes.notify(player, "Thanks for supporting DEEP HAUL! " .. pass.name .. " is active.", "good", pass.icon)
		end
	end)
end

return PassService

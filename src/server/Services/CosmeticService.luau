--!strict
-- Sub skins: equip an owned skin (it shows from the next launch if you're mid-dive).
-- Skins are granted by AchievementService, PassService and RebirthService perks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skins = require(Shared.Config.Skins)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local Validate = require(script.Parent.Validate)

local CosmeticService = {}

function CosmeticService.grantSkin(player: Player, skinId: string, announce: boolean?): boolean
	local data = DataService.get(player)
	local skin = Skins.byId[skinId]
	if not data or not skin or data.Skins.Owned[skinId] then
		return false
	end
	data.Skins.Owned[skinId] = true
	DataService.replicate(player, "Skins")
	if announce ~= false then
		Remotes.notify(player, string.format("New sub skin unlocked: %s! Equip it in Upgrades → Hangar.", skin.name), "good", "🎨")
	end
	return true
end

function CosmeticService.equip(player: Player, skinId: string): boolean
	local data = DataService.get(player)
	local skin = Skins.byId[skinId]
	if not data or not skin then
		return false
	end
	if not data.Skins.Owned[skinId] then
		Remotes.notify(player, "You haven't unlocked that skin yet.", "warn", "🔒")
		return false
	end
	if data.Skins.Equipped == skinId then
		return false
	end
	data.Skins.Equipped = skinId
	DataService.replicate(player, "Skins")
	local state = PlayerState.get(player)
	local suffix = if state and state.dive then " It'll show on your next dive." else ""
	Remotes.notify(player, string.format("%s equipped.%s", skin.name, suffix), "good", "🎨")
	return true
end

function CosmeticService.Start()
	Remotes.on("EquipSkin", 2, 4, function(player, skinId)
		if Validate.oneOf(skinId, Skins.byId) then
			CosmeticService.equip(player, skinId)
		end
	end)
end

return CosmeticService

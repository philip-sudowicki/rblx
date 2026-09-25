--!strict
-- Saves player settings. The client applies them instantly; this only persists validated values
-- (never trusts the type or range the client sends).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local Validate = require(script.Parent.Validate)

local SettingsService = {}

local GRAPHICS: { [string]: boolean } = { High = true, Low = true }

-- Returns the sanitised value for a setting, or nil if the key/value is not acceptable.
function SettingsService.sanitize(key: any, value: any): any
	if key == "Music" or key == "SFX" then
		if Validate.number(value, 0, 1) then
			return math.floor(value * 100 + 0.5) / 100
		end
	elseif key == "Graphics" then
		if Validate.oneOf(value, GRAPHICS) then
			return value
		end
	elseif key == "SellKeep" then
		if Validate.integer(value, 2, Rarities.count + 1) then
			return value
		end
	elseif key == "Offers" or key == "CameraShake" then
		if Validate.boolean(value) then
			return value
		end
	end
	return nil
end

function SettingsService.Start()
	Remotes.on("SetSetting", 6, 12, function(player, key, value)
		local clean = SettingsService.sanitize(key, value)
		if clean == nil then
			return
		end
		local data = DataService.get(player)
		if data then
			(data.Settings :: any)[key] = clean
		end
	end)
end

return SettingsService

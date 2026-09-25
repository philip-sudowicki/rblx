--!strict
-- Code redemption (Shop » Codes). The code list is server-only (Config/Codes). Each code
-- works once per player; wrong guesses are throttled so the list can't be brute forced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Skins = require(Shared.Config.Skins)
local DepthMath = require(Shared.Modules.DepthMath)
local Stats = require(Shared.Modules.Stats)
local Format = require(Shared.Modules.Format)
local Codes = require(script.Parent.Parent.Config.Codes)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local CosmeticService = require(script.Parent.CosmeticService)

local CodesService = {}

local MAX_FAILURES = 5
local LOCKOUT_SECONDS = 60
local COIN_SCALE = { 1, 2, 4, 8, 15, 30, 60, 120, 240, 1000 }

local byCode: { [string]: Codes.Code } = {}
for _, entry in Codes do
	byCode[entry.code:upper()] = entry
end

type Failures = { count: number, lockedUntil: number }
local failures: { [Player]: Failures } = {}

function CodesService.normalize(text: string): string
	return (text:gsub("%s+", "")):upper()
end

local function fail(player: Player, message: string): (boolean, string)
	local record: Failures = failures[player] or { count = 0, lockedUntil = 0 }
	record.count += 1
	if record.count >= MAX_FAILURES then
		record.count = 0
		record.lockedUntil = os.clock() + LOCKOUT_SECONDS
	end
	failures[player] = record
	return false, message
end

function CodesService.redeem(player: Player, raw: string): (boolean, string)
	local data = DataService.get(player)
	if not data then
		return false, "Still loading - try again in a moment."
	end
	local record = failures[player]
	if record and os.clock() < record.lockedUntil then
		return false, string.format("Too many tries. Wait %ds and try again.", math.ceil(record.lockedUntil - os.clock()))
	end
	local code = CodesService.normalize(raw)
	if #code == 0 then
		return false, "Type a code first."
	end
	local entry = byCode[code]
	if not entry then
		return fail(player, "That code doesn't exist. Check the spelling!")
	end
	if data.Codes[code] then
		return false, "You've already redeemed that code."
	end
	if entry.expires and os.time() >= entry.expires then
		return fail(player, "That code has expired.")
	end
	if entry.minRebirths and data.Rebirths < entry.minRebirths then
		return false, string.format("You need to Resurface %d time%s to use this code.", entry.minRebirths, if entry.minRebirths == 1 then "" else "s")
	end
	data.Codes[code] = true
	failures[player] = nil
	local rewards = entry.rewards
	local parts = {}
	if rewards.coins then
		local coins = rewards.coins * Stats.coinScale(COIN_SCALE, DepthMath.zoneIndexAtMeters(data.Stats.DeepestMeters))
		DataService.addCoins(player, coins, "Code")
		Remotes.fire(player, "Effect", { kind = "Coins", coins = coins })
		table.insert(parts, Format.short(coins) .. " coins")
	end
	if rewards.boosts then
		for boostId, seconds in rewards.boosts do
			local boost = Game.Boosts[boostId]
			if boost then
				DataService.addBoost(player, boostId, seconds)
				table.insert(parts, string.format("%s (%d min)", boost.name, math.floor(seconds / 60)))
			end
		end
	end
	if rewards.consumables then
		for key, amount in rewards.consumables do
			DataService.addConsumable(player, key, amount)
			table.insert(parts, string.format("%d× %s", amount, (key:gsub("(%l)(%u)", "%1 %2"))))
		end
	end
	if rewards.tokens then
		DataService.addTokens(player, rewards.tokens)
		table.insert(parts, string.format("%d rebirth tokens", rewards.tokens))
	end
	if rewards.skin and Skins.byId[rewards.skin] then
		CosmeticService.grantSkin(player, rewards.skin, false)
		table.insert(parts, Skins.byId[rewards.skin].name .. " skin")
	end
	DataService.save(player)
	return true, "Redeemed! " .. table.concat(parts, ", ")
end

function CodesService.Start()
	Remotes.invoke("RedeemCode", 0.5, 3, function(player, raw)
		if typeof(raw) ~= "string" or #raw > 40 or utf8.len(raw) == nil then
			return { ok = false, message = "That code doesn't exist." }
		end
		local ok, message = CodesService.redeem(player, raw)
		return { ok = ok, message = message }
	end)
	ServerSignals.PlayerLeaving:Connect(function(player)
		failures[player] = nil
	end)
end

return CodesService

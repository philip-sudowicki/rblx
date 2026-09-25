--!strict
-- First-time tutorial, server side. data.Tutorial.Step advances only on real gameplay:
-- launching, descending, catching a fish, salvaging a treasure, surfacing, selling and buying
-- an upgrade. It spawns the guided fish / treasure, pays the bonus and finish coins, and tells
-- the client what to show through the "Tutorial" remote. Players can skip it at any time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Game = require(Shared.Config.Game)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local ServerSignals = require(script.Parent.ServerSignals)
local SpawnService = require(script.Parent.SpawnService)
local SubService = require(script.Parent.SubService)
local WorldService = require(script.Parent.WorldService)

local TutorialService = {}

type Guide = { fish: number?, treasure: number? }

local guides: { [Player]: Guide } = {}

local function currentStep(data: Types.PlayerData): string?
	if data.Tutorial.Done then
		return nil
	end
	local step = Tutorial.steps[data.Tutorial.Step]
	return if step then step.id else nil
end

local function promptPosition(action: string?): Vector3?
	local dock = WorldService.dock
	if not dock or not action then
		return nil
	end
	local prompt = dock.prompts[action]
	local parent = if prompt then prompt.Parent else nil
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function send(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	if data.Tutorial.Done then
		Remotes.fire(player, "Tutorial", { done = true })
		return
	end
	local step = Tutorial.steps[data.Tutorial.Step]
	local guide = guides[player]
	Remotes.fire(player, "Tutorial", {
		step = data.Tutorial.Step,
		target = if step then promptPosition(step.target) else nil,
		launch = promptPosition("Launch"),
		fish = if guide then guide.fish else nil,
		treasure = if guide then guide.treasure else nil,
	})
end

-- Stops pointing at the guided fish / treasure (they despawn on their own lifetime).
local function clearGuide(player: Player)
	guides[player] = nil
end

-- Makes sure the guided fish / treasure for the current step exists (while diving).
local function ensureGuide(player: Player): boolean
	local data = DataService.get(player)
	if not data or not SubService.isDiving(player) then
		return false
	end
	local step = currentStep(data)
	local guide: Guide = guides[player] or {}
	guides[player] = guide
	local changed = false
	if step == "Catch" and not (guide.fish and SpawnService.fish[guide.fish]) then
		local entity = SpawnService.spawnTutorialFish(player)
		guide.fish = if entity then entity.id else nil
		changed = true
	elseif step == "Salvage" and not (guide.treasure and SpawnService.treasure[guide.treasure]) then
		local entity = SpawnService.spawnTutorialTreasure(player)
		guide.treasure = if entity then entity.id else nil
		changed = true
	end
	return changed
end

local function finish(player: Player, skipped: boolean)
	local data = DataService.get(player)
	if not data or data.Tutorial.Done then
		return
	end
	data.Tutorial.Done = true
	data.Tutorial.Step = #Tutorial.steps + 1
	clearGuide(player)
	DataService.replicate(player, "Tutorial")
	if skipped then
		Remotes.notify(player, "Tutorial skipped. Dive in and have fun - the Quest Board has goals if you want them!", "info", "⚓")
	else
		DataService.addCoins(player, Game.Economy.TutorialFinishCoins, "Tutorial")
		Remotes.fire(player, "Effect", { kind = "Coins", coins = Game.Economy.TutorialFinishCoins })
		Remotes.fire(player, "Effect", { kind = "TutorialDone" })
		Remotes.notify(player, string.format("Tutorial complete! +%d coins. Now dive deeper - rarer fish live further down.", Game.Economy.TutorialFinishCoins), "good", "🎉")
	end
	send(player)
	DataService.save(player)
end

local function enter(player: Player, index: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	if index > #Tutorial.steps then
		finish(player, false)
		return
	end
	data.Tutorial.Step = index
	DataService.replicate(player, "Tutorial")
	local step = Tutorial.steps[index].id
	if step == "Catch" or step == "Salvage" then
		ensureGuide(player)
	elseif step == "Descend" then
		-- a gentle fallback if they stay shallow
		task.delay(20, function()
			local current = DataService.get(player)
			if current and currentStep(current) == "Descend" and SubService.isDiving(player) then
				enter(player, index + 1)
			end
		end)
	elseif step == "Sell" then
		-- lost everything in a blackout? Skip straight to the upgrade with the bonus.
		local sellable = false
		for _, item in data.Inventory do
			if not item.g and not item.f and item.d == nil then
				sellable = true
				break
			end
		end
		if not sellable then
			DataService.addCoins(player, Game.Economy.TutorialBonusCoins, "Tutorial")
			enter(player, index + 1)
			return
		end
	end
	send(player)
end

-- Moves on only if the player is on `stepId` (signals can arrive in any order).
local function advanceFrom(player: Player, stepId: string)
	local data = DataService.get(player)
	if data and currentStep(data) == stepId then
		enter(player, data.Tutorial.Step + 1)
	end
end

function TutorialService.isActive(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and not data.Tutorial.Done
end

function TutorialService.Start()
	DataService.onLoaded(function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		if not data.Tutorial.Done then
			data.Tutorial.Step = math.clamp(data.Tutorial.Step, 1, #Tutorial.steps)
			-- a rejoin mid-dive step restarts from the launch
			local step = currentStep(data)
			if step == "Descend" or step == "Catch" or step == "Salvage" or step == "Surface" then
				data.Tutorial.Step = Tutorial.indexOf.Launch
			end
		end
		task.delay(2, send, player)
	end)
	ServerSignals.DiveStarted:Connect(function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		local step = currentStep(data)
		if step == "Launch" then
			enter(player, data.Tutorial.Step + 1)
		elseif step == "Catch" or step == "Salvage" then
			ensureGuide(player)
			send(player)
		end
	end)
	ServerSignals.DepthReached:Connect(function(player)
		advanceFrom(player, "Descend")
	end)
	ServerSignals.ItemObtained:Connect(function(player, _item, context)
		if context.source == "Catch" then
			advanceFrom(player, "Catch")
		elseif context.source == "Salvage" then
			advanceFrom(player, "Salvage")
		end
	end)
	ServerSignals.DiveEnded:Connect(function(player, reason)
		local data = DataService.get(player)
		if not data then
			return
		end
		local step = currentStep(data)
		if step == "Surface" then
			if reason == "Blackout" then
				Remotes.notify(player, "Blackouts cost you half your cargo! Next time, surface before oxygen or hull run out.", "warn", "💀")
			end
			enter(player, data.Tutorial.Step + 1)
		elseif step == "Descend" or step == "Catch" or step == "Salvage" then
			-- surfaced early: they'll relaunch to continue this step
			clearGuide(player)
			send(player)
		end
	end)
	ServerSignals.ItemsSold:Connect(function(player)
		local data = DataService.get(player)
		if data and currentStep(data) == "Sell" then
			DataService.addCoins(player, Game.Economy.TutorialBonusCoins, "Tutorial")
			Remotes.notify(player, string.format("Here's %d bonus coins to get you started!", Game.Economy.TutorialBonusCoins), "good", "💰")
			advanceFrom(player, "Sell")
		end
	end)
	ServerSignals.UpgradeBought:Connect(function(player)
		advanceFrom(player, "Upgrade")
	end)
	ServerSignals.PlayerLeaving:Connect(clearGuide)
	Remotes.on("Tutorial", 1, 2, function(player, action)
		if action == "Skip" then
			finish(player, true)
		elseif action == "Sync" then
			send(player)
		end
	end)
	-- respawn the guided fish / treasure if it swam off or was taken
	task.spawn(function()
		while true do
			task.wait(Tutorial.respawnCheckSeconds)
			for _, state in PlayerState.all() do
				local player = state.player
				if state.ready and state.dive and TutorialService.isActive(player) and ensureGuide(player) then
					send(player)
				end
			end
		end
	end)
end

return TutorialService

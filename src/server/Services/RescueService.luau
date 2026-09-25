--!strict
-- Keeps walkers out of trouble: anyone who isn't diving and has been swimming for a while, is
-- stuck under the dock, or has somehow left the map is "washed ashore" back onto the beach
-- (with a short fade on their screen). Subs are never touched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local PlayerState = require(script.Parent.PlayerState)
local Remotes = require(script.Parent.Remotes)
local WorldService = require(script.Parent.WorldService)

local RescueService = {}

local SWIM_SECONDS = 7 -- swimming this long (and not heading for shore) triggers a rescue
local CHECK_INTERVAL = 0.5

local swimTime: { [Player]: number } = {}
local rescuing: { [Player]: boolean } = {}

local function beachCFrame(): CFrame
	local points = WorldService.dock.spawnPoints
	local base = if #points > 0 then points[math.random(1, #points)] else Zones.world.plazaCenter + Vector3.new(0, 4, 0)
	local position = base + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	return CFrame.lookAt(position, Vector3.new(Zones.world.pierEnd.X, position.Y, Zones.world.pierEnd.Z))
end

function RescueService.rescue(player: Player, reason: string)
	if rescuing[player] then
		return
	end
	rescuing[player] = true
	Remotes.fire(player, "Effect", { kind = "WashedAshore", reason = reason })
	task.delay(0.45, function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local state = PlayerState.get(player)
		if character and root and root:IsA("BasePart") and not (state and state.dive) then
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(beachCFrame())
		end
		swimTime[player] = 0
		task.delay(1, function()
			rescuing[player] = nil
		end)
	end)
end

local function check()
	local world = Zones.world
	for _, player in Players:GetPlayers() do
		local state = PlayerState.get(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if state and not state.dive and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local position = root.Position
			local outside = math.abs(position.X) > world.boundaryHalfX + 20
				or position.Z < world.boundaryMinZ - 20
				or position.Z > world.boundaryMaxZ + 20
				or position.Y < world.characterBarrierY - 12
			if outside then
				RescueService.rescue(player, "lost")
			elseif humanoid:GetState() == Enum.HumanoidStateType.Swimming or position.Y < -1 then
				swimTime[player] = (swimTime[player] or 0) + CHECK_INTERVAL
				if (swimTime[player] or 0) >= SWIM_SECONDS then
					RescueService.rescue(player, "swim")
				end
			else
				swimTime[player] = 0
			end
		else
			swimTime[player] = 0
		end
	end
end

function RescueService.Start()
	Players.PlayerRemoving:Connect(function(player)
		swimTime[player] = nil
		rescuing[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(check :: (...any) -> ...any)
			if not ok then
				warn("[DeepHaul] rescue check: " .. tostring(err))
			end
		end
	end)
end

return RescueService

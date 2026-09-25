--!strict
-- Drives the local player's submarine and camera during a dive.
-- Movement is weighty: velocity eases toward the input target (acceleration), coasts when you
-- let go (drift), banks into turns, pitches when climbing, and bobs gently when idle.
-- The client owns the sub's physics; the server validates what it sees.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)

local SubController = {}

SubController.sub = nil :: Model?
SubController.root = nil :: BasePart?
SubController.velocity = Vector3.zero
SubController.speed = 0
SubController.timeScale = 1
SubController.frozen = false
SubController.damping = 1 -- multiplier on top speed (salvage slows you)
SubController.boosting = false -- thrusters firing this frame
SubController.Started = Signal.new() :: Signal.Signal<Model>
SubController.Ended = Signal.new() :: Signal.Signal<any>

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local drive: LinearVelocity? = nil
local steer: AlignOrientation? = nil
local propWeld: Weld? = nil
local propBase = CFrame.identity
local bubbles: ParticleEmitter? = nil
local knock = Vector3.zero
local yaw = 0
local lastYaw = 0
local roll = 0
local camYaw = 0
local camPitch = -12
local camPosition: Vector3? = nil
local propAngle = 0
local elapsed = 0
local shakeMagnitude = 0
local shakeUntil = 0
local emergencySent = false
local launchUntil = 0 -- the crane drop at the start of a dive runs until this time
local lastY = 0

-- A splash where the sub breaks the surface: a burst of spray and an expanding foam ring.
local function splash(position: Vector3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position.X, 0.3, position.Z)
	anchor.Parent = workspace
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Size = NumberSequence.new(2.5, 6)
	spray.Lifetime = NumberRange.new(0.6, 1.2)
	spray.Speed = NumberRange.new(18, 34)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Acceleration = Vector3.new(0, -45, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Enabled = false
	spray.Parent = anchor
	spray:Emit(if big then 45 else 25)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(240, 252, 255)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.3, 6, 6)
	ring.CFrame = CFrame.new(position.X, 0.1, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Size = Vector3.new(0.3, 30, 30), Transparency = 1 }):Play()
	task.delay(1.6, function()
		anchor:Destroy()
		ring:Destroy()
	end)
end
local connections: { RBXScriptConnection } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function lerpAngle(a: number, b: number, t: number): number
	local diff = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + diff * t
end

function SubController.shake(magnitude: number, duration: number)
	local data = ClientState.data
	if data and data.Settings and data.Settings.CameraShake == false then
		return
	end
	shakeMagnitude = math.max(shakeMagnitude, magnitude)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

function SubController.applyImpulse(impulse: Vector3)
	knock += impulse
end

function SubController.isDiving(): boolean
	return SubController.root ~= nil
end

local function shakeOffset(): CFrame
	local now = os.clock()
	if now >= shakeUntil then
		shakeMagnitude = 0
		return CFrame.identity
	end
	local remaining = (shakeUntil - now)
	local m = shakeMagnitude * math.clamp(remaining * 2, 0, 1)
	local t = now * 38
	return CFrame.new(math.noise(t, 0.3) * m, math.noise(0.7, t) * m, 0) * CFrame.Angles(0, 0, math.noise(t, t) * m * 0.02)
end

local function stepMovement(dt: number)
	local root = SubController.root
	if not root or not root.Parent or not drive or not steer then
		return
	end
	elapsed += dt
	local stats = ClientState.stats()
	local maxSpeed = stats.speed * SubController.damping
	SubController.boosting = InputController.boosting and not InputController.silent and not SubController.frozen
	if SubController.boosting then
		maxSpeed *= Game.Dive.BoostSpeedMultiplier
	end
	local move = InputController.moveVector()
	local look = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
	local wish = look.LookVector * -move.Z + look.RightVector * move.X
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	local target = wish * maxSpeed + Vector3.yAxis * InputController.vertical() * maxSpeed * Game.Movement.VerticalFactor
	if InputController.silent and target.Magnitude > Game.Dive.SilentRunningSpeed then
		target = target.Unit * Game.Dive.SilentRunningSpeed
	end
	if SubController.frozen then
		target = Vector3.zero
	end
	local rate = if target.Magnitude > 0.5 then Game.Movement.Acceleration else Game.Movement.Drag
	if SubController.frozen then
		rate = 6
	end
	-- launch: the crane lets go and the sub drops nose-level into the water
	local y = root.Position.Y
	if os.clock() < launchUntil and y > Game.Dive.SurfaceY - 8 then
		target = Vector3.new(0, -Game.Dive.LaunchDropSpeed, 0) + look.LookVector * Vector3.new(1, 0, 1) * 6
		rate = 10
	end
	if (lastY > 0) ~= (y > 0) then
		splash(root.Position, lastY > 0)
		SubController.shake(if lastY > 0 then 0.7 else 0.3, 0.6)
	end
	lastY = y
	local velocity = SubController.velocity:Lerp(target, 1 - math.exp(-rate * dt))
	SubController.velocity = velocity
	SubController.speed = velocity.Magnitude
	knock = knock:Lerp(Vector3.zero, 1 - math.exp(-2.5 * dt))

	local speedFraction = math.clamp(SubController.speed / math.max(stats.speed, 1), 0, 1)
	local bob = math.sin(elapsed * Game.Movement.BobFrequency * math.pi * 2) * Game.Movement.BobAmplitude * (1 - speedFraction)
	drive.VectorVelocity = (velocity + knock) * SubController.timeScale + Vector3.new(0, bob, 0)

	-- orientation: face travel direction, else ease toward where the camera looks
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local desiredYaw = if flat.Magnitude > 3 then math.atan2(-flat.X, -flat.Z) else math.rad(camYaw)
	local turnRate = if flat.Magnitude > 3 then Game.Movement.TurnResponsiveness else 1.2
	yaw = lerpAngle(yaw, desiredYaw, 1 - math.exp(-turnRate * dt))
	local yawRate = ((yaw - lastYaw + math.pi) % (math.pi * 2) - math.pi) / math.max(dt, 1e-3)
	lastYaw = yaw
	local targetRoll = math.clamp(yawRate * 0.35, -1, 1) * math.rad(Game.Movement.BankAngle)
	roll += (targetRoll - roll) * (1 - math.exp(-4 * dt))
	local pitch = math.clamp(velocity.Y / math.max(stats.speed, 1), -1, 1) * math.rad(Game.Movement.PitchAngle)
	pitch += math.sin(elapsed * 0.7) * 0.02 * (1 - speedFraction)
	steer.CFrame = CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)

	-- propeller and bubbles
	propAngle += (2 + SubController.speed * 0.9) * dt
	if propWeld then
		propWeld.C0 = propBase * CFrame.Angles(propAngle, 0, 0)
	end
	if bubbles then
		bubbles.Rate = (4 + SubController.speed * 1.2) * (if SubController.boosting then 2.2 else 1)
	end

	-- emergency surface hold
	if InputController.emergencyProgress() >= 1 and not emergencySent then
		emergencySent = true
		InputController.endEmergency()
		Net.event("EmergencySurface"):FireServer()
	end
end

local function stepCamera(dt: number)
	local root = SubController.root
	if not root or not root.Parent then
		return
	end
	camera = workspace.CurrentCamera
	-- the default camera scripts can reset mouse behaviour; re-assert our lock every frame
	InputController.updateCursor()
	local delta = InputController.consumeLook(dt)
	camYaw -= delta.X
	camPitch = math.clamp(camPitch - delta.Y, Game.Camera.MinPitch, Game.Camera.MaxPitch)
	local rotation = CFrame.fromEulerAnglesYXZ(math.rad(camPitch), math.rad(camYaw), 0)
	local focus = root.Position + Vector3.new(0, 3, 0)
	local desired = focus - rotation.LookVector * Game.Camera.Distance + Vector3.new(0, Game.Camera.Height * 0.3, 0)
	local filter: { Instance } = {}
	local sub = SubController.sub
	if sub then
		table.insert(filter, sub)
	end
	if player.Character then
		table.insert(filter, player.Character)
	end
	local subs = workspace:FindFirstChild("Subs")
	if subs then
		table.insert(filter, subs)
	end
	local loot = workspace:FindFirstChild("ClientLoot")
	if loot then
		table.insert(filter, loot)
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(focus, desired - focus, rayParams)
	if hit then
		desired = hit.Position + hit.Normal * 1.5
	end
	if not camPosition then
		camPosition = desired
	end
	local current = camPosition :: Vector3
	camPosition = current:Lerp(desired, 1 - math.exp(-Game.Camera.Smoothing * dt))
	camera.CFrame = CFrame.lookAt(camPosition :: Vector3, focus + rotation.LookVector * 12) * shakeOffset()
	local stats = ClientState.stats()
	local speedFraction = math.clamp(SubController.speed / math.max(stats.speed, 1), 0, 1)
	local boostFOV = if SubController.boosting then 8 else 0
	camera.FieldOfView = Game.Camera.FOV + Game.Camera.SpeedFOV * speedFraction + boostFOV
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	RunService:UnbindFromRenderStep("DeepHaulSubCamera")
	SubController.sub = nil
	SubController.root = nil
	drive, steer, propWeld, bubbles = nil, nil, nil, nil
	SubController.velocity = Vector3.zero
	SubController.frozen = false
	SubController.damping = 1
	knock = Vector3.zero
	camPosition = nil
	emergencySent = false
	InputController.setDiving(false)
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = Game.Camera.FOV
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function begin(subName: string)
	local folder = workspace:WaitForChild("Subs", 10)
	if not folder then
		return
	end
	local sub = folder:WaitForChild(subName, 10)
	if not sub or not sub:IsA("Model") then
		return
	end
	local root = sub:WaitForChild("Root", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	local driveInst = root:WaitForChild("Drive", 5)
	local steerInst = root:WaitForChild("Steer", 5)
	if not driveInst or not driveInst:IsA("LinearVelocity") or not steerInst or not steerInst:IsA("AlignOrientation") then
		return
	end
	SubController.sub = sub
	SubController.root = root
	drive = driveInst
	steer = steerInst
	local hub = sub:FindFirstChild("PropHub")
	local weld = hub and hub:FindFirstChild("PropWeld")
	if weld and weld:IsA("Weld") then
		propWeld = weld
		propBase = weld.C0
	end
	local bubbleAttachment = root:FindFirstChild("Bubbles")
	local emitter = bubbleAttachment and bubbleAttachment:FindFirstChild("BubbleTrail")
	if emitter and emitter:IsA("ParticleEmitter") then
		bubbles = emitter
	end
	local _, rootYaw = root.CFrame:ToEulerAnglesYXZ()
	yaw = rootYaw
	lastYaw = rootYaw
	camYaw = math.deg(rootYaw)
	camPitch = -8
	launchUntil = os.clock() + 2.5
	lastY = root.Position.Y
	SubController.velocity = Vector3.zero
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	InputController.setDiving(true)
	table.insert(connections, RunService.PreSimulation:Connect(stepMovement))
	RunService:BindToRenderStep("DeepHaulSubCamera", Enum.RenderPriority.Camera.Value + 1, stepCamera)
	SubController.Started:Fire(sub)
end

function SubController.Init()
	Net.event("DiveEvent").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.type == "Started" then
			task.spawn(begin, payload.name)
		elseif payload.type == "Ended" then
			cleanup()
			SubController.Ended:Fire(payload)
		elseif payload.type == "Snap" then
			SubController.velocity = Vector3.zero
			knock = Vector3.zero
		elseif payload.type == "Damage" then
			if typeof(payload.impulse) == "Vector3" then
				SubController.applyImpulse(payload.impulse)
			end
			SubController.shake(0.6, 0.35)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		if not SubController.root then
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				workspace.CurrentCamera.CameraSubject = humanoid :: Humanoid
			end
		end
	end)
end

return SubController

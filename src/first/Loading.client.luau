--!strict
-- Loading screen (ReplicatedFirst, so it shows before anything else loads). Self-contained: it
-- can't rely on shared modules. Rising bubbles, the DEEP HAUL title and rotating tips; fades out
-- once the game has loaded and the client reports ready (player attribute DH_ClientReady), or
-- after a timeout. A Skip button appears if it takes a while. Sets DH_LoadingDone when gone.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TIMEOUT = 90
local TIPS = {
	"Rarer fish live deeper. Upgrade your hull to survive the pressure.",
	"Surface before your oxygen runs out, or you'll lose half your cargo!",
	"PERFECT catches are worth more. Stop the marker dead centre.",
	"Ping your sonar to reveal loot nearby and stun predators.",
	"Catch or salvage again within 15 seconds to build a streak worth up to +50%.",
	"Events start every 45 minutes. Watch the timer at the top of the screen.",
	"Complete collection sets for permanent bonuses.",
	"Fish that glow can be seen from far away in the dark.",
	"Log in every day: day 7 of the streak is the jackpot.",
}

local gui = Instance.new("ScreenGui")
gui.Name = "DeepHaulLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BorderSizePixel = 0
background.BackgroundColor3 = Color3.fromRGB(4, 22, 40)
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(20, 110, 160), Color3.fromRGB(2, 8, 18))
gradient.Parent = background

local bubbles = Instance.new("Frame")
bubbles.BackgroundTransparency = 1
bubbles.Size = UDim2.fromScale(1, 1)
bubbles.ClipsDescendants = true
bubbles.Parent = background

local function label(text: string, size: number, position: UDim2, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = position
	l.Size = UDim2.new(0.9, 0, 0, size + 10)
	l.Font = font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.Parent = background
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 20, 40)
	stroke.Parent = l
	return l
end

local title = label("DEEP HAUL", 84, UDim2.fromScale(0.5, 0.38), Enum.Font.FredokaOne, Color3.fromRGB(120, 230, 255))
local subtitle = label("How deep will you go?", 26, UDim2.fromScale(0.5, 0.48), Enum.Font.GothamBold, Color3.fromRGB(200, 235, 250))
local status = label("Filling the ocean…", 20, UDim2.fromScale(0.5, 0.66), Enum.Font.GothamBold, Color3.fromRGB(170, 210, 230))
local tip = label("", 18, UDim2.fromScale(0.5, 0.8), Enum.Font.Gotham, Color3.fromRGB(150, 190, 215))

local skip = Instance.new("TextButton")
skip.AnchorPoint = Vector2.new(1, 1)
skip.Position = UDim2.new(1, -24, 1, -24)
skip.Size = UDim2.fromOffset(120, 40)
skip.BackgroundColor3 = Color3.fromRGB(30, 60, 90)
skip.Font = Enum.Font.GothamBold
skip.TextSize = 18
skip.TextColor3 = Color3.new(1, 1, 1)
skip.Text = "Skip"
skip.Visible = false
skip.Parent = background
local corner = Instance.new("UICorner")
corner.Parent = skip

gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- rising bubbles
local running = true
task.spawn(function()
	local random = Random.new()
	while running do
		local size = random:NextInteger(6, 26)
		local bubble = Instance.new("Frame")
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.Size = UDim2.fromOffset(size, size)
		bubble.Position = UDim2.new(random:NextNumber(0.02, 0.98), 0, 1.05, 0)
		bubble.BackgroundColor3 = Color3.fromRGB(190, 240, 255)
		bubble.BackgroundTransparency = random:NextNumber(0.55, 0.8)
		bubble.BorderSizePixel = 0
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = bubble
		bubble.Parent = bubbles
		local duration = random:NextNumber(3, 6)
		TweenService:Create(bubble, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
			Position = UDim2.new(bubble.Position.X.Scale + random:NextNumber(-0.05, 0.05), 0, -0.05, 0),
		}):Play()
		task.delay(duration, function()
			bubble:Destroy()
		end)
		task.wait(0.12)
	end
end)

-- title bob and rotating tips
local tipIndex = math.random(1, #TIPS)
tip.Text = "💡 " .. TIPS[tipIndex]
local started = os.clock()
local connection = RunService.RenderStepped:Connect(function()
	local t = os.clock() - started
	title.Position = UDim2.new(0.5, 0, 0.38, math.sin(t * 1.6) * 6)
	gradient.Offset = Vector2.new(0, math.sin(t * 0.4) * 0.05)
end)
task.spawn(function()
	while running do
		task.wait(4)
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = "💡 " .. TIPS[tipIndex]
	end
end)

local finished = false
local function finish()
	if finished then
		return
	end
	finished = true
	status.Text = "Dive in!"
	local fade = TweenInfo.new(0.8)
	TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
	for _, child in background:GetDescendants() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, fade, { TextTransparency = 1 }):Play()
		elseif child:IsA("UIStroke") then
			TweenService:Create(child, fade, { Transparency = 1 }):Play()
		elseif child:IsA("Frame") or child:IsA("TextButton") then
			TweenService:Create(child, fade, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(0.85, function()
		running = false
		connection:Disconnect()
		gui:Destroy()
		player:SetAttribute("DH_LoadingDone", true)
	end)
end

skip.Activated:Connect(finish)
task.delay(10, function()
	if not finished then
		skip.Visible = true
	end
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local deadline = os.clock() + TIMEOUT
while not finished and ReplicatedStorage:GetAttribute("WorldReady") ~= true and os.clock() < deadline do
	status.Text = "Filling the ocean…"
	task.wait(0.2)
end
status.Text = "Loading your save…"
while not finished and player:GetAttribute("DH_ClientReady") ~= true and os.clock() < deadline do
	task.wait(0.1)
end
subtitle.Text = "How deep will you go?"
task.wait(0.4)
finish()

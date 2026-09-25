--!strict
-- The catch timing bar. The server sends the green zone, speed and start time; the marker is
-- drawn with the shared formula against the synced server clock, and a tap sends the server
-- the exact moment you pressed. Rarer fish: smaller zone, faster marker, always ≤ 3 seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local Fish = require(Shared.Config.Fish)
local Game = require(Shared.Config.Game)
local MinigameMath = require(Shared.Modules.MinigameMath)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local MobileControls = require(script.Parent.MobileControls)

local MinigameController = {}

MinigameController.active = false

type Session = {
	id: number,
	startsAt: number,
	duration: number,
	zoneStart: number,
	zoneWidth: number,
	sweeps: number,
	tapped: boolean,
	tier: number,
}

local gui: ScreenGui
local window: Frame
local title: TextLabel
local hint: TextLabel
local bar: Frame
local zone: Frame
local perfectZone: Frame
local markerFrame: Frame
local timer: Frame
local result: TextLabel
local session: Session? = nil
local hideToken = 0

local function hide(delay: number)
	hideToken += 1
	local token = hideToken
	task.delay(delay, function()
		if token ~= hideToken then
			return
		end
		UIKit.tween(window, { Position = UDim2.new(0.5, 0, 0.78, 40) }, 0.2)
		task.delay(0.2, function()
			if token == hideToken then
				gui.Enabled = false
			end
		end)
	end)
end

local function finish()
	MinigameController.active = false
	session = nil
	SubController.frozen = false
end

local function tap()
	local current = session
	if not current or current.tapped then
		return
	end
	current.tapped = true
	local now = workspace:GetServerTimeNow()
	Net.event("CatchTap"):FireServer(current.id, now)
	local marker = MinigameMath.marker(now - current.startsAt, current.sweeps)
	local hit = now >= current.startsAt and MinigameMath.inZone(marker, current.zoneStart, current.zoneWidth)
	markerFrame.BackgroundColor3 = if hit then Theme.Good else Theme.Bad
	UIKit.tween(markerFrame, { Size = UDim2.new(0, 10, 1, 18) }, 0.08)
end
MinigameController.tap = tap

local function show(payload: any)
	local def = Fish.byId[payload.fishId]
	local rarity = Rarities.list[payload.tier] or Rarities.list[1]
	session = {
		id = payload.id,
		startsAt = payload.startsAt,
		duration = payload.duration,
		zoneStart = payload.zoneStart,
		zoneWidth = payload.zoneWidth,
		sweeps = payload.sweeps,
		tapped = false,
		tier = rarity.index,
	}
	MinigameController.active = true
	SubController.frozen = true
	hideToken += 1
	local name = if rarity.hidden then "???" else (if def then def.name else "Fish")
	title.Text = string.format('<font color="#%s">%s</font>  %s', rarity.color:ToHex(), rarity.name:upper(), name)
	hint.Text = if InputController.mode == "Touch" then "Tap ACTION in the green!" elseif InputController.mode == "Gamepad" then "Press A in the green!" else "Click in the green!"
	zone.Position = UDim2.fromScale(payload.zoneStart, 0)
	zone.Size = UDim2.fromScale(payload.zoneWidth, 1)
	local perfectWidth = payload.zoneWidth * Game.Catch.PerfectFraction
	perfectZone.Position = UDim2.fromScale(payload.zoneStart + (payload.zoneWidth - perfectWidth) / 2, 0)
	perfectZone.Size = UDim2.fromScale(perfectWidth, 1)
	markerFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	markerFrame.Size = UDim2.new(0, 6, 1, 12)
	markerFrame.Position = UDim2.fromScale(0, 0.5)
	result.Text = ""
	timer.Size = UDim2.fromScale(1, 1)
	gui.Enabled = true
	window.Position = UDim2.new(0.5, 0, 0.78, 40)
	UIKit.tween(window, { Position = UDim2.fromScale(0.5, 0.78) }, 0.2, Enum.EasingStyle.Back)
	MobileControls.setAction("TAP!", true, Theme.Good)
	AudioController.play("MinigameStart", 1 + (rarity.index - 1) * 0.04)
	-- safety net if the result never arrives
	local id = payload.id
	task.delay(payload.duration + Game.Catch.LeadIn + 2, function()
		if session and session.id == id then
			finish()
			hide(0)
		end
	end)
end

local function onResult(payload: any)
	if not session or payload.id ~= session.id then
		return
	end
	if payload.ok then
		result.Text = if payload.perfect then "✨ PERFECT! ✨" else "CAUGHT!"
		result.TextColor3 = if payload.perfect then Theme.Coin else Theme.Good
		AudioController.play(if payload.perfect then "CatchPerfect" else "CatchSuccess")
	else
		result.Text = if payload.gone then "It vanished..." else "IT GOT AWAY!"
		result.TextColor3 = Theme.Bad
		AudioController.play("CatchFail")
		SubController.shake(0.3, 0.25)
	end
	local scale = result:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.5
		UIKit.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	end
	finish()
	hide(0.7)
end

local function step()
	local current = session
	if not current then
		return
	end
	local now = workspace:GetServerTimeNow()
	local elapsed = now - current.startsAt
	local marker = MinigameMath.marker(elapsed, current.sweeps)
	if not current.tapped then
		markerFrame.Position = UDim2.fromScale(marker, 0.5)
	end
	local remaining = math.clamp(1 - elapsed / current.duration, 0, 1)
	timer.Size = UDim2.fromScale(if elapsed < 0 then 1 else remaining, 1)
end

function MinigameController.Init()
	gui = UIKit.screen("DeepHaulMinigame", 25)
	gui.Enabled = false
	window = UIKit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.fromOffset(560, 130),
		Parent = gui,
	})
	UIKit.scaled(window)
	title = UIKit.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 32),
		Font = Theme.FontDisplay,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = window,
	})
	UIKit.textStroke(2).Parent = title
	bar = UIKit.frame({
		BackgroundColor3 = Theme.PanelDark,
		Position = UDim2.fromOffset(20, 40),
		Size = UDim2.new(1, -40, 0, 34),
		Parent = window,
	})
	UIKit.corner(UDim.new(0, 10)).Parent = bar
	UIKit.stroke(Theme.Stroke, 2, 0).Parent = bar
	zone = UIKit.frame({ BackgroundColor3 = Theme.Good, BackgroundTransparency = 0.15, Size = UDim2.fromScale(0.2, 1), Parent = bar })
	UIKit.corner(UDim.new(0, 8)).Parent = zone
	perfectZone = UIKit.frame({ BackgroundColor3 = Color3.fromRGB(200, 255, 200), BackgroundTransparency = 0.1, Size = UDim2.fromScale(0.05, 1), Parent = bar })
	markerFrame = UIKit.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 6, 1, 12),
		ZIndex = 3,
		Parent = bar,
	})
	UIKit.corner(UDim.new(1, 0)).Parent = markerFrame
	UIKit.stroke(Theme.Background, 2, 0).Parent = markerFrame
	local timerTrack = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, Position = UDim2.fromOffset(20, 80), Size = UDim2.new(1, -40, 0, 6), Parent = window })
	UIKit.corner(UDim.new(1, 0)).Parent = timerTrack
	timer = UIKit.frame({ BackgroundColor3 = Theme.Accent, Size = UDim2.fromScale(1, 1), Parent = timerTrack })
	UIKit.corner(UDim.new(1, 0)).Parent = timer
	hint = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.TextMuted, Parent = window })
	UIKit.textStroke(1.5).Parent = hint
	result = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(500, 50),
		Font = Theme.FontDisplay,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = window,
	})
	UIKit.new("UIScale", { Parent = result })
	UIKit.textStroke(3).Parent = result
	-- tapping the bar itself also counts on touch screens
	local tapArea = UIKit.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), Parent = window }) :: TextButton
	tapArea.Activated:Connect(tap)
end

function MinigameController.Start()
	Net.event("Minigame").OnClientEvent:Connect(show)
	Net.event("CatchResult").OnClientEvent:Connect(onResult)
	InputController.Action:Connect(function(down)
		if down and MinigameController.active then
			tap()
		end
	end)
	SubController.Ended:Connect(function()
		if session then
			finish()
			hide(0)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return MinigameController

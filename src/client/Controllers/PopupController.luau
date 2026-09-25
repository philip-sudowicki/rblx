--!strict
-- Modal popups, queued so they never stack: "Welcome back" offline aquarium earnings and any
-- other one-off announcements (daily reward ready, new skin, etc.). Popups wait until the
-- player has loaded in and isn't mid-dive.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)

export type Popup = {
	icon: string,
	title: string,
	body: string,
	highlight: string?, -- big line in the middle (e.g. the coin amount)
	highlightColor: Color3?,
	button: string?,
	onClose: (() -> ())?,
}

local PopupController = {}

local gui: ScreenGui
local queue: { Popup } = {}
local showing = false
-- Set by the loading screen / tutorial to hold popups back while they're on screen.
PopupController.holds = 0

local showNext: () -> ()

local function canShow(): boolean
	return ClientState.ready
		and (ClientState.player:GetAttribute("DH_LoadingDone") == true or os.clock() > 45)
		and not SubController.isDiving()
		and PopupController.holds <= 0
end

local function present(popup: Popup)
	showing = true
	local dim = UIKit.frame({ BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	UIKit.tween(dim, { BackgroundTransparency = 0.45 }, 0.25)
	local box = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 300), Parent = dim })
	local scale = UIKit.scaled(box)
	local base = scale.Scale
	scale.Scale = base * 0.6
	UIKit.tween(scale, { Scale = base }, 0.35, Enum.EasingStyle.Back)
	UIKit.label({ Text = popup.icon, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 56), TextSize = 50, TextXAlignment = Enum.TextXAlignment.Center, Parent = box })
	local title = UIKit.label({ Text = popup.title, Position = UDim2.fromOffset(20, 70), Size = UDim2.new(1, -40, 0, 36), Font = Theme.FontDisplay, TextSize = 30, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Center, Parent = box })
	UIKit.textStroke(2).Parent = title
	local y = 110
	if popup.highlight then
		local highlight = UIKit.label({ Text = popup.highlight, Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 44), Font = Theme.FontDisplay, TextSize = 38, TextColor3 = popup.highlightColor or Theme.Coin, TextXAlignment = Enum.TextXAlignment.Center, Parent = box })
		UIKit.textStroke(2.5).Parent = highlight
		y += 48
	end
	UIKit.label({ Text = popup.body, Position = UDim2.fromOffset(24, y), Size = UDim2.new(1, -48, 0, 230 - y), TextSize = 16, TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Parent = box })

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		ContextActionService:UnbindAction("DH_PopupClose")
		InputController.setMenuOpen(false)
		GuiService.SelectedObject = nil
		UIKit.tween(scale, { Scale = base * 0.8 }, 0.15)
		UIKit.tween(dim, { BackgroundTransparency = 1 }, 0.18)
		task.delay(0.18, function()
			dim:Destroy()
			showing = false
			if popup.onClose then
				popup.onClose()
			end
			showNext()
		end)
	end
	local button = UIKit.button({
		Text = popup.button or "OK",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, 50),
		Font = Theme.FontDisplay,
		TextSize = 24,
		Parent = box,
	}, close, Theme.Good)
	InputController.setMenuOpen(true)
	ContextActionService:BindActionAtPriority("DH_PopupClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 80, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonA, Enum.KeyCode.Return)
	if InputController.mode == "Gamepad" then
		GuiService.SelectedObject = button
	end
	AudioController.play("Notify")
end

showNext = function()
	if showing or #queue == 0 then
		return
	end
	if not canShow() then
		return
	end
	present(table.remove(queue, 1) :: Popup)
end

function PopupController.show(popup: Popup)
	table.insert(queue, popup)
	showNext()
end

-- Re-check the queue (called when a hold is released or a dive ends).
function PopupController.poke()
	showNext()
end

local function welcomeBack(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local coins = if typeof(payload.coins) == "number" then payload.coins else 0
	local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 0
	-- short server hops aren't worth a popup
	if coins <= 0 and seconds < 1800 then
		return
	end
	local name = ClientState.player.DisplayName
	if coins > 0 then
		local body = string.format("Your aquarium earned coins while you were away for %s.", Format.duration(seconds))
		if payload.capped then
			body ..= string.format("\nOffline earnings stop after %d hours - come back sooner, or display rarer fish to earn more.", Game.Aquarium.OfflineCapHours)
		end
		PopupController.show({
			icon = "🐠",
			title = "Welcome back, " .. name .. "!",
			highlight = "+" .. Format.commas(coins) .. " 🪙",
			body = body,
			button = "Nice!",
			onClose = function()
				EffectsController.coinBurst(coins)
			end,
		})
	else
		PopupController.show({
			icon = "🐠",
			title = "Welcome back, " .. name .. "!",
			body = string.format("Tip: fish and treasure on display in your aquarium earn coins, even while you're offline (up to %d hours).", Game.Aquarium.OfflineCapHours),
			button = "Let's dive",
		})
	end
end

function PopupController.Init()
	gui = UIKit.screen("DeepHaulPopups", 40)
end

function PopupController.Start()
	Net.event("WelcomeBack").OnClientEvent:Connect(welcomeBack)
	ClientState.Ready:Connect(function()
		task.delay(1, showNext)
	end)
	ClientState.player:GetAttributeChangedSignal("DH_LoadingDone"):Connect(function()
		task.delay(0.5, showNext)
	end)
	SubController.Ended:Connect(function()
		task.delay(2.5, showNext)
	end)
end

return PopupController

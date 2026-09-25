--!strict
-- The catch reveal: a card pops up with the model, rarity colour, name, mutation, weight or
-- condition, value and a NEW! badge, with a sound that escalates by rarity. Mythic and above
-- get a screen flash, camera shake and a slow-motion reveal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Mutations = require(Shared.Config.Mutations)
local Conditions = require(Shared.Config.Conditions)
local Events = require(Shared.Config.Events)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Types = require(Shared.Modules.Types)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ItemViewport = require(script.Parent.Parent.UI.ItemViewport)
local ClientState = require(script.Parent.ClientState)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local EffectsController = require(script.Parent.EffectsController)

local RevealController = {}

RevealController.Revealed = Signal.new() :: Signal.Signal<Types.Item>

local gui: ScreenGui
local card: Frame
local cardScale: UIScale
local header: TextLabel
local headerFrame: Frame
local headerGradient: UIGradient? = nil
local newBadge: TextLabel
local nameLabel: TextLabel
local tagsLabel: TextLabel
local statLabel: TextLabel
local valueLabel: TextLabel
local eventLabel: TextLabel
local viewport: ItemViewport.ItemView
local queue: { any } = {}
local showing = false

local function nextReveal()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local payload = table.remove(queue, 1)
	local item: Types.Item = payload.item
	local rarity = Rarities.list[item.r] or Rarities.list[1]
	local isFish = item.k == "F"
	local def: any = if isFish then Fish.byId[item.i] else Treasure.byId[item.i]
	if not def then
		showing = false
		nextReveal()
		return
	end
	header.Text = rarity.name:upper()
	headerFrame.BackgroundColor3 = rarity.color
	if headerGradient then
		headerGradient:Destroy()
		headerGradient = nil
	end
	headerGradient = UIKit.rarityGradient(headerFrame, rarity.index)
	header.TextColor3 = if rarity.index == 7 then rarity.color else Theme.TextDark
	headerFrame.BackgroundColor3 = if rarity.index == 7 then Color3.fromRGB(6, 10, 18) else rarity.color
	newBadge.Visible = payload.isNew == true
	nameLabel.Text = def.name
	nameLabel.TextColor3 = rarity.color
	local tags = {}
	if item.x then
		table.insert(tags, '<font color="#FF9F43">COLOSSAL</font>')
	end
	if item.m and Mutations.byId[item.m] then
		local mutation = Mutations.byId[item.m]
		table.insert(tags, string.format('<font color="#%s">%s ×%d</font>', mutation.color:ToHex(), mutation.name:upper(), mutation.multiplier))
	end
	if item.p then
		table.insert(tags, '<font color="#FFD24A">PERFECT</font>')
	end
	tagsLabel.Text = table.concat(tags, "  ·  ")
	if isFish then
		statLabel.Text = string.format("⚖️ %s", Format.weight(item.w or 0))
	else
		local condition = Conditions.byId[item.c or "Worn"]
		statLabel.Text = string.format('Condition: <font color="#%s"><b>%s</b></font> ×%s', condition.color:ToHex(), condition.name, tostring(condition.multiplier))
	end
	local sellMult = ClientState.stats().sellMult
	valueLabel.Text = string.format("🪙 %s", Format.commas(math.floor(item.v * sellMult + 0.5)))
	local eventDef = item.e and Events.byId[item.e]
	eventLabel.Visible = eventDef ~= nil
	if eventDef then
		eventLabel.Text = string.format("%s %s", eventDef.icon, eventDef.name)
		eventLabel.TextColor3 = eventDef.color
	end
	viewport.set(item.k, item.i, { mutation = item.m, colossal = item.x })

	local epic = rarity.reveal == "epic"
	local big = rarity.reveal == "big"
	AudioController.play(rarity.sound)
	if epic then
		EffectsController.flash(rarity.color, 0.85, 1.2)
		SubController.shake(1.4, 1.2)
		EffectsController.slowMo(0.25, 1.6)
	elseif big then
		EffectsController.flash(rarity.color, 0.35, 0.5)
		SubController.shake(0.4, 0.4)
	end
	card.Position = UDim2.new(1, -24, 0.5, 0)
	card.AnchorPoint = Vector2.new(1, 0.5)
	if epic then
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
	end
	local base = UIKit.scaleFactor()
	cardScale.Scale = 0
	gui.Enabled = true
	UIKit.tween(cardScale, { Scale = base * (if epic then 1.15 else 1) }, if epic then 1.1 else 0.35, if epic then Enum.EasingStyle.Elastic else Enum.EasingStyle.Back)
	local hold = if epic then 4.5 elseif big then 3 else 2.2
	task.delay(hold, function()
		UIKit.tween(cardScale, { Scale = 0 }, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.28, function()
			gui.Enabled = false
			viewport.clear()
			showing = false
			nextReveal()
		end)
	end)
	RevealController.Revealed:Fire(item)
end

function RevealController.Init()
	gui = UIKit.screen("DeepHaulReveal", 28)
	gui.Enabled = false
	card = UIKit.panel({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.fromOffset(330, 420),
		Parent = gui,
	})
	cardScale = UIKit.new("UIScale", { Scale = 1, Parent = card }) :: UIScale
	headerFrame = UIKit.frame({ Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.Accent, Parent = card })
	UIKit.corner().Parent = headerFrame
	header = UIKit.label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontDisplay,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.TextDark,
		Parent = headerFrame,
	})
	newBadge = UIKit.label({
		Text = "NEW!",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -10),
		Size = UDim2.fromOffset(70, 30),
		Font = Theme.FontDisplay,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		Rotation = 12,
		ZIndex = 5,
		Parent = card,
	})
	UIKit.corner(UDim.new(0, 8)).Parent = newBadge
	viewport = ItemViewport.new(card, UDim2.fromOffset(290, 190), UDim2.fromOffset(20, 50))
	nameLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 244), Size = UDim2.new(1, -32, 0, 34), Font = Theme.FontDisplay, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Parent = card })
	UIKit.textStroke(2).Parent = nameLabel
	tagsLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 280), Size = UDim2.new(1, -32, 0, 22), Font = Theme.FontBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	statLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 306), Size = UDim2.new(1, -32, 0, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	valueLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 334), Size = UDim2.new(1, -32, 0, 38), Font = Theme.FontDisplay, TextSize = 32, TextColor3 = Theme.Coin, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	UIKit.textStroke(2).Parent = valueLabel
	eventLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 378), Size = UDim2.new(1, -32, 0, 22), Font = Theme.FontBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, Parent = card })
	local dismiss = UIKit.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = card }) :: TextButton
	dismiss.Activated:Connect(function()
		cardScale.Scale = 0
	end)
end

function RevealController.Start()
	Net.event("Reveal").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.item) == "table" then
			table.insert(queue, payload)
			nextReveal()
		end
	end)
end

return RevealController

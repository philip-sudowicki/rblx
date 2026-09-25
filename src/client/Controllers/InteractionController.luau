--!strict
-- Context-sensitive Action: picks the best fish or treasure in reach, shows a world prompt
-- ("CATCH" / "SALVAGE" / "Requires Claw Tier 3"), sends the intent to the server, and warns
-- you when you're moving fast enough to spook a skittish fish.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Rarities = require(Shared.Config.Rarities)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local EntityRenderer = require(script.Parent.EntityRenderer)
local MinigameController = require(script.Parent.MinigameController)
local SalvageController = require(script.Parent.SalvageController)
local MobileControls = require(script.Parent.MobileControls)
local HUDController = require(script.Parent.HUDController)

local InteractionController = {}

type Target = { kind: string, id: number, allowed: boolean }

InteractionController.target = nil :: Target?

local player = Players.LocalPlayer
local prompt: BillboardGui
local promptTitle: TextLabel
local promptSub: TextLabel
local promptStroke: UIStroke
local spookLabel: TextLabel
local salvaging = false
local accumulator = 0

local function keyHint(): string
	if InputController.mode == "Touch" then
		return "ACTION"
	elseif InputController.mode == "Gamepad" then
		return "A"
	end
	return "Click"
end

local function requiredTier(treasureId: string, tier: number): number
	local def = Treasure.byId[treasureId]
	if def and def.clawTier then
		return def.clawTier
	end
	return Rarities.list[tier].clawTier
end

local function choose(): Target?
	local root = SubController.root
	if not root then
		return nil
	end
	local position = root.Position
	local look = root.CFrame.LookVector
	local now = workspace:GetServerTimeNow()
	local best: Target? = nil
	local bestScore = math.huge
	local catchRange = Game.Catch.Range
	for id, view in EntityRenderer.fish do
		if view.built and not view.record.g and now >= (view.record.w or 0) then
			local offset = view.position - position
			local d = offset.Magnitude
			if d <= catchRange then
				local score = d - look:Dot(offset.Unit) * 6 - view.tier * 0.5
				if score < bestScore then
					best, bestScore = { kind = "Fish", id = id, allowed = true }, score
				end
			end
		end
	end
	local clawTier = ClientState.stats().clawTier
	for id, view in EntityRenderer.treasure do
		if view.built and not view.record.g then
			local offset = view.position - position
			local d = offset.Magnitude
			if d <= Game.Salvage.Range then
				local score = d - look:Dot(offset.Unit) * 6 - 2
				if score < bestScore then
					best, bestScore = { kind = "Treasure", id = id, allowed = clawTier >= requiredTier(view.treasureId, view.tier) }, score
				end
			end
		end
	end
	return best
end

local function refreshPrompt(target: Target?)
	if not target or MinigameController.active or SalvageController.active then
		prompt.Enabled = false
		if not MinigameController.active then
			MobileControls.setAction("ACTION", false)
		end
		return
	end
	local stats = ClientState.stats()
	local cargoFull = ClientState.cargoCount() >= stats.cargo
	if target.kind == "Fish" then
		local view = EntityRenderer.fish[target.id]
		local built = view and view.built
		if not view or not built then
			prompt.Enabled = false
			return
		end
		local rarity = Rarities.list[view.tier]
		local def = Fish.byId[view.fishId]
		prompt.Adornee = built.root
		promptTitle.Text = if cargoFull then "📦 CARGO FULL" else string.format("🎣 CATCH  [%s]", keyHint())
		promptSub.Text = string.format("%s %s", rarity.name, if rarity.hidden then "???" else def.name)
		promptSub.TextColor3 = rarity.color
		promptStroke.Color = rarity.color
		MobileControls.setAction(if cargoFull then "FULL" else "CATCH", not cargoFull, rarity.color)
	else
		local view = EntityRenderer.treasure[target.id]
		local built = view and view.built
		if not view or not built then
			prompt.Enabled = false
			return
		end
		local rarity = Rarities.list[view.tier]
		local def = Treasure.byId[view.treasureId]
		prompt.Adornee = built.root
		if not target.allowed then
			promptTitle.Text = string.format("🔒 Requires Claw Tier %d", requiredTier(view.treasureId, view.tier))
			promptTitle.TextColor3 = Theme.Bad
			MobileControls.setAction(string.format("CLAW T%d", requiredTier(view.treasureId, view.tier)), false)
		else
			promptTitle.Text = if cargoFull then "📦 CARGO FULL" else string.format("🧲 SALVAGE  [Hold %s]", keyHint())
			promptTitle.TextColor3 = Theme.Text
			MobileControls.setAction(if cargoFull then "FULL" else "SALVAGE", not cargoFull, rarity.color)
		end
		promptSub.Text = string.format("%s %s", rarity.name, if rarity.hidden then "???" else def.name)
		promptSub.TextColor3 = rarity.color
		promptStroke.Color = rarity.color
	end
	if target.kind == "Fish" then
		promptTitle.TextColor3 = Theme.Text
	end
	prompt.Enabled = true
end

local function spookCheck()
	local root = SubController.root
	if not root then
		spookLabel.Visible = false
		return
	end
	local speed = SubController.speed
	local warn = false
	for _, view in EntityRenderer.fish do
		local flee = Rarities.list[view.tier].flee
		if flee and not view.record.tu then
			local d = (view.position - root.Position).Magnitude
			if d < flee.detectRadius + 25 and speed > flee.speedThreshold * 0.85 then
				warn = true
				break
			end
		end
	end
	spookLabel.Visible = warn
	if warn then
		local keys = if InputController.mode == "Gamepad" then "L3" elseif InputController.mode == "Touch" then "SLOW" else "Ctrl"
		spookLabel.Text = string.format("⚠ Too fast! Rare fish spook easily - slow down (%s)", keys)
	end
end

local function step(dt: number)
	if not SubController.isDiving() then
		prompt.Enabled = false
		spookLabel.Visible = false
		return
	end
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	local target = choose()
	InteractionController.target = target
	refreshPrompt(target)
	spookCheck()
end

local function onAction(down: boolean)
	if not SubController.isDiving() or MinigameController.active then
		return
	end
	if down then
		local target = InteractionController.target
		if not target then
			return
		end
		if target.kind == "Fish" then
			Net.event("CatchStart"):FireServer(target.id)
		elseif target.allowed then
			salvaging = true
			Net.event("SalvageStart"):FireServer(target.id)
		else
			HUDController.toast("Upgrade your Salvage Claw at the Workshop to lift this.", "warn", "🧲")
		end
	elseif salvaging then
		salvaging = false
		Net.event("SalvageCancel"):FireServer()
	end
end

function InteractionController.Init()
	prompt = Instance.new("BillboardGui")
	prompt.Name = "DeepHaulPrompt"
	prompt.Size = UDim2.fromOffset(240, 58)
	prompt.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	prompt.AlwaysOnTop = true
	prompt.LightInfluence = 0
	prompt.Enabled = false
	prompt.Parent = player:WaitForChild("PlayerGui")
	local frame = UIKit.frame({ BackgroundColor3 = Theme.PanelDark, BackgroundTransparency = 0.15, Size = UDim2.fromScale(1, 1), Parent = prompt })
	UIKit.corner(Theme.CornerSmall).Parent = frame
	promptStroke = UIKit.stroke(Theme.Accent, 2, 0)
	promptStroke.Parent = frame
	promptTitle = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.FontBold, TextSize = 18, Parent = frame })
	promptSub = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.FontBold, TextSize = 15, Parent = frame })
	spookLabel = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 30),
		Size = UDim2.fromOffset(560, 26),
		Font = Theme.FontBold,
		TextSize = 18,
		TextColor3 = Theme.Warn,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = HUDController.diveRoot,
	})
	UIKit.scaled(spookLabel)
	UIKit.textStroke(2).Parent = spookLabel
end

function InteractionController.Start()
	InputController.Action:Connect(onAction)
	SubController.Ended:Connect(function()
		salvaging = false
		prompt.Enabled = false
	end)
	RunService.RenderStepped:Connect(step)
end

return InteractionController

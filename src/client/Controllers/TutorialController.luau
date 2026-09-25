--!strict
-- The tutorial on screen: an instruction panel with text for your input device, a glowing guide
-- beam and a bouncing arrow to the current target (dock station, the guided fish or treasure,
-- or the surface), and a Skip button. The server decides the step (TutorialService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Tutorial = require(Shared.Config.Tutorial)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Window = require(script.Parent.Parent.UI.Window)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local SubController = require(script.Parent.SubController)
local EntityRenderer = require(script.Parent.EntityRenderer)
local AudioController = require(script.Parent.AudioController)
local HUDController = require(script.Parent.HUDController)
local EffectsController = require(script.Parent.EffectsController)

local TutorialController = {}

TutorialController.active = false

type State = {
	step: number,
	target: Vector3?,
	launch: Vector3?,
	fish: number?,
	treasure: number?,
}

local DIVE_STEPS = { Descend = true, Catch = true, Salvage = true, Surface = true }
local HIDE_BEAM_WITHIN = 9

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local titleLabel: TextLabel
local bodyLabel: TextLabel
local iconLabel: TextLabel
local fromPart: Part
local toPart: Part
local beam: Beam
local arrow: BillboardGui
local arrowLabel: TextLabel
local distanceLabel: TextLabel
local state: State? = nil
local lastStep = 0

local function stepDef(index: number): Tutorial.Step?
	return Tutorial.steps[index]
end

local function textFor(step: Tutorial.Step): string
	local mode = InputController.mode
	if mode == "Gamepad" then
		return step.text.Gamepad
	elseif mode == "Touch" then
		return step.text.Touch
	end
	return step.text.KeyboardMouse
end

local function refreshText()
	local current = state
	if not current then
		return
	end
	local step = stepDef(current.step)
	if not step then
		return
	end
	header.Text = string.format("TUTORIAL  ·  %d / %d", current.step, #Tutorial.steps)
	iconLabel.Text = step.icon
	if DIVE_STEPS[step.id] and not SubController.isDiving() then
		titleLabel.Text = step.title
		bodyLabel.Text = "Head back to the Launch Bay and dive in to continue."
	else
		titleLabel.Text = step.title
		bodyLabel.Text = textFor(step)
	end
end

local function sourcePosition(): Vector3?
	local root = SubController.root
	if SubController.isDiving() and root then
		return root.Position
	end
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

local function targetPosition(): Vector3?
	local current = state
	if not current then
		return nil
	end
	local step = stepDef(current.step)
	if not step then
		return nil
	end
	local diving = SubController.isDiving()
	if DIVE_STEPS[step.id] and not diving then
		return current.launch
	end
	if step.target == "Fish" then
		local view = if current.fish then EntityRenderer.fish[current.fish] else nil
		return if view then view.position else nil
	elseif step.target == "Treasure" then
		local view = if current.treasure then EntityRenderer.treasure[current.treasure] else nil
		return if view then view.position else nil
	elseif step.target == "Surface" then
		local from = sourcePosition()
		return if from then Vector3.new(from.X, -1, from.Z) else nil
	end
	return current.target
end

local function setVisible(visible: boolean)
	TutorialController.active = visible
	panel.Visible = visible
	if not visible then
		beam.Enabled = false
		arrow.Enabled = false
	end
end

local function onState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.done then
		state = nil
		setVisible(false)
		return
	end
	if typeof(payload.step) ~= "number" then
		return
	end
	state = {
		step = payload.step,
		target = if typeof(payload.target) == "Vector3" then payload.target else nil,
		launch = if typeof(payload.launch) == "Vector3" then payload.launch else nil,
		fish = if typeof(payload.fish) == "number" then payload.fish else nil,
		treasure = if typeof(payload.treasure) == "number" then payload.treasure else nil,
	}
	if payload.step > lastStep and lastStep > 0 then
		AudioController.play("QuestComplete")
		EffectsController.flash(Theme.Accent, 0.2, 0.4)
		local scale = panel:FindFirstChildOfClass("UIScale")
		if scale then
			local base = scale.Scale
			scale.Scale = base * 1.08
			UIKit.tween(scale, { Scale = base }, 0.35, Enum.EasingStyle.Back)
		end
	end
	lastStep = payload.step
	setVisible(true)
	refreshText()
end

local function step()
	local current = state
	if not current then
		return
	end
	local from = sourcePosition()
	local to = targetPosition()
	if not from or not to then
		beam.Enabled = false
		arrow.Enabled = false
		return
	end
	fromPart.CFrame = CFrame.new(from)
	toPart.CFrame = CFrame.new(to)
	local distance = (to - from).Magnitude
	beam.Enabled = distance > HIDE_BEAM_WITHIN
	arrow.Enabled = true
	local bob = math.sin(os.clock() * 4) * 0.6
	arrow.StudsOffset = Vector3.new(0, 5 + bob, 0)
	local stepInfo = stepDef(current.step)
	arrowLabel.Text = if stepInfo and stepInfo.target == "Surface" and SubController.isDiving() then "⬆" else "⬇"
	distanceLabel.Text = if distance > HIDE_BEAM_WITHIN then string.format("%dm", math.floor(distance)) else ""
end

local function skip()
	Window.confirm(gui, "Skip the tutorial?", "You can still find everything on the dock: the Launch Bay, Fish Market, Workshop and Quest Board.", "SKIP", function()
		Net.event("Tutorial"):FireServer("Skip")
	end)
end

function TutorialController.Init()
	gui = UIKit.screen("DeepHaulTutorial", 12)
	panel = UIKit.panel({
		Name = "TutorialPanel",
		Position = UDim2.fromOffset(110, 310),
		Size = UDim2.fromOffset(420, 136),
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = gui,
	})
	UIKit.scaled(panel)
	iconLabel = UIKit.label({ Text = "⚓", Position = UDim2.fromOffset(10, 30), Size = UDim2.fromOffset(52, 52), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	header = UIKit.label({ Text = "TUTORIAL", Position = UDim2.fromOffset(16, 6), Size = UDim2.fromOffset(250, 20), TextSize = 13, Font = Theme.FontBold, TextColor3 = Theme.Accent, Parent = panel })
	titleLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(70, 28), Size = UDim2.new(1, -84, 0, 28), Font = Theme.FontDisplay, TextSize = 22, Parent = panel })
	UIKit.textStroke(1.5).Parent = titleLabel
	bodyLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(70, 58), Size = UDim2.new(1, -84, 0, 70), TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top, Parent = panel })
	UIKit.button({ Text = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(64, 24), TextSize = 13, Parent = panel }, skip, Theme.PanelLight)

	local folder = Instance.new("Folder")
	folder.Name = "DH_TutorialGuide"
	folder.Parent = workspace
	local function anchorPart(name: string): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = folder
		return part
	end
	fromPart = anchorPart("From")
	toPart = anchorPart("To")
	local a0 = Instance.new("Attachment")
	a0.Parent = fromPart
	local a1 = Instance.new("Attachment")
	a1.Parent = toPart
	beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Theme.Accent, Color3.new(1, 1, 1))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
	beam.Width0 = 0.5
	beam.Width1 = 0.9
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 12
	beam.Enabled = false
	beam.Parent = folder

	arrow = Instance.new("BillboardGui")
	arrow.Name = "DH_TutorialArrow"
	arrow.Adornee = toPart
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.Size = UDim2.fromOffset(80, 90)
	arrow.StudsOffset = Vector3.new(0, 5, 0)
	arrow.Enabled = false
	arrow.ResetOnSpawn = false
	arrowLabel = UIKit.label({ Text = "⬇", Size = UDim2.new(1, 0, 0, 60), TextSize = 54, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Center, Parent = arrow })
	UIKit.textStroke(3).Parent = arrowLabel
	distanceLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Font = Theme.FontDisplay, TextXAlignment = Enum.TextXAlignment.Center, Parent = arrow })
	UIKit.textStroke(2).Parent = distanceLabel
	arrow.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TutorialController.Start()
	Net.event("Tutorial").OnClientEvent:Connect(onState)
	Net.event("Effect").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.kind == "TutorialDone" then
			AudioController.play("Achievement")
			EffectsController.flash(Theme.Good, 0.35, 0.8)
			HUDController.banner("TUTORIAL COMPLETE!", "Dive deeper for rarer fish. Check the Quest Board for goals!", Theme.Good, 5)
		end
	end)
	InputController.ModeChanged:Connect(refreshText)
	SubController.Started:Connect(refreshText)
	SubController.Ended:Connect(refreshText)
	RunService.RenderStepped:Connect(step)
	-- ask again once data is in, in case the first state arrived before this listener
	ClientState.waitReady()
	local data = ClientState.data
	if data and not data.Tutorial.Done and not state then
		Net.event("Tutorial"):FireServer("Sync")
	end
end

return TutorialController

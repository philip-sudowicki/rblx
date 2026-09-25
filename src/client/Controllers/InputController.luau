--!strict
-- Unifies PC, touch and console input into dive intents.
--
-- PC:      WASD move (via PlayerModule), mouse look, Space up, Left Shift down, Left Click action,
--          F sonar, hold Q thrusters, hold R emergency surface, Ctrl / C silent running, hold Alt for the cursor,
--          M menu.
-- Touch:   default thumbstick + MobileControls buttons (Up, Down, ACTION, Sonar, Surface, Slow),
--          drag on the right side of the screen to look.
-- Console: left stick move, right stick look, RT up, LT down, A action, Y sonar,
--          hold RB thrusters, hold X emergency surface, L3 silent running, Select (View) opens the menu.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Modules.Signal)
local Game = require(Shared.Config.Game)

local InputController = {}

InputController.mode = "KeyboardMouse" -- "KeyboardMouse" | "Touch" | "Gamepad"
InputController.ModeChanged = Signal.new() :: Signal.Signal<string>
InputController.Action = Signal.new() :: Signal.Signal<boolean>
InputController.Sonar = Signal.new() :: Signal.Signal<()>
InputController.Emergency = Signal.new() :: Signal.Signal<()>
InputController.SilentChanged = Signal.new() :: Signal.Signal<boolean>
InputController.MenuToggle = Signal.new() :: Signal.Signal<()>

InputController.silent = false
InputController.boosting = false -- thrusters held (Q / RB / BOOST button)
InputController.BoostChanged = Signal.new() :: Signal.Signal<boolean>
InputController.actionHeld = false
InputController.diving = false
InputController.cursorFree = false -- menus open or Alt held
InputController.menuOpen = false
InputController.emergencyStart = 0 -- os.clock() when the emergency hold began (0 = not holding)

local keyboardVertical = 0
local ascendHeld, descendHeld = false, false
local triggerUp, triggerDown = 0, 0
local touchVertical = 0
local rightStick = Vector2.zero
local touchLook = Vector2.zero
local lookTouch: InputObject? = nil
local lookTouchLast: Vector3? = nil
local altHeld = false
local controls: any = nil

local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 50

local function setMode(mode: string)
	if InputController.mode ~= mode then
		InputController.mode = mode
		InputController.ModeChanged:Fire(mode)
	end
end

local function modeFor(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
		return "KeyboardMouse"
	end
	return nil
end

-- Move input in the PlayerModule convention: X = right, Z = back (so forward is -Z).
function InputController.moveVector(): Vector3
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

-- -1 (down) … 1 (up)
function InputController.vertical(): number
	local v = keyboardVertical + triggerUp - triggerDown + touchVertical
	return math.clamp(v, -1, 1)
end

function InputController.setTouchVertical(value: number)
	touchVertical = value
end

-- Look delta this frame in "degrees" (already scaled for sensitivity per device).
function InputController.consumeLook(dt: number): Vector2
	local delta = Vector2.zero
	if InputController.mode == "KeyboardMouse" and not InputController.cursorFree then
		local mouse = UserInputService:GetMouseDelta()
		delta += mouse * Game.Camera.MouseSensitivity
	end
	if rightStick.Magnitude > 0.15 then
		delta += Vector2.new(rightStick.X, -rightStick.Y) * Game.Camera.GamepadSensitivity * dt
	end
	if touchLook.Magnitude > 0 then
		delta += touchLook * Game.Camera.TouchSensitivity
		touchLook = Vector2.zero
	end
	return delta
end

function InputController.setSilent(value: boolean)
	if InputController.silent ~= value then
		InputController.silent = value
		InputController.SilentChanged:Fire(value)
	end
end

function InputController.setBoost(down: boolean)
	if InputController.boosting ~= down then
		InputController.boosting = down
		InputController.BoostChanged:Fire(down)
	end
end

function InputController.pressAction(down: boolean)
	if InputController.actionHeld == down then
		return
	end
	InputController.actionHeld = down
	InputController.Action:Fire(down)
end

function InputController.beginEmergency()
	if InputController.emergencyStart == 0 then
		InputController.emergencyStart = os.clock()
	end
end

function InputController.endEmergency()
	InputController.emergencyStart = 0
end

-- 0..1 progress of the emergency hold
function InputController.emergencyProgress(): number
	if InputController.emergencyStart == 0 then
		return 0
	end
	return math.clamp((os.clock() - InputController.emergencyStart) / Game.Dive.EmergencyHoldSeconds, 0, 1)
end

local function updateCursor()
	InputController.cursorFree = InputController.menuOpen or altHeld or not InputController.diving
	if InputController.diving and not InputController.cursorFree and InputController.mode == "KeyboardMouse" then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end
InputController.updateCursor = updateCursor

function InputController.setMenuOpen(open: boolean)
	InputController.menuOpen = open
	if open then
		InputController.pressAction(false)
	end
	updateCursor()
end

local function sink(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function bindDiveActions()
	ContextActionService:BindActionAtPriority("DH_Ascend", function(_, inputState, input)
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			triggerUp = if inputState == Enum.UserInputState.End then 0 else input.Position.Z
		else
			ascendHeld = inputState == Enum.UserInputState.Begin or (inputState == Enum.UserInputState.Change and ascendHeld)
			if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				ascendHeld = false
			end
		end
		keyboardVertical = (if ascendHeld then 1 else 0) - (if descendHeld then 1 else 0)
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)

	ContextActionService:BindActionAtPriority("DH_Descend", function(_, inputState, input)
		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			triggerDown = if inputState == Enum.UserInputState.End then 0 else input.Position.Z
		else
			descendHeld = inputState == Enum.UserInputState.Begin or (inputState == Enum.UserInputState.Change and descendHeld)
			if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				descendHeld = false
			end
		end
		keyboardVertical = (if ascendHeld then 1 else 0) - (if descendHeld then 1 else 0)
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL2)

	ContextActionService:BindActionAtPriority("DH_Action", function(_, inputState, input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and InputController.cursorFree then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			InputController.pressAction(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			InputController.pressAction(false)
		end
		return sink()
	end, false, ACTION_PRIORITY, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonA)

	ContextActionService:BindActionAtPriority("DH_Sonar", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			InputController.Sonar:Fire()
		end
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.F, Enum.KeyCode.ButtonY)

	ContextActionService:BindActionAtPriority("DH_Emergency", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			InputController.beginEmergency()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			InputController.endEmergency()
		end
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

	ContextActionService:BindActionAtPriority("DH_Boost", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			InputController.setBoost(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			InputController.setBoost(false)
		end
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)

	ContextActionService:BindActionAtPriority("DH_Silent", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			InputController.setSilent(not InputController.silent)
		end
		return sink()
	end, false, ACTION_PRIORITY, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonL3)
end

local function unbindDiveActions()
	for _, name in { "DH_Ascend", "DH_Descend", "DH_Action", "DH_Sonar", "DH_Emergency", "DH_Silent", "DH_Boost" } do
		ContextActionService:UnbindAction(name)
	end
	InputController.setBoost(false)
	ascendHeld, descendHeld = false, false
	keyboardVertical, triggerUp, triggerDown, touchVertical = 0, 0, 0, 0
	InputController.pressAction(false)
	InputController.endEmergency()
end

function InputController.setDiving(diving: boolean)
	if InputController.diving == diving then
		return
	end
	InputController.diving = diving
	if diving then
		bindDiveActions()
	else
		unbindDiveActions()
		InputController.setSilent(false)
	end
	updateCursor()
end

function InputController.Init()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	task.spawn(function()
		local playerModule = playerScripts:WaitForChild("PlayerModule", 30)
		if playerModule and playerModule:IsA("ModuleScript") then
			local ok, module = pcall(require, playerModule)
			if ok and module then
				controls = (module :: any):GetControls()
			end
		end
	end)

	local initial = modeFor(UserInputService:GetLastInputType())
	if initial then
		setMode(initial)
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		setMode("Touch")
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		setMode("Gamepad")
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local mode = modeFor(inputType)
		if mode then
			setMode(mode)
			updateCursor()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			altHeld = true
			updateCursor()
		elseif (input.KeyCode == Enum.KeyCode.ButtonSelect or input.KeyCode == Enum.KeyCode.M) and not processed then
			InputController.MenuToggle:Fire()
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed and InputController.diving then
			local camera = workspace.CurrentCamera
			if camera and input.Position.X > camera.ViewportSize.X * 0.42 and lookTouch == nil then
				lookTouch = input
				lookTouchLast = input.Position
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.new(input.Position.X, input.Position.Y)
		elseif input == lookTouch and lookTouchLast then
			local delta = input.Position - lookTouchLast
			lookTouchLast = input.Position
			touchLook += Vector2.new(delta.X, delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			altHeld = false
			updateCursor()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.zero
		elseif input == lookTouch then
			lookTouch = nil
			lookTouchLast = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		altHeld = false
		InputController.pressAction(false)
		InputController.endEmergency()
		ascendHeld, descendHeld, keyboardVertical = false, false, 0
	end)
end

return InputController

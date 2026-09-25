--!strict
-- Routes the dock's ProximityPrompts (attribute "DeepHaulAction") to the right UI. The server
-- validates every action again; prompts only open menus. Also hides other players' aquarium
-- collectors and every dock prompt while diving.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Modules.Signal)

local PromptRouter = {}

-- (action, prompt) for menus that aren't the launch panel
PromptRouter.Triggered = Signal.new() :: Signal.Signal<string, ProximityPrompt>

local handlers: { [string]: (ProximityPrompt) -> () } = {}

function PromptRouter.on(action: string, handler: (ProximityPrompt) -> ())
	handlers[action] = handler
end

function PromptRouter.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWhoTriggered)
		if playerWhoTriggered ~= Players.LocalPlayer then
			return
		end
		local action = prompt:GetAttribute("DeepHaulAction")
		if typeof(action) ~= "string" then
			return
		end
		local handler = handlers[action]
		if handler then
			handler(prompt)
		end
		PromptRouter.Triggered:Fire(action, prompt)
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if Players.LocalPlayer:GetAttribute("Diving") == true and prompt:GetAttribute("DeepHaulAction") ~= nil then
			prompt.Enabled = false
			task.delay(1, function()
				prompt.Enabled = true
			end)
		end
	end)
end

return PromptRouter

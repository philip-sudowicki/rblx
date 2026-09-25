--!strict
-- DEEP HAUL client bootstrap: Init every controller (UI construction, signal wiring), then Start.

local StarterGui = game:GetService("StarterGui")

local Controllers = script.Parent:WaitForChild("Controllers")
local Menus = script.Parent:WaitForChild("Menus")
local UI = script.Parent:WaitForChild("UI")

local ORDER: { Instance } = {
	UI:WaitForChild("UIKit"),
	Controllers:WaitForChild("ClientState"),
	Controllers:WaitForChild("InputController"),
	Controllers:WaitForChild("SubController"),
	Controllers:WaitForChild("ZoneController"),
	Controllers:WaitForChild("AudioController"),
	Controllers:WaitForChild("WorldFXController"),
	Controllers:WaitForChild("HUDController"),
	Controllers:WaitForChild("EffectsController"),
	Controllers:WaitForChild("PopupController"),
	Controllers:WaitForChild("MarketController"),
	Controllers:WaitForChild("MobileControls"),
	Controllers:WaitForChild("EntityRenderer"),
	Controllers:WaitForChild("CraneController"),
	Controllers:WaitForChild("MinigameController"),
	Controllers:WaitForChild("SalvageController"),
	Controllers:WaitForChild("InteractionController"),
	Controllers:WaitForChild("SonarController"),
	Controllers:WaitForChild("RevealController"),
	Controllers:WaitForChild("PromptRouter"),
	Menus:WaitForChild("LaunchPanel"),
	Controllers:WaitForChild("MenuController"),
	Controllers:WaitForChild("DockController"),
	Controllers:WaitForChild("TutorialController"),
	Controllers:WaitForChild("EventController"),
	Controllers:WaitForChild("ChatController"),
	Controllers:WaitForChild("OfferController"),
	Controllers:WaitForChild("DebugConsole"),
}

local modules: { { name: string, module: any } } = {}
for _, moduleScript in ORDER do
	assert(moduleScript:IsA("ModuleScript"), moduleScript.Name .. " is not a ModuleScript")
	table.insert(modules, { name = moduleScript.Name, module = require(moduleScript) :: any })
end

for _, entry in modules do
	if entry.module.Init then
		local ok, err = pcall(entry.module.Init)
		if not ok then
			warn(string.format("[DeepHaul] %s.Init failed: %s", entry.name, tostring(err)))
		end
	end
end
for _, entry in modules do
	if entry.module.Start then
		task.spawn(function()
			local ok, err = pcall(entry.module.Start)
			if not ok then
				warn(string.format("[DeepHaul] %s.Start failed: %s", entry.name, tostring(err)))
			end
		end)
	end
end

-- tell the loading screen we're ready once the save has arrived and everything has started
task.spawn(function()
	local ClientState = require(Controllers:WaitForChild("ClientState")) :: any
	ClientState.waitReady()
	task.wait(0.5)
	game:GetService("Players").LocalPlayer:SetAttribute("DH_ClientReady", true)
end)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

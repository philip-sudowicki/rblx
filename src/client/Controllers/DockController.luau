--!strict
-- Glue for the dock: opens the Launch panel from the Launch Bay prompt and reports how a dive
-- ended (secured / lost / auto-sold).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Modules.Format)
local PromptRouter = require(script.Parent.PromptRouter)
local SubController = require(script.Parent.SubController)
local HUDController = require(script.Parent.HUDController)
local LaunchPanel = require(script.Parent.Parent.Menus.LaunchPanel)

local DockController = {}

function DockController.Start()
	PromptRouter.on("Launch", function()
		LaunchPanel.open()
	end)
	SubController.Ended:Connect(function(summary)
		if typeof(summary) ~= "table" then
			return
		end
		if summary.reason == "Blackout" then
			if summary.insured then
				HUDController.toast("You blacked out, but Cargo Insurance saved your whole haul!", "good", "🛡️")
			elseif summary.lost > 0 then
				HUDController.toast(string.format("You blacked out and lost %d items (%s coins of loot).", summary.lost, Format.short(summary.lostValue)), "bad", "💀")
			else
				HUDController.toast("You blacked out! Keep an eye on oxygen and hull.", "bad", "💀")
			end
		elseif summary.secured > 0 then
			HUDController.toast(string.format("Surfaced! %d items secured in storage.", summary.secured), "good", "⚓")
		end
		if summary.autoSold and summary.autoSold > 0 then
			HUDController.toast(string.format("Auto-Sold %d items for %s coins.", summary.autoSold, Format.short(summary.autoCoins)), "good", "💸")
		end
	end)
end

return DockController

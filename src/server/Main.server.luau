--!strict
-- DEEP HAUL server bootstrap. Services are required in dependency order, then every service's
-- Init runs (setup, no cross-service calls that need other services started), then Start.

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"PlayerState",
	"RateLimiter",
	"Remotes",
	"AnnounceService",
	"DataService",
	"WorldService",
	"PassService",
	"BoostService",
	"EventService",
	"StatsService",
	"InventoryService",
	"SubService",
	"SpawnService",
	"LootService",
	"CatchService",
	"SalvageService",
	"PredatorService",
	"UpgradeService",
	"RebirthService",
	"AquariumService",
	"IndexService",
	"NametagService",
	"CosmeticService",
	"SettingsService",
	"DailyService",
	"QuestService",
	"AchievementService",
	"LeaderboardService",
	"CodesService",
	"TutorialService",
	"EventContentService",
	"MonetizationService",
}

local modules: { { name: string, module: any } } = {}
for _, name in ORDER do
	local moduleScript = Services:FindFirstChild(name)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "missing service " .. name)
	table.insert(modules, { name = name, module = require(moduleScript) :: any })
end

for _, entry in modules do
	if typeof(entry.module) == "table" and entry.module.Init then
		local ok, err = pcall(entry.module.Init)
		if not ok then
			warn(string.format("[DeepHaul] %s.Init failed: %s", entry.name, tostring(err)))
		end
	end
end

for _, entry in modules do
	if typeof(entry.module) == "table" and entry.module.Start then
		task.spawn(function()
			local ok, err = pcall(entry.module.Start)
			if not ok then
				warn(string.format("[DeepHaul] %s.Start failed: %s", entry.name, tostring(err)))
			end
		end)
	end
end

print("[DeepHaul] server ready")

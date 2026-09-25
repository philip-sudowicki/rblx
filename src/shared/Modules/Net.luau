--!strict
-- Remote definitions. The server creates every remote at startup (Remotes service); clients
-- look them up here. Client → server remotes are intents only; see server/Services/Remotes for
-- rate limits and validation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FOLDER = "Remotes"

-- Reliable RemoteEvents
Net.Events = {
	-- client → server
	"Dive",
	"EmergencySurface",
	"CatchStart",
	"CatchTap",
	"SalvageStart",
	"SalvageCancel",
	"Sonar",
	"Sell",
	"SellAll",
	"Favorite",
	"Display",
	"Undisplay",
	"CollectAquarium",
	"BuyUpgrade",
	"Rebirth",
	"BuyPerk",
	"ClaimDaily",
	"ClaimQuest",
	"ClaimIndex",
	"EquipSkin",
	"SetSetting",
	"Tutorial",
	"UseConsumable",
	"PromptPurchase",
	"DebugCommand",
	-- server → client
	"DataInit",
	"DataSet",
	"InvAdd",
	"InvRemove",
	"InvUpdate",
	"Entities",
	"Minigame",
	"CatchResult",
	"SalvageState",
	"DiveEvent",
	"Notify",
	"Reveal",
	"Announce",
	"EventState",
	"WelcomeBack",
	"Effect",
}

-- UnreliableRemoteEvents (high-frequency, loss-tolerant)
Net.Unreliable = {
	"Predators",
}

-- RemoteFunctions (client → server request/response)
Net.Functions = {
	"RedeemCode",
}

local cachedFolder: Folder? = nil

local function getFolder(): Folder
	local existingCache = cachedFolder
	if existingCache then
		return existingCache
	end
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Net.FOLDER)
		if existing and existing:IsA("Folder") then
			result = existing
		else
			local created = Instance.new("Folder")
			created.Name = Net.FOLDER
			created.Parent = ReplicatedStorage
			result = created
		end
	else
		result = ReplicatedStorage:WaitForChild(Net.FOLDER) :: Folder
	end
	cachedFolder = result
	return result
end

function Net.event(name: string): RemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: UnreliableRemoteEvent
	end
	return f:WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteFunction
	end
	return f:WaitForChild(name) :: RemoteFunction
end

-- Server only: create every remote. Called once by the Remotes service before players join.
function Net.createAll()
	assert(RunService:IsServer(), "Net.createAll is server-only")
	local f = getFolder()
	for _, name in Net.Events do
		if not f:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = f
		end
	end
	for _, name in Net.Unreliable do
		if not f:FindFirstChild(name) then
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = f
		end
	end
	for _, name in Net.Functions do
		if not f:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = f
		end
	end
end

return Net

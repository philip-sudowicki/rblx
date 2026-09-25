--!strict
-- Global leaderboards on the four dock boards (OrderedDataStores): Deepest Dive, Rarest Catch,
-- Total Haul Value and Most Resurfaced. Scores are written every few minutes and when a player
-- leaves; the top 10 are read periodically and drawn on SurfaceGuis. If DataStores aren't
-- reachable (Studio without API access, an outage) a board shows this server's players instead.
-- Also keeps the player-list leaderstats (Coins, Deepest, Rebirths) up to date.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Fish = require(Shared.Config.Fish)
local Treasure = require(Shared.Config.Treasure)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local LootMath = require(Shared.Modules.LootMath)
local Format = require(Shared.Modules.Format)
local Types = require(Shared.Modules.Types)
local DataService = require(script.Parent.DataService)
local PlayerState = require(script.Parent.PlayerState)
local ServerSignals = require(script.Parent.ServerSignals)
local WorldService = require(script.Parent.WorldService)

local LeaderboardService = {}

type Entry = { userId: number, value: number }

type Board = {
	id: string,
	title: string,
	icon: string,
	color: Color3,
	storeName: string,
	value: (data: Types.PlayerData) -> number,
	describe: (value: number) -> (string, Color3?),
	store: OrderedDataStore?,
	rows: { { frame: Frame, rank: TextLabel, avatar: ImageLabel, name: TextLabel, value: TextLabel } },
	status: TextLabel?,
}

local function rarestText(value: number): (string, Color3?)
	if value <= 0 then
		return "—", nil
	end
	local score, mutationIndex, isTreasure, order = LootMath.decodeBoardScore(value)
	local def: any = if isTreasure then Treasure.list[order] else Fish.list[order]
	if not def then
		return "1 in " .. Format.short(10 ^ (score / 1000)), nil
	end
	local mutationName = ""
	if mutationIndex > 0 then
		for _, mutation in Mutations.list do
			if mutation.order == mutationIndex then
				mutationName = mutation.name .. " "
			end
		end
	end
	local rarity = Rarities.byId[def.rarity]
	return string.format("%s%s", mutationName, def.name), if rarity then rarity.color else nil
end

local BOARDS: { Board } = {
	{
		id = "DeepestDive",
		title = "DEEPEST DIVE",
		icon = "🌊",
		color = Color3.fromRGB(90, 200, 255),
		storeName = "DH_Board_DeepestDive_v1",
		value = function(data)
			return math.floor(data.Stats.DeepestMeters)
		end,
		describe = function(value)
			return Format.meters(value), nil
		end,
		store = nil,
		rows = {},
	},
	{
		id = "RarestCatch",
		title = "RAREST CATCH",
		icon = "💎",
		color = Color3.fromRGB(200, 120, 255),
		storeName = "DH_Board_RarestCatch_v1",
		value = function(data)
			return math.floor(data.Stats.BestBoardValue)
		end,
		describe = rarestText,
		store = nil,
		rows = {},
	},
	{
		id = "TotalHaul",
		title = "TOTAL HAUL VALUE",
		icon = "🪙",
		color = Color3.fromRGB(255, 210, 80),
		storeName = "DH_Board_TotalHaul_v1",
		value = function(data)
			return math.floor(data.Stats.CoinsEarned)
		end,
		describe = function(value)
			return "🪙 " .. Format.short(value), nil
		end,
		store = nil,
		rows = {},
	},
	{
		id = "Rebirths",
		title = "MOST RESURFACED",
		icon = "🔱",
		color = Color3.fromRGB(120, 240, 220),
		storeName = "DH_Board_Rebirths_v1",
		value = function(data)
			return data.Rebirths
		end,
		describe = function(value)
			return string.format("%d rebirth%s", value, if value == 1 then "" else "s"), nil
		end,
		store = nil,
		rows = {},
	},
}

local lastWritten: { [Player]: { [string]: number } } = {}
local nameCache: { [number]: string } = {}
local thumbCache: { [number]: string } = {}

---------------------------------------------------------------- drawing

local RANK_COLORS = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(215, 225, 235), Color3.fromRGB(215, 140, 80) }

local function newLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function buildBoard(board: Board, part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Parent = part
	local root = Instance.new("Frame")
	root.BackgroundColor3 = Color3.fromRGB(8, 20, 36)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local title = newLabel(root, {
		Text = board.icon .. " " .. board.title,
		TextColor3 = board.color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.03, 0.02),
		Size = UDim2.fromScale(0.94, 0.11),
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = title
	for i = 1, Game.Leaderboards.Top do
		local y = 0.15 + (i - 1) * 0.075
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(14, 32, 54) else Color3.fromRGB(18, 40, 66)
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromScale(0.03, y)
		frame.Size = UDim2.fromScale(0.94, 0.07)
		frame.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = frame
		local rank = newLabel(frame, {
			Text = "#" .. i,
			TextColor3 = RANK_COLORS[i] or Color3.fromRGB(170, 190, 210),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(0.1, 0.8),
			Position = UDim2.fromScale(0, 0.1),
		})
		local avatar = Instance.new("ImageLabel")
		avatar.BackgroundTransparency = 1
		avatar.Position = UDim2.fromScale(0.105, 0.05)
		avatar.Size = UDim2.fromScale(0.07, 0.9)
		avatar.Image = ""
		avatar.Parent = frame
		local name = newLabel(frame, { Text = "", Position = UDim2.fromScale(0.19, 0.12), Size = UDim2.fromScale(0.4, 0.76) })
		local value = newLabel(frame, { Text = "", TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.6, 0.15), Size = UDim2.fromScale(0.38, 0.7) })
		board.rows[i] = { frame = frame, rank = rank, avatar = avatar, name = name, value = value }
	end
	board.status = newLabel(root, {
		Text = "Loading…",
		TextColor3 = Color3.fromRGB(130, 160, 190),
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.03, 0.915),
		Size = UDim2.fromScale(0.94, 0.06),
	})
end

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "Diver " .. tostring(userId)
	nameCache[userId] = result
	return result
end

-- Batch-resolves display names for ids we haven't seen (one web call instead of ten).
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not nameCache[id] and id > 0 then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and typeof(infos) == "table" then
		for _, info in infos do
			if typeof(info) == "table" and typeof(info.Id) == "number" and typeof(info.DisplayName) == "string" then
				nameCache[info.Id] = info.DisplayName
			end
		end
	end
end

local function thumbOf(userId: number): string
	local cached = thumbCache[userId]
	if cached then
		return cached
	end
	if userId <= 0 then
		return ""
	end
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	local result = if ok and typeof(content) == "string" then content else ""
	thumbCache[userId] = result
	return result
end

local function draw(board: Board, entries: { Entry }, live: boolean)
	local ids = {}
	for _, entry in entries do
		table.insert(ids, entry.userId)
	end
	resolveNames(ids)
	for i, row in board.rows do
		local entry = entries[i]
		if entry then
			local text, color = board.describe(entry.value)
			row.name.Text = nameOf(entry.userId)
			row.value.Text = text
			row.value.TextColor3 = color or Color3.new(1, 1, 1)
			row.avatar.Image = thumbOf(entry.userId)
			row.frame.Visible = true
		else
			row.name.Text = ""
			row.value.Text = ""
			row.avatar.Image = ""
			row.frame.Visible = i <= 3
		end
	end
	local status = board.status
	if status then
		status.Text = if live then string.format("Global top %d · updates every %d min", Game.Leaderboards.Top, math.floor(Game.Leaderboards.RefreshSeconds / 60)) else "Showing this server (global boards offline)"
	end
end

---------------------------------------------------------------- data

local function localEntries(board: Board): { Entry }
	local out: { Entry } = {}
	for _, state in PlayerState.all() do
		local data = DataService.get(state.player)
		if data then
			local value = board.value(data)
			if value > 0 then
				table.insert(out, { userId = state.player.UserId, value = value })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.value > b.value
	end)
	while #out > Game.Leaderboards.Top do
		table.remove(out)
	end
	return out
end

local function refreshBoard(board: Board)
	local store = board.store
	local entries: { Entry } = {}
	local live = false
	if store then
		local ok, result = pcall(function()
			local pages = store:GetSortedAsync(false, Game.Leaderboards.Top, 1)
			return pages:GetCurrentPage()
		end)
		if ok and typeof(result) == "table" then
			live = true
			for _, item in result do
				local userId = tonumber(item.key)
				if userId and typeof(item.value) == "number" then
					table.insert(entries, { userId = userId, value = item.value })
				end
			end
		end
	end
	if not live then
		entries = localEntries(board)
	end
	draw(board, entries, live)
end

local function writePlayer(player: Player, force: boolean?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local written = lastWritten[player]
	if not written then
		written = {}
		lastWritten[player] = written
	end
	for _, board in BOARDS do
		local store = board.store
		local value = board.value(data)
		if store and value > 0 and (force or written[board.id] ~= value) then
			local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync)
			if budget > 0 then
				local ok, err = pcall(function()
					store:SetAsync(tostring(player.UserId), value)
				end)
				if ok then
					written[board.id] = value
				else
					warn(string.format("[DeepHaul] leaderboard %s write failed: %s", board.id, tostring(err)))
				end
			end
		end
	end
end

---------------------------------------------------------------- leaderstats

local function ensureStats(player: Player): Folder
	local folder = player:FindFirstChild("leaderstats")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = created
	local deepest = Instance.new("StringValue")
	deepest.Name = "Deepest"
	deepest.Value = "0m"
	deepest.Parent = created
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = 0
	rebirths.Parent = created
	created.Parent = player
	return created
end

local function updateStats(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local folder = ensureStats(player)
	local coins = folder:FindFirstChild("Coins") :: StringValue?
	local deepest = folder:FindFirstChild("Deepest") :: StringValue?
	local rebirths = folder:FindFirstChild("Rebirths") :: IntValue?
	local coinText = Format.short(data.Coins)
	if coins and coins.Value ~= coinText then
		coins.Value = coinText
	end
	local depthText = Format.meters(data.Stats.DeepestMeters)
	if deepest and deepest.Value ~= depthText then
		deepest.Value = depthText
	end
	if rebirths and rebirths.Value ~= data.Rebirths then
		rebirths.Value = data.Rebirths
	end
end

function LeaderboardService.Start()
	for _, board in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.storeName)
		end)
		board.store = if ok then store else nil
		local part = WorldService.dock and WorldService.dock.boards[board.id]
		if part then
			buildBoard(board, part)
		end
	end
	DataService.onLoaded(function(player)
		nameCache[player.UserId] = player.DisplayName
		updateStats(player)
	end)
	ServerSignals.PlayerLeaving:Connect(function(player)
		task.spawn(function()
			writePlayer(player)
			lastWritten[player] = nil
		end)
	end)
	-- leaderstats
	task.spawn(function()
		while true do
			task.wait(1)
			for _, state in PlayerState.all() do
				if state.ready then
					updateStats(state.player)
				end
			end
		end
	end)
	-- periodic writes, staggered so every player isn't written in the same second
	task.spawn(function()
		while true do
			task.wait(Game.Leaderboards.WriteSeconds)
			for _, state in PlayerState.all() do
				if state.ready and state.player.Parent then
					writePlayer(state.player)
					task.wait(0.5)
				end
			end
		end
	end)
	-- periodic reads
	task.spawn(function()
		task.wait(5)
		while true do
			for _, board in BOARDS do
				if board.status then
					refreshBoard(board)
				end
			end
			task.wait(Game.Leaderboards.RefreshSeconds)
		end
	end)
end

return LeaderboardService

--!strict
-- Server-wide chat announcements, banners, and cross-server announcements via MessagingService.

local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)

local AnnounceService = {}

local TOPIC = "DeepHaul_Global_v1"
local lastGlobal = 0

local function hex(color: Color3?): string
	if not color then
		return "#FFFFFF"
	end
	return "#" .. color:ToHex()
end

-- Chat system message in this server. `text` may contain RichText; plain player names are safe.
function AnnounceService.chat(text: string, color: Color3?)
	Remotes.fireAll("Announce", { kind = "chat", text = text, color = hex(color) })
end

-- Big banner across the top of every screen in this server.
function AnnounceService.banner(text: string, color: Color3?, seconds: number?)
	Remotes.fireAll("Announce", { kind = "banner", text = text, color = hex(color), seconds = seconds or 5 })
end

function AnnounceService.chatTo(player: Player, text: string, color: Color3?)
	Remotes.fire(player, "Announce", { kind = "chat", text = text, color = hex(color) })
end

-- Announce in every server in the experience (Secret catches).
function AnnounceService.global(text: string, color: Color3?)
	AnnounceService.chat(text, color)
	AnnounceService.banner(text, color, 8)
	if RunService:IsStudio() then
		return
	end
	-- Keep well under MessagingService limits even if many secrets land at once.
	if os.clock() - lastGlobal < 2 then
		return
	end
	lastGlobal = os.clock()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(TOPIC, { text = text, color = hex(color), job = game.JobId })
		end)
		if not ok then
			warn("[DeepHaul] global announce failed: " .. tostring(err))
		end
	end)
end

function AnnounceService.Start()
	if RunService:IsStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local data = message.Data
				if typeof(data) ~= "table" or data.job == game.JobId then
					return
				end
				if typeof(data.text) ~= "string" or #data.text > 400 then
					return
				end
				local color = if typeof(data.color) == "string" then data.color else "#FFFFFF"
				Remotes.fireAll("Announce", { kind = "chat", text = "🌐 " .. data.text, color = color })
				Remotes.fireAll("Announce", { kind = "banner", text = data.text, color = color, seconds = 8 })
			end)
		end)
		if not ok then
			warn("[DeepHaul] global announce subscribe failed: " .. tostring(err))
		end
	end)
end

return AnnounceService

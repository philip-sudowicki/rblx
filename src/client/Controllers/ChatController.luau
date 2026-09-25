--!strict
-- Server announcements and chat tags. "Announce" chat messages appear as coloured system
-- messages in TextChatService; banners slide across the top of the screen (queued, never
-- overlapping). Player messages get a [VIP] tag and their rebirth stars from player attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Rebirth = require(Shared.Config.Rebirth)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ChatController = {}

local MAX_TEXT = 300

local bannerFrame: Frame
local bannerLabel: TextLabel
local bannerQueue: { { text: string, color: Color3, seconds: number } } = {}
local bannerBusy = false

local function parseColor(value: any): Color3
	if typeof(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return Color3.new(1, 1, 1)
end

-- Server text is trusted, but strip markup anyway so a player's display name can't inject tags.
local function plain(text: string): string
	return (text:gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemMessage(text: string, color: Color3)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general and general:IsA("TextChannel") then
		general:DisplaySystemMessage(string.format('<font color="#%s">%s</font>', color:ToHex(), plain(text)))
	end
end

local showNextBanner: () -> ()

showNextBanner = function()
	if bannerBusy or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local entry = table.remove(bannerQueue, 1) :: { text: string, color: Color3, seconds: number }
	bannerLabel.Text = entry.text
	bannerLabel.TextColor3 = entry.color
	bannerFrame.Visible = true
	bannerFrame.Position = UDim2.new(0.5, 0, 0, -80)
	UIKit.tween(bannerFrame, { Position = UDim2.new(0.5, 0, 0, 70) }, 0.4, Enum.EasingStyle.Back)
	task.delay(entry.seconds, function()
		UIKit.tween(bannerFrame, { Position = UDim2.new(0.5, 0, 0, -80) }, 0.35)
		task.delay(0.4, function()
			bannerFrame.Visible = false
			bannerBusy = false
			showNextBanner()
		end)
	end)
end

function ChatController.banner(text: string, color: Color3?, seconds: number?)
	if #bannerQueue >= 4 then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, { text = text, color = color or Theme.Text, seconds = math.clamp(seconds or 5, 2, 10) })
	showNextBanner()
end

local function badgeFor(rebirths: number): (string?, Color3?)
	local best = nil
	for _, badge in Rebirth.badges do
		if rebirths >= badge.at then
			best = badge
		end
	end
	if best then
		return best.text, best.color
	end
	return nil, nil
end

function ChatController.Init()
	local gui = UIKit.screen("DeepHaulAnnouncements", 25)
	bannerFrame = UIKit.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -80), Size = UDim2.fromOffset(760, 54), Visible = false, Parent = gui })
	UIKit.scaled(bannerFrame)
	bannerLabel = UIKit.label({ Text = "", Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 1, 0), Font = Theme.FontDisplay, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, RichText = false, TextScaled = true, Parent = bannerFrame })
	UIKit.textStroke(2).Parent = bannerLabel
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 24
	constraint.Parent = bannerLabel
end

function ChatController.Start()
	Net.event("Announce").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
			return
		end
		local text = payload.text:sub(1, MAX_TEXT)
		local color = parseColor(payload.color)
		if payload.kind == "banner" then
			ChatController.banner(text, color, if typeof(payload.seconds) == "number" then payload.seconds else 5)
		else
			systemMessage(text, color)
		end
	end)
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return nil
		end
		local prefix = ""
		local rebirths = player:GetAttribute("Rebirths")
		if typeof(rebirths) == "number" and rebirths > 0 then
			local text, color = badgeFor(rebirths)
			if text and color then
				prefix ..= string.format('<font color="#%s">%s</font> ', color:ToHex(), text)
			end
		end
		if player:GetAttribute("VIP") == true then
			prefix ..= '<font color="#FFD24A">[VIP]</font> '
		end
		if prefix == "" then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = prefix .. message.PrefixText
		return properties
	end
end

return ChatController

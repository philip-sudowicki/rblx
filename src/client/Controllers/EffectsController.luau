--!strict
-- Screen-space juice: flashes, slow motion, floating numbers, coin bursts flying to the coin
-- counter, and the fade used for surfacing / blackout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Rebirth = require(Shared.Config.Rebirth)
local CollectionSets = require(Shared.Config.CollectionSets)
local Achievements = require(Shared.Config.Achievements)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local SubController = require(script.Parent.SubController)
local AudioController = require(script.Parent.AudioController)
local HUDController = require(script.Parent.HUDController)

local EffectsController = {}

local gui: ScreenGui
local flash: Frame
local fade: Frame
local fadeText: TextLabel
local fadeSub: TextLabel
local layer: Frame

EffectsController.timeScale = 1

function EffectsController.flash(color: Color3?, strength: number?, duration: number?)
	flash.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1 - (strength or 0.7)
	UIKit.tween(flash, { BackgroundTransparency = 1 }, duration or 0.6)
end

-- Slows the sub and loot animation for a dramatic moment.
function EffectsController.slowMo(scale: number, duration: number)
	EffectsController.timeScale = scale
	SubController.timeScale = scale
	task.delay(duration, function()
		EffectsController.timeScale = 1
		SubController.timeScale = 1
	end)
end

function EffectsController.fadeOut(title: string, subtitle: string?, color: Color3?, hold: number?)
	fade.BackgroundColor3 = color or Color3.new(0, 0, 0)
	fadeText.Text = title
	fadeSub.Text = subtitle or ""
	fade.BackgroundTransparency = 1
	fadeText.TextTransparency = 1
	fadeSub.TextTransparency = 1
	fade.Visible = true
	UIKit.tween(fade, { BackgroundTransparency = 0 }, 0.35)
	UIKit.tween(fadeText, { TextTransparency = 0 }, 0.5)
	UIKit.tween(fadeSub, { TextTransparency = 0 }, 0.6)
	task.delay(hold or 1.4, function()
		UIKit.tween(fade, { BackgroundTransparency = 1 }, 0.8)
		UIKit.tween(fadeText, { TextTransparency = 1 }, 0.6)
		UIKit.tween(fadeSub, { TextTransparency = 1 }, 0.6)
		task.delay(0.85, function()
			fade.Visible = false
		end)
	end)
end

-- Floating text rising from a screen position (defaults to screen centre).
function EffectsController.floatText(text: string, color: Color3?, at: UDim2?)
	local label = UIKit.label({
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at or UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(360, 44),
		Font = Theme.FontDisplay,
		TextSize = 34,
		TextColor3 = color or Theme.Coin,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = layer,
	})
	UIKit.textStroke(2.5).Parent = label
	local scale = UIKit.scaled(label)
	local base = scale.Scale
	scale.Scale = base * 0.5
	UIKit.tween(scale, { Scale = base * 1.1 }, 0.25, Enum.EasingStyle.Back)
	local target = label.Position - UDim2.fromOffset(0, 90)
	UIKit.tween(label, { Position = target }, 1.4, Enum.EasingStyle.Quad)
	task.delay(0.8, function()
		UIKit.tween(label, { TextTransparency = 1 }, 0.6)
	end)
	task.delay(1.5, function()
		label:Destroy()
	end)
end

-- Coins fly from the centre of the screen into the coin counter.
function EffectsController.coinBurst(amount: number)
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 3), 4, 18)
	local target = HUDController.topLeft.AbsolutePosition + Vector2.new(40, 20)
	local camera = workspace.CurrentCamera
	local centre = if camera then camera.ViewportSize / 2 else Vector2.new(640, 360)
	for i = 1, count do
		local coin = UIKit.label({
			Text = "💰",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(30, 30),
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(centre.X + math.random(-60, 60), centre.Y + math.random(-40, 40)),
			Parent = layer,
		})
		task.delay(i * 0.035, function()
			local mid = UDim2.fromOffset(centre.X + math.random(-160, 160), centre.Y - math.random(40, 160))
			UIKit.tween(coin, { Position = mid }, 0.25, Enum.EasingStyle.Quad)
			task.delay(0.25, function()
				UIKit.tween(coin, { Position = UDim2.fromOffset(target.X, target.Y), TextTransparency = 0.3 }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.46, function()
					coin:Destroy()
				end)
			end)
		end)
	end
	task.delay(0.7, function()
		AudioController.play("CoinGain", 1 + math.random() * 0.1)
	end)
end

function EffectsController.Init()
	gui = UIKit.screen("DeepHaulEffects", 30)
	layer = UIKit.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	flash = UIKit.frame({ BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = gui })
	fade = UIKit.frame({ BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Visible = false, Parent = gui })
	fadeText = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(900, 80),
		Font = Theme.FontDisplay,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 61,
		Parent = fade,
	})
	UIKit.scaled(fadeText)
	fadeSub = UIKit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 60),
		Size = UDim2.fromOffset(900, 40),
		Font = Theme.FontBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 61,
		Parent = fade,
	})
	UIKit.scaled(fadeSub)
end

function EffectsController.Start()
	Net.event("Effect").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "Sold" then
			EffectsController.floatText("+" .. Format.short(payload.coins) .. " 💰", Theme.Coin)
			EffectsController.coinBurst(payload.coins)
			AudioController.play("CoinBurst")
		elseif payload.kind == "Coins" then
			EffectsController.floatText("+" .. Format.short(payload.coins) .. " 💰", Theme.Coin)
			EffectsController.coinBurst(payload.coins)
		elseif payload.kind == "PredatorHit" then
			AudioController.play("Impact")
			EffectsController.flash(Theme.Bad, 0.35, 0.4)
		elseif payload.kind == "PredatorAggro" then
			AudioController.play("PredatorGrowl")
		elseif payload.kind == "Upgrade" then
			local upgrade = Upgrades.byId[payload.id]
			if upgrade then
				AudioController.play("Upgrade", 0.95 + math.min(payload.level or 1, 15) * 0.02)
				EffectsController.floatText(string.format("%s %s Lv %d", upgrade.icon, upgrade.name, payload.level or 1), Theme.Good)
				EffectsController.flash(Theme.Good, 0.18, 0.35)
			end
		elseif payload.kind == "Rebirth" then
			AudioController.play("Rebirth")
			EffectsController.flash(Theme.Token, 0.8, 1.2)
			EffectsController.fadeOut(
				string.format("🔱 REBIRTH #%d", payload.count or 1),
				string.format("x%s sell value forever · +%d tokens", tostring(1 + (payload.count or 1) * Rebirth.sellMultiplierPerRebirth), payload.tokens or 0),
				Color3.fromRGB(8, 40, 70),
				2.2
			)
			if payload.riftUnlocked then
				task.delay(3.2, function()
					HUDController.banner("THE RIFT IS OPEN", "Something ancient stirs below the Hadal Maw", Color3.fromRGB(200, 90, 255), 6)
				end)
			end
		elseif payload.kind == "Achievement" then
			local achievement = Achievements.byId[payload.id]
			if achievement then
				AudioController.play("Achievement")
				EffectsController.flash(Theme.Coin, 0.25, 0.6)
				HUDController.banner("🏅 " .. achievement.name, achievement.desc, Theme.Coin, 3.5)
			end
		elseif payload.kind == "WashedAshore" then
			EffectsController.fadeOut("WASHED ASHORE", if payload.reason == "swim" then "The tide carried you back to the beach" else "Back on the island", Color3.fromRGB(10, 60, 90), 0.6)
		elseif payload.kind == "QuestComplete" then
			AudioController.play("QuestComplete")
		elseif payload.kind == "Daily" then
			AudioController.play("DailyClaim")
			EffectsController.flash(Theme.Good, 0.3, 0.6)
		elseif payload.kind == "SetComplete" then
			local set = CollectionSets.byId[payload.id]
			if set then
				AudioController.play("Achievement")
				EffectsController.flash(set.color, 0.35, 0.8)
				HUDController.banner("SET COMPLETE!", set.name, set.color, 4)
			end
		end
	end)
	-- catch streak popup (the server adds +5% value per step while you keep catching)
	Net.event("Reveal").OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.streak) == "number" and payload.streak >= 2 then
			local bonus = math.min((payload.streak - 1) * Game.Catch.StreakBonusPerStep, Game.Catch.StreakMaxBonus)
			task.delay(0.6, function()
				EffectsController.floatText(string.format("🔥 %d streak! +%d%%", payload.streak, math.floor(bonus * 100 + 0.5)), Theme.Warn, UDim2.fromScale(0.5, 0.62))
				AudioController.play("CoinGain", 1 + math.min(payload.streak, 10) * 0.04, 0.5)
			end)
		end
	end)
	SubController.Ended:Connect(function(summary)
		if typeof(summary) ~= "table" then
			return
		end
		if summary.reason == "Blackout" then
			AudioController.play("Blackout")
			local subtitle = if summary.insured then "Cargo Insurance kept your whole haul"
				elseif summary.lost > 0 then string.format("You lost %d items", summary.lost)
				else "You made it back to the dock"
			EffectsController.fadeOut("BLACKOUT", subtitle, Color3.new(0, 0, 0), 1.8)
		elseif summary.reason == "Emergency" then
			AudioController.play("Emergency")
			EffectsController.fadeOut("SURFACED", string.format("%d items secured", summary.secured), Color3.fromRGB(10, 60, 90), 0.9)
		else
			AudioController.play("SubSurface")
			EffectsController.fadeOut("SURFACED", string.format("%d items secured", summary.secured), Color3.fromRGB(20, 110, 150), 0.7)
		end
	end)
	SubController.Started:Connect(function()
		AudioController.play("SubLaunch")
	end)
	Net.event("DiveEvent").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.type == "Damage" then
			AudioController.play("HullCrack", 0.9 + math.random() * 0.2)
		elseif payload.type == "Refill" then
			AudioController.play("Refill")
			EffectsController.flash(Theme.Accent, 0.3, 0.5)
		end
	end)
end

return EffectsController

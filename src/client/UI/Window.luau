--!strict
-- The standard menu window: dark navy panel, icon + title, close button, optional tabs and a
-- content area. 900×560 at the reference resolution; scaled responsively.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local Signal = require(Shared.Modules.Signal)
local UIKit = require(script.Parent.UIKit)

export type Window = {
	root: Frame,
	content: Frame,
	pages: { [string]: Frame },
	tab: string,
	TabChanged: Signal.Signal<string>,
	closeButton: TextButton,
	tabButtons: { [string]: TextButton },
	setTab: (name: string) -> (),
	title: TextLabel,
}

local Window = {}

Window.WIDTH = 900
Window.HEIGHT = 560

function Window.new(parent: Instance, title: string, icon: string, tabs: { string }?, onClose: () -> ()): Window
	local root = UIKit.panel({
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Window.WIDTH, Window.HEIGHT),
		Visible = false,
		Parent = parent,
	})
	UIKit.scaled(root, 0.98)
	local titleLabel = UIKit.label({
		Text = icon .. "  " .. title:upper(),
		Font = Theme.FontDisplay,
		TextSize = 30,
		TextColor3 = Theme.Accent,
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -120, 0, 40),
		Parent = root,
	})
	UIKit.textStroke(2).Parent = titleLabel
	local closeButton = UIKit.button({
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		TextSize = 22,
		Parent = root,
	}, onClose, Theme.PanelLight)

	local contentTop = 58
	local tabButtons: { [string]: TextButton } = {}
	local pages: { [string]: Frame } = {}
	local window: Window
	local tabChanged = Signal.new() :: Signal.Signal<string>

	local content = UIKit.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, contentTop),
		Size = UDim2.new(1, -32, 1, -contentTop - 14),
		Parent = root,
	})

	local function setTab(name: string)
		window.tab = name
		for tabName, button in tabButtons do
			local selected = tabName == name
			button.BackgroundColor3 = if selected then Theme.Accent else Theme.PanelLight
			button.TextColor3 = if selected then Theme.TextDark else Theme.Text
		end
		for pageName, page in pages do
			page.Visible = pageName == name
		end
		tabChanged:Fire(name)
	end

	if tabs and #tabs > 0 then
		local bar = UIKit.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, contentTop),
			Size = UDim2.new(1, -32, 0, 38),
			Parent = root,
		})
		UIKit.list(Enum.FillDirection.Horizontal, 8).Parent = bar
		for index, tabName in tabs do
			local button = UIKit.button({
				Text = tabName,
				Size = UDim2.fromOffset(150, 36),
				TextSize = 17,
				LayoutOrder = index,
				Parent = bar,
			}, function()
				setTab(tabName)
			end, Theme.PanelLight)
			tabButtons[tabName] = button
			local page = UIKit.frame({ Name = tabName, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
			pages[tabName] = page
		end
		content.Position = UDim2.fromOffset(16, contentTop + 46)
		content.Size = UDim2.new(1, -32, 1, -contentTop - 46 - 14)
	end

	window = {
		root = root,
		content = content,
		pages = pages,
		tab = if tabs and tabs[1] then tabs[1] else "",
		TabChanged = tabChanged,
		closeButton = closeButton,
		tabButtons = tabButtons,
		setTab = setTab,
		title = titleLabel,
	}
	if tabs and tabs[1] then
		setTab(tabs[1])
	end
	return window
end

-- A left/right pager for long grids. Returns controls and a set() to update the label.
function Window.pager(parent: Instance, position: UDim2, onChange: (delta: number) -> ()): (Frame, (page: number, pages: number) -> ())
	local frame = UIKit.frame({ BackgroundTransparency = 1, Position = position, Size = UDim2.fromOffset(220, 34), Parent = parent })
	UIKit.button({ Text = "◀", Size = UDim2.fromOffset(44, 34), Parent = frame }, function()
		onChange(-1)
	end, Theme.PanelLight)
	local label = UIKit.label({ Text = "1 / 1", Position = UDim2.fromOffset(50, 0), Size = UDim2.fromOffset(120, 34), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.FontBold, Parent = frame })
	UIKit.button({ Text = "▶", Position = UDim2.fromOffset(176, 0), Size = UDim2.fromOffset(44, 34), Parent = frame }, function()
		onChange(1)
	end, Theme.PanelLight)
	return frame, function(page: number, pages: number)
		label.Text = string.format("%d / %d", page, math.max(pages, 1))
	end
end

-- Confirmation dialog on top of a window.
function Window.confirm(parent: Instance, title: string, body: string, confirmText: string, onConfirm: () -> ())
	local dim = UIKit.frame({ BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = parent })
	local box = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 240),
		ZIndex = 41,
		Parent = dim,
	})
	UIKit.scaled(box)
	UIKit.label({ Text = title, Font = Theme.FontDisplay, TextSize = 28, TextColor3 = Theme.Accent, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 34), ZIndex = 42, Parent = box })
	UIKit.label({ Text = body, TextSize = 17, Position = UDim2.fromOffset(20, 54), Size = UDim2.new(1, -40, 0, 110), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 42, Parent = box })
	UIKit.button({ Text = "Cancel", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -16), Size = UDim2.fromOffset(150, 44), ZIndex = 42, Parent = box }, function()
		dim:Destroy()
	end, Theme.PanelLight)
	UIKit.button({ Text = confirmText, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(200, 44), ZIndex = 42, Parent = box }, function()
		dim:Destroy()
		onConfirm()
	end)
end

return Window

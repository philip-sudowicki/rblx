--!strict
-- UI palette and fonts. Rarity colours come from Config/Rarities so they match everywhere.

local rgb = Color3.fromRGB

return {
	Background = rgb(8, 16, 30),
	Panel = rgb(14, 28, 50),
	PanelLight = rgb(22, 42, 72),
	PanelDark = rgb(8, 18, 34),
	Stroke = rgb(40, 90, 140),
	Accent = rgb(0, 214, 255),
	AccentDark = rgb(0, 140, 190),
	Text = rgb(232, 246, 255),
	TextMuted = rgb(140, 170, 200),
	TextDark = rgb(8, 20, 34),
	Good = rgb(80, 230, 140),
	Warn = rgb(255, 196, 60),
	Bad = rgb(255, 80, 90),
	Coin = rgb(255, 210, 70),
	Token = rgb(150, 230, 255),
	Oxygen = rgb(90, 220, 255),
	Hull = rgb(150, 240, 150),

	Corner = UDim.new(0, 14),
	CornerSmall = UDim.new(0, 8),
	PanelTransparency = 0.05,

	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontDisplay = Enum.Font.FredokaOne,

	TweenFast = 0.15,
	TweenMedium = 0.28,
}

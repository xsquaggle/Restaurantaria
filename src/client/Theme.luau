--!strict
-- Live UI tokens from Style Guide v1 (Astra). Generated art is approximate; these are exact.

local Theme = {}

Theme.Colour = {
	ink = Color3.fromHex("#482C24"),
	paper = Color3.fromHex("#FFF2D7"),
	dough = Color3.fromHex("#E7CE9F"),
	mutedInk = Color3.fromHex("#7D6254"),
	tomato = Color3.fromHex("#C6513D"),
	basil = Color3.fromHex("#5B7D48"),
	oven = Color3.fromHex("#E6A143"),
	action = Color3.fromHex("#1D6B70"),
	actionPressed = Color3.fromHex("#175A60"),
	actionEdge = Color3.fromHex("#69B6B3"),
	disabled = Color3.fromHex("#C7B79C"),
	white = Color3.new(1, 1, 1),
	-- Live labels on Astra's V2 art (UI V2 integration proof 01 README).
	label = Color3.fromHex("#FFF8E8"),
	labelStroke = Color3.fromHex("#643027"),
	labelDisabled = Color3.fromHex("#40241F"),
	-- Scene stand-ins until station art exists.
	wall = Color3.fromHex("#F3E2C4"),
	counter = Color3.fromHex("#B98A5E"),
	tile = Color3.fromHex("#EAD7B5"),
}

Theme.Font = {
	display = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	-- Rounded body face to sit with Fredoka; its larger x-height keeps TextSize 14 legible.
	body = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.SemiBold),
	bodySemi = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold),
	bodyBold = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold),
}

Theme.Motion = {
	press = 0.08,
	release = 0.11,
	station = 0.14,
	status = 0.16,
	nudge = 0.45,
	repeatGuard = 0.35,
	toastSeconds = 4.5,
}

return Theme

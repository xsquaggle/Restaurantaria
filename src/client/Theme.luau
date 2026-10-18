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
	-- Scene stand-ins until station art exists.
	wall = Color3.fromHex("#F3E2C4"),
	counter = Color3.fromHex("#B98A5E"),
	tile = Color3.fromHex("#EAD7B5"),
}

Theme.Font = {
	display = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	body = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
	bodySemi = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold),
	bodyBold = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold),
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

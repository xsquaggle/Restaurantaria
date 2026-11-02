-- Studio-only comparison sheet for slice 8a's sauce: the continuous surface (Astra r21, the
-- default) against the slice 2 discs, for the same records. Run in Studio during Play, in the
-- Client (paste it: loadstring is not available there); it sets shared.sauceCompare to
-- { sheet = function(seconds, size), clear = function() }. sheet lays a sheet over the game: one
-- row per renderer, one column per record (Astra r21's proof set), every pizza drawn by the
-- game's own MakeLayers top-down on the same round dough at the given bake seconds (nil = raw).
-- Returns, per pizza, the grade's coverage and score, and for the surface its tiles (and the
-- deep-red bands'), drawn area against the credited area, and the specks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
local MakeLayers = require(Client.MakeLayers)
local MakeSauce = require(Shared.MakeSauce)
local SauceCover = require(Shared.SauceCover)
local G = require(Shared.PrepGeometry)

local function P(x: number, y: number)
	return { x = x, y = y }
end
local function circle(r: number): { any }
	local out = {}
	for i = 0, 40 do
		local a = 2 * math.pi * i / 40
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function sauceOf(pours: { any }, spreads: { { any } }): any
	local actions = {}
	for _, p in pours do
		table.insert(actions, { kind = "pour", x = p.x, y = p.y })
	end
	for _, s in spreads do
		table.insert(actions, { kind = "spread", points = s })
	end
	return { actions = actions }
end
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local function ring(r: number): { any }
	local out = {}
	for k = 0, 2 do
		local a = math.pi / 2 + k * 2 * math.pi / 3
		table.insert(out, P(r * math.cos(a), r * math.sin(a)))
	end
	return out
end
-- Astra r21's sauce proof set: sparse, even, bare island, crust only, spill, plus the mound
-- (thick sauce, deep red).
local RECORDS = {
	{ "Sparse", sauceOf({ P(-0.5, 0.1) }, { { P(-0.6, 0.1), P(0.75, 0.1) }, { P(0.75, 0.15), P(-0.2, 0.15) } }) },
	{ "Even", sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) }) },
	{ "Bare island", sauceOf(ring(0.6), { circle(0.55), circle(0.75) }) },
	{ "Crust only", sauceOf(ring(0.88), { circle(0.88), circle(0.9) }) },
	{ "Spill", sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7), circle(0.88) }) },
	{ "Mound", sauceOf({ P(0, 0), P(0.06, 0), P(-0.06, 0), P(0, 0.06), P(0, -0.06), P(0.04, 0.04) }, { { P(-0.15, 0), P(0.15, 0) } }) },
}
local VIEWS = {
	{ sauce = "surface", label = "Continuous surface (slice 8a, default)" },
	{ sauce = "material", label = "Discs (slice 2, before)" },
}

local function credited(field: { number }): number
	local a = 0
	for _, i in SauceCover.cells do
		a += SauceCover.credit(field[i]) * MakeSauce.CELL * MakeSauce.CELL
	end
	return a
end

local function clear()
	local old = Players.LocalPlayer.PlayerGui:FindFirstChild("SauceCompare")
	if old then
		old:Destroy()
	end
end

local function sheet(seconds: number?, size: number?): string
	clear()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SauceCompare"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer.PlayerGui
	local screen = gui.AbsoluteSize
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(58, 46, 38)
	back.BorderSizePixel = 0
	back.Parent = gui
	local phone = screen.Y < 500
	local text = if phone then 12 else 18
	local cols, rows = #RECORDS, #VIEWS
	local head = text + 8
	local cellW = screen.X / cols
	local cellH = (screen.Y - head) / rows
	local px = math.floor(math.min(size or screen.Y / 2, cellW - 8, cellH - 2 * (text + 4) - 6))
	local S = G.shape(0.95, 0.95, 0)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, head)
	title.Font = Enum.Font.GothamBold
	title.TextSize = text
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = string.format("SAUCE: same records, two renderers (%s)", if seconds then string.format("%.0f s in the oven", seconds) else "raw")
	title.Parent = back
	local lines = { title.Text, string.format("screen %dx%d, pizza %d px", screen.X, screen.Y, px) }
	for r, v in VIEWS do
		local rowLabel = Instance.new("TextLabel")
		rowLabel.BackgroundTransparency = 1
		rowLabel.Position = UDim2.fromOffset(0, math.floor(head + (r - 1) * cellH))
		rowLabel.Size = UDim2.new(1, 0, 0, text + 4)
		rowLabel.Font = Enum.Font.GothamMedium
		rowLabel.TextSize = text
		rowLabel.TextColor3 = Color3.fromRGB(255, 226, 170)
		rowLabel.Text = v.label
		rowLabel.Parent = back
		for c, rec in RECORDS do
			local name, sauce = rec[1], rec[2]
			local field = MakeSauce.replay(sauce)
			local grade = MakeSauce.grade(sauce)
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromOffset(px, px)
			holder.Position = UDim2.fromOffset(math.floor((c - 0.5) * cellW - px / 2), math.floor(head + (r - 1) * cellH + text + 6))
			holder.Parent = back
			local food = MakeLayers.new(holder, 1, { sauce = v.sauce })
			food:place(px / 2, px / 2, px, S, 1)
			food:dough(true, seconds)
			food:bake(seconds)
			food:sauce(field, sauce.actions)
			local info = food:sauceInfo()
			local caption = Instance.new("TextLabel")
			caption.BackgroundTransparency = 1
			caption.Position = UDim2.fromOffset(math.floor((c - 1) * cellW), math.floor(head + (r - 1) * cellH + text + 8 + px))
			caption.Size = UDim2.fromOffset(cellW, text + 2)
			caption.Font = Enum.Font.Gotham
			caption.TextSize = text
			caption.TextColor3 = Color3.new(1, 1, 1)
			if phone then
				caption.TextScaled = true
				local limit = Instance.new("UITextSizeConstraint")
				limit.MaxTextSize = text
				limit.Parent = caption
			end
			caption.Text = string.format("%s: %.0f%% covered, Sauce %d", name, grade.detail.coverage * 100, grade.score)
			caption.Parent = back
			table.insert(lines, string.format("%s / %s: coverage=%.3f score=%d tiles=%d deepTiles=%s surface=%s credited=%.3f specks=%d stride=%s", v.sauce, name, grade.detail.coverage, grade.score, info.tiles, tostring(info.deepTiles), if info.drawn then string.format("%.3f", info.drawn) else "-", credited(field), info.specks, tostring(info.stride)))
		end
	end
	return table.concat(lines, "\n")
end

shared.sauceCompare = { sheet = sheet, clear = clear }
return "installed"

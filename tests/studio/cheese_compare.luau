-- Studio-only comparison sheet for slice 8a's cheese (both views are COMPARISON PROTOTYPES).
-- Run in Studio during Play, in the Client: it returns a function; call it with the bake
-- seconds to show (nil = raw) and the pizza size in px (default: the size the oven draws on this
-- screen, else a third of the screen's height). It lays a sheet over the game: one row per view
-- (the strict shared-coverage outline, then the fuller finished base, a flat-colour PLACEHOLDER
-- until Astra's art), one column per proof (CheeseProofs: even, large miss, heavy pile, 24
-- pinches each), every pizza drawn by the game's own MakeLayers top-down with the same round
-- dough, the same clean sauce and the same bake. Returns what each pizza drew (variant, the
-- map's coverage, the base and strict shares, the drawn areas, tile counts) and the Cheese grade
-- the server would record. Call it again to redraw; `clear` removes the sheet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client")
local MakeLayers = require(Client.MakeLayers)
local MakeSauce = require(Shared.MakeSauce)
local MakeCheese = require(Shared.MakeCheese)
local CheeseProofs = require(Shared.CheeseProofs)
local G = require(Shared.PrepGeometry)

-- The clean sauce of the server's debug hook (cleanSauce): three ladles, three circles.
local function cleanSauce(): any
	local actions = {}
	for k = 0, 2 do
		local a = math.pi / 2 + k * 2 * math.pi / 3
		table.insert(actions, { kind = "pour", x = 0.4 * math.cos(a), y = 0.4 * math.sin(a) })
	end
	for _, r in { 0.3, 0.5, 0.7 } do
		local points = {}
		for i = 0, 40 do
			local a = 2 * math.pi * i / 40
			table.insert(points, { x = r * math.cos(a), y = r * math.sin(a) })
		end
		table.insert(actions, { kind = "spread", points = points })
	end
	return { actions = actions }
end

local VIEWS = {
	{ view = "strict", label = "Strict shared coverage (comparison prototype)" },
	{ view = "base", label = "Fuller finished base, placeholder colour (comparison prototype)" },
}

local function clear()
	local old = Players.LocalPlayer.PlayerGui:FindFirstChild("CheeseCompare")
	if old then
		old:Destroy()
	end
end

local function ovenSize(): number?
	-- The Bake station's pizza, if it is on screen: the largest visible "Food" frame's width.
	local best = nil
	for _, d in Players.LocalPlayer.PlayerGui:GetDescendants() do
		if d:IsA("Frame") and d.Name == "Food" and d.AbsoluteSize.X > 0 then
			best = math.max(best or 0, d.AbsoluteSize.X)
		end
	end
	return best
end

local function sheet(seconds: number?, size: number?): string
	local oven = ovenSize()
	clear()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CheeseCompare"
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
	local cols, rows = #CheeseProofs.names, #VIEWS
	local head = text + 8
	local cellW = screen.X / cols
	local cellH = (screen.Y - head) / rows
	local px = size or oven or screen.Y / 3
	px = math.floor(math.min(px, cellW - 8, cellH - 2 * (text + 4) - 6))
	local sauce = cleanSauce()
	local field = MakeSauce.replay(sauce)
	local S = G.shape(0.95, 0.95, 0)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, head)
	title.Font = Enum.Font.GothamBold
	title.TextSize = text
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = string.format("COMPARISON PROTOTYPES: same 24 pinches each, same dough, sauce and bake (%s)", if seconds then string.format("%.0f s in the oven", seconds) else "raw")
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
		for c, name in CheeseProofs.names do
			local pinches = CheeseProofs.pinches(name)
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromOffset(px, px)
			holder.Position = UDim2.fromOffset(math.floor((c - 0.5) * cellW - px / 2), math.floor(head + (r - 1) * cellH + text + 6))
			holder.Parent = back
			local food = MakeLayers.new(holder, 1, { cheeseView = v.view })
			food:place(px / 2, px / 2, px, S, 1)
			food:dough(true, seconds)
			food:bake(seconds)
			food:sauce(field, sauce.actions)
			food:cheese(pinches)
			local info = food:cheeseInfo()
			-- The grade the server would record for these pinches (each its own tap).
			local strokes = {}
			for _, q in pinches do
				table.insert(strokes, { q })
			end
			local g = MakeCheese.grade({ strokes = strokes })
			local score, coverage = g.score, g.detail.coverage
			local caption = Instance.new("TextLabel")
			caption.BackgroundTransparency = 1
			caption.Position = UDim2.fromOffset(math.floor((c - 1) * cellW), math.floor(head + (r - 1) * cellH + text + 8 + px))
			caption.Size = UDim2.fromOffset(cellW, text + 2)
			caption.Font = Enum.Font.Gotham
			caption.TextSize = text
			caption.TextColor3 = Color3.new(1, 1, 1)
			caption.Text = string.format("%s: %.0f%% covered%s, Cheese %d", CheeseProofs.labels[name], coverage * 100, if info.variant and v.view == "base" then ", " .. info.variant .. " base" else "", math.floor(score + 0.5))
			caption.Parent = back
			table.insert(lines, string.format("%s / %s: variant=%s coverage=%.3f strictShare=%s baseShare=%s strictDrawn=%s baseDrawn=%s tiles=%d cheese=%d", v.view, name, tostring(info.variant), coverage, if info.strictShare then string.format("%.3f", info.strictShare) else "-", if info.baseShare then string.format("%.3f", info.baseShare) else "-", if info.strictDrawn then string.format("%.4f", info.strictDrawn) else "-", if info.baseDrawn then string.format("%.4f", info.baseDrawn) else "-", info.tiles, math.floor(score + 0.5)))
		end
	end
	return table.concat(lines, "\n")
end

return { sheet = sheet, clear = clear }

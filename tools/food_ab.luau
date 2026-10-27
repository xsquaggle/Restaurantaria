-- Same-input food A/B harness (slice 2, Astra r14): draws the comparison records with the r13
-- stamps / v1 cheese and with the r14 material / v2 cheese side by side, through the game's own
-- MakeLayers, over the prep board art. Studio only, for captures: put it in ReplicatedStorage as
-- a ModuleScript named FoodAB before Play (remove it afterwards), then from the Client datamodel:
--   local AB = require(game.ReplicatedStorage.FoodAB)
--   AB.show({ { label = ..., record = "half spread", sauce = "stamps", cheese = "v1", seconds = nil }, ... }, F, cols, title)
-- The records are the ones tests/sauce_cover_check.luau grades.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Art = require(RS.Shared.Art)
local G = require(RS.Shared.PrepGeometry)
local MakeSauce = require(RS.Shared.MakeSauce)

local AB = {}

local function P(x, y)
	return { x = x, y = y }
end
local function circle(r)
	local o = {}
	for i = 0, 40 do
		local a = 2 * math.pi * i / 40
		o[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return o
end
local function arc(r, f, t)
	local o = {}
	for i = 0, 32 do
		local a = math.rad(f + (t - f) * i / 32)
		o[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return o
end
local function slice(l, a, b)
	local o = {}
	for i = a, b do
		table.insert(o, l[i])
	end
	return o
end
local function sauceOf(pours, spreads)
	local a = {}
	for _, p in pours do
		table.insert(a, { kind = "pour", x = p.x, y = p.y })
	end
	for _, s in spreads do
		table.insert(a, { kind = "spread", points = s })
	end
	return { actions = a }
end
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local wide = circle(1.1)

AB.records = {
	["small pour"] = sauceOf({ P(0.2, -0.1) }, {}),
	["thin trace"] = sauceOf({ P(-0.5, 0.1) }, { { P(-0.6, 0.1), P(0.75, 0.1) }, { P(0.75, 0.15), P(-0.2, 0.15) } }),
	["half spread"] = sauceOf({ P(0.3, 0), P(0.45, 0.4), P(0.45, -0.4) }, { arc(0.2, -80, 80), arc(0.4, -80, 80), arc(0.6, -80, 80), arc(0.75, -80, 80) }),
	["even adequate"] = sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) }),
	["excess mound"] = sauceOf({ P(0, 0), P(0.06, 0), P(-0.06, 0), P(0, 0.06), P(0, -0.06), P(0.04, 0.04) }, { { P(-0.15, 0), P(0.15, 0) } }),
	["rim spill"] = sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7), circle(0.88) }),
	["board spill"] = sauceOf(tri, { circle(0.3), circle(0.6), circle(0.9), slice(wide, 1, 21), slice(wide, 21, 41) }),
	["undo after"] = sauceOf(tri, { circle(0.3), circle(0.5) }),
	["unmoved dollops"] = sauceOf(tri, {}),
}

-- Cheese placements: clean 24 (three rings), sparse 8, 24 clustered in one corner.
local function ring24()
	local o = {}
	for _, ring in { { 0.2, 6 }, { 0.45, 8 }, { 0.68, 10 } } do
		for k = 0, ring[2] - 1 do
			local a = 2 * math.pi * (k + 0.5 * (ring[2] % 2)) / ring[2]
			o[#o + 1] = P(ring[1] * math.cos(a), ring[1] * math.sin(a))
		end
	end
	return o
end
local sparse = {}
for k = 0, 7 do
	local a = 2 * math.pi * k / 8 + 0.3
	sparse[#sparse + 1] = P(0.45 * math.cos(a), 0.45 * math.sin(a))
end
local cluster = {}
for k = 0, 23 do
	local a = math.rad(200 + (k % 6) * 12)
	local r = 0.25 + math.floor(k / 6) * 0.13
	cluster[#cluster + 1] = P(r * math.cos(a), r * math.sin(a))
end
AB.cheeses = { clean = ring24(), sparse = sparse, clustered = cluster, none = {} }

function AB.show(specs, F, cols, title)
	local MakeLayers = require(Players.LocalPlayer.PlayerScripts:WaitForChild("Client").MakeLayers)
	local pg = Players.LocalPlayer.PlayerGui
	local old = pg:FindFirstChild("ABHarness")
	if old then
		old:Destroy()
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "ABHarness"
	sg.DisplayOrder = 1000
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = pg
	local bg = Instance.new("ImageLabel")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(236, 226, 205)
	bg.BorderSizePixel = 0
	bg.ScaleType = Enum.ScaleType.Crop
	Art.apply(bg, "surface_prep_board")
	bg.Parent = sg
	local vp = sg.AbsoluteSize
	local rows = math.ceil(#specs / cols)
	local head = if title then 22 else 0
	local cellW, cellH = vp.X / cols, (vp.Y - head) / rows
	if title then
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 0.2
		t.BackgroundColor3 = Color3.new(1, 1, 1)
		t.Size = UDim2.new(1, 0, 0, head)
		t.Text = title
		t.TextSize = 14
		t.TextScaled = vp.X < 1000
		t.Font = Enum.Font.GothamMedium
		t.TextColor3 = Color3.new(0, 0, 0)
		t.Parent = sg
	end
	local made = {}
	for k, sp in specs do
		local c, r = (k - 1) % cols, math.floor((k - 1) / cols)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(c * cellW, head + r * cellH)
		holder.Size = UDim2.fromOffset(cellW, cellH)
		holder.Parent = sg
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 0.25
		lab.BackgroundColor3 = Color3.new(1, 1, 1)
		lab.Size = UDim2.new(1, -4, 0, 16)
		lab.Position = UDim2.fromOffset(2, 1)
		lab.Text = sp.label
		lab.TextSize = 14
		lab.TextScaled = vp.X < 1000
		lab.Font = Enum.Font.GothamMedium
		lab.TextColor3 = Color3.new(0, 0, 0)
		lab.ZIndex = 50
		lab.Parent = holder
		local layers = MakeLayers.new(holder, 5, { sauce = sp.sauce, cheese = sp.cheese })
		local S = sp.S or G.shape(0.95, 0.95, 0)
		layers:place(cellW / 2, 17 + (cellH - 17) / 2, F, S, sp.flatten)
		layers:dough(true, sp.seconds)
		layers:bake(sp.seconds)
		local rec = AB.records[sp.record]
		if rec then
			layers:sauce((MakeSauce.replay(rec)), rec.actions)
		else
			layers:sauce(nil, {})
		end
		layers:cheese(AB.cheeses[sp.cheeseSet or "none"])
		made[k] = layers
	end
	AB.layers = made
	return string.format("viewport %dx%d, %d panels", vp.X, vp.Y, #specs)
end

return AB

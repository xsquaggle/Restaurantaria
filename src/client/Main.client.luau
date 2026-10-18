--!strict
-- Client bootstrap: builds the station layout for the current viewport, keeps the newest
-- server snapshot, and drives the per-frame timers (oven rings, patience) from server time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage.Shared
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local Remote = require(script.Parent.Remote)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Widgets = require(script.Parent.Widgets)
local Stations = {
	Order = require(script.Parent.Stations.Order),
	Topping = require(script.Parent.Stations.Topping),
	Bake = require(script.Parent.Stations.Bake),
	Cut = require(script.Parent.Stations.Cut),
}
local STATION_ORDER = { "Order", "Topping", "Bake", "Cut" }

local C = Theme.Colour
local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local gui = Ui.new("ScreenGui", {
	Name = "Restaurantaria",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
-- Fills the area under Roblox's top bar so the 3D world never shows behind the game.
Ui.new("ScreenGui", {
	Name = "RestaurantariaBackdrop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -1,
	Parent = player.PlayerGui,
}, { Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(140, 98, 66), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }) })

------------------------------------------------------------------------------------------
-- Shared client state and helpers handed to every station.

local ctx: any = {
	snapshot = nil,
	selectedTicket = nil,
	station = "Order",
	pending = {},
	optimistic = {},
	compact = false,
	stationSize = Vector2.zero,
	connections = {},
}

function ctx.send(action: string, args: any, done: any)
	Remote.send(action, args, done)
end

function ctx.connect(signal: RBXScriptSignal, fn: (...any) -> ())
	table.insert(ctx.connections, signal:Connect(fn))
end

function ctx.customer(snap: any, id: number): any
	for _, c in snap.customers do
		if c.id == id then
			return c
		end
	end
	return nil
end

function ctx.freeOvenSlot(snap: any): boolean
	for _, v in snap.ovens do
		if v == false then
			return true
		end
	end
	return false
end

function ctx.focusPizza(snap: any, stage: string): any
	local fallback = nil
	for _, p in snap.pizzas do
		if p.stage == stage then
			if p.ticketId == ctx.selectedTicket then
				return p
			end
			fallback = fallback or p
		end
	end
	return fallback
end

function ctx.toLocal(frame: GuiObject, position: Vector3): (number, number)
	local rel = (Vector2.new(position.X, position.Y) - frame.AbsolutePosition) / frame.AbsoluteSize
	return math.clamp(rel.X * 2 - 1, -1.6, 1.6), math.clamp(rel.Y * 2 - 1, -1.6, 1.6)
end

function ctx.addOptimistic(pizzaId: number, piece: any)
	ctx.optimistic[pizzaId] = ctx.optimistic[pizzaId] or {}
	table.insert(ctx.optimistic[pizzaId], piece)
	ctx.refresh()
end

function ctx.removeOptimistic(pizzaId: number, piece: any)
	local list = ctx.optimistic[pizzaId]
	if list then
		local i = table.find(list, piece)
		if i then
			table.remove(list, i)
		end
	end
	ctx.refresh()
end

function ctx.withOptimistic(pizza: any): any
	local list = ctx.optimistic[pizza.id]
	if not list or #list == 0 then
		return pizza
	end
	local copy = table.clone(pizza)
	copy.toppings = table.clone(pizza.toppings)
	for _, piece in list do
		table.insert(copy.toppings, piece)
	end
	return copy
end

function ctx.ovenStatus(bakeId: string, seconds: number): any
	local target = Config.Oven.targets[bakeId]
	local state = Scoring.bakeState(target, seconds)
	local progress = math.clamp(seconds / target, 0, 1)
	if state == "under" then
		return { progress = progress, colour = C.oven, text = string.format("%ds", math.ceil(target - seconds)), ready = false, alert = false }
	elseif state == "perfect" then
		return { progress = progress, colour = C.basil, text = "Ready!", ready = true, alert = true }
	elseif state == "over" then
		return { progress = 1, colour = C.tomato, text = string.format("+%ds", math.floor(seconds - target)), ready = true, alert = true }
	end
	return { progress = 1, colour = C.tomato, text = "Burnt", ready = true, alert = true }
end

------------------------------------------------------------------------------------------
-- Layout

local ui: any = nil

local function destroyLayout()
	for _, conn in ctx.connections do
		conn:Disconnect()
	end
	ctx.connections = {}
	Ui.clear(gui)
	ui = nil
end

local function badge(parent: GuiObject, size: number): TextLabel
	local b = Ui.text({
		Text = "",
		FontFace = Theme.Font.bodyBold,
		TextColor3 = C.white,
		TextSize = math.max(14, math.floor(size * 0.62)),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = C.tomato,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
		Visible = false,
		Parent = parent,
	})
	Ui.round().Parent = b
	Ui.stroke(C.ink, 2).Parent = b
	return b
end

local function buildLayout()
	destroyLayout()
	local size = gui.AbsoluteSize
	local compact = size.Y < 520
	ctx.compact = compact
	local navH = if compact then 64 else 96
	local railH = if compact then 88 else 140
	local ovenW = if compact then 156 else 250
	ctx.stationSize = Vector2.new(size.X, size.Y - railH - navH)

	local root = Ui.new("Frame", { Name = "Root", BackgroundColor3 = C.wall, Size = UDim2.fromScale(1, 1), Parent = gui })

	-- Ticket rail (top-left): compact summaries of open tickets.
	local rail = Ui.new("ScrollingFrame", {
		Name = "Rail",
		BackgroundColor3 = Color3.fromRGB(140, 98, 66),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -ovenW, 0, railH),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = root,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	local railEmpty = Ui.text({
		Text = "No open tickets",
		TextColor3 = C.paper,
		FontFace = Theme.Font.bodySemi,
		TextSize = if compact then 16 else 20,
		Size = UDim2.new(0, 220, 1, 0),
		Parent = rail,
	})

	-- Oven status (top-right), visible on every station. Tap to jump to the ovens.
	local ovenPanel = Ui.new("TextButton", {
		Name = "Ovens",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(92, 64, 52),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(ovenW, railH),
		Parent = root,
	})
	local ringSize = math.min(railH - (if compact then 26 else 36), ovenW / 2 - 12)
	local ovenRings = {}
	for i = 1, Config.Oven.slots do
		local ring = Widgets.ring(ringSize)
		ring.frame.AnchorPoint = Vector2.new(0.5, 0)
		ring.frame.Position = UDim2.new((i - 0.5) / Config.Oven.slots, 0, 0, 4)
		ring.frame.Parent = ovenPanel
		local label = Ui.text({
			Text = "Oven " .. i,
			FontFace = Theme.Font.bodySemi,
			TextColor3 = C.paper,
			TextSize = if compact then 14 else 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new((i - 0.5) / Config.Oven.slots, 0, 1, -2),
			Size = UDim2.new(0.5, 0, 0, if compact then 18 else 24),
			Parent = ovenPanel,
		})
		ovenRings[i] = { ring = ring, label = label }
	end
	ovenPanel.Activated:Connect(function()
		ctx.switchTo("Bake")
	end)

	-- Stations
	local stationArea = Ui.new("Frame", {
		Name = "Stations",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, railH),
		Size = UDim2.new(1, 0, 1, -(railH + navH)),
		Parent = root,
	})
	local stations = {}
	for _, name in STATION_ORDER do
		local holder = Ui.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = stationArea })
		stations[name] = Stations[name].new(ctx, holder)
		stations[name].holder = holder
	end

	-- Navigation: proof backplate with four independent hit regions and live badges.
	local nav = Ui.new("Frame", {
		Name = "Nav",
		BackgroundColor3 = Color3.fromRGB(140, 98, 66),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, navH),
		Parent = root,
	})
	local barH = navH - 8
	local barW = math.min(size.X - 16, barH * Assets.Meta.tabBarAspect)
	barH = barW / Assets.Meta.tabBarAspect
	local bar = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(barW, barH),
		Parent = nav,
	})
	local barId = Assets.get("ui_tabBar_idle")
	if barId then
		Ui.new("ImageLabel", { BackgroundTransparency = 1, Image = barId, Size = UDim2.fromScale(1, 1), Parent = bar })
	else
		Ui.new("Frame", { BackgroundColor3 = C.paper, Size = UDim2.fromScale(1, 1), Parent = bar }, { Ui.corner(14), Ui.stroke(C.ink, 3) })
		for i = 1, 3 do
			Ui.new("Frame", { BackgroundColor3 = C.ink, BorderSizePixel = 0, Position = UDim2.new(i / 4, -1, 0.1, 0), Size = UDim2.new(0, 2, 0.8, 0), Parent = bar })
		end
	end
	local tabs = {}
	local tabNames = { Order = "Order", Topping = "Topping", Bake = "Bake", Cut = "Cut" }
	for i, name in STATION_ORDER do
		local hit = Ui.new("TextButton", {
			Name = name .. "Tab",
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((i - 1) / 4, 0),
			Size = UDim2.fromScale(0.25, 1),
			ZIndex = 3,
			Parent = bar,
		})
		local label = Ui.text({
			Text = tabNames[name],
			FontFace = Theme.Font.bodySemi,
			TextSize = if compact then 18 else 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(0.8, 0.6),
			Position = UDim2.fromScale(0.08, 0.16),
			ZIndex = 4,
			Parent = hit,
		})
		local indicator = Ui.new("Frame", {
			BackgroundColor3 = C.action,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.new(0.5, 0, 0, if compact then 4 else 6),
			ZIndex = 4,
			Visible = false,
			Parent = hit,
		}, { Ui.round() })
		local glow = Ui.new("Frame", {
			BackgroundColor3 = C.action,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.78),
			ZIndex = 2,
			Parent = hit,
		}, { Ui.corner(12) })
		local b = badge(hit, math.max(18, barH * 0.34))
		b.Position = UDim2.fromScale(0.88, 0.28)
		hit.Activated:Connect(function()
			ctx.switchTo(name)
		end)
		tabs[name] = { label = label, indicator = indicator, badge = b, glow = glow }
	end

	-- Status banner for save problems, and the result toast area.
	local banner = Ui.text({
		Name = "SaveBanner",
		Text = "",
		Visible = false,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = C.paper,
		FontFace = Theme.Font.bodySemi,
		TextSize = if compact then 14 else 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(0, math.max(120, (size.X - barW) / 2 - 16), 1, -12),
		ZIndex = 8,
		Parent = nav,
	})
	Ui.corner(8).Parent = banner
	local toastHolder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -(navH + 6)),
		Size = UDim2.fromOffset(if compact then 300 else 380, if compact then 150 else 190),
		ZIndex = 9,
		Parent = root,
	})
	local summary = Ui.new("Frame", {
		Name = "Summary",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})

	ui = {
		root = root,
		rail = rail,
		railEmpty = railEmpty,
		railCards = {},
		ovenRings = ovenRings,
		stations = stations,
		tabs = tabs,
		banner = banner,
		toastHolder = toastHolder,
		summary = summary,
		summaryShift = nil,
	}
	ctx.switchTo(ctx.station, true)
end

------------------------------------------------------------------------------------------
-- Behaviour

function ctx.switchTo(name: string, instant: boolean?)
	if not ui then
		return
	end
	local changed = ctx.station ~= name
	ctx.station = name
	for n, s in ui.stations do
		s.holder.Visible = n == name
	end
	for n, t in ui.tabs do
		local on = n == name
		t.indicator.Visible = on
		t.label.FontFace = if on then Theme.Font.bodyBold else Theme.Font.bodySemi
		t.label.TextColor3 = if on then C.action else C.ink
	end
	if changed and not instant then
		Widgets.tweenIn(ui.stations[name].holder, 24)
	end
	ctx.refresh()
end

-- Results of an action never move the player: the destination tab flashes instead, so a
-- second tap can't land on whatever control sits in the same spot on the next station.
function ctx.nudge(name: string)
	if ui and ctx.station ~= name then
		Widgets.flash(ui.tabs[name].glow, 0.55)
	end
end

function ctx.selectTicket(id: number?)
	ctx.selectedTicket = id
	ctx.refresh()
end

local STAGE_TEXT = { topping = "Topping", oven = "In oven", cutting = "Cutting", served = "Served" }

local function refreshRail(snap: any)
	local seen = {}
	local compact = ctx.compact
	for _, customer in snap.customers do
		if customer.status == "ordered" then
			seen[customer.id] = true
			local card = ui.railCards[customer.id]
			if not card then
				local w = if compact then 150 else 220
				local button = Ui.new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = C.paper,
					Size = UDim2.new(0, w, 1, -12),
					LayoutOrder = customer.id,
					Parent = ui.rail,
				}, { Ui.corner(8) })
				local stroke = Ui.stroke(C.ink, 2)
				stroke.Parent = button
				local recipe = Recipes.ById[customer.order.recipe]
				local title = Ui.text({
					Text = Recipes.Cast[customer.cast].name .. " · " .. recipe.name,
					FontFace = Theme.Font.bodyBold,
					TextSize = 16,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(8, 4),
					Size = UDim2.new(1, -16, 0, 18),
					Parent = button,
				})
				local stage = Ui.text({
					Text = "",
					FontFace = Theme.Font.body,
					TextSize = if compact then 14 else 16,
					TextColor3 = C.mutedInk,
					Position = UDim2.fromOffset(8, 22),
					Size = UDim2.new(1, -16, 0, 18),
					Parent = button,
				})
				local meter = Widgets.patience()
				local aspect = meter.frame:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
				aspect.DominantAxis = Enum.DominantAxis.Height
				meter.frame.AnchorPoint = Vector2.new(0.5, 1)
				meter.frame.Position = UDim2.new(0.5, 0, 1, -4)
				meter.frame.Size = UDim2.new(1, -8, 1, -46)
				meter.frame.Parent = button
				button.Activated:Connect(function()
					ctx.selectTicket(customer.id)
				end)
				card = { button = button, stroke = stroke, stage = stage, meter = meter, title = title }
				ui.railCards[customer.id] = card
			end
			card.customer = customer
			local pizza = nil
			for _, p in snap.pizzas do
				if p.id == customer.pizzaId then
					pizza = p
				end
			end
			card.stage.Text = if pizza then (STAGE_TEXT[pizza.stage] .. (if pizza.slot then " " .. pizza.slot else "")) else ""
			local selected = customer.id == ctx.selectedTicket
			card.stroke.Color = if selected then C.action else C.ink
			card.stroke.Thickness = if selected then 4 else 2
		end
	end
	for id, card in ui.railCards do
		if not seen[id] then
			card.button:Destroy()
			ui.railCards[id] = nil
		end
	end
	ui.railEmpty.Visible = next(ui.railCards) == nil
end

local function refreshBadges(snap: any)
	local counts = { Order = 0, Topping = 0, Bake = 0, Cut = 0 }
	for _, c in snap.customers do
		if c.status == "waiting" then
			counts.Order += 1
		end
	end
	for _, p in snap.pizzas do
		if p.stage == "topping" then
			counts.Topping += 1
		elseif p.stage == "oven" then
			counts.Bake += 1
		elseif p.stage == "cutting" then
			counts.Cut += 1
		end
	end
	for name, t in ui.tabs do
		t.badge.Visible = counts[name] > 0
		t.badge.Text = tostring(counts[name])
	end
end

local function refreshSummary(snap: any)
	local summary = ui.summary
	summary.Visible = snap.finished == true
	if not snap.finished or ui.summaryShift == snap.shiftId then
		return
	end
	ui.summaryShift = snap.shiftId
	Ui.clear(summary)
	local card = Ui.new("Frame", {
		BackgroundColor3 = C.paper,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if ctx.compact then 420 else 560, if ctx.compact then 300 else 400),
		ZIndex = 21,
		Parent = summary,
	}, { Ui.corner(24), Ui.stroke(C.ink, 3) })
	local profile = snap.profile or {}
	local lines = {
		string.format("Tips this shift: %d", snap.tips),
		string.format("Experience: +%d", snap.xp),
		string.format("Rank %d · %d shifts completed", profile.rank or 1, profile.shiftsCompleted or 0),
		if snap.saved then "Progress saved" else ("Not saved: " .. tostring(snap.saveMessage or profile.message or "unknown")),
	}
	Ui.text({
		Text = "Shift complete",
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 28 else 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 12),
		ZIndex = 22,
		Parent = card,
	})
	Ui.text({
		Text = table.concat(lines, "\n"),
		FontFace = Theme.Font.body,
		TextSize = if ctx.compact then 18 else 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 24, 0, 72),
		Size = UDim2.new(1, -48, 0.5, 0),
		ZIndex = 22,
		Parent = card,
	})
	local again = Widgets.button("Next shift", function()
		ctx.send("newShift", {})
	end)
	again.frame.AnchorPoint = Vector2.new(0.5, 1)
	again.frame.Position = UDim2.new(0.5, 0, 1, -16)
	again.frame.Size = UDim2.fromOffset(if ctx.compact then 200 else 260, if ctx.compact then 56 else 72)
	again.frame.ZIndex = 22
	for _, d in again.frame:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 22 + d.ZIndex
		end
	end
	again.frame.Parent = card
end

function ctx.showResult(ticketId: number)
	local snap = ctx.snapshot
	local customer = snap and ctx.customer(snap, ticketId)
	if not ui or not customer or not customer.result then
		return
	end
	local r = customer.result
	Ui.clear(ui.toastHolder)
	local toast = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.paper,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		Parent = ui.toastHolder,
	}, { Ui.corner(16), Ui.stroke(C.ink, 3) })
	local notes = {}
	for _, part in { r.topping, r.bake, r.cut, r.wait } do
		for _, n in part.notes do
			if #notes < 3 then
				table.insert(notes, n)
			end
		end
	end
	Ui.text({
		Text = string.format("%s · %d%% · +%d tips", Recipes.Cast[customer.cast].name, r.overall, r.tip),
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 18 else 24,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 28),
		ZIndex = 10,
		Parent = toast,
	})
	Ui.text({
		Text = string.format("Wait %d · Topping %d · Bake %d · Cut %d", r.wait.score, r.topping.score, r.bake.score, r.cut.score),
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 14 else 18,
		Position = UDim2.fromOffset(12, if ctx.compact then 36 else 40),
		Size = UDim2.new(1, -24, 0, 22),
		ZIndex = 10,
		Parent = toast,
	})
	Ui.text({
		Text = if #notes > 0 then table.concat(notes, "\n") else "Perfect!",
		FontFace = Theme.Font.body,
		TextSize = if ctx.compact then 14 else 16,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(12, if ctx.compact then 60 else 68),
		Size = UDim2.new(1, -24, 1, -(if ctx.compact then 64 else 72)),
		ZIndex = 10,
		Parent = toast,
	})
	toast.Activated:Connect(function()
		toast:Destroy()
	end)
	task.delay(8, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

function ctx.refresh()
	local snap = ctx.snapshot
	if not ui or not snap then
		return
	end
	refreshRail(snap)
	refreshBadges(snap)
	for _, s in ui.stations do
		s.refresh(snap)
	end
	local profile = snap.profile
	ui.banner.Visible = profile ~= nil and profile.status ~= "ok"
	if profile and profile.message then
		ui.banner.Text = profile.message
	end
	refreshSummary(snap)
end

Remote.onSnapshot = function(snap: any)
	if ctx.snapshot and snap.version <= ctx.snapshot.version then
		return
	end
	local newShift = ctx.snapshot == nil or ctx.snapshot.shiftId ~= snap.shiftId
	ctx.snapshot = snap
	if newShift then
		ctx.optimistic = {}
		ctx.pending = {}
		ctx.selectedTicket = nil
		if ui then
			buildLayout()
			return
		end
	end
	ctx.refresh()
end

Remote.onRejected = function(action: string, reason: string)
	-- Rejections are expected for races (e.g. a double tap); log for testing.
	print(string.format("[Restaurantaria] %s rejected: %s", action, reason))
end

RunService.RenderStepped:Connect(function()
	local snap = ctx.snapshot
	if not ui or not snap then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, card in ui.railCards do
		local f = Scoring.patienceFraction(card.customer.arrivedAt, now)
		card.meter:set(f, Scoring.patienceBand(f))
	end
	local alert = false
	for i, slot in ui.ovenRings do
		local pizzaId = snap.ovens[i]
		local pizza = nil
		if pizzaId then
			for _, p in snap.pizzas do
				if p.id == pizzaId then
					pizza = p
				end
			end
		end
		if pizza then
			local customer = ctx.customer(snap, pizza.ticketId)
			local status = ctx.ovenStatus(customer.order.bake, now - pizza.bakeStart)
			slot.ring:set(status.progress, status.colour, tostring(i), status.text)
			alert = alert or status.alert
		else
			slot.ring:set(0, C.oven, tostring(i), "Empty")
		end
	end
	ui.tabs.Bake.badge.BackgroundColor3 = if alert then C.tomato else C.mutedInk
	local current = ui.stations[ctx.station]
	if current then
		current.tick(now)
	end
	ui.stations.Order.tick(now)
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if ui then
		buildLayout()
	end
end)

task.wait()
buildLayout()

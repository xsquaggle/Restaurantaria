--!strict
-- Client bootstrap: builds the station layout for the current viewport, keeps the newest
-- server snapshot, and drives the per-frame timers (oven rings, patience) from server time.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
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
	-- Solo prototype: the chat window covered the ticket rail.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end)

-- The stations are laid out for landscape only.
player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local gui = Ui.new("ScreenGui", {
	Name = "Restaurantaria",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
-- Full-screen layer behind everything: station background art, or a plain fill for stations
-- whose art doesn't exist yet, so the 3D world never shows behind the game.
local backdrop = Ui.new("ScreenGui", {
	Name = "RestaurantariaBackdrop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -1,
	Parent = player.PlayerGui,
}, { Ui.new("Frame", { Name = "Fill", BackgroundColor3 = Color3.fromRGB(140, 98, 66), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }) })
-- The HUD lives in the top bar row beside Roblox's buttons, which would otherwise be dead
-- space, so the stations keep their height.
local topGui = Ui.new("ScreenGui", {
	Name = "RestaurantariaTop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 1,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player.PlayerGui,
})

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

-- The ticket the visible station is working on, so the rail highlights what's on screen.
local STATION_STAGE = { Topping = "topping", Cut = "cutting" }
function ctx.activeTicket(snap: any): number?
	local stage = STATION_STAGE[ctx.station]
	if stage then
		local p = ctx.focusPizza(snap, stage)
		return if p then p.ticketId else ctx.selectedTicket
	end
	return ctx.selectedTicket
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
--
-- Composition follows the approved screen references (art/reference/screens-v2): the HUD
-- (day, coins, ovens) sits in Roblox's top bar row, the ticket rail is a right-hand column
-- with the station's main action at its foot, the four tabs run along the bottom, and the
-- station's work surface fills the rest. A station's background art covers the whole screen
-- behind all of it.

local ui: any = nil
local backdropFill = backdrop:FindFirstChild("Fill") :: Frame

local function destroyLayout()
	for _, conn in ctx.connections do
		conn:Disconnect()
	end
	ctx.connections = {}
	Ui.clear(gui)
	Ui.clear(topGui)
	for _, child in backdrop:GetChildren() do
		if child ~= backdropFill then
			child:Destroy()
		end
	end
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

-- Full-screen background art cut into tiles (Assets.Meta.backgrounds), scaled to cover the
-- screen. Wide screens lose a little top and bottom; narrow ones lose the right edge, so
-- the props on the left stay in view.
local function background(name: string): Frame
	local meta = Assets.Meta.backgrounds[name]
	local screen = backdrop.AbsoluteSize
	local k = math.max(screen.X / meta.width, screen.Y / meta.height)
	local holder = Ui.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(math.ceil(meta.width * k), math.ceil(meta.height * k)),
		Visible = false,
		Parent = backdrop,
	})
	for r = 0, meta.rows - 1 do
		for c = 0, meta.cols - 1 do
			local tile = Ui.new("ImageLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(c / meta.cols, r / meta.rows),
				-- One extra pixel hides seams between tiles at fractional scales.
				Size = UDim2.new(1 / meta.cols, 1, 1 / meta.rows, 1),
				Parent = holder,
			})
			Art.apply(tile, string.format("%s_%d", name, r * meta.cols + c + 1))
		end
	end
	return holder
end

local function buildLayout()
	destroyLayout()
	local size = gui.AbsoluteSize
	local compact = size.Y < 520
	ctx.compact = compact
	local inset = GuiService.TopbarInset
	-- The HUD uses the free part of Roblox's top bar row; without one it takes a strip of
	-- the main area instead.
	local hudInTopbar = inset.Height >= 32 and inset.Width >= 300
	local hudH = if hudInTopbar then inset.Height else 44
	local top = if hudInTopbar then 0 else hudH
	local navH = if compact then 64 else math.clamp(math.round(size.Y * 0.11), 64, 120)
	-- Rail widths land on Astra's ticket proofs: 168 px tickets on a phone, 420 px at 1920.
	local railW = if compact then math.max(math.round(size.X * 0.27), 180) else math.clamp(math.round(size.X * 0.24), 280, 460)
	local stationH = size.Y - top - navH
	-- Phones run the rail down beside the tab bar (which centres under the station) so the
	-- ticket has room for its requirement icons; wide screens keep the full-width tab row.
	local railH = if compact then size.Y - top else stationH
	ctx.stationSize = Vector2.new(size.X - railW, stationH)

	local root = Ui.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })

	local backgrounds = {}
	for _, name in STATION_ORDER do
		local art = Stations[name].background
		if art then
			backgrounds[name] = background(art)
		end
	end

	-- HUD: day and coins on the left, the two ovens on the right. Tapping an oven opens Bake.
	local hud = Ui.new("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Position = if hudInTopbar then UDim2.fromOffset(inset.Min.X, inset.Min.Y) else UDim2.fromOffset(0, 0),
		Size = if hudInTopbar then UDim2.fromOffset(inset.Width, inset.Height) else UDim2.new(1, 0, 0, hudH),
		Parent = if hudInTopbar then topGui else root,
	})
	-- Left group: day and coins in Astra's HUD pills (240x44, phone 120x36), then the save
	-- warning when there is one, packed in a row so nothing overlaps whatever the width.
	local pillH = math.min(if compact then 36 else 44, hudH - 4)
	local pillMinW = math.round(pillH * (if compact then 120 / 36 else 240 / 44))
	local pillScale = pillH / Assets.Meta.hudPill.height
	-- Live content stays inside the pill's drawn safe area (96 px of 640 at each end).
	local pillInset = math.round(Assets.Meta.hudPill.inset * pillScale)
	local pillText = if compact then 16 else 22
	local left = Ui.new("Frame", { Name = "Left", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = hud })
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, if compact then 8 else 12),
		Parent = left,
	})
	local function pill(name: string, order: number): TextLabel
		local holder = Ui.new("ImageLabel", {
			Name = name,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Assets.Meta.hudPill.slice,
			SliceScale = pillScale,
			Size = UDim2.fromOffset(pillMinW, pillH),
			LayoutOrder = order,
			Parent = left,
		})
		Art.apply(holder, "ui_hud_pill")
		local text = Ui.text({
			Name = "Text",
			FontFace = Theme.Font.display,
			TextSize = pillText,
			TextColor3 = C.labelStroke,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		})
		-- The pill grows (its middle stretches) when the text needs more room.
		text:GetPropertyChangedSignal("TextBounds"):Connect(function()
			holder.Size = UDim2.fromOffset(math.max(pillMinW, text.TextBounds.X + pillInset * 2), pillH)
		end)
		return text
	end
	local day = pill("Day", 1)
	day.Text = "Day 1"
	local coins = pill("Coins", 2)
	coins.Text = "0 coins"
	local banner = Ui.text({
		Name = "SaveBanner",
		Text = "",
		Visible = false,
		FontFace = Theme.Font.bodySemi,
		TextSize = 14,
		TextColor3 = C.mutedInk,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = left,
	})
	local ringSize = hudH - 6
	-- On phones the oven labels drop to the 16 px floor so the pills and the save warning
	-- still fit beside the ovens.
	local ovenW = 2 * (ringSize + (if compact then 50 else 64)) + 12
	local ovenPanel = Ui.new("TextButton", {
		Name = "Ovens",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		Size = UDim2.new(0, ovenW, 1, 0),
		Parent = hud,
	})
	local ovenRings = {}
	for i = 1, Config.Oven.slots do
		local cell = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((i - 1) / Config.Oven.slots, 0),
			Size = UDim2.fromScale(1 / Config.Oven.slots, 1),
			Parent = ovenPanel,
		})
		local ring = Widgets.ring(ringSize)
		ring.frame.AnchorPoint = Vector2.new(0, 0.5)
		ring.frame.Position = UDim2.fromScale(0, 0.5)
		ring.frame.Parent = cell
		local label = Ui.text({
			Text = "Empty",
			FontFace = Theme.Font.display,
			TextSize = if compact then 16 else math.clamp(math.floor(hudH * 0.36), 12, 22),
			TextWrapped = false,
			Position = UDim2.fromOffset(ringSize + 4, 0),
			Size = UDim2.new(1, -(ringSize + 4), 1, 0),
			Parent = cell,
		})
		Ui.new("UIStroke", { Color = C.paper, Thickness = 2, Parent = label })
		ovenRings[i] = { ring = ring, label = label }
	end
	ovenPanel.Activated:Connect(function()
		ctx.switchTo("Bake")
	end)

	-- Stations: each fills the work surface left of the rail.
	local stationArea = Ui.new("Frame", {
		Name = "Stations",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.fromOffset(ctx.stationSize.X, stationH),
		Parent = root,
	})

	-- Rail: active ticket, the other open tickets as tabs, then the station's main action.
	local rail = Ui.new("Frame", {
		Name = "Rail",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, top),
		Size = UDim2.fromOffset(railW, railH),
		Parent = root,
	})
	local panel = Ui.new("ImageLabel", { Name = "Panel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = rail })
	Art.apply(panel, "ui_rail_panel")
	local pad = if compact then 6 else math.clamp(math.round(railW * 0.045), 12, 20)
	local gap = if compact then 4 else 8
	-- Phones keep the 48 px touch floor by putting the waiting tabs side by side.
	local actionH = if compact then 48 else math.clamp(math.round(railH * 0.121), 56, 110)
	-- Phone tabs are two lines (face and number, then the toppings), still two to a row.
	local tabH = if compact then 60 else math.clamp(math.round(railH * 0.085), 44, 72)
	local tabsN = Config.Shift.maxActiveTickets - 1
	local tabRows = if compact then math.ceil(tabsN / 2) else tabsN
	local ticketH = railH - pad * 2 - actionH - gap - tabRows * (tabH + gap)
	local ticket = Widgets.railTicket(Vector2.new(railW - pad * 2, ticketH), compact)
	ticket.frame.Position = UDim2.fromOffset(pad, pad)
	ticket.frame.Parent = rail
	local railEmpty = Ui.text({
		Text = "No open tickets",
		FontFace = Theme.Font.display,
		TextSize = if compact then 16 else 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(railW - pad * 2, ticketH),
		Parent = rail,
	})
	local tabList = Ui.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, pad + ticketH + gap),
		Size = UDim2.fromOffset(railW - pad * 2, tabRows * (tabH + gap)),
		Parent = rail,
	}, {
		if compact
			then Ui.new("UIGridLayout", { CellPadding = UDim2.fromOffset(gap, gap), CellSize = UDim2.new(0.5, -gap / 2, 0, tabH), SortOrder = Enum.SortOrder.LayoutOrder })
			else Ui.new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local actionArea = Ui.new("Frame", {
		Name = "Action",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, pad, 1, -pad),
		Size = UDim2.new(1, -pad * 2, 0, actionH),
		Parent = rail,
	})
	local actions = {}
	function ctx.actionHost(name: string): Frame
		if not actions[name] then
			actions[name] = Ui.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = actionArea })
		end
		return actions[name]
	end

	local stations = {}
	for _, name in STATION_ORDER do
		local holder = Ui.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = stationArea })
		stations[name] = Stations[name].new(ctx, holder)
		stations[name].holder = holder
	end

	-- Navigation: proof backplate with four independent hit regions and live badges.
	local nav = Ui.new("Frame", {
		Name = "Nav",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = if compact then UDim2.fromOffset(ctx.stationSize.X, navH) else UDim2.new(1, 0, 0, navH),
		Parent = root,
	})
	local barH = navH - 8
	local barW = math.min((if compact then ctx.stationSize.X else size.X) - 16, barH * Assets.Meta.tabBarAspect)
	barH = barW / Assets.Meta.tabBarAspect
	local bar = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(barW, barH),
		Parent = nav,
	})
	Art.apply(Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bar }), "ui_tabBar_idle")
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
			FontFace = Theme.Font.display,
			TextSize = if compact then 18 else math.clamp(math.floor(barH * 0.34), 18, 30),
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
		-- While the V1 bar is in use its badge sockets are part of the art: each count badge
		-- sits exactly on its socket, sized to its ring, so the two read as one circle.
		local socket = Assets.Meta.tabBarSockets
		local b = badge(bar, barH * socket.d - 4)
		b.Position = UDim2.fromScale(socket.x[i], socket.y)
		hit.Activated:Connect(function()
			ctx.switchTo(name)
		end)
		tabs[name] = { label = label, indicator = indicator, badge = b, glow = glow }
	end

	-- Results appear top-centre over the work surface and never take input, so they can't
	-- cover or swallow a tap meant for a button or the pizza.
	local toastHolder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(ctx.stationSize.X / 2, top + 8),
		Size = UDim2.fromOffset(math.min(if compact then 340 else 440, ctx.stationSize.X - 32), 0),
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
		day = day,
		coins = coins,
		ticket = ticket,
		railEmpty = railEmpty,
		tabList = tabList,
		tabH = tabH,
		tabW = if compact then (railW - pad * 2 - gap) / 2 else railW - pad * 2,
		railTabs = {},
		actions = actions,
		backgrounds = backgrounds,
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
	for n, f in ui.backgrounds do
		f.Visible = n == name
	end
	for n, f in ui.actions do
		f.Visible = n == name
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

local function refreshRail(snap: any)
	-- The big ticket is whatever the visible station is working on (or the selected ticket);
	-- every other open ticket is a tab underneath it.
	local active = ctx.activeTicket(snap)
	local open = {}
	for _, customer in snap.customers do
		if customer.status == "ordered" then
			table.insert(open, customer)
		end
	end
	table.sort(open, function(a, b)
		return a.id < b.id
	end)
	local shown = nil
	for _, c in open do
		if c.id == active then
			shown = c
		end
	end
	shown = shown or open[1]
	ui.ticket:set(shown)
	ui.ticket.frame.Visible = shown ~= nil
	ui.railEmpty.Visible = shown == nil
	local seen = {}
	for _, customer in open do
		if customer ~= shown then
			seen[customer.id] = true
			local tab = ui.railTabs[customer.id]
			if not tab then
				tab = Widgets.railTab(customer, ui.tabH, ctx.compact, ui.tabW)
				tab.button.LayoutOrder = customer.id
				tab.button.Parent = ui.tabList
				tab.button.Activated:Connect(function()
					ctx.selectTicket(customer.id)
				end)
				ui.railTabs[customer.id] = tab
			end
			tab.customer = customer
		end
	end
	for id, tab in ui.railTabs do
		if not seen[id] then
			tab.button:Destroy()
			ui.railTabs[id] = nil
		end
	end
end

local function refreshHud(snap: any)
	local profile = snap.profile or {}
	ui.day.Text = string.format("Day %d", (profile.shiftsCompleted or 0) + 1)
	local total = (profile.tips or 0) + (if snap.saved then 0 else snap.tips)
	ui.coins.Text = string.format("%d coins", total)
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
	-- Rebuilt when the save result arrives, which can be after the shift ends.
	local key = if snap.finished then string.format("%s|%s|%s", snap.shiftId, tostring(snap.saved), tostring(snap.saveMessage)) else nil
	if not snap.finished or ui.summaryShift == key then
		return
	end
	ui.summaryShift = key
	Ui.clear(summary)
	local area = ui.root.AbsoluteSize
	local card = Ui.new("Frame", {
		BackgroundColor3 = C.paper,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.min(if ctx.compact then 420 else 560, area.X - 24), math.min(if ctx.compact then 300 else 400, area.Y - 24)),
		ZIndex = 21,
		Parent = summary,
	}, { Ui.corner(24), Ui.stroke(C.ink, 3) })
	local profile = snap.profile or {}
	local lines = {
		string.format("Tips this shift: %d", snap.tips),
		string.format("Experience: +%d", snap.xp),
		string.format("Rank %d · %d shift%s completed", profile.rank or 1, profile.shiftsCompleted or 0, if profile.shiftsCompleted == 1 then "" else "s"),
		if snap.saved then "Progress saved"
			elseif snap.saveMessage == "Saving..." then "Saving..."
			else ("Not saved: " .. tostring(snap.saveMessage or profile.message or "unknown")),
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
	local notes = {}
	for _, part in { r.topping, r.bake, r.cut, r.wait } do
		for _, n in part.notes do
			if #notes < 3 then
				table.insert(notes, n)
			end
		end
	end
	local compact = ctx.compact
	local toast = Ui.new("Frame", {
		BackgroundColor3 = C.paper,
		Size = UDim2.new(1, 0, 0, (if compact then 66 else 76) + math.max(#notes, 1) * (if compact then 17 else 20)),
		ZIndex = 9,
		Parent = ui.toastHolder,
	}, { Ui.corner(16), Ui.stroke(C.ink, 3) })
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
	task.delay(Theme.Motion.toastSeconds, function()
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
	refreshHud(snap)
	refreshBadges(snap)
	for _, s in ui.stations do
		s.refresh(snap)
	end
	local profile = snap.profile
	ui.banner.Visible = profile ~= nil and profile.status ~= "ok"
	if profile and profile.message then
		ui.banner.Text = if ctx.compact then "Not saving"
			elseif profile.status == "unavailable" then "Not saving: unpublished place"
			else "Not saving: load failed"
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
	local shown = ui.ticket.customer
	if shown then
		local f = Scoring.patienceFraction(shown.arrivedAt, now)
		ui.ticket:setPatience(f, Scoring.patienceBand(f))
	end
	for _, tab in ui.railTabs do
		local f = Scoring.patienceFraction(tab.customer.arrivedAt, now)
		tab:setPatience(f, Scoring.patienceBand(f))
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
			slot.ring:set(status.progress, status.colour, tostring(i), "")
			slot.label.Text = status.text
			alert = alert or status.alert
		else
			slot.ring:set(0, C.oven, tostring(i), "")
			slot.label.Text = "Empty"
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
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
	if ui then
		buildLayout()
	end
end)

task.wait()
buildLayout()

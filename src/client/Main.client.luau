--!strict
-- Client bootstrap: builds the station layout for the current viewport, keeps the newest
-- server snapshot, and drives the per-frame timers (oven rings, patience) from server time.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Scoring = require(Shared.Scoring)
local Remote = require(script.Parent.Remote)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Widgets = require(script.Parent.Widgets)
local Tutorial = require(script.Parent.Tutorial)
local Stations = {
	Order = require(script.Parent.Stations.Order),
	Topping = require(script.Parent.Stations.Topping),
	Bake = require(script.Parent.Stations.Bake),
	Cut = require(script.Parent.Stations.Cut),
}
local STATION_ORDER = { "Order", "Topping", "Bake", "Cut" }

local C = Theme.Colour
local NAV_SLIDE = TweenInfo.new(Theme.Motion.station, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NAV_POP = TweenInfo.new(Theme.Motion.nudge, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- The empty rail's note away from Order (QA-006 copy).
local RAIL_NOTE = {
	Topping = "Go to Order to start a pizza",
	Bake = "Add toppings, then send to an oven",
	Cut = "Take a pizza from the oven to cut",
}
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
	-- Stations whose first-shift pointer is done (see Tutorial).
	learned = {},
}

function ctx.send(action: string, args: any, done: any)
	local lesson = Tutorial.Lesson[action]
	if lesson then
		ctx.learned[lesson] = true
	end
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

-- One status word per oven, the same on the HUD pill and the oven's plate, judged against
-- the ticket's requested bake: Cooking with the seconds until it is ready, Ready inside the
-- bake's perfect window, Overdone once past it, Burnt past the gauge's red line. There is no
-- unexplained "+N s": time is only ever shown as the wait until Ready.
function ctx.ovenStatus(bakeId: string, seconds: number): any
	local target = Config.Oven.targets[bakeId]
	local state = Scoring.bakeState(target, seconds)
	local progress = math.clamp(seconds / target, 0, 1)
	if state == "under" then
		local wait = math.max(1, math.ceil(target - Config.Oven.perfectWindow - seconds))
		return { progress = progress, state = "cooking", word = "Cooking", text = string.format("Cooking %ds", wait), ready = false, alert = false }
	elseif state == "perfect" then
		return { progress = progress, state = "ready", word = "Ready", text = "Ready", ready = true, alert = true }
	elseif state == "over" then
		return { progress = 1, state = "ready", word = "Overdone", text = "Overdone", ready = true, alert = true, over = true }
	end
	-- Red is kept for burnt (and errors) only.
	return { progress = 1, state = "burnt", word = "Burnt", text = "Burnt", ready = true, alert = true, burnt = true }
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

-- One count badge per tab: Astra's badge art with the live number centred on it, hidden at
-- zero. Red (alert) asks for action; teal (info) is a count that can wait.
local function badge(parent: GuiObject, size: number): ImageLabel
	local b = Ui.new("ImageLabel", {
		Name = "Badge",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
		Visible = false,
		Parent = parent,
	})
	Art.apply(b, "ui_badge_alert")
	Ui.text({
		Name = "Count",
		Text = "",
		FontFace = Theme.Font.display,
		TextColor3 = C.white,
		TextSize = math.max(14, math.floor(size * 0.56)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = b,
	})
	return b
end

-- Full-screen background art cut into tiles (Assets.Meta.backgrounds), scaled to cover the
-- screen. Wide screens lose a little top and bottom; narrow ones lose the right edge, so
-- the props on the left stay in view.
local function background(name: string): Frame
	local meta = Assets.Meta.backgrounds[name]
	-- The backdrop covers the whole viewport. Its own AbsoluteSize is stale after a resize
	-- while it is disabled (Order shows the 3D room), which left the art short of the screen
	-- edges over the brown fill (QA-004), so the size comes from the camera.
	local screen = workspace.CurrentCamera.ViewportSize
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
			-- Tiles get their art only while the station shows (see switchTo): four
			-- full-screen backgrounds at once overrun Studio's dev-art memory budget.
			tile:SetAttribute("Art", string.format("%s_%d", name, r * meta.cols + c + 1))
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
	-- The drawn bar fills 136 of its 144 px, so phones need a 74 px row (68 px bar) for the
	-- visible bar to meet the 64 px nav floor.
	local navH = if compact then 74 else math.clamp(math.round(size.Y * 0.11), 74, 120)
	-- Rail widths land on Astra's ticket proofs: 168 px tickets on a phone, 420 px at 1920.
	local railW = if compact then math.max(math.round(size.X * 0.27), 180) else math.clamp(math.round(size.X * 0.24), 280, 460)
	-- A reserved hint strip runs between the work surface and the tab bar, so tutorial
	-- instructions and status reasons never cover food, ovens, trays or controls.
	local stripH = if compact then 34 else math.clamp(math.round(size.Y * 0.05), 40, 56)
	local stationH = size.Y - top - navH - stripH
	-- Phones run the rail down beside the tab bar (which centres under the station) so the
	-- ticket has room for its requirement icons; wide screens keep the full-width tab row.
	local railH = if compact then size.Y - top else stationH + stripH
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
	-- Astra's coral HUD strip runs the full width of the top row, behind Roblox's buttons too.
	local strip = Ui.new("ImageLabel", {
		Name = "Strip",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.hudBar.slice,
		SliceScale = hudH / Assets.Meta.hudBar.height,
		Position = UDim2.fromOffset(0, if hudInTopbar then inset.Min.Y else 0),
		Size = UDim2.new(1, 0, 0, hudH),
		ZIndex = 0,
		Parent = if hudInTopbar then topGui else root,
	})
	Art.apply(strip, "ui_hud_bar")
	-- Left group: day and coins in Astra's HUD pills, then the save warning when there is one.
	-- Each pill is one row (icon, 8-10 px gap, value) padded 12-16 px inside the pill and
	-- sized from its text, so icon and value read as one object (QA-009).
	local pillH = math.min(if compact then 36 else 44, hudH - 4)
	local pillScale = pillH / Assets.Meta.hudPill.height
	local pillText = if compact then 16 else 22
	local pillIcon = if compact then 28 else 32
	local left = Ui.new("Frame", { Name = "Left", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = hud })
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, if compact then 8 else 12),
		Parent = left,
	})
	local function pill(name: string, order: number): ImageLabel
		local holder = Ui.new("ImageLabel", {
			Name = name,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Assets.Meta.hudPill.slice,
			SliceScale = pillScale,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, pillH),
			LayoutOrder = order,
			Parent = left,
		}, {
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, if compact then 12 else 16), PaddingRight = UDim.new(0, if compact then 12 else 16) }),
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, if compact then 8 else 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		Art.apply(holder, "ui_hud_pill")
		return holder
	end
	local function pillIconImage(holder: ImageLabel, iconName: string): ImageLabel
		local icon = Ui.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(pillIcon, pillIcon),
			LayoutOrder = 1,
			Parent = holder,
		}, { Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
		Art.apply(icon, iconName)
		return icon
	end
	local function pillValue(holder: ImageLabel): TextLabel
		return Ui.text({
			Name = "Text",
			FontFace = Theme.Font.display,
			TextSize = pillText,
			TextColor3 = C.labelStroke,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, pillH),
			LayoutOrder = 2,
			Parent = holder,
		})
	end
	-- Astra's sun and coin icons lead each pill; the values stay live text.
	local dayPill = pill("Day", 1)
	pillIconImage(dayPill, "icon_day")
	local day = pillValue(dayPill)
	day.Text = "Day 1"
	local coinPill = pill("Coins", 2)
	pillIconImage(coinPill, "icon_coin")
	local coins = pillValue(coinPill)
	coins.Text = if compact then "0" else "0 coins"
	-- A real save failure, in plain words, in the same pill with the alert badge (QA-012).
	local banner = pill("SaveBanner", 3)
	banner.Visible = false
	local alert = pillIconImage(banner, "ui_badge_alert")
	Ui.text({
		Name = "Mark",
		Text = "!",
		FontFace = Theme.Font.display,
		TextColor3 = C.white,
		TextSize = math.floor(pillIcon * 0.64),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Parent = alert,
	})
	local bannerText = pillValue(banner)
	local ringSize = hudH - 6
	-- Each oven is a pill with its badge and ring at the left end and the live status word.
	-- On phones the pill shows the status word alone ("Cooking", the longest) at the 16 px
	-- floor; desktop pills fit "Cooking 12s" at their 22 px cap.
	local ovenPillW = ringSize + (if compact then 82 else 124)
	local ovenGap = 8
	local ovenPanel = Ui.new("TextButton", {
		Name = "Ovens",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		Size = UDim2.new(0, 2 * ovenPillW + ovenGap, 1, 0),
		Parent = hud,
	})
	local ovenRings = {}
	for i = 1, Config.Oven.slots do
		local oven = Widgets.ovenStatus(ovenPillW, ringSize, compact)
		oven.frame.AnchorPoint = Vector2.new(0, 0.5)
		oven.frame.Position = UDim2.new(0, (i - 1) * (ovenPillW + ovenGap), 0.5, 0)
		oven.frame.Parent = ovenPanel
		ovenRings[i] = oven
	end
	-- When the left group needs the room (a long day or coin value, or the save warning on a
	-- phone), the oven pills fold to their rings: badge, number and ring fill still show each
	-- oven, and Bake shows the words. If even that is short, the save warning keeps its badge
	-- and drops its words, so nothing in the row overlaps.
	local hudW = if hudInTopbar then inset.Width else size.X
	local function fitHud()
		-- The row's width with every part showing (the warning's words counted even while they
		-- are hidden), so folding never feeds back into its own measurement.
		local hidden = if banner.Visible and not bannerText.Visible then bannerText.TextBounds.X + (if compact then 8 else 10) else 0
		local free = hudW - 8 - (left.AbsoluteSize.X + hidden) - 8 - 4
		local fold = free < 2 * ovenPillW + ovenGap
		local w = if fold then ringSize else ovenPillW
		for i, oven in ovenRings do
			oven:setFolded(fold)
			oven.frame.Position = UDim2.new(0, (i - 1) * (w + ovenGap), 0.5, 0)
		end
		ovenPanel.Size = UDim2.new(0, 2 * w + ovenGap, 1, 0)
		local words = not banner.Visible or free >= 2 * w + ovenGap
		if bannerText.Visible ~= words then
			bannerText.Visible = words
		end
	end
	left:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHud)
	bannerText:GetPropertyChangedSignal("TextBounds"):Connect(fitHud)
	task.defer(fitHud)
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

	local hintStrip = Widgets.hintStrip(ctx.stationSize.X, stripH, compact)
	hintStrip.frame.Position = UDim2.fromOffset(0, top + stationH)
	hintStrip.frame.Parent = root

	-- Rail: active ticket, the other open tickets as tabs, then the station's main action.
	local rail = Ui.new("Frame", {
		Name = "Rail",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, top),
		Size = UDim2.fromOffset(railW, railH),
		Parent = root,
	})
	local panel = Ui.new("ImageLabel", {
		Name = "Panel",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.railPanel.slice,
		SliceScale = railW / Assets.Meta.railPanel.width,
		Size = UDim2.fromScale(1, 1),
		Parent = rail,
	})
	Art.apply(panel, "ui_rail_panel")
	local pad = if compact then 6 else math.clamp(math.round(railW * 0.045), 12, 20)
	local gap = if compact then 4 else 8
	-- Phones keep the 48 px touch floor by putting the waiting tabs side by side.
	-- 56 px on phones keeps the drawn button (its art, without the shadow margin) at 48 px or more.
	local actionH = if compact then 56 else math.clamp(math.round(railH * 0.121), 56, 110)
	-- Phone tabs are two lines (face and number, then the toppings), still two to a row.
	local tabH = if compact then 60 else math.clamp(math.round(railH * 0.085), 44, 72)
	local tabsN = Config.Shift.maxActiveTickets - 1
	local tabRows = if compact then math.ceil(tabsN / 2) else tabsN
	-- Astra's mounting rail grips the active ticket's top edge. The ticket hangs a little
	-- below the rail's centre so the torn top edge of ui_ticket_top shows under the clips.
	local clipW = railW - pad * 2 + (if compact then 4 else 10)
	local clipH = math.round(clipW / Assets.Meta.clipRail.aspect)
	local drop = math.round(clipH * 0.4)
	local ticketH = railH - pad * 2 - drop - actionH - gap - tabRows * (tabH + gap)
	-- Wide screens: the ticket is only as tall as its content needs (header plus up to
	-- five requirement rows at their largest), in Astra's 420x600 proportion at most; the
	-- spare rail height goes under the waiting tabs instead of into blank paper.
	if not compact then
		ticketH = math.min(ticketH, math.round((railW - pad * 2) * 600 / 420))
	end
	local ticket = Widgets.railTicket(Vector2.new(railW - pad * 2, ticketH), compact)
	ticket.frame.Position = UDim2.fromOffset(pad, pad + drop)
	ticket.frame.Parent = rail
	local clipRail = Ui.new("ImageLabel", {
		Name = "ClipRail",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(railW / 2, pad - 2),
		Size = UDim2.fromOffset(clipW, clipH),
		ZIndex = 3,
		Parent = rail,
	})
	Art.apply(clipRail, "ui_ticket_clip_rail")
	-- With no open ticket, a short cream note says what to do next, right above the action
	-- (QA-006): 88% of the rail's inner width, over the footer, which stays put. The frames
	-- sit 11 / 8 px apart so the drawn paper and button art (both have transparent margins)
	-- end up 12-16 px apart, measured at the paper's lowest tooth.
	local railNote = Widgets.railNote(math.round((railW - pad * 2) * 0.88), compact, if compact then 104 else 160)
	railNote.frame.AnchorPoint = Vector2.new(0.5, 1)
	railNote.frame.Position = UDim2.fromOffset(railW / 2, railH - pad - actionH - (if compact then 11 else 8))
	railNote.frame.Visible = false
	railNote.frame.Parent = rail
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
	-- The tabs hang under the active ticket, whose height follows its content on desktop.
	ticket.frame:GetPropertyChangedSignal("Size"):Connect(function()
		tabList.Position = UDim2.fromOffset(pad, pad + drop + ticket.frame.Size.Y.Offset + gap)
	end)
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

	-- Navigation: Astra's continuous ivory bar, one coral pill that slides to the selected
	-- tab, an icon and live label per tab and a single count badge.
	local nav = Ui.new("Frame", {
		Name = "Nav",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = if compact then UDim2.fromOffset(ctx.stationSize.X, navH) else UDim2.new(1, 0, 0, navH),
		Parent = root,
	})
	local barH = navH - (if compact then 6 else 10)
	local barW = math.min((if compact then ctx.stationSize.X else size.X) - (if compact then 8 else 24), if compact then 99999 else barH * 14)
	local bar = Ui.new("ImageLabel", {
		Name = "Frame",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.navBar.slice,
		SliceScale = barH / Assets.Meta.navBar.height,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(barW, barH),
		Parent = nav,
	})
	Art.apply(bar, "ui_nav_bar")
	local edge = math.round(barH * 0.12)
	local tabW = (barW - edge * 2) / 4
	local selH = math.round(barH * 0.78)
	local selected = Ui.new("ImageLabel", {
		Name = "Selected",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.navSelected.slice,
		SliceScale = selH / Assets.Meta.navSelected.height,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(tabW - edge, selH),
		ZIndex = 2,
		Parent = bar,
	})
	Art.apply(selected, "ui_nav_tab_selected")
	local iconNames = {}
	for _, name in STATION_ORDER do
		table.insert(iconNames, "icon_nav_" .. name:lower() .. "_idle")
		table.insert(iconNames, "icon_nav_" .. name:lower() .. "_selected")
	end
	Art.preload(iconNames)
	local tabs = {}
	local labelSize = if compact then 16 else math.clamp(math.floor(barH * 0.3), 18, 30)
	local iconSize = math.round(barH * (if compact then 0.5 else 0.56))
	local badgeSize = if compact then 22 else math.clamp(math.round(barH * 0.32), 24, 36)
	for i, name in STATION_ORDER do
		local centreX = edge + tabW * (i - 0.5)
		local hit = Ui.new("TextButton", {
			Name = name .. "Tab",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(edge + tabW * (i - 1), 0),
			Size = UDim2.new(0, tabW, 1, 0),
			ZIndex = 5,
			Parent = bar,
		})
		local content = Ui.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centreX, barH / 2),
			Size = UDim2.fromOffset(tabW, barH),
			ZIndex = 3,
			Parent = bar,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, if compact then 4 else 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local pop = Ui.new("UIScale", { Scale = 1, Parent = content })
		local icon = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(iconSize, iconSize),
			LayoutOrder = 1,
			ZIndex = 3,
			Parent = content,
		})
		local label = Ui.text({
			Text = name,
			FontFace = Theme.Font.display,
			TextSize = labelSize,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, labelSize + 4),
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = content,
		})
		local stroke = Ui.new("UIStroke", { Color = C.labelStroke, Thickness = if compact then 1 else 2, Enabled = false, Parent = label })
		-- The badge sits at the tab's top right, over the bar's upper edge.
		local b = badge(bar, badgeSize)
		b.Position = UDim2.fromOffset(edge + tabW * i - badgeSize * 0.7, badgeSize * 0.42)
		hit.Activated:Connect(function()
			ctx.switchTo(name)
		end)
		tabs[name] = { label = label, icon = icon, stroke = stroke, badge = b, pop = pop, x = centreX }
	end
	local navSelected = selected

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
	-- End-of-shift modal: an invisible button takes the input; Astra's scrim image dims the
	-- game behind the summary panel.
	local summary = Ui.new("TextButton", {
		Name = "Summary",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})

	-- The shift summary dims and blocks the HUD too, so the modal covers the whole screen.
	-- Only needed when the HUD lives in the top bar's own ScreenGui, which draws above the
	-- root; there it covers the HUD band alone so the summary card below stays undimmed. In
	-- the root, the summary's own scrim already covers the HUD.
	local hudScrim = Ui.new("ImageButton", {
		Name = "HudScrim",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ImageTransparency = 0.55,
		Size = UDim2.new(1, 0, 0, if hudInTopbar then inset.Min.Y + hudH else 0),
		Visible = false,
		ZIndex = 50,
		Parent = if hudInTopbar then topGui else nil,
	})
	Art.apply(hudScrim, "ui_scrim")

	local tutorial = Tutorial.new(root, compact, bar)

	ui = {
		tutorial = tutorial,
		hintStrip = hintStrip,
		hudScrim = hudScrim,
		root = root,
		day = day,
		coins = coins,
		ticket = ticket,
		clipRail = clipRail,
		railNote = railNote,
		tabList = tabList,
		tabH = tabH,
		tabW = if compact then (railW - pad * 2 - gap) / 2 else railW - pad * 2,
		railTabs = {},
		actions = actions,
		backgrounds = backgrounds,
		ovenRings = ovenRings,
		stations = stations,
		tabs = tabs,
		navSelected = navSelected,
		navBarH = barH,
		banner = banner,
		bannerText = bannerText,
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
		if s.setActive then
			s.setActive(n == name)
		end
	end
	-- A station that shows the 3D world (the hybrid Order counter) needs the backdrop gone.
	backdrop.Enabled = not ui.stations[name].world3D
	-- Studio dev art: images freed while this station was hidden come back now.
	Art.restore(ui.stations[name].holder)
	for n, f in ui.backgrounds do
		f.Visible = n == name
		if n ~= name then
			for _, tile in f:GetChildren() do
				Art.release(tile :: ImageLabel)
			end
		end
	end
	local shownBackground = ui.backgrounds[name]
	if shownBackground then
		for _, tile in shownBackground:GetChildren() do
			Art.apply(tile :: ImageLabel, tile:GetAttribute("Art") :: string)
		end
	end
	for n, f in ui.actions do
		f.Visible = n == name
	end
	for n, t in ui.tabs do
		local on = n == name
		Art.apply(t.icon, string.format("icon_nav_%s_%s", n:lower(), if on then "selected" else "idle"))
		t.label.TextColor3 = if on then C.label else C.ink
		t.stroke.Enabled = on
		if on then
			local target = UDim2.fromOffset(t.x, ui.navBarH / 2)
			if instant or not changed then
				ui.navSelected.Position = target
			else
				TweenService:Create(ui.navSelected, NAV_SLIDE, { Position = target }):Play()
			end
		end
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
		-- The destination tab's icon and label pop once.
		local pop = ui.tabs[name].pop
		pop.Scale = 1.18
		TweenService:Create(pop, NAV_POP, { Scale = 1 }):Play()
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
	ui.clipRail.Visible = shown ~= nil
	-- The empty rail's note: on Order, take an order (or nobody is waiting); elsewhere, what
	-- comes first. Exactly one instruction shows, so the hint strip stays empty meanwhile.
	ctx.railEmpty = shown == nil
	ui.railNote.frame.Visible = ctx.railEmpty
	if ctx.railEmpty then
		local waiting = 0
		for _, customer in snap.customers do
			if customer.status == "waiting" then
				waiting += 1
			end
		end
		if ctx.station == "Order" then
			if waiting > 0 then
				ui.railNote:set("Take an order", "Tap the button below.")
			else
				ui.railNote:set("No one waiting", "Check your pizzas")
			end
		else
			ui.railNote:set(nil, RAIL_NOTE[ctx.station] or "")
		end
	end
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
	ui.coins.Text = if ctx.compact then tostring(total) else string.format("%d coins", total)
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
		(t.badge:FindFirstChild("Count") :: TextLabel).Text = tostring(counts[name])
	end
end

local function refreshSummary(snap: any)
	local summary = ui.summary
	summary.Visible = snap.finished == true
	ui.hudScrim.Visible = snap.finished == true
	-- Rebuilt when the save result arrives, which can be after the shift ends.
	local key = if snap.finished then string.format("%s|%s|%s", snap.shiftId, tostring(snap.saved), tostring(snap.saveMessage)) else nil
	if not snap.finished or ui.summaryShift == key then
		return
	end
	ui.summaryShift = key
	Ui.clear(summary)
	local area = ui.root.AbsoluteSize
	local scrim = Ui.new("ImageLabel", {
		Name = "Scrim",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ImageTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = summary,
	})
	Art.apply(scrim, "ui_scrim")
	TweenService:Create(scrim, NAV_SLIDE, { ImageTransparency = 0.55 }):Play()
	local cardW = math.min(if ctx.compact then 420 else 560, area.X - 24)
	local cardH = math.min(if ctx.compact then 300 else 400, area.Y - 24)
	local card = Ui.new("ImageLabel", {
		Name = "Card",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		-- Astra's metadata candidate (QA review, diagnostics/summary-slice-override-candidate):
		-- 80 px margins so the slices clear the drawn corners, scaled by the smaller axis.
		SliceCenter = Rect.new(80, 80, 760, 520),
		SliceScale = math.min(cardW / 840, cardH / 600),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cardW, cardH),
		ZIndex = 21,
		Parent = summary,
	})
	Art.apply(card, "ui_panel_summary")
	local profile = snap.profile or {}
	-- Reward first and largest; rank and the save line are secondary.
	Ui.text({
		Text = string.format("+%d tips", snap.tips),
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 30 else 44,
		TextColor3 = C.tomato,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, if ctx.compact then 36 else 52),
		Position = UDim2.fromOffset(0, if ctx.compact then 50 else 72),
		ZIndex = 22,
		Parent = card,
	})
	local lines = {
		string.format("Experience: +%d", snap.xp),
		string.format("Rank %d · %d shift%s completed", profile.rank or 1, profile.shiftsCompleted or 0, if profile.shiftsCompleted == 1 then "" else "s"),
		if snap.saved then "Progress saved"
			elseif snap.saveMessage == "Saving..." then "Saving..."
			-- Player text only: the technical reason stays in the HUD save label.
			else "Progress not saved",
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
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 18 else 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 24, 0, if ctx.compact then 92 else 132),
		Size = UDim2.new(1, -48, 0, if ctx.compact then 80 else 100),
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
	local toast = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.card.slice,
		SliceScale = if compact then 0.5 else 0.7,
		Size = UDim2.new(1, 0, 0, (if compact then 66 else 76) + math.max(#notes, 1) * (if compact then 17 else 20)),
		ZIndex = 9,
		Parent = ui.toastHolder,
	})
	Art.apply(toast, "ui_card_result")
	Ui.text({
		Text = string.format("%s · %d%% · +%d tips", customer.label, r.overall, r.tip),
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

-- Studio-only developer overlay for save diagnostics (QA-012): outside the HUD layout, so the
-- player HUD looks exactly as it does in a published session.
local diagnostic: TextLabel? = nil
local lastDiagnostic: string? = nil
local function showDiagnostic(message: string?)
	if message ~= lastDiagnostic then
		lastDiagnostic = message
		if message then
			warn("[Save] " .. message)
		end
	end
	if not RunService:IsStudio() then
		return
	end
	if not diagnostic then
		local gui = Instance.new("ScreenGui")
		gui.Name = "RestaurantariaDevDiagnostics"
		gui.DisplayOrder = 100
		gui.ResetOnSpawn = false
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local label = Instance.new("TextLabel")
		label.Name = "Save"
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.new(0, 8, 1, -8)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.4
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 12
		label.Font = Enum.Font.Code
		label.Parent = gui
		diagnostic = label
	end
	local label = diagnostic :: TextLabel
	label.Visible = message ~= nil
	label.Text = if message then " DEV (Studio only): " .. message .. " " else ""
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
	-- Players only hear about a real load failure, in plain words. "unavailable" means the
	-- place has no data store (unpublished, or Studio without API access): a developer
	-- condition, shown in the Studio-only diagnostics overlay instead of the HUD.
	ui.banner.Visible = profile ~= nil and profile.status == "failed"
	if ui.banner.Visible then
		ui.bannerText.Text = if ctx.compact then "Can't save" else "Progress can't save right now"
	end
	showDiagnostic(if profile and profile.status ~= "ok" then profile.message else nil)
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
			slot:set(status.progress, status.state, tostring(i), if ctx.compact then status.word else status.text)
			alert = alert or status.alert
		else
			slot:set(0, "idle", tostring(i), "Empty")
		end
	end
	-- Bake's count is teal while pizzas just bake, red once one needs taking out.
	if alert ~= ui.bakeAlert then
		ui.bakeAlert = alert
		Art.apply(ui.tabs.Bake.badge, if alert then "ui_badge_alert" else "ui_badge_info")
	end
	local current = ui.stations[ctx.station]
	if current then
		current.tick(now)
	end
	-- The pointer runs on the first shift only, until each station's action has been done.
	-- (Studio captures can hide it with the HideTutorial attribute on the screen gui.)
	local firstShift = ((snap.profile or {}).shiftsCompleted or 0) == 0 and not gui:GetAttribute("HideTutorial")
	local hint = nil
	if firstShift and not snap.finished and current and current.hint and not ctx.learned[ctx.station] then
		hint = current.hint(snap, now)
	end
	ui.tutorial.show(hint, now)
	-- The strip carries the tutorial line while there is one, otherwise the station's status
	-- reason (why its action is unavailable and what to do next).
	local status = if current and current.status and not snap.finished then current.status(snap, now) else nil
	local line = if hint and hint.text ~= "" then hint else status
	if ctx.railEmpty then
		line = nil
	end
	ui.hintStrip:set(line and line.text, line and line.legend)
	-- Anything shown again (the strip, the summary, a station) gets back art freed while hidden.
	Art.restore(Players.LocalPlayer.PlayerGui)
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

--!strict
-- Order station: waiting customers stand at the counter. Tap one to select, then take the
-- order from the rail; the selected one stands out while the others wait. With the 3D
-- counter they are native avatars (OrderCrowd) that walk in and out, each with a name tag
-- over their head that grows a little when chosen; without it they are the generated
-- characters (G10), who step forward when chosen and whose expression follows their
-- patience band.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)
local OrderRoom = require(Parent.OrderRoom)
local OrderCrowd = require(Parent.OrderCrowd)

local C = Theme.Colour
local Order = {}

-- Character frames are waist-up drawings, 0.68 (Marta) to 0.81 (Ines) as wide as they are
-- tall; each is fitted into a box of the widest shape so all stand at the same height.
local FIGURE_ASPECT = 0.81
-- Customers the counter is laid out for; more still fit, just closer together.
local ROOM_FOR = 4
local COUNTER_TOP = 0.72
local STEP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Name tags over the 3D customers: the gap above the head box, and the tag's size.
local TAG_GAP = 8
local TAG = {
	compact = { width = 120, pad = 6, text = 16, line = 18, meter = 84 },
	wide = { width = 210, pad = 10, text = 26, line = 30, meter = 160 },
}

-- Full-screen art behind the station (Assets.Meta.backgrounds). The 3D counter view hides
-- it (Main turns the backdrop off for world3D stations) and hangs the same art in the world.
Order.background = "bg_order"
local room3D = OrderRoom.available()

function Order.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Order", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
	local room = if room3D then OrderRoom.new(ctx, container) else nil
	if not room then
		-- The generated counter front, its top edge on COUNTER_TOP, hides the customers' waists.
		local cm = Assets.Meta.orderCounter
		local counterW = area.X + 24
		local counterH = counterW / cm.aspect
		local counter = Ui.new("ImageLabel", {
			Name = "Counter",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Stretch,
			Position = UDim2.fromOffset(-12, area.Y * COUNTER_TOP - counterH * cm.top),
			Size = UDim2.fromOffset(counterW, counterH),
			ZIndex = 3,
			Parent = frame,
		})
		Art.apply(counter, "prop_order_counter")
	end
	-- Figures stand behind the counter, cut at the waist by its top edge.
	-- Room above each figure for the name and patience meter, and for the selected one to
	-- step forward without touching its neighbours.
	local labelH = if ctx.compact then 40 else 64
	local slotW = (area.X - 32) / ROOM_FOR
	local figureH = math.min(area.Y * COUNTER_TOP - labelH - 12, slotW * 0.9 / FIGURE_ASPECT)
	local figureW = figureH * FIGURE_ASPECT
	local row: Frame? = nil
	local crowd = nil
	if room then
		crowd = OrderCrowd.new(room)
	else
		row = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, 0),
			Size = UDim2.new(1, -32, COUNTER_TOP, figureH * 0.12),
			ZIndex = 2,
			Parent = frame,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 0),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end
	local tag = if ctx.compact then TAG.compact else TAG.wide
	local tagH = tag.pad * 2 + tag.line + 2 + tag.meter / 4
	local statusText: string? = nil
	local selected: number? = nil
	-- Take order is the rail's action, like Send to oven and Serve.
	local takeButton = Widgets.button("Take order", function()
		if selected then
			local id = selected
			selected = nil
			ctx.send("takeOrder", { customerId = id }, function(ok)
				if ok then
					ctx.selectTicket(id)
				end
			end)
		end
	end)
	takeButton.frame.Size = UDim2.fromScale(1, 1)
	takeButton.frame.Parent = ctx.actionHost("Order")

	local people: { [number]: any } = {}

	-- 3D: the customer is a figure in the room; the station draws their tag (Astra's cream
	-- card holding the name and patience meter), and the tag and the body below it down to the
	-- counter line are the button that selects them.
	local function tagFor(customer: any)
		local slot = Ui.new("TextButton", {
			Name = "Customer" .. customer.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(tag.width, tagH),
			Visible = false,
			ZIndex = 2,
			Parent = frame,
		})
		-- Anchored at its bottom centre, so the chosen customer's tag grows away from the head.
		local card = Ui.new("ImageLabel", {
			Name = "Tag",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(40, 40, 840, 360),
			SliceScale = math.min(0.5, tagH / 120),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, tagH),
			Size = UDim2.fromOffset(tag.width, tagH),
			ZIndex = 2,
			Parent = slot,
		})
		Art.apply(card, "ui_card_result")
		local scale = Ui.new("UIScale", { Scale = 1, Parent = card })
		local name = Ui.text({
			Text = customer.label,
			FontFace = Theme.Font.display,
			TextSize = tag.text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(tag.pad, tag.pad),
			Size = UDim2.new(1, -tag.pad * 2, 0, tag.line),
			ZIndex = 3,
			Parent = card,
		})
		local meter = Widgets.patience()
		local aspect = meter.frame:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.DominantAxis = Enum.DominantAxis.Width
		meter.frame.AnchorPoint = Vector2.new(0.5, 0)
		meter.frame.Position = UDim2.new(0.5, 0, 0, tag.pad + tag.line + 2)
		meter.frame.Size = UDim2.fromOffset(tag.meter, tag.meter / 4)
		meter.frame.ZIndex = 3
		meter.frame.Parent = card
		slot.Activated:Connect(function()
			selected = customer.id
			ctx.refresh()
		end)
		return { slot = slot, scale = scale, name = name, meter = meter, customer = customer, band = "", chosen = false }
	end

	local function personFor(customer: any)
		if room then
			return tagFor(customer)
		end
		local cast = Recipes.Cast[customer.cast]
		local slot = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, slotW, 1, 0),
			LayoutOrder = customer.id,
			Parent = row,
		})
		local figure = Ui.new("ImageLabel", {
			Name = "Figure",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(figureW, figureH),
			Parent = slot,
		})
		local scale = Ui.new("UIScale", { Scale = 1, Parent = figure })
		local name = Ui.text({
			Text = customer.label,
			FontFace = Theme.Font.display,
			TextSize = if ctx.compact then 18 else 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -figureH * 1.06 - 4),
			Size = UDim2.new(1, 0, 0, if ctx.compact then 20 else 32),
			Parent = slot,
		})
		-- A cream outline keeps the name readable over the busy shop interior.
		Ui.new("UIStroke", { Color = C.label, Thickness = if ctx.compact then 2 else 3, Parent = name })
		local meter = Widgets.patience()
		local aspect = meter.frame:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.DominantAxis = Enum.DominantAxis.Width
		meter.frame.AnchorPoint = Vector2.new(0.5, 1)
		meter.frame.Position = UDim2.new(0.5, 0, 1, -figureH * 1.06 - (if ctx.compact then 22 else 34))
		meter.frame.Size = UDim2.new(0, math.min(slotW * 0.9, if ctx.compact then 110 else 200), 0, 200)
		meter.frame.Parent = slot
		slot.Activated:Connect(function()
			selected = customer.id
			ctx.refresh()
		end)
		local person = { slot = slot, figure = figure, scale = scale, name = name, meter = meter, customer = customer, art = cast.name:lower(), band = "", phase = math.random() * math.pi * 2, chosen = false }
		return person
	end

	local function setBand(p: any, band: string)
		if p.band == band or room then
			return
		end
		local first = p.band == ""
		p.band = band
		-- With no figure art (the 2D portraits are not uploaded), the name and patience meter
		-- would float over an empty slot, so they hide with it.
		local shown = Art.apply(p.figure, string.format("chr_%s_%s", p.art, band))
		p.name.Visible = shown
		p.meter.frame.Visible = shown
		if not first then
			-- A small pop so the change of mood reads.
			p.scale.Scale = (if p.chosen then 1.06 else 1) * 1.05
			TweenService:Create(p.scale, POP, { Scale = if p.chosen then 1.06 else 1 }):Play()
		end
	end

	local station = {}
	-- Customers already waiting when the station is built stand in place; later ones walk in.
	local built = false

	function station.refresh(snap: any)
		local seen = {}
		local waiting: { any } = {}
		for _, customer in snap.customers do
			if customer.status == "waiting" then
				table.insert(waiting, customer)
				seen[customer.id] = true
				if not people[customer.id] then
					people[customer.id] = personFor(customer)
					setBand(people[customer.id], "happy")
				end
				local p = people[customer.id]
				p.customer = customer
				p.name.Text = customer.label
			end
		end
		for id, p in people do
			if not seen[id] then
				-- In 3D the figure walks out on its own (crowd.sync below); the tag goes now.
				p.slot:Destroy()
				people[id] = nil
				if selected == id then
					selected = nil
				end
			end
		end
		if selected == nil then
			-- Default to the longest-waiting customer so one tap is enough.
			local first = nil
			for id in people do
				if first == nil or id < first then
					first = id
				end
			end
			selected = first
		end
		for id, p in people do
			local chosen = id == selected
			if chosen ~= p.chosen then
				p.chosen = chosen
				TweenService:Create(p.scale, STEP, { Scale = if chosen then 1.06 else 1 }):Play()
				if not room then
					TweenService:Create(p.figure, STEP, { ImageTransparency = if chosen then 0 else 0.12 }):Play()
				end
			end
			p.name.TextColor3 = if chosen then C.action else C.ink
		end
		if crowd then
			crowd.sync(waiting, not built)
		end
		built = true
		local active = 0
		for _, customer in snap.customers do
			if customer.status == "ordered" then
				active += 1
			end
		end
		local full = active >= Config.Shift.maxActiveTickets
		takeButton:setEnabled(selected ~= nil and not full)
		-- The action keeps its name; why it is unavailable goes on the hint strip.
		statusText = if #waiting == 0 then "No one waiting. Check your pizzas."
			elseif full then "Rail full: serve a pizza to free a ticket"
			else nil
	end

	local lastTick: number? = nil
	function station.tick(now: number)
		local dt = if lastTick then math.min(now - lastTick, 0.1) else 0
		lastTick = now
		if crowd then
			crowd.tick(dt)
		end
		for id, p in people do
			local f = Scoring.patienceFraction(p.customer.arrivedAt, now)
			local band = Scoring.patienceBand(f)
			p.meter:set(f, band)
			setBand(p, band)
			if crowd then
				-- The tag rides above the head (and any hat) while the customer stands at the
				-- counter; the button runs from it down to the counter line.
				local x0, y0, x1 = crowd.head(id)
				local shown = x0 ~= nil and crowd.standing(id)
				p.slot.Visible = shown
				if shown then
					local left = math.clamp(((x0 :: number) + (x1 :: number)) / 2 - tag.width / 2, 4, area.X - tag.width - 4)
					local top = math.max(4, (y0 :: number) - TAG_GAP - tagH)
					p.slot.Position = UDim2.fromOffset(math.round(left), math.round(top))
					p.slot.Size = UDim2.fromOffset(tag.width, math.max(tagH, room.line - math.round(top)))
				end
			else
				-- Idle breathing: a slow, slight rise and fall, out of step between customers.
				local lift = math.sin(now * 2.2 + p.phase) * figureH * 0.006
				p.figure.Position = UDim2.new(0.5, 0, 1, lift)
			end
		end
	end

	function station.setActive(on: boolean)
		if room then
			room.setActive(on)
		end
	end
	station.world3D = room ~= nil
	if room then
		-- Not ctx.connect: layout teardown drops those before it destroys the frames.
		frame.Destroying:Connect(function()
			if crowd then
				crowd.destroy()
			end
			room.destroy()
		end)
	end

	function station.status(_snap: any): any
		return if statusText then { text = statusText } else nil
	end

	-- First-shift pointer: Take order, once someone is waiting and a ticket slot is free.
	function station.hint(snap: any): any
		if selected and takeButton.enabled then
			return { target = takeButton.frame, text = "Tap Take order to start a ticket", from = "left" }
		end
		return nil
	end

	station.frame = frame
	return station
end

return Order

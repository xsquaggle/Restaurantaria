--!strict
-- Order station: waiting customers stand at the counter. Tap one to select, then take the
-- order from the rail. Each customer is a generated character (G10) whose expression
-- follows their patience band; the selected one steps forward while the others wait.

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
-- Hybrid proof: with the 3D counter, customers walk in from the left, wait at the counter
-- and walk out to the right. Work surfaces crossed per second, and steps per second.
local WALK_SPEED = 0.45
local STEP_RATE = 2.2

-- Full-screen art behind the station (Assets.Meta.backgrounds). The 3D counter view hides
-- it (Main turns the backdrop off for world3D stations) and hangs the same art in the world.
Order.background = "bg_order"
local room3D = OrderRoom.available()

function Order.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Order", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
	local room = if room3D then OrderRoom.new(ctx, container) else nil
	local counterTop = COUNTER_TOP
	if room then
		-- The 3D counter's far top edge, where the customers are cut.
		counterTop = room.line / area.Y
	else
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
	local figureH = math.min(area.Y * counterTop - labelH - 12, slotW * 0.9 / FIGURE_ASPECT)
	local figureW = figureH * FIGURE_ASPECT
	local row
	if room then
		-- Over the 3D counter the row is cut at the counter line (the drawn counter used to
		-- cover the waists), and customers are placed by hand so they can walk.
		local clip = Ui.new("Frame", {
			Name = "CounterClip",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.new(1, 0, 0, area.Y * counterTop),
			ZIndex = 2,
			Parent = frame,
		})
		row = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, 0),
			Size = UDim2.new(1, -32, 0, area.Y * counterTop + figureH * 0.12),
			ZIndex = 2,
			Parent = clip,
		})
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
	local rowW = area.X - 32
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

	local function personFor(customer: any)
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
			Text = cast.name,
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
		local person = { slot = slot, figure = figure, scale = scale, name = name, meter = meter, customer = customer, art = cast.name:lower(), band = "", phase = math.random() * math.pi * 2, chosen = false, x = nil :: number?, target = 0, leaving = false, walked = 0 }
		return person
	end

	local function setBand(p: any, band: string)
		if p.band == band then
			return
		end
		local first = p.band == ""
		p.band = band
		-- With no figure art (the 2D portraits are not uploaded), the name and patience meter
		-- would float over an empty slot, so they hide with it.
		local shown = Art.apply(p.figure, string.format("chr_%s_%s", p.art, band))
		p.name.Visible = shown and not p.leaving
		p.meter.frame.Visible = shown and not p.leaving
		if not first then
			-- A small pop so the change of mood reads.
			p.scale.Scale = (if p.chosen then 1.06 else 1) * 1.05
			TweenService:Create(p.scale, POP, { Scale = if p.chosen then 1.06 else 1 }):Play()
		end
	end

	local station = {}
	-- Customers already waiting when the station is built stand in place; later ones walk in.
	local built = false

	-- Hand layout over the 3D counter: waiting customers spread evenly in arrival order.
	local function arrange()
		local ids = {}
		for id, p in people do
			if not p.leaving then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		local x0 = (rowW - #ids * slotW) / 2
		for i, id in ids do
			local p = people[id]
			p.target = x0 + (i - 1) * slotW
			if p.x == nil then
				p.x = if built then -slotW else p.target
			end
		end
	end

	function station.refresh(snap: any)
		local seen = {}
		local waiting = 0
		for _, customer in snap.customers do
			if customer.status == "waiting" then
				waiting += 1
				seen[customer.id] = true
				if not people[customer.id] then
					people[customer.id] = personFor(customer)
					setBand(people[customer.id], "happy")
				end
				people[customer.id].customer = customer
			end
		end
		for id, p in people do
			if not seen[id] and not p.leaving then
				if room then
					-- Walks out to the right; tick removes the slot once off the work surface.
					p.leaving = true
					p.target = rowW + slotW
					p.slot.Interactable = false
					p.slot.ZIndex = 1
					p.name.Visible = false
					p.meter.frame.Visible = false
				else
					p.slot:Destroy()
					people[id] = nil
				end
				if selected == id then
					selected = nil
				end
			end
		end
		if room then
			arrange()
		end
		built = true
		if selected == nil then
			-- Default to the longest-waiting customer so one tap is enough.
			local first = nil
			for id, p in people do
				if p.leaving then
					continue
				end
				if first == nil or id < first then
					first = id
				end
			end
			selected = first
		end
		for id, p in people do
			if p.leaving then
				continue
			end
			local chosen = id == selected
			if chosen ~= p.chosen then
				p.chosen = chosen
				TweenService:Create(p.scale, STEP, { Scale = if chosen then 1.06 else 1 }):Play()
				TweenService:Create(p.figure, STEP, { ImageTransparency = if chosen then 0 else 0.12 }):Play()
			end
			p.name.TextColor3 = if chosen then C.action else C.ink
		end
		local active = 0
		for _, customer in snap.customers do
			if customer.status == "ordered" then
				active += 1
			end
		end
		local full = active >= Config.Shift.maxActiveTickets
		takeButton:setEnabled(selected ~= nil and not full)
		-- The action keeps its name; why it is unavailable goes on the hint strip.
		statusText = if waiting == 0 then "No one waiting. Check your pizzas."
			elseif full then "Rail full: serve a pizza to free a ticket"
			else nil
	end

	local lastTick: number? = nil
	function station.tick(now: number)
		local dt = if lastTick then math.min(now - lastTick, 0.1) else 0
		lastTick = now
		for id, p in people do
			if not p.leaving then
				local f = Scoring.patienceFraction(p.customer.arrivedAt, now)
				local band = Scoring.patienceBand(f)
				p.meter:set(f, band)
				setBand(p, band)
			end
			-- Idle breathing: a slow, slight rise and fall, out of step between customers.
			local lift = math.sin(now * 2.2 + p.phase) * figureH * 0.006
			if room and p.x then
				local gap = p.target - p.x
				local stepPx = area.X * WALK_SPEED * dt
				if math.abs(gap) > 0.5 then
					p.x += math.clamp(gap, -stepPx, stepPx)
					p.walked += math.abs(math.clamp(gap, -stepPx, stepPx))
					-- Walking: a step bounce in time with the travelled distance, so the
					-- bounce stops the moment the customer does.
					local stride = area.X * WALK_SPEED / STEP_RATE
					lift = -math.abs(math.sin(p.walked / stride * math.pi)) * figureH * 0.03
				elseif p.leaving then
					p.slot:Destroy()
					people[id] = nil
					continue
				end
				p.slot.Position = UDim2.fromOffset(p.x, 0)
			end
			p.figure.Position = UDim2.new(0.5, 0, 1, lift)
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

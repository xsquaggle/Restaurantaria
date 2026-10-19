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

-- Full-screen art behind the station (Assets.Meta.backgrounds).
Order.background = "bg_order"

function Order.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Order", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
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
	-- Figures stand behind the counter, cut at the waist by its top edge.
	-- Room above each figure for the name and patience meter, and for the selected one to
	-- step forward without touching its neighbours.
	local labelH = if ctx.compact then 40 else 64
	local slotW = (area.X - 32) / ROOM_FOR
	local figureH = math.min(area.Y * COUNTER_TOP - labelH - 12, slotW * 0.9 / FIGURE_ASPECT)
	local figureW = figureH * FIGURE_ASPECT
	local row = Ui.new("Frame", {
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
	-- Status hints sit on the counter below the customers so they never cover anyone.
	local hint = Ui.text({
		Text = "",
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 16 else 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.5, 0.86),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.2),
		ZIndex = 4,
		Parent = frame,
	})
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
			TextSize = if ctx.compact then 16 else 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -figureH * 1.06 - 4),
			Size = UDim2.new(1, 0, 0, if ctx.compact then 18 else 28),
			Parent = slot,
		})
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
		if p.band == band then
			return
		end
		local first = p.band == ""
		p.band = band
		Art.apply(p.figure, string.format("chr_%s_%s", p.art, band))
		if not first then
			-- A small pop so the change of mood reads.
			p.scale.Scale = (if p.chosen then 1.06 else 1) * 1.05
			TweenService:Create(p.scale, POP, { Scale = if p.chosen then 1.06 else 1 }):Play()
		end
	end

	local station = {}

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
			if not seen[id] then
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
		takeButton:setLabel(if full then "Rail full" else "Take order")
		if waiting == 0 then
			hint.Text = if snap.finished then "" else "No one waiting. Check your pizzas."
		elseif full then
			hint.Text = "Finish a pizza to free a ticket slot"
		else
			hint.Text = ""
		end
	end

	function station.tick(now: number)
		for _, p in people do
			local f = Scoring.patienceFraction(p.customer.arrivedAt, now)
			local band = Scoring.patienceBand(f)
			p.meter:set(f, band)
			setBand(p, band)
			-- Idle breathing: a slow, slight rise and fall, out of step between customers.
			p.figure.Position = UDim2.new(0.5, 0, 1, math.sin(now * 2.2 + p.phase) * figureH * 0.006)
		end
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

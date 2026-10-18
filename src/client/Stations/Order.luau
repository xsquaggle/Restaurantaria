--!strict
-- Order station: waiting customers at the counter. Tap one to select, then take the order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Order = {}

function Order.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Order", BackgroundColor3 = C.wall, Size = UDim2.fromScale(1, 1), Parent = container })
	Ui.new("Frame", {
		Name = "Counter",
		BackgroundColor3 = C.counter,
		Position = UDim2.fromScale(0, 0.72),
		Size = UDim2.fromScale(1, 0.28),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = frame,
	})
	local row = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0.04, 0),
		Size = UDim2.new(1, -32, 0.72, 0),
		Parent = frame,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 16),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local hint = Ui.text({
		Text = "",
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 16 else 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0.5, 0.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.2),
		Parent = frame,
	})
	local selected: number? = nil
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
	local bh = if ctx.compact then 52 else 72
	takeButton.frame.Size = UDim2.fromOffset(bh * 3.1, bh)
	takeButton.frame.AnchorPoint = Vector2.new(1, 1)
	takeButton.frame.Position = UDim2.new(1, -16, 1, -12)
	takeButton.frame.ZIndex = 5
	takeButton.frame.Parent = frame

	local cards: { [number]: any } = {}

	local function cardFor(customer: any)
		local w = if ctx.compact then 120 else 180
		local card = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.paper,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(0, w, 1, 0),
			LayoutOrder = customer.id,
			Parent = row,
		}, { Ui.corner(16) })
		local stroke = Ui.stroke(C.ink, 2)
		stroke.Parent = card
		local cast = Recipes.Cast[customer.cast]
		-- Placeholder figure until the illustrated cast exists.
		Ui.new("Frame", {
			BackgroundColor3 = cast.colour,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.7, 0.32),
			Parent = card,
		}, { Ui.corner(30), Ui.stroke(C.ink, 3) })
		Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(248, 214, 178),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.72),
			Size = UDim2.fromScale(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			Parent = card,
		}, { Ui.round(), Ui.stroke(C.ink, 3) })
		local name = Ui.text({
			Text = cast.name,
			FontFace = Theme.Font.display,
			TextSize = if ctx.compact then 18 else 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0, 4),
			Size = UDim2.new(1, -8, 0, if ctx.compact then 20 else 28),
			Parent = card,
		})
		local meter = Widgets.patience()
		meter.frame.Position = UDim2.new(0, 6, 0, name.Size.Y.Offset + 6)
		local aspect = meter.frame:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.DominantAxis = Enum.DominantAxis.Width
		meter.frame.Size = UDim2.new(1, -12, 0, 200)
		meter.frame.Parent = card
		card.Activated:Connect(function()
			selected = customer.id
			ctx.refresh()
		end)
		return { card = card, stroke = stroke, meter = meter, customer = customer }
	end

	local station = {}

	function station.refresh(snap: any)
		local seen = {}
		local waiting = 0
		for _, customer in snap.customers do
			if customer.status == "waiting" then
				waiting += 1
				seen[customer.id] = true
				if not cards[customer.id] then
					cards[customer.id] = cardFor(customer)
				end
				cards[customer.id].customer = customer
			end
		end
		for id, c in cards do
			if not seen[id] then
				c.card:Destroy()
				cards[id] = nil
				if selected == id then
					selected = nil
				end
			end
		end
		if selected == nil then
			-- Default to the longest-waiting customer so one tap is enough.
			local first = nil
			for id in cards do
				if first == nil or id < first then
					first = id
				end
			end
			selected = first
		end
		for id, c in cards do
			local isSel = id == selected
			c.stroke.Color = if isSel then C.action else C.ink
			c.stroke.Thickness = if isSel then 5 else 2
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
		for _, c in cards do
			local f = Scoring.patienceFraction(c.customer.arrivedAt, now)
			c.meter:set(f, Scoring.patienceBand(f))
		end
	end

	station.frame = frame
	return station
end

return Order

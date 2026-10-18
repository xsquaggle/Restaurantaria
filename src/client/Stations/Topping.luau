--!strict
-- Topping station: active ticket, top-down pizza, ingredient bins. Tap the pizza to place
-- the selected ingredient where your finger lands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Topping = {}

function Topping.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Topping", BackgroundColor3 = C.tile, Size = UDim2.fromScale(1, 1), Parent = container })
	local pad = if ctx.compact then 8 else 16
	local area = ctx.stationSize :: Vector2
	local pizzaSize = math.min(area.Y - pad * 2, area.X * 0.46)
	local sideW = (area.X - pizzaSize - pad * 4) / 2

	local ticketSlot = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(sideW, area.Y - pad * 2),
		Parent = frame,
	})
	local board = Ui.new("Frame", {
		BackgroundColor3 = C.dough,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(pizzaSize, pizzaSize),
		Parent = frame,
	}, { Ui.round() })
	local view = Widgets.pizza()
	view.frame.Size = UDim2.fromScale(0.94, 0.94)
	view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	view.frame.Position = UDim2.fromScale(0.5, 0.5)
	view.frame.Parent = board
	local empty = Ui.text({
		Text = "Take an order to start a pizza",
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 16 else 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(0.8, 0.3),
		Position = UDim2.fromScale(0.1, 0.35),
		ZIndex = 5,
		Parent = board,
	})

	local side = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -pad, 0, pad),
		Size = UDim2.fromOffset(sideW, area.Y - pad * 2),
		Parent = frame,
	})
	local binH = if ctx.compact then 48 else 64
	local grid = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, binH * 3 + 16), Parent = side }, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, binH),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local chosen = Recipes.IngredientOrder[1]
	local binStrokes: { [string]: UIStroke } = {}
	for i, id in Recipes.IngredientOrder do
		local info = Recipes.Ingredients[id]
		local bin = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.paper,
			LayoutOrder = i,
			Parent = grid,
		}, { Ui.corner(12) })
		binStrokes[id] = Ui.stroke(C.ink, 2)
		binStrokes[id].Parent = bin
		local swatch = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.42, 0.8), Position = UDim2.fromScale(0.02, 0.1), Parent = bin })
		Ui.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = swatch })
		Widgets.drawPiece(swatch, { ingredient = id, x = 0, y = 0 }, 0, false)
		local piece = swatch:FindFirstChildWhichIsA("Frame") :: Frame
		piece.Size = UDim2.fromScale(0.8, 0.8)
		Ui.text({
			Text = info.name,
			FontFace = Theme.Font.bodySemi,
			TextSize = if ctx.compact then 14 else 18,
			Position = UDim2.fromScale(0.42, 0),
			Size = UDim2.fromScale(0.56, 1),
			Parent = bin,
		})
		bin.Activated:Connect(function()
			chosen = id
			ctx.refresh()
		end)
	end
	local btnH = if ctx.compact then 50 else 68
	local undo = Ui.new("TextButton", {
		Text = "Undo",
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 16 else 20,
		TextColor3 = C.ink,
		BackgroundColor3 = C.paper,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(btnH + 12)),
		Size = UDim2.new(1, 0, 0, if ctx.compact then 44 else 52),
		Parent = side,
	}, { Ui.corner(12), Ui.stroke(C.ink, 2) })

	local current: any = nil
	local bake = Widgets.button("Bake", function()
		if current and not ctx.pending[current.id] then
			local id = current.id
			ctx.pending[id] = true
			ctx.refresh()
			ctx.send("sendToOven", { pizzaId = id }, function(ok)
				ctx.pending[id] = nil
				if ok then
					ctx.nudge("Bake")
				end
				ctx.refresh()
			end)
		end
	end)
	bake.frame.Size = UDim2.new(1, 0, 0, btnH)
	bake.frame.AnchorPoint = Vector2.new(0, 1)
	bake.frame.Position = UDim2.fromScale(0, 1)
	bake.frame.Parent = side

	undo.Activated:Connect(function()
		if current then
			ctx.send("undoTopping", { pizzaId = current.id })
		end
	end)

	-- Place on press, at the touch point.
	view.frame.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not current or ctx.pending[current.id] then
			return
		end
		local x, y = ctx.toLocal(view.frame, input.Position)
		if x * x + y * y > Config.Topping.placeRadius ^ 2 then
			return
		end
		local piece = { ingredient = chosen, x = x, y = y, pending = true }
		local pizzaId = current.id
		ctx.addOptimistic(pizzaId, piece)
		ctx.send("placeTopping", { pizzaId = pizzaId, ingredient = chosen, x = x, y = y }, function()
			ctx.removeOptimistic(pizzaId, piece)
		end)
	end)

	local shownTicket: number? = nil
	local station = { frame = frame }

	function station.refresh(snap: any)
		current = ctx.focusPizza(snap, "topping")
		for id, s in binStrokes do
			s.Color = if id == chosen then C.action else C.ink
			s.Thickness = if id == chosen then 4 else 2
		end
		view.frame.Visible = current ~= nil
		empty.Visible = current == nil
		bake:setEnabled(current ~= nil and not ctx.pending[current.id] and ctx.freeOvenSlot(snap))
		bake:setLabel(if current and ctx.pending[current.id] then "Sending..." elseif current and not ctx.freeOvenSlot(snap) then "Ovens full" else "Bake")
		local ticketId = if current then current.ticketId else nil
		if ticketId ~= shownTicket then
			shownTicket = ticketId
			Ui.clear(ticketSlot)
			if current then
				local customer = ctx.customer(snap, current.ticketId)
				local t = Widgets.ticket(Recipes.Cast[customer.cast].name, customer.order, ctx.compact)
				t.Size = UDim2.fromScale(1, 1)
				t.Parent = ticketSlot
			end
		end
		if current then
			view:set(ctx.withOptimistic(current), 0)
		end
	end

	function station.tick(_now: number) end

	return station
end

return Topping

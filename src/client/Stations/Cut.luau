--!strict
-- Cutting station: drag across the pizza to cut; each line is a chord through the drag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Cut = {}

function Cut.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Cut", BackgroundColor3 = Color3.fromRGB(214, 196, 168), Size = UDim2.fromScale(1, 1), Parent = container })
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
		BackgroundColor3 = Color3.fromRGB(176, 132, 90),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(pizzaSize, pizzaSize),
		Parent = frame,
	}, { Ui.corner(24), Ui.stroke(C.ink, 3) })
	local view = Widgets.pizza()
	view.frame.Size = UDim2.fromScale(0.9, 0.9)
	view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	view.frame.Position = UDim2.fromScale(0.5, 0.5)
	view.frame.Parent = board
	local preview = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = view.frame })
	local empty = Ui.text({
		Text = "Take a pizza out of the oven to cut it",
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
	local guide = Ui.text({
		Text = "",
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 16 else 22,
		Size = UDim2.new(1, 0, 0.4, 0),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = side,
	})
	local btnH = if ctx.compact then 50 else 68
	local undo = Ui.new("TextButton", {
		Text = "Undo cut",
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
	local serve = Widgets.button("Serve", function()
		if current and not ctx.pending[current.id] then
			local id = current.id
			local ticketId = current.ticketId
			ctx.pending[id] = true
			ctx.refresh()
			ctx.send("serve", { pizzaId = id }, function(ok)
				ctx.pending[id] = nil
				if ok then
					ctx.showResult(ticketId)
				end
				ctx.refresh()
			end)
		end
	end)
	serve.frame.Size = UDim2.new(1, 0, 0, btnH)
	serve.frame.AnchorPoint = Vector2.new(0, 1)
	serve.frame.Position = UDim2.fromScale(0, 1)
	serve.frame.Parent = side

	undo.Activated:Connect(function()
		if current then
			ctx.send("undoCut", { pizzaId = current.id })
		end
	end)

	-- Drag to cut, with a live preview chord. Drags may start anywhere on the board, so a
	-- stroke that begins just off the crust still counts.
	local dragStart: Vector2? = nil
	local dragInput: InputObject? = nil
	board.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if current and not ctx.pending[current.id] then
			local x, y = ctx.toLocal(view.frame, input.Position)
			dragStart = Vector2.new(math.clamp(x, -1.6, 1.6), math.clamp(y, -1.6, 1.6))
			dragInput = input
		end
	end)
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		if not dragStart then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
			local x, y = ctx.toLocal(view.frame, input.Position)
			Ui.clear(preview)
			local s = dragStart :: Vector2
			if (Vector2.new(x, y) - s).Magnitude > 0.2 then
				Widgets.drawCut(preview, { x1 = s.X, y1 = s.Y, x2 = x, y2 = y }, C.actionEdge)
			end
		end
	end)
	ctx.connect(UserInputService.InputEnded, function(input: InputObject)
		if not dragStart then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input ~= dragInput then
			return
		end
		local s = dragStart :: Vector2
		dragStart, dragInput = nil, nil
		Ui.clear(preview)
		if not current then
			return
		end
		local x, y = ctx.toLocal(view.frame, input.Position)
		if (Vector2.new(x, y) - s).Magnitude >= Config.Cut.minDragLength then
			ctx.send("cut", { pizzaId = current.id, x1 = s.X, y1 = s.Y, x2 = math.clamp(x, -1.6, 1.6), y2 = math.clamp(y, -1.6, 1.6) })
		end
	end)

	local shownTicket: number? = nil
	local station = { frame = frame }

	function station.refresh(snap: any)
		current = ctx.focusPizza(snap, "cutting")
		view.frame.Visible = current ~= nil
		empty.Visible = current == nil
		serve:setEnabled(current ~= nil and not ctx.pending[current.id])
		serve:setLabel(if current and ctx.pending[current.id] then "Serving..." else "Serve")
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
			local customer = ctx.customer(snap, current.ticketId)
			local cuts = #current.cuts
			guide.Text = string.format("Cut into %d slices.\nDrag across the centre. %d of %d cuts.", customer.order.slices, cuts, customer.order.slices // 2)
			view:set(current, Widgets.doneness(current.bakeSeconds or 0))
			serve:setHighlighted(cuts == customer.order.slices // 2)
		else
			guide.Text = ""
		end
	end

	function station.tick(_now: number) end

	return station
end

return Cut

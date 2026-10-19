--!strict
-- Cutting station: drag across the pizza to cut; each line is a chord through the drag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Cut = {}

function Cut.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Cut", BackgroundColor3 = Color3.fromRGB(214, 196, 168), Size = UDim2.fromScale(1, 1), Parent = container })
	-- Composition follows 03-cut: the board fills the middle of the work surface, the hint
	-- sits top left, Undo bottom left, and Serve is the rail's action. The ticket is the
	-- rail's own, so the station does not repeat it.
	local pad = if ctx.compact then 8 else 16
	local area = ctx.stationSize :: Vector2
	local hintH = if ctx.compact then 40 else 64
	local undoH = if ctx.compact then 48 else math.clamp(math.round(area.Y * 0.08), 52, 64)
	local undoW = if ctx.compact then 112 else math.clamp(math.round(area.X * 0.16), 150, 220)
	-- The board takes the height left between the hint and Undo rows when they would
	-- otherwise overlap it, and the full height when the sides have room for them.
	local boardD = math.min(area.Y - pad * 2, area.X - pad * 2)
	local sideRoom = (area.X - boardD) / 2 - pad * 2
	if sideRoom < undoW then
		boardD = math.min(area.X - (undoW + pad * 2) * 2, area.Y - pad * 2)
	end
	local pizzaSize = boardD / Assets.Meta.boardOverPizza

	local board = Ui.new("ImageLabel", {
		Name = "Board",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(boardD, boardD),
		Parent = frame,
	})
	Art.apply(board, "board_round")
	local view = Widgets.pizza()
	view.frame.Size = UDim2.fromOffset(pizzaSize, pizzaSize)
	view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	view.frame.Position = UDim2.fromScale(0.5, 0.5)
	view.frame.ZIndex = 2
	view.frame.Parent = board
	local preview = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = view.frame })
	local empty = Ui.text({
		Text = "Take a pizza out of the oven to cut it",
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 16 else 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(0.7, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 5,
		Parent = board,
	})

	local current: any = nil

	-- Live hint text; the cream hint chip behind it is requested (A21).
	local guide = Ui.text({
		Text = "",
		FontFace = Theme.Font.bodySemi,
		TextSize = if ctx.compact then 16 else 22,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(math.max(undoW, (area.X - boardD) / 2 - pad * 2 + boardD * 0.18), hintH * 2),
		ZIndex = 6,
		Parent = frame,
	})
	local undo = Widgets.button("Undo cut", function()
		if current then
			ctx.send("undoCut", { pizzaId = current.id })
		end
	end, "secondary")
	undo.frame.AnchorPoint = Vector2.new(0, 1)
	undo.frame.Position = UDim2.new(0, pad, 1, -pad)
	undo.frame.Size = UDim2.fromOffset(undoW, undoH)
	undo.frame.ZIndex = 6
	undo.frame.Parent = frame

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
	serve.frame.Size = UDim2.fromScale(1, 1)
	serve.frame.Parent = ctx.actionHost("Cut")

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

	local station = { frame = frame }

	function station.refresh(snap: any)
		current = ctx.focusPizza(snap, "cutting")
		view.frame.Visible = current ~= nil
		empty.Visible = current == nil
		serve:setEnabled(current ~= nil and not ctx.pending[current.id])
		undo:setEnabled(current ~= nil and #current.cuts > 0)
		serve:setLabel(if current and ctx.pending[current.id] then "Serving..." else "Serve")
		if current then
			local customer = ctx.customer(snap, current.ticketId)
			local cuts = #current.cuts
			guide.Text = string.format("Cut into %d slices\nDrag across the centre: %d of %d cuts", customer.order.slices, cuts, customer.order.slices // 2)
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

--!strict
-- Cutting station: drag across the pizza to cut; each line is a chord through the drag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local Cut = {}

-- Full-screen art behind the station (Assets.Meta.backgrounds).
Cut.background = "bg_cut"

function Cut.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Cut", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	-- Composition follows 03-cut: the cutting board fills the work surface with the pizza
	-- left of centre and the cutter resting to its right; the hint sits top left, Undo
	-- bottom left, and Serve is the rail's action. The ticket is the rail's own, so the
	-- station does not repeat it.
	local pad = if ctx.compact then 8 else 16
	local area = ctx.stationSize :: Vector2
	local hintH = if ctx.compact then 40 else 64
	-- 54 px keeps the drawn button (90% of its frame) at the 48 px floor.
	local undoH = if ctx.compact then 54 else math.clamp(math.round(area.Y * 0.08), 52, 64)
	local undoW = if ctx.compact then 112 else math.clamp(math.round(area.X * 0.16), 150, 220)
	local boardAspect = Assets.Meta.cutBoard.aspect
	local boardH = math.min(area.Y - pad * 2, (area.X - pad * 2) / boardAspect)
	local boardW = boardH * boardAspect
	local pizzaSize = boardH * 0.9
	-- Pizza centre in station pixels: left of the board's centre to leave the cutter room.
	local pizzaX, pizzaY = area.X / 2 - boardW * 0.06, area.Y / 2

	local board = Ui.new("ImageLabel", {
		Name = "Board",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(boardW, boardH),
		Parent = frame,
	})
	Art.apply(board, "board_cut")
	local view = Widgets.pizza()
	view.frame.Size = UDim2.fromOffset(pizzaSize, pizzaSize)
	view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	view.frame.Position = UDim2.fromOffset(pizzaX, pizzaY)
	view.frame.ZIndex = 2
	view.frame.Parent = frame
	local preview = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = view.frame })
	local empty = Ui.text({
		Text = "Take a pizza out of the oven to cut it",
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 16 else 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(pizzaSize * 0.7, pizzaSize * 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(pizzaX, pizzaY),
		ZIndex = 5,
		Parent = frame,
	})

	local current: any = nil

	-- Live cut count on Astra's cream result card (stand-in backing until the A21 hint chip
	-- arrives), so it reads over the busy backdrop. Same width as Undo, clear of the pizza.
	local guideSize = if ctx.compact then 16 else 22
	local guidePad = if ctx.compact then 8 else 12
	local guideCard = Ui.new("ImageLabel", {
		Name = "Guide",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(40, 40, 840, 360),
		SliceScale = 0.4,
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(undoW, guideSize * 2 + guidePad * 2 + 4),
		Visible = false,
		ZIndex = 6,
		Parent = frame,
	})
	Art.apply(guideCard, "ui_card_result")
	local guide = Ui.text({
		Text = "",
		FontFace = Theme.Font.bodySemi,
		TextSize = guideSize,
		TextColor3 = Theme.Colour.ink,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(guidePad, guidePad),
		Size = UDim2.new(1, -guidePad * 2, 1, -guidePad * 2),
		ZIndex = 7,
		Parent = guideCard,
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

	-- The cutter: the generated wheel on its handle, resting on the board right of the
	-- pizza. While cutting it follows the pointer, its handle trailing the stroke and the
	-- wheel spinning with the distance rolled, then it glides back to rest.
	local wheelD = pizzaSize * 0.3
	local handleH = pizzaSize * 0.62
	local handle = Assets.Meta.cutterHandle
	-- The holder is the wheel's square, so turning it (GUI rotation is about the centre)
	-- turns the handle around the axle; the handle hangs outside it.
	local cutter = Ui.new("Frame", {
		Name = "Cutter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(wheelD, wheelD),
		ZIndex = 6,
		Parent = frame,
	})
	local handleImg = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		AnchorPoint = Vector2.new(0.5, handle.axle),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(handleH * handle.aspect, handleH),
		ZIndex = 1,
		Parent = cutter,
	})
	Art.apply(handleImg, "prop_cutter_handle")
	local wheel = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = cutter,
	})
	Art.apply(wheel, "prop_cutter_wheel")
	local rest = UDim2.fromOffset(math.min(pizzaX + pizzaSize * 0.5 + wheelD * 0.45, area.X / 2 + boardW * 0.5 - wheelD * 0.6), pizzaY - pizzaSize * 0.14)
	local REST_ANGLE = -32
	cutter.Position = rest
	cutter.Rotation = REST_ANGLE
	local GLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local PICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local lastPoint: Vector2? = nil

	local function toStation(position: Vector3): Vector2
		-- Keep the whole wheel inside the station so its edge never clips at the panel.
		local p = Vector2.new(position.X, position.Y) - frame.AbsolutePosition
		local inset = wheelD * 0.5
		return Vector2.new(math.clamp(p.X, inset, area.X - inset), math.clamp(p.Y, inset, area.Y - inset))
	end
	local function follow(point: Vector2)
		local prev = lastPoint
		lastPoint = point
		cutter.Position = UDim2.fromOffset(point.X, point.Y)
		if prev then
			local d = point - prev
			if d.Magnitude > 0.5 then
				-- Handle trails the stroke; turn toward it smoothly so jitter doesn't shake it.
				local target = math.deg(math.atan2(d.X, -d.Y))
				local delta = (target - cutter.Rotation + 180) % 360 - 180
				cutter.Rotation += delta * 0.35
				wheel.Rotation += math.deg(d.Magnitude / (wheelD / 2))
			end
		end
	end

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
			local point = toStation(input.Position)
			lastPoint = point
			TweenService:Create(cutter, PICK, { Position = UDim2.fromOffset(point.X, point.Y) }):Play()
		end
	end)
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		if not dragStart then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
			follow(toStation(input.Position))
			local x, y = ctx.toLocal(view.frame, input.Position)
			Ui.clear(preview)
			local s = dragStart :: Vector2
			if (Vector2.new(x, y) - s).Magnitude > 0.2 then
				Widgets.drawCut(preview, { x1 = s.X, y1 = s.Y, x2 = x, y2 = y }, 0.45)
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
		dragStart, dragInput, lastPoint = nil, nil, nil
		Ui.clear(preview)
		TweenService:Create(cutter, GLIDE, { Position = rest, Rotation = REST_ANGLE }):Play()
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
			guide.Text = string.format("%d slices\n%d of %d cuts", customer.order.slices, cuts, customer.order.slices // 2)
			guideCard.Visible = true
			view:set(current, Widgets.doneness(current.bakeSeconds or 0), ctx.ovenStatus(customer.order.bake, current.bakeSeconds or 0).burnt)
			serve:setHighlighted(cuts == customer.order.slices // 2)
		else
			guideCard.Visible = false
		end
	end

	function station.tick(_now: number) end

	-- First-shift pointer: drag across the pizza for the first cut.
	function station.hint(_snap: any): any
		if current and #current.cuts == 0 then
			return { target = view.frame, text = "Drag across the pizza to cut", from = "left", cardOver = view.frame }
		end
		return nil
	end

	return station
end

return Cut

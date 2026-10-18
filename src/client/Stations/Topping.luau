--!strict
-- Topping station, composed like the approved reference: the pizza on its board is the
-- centre of the counter and the five ingredient trays sit in a row beneath it. Drag a piece
-- from a tray onto the pizza, or tap a tray and then tap the pizza where it should go.
-- The ticket and "Send to oven" live in the rail (Main.client.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local PizzaArt = require(Parent.PizzaArt)
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Topping = {}

-- Full-screen art behind the station (Assets.Meta.backgrounds).
Topping.background = "counter_topping"

local PRESS = TweenInfo.new(Theme.Motion.press, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RETURN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SEND = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ARRIVE = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DRAG_START = 6 -- pixels of travel before a press on a tray becomes a drag

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Topping.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Topping", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
	local W, H = area.X, area.Y
	local margin = math.clamp(math.round(H * 0.03), 6, 24)

	-- Two ways to fit the counter; the one that gives the bigger pizza wins. Wide screens get
	-- the reference composition (trays in a row under the pizza); short phone screens stack
	-- the trays two across beside it, which leaves the pizza much more room.
	local trayAspect = Art.aspect("tray_pepperoni", Assets.Meta.trayAspect)
	local gap = math.max(4, math.round(W * 0.01))
	local count = #Recipes.IngredientOrder

	local trayW = (W - margin * 2 - gap * (count - 1)) / count
	local trayH = trayW / trayAspect
	if trayH > H * 0.3 then
		trayH = H * 0.3
		trayW = trayH * trayAspect
	end
	local boardTop = margin * 0.6
	-- The row tucks slightly over the board's lower edge.
	local boardD = math.min(H - margin - trayH * 0.84 - boardTop, W * 0.62)

	local cols, rows = 2, math.ceil((count + 1) / 2) -- one spare cell holds Undo
	local sideTrayH = (H - margin * 2 - gap * (rows - 1)) / rows
	local sideTrayW = sideTrayH * trayAspect
	local gridW = sideTrayW * cols + gap * (cols - 1)
	local sideBoardD = math.min(H - margin * 2, W - gridW - margin * 3)
	local side = sideBoardD > boardD * 1.08

	local cx: number, cy: number
	local homes: { UDim2 } = {}
	if side then
		trayW, trayH, boardD = sideTrayW, sideTrayH, sideBoardD
		local left = margin * 2 + gridW
		cx = left + (W - margin - left) / 2
		cy = H / 2
		for i = 1, count + 1 do
			local col, row = (i - 1) % cols, (i - 1) // cols
			homes[i] = UDim2.fromOffset(margin + col * (trayW + gap) + trayW / 2, margin + row * (trayH + gap) + trayH / 2)
		end
	else
		cx = math.clamp(W * 0.54, boardD / 2 + margin, W - boardD / 2 - margin)
		cy = boardTop + boardD / 2
		local rowW = trayW * count + gap * (count - 1)
		local rowX = (W - rowW) / 2
		for i = 1, count do
			homes[i] = UDim2.fromOffset(rowX + (i - 1) * (trayW + gap) + trayW / 2, H - margin - trayH / 2)
		end
	end
	local pizzaD = boardD / Assets.Meta.boardOverPizza

	local board = Ui.new("ImageLabel", {
		Name = "Board",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(boardD, boardD),
		Parent = frame,
	})
	Art.apply(board, "board_round")
	local view = PizzaArt.new()
	view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	view.frame.Position = UDim2.fromOffset(cx, cy)
	view.frame.Size = UDim2.fromOffset(pizzaD, pizzaD)
	view.frame.ZIndex = 2
	view.frame.Parent = frame
	local empty = Ui.text({
		Text = "Take an order to start a pizza",
		FontFace = Theme.Font.display,
		TextSize = if ctx.compact then 15 else 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(boardD * 0.7, boardD * 0.3),
		ZIndex = 3,
		Parent = frame,
	})
	Ui.new("UIStroke", { Color = C.paper, Thickness = 2, Parent = empty })

	-- Loose pieces (held or previewed) float above everything on the station.
	local overlay = Ui.new("Frame", { Name = "Hand", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = frame })

	local chosen = Recipes.IngredientOrder[1]
	local trays: { [string]: { button: ImageButton, scale: UIScale, home: UDim2 } } = {}
	for i, id in Recipes.IngredientOrder do
		local home = homes[i]
		local button = Ui.new("ImageButton", {
			Name = "Tray_" .. id,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = home,
			Size = UDim2.fromOffset(trayW, trayH),
			ZIndex = 4,
			Parent = frame,
		})
		Art.apply(button, "tray_" .. Recipes.Ingredients[id].art)
		trays[id] = { button = button, scale = Ui.new("UIScale", { Scale = 1, Parent = button }), home = home }
	end

	local function showChosen()
		for id, t in trays do
			local on = id == chosen
			-- The chosen tray sits a little larger and pulled toward the pizza.
			local lift = if side then UDim2.fromOffset(trayW * 0.06, 0) else UDim2.fromOffset(0, -trayH * 0.14)
			TweenService:Create(t.scale, RELEASE, { Scale = if on then 1.1 else 1 }):Play()
			TweenService:Create(t.button, RELEASE, { Position = if on then t.home + lift else t.home }):Play()
			t.button.ZIndex = if on then 5 else 4
		end
	end

	local undo = Widgets.button("Undo", function()
		local current = ctx.focusPizza(ctx.snapshot, "topping")
		if current and not ctx.pending[current.id] then
			ctx.send("undoTopping", { pizzaId = current.id })
		end
	end)
	if side then
		-- The spare cell of the tray grid.
		undo.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		undo.frame.Position = homes[count + 1]
		undo.frame.Size = UDim2.fromOffset(trayW * 0.86, math.min(trayH * 0.56, 44))
	else
		undo.frame.AnchorPoint = Vector2.new(1, 0)
		undo.frame.Position = UDim2.fromOffset(W - margin, margin)
		undo.frame.Size = if ctx.compact then UDim2.fromOffset(92, 36) else UDim2.fromOffset(math.clamp(W * 0.14, 120, 180), math.clamp(H * 0.08, 44, 64))
	end
	undo.frame.ZIndex = 5
	undo.frame.Parent = frame

	local current: any = nil
	local sending: number? = nil

	-- Send to oven: the rail's action for this station.
	local send = Widgets.button("Send to oven", function()
		if current and not ctx.pending[current.id] then
			local id = current.id
			ctx.pending[id] = true
			sending = id
			ctx.refresh()
			-- The pizza slides off toward the ovens; purely visual, nothing waits for it.
			TweenService:Create(view.frame, SEND, {
				Position = UDim2.fromOffset(cx + W * 0.3, cy - H * 0.05),
				Rotation = 12,
			}):Play()
			ctx.send("sendToOven", { pizzaId = id }, function(ok)
				ctx.pending[id] = nil
				if ok then
					ctx.nudge("Bake")
				end
				sending = nil
				ctx.refresh()
			end)
		end
	end)
	send.frame.Size = UDim2.fromScale(1, 1)
	send.frame.Parent = ctx.actionHost("Topping")

	local function place(x: number, y: number)
		if not current or ctx.pending[current.id] then
			return
		end
		if x * x + y * y > Config.Topping.placeRadius ^ 2 then
			return
		end
		local piece = { ingredient = chosen, x = x, y = y, pending = true }
		local pizzaId = current.id
		ctx.addOptimistic(pizzaId, piece)
		ctx.send("placeTopping", { pizzaId = pizzaId, ingredient = chosen, x = x, y = y }, function()
			ctx.removeOptimistic(pizzaId, piece)
		end)
	end

	local function overlayPoint(position: Vector3): UDim2
		local p = Vector2.new(position.X, position.Y) - frame.AbsolutePosition
		return UDim2.fromOffset(p.X, p.Y)
	end

	local function pieceSize(ingredient: string): number
		return Recipes.Ingredients[ingredient].size * view.frame.AbsoluteSize.X
	end

	-- Tap the pizza: place the chosen ingredient where the finger lands.
	local dragging: any = nil
	view.frame.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not dragging then
			place(ctx.toLocal(view.frame, input.Position))
		end
	end)

	-- Press a tray: choose it. Keep moving and the press becomes a drag that carries a piece.
	for id, t in trays do
		t.button.InputBegan:Connect(function(input: InputObject)
			if not isPress(input) or dragging then
				return
			end
			chosen = id
			TweenService:Create(t.scale, PRESS, { Scale = 0.95 }):Play()
			task.delay(Theme.Motion.press, showChosen)
			dragging = { input = input, ingredient = id, start = input.Position, held = nil }
		end)
	end

	local hover: ImageLabel? = nil
	local function clearHover()
		if hover then
			hover:Destroy()
			hover = nil
		end
	end

	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		if dragging and (input == dragging.input or (isMouse and dragging.input.UserInputType == Enum.UserInputType.MouseButton1)) then
			local travel = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(dragging.start.X, dragging.start.Y)).Magnitude
			if not dragging.held and travel >= DRAG_START then
				clearHover()
				local held = PizzaArt.loosePiece(dragging.ingredient, math.random(1, 3), math.random(0, 359), pieceSize(dragging.ingredient))
				-- Picked up: a touch bigger than it will sit, so it reads as lifted.
				Ui.new("UIScale", { Scale = 1.2, Parent = held })
				held.Parent = overlay
				dragging.held = held
			end
			if dragging.held then
				dragging.held.Position = overlayPoint(input.Position)
			end
		elseif isMouse and not dragging and current and not ctx.pending[current.id] then
			-- Mouse only: a faint preview of the next piece under the pointer.
			local x, y = ctx.toLocal(view.frame, input.Position)
			if x * x + y * y <= Config.Topping.placeRadius ^ 2 then
				if not hover or hover:GetAttribute("Ingredient") ~= chosen then
					clearHover()
					hover = PizzaArt.loosePiece(chosen, 1, 0, pieceSize(chosen))
					local h = hover :: ImageLabel
					h:SetAttribute("Ingredient", chosen)
					h.ImageTransparency = 0.55
					h.Parent = overlay
				end
				(hover :: ImageLabel).Position = overlayPoint(input.Position)
			else
				clearHover()
			end
		end
	end)

	ctx.connect(UserInputService.InputEnded, function(input: InputObject)
		if not dragging or not isPress(input) then
			return
		end
		if input ~= dragging.input and input.UserInputType ~= dragging.input.UserInputType then
			return
		end
		local d = dragging
		dragging = nil
		local held: ImageLabel? = d.held
		if not held then
			return
		end
		local x, y = ctx.toLocal(view.frame, input.Position)
		if current and not ctx.pending[current.id] and x * x + y * y <= Config.Topping.placeRadius ^ 2 then
			held:Destroy()
			chosen = d.ingredient
			place(x, y)
		else
			-- Dropped off the pizza: the piece goes back to its tray.
			local tray = trays[d.ingredient].button
			local home = tray.AbsolutePosition + tray.AbsoluteSize / 2 - frame.AbsolutePosition
			local back = TweenService:Create(held, RETURN, { Position = UDim2.fromOffset(home.X, home.Y), ImageTransparency = 1 })
			back.Completed:Connect(function()
				held:Destroy()
			end)
			back:Play()
		end
	end)

	local shownId: number? = nil
	local station = { frame = frame }

	function station.refresh(snap: any)
		current = ctx.focusPizza(snap, "topping")
		local id = if current then current.id else nil
		local leavingNow = sending ~= nil and sending == id
		if id ~= shownId and not leavingNow then
			shownId = id
			-- A new pizza slides in from the left; the one that left is reset off-screen.
			view.frame.Rotation = 0
			if current then
				view.frame.Position = UDim2.fromOffset(cx - W * 0.35, cy)
				TweenService:Create(view.frame, ARRIVE, { Position = UDim2.fromOffset(cx, cy) }):Play()
			else
				view.frame.Position = UDim2.fromOffset(cx, cy)
			end
		end
		view.frame.Visible = current ~= nil
		empty.Visible = current == nil
		if not current then
			clearHover()
		end
		local busy = current ~= nil and ctx.pending[current.id] == true
		send:setEnabled(current ~= nil and not busy and ctx.freeOvenSlot(snap))
		send:setLabel(if busy then "Sending..." elseif current and not ctx.freeOvenSlot(snap) then "Ovens full" else "Send to oven")
		undo:setEnabled(current ~= nil and not busy and #current.toppings > 0)
		view:set(if current then ctx.withOptimistic(current) else nil, true)
		if not sending and current and view.frame.Rotation ~= 0 then
			-- The send was refused: bring the pizza back.
			TweenService:Create(view.frame, ARRIVE, { Position = UDim2.fromOffset(cx, cy), Rotation = 0 }):Play()
		end
	end

	function station.tick(_now: number) end

	showChosen()
	return station
end

return Topping

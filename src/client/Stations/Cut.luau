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

-- Full-screen art behind the station (Assets.Meta.backgrounds): Astra's clean ivory cutting
-- worktop (r13). The old bg_cut had a plant and shakers baked in that the board covered.
Cut.background = "bg_cut_clean_ivory"
-- Studio play tests only, through attributes on the local player (set from the Client command
-- bar): RestaurantariaCutTrace = "" records each stroke (begin, send, reply, cancel, refusals)
-- into that attribute; RestaurantariaCutButton2 = true lets a driver whose injected primary
-- button arrives as MouseButton2 (swapped buttons) make real-mouse strokes.
local IS_STUDIO = game:GetService("RunService"):IsStudio()
local LocalPlayer = game:GetService("Players").LocalPlayer

function Cut.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Cut", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	-- Composition follows 03-cut: the cutting board fills the work surface with the pizza
	-- left of centre and the cutter resting to its right; the hint sits top left, Undo
	-- bottom left, and Serve is the rail's action. The ticket is the rail's own, so the
	-- station does not repeat it.
	local pad = if ctx.compact then 8 else 16
	local area = ctx.stationSize :: Vector2
	local hintH = if ctx.compact then 40 else 64
	-- 56 px keeps the drawn button (its art, without the shadow margin) at 48 px or more.
	local undoH = if ctx.compact then 56 else math.clamp(math.round(area.Y * 0.08), 56, 64)
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
	local current: any = nil

	-- Live cut count on Astra's hint chip (A21), so it reads over the busy backdrop. Same width
	-- as Undo, clear of the pizza.
	local guideSize = if ctx.compact then 18 else 22
	local guidePad = if ctx.compact then 8 else 12
	local guideH = guideSize * 2 + guidePad * 2 + 4
	local chip = Assets.Meta.hintChip
	local guideCard = Ui.new("ImageLabel", {
		Name = "Guide",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = chip.slice,
		SliceScale = math.min(undoW / chip.width, guideH / chip.height),
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(undoW, guideH),
		Visible = false,
		ZIndex = 6,
		Parent = frame,
	})
	Art.apply(guideCard, "ui_hint_chip")
	local guide = Ui.text({
		Text = "",
		FontFace = Theme.Font.display,
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
	undo:setIcon("icon_undo")
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
	serve:setIcon("icon_serve_white")
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
	-- stroke that begins just off the crust still counts. One stroke at a time: it belongs to
	-- the input that started it (the mouse, or that one finger) and to the pizza it started on;
	-- other fingers are ignored and a ticket or station change cancels it without cutting.
	local RANGE = 1.6 -- the server's accepted coordinate range
	type Stroke = { input: InputObject, mouse: boolean, button: Enum.UserInputType, pizzaId: number, start: Vector2 }
	local stroke: Stroke? = nil

	-- Pizza-local point of a screen position, not clamped.
	local function rawLocal(position: Vector3): Vector2
		local rel = (Vector2.new(position.X, position.Y) - view.frame.AbsolutePosition) / view.frame.AbsoluteSize
		return Vector2.new(rel.X * 2 - 1, rel.Y * 2 - 1)
	end
	-- The stroke's end inside the accepted range, moved back along the stroke so the cut keeps
	-- the dragged direction (clamping each axis on its own bent long drags toward 45 degrees).
	local function endPoint(s: Vector2, e: Vector2): Vector2
		local d = e - s
		local t = 1
		for _, axis in { "X", "Y" } do
			local dv, sv = (d :: any)[axis], (s :: any)[axis]
			if dv > 1e-9 then
				t = math.min(t, (RANGE - sv) / dv)
			elseif dv < -1e-9 then
				t = math.min(t, (-RANGE - sv) / dv)
			end
		end
		return s + d * math.max(t, 0)
	end
	local function trace(line: string)
		local log = IS_STUDIO and LocalPlayer:GetAttribute("RestaurantariaCutTrace")
		if type(log) == "string" and #log < 60000 then
			LocalPlayer:SetAttribute("RestaurantariaCutTrace", log .. string.format("%.3f %s\n", os.clock(), line))
		end
	end
	local function endStroke()
		stroke, lastPoint = nil, nil
		Ui.clear(preview)
		TweenService:Create(cutter, GLIDE, { Position = rest, Rotation = REST_ANGLE }):Play()
	end
	local function cancelStroke(reason: string)
		if stroke then
			trace("cancel " .. reason .. " pizza=" .. stroke.pizzaId)
			endStroke()
		end
	end

	board.InputBegan:Connect(function(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
			or (IS_STUDIO and LocalPlayer:GetAttribute("RestaurantariaCutButton2") == true and input.UserInputType == Enum.UserInputType.MouseButton2)
		if not isMouse and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if stroke or not current or ctx.pending[current.id] then
			trace("ignored begin " .. input.UserInputType.Name .. (if stroke then " (stroke held)" else ""))
			return
		end
		local p = rawLocal(input.Position)
		local s = Vector2.new(math.clamp(p.X, -RANGE, RANGE), math.clamp(p.Y, -RANGE, RANGE))
		stroke = { input = input, mouse = isMouse, button = input.UserInputType, pizzaId = current.id, start = s }
		local point = toStation(input.Position)
		lastPoint = point
		TweenService:Create(cutter, PICK, { Position = UDim2.fromOffset(point.X, point.Y) }):Play()
		trace(string.format("begin %s screen=%.0f,%.0f local=%.3f,%.3f pizza=%d ticket=%d", input.UserInputType.Name, input.Position.X, input.Position.Y, s.X, s.Y, current.id, current.ticketId))
	end)
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		local st = stroke
		if not st then
			return
		end
		if (st.mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or (not st.mouse and input == st.input) then
			follow(toStation(input.Position))
			local e = endPoint(st.start, rawLocal(input.Position))
			Ui.clear(preview)
			local len = (e - st.start).Magnitude
			if len > 0.05 then
				-- The groove only follows the cutter: it shows where the wheel has rolled, never
				-- the line ahead of it (Lawson, 2026-10-26). Faint until the drag is long enough
				-- to cut, so it never promises a cut the release would drop.
				Widgets.drawCut(preview, { x1 = st.start.X, y1 = st.start.Y, x2 = e.X, y2 = e.Y }, if len >= Config.Cut.minDragLength then 0.3 else 0.7, true)
			end
		end
	end)
	ctx.connect(UserInputService.InputEnded, function(input: InputObject)
		local st = stroke
		if not st then
			return
		end
		if (st.mouse and input.UserInputType ~= st.button) or (not st.mouse and input ~= st.input) then
			return
		end
		endStroke()
		if not current or current.id ~= st.pizzaId then
			trace("dropped: pizza changed")
			return
		end
		local e = endPoint(st.start, rawLocal(input.Position))
		local len = (e - st.start).Magnitude
		local angle = math.deg(math.atan2(e.Y - st.start.Y, e.X - st.start.X))
		if len >= Config.Cut.minDragLength then
			trace(string.format("send %s screen=%.0f,%.0f line=%.3f,%.3f>%.3f,%.3f angle=%.1f pizza=%d", input.UserInputType.Name, input.Position.X, input.Position.Y, st.start.X, st.start.Y, e.X, e.Y, angle, st.pizzaId))
			ctx.send("cut", { pizzaId = st.pizzaId, x1 = st.start.X, y1 = st.start.Y, x2 = e.X, y2 = e.Y }, function(ok, reason)
				trace(string.format("reply ok=%s %s", tostring(ok), tostring(reason)))
			end)
		else
			trace(string.format("too short %.3f < %.2f", len, Config.Cut.minDragLength))
			guide.Text = "Drag all the way\nacross the pizza"
			task.delay(1.5, ctx.refresh)
		end
	end)

	local station = { frame = frame }

	function station.refresh(snap: any)
		current = ctx.focusPizza(snap, "cutting")
		if stroke and (not current or current.id ~= stroke.pizzaId) then
			cancelStroke("ticket changed")
		end
		view.frame.Visible = current ~= nil
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

	-- Leaving the station mid-stroke cancels the stroke.
	function station.setActive(active: boolean)
		if not active then
			cancelStroke("station changed")
		end
	end

	-- Why there is nothing to cut, on the hint strip.
	function station.status(_snap: any): any
		return if current then nil else { text = "Take a pizza out of the oven to cut it" }
	end

	-- First-shift pointer: drag across the pizza for the first cut.
	function station.hint(_snap: any): any
		if current and #current.cuts == 0 then
			return { target = view.frame, text = "Drag across the pizza to cut", from = "left" }
		end
		return nil
	end

	return station
end

return Cut

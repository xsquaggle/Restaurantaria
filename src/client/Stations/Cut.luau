--!strict
-- Cutting station: drag across the pizza to cut. Cuts are freehand: the groove follows the
-- dragged path, and the server keeps that path and grades how straight and complete it is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Scoring = require(Shared.Scoring)
local CutStroke = require(Shared.CutStroke)
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Parent = script.Parent.Parent
local Motion = require(Parent.Motion)
local MotionPlan = require(Parent.MotionPlan)
local ServeGate = require(Parent.ServeGate)
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
	-- as Undo, clear of the pizza. It holds two lines, and on a phone each fits only about ten
	-- characters, so every hint here is two short lines.
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

	-- Serve serves the pizza the board shows (ServeGate, Astra r19 D1); onServe is set below.
	local gate = ServeGate.new()
	local onServe = function() end
	local serve = Widgets.button("Serve", function()
		onServe()
	end)
	serve:setIcon("icon_serve_white")
	serve.frame.Size = UDim2.fromScale(1, 1)
	serve.frame.Parent = ctx.actionHost("Cut")
	serve.hit.MouseButton1Down:Connect(function()
		ServeGate.press(gate, os.clock())
	end)

	-- The cutter: the generated wheel on its handle, resting on the board right of the
	-- pizza. While cutting it follows the pointer, its handle trailing the stroke and the
	-- wheel spinning with the distance rolled, then it glides back to rest. When the stroke
	-- records nothing more (lift, below) it lifts off the pizza until the release.
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
	-- While a stroke is held the handle turns see-through, so it never hides the groove it trails
	-- (open item fc-02); the wheel stays solid.
	local HANDLE_HELD = 0.55
	local GLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local PICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local lastPoint: Vector2? = nil
	-- A stroke that records nothing more (CutStroke.stopped: the sample limit, or a jump back
	-- across the dough) lifts the cutter off the pizza (Astra r17, D2): it grows a little, its
	-- wheel turns see-through and stops rolling, and the hint asks to let go, so the groove
	-- visibly ends where the cut ends. Letting go places exactly that cut; another cut needs a
	-- new press. Scale, wheel transparency and time are proposals.
	local LIFT_SCALE = 1.1
	local LIFT_WHEEL = 0.4
	local LIFT_TIME = 0.14
	local cutterScale = Motion.scale(cutter)
	local liftKey = {}
	local lifted = false

	-- One instruction owner for the gesture (Astra r19 R19-02, r20 R20-07): the chip on the
	-- board and the hint strip (with the first shift's glove) read the same state, so they never
	-- disagree. A lifted stroke asks to let go on both; a refused stroke shows its correction on
	-- both for at least REFUSAL_HOLD s (a snapshot refresh does not replace it) or until the next
	-- press; otherwise the chip shows the cut count and the strip the drag instruction (first
	-- shift) or nothing. The chip holds two short lines, the strip one.
	local GESTURE = { lifted = "Let go\nto finish", refused = "Cut all the\nway across" }
	local REFUSAL_HOLD = 1.6
	local refusedUntil = 0
	local countText = ""
	local function gesture(now: number): string?
		if lifted then
			return GESTURE.lifted
		elseif now < refusedUntil then
			return GESTURE.refused
		end
		return nil
	end
	local function paintGuide()
		guide.Text = gesture(os.clock()) or countText
	end

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
				if not lifted then
					wheel.Rotation += math.deg(d.Magnitude / (wheelD / 2))
				end
			end
		end
	end

	-- Drag to cut. Drags may start anywhere on the work surface, so a stroke that begins just off the
	-- crust still counts. One stroke at a time: it belongs to the input that started it (the
	-- mouse, or that one finger) and to the pizza it started on; other fingers are ignored and
	-- a ticket or station change, or a resize of the pizza, cancels it without cutting. The drag
	-- is recorded as one append-only list of samples (CutStroke, slice 3): the live groove and
	-- the cutter show those samples' outputs (assisted when the shift has the assist on), the
	-- release sends exactly those samples, and the server rebuilds the same outputs from them.
	type Stroke = {
		input: InputObject,
		mouse: boolean,
		button: Enum.UserInputType,
		pizzaId: number,
		dough: any, -- the pizza's footprint (Scoring.footprint), fixed for the stroke
		assist: boolean, -- the shift's cutting assist when the stroke began
		stream: CutStroke.Stream,
		view: { Vector2 }, -- the pizza's screen position and size when the stroke began
	}
	local stroke: Stroke? = nil
	local assistOn = false

	-- Pizza-local point of a screen position, not clamped, through the view frozen at the press.
	local function rawLocal(position: Vector3, frozen: { Vector2 }?): Vector2
		local at, size = view.frame.AbsolutePosition, view.frame.AbsoluteSize
		if frozen then
			at, size = frozen[1], frozen[2]
		end
		local rel = (Vector2.new(position.X, position.Y) - at) / size
		return Vector2.new(rel.X * 2 - 1, rel.Y * 2 - 1)
	end
	local function trace(line: string)
		local log = IS_STUDIO and LocalPlayer:GetAttribute("RestaurantariaCutTrace")
		if type(log) == "string" and #log < 60000 then
			LocalPlayer:SetAttribute("RestaurantariaCutTrace", log .. string.format("%.3f %s\n", os.clock(), line))
		end
	end
	local function pathLength(path: { any }): number
		local total = 0
		for i = 2, #path do
			total += math.sqrt((path[i].x - path[i - 1].x) ^ 2 + (path[i].y - path[i - 1].y) ^ 2)
		end
		return total
	end
	-- The groove grows behind the cutter: the samples' outputs, clipped to the dough as the grade
	-- clips them. It is faint until the server's own grading of these samples would accept the
	-- cut (CutStroke.grade on the same footprint), so it never promises a cut the release would
	-- drop. Runs already drawn never change as the stroke grows (CutStroke.runs).
	local function drawGroove(st: Stroke)
		st.stream.dirty = false
		local strong = CutStroke.grade(st.stream.points, st.dough, st.assist) ~= nil
		Ui.clear(preview)
		Widgets.drawCut(preview, { path = st.stream.out }, if strong then 0.3 else 0.7, st.dough)
	end
	-- Where the wheel touches: the pointer moved by the newest sample's correction, so the wheel
	-- runs on the line the groove shows.
	local function contact(st: Stroke, point: Vector2): Vector2
		local c = CutStroke.lastCorrection(st.stream)
		local size = st.view[2]
		return point + Vector2.new(c.x * size.X / 2, c.y * size.Y / 2)
	end
	-- Scale and wheel transparency from where they are to (scale, wheel) over `duration`.
	local function liftTo(scale: number, wheelTransparency: number, duration: number)
		if Motion.reduced() then
			Motion.stop(liftKey)
			cutterScale.Scale, wheel.ImageTransparency = scale, wheelTransparency
			return
		end
		local fromScale, fromWheel = cutterScale.Scale, wheel.ImageTransparency
		Motion.run(liftKey, duration, function(t: number)
			local e = MotionPlan.easeOut(t)
			cutterScale.Scale = fromScale + (scale - fromScale) * e
			wheel.ImageTransparency = fromWheel + (wheelTransparency - fromWheel) * e
		end)
	end
	local function lift(st: Stroke)
		if lifted then
			return
		end
		lifted = true
		paintGuide()
		liftTo(LIFT_SCALE, LIFT_WHEEL, LIFT_TIME)
		trace(string.format("stopped %s points=%d", if st.stream.full then "full" else "closed", #st.stream.points))
	end
	-- Back down as it glides home.
	local function land()
		if not lifted then
			return
		end
		lifted = false
		paintGuide()
		liftTo(1, 0, GLIDE.Time)
	end
	local function endStroke()
		stroke, lastPoint = nil, nil
		Ui.clear(preview)
		handleImg.ImageTransparency = 0
		land()
		TweenService:Create(cutter, GLIDE, { Position = rest, Rotation = REST_ANGLE }):Play()
	end
	local function cancelStroke(reason: string)
		if stroke then
			trace("cancel " .. reason .. " pizza=" .. stroke.pizzaId)
			endStroke()
		end
	end
	-- A held stroke whose release never arrived (focus lost, window switched) would block every
	-- new press until a ticket or station change; a new press finds it stale and drops it. A
	-- mouse button can't be pressed again without being released, so a new press of the
	-- stroke's own button means its release was lost. (Asking whether the button is held can't
	-- tell: during the new press it is. Roblox may hand the new press the same InputObject, so
	-- the input's identity can't tell either.) A finger's stroke is stale once its touch ended.
	local function stale(st: Stroke, input: InputObject, isMouse: boolean): boolean
		if st.mouse then
			return isMouse and input.UserInputType == st.button
		end
		return st.input.UserInputState == Enum.UserInputState.End or st.input.UserInputState == Enum.UserInputState.Cancel
	end

	-- A press anywhere on the work surface starts a stroke (slice 3): on a phone the board leaves
	-- only a few pixels around the crust, so a stroke may begin on the worktop beside the board
	-- and still reach across the pizza. Undo keeps its own presses.
	local function overUndo(position: Vector3): boolean
		local at, size = undo.frame.AbsolutePosition, undo.frame.AbsoluteSize
		return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
	end
	frame.InputBegan:Connect(function(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
			or (IS_STUDIO and LocalPlayer:GetAttribute("RestaurantariaCutButton2") == true and input.UserInputType == Enum.UserInputType.MouseButton2)
		if not isMouse and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if overUndo(input.Position) then
			return
		end
		if stroke and stale(stroke, input, isMouse) then
			cancelStroke("stale (release lost)")
		end
		if stroke or not current or ctx.pending[current.id] then
			trace("ignored begin " .. input.UserInputType.Name .. (if stroke then " (stroke held)" else ""))
			return
		end
		local frozen = { view.frame.AbsolutePosition, view.frame.AbsoluteSize }
		local p = rawLocal(input.Position, frozen)
		local dough = Scoring.footprint(current.make)
		local st: Stroke = {
			input = input,
			mouse = isMouse,
			button = input.UserInputType,
			pizzaId = current.id,
			dough = dough,
			assist = assistOn,
			stream = CutStroke.stream(dough, assistOn, { x = p.X, y = p.Y }),
			view = frozen,
		}
		stroke = st
		-- A new attempt ends the refusal's correction.
		refusedUntil = 0
		paintGuide()
		local s = st.stream.points[1]
		local point = toStation(input.Position)
		lastPoint = point
		handleImg.ImageTransparency = HANDLE_HELD
		TweenService:Create(cutter, PICK, { Position = UDim2.fromOffset(point.X, point.Y) }):Play()
		trace(string.format("begin %s screen=%.0f,%.0f local=%.4f,%.4f pizza=%d ticket=%d assist=%s", input.UserInputType.Name, input.Position.X, input.Position.Y, s.x, s.y, current.id, current.ticketId, tostring(assistOn)))
	end)
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		local st = stroke
		if not st then
			return
		end
		if (st.mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or (not st.mouse and input == st.input) then
			local p = rawLocal(input.Position, st.view)
			CutStroke.record(st.stream, { x = p.X, y = p.Y })
			if CutStroke.stopped(st.stream) then
				lift(st)
			end
			follow(contact(st, toStation(input.Position)))
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
		local p = rawLocal(input.Position, st.view)
		CutStroke.record(st.stream, { x = p.X, y = p.Y }, true)
		endStroke()
		if not current or current.id ~= st.pizzaId then
			trace("dropped: pizza changed")
			return
		end
		-- Exactly the recorded samples; the server's own grading of them on the same footprint
		-- runs first so a refusal is explained instead of sent.
		local path = st.stream.points
		local cut, reason = CutStroke.grade(path, st.dough, st.assist)
		if cut then
			local first, last = path[1], path[#path]
			trace(string.format("send %s screen=%.0f,%.0f points=%d from=%.4f,%.4f to=%.4f,%.4f length=%.3f angle=%.1f straight=%.3f dev=%.4f complete=%.3f assist=%s%s pizza=%d",
				input.UserInputType.Name, input.Position.X, input.Position.Y, #path, first.x, first.y, last.x, last.y, pathLength(path),
				math.deg(math.atan2(cut.y2 - cut.y1, cut.x2 - cut.x1)), cut.straightness :: number, cut.deviation, cut.completeness :: number,
				tostring(st.assist) .. (if st.assist and not cut.assisted then " kept-raw" else ""),
				if st.stream.filter.reason then " off:" .. st.stream.filter.reason else "", st.pizzaId))
			-- The sent samples themselves, so a recorded stroke can be replayed in the offline checks.
			local pts = table.create(#path)
			for i, q in path do
				pts[i] = string.format("%.4f,%.4f", q.x, q.y)
			end
			trace("path " .. table.concat(pts, " "))
			if st.assist then
				-- And their outputs, which the live groove showed and the server stores (unless the
				-- guard kept the raw path: "kept-raw" above).
				for i, q in st.stream.out do
					pts[i] = string.format("%.4f,%.4f", q.x, q.y)
				end
				trace("out " .. table.concat(pts, " "))
			end
			ctx.send("cut", { pizzaId = st.pizzaId, path = path }, function(ok, why)
				trace(string.format("reply ok=%s %s", tostring(ok), tostring(why)))
			end)
		else
			trace(string.format("refused locally: %s length=%.3f points=%d", tostring(reason), pathLength(path), #path))
			refusedUntil = os.clock() + REFUSAL_HOLD
			paintGuide()
		end
	end)

	onServe = function()
		local now = os.clock()
		local snap = ctx.snapshot
		local focus = if snap then ctx.focusPizza(snap, "cutting") else nil
		local id, ticketId, why = ServeGate.intent(gate, now, gate.shown ~= nil and ctx.pending[gate.shown] == true)
		-- Selected ticket, focused pizza, the board's pizza and its ticket, then what is sent.
		trace(string.format("serve press selected=%s focus=%s shown=%s ticket=%s -> %s", tostring(ctx.selectedTicket), tostring(focus and focus.id),
			tostring(gate.shown), tostring(gate.ticket), if id then string.format("send pizza=%d ticket=%d", id, ticketId :: number) else "none: " .. tostring(why)))
		if not id then
			-- Ignored, not an intent: the next press is not held back by the repeat guard.
			serve:forgive()
			return
		end
		local ticket = ticketId :: number
		ctx.pending[id] = true
		ctx.refresh()
		ctx.send("serve", { pizzaId = id, ticketId = ticket }, function(ok, reason)
			ctx.pending[id] = nil
			local result = nil
			local latest = ctx.snapshot
			if ok and latest then
				local c = ctx.customer(latest, ticket)
				result = c and c.status
			end
			trace(string.format("serve reply ok=%s %s pizza=%d ticket=%d ticketNow=%s", tostring(ok), tostring(reason), id, ticket, tostring(result)))
			if ok then
				ctx.showResult(ticket)
			end
			ctx.refresh()
		end)
	end

	local station = { frame = frame }

	function station.refresh(snap: any)
		assistOn = snap.cutAssist == true
		current = ctx.focusPizza(snap, "cutting")
		if stroke and (not current or current.id ~= stroke.pizzaId) then
			cancelStroke("ticket changed")
		end
		undo:setEnabled(current ~= nil and #current.cuts > 0)
		serve:setLabel(if current and ctx.pending[current.id] then "Serving..." else "Serve")
		local customer = if current then ctx.customer(snap, current.ticketId) else nil
		view.frame.Visible = current ~= nil and customer ~= nil
		if current and customer then
			local cuts = #current.cuts
			-- Cuts made against cuts needed: a freehand path need not make exactly 2 x cuts slices.
			countText = string.format("%d slices\nCuts %d / %d", customer.order.slices, cuts, customer.order.slices // 2)
			paintGuide()
			guideCard.Visible = true
			view:set(current, Widgets.doneness(current.bakeSeconds or 0), ctx.ovenStatus(customer.order.bake, current.bakeSeconds or 0).burnt)
			serve:setHighlighted(cuts == customer.order.slices // 2)
			-- Bound to Serve only now that the board shows it.
			ServeGate.show(gate, current.id, current.ticketId, os.clock())
		else
			guideCard.Visible = false
			ServeGate.show(gate, nil, nil, os.clock())
		end
		-- Serve keeps its look while settling or serving; ServeGate.intent ignores those presses.
		serve:setEnabled(ServeGate.enabled(gate))
	end

	local refusalShown = false
	function station.tick(_now: number)
		-- The refusal's correction ends on its own once held long enough.
		local refusing = os.clock() < refusedUntil
		if refusalShown and not refusing then
			paintGuide()
		end
		refusalShown = refusing
		local st = stroke
		if st then
			-- The view is frozen for the stroke: a resize or move of the pizza cancels it.
			if view.frame.AbsoluteSize ~= st.view[2] or view.frame.AbsolutePosition ~= st.view[1] then
				cancelStroke("view moved")
			elseif st.stream.dirty then
				drawGroove(st)
			end
		end
	end

	-- Leaving the station mid-stroke cancels the stroke.
	function station.setActive(active: boolean)
		if not active then
			cancelStroke("station changed")
		end
	end

	-- The strip's line on every shift: nothing to cut, or the gesture's instruction (the chip's
	-- own words on one line).
	local function gestureLine(): any
		local g = gesture(os.clock())
		return if g then { text = (g:gsub("\n", " ")) } else nil
	end
	function station.status(_snap: any): any
		if not current then
			return { text = "Take a pizza out of the oven to cut it" }
		end
		return gestureLine()
	end

	-- First-shift pointer: drag across the pizza for the first cut. The gesture's instruction
	-- wins (no glove then), and the glove keeps off the pizza while a stroke is held.
	function station.hint(_snap: any): any
		local line = gestureLine()
		if line then
			return line
		end
		if current and #current.cuts == 0 then
			if stroke then
				return { text = "Drag across the pizza to cut" }
			end
			return { target = view.frame, text = "Drag across the pizza to cut", from = "left" }
		end
		return nil
	end

	return station
end

return Cut

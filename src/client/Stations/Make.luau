--!strict
-- Make station (the tab once called Topping, then Prep; Lawson 2026-10-26): the whole manual
-- chain as ordered steps on one board. Flour the board, pull the dough onto it, roll it; sauce
-- and cheese are not hands-on yet, so "Next" adds them with today's look; then the toppings
-- (the Topping view, unchanged) and Send to oven. Steps never reopen; Undo works inside the
-- dough step only.
--
-- The dough step draws Astra's response-13 kit at its measured registration: the clean board
-- (P1), flour crock, scoop and dust stamps (F1-F4), the dough tub and ball (P2, P3), the six
-- rolled appearance keys (P4, crossfaded by mean radius and stretched to the exact scored oval,
-- so the rim thins with the body) and the rolling pin (P5). Every input is drawn at once and
-- sent to the server, which checks and keeps it (MakeDough); a refusal snaps the view back.
-- Actions for one pizza go out one at a time, so a reply can never land on a later one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeDough = require(Shared.MakeDough)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)
local Topping = require(script.Parent.Topping)

local C = Theme.Colour
local Make = {}

Make.background = Topping.background

-- Measured registration of the kit's full-canvas bodies (asset-manifest.json, response 13):
-- alpha share of the canvas on each axis, body centre on the canvas centre.
local DOUGH_BODY = { alphaX = 0.94921875, alphaY = 0.94921875, centreX = 0, centreY = 0 }
local BOARD_SHARE = 0.87890625 -- surface_prep_board alpha width / canvas
local PIN_SHARE = 0.87890625 -- tool_rolling_pin alpha width / canvas
local DUST_SHARE = 0.8633 -- fx_flour_dust alpha width / canvas
local CLUMP_SHARE = 0.8789
local SCOOP_SHARE_Y = 0.877 -- tool_flour_scoop alpha height / canvas
local ROLLS = { "food_dough_roll_01", "food_dough_roll_02", "food_dough_roll_03", "food_dough_roll_04", "food_dough_roll_05", "food_dough_roll_06" }
-- Proposals for how the tools sit (live layout, not balance): the pin's drawn length and the
-- scoop's drawn height as shares of the pizza frame F; the dust stamps' opacity.
local PIN_LENGTH = 0.6
local SCOOP_HEIGHT = 0.32
local DUST_OPACITY = 0.55
local DRAG_START = 6 -- pixels of travel before a press on the tub becomes a drag
local HANDOFF = TweenInfo.new(0.1, Enum.EasingStyle.Linear) -- ball out, rolled key in, same oval
local SNAP = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local STEP_NAMES = { flour = "Flour", dough = "Dough", roll = "Roll", sauce = "Sauce", cheese = "Cheese", toppings = "Toppings" }

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- The steps this ticket goes through, in order: Toppings only when it asks for some.
local function stepsFor(recipe: Recipes.Recipe?): { string }
	local list = { "flour", "dough", "roll", "sauce", "cheese" }
	if recipe and #recipe.toppings > 0 then
		table.insert(list, "toppings")
	end
	return list
end

-- A copy of a pizza's make record, deep enough to apply local actions to.
local function copyMake(m: any): any
	local flour = table.create(#m.flour)
	for i, s in m.flour do
		flour[i] = s
	end
	return { step = m.step, flour = flour, placed = m.placed, strokes = table.clone(m.strokes) }
end

local function signature(m: any): string
	return string.format("%s|%d|%d|%s|%d", m.step, #m.flour, MakeDough.stampCount(m), tostring(m.placed), #m.strokes)
end

-- What one action does to a make record (the server's rules, without the checks it makes).
local function applyOp(m: any, op: any)
	if op.action == "flour" then
		table.insert(m.flour, op.args.points)
	elseif op.action == "placeDough" then
		m.placed = true
	elseif op.action == "rollDough" then
		table.insert(m.strokes, { x1 = op.args.x1, y1 = op.args.y1, x2 = op.args.x2, y2 = op.args.y2 })
	elseif op.action == "undoDough" then
		if #m.strokes > 0 then
			table.remove(m.strokes)
		elseif m.placed then
			m.placed = false
		elseif #m.flour > 0 then
			table.remove(m.flour)
		end
	elseif op.action == "finishDough" then
		m.step = "toppings"
	end
end

function Make.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Make", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
	local toppingHolder = Ui.new("Frame", { Name = "ToppingStep", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local toppings = Topping.new(ctx, toppingHolder)
	local dough = Ui.new("Frame", { Name = "DoughStep", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = frame })

	-- Layout: the tool column (two across, three rows) on the left, the board on the right, as
	-- the Topping station's side layout and the Prep proof. Row 1 holds the step list, row 2
	-- the flour crock and the dough tub, row 3 the resting pin and Undo.
	local area = ctx.stationSize :: Vector2
	local W, H = area.X, area.Y
	local compact = ctx.compact
	local margin = if compact then 6 else math.clamp(math.round(H * 0.03), 6, 24)
	local gap = if compact then 4 else math.max(4, math.round(W * 0.01))
	local cellH = (H - margin * 2 - gap * 2) / 3
	local cellW = cellH * 76 / 62
	local gridW = cellW * 2 + gap
	-- The board meets the station's top and bottom on a phone (station 209 px: frame 188, the
	-- plan's 190 needs the hint strip's 3 px, not taken here).
	local matMax = math.min(H - (if compact then 0 else margin * 2), W - gridW - margin * 3)
	local F = math.floor(matMax * 0.9) -- the pizza frame: radius 1 in pizza-local units
	local mat = math.ceil(F / 0.9 - 1e-9)
	local left = margin * 2 + gridW
	local cx, cy = left + (W - margin - left) / 2, H / 2
	local function cell(col: number, row: number): (number, number)
		return margin + col * (cellW + gap), margin + row * (cellH + gap)
	end

	-- Board (P1) and the layers on it, bottom up: flour dust, the dough, the live tool.
	local boardCanvas = mat / BOARD_SHARE
	local board = Ui.new("ImageLabel", {
		Name = "Board",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(boardCanvas, boardCanvas),
		ZIndex = 1,
		Parent = dough,
	})
	Art.apply(board, "surface_prep_board")
	-- The input area: the board's visible disc (radius 1 / 0.9 in pizza-local units).
	local pad = Ui.new("Frame", {
		Name = "Pad",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(mat, mat),
		ZIndex = 1,
		Parent = dough,
	})
	local dustLayer = Ui.new("Frame", { Name = "Flour", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = dough })
	local ball = Ui.new("ImageLabel", { Name = "Ball", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Visible = false, Parent = dough })
	Art.apply(ball, "food_dough_ball")
	local keys: { ImageLabel } = {}
	for i, name in ROLLS do
		local img = Ui.new("ImageLabel", { Name = "Roll" .. i, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Visible = false, Parent = dough })
		Art.apply(img, name)
		keys[i] = img
	end
	local hand = Ui.new("Frame", { Name = "Hand", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = dough })
	local pinLen = F * PIN_LENGTH
	local pin = Ui.new("ImageLabel", {
		Name = "Pin",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(pinLen / PIN_SHARE, pinLen / PIN_SHARE),
		ZIndex = 21,
		Visible = false,
		Parent = hand,
	})
	Art.apply(pin, "tool_rolling_pin")
	local scoopCanvas = F * SCOOP_HEIGHT / SCOOP_SHARE_Y
	local scoop = Ui.new("ImageLabel", {
		Name = "Scoop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.75),
		Size = UDim2.fromOffset(scoopCanvas, scoopCanvas),
		Rotation = -20,
		ZIndex = 21,
		Visible = false,
		Parent = hand,
	})
	Art.apply(scoop, "tool_flour_scoop")
	local carried = Ui.new("ImageLabel", { Name = "CarriedBall", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 21, Visible = false, Parent = hand })
	Art.apply(carried, "food_dough_ball")

	-- Tool column.
	local function toolButton(name: string, art: string, col: number, row: number): ImageButton
		local x, y = cell(col, row)
		local b = Ui.new("ImageButton", {
			Name = name,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(cellW, cellH),
			ZIndex = 5,
			Parent = dough,
		})
		Art.apply(b, art)
		return b
	end
	local crock = toolButton("FlourCrock", "tool_flour_crock", 0, 1)
	local tub = toolButton("DoughTub", "tool_dough_tub", 1, 1)
	-- The ball waiting in the tub (a separate sprite on the tray, as the kit draws them).
	local tubBall = Ui.new("ImageLabel", {
		Name = "TubBall",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.4, 0.4),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 6,
		Parent = tub,
	})
	Art.apply(tubBall, "food_dough_ball")
	do
		local x, y = cell(0, 2)
		local rest = Ui.new("ImageLabel", {
			Name = "PinRest",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + cellW / 2, y + cellH / 2),
			Size = UDim2.fromOffset(cellW * 1.05, cellW * 1.05),
			Rotation = -12,
			ZIndex = 5,
			Parent = dough,
		})
		Art.apply(rest, "tool_rolling_pin")
	end

	-- Step list: every step of this ticket in order. The current step sits on the nav's coral
	-- pill; done steps are muted. Phones show the current step alone with its number.
	local stepsX, stepsY = cell(0, 0)
	local stepsBox = Ui.new("Frame", { Name = "Steps", BackgroundTransparency = 1, Position = UDim2.fromOffset(stepsX, stepsY), Size = UDim2.fromOffset(gridW, cellH), ZIndex = 5, Parent = dough })
	local function renderSteps(list: { string }, currentStep: string)
		Ui.clear(stepsBox)
		local index = table.find(list, currentStep) or 1
		if compact then
			Ui.text({
				Text = string.format("Step %d of %d", index, #list),
				FontFace = Theme.Font.bodySemi,
				TextSize = 14,
				TextColor3 = C.ink,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 18),
				ZIndex = 6,
				Parent = stepsBox,
			})
			local pill = Ui.new("ImageLabel", {
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Assets.Meta.navSelected.slice,
				SliceScale = 40 / Assets.Meta.navSelected.height,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 20),
				Size = UDim2.new(1, 0, 0, 40),
				ZIndex = 6,
				Parent = stepsBox,
			})
			Art.apply(pill, "ui_nav_tab_selected")
			local label = Ui.text({
				Text = STEP_NAMES[currentStep],
				FontFace = Theme.Font.display,
				TextSize = 18,
				TextColor3 = C.label,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 7,
				Parent = pill,
			})
			Ui.new("UIStroke", { Color = C.labelStroke, Thickness = 1, Parent = label })
			return
		end
		local cols = 3
		local rows = math.ceil(#list / cols)
		local chipW = (gridW - gap * (cols - 1)) / cols
		local chipH = math.min((cellH - gap * (rows - 1)) / rows, 72)
		local top = (cellH - (chipH * rows + gap * (rows - 1))) / 2
		local textSize = math.clamp(math.floor(chipH * 0.36), 18, 26)
		for i, step in list do
			local col, row = (i - 1) % cols, (i - 1) // cols
			local chip = Ui.new("Frame", {
				Name = "Step_" .. step,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(col * (chipW + gap), top + row * (chipH + gap)),
				Size = UDim2.fromOffset(chipW, chipH),
				ZIndex = 6,
				Parent = stepsBox,
			})
			local on = i == index
			if on then
				local pill = Ui.new("ImageLabel", {
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Slice,
					SliceCenter = Assets.Meta.navSelected.slice,
					SliceScale = chipH / Assets.Meta.navSelected.height,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 6,
					Parent = chip,
				})
				Art.apply(pill, "ui_nav_tab_selected")
			end
			local label = Ui.text({
				Text = string.format("%d %s", i, STEP_NAMES[step]),
				FontFace = Theme.Font.display,
				TextSize = textSize,
				TextColor3 = if on then C.label elseif i < index then C.mutedInk else C.ink,
				TextTransparency = if i < index then 0.25 else 0,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 7,
				Parent = chip,
			})
			if on then
				Ui.new("UIStroke", { Color = C.labelStroke, Thickness = 2, Parent = label })
			end
		end
	end

	------------------------------------------------------------------------------------------
	-- State: the server's make record for the focused pizza, plus this client's actions in
	-- order. One per pizza is in flight; the rest wait. While the server has not applied the
	-- in-flight action (its record still has the signature it had when the action went out),
	-- the view applies it locally.

	local current: any = nil
	local queues: { [number]: { inFlight: any?, waiting: { any } } } = {}
	local live: any = nil -- the held drag: { kind = "flour" | "roll" | "ball", input, ... }

	local function queueOf(id: number)
		local q = queues[id]
		if not q then
			q = { inFlight = nil, waiting = {} }
			queues[id] = q
		end
		return q
	end

	local function shown(pizza: any): any
		local m = copyMake(pizza.make)
		local q = queues[pizza.id]
		if q then
			if q.inFlight and signature(pizza.make) == q.inFlight.before then
				applyOp(m, q.inFlight)
			end
			for _, op in q.waiting do
				applyOp(m, op)
			end
		end
		return m
	end

	local pump: (number) -> ()
	pump = function(id: number)
		local q = queueOf(id)
		if q.inFlight or #q.waiting == 0 then
			return
		end
		local pizza = nil
		for _, p in (ctx.snapshot and ctx.snapshot.pizzas) or {} do
			if p.id == id then
				pizza = p
			end
		end
		if not pizza or pizza.stage ~= "topping" then
			q.waiting = {}
			return
		end
		local op = table.remove(q.waiting, 1)
		op.before = signature(pizza.make)
		q.inFlight = op
		ctx.send(op.action, op.args, function(ok)
			q.inFlight = nil
			if not ok then
				-- Everything queued after a refused action was built on it.
				q.waiting = {}
			end
			pump(id)
			ctx.refresh()
		end)
	end

	local function push(action: string, args: any)
		if not current then
			return
		end
		local id = current.id
		args.pizzaId = id
		table.insert(queueOf(id).waiting, { action = action, args = args })
		pump(id)
		ctx.refresh()
	end

	------------------------------------------------------------------------------------------
	-- Drawing

	local function toScreen(p: any): Vector2
		return Vector2.new(cx + p.x * F / 2, cy + p.y * F / 2)
	end
	local function toLocal(position: Vector3): Vector2
		local o = dough.AbsolutePosition
		return Vector2.new((position.X - o.X - cx) / (F / 2), (position.Y - o.Y - cy) / (F / 2))
	end

	local dustDrawn = 0
	local dustKey = ""
	local function drawFlour(m: any, extra: { any }?)
		local key = signature(m) .. "|" .. tostring(extra and #extra or 0)
		if key == dustKey then
			return
		end
		dustKey = key
		Ui.clear(dustLayer)
		dustDrawn = 0
		local dustD = 2 * Config.Make.flourRadius * F / 2
		local function stamp(p: any)
			dustDrawn += 1
			local s = toScreen(p)
			local excess = dustDrawn > Config.Make.flourPlenty
			local img = Ui.new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(s.X, s.Y),
				Size = if excess then UDim2.fromOffset(dustD * 0.45 / CLUMP_SHARE, dustD * 0.45 / CLUMP_SHARE) else UDim2.fromOffset(dustD / DUST_SHARE, dustD / DUST_SHARE),
				Rotation = (dustDrawn * 137.5) % 360,
				ImageTransparency = if excess then 0 else 1 - DUST_OPACITY,
				ZIndex = 2,
				Parent = dustLayer,
			})
			-- Past the plenty mark the extra flour shows as clumps (looks only).
			Art.apply(img, if excess then "fx_flour_clump" else "fx_flour_dust")
		end
		for _, strokeP in m.flour do
			for _, p in strokeP do
				stamp(p)
			end
		end
		for _, p in extra or {} do
			stamp(p)
		end
	end

	local ballShown = true
	local function drawDough(m: any, S: any)
		local e = G.ellipseOf(G.viewMatrix(S, F))
		local pl = G.bodyPlacement(e, DOUGH_BODY)
		local function place(img: ImageLabel)
			img.Size = UDim2.fromOffset(pl.width, pl.height)
			img.Rotation = pl.rotation
			img.Position = UDim2.fromOffset(cx + pl.offset.x, cy + pl.offset.y)
		end
		local rolled = #m.strokes > 0 or (live ~= nil and live.kind == "roll" and live.moved)
		if not m.placed then
			ball.Visible = false
			for _, k in keys do
				k.Visible = false
			end
			ballShown = true
			return
		end
		-- The ball until the first roll; then the rolled keys either side of the mean radius,
		-- the upper one crossfaded in. The ball hands off over 0.1 s on the same oval.
		place(ball)
		ball.Visible = true
		if not rolled then
			if not ballShown then
				ballShown = true
				ball.ImageTransparency = 0
			end
			for _, k in keys do
				k.Visible = false
			end
			return
		end
		if ballShown then
			ballShown = false
			ball.ImageTransparency = 0
			TweenService:Create(ball, HANDOFF, { ImageTransparency = 1 }):Play()
		end
		local i1, i2, w = G.stateBlend(G.meanRadius(S))
		for i, k in keys do
			local on = i == i1 or (i == i2 and w > 0)
			k.Visible = on
			if on then
				place(k)
				k.ZIndex = if i == i2 and i2 ~= i1 then 4 else 3
				k.ImageTransparency = if i == i2 and i2 ~= i1 then 1 - w else 0
			end
		end
	end

	-- The record to draw (server + this client's actions) and the live drag's preview.
	local function redraw()
		if not current then
			return
		end
		local m = shown(current)
		local S = MakeDough.shape(m)
		if live and live.kind == "roll" and live.moved then
			S = G.roll(S, live.from, live.to) or S
		end
		drawFlour(m, if live and live.kind == "flour" then live.points else nil)
		drawDough(m, S)
		tubBall.Visible = not m.placed and not (live and live.kind == "ball")
	end

	------------------------------------------------------------------------------------------
	-- Input

	local function phaseOf(): string
		return if current then MakeDough.phase(shown(current)) else "none"
	end

	local function flourAllowed(): boolean
		if not current or current.make.step ~= "dough" then
			return false
		end
		local m = shown(current)
		return not m.placed and MakeDough.stampCount(m) < Config.Make.flourMaxStamps
	end

	-- Flour: the drag drops stamps while it is over the board. Leaving the board, or a stroke
	-- reaching its stamp limit, sends what was dusted so far and starts a fresh stroke.
	local function flushFlour()
		if live and live.kind == "flour" and #live.points > 0 then
			push("flour", { points = live.points })
			live.points = {}
		end
	end
	local function flourAt(p: Vector2)
		local st = live
		if not st or st.kind ~= "flour" then
			return
		end
		local reach = Config.Make.flourReach
		-- Off the board the scoop drops nothing; over the board's rim the dust is pulled back
		-- inside, so it never lands off the board.
		if p.Magnitude > 1 / 0.9 then
			flushFlour()
			st.sampler = nil
			return
		end
		if p.Magnitude > reach then
			p = p.Unit * reach
		end
		if not st.sampler then
			st.sampler = MakeDough.flourSampler()
		end
		local m = shown(current)
		local budget = Config.Make.flourMaxStamps - MakeDough.stampCount(m) - #st.points
		for _, s in st.sampler.feed({ x = p.X, y = p.Y }) do
			if budget <= 0 then
				break
			end
			if s.x * s.x + s.y * s.y <= reach * reach + 1e-9 then
				table.insert(st.points, s)
				budget -= 1
				if #st.points >= Config.Make.flourMaxPerStroke then
					flushFlour()
					st.sampler = MakeDough.flourSampler()
					st.sampler.feed({ x = s.x, y = s.y })
				end
			end
		end
	end

	local function showScoop(position: Vector3?)
		scoop.Visible = position ~= nil
		if position then
			local o = dough.AbsolutePosition
			scoop.Position = UDim2.fromOffset(position.X - o.X, position.Y - o.Y)
		end
	end

	local function beginFlour(input: InputObject)
		live = { kind = "flour", input = input, points = {}, sampler = nil }
		showScoop(input.Position)
		flourAt(toLocal(input.Position))
		redraw()
	end

	local function placeBall()
		if current and phaseOf() == "dough" then
			push("placeDough", {})
		end
	end

	local function endLive(commit: boolean, input: InputObject?)
		local st = live
		if not st then
			return
		end
		live = nil
		scoop.Visible = false
		pin.Visible = false
		carried.Visible = false
		if st.kind == "flour" then
			if commit then
				if #st.points > 0 then
					push("flour", { points = st.points })
				end
			end
		elseif st.kind == "roll" then
			if commit and st.moved and current then
				local d = st.to - st.from
				local args = { x1 = st.from.X, y1 = st.from.Y, x2 = st.to.X, y2 = st.to.Y }
				if d.Magnitude >= Config.Make.minStroke and MakeDough.validateRoll(shown(current), args) then
					push("rollDough", args)
				end
			end
		elseif st.kind == "ball" then
			if commit and input then
				local p = toLocal(input.Position)
				-- A tap on the tub, or a drag released over the board, pulls the dough on.
				if not st.dragged or p.Magnitude <= 1 / 0.9 then
					placeBall()
				end
			end
		end
		redraw()
	end

	local function rollAt(position: Vector3)
		local st = live
		if not st or st.kind ~= "roll" then
			return
		end
		local p = toLocal(position)
		p = Vector2.new(math.clamp(p.X, -Config.Make.strokeReach, Config.Make.strokeReach), math.clamp(p.Y, -Config.Make.strokeReach, Config.Make.strokeReach))
		st.to = p
		local d = p - st.from
		if d.Magnitude > 0.02 then
			st.moved = true
			-- The pin lies across the stroke and rolls along it.
			pin.Rotation = math.deg(math.atan2(d.Y, d.X)) + 90
		end
		local o = dough.AbsolutePosition
		pin.Position = UDim2.fromOffset(position.X - o.X, position.Y - o.Y)
		pin.Visible = true
		redraw()
	end

	pad.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or live or not current then
			return
		end
		local p = toLocal(input.Position)
		if p.Magnitude > 1 / 0.9 then
			return
		end
		local phase = phaseOf()
		if phase == "flour" or (phase == "dough" and flourAllowed()) then
			if flourAllowed() then
				beginFlour(input)
			end
		elseif phase == "roll" then
			live = { kind = "roll", input = input, from = p, to = p, moved = false }
			rollAt(input.Position)
		end
	end)
	crock.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not live and flourAllowed() then
			-- The scoop comes out of the crock; dust lands once it is over the board.
			live = { kind = "flour", input = input, points = {}, sampler = nil }
			showScoop(input.Position)
		end
	end)
	tub.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not live and phaseOf() == "dough" then
			live = { kind = "ball", input = input, start = input.Position, dragged = false }
		end
	end)

	local function ownsInput(input: InputObject): boolean
		local st = live
		if not st then
			return false
		end
		local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
		return input == st.input or (isMouse and st.input.UserInputType == Enum.UserInputType.MouseButton1)
	end
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		local st = live
		if not st or not ownsInput(input) then
			return
		end
		if st.kind == "flour" then
			showScoop(input.Position)
			flourAt(toLocal(input.Position))
			redraw()
		elseif st.kind == "roll" then
			rollAt(input.Position)
		elseif st.kind == "ball" then
			local travel = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(st.start.X, st.start.Y)).Magnitude
			if travel >= DRAG_START then
				st.dragged = true
				local d = G.BALL * F / DOUGH_BODY.alphaX
				carried.Size = UDim2.fromOffset(d, d)
				local o = dough.AbsolutePosition
				carried.Position = UDim2.fromOffset(input.Position.X - o.X, input.Position.Y - o.Y)
				carried.Visible = true
				redraw()
			end
		end
	end)
	ctx.connect(UserInputService.InputEnded, function(input: InputObject)
		local st = live
		if not st or not isPress(input) then
			return
		end
		if input ~= st.input and input.UserInputType ~= st.input.UserInputType then
			return
		end
		endLive(true, input)
	end)

	-- Undo, inside the dough step only: the last roll, then the ball, then the last flour stroke.
	local function doUndo()
		if live or not current or current.make.step ~= "dough" then
			return
		end
		local m = shown(current)
		if #m.flour == 0 and not m.placed then
			return
		end
		push("undoDough", {})
	end
	local undo = Widgets.button("Undo", doUndo, "secondary")
	undo:setIcon("icon_undo")
	do
		local x, y = cell(1, 2)
		local w = if compact then math.max(86, cellW) else cellW
		undo.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		undo.frame.Position = UDim2.fromOffset(x + cellW / 2, y + cellH / 2)
		undo.frame.Size = UDim2.fromOffset(w, math.max(56, math.min(cellH * 0.6, 64)))
		undo.frame.ZIndex = 5
		undo.frame.Parent = dough
	end
	-- Rail action for the dough step: on to sauce and cheese (added for the player until they are
	-- hands-on steps). Shares the Make action slot with Topping's Send to oven.
	local finishing: number? = nil
	local nextButton = Widgets.button("Next: sauce & cheese", function()
		if live or not current or finishing == current.id then
			return
		end
		if not MakeDough.canFinish(shown(current)) then
			return
		end
		finishing = current.id
		push("finishDough", { from = "dough" })
	end)
	nextButton.frame.Size = UDim2.fromScale(1, 1)
	nextButton.frame.Visible = false
	nextButton.frame.Parent = ctx.actionHost("Topping")

	------------------------------------------------------------------------------------------

	local station = { frame = frame }
	local stepsKey = ""

	function station.refresh(snap: any)
		toppings.refresh(snap)
		local focus = ctx.focusPizza(snap, "topping")
		if current and (not focus or focus.id ~= current.id) then
			-- Another ticket: a held drag stays with the pizza it started on, so drop it.
			endLive(false)
		end
		current = focus
		local inDough = current ~= nil and current.make.step == "dough"
		if finishing and (not current or current.id ~= finishing or not inDough) then
			finishing = nil
		end
		dough.Visible = inDough
		toppingHolder.Visible = not inDough
		nextButton.frame.Visible = inDough
		toppings.sendButton.frame.Visible = not inDough
		local customer = current and ctx.customer(snap, current.ticketId)
		local recipe = customer and Recipes.ById[customer.order.recipe]
		local m = if current then shown(current) else nil
		local phase = if m then MakeDough.phase(m) else "none"
		local stepName = if phase == "done" then "toppings" elseif phase == "none" then "flour" else phase
		local list = stepsFor(recipe)
		local key = table.concat(list, ",") .. "|" .. stepName
		if inDough and key ~= stepsKey then
			stepsKey = key
			renderSteps(list, stepName)
		end
		if inDough and m then
			undo:setEnabled(not live and (#m.flour > 0 or m.placed))
			local busy = finishing ~= nil
			nextButton:setEnabled(not busy and MakeDough.canFinish(m))
			nextButton:setLabel(if busy then "Adding..." elseif compact then "Next" else "Next: sauce & cheese")
			crock.ImageTransparency = if flourAllowed() then 0 else 0.45
			tub.ImageTransparency = if phase == "dough" then 0 else 0.45
			redraw()
		end
	end

	function station.tick(now: number)
		toppings.tick(now)
	end

	function station.setActive(active: boolean)
		if not active then
			endLive(false)
		end
	end

	-- Why the rail's action is unavailable, on the hint strip.
	function station.status(snap: any): any
		if not current or current.make.step ~= "dough" then
			return toppings.status(snap)
		end
		local phase = phaseOf()
		if phase == "flour" then
			return { text = "Drag the scoop across the board to flour it" }
		elseif phase == "dough" then
			return { text = "Drag the dough from the tub onto the board" }
		elseif phase == "roll" and #shown(current).strokes == 0 then
			return { text = "Drag across the dough to roll it out" }
		end
		return nil
	end

	-- First-shift pointer, one lesson per part of the dough step, then Topping's own.
	function station.hint(snap: any): any
		if not current then
			return nil
		end
		if current.make.step ~= "dough" then
			if ctx.learned["Make.toppings"] then
				return nil
			end
			return toppings.hint(snap)
		end
		local phase = phaseOf()
		if phase == "flour" and not ctx.learned["Make.flour"] then
			return { target = crock, text = "Drag the scoop across the board to flour it", from = if compact then "right" else "below" }
		elseif phase == "dough" and not ctx.learned["Make.dough"] then
			return { target = tub, text = "Drag the dough onto the floured board", from = if compact then "right" else "below" }
		elseif phase == "roll" then
			local m = shown(current)
			if #m.strokes == 0 and not ctx.learned["Make.roll"] then
				return { target = ball, text = "Drag across the dough to roll it out", from = "below" }
			end
			if MakeDough.canFinish(m) and not ctx.learned["Make.next"] then
				if G.meanRadius(MakeDough.shape(m)) >= Config.Make.sizeFullLow then
					return { target = nextButton.frame, text = "Round and full size: tap Next", from = if compact then "aboveLeft" else "left" }
				end
				-- Between the first roll and full size Next already works, so the first shift
				-- says what full size looks like before pointing at it.
				return { target = pad, text = "Keep rolling until the dough reaches the rim", from = "below" }
			end
		end
		return nil
	end

	return station
end

return Make

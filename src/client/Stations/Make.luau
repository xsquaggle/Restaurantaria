--!strict
-- Make station (the tab once called Topping, then Prep; Lawson 2026-10-26): the whole manual
-- chain as ordered steps on one board. Flour the board, pull the dough onto it, roll it; pour and
-- spread the sauce; sprinkle the cheese; then the toppings (the Topping view, drawn on the
-- player's own dough, sauce and cheese) and Send to oven. Steps never reopen; Undo works inside
-- the current step.
--
-- The dough step draws Astra's response-13 kit at its measured registration: the clean board
-- (P1), flour crock, scoop and dust stamps (F1-F4), the dough tub and ball (P2, P3), the six
-- rolled appearance keys (P4, crossfaded by mean radius and stretched to the exact scored oval,
-- so the rim thins with the body) and the rolling pin (P5). The sauce step draws the pot and
-- ladle (P6), the sauce as soft stamps and dollops (P9, P7; MakeLayers); the cheese step the
-- bowl (P10) and the pinches (P11). Every input is drawn at once and sent to the server, which
-- checks and keeps it (MakeDough, MakeSauce, MakeCheese); a refusal snaps the view back.
--
-- Roll: a held drag is split into passes where the pointer turns (MakeDough.rollDrag), so rolling
-- back and forth in one hold is several passes, each sent as it ends; the open pass is previewed
-- and only grows. The pin lies across its pass and keeps its turn when the pass reverses; the
-- dough art turns as little as its outline allows (PrepGeometry.steadyEllipse).
--
-- Sauce: a press on the dough is a pour unless it moves Config.Sauce.tapPixels first, then it is
-- a spread (plan rev 6, D8); a drag from the pot pours where it is released. The live spread is
-- the server's own spread function applied to the path so far. Cheese: hold and drag to
-- sprinkle (PrepFood.sampler); pinches are drawn at once and sent in batches of up to
-- Config.Cheese.batchSize, one batch every Config.Cheese.batchGap s while held, the rest on
-- release.
-- Actions for one pizza go out one at a time, so a reply can never land on a later one.
--
-- Studio play tests only: RestaurantariaMakeButton2 = true on the local player (set from the
-- Client command bar) lets a driver whose injected primary button arrives as MouseButton2
-- (swapped buttons) make real-mouse drags, as Cut's RestaurantariaCutButton2 does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeCheese = require(Shared.MakeCheese)
local MakeDough = require(Shared.MakeDough)
local MakeSauce = require(Shared.MakeSauce)
local PrepFood = require(Shared.PrepFood)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local MakeLayers = require(Parent.MakeLayers)
local Motion = require(Parent.Motion)
local MotionPlan = require(Parent.MotionPlan)
local StationLayout = require(Parent.StationLayout)
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
local LADLE_SHARE_Y = 0.859375 -- tool_ladle_loaded / _empty alpha height / canvas
local ROLLS = { "food_dough_roll_01", "food_dough_roll_02", "food_dough_roll_03", "food_dough_roll_04", "food_dough_roll_05", "food_dough_roll_06" }
-- Proposals for how the tools sit (live layout, not balance): the pin's drawn length and the
-- scoop's drawn height as shares of the pizza frame F; the dust stamps' opacity.
local PIN_LENGTH = 0.6
local SCOOP_HEIGHT = 0.32
local LADLE_HEIGHT = 0.5
local DUST_OPACITY = 0.55
local DRAG_START = 6 -- pixels of travel before a press on the tub becomes a drag
local HANDOFF = TweenInfo.new(0.1, Enum.EasingStyle.Linear) -- ball out, rolled key in, same oval
-- Rolling motion (Lawson 2026-10-28, proposals): the dough art keeps its turn while its drawn
-- outline stays within ART_TOL px of the scored one (PrepGeometry.steadyEllipse); the pin eases
-- to its pass's turn with time constant PIN_EASE s, pops as it is picked up and glides back to
-- its rest over PIN_HOME s when let go.
local ART_TOL = 1
local PIN_EASE = 0.045
local PIN_HOME = 0.26
local PIN_REST_TURN = -12
-- The drawn dough eases onto its shape with time constant DOUGH_EASE s while it grows (a held pass
-- shows only once the server would keep it, minStroke long, so it takes up its growth here
-- instead of jumping). Shrinking (Undo) and a new pizza snap. Proposal.
local DOUGH_EASE = 0.06
local SNAP = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local STEP_NAMES = { flour = "Flour", dough = "Dough", roll = "Roll", sauce = "Sauce", cheese = "Cheese", toppings = "Toppings" }

local IS_STUDIO = RunService:IsStudio()

local function isMouseButton(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or (IS_STUDIO and Players.LocalPlayer:GetAttribute("RestaurantariaMakeButton2") == true and input.UserInputType == Enum.UserInputType.MouseButton2)
end

local function isPress(input: InputObject): boolean
	return isMouseButton(input) or input.UserInputType == Enum.UserInputType.Touch
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
	local cheese = table.create(#m.cheese.strokes)
	for i, s in m.cheese.strokes do
		cheese[i] = table.clone(s)
	end
	return {
		step = m.step,
		flour = flour,
		placed = m.placed,
		strokes = table.clone(m.strokes),
		sauce = { actions = table.clone(m.sauce.actions) },
		cheese = { strokes = cheese },
	}
end

local function signature(m: any): string
	return string.format("%s|%d|%d|%s|%d|%d|%d|%d", m.step, #m.flour, MakeDough.stampCount(m), tostring(m.placed), #m.strokes, #m.sauce.actions, #m.cheese.strokes, MakeCheese.count(m.cheese))
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
		m.step = "sauce"
	elseif op.action == "pourSauce" then
		table.insert(m.sauce.actions, { kind = "pour", x = op.args.x, y = op.args.y })
	elseif op.action == "spreadSauce" then
		table.insert(m.sauce.actions, { kind = "spread", points = op.args.points })
	elseif op.action == "undoSauce" then
		table.remove(m.sauce.actions)
	elseif op.action == "finishSauce" then
		m.step = "cheese"
	elseif op.action == "addCheese" then
		MakeCheese.add(m.cheese, op.args.points, op.args.newStroke == true or #m.cheese.strokes == 0)
	elseif op.action == "undoCheese" then
		table.remove(m.cheese.strokes)
	elseif op.action == "finishCheese" then
		m.step = "toppings"
	end
end

-- The steps drawn on the board (the rest is the Topping view).
local ON_BOARD = { dough = true, sauce = true, cheese = true }

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
	-- The numbers live in StationLayout (offline-checked): on a 667x375 phone the station is
	-- 212 px tall, so the board meets its top and bottom with the agreed 190 px pizza frame and
	-- a 212 px mat.
	local L = StationLayout.make(W, H, compact)
	local margin, gap, cellW, cellH, gridW = L.margin, L.gap, L.cellW, L.cellH, L.gridW
	local F, mat = L.F, L.mat
	local cx, cy = L.cx, L.cy
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
	-- Rolling target (Astra r15): a faint band over the full-size range (Config.Make sizeFullLow
	-- to sizeFullHigh of the frame radius, the dough's mean semi-axis that Size grades) with a
	-- thin line at 1.00, behind the dough, shown only while rolling. A code-drawn stand-in
	-- until her P1 ring art arrives; it follows the scored numbers, so the hint can name its
	-- "inner guide edge". Not a perfect-dough mark: roundness and flour are graded apart.
	local guide = Ui.new("Frame", { Name = "RollGuide", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Visible = false, Parent = dough })
	do
		local R = F / 2
		local low, high = Config.Make.sizeFullLow, Config.Make.sizeFullHigh
		local function ring(name: string, radius: number, thickness: number, transparency: number)
			-- A UIStroke grows outward from its frame's edge.
			Ui.new("Frame", {
				Name = name,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx, cy),
				Size = UDim2.fromOffset(radius * 2, radius * 2),
				ZIndex = 2,
				Parent = guide,
			}, {
				Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Ui.new("UIStroke", { Color = C.ink, Thickness = thickness, Transparency = transparency }),
			})
		end
		ring("Band", low * R, (high - low) * R, 0.72)
		local line = if compact then 1 else 2
		ring("Line", R - line / 2, line, 0.35)
	end
	local dustLayer = Ui.new("Frame", { Name = "Flour", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = dough })
	local ball = Ui.new("ImageLabel", { Name = "Ball", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Visible = false, Parent = dough })
	Art.apply(ball, "food_dough_ball")
	local keys: { ImageLabel } = {}
	for i, name in ROLLS do
		local img = Ui.new("ImageLabel", { Name = "Roll" .. i, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Visible = false, Parent = dough })
		Art.apply(img, name)
		keys[i] = img
	end
	-- The dough step's pictures that first show mid-action (the rolled keys, the pin and scoop
	-- in the hand, the flour stamps) load with the station, so none is blank the first time.
	Art.preload({ "food_dough_ball", "tool_rolling_pin", "tool_flour_scoop", "fx_flour_dust", "fx_flour_clump", table.unpack(ROLLS) })
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(scoopCanvas, scoopCanvas),
		Rotation = StationLayout.SCOOP_TILT,
		ZIndex = 21,
		Visible = false,
		Parent = hand,
	})
	Art.apply(scoop, "tool_flour_scoop")
	local carried = Ui.new("ImageLabel", { Name = "CarriedBall", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 21, Visible = false, Parent = hand })
	Art.apply(carried, "food_dough_ball")
	-- The ladle in the hand: loaded (tipped) for a pour, empty for a spread; its bowl's centre
	-- on the pointer at either tilt (StationLayout.toolCentre).
	local ladleCanvas = F * LADLE_HEIGHT / LADLE_SHARE_Y
	local ladle = Ui.new("ImageLabel", {
		Name = "Ladle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(ladleCanvas, ladleCanvas),
		ZIndex = 21,
		Visible = false,
		Parent = hand,
	})
	Art.apply(ladle, "tool_ladle_loaded")
	-- The player's sauce and cheese, between the dough and the hand.
	local food = MakeLayers.new(dough, 5)

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
	-- The sauce and cheese steps' tools take the same two cells.
	local pot = toolButton("SaucePot", "tool_sauce_pot", 0, 1)
	local bowl = toolButton("CheeseBowl", "tool_cheese_bowl", 1, 1)
	local pinRest: ImageLabel
	do
		local x, y = cell(0, 2)
		local rest = Ui.new("ImageLabel", {
			Name = "PinRest",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + cellW / 2, y + cellH / 2),
			Size = UDim2.fromOffset(cellW * 1.05, cellW * 1.05),
			Rotation = PIN_REST_TURN,
			ZIndex = 5,
			Parent = dough,
		})
		Art.apply(rest, "tool_rolling_pin")
		pinRest = rest
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
	local pinHome: (glide: boolean) -> ()
	local pinTick: () -> ()
	local readyPulse: () -> ()
	local queues: { [number]: { inFlight: any?, waiting: { any } } } = {}
	local live: any = nil -- the held drag: { kind = "flour" | "roll" | "ball" | "ladle" | "pot" | "cheese", input, mouse, button, ... }
	local finishing: number? = nil -- the pizza whose Next is on its way
	local finishingFrom = "" -- and the step it leaves

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

	local FINISH = { finishDough = true, finishSauce = true, finishCheese = true }

	-- An action that will never land: if it was Next, its button stops saying "Adding...".
	local function dropped(id: number, op: any)
		if FINISH[op.action] and finishing == id then
			finishing = nil
		end
	end
	local function dropWaiting(id: number, q: any)
		for _, op in q.waiting do
			dropped(id, op)
		end
		q.waiting = {}
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
			dropWaiting(id, q)
			return
		end
		local op = table.remove(q.waiting, 1)
		op.before = signature(pizza.make)
		q.inFlight = op
		ctx.send(op.action, op.args, function(ok)
			q.inFlight = nil
			if not ok then
				-- Everything queued after a refused action was built on it.
				dropped(id, op)
				dropWaiting(id, q)
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
	-- Uploaded art draws nothing until it has loaded, and a label that is not on screen does not
	-- start loading: in Studio play each rolled key first showed blank for a frame or more, so
	-- the dough flashed see-through as its picture changed (Lawson 2026-10-28, real mouse: "I
	-- could see gaps of the asset switching"). The keys load with the station (Art.preload,
	-- where they are made) and are drawn under the ball before the first roll; until the key
	-- that should cover the dough has loaded, the key that last did stays drawn under it, or
	-- the ball stays up.
	local coverKey: ImageLabel? = nil -- the last base key drawn once it had loaded
	local waitKey: ImageLabel? = nil -- a base key drawn before it loaded (the tick redraws on load)
	-- The dough art's last turn (radians) and the pizza it was drawn for: each drawing turns the
	-- art as little as the outline allows (PrepGeometry.steadyEllipse), so it never spins.
	local artTurn = 0
	local artFor: number? = nil
	local function drawDough(m: any, S: any, previewing: boolean)
		local id = if current then current.id else nil
		if not m.placed or id ~= artFor then
			artTurn, artFor = 0, id
		end
		local drawn = G.steadyEllipse(G.ellipseOf(G.viewMatrix(S, F)), artTurn, ART_TOL)
		artTurn = drawn.angle
		local pl = G.bodyPlacement(drawn, DOUGH_BODY)
		local function place(img: ImageLabel)
			img.Size = UDim2.fromOffset(pl.width, pl.height)
			img.Rotation = pl.rotation
			img.Position = UDim2.fromOffset(cx + pl.offset.x, cy + pl.offset.y)
		end
		local rolled = #m.strokes > 0 or previewing
		if not m.placed then
			-- Hardening (Astra r19, not reproduced live): a ticket reset must not leave the ball
			-- faded from an earlier hand-off.
			ball.ImageTransparency = 0
			ball.Visible = false
			for _, k in keys do
				k.Visible = false
			end
			ballShown, waitKey = true, nil
			return
		end
		-- The ball until the first roll; then the rolled keys either side of the mean radius,
		-- the upper one crossfaded in. The ball hands off over 0.1 s on the same oval once a
		-- loaded key is under it.
		place(ball)
		ball.Visible = true
		if not rolled then
			if not ballShown then
				ballShown = true
				ball.ImageTransparency = 0
			end
			-- Even preloaded, a key is ready a frame or more after it is first drawn (the fourth
			-- took 0.38 s in Studio play), so each key not ready yet is drawn as one pixel under
			-- the ball's centre: by the first roll every key is.
			for _, k in keys do
				k.Visible = not k.IsLoaded
				k.Size, k.Position, k.Rotation = UDim2.fromOffset(1, 1), ball.Position, 0
				k.ZIndex, k.ImageTransparency = 3, 0
			end
			waitKey = nil
			return
		end
		local i1, i2, w = G.stateBlend(G.meanRadius(S))
		local base = keys[i1]
		local under: ImageLabel? = nil
		if base.IsLoaded then
			coverKey, waitKey = base, nil
		else
			under, waitKey = coverKey, base
		end
		for i, k in keys do
			local top = i == i2 and i2 ~= i1
			local on = i == i1 or (top and w > 0) or k == under
			k.Visible = on
			if on then
				place(k)
				if k == under then
					k.ZIndex, k.ImageTransparency = 2, 0
				else
					k.ZIndex = if top then 4 else 3
					k.ImageTransparency = if top then 1 - w else 0
				end
			end
		end
		if ballShown and (base.IsLoaded or under ~= nil) then
			ballShown = false
			ball.ImageTransparency = 0
			TweenService:Create(ball, HANDOFF, { ImageTransparency = 1 }):Play()
		end
	end

	-- The sauce field of a record (MakeSauce's replay memo: a frame with no new action replays
	-- nothing). Shared: read it, never change it.
	local function sauceField(m: any): { number }
		return (MakeSauce.replay(m.sauce))
	end

	-- The dough as it shows: the committed rolls plus the open pass of a held roll once the server
	-- would keep it (MakeDough.preview). It only grows while a pass is held, and the release
	-- commits exactly what was shown, so nothing snaps back. Also true when that pass shows.
	local function shownShape(m: any): (any, boolean)
		local open = if live and live.kind == "roll" then live.drag.line() else nil
		return MakeDough.preview(m, open), MakeDough.keptPass(m, open) ~= nil
	end

	-- The drawn dough, eased onto the shown shape while it grows (DOUGH_EASE).
	local easedS: any = nil
	local easedFor: number? = nil
	local easedClock: number? = nil
	local doughEasing = false
	local function easeDough(m: any, S: any): any
		local id = if current then current.id else nil
		local now = Motion.now()
		local dt = if easedClock then math.clamp(now - easedClock, 0, 0.1) else 0
		easedClock = now
		if not easedS or easedFor ~= id or not m.placed or Motion.reduced() or G.meanRadius(S) < G.meanRadius(easedS) - 1e-6 then
			easedS, easedFor, doughEasing = S, id, false
			return S
		end
		local k = 1 - math.exp(-dt / DOUGH_EASE)
		local E = easedS
		local next = G.mat(E.a + (S.a - E.a) * k, E.b + (S.b - E.b) * k, E.c + (S.c - E.c) * k, E.d + (S.d - E.d) * k)
		local gap = math.max(math.abs(S.a - next.a), math.abs(S.b - next.b), math.abs(S.c - next.c), math.abs(S.d - next.d))
		if gap < 1e-4 then
			next = S
		end
		easedS, doughEasing = next, gap >= 1e-4
		return next
	end

	-- The record to draw (server + this client's actions) and the live drag's preview.
	local function redraw()
		if not current then
			return
		end
		local m = shown(current)
		local S, previewing = shownShape(m)
		drawFlour(m, if live and live.kind == "flour" then live.drag.points else nil)
		if m.step == "dough" then
			drawDough(m, easeDough(m, S), previewing)
		else
			easedS, doughEasing = nil, false
			drawDough(m, S, false)
		end
		tubBall.Visible = not m.placed and not (live and live.kind == "ball")
		guide.Visible = m.step == "dough" and m.placed
		-- Sauce and cheese, on the dough as it is now (its shape is fixed once rolled).
		if m.step == "dough" then
			food.frame.Visible = false
			return
		end
		food.frame.Visible = true
		food:place(cx, cy, F, S)
		local field = sauceField(m)
		if live and live.kind == "ladle" and live.moved then
			field = table.clone(field)
			MakeSauce.spread(field, live.preview)
		end
		food:sauce(field, m.sauce.actions)
		local pinches = MakeCheese.pinches(m.cheese)
		if live and live.kind == "cheese" then
			for _, p in live.pending do
				table.insert(pinches, p)
			end
		end
		food:cheese(pinches)
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

	-- Flour: MakeDough.flourDrag turns the held drag into batches (it closes one when the drag
	-- leaves the board or a batch is full). Each batch is checked here as the server will check
	-- it, so a batch that would be refused is dropped instead of clearing the queue behind it.
	local function sendFlour(points: { any })
		if current and MakeDough.validateFlour(shown(current), points) then
			push("flour", { points = points })
		end
	end
	local function flourAt(p: Vector2)
		local st = live
		if not st or st.kind ~= "flour" or not current then
			return
		end
		local room = Config.Make.flourMaxStamps - MakeDough.stampCount(shown(current))
		for _, batch in st.drag.move({ x = p.X, y = p.Y }, room) do
			sendFlour(batch)
		end
	end

	local function showScoop(position: Vector3?)
		scoop.Visible = position ~= nil
		if position then
			-- Astra's contact anchor (the floury bowl) on the pointer, turned with the scoop.
			local o = dough.AbsolutePosition
			local a = StationLayout.SCOOP_CONTACT
			local x, y = StationLayout.toolCentre(position.X - o.X, position.Y - o.Y, scoopCanvas, scoopCanvas, a.x, a.y, StationLayout.SCOOP_TILT)
			scoop.Position = UDim2.fromOffset(x, y)
		end
	end

	local function hold(kind: string, input: InputObject): any
		return { kind = kind, input = input, mouse = isMouseButton(input), button = input.UserInputType, began = os.clock() }
	end

	local function beginFlour(input: InputObject)
		live = hold("flour", input)
		live.drag = MakeDough.flourDrag()
		showScoop(input.Position)
		flourAt(toLocal(input.Position))
		redraw()
	end

	local function placeBall()
		if current and phaseOf() == "dough" then
			push("placeDough", {})
		end
	end

	-- One pass of the pin (MakeDough.rollDrag), sent if the server would keep it.
	local function commitPass(line: any)
		if not current then
			return
		end
		local args = { x1 = line.x1, y1 = line.y1, x2 = line.x2, y2 = line.y2 }
		if (args.x2 - args.x1) ^ 2 + (args.y2 - args.y1) ^ 2 >= Config.Make.minStroke ^ 2 and MakeDough.validateRoll(shown(current), args) then
			push("rollDough", args)
		end
	end

	-- The pin in the hand: picked up from its rest (it pops as it is lifted), eased onto each
	-- pass's turn by the tick, and glided back to the rest when let go. pinOut while it is away
	-- from the rest, so the resting pin is never drawn twice.
	local pinOut = false
	local pinAngle = PIN_REST_TURN -- drawn
	local pinTarget = PIN_REST_TURN
	local pinClock: number? = nil
	local pinKey = {}
	local pinScale = Motion.scale(pin)
	local function pinPickUp()
		Motion.stop(pinKey)
		pin.Size = UDim2.fromOffset(pinLen / PIN_SHARE, pinLen / PIN_SHARE)
		if not pinOut then
			pinOut = true
			pinRest.Visible = false
			pinAngle, pinTarget = PIN_REST_TURN, PIN_REST_TURN
			if not Motion.reduced() then
				Motion.pop(pinScale, 0.9, 1.06, 0.22)
			end
		end
		pinTarget = pinAngle
		pin.Rotation = pinAngle
		pinClock = nil
	end
	local function pinAway()
		pin.Visible = false
		Motion.stop(pinScale)
		pinScale.Scale = 1
		pinOut = false
		pinRest.Visible = current ~= nil and shown(current).step == "dough"
	end
	function pinHome(glide: boolean)
		if not pinOut or (live and live.kind == "roll") then
			return
		end
		if not glide or not pin.Visible or Motion.reduced() then
			Motion.stop(pinKey)
			pinAway()
			return
		end
		-- Back to the rest along an ease-out, turning the short way to the rest's own turn.
		local fromPos, fromSize, fromTurn = pin.Position, pin.Size, pinAngle
		local toPos, toSize = pinRest.Position, pinRest.Size
		local toTurn = PIN_REST_TURN + 360 * math.floor((fromTurn - PIN_REST_TURN) / 360 + 0.5)
		Motion.run(pinKey, PIN_HOME, function(t: number)
			local e = MotionPlan.easeOut(t)
			pin.Position = fromPos:Lerp(toPos, e)
			pin.Size = fromSize:Lerp(toSize, e)
			pinAngle = fromTurn + (toTurn - fromTurn) * e
			pin.Rotation = pinAngle
		end, pinAway)
	end
	function pinTick()
		local st = live
		if not st or st.kind ~= "roll" then
			pinClock = nil
			return
		end
		local now = Motion.now()
		local dt = if pinClock then math.clamp(now - pinClock, 0, 0.1) else 0
		pinClock = now
		if Motion.reduced() then
			pinAngle = pinTarget
		else
			pinAngle += (pinTarget - pinAngle) * (1 - math.exp(-dt / PIN_EASE))
		end
		pin.Rotation = pinAngle
	end

	-- Sauce and cheese are stored dough-local: the screen position mapped through the dough as
	-- it is now.
	local function toDoughLocal(position: Vector3): any
		local p = toLocal(position)
		return G.toDough(MakeDough.shape(shown(current)), { x = p.X, y = p.Y })
	end

	local ladleArt = ""
	local function showLadle(position: Vector3?, loaded: boolean)
		ladle.Visible = position ~= nil
		if position then
			-- Tipped to pour; flat on its back to spread. The bowl stays on the pointer either way.
			local tilt = if loaded then StationLayout.LADLE_POUR else StationLayout.LADLE_SPREAD
			local o = dough.AbsolutePosition
			local a = StationLayout.LADLE_CONTACT
			local x, y = StationLayout.toolCentre(position.X - o.X, position.Y - o.Y, ladleCanvas, ladleCanvas, a.x, a.y, tilt)
			ladle.Position = UDim2.fromOffset(x, y)
			ladle.Rotation = tilt
			local art = if loaded then "tool_ladle_loaded" else "tool_ladle_empty"
			if art ~= ladleArt then
				ladleArt = art
				Art.apply(ladle, art)
			end
		end
	end

	local function pourAt(q: any)
		if not current then
			return
		end
		local m = shown(current)
		local args = { x = q.x, y = q.y }
		if m.step == "sauce" and MakeSauce.validatePour(m.sauce, args) then
			push("pourSauce", args)
		end
	end
	-- A spread is checked here as the server will check it (it must cross sauce), so one that
	-- would be refused is dropped instead of clearing the queue behind it.
	local function sendSpread(points: { any })
		if not current or #points < 2 then
			return
		end
		local m = shown(current)
		local args = { points = points }
		if m.step == "sauce" and MakeSauce.validateSpread(m.sauce, args) then
			push("spreadSauce", args)
		end
	end
	local RECORD = 0.05 -- dough-local travel between recorded spread points
	local function clampReach(q: any): any
		local r = Config.Sauce.strokeReach
		return { x = math.clamp(q.x, -r, r), y = math.clamp(q.y, -r, r) }
	end
	-- Adds a point to the held spread. A very long drag (maxPoints points or maxSpread of travel)
	-- goes out as one spread and carries on as the next from its last point.
	local function extendSpread(st: any, q: any)
		local last = st.path[#st.path]
		local seg = math.sqrt((q.x - last.x) ^ 2 + (q.y - last.y) ^ 2)
		if st.length + seg > Config.Sauce.maxSpread then
			sendSpread(st.path)
			st.path, st.length = { last }, 0
		end
		table.insert(st.path, q)
		st.length += seg
		if #st.path >= Config.Sauce.maxPoints then
			sendSpread(st.path)
			st.path, st.length = { q }, 0
		end
	end
	local function ladleAt(position: Vector3)
		local st = live
		if not st or st.kind ~= "ladle" or not current then
			return
		end
		if not st.moved and (Vector2.new(position.X, position.Y) - st.start).Magnitude >= Config.Sauce.tapPixels then
			st.moved = true
		end
		showLadle(position, not st.moved)
		if st.moved then
			local q = clampReach(toDoughLocal(position))
			local last = st.path[#st.path]
			if (q.x - last.x) ^ 2 + (q.y - last.y) ^ 2 >= RECORD * RECORD then
				extendSpread(st, q)
			end
			st.preview = table.clone(st.path)
			if st.preview[#st.preview] ~= q then
				table.insert(st.preview, q)
			end
			redraw()
		end
	end

	-- Cheese: pinches still allowed on this pizza (the server's cap), counting the unsent ones.
	local function cheeseRoom(st: any): number
		return PrepFood.MAX_PINCHES - MakeCheese.count(shown(current).cheese) - #st.pending
	end
	-- Sends the held sprinkle's unsent pinches: one batch if a batch gap has passed, or all of
	-- them (release, a break in the stroke). A batch that would be refused is dropped, and the
	-- next one starts a new stroke.
	local function flushCheese(st: any, all: boolean)
		while #st.pending > 0 and current do
			if not all and os.clock() - st.lastFlush < Config.Cheese.batchGap then
				return
			end
			local batch = {}
			while #batch < Config.Cheese.batchSize and #st.pending > 0 do
				table.insert(batch, table.remove(st.pending, 1))
			end
			local args = { newStroke = st.first, points = batch }
			if MakeCheese.validate(shown(current).cheese, args) then
				push("addCheese", args)
				st.first = false
			else
				st.first = true
			end
			st.lastFlush = os.clock()
			if not all then
				return
			end
		end
	end
	local function cheeseAt(position: Vector3)
		local st = live
		if not st or st.kind ~= "cheese" or not current then
			return
		end
		for _, p in st.sampler.feed(toDoughLocal(position)) do
			if p.x * p.x + p.y * p.y > PrepFood.PINCH_REACH * PrepFood.PINCH_REACH then
				-- Out of reach: nothing lands, and the pinches after the gap are a new stroke
				-- (the server checks the spacing within one).
				st.gap = true
			elseif cheeseRoom(st) > 0 then
				if st.gap and st.any then
					flushCheese(st, true)
					st.first = true
					st.any = false
				end
				st.gap = false
				st.any = true
				table.insert(st.pending, p)
			end
		end
		flushCheese(st, false)
		redraw()
	end

	local beginCheese: (InputObject) -> ()

	local function endLive(commit: boolean, input: InputObject?)
		local st = live
		if not st then
			return
		end
		live = nil
		scoop.Visible = false
		if st.kind ~= "roll" then
			pin.Visible = false
		end
		carried.Visible = false
		ladle.Visible = false
		if st.kind == "flour" then
			local batch = st.drag.close()
			if commit and batch then
				sendFlour(batch)
			end
		elseif st.kind == "roll" then
			local last = st.drag.close()
			if commit and last then
				commitPass(last)
			end
			pinHome(commit)
		elseif st.kind == "ball" then
			if commit and input then
				local p = toLocal(input.Position)
				-- A tap on the tub, or a drag released over the board, pulls the dough on.
				if not st.dragged or p.Magnitude <= 1 / 0.9 then
					placeBall()
				end
			end
		elseif st.kind == "ladle" then
			if commit and current then
				if not st.moved then
					-- A tap: one ladle where the press landed.
					pourAt(st.q0)
				else
					if input then
						local q = clampReach(toDoughLocal(input.Position))
						local last = st.path[#st.path]
						if q.x ~= last.x or q.y ~= last.y then
							extendSpread(st, q)
						end
					end
					sendSpread(st.path)
				end
			end
		elseif st.kind == "pot" then
			-- Dragged from the pot: pours where it is released, if that is on the dough.
			if commit and input and st.dragged and current then
				local q = toDoughLocal(input.Position)
				if q.x * q.x + q.y * q.y <= G.CRUST * G.CRUST then
					pourAt(q)
				end
			end
		elseif st.kind == "cheese" then
			-- Every pinch already drawn goes out; a ticket switch (commit false) drops them.
			if commit then
				flushCheese(st, true)
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
		local ended = st.drag.move({ x = p.X, y = p.Y })
		if ended then
			-- A turn: the pass just rolled is kept, and the next one starts where it turned.
			commitPass(ended)
		end
		local axis = st.drag.axis
		if axis then
			-- The pin lies across the pass and rolls along it; a pass back the other way keeps
			-- its turn (MakeDough.pinTurn). The tick eases it there.
			pinTarget = MakeDough.pinTurn(axis, pinTarget)
		end
		local o = dough.AbsolutePosition
		pin.Position = UDim2.fromOffset(position.X - o.X, position.Y - o.Y)
		pin.Visible = true
		redraw()
	end

	-- A held drag whose release never arrived (focus lost, window switched) would block every
	-- new press, Undo and Next until a ticket or station change. Cut's rule: a new press of the
	-- drag's own mouse button means its release was lost (the button can't be pressed again
	-- without being released, and Roblox may hand the new press the same InputObject, so its
	-- identity can't tell); a finger's drag is stale once its touch ended. With no input, a
	-- button was clicked: that click is a new press of mouse button 1. A stale flour drag keeps
	-- the dust it laid and a stale sprinkle its cheese; a stale roll, dough carry, pour or spread is
	-- dropped.
	local function stale(st: any, input: InputObject?): boolean
		if st.mouse then
			if input then
				return isMouseButton(input) and input.UserInputType == st.button
			end
			return st.button == Enum.UserInputType.MouseButton1
		end
		local state = st.input.UserInputState
		return state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	end
	local function dropStale(input: InputObject?)
		local st = live
		if st and stale(st, input) then
			endLive(st.kind == "flour" or st.kind == "cheese")
		end
	end
	-- Any new press, wherever it lands (a button, the tab bar), drops a stale drag before its
	-- release could be taken for the drag's own. A drag begun by this same press (its handler
	-- may run first) is under 0.1 s old; a mouse can't release and press again that fast.
	ctx.connect(UserInputService.InputBegan, function(input: InputObject)
		local st = live
		if st and isPress(input) and os.clock() - st.began > 0.1 then
			dropStale(input)
		end
	end)

	function beginCheese(input: InputObject)
		live = hold("cheese", input)
		live.sampler = PrepFood.sampler()
		live.pending, live.first, live.any, live.gap, live.lastFlush = {}, true, false, false, -math.huge
		cheeseAt(input.Position)
	end

	pad.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or not current then
			return
		end
		dropStale(input)
		if live then
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
			live = hold("roll", input)
			live.drag = MakeDough.rollDrag({ x = p.X, y = p.Y })
			pinPickUp()
			rollAt(input.Position)
		elseif shown(current).step == "sauce" then
			-- Undecided until it moves tapPixels (a spread) or ends (a pour).
			live = hold("ladle", input)
			live.start = Vector2.new(input.Position.X, input.Position.Y)
			live.q0 = clampReach(toDoughLocal(input.Position))
			live.path, live.length, live.moved = { live.q0 }, 0, false
			showLadle(input.Position, true)
		elseif shown(current).step == "cheese" then
			beginCheese(input)
		end
	end)
	pot.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			dropStale(input)
		end
		if isPress(input) and not live and current and shown(current).step == "sauce" then
			live = hold("pot", input)
			live.start, live.dragged = Vector2.new(input.Position.X, input.Position.Y), false
			showLadle(input.Position, true)
		end
	end)
	bowl.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			dropStale(input)
		end
		if isPress(input) and not live and current and shown(current).step == "cheese" then
			-- Cheese lands once the hand is over the dough.
			beginCheese(input)
		end
	end)
	crock.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			dropStale(input)
		end
		if isPress(input) and not live and flourAllowed() then
			-- The scoop comes out of the crock; dust lands once it is over the board.
			live = hold("flour", input)
			live.drag = MakeDough.flourDrag()
			showScoop(input.Position)
		end
	end)
	tub.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			dropStale(input)
		end
		if isPress(input) and not live and phaseOf() == "dough" then
			live = hold("ball", input)
			live.start, live.dragged = input.Position, false
		end
	end)

	local function ownsInput(input: InputObject): boolean
		local st = live
		if not st then
			return false
		end
		if st.mouse then
			return input.UserInputType == Enum.UserInputType.MouseMovement
		end
		return input == st.input
	end
	ctx.connect(UserInputService.InputChanged, function(input: InputObject)
		local st = live
		if not st or not ownsInput(input) then
			return
		end
		if st.kind == "ladle" then
			ladleAt(input.Position)
			return
		elseif st.kind == "pot" then
			if (Vector2.new(input.Position.X, input.Position.Y) - st.start).Magnitude >= Config.Sauce.tapPixels then
				st.dragged = true
			end
			showLadle(input.Position, true)
			return
		elseif st.kind == "cheese" then
			cheeseAt(input.Position)
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
		if (st.mouse and input.UserInputType ~= st.button) or (not st.mouse and input ~= st.input) then
			return
		end
		endLive(true, input)
	end)

	-- Undo, inside the current step: the dough step takes back the last roll, then the ball, then
	-- the last flour batch; the sauce step the last pour or spread; the cheese step the last
	-- sprinkle, all of it.
	local function canUndo(m: any): boolean
		if m.step == "dough" then
			return #m.flour > 0 or m.placed
		elseif m.step == "sauce" then
			return #m.sauce.actions > 0
		elseif m.step == "cheese" then
			return #m.cheese.strokes > 0
		end
		return false
	end
	local UNDO = { dough = "undoDough", sauce = "undoSauce", cheese = "undoCheese" }
	local function doUndo()
		dropStale()
		if live or not current then
			return
		end
		local m = shown(current)
		if canUndo(m) then
			push(UNDO[m.step], {})
		end
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
	-- Rail action for the board's steps: on to the next step once this one's minimum is met.
	-- Shares the Make action slot with Topping's Send to oven.
	local function canFinish(m: any): boolean
		if m.step == "dough" then
			return MakeDough.canFinish(m)
		elseif m.step == "sauce" then
			return MakeSauce.canFinish(m.sauce)
		elseif m.step == "cheese" then
			return MakeCheese.canFinish(m.cheese)
		end
		return false
	end
	local NEXT = { dough = "finishDough", sauce = "finishSauce", cheese = "finishCheese" }
	local nextButton = Widgets.button("Next: sauce", function()
		dropStale()
		if live or not current or finishing == current.id then
			return
		end
		local m = shown(current)
		if not NEXT[m.step] or not canFinish(m) then
			return
		end
		finishing, finishingFrom = current.id, m.step
		push(NEXT[m.step], { from = m.step })
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
		-- The board shows the dough, sauce and cheese steps; the toppings step is the Topping
		-- view. The server's step decides (a Next still on its way keeps the board).
		local onBoard = current ~= nil and ON_BOARD[current.make.step] == true
		if finishing and (not current or current.id ~= finishing or current.make.step ~= finishingFrom) then
			finishing = nil
		end
		dough.Visible = onBoard
		toppingHolder.Visible = not onBoard
		nextButton.frame.Visible = onBoard
		toppings.sendButton.frame.Visible = not onBoard
		local customer = current and ctx.customer(snap, current.ticketId)
		local recipe = customer and Recipes.ById[customer.order.recipe]
		local m = if current then shown(current) else nil
		local step = if m then m.step else "dough"
		local phase = if m then MakeDough.phase(m) else "none"
		local stepName = if step ~= "dough" then step elseif phase == "none" then "flour" else phase
		local list = stepsFor(recipe)
		local key = table.concat(list, ",") .. "|" .. stepName
		if onBoard and key ~= stepsKey then
			stepsKey = key
			renderSteps(list, stepName)
		end
		if onBoard and m then
			-- Each step's own tools in the two tool cells.
			local inDough = step == "dough"
			crock.Visible, tub.Visible = inDough, inDough
			-- The resting pin is away while it is in the hand or gliding back.
			pinRest.Visible = inDough and not pinOut
			pot.Visible, bowl.Visible = not inDough, not inDough
			undo:setEnabled(canUndo(m))
			local busy = finishing ~= nil
			nextButton:setEnabled(not busy and ON_BOARD[step] == true and canFinish(m))
			local nextLabel = if step == "dough" then "Next: sauce"
				elseif step == "sauce" then "Next: cheese"
				elseif recipe and #recipe.toppings > 0 then "Next: toppings"
				else "Next: finish"
			nextButton:setLabel(if busy then "Adding..." elseif compact then "Next" else nextLabel)
			crock.ImageTransparency = if flourAllowed() then 0 else 0.45
			tub.ImageTransparency = if phase == "dough" then 0 else 0.45
			pot.ImageTransparency = if step == "sauce" then 0 else 0.45
			bowl.ImageTransparency = if step == "cheese" then 0 else 0.45
			redraw()
		end
	end

	-- One modest pulse of Next the moment the dough shows ready (Astra r19), on every shift; it
	-- never moves on by itself.
	local pulsed: { [number]: boolean } = {} -- pizzas whose ready pulse has played
	local nextScale = Motion.scale(nextButton.frame)
	function readyPulse()
		if not current or current.make.step ~= "dough" then
			return
		end
		local m = shown(current)
		local isReady = m.placed and MakeDough.ready((shownShape(m)))
		if isReady and not pulsed[current.id] and not Motion.reduced() then
			Motion.pop(nextScale, 1, 1.08, 0.32)
		end
		-- Undo below ready lets it pulse again when the dough is ready once more.
		pulsed[current.id] = isReady
	end

	function station.tick(now: number)
		toppings.tick(now)
		pinTick()
		-- The drawn dough still easing onto its shape: draw the next step.
		if doughEasing then
			redraw()
		end
		readyPulse()
		-- A base key drawn before its picture loaded: draw again once it has (drawDough).
		if waitKey and waitKey.IsLoaded then
			waitKey = nil
			redraw()
		end
		local st = live
		if st and st.kind == "cheese" then
			flushCheese(st, false)
		end
	end

	function station.setActive(active: boolean)
		if not active then
			endLive(false)
			pinHome(false)
		end
	end

	-- Why the rail's action is unavailable, on the hint strip.
	function station.status(snap: any): any
		if not current or not ON_BOARD[current.make.step] then
			return toppings.status(snap)
		end
		local m = shown(current)
		if m.step == "sauce" then
			local pours = MakeSauce.counts(m.sauce)
			if pours == 0 then
				return { text = "Tap the dough to pour a ladle of sauce" }
			elseif not MakeSauce.canFinish(m.sauce) then
				return { text = "Drag across the sauce to spread it" }
			end
			return nil
		elseif m.step == "cheese" then
			if MakeCheese.count(m.cheese) == 0 then
				return { text = "Drag over the sauce to sprinkle cheese" }
			end
			return nil
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

	-- First-shift pointer, one lesson per part of the dough step, then Topping's own. The
	-- glove keeps clear of the tool column, the step label and Undo (Tutorial's hint.clear).
	local keepClear = { stepsBox, crock, tub, pot, bowl, pinRest, undo.frame }
	local hintFor: (any) -> any
	function station.hint(snap: any): any
		local h = hintFor(snap)
		if h and current and current.make.step ~= "toppings" then
			h.clear = keepClear
		end
		return h
	end
	function hintFor(snap: any): any
		if not current then
			return nil
		end
		local side = if compact then "left" else "below"
		local toNext = if compact then "aboveLeft" else "left"
		if current.make.step == "sauce" or current.make.step == "cheese" then
			-- Until the step's first Next: what the sauce or cheese still needs, then Next.
			local m = shown(current)
			if m.step == "sauce" and not ctx.learned["Make.sauceNext"] then
				local field, pours, spreadMet = MakeSauce.replay(m.sauce)
				local coverage, crust, off = MakeSauce.measure(field)
				if pours == 0 then
					return { target = pad, text = "Tap the dough to pour a ladle of sauce", from = side }
				elseif pours < Config.Sauce.targetPours then
					return { target = pad, text = string.format("Pour %d ladles in all, spread apart", Config.Sauce.targetPours), from = side }
				elseif not spreadMet then
					return { target = pad, text = "Drag across the sauce to spread it", from = side }
				elseif off > Config.Sauce.spillAbove then
					return { target = undo.frame, text = "Sauce on the board: tap Undo", from = "below" }
				elseif crust > Config.Sauce.crustAbove then
					return { target = undo.frame, text = "Sauce on the crust: tap Undo", from = "below" }
				elseif coverage < Config.Sauce.bareBelow then
					return { target = pad, text = "Spread it out to the crust, covering the bare spots", from = side }
				end
				return { target = nextButton.frame, text = "Sauce spread evenly: tap Next", from = toNext }
			elseif m.step == "cheese" and not ctx.learned["Make.cheeseNext"] then
				local _, inside, spread = PrepFood.cheeseScore(MakeCheese.pinches(m.cheese))
				if inside < Config.Cheese.fewBelow then
					return { target = pad, text = "Hold and drag over the sauce to sprinkle cheese", from = side }
				elseif spread < Config.Cheese.bunchedBelow then
					return { target = pad, text = "Sprinkle the bare parts too", from = side }
				end
				return { target = nextButton.frame, text = "Cheese all over: tap Next", from = toNext }
			end
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
			-- Next works from the first roll, so until the first Next the pointer says what the
			-- dough still needs and points at Next only when size and roundness get full marks.
			-- Read from the dough as it shows, so the pointer changes the moment a held pass makes
			-- it ready, not on the release (Open 12).
			local S, previewing = shownShape(m)
			local advice = if ctx.learned["Make.next"] then nil else MakeDough.rollAdvice(m, if previewing then S else nil)
			-- Astra r19's cue. "Roll along the short side" is gone: rolling alone cannot make the
			-- dough uneven (make_check section 4), so the pointer never said it.
			if advice == "ready" then
				return { target = nextButton.frame, text = "Ready \u{2014} next: sauce", from = toNext }
			elseif advice == "small" then
				return { target = pad, text = "Keep rolling until the dough reaches the inner guide edge", from = side }
			elseif advice == "big" then
				return { target = undo.frame, text = "Too big and thin: tap Undo", from = "below" }
			end
		end
		return nil
	end

	return station
end

return Make

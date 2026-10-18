--!strict
-- Reusable interface pieces. Each uses the uploaded proof art when its asset id exists and a
-- token-styled stand-in otherwise, with identical hitboxes and anchors either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local C = Theme.Colour
local Widgets = {}

------------------------------------------------------------------------------------------
-- Primary button: one fixed hitbox and label anchor across idle/pressed/disabled/highlighted.

export type Button = {
	frame: Frame,
	hit: TextButton,
	label: TextLabel,
	setEnabled: (Button, boolean) -> (),
	setHighlighted: (Button, boolean) -> (),
	setLabel: (Button, string) -> (),
	enabled: boolean,
	highlighted: boolean,
}

function Widgets.button(text: string, onActivated: () -> ()): Button
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 70) })
	local art = Ui.new("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.Meta.primarySlice,
		Parent = frame,
	})
	local fallback = Ui.new("Frame", {
		Name = "Fallback",
		BackgroundColor3 = C.action,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	}, { Ui.corner(18), Ui.stroke(C.ink, 3) })
	local label = Ui.text({
		Name = "Label",
		Text = text,
		FontFace = Theme.Font.bodyBold,
		TextColor3 = C.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		Size = UDim2.new(1, -24, 0.5, 0),
		Position = UDim2.fromScale(0.5, 0.44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = frame,
	})
	Ui.new("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 30, Parent = label })
	local hit = Ui.new("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = frame,
	})

	local self: Button
	local pressed = false
	local function render()
		local state = if not self.enabled then "disabled" elseif pressed then "pressed" elseif self.highlighted then "highlighted" else "idle"
		local id = Assets.get("ui_primary_" .. state)
		art.Visible = id ~= nil
		fallback.Visible = id == nil
		if id then
			art.Image = id
		end
		fallback.BackgroundColor3 = if state == "disabled" then C.disabled elseif state == "pressed" then C.actionPressed else C.action
		local stroke = fallback:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = if state == "highlighted" then C.paper else C.ink
		label.TextColor3 = if state == "disabled" then C.ink else C.white
		-- Pressed label displacement stays within 2 px per the guide.
		label.Position = UDim2.new(0.5, 0, 0.44, if pressed then 2 else 0)
	end

	self = {
		frame = frame,
		hit = hit,
		label = label,
		enabled = true,
		highlighted = false,
		setEnabled = function(b: Button, on: boolean)
			b.enabled = on
			render()
		end,
		setHighlighted = function(b: Button, on: boolean)
			b.highlighted = on
			render()
		end,
		setLabel = function(_b: Button, t: string)
			label.Text = t
		end,
	}
	hit.MouseButton1Down:Connect(function()
		if self.enabled then
			pressed = true
			render()
		end
	end)
	local function release()
		if pressed then
			pressed = false
			render()
		end
	end
	hit.MouseButton1Up:Connect(release)
	hit.MouseLeave:Connect(release)
	hit.Activated:Connect(function()
		release()
		if self.enabled then
			onActivated()
		end
	end)
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		art.SliceScale = math.max(frame.AbsoluteSize.Y / 207, 0.05)
	end)
	render()
	return self
end

------------------------------------------------------------------------------------------
-- Oven ring: proof shell plus a live arc drawn with two clipped halves.

export type Ring = { frame: Frame, set: (Ring, number, Color3, string, string) -> () }

local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.5001, 1),
	NumberSequenceKeypoint.new(1, 1),
})

function Widgets.ring(size: number): Ring
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	local shellId = Assets.get("ui_ovenRing_idle")
	if shellId then
		Ui.new("ImageLabel", { BackgroundTransparency = 1, Image = shellId, Size = UDim2.fromScale(1, 1), Parent = frame })
	else
		Ui.new("Frame", {
			BackgroundColor3 = C.paper,
			BackgroundTransparency = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		}, { Ui.round(), Ui.stroke(C.ink, 2) })
	end

	-- UIStroke draws outside its frame, so size the clip halves to hold the whole stroke and
	-- shrink the circle so the stroke's centreline sits on the shell's band.
	local thickness = math.max(3, math.floor(size * Assets.Meta.ringBandWidth * 0.75))
	local radius = Assets.Meta.ringBandRadius * size - thickness / 2
	local holderSize = math.ceil(2 * (radius + thickness)) + 2
	local arcHolder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(holderSize, holderSize),
		ZIndex = 2,
		Parent = frame,
	})
	local gradients: { [string]: UIGradient } = {}
	local strokes: { UIStroke } = {}
	local inset = holderSize / 2 - radius
	for _, side in { "right", "left" } do
		local clip = Ui.new("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(if side == "right" then 0.5 else 0, 0),
			ZIndex = 2,
			Parent = arcHolder,
		})
		local circle = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(radius * 2, radius * 2),
			Position = UDim2.fromOffset(if side == "right" then -radius else inset, inset),
			ZIndex = 2,
			Parent = clip,
		}, { Ui.round() })
		local stroke = Ui.new("UIStroke", {
			Thickness = thickness,
			Color = C.oven,
			Parent = circle,
		})
		gradients[side] = Ui.new("UIGradient", { Transparency = HALF, Parent = stroke })
		table.insert(strokes, stroke)
	end

	local slotLabel = Ui.text({
		FontFace = Theme.Font.display,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.3),
		ZIndex = 3,
		Parent = frame,
	})
	local statusLabel = Ui.text({
		FontFace = Theme.Font.bodyBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.62, 0.2),
		ZIndex = 3,
		Parent = frame,
	})
	Ui.new("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 22, Parent = statusLabel })

	local ring: Ring = {
		frame = frame,
		set = function(_r: Ring, progress: number, colour: Color3, slotText: string, status: string)
			local angle = math.clamp(progress, 0, 1) * 360
			gradients.right.Rotation = math.clamp(angle, 0, 180)
			gradients.left.Rotation = math.clamp(angle, 180, 360)
			for _, s in strokes do
				s.Color = colour
				s.Enabled = progress > 0
			end
			slotLabel.Text = slotText
			statusLabel.Text = status
		end,
	}
	ring:set(0, C.oven, "", "")
	return ring
end

------------------------------------------------------------------------------------------
-- Patience meter: four face/track proofs plus a continuous live fill.

export type Patience = { frame: Frame, set: (Patience, number, string) -> () }

local BAND_COLOUR = { happy = C.basil, neutral = C.basil, impatient = C.oven, grumpy = C.tomato }
local BAND_FACE = { happy = "^ ^", neutral = "- -", impatient = "> <", grumpy = "x x" }

function Widgets.patience(): Patience
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 68) })
	Ui.new("UIAspectRatioConstraint", { AspectRatio = Assets.Meta.patienceAspect, Parent = frame })
	local art = Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local fb = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local fm = Assets.Meta.patienceFill
	Ui.new("Frame", {
		BackgroundColor3 = C.paper,
		Position = UDim2.fromScale(fm.x - 0.02, fm.y - 0.06),
		Size = UDim2.fromScale(fm.w + 0.04, fm.h + 0.12),
		Parent = fb,
	}, { Ui.round(), Ui.stroke(C.ink, 2) })
	local face = Ui.new("TextLabel", {
		BackgroundColor3 = C.paper,
		Size = UDim2.fromScale(0.26, 0.92),
		Position = UDim2.fromScale(0.02, 0.04),
		FontFace = Theme.Font.bodyBold,
		TextColor3 = C.ink,
		TextScaled = true,
		Parent = fb,
	}, { Ui.round(), Ui.stroke(C.ink, 2) })
	local fill = Ui.new("Frame", {
		BackgroundColor3 = C.basil,
		Position = UDim2.fromScale(fm.x, fm.y),
		Size = UDim2.fromScale(fm.w, fm.h),
		ZIndex = 2,
		Parent = frame,
	}, { Ui.round() })

	local p: Patience = {
		frame = frame,
		set = function(_p: Patience, fraction: number, band: string)
			local id = Assets.get("ui_patience_" .. band)
			art.Visible = id ~= nil
			fb.Visible = id == nil
			if id then
				art.Image = id
			end
			face.Text = BAND_FACE[band]
			fill.Size = UDim2.fromScale(fm.w * math.clamp(fraction, 0, 1), fm.h)
			fill.Visible = fraction > 0.01
			fill.BackgroundColor3 = BAND_COLOUR[band]
		end,
	}
	p:set(1, "happy")
	return p
end

------------------------------------------------------------------------------------------
-- Ticket detail: blank ticket proof with live order text.

local REGION_TEXT = { whole = "all over", left = "left half", right = "right half" }
local BAKE_TEXT = { light = "Light bake", regular = "Regular bake", well = "Well done" }

function Widgets.orderLines(order: any): { string }
	local recipe = Recipes.ById[order.recipe]
	local lines = {}
	if #recipe.toppings == 0 then
		table.insert(lines, "No toppings")
	end
	for _, req in recipe.toppings do
		local info = Recipes.Ingredients[req.ingredient]
		table.insert(lines, string.format("%d %s, %s", req.count, info.plural, REGION_TEXT[req.region]))
	end
	return lines
end

function Widgets.ticket(customerName: string, order: any, compact: boolean): Frame
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 300) })
	Ui.new("UIAspectRatioConstraint", { AspectRatio = Assets.Meta.ticketAspect, Parent = frame })
	local id = Assets.get("ui_orderTicket_blank")
	if id then
		Ui.new("ImageLabel", { BackgroundTransparency = 1, Image = id, Size = UDim2.fromScale(1, 1), Parent = frame })
	else
		Ui.new("Frame", { BackgroundColor3 = C.paper, Size = UDim2.fromScale(1, 1), Parent = frame }, {
			Ui.corner(6),
			Ui.stroke(C.ink, 2),
			Ui.new("Frame", { BackgroundColor3 = C.tomato, Size = UDim2.new(1, 0, 0.035, 0), BorderSizePixel = 0 }),
		})
	end
	local body = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.1, 0.07),
		Size = UDim2.fromScale(0.8, 0.84),
		Parent = frame,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local base = if compact then 16 else 20
	local function line(text: string, font: Font, sizeBoost: number, colour: Color3?, order_: number)
		local l = Ui.text({
			Text = text,
			FontFace = font,
			TextSize = base + sizeBoost,
			TextColor3 = colour or C.ink,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = order_,
			Parent = body,
		})
		return l
	end
	local recipe = Recipes.ById[order.recipe]
	line(customerName, Theme.Font.display, 4, nil, 1)
	line(recipe.name, Theme.Font.bodyBold, 2, C.tomato, 2)
	for i, text in Widgets.orderLines(order) do
		line(text, Theme.Font.body, 0, nil, 2 + i)
	end
	line(BAKE_TEXT[order.bake], Theme.Font.bodySemi, 0, nil, 20)
	line(order.slices .. " slices", Theme.Font.bodySemi, 0, nil, 21)
	return frame
end

------------------------------------------------------------------------------------------
-- Greybox top-down pizza. Bake changes crust and cheese separately and only lightly darkens
-- toppings, so ingredients stay recognizable (per Astra's correction).

local RAW_CRUST, GOLD_CRUST, BURNT_CRUST = Color3.fromRGB(236, 214, 170), Color3.fromRGB(205, 140, 72), Color3.fromRGB(70, 42, 28)
local RAW_CHEESE, GOLD_CHEESE, BURNT_CHEESE = Color3.fromRGB(255, 244, 206), Color3.fromRGB(246, 200, 104), Color3.fromRGB(110, 76, 44)
local SAUCE = Color3.fromRGB(196, 62, 44)

local function bakeColours(doneness: number): (Color3, Color3, number)
	-- doneness: 0 raw, 1 golden (regular target), 1.6+ burnt
	if doneness <= 1 then
		return RAW_CRUST:Lerp(GOLD_CRUST, doneness), RAW_CHEESE:Lerp(GOLD_CHEESE, doneness), 0
	end
	local t = math.clamp((doneness - 1) / 0.6, 0, 1)
	return GOLD_CRUST:Lerp(BURNT_CRUST, t), GOLD_CHEESE:Lerp(BURNT_CHEESE, t), t
end

function Widgets.doneness(seconds: number): number
	return seconds / Config.Oven.targets.regular
end

export type PizzaView = { frame: Frame, toppingLayer: Frame, cutLayer: Frame, set: (PizzaView, any, number) -> () }

local BLISTERS = { { -0.3, -0.2 }, { 0.25, -0.35 }, { 0.1, 0.3 }, { -0.35, 0.28 }, { 0.38, 0.1 }, { -0.05, -0.45 }, { -0.1, 0.05 } }

local function toppingDarken(doneness: number, burnt: number): number
	return math.clamp((doneness - 0.8) * 0.25, 0, 0.35) + burnt * 0.3
end

function Widgets.pizza(): PizzaView
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 300) })
	Ui.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = frame })
	local crust = Ui.new("Frame", { BackgroundColor3 = RAW_CRUST, Size = UDim2.fromScale(1, 1), Parent = frame }, {
		Ui.round(),
		Ui.stroke(C.ink, 3),
	})
	Ui.new("Frame", {
		BackgroundColor3 = SAUCE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, 0.88),
		Parent = frame,
	}, { Ui.round() })
	local cheese = Ui.new("Frame", {
		BackgroundColor3 = RAW_CHEESE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		Parent = frame,
	}, { Ui.round() })
	local blisters = {}
	for _, b in BLISTERS do
		table.insert(blisters, Ui.new("Frame", {
			BackgroundColor3 = GOLD_CRUST,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + b[1] * 0.5, 0.5 + b[2] * 0.5),
			Size = UDim2.fromScale(0.07, 0.05),
			Parent = frame,
		}, { Ui.round() }))
	end
	local toppingLayer = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = frame })
	local cutLayer = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = frame })

	-- Pieces and cut lines are rebuilt only when their content changes; per-frame bake
	-- updates just recolour what already exists.
	local contentKey = ""
	local pieces: { { frame: Frame, base: Color3 } } = {}
	local lastDarken = -1

	local view: PizzaView = {
		frame = frame,
		toppingLayer = toppingLayer,
		cutLayer = cutLayer,
		set = function(_v: PizzaView, pizza: any, doneness: number)
			local crustC, cheeseC, burnt = bakeColours(doneness)
			crust.BackgroundColor3 = crustC
			cheese.BackgroundColor3 = cheeseC
			local blisterAlpha = if doneness < 0.6 then 1 else math.clamp(1 - (doneness - 0.6) * 2, 0.15, 1)
			for _, b in blisters do
				b.BackgroundTransparency = blisterAlpha
				b.BackgroundColor3 = GOLD_CRUST:Lerp(BURNT_CRUST, burnt)
			end

			local parts = { tostring(pizza.id) }
			for _, piece in pizza.toppings do
				table.insert(parts, string.format("%s%.3f%.3f%s", piece.ingredient, piece.x, piece.y, if piece.pending then "p" else ""))
			end
			table.insert(parts, "|")
			for _, line in pizza.cuts or {} do
				table.insert(parts, string.format("%.3f%.3f%.3f%.3f", line.x1, line.y1, line.x2, line.y2))
			end
			local key = table.concat(parts, ",")
			local darken = toppingDarken(doneness, burnt)
			if key ~= contentKey then
				contentKey = key
				Ui.clear(toppingLayer)
				pieces = {}
				for _, piece in pizza.toppings do
					local f = Widgets.drawPiece(toppingLayer, piece, 0, piece.pending == true)
					table.insert(pieces, { frame = f, base = Recipes.Ingredients[piece.ingredient].colour })
				end
				Ui.clear(cutLayer)
				for _, line in pizza.cuts or {} do
					Widgets.drawCut(cutLayer, line, C.paper)
				end
				lastDarken = -1
			end
			if math.abs(darken - lastDarken) > 0.005 then
				lastDarken = darken
				local tint = Color3.new(0.15, 0.08, 0.05)
				for _, p in pieces do
					local colour = p.base:Lerp(tint, darken)
					p.frame.BackgroundColor3 = colour
					local stroke = p.frame:FindFirstChildOfClass("UIStroke")
					if stroke and stroke.Color ~= C.ink then
						stroke.Color = colour
					end
				end
			end
		end,
	}
	return view
end

function Widgets.drawPiece(layer: Frame, piece: any, darken: number, pending: boolean): Frame
	local info = Recipes.Ingredients[piece.ingredient]
	local colour = info.colour:Lerp(Color3.new(0.15, 0.08, 0.05), darken)
	local s = info.size
	local f = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + piece.x * 0.5, 0.5 + piece.y * 0.5),
		Size = UDim2.fromScale(s, s),
		BackgroundColor3 = colour,
		BackgroundTransparency = if info.shape == "ring" then 1 else (if pending then 0.35 else 0),
		ZIndex = 2,
		Parent = layer,
	}, { Ui.round() })
	local stroke = Ui.stroke(if info.shape == "ring" then colour else C.ink, if info.shape == "ring" then 4 else 1.5)
	stroke.Parent = f
	if info.shape == "disc" then
		Ui.new("Frame", {
			BackgroundColor3 = colour:Lerp(Color3.new(0, 0, 0), 0.25),
			Position = UDim2.fromScale(0.25, 0.3),
			Size = UDim2.fromScale(0.18, 0.18),
			ZIndex = 2,
			Parent = f,
		}, { Ui.round() })
	elseif info.shape == "cap" then
		Ui.new("Frame", {
			BackgroundColor3 = colour:Lerp(Color3.new(0.3, 0.2, 0.1), 0.4),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromScale(0.3, 0.4),
			ZIndex = 2,
			Parent = f,
		}, { Ui.corner(3) })
	end
	return f
end

function Widgets.drawCut(layer: Frame, line: any, colour: Color3)
	-- Chord of the infinite line through the two points, clipped to the pizza circle.
	local dx, dy = line.x2 - line.x1, line.y2 - line.y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1e-4 then
		return
	end
	local ux, uy = dx / len, dy / len
	local t = -(line.x1 * ux + line.y1 * uy)
	local cx, cy = line.x1 + ux * t, line.y1 + uy * t
	local d2 = cx * cx + cy * cy
	if d2 >= 1 then
		return
	end
	local half = math.sqrt(1 - d2)
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + cx * 0.5, 0.5 + cy * 0.5),
		Size = UDim2.new(half, 0, 0, 4),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = layer,
	}, { Ui.stroke(C.ink, 1) })
end

function Widgets.tweenIn(frame: GuiObject, offsetX: number)
	-- Visual only: the frame is fully interactive from the first frame of the slide.
	local target = frame.Position
	frame.Position = target + UDim2.fromOffset(offsetX, 0)
	TweenService:Create(frame, TweenInfo.new(Theme.Motion.station, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
end

function Widgets.flash(frame: GuiObject, from: number)
	-- Fades a highlight from `from` transparency back to invisible; used to point at a tab.
	frame.BackgroundTransparency = from
	TweenService:Create(frame, TweenInfo.new(Theme.Motion.nudge, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

return Widgets

--!strict
-- Reusable interface pieces drawn with supplied art (src/shared/Art.luau). When a piece's art
-- is missing it stays empty apart from its live text; hitboxes and anchors never change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local PizzaArt = require(script.Parent.PizzaArt)

local C = Theme.Colour
local Widgets = {}

------------------------------------------------------------------------------------------
-- Action button: one fixed hitbox and label anchor across idle/pressed/disabled/highlighted.
-- Primary actions use Astra's V2 button, whose four states share one body outline, so only
-- the image changes between states. Secondary actions keep the V1 proof until V2 secondary
-- art arrives.

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

local BUTTON_STATES = { "idle", "pressed", "disabled", "highlighted" }
local PRESS_IN = TweenInfo.new(Theme.Motion.press, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT = TweenInfo.new(Theme.Motion.release + 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local preloaded = false

function Widgets.button(text: string, onActivated: () -> (), kind: ("primary" | "secondary")?): Button
	local primary = kind ~= "secondary"
	local artPrefix = if primary then "ui_button_primary_" else "ui_primary_"
	if not preloaded then
		preloaded = true
		local names = {}
		for _, state in BUTTON_STATES do
			table.insert(names, "ui_button_primary_" .. state)
			table.insert(names, "ui_primary_" .. state)
		end
		Art.preload(names)
	end
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 70) })
	-- Art and label share one body, so the press motion moves them together.
	local body = Ui.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	local press = Ui.new("UIScale", { Scale = 1, Parent = body })
	local art = Ui.new("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = if primary then Assets.Meta.buttonPrimary.slice else Assets.Meta.primarySlice,
		Parent = body,
	})
	local label = Ui.text({
		Name = "Label",
		Text = text,
		FontFace = if primary then Theme.Font.display else Theme.Font.bodyBold,
		TextColor3 = if primary then C.label else C.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
		Parent = body,
	})
	local sizeLimit = Ui.new("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 30, Parent = label })
	-- Ivory on coral needs its outline to read (Astra's README).
	local stroke = Ui.new("UIStroke", { Color = C.labelStroke, Thickness = 1, Enabled = primary, Parent = label })
	local hit = Ui.new("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = frame,
	})

	local self: Button
	local pressed = false
	local function render()
		local state = if not self.enabled then "disabled" elseif pressed then "pressed" elseif self.highlighted then "highlighted" else "idle"
		Art.apply(art, artPrefix .. state)
		if primary then
			label.TextColor3 = if state == "disabled" then C.labelDisabled else C.label
			stroke.Enabled = state ~= "disabled"
		else
			label.TextColor3 = if state == "disabled" then C.ink else C.white
		end
	end
	local function layout()
		local w, h = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
		if h <= 0 then
			return
		end
		-- Astra's live-content insets: 32/24 px at 420x110 and 14/10 px at 168x48, i.e. a
		-- fixed share of the height. Text keeps the 16 px floor and grows to 32 px.
		local insetX, insetY = math.round(h * 0.29), math.round(h * 0.215)
		art.SliceScale = math.max(h / (if primary then Assets.Meta.buttonPrimary.height else 207), 0.05)
		label.Size = UDim2.fromOffset(math.max(w - insetX * 2, 0), math.max(h - insetY * 2, 0))
		sizeLimit.MaxTextSize = math.clamp(math.round(h * 0.29), 16, 32)
		stroke.Thickness = if h < 64 then 1 else 2
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
			TweenService:Create(press, PRESS_IN, { Scale = 0.96 }):Play()
		end
	end)
	local function release()
		if pressed then
			pressed = false
			render()
			TweenService:Create(press, PRESS_OUT, { Scale = 1 }):Play()
		end
	end
	hit.MouseButton1Up:Connect(release)
	hit.MouseLeave:Connect(release)
	-- A second activation inside the repeat window is a double tap, not a new intent.
	local lastFired = -math.huge
	hit.Activated:Connect(function()
		release()
		if self.enabled and os.clock() - lastFired >= Theme.Motion.repeatGuard then
			lastFired = os.clock()
			onActivated()
		end
	end)
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
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
	Art.apply(Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame }), "ui_ovenRing_idle")

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
	-- Phone top-row rings are ~50px; let the status shrink below the usual 12px floor there.
	Ui.new("UITextSizeConstraint", { MinTextSize = if size < 70 then 9 else 12, MaxTextSize = 22, Parent = statusLabel })

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

function Widgets.patience(): Patience
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 68) })
	Ui.new("UIAspectRatioConstraint", { AspectRatio = Assets.Meta.patienceAspect, Parent = frame })
	local art = Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local fm = Assets.Meta.patienceFill
	local fill = Ui.new("Frame", {
		BackgroundColor3 = C.basil,
		Position = UDim2.fromScale(fm.x, fm.y),
		Size = UDim2.fromScale(fm.w, fm.h),
		ZIndex = 2,
		Parent = frame,
	}, { Ui.round() })

	local shownBand = nil
	local p: Patience = {
		frame = frame,
		set = function(_p: Patience, fraction: number, band: string)
			if band ~= shownBand then
				shownBand = band
				Art.apply(art, "ui_patience_" .. band)
			end
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
	Art.apply(Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame }), "ui_orderTicket_blank")
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
	line(Recipes.Doneness[order.bake].label, Theme.Font.bodySemi, 0, nil, 20)
	line(order.slices .. " slices", Theme.Font.bodySemi, 0, nil, 21)
	return frame
end

------------------------------------------------------------------------------------------
-- Rail ticket: the order being worked on, as in the approved references: ticket number and
-- patience on top, then one line per requirement with its picture.

export type RailTicket = {
	frame: Frame,
	customer: any,
	set: (RailTicket, any) -> (),
	setPatience: (RailTicket, number, string) -> (),
}

-- Every line is a picture plus live text. Phone tickets use the short ingredient name and
-- put a half-pizza region on a second, smaller line, so nothing drops under 16/14 px. The
-- bake and slice pictures come from Astra's icon family; until they arrive their space stays
-- reserved and empty.
local function requirementLines(order: any, compact: boolean): { { icon: string?, title: string, sub: string? } }
	local recipe = Recipes.ById[order.recipe]
	local lines = {}
	if #recipe.toppings == 0 then
		table.insert(lines, { icon = "pizza_raw", title = "Cheese only", sub = if compact then nil else "No toppings" })
	end
	for _, req in recipe.toppings do
		local info = Recipes.Ingredients[req.ingredient]
		local icon = "topping_" .. info.art .. "_1"
		if compact then
			local sub = if req.region ~= "whole" then REGION_TEXT[req.region] else nil
			table.insert(lines, { icon = icon, title = string.format("%s x%d", info.short or info.name, req.count), sub = sub })
		else
			local where = if req.region ~= "whole" then ", " .. REGION_TEXT[req.region] else ""
			local sub = string.format("%d piece%s", req.count, if req.count == 1 then "" else "s") .. where
			table.insert(lines, { icon = icon, title = info.name, sub = sub })
		end
	end
	local doneness = Recipes.Doneness[order.bake]
	table.insert(lines, { icon = doneness.icon, title = doneness.label })
	-- The slice picture shows the pizza cut into exactly this many slices.
	table.insert(lines, { icon = string.format("icon_slices_%d", order.slices), title = order.slices .. " slices" })
	return lines
end

-- Astra's three-part ticket: the caps keep their drawn proportions for the width (96 px at
-- the 840 px master: 48 px at 420, 19 px at 168) and only the middle stretches. The parts
-- abut with no overlap.
function Widgets.ticketBody(parent: GuiObject, w: number, h: number)
	local cap = math.round(w * Assets.Meta.ticket.cap / Assets.Meta.ticket.width)
	local function part(name: string, y: number, height: number)
		Art.apply(Ui.new("ImageLabel", {
			Name = name,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Stretch,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(w, height),
			Parent = parent,
		}), name)
	end
	part("ui_ticket_top", 0, cap)
	part("ui_ticket_mid", cap, h - cap * 2)
	part("ui_ticket_bottom", h - cap, cap)
end

function Widgets.railTicket(size: Vector2, compact: boolean): RailTicket
	local frame = Ui.new("Frame", { Name = "Ticket", BackgroundTransparency = 1, Size = UDim2.fromOffset(size.X, size.Y) })
	Widgets.ticketBody(frame, size.X, size.Y)
	-- Astra's content insets: 12/14 px on the 168 px phone ticket, 28/32 px at 420 px.
	local padX = if compact then 12 else math.round(size.X * 28 / 420)
	local padTop = if compact then 14 else math.round(size.X * 32 / 420)
	local padBottom = padTop
	local inner = Vector2.new(size.X - padX * 2, size.Y - padTop - padBottom)
	local headerH = math.clamp(math.round(inner.Y * 0.2), 28, 70)
	local number = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = math.floor(headerH * 0.72),
		TextWrapped = false,
		Position = UDim2.fromOffset(padX, padTop),
		Size = UDim2.fromOffset(inner.X * 0.5, headerH * 0.72),
		Parent = frame,
	})
	local name = Ui.text({
		FontFace = Theme.Font.bodySemi,
		TextSize = math.max(14, math.floor(headerH * 0.3)),
		TextColor3 = C.mutedInk,
		TextWrapped = false,
		Position = UDim2.fromOffset(padX, padTop + headerH * 0.7),
		Size = UDim2.fromOffset(inner.X * 0.5, math.max(14, math.floor(headerH * 0.3))),
		Parent = frame,
	})
	local meter = Widgets.patience()
	meter.frame.AnchorPoint = Vector2.new(1, 0)
	meter.frame.Position = UDim2.fromOffset(padX + inner.X, padTop + headerH * 0.1)
	meter.frame.Size = UDim2.fromOffset(inner.X * 0.5, headerH * 0.8)
	meter.frame.Parent = frame
	local body = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padX, padTop + headerH + 4),
		Size = UDim2.fromOffset(inner.X, inner.Y - headerH - 4),
		Parent = frame,
	})

	local key = nil
	local ticket: RailTicket
	ticket = {
		frame = frame,
		customer = nil,
		set = function(t: RailTicket, customer: any)
			t.customer = customer
			local k = if customer then string.format("%d|%s|%s|%d", customer.id, customer.order.recipe, customer.order.bake, customer.order.slices) else nil
			if k == key then
				return
			end
			key = k
			Ui.clear(body)
			if not customer then
				return
			end
			number.Text = string.format("#%02d", customer.id)
			name.Text = Recipes.Cast[customer.cast].name
			local lines = requirementLines(customer.order, compact)
			-- On phones a line with a second row gets a little more height than the others.
			local weights, total = {}, 0
			for i, line in lines do
				weights[i] = if compact and line.sub then 1.3 else 1
				total += weights[i]
			end
			local unit = math.min(body.Size.Y.Offset / math.max(total, 3), if compact then 40 else 76)
			local icon = if compact then math.clamp(math.floor(unit * 0.8), 24, 30) else math.floor(unit * 0.78)
			local y = 0
			for i, line in lines do
				local rowH = unit * weights[i]
				local row = Ui.new("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.new(1, 0, 0, rowH),
					Parent = body,
				})
				y += rowH
				if line.icon then
					local img = Ui.new("ImageLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0, 0.5),
						Size = UDim2.fromOffset(icon, icon),
						Parent = row,
					})
					Art.apply(img, line.icon)
				end
				local textX = icon + math.floor(rowH * 0.2)
				-- Style guide floor: 16 px for ordinary text, 14 for secondary.
				local titleSize = math.clamp(math.floor(rowH * (if line.sub then 0.4 elseif compact then 0.56 else 0.44)), 16, 28)
				local title = Ui.text({
					Text = line.title,
					FontFace = Theme.Font.display,
					TextScaled = true,
					TextWrapped = false,
					AnchorPoint = Vector2.new(0, if line.sub then 1 else 0.5),
					Position = UDim2.new(0, textX, if line.sub then 0.56 else 0.5, 0),
					Size = UDim2.new(1, -textX, 0, titleSize + 2),
					Parent = row,
				})
				-- Long titles shrink to fit, but never under the 16 px floor.
				Ui.new("UITextSizeConstraint", { MaxTextSize = titleSize, MinTextSize = 16, Parent = title })
				if line.sub then
					local subSize = math.clamp(math.floor(rowH * 0.32), 14, 24)
					Ui.text({
						Text = line.sub,
						FontFace = Theme.Font.bodySemi,
						TextSize = subSize,
						TextColor3 = C.mutedInk,
						TextWrapped = false,
						TextTruncate = Enum.TextTruncate.AtEnd,
						Position = UDim2.new(0, textX, 0.56, 0),
						Size = UDim2.new(1, -textX, 0, subSize + 2),
						Parent = row,
					})
				end
			end
		end,
		setPatience = function(_t: RailTicket, fraction: number, band: string)
			meter:set(fraction, band)
		end,
	}
	return ticket
end

-- Rail tab: a waiting ticket in one line (patience face, number, toppings with counts).

export type RailTab = { button: TextButton, customer: any, setPatience: (RailTab, number, string) -> () }

-- Compact tabs sit two to a row on two lines: the face and number, then the toppings side
-- by side, so waiting orders tell apart by number as well as by their pictures.
function Widgets.railTab(customer: any, height: number, compact: boolean?, width: number?): RailTab
	local button = Ui.new("TextButton", {
		Name = "Tab" .. customer.id,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = if compact then UDim2.new(0.5, -2, 0, height) else UDim2.new(1, 0, 0, height),
	})
	Art.apply(Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = button }), "ui_ticket_tab")
	local faceSize = if compact then 24 else math.floor(height * 0.72)
	local faceX = if compact then 4 else 6
	-- The patience proofs carry the face in their left square; show just that part.
	local face = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if compact then UDim2.fromOffset(faceX, 4 + faceSize / 2) else UDim2.new(0, faceX, 0.5, 0),
		Size = UDim2.fromOffset(faceSize, faceSize),
		ImageRectSize = Vector2.new(216, 216),
		Parent = button,
	})
	local recipe = Recipes.ById[customer.order.recipe]
	local textSize = math.clamp(math.floor(height * 0.46), 16, 30)
	if compact then
		Ui.text({
			Text = string.format("#%02d", customer.id),
			FontFace = Theme.Font.display,
			TextSize = 16,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(faceX + faceSize + 4, 4 + faceSize / 2),
			Size = UDim2.fromOffset(40, faceSize),
			Parent = button,
		})
		local icon = 20
		local list = if #recipe.toppings > 0 then recipe.toppings else { { ingredient = "" } }
		for i, req in list do
			local img = Ui.new("ImageLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(faceX + (i - 1) * (icon + 4), height - icon - 6),
				Size = UDim2.fromOffset(icon, icon),
				Parent = button,
			})
			-- Cheese only: the plain pizza is the picture.
			Art.apply(img, if req.ingredient ~= "" then "topping_" .. Recipes.Ingredients[req.ingredient].art .. "_1" else "pizza_raw")
		end
	else
		Ui.text({
			Text = string.format("#%02d", customer.id),
			FontFace = Theme.Font.display,
			TextSize = textSize,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, faceSize + 12, 0.5, 0),
			Size = UDim2.fromOffset(textSize * 2.2, height),
			Parent = button,
		})
		local x = faceSize + 12 + textSize * 2.4
		local icon = math.floor(height * 0.62)
		for _, req in recipe.toppings do
			local info = Recipes.Ingredients[req.ingredient]
			local img = Ui.new("ImageLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(icon, icon),
				Parent = button,
			})
			Art.apply(img, "topping_" .. info.art .. "_1")
			Ui.text({
				Text = "x" .. req.count,
				FontFace = Theme.Font.display,
				TextSize = math.floor(textSize * 0.8),
				TextWrapped = false,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x + icon + 2, 0.5, 0),
				Size = UDim2.fromOffset(textSize * 1.6, height),
				Parent = button,
			})
			x += icon + textSize * 1.9
		end
		if #recipe.toppings == 0 then
			Ui.text({
				Text = "Cheese",
				FontFace = Theme.Font.display,
				TextSize = math.floor(textSize * 0.8),
				TextWrapped = false,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(textSize * 4, height),
				Parent = button,
			})
		end
	end
	local band = nil
	local tab: RailTab = {
		button = button,
		customer = customer,
		setPatience = function(_t: RailTab, _fraction: number, b: string)
			if b ~= band then
				band = b
				Art.apply(face, "ui_patience_" .. b)
			end
		end,
	}
	return tab
end

------------------------------------------------------------------------------------------
-- The pizza after the topping station: the same generated base and topping sprites the
-- Topping station uses (PizzaArt), so one pizza travels through every station. The crust
-- and cheese crossfade through the drawn bake states (raw, light, regular, well done,
-- burnt; G6) by how long the pizza has baked. Toppings only darken lightly as a tint until
-- their baked drawings exist (G7), so ingredients stay recognizable (per Astra's
-- correction). Contact shadows keep their own tint.

-- Seconds of baking at which each drawn state is fully shown; the last is the burnt look.
local BAKE_STATES = {
	{ art = "pizza_raw", at = 0 },
	{ art = "pizza_bake_light", at = Config.Oven.targets.light },
	{ art = "pizza_bake_regular", at = Config.Oven.targets.regular },
	{ art = "pizza_bake_well", at = Config.Oven.targets.well },
	{ art = "pizza_bake_burnt", at = Config.Oven.targets.well + Config.Oven.burntAfter },
}

local RAW, TOPPING_GOLDEN, TOPPING_BURNT = Color3.new(1, 1, 1), Color3.fromRGB(236, 218, 198), Color3.fromRGB(116, 80, 60)

local function toppingTint(seconds: number): Color3
	local regular = Config.Oven.targets.regular
	if seconds <= regular then
		return RAW:Lerp(TOPPING_GOLDEN, math.max(seconds, 0) / regular)
	end
	return TOPPING_GOLDEN:Lerp(TOPPING_BURNT, math.clamp((seconds - regular) / (BAKE_STATES[#BAKE_STATES].at - regular), 0, 1))
end

-- The two neighbouring drawn states and how far the pizza is from the first to the second.
local function bakeBlend(seconds: number): (number, number)
	for i = 1, #BAKE_STATES - 1 do
		if seconds < BAKE_STATES[i + 1].at then
			return i, math.clamp((seconds - BAKE_STATES[i].at) / (BAKE_STATES[i + 1].at - BAKE_STATES[i].at), 0, 1)
		end
	end
	return #BAKE_STATES - 1, 1
end

function Widgets.doneness(seconds: number): number
	return seconds / Config.Oven.targets.regular
end

export type PizzaView = { frame: Frame, cutLayer: Frame, set: (PizzaView, any, number, boolean?) -> () }

function Widgets.pizza(): PizzaView
	local art = PizzaArt.new()
	local frame = art.frame
	Ui.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = frame })
	-- The drawn bake states replace PizzaArt's raw base: the lower one is fully shown and
	-- the upper one fades in over it.
	local base = frame:FindFirstChild("Base") :: ImageLabel
	base.ImageTransparency = 1
	local lower = Ui.new("ImageLabel", { Name = "BakeLower", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local upper = Ui.new("ImageLabel", { Name = "BakeUpper", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	local shownState = 0
	-- Inside the pizza's frame, so cut lines move with its wobble.
	local cutLayer = Ui.new("Frame", { Name = "Cuts", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = frame })

	local cutKey = ""
	local view: PizzaView = {
		frame = frame,
		cutLayer = cutLayer,
		set = function(_v: PizzaView, pizza: any, doneness: number, burnt: boolean?)
			art:set(pizza, false)
			local seconds = doneness * Config.Oven.targets.regular
			if burnt then
				seconds = math.max(seconds, BAKE_STATES[#BAKE_STATES].at)
			end
			local i, t = bakeBlend(seconds)
			if i ~= shownState then
				shownState = i
				Art.apply(lower, BAKE_STATES[i].art)
				Art.apply(upper, BAKE_STATES[i + 1].art)
			end
			upper.ImageTransparency = 1 - t
			local tint = toppingTint(seconds)
			for _, d in frame:GetDescendants() do
				if d:IsA("ImageLabel") and d.Name == "Sprite" then
					d.ImageColor3 = tint
				end
			end
			local parts = { tostring(pizza.id) }
			for _, line in pizza.cuts or {} do
				table.insert(parts, string.format("%.3f%.3f%.3f%.3f", line.x1, line.y1, line.x2, line.y2))
			end
			local key = table.concat(parts, ",")
			if key ~= cutKey then
				cutKey = key
				Ui.clear(cutLayer)
				for _, line in pizza.cuts or {} do
					Widgets.drawCut(cutLayer, line)
				end
			end
		end,
	}
	return view
end

-- A cut: the generated groove (G9) stretched along the chord of the infinite line through
-- the two points, clipped to the pizza circle. `transparency` fades it (the live preview).
local CRUST_EDGE = 0.95

function Widgets.drawCut(layer: Frame, line: any, transparency: number?)
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
	-- The crust edge sits a little inside the pizza frame; stop the groove there.
	local half = math.sqrt(1 - d2) * CRUST_EDGE
	local groove = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ImageTransparency = transparency or 0,
		ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + cx * 0.5, 0.5 + cy * 0.5),
		Size = UDim2.fromScale(half, 0.034),
		Rotation = math.deg(math.atan2(dy, dx)),
		ZIndex = 3,
		Parent = layer,
	})
	Art.apply(groove, "fx_cut_groove_b")
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

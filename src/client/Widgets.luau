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
-- Primary actions use Astra's coral V2 button and secondary actions her cream one; each
-- family's states share one body outline, so only the image changes between states.

export type Button = {
	frame: Frame,
	hit: TextButton,
	label: TextLabel,
	setEnabled: (Button, boolean) -> (),
	setHighlighted: (Button, boolean) -> (),
	setLabel: (Button, string) -> (),
	setIcon: (Button, string?) -> (),
	enabled: boolean,
	highlighted: boolean,
}

local BUTTON_STATES = { "idle", "pressed", "disabled", "highlighted" }
local PRESS_IN = TweenInfo.new(Theme.Motion.press, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT = TweenInfo.new(Theme.Motion.release + 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local preloaded = false

function Widgets.button(text: string, onActivated: () -> (), kind: ("primary" | "secondary")?): Button
	local primary = kind ~= "secondary"
	local artPrefix = if primary then "ui_button_primary_" else "ui_button_secondary_"
	local meta = if primary then Assets.Meta.buttonPrimary else Assets.Meta.buttonSecondary
	if not preloaded then
		preloaded = true
		local names = {}
		for _, state in BUTTON_STATES do
			table.insert(names, "ui_button_primary_" .. state)
			if state ~= "highlighted" then
				table.insert(names, "ui_button_secondary_" .. state)
			end
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
		SliceCenter = meta.slice,
		Parent = body,
	})
	local label = Ui.text({
		Name = "Label",
		Text = text,
		FontFace = Theme.Font.display,
		TextColor3 = if primary then C.label else C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 3,
		Parent = body,
	})
	local sizeLimit = Ui.new("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 30, Parent = label })
	-- Optional supplied icon left of the label (icon_undo, icon_oven_white). When the button
	-- is too narrow for both, the icon stands alone and the label is kept for screen readers.
	local icon = Ui.new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0, 0.5), Visible = false, ZIndex = 3, Parent = body })
	local iconName: string? = nil
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
		-- The cream family has no highlighted state; it stays idle.
		Art.apply(art, artPrefix .. (if not primary and state == "highlighted" then "idle" else state))
		if primary then
			label.TextColor3 = if state == "disabled" then C.labelDisabled else C.label
			stroke.Enabled = state ~= "disabled"
		else
			label.TextColor3 = if state == "disabled" then C.mutedInk else C.ink
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
		art.SliceScale = math.max(h / meta.height, 0.05)
		local innerW, innerH = math.max(w - insetX * 2, 0), math.max(h - insetY * 2, 0)
		sizeLimit.MaxTextSize = math.clamp(math.round(h * 0.29), 16, 32)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromOffset(innerW, innerH)
		label.Visible = true
		icon.Visible = iconName ~= nil
		if iconName then
			local iconSize = math.round(math.min(innerH * 1.1, h * 0.5))
			local gap = math.round(iconSize * 0.25)
			-- The label's width at its smallest allowed size (display font, about 0.55 em a glyph).
			local need = #label.Text * 16 * 0.55
			if innerW < iconSize + gap + need then
				label.Visible = false
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
			else
				label.Size = UDim2.fromOffset(innerW - iconSize - gap, innerH)
				label.Position = UDim2.new(0.5, (iconSize + gap) / 2, 0.5, 0)
				local textW = math.min(label.TextBounds.X, innerW - iconSize - gap)
				icon.AnchorPoint = Vector2.new(0, 0.5)
				icon.Position = UDim2.new(0.5, -(textW + iconSize + gap) / 2 + 0, 0.5, 0)
			end
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
		end
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
		setIcon = function(_b: Button, name: string?)
			iconName = name
			if name then
				Art.apply(icon, name)
			end
			layout()
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
	label:GetPropertyChangedSignal("TextBounds"):Connect(function()
		if iconName and label.Visible then
			layout()
		end
	end)
	layout()
	render()
	return self
end

------------------------------------------------------------------------------------------
-- Oven status (HUD): Astra's cream pill with the oven's badge at its left end, a progress
-- ring round the badge and the live status word. The ring is her full-circle sprite shown
-- through two half-clips whose gradients reveal it clockwise; nothing is drawn in code.

export type OvenStatus = { frame: Frame, set: (OvenStatus, number, string, string, string) -> () }

local HALF = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.5001, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local OVEN_STATES = { "idle", "cooking", "ready", "burnt" }

function Widgets.ovenStatus(width: number, height: number, compact: boolean): OvenStatus
	local names = {}
	for _, state in OVEN_STATES do
		table.insert(names, "ui_oven_badge_" .. state)
		if state ~= "idle" then
			table.insert(names, "ui_ring_fill_" .. state)
		end
	end
	Art.preload(names)
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height) })
	local pm = Assets.Meta.ovenPill
	-- The pill sits a little inside the ring's height so the ring reads as mounted on its end.
	local pillH = math.round(height * 0.8)
	local pill = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = pm.slice,
		SliceScale = pillH / pm.height,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, height * 0.5, 0.5, 0),
		Size = UDim2.fromOffset(width - height * 0.5, pillH),
		Parent = frame,
	})
	Art.apply(pill, "ui_oven_pill")
	local disc = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(height, height), ZIndex = 2, Parent = frame })
	local badge = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		ZIndex = 2,
		Parent = disc,
	})
	local rings: { ImageLabel } = {}
	local gradients: { [string]: UIGradient } = {}
	for _, side in { "right", "left" } do
		local clip = Ui.new("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(if side == "right" then 0.5 else 0, 0),
			ZIndex = 3,
			Parent = disc,
		})
		local img = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(height, height),
			Position = UDim2.fromOffset(if side == "right" then -height / 2 else 0, 0),
			ZIndex = 3,
			Parent = clip,
		})
		gradients[side] = Ui.new("UIGradient", { Transparency = HALF, Parent = img })
		table.insert(rings, img)
	end
	local number = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = math.max(16, math.floor(height * 0.4)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 4,
		Parent = disc,
	})
	local status = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = if compact then 16 else math.clamp(math.floor(height * 0.4), 16, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Position = UDim2.fromOffset(height + 2, 0),
		Size = UDim2.new(1, -(height + 2) - math.round(pillH * 0.3), 1, 0),
		ZIndex = 2,
		Parent = frame,
	})
	local shown = nil
	local o: OvenStatus = {
		frame = frame,
		set = function(_o: OvenStatus, progress: number, state: string, slotText: string, statusText: string)
			if state ~= shown then
				shown = state
				Art.apply(badge, "ui_oven_badge_" .. state)
				for _, img in rings do
					if state ~= "idle" then
						Art.apply(img, "ui_ring_fill_" .. state)
					end
				end
			end
			local angle = math.clamp(progress, 0, 1) * 360
			gradients.right.Rotation = math.clamp(angle, 0, 180)
			gradients.left.Rotation = math.clamp(angle, 180, 360)
			for _, img in rings do
				img.Visible = state ~= "idle" and progress > 0
			end
			number.Text = slotText
			status.Text = statusText
		end,
	}
	o:set(0, "idle", "", "")
	return o
end

------------------------------------------------------------------------------------------
-- Patience meter: Astra's face for the band, then her track with the band's fill laid over
-- it at full size and revealed through a clipping frame, so the fill art never squashes.

export type Patience = { frame: Frame, set: (Patience, number, string) -> () }

local BAND_FILL = { happy = "green", neutral = "green", impatient = "amber", grumpy = "red" }

function Widgets.patience(): Patience
	local frame = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(264, 64) })
	Ui.new("UIAspectRatioConstraint", { AspectRatio = 4, Parent = frame })
	local face = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.25, 1),
		ZIndex = 2,
		Parent = frame,
	})
	local mm = Assets.Meta.meter
	local track = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = mm.slice,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.25, 2, 0.5, 0),
		Size = UDim2.new(0.75, -2, 0.42, 0),
		Parent = frame,
	})
	Art.apply(track, "ui_patience_track")
	local clip = Ui.new("Frame", { BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2, Parent = track })
	local fill = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = mm.slice,
		ZIndex = 2,
		Parent = clip,
	})
	local shownBand, shownFill = nil, nil
	local fraction = 1
	local function layout()
		local w, h = track.AbsoluteSize.X, track.AbsoluteSize.Y
		if h <= 0 then
			return
		end
		local k = h / mm.height
		track.SliceScale = k
		fill.SliceScale = k
		fill.Size = UDim2.fromOffset(w, h)
		-- The fill's drawn body runs from fillLeft to fillRight of the 512 px canvas; the
		-- slice margins keep their scaled size, so the right end sits that far in from w.
		local left, right = mm.fillLeft * k, w - (mm.width - mm.fillRight) * k
		clip.Size = UDim2.fromOffset(left + (right - left) * fraction, h)
		clip.Visible = fraction > 0.005
	end
	track:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local p: Patience = {
		frame = frame,
		set = function(_p: Patience, f: number, band: string)
			fraction = math.clamp(f, 0, 1)
			if band ~= shownBand then
				shownBand = band
				Art.apply(face, "ui_patience_" .. band)
			end
			local fillName = BAND_FILL[band]
			if fillName ~= shownFill then
				shownFill = fillName
				Art.apply(fill, "ui_patience_fill_" .. fillName)
			end
			layout()
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
	local nameSize = math.max(16, math.floor(headerH * 0.34))
	local name = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = nameSize,
		TextColor3 = C.ink,
		TextWrapped = false,
		Position = UDim2.fromOffset(padX, padTop + headerH * 0.68),
		Size = UDim2.fromOffset(inner.X * 0.5, nameSize),
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
	local rm = Assets.Meta.railTab
	local plate = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = rm.slice,
		SliceScale = math.min(height / rm.height, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = button,
	})
	Art.apply(plate, "ui_ticket_tab_idle")
	-- Pressed shows Astra's selected waiting tab; the frame size never changes.
	button.MouseButton1Down:Connect(function()
		Art.apply(plate, "ui_ticket_tab_selected")
	end)
	for _, signal in { button.MouseButton1Up, button.MouseLeave } do
		signal:Connect(function()
			Art.apply(plate, "ui_ticket_tab_idle")
		end)
	end
	local faceSize = if compact then 28 else math.floor(height * 0.72)
	local faceX = if compact then 4 else 6
	local face = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if compact then UDim2.fromOffset(faceX, 4 + faceSize / 2) else UDim2.new(0, faceX, 0.5, 0),
		Size = UDim2.fromOffset(faceSize, faceSize),
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
	{ art = "pizza_bake_burnt", at = Config.Oven.burntAt },
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

-- Reserved hint strip between the work surface and the tab bar: one line of live text and,
-- optionally, a row of key icons with live labels. It never takes input and never sits over
-- food, trays, ovens, tickets or controls, because the layout gives it its own band.
-- Backing is Astra's cream result card until the A21 hint chip exists.
export type HintStrip = { frame: Frame, set: (HintStrip, string?, { { icon: string, text: string } }?) -> () }

function Widgets.hintStrip(width: number, height: number, compact: boolean): HintStrip
	Art.preload({ "ui_card_result" })
	local frame = Ui.new("Frame", { Name = "Hints", BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height) })
	local card = Ui.new("ImageLabel", {
		Name = "Card",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(40, 40, 840, 360),
		SliceScale = math.min(0.5, (height - 4) / 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height - 4),
		Visible = false,
		Parent = frame,
	}, {
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, if compact then 12 else 20), PaddingRight = UDim.new(0, if compact then 12 else 20) }),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(width - 8, math.huge) }),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, if compact then 6 else 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Art.apply(card, "ui_card_result")
	local textSize = if compact then 16 else 18
	local label = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = textSize,
		TextWrapped = false,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height - 4),
		LayoutOrder = 0,
		Parent = card,
	})
	local iconSize = if compact then 24 else 32
	local keys: { Frame } = {}
	local strip: HintStrip
	strip = {
		frame = frame,
		set = function(_s: HintStrip, text: string?, legend: { { icon: string, text: string } }?)
			local entries = legend or {}
			card.Visible = (text ~= nil and text ~= "") or #entries > 0
			label.Text = text or ""
			label.Visible = label.Text ~= ""
			for i, e in entries do
				local key = keys[i]
				if not key then
					key = Ui.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, iconSize), LayoutOrder = i, Parent = card }, {
						Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
						Ui.new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(iconSize, iconSize), LayoutOrder = 1 }),
						Ui.text({ Name = "Text", FontFace = Theme.Font.bodyBold, TextSize = if compact then 14 else 16, TextColor3 = C.ink, TextWrapped = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, iconSize), LayoutOrder = 2 }),
					})
					keys[i] = key
				end
				key.Visible = true
				if key:GetAttribute("Icon") ~= e.icon then
					key:SetAttribute("Icon", e.icon)
					Art.apply(key:FindFirstChild("Icon") :: ImageLabel, e.icon)
				end
				(key:FindFirstChild("Text") :: TextLabel).Text = e.text
			end
			for i = #entries + 1, #keys do
				keys[i].Visible = false
			end
		end,
	}
	return strip
end

function Widgets.tweenIn(frame: GuiObject, offsetX: number)
	-- Visual only: the frame is fully interactive from the first frame of the slide.
	local target = frame.Position
	frame.Position = target + UDim2.fromOffset(offsetX, 0)
	TweenService:Create(frame, TweenInfo.new(Theme.Motion.station, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
end

return Widgets

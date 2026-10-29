--!strict
-- The end-of-shift card (Astra's compact receipt, visual review V25-01..03): completion
-- emblem and completed day, earned coins as the strongest row, the XP block, one quiet save
-- line and one continuation action. Built from a SummaryLines model; every label is live text.
--
-- Supplied art: ui_panel_summary, icon_shift_complete, icon_coin, icon_xp_star, ui_xp_track,
-- ui_xp_fill and the primary button family (astra-response-7); fx_oven_glow lights the coin
-- and the emblem. The rest of the reward light (Shine: sparkles, rays, the card's edge glow,
-- the star's glow, sweeps, confetti) and the save line's spinner and check (SaveLine) are
-- declared stand-ins: no sparkle, ray, cool glow, confetti, spinner or check art has been
-- supplied.
--
-- Layout and presentation are separate so the card can be re-skinned or animated without
-- touching the values: SummaryCard.build lays the card out at its final size and returns the
-- live parts; SummaryCard.show puts the model's values in them and plays the reward motion
-- (slice 5: Astra r15 motion brief, retuned and lit for Lawson's 2026-10-28 direction), which
-- always ends on those same final values.

local GuiService = game:GetService("GuiService")

local Art = require(game:GetService("ReplicatedStorage").Shared.Art)
local Assets = require(game:GetService("ReplicatedStorage").Shared.Assets)
local Motion = require(script.Parent.Motion)
local MotionPlan = require(script.Parent.MotionPlan)
local SaveLine = require(script.Parent.SaveLine)
local Shine = require(script.Parent.Shine)
local SummaryLines = require(script.Parent.SummaryLines)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Widgets = require(script.Parent.Widgets)

local C = Theme.Colour
local WHITE = Color3.new(1, 1, 1)

local SummaryCard = {}

-- Below this root height the card drops, in Astra's order (Message 15 ask 3), the optional
-- row (none is built yet), the emblem art and the bar caption, and tightens its spacing, so
-- the required reward, save and action rows keep the text floors. A qualifier the caption
-- carried moves into the rank words (Astra r17 R17-08). The action keeps its phone size (its
-- drawn silhouette is not shrunk); whatever still does not fit scrolls inside the card while
-- the save line and the action stay fixed below it.
SummaryCard.TIGHT_HEIGHT = 292

export type View = {
	tight: boolean, -- built in the small-height fallback (root under TIGHT_HEIGHT)
	compact: boolean,
	card: ImageLabel,
	-- The groups the reward motion moves. Each sits centred in a fixed-size holder, so a
	-- pop or a settle never moves the rows around it.
	header: Frame,
	earned: Frame,
	bonus: TextLabel?,
	xp: Frame,
	-- Icons sit centred in fixed holders (the layout places the holder), so each image can
	-- scale, turn or spin about its centre with room for light around it.
	emblem: ImageLabel?,
	coinHolder: Frame,
	coin: ImageLabel,
	starHolder: Frame,
	star: ImageLabel,
	title: TextLabel,
	left: Frame,
	xpRow: Frame,
	coins: TextLabel,
	xpEarned: TextLabel,
	rank: TextLabel,
	caption: TextLabel?,
	track: ImageLabel?,
	-- The bar: the confirmed part (fillClip) over the lighter projected part (ghostClip).
	fillClip: Frame?,
	ghostClip: Frame?,
	fillWidth: number,
	fillH: number,
	insetX: number,
	insetY: number,
	xpSize: number,
	captionSize: number,
	-- The fixed footer: the one save line and the action.
	footer: Frame,
	status: TextLabel,
	saveLine: SaveLine.Line, -- the save line's motion over the status row
	button: Widgets.Button,
	-- True while the reward rows scroll (the content is taller than the screen allows).
	scrolling: () -> boolean,
	-- Lasting light (dark until the reward motion lights it; never under reduced motion):
	-- rays behind the card and a glow round its edge, soft glows behind the coin and the star.
	rays: Shine.Rays,
	edge: Shine.EdgeGlow,
	coinGlow: Shine.Glow,
	starGlow: Shine.Glow,
}

-- Text sizes: desktop / phone. Phone primary text stays at 16 or more, secondary at 14.
local SIZE = {
	title = { 36, 24 },
	subtitle = { 20, 16 },
	earnedLabel = { 18, 14 },
	coins = { 44, 30 },
	bonus = { 22, 16 },
	xp = { 22, 18 },
	caption = { 18, 14 },
	status = { 20, 16 },
}

local TONE = { saved = C.basil, pending = C.mutedInk, warn = C.tomato }

-- Highlight colours the light sweeps carry through text.
local TITLE_GLINT = Color3.fromRGB(240, 164, 72)
local COIN_GLINT = Color3.fromRGB(255, 205, 96)
local XP_GLINT = Color3.fromRGB(38, 196, 168)
-- The coin's colour edge-on while it spins.
local COIN_EDGE = Color3.fromRGB(196, 124, 44)
-- The card's rays and edge glow (warm light over the dark backdrop), and the glow behind the
-- star (mint that reads on the cream card).
local RAY_LIGHT = Color3.fromRGB(255, 232, 168)
local EDGE_LIGHT = Color3.fromRGB(255, 212, 120)
-- The panel art's outer corner radius, in its own pixels (ui_panel_summary, 840x600).
local PANEL_CORNER = 45

local function size(name: string, compact: boolean): number
	return SIZE[name][if compact then 2 else 1]
end

local function row(parent: Instance, name: string, height: number, order: number, align: Enum.HorizontalAlignment?, gap: number?): Frame
	return Ui.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, gap or 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

-- An icon in a fixed holder: the holder is laid out, the image inside is centred. The holder
-- sits above its row's text (z 2) so light around the icon passes over the words.
local function badge(parent: Instance, art: string, px: number, order: number): (Frame, ImageLabel)
	local holder = Ui.new("Frame", {
		Name = art,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px, px),
		LayoutOrder = order,
		ZIndex = 2,
		Parent = parent,
	})
	local image = Ui.new("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	Art.apply(image, art)
	return holder, image
end

-- Moves a fixed-size row's contents into a centred "Group" frame of the same size, so the
-- group can scale and settle inside the row while the list layout keeps the row still.
local function lift(holder: Frame): Frame
	local group = Ui.new("Frame", {
		Name = "Group",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	for _, child in holder:GetChildren() do
		child.Parent = group
	end
	group.Parent = holder
	return group
end

-- A column of text lines that is as wide as its widest line.
local function column(parent: Instance, order: number): Frame
	return Ui.new("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = order,
		Parent = parent,
	}, {
		Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }),
	})
end

local function line(parent: Instance, name: string, font: Font, px: number, colour: Color3, order: number): TextLabel
	return Ui.text({
		Name = name,
		FontFace = font,
		TextSize = px,
		TextColor3 = colour,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = order,
		Parent = parent,
	})
end

-- A tap on the scrolling body: released within this many pixels and seconds of the press. Any
-- more movement is a scroll, never a skip (Astra r18 M18-03).
local TAP_SLOP = 10
local TAP_TIME = 0.5

-- Lays the card out inside `parent` (the full-screen summary layer) for `model`. The card is
-- as tall as its content, up to the screen. onAction runs for the action button; onTap for a
-- tap (not a scroll) on the reward rows while they scroll, which the full-screen layer behind
-- may not receive.
function SummaryCard.build(parent: Instance, area: Vector2, compact: boolean, model: any, onAction: () -> (), onTap: (() -> ())?): View
	local tight = area.Y < SummaryCard.TIGHT_HEIGHT
	local cardW = math.min(if compact then 420 else 560, area.X - 24)
	local padX = if compact then 22 else 36
	local padY = if tight then 8 elseif compact then 12 else 24
	local gap = if tight then 2 elseif compact then 4 else 12
	local innerW = cardW - padX * 2
	-- Behind the card, over the backdrop: slow light rays and a warm glow round its edge.
	local rays = Shine.rays(parent, {
		at = UDim2.fromScale(0.5, 0.5),
		radius = cardW,
		count = 16,
		colour = RAY_LIGHT,
		opacity = 0.42,
		width = 0.11,
		z = 21,
	})
	rays.setLevel(0)
	local edge = Shine.edgeGlow(parent, {
		colour = EDGE_LIGHT,
		opacity = 0.62,
		layers = if compact then 10 else 14,
		step = if compact then 2.5 else 3.5,
		z = 22,
	})
	edge.setLevel(0)
	local card = Ui.new("ImageLabel", {
		Name = "Card",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		-- 80 px margins so the slices clear the drawn corners, scaled by the smaller axis (the
		-- manifest's correction, Assets.Meta.panelSummary).
		SliceCenter = Assets.Meta.panelSummary.slice,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cardW, 200),
		ZIndex = 23,
		Parent = parent,
	})
	Art.apply(card, "ui_panel_summary")
	-- The reward rows live in the body (which scrolls if it must); the save line and the
	-- action live in the footer, always in view.
	local body = Ui.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padX, padY),
		Size = UDim2.fromOffset(innerW, 0),
		ZIndex = 1,
		Parent = card,
	})
	local content = Ui.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(innerW, 0),
		Parent = body,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- 1. Emblem, title and the completed day.
	local headH = if tight then 40 elseif compact then 44 else 72
	local head = row(content, "Header", headH, 1)
	head.ZIndex = 2
	local emblem: ImageLabel? = nil
	if not tight then
		local _, image = badge(head, "icon_shift_complete", headH, 1)
		emblem = image
	end
	local headText = column(head, 2)
	local title = line(headText, "Title", Theme.Font.display, size("title", compact), C.ink, 1)
	title.Text = "Shift complete!"
	local served = string.format("%d customer%s served", model.served, if model.served == 1 then "" else "s")
	line(headText, "Day", Theme.Font.bodyBold, size("subtitle", compact), C.mutedInk, 2).Text = if model.day
		then string.format("Day %d · %s", model.day, served)
		else served
	local headGroup = lift(head)

	-- 2. Earned coins: the shift's whole reward (snap.tips), in the HUD's currency. Above the
	-- other rows (z 3), so the coin's light passes over them.
	local earnH = if compact then 44 else 64
	local earned = row(content, "Earned", earnH, 2)
	earned.ZIndex = 3
	local coinHolder, coin = badge(earned, "icon_coin", earnH, 1)
	-- The coin's warm glow, under the coin (dark until the reward lights it).
	local coinGlow = Shine.glowShape(coinHolder, math.round(earnH * 2.1), WHITE, coin.ZIndex - 1, "fx_oven_glow")
	local earnText = column(earned, 2)
	line(earnText, "Label", Theme.Font.bodyBold, size("earnedLabel", compact), C.mutedInk, 1).Text = "Earned this shift"
	local coins = line(earnText, "Coins", Theme.Font.display, size("coins", compact), C.tomato, 2)
	local earnGroup = lift(earned)

	-- The one-time tutorial bonus: its own line, never added to the earned coins.
	local bonus: TextLabel? = nil
	if model.bonus > 0 then
		bonus = line(content, "TutorialBonus", Theme.Font.display, size("bonus", compact), C.tomato, 3)
	end

	-- 3. XP block: earned XP and rank, then the bar against the real per-rank threshold.
	-- The block's height is worked out here, not left to AutomaticSize, so its group can rise
	-- inside it without the rows below moving.
	local xpW = math.min(innerW, if compact then innerW else 440)
	local xpPad = if compact then 2 else 4
	local xpRowH = if compact then 24 else 30
	local trackH = if compact then 26 else 36
	local captionH = size("caption", compact) + 4
	local xpH = xpRowH + (if model.bar then xpPad + trackH + (if tight then 0 else xpPad + captionH) else 0)
	local xpHolder = Ui.new("Frame", {
		Name = "Xp",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(xpW, xpH),
		LayoutOrder = 4,
		ZIndex = 2,
		Parent = content,
	})
	local xpBlock = Ui.new("Frame", {
		Name = "Group",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = xpHolder,
	}, {
		Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, xpPad) }),
	})
	local xpRow = Ui.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, xpRowH), LayoutOrder = 1, Parent = xpBlock })
	local left = row(xpRow, "Left", xpRowH, 1, Enum.HorizontalAlignment.Left, 6)
	local starHolder, star = badge(left, "icon_xp_star", xpRowH, 1)
	local starGlow = Shine.glowShape(starHolder, math.round(xpRowH * 2.6), Shine.TEAL, star.ZIndex - 1)
	local xpEarned = line(left, "Earned", Theme.Font.display, size("xp", compact), C.ink, 2)
	-- The rank words take the width they need at the right; the award gets the rest.
	local rank = Ui.text({
		Name = "Rank",
		FontFace = Theme.Font.display,
		TextSize = size("xp", compact),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = 2,
		Parent = xpRow,
	})
	local caption: TextLabel? = nil
	local track: ImageLabel? = nil
	local fillClip: Frame? = nil
	local ghostClip: Frame? = nil
	local fillWidth, fillH, insetX, insetY = 0, 0, 0, 0
	if model.bar then
		-- Track and fill per Astra's manifest (Assets.Meta.xpTrack / xpFill).
		local meta, fillMeta = Assets.Meta.xpTrack, Assets.Meta.xpFill
		local s = trackH / meta.height
		local trackImage = Ui.new("ImageLabel", {
			Name = "Track",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = meta.slice,
			SliceScale = s,
			Size = UDim2.new(1, 0, 0, trackH),
			LayoutOrder = 2,
			Parent = xpBlock,
		})
		Art.apply(trackImage, "ui_xp_track")
		track = trackImage
		insetX, insetY = math.round(meta.insetX * s), math.round(meta.insetY * s)
		fillWidth = xpW - insetX * 2
		fillH = trackH - insetY * 2
		-- The same fill art twice, revealed by clipping, never squeezed: lighter for XP the
		-- save does not have yet, solid for confirmed XP on top.
		local function clip(name: string, z: number, transparency: number): Frame
			local holder = Ui.new("Frame", {
				Name = name,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromOffset(insetX, insetY),
				Size = UDim2.fromOffset(0, fillH),
				ZIndex = z,
				Parent = trackImage,
			})
			local fill = Ui.new("ImageLabel", {
				Name = "Fill",
				BackgroundTransparency = 1,
				ImageTransparency = transparency,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = fillMeta.slice,
				SliceScale = fillH / fillMeta.height,
				Size = UDim2.fromOffset(fillWidth, fillH),
				ZIndex = z,
				Parent = holder,
			})
			Art.apply(fill, "ui_xp_fill")
			return holder
		end
		ghostClip = clip("ProjectedClip", 2, 0.55)
		fillClip = clip("FillClip", 3, 0)
		caption = if tight then nil else Ui.text({
			Name = "Caption",
			FontFace = Theme.Font.bodyBold,
			TextSize = size("caption", compact),
			TextColor3 = C.mutedInk,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			Size = UDim2.new(1, 0, 0, captionH),
			LayoutOrder = 3,
			Parent = xpBlock,
		})
	end

	-- 4 and 5. The footer: the one save line and the continuation action, fixed at the
	-- bottom of the card.
	local footer = Ui.new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, padX, 1, -padY),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(innerW, 0),
		ZIndex = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local status = Ui.text({
		Name = "Status",
		FontFace = Theme.Font.bodyBold,
		TextSize = size("status", compact),
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 1,
		Parent = footer,
	})
	local saveLine = SaveLine.new(status, size("status", compact))
	-- The tight card keeps the phone button (56 px; its art draws 224/240 of that, 52 px):
	-- the reward rows scroll before the action's silhouette would shrink (Astra r17 R17-08).
	local buttonH = if compact or tight then 56 else 72
	local holder = Ui.new("Frame", { Name = "Action", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, buttonH), LayoutOrder = 2, Parent = footer })
	local button = Widgets.button(model.action.label, onAction)
	-- One stable path whatever the label says (Root.Summary.Card.Footer.Action.ActionButton).
	-- Centred, so an accent scales it about its middle.
	button.frame.Name = "ActionButton"
	button.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	button.frame.Position = UDim2.fromScale(0.5, 0.5)
	button.frame.Size = UDim2.fromOffset(if compact then 200 else 260, buttonH)
	button.frame.Parent = holder

	-- Everything inside sits above the card art.
	for _, root in { body, footer } do
		for _, d in root:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 22 + d.ZIndex
			end
		end
	end

	-- The card follows its content's height, up to the screen. Past that, the reward rows
	-- scroll in a bounded body and the footer stays where it is (Astra r17 R17-08). Sizes are
	-- read without the card's own presentation scale, so a pop never resizes the card.
	local scroller: ScrollingFrame? = nil
	local function setScrolling(on: boolean)
		if on == (scroller ~= nil) then
			return
		end
		if on then
			local frame = Ui.new("ScrollingFrame", {
				Name = "Scroll",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = if compact then 4 else 6,
				ScrollBarImageColor3 = C.mutedInk,
				ScrollBarImageTransparency = 0.35,
				VerticalScrollBarInset = Enum.ScrollBarInset.None,
				ZIndex = 22,
				Parent = body,
			})
			local downAt: Vector3? = nil
			local downTime = 0
			local function pointer(input: InputObject): boolean
				return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
			end
			frame.InputBegan:Connect(function(input: InputObject)
				if pointer(input) then
					downAt, downTime = input.Position, os.clock()
				end
			end)
			frame.InputEnded:Connect(function(input: InputObject)
				local from = downAt
				if from and pointer(input) then
					downAt = nil
					if (input.Position - from).Magnitude <= TAP_SLOP and os.clock() - downTime <= TAP_TIME and onTap then
						onTap()
					end
				end
			end)
			content.Parent = frame
			scroller = frame
		else
			content.Parent = body
			local frame = scroller :: ScrollingFrame
			scroller = nil
			frame:Destroy()
		end
	end
	-- The card's presentation scale (the panel's pop). Sizes are measured at rest only:
	-- mid-pop, the scaled sizes rounded back made the card's height wobble by a pixel or two.
	local presentation = Motion.scale(card)
	local function fit()
		if math.abs(presentation.Scale - 1) > 1e-3 then
			return
		end
		local k = if card.AbsoluteSize.X > 0 then card.AbsoluteSize.X / cardW else 1
		local contentH = math.round(content.AbsoluteSize.Y / k)
		local footH = math.round(footer.AbsoluteSize.Y / k)
		local room = math.max(area.Y - 24 - padY * 2 - gap - footH, 0)
		setScrolling(contentH > room)
		local bodyH = math.min(contentH, room)
		body.Size = UDim2.fromOffset(innerW, bodyH)
		local h = padY * 2 + bodyH + gap + footH
		card.Size = UDim2.fromOffset(cardW, h)
		card.SliceScale = math.min(cardW / Assets.Meta.panelSummary.width, h / Assets.Meta.panelSummary.height)
		-- The light behind follows the card's size: the edge glow hugs it, the rays reach
		-- half again past its corners.
		edge.root.Size = UDim2.fromOffset(cardW, h)
		edge.setCorner(PANEL_CORNER * card.SliceScale)
		rays.setRadius(math.round(math.sqrt(cardW * cardW + h * h) / 2 * 1.5))
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	footer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	presentation:GetPropertyChangedSignal("Scale"):Connect(fit)
	fit()

	return {
		tight = tight,
		compact = compact,
		card = card,
		header = headGroup,
		earned = earnGroup,
		bonus = bonus,
		xp = xpBlock,
		emblem = emblem,
		coinHolder = coinHolder,
		coin = coin,
		starHolder = starHolder,
		star = star,
		title = title,
		left = left,
		xpRow = xpRow,
		coins = coins,
		xpEarned = xpEarned,
		rank = rank,
		caption = caption,
		track = track,
		fillClip = fillClip,
		ghostClip = ghostClip,
		fillWidth = fillWidth,
		fillH = fillH,
		insetX = insetX,
		insetY = insetY,
		xpSize = size("xp", compact),
		captionSize = size("caption", compact),
		footer = footer,
		status = status,
		saveLine = saveLine,
		button = button,
		scrolling = function()
			return scroller ~= nil
		end,
		rays = rays,
		edge = edge,
		coinGlow = coinGlow,
		starGlow = starGlow,
	}
end

------------------------------------------------------------------------------------------
-- Values. writeValues puts the model's final values in the card; writeStatus the save line
-- and the action, which always show the current save state at once (never after a motion).

local function coinText(n: number): string
	return string.format("%d coin%s", n, if n == 1 then "" else "s")
end

local function bonusText(n: number): string
	return string.format("Tutorial bonus: +%d coin%s", n, if n == 1 then "" else "s")
end

-- "+30 XP · save pending" -> " · save pending": what the counting label keeps after "+n XP".
local function xpSuffix(model: any): string
	local base = string.format("+%d XP", model.xpEarned)
	local label = model.xpLabel or base
	return if string.sub(label, 1, #base) == base then string.sub(label, #base + 1) else ""
end

-- The bar's two layers: the confirmed part and, under it, the whole shown fill.
local function setFill(view: View, solid: number, shown: number)
	local function set(clip: Frame?, fraction: number)
		if clip then
			local w = math.round(view.fillWidth * math.clamp(fraction, 0, 1))
			clip.Size = UDim2.fromOffset(w, clip.Size.Y.Offset)
			-- At zero the fill is hidden outright, so no sliver of its cap shows.
			clip.Visible = w > 0
		end
	end
	set(view.fillClip, solid)
	set(view.ghostClip, math.max(shown, solid))
end

-- The rank words take the width they need; the award label gets the rest of the row. The
-- small style (a qualifier: "Projected Rank 3") uses the caption size in the muted ink.
local function writeRank(view: View, text: string, small: boolean)
	local label = view.rank
	label.Text = text
	label.TextSize = if small then view.captionSize else view.xpSize
	label.TextColor3 = if small then C.mutedInk else C.ink
	local w = math.ceil(label.TextBounds.X) + 2
	label.Size = UDim2.new(0, w, 1, 0)
	view.left.Size = UDim2.new(1, -(w + 8), 1, 0)
end

local function writeXpLabel(view: View, model: any)
	view.xpEarned.Text = model.xpLabel or string.format("+%d XP", model.xpEarned)
end

local function writeBar(view: View, model: any)
	local bar = model.bar
	if bar then
		writeRank(view, SummaryLines.rankText(bar, bar.rank, true, view.tight))
		setFill(view, bar.solidFraction, bar.fraction)
	else
		writeRank(view, if model.rank then string.format("Rank %d", model.rank) else "", false)
	end
	if view.caption then
		view.caption.Text = model.xpCaption or ""
	end
end

-- `landing` says whether the save has just landed (the save line plays it once) or how long
-- ago it did; nil keeps whatever the line shows for an unchanged state.
local function writeStatus(view: View, model: any, landing: SaveLine.Cue?)
	SaveLine.set(view.saveLine, model.tone, model.status, TONE[model.tone] or C.mutedInk, landing)
	view.button:setLabel(model.action.label)
	-- Waiting for the save is an automatic wait: the mint standby, no emphasis, no press.
	view.button:setStandby(model.action.mode == "standby")
end

local function writeValues(view: View, model: any, landing: SaveLine.Cue?)
	view.coins.Text = coinText(model.coins)
	if view.bonus then
		view.bonus.Text = bonusText(model.bonus)
	end
	writeXpLabel(view, model)
	writeBar(view, model)
	writeStatus(view, model, landing)
end

-- The save line's cue from the presentation cue: whether the save has just landed and how
-- long ago it did, on the motion clock; a fresh landing waits `delay` seconds.
local function landingOf(cue: any?, delay: number): SaveLine.Cue
	local at = if cue ~= nil then cue.savedAt else nil
	return {
		fresh = cue ~= nil and cue.saveFresh == true,
		age = if at ~= nil then Motion.now() - at else math.huge,
		delay = delay,
	}
end

------------------------------------------------------------------------------------------
-- The reward presentation (Astra r15 motion brief, section 4; Lawson 2026-10-28: fluid and
-- richly lit). A Show holds one card's presentation; Main keeps it outside the rebuilt UI.
-- It only observes the save state: the status line and the action follow the model at once,
-- and nothing here decides when the action is available (that is model.action alone).
--
-- `cue` (SummaryLines.presentation) says why the card is shown: only cue.revealEarnings
-- plays the sequence (once per shift). The panel lands as light rays and a warm glow come up
-- behind it, a little burst of confetti flies up from behind its top edge and a sweep of
-- light crosses it; the emblem stamps in with a flare; the coin spins down and glows
-- brighter as it counts among sparkles, then pays off in a flare, a ring, a burst of
-- sparkles and a toss of small coins while the light behind the card surges; the XP arrives
-- in the star's glow, counts and fills the bar from the real pre-shift progress with light
-- on its leading edge, across rank thresholds, then flashes and flares. A pending award
-- fills as a labelled projection and never gets the definitive rank-up; when the save
-- accepts it (cue.confirmXp) it locks in with a flash, and only then a real rank-up is
-- celebrated. Nothing counts twice. A shift that earned nothing is revealed quietly: no
-- rays, glows, confetti or payoff light. The save line (SaveLine) waves while the save runs
-- and lands once on "Saved!" (cue.saveFresh), which fades away after a moment.
-- At rest the rays turn slowly at a lower light, the coin and the star keep a soft glow, the
-- action gets a call to action once it can be pressed, then an occasional glint.
-- Reduced motion shows final values with a short fade on the first showing only, no light.

export type Show = {
	view: View,
	model: any,
	pr: Motion.Presentation?,
	light: boolean, -- light effects on (not reduced motion)
	festive: boolean, -- the shift earned something (coins, a bonus or XP): the card is lit
	gloryBase: number, -- the level the rays and the edge glow sit at (1 = full light)
	gloryShown: number, -- the level they show now
	coinState: string, -- "waiting" | "counting" | "done"
	xpState: string, -- "waiting" | "counting" | "done"
	filling: boolean,
	-- The running fill's own motion key and the light on its leading edge, so a correction
	-- can stop both (M18-01); fillStarted: the fill has begun (it may have ended).
	fillKey: any?,
	fillLightRemove: (() -> ())?,
	fillStarted: boolean,
	-- The confirmed rank-up has been celebrated (once per card, M18-02).
	rankCelebrated: boolean,
	-- Effects that outlive the timeline but not a skip or the card (the confetti, M18-03).
	fx: Motion.Presentation?,
	finaleStarted: boolean,
	-- The save accepted the award after the sequence's own payoff: lock in at rest.
	lockInWaiting: boolean,
	resting: boolean,
	called: boolean, -- the action's call to action has played
	closed: boolean,
	idle: { any }, -- keys of the lasting light and the resting glints
	phases: { MotionPlan.Phase },
}

local CENTRE = UDim2.fromScale(0.5, 0.5)

-- The bar at progress p (0..1) of its fill from bar.fromXp to bar.toXp, in the style of the
-- current model (a projection can be accepted while it fills). Returns the rank shown.
local function fillAt(show: Show, segments: { MotionPlan.Segment }, p: number): number
	local view = show.view
	local bar = show.model.bar
	local rank, fraction = MotionPlan.xpAt(segments, p)
	if not bar then
		return rank
	end
	local solid = if not bar.projected then fraction elseif rank == bar.baseRank then math.min(bar.baseFraction, fraction) else 0
	setFill(view, solid, fraction)
	writeRank(view, SummaryLines.rankText(bar, rank, false, view.tight))
	if view.caption then
		view.caption.Text = SummaryLines.caption(bar, rank, fraction)
	end
	return rank
end

-- The top layer of the bar as the model stands: solid once accepted, else the projection.
local function leadClip(show: Show): Frame?
	local bar = show.model.bar
	return if bar and bar.projected then show.view.ghostClip else show.view.fillClip
end

local function zAbove(gui: GuiObject, by: number?): number
	return gui.ZIndex + (by or 1)
end

------------------------------------------------------------------------------------------
-- Lasting light: the rays and edge glow behind the card (its glory) and the glows behind
-- the coin and the star. Owned by the show, not the presentation: a skip settles them to
-- their resting light, and they end only when the card closes.

local function setGlory(show: Show, level: number)
	show.gloryShown = level
	show.view.rays.setLevel(level)
	show.view.edge.setLevel(level)
end

local function gloryKey(show: Show): any
	return Motion.keyOf(show.view.rays.root, "glory")
end

-- The glory eases from where it shows to its resting level (the sequence ended or skipped).
local function settleGlory(show: Show, duration: number)
	if show.closed then
		return
	end
	local T = Motion.T
	local key = gloryKey(show)
	if not table.find(show.idle, key) then
		table.insert(show.idle, key)
	end
	local from = show.gloryShown
	show.gloryBase = T.gloryRest
	show.view.rays.setScale(1)
	Motion.run(key, duration, function(p)
		setGlory(show, from + (T.gloryRest - from) * MotionPlan.easeInOut(p))
	end)
end

-- A payoff: the glory surges past its level and comes back as the rays swell a little.
-- `strength` 1 is the coin payoff's surge.
local function surgeGlory(show: Show, strength: number)
	if not show.light or not show.festive or show.closed then
		return
	end
	local T = Motion.T
	local base = show.gloryBase
	local peak = 1 + (T.glorySurge - 1) * strength
	local rays = show.view.rays
	Motion.run(gloryKey(show), T.glorySurgeTime, function(p)
		setGlory(show, base * MotionPlan.pop(p, 1, peak))
		rays.setScale(MotionPlan.pop(p, 1, 1 + 0.06 * strength))
	end)
end

-- f() on every frame while the card stays up.
local function always(show: Show, f: () -> ())
	local key = {}
	table.insert(show.idle, key)
	local LAP = 30
	local function lap()
		if show.closed or not show.view.card.Parent then
			return
		end
		Motion.run(key, LAP, function()
			f()
		end, lap)
	end
	lap()
end

-- The rays turn on the motion clock itself, so a rebuilt card's rays carry on at the same
-- angle. `landed`: when the panel began to land (its whirl), or nil for no whirl.
local function turnRays(show: Show, landed: number?)
	local rays = show.view.rays
	always(show, function()
		local now = Motion.now()
		rays.setTurn(MotionPlan.raysTurn(now, if landed then now - landed else math.huge) % 360)
	end)
end

local function coinGlowKey(show: Show): any
	return Motion.keyOf(show.view.coinGlow.root, "glow")
end

local function starGlowKey(show: Show): any
	return Motion.keyOf(show.view.starGlow.root, "glow")
end

-- The coin's and the star's resting glow: only for a reward the card actually shows.
local function restCoinGlow(show: Show)
	show.view.coinGlow.set(1, if show.light and show.model.coins > 0 then Motion.T.coinGlowRest else 1)
end

local function restStarGlow(show: Show)
	show.view.starGlow.set(1, if show.light and show.model.xpEarned > 0 then Motion.T.starGlowRest else 1)
end

-- A soft pulse of a resting glow (a glint, a lock-in): brighter and a little larger, then back.
local function pulseGlow(key: any, glow: Shine.Glow, rest: number, life: number, by: number)
	Motion.run(key, life, function(p)
		local k = math.sin(math.pi * p)
		glow.set(1 + 0.1 * k, rest - by * k)
	end)
end

-- A little burst of confetti as the card lands (Lawson 2026-10-28): from just inside the
-- card's top edge, up and outward, some behind the card and some in front. It carries no
-- value, so the presentation does not own it: a skip lets it fall on, a rebuild clears it.
local function confetti(show: Show)
	local card = show.view.card
	local host = card.Parent
	if show.closed or not host or not host:IsA("GuiObject") then
		return
	end
	local T = Motion.T
	local w, h = card.Size.X.Offset, card.Size.Y.Offset
	local k = w / 560
	local lineY = math.round(-h / 2 + h * 0.1)
	-- The room above the line up to the top of the screen (the card is centred in its layer,
	-- whose gui may start below the top bar): on a phone the card nearly fills the height, so
	-- the burst is squashed to fit rather than thrown off the top.
	local screen = host:FindFirstAncestorWhichIsA("ScreenGui")
	local top = if screen and not screen.IgnoreGuiInset then GuiService:GetGuiInset().Y else 0
	local size = T.confettiSize * k
	-- Owned by the card's effects, not the timeline: the burst finishes its fall after the
	-- sequence ends, but a skip or the card closing removes it (Astra r18 M18-03).
	Shine.confetti(show.fx, host, {
		at = UDim2.new(0.5, 0, 0.5, lineY),
		width = w * 0.8,
		count = if show.view.compact then T.confettiCompact else T.confetti,
		speed = T.confettiSpeed * k,
		drag = T.confettiDrag,
		fall = T.confettiFall * k,
		size = size,
		life = T.confettiLife,
		back = card.ZIndex - 1,
		front = card.ZIndex + 1,
		frontShare = T.confettiFront,
		seed = 23,
		room = host.AbsolutePosition.Y + host.AbsoluteSize.Y / 2 + lineY + top - size,
	})
end

------------------------------------------------------------------------------------------
-- Payoffs and the resting state

-- A real (accepted) rank-up: the rank words pop in a warm flare and throw gold sparkles.
-- Once per card: a fill across several thresholds, the payoff and a later lock-in never
-- celebrate the same confirmed gain twice, and the rank's impact hook (sound or vibration,
-- when bound) fires only here, for an accepted award (Astra r18 M18-02).
local function celebrateRank(show: Show, pr: Motion.Presentation?)
	if show.rankCelebrated then
		return
	end
	show.rankCelebrated = true
	Motion.hook("impact", "rank")
	local view = show.view
	local T = Motion.T
	local scale = Motion.scale(view.rank)
	if pr then
		pr:own(scale, function()
			scale.Scale = 1
		end)
	end
	Motion.pop(scale, 1, T.rankPeak, T.rankPop)
	local w = view.rank.Size.X.Offset
	local h = view.xpRow.Size.Y.Offset
	local at = UDim2.new(1, -w / 2, 0.5, 0)
	Shine.flare(pr, view.xpRow, {
		at = at,
		size = math.max(w, h * 2.4),
		from = 0.6,
		to = 1.7,
		life = T.flare,
		art = "fx_oven_glow",
		peak = 0.2,
		z = view.rank.ZIndex - 1,
	})
	Shine.burst(pr, view.xpRow, {
		at = at,
		count = 8,
		from = 4,
		to = math.max(w * 0.6, h * 1.6),
		size = h * 0.8,
		colours = { Shine.GOLD, Shine.WARM },
		halo = Shine.GOLD,
		z = zAbove(view.rank),
		seed = 41,
		life = 0.5,
		stagger = 0.06,
	})
end

-- Light along the bar: a flash over the filled part and a sweep across the whole track.
local function barLight(show: Show, pr: Motion.Presentation?, life: number)
	local view = show.view
	local track, lead = view.track, leadClip(show)
	if not track or not lead then
		return
	end
	Shine.flash(pr, lead, { life = life * 0.75, peak = 0.3, z = zAbove(lead, 2), corner = UDim.new(0.5, 0) })
	Shine.sheen(pr, track, {
		life = life,
		peak = 0.2,
		inset = Vector2.new(view.insetX, view.insetY),
		corner = UDim.new(0.5, 0),
		z = zAbove(lead, 3),
		angle = 12,
	})
end

-- The star's payoff light: a mint flare, a ring and sparkles thrown out of it.
local function starLight(show: Show, pr: Motion.Presentation?, count: number, seed: number)
	local view = show.view
	local T = Motion.T
	local px = view.starHolder.Size.X.Offset
	Shine.flare(pr, view.starHolder, {
		at = CENTRE,
		size = px * 3,
		from = 0.6,
		to = 2.4,
		life = T.flare,
		colour = Shine.TEAL,
		peak = 0.2,
		z = view.star.ZIndex - 2,
	})
	Shine.ring(pr, view.starHolder, { at = CENTRE, from = px * 0.8, to = px * 2.8, life = 0.55, colour = Shine.TEAL, peak = 0, z = view.star.ZIndex - 1 })
	Shine.burst(pr, view.starHolder, {
		at = CENTRE,
		count = count,
		from = px * 0.3,
		to = px * 1.8,
		size = px * 0.7,
		colours = { Shine.TEAL, Shine.WARM },
		halo = Shine.MINT,
		z = zAbove(view.star),
		seed = seed,
		life = 0.5,
		stagger = 0.05,
	})
	if show.model.xpEarned > 0 then
		pulseGlow(starGlowKey(show), view.starGlow, T.starGlowRest, 0.6, 0.35)
	end
end

-- The save accepted an award shown as a projection: the light gain becomes solid under a
-- flash, the qualifier goes, and a real rank-up is celebrated now. Nothing counts again.
local function lockIn(show: Show)
	local view, model = show.view, show.model
	writeXpLabel(view, model)
	writeBar(view, model)
	if show.closed or not show.light then
		return
	end
	local T = Motion.T
	barLight(show, nil, T.lockIn)
	starLight(show, nil, 5, 53)
	surgeGlory(show, 0.5)
	if model.bar and model.bar.counted and model.bar.rankUp then
		celebrateRank(show, nil)
	end
end

-- A sweep of light across the action button.
local function buttonGlint(show: Show)
	local button = show.view.button
	local h = button.frame.Size.Y.Offset
	Shine.sheen(nil, button.body, {
		life = Motion.T.glint,
		peak = 0.35,
		inset = Vector2.new(math.round(h * 0.1), math.round(h * 0.12)),
		corner = UDim.new(0.5, 0),
		colour = Shine.WARM,
		z = button.label.ZIndex - 1,
		angle = 24,
	})
end

-- A glint across the coin, a twinkle on its rim and a soft pulse of its glow.
local function coinGlint(show: Show)
	local view = show.view
	local px = view.coinHolder.Size.X.Offset
	Shine.sheen(nil, view.coinHolder, {
		life = 0.45,
		peak = 0.3,
		inset = Vector2.new(px * 0.08, px * 0.08),
		corner = UDim.new(0.5, 0),
		z = zAbove(view.coin),
		angle = 30,
	})
	Shine.twinkle(nil, view.coinHolder, {
		at = UDim2.fromScale(0.22, 0.24),
		size = px * 0.55,
		colour = Shine.WARM,
		halo = Shine.WARM,
		z = zAbove(view.coin, 2),
		delay = 0.12,
	})
	pulseGlow(coinGlowKey(show), view.coinGlow, Motion.T.coinGlowRest, 0.7, 0.22)
end

-- The action is "Next shift" and can be pressed: the only state that gets the success
-- accent (a wait or "Retry save" stays calm, motion brief: errors and saving).
local function ready(show: Show): boolean
	local button = show.view.button
	return show.model.action.mode == "ready" and not button.standby and button.enabled
end

-- Once the action is ready after the sequence: one pop and a glint, once per shift.
local function callToAction(show: Show)
	if show.called or show.closed or not show.light or not ready(show) then
		return
	end
	show.called = true
	local T = Motion.T
	Motion.pop(show.view.button.press, 1, T.buttonPeak, T.buttonPop)
	buttonGlint(show)
end

-- f now and then while the card is up: first after `first` seconds, then every `period`.
local function every(show: Show, first: number, period: number, f: () -> ())
	local key = {}
	table.insert(show.idle, key)
	local function tick()
		if show.closed or not show.view.card.Parent then
			return
		end
		f()
		Motion.after(key, period, tick)
	end
	Motion.after(key, first, tick)
end

-- The sequence has ended (or was skipped, or never played): the resting state.
local function atRest(show: Show)
	if show.closed or show.resting then
		return
	end
	show.resting = true
	if show.lockInWaiting then
		show.lockInWaiting = false
		lockIn(show)
	end
	if not show.light then
		return
	end
	callToAction(show)
	local T = Motion.T
	every(show, 1.4, T.buttonGlint, function()
		if ready(show) then
			buttonGlint(show)
		end
	end)
	every(show, 2.6, T.coinGlint, function()
		if show.model.coins > 0 then
			coinGlint(show)
		end
	end)
end

-- Light on the moving bar: a glow inside the fill's leading edge, a twinkle riding its tip
-- and motes shed behind it. Returns the per-frame update (linear progress 0..1).
local function fillLight(show: Show, pr: Motion.Presentation, duration: number): ((number) -> (), () -> ())
	local view = show.view
	local track = view.track :: ImageLabel
	local lead = leadClip(show) :: Frame
	local h = view.fillH
	local k = h / 24
	local z = zAbove(view.fillClip :: Frame, 3)
	local glow = Ui.new("Frame", {
		Name = "Lead",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(math.round(h * 2.4), h),
		ZIndex = zAbove(lead),
		Parent = lead,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Ui.new("UIGradient", { Transparency = NumberSequence.new(1, 0.1) }),
	})
	local comet = Shine.twinkleShape(track, math.round(h * 2.3), Shine.WARM, z, Shine.MINT)
	local key = {}
	local function remove()
		glow:Destroy()
		comet.root:Destroy()
	end
	pr:own(key, remove)
	local rng = Random.new(23)
	local emitted = 0
	return function(p: number)
		-- In over the first 8 %, out over the last 20 %.
		local alpha = math.min(p / 0.08, 1) * (1 - math.clamp((p - 0.8) / 0.2, 0, 1))
		glow.BackgroundTransparency = 1 - 0.85 * alpha
		local x = view.insetX + lead.Size.X.Offset
		comet.root.Position = UDim2.new(0, x, 0.5, 0)
		comet.set(alpha, 1 - alpha, p * 200)
		local due = math.floor(p * duration / Motion.T.moteEvery)
		while emitted < due and alpha > 0.05 do
			emitted += 1
			Shine.mote(pr, track, {
				at = UDim2.new(0, x - 2, 0.5, rng:NextNumber(-0.35, 0.35) * h),
				drift = Vector2.new(-rng:NextNumber(8, 24), rng:NextNumber(-12, 12)) * k,
				size = math.max(2, rng:NextNumber(3, 6) * k),
				life = Motion.T.mote,
				colour = if emitted % 2 == 0 then WHITE else Shine.MINT,
				z = z,
				peak = 0.1,
			})
		end
		emitted = math.max(emitted, due)
		if p >= 1 then
			remove()
		end
	end, remove
end

-- Fills the bar from bar.fromXp to bar.toXp over `duration` under the show's presentation,
-- carrying overflow into the next rank; ends on the model's final bar.
local function fill(show: Show, duration: number)
	local view, model = show.view, show.model
	local bar = model.bar
	local pr = show.pr
	if not bar or not view.fillClip or not view.track or show.filling or not pr or not pr.alive then
		return
	end
	show.filling = true
	show.fillStarted = true
	local presentation = pr :: Motion.Presentation
	local key = Motion.keyOf(view.fillClip :: Frame, "fill")
	show.fillKey = key
	presentation:own(key, function()
		show.filling = false
		writeBar(view, show.model)
	end)
	Motion.trace("phase", "xpFill")
	local segments = MotionPlan.xpSegments(bar.fromXp, bar.toXp, bar.need)
	local lastRank = if segments[1] then segments[1].rank else bar.baseRank
	local light = nil
	if show.light then
		light, show.fillLightRemove = fillLight(show, presentation, duration)
	end
	Motion.run(key, duration, function(p)
		local rank = fillAt(show, segments, MotionPlan.easeOut(p))
		if rank > lastRank then
			lastRank = rank
			if show.light then
				-- A threshold: the bar flashes as it carries over. Only an accepted award's
				-- rank-up is celebrated (once, with its hook); a projection gets no definitive
				-- rank-up cue.
				local lead = leadClip(show)
				if lead then
					Shine.flash(presentation, lead, { life = 0.3, peak = 0.25, z = zAbove(lead, 2), corner = UDim.new(0.5, 0) })
				end
			end
			local now = show.model.bar
			if now and now.counted and show.light then
				celebrateRank(show, presentation)
			end
		end
		if light then
			light(p)
		end
	end, function()
		show.filling = false
		writeBar(view, show.model)
		Motion.hook("complete", "xp")
	end)
end

-- A correction while the bar fills (Astra r18 M18-01): the fill was planned from the old
-- span, so it stops where it is and the bar, the rank and the caption settle quietly on the
-- corrected values, together with the award's number. Nothing replays or celebrates.
local function rebaseFill(show: Show)
	local view = show.view
	if show.fillKey then
		Motion.stop(show.fillKey, false)
	end
	if show.fillLightRemove then
		show.fillLightRemove()
		show.fillLightRemove = nil
	end
	show.filling = false
	Motion.trace("rebase", show.model.xpEarned)
	if show.xpState ~= "done" then
		Motion.stop(Motion.keyOf(view.xpEarned, "count"), false)
		show.xpState = "done"
	end
	writeXpLabel(view, show.model)
	writeBar(view, show.model)
end

-- The XP payoff after the bar settles: the block pops, the bar flashes and a sweep crosses
-- it, the star flares and throws sparkles, light runs through the award and the light behind
-- the card surges. A real rank-up (accepted award) is celebrated here; a projection's waits
-- for the save.
local function finale(show: Show, pr: Motion.Presentation)
	local view, model = show.view, show.model
	local T = Motion.T
	show.finaleStarted = true
	local xpScale = Motion.scale(view.xp)
	pr:own(xpScale, function()
		xpScale.Scale = 1
	end)
	Motion.pop(xpScale, 1, T.finalePeak, T.finalePop)
	barLight(show, pr, 0.55)
	starLight(show, pr, 8, 17)
	Shine.text(pr, view.xpEarned, { colour = XP_GLINT, life = 0.55 })
	surgeGlory(show, 0.7)
	if model.bar and model.bar.counted and model.bar.rankUp then
		celebrateRank(show, pr)
	end
end

function SummaryCard.show(view: View, model: any, cue: any?): Show
	local show: Show = {
		view = view,
		model = model,
		pr = nil,
		light = not Motion.reduced(),
		festive = model.coins > 0 or model.bonus > 0 or model.xpEarned > 0,
		gloryBase = 0,
		gloryShown = 0,
		coinState = "done",
		xpState = "done",
		filling = false,
		fillKey = nil,
		fillLightRemove = nil,
		fillStarted = false,
		rankCelebrated = false,
		fx = nil,
		finaleStarted = false,
		lockInWaiting = false,
		resting = false,
		called = false,
		closed = false,
		idle = {},
		phases = {},
	}
	local reveal = cue ~= nil and cue.revealEarnings == true
	local fillBar = reveal and cue ~= nil and cue.advanceXp == true and model.bar ~= nil and view.track ~= nil
	local reduced = Motion.reduced()
	-- A save that has already landed when the card first shows lands as the panel does.
	writeValues(view, model, landingOf(cue, if reveal and not reduced then Motion.T.panelEnter * 0.5 else 0))
	-- The card's own fade brings the action in, so its standby look is already in place.
	view.button:rest()
	local phases = MotionPlan.rewardTimeline(model.coins, model.bonus, model.xpEarned, reveal, fillBar, reduced)
	show.phases = phases
	local T = Motion.T
	local lit = show.light and show.festive
	if #phases == 0 then
		-- Nothing replays: a later showing (a resize, a correction, a late notification) rests
		-- on the final values and the resting light, without the call to action it has had
		-- already. An acceptance that came with a rebuild still locks in once, and its action
		-- may now be ready.
		if lit then
			show.gloryBase = T.gloryRest
			setGlory(show, T.gloryRest)
			turnRays(show, nil)
		end
		restCoinGlow(show)
		restStarGlow(show)
		if cue ~= nil and cue.confirmXp == true then
			show.lockInWaiting = true
		else
			show.called = true
		end
		atRest(show)
		return show
	end
	local pr = Motion.presentation()
	show.pr = pr
	show.fx = Motion.presentation()
	pr.onFinished = function()
		atRest(show)
	end
	local function phase(name: string): MotionPlan.Phase?
		return MotionPlan.find(phases, name)
	end

	if reduced then
		-- A short fade of the whole card; every value is final already.
		local f = Motion.fader(view.card, { view.status })
		SaveLine.appear(view.saveLine, T.reducedFade)
		pr:own(f.key, function()
			f:rest()
		end)
		f:hide()
		f:show(T.reducedFade)
		pr:at(T.reducedFade, function()
			pr:finish()
		end)
		return show
	end

	-- Everything that arrives later waits hidden in its resting place; the card art, the
	-- save line and the action fade in with the panel. The glows have their own light.
	local skip: { Instance } = { view.header, view.earned, view.xp, view.status }
	if view.bonus then
		table.insert(skip, view.bonus)
	end
	local cardFade = Motion.fader(view.card, skip)
	local headFade = Motion.fader(view.header)
	local earnFade = Motion.fader(view.earned, { view.coinGlow.root })
	local xpFade = Motion.fader(view.xp, { view.starGlow.root })
	local bonusFade = if view.bonus then Motion.fader(view.bonus) else nil
	local cardScale = Motion.scale(view.card)
	local earnScale = Motion.scale(view.earned)
	local coinKey = Motion.keyOf(view.coins, "count")
	local xpKey = Motion.keyOf(view.xpEarned, "count")
	pr:own(cardScale, function()
		cardScale.Scale = 1
	end)
	pr:own(earnScale, function()
		earnScale.Scale = 1
	end)
	for _, gui in { view.card, view.header, view.earned, view.xp } do
		pr:own(Motion.keyOf(gui, "settle"), function()
			Motion.rest(gui)
		end)
	end
	for _, f in { cardFade, headFade, earnFade, xpFade, bonusFade } do
		local fader = f :: Motion.Fader
		pr:own(fader.key, function()
			fader:rest()
		end)
		fader:hide()
	end
	pr:own(coinKey, function()
		show.coinState = "done"
		view.coins.Text = coinText(show.model.coins)
	end)
	pr:own(xpKey, function()
		show.xpState = "done"
		writeXpLabel(view, show.model)
	end)
	-- The glows end on their resting light, whatever ends the presentation.
	pr:own(coinGlowKey(show), function()
		restCoinGlow(show)
	end)
	pr:own(starGlowKey(show), function()
		restStarGlow(show)
	end)
	-- The coin row is centred, so the counting label keeps its final width (the final
	-- text is in it now) and the icon does not slide sideways as digits are added.
	local finalW = math.ceil(view.coins.TextBounds.X)
	if finalW > 0 then
		view.coins.AutomaticSize = Enum.AutomaticSize.Y
		view.coins.Size = UDim2.fromOffset(finalW, 0)
		view.coins.TextXAlignment = Enum.TextXAlignment.Left
	end
	show.coinState = "waiting"
	show.xpState = "waiting"
	view.coins.Text = coinText(0)
	view.xpEarned.Text = "+0 XP" .. xpSuffix(model)
	-- The XP arrives on the real pre-shift progress and fills from there.
	if fillBar and model.bar then
		fillAt(show, MotionPlan.xpSegments(model.bar.fromXp, model.bar.toXp, model.bar.need), 0)
	end

	-- Panel: lands from 0.9 through one overshoot, rising and fading in, as light rays and a
	-- warm glow come up behind it; a glare of light crosses it and twinkles catch its rim.
	Motion.trace("phase", "panel")
	cardFade:show(T.panelFade)
	SaveLine.appear(view.saveLine, T.panelFade)
	Motion.pop(cardScale, T.panelFrom, T.panelPeak, T.panelEnter)
	Motion.settle(view.card, T.panelRise, T.panelEnter)
	Motion.hook("impact", "panel")
	if lit then
		-- The edge glow lands with the card (the same pop and rise), so it hugs the edge.
		local edgeRoot = view.edge.root
		local edgeScale = Motion.scale(edgeRoot)
		pr:own(edgeScale, function()
			edgeScale.Scale = 1
		end)
		pr:own(Motion.keyOf(edgeRoot, "settle"), function()
			Motion.rest(edgeRoot)
		end)
		Motion.pop(edgeScale, T.panelFrom, T.panelPeak, T.panelEnter)
		Motion.settle(edgeRoot, T.panelRise, T.panelEnter)
		show.gloryBase = 1
		local key = gloryKey(show)
		pr:own(key, function()
			settleGlory(show, T.gloryRestIn)
		end)
		Motion.run(key, T.gloryIn, function(p)
			setGlory(show, MotionPlan.easeOut(p))
		end)
		turnRays(show, Motion.now())
		pr:at(T.confettiAt, function()
			confetti(show)
		end)
	end
	local s = view.card.SliceScale
	Shine.sheen(pr, view.card, {
		delay = T.cardSheenDelay,
		life = T.cardSheen,
		peak = 0.45,
		inset = Vector2.new(5 * s, 5 * s),
		corner = UDim.new(0, math.round((PANEL_CORNER - 5) * s)),
		colour = WHITE,
		z = 30,
		angle = 24,
	})
	if lit then
		local rim = { { 0.03, 0.05 }, { 0.975, 0.07 }, { 0.995, 0.5 }, { 0.006, 0.62 }, { 0.955, 0.965 }, { 0.07, 0.955 } }
		local px = if view.compact then 44 else 68
		for i, at in rim do
			local gold = i % 2 == 0
			Shine.twinkle(pr, view.card, {
				at = UDim2.fromScale(at[1], at[2]),
				size = if gold then px * 0.75 else px,
				colour = if gold then Shine.GOLD else Shine.WARM,
				halo = if gold then Shine.GOLD else Shine.WARM,
				z = 31,
				delay = 0.2 + (i - 1) * 0.08,
				life = 0.6,
				spin = if gold then -50 else 50,
			})
		end
	end

	-- Heading: fades and rises; the emblem stamps in with a flare and a ring of light, light
	-- runs through the title.
	local heading = phase("heading") :: MotionPlan.Phase
	pr:at(heading.start, function()
		Motion.trace("phase", "heading")
		headFade:show(heading.duration)
		Motion.settle(view.header, T.headingRise, heading.duration)
		local emblem = view.emblem
		if emblem then
			local scale = Motion.scale(emblem)
			local tiltKey = Motion.keyOf(emblem, "tilt")
			pr:own(scale, function()
				scale.Scale = 1
			end)
			pr:own(tiltKey, function()
				emblem.Rotation = 0
			end)
			Motion.pop(scale, T.emblemFrom, T.emblemPeak, T.emblemStamp)
			Motion.run(tiltKey, T.emblemStamp, function(p)
				emblem.Rotation = MotionPlan.tilt(p, T.emblemTilt)
			end)
			local holder = emblem.Parent :: Frame
			local px = holder.Size.X.Offset
			Shine.ring(pr, holder, { at = CENTRE, from = px * 0.8, to = px * 1.9, life = 0.5, colour = Shine.GOLD, peak = 0.1, z = emblem.ZIndex - 1, delay = 0.18 })
			if lit then
				Shine.flare(pr, holder, {
					at = CENTRE,
					size = px * 2,
					from = 0.5,
					to = 1.8,
					life = T.flare,
					art = "fx_oven_glow",
					peak = 0.1,
					z = emblem.ZIndex - 2,
					delay = 0.12,
				})
				for i, at in { { 0.08, 0.16 }, { 0.94, 0.22 }, { 0.86, 0.92 } } do
					Shine.twinkle(pr, holder, {
						at = UDim2.fromScale(at[1], at[2]),
						size = px * 0.46,
						colour = Shine.WARM,
						halo = Shine.GOLD,
						z = zAbove(emblem),
						delay = 0.16 + i * 0.06,
						life = 0.5,
					})
				end
			end
		end
		Shine.text(pr, view.title, { colour = TITLE_GLINT, life = 0.75, delay = 0.22 })
	end)

	-- Coin impact: the row drops in with one overshoot while the coin spins down to face-on
	-- and its glow comes up behind it.
	local coinPx = view.coinHolder.Size.X.Offset
	local impact = phase("impact") :: MotionPlan.Phase
	pr:at(impact.start, function()
		Motion.trace("phase", "impact")
		earnFade:show(impact.duration * 0.6)
		Motion.pop(earnScale, T.impactFrom, T.impactPeak, impact.duration)
		Motion.settle(view.earned, -T.impactDrop, impact.duration)
		Shine.spin(pr, view.coin, { turns = T.coinTurns, life = T.coinSpin, edge = COIN_EDGE })
		if show.model.coins > 0 then
			Motion.run(coinGlowKey(show), T.glowIn, function(p)
				local e = MotionPlan.easeOut(p)
				view.coinGlow.set(0.6 + 0.4 * e, 1 - (1 - T.coinGlowRest) * e)
			end)
		end
		Motion.hook("impact", "coins")
	end)

	-- Coin count: the row swells a little and the coin's glow brightens while sparkles catch
	-- its rim.
	local coins = phase("coins")
	if coins then
		pr:at(coins.start, function()
			Motion.trace("phase", "coins")
			show.coinState = "counting"
			Motion.count(coinKey, show.model.coins, coins.duration, function(n)
				view.coins.Text = coinText(n)
			end, "coinTick", function()
				show.coinState = "done"
				Motion.hook("complete", "coins")
			end)
			Motion.run(earnScale, coins.duration, function(p)
				earnScale.Scale = 1 + (T.countSwell - 1) * MotionPlan.easeInOut(p)
			end)
			Motion.run(coinGlowKey(show), coins.duration, function(p)
				local e = MotionPlan.easeInOut(p)
				view.coinGlow.set(1 + 0.25 * e, T.coinGlowRest + (T.coinGlowCount - T.coinGlowRest) * e)
			end)
			local rng = Random.new(11)
			local n = math.max(1, math.floor(coins.duration / 0.2))
			for i = 0, n - 1 do
				local a = rng:NextNumber(0, math.pi * 2)
				local r = coinPx * rng:NextNumber(0.36, 0.5)
				Shine.twinkle(pr, view.coinHolder, {
					at = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r),
					size = coinPx * rng:NextNumber(0.6, 0.8),
					colour = if i % 2 == 0 then Shine.WARM else Shine.GOLD,
					halo = Shine.WARM,
					z = zAbove(view.coin),
					delay = i * coins.duration / n + rng:NextNumber(0, 0.05),
					life = 0.45,
					spin = 60,
				})
			end
		end)
	end

	-- Coin payoff: the row pops as a warm flare blooms out of the coin, a gold ring and
	-- sparkles leave it and small coins are tossed out of it, the light behind the card
	-- surges, light crosses the coin and runs through the amount.
	local payoff = phase("coinsDone")
	if payoff then
		pr:at(payoff.start, function()
			Motion.trace("phase", "coinsDone")
			Motion.pop(earnScale, T.countSwell, T.flourishPeak, T.flourishPop)
			Shine.flare(pr, view.coinHolder, {
				at = CENTRE,
				size = coinPx * 2.2,
				from = 0.7,
				to = 2.1,
				life = T.flare,
				art = "fx_oven_glow",
				peak = 0.05,
				z = view.coin.ZIndex - 2,
			})
			Motion.run(coinGlowKey(show), 0.5, function(p)
				local e = MotionPlan.easeOut(p)
				view.coinGlow.set(1.25 - 0.25 * e, T.coinGlowCount + (T.coinGlowRest - T.coinGlowCount) * e)
			end)
			Shine.ring(pr, view.coinHolder, { at = CENTRE, from = coinPx * 0.8, to = coinPx * 2.6, life = 0.55, colour = Shine.GOLD, peak = 0, z = view.coin.ZIndex - 1 })
			Shine.toss(pr, view.coinHolder, {
				at = CENTRE,
				count = MotionPlan.tossCount(show.model.coins),
				size = coinPx * 0.46,
				speed = coinPx * 6.5,
				gravity = coinPx * 22,
				spread = 140,
				edge = COIN_EDGE,
				z = zAbove(view.coin, 2),
				seed = 29,
			})
			Shine.burst(pr, view.coinHolder, {
				at = CENTRE,
				count = 10,
				from = coinPx * 0.35,
				to = coinPx * 1.6,
				size = coinPx * 0.55,
				colours = { Shine.GOLD, Shine.WARM, Shine.GOLD },
				halo = Shine.GOLD,
				z = zAbove(view.coin, 3),
				seed = 7,
				life = 0.5,
				stagger = 0.05,
			})
			Shine.sheen(pr, view.coinHolder, {
				life = 0.45,
				peak = 0.25,
				inset = Vector2.new(coinPx * 0.08, coinPx * 0.08),
				corner = UDim.new(0.5, 0),
				z = zAbove(view.coin),
				angle = 30,
			})
			Shine.text(pr, view.coins, { colour = COIN_GLINT, life = 0.55 })
			surgeGlory(show, 1)
		end)
	end
	local bonus = phase("bonus")
	if bonus and bonusFade then
		pr:at(bonus.start, function()
			Motion.trace("phase", "bonus")
			bonusFade:show(bonus.duration)
			if view.bonus then
				Shine.text(pr, view.bonus, { colour = COIN_GLINT, life = 0.55, delay = bonus.duration })
			end
		end)
	end

	-- XP arrival: the block rises in, the star spins in with mint twinkles and its glow comes
	-- up behind it.
	local starPx = view.starHolder.Size.X.Offset
	local arrive = phase("xpArrive") :: MotionPlan.Phase
	pr:at(arrive.start, function()
		Motion.trace("phase", "xpArrive")
		if not phase("xpCount") then
			show.xpState = "done"
			writeXpLabel(view, show.model)
		end
		xpFade:show(arrive.duration)
		Motion.settle(view.xp, T.xpRise, arrive.duration)
		local starScale = Motion.scale(view.star)
		local tiltKey = Motion.keyOf(view.star, "tilt")
		pr:own(starScale, function()
			starScale.Scale = 1
		end)
		pr:own(tiltKey, function()
			view.star.Rotation = 0
		end)
		Motion.pop(starScale, T.starFrom, T.starPeak, T.starSpin)
		Motion.run(tiltKey, T.starSpin, function(p)
			view.star.Rotation = MotionPlan.tilt(p, T.starTilt)
		end)
		if show.model.xpEarned > 0 then
			Motion.run(starGlowKey(show), arrive.duration + 0.2, function(p)
				local e = MotionPlan.easeOut(p)
				view.starGlow.set(0.5 + 0.5 * e, 1 - (1 - T.starGlowRest) * e)
			end)
		end
		for i, at in { { 0.05, 0.1 }, { 0.98, 0.2 }, { 0.9, 0.98 }, { 0.08, 0.9 } } do
			Shine.twinkle(pr, view.starHolder, {
				at = UDim2.fromScale(at[1], at[2]),
				size = starPx * 0.62,
				colour = if i % 2 == 0 then Shine.TEAL else Shine.WARM,
				halo = if i % 2 == 0 then Shine.MINT else Shine.TEAL,
				z = zAbove(view.star),
				delay = 0.12 + i * 0.04,
				life = 0.45,
			})
		end
	end)

	-- XP count, with the bar filling along the same progress.
	local count = phase("xpCount")
	if count then
		pr:at(count.start, function()
			Motion.trace("phase", "xpCount")
			show.xpState = "counting"
			Motion.count(xpKey, show.model.xpEarned, count.duration, function(n)
				view.xpEarned.Text = string.format("+%d XP", n) .. xpSuffix(show.model)
			end, "xpTick", function()
				show.xpState = "done"
				writeXpLabel(view, show.model)
				if not fillBar and show.light then
					-- No bar to fill: the award's own payoff is a sweep of light.
					Shine.text(pr, view.xpEarned, { colour = XP_GLINT, life = 0.55 })
				end
			end)
			if fillBar then
				-- The phase's own length, so the number and the bar end together even if
				-- the award was corrected before the count began.
				fill(show, count.duration)
			end
		end)
	end
	local done = phase("xpDone")
	if done then
		pr:at(done.start, function()
			Motion.trace("phase", "xpDone")
			finale(show, pr)
		end)
	end
	pr:at(MotionPlan.total(phases), function()
		Motion.trace("phase", "timelineEnd")
		pr:finish()
	end)
	return show
end

-- A newer snapshot of the same shift and layout (a save result, or a corrected amount with
-- the same save wording, Astra r17 R17-06): the save line and the action change at once, and
-- the values are reconciled quietly to the new model without replaying anything. A count
-- still running when its amount changes stops on the new amount; one still to come counts to
-- it. An award the save has just accepted locks in (cue.confirmXp), at once if the sequence
-- is over or its payoff has passed, else in the payoff itself.
function SummaryCard.update(show: Show, model: any, cue: any?)
	local old = show.model
	show.model = model
	local view = show.view
	writeStatus(view, model, landingOf(cue, 0))
	if view.bonus then
		view.bonus.Text = bonusText(model.bonus)
	end
	local running = SummaryCard.playing(show)
	if not running or show.coinState == "done" then
		view.coins.Text = coinText(model.coins)
	elseif show.coinState == "counting" and model.coins ~= old.coins then
		Motion.stop(Motion.keyOf(view.coins, "count"), false)
		show.coinState = "done"
		view.coins.Text = coinText(model.coins)
	end
	if not running or show.xpState == "done" then
		writeXpLabel(view, model)
	elseif show.xpState == "counting" and model.xpEarned ~= old.xpEarned then
		Motion.stop(Motion.keyOf(view.xpEarned, "count"), false)
		show.xpState = "done"
		writeXpLabel(view, model)
	end
	-- A glow only stays lit for a reward the card still shows.
	if not running then
		restCoinGlow(show)
		restStarGlow(show)
	end
	local confirm = cue ~= nil and cue.confirmXp == true
	if not running then
		if confirm then
			lockIn(show)
		else
			writeBar(view, model)
		end
	elseif show.filling then
		-- A corrected span stops the fill on the new values (M18-01); an acceptance of the
		-- same numbers carries on and fills solid.
		if not SummaryLines.sameFill(old.bar, model.bar) then
			rebaseFill(show)
		end
	else
		-- After the fill (before or in its payoff) the bar shows the new values at once.
		if show.fillStarted or show.finaleStarted then
			writeBar(view, model)
		end
		if show.finaleStarted and confirm then
			show.lockInWaiting = true
		end
		-- Before the fill starts, the fill itself uses the new model.
	end
	-- The action has just become ready (the save confirmed): it gets its call to action.
	if old.action.mode ~= "ready" and model.action.mode == "ready" then
		show.called = false
	end
	if show.resting then
		callToAction(show)
	end
end

-- Skip (tap anywhere on the summary, or the action): every value final at once, every
-- effect stopped, the lasting light settling to rest. It never touches saving or awards
-- anything.
function SummaryCard.finish(show: Show)
	local pr = show.pr
	if pr and pr.alive then
		pr:finish()
	end
	-- Foreground effects still in flight (the confetti) go with the skip.
	local fx = show.fx
	if fx and fx.alive then
		fx:finish()
	end
	show.filling = false
	writeValues(show.view, show.model)
end

-- The card is going away (the shift moved on, or it is rebuilt): stops its motion, its
-- lasting light and its resting glints for good.
function SummaryCard.close(show: Show)
	show.closed = true
	for _, key in show.idle do
		Motion.stop(key, false)
	end
	SaveLine.close(show.view.saveLine)
	SummaryCard.finish(show)
end

function SummaryCard.playing(show: Show?): boolean
	return show ~= nil and show.pr ~= nil and (show.pr :: Motion.Presentation).alive
end

return SummaryCard

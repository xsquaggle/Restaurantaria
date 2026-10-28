--!strict
-- The end-of-shift card (Astra's compact receipt, visual review V25-01..03): completion
-- emblem and completed day, earned coins as the strongest row, the XP block, one quiet save
-- line and one continuation action. Built from a SummaryLines model; every label is live text.
--
-- Supplied art: ui_panel_summary, icon_shift_complete, icon_coin, icon_xp_star, ui_xp_track,
-- ui_xp_fill and the primary button family (astra-response-7). Nothing is drawn in code.
--
-- Layout and presentation are separate so the card can be re-skinned or animated without
-- touching the values: SummaryCard.build lays the card out at its final size and returns the
-- live parts; SummaryCard.show puts the model's values in them and plays the reward motion
-- (slice 5, Astra r15 motion brief), which always ends on those same final values.

local Art = require(game:GetService("ReplicatedStorage").Shared.Art)
local Assets = require(game:GetService("ReplicatedStorage").Shared.Assets)
local Motion = require(script.Parent.Motion)
local MotionPlan = require(script.Parent.MotionPlan)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local Widgets = require(script.Parent.Widgets)

local C = Theme.Colour

local SummaryCard = {}

-- Below this root height the card drops, in Astra's order (Message 15 ask 3), the optional
-- row (none is built yet), the emblem art and the bar caption, and tightens its spacing, so
-- the required reward, save and action rows keep the text floors.
SummaryCard.TIGHT_HEIGHT = 292

export type View = {
	tight: boolean, -- built in the small-height fallback (root under TIGHT_HEIGHT)
	card: ImageLabel,
	-- The groups the reward motion moves. Each sits centred in a fixed-size holder, so a
	-- pop or a settle never moves the rows around it.
	header: Frame,
	earned: Frame,
	bonus: TextLabel?,
	xp: Frame,
	left: Frame,
	coins: TextLabel,
	xpEarned: TextLabel,
	rank: TextLabel,
	caption: TextLabel?,
	fillClip: Frame?,
	fillWidth: number,
	status: TextLabel,
	button: Widgets.Button,
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

local function icon(parent: Instance, art: string, px: number, order: number): ImageLabel
	local label = Ui.new("ImageLabel", {
		Name = art,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(px, px),
		LayoutOrder = order,
		Parent = parent,
	})
	Art.apply(label, art)
	return label
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

-- Lays the card out inside `parent` (the full-screen summary layer) for `model`. The card is
-- as tall as its content, up to the screen. onAction runs for the action button.
function SummaryCard.build(parent: Instance, area: Vector2, compact: boolean, model: any, onAction: () -> ()): View
	local tight = area.Y < SummaryCard.TIGHT_HEIGHT
	local cardW = math.min(if compact then 420 else 560, area.X - 24)
	local padX = if compact then 22 else 36
	local padY = if tight then 8 elseif compact then 12 else 24
	local innerW = cardW - padX * 2
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
		ZIndex = 21,
		Parent = parent,
	})
	Art.apply(card, "ui_panel_summary")
	local content = Ui.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padX, padY),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(innerW, 0),
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, if tight then 2 elseif compact then 4 else 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- 1. Emblem, title and the completed day.
	local headH = if tight then 40 elseif compact then 44 else 72
	local head = row(content, "Header", headH, 1)
	if not tight then
		icon(head, "icon_shift_complete", headH, 1)
	end
	local headText = column(head, 2)
	line(headText, "Title", Theme.Font.display, size("title", compact), C.ink, 1).Text = "Shift complete!"
	local served = string.format("%d customer%s served", model.served, if model.served == 1 then "" else "s")
	line(headText, "Day", Theme.Font.bodyBold, size("subtitle", compact), C.mutedInk, 2).Text = if model.day
		then string.format("Day %d · %s", model.day, served)
		else served
	local headGroup = lift(head)

	-- 2. Earned coins: the shift's whole reward (snap.tips), in the HUD's currency.
	local earnH = if compact then 44 else 64
	local earned = row(content, "Earned", earnH, 2)
	icon(earned, "icon_coin", earnH, 1)
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
	-- inside it without the save line and the button moving.
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
	icon(left, "icon_xp_star", xpRowH, 1)
	local xpEarned = line(left, "Earned", Theme.Font.display, size("xp", compact), C.ink, 2)
	local rank = Ui.text({
		Name = "Rank",
		FontFace = Theme.Font.display,
		TextSize = size("xp", compact),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.5, 1),
		Parent = xpRow,
	})
	local caption: TextLabel? = nil
	local fillClip: Frame? = nil
	local fillWidth = 0
	if model.bar then
		-- Track and fill per Astra's manifest (Assets.Meta.xpTrack / xpFill).
		local meta, fillMeta = Assets.Meta.xpTrack, Assets.Meta.xpFill
		local s = trackH / meta.height
		local track = Ui.new("ImageLabel", {
			Name = "Track",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = meta.slice,
			SliceScale = s,
			Size = UDim2.new(1, 0, 0, trackH),
			LayoutOrder = 2,
			Parent = xpBlock,
		})
		Art.apply(track, "ui_xp_track")
		local insetX, insetY = math.round(meta.insetX * s), math.round(meta.insetY * s)
		fillWidth = xpW - insetX * 2
		local fillH = trackH - insetY * 2
		fillClip = Ui.new("Frame", {
			Name = "FillClip",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(insetX, insetY),
			Size = UDim2.fromOffset(0, fillH),
			ZIndex = 2,
			Parent = track,
		})
		local fill = Ui.new("ImageLabel", {
			Name = "Fill",
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = fillMeta.slice,
			SliceScale = fillH / fillMeta.height,
			Size = UDim2.fromOffset(fillWidth, fillH),
			ZIndex = 2,
			Parent = fillClip,
		})
		Art.apply(fill, "ui_xp_fill")
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

	-- 4. The one save line.
	local status = Ui.text({
		Name = "Status",
		FontFace = Theme.Font.bodyBold,
		TextSize = size("status", compact),
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 5,
		Parent = content,
	})

	-- 5. The continuation action.
	local buttonH = if tight then 48 elseif compact then 56 else 72
	local holder = Ui.new("Frame", { Name = "Action", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, buttonH), LayoutOrder = 6, Parent = content })
	local button = Widgets.button(model.action.label, onAction)
	-- One stable path whatever the label says (Root.Summary.Card.Content.Action.ActionButton).
	button.frame.Name = "ActionButton"
	button.frame.AnchorPoint = Vector2.new(0.5, 0)
	button.frame.Position = UDim2.fromScale(0.5, 0)
	button.frame.Size = UDim2.fromOffset(if compact then 200 else 260, buttonH)
	button.frame.Parent = holder

	-- Everything inside sits above the card art.
	for _, d in content:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 22 + d.ZIndex
		end
	end

	-- The card follows its content's height, up to the screen.
	local function fit()
		local h = math.min(math.ceil(content.AbsoluteSize.Y) + padY * 2, area.Y - 24)
		card.Size = UDim2.fromOffset(cardW, h)
		card.SliceScale = math.min(cardW / Assets.Meta.panelSummary.width, h / Assets.Meta.panelSummary.height)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	return {
		tight = tight,
		card = card,
		header = headGroup,
		earned = earnGroup,
		bonus = bonus,
		xp = xpBlock,
		left = left,
		coins = coins,
		xpEarned = xpEarned,
		rank = rank,
		caption = caption,
		fillClip = fillClip,
		fillWidth = fillWidth,
		status = status,
		button = button,
	}
end


------------------------------------------------------------------------------------------
-- Values. writeValues puts the model's final values in the card; writeStatus the save line
-- and the action, which always show the current save state at once (never after a motion).

local function coinText(n: number): string
	return string.format("%d coin%s", n, if n == 1 then "" else "s")
end

-- "+30 XP · save pending" -> " · save pending": what the counting label keeps after "+n XP".
local function xpSuffix(model: any): string
	local base = string.format("+%d XP", model.xpEarned)
	local label = model.xpLabel or base
	return if string.sub(label, 1, #base) == base then string.sub(label, #base + 1) else ""
end

local function setFill(view: View, fraction: number)
	local clip = view.fillClip
	if clip then
		local w = math.round(view.fillWidth * math.clamp(fraction, 0, 1))
		clip.Size = UDim2.fromOffset(w, clip.Size.Y.Offset)
		-- At zero the fill is hidden outright, so no sliver of its cap shows.
		clip.Visible = w > 0
	end
end

local function writeXpLabel(view: View, model: any)
	view.xpEarned.Text = model.xpLabel or string.format("+%d XP", model.xpEarned)
	-- A pending qualifier ("· save pending") needs more of the row; the rank then has no
	-- rank-up words (those wait for the save).
	local leftShare = if model.xpLabel and string.find(model.xpLabel, "·") then 0.7 else 0.5
	view.left.Size = UDim2.fromScale(leftShare, 1)
	view.rank.Size = UDim2.fromScale(1 - leftShare, 1)
end

local function writeBar(view: View, model: any)
	view.rank.Text = if model.rank
		then string.format("Rank %d%s", model.rank, if model.bar and model.bar.rankUp then " · Rank up!" else "")
		else ""
	if model.bar then
		setFill(view, model.bar.fraction)
	end
	if view.caption then
		view.caption.Text = model.xpCaption or ""
	end
end

local function writeStatus(view: View, model: any)
	view.status.Text = model.status
	view.status.TextColor3 = TONE[model.tone] or C.mutedInk
	view.button:setLabel(model.action.label)
	-- Waiting for the save is an automatic wait: the mint standby, no emphasis, no press.
	view.button:setStandby(model.action.mode == "standby")
end

local function writeValues(view: View, model: any)
	view.coins.Text = coinText(model.coins)
	if view.bonus then
		view.bonus.Text = string.format("Tutorial bonus: +%d coin%s", model.bonus, if model.bonus == 1 then "" else "s")
	end
	writeXpLabel(view, model)
	writeBar(view, model)
	writeStatus(view, model)
end

------------------------------------------------------------------------------------------
-- The reward presentation (Astra r15 motion brief, section 4). A Show holds one card's
-- presentation; Main keeps it outside the rebuilt UI. It only observes the save state: the
-- status line and the action follow the model at once, and nothing here decides when the
-- action is available (that is model.action alone).
--
-- `cue` (SummaryLines.presentation) says why the card is shown: only cue.revealEarnings
-- plays the entry, coin impact, coin count and XP count (once per shift), and only
-- cue.advanceXp fills the bar, from the real pre-shift progress to the accepted total,
-- across rank thresholds. Anything else shows final values. Reduced motion shows final
-- values with a short fade on the first showing only.

export type Show = {
	view: View,
	model: any,
	pr: Motion.Presentation?,
	xpStarted: boolean, -- the XP phase has begun (a later acceptance fills at once)
	xpLabelDone: boolean, -- the XP label has finished counting (or never counts)
	fillWanted: boolean, -- the award was accepted; the XP phase fills the bar
	filling: boolean,
	-- The fill started its own presentation (no entry running), so it ends it too.
	fillOnly: boolean,
	-- The entry's timeline has ended while the fill still runs: the fill ends it.
	endAfterFill: boolean,
	phases: { MotionPlan.Phase },
}

-- The bar at progress p (0..1) of its fill from bar.fromXp to bar.toXp.
local function fillAt(view: View, bar: any, segments: { MotionPlan.Segment }, p: number)
	local rank, fraction = MotionPlan.xpAt(segments, p)
	setFill(view, fraction)
	view.rank.Text = string.format("Rank %d", rank)
	if view.caption then
		view.caption.Text = string.format("%d / %d XP to Rank %d", math.floor(fraction * bar.need + 0.5), bar.need, rank + 1)
	end
end

local function fillDuration(model: any): number
	local T = Motion.T
	return MotionPlan.countDuration(model.xpEarned, T.xpCount, T.xpCountMin, T.xpCountMax)
end

-- Fills the bar from bar.fromXp to bar.toXp over `duration` under the show's presentation
-- (or a new one), carrying overflow into the next rank; ends on the model's final bar.
local function fill(show: Show, duration: number)
	local view, model = show.view, show.model
	local bar = model.bar
	if not bar or not view.fillClip or show.filling then
		return
	end
	show.filling = true
	local pr = show.pr
	if not pr or not pr.alive then
		pr = Motion.presentation()
		show.pr = pr
		show.fillOnly = true
	end
	local presentation = pr :: Motion.Presentation
	local key = Motion.keyOf(view.fillClip :: Frame, "fill")
	presentation:own(key, function()
		show.filling = false
		writeBar(view, show.model)
	end)
	Motion.trace("phase", "xpFill")
	local segments = MotionPlan.xpSegments(bar.fromXp, bar.toXp, bar.need)
	Motion.run(key, duration, function(p)
		fillAt(view, bar, segments, MotionPlan.easeOut(p))
	end, function()
		show.filling = false
		writeBar(view, show.model)
		Motion.hook("complete", "xp")
		if show.fillOnly or show.endAfterFill then
			presentation:finish()
		end
	end)
end

function SummaryCard.show(view: View, model: any, cue: any?): Show
	local show: Show = {
		view = view,
		model = model,
		pr = nil,
		xpStarted = false,
		xpLabelDone = false,
		fillWanted = false,
		filling = false,
		fillOnly = false,
		endAfterFill = false,
		phases = {},
	}
	writeValues(view, model)
	local reveal = cue ~= nil and cue.revealEarnings == true
	local advance = cue ~= nil and cue.advanceXp == true and model.bar ~= nil and model.bar.counted == true
	local reduced = Motion.reduced()
	local phases = MotionPlan.rewardTimeline(model.coins, model.bonus, model.xpEarned, reveal, advance, reduced)
	show.phases = phases
	if #phases == 0 then
		show.xpStarted = true
		show.xpLabelDone = true
		return show
	end
	local T = Motion.T
	local pr = Motion.presentation()
	show.pr = pr
	local cardScale = Motion.scale(view.card)
	local function phase(name: string): MotionPlan.Phase?
		return MotionPlan.find(phases, name)
	end

	if reduced then
		-- A short fade of the whole card; every value is final already.
		local f = Motion.fader(view.card)
		pr:own(f.key, function()
			f:rest()
		end)
		f:hide()
		f:show(T.reducedFade)
		show.xpStarted = true
		show.xpLabelDone = true
		pr:at(T.reducedFade, function()
			pr:finish()
		end)
		return show
	end

	if reveal then
		-- Everything that arrives later waits hidden in its resting place.
		local headFade, earnFade, xpFade = Motion.fader(view.header), Motion.fader(view.earned), Motion.fader(view.xp)
		local bonusFade = if view.bonus then Motion.fader(view.bonus) else nil
		local earnScale = Motion.scale(view.earned)
		pr:own(cardScale, function()
			cardScale.Scale = 1
		end)
		pr:own(Motion.keyOf(view.card, "settle"), function()
			Motion.rest(view.card)
		end)
		pr:own(Motion.keyOf(view.header, "settle"), function()
			Motion.rest(view.header)
		end)
		pr:own(Motion.keyOf(view.earned, "settle"), function()
			Motion.rest(view.earned)
		end)
		pr:own(Motion.keyOf(view.xp, "settle"), function()
			Motion.rest(view.xp)
		end)
		pr:own(earnScale, function()
			earnScale.Scale = 1
		end)
		for _, f in { headFade, earnFade, xpFade, bonusFade } do
			local fader = f :: Motion.Fader
			pr:own(fader.key, function()
				fader:rest()
			end)
			fader:hide()
		end
		local coinKey = Motion.keyOf(view.coins, "count")
		local xpKey = Motion.keyOf(view.xpEarned, "count")
		pr:own(coinKey, function()
			view.coins.Text = coinText(show.model.coins)
		end)
		pr:own(xpKey, function()
			writeXpLabel(view, show.model)
		end)
		-- The coin row is centred, so the counting label keeps its final width (the final
		-- text is in it now) and the icon does not slide sideways as digits are added.
		local finalW = math.ceil(view.coins.TextBounds.X)
		if finalW > 0 then
			view.coins.AutomaticSize = Enum.AutomaticSize.Y
			view.coins.Size = UDim2.fromOffset(finalW, 0)
			view.coins.TextXAlignment = Enum.TextXAlignment.Left
		end
		view.coins.Text = coinText(0)
		view.xpEarned.Text = "+0 XP" .. xpSuffix(model)
		-- An accepted award arrives on the real pre-award progress and fills from there.
		if advance and model.bar then
			fillAt(view, model.bar, MotionPlan.xpSegments(model.bar.fromXp, model.bar.toXp, model.bar.need), 0)
		end

		-- Panel enter: 0.96 -> 1.01 -> 1.00 with a small upward settle.
		Motion.trace("phase", "panel")
		Motion.pop(cardScale, T.panelFrom, T.panelPeak, T.panelEnter)
		Motion.settle(view.card, T.panelRise, T.panelEnter)
		Motion.hook("impact", "panel")
		local heading = phase("heading") :: MotionPlan.Phase
		pr:at(heading.start, function()
			Motion.trace("phase", "heading")
			headFade:show(heading.duration)
			Motion.settle(view.header, T.headingRise, heading.duration)
		end)
		local impact = phase("impact") :: MotionPlan.Phase
		pr:at(impact.start, function()
			Motion.trace("phase", "impact")
			-- The coin group lands from a few px above with one overshoot.
			earnFade:show(impact.duration * 0.6)
			Motion.pop(earnScale, T.impactFrom, T.impactPeak, impact.duration)
			Motion.settle(view.earned, -T.impactDrop, impact.duration)
			Motion.hook("impact", "coins")
		end)
		local coins = phase("coins")
		if coins then
			pr:at(coins.start, function()
				Motion.trace("phase", "coins")
				Motion.count(coinKey, show.model.coins, coins.duration, function(n)
					view.coins.Text = coinText(n)
				end, "coinTick", function()
					Motion.hook("complete", "coins")
				end)
			end)
		end
		local bonus = phase("bonus")
		if bonus and bonusFade then
			pr:at(bonus.start, function()
				Motion.trace("phase", "bonus")
				bonusFade:show(bonus.duration)
			end)
		end
		local arrive = phase("xpArrive") :: MotionPlan.Phase
		pr:at(arrive.start, function()
			Motion.trace("phase", "xpArrive")
			show.xpStarted = true
			if not phase("xpCount") then
				show.xpLabelDone = true
				writeXpLabel(view, show.model)
			end
			xpFade:show(arrive.duration)
			Motion.settle(view.xp, T.xpRise, arrive.duration)
		end)
		local count = phase("xpCount")
		local countStart = arrive.start + arrive.duration
		if count then
			pr:at(count.start, function()
				Motion.trace("phase", "xpCount")
				Motion.count(xpKey, show.model.xpEarned, count.duration, function(n)
					view.xpEarned.Text = string.format("+%d XP", n) .. xpSuffix(show.model)
				end, "xpTick", function()
					show.xpLabelDone = true
					writeXpLabel(view, show.model)
				end)
			end)
		end
		show.fillWanted = advance
		pr:at(countStart, function()
			Motion.trace("phase", "xpFillCheck")
			if show.fillWanted then
				fill(show, fillDuration(show.model))
			end
		end)
		pr:at(MotionPlan.total(phases), function()
			Motion.trace("phase", "timelineEnd")
			if show.filling then
				show.endAfterFill = true
			else
				pr:finish()
			end
		end)
	else
		-- The award was accepted after the first showing: the bar alone fills, once.
		show.xpStarted = true
		show.xpLabelDone = true
		fill(show, fillDuration(model))
	end
	return show
end

-- A newer snapshot of the same shift and layout (the save result): the save line and the
-- action change at once; values a running count owns finish on the new model by themselves.
-- An award accepted now fills the bar, during the XP phase or straight away after it.
function SummaryCard.update(show: Show, model: any, cue: any?)
	show.model = model
	local view = show.view
	writeStatus(view, model)
	local running = show.pr ~= nil and (show.pr :: Motion.Presentation).alive
	if view.bonus then
		view.bonus.Text = string.format("Tutorial bonus: +%d coin%s", model.bonus, if model.bonus == 1 then "" else "s")
	end
	if not running then
		view.coins.Text = coinText(model.coins)
	end
	-- The XP label follows the new model unless its count is running (the count picks the
	-- new wording up itself) or is still to come (the label waits hidden at zero).
	if not running or show.xpLabelDone then
		writeXpLabel(view, model)
	end
	local advance = cue ~= nil and cue.advanceXp == true and model.bar ~= nil and model.bar.counted == true
	if advance and not Motion.reduced() then
		if show.xpStarted then
			fill(show, fillDuration(model))
		else
			show.fillWanted = true
		end
		return
	end
	if not show.filling then
		writeBar(view, model)
	end
end

-- Skip (tap anywhere on the summary, or the action): every value final at once, every
-- effect stopped. It never touches saving or awards anything.
function SummaryCard.finish(show: Show)
	local pr = show.pr
	if pr and pr.alive then
		pr:finish()
	end
	show.filling = false
	writeValues(show.view, show.model)
end

function SummaryCard.playing(show: Show?): boolean
	return show ~= nil and show.pr ~= nil and (show.pr :: Motion.Presentation).alive
end

return SummaryCard

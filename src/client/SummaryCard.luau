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
-- live parts; SummaryCard.present puts the model's final values in them. Motion (panel
-- settle, coin count-up, XP fill) belongs in present and must end on the same final values.

local Art = require(game:GetService("ReplicatedStorage").Shared.Art)
local Assets = require(game:GetService("ReplicatedStorage").Shared.Assets)
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

	-- 2. Earned coins: the shift's whole reward (snap.tips), in the HUD's currency.
	local earnH = if compact then 44 else 64
	local earned = row(content, "Earned", earnH, 2)
	icon(earned, "icon_coin", earnH, 1)
	local earnText = column(earned, 2)
	line(earnText, "Label", Theme.Font.bodyBold, size("earnedLabel", compact), C.mutedInk, 1).Text = "Earned this shift"
	local coins = line(earnText, "Coins", Theme.Font.display, size("coins", compact), C.tomato, 2)

	-- The one-time tutorial bonus: its own line, never added to the earned coins.
	if model.bonus > 0 then
		local bonus = line(content, "TutorialBonus", Theme.Font.display, size("bonus", compact), C.tomato, 3)
		bonus.Text = string.format("Tutorial bonus: +%d coin%s", model.bonus, if model.bonus == 1 then "" else "s")
	end

	-- 3. XP block: earned XP and rank, then the bar against the real per-rank threshold.
	local xpW = math.min(innerW, if compact then innerW else 440)
	local xpBlock = Ui.new("Frame", {
		Name = "Xp",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(xpW, 0),
		LayoutOrder = 4,
		Parent = content,
	}, {
		Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, if compact then 2 else 4) }),
	})
	local xpRowH = if compact then 24 else 30
	local xpRow = Ui.new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, xpRowH), LayoutOrder = 1, Parent = xpBlock })
	local left = row(xpRow, "Left", xpRowH, 1, Enum.HorizontalAlignment.Left, 6)
	-- A pending qualifier ("· save pending") needs more of the row; the rank then has no
	-- rank-up words (those wait for the save).
	local leftShare = if model.xpLabel and string.find(model.xpLabel, "·") then 0.7 else 0.5
	left.Size = UDim2.fromScale(leftShare, 1)
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
		Size = UDim2.fromScale(1 - leftShare, 1),
		Parent = xpRow,
	})
	local caption: TextLabel? = nil
	local fillClip: Frame? = nil
	local fillWidth = 0
	if model.bar then
		-- Track and fill per Astra's manifest (Assets.Meta.xpTrack / xpFill).
		local meta, fillMeta = Assets.Meta.xpTrack, Assets.Meta.xpFill
		local trackH = if compact then 26 else 36
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
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
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

-- Shows the model's final values. The hook for motion: a count-up sets view.coins from 0 to
-- model.coins, an XP fill moves view.fillClip from bar.fromXp to bar.toXp (both are within
-- the same rank unless bar.rankUp). Whatever runs here must finish on these values and must
-- never decide when the action is available: that comes from model.action alone. With
-- GuiService.ReducedMotionEnabled, set the final values at once (what this does today).
-- `cue` (SummaryLines.presentation, kept by Main outside the rebuilt UI) says why the card was
-- built: only cue.revealEarnings may count the coins up and only cue.advanceXp may fill the
-- bar, each once per shift; "rebuild" shows final values. No motion is built yet (slice 5).
function SummaryCard.present(view: View, model: any, cue: any?)
	local _ = cue
	view.coins.Text = string.format("%d coin%s", model.coins, if model.coins == 1 then "" else "s")
	view.xpEarned.Text = model.xpLabel or string.format("+%d XP", model.xpEarned)
	view.rank.Text = if model.rank
		then string.format("Rank %d%s", model.rank, if model.bar and model.bar.rankUp then " · Rank up!" else "")
		else ""
	if model.bar and view.fillClip then
		local w = math.round(view.fillWidth * model.bar.fraction)
		view.fillClip.Size = UDim2.fromOffset(w, view.fillClip.Size.Y.Offset)
		-- At zero the fill is hidden outright, so no sliver of its cap shows.
		view.fillClip.Visible = w > 0
	end
	if view.caption then
		view.caption.Text = model.xpCaption or ""
	end
	view.status.Text = model.status
	view.status.TextColor3 = TONE[model.tone] or C.mutedInk
	view.button:setLabel(model.action.label)
	-- Waiting for the save is an automatic wait: the mint standby, no emphasis, no press.
	view.button:setStandby(model.action.mode == "standby")
end

return SummaryCard

--!strict
-- First-shift pointer: Astra's tutorial glove and target halo point at the next action on
-- the visible station, with a short live instruction. On Bake it also shows the bake key
-- (her doneness icons with live labels). Each station's pointer stops once that action has
-- been done. The art never takes input.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Recipes = require(Shared.Recipes)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local C = Theme.Colour
local Tutorial = {}

-- The action that teaches each station.
Tutorial.Lesson = { takeOrder = "Order", placeTopping = "Topping", takeOut = "Bake", cut = "Cut" }

-- Glove rotation for each side it comes from (the drawing points up).
local ROTATION = { below = 0, above = 180, left = 90, right = -90 }

export type Hint = { target: GuiObject?, text: string, from: string?, legend: boolean?, anchor: GuiObject? }

-- `avoid` is a control strip (the tab bar) the glove must not cover.
function Tutorial.new(parent: GuiObject, compact: boolean, avoid: GuiObject?)
	Art.preload({ "ui_tutorial_hand", "ui_tutorial_target_halo", "ui_card_result" })
	local layer = Ui.new("Frame", { Name = "Tutorial", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Visible = false, Parent = parent })
	local handSize = if compact then 56 else 80
	local haloSize = if compact then 56 else 72
	local halo = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(haloSize, haloSize),
		ZIndex = 30,
		Parent = layer,
	})
	Art.apply(halo, "ui_tutorial_target_halo")
	-- A zero-size pivot at the fingertip, so turning the glove turns it about the fingertip.
	local pivot = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = 31, Parent = layer })
	local tip = Assets.Meta.tutorialHand.tip
	local hand = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-tip.X * handSize, -tip.Y * handSize),
		Size = UDim2.fromOffset(handSize, handSize),
		ZIndex = 31,
		Parent = pivot,
	})
	Art.apply(hand, "ui_tutorial_hand")

	local textSize = 16
	local cardPad = if compact then 10 else 14
	local card = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(40, 40, 840, 360),
		SliceScale = 0.5,
		ZIndex = 30,
		Parent = layer,
	})
	Art.apply(card, "ui_card_result")
	local label = Ui.text({
		FontFace = Theme.Font.display,
		TextSize = if compact then textSize else 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(cardPad, cardPad),
		ZIndex = 31,
		Parent = card,
	})
	-- Bake key: requested bake icon and its live name, then the burnt colour.
	local legend = Ui.new("Frame", { BackgroundTransparency = 1, ZIndex = 31, Parent = card }, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, if compact then 6 else 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local keyIcon = if compact then 28 else 36
	local entries = {}
	for _, id in Recipes.DonenessOrder do
		local d = Recipes.Doneness[id]
		table.insert(entries, { icon = d.icon, text = d.short })
	end
	table.insert(entries, { icon = "ui_oven_badge_burnt", text = "Burnt" })
	for i, e in entries do
		local item = Ui.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, keyIcon), LayoutOrder = i, ZIndex = 31, Parent = legend }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		Art.apply(Ui.new("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(keyIcon, keyIcon), LayoutOrder = 1, ZIndex = 31, Parent = item }), e.icon)
		Ui.text({
			Text = e.text,
			FontFace = Theme.Font.bodyBold,
			TextSize = if compact then 14 else 16,
			TextColor3 = C.ink,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, keyIcon),
			LayoutOrder = 2,
			ZIndex = 31,
			Parent = item,
		})
	end

	local haloPulse = TweenService:Create(halo, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = 0.5 })
	haloPulse:Play()

	local self = {}
	function self.show(hint: Hint?, now: number)
		layer.Visible = hint ~= nil
		if not hint then
			return
		end
		local origin = layer.AbsolutePosition
		local area = layer.AbsoluteSize
		local pointing = hint.target ~= nil and hint.target.Visible
		halo.Visible = pointing
		pivot.Visible = pointing
		local tipAt = Vector2.zero
		local from = hint.from or "below"
		if pointing then
			local t = hint.target :: GuiObject
			local p, s = t.AbsolutePosition - origin, t.AbsoluteSize
			-- Turn to the other side when the glove would leave the screen.
			if from == "left" and p.X < handSize + 8 then
				from = "right"
			elseif from == "below" then
				local floor = if avoid then avoid.AbsolutePosition.Y - origin.Y else area.Y
				local x = p.X + s.X / 2
				local overAvoid = avoid ~= nil and x + handSize > avoid.AbsolutePosition.X - origin.X and x - handSize < avoid.AbsolutePosition.X - origin.X + avoid.AbsoluteSize.X
				if p.Y + s.Y + handSize + 8 > (if overAvoid then floor else area.Y) then
					from = "above"
				end
			end
			local gap = 6
			tipAt = if from == "left" then Vector2.new(p.X - gap, p.Y + s.Y / 2)
				elseif from == "right" then Vector2.new(p.X + s.X + gap, p.Y + s.Y / 2)
				elseif from == "above" then Vector2.new(p.X + s.X / 2, p.Y - gap)
				else Vector2.new(p.X + s.X / 2, p.Y + s.Y + gap)
			-- A small tap motion toward the target.
			local towards = if from == "left" then Vector2.new(1, 0) elseif from == "right" then Vector2.new(-1, 0) elseif from == "above" then Vector2.new(0, 1) else Vector2.new(0, -1)
			local bob = towards * (math.sin(now * 5) * 0.5 + 0.5) * (if compact then 4 else 6) - towards * 6
			pivot.Position = UDim2.fromOffset(tipAt.X + bob.X, tipAt.Y + bob.Y)
			pivot.Rotation = ROTATION[from]
			-- The halo rings the tap point on the target's edge, clear of its label.
			halo.Position = UDim2.fromOffset(tipAt.X - towards.X * haloSize * 0.15, tipAt.Y - towards.Y * haloSize * 0.15)
		end

		-- Instruction card: beside the glove, kept on screen.
		label.Text = hint.text
		local cardW = math.min(if hint.legend then (if compact then 330 else 460) else (if compact then 230 else 320), area.X - 16)
		local lines = if compact then 2 else 1
		local textH = (if compact then textSize else 20) * lines + 6
		local legendH = if hint.legend then keyIcon + 6 else 0
		local cardH = cardPad * 2 + textH + legendH
		label.Size = UDim2.fromOffset(cardW - cardPad * 2, textH)
		legend.Visible = hint.legend == true
		legend.Position = UDim2.fromOffset(cardPad, cardPad + textH)
		legend.Size = UDim2.fromOffset(cardW - cardPad * 2, legendH)
		local at: Vector2
		if pointing then
			at = if from == "left" then Vector2.new(tipAt.X - handSize - 8 - cardW, tipAt.Y - cardH / 2)
				elseif from == "right" then Vector2.new(tipAt.X + handSize + 8, tipAt.Y - cardH / 2)
				elseif from == "above" then Vector2.new(tipAt.X - cardW / 2, tipAt.Y - handSize - 8 - cardH)
				else Vector2.new(tipAt.X - cardW / 2, tipAt.Y + handSize + 8)
			-- No room on that side: put the card above the target instead.
			if at.X < 8 or at.X + cardW > area.X - 8 or at.Y + cardH > area.Y - 8 then
				local t = hint.target :: GuiObject
				local p = t.AbsolutePosition - origin
				at = Vector2.new(p.X + t.AbsoluteSize.X / 2 - cardW / 2, p.Y - cardH - 10)
			end
		else
			local a = hint.anchor
			local p = if a then a.AbsolutePosition - origin else Vector2.new(area.X / 2, area.Y / 2)
			local w = if a then a.AbsoluteSize.X else 0
			at = Vector2.new(p.X + w / 2 - cardW / 2, p.Y - cardH - 10)
		end
		at = Vector2.new(math.clamp(at.X, 8, area.X - cardW - 8), math.clamp(at.Y, 8, area.Y - cardH - 8))
		card.Position = UDim2.fromOffset(at.X, at.Y)
		card.Size = UDim2.fromOffset(cardW, cardH)
	end
	return self
end

return Tutorial

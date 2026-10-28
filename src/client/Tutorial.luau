--!strict
-- First-shift pointer: Astra's tutorial glove and target halo point at the next action on
-- the visible station, and her arrow at something to watch rather than tap (Bake's gauge).
-- The glove switches to her pressed glove at the bottom of each tap; both drawings share the
-- fingertip, so the contact point holds still. The instruction itself (and Bake's key) goes
-- in the reserved hint strip (Widgets.hintStrip), never over the work surface. Each
-- station's pointer stops once that action has been done. The art never takes input.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Ui = require(script.Parent.Ui)

local Tutorial = {}

-- The action that teaches each station. Make (station key Topping) teaches one lesson per part
-- of its dough step and one per sauce and cheese step (Make.hint reads them) and is learned as a
-- whole when a pizza is sent.
Tutorial.Lesson = {
	takeOrder = "Order",
	flour = "Make.flour",
	placeDough = "Make.dough",
	rollDough = "Make.roll",
	finishDough = "Make.next",
	pourSauce = "Make.sauce",
	finishSauce = "Make.sauceNext",
	finishCheese = "Make.cheeseNext",
	placeTopping = "Make.toppings",
	sendToOven = "Topping",
	takeOut = "Bake",
	cut = "Cut",
}

-- Glove and arrow rotation for each side they come from (both drawings point up).
local ROTATION = { below = 0, above = 180, left = 90, right = -90, aboveLeft = 135 }
-- Share of each tap's cycle spent at the bottom, where the pressed glove shows.
local CONTACT = 0.85

-- text and legend are shown by the hint strip; an empty text points without a line.
-- pointer "arrow" points at the target without a tap (no halo, no press).
-- clear: controls the glove must not cover (it moves to a clear side, or stays away).
export type Hint = { target: GuiObject?, text: string, from: string?, pointer: string?, legend: { { icon: string, text: string } }?, clear: { GuiObject }? }

-- `avoid` is a control strip (the tab bar) the glove must not cover.
function Tutorial.new(parent: GuiObject, compact: boolean, avoid: GuiObject?)
	Art.preload({ "ui_tutorial_hand", "ui_tutorial_hand_pressed", "ui_tutorial_arrow", "ui_tutorial_target_halo" })
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
	local pressed = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = hand.Position,
		Size = hand.Size,
		Visible = false,
		ZIndex = 31,
		Parent = pivot,
	})
	Art.apply(pressed, "ui_tutorial_hand_pressed")
	local arrowTip = Assets.Meta.tutorialArrow.tip
	local arrow = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-arrowTip.X * handSize, -arrowTip.Y * handSize),
		Size = UDim2.fromOffset(handSize, handSize),
		Visible = false,
		ZIndex = 31,
		Parent = pivot,
	})
	Art.apply(arrow, "ui_tutorial_arrow")

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
		local tapping = hint.pointer ~= "arrow"
		halo.Visible = pointing and tapping
		pivot.Visible = pointing
		arrow.Visible = not tapping
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
			-- A side glove that would land on the avoided strip (the tab bar beside a rail
			-- button on phones) comes from above instead.
			if avoid and (from == "left" or from == "right") then
				local ap, as = avoid.AbsolutePosition - origin, avoid.AbsoluteSize
				local gx0 = if from == "left" then p.X - handSize - 6 else p.X + s.X + 6
				local gy0, gy1 = p.Y + s.Y / 2 - handSize / 2, p.Y + s.Y / 2 + handSize / 2
				if gx0 < ap.X + as.X and gx0 + handSize > ap.X and gy1 > ap.Y and gy0 < ap.Y + as.Y then
					from = "above"
				end
			end
			local gap = 6
			-- Controls the glove must leave uncovered (hint.clear, e.g. Make's tool column and
			-- Undo; Astra r14: the glove covered the cheese bowl on phones). Keep the side when
			-- it is clear, else take the first clear side on screen; when no side is clear the
			-- glove stays away and the halo alone marks the target, with the text in the strip.
			local glove = true
			if hint.clear then
				local function rectFor(side: string): (Vector2, Vector2)
					local c = if side == "left" then Vector2.new(p.X - gap - handSize / 2, p.Y + s.Y / 2)
						elseif side == "right" then Vector2.new(p.X + s.X + gap + handSize / 2, p.Y + s.Y / 2)
						elseif side == "above" then Vector2.new(p.X + s.X / 2, p.Y - gap - handSize / 2)
						elseif side == "aboveLeft" then Vector2.new(p.X + gap - handSize * 0.35, p.Y + gap - handSize * 0.35)
						else Vector2.new(p.X + s.X / 2, p.Y + s.Y + gap + handSize / 2)
					local half = Vector2.new(handSize / 2, handSize / 2)
					return c - half, c + half
				end
				local function clearSide(side: string): boolean
					local a, b = rectFor(side)
					if a.X < 0 or a.Y < 0 or b.X > area.X or b.Y > area.Y then
						return false
					end
					for _, other in hint.clear :: { GuiObject } do
						if other.Visible and other ~= t then
							local op, os = other.AbsolutePosition - origin, other.AbsoluteSize
							-- 2 px of slack so a glove that only grazes an edge still counts as clear.
							if a.X < op.X + os.X - 2 and b.X > op.X + 2 and a.Y < op.Y + os.Y - 2 and b.Y > op.Y + 2 then
								return false
							end
						end
					end
					return true
				end
				if not clearSide(from) then
					glove = false
					for _, side in { "right", "left", "above", "below" } do
						if side ~= from and clearSide(side) then
							from, glove = side, true
							break
						end
					end
				end
			end
			tipAt = if from == "left" then Vector2.new(p.X - gap, p.Y + s.Y / 2)
				elseif from == "right" then Vector2.new(p.X + s.X + gap, p.Y + s.Y / 2)
				elseif from == "above" then Vector2.new(p.X + s.X / 2, p.Y - gap)
				elseif from == "aboveLeft" then Vector2.new(p.X + gap, p.Y + gap)
				else Vector2.new(p.X + s.X / 2, p.Y + s.Y + gap)
			-- A small tap motion toward the target.
			local towards = if from == "left" then Vector2.new(1, 0)
				elseif from == "right" then Vector2.new(-1, 0)
				elseif from == "above" then Vector2.new(0, 1)
				elseif from == "aboveLeft" then Vector2.new(0.7071, 0.7071)
				else Vector2.new(0, -1)
			local reach = math.sin(now * 5) * 0.5 + 0.5
			local bob = towards * reach * (if compact then 4 else 6) - towards * 6
			pivot.Position = UDim2.fromOffset(tipAt.X + bob.X, tipAt.Y + bob.Y)
			pivot.Visible = glove
			hand.Visible = tapping and reach < CONTACT
			pressed.Visible = tapping and reach >= CONTACT
			pivot.Rotation = ROTATION[from]
			-- The halo rings the tap point on the target's edge, clear of its label.
			halo.Position = UDim2.fromOffset(tipAt.X - towards.X * haloSize * 0.15, tipAt.Y - towards.Y * haloSize * 0.15)
		end
	end
	return self
end

return Tutorial

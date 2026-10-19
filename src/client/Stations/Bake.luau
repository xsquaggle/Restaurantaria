--!strict
-- Bake station: both ovens side by side as in 02-bake. Each oven is the generated oven
-- unit; the pizza sits on its rack (scaled flat for the oven's perspective), the gauge
-- needle sweeps from cold through the target zone toward burnt, and Take out sits on the
-- oven's lower panel. Numbers and the gauge reading are live text on the oven's blank plates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Bake = {}

local OVEN = Assets.Meta.oven
local NEEDLE = Assets.Meta.needle
-- The pizza on the rack: share of the window it spans, and how much flatter than round it
-- is drawn to sit in the oven's perspective.
local PIZZA_SPAN, PIZZA_FLATTEN = 0.82, 0.58
local NEEDLE_EASE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GLOW_PULSE = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Needle angle: -90 (cold, pointing left) up to 0 (straight up, the green target zone) at
-- the order's target, then on toward +90 (brown, burnt).
local function needleAngle(target: number, seconds: number): number
	if seconds <= target then
		return -90 + 90 * math.clamp(seconds / target, 0, 1)
	end
	return 90 * math.clamp((seconds - target) / Config.Oven.burntAfter, 0, 1)
end

local function rect(parent: GuiObject, r: any, props: { [string]: any }?): any
	local p = props or {}
	p.Position = UDim2.fromScale(r.x, r.y)
	p.Size = UDim2.fromScale(r.w, r.h)
	p.BackgroundTransparency = 1
	p.Parent = parent
	return p
end

function Bake.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Bake", BackgroundColor3 = Color3.fromRGB(92, 64, 52), Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
	local pad = if ctx.compact then 6 else 16
	local slotW = (area.X - pad * 3) / 2
	local ovenH = math.min(area.Y - pad * 2, slotW / OVEN.aspect)
	local ovenW = ovenH * OVEN.aspect
	local slots = {}

	for i = 1, Config.Oven.slots do
		local oven = Ui.new("ImageLabel", {
			Name = "Oven" .. i,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(pad + (i - 1) * (slotW + pad) + slotW / 2, area.Y / 2),
			Size = UDim2.fromOffset(ovenW, ovenH),
			Parent = frame,
		})
		Art.apply(oven, "prop_oven")

		local number = Ui.text({
			Text = tostring(i),
			FontFace = Theme.Font.display,
			TextSize = math.max(16, math.round(ovenW * OVEN.medallion.d * 0.7)),
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(OVEN.medallion.x, OVEN.medallion.y),
			Size = UDim2.fromOffset(ovenW * OVEN.medallion.d, ovenW * OVEN.medallion.d),
			ZIndex = 3,
			Parent = oven,
		})

		-- The needle turns about its hub, which sits on the dial centre.
		local dialR = ovenW * OVEN.dial.r
		local pivot = Ui.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(OVEN.dial.x, OVEN.dial.y),
			Size = UDim2.fromOffset(dialR * 2, dialR * 2),
			Rotation = -90,
			ZIndex = 3,
			Parent = oven,
		})
		local needleH = dialR * 0.95 / NEEDLE.hub
		local needle = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			AnchorPoint = Vector2.new(0.5, NEEDLE.hub),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(needleH * NEEDLE.aspect, needleH),
			ZIndex = 3,
			Parent = pivot,
		})
		Art.apply(needle, "prop_oven_needle")
		local reading = Ui.text(rect(oven, OVEN.plate, {
			Text = "",
			FontFace = Theme.Font.display,
			TextSize = math.max(14, math.round(ovenH * OVEN.plate.h * 0.75)),
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
		}))

		local window = Ui.new("Frame", rect(oven, OVEN.window, { Name = "Window", ZIndex = 2, ClipsDescendants = true }))
		local glow = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			ImageTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.6),
			Size = UDim2.fromScale(1.1, 1.3),
			ZIndex = 2,
			Parent = window,
		})
		Art.apply(glow, "fx_oven_glow")
		local view = Widgets.pizza()
		local aspect = view.frame:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.AspectRatio = 1 / PIZZA_FLATTEN
		view.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		view.frame.Position = UDim2.fromScale(0.5, 0.58)
		view.frame.Size = UDim2.fromScale(PIZZA_SPAN, 1)
		view.frame.ZIndex = 3
		view.frame.Parent = window
		-- Window glass over the pizza: reflections and a little steam.
		local glass = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			ImageTransparency = 0.35,
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = window,
		})
		Art.apply(glass, "fx_oven_glass")

		local slot: any = { pizza = nil }
		local button = Widgets.button("Take out", function()
			local pizza = slot.pizza
			if pizza and not ctx.pending[pizza.id] then
				ctx.pending[pizza.id] = true
				ctx.refresh()
				ctx.send("takeOut", { pizzaId = pizza.id }, function(ok)
					ctx.pending[pizza.id] = nil
					if ok then
						ctx.selectTicket(pizza.ticketId)
						ctx.nudge("Cut")
					end
					ctx.refresh()
				end)
			end
		end)
		-- On the oven's lower panel; phones keep the 48 px touch floor.
		local btnH = math.max(if ctx.compact then 48 else 56, ovenH * OVEN.panel.h * 0.72)
		button.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		button.frame.Position = UDim2.new(0.5, 0, OVEN.panel.y + OVEN.panel.h / 2, 0)
		button.frame.Size = UDim2.new(OVEN.panel.w * 0.86, 0, 0, btnH)
		button.frame.ZIndex = 4
		button.frame.Parent = oven

		slot.view, slot.button, slot.glow, slot.pivot, slot.reading, slot.number = view, button, glow, pivot, reading, number
		slot.angle = -90
		slots[i] = slot
	end

	local station = { frame = frame }

	function station.refresh(snap: any)
		for i, slot in slots do
			local pizzaId = snap.ovens[i]
			slot.pizza = nil
			if pizzaId then
				for _, p in snap.pizzas do
					if p.id == pizzaId then
						slot.pizza = p
					end
				end
			end
			local pizza = slot.pizza
			slot.view.frame.Visible = pizza ~= nil
			slot.button:setEnabled(pizza ~= nil and not ctx.pending[pizza.id])
			if not pizza then
				slot.reading.Text = "Empty"
				slot.angle = -90
				TweenService:Create(slot.pivot, NEEDLE_EASE, { Rotation = -90 }):Play()
				if slot.pulse then
					slot.pulse:Cancel()
					slot.pulse = nil
				end
				slot.glow.ImageTransparency = 1
			end
		end
	end

	function station.tick(now: number)
		for _, slot in slots do
			local pizza = slot.pizza
			if pizza then
				local customer = ctx.customer(ctx.snapshot, pizza.ticketId)
				local seconds = now - pizza.bakeStart
				local status = ctx.ovenStatus(customer.order.bake, seconds)
				slot.reading.Text = if status.ready and not status.burnt and status.text == "Ready!" then "Ready" else status.text
				slot.pivot.Rotation = needleAngle(Config.Oven.targets[customer.order.bake], seconds)
				slot.view:set(pizza, Widgets.doneness(seconds), status.burnt)
				slot.button:setHighlighted(status.ready)
				-- The glow warms up while baking and pulses once the pizza is ready.
				if status.ready and not slot.pulse then
					slot.glow.ImageTransparency = 0.15
					slot.pulse = TweenService:Create(slot.glow, GLOW_PULSE, { ImageTransparency = 0.5 })
					slot.pulse:Play()
				elseif not status.ready then
					slot.glow.ImageTransparency = 1 - 0.45 * math.clamp(status.progress, 0, 1)
				end
			end
		end
	end

	-- First-shift pointer: Take out on a ready oven. The bake key shows whenever a pizza is in.
	function station.hint(_snap: any, now: number): any
		local busy = false
		for _, slot in slots do
			local pizza = slot.pizza
			if pizza then
				busy = true
				local customer = ctx.customer(ctx.snapshot, pizza.ticketId)
				local status = ctx.ovenStatus(customer.order.bake, now - pizza.bakeStart)
				if status.ready and not status.burnt then
					return { target = slot.button.frame, text = "Ready! Take it out", from = "left", legend = true }
				end
			end
		end
		if busy then
			return { text = "Take it out when the needle reaches the ticket's bake", legend = true, anchor = slots[1].button.frame }
		end
		return nil
	end

	return station
end

return Bake

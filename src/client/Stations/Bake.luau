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
local Recipes = require(Shared.Recipes)
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

-- The gauge reads absolute bake time, the same scale on every ticket. Its art (v3) has five
-- bands: cold (neutral), Light (teal), Regular (green), Well done (amber) and Burnt (red).
-- Band edges in seconds come from the grading: each bake's band runs halfway to its
-- neighbours' targets, so its whole perfect window (target +/- perfectWindow) sits inside
-- it, and red starts exactly at Config.Oven.burntAt. GAUGE.edges are the measured angles of
-- the art's band dividers (degrees from straight up); the needle moves linearly within each
-- band.
local T = Config.Oven.targets
local GAUGE = {
	seconds = { 0, T.light - Config.Oven.perfectWindow - 1, (T.light + T.regular) / 2, (T.regular + T.well) / 2, Config.Oven.burntAt, Config.Oven.burntAt + 8 },
	edges = OVEN.gaugeEdges,
}
local function needleAngle(seconds: number): number
	local s, e = GAUGE.seconds, GAUGE.edges
	if seconds <= 0 then
		return e[1]
	end
	for i = 1, #s - 1 do
		if seconds <= s[i + 1] then
			return e[i] + (e[i + 1] - e[i]) * (seconds - s[i]) / (s[i + 1] - s[i])
		end
	end
	return e[#e]
end
Bake.needleAngle = needleAngle
Bake.gaugeSeconds = GAUGE.seconds

local function rect(parent: GuiObject, r: any, props: { [string]: any }?): any
	local p = props or {}
	p.Position = UDim2.fromScale(r.x, r.y)
	p.Size = UDim2.fromScale(r.w, r.h)
	p.BackgroundTransparency = 1
	p.Parent = parent
	return p
end

-- Full-screen art behind the station (Assets.Meta.backgrounds).
Bake.background = "bg_bake"

function Bake.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Bake", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = container })
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
			Rotation = GAUGE.edges[1],
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

		local slot: any = { pizza = nil, window = window }
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
								TweenService:Create(slot.pivot, NEEDLE_EASE, { Rotation = GAUGE.edges[1] }):Play()
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
				-- Phone plates are about 60 px wide: the word only; the HUD pill above adds the time.
				slot.reading.Text = if ctx.compact then status.word else status.text
				slot.pivot.Rotation = needleAngle(seconds)
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

	-- First-shift pointer. A ready oven gets the glove on its Take out; otherwise the strip
	-- teaches the gauge: take out when the needle reaches the ticket's bake. Phones key the
	-- bakes in the ovens (or the active ticket's) plus Burnt; wide screens key all of them.
	function station.hint(snap: any, now: number): any
		local wanted, seen = {}, {}
		for _, slot in slots do
			local pizza = slot.pizza
			if pizza then
				local customer = ctx.customer(ctx.snapshot, pizza.ticketId)
				local status = ctx.ovenStatus(customer.order.bake, now - pizza.bakeStart)
				if status.ready and not status.burnt then
					return { target = slot.button.frame, text = "Ready! Tap Take out", from = "left" }
				end
				if not seen[customer.order.bake] then
					seen[customer.order.bake] = true
					table.insert(wanted, customer.order.bake)
				end
			end
		end
		if #wanted == 0 then
			local id = ctx.activeTicket(snap)
			local customer = id and ctx.customer(snap, id)
			if customer then
				table.insert(wanted, customer.order.bake)
			end
		end
		local legend = {}
		for _, id in (if ctx.compact then wanted else Recipes.DonenessOrder) do
			local d = Recipes.Doneness[id]
			table.insert(legend, { icon = d.icon, text = d.short })
		end
		table.insert(legend, { icon = "ui_oven_badge_burnt", text = "Burnt" })
		return {
			text = if ctx.compact then "Take out at the ticket's bake:" else "Take it out when the needle reaches the ticket's bake:",
			legend = legend,
		}
	end

	return station
end

return Bake

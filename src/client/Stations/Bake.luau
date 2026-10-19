--!strict
-- Bake station: both oven slots, each with its live ring, the pizza browning and Take out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local Parent = script.Parent.Parent
local Theme = require(Parent.Theme)
local Ui = require(Parent.Ui)
local Widgets = require(Parent.Widgets)

local C = Theme.Colour
local Bake = {}


function Bake.new(ctx: any, container: Frame)
	local frame = Ui.new("Frame", { Name = "Bake", BackgroundColor3 = Color3.fromRGB(92, 64, 52), Size = UDim2.fromScale(1, 1), Parent = container })
	local area = ctx.stationSize :: Vector2
	local pad = if ctx.compact then 8 else 16
	local slotW = (area.X - pad * 3) / 2
	local slots = {}

	for i = 1, Config.Oven.slots do
		local panel = Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(60, 40, 34),
			Position = UDim2.fromOffset(pad + (i - 1) * (slotW + pad), pad),
			Size = UDim2.fromOffset(slotW, area.Y - pad * 2),
			Parent = frame,
		}, { Ui.corner(20), Ui.stroke(C.ink, 3) })
		local title = Ui.text({
			Text = "Oven " .. i,
			FontFace = Theme.Font.display,
			TextColor3 = C.paper,
			TextSize = if ctx.compact then 18 else 26,
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, if ctx.compact then 22 else 32),
			Parent = panel,
		})
		local info = Ui.text({
			Text = "Empty",
			FontFace = Theme.Font.bodySemi,
			TextColor3 = C.paper,
			TextSize = if ctx.compact then 16 else 20,
			Position = UDim2.fromOffset(12, title.Size.Y.Offset + 8),
			Size = UDim2.new(1, -24, 0, if ctx.compact then 20 else 26),
			Parent = panel,
		})
		local btnH = if ctx.compact then 48 else 64
		local bodyTop = title.Size.Y.Offset + info.Size.Y.Offset + 16
		local bodyH = area.Y - pad * 2 - bodyTop - btnH - 20
		local mouth = Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(34, 22, 18),
			Position = UDim2.fromOffset(12, bodyTop),
			Size = UDim2.new(1, -24, 0, bodyH),
			Parent = panel,
		}, { Ui.corner(14) })
		local glow = Ui.new("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(230, 120, 40), Color3.fromRGB(60, 24, 12)),
			Rotation = 90,
			Parent = mouth,
		})
		glow.Enabled = false
		local view = Widgets.pizza()
		view.frame.Size = UDim2.fromScale(0.9, 0.9)
		view.frame.AnchorPoint = Vector2.new(0, 0.5)
		view.frame.Position = UDim2.new(0, 10, 0.5, 0)
		view.frame.Parent = mouth
		local ringSize = math.min(bodyH * 0.8, (slotW - 24) * 0.42)
		local ring = Widgets.ring(ringSize)
		ring.frame.AnchorPoint = Vector2.new(1, 0.5)
		ring.frame.Position = UDim2.new(1, -10, 0.5, 0)
		ring.frame.Parent = mouth
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
		button.frame.Size = UDim2.new(1, -24, 0, btnH)
		button.frame.AnchorPoint = Vector2.new(0.5, 1)
		button.frame.Position = UDim2.new(0.5, 0, 1, -10)
		button.frame.Parent = panel
		slot.panel, slot.info, slot.view, slot.ring, slot.button, slot.glow = panel, info, view, ring, button, glow
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
			slot.glow.Enabled = pizza ~= nil
			slot.button:setEnabled(pizza ~= nil and not ctx.pending[pizza.id])
			if pizza then
				local customer = ctx.customer(snap, pizza.ticketId)
				slot.info.Text = string.format("%s · %s · %s", Recipes.Cast[customer.cast].name, Recipes.ById[customer.order.recipe].name, Recipes.Doneness[customer.order.bake].short)
			else
				slot.info.Text = "Empty"
				slot.ring:set(0, C.oven, "", "")
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
				slot.ring:set(status.progress, status.colour, "", status.text)
				slot.view:set(pizza, Widgets.doneness(seconds))
				slot.button:setHighlighted(status.ready)
			end
		end
	end

	return station
end

return Bake

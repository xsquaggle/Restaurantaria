--!strict
-- Illustrated pizza: the generated base with one topping sprite per piece. Pieces keep their
-- identity across refreshes, so only new pieces animate in and only removed ones animate
-- out, and the pizza gives a small wobble when something lands on it. Everything here is
-- cosmetic: it never delays or blocks input.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Recipes = require(Shared.Recipes)
local Ui = require(script.Parent.Ui)

local PizzaArt = {}

export type View = {
	frame: Frame,
	pizzaId: number?,
	set: (View, any?, boolean) -> (),
	wobble: (View) -> (),
}

local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- A piece's drawing (one of three per ingredient) and turn, derived from where it sits so it
-- looks the same on every refresh and on every station.
function PizzaArt.look(pizzaId: number, piece: any): (string, number)
	local h = hash(string.format("%d:%s:%.3f:%.3f", pizzaId, piece.ingredient, piece.x, piece.y))
	local info = Recipes.Ingredients[piece.ingredient]
	return string.format("topping_%s_%d", info.art, h % 3 + 1), (h // 3) % 360
end

-- A loose piece (held in the hand, or a hover preview), sized in pixels.
function PizzaArt.loosePiece(ingredient: string, variant: number, rotation: number, sizePx: number): ImageLabel
	local info = Recipes.Ingredients[ingredient]
	local label = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
		Rotation = rotation,
		ZIndex = 20,
	})
	Art.apply(label, string.format("topping_%s_%d", info.art, variant))
	return label
end

local DROP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.08, Enum.EasingStyle.Linear)
local LIFT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SWELL = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RIPPLE = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

function PizzaArt.new(): View
	local frame = Ui.new("Frame", { Name = "Pizza", BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 300) })
	local wobbleScale = Ui.new("UIScale", { Scale = 1, Parent = frame })
	local base = Ui.new("ImageLabel", { Name = "Base", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame })
	Art.apply(base, "pizza_raw")
	local layer = Ui.new("Frame", { Name = "Toppings", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = frame })

	local shown: { [string]: ImageLabel } = {}
	local leaving: { [string]: boolean } = {}
	local latest: { [string]: any } = {}
	local wobbleTween: Tween? = nil

	local view: View
	view = {
		frame = frame,
		pizzaId = nil,
		wobble = function(_v: View)
			if wobbleTween then
				wobbleTween:Cancel()
			end
			local up = TweenService:Create(wobbleScale, SWELL, { Scale = 1.018 })
			up.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					wobbleTween = TweenService:Create(wobbleScale, RIPPLE, { Scale = 1 })
					wobbleTween:Play()
				end
			end)
			wobbleTween = up
			up:Play()
		end,
		set = function(v: View, pizza: any?, animate: boolean)
			local id = if pizza then pizza.id else nil
			if id ~= v.pizzaId then
				v.pizzaId = id
				for _, label in shown do
					label:Destroy()
				end
				table.clear(shown)
				table.clear(leaving)
				animate = false
			end
			if not pizza then
				return
			end
			-- Same ingredient at the same spot twice is two pieces: number repeats.
			local wanted: { [string]: any } = {}
			local seen: { [string]: number } = {}
			for _, piece in pizza.toppings do
				local base_ = string.format("%s:%.3f:%.3f", piece.ingredient, piece.x, piece.y)
				seen[base_] = (seen[base_] or 0) + 1
				wanted[base_ .. "#" .. seen[base_]] = piece
			end
			latest = wanted
			for key, label in shown do
				if not wanted[key] and not leaving[key] then
					-- A placed piece briefly drops out between the local copy being cleared and
					-- the server's copy arriving; only animate it away if it stays gone.
					leaving[key] = true
					task.delay(0.12, function()
						leaving[key] = nil
						if latest[key] or shown[key] ~= label then
							return
						end
						shown[key] = nil
						local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
						TweenService:Create(scale, LIFT, { Scale = 0.3 }):Play()
						local out = TweenService:Create(label, LIFT, { ImageTransparency = 1 })
						out.Completed:Connect(function()
							label:Destroy()
						end)
						out:Play()
					end)
				end
			end
			local landed = false
			for key, piece in wanted do
				if not shown[key] then
					local art, rotation = PizzaArt.look(pizza.id, piece)
					local info = Recipes.Ingredients[piece.ingredient]
					local label = Ui.new("ImageLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5 + piece.x * 0.5, 0.5 + piece.y * 0.5),
						Size = UDim2.fromScale(info.size, info.size),
						Rotation = rotation,
						ZIndex = 2,
						Parent = layer,
					})
					local scale = Ui.new("UIScale", { Scale = 1, Parent = label })
					Art.apply(label, art)
					shown[key] = label
					if animate then
						-- Dropped from a little above: lands big, overshoots, settles with a twist.
						scale.Scale = 1.45
						label.Rotation = rotation - 25
						label.ImageTransparency = 0.5
						TweenService:Create(scale, DROP, { Scale = 1 }):Play()
						TweenService:Create(label, SETTLE, { Rotation = rotation }):Play()
						TweenService:Create(label, FADE_IN, { ImageTransparency = 0 }):Play()
						landed = true
					end
				end
			end
			if landed then
				task.delay(0.1, function()
					v:wobble()
				end)
			end
		end,
	}
	return view
end

return PizzaArt

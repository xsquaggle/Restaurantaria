--!strict
-- Illustrated pizza: the generated base with one topping sprite per piece. Pieces keep their
-- identity across refreshes, so only new pieces animate in and only removed ones animate
-- out, and the pizza gives a small wobble when something lands on it. Each piece casts a
-- contact shadow: a dark-tinted, slightly offset copy of its own sprite (Astra, G3).
-- Everything here is cosmetic: it never delays or blocks input.

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

-- A piece's drawing and turn. The nth piece of an ingredient on a pizza always gets the same
-- one, so a piece looks the same on every refresh and every station, and the piece in the
-- hand already shows the drawing it will land with. Ingredients with visual variants (the
-- red and green bell pepper) pick among those; they share everything else.
function PizzaArt.look(pizzaId: number, ingredient: string, n: number): (string, number)
	-- A seeded Random spreads neighbouring counts apart (the raw hash moves in even steps).
	local rng = Random.new(hash(string.format("%d:%s:%d", pizzaId, ingredient, n)))
	local info = Recipes.Ingredients[ingredient]
	local art = if info.variants then info.variants[rng:NextInteger(1, #info.variants)] else string.format("topping_%s_%d", info.art, rng:NextInteger(1, 3))
	return art, rng:NextInteger(0, 359)
end

-- The look the next piece of this ingredient will get on this pizza.
function PizzaArt.nextLook(pizza: any?, ingredient: string): (string, number)
	local n = 1
	if pizza then
		for _, piece in pizza.toppings do
			if piece.ingredient == ingredient then
				n += 1
			end
		end
	end
	return PizzaArt.look(if pizza then pizza.id else 0, ingredient, n)
end

local SHADOW_TINT = Color3.fromRGB(60, 30, 18)
-- Shadow offset (fraction of the piece size) and transparency: resting on the dough, and
-- lifted (in the hand or dropping in), where it falls further away and fainter.
local REST = { offset = Vector2.new(0.04, 0.07), transparency = 0.6 }
local LIFTED = { offset = Vector2.new(0.14, 0.24), transparency = 0.8 }

-- Shadow and sprite inside one root. The root is never rotated, so the shadow always falls
-- the same way whatever the piece's turn.
local function build(root: GuiObject, art: string, rotation: number, shadow: typeof(REST)?): (ImageLabel, ImageLabel?)
	local shade: ImageLabel? = nil
	if shadow then
		shade = Ui.new("ImageLabel", {
			Name = "Shadow",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + shadow.offset.X, 0.5 + shadow.offset.Y),
			Size = UDim2.fromScale(1, 1),
			Rotation = rotation,
			ImageColor3 = SHADOW_TINT,
			ImageTransparency = shadow.transparency,
			ZIndex = 1,
			Parent = root,
		})
		local s = shade :: ImageLabel
		s:SetAttribute("Rest", shadow.transparency)
		Art.apply(s, art)
	end
	local sprite = Ui.new("ImageLabel", {
		Name = "Sprite",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Rotation = rotation,
		ZIndex = 2,
		Parent = root,
	})
	sprite:SetAttribute("Rest", 0)
	sprite:SetAttribute("Look", art)
	Art.apply(sprite, art)
	return sprite, shade
end

-- A loose piece (held in the hand, or a hover preview), sized in pixels. Lifted pieces carry
-- a shadow that falls further away; a preview has none.
function PizzaArt.loosePiece(art: string, rotation: number, sizePx: number, lifted: boolean): Frame
	local root = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
		ZIndex = 20,
	})
	build(root, art, rotation, if lifted then LIFTED else nil)
	return root
end

-- Point a loose piece at another drawing without rebuilding it.
function PizzaArt.setLook(root: GuiObject, art: string, rotation: number)
	for _, child in root:GetChildren() do
		if child:IsA("ImageLabel") then
			Art.apply(child, art)
			child.Rotation = rotation
		end
	end
end

-- Fade a piece (sprite and shadow together): amount 0 is as built, 1 is gone. Without a
-- TweenInfo the change is immediate.
function PizzaArt.fade(root: GuiObject, info: TweenInfo?, amount: number): Tween?
	local last: Tween? = nil
	for _, child in root:GetChildren() do
		if child:IsA("ImageLabel") then
			local rest = (child:GetAttribute("Rest") :: number?) or 0
			local target = 1 - (1 - rest) * (1 - amount)
			if info then
				local t = TweenService:Create(child, info, { ImageTransparency = target })
				t:Play()
				last = t
			else
				child.ImageTransparency = target
			end
		end
	end
	return last
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

	local shown: { [string]: Frame } = {}
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
				for _, root in shown do
					root:Destroy()
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
			local nth: { [string]: number } = {}
			local order: { [any]: number } = {}
			for _, piece in pizza.toppings do
				local base_ = string.format("%s:%.3f:%.3f", piece.ingredient, piece.x, piece.y)
				seen[base_] = (seen[base_] or 0) + 1
				wanted[base_ .. "#" .. seen[base_]] = piece
				nth[piece.ingredient] = (nth[piece.ingredient] or 0) + 1
				order[piece] = nth[piece.ingredient]
			end
			latest = wanted
			for key, root in shown do
				if not wanted[key] and not leaving[key] then
					-- A placed piece briefly drops out between the local copy being cleared and
					-- the server's copy arriving; only animate it away if it stays gone.
					leaving[key] = true
					task.delay(0.12, function()
						leaving[key] = nil
						if latest[key] or shown[key] ~= root then
							return
						end
						shown[key] = nil
						local scale = root:FindFirstChildOfClass("UIScale") :: UIScale
						TweenService:Create(scale, LIFT, { Scale = 0.3 }):Play()
						local out = PizzaArt.fade(root, LIFT, 1)
						if out then
							out.Completed:Connect(function()
								root:Destroy()
							end)
						else
							root:Destroy()
						end
					end)
				end
			end
			local landed = false
			for key, piece in wanted do
				if not shown[key] then
					local art, rotation = PizzaArt.look(pizza.id, piece.ingredient, order[piece])
					local info = Recipes.Ingredients[piece.ingredient]
					local root = Ui.new("Frame", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5 + piece.x * 0.5, 0.5 + piece.y * 0.5),
						Size = UDim2.fromScale(info.size, info.size),
						ZIndex = 2,
						Parent = layer,
					})
					-- Pieces stay round when the pizza is drawn flattened (in the oven).
					Ui.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = root })
					local scale = Ui.new("UIScale", { Scale = 1, Parent = root })
					local sprite, shade = build(root, art, rotation, REST)
					shown[key] = root
					if animate then
						-- Dropped from a little above: lands big, overshoots, settles with a twist,
						-- while its shadow closes in under it.
						scale.Scale = 1.45
						sprite.Rotation = rotation - 25
						sprite.ImageTransparency = 0.5
						TweenService:Create(scale, DROP, { Scale = 1 }):Play()
						TweenService:Create(sprite, SETTLE, { Rotation = rotation }):Play()
						TweenService:Create(sprite, FADE_IN, { ImageTransparency = 0 }):Play()
						if shade then
							shade.Rotation = rotation - 25
							shade.Position = UDim2.fromScale(0.5 + LIFTED.offset.X, 0.5 + LIFTED.offset.Y)
							shade.ImageTransparency = LIFTED.transparency
							TweenService:Create(shade, SETTLE, {
								Rotation = rotation,
								Position = UDim2.fromScale(0.5 + REST.offset.X, 0.5 + REST.offset.Y),
								ImageTransparency = REST.transparency,
							}):Play()
						end
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

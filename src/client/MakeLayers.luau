--!strict
-- Draws the player's own sauce and cheese on the dough they rolled, from the same records the
-- server grades (MakeSauce's thickness field, MakeCheese's pinches), with Astra's response-13
-- kit: the soft circular sauce stamp (P9), the dollop (P7) and the raw cheese pinch (P11).
-- Used by the Make station (sauce and cheese steps) and the Topping view (which also has it draw
-- the rolled dough, P4, as Make draws it), so no step shows a preassembled pizza. Cosmetic only:
-- it never takes input.
--
-- Sauce: one soft stamp on every second grid point of the field (0.1 dough-local apart), its
-- opacity from the field's thickness there, so a bare or thin patch stays visibly bare or thin
-- and overlapping stamps never add coverage the grade does not give. A thick layer (past an even
-- layer of the target pours) is drawn deeper red. A pour still mostly in place shows the dollop.
-- Cheese: one pinch sprite per pinch, on the kit's shared canvas (footprint radius 0.17 dough-
-- local = 0.95 of the canvas), each with a fixed turn.
-- Positions are dough-local and go through the one view map (PrepGeometry.screenOf), so sauce and
-- cheese stretch with the oval; every sprite is fitted to the local stretch (spriteFit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeSauce = require(Shared.MakeSauce)
local PrepFood = require(Shared.PrepFood)
local Ui = require(script.Parent.Ui)

local MakeLayers = {}

-- Registration (asset-manifest.json, response 13).
local SAUCE_SHARE = 0.87890625 -- food_sauce_raw: full soft footprint / canvas
local DOLLOP_SHARE = 0.87890625 -- food_sauce_dollop alpha width / canvas
local CHEESE_SHARE = 0.95 -- food_cheese_raw: shared footprint canvas share
-- Proposals (looks, not grading): the drawn stamp's diameter (dough-local), the stamps that
-- overlap a point of an even layer (to split the wanted opacity between them), the opacity of a
-- layer at full credit, the deep-red tint of a thick layer, the dollop's size.
local STAMP = 0.28
local OVERLAP = 4
local FULL_OPACITY = 0.92
local DEEP = Color3.fromRGB(190, 150, 150)
local DOLLOP = 0.5 -- dough-local diameter of a fresh pour's dollop
local DOUGH_BODY = { alphaX = 0.94921875, alphaY = 0.94921875, centreX = 0, centreY = 0 }
local ROLLS = { "food_dough_roll_01", "food_dough_roll_02", "food_dough_roll_03", "food_dough_roll_04", "food_dough_roll_05", "food_dough_roll_06" }

export type Layers = {
	frame: Frame,
	place: (Layers, number, number, number, any) -> (),
	dough: (Layers, boolean) -> (),
	sauce: (Layers, { number }?, { any }?) -> (),
	cheese: (Layers, { any }?) -> (),
}

local function key(S: any, F: number): string
	return string.format("%.5f,%.5f,%.5f,%.5f,%.3f", S.a, S.b, S.c, S.d, F)
end

-- Composite opacity wanted at thickness t: full credit (half an even layer) shows nearly opaque;
-- thinner shows thinner.
local function opacity(t: number): number
	if t <= 0 then
		return 0
	end
	return FULL_OPACITY * math.min(1, t / MakeSauce.HALF) ^ 0.75
end

function MakeLayers.new(parent: GuiObject, zIndex: number): Layers
	local frame = Ui.new("Frame", { Name = "Food", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Parent = parent })
	local doughLayer = Ui.new("Frame", { Name = "Dough", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Visible = false, Parent = frame })
	local keys: { ImageLabel } = {}
	for i, name in ROLLS do
		local img = Ui.new("ImageLabel", { Name = "Roll" .. i, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex, Visible = false, Parent = doughLayer })
		Art.apply(img, name)
		keys[i] = img
	end
	local sauceLayer = Ui.new("Frame", { Name = "Sauce", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Parent = frame })
	local dollopLayer = Ui.new("Frame", { Name = "Dollops", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 1, Parent = frame })
	local cheeseLayer = Ui.new("Frame", { Name = "Cheese", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 2, Parent = frame })

	local geometry = ""
	local cx, cy, F = 0, 0, 1
	local S: any = G.shape(0.95, 0.95, 0)
	-- Sauce stamps: one per drawn grid point, with the fine cells it averages.
	type Stamp = { image: ImageLabel, cells: { number }, shown: number, tint: number }
	local stamps: { Stamp } = {}
	local dollops: { ImageLabel } = {}
	local pinches: { ImageLabel } = {}

	local function screen(q: any): Vector2
		local o = G.screenOf(S, F, 1, q)
		return Vector2.new(cx + o.x, cy + o.y)
	end
	local function fit(img: ImageLabel, diameter: number, share: number, turn: number)
		local canvas = diameter / share
		local f = G.spriteFit(G.localStretch(S, F, 1), canvas, canvas, math.rad(turn))
		img.Size = UDim2.fromOffset(f.width, f.height)
		img.Rotation = f.rotation
	end

	local function build()
		Ui.clear(sauceLayer)
		table.clear(stamps)
		local N = MakeSauce.GRID
		for gx = -N, N, 2 do
			for gy = -N, N, 2 do
				local centre = MakeSauce.cellAt(gx, gy)
				if centre then
					local cells = {}
					for dx = -1, 1 do
						for dy = -1, 1 do
							local i = MakeSauce.cellAt(gx + dx, gy + dy)
							if i then
								table.insert(cells, i)
							end
						end
					end
					local s = screen({ x = MakeSauce.xs[centre], y = MakeSauce.ys[centre] })
					local img = Ui.new("ImageLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(s.X, s.Y),
						ImageTransparency = 1,
						Visible = false,
						ZIndex = zIndex,
						Parent = sauceLayer,
					})
					fit(img, STAMP, SAUCE_SHARE, 0)
					Art.apply(img, "food_sauce_raw")
					table.insert(stamps, { image = img, cells = cells, shown = 0, tint = 0 })
				end
			end
		end
		for _, d in dollops do
			d:Destroy()
		end
		table.clear(dollops)
		for _, p in pinches do
			p:Destroy()
		end
		table.clear(pinches)
	end

	local layers = {} :: Layers
	layers.frame = frame

	-- Where the dough is drawn: centre (px in the parent), pizza frame F (px), dough shape S.
	function layers.place(_self: Layers, x: number, y: number, frameSize: number, shape: any)
		local k = key(shape, frameSize) .. string.format("|%.2f,%.2f", x, y)
		if k == geometry then
			return
		end
		geometry = k
		cx, cy, F, S = x, y, frameSize, shape
		build()
	end

	-- The rolled dough under the food (the Topping view; Make draws its own, with the ball): the
	-- two appearance keys either side of the mean radius, the upper one crossfaded in, fitted to
	-- the scored oval.
	function layers.dough(_self: Layers, on: boolean)
		doughLayer.Visible = on
		if not on then
			return
		end
		local pl = G.bodyPlacement(G.ellipseOf(G.viewMatrix(S, F)), DOUGH_BODY)
		local i1, i2, w = G.stateBlend(G.meanRadius(S))
		for i, k in keys do
			local shown = i == i1 or (i == i2 and w > 0)
			k.Visible = shown
			if shown then
				k.Size = UDim2.fromOffset(pl.width, pl.height)
				k.Rotation = pl.rotation
				k.Position = UDim2.fromOffset(cx + pl.offset.x, cy + pl.offset.y)
				local upper = i == i2 and i2 ~= i1
				k.ZIndex = if upper then zIndex + 1 else zIndex
				k.ImageTransparency = if upper then 1 - w else 0
			end
		end
	end

	-- The sauce field (nil: none) and the pours that made it (for the dollops).
	function layers.sauce(_self: Layers, field: { number }?, actions: { any }?)
		for _, st in stamps do
			local t = 0
			if field then
				for _, i in st.cells do
					t += field[i]
				end
				t /= #st.cells
			end
			-- Split the wanted opacity between the stamps that overlap one point.
			local a = 1 - (1 - opacity(t)) ^ (1 / OVERLAP)
			local shown = math.floor(a * 200 + 0.5) / 200
			local tint = math.floor(math.clamp((t / MakeSauce.EVEN - 1.3) / 1.7, 0, 1) * 20 + 0.5) / 20
			if shown ~= st.shown then
				st.shown = shown
				st.image.Visible = shown > 0
				st.image.ImageTransparency = 1 - shown
			end
			if tint ~= st.tint then
				st.tint = tint
				st.image.ImageColor3 = Color3.new(1, 1, 1):Lerp(DEEP, tint)
			end
		end
		-- Dollops: a pour still mostly where it landed (the mean thickness around it against one
		-- fresh ladle's) shows the P7 deposit, fading as it is spread away.
		local fresh = 1 / (math.pi * Config.Sauce.pourRadius ^ 2)
		local n = 0
		for _, a in actions or {} do
			if a.kind == "pour" and field then
				local cells = MakeSauce.cellsNear(a.x, a.y, Config.Sauce.pourRadius * 0.5)
				local t = 0
				for _, i in cells do
					t += field[i]
				end
				t = if #cells > 0 then t / #cells else 0
				local strength = math.clamp((t / fresh - 0.55) / 0.45, 0, 1)
				n += 1
				local img = dollops[n]
				if not img then
					img = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex + 1, Parent = dollopLayer })
					Art.apply(img, "food_sauce_dollop")
					dollops[n] = img
				end
				local s = screen(a)
				img.Position = UDim2.fromOffset(s.X, s.Y)
				fit(img, DOLLOP, DOLLOP_SHARE, (n * 97) % 360)
				img.ImageTransparency = 1 - strength
				img.Visible = strength > 0
			end
		end
		for i = n + 1, #dollops do
			dollops[i].Visible = false
		end
	end

	-- The cheese pinches (dough-local), in placement order.
	function layers.cheese(_self: Layers, list: { any }?)
		local n = 0
		for _, p in list or {} do
			n += 1
			local img = pinches[n]
			if not img then
				img = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex + 2, Parent = cheeseLayer })
				Art.apply(img, "food_cheese_raw")
				pinches[n] = img
			end
			local s = screen(p)
			img.Position = UDim2.fromOffset(s.X, s.Y)
			fit(img, 2 * PrepFood.PINCH_RADIUS, CHEESE_SHARE, (n * 137.5) % 360)
			img.Visible = true
		end
		for i = n + 1, #pinches do
			pinches[i].Visible = false
		end
	end

	return layers
end

return MakeLayers

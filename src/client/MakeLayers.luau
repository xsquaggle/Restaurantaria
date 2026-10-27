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
-- and overlapping stamps never add coverage the grade does not give. No stamp reaches past the
-- sauce the grade sees: each shrinks to stop short of the nearest unsauced cell, so the drawn
-- sauce ends where the scored sauce ends (the kit's rule) instead of haloing past it. A thick layer (past an even
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
-- overlap a point of an even layer (to split the wanted opacity between them), each stamp's fixed
-- jitter, the opacity of a layer at full credit, the deep-red tint of a thick layer, the dollop's
-- size.
local STAMP = 0.34
local OVERLAP = 6
local JITTER = 0.06 -- dough-local spread of each stamp's fixed offset
local FULL_OPACITY = 0.92
local BARE = 0.03 -- a cell under this share of full-credit thickness counts as unsauced for the stamp edge
local SIZE_STEP = 0.02 -- stamp diameters are rounded to this (fewer resizes)
local DEEP = Color3.fromRGB(190, 150, 150)
local DOLLOP = 0.5 -- dough-local diameter of a fresh pour's dollop
local DOUGH_BODY = { alphaX = 0.94921875, alphaY = 0.94921875, centreX = 0, centreY = 0 }
-- Baked states (Bake, Cut and the result card): seconds in the oven at which each drawn state is
-- fully shown, the same timeline as the old pre-sauced bake art (Widgets) so the look follows
-- the real bake progress, never the ticket. Crust: the rolled raw dough (P4 keys), then the P13
-- bare crusts (same 0.949 body share, fitted to the scored oval, so the rim thins with it).
-- Cheese: P11 raw, then P14 melted, golden, burnt on the one shared canvas. Sauce: P9 raw, then
-- P15 cooked at one moment (SAUCE_COOKED_AT; no crossfade, which would double every stamp), and
-- the burnt tint past the regular bake. Timings are proposals.
local CRUSTS = {
	{ art = nil, at = 0 },
	{ art = "food_crust_light", at = Config.Oven.targets.light },
	{ art = "food_crust_regular", at = Config.Oven.targets.regular },
	{ art = "food_crust_well", at = Config.Oven.targets.well },
	{ art = "food_crust_burnt", at = Config.Oven.burntAt },
}
local CHEESES = {
	{ art = "food_cheese_raw", at = 0 },
	{ art = "food_cheese_melted", at = Config.Oven.targets.light },
	{ art = "food_cheese_golden", at = Config.Oven.targets.well },
	{ art = "food_cheese_burnt", at = Config.Oven.burntAt },
}
-- Halfway through the toppings' raw-to-baked crossfade (Widgets: from half the light bake to the
-- regular bake).
local SAUCE_COOKED_AT = (Config.Oven.targets.light * 0.5 + Config.Oven.targets.regular) / 2
local SCORCH = Color3.fromRGB(150, 105, 85) -- sauce at the burnt time (proposal)

-- The two neighbouring states and how far the bake is from the first to the second.
local function blend(states: { any }, seconds: number): (number, number)
	for i = 1, #states - 1 do
		if seconds < states[i + 1].at then
			return i, math.clamp((seconds - states[i].at) / (states[i + 1].at - states[i].at), 0, 1)
		end
	end
	return #states - 1, 1
end
local ROLLS = { "food_dough_roll_01", "food_dough_roll_02", "food_dough_roll_03", "food_dough_roll_04", "food_dough_roll_05", "food_dough_roll_06" }

export type Layers = {
	frame: Frame,
	place: (Layers, number, number, number, any, number?) -> (),
	dough: (Layers, boolean, number?) -> (),
	bake: (Layers, number?) -> (),
	sauce: (Layers, { number }?, { any }?) -> (),
	cheese: (Layers, { any }?) -> (),
}

local function key(S: any, F: number): string
	return string.format("%.5f,%.5f,%.5f,%.5f,%.3f", S.a, S.b, S.c, S.d, F)
end

-- Composite opacity wanted at thickness t: full credit (half an even layer) shows nearly opaque;
-- thinner shows proportionally thinner (linear, so a patch graded thin never looks full).
local function opacity(t: number): number
	if t <= 0 then
		return 0
	end
	return FULL_OPACITY * math.min(1, t / MakeSauce.HALF)
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
	-- The baked crusts: the lower state fully shown, the upper fading in over it.
	local crustLower = Ui.new("ImageLabel", { Name = "CrustLower", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex, Visible = false, Parent = doughLayer })
	local crustUpper = Ui.new("ImageLabel", { Name = "CrustUpper", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex + 1, Visible = false, Parent = doughLayer })
	local sauceLayer = Ui.new("Frame", { Name = "Sauce", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Parent = frame })
	local dollopLayer = Ui.new("Frame", { Name = "Dollops", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 1, Parent = frame })
	local cheeseLayer = Ui.new("Frame", { Name = "Cheese", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 2, Parent = frame })

	local geometry = ""
	local cx, cy, F, flat = 0, 0, 1, 1
	-- Seconds in the oven (nil: not baked, the raw art).
	local baked: number? = nil
	local sauceArt = "food_sauce_raw"
	local S: any = G.shape(0.95, 0.95, 0)
	-- Sauce stamps: one per drawn grid point, with the fine cells it averages.
	-- near: the cells within the stamp's reach, nearest first, with their distances (for the edge).
	-- reach: the distance from the stamp's centre to the field's outer edge (extent plus half a
	-- cell), so no stamp is drawn past the grid the grade sees.
	type Stamp = { image: ImageLabel, cells: { number }, near: { { number } }, reach: number, turn: number, size: number, shown: number, tint: number, color: Color3? }
	local stamps: { Stamp } = {}
	local dollops: { ImageLabel } = {}
	-- Each pinch: its lower and upper cooking state (the upper fades in over it).
	local pinches: { { ImageLabel } } = {}
	-- The field last drawn: a replay memo's field is never changed, so the same table again
	-- (a frame with no new action) needs no redraw.
	local drawn: { number }? = nil
	-- The cheese last drawn (pinches, place and cooking state).
	local cheeseKey = ""

	local function screen(q: any): Vector2
		local o = G.screenOf(S, F, flat, q)
		return Vector2.new(cx + o.x, cy + o.y)
	end
	local function fit(img: ImageLabel, diameter: number, share: number, turn: number)
		local canvas = diameter / share
		local f = G.spriteFit(G.localStretch(S, F, flat), canvas, canvas, math.rad(turn))
		img.Size = UDim2.fromOffset(f.width, f.height)
		img.Rotation = f.rotation
	end

	local function build()
		drawn = nil
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
					-- A fixed small offset and turn per stamp, so the regular grid does not show
					-- through as a lattice.
					local n = #stamps + 1
					local jx = (((n * 0.6180339887) % 1) - 0.5) * JITTER
					local jy = (((n * 0.7548776662) % 1) - 0.5) * JITTER
					local px, py = MakeSauce.xs[centre] + jx, MakeSauce.ys[centre] + jy
					local near = {}
					for _, i in MakeSauce.cellsNear(px, py, STAMP / 2 + MakeSauce.CELL) do
						table.insert(near, { i, math.sqrt((MakeSauce.xs[i] - px) ^ 2 + (MakeSauce.ys[i] - py) ^ 2) })
					end
					table.sort(near, function(a, b)
						return a[2] < b[2]
					end)
					local s = screen({ x = px, y = py })
					local img = Ui.new("ImageLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(s.X, s.Y),
						ImageTransparency = 1,
						Visible = false,
						ZIndex = zIndex,
						Parent = sauceLayer,
					})
					local turn = (n * 137.5) % 360
					fit(img, STAMP, SAUCE_SHARE, turn)
					Art.apply(img, sauceArt)
					local reach = Config.Sauce.extent + MakeSauce.CELL / 2 - math.sqrt(px * px + py * py)
					table.insert(stamps, { image = img, cells = cells, near = near, reach = reach, turn = turn, size = STAMP, shown = 0, tint = 0 })
				end
			end
		end
		for _, d in dollops do
			d:Destroy()
		end
		table.clear(dollops)
		for _, p in pinches do
			p[1]:Destroy()
			p[2]:Destroy()
		end
		table.clear(pinches)
		cheeseKey = ""
	end

	local layers = {} :: Layers
	layers.frame = frame

	-- Where the dough is drawn: centre (px in the parent), pizza frame F (px, its width), dough
	-- shape S and the view's flatten (the oven's 0.58; 1 elsewhere).
	function layers.place(_self: Layers, x: number, y: number, frameSize: number, shape: any, flatten: number?)
		local f = flatten or 1
		local k = key(shape, frameSize) .. string.format("|%.2f,%.2f|%.3f", x, y, f)
		if k == geometry then
			return
		end
		geometry = k
		cx, cy, F, S, flat = x, y, frameSize, shape, f
		build()
	end

	-- The rolled dough under the food (the Topping view; Make draws its own, with the ball): the
	-- two appearance keys either side of the mean radius, the upper one crossfaded in, fitted to
	-- the scored oval. With `seconds` (in the oven) the bare crusts take over by the bake
	-- timeline: raw keys, then light, regular, well done and burnt crusts, each crossfaded.
	function layers.dough(_self: Layers, on: boolean, seconds: number?)
		doughLayer.Visible = on
		if not on then
			return
		end
		local pl = G.bodyPlacement(G.ellipseOf(G.viewMatrix(S, F, flat)), DOUGH_BODY)
		local function put(img: ImageLabel)
			img.Size = UDim2.fromOffset(pl.width, pl.height)
			img.Rotation = pl.rotation
			img.Position = UDim2.fromOffset(cx + pl.offset.x, cy + pl.offset.y)
		end
		local ci, ct = 1, 0
		if seconds then
			ci, ct = blend(CRUSTS, seconds)
		end
		-- Raw keys show until the light crust is fully in.
		local rawShown = ci == 1
		local i1, i2, w = G.stateBlend(G.meanRadius(S))
		for i, k in keys do
			local shown = rawShown and (i == i1 or (i == i2 and w > 0))
			k.Visible = shown
			if shown then
				put(k)
				local upper = i == i2 and i2 ~= i1
				k.ZIndex = if upper then zIndex + 1 else zIndex
				k.ImageTransparency = if upper then 1 - w else 0
			end
		end
		local lowerArt = CRUSTS[ci].art
		crustLower.Visible = lowerArt ~= nil
		if lowerArt then
			Art.apply(crustLower, lowerArt)
			put(crustLower)
		end
		crustUpper.Visible = seconds ~= nil and ct > 0
		if crustUpper.Visible then
			Art.apply(crustUpper, CRUSTS[ci + 1].art :: string)
			put(crustUpper)
			-- Over the raw keys (two of them may be stacked) the light crust sits above both.
			crustUpper.ZIndex = zIndex + 2
			crustUpper.ImageTransparency = 1 - ct
		end
	end

	-- How long the pizza has been in the oven (nil: not baked). Swaps the sauce to the cooked
	-- art, tints it toward scorched past the regular bake, and moves the cheese through its
	-- states. Call before sauce() and cheese() so they draw with it.
	function layers.bake(_self: Layers, seconds: number?)
		baked = seconds
		local art = if seconds and seconds >= SAUCE_COOKED_AT then "food_sauce_cooked" else "food_sauce_raw"
		if art ~= sauceArt then
			sauceArt = art
			for _, st in stamps do
				Art.apply(st.image, art)
			end
		end
		-- The deep-red and scorch tints are combined in sauce(); force them to be redone.
		drawn = nil
	end

	-- The sauce field (nil: none) and the pours that made it (for the dollops).
	function layers.sauce(_self: Layers, field: { number }?, actions: { any }?)
		if field ~= nil and rawequal(field, drawn) then
			return
		end
		drawn = field
		local bare = BARE * MakeSauce.HALF
		for _, st in stamps do
			local t = 0
			local size = STAMP
			if field then
				for _, i in st.cells do
					t += field[i]
				end
				t /= #st.cells
				-- The stamp's edge stops half a cell short of the nearest unsauced cell.
				for _, c in st.near do
					if field[c[1]] < bare then
						size = math.clamp(2 * (c[2] - MakeSauce.CELL / 2), 0, STAMP)
						break
					end
				end
				-- Nor past the field's own edge (1.2 plus half a cell): cells beyond it are never
				-- scored, so the drawn sauce stops there too.
				size = math.min(size, 2 * math.max(st.reach, 0))
				size = math.floor(size / SIZE_STEP) * SIZE_STEP
			end
			if size <= 0 then
				t = 0
			elseif math.abs(size - st.size) > 1e-6 then
				st.size = size
				fit(st.image, size, SAUCE_SHARE, st.turn)
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
			local scorch = 0
			if baked and baked > Config.Oven.targets.regular then
				scorch = math.clamp((baked - Config.Oven.targets.regular) / (Config.Oven.burntAt - Config.Oven.targets.regular), 0, 1)
			end
			local deep = Color3.new(1, 1, 1):Lerp(DEEP, tint)
			local hot = Color3.new(1, 1, 1):Lerp(SCORCH, scorch)
			local color = Color3.new(deep.R * hot.R, deep.G * hot.G, deep.B * hot.B)
			if tint ~= st.tint or color ~= st.color then
				st.tint = tint
				st.color = color
				st.image.ImageColor3 = color
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
				local strength = math.clamp((t / fresh - 0.7) / 0.3, 0, 1)
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

	-- The cheese pinches (dough-local), in placement order, in the cooking state of the bake
	-- (raw when not baked): both states on the shared canvas, the upper fading in.
	function layers.cheese(_self: Layers, list: { any }?)
		local i, t = 1, 0
		if baked then
			i, t = blend(CHEESES, baked)
			t = math.floor(t * 50 + 0.5) / 50
		end
		-- Redrawn only when the pinches, the place or the cooking state change (the oven calls
		-- this every frame).
		local parts = { geometry, tostring(baked ~= nil), tostring(i), tostring(t) }
		for _, p in list or {} do
			table.insert(parts, string.format("%.4f,%.4f", p.x, p.y))
		end
		local k = table.concat(parts, "|")
		if k == cheeseKey then
			return
		end
		cheeseKey = k
		local n = 0
		for _, p in list or {} do
			n += 1
			local pair = pinches[n]
			if not pair then
				local lower = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex + 2, Parent = cheeseLayer })
				local upper = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zIndex + 3, Parent = cheeseLayer })
				pair = { lower, upper }
				pinches[n] = pair
			end
			local s = screen(p)
			for k, img in pair do
				img.Position = UDim2.fromOffset(s.X, s.Y)
				fit(img, 2 * PrepFood.PINCH_RADIUS, CHEESE_SHARE, (n * 137.5) % 360)
				local art = if k == 1 then CHEESES[i].art else CHEESES[i + 1].art
				if img:GetAttribute("Look") ~= art then
					img:SetAttribute("Look", art)
					Art.apply(img, art)
				end
			end
			pair[1].Visible = true
			pair[2].Visible = baked ~= nil and t > 0
			pair[2].ImageTransparency = 1 - t
		end
		for k = n + 1, #pinches do
			pinches[k][1].Visible = false
			pinches[k][2].Visible = false
		end
	end

	return layers
end

return MakeLayers

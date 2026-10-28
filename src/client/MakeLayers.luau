--!strict
-- Draws the player's own sauce and cheese on the dough they rolled, from the same records the
-- server grades (MakeSauce's thickness field, MakeCheese's pinches). Used by the Make station
-- (sauce and cheese steps), the Topping view (which also has it draw the rolled dough, P4, as
-- Make draws it) and the pizza views of Bake, Cut and the result, so no step shows a
-- preassembled pizza. Cosmetic only: it never takes input and never changes a record.
--
-- Sauce (slice 2, Astra r14; SauceCover): one thick marinara material through the coverage the
-- grade scores. Every field cell on the dough that carries sauce shows a disc of Astra's material
-- map (sauce_material_raw_v2), sampled at the disc's own dough-local place over the one canonical
-- -1..1 square, so neighbouring discs read as one continuous opaque material: covered patches
-- close up, their edges reach out as far as the edge cells' credit, and thin sauce shows as
-- sparse specks, never as a wash (SauceCover.disc). The discs sit in one CanvasGroup; the cooked map (sauce_material_cooked_v2) is the same discs in a second
-- group over it, its GroupTransparency the cooking share, so the colour moves from raw to cooked
-- under one unchanged mask (opaque wherever the sauce is). Cooking follows the food's own state
-- (SauceCover.cooked), not the ticket. Sauce spilled past the dough's edge shows only as the board
-- smear (sauce_board_spill_v2) at the recorded spill. A pour still mostly in place shows the
-- dollop (P7), which cooks and scorches with the sauce.
-- Config.FoodArt.sauce = "stamps" (or the renderer option) keeps the r13 soft stamps for the
-- same-input A/B: one stamp on every second grid point, its opacity from the thickness there.
-- Cheese: one pinch sprite per pinch, on the kit's shared canvas (footprint radius 0.17 dough-
-- local = 0.95 of the canvas), each with a fixed turn; the cooked family is Astra's r14 v2
-- exports on one shared alpha (or the r13 ones), the lower state in one group and the upper one
-- fading in as a second group over it.
-- Positions are dough-local and go through the one view map (PrepGeometry.screenOf), so sauce and
-- cheese stretch with the oval; every sprite is fitted to the local stretch (spriteFit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeSauce = require(Shared.MakeSauce)
local PrepFood = require(Shared.PrepFood)
local SauceCover = require(Shared.SauceCover)
local Ui = require(script.Parent.Ui)

local MakeLayers = {}

-- Registration (asset-manifest.json, response 13). The stamp values are the r13 renderer's, kept
-- for the A/B.
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
-- Response 14 (asset-manifest.json): the material maps are 1024 px over the -1..1 square; the
-- board smear's alpha spans 41..470 of its 512 px canvas across, centred.
local MATERIAL_PX = 1024
local CLOSE_PX = 1.5 -- see drawDisc
local SPILL_SHARE = (470 - 41) / 512
-- The cooked dollop: P7 tinted to the cooked map's mean colour (measured: P7 alpha>=128 mean
-- 228,35,10; cooked map mean inside radius 0.95 168,21,8; per channel 0.74, 0.59, 0.81).
local COOK_TINT = Color3.fromRGB(188, 151, 207)
-- Half widths (dough-local) of the groups that hold the sauce discs and the cheese pinches.
local SAUCE_REACH = SauceCover.SPAN + 0.02
local CHEESE_REACH = PrepFood.PINCH_REACH + PrepFood.PINCH_RADIUS / CHEESE_SHARE + 0.02
local DOUGH_BODY = { alphaX = 0.94921875, alphaY = 0.94921875, centreX = 0, centreY = 0 }
-- Baked states (Bake, Cut and the result card): seconds in the oven at which each drawn state is
-- fully shown, the same timeline as the old pre-sauced bake art (Widgets) so the look follows
-- the real bake progress, never the ticket. Crust: the rolled raw dough (P4 keys), then the P13
-- bare crusts (same 0.949 body share, fitted to the scored oval, so the rim thins with it).
-- Cheese and sauce follow the food's own cooking state (cheeseStates, SauceCover). Timings are
-- proposals.
local CRUSTS = {
	{ art = nil, at = 0 },
	{ art = "food_crust_light", at = Config.Oven.targets.light },
	{ art = "food_crust_regular", at = Config.Oven.targets.regular },
	{ art = "food_crust_well", at = Config.Oven.targets.well },
	{ art = "food_crust_burnt", at = Config.Oven.burntAt },
}
-- Cheese (slice 2): raw until the food's raw state ends (rawUntil), melted once it is cooked
-- (cookedFrom), golden by the well bake, burnt at burntAt.
local function cheeseStates(family: string): { any }
	local v = if family == "v1" then "" else "_v2"
	return {
		{ art = "food_cheese_raw", at = Config.Oven.rawUntil },
		{ art = "food_cheese_melted" .. v, at = Config.Oven.cookedFrom },
		{ art = "food_cheese_golden" .. v, at = Config.Oven.targets.well },
		{ art = "food_cheese_burnt" .. v, at = Config.Oven.burntAt },
	}
end
-- The r13 stamps' single swap to the cooked P15 stamp (kept for the A/B only): halfway through
-- the toppings' raw-to-baked crossfade (Widgets: from half the light bake to the regular bake).
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

export type Options = {
	-- "material" or "stamps" (default Config.FoodArt.sauce).
	sauce: string?,
	-- "v2" or "v1" (default Config.FoodArt.cheese).
	cheese: string?,
}

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

-- (Stamps) Composite opacity wanted at thickness t: full credit (half an even layer) shows nearly
-- opaque; thinner shows proportionally thinner.
local function opacity(t: number): number
	if t <= 0 then
		return 0
	end
	return FULL_OPACITY * math.min(1, t / MakeSauce.HALF)
end

-- The unsheared draw R(phi) diag(a, b) nearest the view's local stretch J (least squares): every
-- material disc of a view uses it, so all of them sample the map with one orientation and scale
-- and their overlaps show the same material. Returns phi (degrees) and a, b (px per dough-local
-- unit along the drawn axes). Exact for a round dough; on a sheared oval the residual is the
-- shear the GUI cannot draw.
local function tileFit(J: any): (number, number, number)
	local function miss(phi: number): (number, number, number)
		local c, s = math.cos(phi), math.sin(phi)
		local m11, m12 = c * J.a + s * J.c, c * J.b + s * J.d
		local m21, m22 = -s * J.a + c * J.c, -s * J.b + c * J.d
		if m11 <= 0 or m22 <= 0 then
			return math.huge, m11, m22
		end
		return m12 * m12 + m21 * m21, m11, m22
	end
	local best, phi = math.huge, 0
	for k = 0, 359 do
		local e = miss(math.rad(k))
		if e < best then
			best, phi = e, math.rad(k)
		end
	end
	local step = math.rad(1)
	for _ = 1, 24 do
		step /= 2
		for _, p in { phi - step, phi + step } do
			local e = miss(p)
			if e < best then
				best, phi = e, p
			end
		end
	end
	local _, a, b = miss(phi)
	return math.deg(phi), a, b
end

function MakeLayers.new(parent: GuiObject, zIndex: number, options: Options?): Layers
	local opts: Options = options or {}
	local stampsMode = (opts.sauce or Config.FoodArt.sauce) == "stamps"
	local CHEESES = cheeseStates(opts.cheese or Config.FoodArt.cheese)
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
	local spillLayer = Ui.new("Frame", { Name = "Spill", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Parent = frame })
	local sauceLayer = Ui.new("Frame", { Name = "Sauce", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex, Parent = frame })
	local dollopLayer = Ui.new("Frame", { Name = "Dollops", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 1, Parent = frame })
	local cheeseLayer = Ui.new("Frame", { Name = "Cheese", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zIndex + 2, Parent = frame })
	-- One flattened group per layer, sized to the pizza (not the station), so overlapping discs
	-- or pinches inside a group never add opacity to each other and the cooking share is one
	-- GroupTransparency.
	local function group(name: string, z: number, under: Instance): CanvasGroup
		return Ui.new("CanvasGroup", { Name = name, BackgroundTransparency = 1, ZIndex = z, Parent = under })
	end
	local sauceRaw = group("Raw", 1, sauceLayer)
	local sauceCooked = group("Cooked", 2, sauceLayer)
	sauceCooked.Visible = false
	local cheeseLower = group("Lower", 1, cheeseLayer)
	local cheeseUpper = group("Upper", 2, cheeseLayer)
	cheeseUpper.Visible = false

	local geometry = ""
	local cx, cy, F, flat = 0, 0, 1, 1
	-- Seconds in the oven (nil: not baked, the raw art).
	local baked: number? = nil
	local sauceArt = "food_sauce_raw"
	local S: any = G.shape(0.95, 0.95, 0)
	-- The view's local stretch, the material discs' shared draw and the groups' top-left corners
	-- (px in the frame).
	local J: any = G.localStretch(S, F, flat)
	local tileRot, tileA, tileB = 0, 1, 1
	local sauceOrigin, cheeseOrigin = Vector2.zero, Vector2.zero
	-- (Stamps) one per drawn grid point, with the fine cells it averages.
	-- near: the cells within the stamp's reach, nearest first, with their distances (for the edge).
	-- reach: the distance from the stamp's centre to the field's outer edge (extent plus half a
	-- cell), so no stamp is drawn past the grid the grade sees.
	type Stamp = { image: ImageLabel, cells: { number }, near: { { number } }, reach: number, turn: number, size: number, shown: number, tint: number, color: Color3? }
	local stamps: { Stamp } = {}
	-- (Material) one tile per field cell that has carried sauce (made on first use): its raw
	-- label, its cooked twin once the pizza has been in the oven, and what it last showed.
	type Tile = { raw: ImageLabel, cooked: ImageLabel?, key: string, shown: boolean }
	local tiles: { [number]: Tile } = {}
	local cookedOn = false
	local spills: { ImageLabel } = {}
	local dollops: { ImageLabel } = {}
	-- The cooking tint on the dollops and the smear (white when raw).
	local foodTint = Color3.new(1, 1, 1)
	-- Each pinch: its lower state (in cheeseLower) and its upper state (in cheeseUpper).
	local pinches: { { ImageLabel } } = {}
	-- The field last drawn: a replay memo's field is never changed, so the same table again
	-- (a frame with no new action) needs no redraw.
	local drawn: { number }? = nil
	-- The cheese last drawn (pinches, place and the pair of cooking states).
	local cheeseKey = ""

	local function screen(q: any): Vector2
		local o = G.screenOf(S, F, flat, q)
		return Vector2.new(cx + o.x, cy + o.y)
	end
	local function fit(img: ImageLabel, diameter: number, share: number, turn: number)
		local canvas = diameter / share
		local f = G.spriteFit(J, canvas, canvas, math.rad(turn))
		img.Size = UDim2.fromOffset(f.width, f.height)
		img.Rotation = f.rotation
	end
	-- Sizes a group to the screen box of the dough-local square +-reach; returns its corner.
	local function placeGroup(g: CanvasGroup, reach: number): Vector2
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, q in { { x = -reach, y = -reach }, { x = reach, y = -reach }, { x = -reach, y = reach }, { x = reach, y = reach } } do
			local p = screen(q)
			x0, y0, x1, y1 = math.min(x0, p.X), math.min(y0, p.Y), math.max(x1, p.X), math.max(y1, p.Y)
		end
		x0, y0 = math.floor(x0), math.floor(y0)
		g.Position = UDim2.fromOffset(x0, y0)
		g.Size = UDim2.fromOffset(math.ceil(x1) - x0, math.ceil(y1) - y0)
		return Vector2.new(x0, y0)
	end

	local function newDisc(art: string, under: CanvasGroup): ImageLabel
		local img = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, Parent = under })
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = img })
		Art.apply(img, art)
		return img
	end
	local function drawDisc(img: ImageLabel, disc: SauceCover.Disc)
		local p = screen(disc) - sauceOrigin
		-- Pinhole guard: a disc closing a patch is drawn at least CLOSE_PX (screen px, along the
		-- view's shorter axis) past the corner it shares with its diagonal neighbour, so pixel
		-- rounding never opens pinholes between four covered discs. It applies wherever that
		-- disc is small on screen (the phone views, and the flattened oven view at HD too), and
		-- never past the disc's own limit (SauceCover.EDGE_TOL onto a cell drawn bare), so it
		-- cannot fill or shrink a scored hole.
		if disc.kind == "full" then
			local least = MakeSauce.CELL * math.sqrt(2) + 2 * CLOSE_PX / math.min(tileA, tileB)
			least = math.min(least, 2 * disc.limit)
			if disc.w < least then
				disc = table.clone(disc)
				disc.w, disc.h = least, least
			end
		end
		img.Position = UDim2.fromOffset(p.X, p.Y)
		img.Size = UDim2.fromOffset(tileA * disc.w, tileB * disc.h)
		img.Rotation = tileRot
		local u, v, uw, vh = SauceCover.uv(disc)
		img.ImageRectOffset = Vector2.new(u * MATERIAL_PX, v * MATERIAL_PX)
		img.ImageRectSize = Vector2.new(uw * MATERIAL_PX, vh * MATERIAL_PX)
		img.ImageColor3 = Color3.new(1, 1, 1):Lerp(DEEP, disc.deep)
	end

	local function build()
		drawn = nil
		if stampsMode then
			for _, st in stamps do
				st.image:Destroy()
			end
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
		else
			-- The discs are redrawn at the new place when next shown.
			for _, tile in tiles do
				tile.key = ""
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
	-- shape S and the view's flatten (the oven's, StationLayout.OVEN; 1 elsewhere).
	function layers.place(_self: Layers, x: number, y: number, frameSize: number, shape: any, flatten: number?)
		local f = flatten or 1
		local k = key(shape, frameSize) .. string.format("|%.2f,%.2f|%.3f", x, y, f)
		if k == geometry then
			return
		end
		geometry = k
		cx, cy, F, S, flat = x, y, frameSize, shape, f
		J = G.localStretch(S, F, flat)
		tileRot, tileA, tileB = tileFit(J)
		sauceOrigin = placeGroup(sauceRaw, SAUCE_REACH)
		placeGroup(sauceCooked, SAUCE_REACH)
		cheeseOrigin = placeGroup(cheeseLower, CHEESE_REACH)
		placeGroup(cheeseUpper, CHEESE_REACH)
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

	-- The cooking tint on the dollops and the board smear.
	local function tintFood()
		for _, img in dollops do
			img.ImageColor3 = foodTint
		end
		for _, img in spills do
			img.ImageColor3 = foodTint
		end
	end

	-- How long the pizza has been in the oven (nil: not baked). Material: the cooked discs come
	-- in over the raw ones as one group (the cooking share is its GroupTransparency), both
	-- scorch together, the dollops and the smear take the same cooking; nothing is redrawn.
	-- Stamps (A/B only): swaps every stamp to P15 at SAUCE_COOKED_AT and redraws the tints.
	-- The cheese moves through its states. Call before sauce() and cheese() so they draw with it.
	function layers.bake(_self: Layers, seconds: number?)
		baked = seconds
		if stampsMode then
			local art = if seconds and seconds >= SAUCE_COOKED_AT then "food_sauce_cooked" else "food_sauce_raw"
			if art ~= sauceArt then
				sauceArt = art
				for _, st in stamps do
					Art.apply(st.image, art)
				end
			end
			-- The deep-red and scorch tints are combined in sauce(); force them to be redone.
			drawn = nil
			return
		end
		if seconds and not cookedOn then
			-- The cooked twins are made by the next sauce().
			cookedOn = true
			drawn = nil
		end
		local k = math.floor(SauceCover.cooked(seconds) * 50 + 0.5) / 50
		sauceRaw.Visible = k < 1
		sauceCooked.Visible = cookedOn and k > 0
		sauceCooked.GroupTransparency = 1 - k
		local hot = Color3.new(1, 1, 1):Lerp(SCORCH, SauceCover.scorched(seconds))
		sauceRaw.GroupColor3 = hot
		sauceCooked.GroupColor3 = hot
		local cook = Color3.new(1, 1, 1):Lerp(COOK_TINT, k)
		local tint = Color3.new(cook.R * hot.R, cook.G * hot.G, cook.B * hot.B)
		if tint ~= foodTint then
			foodTint = tint
			tintFood()
		end
	end

	-- (Stamps) the r13 drawing, kept for the A/B.
	local function drawStamps(field: { number }?)
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
	end

	-- (Material) the discs of the field and the smear of its spill.
	local function drawMaterial(field: { number }?)
		local seen: { [number]: boolean } = {}
		if field then
			for _, disc in SauceCover.discs(field) do
				seen[disc.cell] = true
				local tile = tiles[disc.cell]
				if not tile then
					tile = { raw = newDisc("sauce_material_raw_v2", sauceRaw), cooked = nil, key = "", shown = false }
					tiles[disc.cell] = tile
				end
				if cookedOn and not tile.cooked then
					tile.cooked = newDisc("sauce_material_cooked_v2", sauceCooked)
					tile.key = ""
				end
				local key = string.format("%.4f,%.4f,%.4f,%.4f,%.2f,%.4f", disc.x, disc.y, disc.w, disc.h, disc.deep, math.min(disc.limit, 1))
				if tile.key ~= key then
					tile.key = key
					drawDisc(tile.raw, disc)
					if tile.cooked then
						drawDisc(tile.cooked, disc)
					end
				end
				if not tile.shown then
					tile.shown = true
					tile.raw.Visible = true
					if tile.cooked then
						tile.cooked.Visible = true
					end
				end
			end
		end
		for i, tile in tiles do
			if tile.shown and not seen[i] then
				tile.shown = false
				tile.raw.Visible = false
				if tile.cooked then
					tile.cooked.Visible = false
				end
			end
		end
		local n = 0
		for _, sp in (if field then SauceCover.spills(field) else {}) do
			n += 1
			local img = spills[n]
			if not img then
				img = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ImageColor3 = foodTint, Parent = spillLayer })
				Art.apply(img, "sauce_board_spill_v2")
				spills[n] = img
			end
			local s = screen(sp)
			img.Position = UDim2.fromOffset(s.X, s.Y)
			fit(img, sp.width, SPILL_SHARE, math.deg(sp.along))
			img.Visible = true
		end
		for i = n + 1, #spills do
			spills[i].Visible = false
		end
	end

	-- The sauce field (nil: none) and the pours that made it (for the dollops).
	function layers.sauce(_self: Layers, field: { number }?, actions: { any }?)
		if field ~= nil and rawequal(field, drawn) then
			return
		end
		drawn = field
		if stampsMode then
			drawStamps(field)
		else
			drawMaterial(field)
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
					img = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ImageColor3 = foodTint, ZIndex = zIndex + 1, Parent = dollopLayer })
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
	-- (raw when not baked): the lower state in one group, the upper state in a second group
	-- fading in over it (its GroupTransparency, so the oven's every-frame call redraws nothing).
	function layers.cheese(_self: Layers, list: { any }?)
		local i, t = 1, 0
		if baked then
			i, t = blend(CHEESES, baked)
			t = math.floor(t * 50 + 0.5) / 50
		end
		cheeseUpper.Visible = baked ~= nil and t > 0
		cheeseUpper.GroupTransparency = 1 - t
		-- Redrawn only when the pinches, the place or the pair of states change.
		local parts = { geometry, tostring(i) }
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
				local lower = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Parent = cheeseLower })
				local upper = Ui.new("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Parent = cheeseUpper })
				pair = { lower, upper }
				pinches[n] = pair
			end
			local s = screen(p) - cheeseOrigin
			for j, img in pair do
				img.Position = UDim2.fromOffset(s.X, s.Y)
				fit(img, 2 * PrepFood.PINCH_RADIUS, CHEESE_SHARE, (n * 137.5) % 360)
				local art = if j == 1 then CHEESES[i].art else CHEESES[i + 1].art
				if img:GetAttribute("Look") ~= art then
					img:SetAttribute("Look", art)
					Art.apply(img, art)
				end
				img.Visible = true
			end
		end
		for j = n + 1, #pinches do
			pinches[j][1].Visible = false
			pinches[j][2].Visible = false
		end
	end

	return layers
end

return MakeLayers

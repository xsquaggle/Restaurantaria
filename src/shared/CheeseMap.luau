--!strict
-- The one cheese map (Lawson, 2026-10-29 13:45: cheese is graded on how much of the pizza it
-- really covers, one shared coverage map read by both the picture and the grade). Built from the
-- accepted pinches on the actual dough (dough-local, so an oval keeps its own outline) and read
-- by MakeCheese.grade (coverage), by the Make hints, and by every drawn view (MakeLayers): the
-- strict surface is this map's own outline, the baked base is chosen and shaped from it.
-- Pure functions, shared by server, client and tests.
--
-- The map is a grid of nodes GRID_STEP apart over the dough-local square. At each node on the
-- dough (radius up to DOUGH) it holds:
--  * count: how many pinch footprints (PrepFood.PINCH_RADIUS discs) cover the node; and
--  * edge: the signed distance to the nearest footprint's rim (positive inside), clipped by the
--    dough's own edge, so the strict surface is the union of the footprints on the dough, drawn
--    with its real outline (linear interpolation between nodes; no gap fill).
-- Cheese stops at the dough's actual outer edge (Lawson; Astra r21): no node past DOUGH ever
-- holds cheese, and PrepFood refuses pinch centres past it (no accepted deposit, no supply used).
-- The smaller edible target (EDIBLE, 0.84) is only where coverage is graded.
--
-- Presentation (Lawson 2026-11-01 22:08, with Astra): the baked look is an authored finished
-- cheese base chosen by coverage, amount and evenness, not the order grade. look() picks the
-- variant and shapes the base from this map (broad misses and heavy piles kept, gaps between
-- shreds closed). It changes the picture only: the recorded score is the grade's, from the map.
-- Every threshold below marked "proposal" is a proposal, not an approved value.

local PrepFood = require(script.Parent.PrepFood)

local CheeseMap = {}

CheeseMap.DOUGH = 0.95 -- the dough's outer edge, dough-local
CheeseMap.EDIBLE = 0.84 -- the edible target, where coverage is graded
CheeseMap.GRID_STEP = 0.04
CheeseMap.G = 24 -- nodes run from -G to G on each axis (0.96 each way)
-- Proposals (presentation only): a node under PILE footprints or more is a heavy pile; the
-- base closes gaps narrower than about two SMOOTH (a blur of the covered nodes, cut at half);
-- a miss of at least BROAD_MISS (share of the edible area) is a broad miss the base keeps.
CheeseMap.PILE = 3
CheeseMap.SMOOTH = 0.05
CheeseMap.BROAD_MISS = 0.03
-- Variant bands (proposal, Lawson to judge; no earlier percentage is approved): "even" from
-- GOOD_COVERAGE coverage with no broad miss and under HEAVY_SHARE of the edible area piled;
-- "heavy" from HEAVY_SHARE piled; otherwise "patchy".
CheeseMap.GOOD_COVERAGE = 0.85
CheeseMap.HEAVY_SHARE = 0.12

local G, H = CheeseMap.G, CheeseMap.GRID_STEP
local SIDE = 2 * G + 1
CheeseMap.SIDE = SIDE

-- Node index of grid coordinates (gx, gy) in -G..G.
local function idx(gx: number, gy: number): number
	return (gx + G) * SIDE + (gy + G) + 1
end
CheeseMap.index = idx

-- Fixed per-node data: radius and whether on the dough / edible area.
local NODES = SIDE * SIDE
local radius: { number } = table.create(NODES, 0)
local onDough: { boolean } = table.create(NODES, false)
local edible: { boolean } = table.create(NODES, false)
local edibleCount = 0
for gx = -G, G do
	for gy = -G, G do
		local i = idx(gx, gy)
		local r = math.sqrt((gx * H) ^ 2 + (gy * H) ^ 2)
		radius[i] = r
		onDough[i] = r <= CheeseMap.DOUGH + 1e-9
		edible[i] = r <= CheeseMap.EDIBLE + 1e-9
		if edible[i] then
			edibleCount += 1
		end
	end
end
CheeseMap.radius = radius
CheeseMap.onDough = onDough
CheeseMap.edible = edible
CheeseMap.EDIBLE_NODES = edibleCount

export type Vec = { x: number, y: number }
export type Map = {
	count: { number },
	edge: { number },
	pinches: number,
}

local FAR = -1 -- edge value of a node no footprint comes near (well outside every rim)

-- Builds the map from accepted pinches (dough-local). Pinches past the dough's edge (which
-- PrepFood refuses) would add nothing past it either.
function CheeseMap.build(pinches: { Vec }): Map
	local R = PrepFood.PINCH_RADIUS
	local count = table.create(NODES, 0)
	local edge = table.create(NODES, FAR)
	local reach = R + 2 * H
	for _, p in pinches do
		local x0, x1 = math.max(-G, math.floor((p.x - reach) / H)), math.min(G, math.ceil((p.x + reach) / H))
		local y0, y1 = math.max(-G, math.floor((p.y - reach) / H)), math.min(G, math.ceil((p.y + reach) / H))
		for gx = x0, x1 do
			for gy = y0, y1 do
				local i = idx(gx, gy)
				local d = math.sqrt((gx * H - p.x) ^ 2 + (gy * H - p.y) ^ 2)
				local e = R - d
				if e > edge[i] then
					edge[i] = e
				end
				if e >= 0 and onDough[i] then
					count[i] += 1
				end
			end
		end
	end
	-- Clip by the dough's own edge: nothing shows or counts past it.
	for i = 1, NODES do
		local inside = CheeseMap.DOUGH - radius[i]
		if inside < edge[i] then
			edge[i] = inside
		end
		if not onDough[i] then
			count[i] = 0
		end
	end
	return { count = count, edge = edge, pinches = #pinches }
end

-- Coverage of the edible area (share of edible nodes under at least one footprint), the mean
-- footprint count there (amount; one even layer of 24 pinches is about 1), the share of edible
-- nodes piled (count >= PILE), evenness (1 minus the spread of the counts over the edible area
-- against their mean, 0..1), the share of the crust band covered, and the largest bare region
-- inside the edible area (share of the edible area, 4-connected nodes).
export type Measure = {
	coverage: number,
	amount: number,
	piled: number,
	evenness: number,
	crust: number,
	largestMiss: number,
}

function CheeseMap.measure(map: Map): Measure
	local covered, sum, sum2, piled, crustN, crustCovered = 0, 0, 0, 0, 0, 0
	for i = 1, NODES do
		local c = map.count[i]
		if edible[i] then
			sum += c
			sum2 += c * c
			if c >= 1 then
				covered += 1
			end
			if c >= CheeseMap.PILE then
				piled += 1
			end
		elseif onDough[i] then
			crustN += 1
			if c >= 1 then
				crustCovered += 1
			end
		end
	end
	local n = edibleCount
	local mean = sum / n
	local var = math.max(0, sum2 / n - mean * mean)
	local evenness = if mean > 0 then math.clamp(1 - math.sqrt(var) / mean, 0, 1) else 0
	-- Largest bare region inside the edible area.
	local seen: { [number]: boolean } = {}
	local largest = 0
	for gx = -G, G do
		for gy = -G, G do
			local i = idx(gx, gy)
			if edible[i] and map.count[i] == 0 and not seen[i] then
				local size = 0
				local stack = { { gx, gy } }
				seen[i] = true
				while #stack > 0 do
					local top = table.remove(stack) :: { number }
					size += 1
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local nx, ny = top[1] + d[1], top[2] + d[2]
						if nx >= -G and nx <= G and ny >= -G and ny <= G then
							local j = idx(nx, ny)
							if edible[j] and map.count[j] == 0 and not seen[j] then
								seen[j] = true
								table.insert(stack, { nx, ny })
							end
						end
					end
				end
				largest = math.max(largest, size)
			end
		end
	end
	return {
		coverage = covered / n,
		amount = mean,
		piled = piled / n,
		evenness = evenness,
		crust = if crustN > 0 then crustCovered / crustN else 0,
		largestMiss = largest / n,
	}
end

-- A separable blur of a 0/1 node field with a Gaussian of sigma SMOOTH (in dough-local units),
-- kept on the dough. Used for the baked base's shape (presentation only).
local function blur(field: { number }, sigma: number): { number }
	local k = math.max(1, math.ceil(2.5 * sigma / H))
	local w = {}
	local total = 0
	for j = -k, k do
		w[j] = math.exp(-0.5 * (j * H / sigma) ^ 2)
		total += w[j]
	end
	for j = -k, k do
		w[j] /= total
	end
	local tmp = table.create(NODES, 0)
	for gx = -G, G do
		for gy = -G, G do
			local s = 0
			for j = -k, k do
				local x = gx + j
				if x >= -G and x <= G then
					s += w[j] * field[idx(x, gy)]
				end
			end
			tmp[idx(gx, gy)] = s
		end
	end
	local out = table.create(NODES, 0)
	for gx = -G, G do
		for gy = -G, G do
			local s = 0
			for j = -k, k do
				local y = gy + j
				if y >= -G and y <= G then
					s += w[j] * tmp[idx(gx, y)]
				end
			end
			out[idx(gx, gy)] = s
		end
	end
	return out
end

-- The baked look (presentation only): the variant ("even", "patchy" or "heavy") and two node
-- fields to draw at level 0 (positive inside): the base (the covered area with the gaps
-- between shreds closed, broad misses kept, clipped to the dough) and the piles (the heavy
-- areas, drawn over the base). Also the base's area against the scored covered area, as shares
-- of the dough, so every proof can report the visual-only fill.
export type Look = {
	variant: string,
	base: { number },
	piles: { number },
	measure: Measure,
	baseShare: number,
	strictShare: number,
}

function CheeseMap.look(map: Map): Look
	local m = CheeseMap.measure(map)
	local covered = table.create(NODES, 0)
	local heavy = table.create(NODES, 0)
	for i = 1, NODES do
		if map.count[i] >= 1 then
			covered[i] = 1
		end
		if map.count[i] >= CheeseMap.PILE then
			heavy[i] = 1
		end
	end
	local soft = blur(covered, CheeseMap.SMOOTH)
	local softHeavy = blur(heavy, CheeseMap.SMOOTH)
	local base = table.create(NODES, FAR)
	local piles = table.create(NODES, FAR)
	local baseN, strictN, doughN = 0, 0, 0
	for i = 1, NODES do
		local inside = CheeseMap.DOUGH - radius[i]
		-- Level 0 at half the blur; scaled to dough-local distance near the rim (the blur's
		-- slope at its half point is about 0.4 / sigma per unit), clipped by the dough's edge.
		local b = (soft[i] - 0.5) * CheeseMap.SMOOTH * 2.5
		base[i] = math.min(b, inside)
		piles[i] = math.min((softHeavy[i] - 0.5) * CheeseMap.SMOOTH * 2.5, inside)
		if onDough[i] then
			doughN += 1
			if base[i] >= 0 then
				baseN += 1
			end
			if map.count[i] >= 1 then
				strictN += 1
			end
		end
	end
	local variant = "patchy"
	if m.piled >= CheeseMap.HEAVY_SHARE then
		variant = "heavy"
	elseif m.coverage >= CheeseMap.GOOD_COVERAGE and m.largestMiss < CheeseMap.BROAD_MISS then
		variant = "even"
	end
	return {
		variant = variant,
		base = base,
		piles = piles,
		measure = m,
		baseShare = baseN / doughN,
		strictShare = strictN / doughN,
	}
end

return CheeseMap

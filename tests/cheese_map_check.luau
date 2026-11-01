-- Checks for the one cheese map's pictures (slice 8a; Lawson 2026-10-29 15:40 and 2026-11-01
-- 22:08, with Astra): the strict surface is the map's own outline, the baked base is a coherent
-- finished cheese layer chosen and shaped from the same map (gaps between shreds closed, broad
-- misses and heavy piles kept), nothing is drawn past the dough's edge, and the picture never
-- changes the recorded score. Also the tile surface (SurfaceTiles) the client draws both with.
-- The three proofs (CheeseProofs: even, large miss, heavy pile) have the same 24 pinches each.
-- Arithmetic only, no Studio: the drawn result is shown by the Studio captures.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local PrepFood = require(Shared.PrepFood)
local MakeCheese = require(Shared.MakeCheese)
local CheeseMap = require(Shared.CheeseMap)
local CheeseProofs = require(Shared.CheeseProofs)
local SurfaceTiles = require(Shared.SurfaceTiles)

local failures = {}
local passed = 0
local report = {}
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end
local function near(name: string, got: number, want: number, tol: number)
	check(string.format("%s (%.4f vs %.4f, within %.4f)", name, got, want, tol), math.abs(got - want) <= tol, true)
end
local function note(line: string)
	table.insert(report, line)
end

local G, H = CheeseMap.G, CheeseMap.GRID_STEP

------------------------------------------------------------------------------------------
-- 1. The tile surface on known fields.

local function field(f: (number, number) -> number): (number, number) -> number
	return f
end
-- A disc of radius 0.5: area pi r^2 (the polygon through the grid crossings is a little less).
local disc = SurfaceTiles.build(G, H, field(function(gx, gy)
	return 0.5 - math.sqrt((gx * H) ^ 2 + (gy * H) ^ 2)
end), 0)
near("tiles: a disc's drawn area", SurfaceTiles.area(disc), math.pi * 0.25, 0.01)
local cuts = 0
for _, t in disc do
	if t.kind == "cut" then
		cuts += 1
	end
end
check("tiles: a disc's outline is cut tiles, its inside a few long runs", cuts > 0 and #disc - cuts <= 2 * G, true)
-- Everything and nothing.
local all = SurfaceTiles.build(G, H, field(function()
	return 1
end), 0)
near("tiles: a full field covers the whole grid", SurfaceTiles.area(all), (2 * G * H) ^ 2, 1e-9)
check("tiles: a full field is one run per row", #all, 2 * G)
check("tiles: an empty field draws nothing", #SurfaceTiles.build(G, H, field(function()
	return -1
end), 0), 0)
-- A half plane x <= 0.1: area of the part of the grid square left of it, every cut straight.
local half = SurfaceTiles.build(G, H, field(function(gx, _gy)
	return 0.1 - gx * H
end), 0)
near("tiles: a half plane's drawn area", SurfaceTiles.area(half), (0.1 + G * H) * 2 * G * H, 1e-9)
-- A saddle (corners alternate) is drawn as the middle says.
local function saddle(mid: number): number
	local tiles = SurfaceTiles.build(1, 1, function(gx, gy)
		if gx == 0 and gy == 0 then
			return 1
		elseif gx == 1 and gy == 1 then
			return 1
		elseif gx == 0 or gy == 0 then
			return -1 + mid
		end
		return -1
	end, 0)
	return #tiles
end
check("tiles: a saddle with its middle outside is two pieces", saddle(0) >= 2, true)

------------------------------------------------------------------------------------------
-- 2. The three proofs: the same 24 pinches, all accepted by the server's check.

local proofs = {}
for _, name in CheeseProofs.names do
	local pinches = CheeseProofs.pinches(name)
	check(name .. ": 24 pinches", #pinches, 24)
	local inside, edible = 0, 0
	for _, p in pinches do
		local r = math.sqrt(p.x * p.x + p.y * p.y)
		if r <= PrepFood.PINCH_REACH then
			inside += 1
		end
		if r <= CheeseMap.EDIBLE then
			edible += 1
		end
	end
	check(name .. ": every pinch on the edible area", edible, 24)
	-- Stored through the server's check, each pinch its own short sprinkle (a tap), as the
	-- debug proof command sends them.
	local cheese = { strokes = {} }
	local refused = 0
	for _, p in pinches do
		local clean, newStroke = MakeCheese.validate(cheese, { newStroke = true, points = { p } })
		if clean then
			MakeCheese.add(cheese, clean, newStroke)
		else
			refused += 1
		end
	end
	check(name .. ": stored without refusals", refused, 0)
	local map = CheeseMap.build(MakeCheese.pinches(cheese))
	local grade = MakeCheese.grade(cheese)
	proofs[name] = { pinches = pinches, cheese = cheese, map = map, grade = grade, look = CheeseMap.look(map) }
end

------------------------------------------------------------------------------------------
-- 3. The variant, and what the base keeps.

check("even: the even variant", proofs.even.look.variant, "even")
check("large miss: the patchy variant", proofs.miss.look.variant, "patchy")
check("heavy pile: the heavy variant", proofs.pile.look.variant, "heavy")

-- The even base closes the gaps between shreds: it covers more than the strict outline, and
-- leaves no broad miss.
local ev = proofs.even.look
check("even: the base covers at least the good share inside the rim", ev.baseCoverage >= CheeseMap.GOOD_COVERAGE, true)
check("even: the base is fuller than the strict outline", ev.baseShare > ev.strictShare, true)
check("even: no broad miss left", ev.broadMiss < CheeseMap.BROAD_MISS, true)

-- The large miss keeps its bare half: nodes well inside the right half stay bare in the base.
local mi = proofs.miss.look
local rightBare, rightN = 0, 0
for gx = -G, G do
	for gy = -G, G do
		local x, y = gx * H, gy * H
		if x >= 0.25 and x * x + y * y <= 0.7 * 0.7 then
			rightN += 1
			if mi.base[CheeseMap.index(gx, gy)] < 0 then
				rightBare += 1
			end
		end
	end
end
check("large miss: the base keeps the right half bare", rightBare, rightN)
check("large miss: the base reports a broad miss", mi.broadMiss >= CheeseMap.BROAD_MISS, true)

-- The heavy pile keeps its pile: the pile field is positive at the pile's spot and nowhere far
-- from it; the rest is still one base.
local pl = proofs.pile.look
local function nodeAt(x: number, y: number): number
	return CheeseMap.index(math.round(x / H), math.round(y / H))
end
check("heavy pile: the pile is drawn at its spot", pl.piles[nodeAt(0.3, 0.1)] > 0, true)
local farPile = 0
for gx = -G, G do
	for gy = -G, G do
		local x, y = gx * H, gy * H
		if (x - 0.3) ^ 2 + (y - 0.1) ^ 2 > 0.35 ^ 2 and pl.piles[CheeseMap.index(gx, gy)] >= 0 then
			farPile += 1
		end
	end
end
check("heavy pile: no pile drawn far from the spot", farPile, 0)
check("heavy pile: the pile sits on the base", pl.base[nodeAt(0.3, 0.1)] > 0, true)
-- Even and the miss have no piles drawn.
for _, name in { "even", "miss" } do
	local any = 0
	for i = 1, #proofs[name].look.piles do
		if proofs[name].look.piles[i] >= 0 then
			any += 1
		end
	end
	check(name .. ": no pile drawn", any, 0)
end

------------------------------------------------------------------------------------------
-- 4. Nothing past the dough's edge, in the map and in every drawn surface.

for _, name in CheeseProofs.names do
	local pr = proofs[name]
	local past = 0
	for i = 1, #pr.map.edge do
		if CheeseMap.radius[i] > CheeseMap.DOUGH + 1e-9 then
			if pr.map.edge[i] >= 0 or pr.look.base[i] >= 0 or pr.look.piles[i] >= 0 or pr.map.count[i] > 0 then
				past += 1
			end
		end
	end
	check(name .. ": no node past the dough holds cheese", past, 0)
end
-- An edge-heavy deposit (pinches on the dough's edge all around): the strict and base tiles
-- stay inside the dough (sampled inside every tile's drawn part).
local rim = {}
for i = 0, 23 do
	local a = i / 24 * 2 * math.pi
	table.insert(rim, { x = 0.95 * math.cos(a), y = 0.95 * math.sin(a) })
end
local rimMap = CheeseMap.build(rim)
local rimLook = CheeseMap.look(rimMap)
local function index(f: { number }): (number, number) -> number
	return function(gx: number, gy: number): number
		return f[CheeseMap.index(gx, gy)]
	end
end
local worst = 0
for _, tiles in { SurfaceTiles.build(G, H, index(rimMap.edge), 0), SurfaceTiles.build(G, H, index(rimLook.base), 0) } do
	for _, t in tiles do
		for sx = 0, 4 do
			for sy = 0, 4 do
				local x = t.x0 + (t.x1 - t.x0) * sx / 4
				local y = t.y0 + (t.y1 - t.y0) * sy / 4
				local inside = true
				if t.kind == "cut" then
					local cx, cy = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2
					inside = (t.nx :: number) * (x - cx) + (t.ny :: number) * (y - cy) <= (t.d :: number) + 1e-9
				end
				if inside then
					worst = math.max(worst, math.sqrt(x * x + y * y) - CheeseMap.DOUGH)
				end
			end
		end
	end
end
-- Between nodes the outline is straight, so it can cut a corner of the round edge by at most
-- the sagitta of one grid square's chord (about h^2 / (8 r) plus the square's diagonal step).
check("edge: no drawn cheese more than 0.005 past the dough's edge", worst <= 0.005, true)
note(string.format("Edge deposit (24 pinches on the dough's edge): drawn cheese reaches %.4f past the edge at most (strict and base)", math.max(0, worst)))

------------------------------------------------------------------------------------------
-- 5. The strict surface is the scored coverage; the picture never changes the score.

-- An independent fine grid (0.01) of the footprint union on the dough, against the strict
-- tiles' drawn area.
local function union(pinches: { any }): number
	local hit = 0
	local step = 0.01
	for x = -0.95, 0.95, step do
		for y = -0.95, 0.95, step do
			if x * x + y * y <= 0.95 * 0.95 then
				for _, p in pinches do
					if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= PrepFood.PINCH_RADIUS ^ 2 then
						hit += 1
						break
					end
				end
			end
		end
	end
	return hit * step * step
end
note("proof        pinches  scored coverage  strict drawn / footprints  base inside rim  broad miss  pile share  base fill beyond strict  variant  Cheese grade")
for _, name in CheeseProofs.names do
	local pr = proofs[name]
	local strict = SurfaceTiles.build(G, H, index(pr.map.edge), 0)
	local drawn = SurfaceTiles.area(strict)
	local truth = union(pr.pinches)
	check(name .. ": the strict surface draws the footprints' area within 4%", math.abs(drawn - truth) / truth <= 0.04, true)
	-- The score reads the map, never the look.
	local before = MakeCheese.grade(pr.cheese).score
	CheeseMap.look(pr.map)
	check(name .. ": building the look leaves the score alone", MakeCheese.grade(pr.cheese).score, before)
	near(name .. ": the grade's coverage is the map's", pr.grade.detail.coverage, CheeseMap.measure(pr.map).coverage, 1e-9)
	local lk = pr.look
	note(string.format("%-12s %7d  %15.3f  %12.3f / %-12.3f  %15.3f  %10.3f  %10.3f  %23s  %-7s  %12d", CheeseProofs.labels[name], #pr.pinches, pr.grade.detail.coverage, drawn, truth, lk.baseCoverage, lk.broadMiss, lk.pileShare, string.format("%+.3f of the dough", lk.baseShare - lk.strictShare), lk.variant, pr.grade.score))
end
check("proofs: even scores above the miss and the pile", proofs.even.grade.score > proofs.miss.grade.score and proofs.even.grade.score > proofs.pile.grade.score, true)

------------------------------------------------------------------------------------------
-- 6. Proposals carried by these checks (none approved; Lawson to judge).

check("proposal: closing radius", CheeseMap.CLOSE, 0.08)
check("proposal: outline smoothing", CheeseMap.SMOOTH, 0.05)
check("proposal: broad miss share", CheeseMap.BROAD_MISS, 0.03)
check("proposal: rim left out of the variant", CheeseMap.RIM, 0.08)
check("proposal: good coverage", CheeseMap.GOOD_COVERAGE, 0.8)
check("proposal: heavy pile share", CheeseMap.HEAVY_SHARE, 0.25)
check("proposal: heavy amount", CheeseMap.HEAVY_AMOUNT, 1.6)
check("proposal: pile depth", CheeseMap.PILE, 4)
note(string.format("Melt (proposal): the loose shreds fade out and the finished base fades in from %d s to %d s in the oven (the end of raw to cooked); colour follows the bake after that", Config.Oven.rawUntil, Config.Oven.cookedFrom))

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cheese map checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

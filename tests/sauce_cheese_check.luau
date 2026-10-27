-- Checks for the Make tab's sauce and cheese steps: the sauce thickness field (pours, spreads,
-- conservation, event-rate independence), every server refusal (each leaving the pizza as it
-- was), the cheese batch check (true array, batch cap, a refused first batch stores nothing),
-- Undo, the steps' minimums, the sparse / half / heavy / spilled sauce and sparse / clustered
-- cheese grades with their coverage ceilings, the Make mean and the server's actions. Sauce
-- grade values are an independent recompute (a separate Python model of the same rules, not the
-- Luau under test); ceilings and means are worked by hand from them. Cheese scores come from
-- PrepFood.cheeseScore, which prep_check covers; here they are read and only the notes, the
-- ceiling and the mean are worked. Run offline with tests/offline/run.py, or in Studio Edit after
-- a sync. Arithmetic only: how the sauce and cheese look is checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local MakeCheese = require(Shared.MakeCheese)
local MakeDough = require(Shared.MakeDough)
local MakeSauce = require(Shared.MakeSauce)
local PrepFood = require(Shared.PrepFood)
local Recipes = require(Shared.Recipes)
local Scoring = require(Shared.Scoring)
local ShiftService = require(game:GetService("ServerScriptService").Server.ShiftService)

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
local function near(name: string, got: number?, want: number, tol: number?)
	if type(got) == "number" and math.abs(got - want) <= (tol or 1e-6) then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %.6f (+-%g)", name, tostring(got), want, tol or 1e-6))
	end
end
local function note(line: string)
	table.insert(report, line)
end
local function P(x: number, y: number)
	return { x = x, y = y }
end
local function has(notes: { string }, text: string): boolean
	return table.find(notes, text) ~= nil
end
local function circle(r: number): { any }
	local out = {}
	for i = 0, 40 do
		local a = 2 * math.pi * i / 40
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function arc(r: number, from: number, to: number): { any }
	local out = {}
	for i = 0, 32 do
		local a = math.rad(from + (to - from) * i / 32)
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function slice(list: { any }, a: number, b: number): { any }
	local out = {}
	for i = a, b do
		table.insert(out, list[i])
	end
	return out
end
local function sauceOf(pours: { any }, spreads: { { any } }): any
	local actions = {}
	for _, p in pours do
		table.insert(actions, { kind = "pour", x = p.x, y = p.y })
	end
	for _, s in spreads do
		table.insert(actions, { kind = "spread", points = s })
	end
	return { actions = actions }
end
local function mass(field: { number }): number
	local t = 0
	for _, v in field do
		t += v
	end
	return t * MakeSauce.CELL * MakeSauce.CELL
end

local cfg = Config.Sauce
-- The proposed constants this file's values assume.
check("proposal: cell", cfg.cell, 0.05)
check("proposal: extent", cfg.extent, 1.2)
check("proposal: pour radius", cfg.pourRadius, 0.3)
check("proposal: ladle radius", cfg.ladleRadius, 0.18)
check("proposal: spread step", cfg.spreadStep, 0.04)
check("proposal: pick", cfg.pick, 0.5)
check("proposal: lay", cfg.lay, 0.5)
check("proposal: occupied", cfg.occupied, 0.05)
check("proposal: tap pixels", cfg.tapPixels, 8)
check("proposal: target pours", cfg.targetPours, 3)
check("proposal: max pours", cfg.maxPours, 6)
check("proposal: max spreads", cfg.maxSpreads, 30)
check("proposal: max points", cfg.maxPoints, 64)
check("proposal: stroke reach", cfg.strokeReach, 1.6)
check("proposal: min spread", cfg.minSpread, 0.2)
check("proposal: max spread", cfg.maxSpread, 6)
check("proposal: weights", string.format("%g/%g/%g/%g", cfg.amountWeight, cfg.coverWeight, cfg.cleanWeight, cfg.offWeight), "0.3/0.5/0.2/2")
check("proposal: note thresholds", string.format("%g/%g/%g", cfg.bareBelow, cfg.crustAbove, cfg.spillAbove), "0.9/0.05/0.02")
check("proposal: ceiling ramp", string.format("%g/%g/%g", cfg.ceilingFloor, cfg.ceilingFrom, cfg.ceilingTo), "35/0.25/0.75")
check("proposal: cheese batch", Config.Cheese.batchSize, 8)
check("proposal: cheese notes", string.format("%g/%g/%g", Config.Cheese.fewBelow, Config.Cheese.manyAbove, Config.Cheese.bunchedBelow), "20/28/0.7")

-- 1. The grid: cells 0.05 apart within radius 1.2. Counted independently: 1793 cells, 885 of them
-- within the edible 0.84. HALF = 3 / (pi 0.84^2) / 2 = 0.676679.
check("grid: cells", MakeSauce.COUNT, 1793)
check("grid: edible cells", MakeSauce.EDIBLE_CELLS, 885)
near("grid: half an even layer", MakeSauce.HALF, 3 / (math.pi * 0.84 * 0.84) / 2, 1e-12)
check("grid: centre cell", MakeSauce.xs[MakeSauce.cellAt(0, 0) :: number], 0)
check("grid: past the extent", MakeSauce.cellAt(24, 24), nil)

-- 2. A pour lays exactly one unit; a spread moves sauce and never creates or loses any.
do
	local f = MakeSauce.empty()
	check("pour: accepted", MakeSauce.pour(f, P(0.2, -0.1)), true)
	near("pour: one unit", mass(f), 1, 1e-12)
	local crossed, moved = MakeSauce.spread(f, { P(-0.5, -0.1), P(0.6, -0.1) })
	check("spread over the pour: crossed sauce", crossed, true)
	check("spread over the pour: moved sauce", moved > 0, true)
	near("spread: sauce conserved", mass(f), 1, 1e-12)
	local bare = MakeSauce.empty()
	MakeSauce.pour(bare, P(0.4, 0))
	local crossedBare, _ = MakeSauce.spread(bare, { P(-0.8, -0.5), P(-0.3, -0.8) })
	check("spread over bare dough: did not cross sauce", crossedBare, false)
end

-- 3. Event-rate independence: the same straight drag as 2 points or as 41 gives the same marks
-- (one every 0.04 of travel: 0.8 / 0.04 = 20 steps, 21 marks) and the same field.
do
	local two = { P(-0.4, 0.1), P(0.4, 0.1) }
	local many = {}
	for i = 0, 40 do
		many[i + 1] = P(-0.4 + 0.8 * i / 40, 0.1)
	end
	check("marks: 21 from two points", #MakeSauce.marks(two), 21)
	check("marks: 21 from forty-one points", #MakeSauce.marks(many), 21)
	local f1, f2 = MakeSauce.empty(), MakeSauce.empty()
	MakeSauce.pour(f1, P(0, 0.1))
	MakeSauce.pour(f2, P(0, 0.1))
	MakeSauce.spread(f1, two)
	MakeSauce.spread(f2, many)
	local worst = 0
	for i = 1, MakeSauce.COUNT do
		worst = math.max(worst, math.abs(f1[i] - f2[i]))
	end
	near("event rate: same field", worst, 0, 1e-9)
end

-- 4. The coverage ceiling ramp (plan rev 6, 5.3d): 35 up to 0.25, 100 from 0.75, linear between:
-- 0.5 -> 35 + 65 x 0.5 = 67.5 -> 68; 0.6 -> 35 + 65 x 0.7 = 80.5 -> 81.
check("ceiling at 0", MakeSauce.ceiling(0), 35)
check("ceiling at 0.25", MakeSauce.ceiling(0.25), 35)
check("ceiling at 0.5", MakeSauce.ceiling(0.5), 68)
check("ceiling at 0.6", MakeSauce.ceiling(0.6), 81)
check("ceiling at 0.75", MakeSauce.ceiling(0.75), 100)
check("ceiling at 1", MakeSauce.ceiling(1), 100)

-- 5. Sauce grades. Recomputed independently (score = round(100 x (0.3 amount + 0.5 coverage +
-- 0.2 clean)), amount = 1 - |pours - 3| / 3, clean = 1 - crust - 2 off):
--   clean    3 pours at r 0.4 (90, 210, 330 deg), circles r 0.3, 0.5, 0.7: 97, coverage 0.956472
--   sparse   1 pour at the centre, circles r 0.2, 0.4, 0.6, 0.75:           51, coverage 0.434310
--   half     3 pours on the right, arcs -80..80 deg at the same radii:       74, coverage 0.532845
--   heavy    6 pours at r 0.45, circles as sparse:                          68, coverage 0.998870
--   spilled  3 pours as clean, circles r 0.3, 0.6, 0.9 and 1.1 (in halves):  87, off 0.038872
--   unspread 3 pours as clean, no spread:                                   69, coverage 0.376271
-- Ceilings from the coverage: sparse 35 + 65 x 0.36862 = 58.96 -> 59; half 35 + 65 x 0.56569 =
-- 71.77 -> 72; unspread 35 + 65 x 0.25254 = 51.42 -> 51; the rest over 0.75 -> 100.
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local six = {}
for k = 0, 5 do
	six[k + 1] = P(0.45 * math.cos(math.rad(60 * k)), 0.45 * math.sin(math.rad(60 * k)))
end
local wide = circle(1.1)
local cases = {
	clean = sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) }),
	sparse = sauceOf({ P(0, 0) }, { circle(0.2), circle(0.4), circle(0.6), circle(0.75) }),
	half = sauceOf({ P(0.3, 0), P(0.45, 0.4), P(0.45, -0.4) }, { arc(0.2, -80, 80), arc(0.4, -80, 80), arc(0.6, -80, 80), arc(0.75, -80, 80) }),
	heavy = sauceOf(six, { circle(0.2), circle(0.4), circle(0.6), circle(0.75) }),
	spilled = sauceOf(tri, { circle(0.3), circle(0.6), circle(0.9), slice(wide, 1, 21), slice(wide, 21, 41) }),
	unspread = sauceOf(tri, {}),
}
local want = {
	clean = { 97, 0.956472, 0, 100, "" },
	sparse = { 51, 0.434310, 0, 59, "Not enough sauce|Bare spots in the sauce|Sauce on the crust" },
	half = { 74, 0.532845, 0, 72, "Bare spots in the sauce|Sauce on the crust" },
	heavy = { 68, 0.998870, 0, 100, "Too much sauce|Sauce on the crust" },
	spilled = { 87, 0.771323, 0.038872, 100, "Bare spots in the sauce|Sauce spilled off the dough" },
	unspread = { 69, 0.376271, 0, 51, "Bare spots in the sauce" },
}
local grades = {}
for _, name in { "clean", "sparse", "half", "heavy", "spilled", "unspread" } do
	local g = MakeSauce.grade(cases[name])
	grades[name] = g
	local w = want[name]
	check("sauce " .. name .. ": score", g.score, w[1])
	near("sauce " .. name .. ": coverage", g.detail.coverage, w[2], 2e-6)
	near("sauce " .. name .. ": off the dough", g.detail.off, w[3], 2e-6)
	check("sauce " .. name .. ": ceiling", g.detail.ceiling, w[4])
	check("sauce " .. name .. ": notes", table.concat(g.notes, "|"), w[5])
	near("sauce " .. name .. ": one unit per pour, conserved", mass((MakeSauce.field(cases[name]))), (MakeSauce.counts(cases[name])), 1e-9)
	note(string.format("sauce %-8s score %3d coverage %.4f clean %.4f crust %.4f off %.4f ceiling %d", name, g.score, g.detail.coverage, g.detail.clean, g.detail.crust, g.detail.off, g.detail.ceiling))
end
check("sauce: four looks graded apart (sparse < half < spilled < clean)", grades.sparse.score < grades.half.score and grades.half.score < grades.spilled.score and grades.spilled.score < grades.clean.score, true)
-- No sauce: 0 (no amount, no coverage and no clean credit), held to 35, noted.
local none = MakeSauce.grade({ actions = {} })
check("sauce none: score", none.score, 0)
check("sauce none: notes", table.concat(none.notes, "|"), "No sauce")
check("sauce none: ceiling", none.detail.ceiling, 35)

-- 6. The step's minimum: a pour and a spread that moved sauce.
check("finish: nothing", MakeSauce.canFinish({ actions = {} }), false)
check("finish: pours only", MakeSauce.canFinish(cases.unspread), false)
check("finish: poured and spread", MakeSauce.canFinish(cases.clean), true)

-- 7. Spread and pour checks, before anything is stored.
do
	local s = sauceOf({ P(0, 0) }, {})
	local function refusedSpread(name: string, args: any, reason: string)
		local a, why = MakeSauce.validateSpread(s, args)
		check("spread " .. name .. ": refused", a, nil)
		check("spread " .. name .. ": reason", why, reason)
	end
	check("spread before a pour", select(2, MakeSauce.validateSpread({ actions = {} }, { points = { P(-0.3, 0), P(0.3, 0) } })), "pour some sauce first")
	refusedSpread("not a list", { points = 5 }, "bad spread")
	refusedSpread("one point", { points = { P(0, 0) } }, "spread too short")
	local long = {}
	for i = 1, 65 do
		long[i] = P(-0.3 + 0.6 * i / 65, 0)
	end
	refusedSpread("65 points", { points = long }, "spread too long")
	local stuffed = { P(-0.3, 0), P(0.3, 0) } :: any
	stuffed.extra = true
	refusedSpread("stuffed with a key", { points = stuffed }, "bad spread")
	refusedSpread("NaN point", { points = { P(0, 0), P(0 / 0, 0) } }, "spread out of range")
	refusedSpread("past the reach", { points = { P(0, 0), P(1.7, 0) } }, "spread out of range")
	refusedSpread("not a point", { points = { P(0, 0), "x" } }, "spread out of range")
	refusedSpread("0.1 long", { points = { P(-0.05, 0), P(0.05, 0) } }, "spread too short")
	-- 6.9 of travel (a full circle at r 1.1) is past maxSpread 6.
	refusedSpread("past maxSpread", { points = circle(1.1) }, "spread too long")
	refusedSpread("over bare dough", { points = { P(-0.8, -0.5), P(-0.3, -0.8) } }, "spread missed the sauce")
	local ok = MakeSauce.validateSpread(s, { points = { P(-0.3, 0), P(0.3, 0) } })
	check("spread across the pour accepted", ok ~= nil and ok.kind, "spread")
	local function refusedPour(name: string, args: any, sauce: any, reason: string)
		local a, why = MakeSauce.validatePour(sauce, args)
		check("pour " .. name .. ": refused", a, nil)
		check("pour " .. name .. ": reason", why, reason)
	end
	refusedPour("NaN", { x = 0 / 0, y = 0 }, s, "pour off the dough")
	refusedPour("string", { x = "0", y = 0 }, s, "pour off the dough")
	refusedPour("past the edge", { x = 0.7, y = 0.7 }, s, "pour off the dough")
	refusedPour("seventh ladle", { x = 0, y = 0 }, cases.heavy, "too many ladles")
	check("pour at the edge accepted", MakeSauce.validatePour(s, { x = 0.95, y = 0 }) ~= nil, true)
end

-- 8. Cheese batch check.
do
	local empty = { strokes = {} }
	local function refused(name: string, cheese: any, args: any, reason: string)
		local points, _, why = MakeCheese.validate(cheese, args)
		check("cheese " .. name .. ": refused", points, nil)
		check("cheese " .. name .. ": reason", why, reason)
	end
	refused("not a list", empty, { points = "x" }, "bad cheese")
	refused("empty", empty, { points = {} }, "no cheese")
	local nine = {}
	for i = 1, 9 do
		nine[i] = P(0.02 * i, 0)
	end
	refused("nine at once", empty, { points = nine }, "too many pinches at once")
	local stuffed = { P(0, 0) } :: any
	stuffed[3] = P(0, 0)
	refused("a hole in the list", empty, { points = stuffed }, "bad cheese")
	local keyed = { P(0, 0) } :: any
	keyed.x = 1
	refused("stuffed with a key", empty, { points = keyed }, "bad cheese")
	refused("not a point", empty, { points = { 5 } }, "bad cheese")
	refused("newStroke not a boolean", empty, { points = { P(0, 0) }, newStroke = "yes" }, "bad cheese")
	refused("NaN", empty, { points = { P(0 / 0, 0) } }, "bad cheese")
	refused("past the reach", empty, { points = { P(1.6, 0) } }, "cheese out of reach")
	refused("too far apart", empty, { points = { P(0, 0), P(0.3, 0) } }, "pinches too far apart")
	local full = { strokes = {} }
	for s = 1, 6 do
		local stroke = {}
		for i = 1, 8 do
			stroke[i] = P(0, 0)
		end
		full.strokes[s] = stroke
	end
	check("cheese: 48 held", MakeCheese.count(full), 48)
	refused("past the cap", full, { points = { P(0, 0) }, newStroke = true }, "too much cheese")
	-- A first batch starts a stroke even without newStroke; a later one continues unless asked.
	local pts, newStroke = MakeCheese.validate(empty, { points = { P(0, 0) } })
	check("cheese: first batch starts a stroke", newStroke, true)
	local held = { strokes = { { P(0, 0) } } }
	local _, continues = MakeCheese.validate(held, { points = { P(0.2, 0) } })
	check("cheese: a later batch continues", continues, false)
	-- Across the join: 0.2 from the held stroke's last pinch is fine, 0.3 is not.
	check("cheese: join 0.3 refused", select(3, MakeCheese.validate(held, { points = { P(0.3, 0) } })), "pinches too far apart")
	check("cheese: join ignored on a new stroke", select(3, MakeCheese.validate(held, { points = { P(0.5, 0) }, newStroke = true })), nil)
	check("cheese: canFinish empty", MakeCheese.canFinish(empty), false)
	MakeCheese.add(empty, pts :: any, newStroke)
	check("cheese: canFinish one", MakeCheese.canFinish(empty), true)
	-- The stored copy holds only x and y.
	local copy = MakeCheese.validate({ strokes = {} }, { points = { { x = 0.1, y = 0.2, junk = 1 } } })
	check("cheese: clean copy", copy ~= nil and copy[1].junk, nil)
end

-- 9. Cheese grades. Clean: one pinch on each of the 24 sauce-cell centroids. Sparse: the 8 inner
-- centroids (count 1 - 16 / 24 = 1/3; "Not enough cheese"). Clustered: 24 pinches on a 6 x 4 grid
-- in one quarter (x 0.15..0.6, y 0.15..0.51, all inside 0.84): the count is full but the spread
-- is short ("Cheese patchy, with bare parts"), and the ceiling follows the spread on the sauce's
-- ramp. Scores are PrepFood.cheeseScore's, read.
local function oneEach(list: { any }): any
	local strokes = {}
	for i, p in list do
		strokes[i] = { p }
	end
	return { strokes = strokes }
end
local cleanCheese = oneEach(table.move(PrepFood.centroids, 1, 24, 1, {}))
local sparseCheese = oneEach(table.move(PrepFood.centroids, 1, 8, 1, {}))
local bunch = {}
for i = 0, 5 do
	for j = 0, 3 do
		table.insert(bunch, P(0.15 + 0.09 * i, 0.15 + 0.12 * j))
	end
end
local clusteredCheese = oneEach(bunch)
local cheeseGrades = {}
for name, c in { clean = cleanCheese, sparse = sparseCheese, clustered = clusteredCheese } do
	local g = MakeCheese.grade(c)
	cheeseGrades[name] = g
	check("cheese " .. name .. ": score is PrepFood's", g.score, (PrepFood.cheeseScore(MakeCheese.pinches(c))))
	check("cheese " .. name .. ": ceiling on the spread", g.detail.ceiling, MakeSauce.ceiling(g.detail.spread))
	note(string.format("cheese %-9s score %3d inside %d spread %.4f ceiling %d notes %s", name, g.score, g.detail.inside, g.detail.spread, g.detail.ceiling, table.concat(g.notes, "|")))
end
check("cheese clean: 24 inside", cheeseGrades.clean.detail.inside, 24)
check("cheese clean: no notes", #cheeseGrades.clean.notes, 0)
check("cheese clean: no ceiling", cheeseGrades.clean.detail.ceiling, 100)
check("cheese sparse: 8 inside", cheeseGrades.sparse.detail.inside, 8)
check("cheese sparse: noted", has(cheeseGrades.sparse.notes, "Not enough cheese"), true)
check("cheese sparse: patchy too (only the inner ring covered)", has(cheeseGrades.sparse.notes, "Cheese patchy, with bare parts"), true)
check("cheese clustered: 24 inside", cheeseGrades.clustered.detail.inside, 24)
check("cheese clustered: bunched", has(cheeseGrades.clustered.notes, "Cheese patchy, with bare parts"), true)
check("cheese clustered: held under 100", cheeseGrades.clustered.detail.ceiling < 100, true)
check("cheese: clean beats clustered and sparse", cheeseGrades.clean.score > cheeseGrades.clustered.score and cheeseGrades.clean.score > cheeseGrades.sparse.score, true)
local noCheese = MakeCheese.grade({ strokes = {} })
check("cheese none: score", noCheese.score, 0)
check("cheese none: notes", table.concat(noCheese.notes, "|"), "No cheese")
check("cheese none: ceiling", noCheese.detail.ceiling, 35)
local crusty = MakeCheese.grade(oneEach({ P(0.9, 0), P(1.2, 0) }))
check("cheese on the crust and off: notes", has(crusty.notes, "Cheese on the crust") and has(crusty.notes, "Cheese fell off the dough"), true)

-- 10. The Make part of the order grade: the mean of Dough, Sauce, Cheese (and Toppings when the
-- ticket has any), held by the lower coverage ceiling. Dough here is the clean test-hook dough
-- (100, make_check 6). With C = the clean cheese score:
--   clean sauce:  (100 + 97 + C) / 3, no ceiling under it;
--   sparse sauce: (100 + 51 + C) / 3 >= 151 / 3 = 50.3 ... above 59 once C >= 27: held to 59;
--   clustered cheese with clean sauce: held to the cheese ceiling when it is under the mean.
local function cleanDough(): any
	local m = MakeDough.new()
	local grid = {}
	for gx = -7, 7 do
		local stroke = {}
		for gy = -7, 7 do
			local p = P(gx * 0.15, gy * 0.15)
			if p.x * p.x + p.y * p.y <= 0.76 * 0.76 then
				table.insert(stroke, p)
			end
		end
		table.insert(grid, stroke)
	end
	m.flour = grid
	m.placed = true
	local function line(deg: number): any
		local a = math.rad(deg)
		return { x1 = -1.2 * math.cos(a), y1 = -1.2 * math.sin(a), x2 = 1.2 * math.cos(a), y2 = 1.2 * math.sin(a) }
	end
	for _, deg in { 0, 90, 45, 135, 90, 0, 135, 45 } do
		table.insert(m.strokes, line(deg))
	end
	return m
end
local base = cleanDough()
check("make: clean dough is 100", MakeDough.grade(base).score, 100)
local C = cheeseGrades.clean.score
local cheeseOrder = Recipes.ById.cheese
local function makeWith(sauce: any, cheese: any): any
	local m = cleanDough()
	m.sauce, m.cheese = sauce, cheese
	return m
end
local gClean = Scoring.make(cheeseOrder, makeWith(cases.clean, cleanCheese), {})
check("make clean: mean of three", gClean.score, math.floor((100 + 97 + C) / 3 + 0.5 + 1e-9))
check("make clean: no hold", gClean.score, gClean.detail.mean)
check("make clean: C is at least 27 (so the holds below apply)", C >= 27, true)
local gSparse = Scoring.make(cheeseOrder, makeWith(cases.sparse, cleanCheese), {})
check("make sparse sauce: held to 59", gSparse.score, 59)
check("make sparse sauce: hold noted first", gSparse.notes[1], "Most of the pizza has no sauce: Make held to 59")
check("make sparse sauce: step notes kept", has(gSparse.notes, "Bare spots in the sauce"), true)
local cc = cheeseGrades.clustered.detail.ceiling
local gBunch = Scoring.make(cheeseOrder, makeWith(cases.clean, clusteredCheese), {})
local bunchMean = math.floor((100 + 97 + cheeseGrades.clustered.score) / 3 + 0.5 + 1e-9)
check("make clustered cheese: mean", gBunch.detail.mean, bunchMean)
check("make clustered cheese: held to the cheese ceiling", gBunch.score, math.min(bunchMean, cc))
if cc < bunchMean then
	check("make clustered cheese: hold noted", gBunch.notes[1], string.format("Cheese bunched or missing: Make held to %d", cc))
end
-- Pepperoni: eight perfect pieces (Toppings 100), the mean of four.
local pep = Recipes.ById.pepperoni
local pieces = {}
for i = 1, 8 do
	local a = math.rad(22.5 + (i - 1) * 45)
	pieces[i] = { ingredient = "pepperoni", x = math.cos(a) * 0.5, y = -math.sin(a) * 0.5 }
end
check("make pepperoni: mean of four", Scoring.make(pep, makeWith(cases.clean, cleanCheese), pieces).score, math.floor((100 + 97 + C + 100) / 4 + 0.5 + 1e-9))
-- A record from before this slice (no sauce or cheese) grades as empty steps, without error.
local old = cleanDough()
old.sauce, old.cheese = nil, nil
check("make: old record grades (100 + 0 + 0) / 3 = 33", Scoring.make(cheeseOrder, old, {}).score, 33)
note(string.format("make: clean %d (cheese %d); sparse sauce %d (mean %d); clustered cheese %d (mean %d, ceiling %d)", gClean.score, C, gSparse.score, gSparse.detail.mean, gBunch.score, gBunch.detail.mean, cc))

-- 11. Server actions through ShiftService.apply; every refusal leaves the pizza as it was.
local pizza = { id = 4, ticketId = 1, stage = "topping", make = cleanDough(), toppings = {}, cuts = {} }
local session = { shift = { pizzas = { [4] = pizza }, ovens = { false, false }, ingredients = {} } } :: any
local function act(action: string, args: any): (boolean, string?)
	args.pizzaId = args.pizzaId or 4
	return ShiftService.apply(session, action, args)
end
local function snapshot(): string
	local m = pizza.make
	local parts = { m.step }
	for _, a in m.sauce.actions do
		table.insert(parts, if a.kind == "pour" then string.format("p%.3f,%.3f", a.x, a.y) else "s" .. #a.points)
	end
	for _, s in m.cheese.strokes do
		table.insert(parts, "c" .. #s)
	end
	return table.concat(parts, "|")
end
local function refused(name: string, action: string, args: any, want: string)
	local before = snapshot()
	local ok, reason = act(action, args)
	check("server " .. name .. ": refused", ok, false)
	check("server " .. name .. ": reason", reason, want)
	check("server " .. name .. ": nothing changed", snapshot(), before)
end
refused("pour on the dough step", "pourSauce", { x = 0, y = 0 }, "not at the sauce step")
refused("cheese on the dough step", "addCheese", { points = { P(0, 0) } }, "not at the cheese step")
check("server: dough finished", (act("finishDough", { from = "dough" })), true)
check("server: at the sauce", pizza.make.step, "sauce")
refused("finish sauce with none", "finishSauce", { from = "sauce" }, "pour and spread the sauce first")
refused("finish sauce from the wrong step", "finishSauce", { from = "cheese" }, "bad step")
refused("undo with nothing", "undoSauce", {}, "nothing to undo")
refused("spread before a pour", "spreadSauce", { points = { P(-0.3, 0), P(0.3, 0) } }, "pour some sauce first")
refused("pour off the dough", "pourSauce", { x = 1, y = 0 }, "pour off the dough")
refused("cheese at the sauce step", "addCheese", { points = { P(0, 0) } }, "not at the cheese step")
refused("oven at the sauce step", "sendToOven", {}, "not at the toppings step")
for _, p in tri do
	check("server: pour accepted", (act("pourSauce", { x = p.x, y = p.y })), true)
end
refused("finish sauce unspread", "finishSauce", { from = "sauce" }, "pour and spread the sauce first")
refused("spread over bare dough", "spreadSauce", { points = { P(-0.9, -0.1), P(-0.8, -0.4) } }, "spread missed the sauce")
local stuffedSpread = { P(-0.3, 0), P(0.3, 0) } :: any
stuffedSpread.n = 1
refused("stuffed spread", "spreadSauce", { points = stuffedSpread }, "bad spread")
check("server: spread accepted", (act("spreadSauce", { points = circle(0.5) })), true)
check("server: undo takes the spread back", (act("undoSauce", {})), true)
check("server: three pours left", snapshot(), "sauce|p0.000,0.400|p-0.346,-0.200|p0.346,-0.200")
for _, r in { 0.3, 0.5, 0.7 } do
	act("spreadSauce", { points = circle(r) })
end
check("server: stored like the clean case", MakeSauce.grade(pizza.make.sauce).score, 97)
check("server: sauce finished", (act("finishSauce", { from = "sauce" })), true)
check("server: at the cheese", pizza.make.step, "cheese")
refused("sauce after", "pourSauce", { x = 0, y = 0 }, "sauce is done")
refused("undo sauce after", "undoSauce", {}, "sauce is done")
refused("finish cheese with none", "finishCheese", { from = "cheese" }, "sprinkle some cheese first")
refused("undo cheese with nothing", "undoCheese", {}, "nothing to undo")
refused("refused first batch", "addCheese", { points = { P(2, 0) }, newStroke = true }, "cheese out of reach")
check("server: refused first batch made no stroke", #pizza.make.cheese.strokes, 0)
refused("nine pinches", "addCheese", { points = (function()
	local t = {}
	for i = 1, 9 do
		t[i] = P(0.02 * i, 0)
	end
	return t
end)() }, "too many pinches at once")
check("server: first batch", (act("addCheese", { points = { P(0, 0), P(0.2, 0) }, newStroke = true })), true)
check("server: second batch continues", (act("addCheese", { points = { P(0.4, 0) } })), true)
refused("join too far", "addCheese", { points = { P(0.7, 0) } }, "pinches too far apart")
check("server: new stroke", (act("addCheese", { points = { P(-0.4, 0.3) }, newStroke = true })), true)
check("server: two strokes", snapshot():match("c3|c1$") ~= nil, true)
check("server: undo removes the whole last sprinkle", (act("undoCheese", {})), true)
check("server: one stroke of three", snapshot():match("|c3$") ~= nil, true)
check("server: cheese finished", (act("finishCheese", { from = "cheese" })), true)
check("server: at the toppings", pizza.make.step, "toppings")
refused("cheese after", "addCheese", { points = { P(0, 0) }, newStroke = true }, "cheese is done")
check("server: cheese order goes to the oven", (act("sendToOven", {})), true)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("sauce and cheese checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

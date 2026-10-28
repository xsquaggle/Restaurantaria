-- Checks for the grade split (2026-10-27; plan rev 6, 5.1 to 5.3, with the rev 7 amendment):
-- Make 50 / Bake 30 / Cut 20, Service joining the pay once, the Make ceilings (coverage, plan
-- 5.3d) on the whole order grade, the completeness ceilings (plan 5.3c: pours / 3, pinches on the
-- dough / 24, dough area / the full round's), each switch in Config.Grade, and the before / after
-- table for the staged cases (slice 2's join against the split). Step scores come from the
-- step models (sauce_cheese_check and make_check cover them); the join, the ceilings, the pay
-- and the XP are worked here by hand from those step scores, apart from the code under test, and
-- the printed table is what handoff-make-3.md quotes. Run offline with tests/offline/run.py.
-- Arithmetic only: proposals, not balance decisions.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local MakeCheese = require(Shared.MakeCheese)
local MakeDough = require(Shared.MakeDough)
local MakeSauce = require(Shared.MakeSauce)
local PrepFood = require(Shared.PrepFood)
local PrepGeometry = require(Shared.PrepGeometry)
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
local function note(line: string)
	table.insert(report, line)
end
local function P(x: number, y: number)
	return { x = x, y = y }
end
local function whole(x: number): number
	return math.floor(x + 0.5 + 1e-9)
end

-- 1. Defaults: the proposal as built.
local defaults = table.clone(Config.Grade)
check("defaults: split join", defaults.join, "split")
check("defaults: weights 50 / 30 / 20", string.format("%.2f/%.2f/%.2f", defaults.weights.make, defaults.weights.bake, defaults.weights.cut), "0.50/0.30/0.20")
check("defaults: weights sum to 1", math.abs(defaults.weights.make + defaults.weights.bake + defaults.weights.cut - 1) < 1e-12, true)
check("defaults: ceilings on the order grade", defaults.ceilingsOn, "order")
check("defaults: completeness ceilings on", defaults.completeness, true)
check("defaults: dough completeness on", defaults.doughCompleteness, true)
check("defaults: service share 0.25", defaults.serviceShare, 0.25)
local function setGrade(over: { [string]: any })
	for k, v in defaults do
		Config.Grade[k] = v
	end
	for k, v in over do
		Config.Grade[k] = v
	end
end
local SLICE2 = { join = "average", ceilingsOn = "make", completeness = false }
local COVER_ONLY = { completeness = false }

-- 2. The staged cases (the same records as sauce_cheese_check and the captures).
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
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local six = {}
for k = 0, 5 do
	six[k + 1] = P(0.45 * math.cos(math.rad(60 * k)), 0.45 * math.sin(math.rad(60 * k)))
end
local wide = circle(1.1)
local sauces = {
	clean = sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) }),
	sparse = sauceOf({ P(0, 0) }, { circle(0.2), circle(0.4), circle(0.6), circle(0.75) }),
	half = sauceOf({ P(0.3, 0), P(0.45, 0.4), P(0.45, -0.4) }, { arc(0.2, -80, 80), arc(0.4, -80, 80), arc(0.6, -80, 80), arc(0.75, -80, 80) }),
	heavy = sauceOf(six, { circle(0.2), circle(0.4), circle(0.6), circle(0.75) }),
	spilled = sauceOf(tri, { circle(0.3), circle(0.6), circle(0.9), slice(wide, 1, 21), slice(wide, 21, 41) }),
}
local function oneEach(list: { any }): any
	local strokes = {}
	for i, p in list do
		strokes[i] = { p }
	end
	return { strokes = strokes }
end
local bunch = {}
for i = 0, 5 do
	for j = 0, 3 do
		table.insert(bunch, P(0.15 + 0.09 * i, 0.15 + 0.12 * j))
	end
end
local cheeses = {
	clean = oneEach(table.move(PrepFood.centroids, 1, 24, 1, {})),
	sparse = oneEach(table.move(PrepFood.centroids, 1, 8, 1, {})),
	clustered = oneEach(bunch),
}
local function flouredDough(): any
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
	return m
end
local function line(deg: number): any
	local a = math.rad(deg)
	return { x1 = -1.2 * math.cos(a), y1 = -1.2 * math.sin(a), x2 = 1.2 * math.cos(a), y2 = 1.2 * math.sin(a) }
end
local function cleanDough(): any
	local m = flouredDough()
	for _, deg in { 90, 0, 90 } do
		table.insert(m.strokes, line(deg))
	end
	return m
end
-- The smallest dough Next allows: one full pass along x, 0.60 x 0.56 (plan row 47's under-rolled
-- case). Until 2026-10-28 this was the worst oval, every stroke one way to 1.1 x 0.35; the
-- three-pass roll model grows both axes, so that oval can no longer be rolled.
local function ovalDough(): any
	local m = flouredDough()
	table.insert(m.strokes, line(0))
	return m
end
local oval = PrepGeometry.axes(MakeDough.shape(ovalDough()))
check("one pass: long axis 0.60", math.abs(oval.major - 0.60) < 1e-9, true)
note(string.format("one-pass dough: %.4f x %.4f, area share %.4f", oval.major, oval.minor, oval.major * oval.minor / 0.9025))
check("one pass: short axis 0.56", math.abs(oval.minor - 0.56) < 1e-9, true)

local cheeseOrder = Recipes.ById.cheese
local function makeOf(dough: any, sauce: any, cheese: any): any
	dough.sauce, dough.cheese = sauce, cheese
	return dough
end
local perfect = { score = 100, notes = {} }
local function grade(score: number): any
	return { score = score, notes = {} }
end

-- Each case: the made pizza and the other parts' scores (Bake, Cut, Wait).
type Case = { name: string, make: any, bake: number, cut: number, wait: number }
local cases: { Case } = {
	{ name = "clean", make = makeOf(cleanDough(), sauces.clean, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "sparse sauce", make = makeOf(cleanDough(), sauces.sparse, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "half sauce", make = makeOf(cleanDough(), sauces.half, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "heavy sauce", make = makeOf(cleanDough(), sauces.heavy, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "spilled sauce", make = makeOf(cleanDough(), sauces.spilled, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "sparse cheese", make = makeOf(cleanDough(), sauces.clean, cheeses.sparse), bake = 100, cut = 100, wait = 100 },
	{ name = "clustered cheese", make = makeOf(cleanDough(), sauces.clean, cheeses.clustered), bake = 100, cut = 100, wait = 100 },
	{ name = "one-pass dough", make = makeOf(ovalDough(), sauces.clean, cheeses.clean), bake = 100, cut = 100, wait = 100 },
	{ name = "Lawson's real cuts (Cut 89)", make = makeOf(cleanDough(), sauces.clean, cheeses.clean), bake = 100, cut = 89, wait = 100 },
	{ name = "clean, served slowly (Wait 40)", make = makeOf(cleanDough(), sauces.clean, cheeses.clean), bake = 100, cut = 100, wait = 40 },
	{ name = "clean, burnt (Bake 0)", make = makeOf(cleanDough(), sauces.clean, cheeses.clean), bake = 0, cut = 100, wait = 100 },
}

-- 3. The join worked by hand (not Scoring's code): from the step scores and the coverage /
-- completeness measures the step models report.
local function ramp(e: number): number
	return whole(35 + 65 * math.clamp((e - 0.25) / 0.5, 0, 1))
end
type Hand = { mean: number, make: number, weighted: number, grade: number, coins: number, xp: number, low: number }
local function byHand(c: Case, setting: string): Hand
	local d = MakeDough.grade(c.make)
	local s = MakeSauce.grade(c.make.sauce)
	local ch = MakeCheese.grade(c.make.cheese)
	local mean = whole((d.score + s.score + ch.score) / 3)
	local low = math.min(ramp(s.detail.coverage), ramp(ch.detail.spread))
	if setting == "full" then
		local pours = 0
		for _, a in c.make.sauce.actions do
			if a.kind == "pour" and a.x * a.x + a.y * a.y <= 0.9025 then
				pours += 1
			end
		end
		local e = PrepGeometry.axes(MakeDough.shape(c.make))
		low = math.min(low, ramp(math.min(1, pours / 3)), ramp(math.min(1, (ch.detail.inside + ch.detail.crust) / 24)), ramp(math.min(1, e.major * e.minor / 0.9025)))
	end
	if setting == "slice2" then
		local make = math.min(mean, low)
		local g = whole((c.wait + make + c.bake + c.cut) / 4)
		return { mean = mean, make = make, weighted = g, grade = g, coins = whole(12 * g / 100), xp = whole(10 * g / 100), low = low }
	end
	local weighted = whole(0.5 * mean + 0.3 * c.bake + 0.2 * c.cut)
	local g = math.min(weighted, low)
	local paid = whole(g * (0.75 + 0.25 * c.wait / 100))
	return { mean = mean, make = mean, weighted = weighted, grade = g, coins = whole(12 * paid / 100), xp = whole(10 * g / 100), low = low }
end

local function viaCode(c: Case): (any, Scoring.Order)
	local make = Scoring.make(cheeseOrder, c.make, {})
	return make, Scoring.order(grade(c.wait), make, grade(c.bake), grade(c.cut))
end

local rows = {}
for _, c in cases do
	local out = {}
	for _, setting in { "slice2", "cover", "full" } do
		setGrade(if setting == "slice2" then SLICE2 elseif setting == "cover" then COVER_ONLY else {})
		local make, o = viaCode(c)
		local h = byHand(c, setting)
		local label = c.name .. " [" .. setting .. "]"
		check(label .. ": Make", make.score, h.make)
		check(label .. ": weighted", o.weighted, h.weighted)
		check(label .. ": grade", o.grade, h.grade)
		check(label .. ": coins", o.coins, h.coins)
		check(label .. ": XP", o.xp, h.xp)
		if setting ~= "slice2" then
			check(label .. ": held only when a ceiling is under the weighted score", o.held ~= nil, h.low < h.weighted)
		end
		out[setting] = { make = make, o = o }
	end
	table.insert(rows, { case = c, out = out })
end
setGrade({})

-- 4. Worked rows in the plan's form (checked against the code above, printed for the hand-off).
local function ceilingText(make: any): string
	local parts = {}
	for _, cl in make.detail.ceilings do
		table.insert(parts, cl.name .. " " .. cl.value)
	end
	return if #parts > 0 then table.concat(parts, ", ") else "none"
end
note("| Case | Dough / Sauce / Cheese | Make mean | Bake | Cut | Wait | Before (slice 2): Make held, grade, coins, XP | After, coverage only: weighted, grade, coins, XP | After, full proposal: ceilings under 100 | weighted | grade | coins | XP |")
note("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for _, r in rows do
	local c, s2, cv, fu = r.case, r.out.slice2, r.out.cover, r.out.full
	local d = fu.make.detail
	note(string.format("| %s | %d / %d / %d | %d | %d | %d | %d | %d, **%d**, %d, %d | %d, **%d**, %d, %d | %s | %d | **%d** | %d | %d |",
		c.name, d.dough.score, d.sauce.score, d.cheese.score, d.mean, c.bake, c.cut, c.wait,
		s2.make.score, s2.o.grade, s2.o.coins, s2.o.xp,
		cv.o.weighted, cv.o.grade, cv.o.coins, cv.o.xp,
		ceilingText(fu.make), fu.o.weighted, fu.o.grade, fu.o.coins, fu.o.xp))
end

-- 5. Spot values worked out in full (so a reader can follow one row without the code).
local function row(name: string): any
	for _, r in rows do
		if r.case.name == name then
			return r.out
		end
	end
	error(name)
end
-- Clean: Dough 100, Sauce 97, Cheese 100 -> mean 99; 0.5 x 99 + 30 + 20 = 99.5 -> 100 (guarded
-- rounding). Slice 2: (100 + 99 + 100 + 100) / 4 = 99.75 -> 100. 12 coins, 10 XP either way.
check("clean: split grade", row("clean").full.o.grade, 100)
check("clean: slice 2 grade", row("clean").slice2.o.grade, 100)
check("clean: coins", row("clean").full.o.coins, 12)
-- Sparse sauce: one ladle. Coverage 0.434 -> ceiling 59; one pour of three -> c 0.333 -> 46. With
-- completeness on, the grade is held to 46; coverage only, 59.
check("sparse: coverage ceiling 59", row("sparse sauce").cover.o.grade, 59)
check("sparse: completeness ceiling 46", row("sparse sauce").full.o.grade, 46)
check("sparse: held by the sauce amount", row("sparse sauce").full.o.held.name, "sauceAmount")
-- Sparse cheese: 8 pinches. Spread 0.333 -> 46; 8 of 24 -> 46 as well (tie: coverage first).
check("sparse cheese: grade 46", row("sparse cheese").full.o.grade, 46)
check("sparse cheese: tie names the coverage ceiling", row("sparse cheese").full.o.held.name, "cheeseCover")
-- Clustered cheese: spread 0.25 -> 35; 24 pinches -> no amount ceiling.
check("clustered: grade 35", row("clustered cheese").full.o.grade, 35)
-- One pass: area 0.60 x 0.56 / 0.9025 = 0.3723 -> 35 + 65 x 0.2446 = 50.90 -> 51 (plan row 47).
check("one pass: dough completeness ceiling 51", row("one-pass dough").full.o.grade, 51)
check("one pass: no ceiling with completeness off", row("one-pass dough").cover.o.held, nil)
-- Lawson's cuts (89): 0.5 x 99 + 30 + 17.8 = 97.3 -> 97; slice 2: (100 + 99 + 100 + 89) / 4 = 97.
check("cuts 89: split grade 97", row("Lawson's real cuts (Cut 89)").full.o.grade, 97)
check("cuts 89: slice 2 grade 97", row("Lawson's real cuts (Cut 89)").slice2.o.grade, 97)
-- Slow service (Wait 40): the grade stays 100 (service is not in it); paid 100 x 0.85 = 85 ->
-- 10 coins, XP 10. Slice 2: (40 + 99 + 100 + 100) / 4 = 84.75 -> 85, 10 coins, 9 XP.
check("slow: split grade", row("clean, served slowly (Wait 40)").full.o.grade, 100)
check("slow: split paid", row("clean, served slowly (Wait 40)").full.o.paid, 85)
check("slow: split coins", row("clean, served slowly (Wait 40)").full.o.coins, 10)
check("slow: split XP", row("clean, served slowly (Wait 40)").full.o.xp, 10)
check("slow: slice 2 XP", row("clean, served slowly (Wait 40)").slice2.o.xp, 9)
-- Burnt: 0.5 x 99 + 0 + 20 = 69.5 -> 70 (slice 2: 75). These rows feed a bare Bake 0 with no
-- food state, so no food hold applies here; the raw/burnt hold (slice 1) is section 10.
check("burnt: split grade 70", row("clean, burnt (Bake 0)").full.o.grade, 70)
check("burnt: slice 2 grade 75", row("clean, burnt (Bake 0)").slice2.o.grade, 75)

-- 6. The switches each do one thing.
setGrade({ ceilingsOn = "make" })
local mk, o = viaCode(cases[2])
check("switch make: Make held to the lowest ceiling", mk.score, 46)
check("switch make: hold note on Make", mk.notes[1], "Not enough sauce poured: Make held to 46")
check("switch make: order not held again", o.held, nil)
check("switch make: weighted from the held Make", o.weighted, whole(0.5 * 46 + 30 + 20))
setGrade({ doughCompleteness = false })
check("switch dough off: one-pass dough not held", (select(2, viaCode(cases[8]))).held, nil)
setGrade({ join = "average" })
local _, oa = viaCode(cases[10])
check("switch average: Wait back in the grade", oa.grade, whole((40 + 99 + 100 + 100) / 4))
check("switch average: no service on the pay", oa.paid, oa.grade)
setGrade({})

-- 7. Ceilings only lower: a case with every ceiling at 100 grades its weighted score, and no
-- ceiling ever raises a low weighted score.
local _, oc = viaCode(cases[1])
check("ceilings: clean has none", #(Scoring.make(cheeseOrder, cases[1].make, {}).detail.ceilings), 0)
check("ceilings: clean grade = weighted", oc.grade, oc.weighted)
local low = Scoring.order(grade(0), grade(0), grade(0), grade(0))
check("ceilings: all zero grades 0", low.grade, 0)
check("ceilings: all zero pays 0", low.coins, 0)
-- A pour off the dough does not count towards the amount.
local off = makeOf(cleanDough(), sauceOf({ P(0, 0), P(0, 0), P(1.0, 0) }, { circle(0.3) }), cheeses.clean)
local offCeil = 0
for _, cl in Scoring.make(cheeseOrder, off, {}).detail.ceilings do
	if cl.name == "sauceAmount" then
		offCeil = cl.value
	end
end
check("completeness: a pour at r 1.0 is not on the dough (2 of 3 -> 35 + 65 x 0.8333 = 89)", offCeil, 89)

-- 8. The server's serve: the result keeps every part, the grade, the hold and the rewards.
local cutsPerfect = {}
for _, deg in { 0, 45, 90, 135 } do
	table.insert(cutsPerfect, line(deg))
end
local pz = { id = 71, ticketId = 70, stage = "cutting", make = makeOf(cleanDough(), sauces.sparse, cheeses.clean), toppings = {}, cuts = cutsPerfect, bakeSeconds = Config.Oven.targets.regular }
local session = {
	shift = {
		customers = { { id = 70, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = workspace:GetServerTimeNow() } },
		pizzas = { [71] = pz },
		ovens = { false, false },
		ingredients = {},
		nextArrival = 1,
		customerCount = 5,
		tips = 0,
		xp = 0,
		tutorial = false,
	},
} :: any
check("serve: accepted", (ShiftService.apply(session, "serve", { pizzaId = 71 })), true)
local r = session.shift.customers[1].result
check("serve: cut perfect", r.cut.score, 100)
check("serve: bake perfect", r.bake.score, 100)
check("serve: join recorded", r.join, "split")
check("serve: grade held to 46", r.overall, 46)
check("serve: weighted kept", r.weighted, whole(0.5 * r.make.score + 50))
check("serve: hold recorded", r.held and r.held.name, "sauceAmount")
check("serve: hold note leads Make's notes", r.make.notes[1], "Not enough sauce poured: grade held to 46")
check("serve: coins from the paid grade", r.tip, whole(12 * r.paid / 100))
check("serve: shift coins", session.shift.tips, r.tip)
check("serve: shift XP from the grade", session.shift.xp, whole(10 * 46 / 100))
note(string.format("serve: sparse sauce, wait %d -> grade %d (weighted %d, held by %s), paid %d, coins %d, XP %d", r.wait.score, r.overall, r.weighted, r.held.name, r.paid, r.tip, r.xp))

-- 9. Slice 1 (2026-10-27): the topping completeness safeguard (Astra r14 P1). For each
-- ingredient the ticket asks for, the right pieces inside the asked region against the count
-- (capped at 1; wrong and extra pieces never count); the lowest share sets a ceiling on the same
-- ramp as the other completeness ceilings: 35 at a quarter or less, none from three quarters.
-- Pieces are dough-local; the made pizza is the clean round one (Dough 100, Sauce 97, Cheese 100),
-- Bake 100, Cut 100, Wait 100. Before = the safeguard off (today's rule), after = on.
check("defaults: topping completeness on", defaults.toppingCompleteness, true)
local function ring(ingredient: string, n: number, from: number, to: number, r: number?): { any }
	local out = {}
	for k = 0, n - 1 do
		local a = math.rad(from + (to - from) * (k + 0.5) / n)
		table.insert(out, { ingredient = ingredient, x = (r or 0.5) * math.cos(a), y = (r or 0.5) * math.sin(a) })
	end
	return out
end
local function join(...): { any }
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			table.insert(out, p)
		end
	end
	return out
end
-- Left half on screen: x < 0, i.e. angles 90..270 (y down); right: -90..90.
type TopCase = { name: string, recipe: string, pieces: { any }, e: number }
local topCases: { TopCase } = {
	{ name = "pepperoni 0/8", recipe = "pepperoni", pieces = {}, e = 0 },
	{ name = "pepperoni 1/8", recipe = "pepperoni", pieces = ring("pepperoni", 1, 0, 360), e = 1 / 8 },
	{ name = "pepperoni 6/8", recipe = "pepperoni", pieces = ring("pepperoni", 6, 0, 360), e = 6 / 8 },
	{ name = "pepperoni 8/8", recipe = "pepperoni", pieces = ring("pepperoni", 8, 0, 360), e = 1 },
	{ name = "pepperoni 12/8 (extra)", recipe = "pepperoni", pieces = ring("pepperoni", 12, 0, 360), e = 1 },
	{ name = "pepperoni 1/8 + 12 olives (wrong)", recipe = "pepperoni", pieces = join(ring("pepperoni", 1, 0, 360), ring("olive", 12, 0, 360, 0.3)), e = 1 / 8 },
	{ name = "half & half, halves swapped", recipe = "halfolive", pieces = join(ring("olive", 6, -80, 80), ring("pepperoni", 4, 100, 260)), e = 0 },
	{ name = "half & half, right", recipe = "halfolive", pieces = join(ring("olive", 6, 100, 260), ring("pepperoni", 4, -80, 80)), e = 1 },
	{ name = "garden, no peppers", recipe = "garden", pieces = ring("mushroom", 6, 0, 360), e = 0 },
	{ name = "garden, 6 mushrooms + 3 peppers", recipe = "garden", pieces = join(ring("mushroom", 6, 0, 360), ring("pepper", 3, 30, 390, 0.3)), e = 3 / 6 },
	{ name = "pepperoni basil, no basil", recipe = "pepbasil", pieces = ring("pepperoni", 6, 0, 360), e = 0 },
}
note("")
note("| Topping case | Toppings | Make (mean of 4) | Before: weighted, grade, coins, XP | Completeness | Ceiling | After: grade, coins, XP | Hold note |")
note("|---|---|---|---|---|---|---|---|")
local topRows = {}
for _, c in topCases do
	local recipe = Recipes.ById[c.recipe]
	local made = makeOf(cleanDough(), sauces.clean, cheeses.clean)
	setGrade({ toppingCompleteness = false })
	local mb = Scoring.make(recipe, made, c.pieces)
	local ob = Scoring.order(grade(100), mb, grade(100), grade(100))
	setGrade({})
	local ma = Scoring.make(recipe, made, c.pieces)
	local oa = Scoring.order(grade(100), ma, grade(100), grade(100))
	local tops = ma.detail.toppings
	-- By hand: the share and its ramp; the grade is the weighted score held by it.
	local ceil = ramp(c.e)
	check(c.name .. ": completeness", math.abs(tops.detail.completeness - c.e) < 1e-9, true)
	check(c.name .. ": Make mean unchanged by the safeguard", ma.score, mb.score)
	check(c.name .. ": before = weighted", ob.grade, ob.weighted)
	check(c.name .. ": after = weighted held by the ramp", oa.grade, math.min(oa.weighted, ceil))
	check(c.name .. ": coins from the grade", oa.coins, whole(12 * oa.grade / 100))
	check(c.name .. ": XP from the grade", oa.xp, whole(10 * oa.grade / 100))
	local held = if oa.held then oa.held.note else "none"
	topRows[c.name] = { before = ob, after = oa, make = ma }
	note(string.format("| %s | %d | %d | %d, **%d**, %d, %d | %.3f | %d | **%d**, %d, %d | %s |", c.name, tops.score, ma.score, ob.weighted, ob.grade, ob.coins, ob.xp, c.e, ceil, oa.grade, oa.coins, oa.xp, held))
end
-- The defect Astra found: one correct pepperoni of eight. Toppings 0.6 x 1/8 + 0.4 = 0.475 -> 48;
-- Make (100 + 97 + 100 + 48) / 4 = 86.25 -> 86; weighted 0.5 x 86 + 30 + 20 = 93 before. After:
-- 1/8 = 0.125 is under a quarter, so the grade is held to 35 (4 coins, 4 XP).
check("1/8 pepperoni: toppings 48", topRows["pepperoni 1/8"].make.detail.toppings.score, 48)
check("1/8 pepperoni: before 93", topRows["pepperoni 1/8"].before.grade, 93)
check("1/8 pepperoni: after held to 35", topRows["pepperoni 1/8"].after.grade, 35)
check("1/8 pepperoni: the hold names the food", topRows["pepperoni 1/8"].after.held.note, "Needed 8 pepperoni on the whole pizza, placed 1")
check("1/8 pepperoni + wrong olives: still 35", topRows["pepperoni 1/8 + 12 olives (wrong)"].after.grade, 35)
check("halves swapped: held to 35", topRows["half & half, halves swapped"].after.grade, 35)
check("garden without peppers: held to 35", topRows["garden, no peppers"].after.grade, 35)
check("garden without peppers: note names the missing ingredient", topRows["garden, no peppers"].after.held.note, "Needed 6 bell peppers on the whole pizza, placed 0")
check("pepperoni basil without basil: held to 35", topRows["pepperoni basil, no basil"].after.grade, 35)
-- 3 of 6 peppers: 0.5 -> 35 + 65 x 0.5 = 67.5 -> 68.
check("garden half the peppers: ceiling 68", topRows["garden, 6 mushrooms + 3 peppers"].after.grade, math.min(topRows["garden, 6 mushrooms + 3 peppers"].after.weighted, 68))
check("8/8: no hold", topRows["pepperoni 8/8"].after.held, nil)
check("6/8: no hold (three quarters is the ramp's top)", topRows["pepperoni 6/8"].after.held, nil)
check("12/8: extra pieces never raise completeness past 1", topRows["pepperoni 12/8 (extra)"].after.held, nil)

-- Dough-local pieces on an oval (slice 1): halves are what the player sees, the physical x of
-- toPizza(S, q). On the worst oval turned 60 degrees, q = (0.2, -0.6) has q.x > 0 but sits left
-- on screen: S q / 0.95 has x = (0.5375 x 0.2 - 0.3248 x 0.6) / 0.95 = -0.092.
local TURNED = PrepGeometry.shape(1.1, 0.35, math.rad(60))
local qL = PrepGeometry.toPizza(TURNED, P(0.2, -0.6))
check("oval halves: the stored point is physically left", qL.x < 0, true)
local leftOlives = {}
for _ = 1, 6 do
	table.insert(leftOlives, { ingredient = "olive", x = 0.2, y = -0.6 })
end
local half = Scoring.toppings(Recipes.ById.halfolive, join(leftOlives, ring("pepperoni", 0, 0, 0)), TURNED)
check("oval halves: no olive is called outside the left half", table.find(half.notes, "6 olives landed outside the left half"), nil)
check("oval halves: olive share 1, pepperoni share 0", half.detail.completeness, 0)
check("oval halves: the short ingredient is the pepperoni", half.detail.short.ingredient, "pepperoni")
-- A round dough: dough-local and pizza-local agree, so the grade is today's.
check("round dough: toppings unchanged", Scoring.toppings(Recipes.ById.pepperoni, ring("pepperoni", 8, 0, 360)).score, Scoring.toppings(Recipes.ById.pepperoni, ring("pepperoni", 8, 0, 360), Scoring.ROUND).score)

-- The server stores and checks dough-local positions: on the one-pass dough (0.60 x 0.56) a piece
-- at q = (0.8, 0) sits inside the sauce edge (0.84), drawn at x = 0.60 x 0.8 / 0.95 = 0.505;
-- q = (0.9, 0) is refused.
local ovalMade = makeOf(ovalDough(), sauces.clean, cheeses.clean)
ovalMade.step = "toppings"
local tp = { id = 81, ticketId = 80, stage = "topping", make = ovalMade, toppings = {}, cuts = {} }
local tSession = { shift = { customers = {}, pizzas = { [81] = tp }, ovens = { false, false }, ingredients = { "pepperoni" } } } :: any
check("server topping: q (0.8, 0) on the one-pass dough accepted", (ShiftService.apply(tSession, "placeTopping", { pizzaId = 81, ingredient = "pepperoni", x = 0.8, y = 0 })), true)
check("server topping: stored dough-local", tp.toppings[1] and tp.toppings[1].x, 0.8)
local okT, whyT = ShiftService.apply(tSession, "placeTopping", { pizzaId = 81, ingredient = "pepperoni", x = 0.9, y = 0 })
check("server topping: q (0.9, 0) refused", okT, false)
check("server topping: reason", whyT, "off the pizza")
check("server topping: drawn on the dough", math.abs(PrepGeometry.toPizza(MakeDough.shape(ovalMade), tp.toppings[1]).x - PrepGeometry.axes(MakeDough.shape(ovalMade)).major * 0.8 / 0.95) < 1e-9, true)

-- 10. Slice 1: the food-state hold (Config.Oven, proposals: raw up to 8 s, cooked 12 s to 32 s,
-- burnt past 36 s, hold 35). The Bake score is only the distance from the asked doneness; raw or
-- burnt food holds the grade, continuously. Boundary table: for light 18, regular 24 and well 30,
-- just before, at and after every boundary, Make 99 / Cut 100 and Make 100 / Cut 100, Wait 100.
local oven = Config.Oven
check("proposal: burnt at 36", oven.burntAt, 36)
check("proposal: hold 35", oven.foodCap, 35)
check("proposal: raw until 8", oven.rawUntil, 8)
check("proposal: cooked from 12", oven.cookedFrom, 12)
check("proposal: scorching from 32 (well 30 + window 2)", oven.scorchFrom, oven.targets.well + oven.perfectWindow)
local function capByHand(t: number): number
	if t <= 8 or t >= 36 then
		return 35
	elseif t < 12 then
		return 35 + 65 * (t - 8) / 4
	elseif t > 32 then
		return 35 + 65 * (36 - t) / 4
	end
	return 100
end
local function bakeByHand(target: number, t: number): number
	local over = math.abs(t - target) - 2
	return if over <= 0 then 100 else whole(100 * math.clamp(1 - over / 10, 0, 1))
end
local function serveAt(bakeId: string, t: number, makeScore: number, capOn: boolean): (any, any)
	oven.foodCapOn = capOn
	local b = Scoring.bake(bakeId, t)
	local o = Scoring.order(grade(100), grade(makeScore), b, grade(100))
	oven.foodCapOn = true
	return b, o
end
local times = { 0, 7.9, 8, 8.1, 9.9, 10, 11.9, 12, 12.1, 15.9, 16, 16.1, 19.9, 20, 20.1, 21.9, 22, 22.1, 25.9, 26, 26.1, 27.9, 28, 28.1, 31.9, 32, 32.1, 33, 34, 35, 35.9, 36, 36.1, 38, 40, 48 }
note("")
note("| Bake | Time s | Make / Cut | Before: Bake, grade, coins, XP | After: Bake, hold, grade, coins, XP |")
note("|---|---|---|---|---|")
for _, bakeId in { "light", "regular", "well" } do
	local target = oven.targets[bakeId]
	for _, mk in { 99, 100 } do
		local prev: number? = nil
		for _, t in times do
			local bb, ob = serveAt(bakeId, t, mk, false)
			local ba, oa = serveAt(bakeId, t, mk, true)
			-- By hand: Bake from the distance alone; the grade is the weighted score held by the hold.
			local bh = bakeByHand(target, t)
			local wh = whole(0.5 * mk + 0.3 * bh + 20)
			local gh = math.min(wh, whole(capByHand(t)))
			check(string.format("%s %.1fs make %d: Bake", bakeId, t, mk), ba.score, bh)
			check(string.format("%s %.1fs make %d: grade", bakeId, t, mk), oa.grade, gh)
			check(string.format("%s %.1fs make %d: coins", bakeId, t, mk), oa.coins, whole(12 * gh / 100))
			check(string.format("%s %.1fs make %d: XP", bakeId, t, mk), oa.xp, whole(10 * gh / 100))
			-- Never up past the peak, never down before it: the grade rises to the window and falls after.
			if prev then
				local step = oa.grade - prev
				if t <= target then
					check(string.format("%s %.1fs make %d: rising before the target", bakeId, t, mk), step >= 0, true)
				else
					check(string.format("%s %.1fs make %d: falling after the target", bakeId, t, mk), step <= 0, true)
				end
			end
			prev = oa.grade
			-- The printed table keeps the state boundaries (8, 12, 32, 36 s) and this bake's
			-- perfect-window edges, just before, at and after each.
			local lo, hi = target - oven.perfectWindow, target + oven.perfectWindow
			local edge = false
			for _, b in { 8, 12, 32, 36, lo, hi } do
				if math.abs(t - b) <= 0.1 + 1e-9 then
					edge = true
				end
			end
			if edge then
				note(string.format("| %s | %.1f | %d / 100 | %d, %d, %d, %d | %d, %s, **%d**, %d, %d |", bakeId, t, mk, bb.score, ob.grade, ob.coins, ob.xp, ba.score, if ba.detail.cap < 100 then tostring(ba.detail.cap) else "none", oa.grade, oa.coins, oa.xp))
			end
		end
	end
end
-- No jump: across 36.0 / 36.1 (well, Make 99) the grade moves by at most the 0.1 s slope.
local _, o359 = serveAt("well", 35.9, 99, true)
local _, o360 = serveAt("well", 36.0, 99, true)
local _, o361 = serveAt("well", 36.1, 99, true)
local _, b359 = serveAt("well", 35.9, 99, false)
local _, b361 = serveAt("well", 36.1, 99, false)
check("well 35.9 / 36.0 / 36.1 before: 88 / 88 / 70 (Astra's cliff)", string.format("%d/%d", b359.grade, b361.grade), "88/70")
check("well 35.9 after: hold 35 + 65 x 0.1 / 4 = 36.6 -> 37", o359.grade, 37)
check("well 36.0 after: 35", o360.grade, 35)
check("well 36.1 after: 35", o361.grade, 35)
check("well 36.1 after: held by the food", o361.held and o361.held.name, "food")
check("well 36.1 after: Bake is the distance (6.1 s past: 59)", (Scoring.bake("well", 36.1)).score, 59)
-- A pizza baked inside any perfect window is never held.
for _, bakeId in { "light", "regular", "well" } do
	for _, d in { -2, 0, 2 } do
		local _, o = serveAt(bakeId, oven.targets[bakeId] + d, 99, true)
		check(string.format("%s %+ds: perfect window never held", bakeId, d), o.held, nil)
	end
end
-- Lighter than asked but cooked is not raw: regular asked, light 18 s baked: Bake 60, no hold.
local bl, ol = serveAt("regular", 18, 99, true)
check("regular asked, 18 s: Bake 60", bl.score, 60)
check("regular asked, 18 s: cooked, not held", ol.held, nil)
check("regular asked, 18 s: food state cooked", bl.detail.food, "cooked")
check("raw pizza (0 s): held to 35", (select(2, serveAt("regular", 0, 99, true))).grade, 35)
check("raw pizza (0 s): note", (Scoring.bake("regular", 0)).notes[1], "Still raw")
check("burnt note first", (Scoring.bake("well", 37)).notes[1], "Burnt")

-- The server says the hold on Bake's notes ("Burnt: grade held to 35"), not on Make's.
local burntPizza = { id = 91, ticketId = 90, stage = "cutting", make = makeOf(cleanDough(), sauces.clean, cheeses.clean), toppings = {}, cuts = cutsPerfect, bakeSeconds = 40 }
local bSession = {
	shift = {
		customers = { { id = 90, status = "ordered", order = { recipe = "cheese", bake = "well", slices = 8 }, arrivedAt = workspace:GetServerTimeNow() } },
		pizzas = { [91] = burntPizza },
		ovens = { false, false },
		ingredients = {},
		nextArrival = 1,
		customerCount = 5,
		tips = 0,
		xp = 0,
		tutorial = false,
	},
} :: any
check("serve burnt: accepted", (ShiftService.apply(bSession, "serve", { pizzaId = 91 })), true)
local br = bSession.shift.customers[1].result
check("serve burnt: grade 35", br.overall, 35)
check("serve burnt: hold on Bake's notes", br.bake.notes[1], "Burnt: grade held to 35")
check("serve burnt: Make's notes untouched", br.make.notes[1] ~= "Burnt: grade held to 35", true)

-- 11. Slice 1: Service is a 0.85-1.00 pay modifier before integer rounding. The final coin cut
-- can exceed 15 % on small payouts. Low-payout cases (Wait 100 against Wait 40, Service's floor):
-- grade 100: paid 100 / 85, coins 12 / 10 (-16.7 %); grade 13: paid 13 / 11, coins 2 / 1 (-50 %).
note("")
note("| Grade | Coins at Service 100 | Paid at Service 40 | Coins at Service 40 | Coin cut |")
note("|---|---|---|---|---|")
for _, g in { 100, 50, 35, 21, 13, 4 } do
	local o100 = Scoring.order(grade(100), grade(g), grade(g), grade(g))
	local o40 = Scoring.order(grade(40), grade(g), grade(g), grade(g))
	check(string.format("service grade %d: same grade either way", g), o40.grade, o100.grade)
	check(string.format("service grade %d: same XP either way", g), o40.xp, o100.xp)
	check(string.format("service grade %d: paid = round(grade x 0.85)", g), o40.paid, whole(o100.grade * 0.85))
	check(string.format("service grade %d: coins = round(12 x paid / 100)", g), o40.coins, whole(12 * o40.paid / 100))
	note(string.format("| %d | %d | %d | %d | %s |", o100.grade, o100.coins, o40.paid, o40.coins, if o100.coins > 0 then string.format("%.1f %%", 100 * (o100.coins - o40.coins) / o100.coins) else "n/a"))
end
check("service: grade 100 -> 12 / 10 coins", string.format("%d/%d", Scoring.order(grade(100), grade(100), grade(100), grade(100)).coins, Scoring.order(grade(40), grade(100), grade(100), grade(100)).coins), "12/10")
check("service: grade 13 -> 2 / 1 coins", string.format("%d/%d", Scoring.order(grade(100), grade(13), grade(13), grade(13)).coins, Scoring.order(grade(40), grade(13), grade(13), grade(13)).coins), "2/1")

for k, v in defaults do
	Config.Grade[k] = v
end
for _, l in report do
	print("  " .. l)
end
local summary = string.format("grade checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
print("  " .. summary)

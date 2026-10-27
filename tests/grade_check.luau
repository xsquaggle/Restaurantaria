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
	for _, deg in { 0, 90, 45, 135, 90, 0, 135, 45 } do
		table.insert(m.strokes, line(deg))
	end
	return m
end
-- The worst allowed oval: every stroke one way, to within 0.002 of the 1.1 cap along x (the taper
-- nears the cap without reaching it) with the short axis left at the ball's 0.35 (plan row 47;
-- the capture's oval is staged the same way).
local function ovalDough(): any
	local m = flouredDough()
	for _ = 1, 8 do
		table.insert(m.strokes, line(0))
	end
	return m
end
local oval = PrepGeometry.axes(MakeDough.shape(ovalDough()))
check("oval: long axis within 0.002 of the 1.1 cap", oval.major > 1.098 and oval.major <= 1.1, true)
note(string.format("worst oval: %.4f x %.4f, area share %.4f", oval.major, oval.minor, oval.major * oval.minor / 0.9025))
check("oval: short axis stays 0.35", math.abs(oval.minor - 0.35) < 1e-9, true)

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
	{ name = "worst oval dough", make = makeOf(ovalDough(), sauces.clean, cheeses.clean), bake = 100, cut = 100, wait = 100 },
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
-- Worst oval: area 1.1 x 0.35 / 0.9025 = 0.4266 -> 35 + 65 x 0.3532 = 57.96 -> 58 (plan row 47).
check("oval: dough completeness ceiling 58", row("worst oval dough").full.o.grade, 58)
check("oval: no ceiling with completeness off", row("worst oval dough").cover.o.held, nil)
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
-- Burnt: 0.5 x 99 + 0 + 20 = 69.5 -> 70 (slice 2: 75). No bake ceiling is built (plan 5.3a
-- waits on the burnt time, Lawson's call), so burnt food still grades 70.
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
check("switch dough off: oval not held", (select(2, viaCode(cases[8]))).held, nil)
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

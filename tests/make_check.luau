-- Checks for the Make tab's dough steps (flour the board, pull the dough, roll): the shared
-- flour sampler, stroke check and drag batching, the flour coverage under the finished dough,
-- the revised roll taper, the Dough score, the first shift's roll advice, the Make part of the
-- order grade and the server's actions, which refuse bad input without changing the pizza. Expected values are worked by hand from the
-- rules (see the comments), never from the helpers under test. Run offline with
-- tests/offline/run.py, or in Studio Edit after a sync. Arithmetic only: how the art looks and
-- how a real drag feels are checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeDough = require(Shared.MakeDough)
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
local function line(deg: number, reach: number): any
	local a = math.rad(deg)
	return { x1 = -reach * math.cos(a), y1 = -reach * math.sin(a), x2 = reach * math.cos(a), y2 = reach * math.sin(a) }
end

local cfg = Config.Make
-- The proposed constants this file's hand-worked values assume.
check("proposal: flour step", cfg.flourStep, 0.15)
check("proposal: flour radius", cfg.flourRadius, 0.35)
check("proposal: flour reach", cfg.flourReach, 0.76)
check("proposal: flour per stroke", cfg.flourMaxPerStroke, 40)
check("proposal: flour cap", cfg.flourMaxStamps, 96)
check("proposal: flour full", cfg.flourCoverFull, 0.8)
check("proposal: flour zero", cfg.flourCoverZero, 0.2)
check("proposal: flour weight", cfg.flourWeight, 0.2)
check("proposal: min stroke", cfg.minStroke, 0.3)
check("proposal: max strokes", cfg.maxStrokes, 24)
check("proposal: taper from", G.TAPER_FROM, 0.85)

-- 1. Flour sampler: a drag from (-0.75, 0) to (0.75, 0) stamps at the press point and every 0.15
-- of travel: x = -0.75 + 0.15 k for k = 0..10 (10 x 0.15 = 1.5), 11 stamps, whether the drag
-- arrives as one pointer sample or as forty.
local function drag(n: number, from: any, to: any): { any }
	local sampler = MakeDough.flourSampler()
	local out = {}
	for i = 0, n do
		for _, p in sampler.feed(P(from.x + (to.x - from.x) * i / n, from.y + (to.y - from.y) * i / n)) do
			table.insert(out, p)
		end
	end
	return out
end
local one = drag(1, P(-0.75, 0), P(0.75, 0))
local forty = drag(40, P(-0.75, 0), P(0.75, 0))
check("sampler: 11 stamps in one sample", #one, 11)
check("sampler: 11 stamps in forty samples", #forty, 11)
local same = true
for i = 1, math.min(#one, #forty) do
	same = same and math.abs(one[i].x - forty[i].x) < 1e-9 and math.abs(one[i].x - (-0.75 + 0.15 * (i - 1))) < 1e-9
end
check("sampler: stamps at -0.75 + 0.15 k either way", same, true)
-- A drag that comes back counts its travel both ways: 0 -> 0.3 -> 0: stamps at 0, 0.15, 0.3,
-- then 0.15, 0 on the way back = 5.
local back = MakeDough.flourSampler()
local n = #back.feed(P(0, 0)) + #back.feed(P(0.3, 0)) + #back.feed(P(0, 0))
check("sampler: reversal keeps dusting", n, 5)

-- 2. The flour stroke check refuses before storing anything.
local function newMake(): any
	return MakeDough.new()
end
local mk = newMake()
local okStroke = MakeDough.validateFlour(mk, one)
check("flour: a clean stroke passes", okStroke ~= nil and #okStroke, 11)
check("flour: the stored copy is a copy", okStroke ~= nil and okStroke[1] ~= one[1], true)
local function refused(name: string, points: any, want: string, make: any?)
	local got, why = MakeDough.validateFlour(make or mk, points)
	check("flour " .. name .. ": refused", got, nil)
	check("flour " .. name .. ": reason", why, want)
end
refused("empty", {}, "bad flour stroke")
refused("not a list", "x", "bad flour stroke")
local long = {}
for i = 1, cfg.flourMaxPerStroke + 1 do
	long[i] = P(0, 0)
end
refused("41 stamps", long, "bad flour stroke")
refused("off the board", { P(0.77, 0) }, "flour off the board")
-- (0.6, 0.6) is inside the +-0.76 box but 0.849 from the centre, past the stamps' round limit.
refused("past the round edge", { P(0.6, 0.6) }, "flour off the board")
refused("NaN", { P(0 / 0, 0) }, "flour off the board")
refused("a gap", { P(0, 0), P(0.16, 0) }, "flour stamps too far apart")
check("flour: 0.15 apart passes", MakeDough.validateFlour(mk, { P(0, 0), P(0.15, 0) }) ~= nil, true)
local full = newMake()
for _ = 1, 3 do
	local stroke = {}
	for i = 1, 32 do
		stroke[i] = P(0, 0)
	end
	table.insert(full.flour, stroke)
end
refused("past the cap (96 + 1)", { P(0, 0) }, "too much flour", full)
local placed = newMake()
placed.placed = true
refused("after the dough is placed", { P(0, 0) }, "the dough is already on the board", placed)
local finished = newMake()
finished.step = "toppings"
refused("after the dough is done", { P(0, 0) }, "dough is done", finished)
-- Reach slack: a stamp pulled back onto the reach (float error either way) passes; one 2e-6
-- past it does not. 0.76 / sqrt(2) on both axes lies on the reach circle.
local onReach = 0.76 / math.sqrt(2)
check("flour: on the reach, a hair over", MakeDough.validateFlour(mk, { P(0.76 * (1 + 1e-9), 0) }) ~= nil, true)
check("flour: on the reach, diagonal", MakeDough.validateFlour(mk, { P(onReach * (1 + 1e-12), onReach) }) ~= nil, true)
refused("past the reach slack", { P(0.76 + 2e-6, 0) }, "flour off the board")

-- 2b. One held drag split into batches (MakeDough.flourDrag), as the client sends them. Fast
-- drags (pointer samples far apart) used to be refused "flour stamps too far apart" when a
-- batch filled up inside one pointer step; every batch must now pass the server's check in
-- order, on top of the batches before it.
local function runDrag(path: { any }): ({ { any } }, any, string?)
	local m = newMake()
	local fd = MakeDough.flourDrag()
	local batches = {}
	local function take(list: { { any } })
		for _, b in list do
			table.insert(batches, b)
		end
	end
	for _, q in path do
		take(fd.move(q, cfg.flourMaxStamps - MakeDough.stampCount(m)))
		-- The client pushes each closed batch at once, so the room shrinks with it.
		for i = #m.flour + 1, #batches do
			local clean, why = MakeDough.validateFlour(m, batches[i])
			if not clean then
				return batches, m, why
			end
			table.insert(m.flour, clean)
		end
	end
	local last = fd.close()
	if last then
		table.insert(batches, last)
		local clean, why = MakeDough.validateFlour(m, last)
		if not clean then
			return batches, m, why
		end
		table.insert(m.flour, clean)
	end
	return batches, m, nil
end
-- A five-row zigzag over the whole board (rows at y = -0.7 .. 0.7, out to x = +-1.0, so the
-- pointer passes the reach and is pulled back), walked in pointer steps of `step`.
local function zigzag(step: number): { any }
	local corners = {}
	for row = 0, 4 do
		local y = -0.7 + 0.35 * row
		local a, b = -1.0, 1.0
		if row % 2 == 1 then
			a, b = 1.0, -1.0
		end
		table.insert(corners, P(a, y))
		table.insert(corners, P(b, y))
	end
	local path = { corners[1] }
	for i = 2, #corners do
		local from, to = corners[i - 1], corners[i]
		local len = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
		local n = math.max(1, math.ceil(len / step))
		for k = 1, n do
			table.insert(path, P(from.x + (to.x - from.x) * k / n, from.y + (to.y - from.y) * k / n))
		end
	end
	return path
end
for _, step in { 0.05, 0.3, 0.35, 0.45, 0.6, 1.0 } do
	local batches, m, why = runDrag(zigzag(step))
	local name = string.format("flour drag, pointer step %.2f", step)
	check(name .. ": every batch accepted", why, nil)
	local biggest = 0
	for _, b in batches do
		biggest = math.max(biggest, #b)
	end
	check(name .. ": batches of 40 or fewer", biggest <= cfg.flourMaxPerStroke, true)
	check(name .. ": more than one batch", #batches > 1, true)
	check(name .. ": within the pizza's 96", MakeDough.stampCount(m) <= cfg.flourMaxStamps, true)
end
-- Random fast drags: 40 deterministic walks per pointer step (each event moves `step` on a
-- heading that drifts by up to +-0.7 rad and turns back toward the centre past 0.9; 60 events).
-- A scratch copy of 03d102a's batching (a fresh sampler at the stamp that filled a batch) had 2
-- of the 0.35 walks and 1 of the 0.45 walks refused; every walk must pass now.
local function walks(step: number, count: number): { { any } }
	local seed = 12345
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local all = {}
	for _ = 1, count do
		local a, r = rnd() * 2 * math.pi, 0.6 * math.sqrt(rnd())
		local x, y = r * math.cos(a), r * math.sin(a)
		local h = rnd() * 2 * math.pi
		local path = { P(x, y) }
		for _ = 1, 60 do
			h += (rnd() - 0.5) * 1.4
			if x * x + y * y > 0.81 then
				h = math.atan2(-y, -x) + (rnd() - 0.5) * 0.6
			end
			x += step * math.cos(h)
			y += step * math.sin(h)
			table.insert(path, P(x, y))
		end
		table.insert(all, path)
	end
	return all
end
for _, step in { 0.3, 0.35, 0.45, 0.6 } do
	local refusedWalks = 0
	for _, path in walks(step, 40) do
		local _, _, why = runDrag(path)
		if why then
			refusedWalks += 1
		end
	end
	check(string.format("flour random walks, pointer step %.2f: none refused", step), refusedWalks, 0)
end
-- Off the board and back: the batch closes when the pointer passes the board's edge (1 / 0.9)
-- and dusting starts afresh where it comes back, so the stamps either side are not checked
-- against each other. From (-0.6, 0) to (0.6, 0): 9 stamps (0.15 apart over 1.2); out to
-- (0, 1.3) and back to (0, 0.6), then to (0, -0.6): a new line of 9.
do
	local batches, m, why = runDrag({ P(-0.6, 0), P(0.6, 0), P(0, 1.3), P(0, 0.6), P(0, -0.6) })
	check("flour drag off the board: accepted", why, nil)
	check("flour drag off the board: two batches", #batches, 2)
	check("flour drag off the board: first batch", batches[1] and #batches[1], 9)
	check("flour drag off the board: second batch", batches[2] and #batches[2], 9)
	check("flour drag off the board: second starts where it came back", batches[2] and batches[2][1].y, 0.6)
	check("flour drag off the board: stamps stored", MakeDough.stampCount(m), 18)
end
-- Between the reach and the edge the pointer is pulled back onto the reach: a press at (1, 0)
-- lands its stamp at (0.76, 0).
do
	local fd = MakeDough.flourDrag()
	fd.move(P(1, 0), cfg.flourMaxStamps)
	near("flour drag: pulled back onto the reach", fd.points[1] and fd.points[1].x, 0.76, 1e-12)
	check("flour drag: close returns the open batch", #(fd.close() or {}), 1)
	check("flour drag: nothing left open", fd.close(), nil)
end
-- The pizza's room is honoured: with room for 5, a long drag keeps 5.
do
	local fd = MakeDough.flourDrag()
	fd.move(P(-0.75, 0), 5)
	fd.move(P(0.75, 0), 5)
	check("flour drag: stops at the room left", #fd.points, 5)
end

-- 3. Coverage under the dough. The 61-point sample sits at the centre and on rings at radius
-- sqrt(4/61) = 0.2561, sqrt(13/61) = 0.4616, sqrt(28/61) = 0.6775, sqrt(49/61) = 0.8963.
check("sample: 61 points", #MakeDough.SAMPLE, 61)
near("sample: ring 1 radius", math.sqrt(MakeDough.SAMPLE[2].x ^ 2 + MakeDough.SAMPLE[2].y ^ 2), math.sqrt(4 / 61), 1e-12)
near("sample: ring 4 radius", math.sqrt(MakeDough.SAMPLE[61].x ^ 2 + MakeDough.SAMPLE[61].y ^ 2), math.sqrt(49 / 61), 1e-12)
local centre = newMake()
table.insert(centre.flour, { P(0, 0) })
-- One stamp at the centre (radius 0.35) covers the whole ball (outline radius 0.35): 61 / 61.
near("coverage: one stamp covers the ball", MakeDough.flourCoverage(centre, G.ball()), 1, 1e-12)
-- On a full 0.95 dough the same stamp reaches sample radius 0.35 / 0.95 = 0.368: the centre and
-- ring 1 (0.256), not ring 2 (0.462): 7 / 61.
near("coverage: one stamp on a full dough", MakeDough.flourCoverage(centre, G.shape(0.95, 0.95, 0)), 7 / 61, 1e-12)
near("coverage: no flour", MakeDough.flourCoverage(newMake(), G.ball()), 0, 1e-12)

-- 4. Roll. Below TAPER_FROM the parts multiply to exactly 1.35: one full stroke on the ball
-- gives semi-axes 0.4725 x 0.35 (0.35 x 1.35).
local e1 = G.axes(G.doughShape({ line(0, 1.2) }))
near("roll: one full stroke, long axis", e1.major, 0.4725, 1e-9)
near("roll: one full stroke, short axis", e1.minor, 0.35, 1e-9)
-- Alternating full strokes, worked from 1.35 per stroke while under 0.85: 0.35, 0.4725, 0.6379,
-- 0.8611 (each axis every second stroke): six strokes = 0.8611 round, untapered.
local six = {}
for i = 1, 6 do
	six[i] = line(if i % 2 == 1 then 0 else 90, 1.2)
end
local e6 = G.axes(G.doughShape(six))
near("roll: six alternating strokes, round", e6.major, 0.35 * 1.35 ^ 3, 1e-9)
near("roll: six alternating strokes, other axis", e6.minor, 0.35 * 1.35 ^ 3, 1e-9)
-- The seventh: with the taper read as the stroke goes on, it lands between 0.95 and 1.05 (the
-- old model jumped to the 1.1 cap). Bounds, not an exact figure: the 16-part integration has
-- no closed form; the continuous limit (dr = r (1.1 - r) / 0.25 past 0.85) gives 1.038.
local seven = table.clone(six)
seven[7] = line(0, 1.2)
local e7 = G.axes(G.doughShape(seven))
check("roll: seventh stroke lands in 0.95 .. 1.05", e7.major >= 0.95 and e7.major <= 1.05, true)
note(string.format("rolls: six alternating full strokes %.4f round; the seventh stretches one axis to %.4f (old model: 1.1)", e6.major, e7.major))
-- Over-rolling still reaches the cap but no further.
local many = table.clone(six)
for i = 1, 30 do
	table.insert(many, line(if i % 2 == 1 then 0 else 90, 1.2))
end
check("roll: capped at 1.1", G.axes(G.doughShape(many)).major <= 1.1 + 1e-12, true)

-- 5. The roll check on the server path.
local rolling = newMake()
table.insert(rolling.flour, { P(0, 0) })
local okLine, why = MakeDough.validateRoll(rolling, line(0, 1.2))
check("roll check: no dough", okLine == nil and why, "no dough on the board")
rolling.placed = true
check("roll check: full stroke passes", MakeDough.validateRoll(rolling, line(0, 1.2)) ~= nil, true)
local function rollRefused(name: string, args: any, want: string)
	local got, reason = MakeDough.validateRoll(rolling, args)
	check("roll " .. name .. ": refused", got, nil)
	check("roll " .. name .. ": reason", reason, want)
end
rollRefused("NaN", { x1 = 0 / 0, y1 = 0, x2 = 1, y2 = 0 }, "roll out of range")
rollRefused("past 1.6", { x1 = -1.7, y1 = 0, x2 = 1, y2 = 0 }, "roll out of range")
rollRefused("too short (0.29)", { x1 = -0.1, y1 = 0, x2 = 0.19, y2 = 0 }, "roll too short")
-- x = 0.5 is past the ball's 0.35 edge for every y: the stroke misses.
rollRefused("beside the dough", { x1 = 0.5, y1 = -1, x2 = 0.5, y2 = 1 }, "roll missed the dough")
for i = 1, cfg.maxStrokes do
	rolling.strokes[i] = line(0, 0.4)
end
rollRefused("the 25th", line(0, 1.2), "too many rolls")

-- 6. The Dough score.
-- Nothing placed: 0.
check("grade: no dough", MakeDough.grade(newMake()).score, 0)
-- Ball rolled once (0.4725 x 0.35), fully floured: mean 0.41125 is under 0.6, size 0; round =
-- (0.35 / 0.4725 - 0.5) / 0.4 = 0.60185; roll = 100 x (0 + 0.5 x 0.60185) = 30.093; flour 100;
-- Dough = 0.8 x 30.093 + 0.2 x 100 = 44.07 -> 44.
local onceFloured = newMake()
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
onceFloured.flour = grid
onceFloured.placed = true
onceFloured.strokes = { line(0, 1.2) }
local g1 = MakeDough.grade(onceFloured)
near("grade: ball rolled once, roll part", g1.detail.roll, 100 * 0.5 * ((0.35 / 0.4725 - 0.5) / 0.4), 1e-9)
near("grade: ball rolled once, flour coverage", g1.detail.coverage, 1, 1e-12)
check("grade: ball rolled once", g1.score, 44)
check("grade: too small note", table.find(g1.notes, "Dough too small") ~= nil, true)
check("grade: uneven note", table.find(g1.notes, "Dough uneven") ~= nil, true)
check("grade: no flour note when floured", table.find(g1.notes, "Flour the whole board first") == nil, true)
-- The same dough with one flour stamp at the centre: under the 0.4725 x 0.35 oval the stamp
-- (radius 0.35) covers every sample point whose oval position is within 0.35 of the centre.
-- Coverage is read, not worked; the flour part follows the ramp from it.
local thin = table.clone(onceFloured)
thin.flour = { { P(0, 0) } }
local gt = MakeDough.grade(thin)
near("grade: flour part follows the ramp", gt.detail.flour, 100 * math.clamp((gt.detail.coverage - 0.2) / 0.6, 0, 1), 1e-9)
check("grade: no-flour-under note", (gt.detail.coverage < 0.8) == (table.find(gt.notes, "Flour the whole board first") ~= nil), true)
-- The clean test-hook dough (eight rolls at 0, 90, 45, 135, 90, 0, 135, 45; fully floured):
-- round inside 0.95 .. 1.05, so 100.
local clean = table.clone(onceFloured)
clean.strokes = { line(0, 1.2), line(90, 1.2), line(45, 1.2), line(135, 1.2), line(90, 1.2), line(0, 1.2), line(135, 1.2), line(45, 1.2) }
local gc = MakeDough.grade(clean)
check("grade: clean dough", gc.score, 100)
check("grade: clean dough mean radius in the full band", gc.detail.meanRadius >= 0.95 and gc.detail.meanRadius <= 1.05, true)
-- 6b. The first shift's pointer after a roll (MakeDough.rollAdvice). Worked from the shapes above:
-- nothing rolled -> nil; once (0.4725 x 0.35) and six (0.8611 round) -> small; seven (1.028 x
-- 0.8611, minor/major 0.84 < 0.9 with the long side full size) -> uneven; the clean eight ->
-- ready; ten alternating (both axes past 1.05) -> big; six one way (long side at the cap, short
-- side 0.35) -> uneven.
local function advice(strokes: { any }): string?
	local m = newMake()
	m.placed = true
	m.strokes = strokes
	return MakeDough.rollAdvice(m)
end
check("advice: before the first roll", advice({}), nil)
check("advice: rolled once", advice({ line(0, 1.2) }), "small")
check("advice: six alternating", advice(six), "small")
check("advice: seven", advice(seven), "uneven")
check("advice: clean eight", advice(clean.strokes), "ready")
local ten = {}
for i = 1, 10 do
	ten[i] = line(if i % 2 == 1 then 0 else 90, 1.2)
end
local e10 = G.axes(G.doughShape(ten))
check("advice: ten alternating are past full size", e10.minor > 1.05, true)
check("advice: ten alternating", advice(ten), "big")
local oneWay = {}
for i = 1, 6 do
	oneWay[i] = line(0, 1.2)
end
check("advice: six one way", advice(oneWay), "uneven")
note(string.format("roll advice: ten alternating %.4f x %.4f (big); six one way %.4f x %.4f (uneven)", e10.major, e10.minor, G.axes(G.doughShape(oneWay)).major, G.axes(G.doughShape(oneWay)).minor))

note(string.format("dough grades: ball rolled once = %d; clean eight rolls = %d (mean radius %.4f, %.4f x %.4f)", g1.score, gc.score, gc.detail.meanRadius, gc.detail.major, gc.detail.minor))

-- 7. The Make part of the order grade: the mean of Dough, Sauce, Cheese and (only when the ticket
-- has toppings) Toppings; a cheese order has no free topping score. Here the sauce and cheese
-- steps are empty (each 0; sauce_cheese_check covers them), so a cheese order is
-- (44 + 0 + 0) / 3 = 14.67 -> 15, under both coverage ceilings (35, nothing covered), so not
-- held. A pepperoni order's mean is (44 + 0 + 0 + 100) / 4 = 36, over the empty sauce's ceiling of
-- 35, so it is held to 35.
local cheese = Recipes.ById.cheese
check("make: cheese order = mean of dough, sauce, cheese", Scoring.make(cheese, onceFloured, {}).score, 15)
local pep = Recipes.ById.pepperoni
local pieces = {}
for i = 1, 8 do
	local a = math.rad(22.5 + (i - 1) * 45)
	pieces[i] = { ingredient = "pepperoni", x = math.cos(a) * 0.5, y = -math.sin(a) * 0.5 }
end
local tops = Scoring.toppings(pep, pieces).score
check("make: pepperoni toppings perfect", tops, 100)
-- Slice 2's setting (the ceilings hold only Make, no completeness ceilings): held to 35.
local saved = table.clone(Config.Grade)
Config.Grade.ceilingsOn, Config.Grade.completeness = "make", false
local gp = Scoring.make(pep, onceFloured, pieces)
check("make: pepperoni order mean of four", gp.detail.mean, 36)
check("make: pepperoni order held by the sauce ceiling", gp.score, 35)
check("make: pepperoni hold noted", gp.notes[1], "Most of the pizza has no sauce: Make held to 35")
-- The grade split's default (ceilings on the order grade): Make stays the mean, and the lowest
-- ceiling (the empty sauce's 35, first on a tie) is handed to Scoring.order.
for k, v in saved do
	Config.Grade[k] = v
end
local go = Scoring.make(pep, onceFloured, pieces)
check("make (order ceilings): Make is the mean", go.score, 36)
check("make (order ceilings): lowest ceiling is the sauce coverage", go.detail.ceilings[1].name .. "=" .. go.detail.ceilings[1].value, "sauceCover=35")
local anyHeld = false
for _, n in go.notes do
	anyHeld = anyHeld or n:find("held") ~= nil
end
check("make (order ceilings): no hold note on Make", anyHeld, false)

-- 8. Server actions: the dough step through ShiftService.apply; refusals change nothing.
local pizza = { id = 9, ticketId = 1, stage = "topping", make = MakeDough.new(), toppings = {}, cuts = {} }
local session = { shift = { pizzas = { [9] = pizza }, ovens = { false, false }, ingredients = {} } } :: any
local function act(action: string, args: any): (boolean, string?)
	return ShiftService.apply(session, action, args)
end
local function snapshot(): string
	local m = pizza.make
	return string.format("%s|%d|%d|%s|%d|%d", m.step, #m.flour, MakeDough.stampCount(m), tostring(m.placed), #m.strokes, #pizza.toppings)
end
local function serverRefused(name: string, action: string, args: any, want: string)
	local before = snapshot()
	local ok, reason = act(action, args)
	check("server " .. name .. ": refused", ok, false)
	check("server " .. name .. ": reason", reason, want)
	check("server " .. name .. ": nothing changed", snapshot(), before)
end
serverRefused("toppings before the dough", "placeTopping", { pizzaId = 9, ingredient = "pepperoni", x = 0, y = 0 }, "dough not finished")
serverRefused("oven before the dough", "sendToOven", { pizzaId = 9 }, "dough not finished")
serverRefused("dough before flour", "placeDough", { pizzaId = 9 }, "flour the board first")
serverRefused("roll before the dough", "rollDough", { pizzaId = 9, x1 = -1, y1 = 0, x2 = 1, y2 = 0 }, "no dough on the board")
serverRefused("finish before the dough", "finishDough", { pizzaId = 9, from = "dough" }, "roll the dough first")
serverRefused("undo with nothing", "undoDough", { pizzaId = 9 }, "nothing to undo")
serverRefused("flour gap", "flour", { pizzaId = 9, points = { P(0, 0), P(0.5, 0) } }, "flour stamps too far apart")
check("server: flour accepted", (act("flour", { pizzaId = 9, points = one })), true)
check("server: flour stored", snapshot(), "dough|1|11|false|0|0")
check("server: undo removes the flour stroke", (act("undoDough", { pizzaId = 9 })), true)
check("server: flour gone", snapshot(), "dough|0|0|false|0|0")
act("flour", { pizzaId = 9, points = one })
check("server: dough placed", (act("placeDough", { pizzaId = 9 })), true)
serverRefused("dough twice", "placeDough", { pizzaId = 9 }, "the dough is already on the board")
serverRefused("flour under the dough", "flour", { pizzaId = 9, points = { P(0, 0) } }, "the dough is already on the board")
check("server: roll accepted", (act("rollDough", { pizzaId = 9, x1 = -1.2, y1 = 0, x2 = 1.2, y2 = 0 })), true)
check("server: roll stored", snapshot(), "dough|1|11|true|1|0")
serverRefused("roll beside", "rollDough", { pizzaId = 9, x1 = 1.5, y1 = -1, x2 = 1.5, y2 = 1 }, "roll missed the dough")
check("server: undo takes the roll back", (act("undoDough", { pizzaId = 9 })), true)
check("server: undo again lifts the ball", (act("undoDough", { pizzaId = 9 })), true)
check("server: ball off, flour kept", snapshot(), "dough|1|11|false|0|0")
act("placeDough", { pizzaId = 9 })
act("rollDough", { pizzaId = 9, x1 = -1.2, y1 = 0, x2 = 1.2, y2 = 0 })
serverRefused("finish from the wrong step", "finishDough", { pizzaId = 9, from = "toppings" }, "bad step")
check("server: finish accepted", (act("finishDough", { pizzaId = 9, from = "dough" })), true)
check("server: on to the sauce", pizza.make.step, "sauce")
serverRefused("finish twice", "finishDough", { pizzaId = 9, from = "dough" }, "dough is done")
serverRefused("roll after", "rollDough", { pizzaId = 9, x1 = -1.2, y1 = 0, x2 = 1.2, y2 = 0 }, "dough is done")
serverRefused("undo dough after", "undoDough", { pizzaId = 9 }, "dough is done")
serverRefused("flour after", "flour", { pizzaId = 9, points = { P(0, 0) } }, "dough is done")
serverRefused("dough after", "placeDough", { pizzaId = 9 }, "dough is done")
serverRefused("toppings at the sauce step", "placeTopping", { pizzaId = 9, ingredient = "pepperoni", x = 0, y = 0 }, "not at the toppings step")
-- Through the sauce and cheese steps (sauce_cheese_check tests them).
act("pourSauce", { pizzaId = 9, x = 0, y = 0 })
act("spreadSauce", { pizzaId = 9, points = { P(-0.3, 0), P(0.3, 0) } })
check("server: sauce finished", (act("finishSauce", { pizzaId = 9, from = "sauce" })), true)
act("addCheese", { pizzaId = 9, newStroke = true, points = { P(0, 0) } })
check("server: cheese finished", (act("finishCheese", { pizzaId = 9, from = "cheese" })), true)
check("server: on to toppings", pizza.make.step, "toppings")
check("server: toppings now", (act("placeTopping", { pizzaId = 9, ingredient = "pepperoni", x = 0, y = 0 })), false) -- not unlocked on this bare shift
session.shift.ingredients = { "pepperoni" }
check("server: topping placed", (act("placeTopping", { pizzaId = 9, ingredient = "pepperoni", x = 0, y = 0 })), true)
check("server: sent to the oven", (act("sendToOven", { pizzaId = 9 })), true)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("make checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

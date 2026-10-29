-- Rolling, slice 7 (Lawson 2026-10-29, option B: "extra passes after the dough reaches ready
-- size do no harm; flour coverage and stopping too early still affect grading"), with the two
-- rolling items slice 6 left open: a short push previewed growth that snapped back when it was
-- let go (Open 11), and the pointer kept saying "Keep rolling" after the pass that made the dough
-- ready (Open 12). Deterministic passes and pointer paths through the shared logic the server
-- and the Make station use (MakeDough.shape, MakeDough.preview, MakeDough.rollDrag,
-- MakeDough.rollAdvice). The "before" rows replay the slice 6 logic and are checked as showing
-- the faults. Synthetic paths, not a hand: a real-mouse try is still owed.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
local MakeDough = require(Shared.MakeDough)

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

local cfg = Config.Make
local has = type(MakeDough.preview) == "function" and type(MakeDough.keptPass) == "function"
check("the station's preview is shared logic (MakeDough.preview)", has, true)

-- A full pass through the middle at deg degrees (screen, y down), 1.2 each side.
local function pass(deg: number): any
	local a = math.rad(deg)
	return { x1 = -1.2 * math.cos(a), y1 = -1.2 * math.sin(a), x2 = 1.2 * math.cos(a), y2 = 1.2 * math.sin(a) }
end
local function dough(strokes: { any }, flour: { any }?): any
	local m = MakeDough.new()
	m.placed = true
	m.strokes = strokes
	m.flour = flour or {}
	return m
end
local function same(A: G.Mat2, B: G.Mat2): boolean
	return A.a == B.a and A.b == B.b and A.c == B.c and A.d == B.d
end
local function meanOf(S: G.Mat2): number
	return G.meanRadius(S)
end
-- Ready as the pointer's "Round and full size" means it (stated here, so the check also runs on
-- the slice 6 sources for the failing-before evidence).
local function ready(S: G.Mat2): boolean
	local e = G.axes(S)
	local mean = (e.major + e.minor) / 2
	return mean >= cfg.sizeFullLow and mean <= cfg.sizeFullHigh and e.minor / e.major >= cfg.roundFull
end

-- Flour stamps over the whole reach (a well-floured board).
local fullFlour = {}
do
	local batch = {}
	for y = -0.75, 0.75, 0.15 do
		for x = -0.75, 0.75, 0.15 do
			if x * x + y * y <= cfg.flourReach ^ 2 then
				table.insert(batch, { x = x, y = y })
			end
		end
	end
	table.insert(fullFlour, batch)
end

------------------------------------------------------------------------------------------
-- 1. Lawson's real-mouse try (2026-10-28 23:28 UTC): seven alternating passes up and down gave
-- dough 67, "too big and thin". The same seven, alternating direction along one line.

local seven = {}
for i = 1, 7 do
	seven[i] = pass(if i % 2 == 1 then 90 else 270)
end
local g7 = MakeDough.grade(dough(seven, fullFlour))
check("Lawson's seven passes: size full marks", g7.detail.size, 1)
check("Lawson's seven passes: roundness full marks", g7.detail.round, 1)
check("Lawson's seven passes: roll part 100", g7.detail.roll, 100)
check("Lawson's seven passes, floured: Dough 100", g7.score, 100)
check("Lawson's seven passes: no 'too big' note", table.find(g7.notes, "Dough too big and thin"), nil)
note(string.format("seven alternating passes: Dough %d, mean radius %.4f, %.4f x %.4f", g7.score, g7.detail.meanRadius, g7.detail.major, g7.detail.minor))
-- Ready after the third: the fourth to seventh leave the dough exactly as the third left it.
local three = { seven[1], seven[2], seven[3] }
check("ready after three passes", ready(MakeDough.shape(dough(three))), true)
check("passes four to seven change nothing", same(MakeDough.shape(dough(three)), MakeDough.shape(dough(seven))), true)

------------------------------------------------------------------------------------------
-- 2. No sequence of passes does harm once ready, and none overshoots full size. 400 seeded
-- sequences of 1 to 24 passes (maxStrokes), each a full or part pass at any angle and offset.

local seed = 12345
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local overshoot, harmed, everReady, notes = 0, 0, 0, 0
local worstMean = 0
for _ = 1, 400 do
	local strokes = {}
	local readyAt: G.Mat2? = nil
	local n = 1 + math.floor(rand() * cfg.maxStrokes)
	for k = 1, n do
		local a = rand() * 2 * math.pi
		local off = (rand() - 0.5) * 0.6
		local reach = 0.4 + rand() * 0.8
		local cx, cy = -math.sin(a) * off, math.cos(a) * off
		strokes[k] = { x1 = cx - math.cos(a) * reach, y1 = cy - math.sin(a) * reach, x2 = cx + math.cos(a) * reach, y2 = cy + math.sin(a) * reach }
		local S = MakeDough.shape(dough(strokes))
		worstMean = math.max(worstMean, meanOf(S))
		if meanOf(S) > cfg.sizeFullHigh + 1e-9 then
			overshoot += 1
		end
		if readyAt then
			if not same(S, readyAt) then
				harmed += 1
			end
		elseif ready(S) then
			readyAt = S
			everReady += 1
		end
	end
	local g = MakeDough.grade(dough(strokes))
	if table.find(g.notes, "Dough too big and thin") then
		notes += 1
	end
end
check("random passes: none past full size", overshoot, 0)
check("random passes: none changes a ready dough", harmed, 0)
check("random passes: no 'too big' note", notes, 0)
check("random passes: most sequences reach ready", everReady > 200, true)
note(string.format("random passes: 400 sequences, %d reached ready, largest mean radius %.4f", everReady, worstMean))

------------------------------------------------------------------------------------------
-- 3. Stopping too early still costs: one and two passes leave the dough small.

for _, case in { { "one pass", { pass(0) } }, { "two crossed passes", { pass(0), pass(90) } } } do
	local g = MakeDough.grade(dough(case[2], fullFlour))
	check(case[1] .. ": 'Dough too small'", table.find(g.notes, "Dough too small") ~= nil, true)
	check(case[1] .. ": below 100", g.score < 100, true)
	note(string.format("%s, floured: Dough %d (mean radius %.4f)", case[1], g.score, g.detail.meanRadius))
end
-- Three full passes still reach full size and round, whichever way they run.
for _, case in { { "one way", { 0, 0, 0 } }, { "crossed", { 90, 0, 90 } }, { "fanned", { 90, 30, 150 } }, { "diagonals", { 45, 135, 45 } } } do
	local strokes = {}
	for i, deg in case[2] do
		strokes[i] = pass(deg)
	end
	check("three passes " .. case[1] .. ": ready", ready(MakeDough.shape(dough(strokes))), true)
end

------------------------------------------------------------------------------------------
-- 4. Flour still counts, and extra passes do not move the dough off it.

local bare = MakeDough.grade(dough(seven))
check("seven passes, no flour: Dough 80 (flour part 0)", bare.score, 80)
check("seven passes, no flour: flour note", table.find(bare.notes, "Flour the whole board first") ~= nil, true)
local c3 = MakeDough.grade(dough(three, fullFlour)).detail.coverage
check("flour coverage after three passes = after seven", c3, g7.detail.coverage)

------------------------------------------------------------------------------------------
-- 5. Short passes do not snap back (Open 11). Pointer paths that push and turn by 0.15 to 0.29
-- (past rollLock 0.12, short of minStroke 0.3), mixed with kept passes, replayed sample by
-- sample as the station draws them. After: the drawn dough is MakeDough.preview (the open pass
-- shows only once the server would keep it). Before (slice 6): the open pass showed from
-- rollLock, through PrepGeometry.roll, whether or not it would be kept.

local function walk(path: { any }, from: any, to: any, step: number)
	local dx, dy = to.x - from.x, to.y - from.y
	local n = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / step))
	for i = 1, n do
		table.insert(path, { x = from.x + dx * i / n, y = from.y + dy * i / n })
	end
end
-- Each hold: a list of points visited in a straight walk.
local HOLDS = {
	{ "short push and let go", { { 0, 0.1 }, { 0, -0.12 } } },
	{ "short push, turn, short pull", { { 0, 0.1 }, { 0, -0.15 }, { 0, 0.1 } } },
	{ "sawing short strokes", { { 0, 0 }, { 0.2, 0 }, { 0.02, 0 }, { 0.22, 0 }, { 0.04, 0 }, { 0.26, 0 } } },
	{ "long pass then a short turn", { { 0, 0.9 }, { 0, -0.9 }, { 0, -0.65 } } },
	{ "long, short, long", { { -0.9, 0 }, { 0.9, 0 }, { 0.7, 0 }, { 0.7, 0.2 }, { 0.7, -0.9 } } },
}

type Run = { shrinks: number, releaseJumps: number, mean: number, strokes: number, adviceAtRelease: number, adviceHeld: number }

local function replay(after: boolean, holds: { any }): Run
	local make = dough({})
	local run: Run = { shrinks = 0, releaseJumps = 0, mean = 0, strokes = 0, adviceAtRelease = 0, adviceHeld = 0 }
	local last: number? = nil
	local function shown(open: any): G.Mat2
		if after and has then
			return MakeDough.preview(make, open)
		end
		-- Slice 6: the committed rolls (the slice 6 model) plus any open pass with a direction.
		local S = G.doughShape(make.strokes)
		if open then
			S = G.roll(S, { x = open.x1, y = open.y1 }, { x = open.x2, y = open.y2 }) or S
		end
		return S
	end
	local function commit(l: any)
		if l and (l.x2 - l.x1) ^ 2 + (l.y2 - l.y1) ^ 2 >= cfg.minStroke ^ 2 and MakeDough.validateRoll(make, l) then
			table.insert(make.strokes, l)
		end
	end
	local function draw(S: G.Mat2): number
		local m = meanOf(S)
		if last and m < last - 1e-9 then
			run.shrinks += 1
		end
		last = m
		return m
	end
	for _, hold in holds do
		local pts = {}
		for i, v in hold do
			local p = { x = v[1], y = v[2] }
			if i == 1 then
				table.insert(pts, p)
			else
				walk(pts, pts[#pts], p, 0.04)
			end
		end
		local drag = MakeDough.rollDrag(pts[1])
		local heldAdvice: string? = nil
		local held = 0
		for i = 2, #pts do
			commit(drag.move(pts[i]))
			local S = shown(drag.line())
			held = draw(S)
			if after and has then
				local previewing = MakeDough.keptPass(make, drag.line()) ~= nil
				heldAdvice = MakeDough.rollAdvice(make, if previewing then S else nil)
			else
				heldAdvice = MakeDough.rollAdvice(make)
			end
		end
		commit(drag.close())
		local released = draw(shown(nil))
		if math.abs(released - held) > 1e-9 then
			run.releaseJumps += 1
		end
		-- The pointer's advice on the release frame against the last held frame.
		if MakeDough.rollAdvice(make) ~= heldAdvice then
			run.adviceAtRelease += 1
		end
	end
	run.mean, run.strokes = meanOf(MakeDough.shape(make)), #make.strokes
	return run
end

for _, h in HOLDS do
	local before = replay(false, { h[2] })
	local after = replay(true, { h[2] })
	check("short passes, " .. h[1] .. ": after, the dough never shrinks", after.shrinks, 0)
	check("short passes, " .. h[1] .. ": after, nothing changes on release", after.releaseJumps, 0)
	note(string.format("%s: before %d shrink(s), %d release jump(s); after %d, %d; kept passes %d", h[1], before.shrinks, before.releaseJumps, after.shrinks, after.releaseJumps, after.strokes))
end
-- The fault, shown on the slice 6 logic for the first three holds (every pass in them is short).
for i = 1, 3 do
	local before = replay(false, { HOLDS[i][2] })
	check("before (slice 6): " .. HOLDS[i][1] .. " snaps back", before.shrinks > 0, true)
end
-- All the holds one after the other on one pizza.
local all = {}
for _, h in HOLDS do
	table.insert(all, h[2])
end
local seq = replay(true, all)
check("all holds in a row: never shrinks", seq.shrinks, 0)
check("all holds in a row: nothing changes on release", seq.releaseJumps, 0)

------------------------------------------------------------------------------------------
-- 6. The pointer changes when the dough shows ready, not on the release (Open 12). Three full
-- passes, each its own hold; the third makes the dough ready while it is held.

local threeHolds = { { { 0, 0.9 }, { 0, -0.9 } }, { { 0, -0.9 }, { 0, 0.9 } }, { { 0, 0.9 }, { 0, -0.9 } } }
local a3 = replay(true, threeHolds)
local b3 = replay(false, threeHolds)
check("three held passes: ready at the end", ready(MakeDough.shape(dough({ pass(90), pass(270), pass(90) }))), true)
check("after: the pointer never changes on a release", a3.adviceAtRelease, 0)
check("before (slice 6): the pointer changed on a release", b3.adviceAtRelease > 0, true)
note(string.format("three held passes: pointer changes at release, before %d, after %d", b3.adviceAtRelease, a3.adviceAtRelease))

------------------------------------------------------------------------------------------
-- 7. Passes past ready are not stored (Astra r19 / staging note: stored no-op passes would spend
-- the 24-stroke cap, stop the preview and make Undo take back a pass that changed nothing).

local readyMake = dough({ pass(90), pass(270), pass(90) }, fullFlour)
local readyShape = MakeDough.shape(readyMake)
local readyGrade = MakeDough.grade(readyMake)
check("a pass on a ready dough is not stored", (MakeDough.validateRoll(readyMake, pass(0))), nil)
check("a pass on a ready dough is not previewed", has and MakeDough.keptPass(readyMake, pass(0)) == nil, true)
-- A long held back-and-forth (sixteen turns in one hold) on the ready dough, as the station
-- commits it: nothing stored, same shape, same grade.
do
	local pts = { { x = 0, y = 0.9 } }
	for k = 1, 16 do
		walk(pts, pts[#pts], { x = 0, y = if k % 2 == 1 then -0.9 else 0.9 }, 0.04)
	end
	local drag = MakeDough.rollDrag(pts[1])
	local sent = 0
	local function commit(l: any)
		if l and (l.x2 - l.x1) ^ 2 + (l.y2 - l.y1) ^ 2 >= cfg.minStroke ^ 2 and MakeDough.validateRoll(readyMake, l) then
			sent += 1
			table.insert(readyMake.strokes, l)
		end
	end
	local changed = 0
	for i = 2, #pts do
		commit(drag.move(pts[i]))
		if has and not same(MakeDough.preview(readyMake, drag.line()), readyShape) then
			changed += 1
		end
	end
	commit(drag.close())
	check("long hold on a ready dough: no pass stored", sent, 0)
	check("long hold on a ready dough: the shown dough never changes", changed, 0)
	check("long hold on a ready dough: same shape", same(MakeDough.shape(readyMake), readyShape), true)
	check("long hold on a ready dough: same grade", MakeDough.grade(readyMake).score, readyGrade.score)
	-- Undo then takes back the third roll, the last one that counted.
	local undone = dough({ pass(90), pass(270) }, fullFlour)
	check("Undo after extra rolling takes back the last roll that counted", #readyMake.strokes, 3)
	check("after that Undo the dough is small again", MakeDough.rollAdvice(undone), "small")
end
-- Capacity: 24 passes that only graze the dough's edge (each stored through validateRoll) leave
-- it short of ready. A 25th is refused, and the held 25th shows no growth.
do
	local m = dough({})
	for k = 1, cfg.maxStrokes do
		local side = if k % 2 == 1 then 1 else -1
		local x = side * (G.radiusAlong(MakeDough.shape(m), { x = 1, y = 0 }) - 0.0003)
		local l = MakeDough.validateRoll(m, { x1 = x, y1 = -0.4, x2 = x, y2 = 0.4 })
		if l then
			table.insert(m.strokes, l)
		end
	end
	check("capacity: 24 grazing passes stored", #m.strokes, cfg.maxStrokes)
	local S = MakeDough.shape(m)
	check("capacity: 24 grazing passes are not ready", ready(S), false)
	note(string.format("capacity fixture: 24 grazing passes, mean radius %.4f", meanOf(S)))
	check("capacity: a 25th pass is refused", (MakeDough.validateRoll(m, pass(0))), nil)
	check("capacity: the held 25th shows no growth", has and same(MakeDough.preview(m, pass(0)), S), true)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("roll option B checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

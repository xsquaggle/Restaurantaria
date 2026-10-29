-- Checks for freehand cuts: the shared path grading (Scoring.cutPath, cutQuality, cut), the
-- path resampling the client sends, and the server's cut action, which grades and keeps the
-- path and refuses bad input without changing the pizza. Expected values are worked by hand
-- from the geometry (see the comments), never from the helpers under test. Run offline with
-- tests/offline/run.py, or in Studio Edit after a sync. Arithmetic only: how the groove looks
-- and how a real drag feels are checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
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

local cfg = Config.Cut
-- The proposed constants this file's hand-worked values assume.
check("proposal: crust radius", cfg.crustRadius, 0.95)
check("proposal: straight perfect", cfg.straightPerfect, 0.04)
check("proposal: straight zero", cfg.straightZero, 0.2)
check("proposal: complete full", cfg.completeFull, 0.95)
check("proposal: complete zero", cfg.completeZero, 0.5)
check("proposal: min complete", cfg.minComplete, 0.25)
check("proposal: max points", cfg.maxPoints, 48)
check("proposal: min drag share", cfg.minDragShare, 0.47)

-- 1. A straight drag across the whole pizza, left to right: deviation 0, the chord spans the
-- crust (x from -0.95 to 0.95), completeness 1, credit 1.
local c = Scoring.cutPath({ P(-1.05, 0), P(1.05, 0) }) :: any
check("straight full: accepted", c ~= nil, true)
near("straight full: straightness", c.straightness, 1)
near("straight full: completeness", c.completeness, 1)
near("straight full: chord starts at the left crust", c.x1, -0.95, 1e-9)
near("straight full: chord ends at the right crust", c.x2, 0.95, 1e-9)
near("straight full: credit", (Scoring.cutQuality(c)), 1)
check("straight full: path kept", #c.path, 2)

-- The chord points the way the cutter travelled: right to left gives x1 > x2.
local r = Scoring.cutPath({ P(1.05, 0), P(-1.05, 0) }) :: any
check("reversed: chord follows the drag", r.x1 > r.x2, true)
-- Diagonal, top-left to bottom-right: angle 45 degrees (y down).
local d = Scoring.cutPath({ P(-0.8, -0.8), P(0.8, 0.8) }) :: any
near("diagonal: angle", math.deg(math.atan2(d.y2 - d.y1, d.x2 - d.x1)), 45, 1e-6)
near("diagonal: completeness (starts and ends past the crust)", d.completeness, 1)

-- 2. Three quarters: from off the left edge to x = 0.475. Span inside the crust -0.95..0.475
-- = 1.425 of the 1.9 chord = 0.75; credit (0.75 - 0.5) / (0.95 - 0.5) = 0.5556.
local q3 = Scoring.cutPath({ P(-1.05, 0), P(0.475, 0) }) :: any
near("three quarters: completeness", q3.completeness, 0.75, 0.006)
near("three quarters: credit", (Scoring.cutQuality(q3)), 0.25 / 0.45, 0.014)

-- 3. Half: off the left edge to the centre. 0.95 / 1.9 = 0.5, which is completeZero: credit 0.
local h = Scoring.cutPath({ P(-1.05, 0), P(0, 0) }) :: any
near("half: completeness", h.completeness, 0.5, 0.006)
near("half: credit", (Scoring.cutQuality(h)), 0, 0.014)

-- 4. A fifth of the way (-1.5..-0.57; inside -0.95..-0.57): 0.38 / 1.9 = 0.2 < 0.25, refused.
local none, why = Scoring.cutPath({ P(-1.5, 0), P(-0.57, 0) })
check("a fifth: refused", none, nil)
check("a fifth: reason", why, "cut doesn't cross the pizza")

-- 5. A shallow chevron (-1.05,0)-(0,0.1)-(1.05,0). By symmetry the fitted line is horizontal
-- at the mean height of the inside part: y = 0.1 (1 - |x| / 1.05) averaged over |x| <= 0.95
-- = 0.1 (1 - 0.475 / 1.05) = 0.054762. Widest distance: the apex 0.1 - 0.054762 = 0.045238
-- (the crust ends, y = 0.009524, are as far on the other side). Since 7b-2 the wobble is measured
-- on the path averaged over Config.Cut.tremor (0.15) along it: around the apex the offset falls
-- off linearly at the leg's slope across the line, 0.0952 / sqrt(1 + 0.0952^2) = 0.0948 per unit
-- of path, so the 0.15 average sits 0.0948 x 0.0375 = 0.00356 below the apex: 0.04168 (the ends,
-- averaged over the half window inside, the same). Straightness 1 - (0.04168 - 0.04) / 0.16
-- = 0.9895. The widest raw distance stays 0.045238 (rawDeviation). Completeness 1.
local ch = Scoring.cutPath({ P(-1.05, 0), P(0, 0.1), P(1.05, 0) }) :: any
near("chevron 0.1: fitted height", (ch.y1 + ch.y2) / 2, 0.054762, 0.0005)
near("chevron 0.1: deviation", ch.deviation, 0.04168, 0.0005)
near("chevron 0.1: raw deviation", ch.rawDeviation, 0.045238, 0.0005)
near("chevron 0.1: straightness", ch.straightness, 0.9895, 0.004)
near("chevron 0.1: completeness", ch.completeness, 1, 1e-6)

-- 6. A deep chevron, apex 0.3: mean height 0.3 x 0.547619 = 0.164286; apex distance 0.135714;
-- crust end (x = 0.9496, y = 0.0287) distance 0.1356. Averaged over 0.15 of path: the slope
-- across the line is 0.2857 / sqrt(1 + 0.2857^2) = 0.2747, so 0.1357 - 0.2747 x 0.0375 = 0.1254;
-- straightness 1 - (0.1254 - 0.04) / 0.16 = 0.466 (0.402 on the widest raw distance). Its fitted line sits 0.164 from the centre, so its chord is 2 x 0.9357, and the path
-- spans past both ends: completeness 1.
local deep = Scoring.cutPath({ P(-1.05, 0), P(0, 0.3), P(1.05, 0) }) :: any
near("chevron 0.3: deviation", deep.deviation, 0.1254, 0.001)
near("chevron 0.3: straightness", deep.straightness, 0.466, 0.008)
near("chevron 0.3: completeness", deep.completeness, 1, 1e-6)

-- 7. A hand wobble of amplitude 0.03 along a diameter (sine, five waves) stays within the 0.04
-- allowance: straightness 1.
local wob = {}
for i = 0, 40 do
	local x = -1.05 + 2.1 * i / 40
	table.insert(wob, P(x, 0.03 * math.sin(i / 40 * 10 * math.pi)))
end
local w = Scoring.cutPath(wob) :: any
near("wobble 0.03: straightness", w.straightness, 1)
-- Amplitude 0.12: the fitted line stays at y ~ 0, the widest distance ~0.12. Its wavelength is
-- 2.1 / 5 = 0.42; a 0.15 average keeps sin(pi 0.15 / 0.42) / (pi 0.15 / 0.42) = 0.803 of it:
-- 0.0964, straightness 1 - (0.0964 - 0.04) / 0.16 = 0.65 (the 41-point path's corners take a
-- little more off).
for i, p in wob do
	p.y = 0.12 * math.sin((i - 1) / 40 * 10 * math.pi)
end
local w2 = Scoring.cutPath(wob) :: any
near("wobble 0.12: straightness", w2.straightness, 0.64, 0.02)
-- Wandering off the pizza does not count against straightness: only the part inside the crust
-- is graded. A straight cut with a hook far outside (at x = 1.4) is still straight.
local hook = Scoring.cutPath({ P(-1.05, 0), P(1.3, 0), P(1.4, 0.6) }) :: any
near("hook off the pizza: straightness", hook.straightness, 1)

-- 8. Refusals.
local function refused(name: string, points: any, reason: string)
	local got, msg = Scoring.cutPath(points)
	check(name .. ": refused", got, nil)
	check(name .. ": reason", msg, reason)
end
refused("nil", nil, "cut path missing")
refused("one point", { P(0, 0) }, "cut path missing")
refused("map, not a list", { a = P(-1, 0), b = P(1, 0) }, "cut path missing")
refused("list with a hole", { [1] = P(-1, 0), [2] = P(0, 0), [4] = P(1, 0) }, "cut path missing")
-- A two-point list stuffed with 1,000 extra keys is refused (key counting stops one past the
-- list's length, so the stuffing costs nothing).
local stuffed: any = { P(-1.05, 0), P(1.05, 0) }
for i = 1, 1000 do
	stuffed["k" .. i] = i
end
refused("list stuffed with extra keys", stuffed, "cut path missing")
-- The count is bounded: the same stuffed list, iterated through a counting __iter, is walked
-- at most three steps (two entries and one past). 734f244 walked all 1,002 keys.
local steps = 0
local counted: any = table.clone(stuffed)
setmetatable(counted, {
	__iter = function(t)
		return function(_, k)
			local nk, v = next(t, k)
			if nk ~= nil then
				steps += 1
			end
			return nk, v
		end, t, nil
	end,
})
refused("stuffed list, counted", counted, "cut path missing")
check("stuffed list: key counting stops one past the length", steps <= 3, true)
-- A 49-point list (one over the cap) stuffed with extra keys is refused on its length before
-- any key is counted ("cut path too long"; 734f244 counted first and said "cut path missing").
local stuffedLong: any = {}
for i = 1, cfg.maxPoints + 1 do
	stuffedLong[i] = P(-1.05 + 2.1 * (i - 1) / cfg.maxPoints, 0)
end
for i = 1, 1000 do
	stuffedLong["k" .. i] = i
end
refused("49 points stuffed with extra keys", stuffedLong, "cut path too long")
local many = {}
for i = 1, cfg.maxPoints + 1 do
	table.insert(many, P(-1.05 + 2.1 * (i - 1) / cfg.maxPoints, 0))
end
refused("over the point cap", many, "cut path too long")
table.remove(many)
check("at the point cap: accepted", Scoring.cutPath(many) ~= nil, true)
refused("NaN", { P(-1, 0), P(0 / 0, 0) }, "cut out of range")
refused("infinity", { P(-1, 0), P(math.huge, 0) }, "cut out of range")
refused("out of range", { P(-1, 0), P(1.7, 0) }, "cut out of range")
refused("string coordinate", { P(-1, 0), { x = "1", y = 0 } }, "cut out of range")
refused("point not a table", { P(-1, 0), 5 }, "cut out of range")
refused("too short", { P(-0.4, 0), P(0.4, 0) }, "cut too short")
refused("misses the pizza", { P(-1.5, 1.2), P(1.5, 1.2) }, "cut missed the pizza")
refused("touches the crust only", { P(-1.5, 0.96), P(1.5, 0.96) }, "cut missed the pizza")

-- 9. Resampling: a 200-point drag comes back as 48 points, evenly spaced, both ends kept.
local long = {}
for i = 0, 199 do
	local x = -1.2 + 2.4 * i / 199
	table.insert(long, P(x, 0.05 * math.sin(x * 3)))
end
local rs = Scoring.resamplePath(long, cfg.maxPoints)
check("resample: point count", #rs, cfg.maxPoints)
near("resample: first kept", rs[1].x, -1.2)
near("resample: last kept", rs[#rs].x, 1.2)
local gaps = {}
for i = 2, #rs do
	table.insert(gaps, math.sqrt((rs[i].x - rs[i - 1].x) ^ 2 + (rs[i].y - rs[i - 1].y) ^ 2))
end
table.sort(gaps)
check("resample: evenly spaced (spread under 5 %)", (gaps[#gaps] - gaps[1]) / gaps[#gaps] < 0.05, true)
check("resample: short paths unchanged", #Scoring.resamplePath({ P(0, 0), P(1, 0) }, cfg.maxPoints), 2)
check("resample: result is accepted", Scoring.cutPath(rs) ~= nil, true)

-- 10. The cut grade: layout (count, evenness, centre) times the mean path credit.
local function line(deg: number, path: { any }?): any
	local a = math.rad(deg)
	local pts = path or { P(-math.cos(a) * 1.05, -math.sin(a) * 1.05), P(math.cos(a) * 1.05, math.sin(a) * 1.05) }
	return (Scoring.cutPath(pts))
end
local four = { line(0), line(45), line(90), line(135) }
local g = Scoring.cut(8, four)
check("grade: four straight full cuts", g.score, 100)
check("grade: no notes", #g.notes, 0)
check("grade: detail layout", g.detail.layout, 100)
check("grade: detail path", g.detail.path, 100)
check("grade: per-cut detail kept", #g.detail.cuts, 4)
-- One three-quarter cut (credit 0.5556): mean (3 + 0.5556) / 4 = 0.8889, grade 89.
local partial = { line(0), line(45), line(90), Scoring.cutPath({ P(-1.05 * math.cos(math.rad(135)), -1.05 * math.sin(math.rad(135))), P(0.475 * math.cos(math.rad(135)), 0.475 * math.sin(math.rad(135))) }) :: any }
local gp = Scoring.cut(8, partial)
near("grade: one cut three quarters", gp.score, 89, 1)
check("grade: short note", table.find(gp.notes, "1 cut stopped short of the crust") ~= nil, true)
-- One three-quarter cut on a 2-slice order: 1 x 0.5556 = 56.
near("grade: 2 slices, one three-quarter cut", Scoring.cut(2, { q3 }).score, 56, 1)
-- Two deep chevrons (straightness 0.466) at 0 and 90 degrees for 4 slices. Each fitted line
-- sits 0.164 off centre, 0.004 past the 0.16 tolerance. Since 7b-2 the centre penalty ramps in
-- over centreRamp 0.1: 0.25 x 0.04 = 0.01 off the layout per cut. The line is off centre because
-- of the bend, and the bend takes more ((1 - 0.466) / 2 = 0.267 off the mean path credit), so
-- only the bend is charged: layout 1, grade 100 x 1 x 0.466 = 47, and no centre note. (Before
-- 7b-2 both were charged: 100 x 0.5 x 0.402 = 20.)
local chev90 = Scoring.cutPath({ P(0, -1.05), P(0.3, 0), P(0, 1.05) }) :: any
local gc = Scoring.cut(4, { deep, chev90 })
near("grade: two deep chevrons", gc.score, 47, 1)
check("grade: wobble note", table.find(gc.notes, "2 cuts wobbled off a straight line") ~= nil, true)
check("grade: no centre note when the bend is what is charged", table.find(gc.notes, "2 cuts missed the centre"), nil)
-- The centre penalty ramps in (7b-2): one straight full cut for 2 slices, offset d from the
-- centre: layout 1 - 0.25 x clamp((d - 0.16) / 0.1), so d 0.16 -> 100, 0.17 -> 97.5 (98),
-- 0.21 -> 87.5 (88), 0.26 and 0.30 -> 75. Before 7b-2: 100 up to 0.16, 75 just past it.
for _, case in { { 0.16, 100 }, { 0.17, 98 }, { 0.21, 88 }, { 0.26, 75 }, { 0.3, 75 } } do
	local d = case[1]
	local g1 = Scoring.cut(2, { { x1 = -1, y1 = d, x2 = 1, y2 = d, straightness = 1, completeness = 1 } })
	check(string.format("centre ramp: offset %.2f", d), g1.score, case[2])
	check(string.format("centre ramp: offset %.2f note", d), table.find(g1.notes, "1 cut missed the centre") ~= nil, case[2] <= 97)
end
-- Lines without path grades (old fixtures) count as straight and full: unchanged score.
check("grade: plain lines unchanged", Scoring.cut(4, { { x1 = -1, y1 = 0, x2 = 1, y2 = 0 }, { x1 = 0, y1 = -1, x2 = 0, y2 = 1 } }).score, 100)
check("grade: uncut", Scoring.cut(8, {}).score, 0)
note(string.format("worked grades: 4 straight full = %d; one 3/4 cut = %d; two deep chevrons (4 slices) = %d", g.score, gp.score, gc.score))

-- 10b. Oval pizzas (slice 1, 2026-10-27): cuts are clipped and graded against the made pizza's
-- own dough outline S (pizza-local; the outline is S applied to the unit circle). Hand-worked from
-- the ellipse x^2 / a^2 + y^2 / b^2 = 1 (axis-aligned) or its rotation; the "before" values are
-- the round-crust rule's (S omitted), shown for the hand-off table.
local WORST = G.shape(1.1, 0.35, 0) -- the slice-3 worst oval (long axis at the 1.1 cap, short at the ball's 0.35)
-- A short-axis stroke across the worst oval, (0, -0.4) to (0, 0.4): 0.8 long. Its chord across
-- the dough is 2 x 0.35 = 0.7 (minimum drag 0.47 x 0.7 = 0.329), the path spans all of it.
-- Before: refused, 0.8 is under the round rule's fixed 0.9.
local shortAxis = { P(0, -0.4), P(0, 0.4) }
local sa = Scoring.cutPath(shortAxis, WORST) :: any
check("oval short axis: accepted", sa ~= nil, true)
near("oval short axis: completeness", sa.completeness, 1)
near("oval short axis: chord starts at the dough's edge", sa.y1, -0.35, 1e-9)
near("oval short axis: chord ends at the dough's edge", sa.y2, 0.35, 1e-9)
local _, saWhy = Scoring.cutPath(shortAxis)
check("oval short axis, round rule (before): refused", saWhy, "cut too short")
-- The same stroke drawn just past the board side of the oval, (0, -0.6) to (0, 0.6): accepted,
-- complete. Before: graded against the round crust, 1.2 of 1.9 = 0.632, credit 0.29.
local sb = Scoring.cutPath({ P(0, -0.6), P(0, 0.6) }, WORST) :: any
near("oval short axis, long drag: completeness", sb.completeness, 1)
near("oval short axis, long drag, round rule (before): completeness", (Scoring.cutPath({ P(0, -0.6), P(0, 0.6) }) :: any).completeness, 1.2 / 1.9, 1e-6)
-- A drag across bare board only (y = 0.6, below the oval's 0.35 edge): refused. Before: the round
-- crust reached it (half chord sqrt(0.95^2 - 0.6^2) = 0.7365), so it counted as a full cut.
local bare = { P(-1.05, 0.6), P(1.05, 0.6) }
local nb, nbWhy = Scoring.cutPath(bare, WORST)
check("oval bare board only: refused", nb, nil)
check("oval bare board only: reason", nbWhy, "cut missed the pizza")
near("oval bare board only, round rule (before): counted complete", (Scoring.cutPath(bare) :: any).completeness, 1)
-- Along the long axis, (-1.2, 0) to (1.2, 0): the chord is the dough's 2.2 (x from -1.1 to 1.1),
-- complete. Before: clipped at the round 0.95, so the groove stopped short of the dough's ends.
local la = Scoring.cutPath({ P(-1.2, 0), P(1.2, 0) }, WORST) :: any
near("oval long axis: chord start", la.x1, -1.1, 1e-9)
near("oval long axis: chord end", la.x2, 1.1, 1e-9)
near("oval long axis: completeness", la.completeness, 1)
-- Half way along the long axis, (-1.2, 0) to (0, 0): 1.1 of 2.2 = 0.5, credit 0.
local lh = Scoring.cutPath({ P(-1.2, 0), P(0, 0) }, WORST) :: any
near("oval long axis, half: completeness", lh.completeness, 0.5, 0.006)
-- A partial short-axis stroke, (0, -0.6) to (0, 0.1): on the dough -0.35..0.1 = 0.45 of 0.7
-- = 0.643; the drag (0.7) is over the 0.329 minimum.
near("oval short axis, partial: completeness", (Scoring.cutPath({ P(0, -0.6), P(0, 0.1) }, WORST) :: any).completeness, 0.45 / 0.7, 0.006)
-- Straightness stays in frame units: a 0.03 sine wobble across the narrow way is still straight,
-- and a 0.12 wobble scores as it would on a round pizza (0.5), not magnified by the thin axis.
local wobS = {}
for i = 0, 40 do
	local y = -0.6 + 1.2 * i / 40
	table.insert(wobS, P(0.03 * math.sin(i / 40 * 10 * math.pi), y))
end
near("oval narrow-way wobble 0.03: straightness", (Scoring.cutPath(wobS, WORST) :: any).straightness, 1)
-- A 45-degree frame line through the centre meets the oval at x = y = 1 / sqrt(1/1.1^2 + 1/0.35^2)
-- = 0.33353; in dough-local units (0.95 S^-1 p) its direction is atan2(0.95/0.35, 0.95/1.1) =
-- 72.35 degrees.
local diag = Scoring.cutPath({ P(-0.6, -0.6), P(0.6, 0.6) }, WORST) :: any
near("oval 45-degree frame line: chord end x", diag.x2, 0.33353, 1e-4)
local q2 = G.toDough(WORST, { x = diag.x2, y = diag.y2 })
near("oval 45-degree frame line: dough-local angle", math.deg(math.atan2(q2.y, q2.x)), 72.35, 0.01)

-- Slices on an oval: four cuts through the centre at equal angles in dough-local units (frame
-- direction S (cos a, sin a)) cut equal-area slices and grade 100. Four cuts at equal FRAME
-- angles (0, 45, 90, 135) are dough-local 0, 72.35, 90, 107.65: gaps 72.35, 17.65, 17.65, 72.35,
-- mean error 27.35 from 45, evenness 1 - (27.35 - 5) / 25 = 0.106, layout 0.5 + 0.053 = 0.553,
-- grade 55 (uneven slices); the round rule (before) called them perfect, 100.
local function doughLine(S: any, deg: number, reach: number?): any
	local a = math.rad(deg)
	local d = G.apply(S, { x = math.cos(a), y = math.sin(a) })
	local k = (reach or 1.3) / math.sqrt(d.x * d.x + d.y * d.y)
	return Scoring.cutPath({ P(-d.x * k, -d.y * k), P(d.x * k, d.y * k) }, S)
end
local function frameLine(S: any, deg: number): any
	local a = math.rad(deg)
	return Scoring.cutPath({ P(-math.cos(a) * 1.3, -math.sin(a) * 1.3), P(math.cos(a) * 1.3, math.sin(a) * 1.3) }, S)
end
local fair = { doughLine(WORST, 0), doughLine(WORST, 45), doughLine(WORST, 90), doughLine(WORST, 135) }
check("oval, equal dough-local angles: 8 slices", Scoring.cut(8, fair, WORST).score, 100)
local frameEq = { frameLine(WORST, 0), frameLine(WORST, 45), frameLine(WORST, 90), frameLine(WORST, 135) }
near("oval, equal frame angles: 8 slices", Scoring.cut(8, frameEq, WORST).score, 55, 1)
check("oval, equal frame angles: uneven note", table.find(Scoring.cut(8, frameEq, WORST).notes, "Slices were uneven sizes") ~= nil, true)
check("oval, equal frame angles, round rule (before): 100", Scoring.cut(8, frameEq).score, 100)
-- 4 and 6 slices on the oval, equal dough-local angles: 100.
check("oval, 4 slices fair", Scoring.cut(4, { doughLine(WORST, 0), doughLine(WORST, 90) }, WORST).score, 100)
check("oval, 6 slices fair", Scoring.cut(6, { doughLine(WORST, 0), doughLine(WORST, 60), doughLine(WORST, 120) }, WORST).score, 100)
-- Reversed drags (each line drawn the other way) grade the same.
local function reversed(c: any): any
	local pts = {}
	for i = #c.path, 1, -1 do
		table.insert(pts, c.path[i])
	end
	return Scoring.cutPath(pts, WORST)
end
check("oval, reversed drags: same grade", Scoring.cut(8, { reversed(fair[1]), reversed(fair[2]), reversed(fair[3]), reversed(fair[4]) }, WORST).score, 100)
-- A duplicate cut (the same line twice) for 4 slices: gaps 0 and 180 against 90, evenness 0,
-- layout 0.5, grade 50, as on a round pizza.
check("oval, duplicate cut: 4 slices", Scoring.cut(4, { fair[1], fair[1] }, WORST).score, 50)
check("round, duplicate cut (same rule): 4 slices", Scoring.cut(4, { line(0), line(0) }).score, 50)
-- A rotated oval (the worst oval turned 30 degrees) and the same fair layout turned with it:
-- the same grade (rotation turns every dough-local angle by the same amount).
local ROT = G.shape(1.1, 0.35, math.rad(30))
check("rotated oval, fair 8 slices", Scoring.cut(8, { doughLine(ROT, 0), doughLine(ROT, 45), doughLine(ROT, 90), doughLine(ROT, 135) }, ROT).score, 100)
local rotFrame = { frameLine(ROT, 30), frameLine(ROT, 75), frameLine(ROT, 120), frameLine(ROT, 165) }
near("rotated oval, equal frame angles turned 30 degrees: same as unrotated", Scoring.cut(8, rotFrame, ROT).score, Scoring.cut(8, frameEq, WORST).score, 1e-9)
-- A sheared oval: the outline of A applied to the unit circle, A = [0.95 0.4; 0 0.6]. Its S is
-- the symmetric factor sqrt(A A^T) (same outline). Lines along A (cos a, sin a) split it into
-- equal areas (A maps equal circle sectors to equal-area sectors), so equal a grade 100.
local A = { a = 0.95, b = 0.4, c = 0, d = 0.6 }
local AAt = G.mul(A, { a = A.a, b = A.c, c = A.b, d = A.d })
local tr, det = AAt.a + AAt.d, AAt.a * AAt.d - AAt.b * AAt.c
local sdet = math.sqrt(det)
local tt = math.sqrt(tr + 2 * sdet)
local SHEAR = { a = (AAt.a + sdet) / tt, b = AAt.b / tt, c = AAt.c / tt, d = (AAt.d + sdet) / tt }
local function shearLine(deg: number): any
	local a = math.rad(deg)
	local d = G.apply(A, { x = math.cos(a), y = math.sin(a) })
	local k = 1.4 / math.sqrt(d.x * d.x + d.y * d.y)
	return Scoring.cutPath({ P(-d.x * k, -d.y * k), P(d.x * k, d.y * k) }, SHEAR)
end
for _, deg in { 0, 90, 200 } do
	local a = math.rad(deg)
	local e = G.apply(A, { x = math.cos(a), y = math.sin(a) })
	local u = G.apply(G.inverse(SHEAR), e)
	near("sheared oval: A's circle point " .. deg .. " lies on S's outline", u.x * u.x + u.y * u.y, 1, 1e-9)
end
check("sheared oval, fair 8 slices", Scoring.cut(8, { shearLine(0), shearLine(45), shearLine(90), shearLine(135) }, SHEAR).score, 100)
check("sheared oval, fair 6 slices", Scoring.cut(6, { shearLine(10), shearLine(70), shearLine(130) }, SHEAR).score, 100)
-- Hand-like strokes: drawn as the client records them (a point every 0.03, jitter up to 0.012,
-- a slight bow of 0.02) and resampled to the 48 points it sends. Deterministic. Synthetic, not a
-- recorded real stroke: the Studio-recorded paths are in the hand-off.
local seed = 7
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648 * 2 - 1
end
local function handStroke(S: any, deg: number, from: number, to: number): any
	local a = math.rad(deg)
	local d = G.apply(S, { x = math.cos(a), y = math.sin(a) })
	local len = math.sqrt(d.x * d.x + d.y * d.y)
	local ux, uy = d.x / len, d.y / len
	local pts = {}
	local n = math.floor((to - from) * len / 0.03)
	for i = 0, n do
		local t = from * len + (to - from) * len * i / n
		local bow = 0.02 * math.sin(math.pi * i / n)
		table.insert(pts, P(ux * t - uy * (bow + 0.012 * rnd()), uy * t + ux * (bow + 0.012 * rnd())))
	end
	return Scoring.cutPath(Scoring.resamplePath(pts, cfg.maxPoints), S)
end
local hand = {}
for _, deg in { 0, 45, 90, 135 } do
	table.insert(hand, (handStroke(WORST, deg, -1.25, 1.25)))
end
local hg = Scoring.cut(8, hand, WORST)
check("oval, careful hand strokes: all accepted", #hand, 4)
check("oval, careful hand strokes: 8 slices grade at least 90", hg.score >= 90, true)
local short = handStroke(WORST, 90, -1.1, 1.1)
check("oval, hand stroke across the narrow way: accepted", short ~= nil, true)
note(string.format("oval (1.1 x 0.35): fair 8 slices = %d; equal frame angles = %d (round rule %d); hand strokes = %d",
	Scoring.cut(8, fair, WORST).score, Scoring.cut(8, frameEq, WORST).score, Scoring.cut(8, frameEq).score, hg.score))

-- 11. The server's cut action grades and keeps the path; refusals leave the pizza unchanged.
local pizza = { id = 7, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
local session = { shift = { pizzas = { [7] = pizza } } } :: any
local ok, reason = ShiftService.apply(session, "cut", { pizzaId = 7, path = { P(-1.05, 0), P(0, 0.1), P(1.05, 0) } })
check("server: freehand cut accepted", ok, true)
check("server: one cut stored", #pizza.cuts, 1)
check("server: path stored", #pizza.cuts[1].path, 3)
near("server: straightness stored", pizza.cuts[1].straightness, 0.9895, 0.004)
check("server: stored path is a copy", pizza.cuts[1].path[2] ~= nil and pizza.cuts[1].path[2].y, 0.1)
local function refusedOnServer(name: string, args: any, want: string)
	local before = #pizza.cuts
	local okR, why = ShiftService.apply(session, "cut", args)
	check("server " .. name .. ": refused", okR, false)
	check("server " .. name .. ": reason", why, want)
	check("server " .. name .. ": nothing stored", #pizza.cuts, before)
end
refusedOnServer("old straight-line args", { pizzaId = 7, x1 = -1.05, y1 = 0, x2 = 1.05, y2 = 0 }, "cut path missing")
refusedOnServer("NaN path", { pizzaId = 7, path = { P(-1, 0), P(0 / 0, 0) } }, "cut out of range")
refusedOnServer("a fifth of the way", { pizzaId = 7, path = { P(-1.5, 0), P(-0.57, 0) } }, "cut doesn't cross the pizza")
refusedOnServer("wrong pizza", { pizzaId = 8, path = { P(-1.05, 0), P(1.05, 0) } }, "no such pizza")
for i = 2, cfg.maxLines do
	ShiftService.apply(session, "cut", { pizzaId = 7, path = { P(-1.05, 0), P(1.05, 0) } })
end
check("server: four cuts stored", #pizza.cuts, cfg.maxLines)
refusedOnServer("fifth cut", { pizzaId = 7, path = { P(-1.05, 0), P(1.05, 0) } }, "already cut 4 times")
check("server: undo", (ShiftService.apply(session, "undoCut", { pizzaId = 7 })), true)
check("server: undo removed the last", #pizza.cuts, cfg.maxLines - 1)
_ = reason
-- The server grades against the pizza's own dough from its made record (never the client's):
-- one full pass along x, 0.60 x 0.56 (the three-pass roll model, 2026-10-28; this was the 1.1 x
-- 0.35 oval of eight passes before).
local ovalMake = { step = "toppings", placed = true, flour = {}, strokes = {}, sauce = { actions = {} }, cheese = { strokes = {} } }
table.insert(ovalMake.strokes, { x1 = -1.2, y1 = 0, x2 = 1.2, y2 = 0 })
local ovalPizza = { id = 9, ticketId = 2, stage = "cutting", make = ovalMake, toppings = {}, cuts = {} }
session.shift.pizzas[9] = ovalPizza
local e = G.axes(Scoring.footprint(ovalMake))
check("server oval: footprint is the rolled dough", math.abs(e.major - 0.60) < 1e-9 and math.abs(e.minor - 0.56) < 1e-9, true)
check("server oval: footprint without a dough on the board is the round crust", Scoring.footprint({ placed = false, strokes = {} }).a, 0.95)
local okB, whyB = ShiftService.apply(session, "cut", { pizzaId = 9, path = { P(-1.05, 0.6), P(1.05, 0.6) } })
check("server oval: bare-board drag refused", okB, false)
check("server oval: bare-board reason", whyB, "cut missed the pizza")
check("server oval: nothing stored", #ovalPizza.cuts, 0)
check("server oval: short-axis stroke accepted", (ShiftService.apply(session, "cut", { pizzaId = 9, path = { P(0, -0.7), P(0, 0.7) } })), true)
near("server oval: stored chord ends at the dough's edge", ovalPizza.cuts[1].y2, 0.56, 1e-6)
near("server oval: stored completeness", ovalPizza.cuts[1].completeness, 1, 1e-6)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

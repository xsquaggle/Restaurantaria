-- Checks for the Cut grade where a cut both bends and misses the centre (slice 8a, Astra r21
-- S21-01). Since 7b-2 such a cut is charged one fault, never both; 7b-2 picked which by
-- comparing a layout share with a path-credit share, then multiplied the two later, so the
-- grade jumped where the choice switched (her fixture: offset 0.2399 -> 0.2401 took the Cut
-- score 48 -> 40). Now both choices are scored in final Cut points and the lower score is kept
-- (the larger cost). These checks hold the grade to: her fixture worked by hand, continuity
-- and monotonicity across the centre ramp (0.16 to 0.26) and the switch, never charging both,
-- and many-cut combinations. Arithmetic only, no Studio. Expected values are worked from the
-- formula in the comments, never from Scoring itself.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)

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

local cfg = Config.Cut
check("proposal: centre tolerance", cfg.centreTolerance, 0.16)
check("proposal: centre ramp", cfg.centreRamp, 0.1)
check("proposal: complete full", cfg.completeFull, 0.95)

-- A complete cut at `deg` whose line sits `d` from the centre in dough-local units, with the
-- given straightness (set directly, as Astra's fixture does). The frame-to-dough scale is
-- measured once with Scoring.cutOffset (it is linear for the round pizza).
local function frameLine(deg: number, h: number): any
	local a = math.rad(deg)
	local ux, uy = math.cos(a), math.sin(a)
	local nx, ny = -uy, ux
	return { x1 = -ux * 0.95 + nx * h, y1 = -uy * 0.95 + ny * h, x2 = ux * 0.95 + nx * h, y2 = uy * 0.95 + ny * h }
end
local SCALE = Scoring.cutOffset(frameLine(0, 0.1)) / 0.1
local function cut(deg: number, d: number, straight: number): any
	local l = frameLine(deg, d / SCALE)
	l.straightness = straight
	l.completeness = 1
	return l
end
check("fixture: offset helper lands on the asked offset", math.abs(Scoring.cutOffset(cut(30, 0.2399, 1)) - 0.2399) < 1e-9, true)

-- By hand, two cuts at 0 and 65 degrees (4 slices): gaps 65 and 115 against ideal 90, mean
-- error 25 degrees, evenness 1 - (25 - 5) / 25 = 0.2; count 1; layout before any centre
-- charge 0.5 + 0.1 = 0.6. Cut 1 straightness s at offset d, cut 2 straight and centred.
-- Centre charge m = 0.25 x clamp((d - 0.16) / 0.1). Charging the bend: 100 x 0.6 x (s + 1) / 2.
-- Charging the centre: 100 x (0.6 - m) x 1. The grade is the lower of the two.
local function byHand(d: number, s: number): number
	local m = 0.25 * math.clamp((d - 0.16) / 0.1, 0, 1)
	local bend = 100 * 0.6 * (s + 1) / 2
	local centre = 100 * math.clamp(0.6 - m, 0, 1)
	if m <= 0 then
		return bend
	elseif s >= 1 then
		return centre
	end
	return math.min(bend, centre)
end
local function grade(d: number, s: number): any
	return Scoring.cut(4, { cut(0, d, s), cut(65, 0, 1) })
end

-- Astra's fixture. 7b-2 gave 48 then 40; the lower of the two at 0.2399 is the centre charge,
-- 100 x (0.6 - 0.19975) = 40.025 -> 40, and 39.975 -> 40 at 0.2401.
local a, b = grade(0.2399, 0.6), grade(0.2401, 0.6)
check("S21-01 fixture: offset 0.2399", a.score, 40)
check("S21-01 fixture: offset 0.2401", b.score, 40)
check("S21-01 fixture: no jump", math.abs(a.score - b.score) <= 1, true)
note(string.format("S21-01 fixture (two cuts 0 and 65 degrees, first straightness 0.6): offset 0.2399 -> %d, 0.2401 -> %d (7b-2: 48, 40)", a.score, b.score))

-- Sweep the offset 0.10 to 0.40 in steps of 0.0005 for several straightness values: the grade
-- matches the hand formula, never rises as the cut moves further out, and never steps by more
-- than one rounded point between neighbours (the true slope is at most 250 points per unit,
-- 0.125 per step).
local maxStep, rises, mismatches, sweepN = 0, 0, 0, 0
for _, s in { 1, 0.95, 0.9, 0.8, 0.6, 0.4, 0.2, 0 } do
	local prev = nil
	for k = 0, 600 do
		local d = 0.1 + k * 0.0005
		local g = grade(d, s).score
		sweepN += 1
		-- Within rounding: the measured angles carry float noise, so a hand value that lands on
		-- a half point may round either way.
		if math.abs(g - byHand(d, s)) > 0.5 + 1e-6 then
			mismatches += 1
		end
		if prev then
			maxStep = math.max(maxStep, math.abs(g - prev))
			if g > prev then
				rises += 1
			end
		end
		prev = g
	end
end
check("ramp sweep: grade equals the hand formula", mismatches, 0)
check("ramp sweep: never rises as the offset grows", rises, 0)
check("ramp sweep: at most one point between neighbouring offsets", maxStep <= 1, true)
note(string.format("Offset sweep 0.10 to 0.40, eight straightness values, %d grades: largest step %d point(s), %d rises, %d off the hand formula", sweepN, maxStep, rises, mismatches))

-- Straightness sweep at fixed offsets: more straightness never lowers the grade, no jumps.
local sRises, sStep = 0, 0
for _, d in { 0.15, 0.16, 0.17, 0.2, 0.2399, 0.2401, 0.26, 0.3 } do
	local prev = nil
	for k = 0, 400 do
		local s = k / 400
		local g = grade(d, s).score
		if prev then
			sStep = math.max(sStep, math.abs(g - prev))
			if g < prev then
				sRises += 1
			end
		end
		prev = g
	end
end
check("straightness sweep: a straighter cut never scores lower", sRises, 0)
check("straightness sweep: at most one point between neighbours", sStep <= 1, true)

-- Boundaries: exactly at the tolerance nothing is charged for the centre; at the end of the
-- ramp the full step; just inside and outside each give the same grade within a point.
for _, edge in { 0.16, 0.26 } do
	for _, s in { 1, 0.6, 0.2 } do
		local lo, hi = grade(edge - 1e-6, s).score, grade(edge + 1e-6, s).score
		check(string.format("boundary %.2f straightness %.1f: continuous", edge, s), math.abs(lo - hi) <= 1, true)
	end
end
check("boundary: straight cut at the tolerance scores full layout", grade(0.16, 1).score, 60)
check("boundary: straight cut at the ramp end loses the full step", grade(0.26, 1).score, 35)

-- Never both: the grade is never below the score with both faults charged, and never above
-- either single charge.
local belowBoth, aboveSingle = 0, 0
for _, d in { 0.17, 0.2, 0.23, 0.25, 0.3 } do
	for _, s in { 0.9, 0.6, 0.3 } do
		local m = 0.25 * math.clamp((d - 0.16) / 0.1, 0, 1)
		local bothCharged = 100 * (0.6 - m) * (s + 1) / 2
		local g = grade(d, s).score
		if g < math.floor(bothCharged + 0.5) then
			belowBoth += 1
		end
		if g > math.floor(math.min(100 * 0.6 * (s + 1) / 2, 100 * (0.6 - m)) + 0.5) then
			aboveSingle += 1
		end
	end
end
check("never charges both faults", belowBoth, 0)
check("never charges less than the larger fault", aboveSingle, 0)

-- Several bent-and-off-centre cuts together (8 slices, four cuts at 0/45/90/135): a seeded
-- random walk moves one cut's offset or straightness at a time in small steps; the grade never
-- jumps by more than a point per step, never rises as a cut moves out, never falls as a cut
-- straightens, and stays between "both charged on every cut" and "the larger fault on each".
local seed = 4242
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local offs, sts = { 0.2, 0.18, 0.22, 0.1 }, { 0.7, 0.8, 0.5, 1 }
local function grade4(): number
	local lines = {}
	for i, deg in { 0, 45, 90, 135 } do
		table.insert(lines, cut(deg, offs[i], sts[i]))
	end
	return Scoring.cut(8, lines).score
end
local walkJump, walkWrong, walkN = 0, 0, 0
local prev = grade4()
for _ = 1, 3000 do
	local i = 1 + math.floor(rnd() * 4)
	local moveOffset = rnd() < 0.5
	local step = (rnd() - 0.5) * 0.004
	if moveOffset then
		offs[i] = math.clamp(offs[i] + step, 0, 0.4)
	else
		sts[i] = math.clamp(sts[i] + step, 0, 1)
	end
	local g = grade4()
	walkN += 1
	walkJump = math.max(walkJump, math.abs(g - prev))
	if moveOffset and ((step > 0 and g > prev) or (step < 0 and g < prev)) then
		walkWrong += 1
	end
	if not moveOffset and ((step > 0 and g < prev) or (step < 0 and g > prev)) then
		walkWrong += 1
	end
	prev = g
end
check("four-cut walk: at most one point per small step", walkJump <= 1, true)
check("four-cut walk: moves the grade only the expected way", walkWrong, 0)
note(string.format("Four-cut random walk, %d small steps: largest step %d point(s), %d moves the wrong way", walkN, walkJump, walkWrong))

-- A wrong cut count caps the grade at 60; the choice still never jumps across the switch.
local capJump = 0
local prevCap = nil
for k = 0, 400 do
	local d = 0.16 + k * 0.00025
	local g = Scoring.cut(8, { cut(0, d, 0.6), cut(90, 0, 1) }).score
	if prevCap then
		capJump = math.max(capJump, math.abs(g - prevCap))
	end
	prevCap = g
end
check("wrong count (capped): no jump across the ramp", capJump <= 1, true)

-- The 7b-2 example still open with Lawson (whether two genuinely independent faults should
-- both be charged) is reported, not decided: one cut 0.35 off with straightness 0.60.
local open = Scoring.cut(2, { cut(0, 0.35, 0.6) })
note(string.format("Open question kept open: one cut 0.35 off centre, straightness 0.60, 2 slices -> %d (charging both would be %d)", open.score, math.floor(100 * 0.75 * 0.6 + 0.5)))

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut branch checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

-- Checks for freehand cuts: the shared path grading (Scoring.cutPath, cutQuality, cut), the
-- path resampling the client sends, and the server's cut action, which grades and keeps the
-- path and refuses bad input without changing the pizza. Expected values are worked by hand
-- from the geometry (see the comments), never from the helpers under test. Run offline with
-- tests/offline/run.py, or in Studio Edit after a sync. Arithmetic only: how the groove looks
-- and how a real drag feels are checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)
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
-- (the crust ends, y = 0.009524, are as far on the other side). Straightness
-- 1 - (0.045238 - 0.04) / 0.16 = 0.96726. Completeness 1.
local ch = Scoring.cutPath({ P(-1.05, 0), P(0, 0.1), P(1.05, 0) }) :: any
near("chevron 0.1: fitted height", (ch.y1 + ch.y2) / 2, 0.054762, 0.0005)
near("chevron 0.1: deviation", ch.deviation, 0.045238, 0.0005)
near("chevron 0.1: straightness", ch.straightness, 0.96726, 0.004)
near("chevron 0.1: completeness", ch.completeness, 1, 1e-6)

-- 6. A deep chevron, apex 0.3: mean height 0.3 x 0.547619 = 0.164286; apex distance 0.135714;
-- crust end (x = 0.9496, y = 0.0287) distance 0.1356. Straightness 1 - (0.1357 - 0.04) / 0.16
-- = 0.402. Its fitted line sits 0.164 from the centre, so its chord is 2 x 0.9357, and the path
-- spans past both ends: completeness 1.
local deep = Scoring.cutPath({ P(-1.05, 0), P(0, 0.3), P(1.05, 0) }) :: any
near("chevron 0.3: deviation", deep.deviation, 0.1357, 0.001)
near("chevron 0.3: straightness", deep.straightness, 0.402, 0.008)
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
-- Amplitude 0.12: the fitted line stays at y ~ 0, the widest distance ~0.12, straightness
-- 1 - (0.12 - 0.04) / 0.16 = 0.5.
for i, p in wob do
	p.y = 0.12 * math.sin((i - 1) / 40 * 10 * math.pi)
end
local w2 = Scoring.cutPath(wob) :: any
near("wobble 0.12: straightness", w2.straightness, 0.5, 0.02)
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
-- Two deep chevrons (straightness 0.402) at 0 and 90 degrees for 4 slices. Each fitted line
-- sits 0.164 off centre, past the 0.16 tolerance, so both miss the centre: layout
-- 0.5 + 0.5 - 2 x 0.25 = 0.5; grade 100 x 0.5 x 0.402 = 20.
local chev90 = Scoring.cutPath({ P(0, -1.05), P(0.3, 0), P(0, 1.05) }) :: any
local gc = Scoring.cut(4, { deep, chev90 })
near("grade: two deep chevrons", gc.score, 20, 1)
check("grade: wobble note", table.find(gc.notes, "2 cuts wobbled off a straight line") ~= nil, true)
check("grade: centre note", table.find(gc.notes, "2 cuts missed the centre") ~= nil, true)
-- Lines without path grades (old fixtures) count as straight and full: unchanged score.
check("grade: plain lines unchanged", Scoring.cut(4, { { x1 = -1, y1 = 0, x2 = 1, y2 = 0 }, { x1 = 0, y1 = -1, x2 = 0, y2 = 1 } }).score, 100)
check("grade: uncut", Scoring.cut(8, {}).score, 0)
note(string.format("worked grades: 4 straight full = %d; one 3/4 cut = %d; two deep chevrons (4 slices) = %d", g.score, gp.score, gc.score))

-- 11. The server's cut action grades and keeps the path; refusals leave the pizza unchanged.
local pizza = { id = 7, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
local session = { shift = { pizzas = { [7] = pizza } } } :: any
local ok, reason = ShiftService.apply(session, "cut", { pizzaId = 7, path = { P(-1.05, 0), P(0, 0.1), P(1.05, 0) } })
check("server: freehand cut accepted", ok, true)
check("server: one cut stored", #pizza.cuts, 1)
check("server: path stored", #pizza.cuts[1].path, 3)
near("server: straightness stored", pizza.cuts[1].straightness, 0.96726, 0.004)
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

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

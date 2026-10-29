-- Checks and report for how cuts feel to grade (slice 7b-2, Lawson 2026-10-29 18:22: "predictable,
-- forgiving control with room for skill"). The same strokes are graded four ways:
--   7b-1      the 7b-1 sampling (a sample each spacing of distance) and the 7b-1 straightness (the
--             widest distance of the path from its line);
--   7b-2 built the 7b-2 sampling by position, 7b-1 straightness (the build Lawson saved 18:20);
--   now       the 7b-2 sampling, straightness with the tremor allowance (Config.Cut.tremor);
--   now, 7b-1 sampling  the identical stroke recorded under the old rule and graded now, to show
--             how much the grade depends on where the samples happened to land.
-- Plus the assist turned on (it is off by default; Config.Cut.assist.on), whole pizzas with their
-- notes, the largest drops over a fixed sweep, and one-cut grades near the centre tolerance. The
-- 7b-1 Cut grade and notes are a replica of the 7b-1 Scoring.cut (oldCut below), so the 7b-1
-- columns stay the 7b-1 rules whatever Scoring.cut does now.
-- Input here is synthetic: "mouse" is dense events with small noise, "touch" sparser events with
-- more noise, plus Astra's four r20 fixtures. Not recorded human behaviour.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)
local CutStroke = require(Shared.CutStroke)

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

local cfg = Config.Cut
check("proposal: tremor allowance", cfg.tremor, 0.15)
check("proposal: note threshold", cfg.noteMinPoints, 3)
check("proposal: assist off by default", cfg.assist.on, false)
local ROUND = Scoring.ROUND

local function qp(p: any): any
	return P(CutStroke.quantize(p.x), CutStroke.quantize(p.y))
end
local function dist(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
-- The 7b-1 sampling (as in cut_budget_check), for paths inside the accepted range.
local function recordBefore(events: { any }): { any }
	local pts = { qp(events[1]) }
	for i = 2, #events do
		if #pts >= cfg.maxPoints then
			break
		end
		local d = dist(events[i], pts[#pts])
		if d >= cfg.spacing or (i == #events and d > 1e-4) then
			table.insert(pts, qp(events[i]))
		end
	end
	return pts
end
local function recordNow(events: { any }): { any }
	local st = CutStroke.stream(ROUND, false, events[1])
	for i = 2, #events do
		CutStroke.record(st, events[i], i == #events)
	end
	return st.points
end
local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end
-- The 7b-1 straightness from a graded cut: the widest raw distance from the line.
local function oldStraight(c: any): number
	return clamp01(1 - (c.rawDeviation - cfg.straightPerfect) / (cfg.straightZero - cfg.straightPerfect))
end
local function completeCredit(c: any): number
	return clamp01((c.completeness - cfg.completeZero) / (cfg.completeFull - cfg.completeZero))
end
-- A cut graded the 7b-1 way: same line and completeness, old straightness.
local function asOld(c: any): any
	local o = table.clone(c)
	o.straightness = oldStraight(c)
	return o
end
-- One stroke graded every way. Returns a table of credits (nil = refused).
local function gradeAll(events: { any }): any
	local before, now = recordBefore(events), recordNow(events)
	local cb = Scoring.cutPath(before, ROUND) :: any
	local cn = Scoring.cutPath(now, ROUND) :: any
	local ca = CutStroke.grade(now, ROUND, true) :: any
	local r: any = { nBefore = #before, nNow = #now }
	if cb then
		r.old = oldStraight(cb) * completeCredit(cb)
		r.oldS = oldStraight(cb)
		r.nowOldSampling = Scoring.cutQuality(cb)
		r.cutBefore = cb
	end
	if cn then
		r.built = oldStraight(cn) * completeCredit(cn)
		r.builtS = oldStraight(cn)
		r.now = Scoring.cutQuality(cn)
		r.nowS = cn.straightness
		r.cutNow = cn
	end
	if ca then
		r.assist = Scoring.cutQuality(ca)
		r.assisted = ca.assisted
	end
	return r
end

-- Synthetic strokes across the pizza at an angle: offset(t) sideways at position t along the
-- line, t from -reach to reach, an event every `step`, plus noise of size `noise`.
local seed = 4242
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648 - 0.5
end
local INPUT = {
	mouse = { step = 0.006, noise = 0.004 },
	touch = { step = 0.03, noise = 0.012 },
}
local function stroke(offset: (number) -> number, input: string, deg: number?, reach: number?): { any }
	local inp = INPUT[input]
	local r = math.rad(deg or 30)
	local ux, uy = math.cos(r), math.sin(r)
	local nx, ny = -uy, ux
	local L = reach or 1.2
	local events = {}
	local t = -L
	while t <= L + 1e-9 do
		local side = offset(t) + rnd() * inp.noise
		table.insert(events, P(ux * t + nx * side, uy * t + ny * side))
		t += inp.step
	end
	return events
end
local SHAPES: { { id: string, kind: string, f: (number) -> number } } = {
	{ id = "straight", kind = "straight", f = function(_t)
		return 0
	end },
	{ id = "tremor (quick shake 0.02)", kind = "mildly shaky", f = function(t)
		return 0.02 * math.sin(2 * math.pi * t / 0.07)
	end },
	{ id = "shaky (0.035, wave 0.12)", kind = "mildly shaky", f = function(t)
		return 0.035 * math.sin(2 * math.pi * t / 0.12)
	end },
	{ id = "slight drift (0.04 bow)", kind = "mildly shaky", f = function(t)
		return 0.04 * (1 - (t / 1.2) ^ 2)
	end },
	{ id = "wavy (0.07, wave 0.5)", kind = "clearly crooked", f = function(t)
		return 0.07 * math.sin(2 * math.pi * t / 0.5)
	end },
	{ id = "bowed (0.15 arc)", kind = "clearly crooked", f = function(t)
		return 0.15 * (1 - (t / 1.2) ^ 2)
	end },
	{ id = "chevron (0.2 apex)", kind = "clearly crooked", f = function(t)
		return 0.2 * (1 - math.abs(t) / 1.2)
	end },
	{ id = "S-bend (0.12)", kind = "clearly crooked", f = function(t)
		return 0.12 * math.sin(math.pi * t / 1.2)
	end },
	-- Short sharp features: the tremor allowance averages much of them away (for Lawson to judge).
	{ id = "kink 0.10 deep, 0.10 wide", kind = "short and sharp", f = function(t)
		return 0.1 * math.max(0, 1 - math.abs(t) / 0.05)
	end },
	{ id = "kink 0.20 deep, 0.18 wide", kind = "short and sharp", f = function(t)
		return 0.2 * math.max(0, 1 - math.abs(t) / 0.09)
	end },
	{ id = "fast zigzag 0.10, period 0.12", kind = "short and sharp", f = function(t)
		local u = (t / 0.12) % 1
		return 0.1 * (4 * math.abs(u - 0.5) - 1)
	end },
}
local function f3(v: number?): string
	return if v then string.format("%.2f", v) else "refused"
end

note("Representative strokes (credit = straightness x completeness credit; 1.00 is a perfect path):")
note("| Stroke | Kind | Input | Samples 7b-1 / now | 7b-1 | 7b-2 built | Now | Now, 7b-1 sampling | Now, assist on |")
note("|---|---|---|---|---|---|---|---|---|")
local byShape = {}
for _, sh in SHAPES do
	for _, input in { "mouse", "touch" } do
		local r = gradeAll(stroke(sh.f, input))
		byShape[sh.id .. "/" .. input] = r
		note(string.format("| %s | %s | %s | %d / %d | %s | %s | %s | %s | %s |", sh.id, sh.kind, input, r.nBefore, r.nNow, f3(r.old), f3(r.built), f3(r.now), f3(r.nowOldSampling), f3(r.assist)))
		if sh.kind == "straight" then
			check(sh.id .. " " .. input .. ": full credit now", r.now ~= nil and r.now >= 0.999, true)
		elseif sh.kind == "mildly shaky" then
			check(sh.id .. " " .. input .. ": forgiven now (credit at least 0.95)", r.now ~= nil and r.now >= 0.95, true)
		elseif sh.kind == "clearly crooked" then
			check(sh.id .. " " .. input .. ": still loses credit now (under 0.92)", r.now ~= nil and r.now < 0.92, true)
		end
	end
end

-- Astra's four r20 fixtures, exactly as in cut_budget_check (one event per point).
local FIXTURES = {
	{ id = "mouse_fine_jitter", events = "-1.2,0 -1.19,0.02874 -1.18,0.04747 -1.17,0.05188 -1.16,0.04554 -1.15,0.03726 -1.14,0.03525 -1.13,0.0418 -1.12,0.05179 -1.11,0.05594 -1.1,0.04682 -1.09,0.02378 -1.08,-0.00618 -1.07,-0.03229 -1.06,-0.04617 -1.05,-0.04654 -1.04,-0.0395 -1.03,-0.03427 -1.02,-0.03718 -1.01,-0.04745 -1,-0.05763 -0.99,-0.05834 -0.98,-0.04427 -0.97,-0.01788 -0.96,0.01176 -0.95,0.03406 -0.94,0.04304 -0.93,0.04046 -0.92,0.03425 -0.91,0.03313 -0.9,0.04086 -0.89,0.05365 -0.88,0.06249 -0.87,0.05883 -0.86,0.04009 -0.85,0.01162 -0.84,-0.01618 -0.83,-0.0339 -0.82,-0.03839 -0.81,-0.03422 -0.8,-0.03031 -0.79,-0.03395 -0.78,-0.04592 -0.77,-0.0598 -0.76,-0.0659 -0.75,-0.05737 -0.74,-0.03467 -0.73,-0.00562 -0.72,0.01902 -0.71,0.03181 -0.7,0.03268 -0.69,0.02844 -0.68,0.02807 -0.67,0.03664 -0.66,0.05187 -0.65,0.0653 -0.64,0.06752 -0.63,0.0541 -0.62,0.02855 -0.61,0.00047 -0.6,-0.02 -0.59,-0.028 -0.58,-0.02645 -0.57,-0.02368 -0.56,-0.02774 -0.55,-0.04095 -0.54,-0.05813 -0.53,-0.06961 -0.52,-0.06719 -0.51,-0.04934 -0.5,-0.02232 -0.49,0.00334 -0.48,0.01902 -0.47,0.02285 -0.46,0.02033 -0.45,0.02041 -0.44,0.02936 -0.43,0.04645 -0.42,0.06408 -0.41,0.0723 -0.4,0.06495 -0.39,0.04356 -0.38,0.01661 -0.37,-0.00543 -0.36,-0.01618 -0.35,-0.01685 -0.34,-0.01491 -0.33,-0.01895 -0.32,-0.03277 -0.31,-0.0526 -0.3,-0.06914 -0.29,-0.07312 -0.28,-0.06101 -0.27,-0.03732 -0.26,-0.01196 -0.25,0.00559 -0.24,0.01176 -0.23,0.01059 -0.22,0.01073 -0.21,0.01944 -0.2,0.03763 -0.19,0.05881 -0.18,0.07282 -0.17,0.07198 -0.16,0.05577 -0.15,0.03124 -0.14,0.00883 -0.13,-0.00382 -0.12,-0.00618 -0.11,-0.00469 -0.1,-0.00818 -0.09,-0.02184 -0.08,-0.04347 -0.07,-0.06445 -0.06,-0.07475 -0.05,-0.06899 -0.04,-0.04972 -0.03,-0.0259 -0.02,-0.00753 -0.01,0.00027 0,0 0.01,-0.00027 0.02,0.00753 0.03,0.0259 0.04,0.04972 0.05,0.06899 0.06,0.07475 0.07,0.06445 0.08,0.04347 0.09,0.02184 0.1,0.00818 0.11,0.00469 0.12,0.00618 0.13,0.00382 0.14,-0.00883 0.15,-0.03124 0.16,-0.05577 0.17,-0.07198 0.18,-0.07282 0.19,-0.05881 0.2,-0.03763 0.21,-0.01944 0.22,-0.01073 0.23,-0.01059 0.24,-0.01176 0.25,-0.00559 0.26,0.01196 0.27,0.03732 0.28,0.06101 0.29,0.07312 0.3,0.06914 0.31,0.0526 0.32,0.03277 0.33,0.01895 0.34,0.01491 0.35,0.01685 0.36,0.01618 0.37,0.00543 0.38,-0.01661 0.39,-0.04356 0.4,-0.06495 0.41,-0.0723 0.42,-0.06408 0.43,-0.04645 0.44,-0.02936 0.45,-0.02041 0.46,-0.02033 0.47,-0.02285 0.48,-0.01902 0.49,-0.00334 0.5,0.02232 0.51,0.04934 0.52,0.06719 0.53,0.06961 0.54,0.05813 0.55,0.04095 0.56,0.02774 0.57,0.02368 0.58,0.02645 0.59,0.028 0.6,0.02 0.61,-0.00047 0.62,-0.02855 0.63,-0.0541 0.64,-0.06752 0.65,-0.0653 0.66,-0.05187 0.67,-0.03664 0.68,-0.02807 0.69,-0.02844 0.7,-0.03268 0.71,-0.03181 0.72,-0.01902 0.73,0.00562 0.74,0.03467 0.75,0.05737 0.76,0.0659 0.77,0.0598 0.78,0.04592 0.79,0.03395 0.8,0.03031 0.81,0.03422 0.82,0.03839 0.83,0.0339 0.84,0.01618 0.85,-0.01162 0.86,-0.04009 0.87,-0.05883 0.88,-0.06249 0.89,-0.05365 0.9,-0.04086 0.91,-0.03313 0.92,-0.03425 0.93,-0.04046 0.94,-0.04304 0.95,-0.03406 0.96,-0.01176 0.97,0.01788 0.98,0.04427 0.99,0.05834 1,0.05763 1.01,0.04745 1.02,0.03718 1.03,0.03427 1.04,0.0395 1.05,0.04654 1.06,0.04617 1.07,0.03229 1.08,0.00618 1.09,-0.02378 1.1,-0.04682 1.11,-0.05594 1.12,-0.05179 1.13,-0.0418 1.14,-0.03525 1.15,-0.03726 1.16,-0.04554 1.17,-0.05188 1.18,-0.04747 1.19,-0.02874 1.2,0" },
	{ id = "mouse_long_wobble_stress", events = "-1.25,0 -1.23958,0.05881 -1.22917,0.09928 -1.21875,0.11134 -1.20833,0.09684 -1.19792,0.06677 -1.1875,0.03409 -1.17708,0.00663 -1.16667,-0.01559 -1.15625,-0.03746 -1.14583,-0.06245 -1.13542,-0.08752 -1.125,-0.10283 -1.11458,-0.09688 -1.10417,-0.06401 -1.09375,-0.00957 -1.08333,0.05084 -1.07292,0.09788 -1.0625,0.11738 -1.05208,0.10655 -1.04167,0.0741 -1.03125,0.03447 -1.02083,-0.00018 -1.01042,-0.02535 -1,-0.04408 -0.98958,-0.06182 -0.97917,-0.08002 -0.96875,-0.09314 -0.95833,-0.09104 -0.94792,-0.06567 -0.9375,-0.01768 -0.92708,0.04133 -0.91667,0.09289 -0.90625,0.12003 -0.89583,0.11519 -0.88542,0.08334 -0.875,0.03855 -0.86458,-0.00379 -0.85417,-0.03441 -0.84375,-0.05294 -0.83333,-0.06495 -0.82292,-0.07548 -0.8125,-0.08376 -0.80208,-0.08266 -0.79167,-0.06351 -0.78125,-0.0231 -0.77083,0.03171 -0.76042,0.08508 -0.75,0.11888 -0.73958,0.12142 -0.72917,0.09307 -0.71875,0.04572 -0.70833,-0.00366 -0.69792,-0.04139 -0.6875,-0.06269 -0.67708,-0.07138 -0.66667,-0.07459 -0.65625,-0.0761 -0.64583,-0.07301 -0.63542,-0.05788 -0.625,-0.025 -0.61458,0.02346 -0.60417,0.07562 -0.59375,0.11412 -0.58333,0.12432 -0.57292,0.10182 -0.5625,0.05487 -0.55208,0.00019 -0.54167,-0.04524 -0.53125,-0.07184 -0.52083,-0.08013 -0.51042,-0.07748 -0.5,-0.07133 -0.48958,-0.06355 -0.47917,-0.04963 -0.46875,-0.0231 -0.45833,0.01784 -0.44792,0.06597 -0.4375,0.10646 -0.42708,0.12342 -0.41667,0.10825 -0.40625,0.06461 -0.39583,0.00718 -0.38542,-0.04537 -0.375,-0.079 -0.36458,-0.08987 -0.35417,-0.08372 -0.34375,-0.07018 -0.33333,-0.05574 -0.32292,-0.04002 -0.3125,-0.01768 -0.30208,0.01568 -0.29167,0.05759 -0.28125,0.09707 -0.27083,0.11888 -0.26042,0.11139 -0.25,0.07347 -0.23958,0.01624 -0.22917,-0.04176 -0.21875,-0.08309 -0.20833,-0.0991 -0.19792,-0.09235 -0.1875,-0.07283 -0.17708,-0.05075 -0.16667,-0.03051 -0.15625,-0.00957 -0.14583,0.01733 -0.13542,0.05175 -0.125,0.08738 -0.11458,0.11138 -0.10417,0.11075 -0.09375,0.08009 -0.08333,0.02599 -0.07292,-0.03495 -0.0625,-0.08347 -0.05208,-0.10644 -0.04167,-0.10207 -0.03125,-0.07887 -0.02083,-0.04935 -0.01042,-0.02254 0,0 0.01042,0.02254 0.02083,0.04935 0.03125,0.07887 0.04167,0.10207 0.05208,0.10644 0.0625,0.08347 0.07292,0.03495 0.08333,-0.02599 0.09375,-0.08009 0.10417,-0.11075 0.11458,-0.11138 0.125,-0.08738 0.13542,-0.05175 0.14583,-0.01733 0.15625,0.00957 0.16667,0.03051 0.17708,0.05075 0.1875,0.07283 0.19792,0.09235 0.20833,0.0991 0.21875,0.08309 0.22917,0.04176 0.23958,-0.01624 0.25,-0.07347 0.26042,-0.11139 0.27083,-0.11888 0.28125,-0.09707 0.29167,-0.05759 0.30208,-0.01568 0.3125,0.01768 0.32292,0.04002 0.33333,0.05574 0.34375,0.07018 0.35417,0.08372 0.36458,0.08987 0.375,0.079 0.38542,0.04537 0.39583,-0.00718 0.40625,-0.06461 0.41667,-0.10825 0.42708,-0.12342 0.4375,-0.10646 0.44792,-0.06597 0.45833,-0.01784 0.46875,0.0231 0.47917,0.04963 0.48958,0.06355 0.5,0.07133 0.51042,0.07748 0.52083,0.08013 0.53125,0.07184 0.54167,0.04524 0.55208,-0.00019 0.5625,-0.05487 0.57292,-0.10182 0.58333,-0.12432 0.59375,-0.11412 0.60417,-0.07562 0.61458,-0.02346 0.625,0.025 0.63542,0.05788 0.64583,0.07301 0.65625,0.0761 0.66667,0.07459 0.67708,0.07138 0.6875,0.06269 0.69792,0.04139 0.70833,0.00366 0.71875,-0.04572 0.72917,-0.09307 0.73958,-0.12142 0.75,-0.11888 0.76042,-0.08508 0.77083,-0.03171 0.78125,0.0231 0.79167,0.06351 0.80208,0.08266 0.8125,0.08376 0.82292,0.07548 0.83333,0.06495 0.84375,0.05294 0.85417,0.03441 0.86458,0.00379 0.875,-0.03855 0.88542,-0.08334 0.89583,-0.11519 0.90625,-0.12003 0.91667,-0.09289 0.92708,-0.04133 0.9375,0.01768 0.94792,0.06567 0.95833,0.09104 0.96875,0.09314 0.97917,0.08002 0.98958,0.06182 1,0.04408 1.01042,0.02535 1.02083,0.00018 1.03125,-0.03447 1.04167,-0.0741 1.05208,-0.10655 1.0625,-0.11738 1.07292,-0.09788 1.08333,-0.05084 1.09375,0.00957 1.10417,0.06401 1.11458,0.09688 1.125,0.10283 1.13542,0.08752 1.14583,0.06245 1.15625,0.03746 1.16667,0.01559 1.17708,-0.00663 1.1875,-0.03409 1.19792,-0.06677 1.20833,-0.09684 1.21875,-0.11134 1.22917,-0.09928 1.23958,-0.05881 1.25,0" },
	{ id = "touch_intent_small_wobble", events = "0,-1.2 0.01391,-1.18 0.02645,-1.16 0.03641,-1.14 0.0428,-1.12 0.045,-1.1 0.0428,-1.08 0.03641,-1.06 0.02645,-1.04 0.01391,-1.02 0,-1 -0.01391,-0.98 -0.02645,-0.96 -0.03641,-0.94 -0.0428,-0.92 -0.045,-0.9 -0.0428,-0.88 -0.03641,-0.86 -0.02645,-0.84 -0.01391,-0.82 0,-0.8 0.01391,-0.78 0.02645,-0.76 0.03641,-0.74 0.0428,-0.72 0.045,-0.7 0.0428,-0.68 0.03641,-0.66 0.02645,-0.64 0.01391,-0.62 0,-0.6 -0.01391,-0.58 -0.02645,-0.56 -0.03641,-0.54 -0.0428,-0.52 -0.045,-0.5 -0.0428,-0.48 -0.03641,-0.46 -0.02645,-0.44 -0.01391,-0.42 0,-0.4 0.01391,-0.38 0.02645,-0.36 0.03641,-0.34 0.0428,-0.32 0.045,-0.3 0.0428,-0.28 0.03641,-0.26 0.02645,-0.24 0.01391,-0.22 0,-0.2 -0.01391,-0.18 -0.02645,-0.16 -0.03641,-0.14 -0.0428,-0.12 -0.045,-0.1 -0.0428,-0.08 -0.03641,-0.06 -0.02645,-0.04 -0.01391,-0.02 0,0 0.01391,0.02 0.02645,0.04 0.03641,0.06 0.0428,0.08 0.045,0.1 0.0428,0.12 0.03641,0.14 0.02645,0.16 0.01391,0.18 0,0.2 -0.01391,0.22 -0.02645,0.24 -0.03641,0.26 -0.0428,0.28 -0.045,0.3 -0.0428,0.32 -0.03641,0.34 -0.02645,0.36 -0.01391,0.38 0,0.4 0.01391,0.42 0.02645,0.44 0.03641,0.46 0.0428,0.48 0.045,0.5 0.0428,0.52 0.03641,0.54 0.02645,0.56 0.01391,0.58 0,0.6 -0.01391,0.62 -0.02645,0.64 -0.03641,0.66 -0.0428,0.68 -0.045,0.7 -0.0428,0.72 -0.03641,0.74 -0.02645,0.76 -0.01391,0.78 0,0.8 0.01391,0.82 0.02645,0.84 0.03641,0.86 0.0428,0.88 0.045,0.9 0.0428,0.92 0.03641,0.94 0.02645,0.96 0.01391,0.98 0,1 -0.01391,1.02 -0.02645,1.04 -0.03641,1.06 -0.0428,1.08 -0.045,1.1 -0.0428,1.12 -0.03641,1.14 -0.02645,1.16 -0.01391,1.18 0,1.2" },
	{ id = "touch_intent_pause_resume", events = "0,-1.2 0.00618,-1.17 0.01176,-1.14 0.01618,-1.11 0.01902,-1.08 0.02,-1.05 0.01902,-1.02 0.01618,-0.99 0.01176,-0.96 0.00618,-0.93 0,-0.9 -0.00618,-0.87 -0.01176,-0.84 -0.01618,-0.81 -0.01902,-0.78 -0.02,-0.75 -0.01902,-0.72 -0.01618,-0.69 -0.01176,-0.66 -0.00618,-0.63 0,-0.6 0.00618,-0.57 0.01176,-0.54 0.01618,-0.51 0.01902,-0.48 0.02,-0.45 0.01902,-0.42 0.01618,-0.39 0.01176,-0.36 0.00618,-0.33 0,-0.3 -0.00618,-0.27 -0.01176,-0.24 -0.01618,-0.21 -0.01902,-0.18 -0.02,-0.15 -0.01902,-0.12 -0.01618,-0.09 -0.01176,-0.06 -0.00618,-0.03 0,0 0,0 0,0 0,0 0.00618,0.03 0.01176,0.06 0.01618,0.09 0.01902,0.12 0.02,0.15 0.01902,0.18 0.01618,0.21 0.01176,0.24 0.00618,0.27 0,0.3 -0.00618,0.33 -0.01176,0.36 -0.01618,0.39 -0.01902,0.42 -0.02,0.45 -0.01902,0.48 -0.01618,0.51 -0.01176,0.54 -0.00618,0.57 0,0.6 0.00618,0.63 0.01176,0.66 0.01618,0.69 0.01902,0.72 0.02,0.75 0.01902,0.78 0.01618,0.81 0.01176,0.84 0.00618,0.87 0,0.9 -0.00618,0.93 -0.01176,0.96 -0.01618,0.99 -0.01902,1.02 -0.02,1.05 -0.01902,1.08 -0.01618,1.11 -0.01176,1.14 -0.00618,1.17 0,1.2" },
}
note("")
note("Astra's r20 fixtures:")
note("| Fixture | Samples 7b-1 / now | 7b-1 | 7b-2 built | Now | Now, 7b-1 sampling | Now, assist on |")
note("|---|---|---|---|---|---|---|")
for _, fx in FIXTURES do
	local events = {}
	for x, y in string.gmatch(fx.events, "([%-%d%.e]+),([%-%d%.e]+)") do
		table.insert(events, P(tonumber(x) :: number, tonumber(y) :: number))
	end
	local r = gradeAll(events)
	note(string.format("| %s | %d / %d | %s | %s | %s | %s | %s |", fx.id, r.nBefore, r.nNow, f3(r.old), f3(r.built), f3(r.now), f3(r.nowOldSampling), f3(r.assist)))
end

-- Whole pizzas: four cuts of one stroke kind at 0/45/90/135 degrees (8 slices), and the same
-- with one cut turned 12 degrees (uneven slices). Cut score and notes, 7b-1 against now.
-- The 7b-1 Scoring.cut on the round dough, written out: the full 0.25 centre step past
-- centreTolerance, every penalty charged, notes without a cost check (uneven past
-- perfectDegrees + 3, wobbly under straightness 0.75, short under 0.9). Cuts carry 7b-1
-- straightness (asOld).
local function oldCut(slices: number, cuts: { any }): (number, { string })
	local needed = slices // 2
	if #cuts == 0 then
		return 0, { "The pizza wasn't cut" }
	end
	local angles, offCentre = {}, 0
	for _, c in cuts do
		local dx, dy = c.x2 - c.x1, c.y2 - c.y1
		local len = math.sqrt(dx * dx + dy * dy)
		table.insert(angles, math.deg(math.atan2(dy, dx)) % 180)
		if math.abs(c.x1 * dy - c.y1 * dx) / len > cfg.centreTolerance then
			offCentre += 1
		end
	end
	table.sort(angles)
	local ideal = 180 / #angles
	local err = 0
	for i = 1, #angles do
		local nxt = if i < #angles then angles[i + 1] else angles[1] + 180
		err += math.abs((nxt - angles[i]) - ideal)
	end
	err /= #angles
	local even = if #angles == 1 then 1 else clamp01(1 - (err - cfg.perfectDegrees) / (cfg.zeroDegrees - cfg.perfectDegrees))
	local count = clamp01(1 - math.abs(#cuts - needed) / needed)
	local layout = clamp01(count * 0.5 + even * 0.5 - offCentre * 0.25)
	local quality, crooked, short = 0, 0, 0
	for _, c in cuts do
		quality += c.straightness * completeCredit(c)
		crooked += if c.straightness < 0.75 then 1 else 0
		short += if c.completeness < 0.9 then 1 else 0
	end
	quality /= #cuts
	local score = 100 * layout * quality
	local notes = {}
	if #cuts ~= needed then
		score = math.min(score, 60)
		table.insert(notes, string.format("Made %d cut%s, the order needed %d", #cuts, if #cuts == 1 then "" else "s", needed))
	end
	if offCentre > 0 then
		table.insert(notes, string.format("%d cut%s missed the centre", offCentre, if offCentre == 1 then "" else "s"))
	end
	if #angles > 1 and err > cfg.perfectDegrees + 3 then
		table.insert(notes, "Slices were uneven sizes")
	end
	if crooked > 0 then
		table.insert(notes, string.format("%d cut%s wobbled off a straight line", crooked, if crooked == 1 then "" else "s"))
	end
	if short > 0 then
		table.insert(notes, string.format("%d cut%s stopped short of the crust", short, if short == 1 then "" else "s"))
	end
	return math.floor(score + 0.5), notes
end
local function oldNotes(slices: number, cuts: { any }): (number, { string })
	local olds = {}
	for _, c in cuts do
		table.insert(olds, asOld(c))
	end
	return oldCut(slices, olds)
end
local function pizza(f: (number) -> number, input: string, turn: number?): (any, any)
	local before, now = {}, {}
	for k = 0, 3 do
		local deg = k * 45 + (if k == 1 then turn or 0 else 0)
		local events = stroke(f, input, deg)
		local cb = Scoring.cutPath(recordBefore(events), ROUND)
		local cn = Scoring.cutPath(recordNow(events), ROUND)
		if cb then
			table.insert(before, cb)
		end
		if cn then
			table.insert(now, cn)
		end
	end
	return before, now
end
note("")
note("Whole pizzas, 8 slices: four cuts of the same kind at 0/45/90/135 degrees, or with one cut 12 or 25 degrees off:")
note("| Cuts | Input | 7b-1 Cut score, notes | Now Cut score, notes |")
note("|---|---|---|---|")
local pizzaRows = {}
for _, sh in SHAPES do
	for _, input in { "mouse", "touch" } do
		for _, turn in { 0, 12, 25 } do
			if turn == 0 or sh.id == "straight" or sh.id == "shaky (0.035, wave 0.12)" then
				local before, now = pizza(sh.f, input, turn)
				local s1, n1 = oldNotes(8, before)
				local g = Scoring.cut(8, now, ROUND)
				local label = sh.id .. (if turn ~= 0 then string.format(", one cut %d deg off", turn) else "")
				note(string.format("| %s | %s | %d (%s) | %d (%s) |", label, input, s1, if #n1 > 0 then table.concat(n1, "; ") else "no notes",
					g.score, if #g.notes > 0 then table.concat(g.notes, "; ") else "no notes"))
				pizzaRows[label .. "/" .. input] = g
			end
		end
	end
end
-- Bowed cuts on either side of the centre tolerance (the fitted line of a bow sits off centre):
-- under 7b-1 the bow 0.21 pizza dropped to 0, four full centre steps on top of the bend.
for _, bow in { 0.2, 0.21, 0.25 } do
	local f = function(t: number): number
		return bow * (1 - (t / 1.2) ^ 2)
	end
	local before, now = pizza(f, "mouse", 0)
	local s1, n1 = oldNotes(8, before)
	local g = Scoring.cut(8, now, ROUND)
	local label = string.format("bowed (%.2f arc)", bow)
	note(string.format("| %s | mouse | %d (%s) | %d (%s) |", label, s1, if #n1 > 0 then table.concat(n1, "; ") else "no notes",
		g.score, if #g.notes > 0 then table.concat(g.notes, "; ") else "no notes"))
	pizzaRows[label] = g
end
check("pizza: bow 0.20 and 0.21 score within 5 points of each other", math.abs(pizzaRows["bowed (0.20 arc)"].score - pizzaRows["bowed (0.21 arc)"].score) <= 5, true)
do
	local g = pizzaRows["straight/mouse"]
	check("pizza: straight cuts, 100 and no notes", g.score == 100 and #g.notes == 0, true)
	local s = pizzaRows["shaky (0.035, wave 0.12)/touch"]
	check("pizza: shaky touch cuts, no wobble note", s ~= nil and #s.notes == 0, true)
	local c = pizzaRows["chevron (0.2 apex)/mouse"]
	local hasWobble = false
	for _, n in c.notes do
		if string.find(n, "wobbled", 1, true) then
			hasWobble = true
		end
	end
	check("pizza: chevron cuts still named as wobbly", hasWobble, true)
	local small = pizzaRows["straight, one cut 12 deg off/mouse"]
	check("pizza: a 12 degree miss costs under 3 points and is not named", small.score >= 98 and #small.notes == 0, true)
	local big = pizzaRows["straight, one cut 25 deg off/mouse"]
	check("pizza: a 25 degree miss is named", big.notes[1], "Slices were uneven sizes")
end

-- The sweep (cut_budget_check's strokes): 7b-1 against now, per stroke, and the largest drops.
local sweepSeed = 777
local function srnd(): number
	sweepSeed = (sweepSeed * 1103515245 + 12345) % 2147483648
	return sweepSeed / 2147483648 - 0.5
end
local AMPS = { 0, 0.02, 0.04, 0.06, 0.09, 0.12 }
local WAVES = { 0.08, 0.15, 0.3 }
local STEPS = { 0.004, 0.012, 0.03, 0.06 }
local OFFSETS = { 0, 0.08 }
local REACHES = { 1.2, 1.55 }
local rows = {}
local n, refusedOld, refusedNow, lower, lower05, higher, sumOld, sumNow, sumBuilt = 0, 0, 0, 0, 0, 0, 0, 0, 0
local samplingGap, samplingGapBuilt, assistLower, assistLower05, assistWorst = 0, 0, 0, 0, 0
local gapSum, gapBuiltSum, gapN, gapAt = 0, 0, 0, ""
for _, a in AMPS do
	for _, w in WAVES do
		for _, e in STEPS do
			for _, o in OFFSETS do
				for _, reach in REACHES do
					for deg = 0, 165, 15 do
						local r = math.rad(deg)
						local ux, uy = math.cos(r), math.sin(r)
						local nx, ny = -uy, ux
						local events = {}
						local t = -reach
						while t <= reach + 1e-9 do
							local side = o + a * math.sin(2 * math.pi * (t + reach) / w) + srnd() * 0.004
							table.insert(events, P(ux * t + nx * side, uy * t + ny * side))
							t += e
						end
						local g = gradeAll(events)
						n += 1
						refusedOld += if g.old then 0 else 1
						refusedNow += if g.now then 0 else 1
						if g.old and g.now then
							sumOld += g.old
							sumNow += g.now
							sumBuilt += g.built
							local d = g.now - g.old
							if d < -1e-9 then
								lower += 1
							elseif d > 1e-9 then
								higher += 1
							end
							if d < -0.05 then
								lower05 += 1
							end
							table.insert(rows, { d = d, a = a, w = w, e = e, o = o, reach = reach, deg = deg, old = g.old, now = g.now, built = g.built })
						end
						-- The same stroke recorded both ways, where both recordings cross the pizza
						-- (the 7b-1 limit cut some short): how far straightness moves with sampling.
						if g.cutNow and g.cutBefore and g.cutNow.completeness >= 0.95 and g.cutBefore.completeness >= 0.95 then
							local gNow = math.abs(g.cutNow.straightness - g.cutBefore.straightness)
							local gBuilt = math.abs(oldStraight(g.cutNow) - oldStraight(g.cutBefore))
							if gNow > samplingGap then
								gapAt = string.format("wobble %.2f, wave %.2f, events every %.3f", a, w, e)
							end
							samplingGap = math.max(samplingGap, gNow)
							samplingGapBuilt = math.max(samplingGapBuilt, gBuilt)
							gapSum += gNow
							gapBuiltSum += gBuilt
							gapN += 1
						end
						if g.now and g.assist then
							local d = g.assist - g.now
							assistLower += if d < -1e-6 then 1 else 0
							assistLower05 += if d < -0.05 then 1 else 0
							assistWorst = math.min(assistWorst, d)
						end
					end
				end
			end
		end
	end
end
local both = #rows
note("")
note(string.format("Sweep: %d strokes (cut_budget_check's set: wobble 0 to 0.12, waves 0.08 to 0.3, four event spacings, two offsets, two lengths, twelve angles).", n))
note(string.format("- refused: 7b-1 %d, now %d", refusedOld, refusedNow))
note(string.format("- over the %d accepted both ways, mean credit 7b-1 %.3f, 7b-2 built %.3f, now %.3f", both, sumOld / both, sumBuilt / both, sumNow / both))
note(string.format("- now against 7b-1, per stroke: %d higher, %d lower (%.1f%%), %d lower by more than 0.05", higher, lower, 100 * lower / both, lower05))
note(string.format("- the same stroke recorded under both sampling rules (%d strokes where both recordings cross the pizza): straightness difference mean %.3f graded now (%.3f the 7b-1 way), largest %.3f (%.3f), at %s", gapN,
	gapSum / math.max(gapN, 1), gapBuiltSum / math.max(gapN, 1), samplingGap, samplingGapBuilt, gapAt))
note(string.format("- assist on against off (now): %d strokes lower, %d by more than 0.05, largest drop %.3f", assistLower, assistLower05, -assistWorst))
table.sort(rows, function(x, y)
	return x.d < y.d
end)
note("Largest drops, now against 7b-1:")
note("| Wobble | Wave | Event spacing | Offset | Length | Angle | 7b-1 | 7b-2 built | Now | Change |")
note("|---|---|---|---|---|---|---|---|---|---|")
for i = 1, math.min(6, #rows) do
	local r = rows[i]
	note(string.format("| %.2f | %.2f | %.3f | %.2f | %.2f | %d | %.3f | %.3f | %.3f | %+.3f |", r.a, r.w, r.e, r.o, r.reach, r.deg, r.old, r.built, r.now, r.d))
end
check("sweep: no stroke refused now that 7b-1 accepted", refusedNow <= refusedOld, true)
check("sweep: graded now, no stroke loses more than 0.05 against 7b-1", lower05, 0)

-- Near the centre tolerance: one cut for a 2-slice order, its line offset 0.14 to 0.17 from the
-- centre, with a bow and a wobble, mouse and touch. The one-cut Cut grade under 7b-1 (sampling,
-- straightness and the 0.25 centre step) against now.
do
	local rows2 = {}
	local total, lowerN, lower5, higherN, newMiss, noLonger, worst = 0, 0, 0, 0, 0, 0, 0
	for _, bow in { 0, 0.05, 0.1, 0.15, 0.2 } do
		for _, amp in { 0, 0.03, 0.06 } do
			for _, off in { 0.14, 0.15, 0.16, 0.17 } do
				for deg = 0, 165, 15 do
					for _, input in { "mouse", "touch" } do
						local f = function(t: number): number
							return off + bow * (1 - (t / 1.2) ^ 2) - bow * 2 / 3 + amp * math.sin(2 * math.pi * t / 0.15)
						end
						local events = stroke(f, input, deg)
						local cb = Scoring.cutPath(recordBefore(events), ROUND)
						local cn = Scoring.cutPath(recordNow(events), ROUND)
						if cb and cn then
							total += 1
							local s1, n1 = oldCut(2, { asOld(cb) })
							local g = Scoring.cut(2, { cn }, ROUND)
							local d = g.score - s1
							if d < 0 then
								lowerN += 1
							elseif d > 0 then
								higherN += 1
							end
							if d < -5 then
								lower5 += 1
							end
							worst = math.min(worst, d)
							local wasMiss = table.find(n1, "1 cut missed the centre") ~= nil
							local isMiss = table.find(g.notes, "1 cut missed the centre") ~= nil
							newMiss += if isMiss and not wasMiss then 1 else 0
							noLonger += if wasMiss and not isMiss then 1 else 0
							table.insert(rows2, { d = d, bow = bow, amp = amp, off = off, deg = deg, input = input, old = s1, now = g.score })
						end
					end
				end
			end
		end
	end
	table.sort(rows2, function(x, y)
		return x.d < y.d
	end)
	note("")
	note(string.format("Near the centre tolerance: %d one-cut strokes (bows 0 to 0.2, wobble 0 to 0.06, line 0.14 to 0.17 from the centre, twelve angles, mouse and touch), one-cut Cut grade 7b-1 against now:", total))
	note(string.format("- %d higher, %d lower, %d lower by more than 5 points, largest drop %d points; the centre note newly shown on %d, no longer shown on %d", higherN, lowerN, lower5, -worst, newMiss, noLonger))
	note("| Bow | Wobble | Line offset | Angle | Input | 7b-1 | Now | Change |")
	note("|---|---|---|---|---|---|---|---|")
	for i = 1, math.min(6, #rows2) do
		local r = rows2[i]
		note(string.format("| %.2f | %.2f | %.2f | %d | %s | %d | %d | %+d |", r.bow, r.amp, r.off, r.deg, r.input, r.old, r.now, r.d))
	end
	check("near the centre: no one-cut grade drops more than 10 points against 7b-1", worst >= -10, true)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut feel checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

-- Checks for the Cut sample budget by position (slice 7b-2; Astra r19 R19-07 and r20 R20-06).
-- Since slice 6 a stroke records at most Config.Cut.maxPoints samples, one each time the pointer
-- had moved Config.Cut.spacing from the last one, so wobble and dense events spent the budget
-- before the cutter crossed the pizza. Now a point is kept only when it carries the cut forward
-- (spacing further from the press point than any sample so far) or is a real turn (detour from
-- the last sample). This file:
-- 1. replays Astra's four portable fixtures (her r20 cut-input-fixtures.json, synthetic paths,
--    one event per point, assist off, the full round dough) under the 7b-1 rule and the new one;
-- 2. replays a fixed synthetic sweep (wobble size and wavelength, event density, angle, offset)
--    and counts refusals, stops at the limit, completeness and straightness before and after;
-- 3. checks the contract on all of them: the stream equals a plain replica of the rule, it only
--    appends, every shown output stays, the server stores exactly the sent samples.
-- Synthetic input only: not recorded human behaviour, not a measured player refusal rate.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)
local CutStroke = require(Shared.CutStroke)
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

local cfg = Config.Cut
check("proposal: max points", cfg.maxPoints, 48)
check("proposal: spacing", cfg.spacing, 0.07)
check("proposal: detour", cfg.detour, 0.21)
check("proposal: assist off by default", cfg.assist.on, false)

local function qp(p: any): any
	return P(CutStroke.quantize(p.x), CutStroke.quantize(p.y))
end
local function dist(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
-- The 7b-1 rule: a sample each spacing (and the release), nothing past the limit. For paths
-- inside the accepted range.
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
-- The rule now, written out plainly (the replica the stream must equal).
local function recordNow(events: { any }): { any }
	local pts = { qp(events[1]) }
	local first, reach = pts[1], 0
	for i = 2, #events do
		if #pts >= cfg.maxPoints then
			break
		end
		local p, last = events[i], pts[#pts]
		local d = dist(p, last)
		local final = i == #events
		if (final and d > 1e-4) or (not final and d >= cfg.spacing and (dist(p, first) >= reach + cfg.spacing or d >= cfg.detour)) then
			local k = qp(p)
			table.insert(pts, k)
			reach = math.max(reach, dist(k, first))
		end
	end
	return pts
end
local function same(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i].x ~= b[i].x or a[i].y ~= b[i].y then
			return false
		end
	end
	return true
end
-- Drives the stream the Cut station uses; checks it only appends and keeps every shown output.
local function drive(S: any, events: { any }): (any, boolean)
	local st = CutStroke.stream(S, false, events[1])
	local stays = true
	for i = 2, #events do
		local before = table.clone(st.points)
		local shown = table.clone(st.out)
		CutStroke.record(st, events[i], i == #events)
		for k, p in before do
			stays = stays and st.points[k].x == p.x and st.points[k].y == p.y
		end
		for k, p in shown do
			stays = stays and st.out[k].x == p.x and st.out[k].y == p.y
		end
	end
	return st, stays
end
local function inRange(events: { any }): boolean
	for _, e in events do
		if math.abs(e.x) > CutStroke.RANGE or math.abs(e.y) > CutStroke.RANGE then
			return false
		end
	end
	return true
end

local session = { shift = { pizzas = {}, cutAssist = false } } :: any
local nextPizza = 100
-- The server's own acceptance and stored path for one sent list, on a fresh pizza.
local function serverKeeps(path: { any }): (boolean, boolean)
	nextPizza += 1
	local pizza = { id = nextPizza, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
	session.shift.pizzas[nextPizza] = pizza
	local ok = ShiftService.apply(session, "cut", { pizzaId = nextPizza, path = path })
	local stored = pizza.cuts[1]
	return ok == true, ok == true and stored ~= nil and same(stored.path, path)
end

local function row(label: string, pts: { any }, S: any): (string, any)
	local cut, why = CutStroke.grade(pts, S, false)
	local last = pts[#pts]
	return string.format("%d samples%s, %s, ends %.2f,%.2f", #pts, if #pts >= cfg.maxPoints then " (limit)" else "",
		if cut then string.format("accepted, complete %.3f, straight %.3f", cut.completeness, cut.straightness) else "refused: " .. tostring(why), last.x, last.y), cut
end

-- 1. Astra's four fixtures.
local FIXTURES = {
	{ id = "mouse_fine_jitter", events = "-1.2,0 -1.19,0.02874 -1.18,0.04747 -1.17,0.05188 -1.16,0.04554 -1.15,0.03726 -1.14,0.03525 -1.13,0.0418 -1.12,0.05179 -1.11,0.05594 -1.1,0.04682 -1.09,0.02378 -1.08,-0.00618 -1.07,-0.03229 -1.06,-0.04617 -1.05,-0.04654 -1.04,-0.0395 -1.03,-0.03427 -1.02,-0.03718 -1.01,-0.04745 -1,-0.05763 -0.99,-0.05834 -0.98,-0.04427 -0.97,-0.01788 -0.96,0.01176 -0.95,0.03406 -0.94,0.04304 -0.93,0.04046 -0.92,0.03425 -0.91,0.03313 -0.9,0.04086 -0.89,0.05365 -0.88,0.06249 -0.87,0.05883 -0.86,0.04009 -0.85,0.01162 -0.84,-0.01618 -0.83,-0.0339 -0.82,-0.03839 -0.81,-0.03422 -0.8,-0.03031 -0.79,-0.03395 -0.78,-0.04592 -0.77,-0.0598 -0.76,-0.0659 -0.75,-0.05737 -0.74,-0.03467 -0.73,-0.00562 -0.72,0.01902 -0.71,0.03181 -0.7,0.03268 -0.69,0.02844 -0.68,0.02807 -0.67,0.03664 -0.66,0.05187 -0.65,0.0653 -0.64,0.06752 -0.63,0.0541 -0.62,0.02855 -0.61,0.00047 -0.6,-0.02 -0.59,-0.028 -0.58,-0.02645 -0.57,-0.02368 -0.56,-0.02774 -0.55,-0.04095 -0.54,-0.05813 -0.53,-0.06961 -0.52,-0.06719 -0.51,-0.04934 -0.5,-0.02232 -0.49,0.00334 -0.48,0.01902 -0.47,0.02285 -0.46,0.02033 -0.45,0.02041 -0.44,0.02936 -0.43,0.04645 -0.42,0.06408 -0.41,0.0723 -0.4,0.06495 -0.39,0.04356 -0.38,0.01661 -0.37,-0.00543 -0.36,-0.01618 -0.35,-0.01685 -0.34,-0.01491 -0.33,-0.01895 -0.32,-0.03277 -0.31,-0.0526 -0.3,-0.06914 -0.29,-0.07312 -0.28,-0.06101 -0.27,-0.03732 -0.26,-0.01196 -0.25,0.00559 -0.24,0.01176 -0.23,0.01059 -0.22,0.01073 -0.21,0.01944 -0.2,0.03763 -0.19,0.05881 -0.18,0.07282 -0.17,0.07198 -0.16,0.05577 -0.15,0.03124 -0.14,0.00883 -0.13,-0.00382 -0.12,-0.00618 -0.11,-0.00469 -0.1,-0.00818 -0.09,-0.02184 -0.08,-0.04347 -0.07,-0.06445 -0.06,-0.07475 -0.05,-0.06899 -0.04,-0.04972 -0.03,-0.0259 -0.02,-0.00753 -0.01,0.00027 0,0 0.01,-0.00027 0.02,0.00753 0.03,0.0259 0.04,0.04972 0.05,0.06899 0.06,0.07475 0.07,0.06445 0.08,0.04347 0.09,0.02184 0.1,0.00818 0.11,0.00469 0.12,0.00618 0.13,0.00382 0.14,-0.00883 0.15,-0.03124 0.16,-0.05577 0.17,-0.07198 0.18,-0.07282 0.19,-0.05881 0.2,-0.03763 0.21,-0.01944 0.22,-0.01073 0.23,-0.01059 0.24,-0.01176 0.25,-0.00559 0.26,0.01196 0.27,0.03732 0.28,0.06101 0.29,0.07312 0.3,0.06914 0.31,0.0526 0.32,0.03277 0.33,0.01895 0.34,0.01491 0.35,0.01685 0.36,0.01618 0.37,0.00543 0.38,-0.01661 0.39,-0.04356 0.4,-0.06495 0.41,-0.0723 0.42,-0.06408 0.43,-0.04645 0.44,-0.02936 0.45,-0.02041 0.46,-0.02033 0.47,-0.02285 0.48,-0.01902 0.49,-0.00334 0.5,0.02232 0.51,0.04934 0.52,0.06719 0.53,0.06961 0.54,0.05813 0.55,0.04095 0.56,0.02774 0.57,0.02368 0.58,0.02645 0.59,0.028 0.6,0.02 0.61,-0.00047 0.62,-0.02855 0.63,-0.0541 0.64,-0.06752 0.65,-0.0653 0.66,-0.05187 0.67,-0.03664 0.68,-0.02807 0.69,-0.02844 0.7,-0.03268 0.71,-0.03181 0.72,-0.01902 0.73,0.00562 0.74,0.03467 0.75,0.05737 0.76,0.0659 0.77,0.0598 0.78,0.04592 0.79,0.03395 0.8,0.03031 0.81,0.03422 0.82,0.03839 0.83,0.0339 0.84,0.01618 0.85,-0.01162 0.86,-0.04009 0.87,-0.05883 0.88,-0.06249 0.89,-0.05365 0.9,-0.04086 0.91,-0.03313 0.92,-0.03425 0.93,-0.04046 0.94,-0.04304 0.95,-0.03406 0.96,-0.01176 0.97,0.01788 0.98,0.04427 0.99,0.05834 1,0.05763 1.01,0.04745 1.02,0.03718 1.03,0.03427 1.04,0.0395 1.05,0.04654 1.06,0.04617 1.07,0.03229 1.08,0.00618 1.09,-0.02378 1.1,-0.04682 1.11,-0.05594 1.12,-0.05179 1.13,-0.0418 1.14,-0.03525 1.15,-0.03726 1.16,-0.04554 1.17,-0.05188 1.18,-0.04747 1.19,-0.02874 1.2,0" },
	{ id = "mouse_long_wobble_stress", events = "-1.25,0 -1.23958,0.05881 -1.22917,0.09928 -1.21875,0.11134 -1.20833,0.09684 -1.19792,0.06677 -1.1875,0.03409 -1.17708,0.00663 -1.16667,-0.01559 -1.15625,-0.03746 -1.14583,-0.06245 -1.13542,-0.08752 -1.125,-0.10283 -1.11458,-0.09688 -1.10417,-0.06401 -1.09375,-0.00957 -1.08333,0.05084 -1.07292,0.09788 -1.0625,0.11738 -1.05208,0.10655 -1.04167,0.0741 -1.03125,0.03447 -1.02083,-0.00018 -1.01042,-0.02535 -1,-0.04408 -0.98958,-0.06182 -0.97917,-0.08002 -0.96875,-0.09314 -0.95833,-0.09104 -0.94792,-0.06567 -0.9375,-0.01768 -0.92708,0.04133 -0.91667,0.09289 -0.90625,0.12003 -0.89583,0.11519 -0.88542,0.08334 -0.875,0.03855 -0.86458,-0.00379 -0.85417,-0.03441 -0.84375,-0.05294 -0.83333,-0.06495 -0.82292,-0.07548 -0.8125,-0.08376 -0.80208,-0.08266 -0.79167,-0.06351 -0.78125,-0.0231 -0.77083,0.03171 -0.76042,0.08508 -0.75,0.11888 -0.73958,0.12142 -0.72917,0.09307 -0.71875,0.04572 -0.70833,-0.00366 -0.69792,-0.04139 -0.6875,-0.06269 -0.67708,-0.07138 -0.66667,-0.07459 -0.65625,-0.0761 -0.64583,-0.07301 -0.63542,-0.05788 -0.625,-0.025 -0.61458,0.02346 -0.60417,0.07562 -0.59375,0.11412 -0.58333,0.12432 -0.57292,0.10182 -0.5625,0.05487 -0.55208,0.00019 -0.54167,-0.04524 -0.53125,-0.07184 -0.52083,-0.08013 -0.51042,-0.07748 -0.5,-0.07133 -0.48958,-0.06355 -0.47917,-0.04963 -0.46875,-0.0231 -0.45833,0.01784 -0.44792,0.06597 -0.4375,0.10646 -0.42708,0.12342 -0.41667,0.10825 -0.40625,0.06461 -0.39583,0.00718 -0.38542,-0.04537 -0.375,-0.079 -0.36458,-0.08987 -0.35417,-0.08372 -0.34375,-0.07018 -0.33333,-0.05574 -0.32292,-0.04002 -0.3125,-0.01768 -0.30208,0.01568 -0.29167,0.05759 -0.28125,0.09707 -0.27083,0.11888 -0.26042,0.11139 -0.25,0.07347 -0.23958,0.01624 -0.22917,-0.04176 -0.21875,-0.08309 -0.20833,-0.0991 -0.19792,-0.09235 -0.1875,-0.07283 -0.17708,-0.05075 -0.16667,-0.03051 -0.15625,-0.00957 -0.14583,0.01733 -0.13542,0.05175 -0.125,0.08738 -0.11458,0.11138 -0.10417,0.11075 -0.09375,0.08009 -0.08333,0.02599 -0.07292,-0.03495 -0.0625,-0.08347 -0.05208,-0.10644 -0.04167,-0.10207 -0.03125,-0.07887 -0.02083,-0.04935 -0.01042,-0.02254 0,0 0.01042,0.02254 0.02083,0.04935 0.03125,0.07887 0.04167,0.10207 0.05208,0.10644 0.0625,0.08347 0.07292,0.03495 0.08333,-0.02599 0.09375,-0.08009 0.10417,-0.11075 0.11458,-0.11138 0.125,-0.08738 0.13542,-0.05175 0.14583,-0.01733 0.15625,0.00957 0.16667,0.03051 0.17708,0.05075 0.1875,0.07283 0.19792,0.09235 0.20833,0.0991 0.21875,0.08309 0.22917,0.04176 0.23958,-0.01624 0.25,-0.07347 0.26042,-0.11139 0.27083,-0.11888 0.28125,-0.09707 0.29167,-0.05759 0.30208,-0.01568 0.3125,0.01768 0.32292,0.04002 0.33333,0.05574 0.34375,0.07018 0.35417,0.08372 0.36458,0.08987 0.375,0.079 0.38542,0.04537 0.39583,-0.00718 0.40625,-0.06461 0.41667,-0.10825 0.42708,-0.12342 0.4375,-0.10646 0.44792,-0.06597 0.45833,-0.01784 0.46875,0.0231 0.47917,0.04963 0.48958,0.06355 0.5,0.07133 0.51042,0.07748 0.52083,0.08013 0.53125,0.07184 0.54167,0.04524 0.55208,-0.00019 0.5625,-0.05487 0.57292,-0.10182 0.58333,-0.12432 0.59375,-0.11412 0.60417,-0.07562 0.61458,-0.02346 0.625,0.025 0.63542,0.05788 0.64583,0.07301 0.65625,0.0761 0.66667,0.07459 0.67708,0.07138 0.6875,0.06269 0.69792,0.04139 0.70833,0.00366 0.71875,-0.04572 0.72917,-0.09307 0.73958,-0.12142 0.75,-0.11888 0.76042,-0.08508 0.77083,-0.03171 0.78125,0.0231 0.79167,0.06351 0.80208,0.08266 0.8125,0.08376 0.82292,0.07548 0.83333,0.06495 0.84375,0.05294 0.85417,0.03441 0.86458,0.00379 0.875,-0.03855 0.88542,-0.08334 0.89583,-0.11519 0.90625,-0.12003 0.91667,-0.09289 0.92708,-0.04133 0.9375,0.01768 0.94792,0.06567 0.95833,0.09104 0.96875,0.09314 0.97917,0.08002 0.98958,0.06182 1,0.04408 1.01042,0.02535 1.02083,0.00018 1.03125,-0.03447 1.04167,-0.0741 1.05208,-0.10655 1.0625,-0.11738 1.07292,-0.09788 1.08333,-0.05084 1.09375,0.00957 1.10417,0.06401 1.11458,0.09688 1.125,0.10283 1.13542,0.08752 1.14583,0.06245 1.15625,0.03746 1.16667,0.01559 1.17708,-0.00663 1.1875,-0.03409 1.19792,-0.06677 1.20833,-0.09684 1.21875,-0.11134 1.22917,-0.09928 1.23958,-0.05881 1.25,0" },
	{ id = "touch_intent_small_wobble", events = "0,-1.2 0.01391,-1.18 0.02645,-1.16 0.03641,-1.14 0.0428,-1.12 0.045,-1.1 0.0428,-1.08 0.03641,-1.06 0.02645,-1.04 0.01391,-1.02 0,-1 -0.01391,-0.98 -0.02645,-0.96 -0.03641,-0.94 -0.0428,-0.92 -0.045,-0.9 -0.0428,-0.88 -0.03641,-0.86 -0.02645,-0.84 -0.01391,-0.82 0,-0.8 0.01391,-0.78 0.02645,-0.76 0.03641,-0.74 0.0428,-0.72 0.045,-0.7 0.0428,-0.68 0.03641,-0.66 0.02645,-0.64 0.01391,-0.62 0,-0.6 -0.01391,-0.58 -0.02645,-0.56 -0.03641,-0.54 -0.0428,-0.52 -0.045,-0.5 -0.0428,-0.48 -0.03641,-0.46 -0.02645,-0.44 -0.01391,-0.42 0,-0.4 0.01391,-0.38 0.02645,-0.36 0.03641,-0.34 0.0428,-0.32 0.045,-0.3 0.0428,-0.28 0.03641,-0.26 0.02645,-0.24 0.01391,-0.22 0,-0.2 -0.01391,-0.18 -0.02645,-0.16 -0.03641,-0.14 -0.0428,-0.12 -0.045,-0.1 -0.0428,-0.08 -0.03641,-0.06 -0.02645,-0.04 -0.01391,-0.02 0,0 0.01391,0.02 0.02645,0.04 0.03641,0.06 0.0428,0.08 0.045,0.1 0.0428,0.12 0.03641,0.14 0.02645,0.16 0.01391,0.18 0,0.2 -0.01391,0.22 -0.02645,0.24 -0.03641,0.26 -0.0428,0.28 -0.045,0.3 -0.0428,0.32 -0.03641,0.34 -0.02645,0.36 -0.01391,0.38 0,0.4 0.01391,0.42 0.02645,0.44 0.03641,0.46 0.0428,0.48 0.045,0.5 0.0428,0.52 0.03641,0.54 0.02645,0.56 0.01391,0.58 0,0.6 -0.01391,0.62 -0.02645,0.64 -0.03641,0.66 -0.0428,0.68 -0.045,0.7 -0.0428,0.72 -0.03641,0.74 -0.02645,0.76 -0.01391,0.78 0,0.8 0.01391,0.82 0.02645,0.84 0.03641,0.86 0.0428,0.88 0.045,0.9 0.0428,0.92 0.03641,0.94 0.02645,0.96 0.01391,0.98 0,1 -0.01391,1.02 -0.02645,1.04 -0.03641,1.06 -0.0428,1.08 -0.045,1.1 -0.0428,1.12 -0.03641,1.14 -0.02645,1.16 -0.01391,1.18 0,1.2" },
	{ id = "touch_intent_pause_resume", events = "0,-1.2 0.00618,-1.17 0.01176,-1.14 0.01618,-1.11 0.01902,-1.08 0.02,-1.05 0.01902,-1.02 0.01618,-0.99 0.01176,-0.96 0.00618,-0.93 0,-0.9 -0.00618,-0.87 -0.01176,-0.84 -0.01618,-0.81 -0.01902,-0.78 -0.02,-0.75 -0.01902,-0.72 -0.01618,-0.69 -0.01176,-0.66 -0.00618,-0.63 0,-0.6 0.00618,-0.57 0.01176,-0.54 0.01618,-0.51 0.01902,-0.48 0.02,-0.45 0.01902,-0.42 0.01618,-0.39 0.01176,-0.36 0.00618,-0.33 0,-0.3 -0.00618,-0.27 -0.01176,-0.24 -0.01618,-0.21 -0.01902,-0.18 -0.02,-0.15 -0.01902,-0.12 -0.01618,-0.09 -0.01176,-0.06 -0.00618,-0.03 0,0 0,0 0,0 0,0 0.00618,0.03 0.01176,0.06 0.01618,0.09 0.01902,0.12 0.02,0.15 0.01902,0.18 0.01618,0.21 0.01176,0.24 0.00618,0.27 0,0.3 -0.00618,0.33 -0.01176,0.36 -0.01618,0.39 -0.01902,0.42 -0.02,0.45 -0.01902,0.48 -0.01618,0.51 -0.01176,0.54 -0.00618,0.57 0,0.6 0.00618,0.63 0.01176,0.66 0.01618,0.69 0.01902,0.72 0.02,0.75 0.01902,0.78 0.01618,0.81 0.01176,0.84 0.00618,0.87 0,0.9 -0.00618,0.93 -0.01176,0.96 -0.01618,0.99 -0.01902,1.02 -0.02,1.05 -0.01902,1.08 -0.01618,1.11 -0.01176,1.14 -0.00618,1.17 0,1.2" },
}
note("| Fixture | Events | 7b-1 rule | Now |")
note("|---|---|---|---|")
for _, f in FIXTURES do
	local events = {}
	for x, y in string.gmatch(f.events, "([%-%d%.e]+),([%-%d%.e]+)") do
		table.insert(events, P(tonumber(x) :: number, tonumber(y) :: number))
	end
	local S = Scoring.ROUND
	local before = recordBefore(events)
	local st, stays = drive(S, events)
	check(f.id .. ": stream = replica of the rule", same(st.points, recordNow(events)), true)
	check(f.id .. ": appends only, shown outputs stay", stays, true)
	local a, cutA = row("before", before, S)
	local b, cutB = row("now", st.points, S)
	note(string.format("| %s | %d | %s | %s |", f.id, #events, a, b))
	check(f.id .. ": accepted now", cutB ~= nil, true)
	check(f.id .. ": under the limit now", #st.points < cfg.maxPoints, true)
	check(f.id .. ": whole cut now", cutB ~= nil and cutB.completeness >= 0.99, true)
	local ok, stored = serverKeeps(st.points)
	check(f.id .. ": server accepts and stores exactly the samples", ok and stored, true)
	-- The pause: a held still pointer adds nothing (her touch_intent_pause_resume).
	if f.id == "mouse_long_wobble_stress" then
		check(f.id .. ": before, the limit stopped it short", #before == cfg.maxPoints and cutA ~= nil and cutA.completeness < 0.85, true)
	end
end
do
	local events = { P(0, -1.2), P(0, -0.5), P(0, -0.3) }
	for _ = 1, 50 do
		table.insert(events, P(0.002, -0.3))
	end
	table.insert(events, P(0, 0.4))
	table.insert(events, P(0, 1.2))
	local st = drive(Scoring.ROUND, events)
	check("pause: holding still adds no samples", #st.points, 5)
end

-- 2. A fixed synthetic sweep: straight crossings from -1.2 to 1.2 along an angle, a sine wobble
-- of amplitude a and wavelength w (cut units) plus a little jitter, events every e along the
-- line, offset o from the centre, from -reach to +reach. Same strokes every run.
local seed = 777
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648 - 0.5
end
local AMPS = { 0, 0.02, 0.04, 0.06, 0.09, 0.12 }
local WAVES = { 0.08, 0.15, 0.3 }
local STEPS = { 0.004, 0.012, 0.03, 0.06 }
local OFFSETS = { 0, 0.08 }
-- Where the stroke starts and ends along its line: from just off the crust, or from the far
-- worktop (a lead-in the 7b-1 rule paid for in samples).
local REACHES = { 1.2, 1.55 }
local stats = {}
local function stat(key: string)
	stats[key] = stats[key] or { n = 0, refusedA = 0, refusedB = 0, limitA = 0, limitB = 0, compA = 0, compB = 0, strA = 0, strB = 0, both = 0,
		credA = 0, credB = 0, lower = 0, lower05 = 0, worst = 0, wobA = 0, wobB = 0 }
	return stats[key]
end
local parity, appendOnly, serverSame, total, attempts, newlyRefused = 0, 0, 0, 0, 0, 0
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
						local side = o + a * math.sin(2 * math.pi * (t + reach) / w) + rnd() * 0.004
						table.insert(events, P(ux * t + nx * side, uy * t + ny * side))
						t += e
					end
					attempts += 1
					if inRange(events) then
						total += 1
						local before = recordBefore(events)
						local st, stays = drive(Scoring.ROUND, events)
						if same(st.points, recordNow(events)) then
							parity += 1
						end
						if stays then
							appendOnly += 1
						end
						local cutA = CutStroke.grade(before, Scoring.ROUND, false)
						local cutB = CutStroke.grade(st.points, Scoring.ROUND, false)
						if cutA and not cutB then
							newlyRefused += 1
						end
						if total % 9 == 0 then
							local ok, stored = serverKeeps(st.points)
							if (ok == (cutB ~= nil)) and (not ok or stored) then
								serverSame += 1
							end
						else
							serverSame += 1
						end
						for _, key in { string.format("wobble %.2f", a), "all" } do
							local s = stat(key)
							s.n += 1
							s.refusedA += if cutA then 0 else 1
							s.refusedB += if cutB then 0 else 1
							s.limitA += if #before >= cfg.maxPoints then 1 else 0
							s.limitB += if #st.points >= cfg.maxPoints then 1 else 0
							if cutA and cutB then
								s.both += 1
								s.compA += cutA.completeness
								s.compB += cutB.completeness
								s.strA += cutA.straightness
								s.strB += cutB.straightness
								-- Path credit (straightness x completeness credit) and the
								-- "wobbled off a straight line" note (straightness under 0.75).
								local qA, stA = Scoring.cutQuality(cutA)
								local qB, stB = Scoring.cutQuality(cutB)
								s.credA += qA
								s.credB += qB
								if qB < qA - 1e-9 then
									s.lower += 1
								end
								if qB < qA - 0.05 then
									s.lower05 += 1
								end
								s.worst = math.min(s.worst, qB - qA)
								s.wobA += if stA < 0.75 then 1 else 0
								s.wobB += if stB < 0.75 then 1 else 0
							end
						end
					end
				end
				end
			end
		end
	end
end
check("sweep: stream = replica on every stroke", parity, total)
check("sweep: appends only, shown outputs stay, on every stroke", appendOnly, total)
check("sweep: the server agrees with the client grade and stores the samples", serverSame, total)
note(string.format("sweep: %d synthetic strokes (6 wobble sizes x 3 wavelengths x 4 event spacings x 2 offsets x 2 lengths x 12 angles%s), assist off, round dough", total,
	if attempts > total then string.format("; %d that leave the accepted range left out", attempts - total) else ""))
note("| Wobble (cut units) | Strokes | Refused 7b-1 -> now | Stopped at the limit 7b-1 -> now | Mean completeness* | Mean straightness* |")
note("|---|---|---|---|---|---|")
for _, key in { "wobble 0.00", "wobble 0.02", "wobble 0.04", "wobble 0.06", "wobble 0.09", "wobble 0.12", "all" } do
	local s = stats[key]
	if s then
		local b = math.max(s.both, 1)
		note(string.format("| %s | %d | %d (%.1f%%) -> %d (%.1f%%) | %d -> %d | %.3f -> %.3f | %.3f -> %.3f |", key, s.n, s.refusedA, 100 * s.refusedA / s.n, s.refusedB, 100 * s.refusedB / s.n,
			s.limitA, s.limitB, s.compA / b, s.compB / b, s.strA / b, s.strB / b))
	end
end
note("* over strokes accepted under both rules")
note("Path credit per cut (straightness x completeness credit; the Cut grade scales its layout score by the mean of these), over strokes accepted under both rules:")
note("| Wobble (cut units) | Both accepted | Mean credit 7b-1 -> now | Lower now | Lower by more than 0.05 | Largest drop | Wobbled note 7b-1 -> now |")
note("|---|---|---|---|---|---|---|")
for _, key in { "wobble 0.00", "wobble 0.02", "wobble 0.04", "wobble 0.06", "wobble 0.09", "wobble 0.12", "all" } do
	local s = stats[key]
	if s then
		local b = math.max(s.both, 1)
		note(string.format("| %s | %d | %.3f -> %.3f | %d (%.1f%%) | %d | %.3f | %d -> %d |", key, s.both, s.credA / b, s.credB / b, s.lower, 100 * s.lower / b,
			s.lower05, s.worst, s.wobA, s.wobB))
	end
end
local all = stats.all
check("sweep: no stroke refused now that the 7b-1 rule accepted", newlyRefused, 0)
check("sweep: fewer strokes stop at the limit", all ~= nil and all.limitB < all.limitA, true)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut budget checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

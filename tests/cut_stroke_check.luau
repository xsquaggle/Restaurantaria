-- Checks for the cut stroke contract (slice 3, CutStroke): one append-only raw sample list feeds
-- the live groove, the payload and the server's rebuild, so a replay is identical on any sample
-- history; and the 0.10 cutting assist on top of it (Astra r15 section 3, test proposals). Strokes
-- are synthetic pointer drags driven through the same CutStroke.stream the Cut station uses;
-- serialized outputs are compared client vs server exactly (%.17g), not only final scores. Run
-- offline with tests/offline/run.py, or in Studio Edit after a sync. Arithmetic only: how the
-- groove looks and how a real drag feels are checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Config = require(Shared.Config)
local CutStroke = require(Shared.CutStroke)
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
local function note(line: string)
	table.insert(report, line)
end
local function P(x: number, y: number)
	return { x = x, y = y }
end

local cfg = Config.Cut
local A = cfg.assist
-- The proposals this file assumes.
check("proposal: max points", cfg.maxPoints, 48)
check("proposal: spacing", cfg.spacing, 0.07)
check("proposal: assist off by default", A.on, false)
check("proposal: strength", A.strength, 0.10)
check("proposal: travel gate (u)", A.travel, 0.10)
check("proposal: deviation gate (u)", A.deviation, 0.15)
check("proposal: backtrack gate (u)", A.backtrack, 0.05)
check("proposal: centre gate (u)", A.centre, 0.10)
check("proposal: decay", A.decay, 0.5)

local function ser(path: { any }): string
	local parts = table.create(#path)
	for i, p in path do
		parts[i] = string.format("%.17g,%.17g", p.x, p.y)
	end
	return table.concat(parts, " ")
end

-- Pseudo-random wobble, the same every run.
local seed = 12345
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648 - 0.5
end

-- Doughs: round, a turned oval, the worst thin oval, and the thin oval turned.
local DOUGHS = {
	{ name = "round", S = Scoring.ROUND },
	{ name = "oval 1.0x0.6 turned 30", S = G.shape(1.0, 0.6, math.rad(30)) },
	{ name = "thin 1.1x0.35", S = G.shape(1.1, 0.35, 0) },
	{ name = "thin 1.1x0.35 turned -40", S = G.shape(1.1, 0.35, math.rad(-40)) },
}

-- Pointer drags (cut units, one event per entry). Each takes the dough's axes so strokes cross
-- the actual food.
local function line(ax: number, ay: number, bx: number, by: number, step: number, wobble: number): { any }
	local pts = {}
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy)
	local n = math.max(1, math.floor(len / step))
	local nx, ny = -dy / len, dx / len
	for i = 0, n do
		local t = i / n
		local w = wobble * (math.sin(t * math.pi * 3) * 0.6 + rnd())
		table.insert(pts, P(ax + dx * t + nx * w, ay + dy * t + ny * w))
	end
	return pts
end
local function across(S: any, deg: number, reach: number, step: number, wobble: number, offset: number?): { any }
	-- A stroke along the dough-local direction deg, reach x the half chord each way, shifted
	-- off the centre by `offset` (cut units, normal to it).
	local a = math.rad(deg)
	local u = G.apply(S, P(math.cos(a), math.sin(a)))
	local len = math.sqrt(u.x * u.x + u.y * u.y)
	local nx, ny = -u.y / len, u.x / len
	local o = offset or 0
	return line(-u.x * reach + nx * o, -u.y * reach + ny * o, u.x * reach + nx * o, u.y * reach + ny * o, step, wobble)
end
local function chevron(S: any, deg: number): { any }
	local a = math.rad(deg)
	local u = G.apply(S, P(math.cos(a), math.sin(a)))
	local n = G.apply(S, P(-math.sin(a), math.cos(a)))
	local first = line(-u.x * 1.2, -u.y * 1.2, n.x * 0.5, n.y * 0.5, 0.02, 0)
	local second = line(n.x * 0.5, n.y * 0.5, u.x * 1.2, u.y * 1.2, 0.02, 0)
	for i = 2, #second do
		table.insert(first, second[i])
	end
	return first
end
local function backtrack(S: any, deg: number): { any }
	local a = math.rad(deg)
	local u = G.apply(S, P(math.cos(a), math.sin(a)))
	local pts = line(-u.x * 1.2, -u.y * 1.2, u.x * 0.4, u.y * 0.4, 0.02, 0.004)
	local back = line(u.x * 0.4, u.y * 0.4, u.x * 0.1, u.y * 0.1, 0.02, 0)
	local fwd = line(u.x * 0.1, u.y * 0.1, u.x * 1.2, u.y * 1.2, 0.02, 0.004)
	for i = 2, #back do
		table.insert(pts, back[i])
	end
	for i = 2, #fwd do
		table.insert(pts, fwd[i])
	end
	return pts
end
local function duplicates(S: any): { any }
	local pts = {}
	for _, p in across(S, 20, 1.25, 0.03, 0.01) do
		table.insert(pts, p)
		table.insert(pts, P(p.x, p.y))
	end
	return pts
end
local function reverse(pts: { any }): { any }
	local out = {}
	for i = #pts, 1, -1 do
		table.insert(out, pts[i])
	end
	return out
end
local function outAndBack(): { any }
	-- Leaves the accepted range off the board's edge and comes back beside the pizza.
	local pts = line(-1.0, -1.3, -1.0, -1.9, 0.05, 0)
	for _, p in line(-1.0, -1.9, -1.3, -1.0, 0.05, 0) do
		table.insert(pts, p)
	end
	for _, p in line(-1.3, -1.0, 1.3, 0.2, 0.03, 0.008) do
		table.insert(pts, p)
	end
	return pts
end

local CASES = {
	{ name = "diagonal, slight wobble", make = function(S) return across(S, 45, 1.25, 0.02, 0.012) end },
	{ name = "diagonal reversed", make = function(S) return reverse(across(S, 45, 1.25, 0.02, 0.012)) end },
	{ name = "near the centre, off by 0.05", make = function(S) return across(S, 100, 1.3, 0.02, 0.01, 0.05) end },
	{ name = "near-edge start", make = function(S) return across(S, 10, 1.02, 0.02, 0.008) end },
	{ name = "short stroke (0.6 of the chord)", make = function(S) return across(S, 70, 0.6, 0.02, 0.006) end },
	{ name = "deliberate curve (chevron)", make = function(S) return chevron(S, 30) end },
	{ name = "backtracking", make = function(S) return backtrack(S, 60) end },
	{ name = "duplicate events", make = duplicates },
	{ name = "low sampling (0.25 jumps)", make = function(S) return across(S, 135, 1.3, 0.25, 0.01) end },
	{ name = "high sampling (0.004)", make = function(S) return across(S, 160, 1.25, 0.004, 0.01) end },
	{ name = "sample limit (corner to corner, wobbly)", make = function(_S) return line(-1.58, -1.58, 1.58, 1.58, 0.01, 0.06) end },
	{ name = "leaves the range and comes back", make = function(_S) return outAndBack() end },
}

-- Drives one drag through the stream exactly as the Cut station does (press, moves, release),
-- keeping every output the live groove showed along the way.
local function drive(S: any, on: boolean, events: { any })
	local st = CutStroke.stream(S, on, events[1])
	local shown = { table.clone(st.out) }
	for i = 2, #events do
		CutStroke.record(st, events[i], i == #events)
		table.insert(shown, table.clone(st.out))
	end
	return st, shown
end

-- 1. Replay equality and frozen outputs, assist off and on, every case on every dough.
local equal, frozen, bounded, offRaw, total, tails, latchedCount = 0, 0, 0, 0, 0, 0, 0
local cap = A.strength * A.deviation
for _, d in DOUGHS do
	for _, c in CASES do
		for _, on in { false, true } do
			total += 1
			local label = d.name .. " / " .. c.name .. (if on then " / on" else " / off")
			local st, shown = drive(d.S, on, c.make(d.S))
			local sent = st.points
			check(label .. ": at most maxPoints samples", #sent <= cfg.maxPoints, true)
			if #sent == cfg.maxPoints then
				tails += 1
			end
			-- The server's rebuild from the sent samples, and the batch replay.
			local batch, f = CutStroke.assist(sent, d.S, on)
			local same = ser(batch) == ser(st.out)
			local cut = CutStroke.grade(sent, d.S, on)
			if cut then
				same = same and ser(cut.path) == ser(st.out)
			end
			check(label .. ": client outputs = server rebuild", same, true)
			if same then
				equal += 1
			end
			if f.latched then
				latchedCount += 1
			end
			-- Every output once shown stays (only an open tail at maxPoints may follow the pointer).
			local stays = true
			for _, snap in shown do
				for i, p in snap do
					if i < cfg.maxPoints and (p.x ~= st.out[i].x or p.y ~= st.out[i].y) then
						stays = false
					end
				end
			end
			-- And each prefix's own replay gives the same output for its last sample.
			for k = 1, #sent - 1 do
				local prefix = table.move(sent, 1, k, 1, {})
				local outk = CutStroke.assist(prefix, d.S, on)
				if outk[k].x ~= st.out[k].x or outk[k].y ~= st.out[k].y then
					stays = false
				end
			end
			check(label .. ": earlier outputs never move", stays, true)
			if stays then
				frozen += 1
			end
			-- The correction never exceeds strength x deviation in u; off means no correction.
			local Si = G.inverse(d.S)
			local within, untouched = true, true
			for i, p in sent do
				local o = st.out[i]
				local cu = G.apply(Si, P(o.x - p.x, o.y - p.y))
				if math.sqrt(cu.x * cu.x + cu.y * cu.y) > cap + 1e-12 then
					within = false
				end
				if o.x ~= p.x or o.y ~= p.y then
					untouched = false
				end
			end
			check(label .. ": correction within the bound", within, true)
			if within then
				bounded += 1
			end
			if not on then
				check(label .. ": off leaves every sample raw", untouched, true)
				if untouched then
					offRaw += 1
				end
			end
		end
	end
end
note(string.format("replay: %d/%d strokes (%d doughs x %d cases x off/on) give identical client and server outputs; %d/%d keep every shown output; %d/%d within the %.3f u bound; %d/%d off strokes untouched; %d hit the %d-sample limit (open tail); the assist switched itself off in %d",
	equal, total, #DOUGHS, #CASES, frozen, total, bounded, total, cap, offRaw, total / 2, tails, cfg.maxPoints, latchedCount))

-- 2. Gates. Before 0.10 u of travel nothing is corrected.
do
	local S = Scoring.ROUND
	local st = drive(S, true, across(S, 30, 1.25, 0.02, 0.02))
	local Si = G.inverse(S)
	local travel, early = 0, true
	for i, p in st.points do
		if i > 1 then
			local a, b = G.apply(Si, st.points[i - 1]), G.apply(Si, p)
			travel += math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		end
		if (travel < A.travel or i < 3) and (st.out[i].x ~= p.x or st.out[i].y ~= p.y) then
			early = false
		end
	end
	check("gate: raw before the travel gate", early, true)
	-- A chevron switches the assist off by deviation and backtracking by backtrack, and it never
	-- comes back on: after the switch every output is raw plus a halving fade of the last one.
	local function latch(events: { any }): (string?, boolean)
		local f = CutStroke.filter(S, true)
		local _, ff = CutStroke.assist(drive(S, true, events).points, S, true)
		local fades = true
		if ff.latched then
			local prev = nil
			for i = ff.latched, #ff.raw do
				local c = P(ff.out[i].x - ff.raw[i].x, ff.out[i].y - ff.raw[i].y)
				if prev then
					local want = P(prev.x * A.decay, prev.y * A.decay)
					if math.abs(want.x) + math.abs(want.y) < 1e-5 then
						want = P(0, 0)
					end
					if math.abs(c.x - want.x) > 1e-15 or math.abs(c.y - want.y) > 1e-15 then
						fades = false
					end
				end
				prev = c
			end
		end
		_ = f
		return ff.reason, fades
	end
	local why, fades = latch(chevron(S, 30))
	check("gate: a chevron switches the assist off", why, "deviation")
	check("gate: after the switch only the fade remains", fades, true)
	local whyB, fadesB = latch(backtrack(S, 60))
	check("gate: a backtrack switches the assist off", whyB, "backtrack")
	check("gate: backtrack fade", fadesB, true)
	local whyS = latch(across(S, 30, 1.25, 0.02, 0.01))
	check("gate: a steady stroke keeps the assist", whyS, nil)
end

-- 3. Degenerate input: all samples at one point, and an exact straight line (no correction).
do
	local S = Scoring.ROUND
	local same = CutStroke.assist({ P(0.1, 0.1), P(0.1, 0.1), P(0.1, 0.1), P(0.1, 0.1) }, S, true)
	check("degenerate: one point repeated stays raw", same[4].x == 0.1 and same[4].y == 0.1, true)
	local straight = {}
	for i = 0, 30 do
		table.insert(straight, P(-1.2 + 2.4 * i / 30, 0))
	end
	local out = CutStroke.assist(straight, S, true)
	local moved = 0
	for i, p in out do
		moved = math.max(moved, math.abs(p.y - straight[i].y), math.abs(p.x - straight[i].x))
	end
	check("degenerate: a straight centred line is not moved", moved < 1e-12, true)
	-- Equal-axis spread (a plus sign of samples) has no principal axis: the direction is first ->
	-- newest, and the result is finite.
	local plus = { P(-0.3, 0), P(0.3, 0), P(0, -0.3), P(0, 0.3), P(0, 0) }
	local po = CutStroke.assist(plus, S, true)
	check("degenerate: equal-axis spread stays finite", po[5].x == po[5].x and po[5].y == po[5].y, true)
end

-- 4. The assist only reduces wobble and near-centre miss: along-line progress is unchanged, a
-- bare-board miss stays a miss, a short stroke is not extended, a bad cut stays bad.
do
	local S = G.shape(1.1, 0.35, 0)
	local miss = line(-1.2, 0.6, 1.2, 0.6, 0.02, 0.004)
	local _, rOff = CutStroke.grade(drive(S, false, miss).points, S, false)
	local _, rOn = CutStroke.grade(drive(S, true, miss).points, S, true)
	check("guard: bare-board miss refused, off", rOff, "cut missed the pizza")
	check("guard: bare-board miss refused, on", rOn, "cut missed the pizza")
	local short = across(Scoring.ROUND, 70, 0.6, 0.02, 0.006)
	local off = CutStroke.grade(drive(Scoring.ROUND, false, short).points, Scoring.ROUND, false)
	local on = CutStroke.grade(drive(Scoring.ROUND, true, short).points, Scoring.ROUND, true)
	check("guard: short stroke accepted both ways", off ~= nil and on ~= nil, true)
	if off and on then
		check("guard: short stroke not extended", on.completeness <= off.completeness + 1e-12, true)
		check("guard: raw samples kept with the cut", #on.raw, #drive(Scoring.ROUND, true, short).points)
	end
end

-- 5. Off vs on on identical drags (the A/B table): grades per stroke and per layout.
local function quality(c: any): number
	return if c then (Scoring.cutQuality(c)) else -1
end
note("| Dough | Stroke | Off: straight / complete / dev | On: straight / complete / dev | Quality off -> on | Assist |")
note("|---|---|---|---|---|---|")
local worstGain, steadyChange = 0, 0
for _, d in DOUGHS do
	for _, c in CASES do
		local events = c.make(d.S)
		local sentOff = drive(d.S, false, events).points
		local sentOn = drive(d.S, true, events).points
		check(d.name .. " / " .. c.name .. ": identical raw samples off and on", ser(sentOff), ser(sentOn))
		local cOff, wOff = CutStroke.grade(sentOff, d.S, false)
		local cOn, wOn = CutStroke.grade(sentOn, d.S, true)
		local _, f = CutStroke.assist(sentOn, d.S, true)
		check(d.name .. " / " .. c.name .. ": same acceptance off and on", cOff ~= nil, cOn ~= nil)
		local function cell(x: any, why: string?): string
			return if x then string.format("%.3f / %.3f / %.4f", x.straightness, x.completeness, x.deviation) else "refused (" .. tostring(why) .. ")"
		end
		local qOff, qOn = quality(cOff), quality(cOn)
		if cOff and cOn then
			worstGain = math.max(worstGain, qOn - qOff)
			-- The assist is light both ways: it may lose a little on a curve it fades out of.
			check(d.name .. " / " .. c.name .. ": quality within 0.05 off vs on", math.abs(qOn - qOff) <= 0.05, true)
		end
		if d.name == "round" or c.name == "diagonal, slight wobble" or c.name == "deliberate curve (chevron)" or c.name == "short stroke (0.6 of the chord)" then
			note(string.format("| %s | %s | %s | %s | %.3f -> %.3f | %s |", d.name, c.name, cell(cOff, wOff), cell(cOn, wOn), qOff, qOn,
				if f.latched then "off at sample " .. f.latched .. " (" .. tostring(f.reason) .. ")" else "on"))
		end
		if c.name == "deliberate curve (chevron)" and cOff and cOn then
			check(d.name .. ": a chevron gains nothing that matters", qOn <= qOff + 0.01, true)
			steadyChange = math.max(steadyChange, qOn - qOff)
		end
	end
end
note(string.format("largest quality gain from the assist on one stroke: %.3f (chevron: %.3f)", worstGain, steadyChange))
check("A/B: no stroke gains more than 0.25 quality", worstGain <= 0.25, true)

-- Layouts: 4, 6 and 8 slices by hand-like strokes at the dough-local fair angles.
note("| Dough | Slices | Cut grade off | Cut grade on |")
note("|---|---|---|---|")
for _, d in DOUGHS do
	for _, slices in { 4, 6, 8 } do
		local offLines, onLines = {}, {}
		for k = 0, slices // 2 - 1 do
			local events = across(d.S, 180 * k / (slices // 2) + 7, 1.25, 0.02, 0.015, 0.03)
			local cOff = CutStroke.grade(drive(d.S, false, events).points, d.S, false)
			local cOn = CutStroke.grade(drive(d.S, true, events).points, d.S, true)
			if cOff then
				table.insert(offLines, cOff)
			end
			if cOn then
				table.insert(onLines, cOn)
			end
		end
		local gOff, gOn = Scoring.cut(slices, offLines, d.S).score, Scoring.cut(slices, onLines, d.S).score
		check(d.name .. " " .. slices .. " slices: accepted alike", #offLines, #onLines)
		check(d.name .. " " .. slices .. " slices: on within 6 points of off", math.abs(gOn - gOff) <= 6, true)
		note(string.format("| %s | %d | %d | %d |", d.name, slices, gOff, gOn))
	end
end

-- 6. The groove's runs only grow forward: every prefix's closed runs are the full path's runs.
do
	local st = drive(Scoring.ROUND, true, chevron(Scoring.ROUND, 30))
	local full = CutStroke.runs(st.out)
	local stable = true
	for k = 2, #st.out do
		local keys = CutStroke.runs(table.move(st.out, 1, k, 1, {}))
		for i = 1, #keys - 1 do
			if keys[i] ~= full[i] then
				stable = false
			end
		end
	end
	check("runs: earlier runs never change as the stroke grows", stable, true)
	check("runs: a chevron is more than one run", #full > 2, true)
	local flat = CutStroke.runs({ P(-1, 0), P(-0.5, 0.001), P(0, 0), P(0.5, -0.001), P(1, 0) })
	check("runs: a steady line is one run", #flat, 2)
end

-- 7. Groove ends: pulled in until both corners of the groove are on the dough.
do
	local worst = 0
	for _, d in DOUGHS do
		local Si = G.inverse(d.S)
		for deg = 0, 175, 5 do
			local a = math.rad(deg)
			local dir = P(math.cos(a), math.sin(a))
			local t0, t1 = Scoring.clipToDough(d.S, -3 * dir.x, -3 * dir.y, 3 * dir.x, 3 * dir.y)
			if t0 and t1 then
				local ex, ey = -3 * dir.x + 6 * dir.x * t0, -3 * dir.y + 6 * dir.y * t0
				local s = CutStroke.endInset(d.S, ex, ey, dir.x, dir.y, 0.03, 3 * (t1 - t0))
				local px, py = ex + dir.x * s, ey + dir.y * s
				for _, sign in { 1, -1 } do
					local c = G.apply(Si, P(px - dir.y * 0.03 * sign, py + dir.x * 0.03 * sign))
					if c.x * c.x + c.y * c.y > 1 + 1e-9 then
						worst = math.huge
					end
				end
				worst = math.max(worst, s)
			end
		end
	end
	check("ends: both corners on the dough at every angle and dough", worst < math.huge, true)
	note(string.format("groove ends: largest pull-in %.4f cut units (%.1f px at 1920x1080, frame radius 372 px)", worst, worst * 372))
end

-- 8. The server: the shift's assist rebuilds from the raw samples and keeps both.
do
	local pizza = { id = 7, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
	local session = { shift = { pizzas = { [7] = pizza }, cutAssist = true } } :: any
	local events = across(Scoring.ROUND, 25, 1.25, 0.02, 0.015)
	local st = drive(Scoring.ROUND, true, events)
	local ok = ShiftService.apply(session, "cut", { pizzaId = 7, path = st.points })
	check("server on: accepted", ok, true)
	check("server on: stored path = the live groove", pizza.cuts[1] and ser(pizza.cuts[1].path), ser(st.out))
	check("server on: raw samples kept", pizza.cuts[1] and ser(pizza.cuts[1].raw), ser(st.points))
	check("server on: marked assisted", pizza.cuts[1] and pizza.cuts[1].assisted, true)
	-- A client claiming an assisted path as raw gets it assisted again: the server never trusts it.
	ShiftService.apply(session, "cut", { pizzaId = 7, path = st.out })
	check("server on: sent outputs are treated as raw", pizza.cuts[2] and ser(pizza.cuts[2].raw), ser(st.out))
	session.shift.cutAssist = false
	ShiftService.apply(session, "cut", { pizzaId = 7, path = st.points })
	check("server off: stored path = the raw samples", pizza.cuts[3] and ser(pizza.cuts[3].path), ser(st.points))
	check("server off: no raw copy", pizza.cuts[3] and pizza.cuts[3].raw, nil)
	local okL = ShiftService.apply(session, "cut", { pizzaId = 7, path = table.create(cfg.maxPoints + 1, P(0, 0)) })
	check("server: more than maxPoints refused", okL, false)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut stroke checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

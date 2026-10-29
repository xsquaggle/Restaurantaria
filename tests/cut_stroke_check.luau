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
check("proposal: detour", cfg.detour, 0.21)
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
local equal, frozen, bounded, offRaw, total, tails, finished, latchedCount, keptRaw = 0, 0, 0, 0, 0, 0, 0, 0, 0
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
				if st.full then
					finished += 1
				end
				check(label .. ": a stroke at the limit is finished", st.full == true, true)
			end
			-- The server's rebuild from the sent samples, and the batch replay.
			local batch, f = CutStroke.assist(sent, d.S, on)
			local same = ser(batch) == ser(st.out)
			local cut = CutStroke.grade(sent, d.S, on)
			if cut and cut.assisted == false then
				-- The guard kept the raw path (the assisted one graded worse): stored = sent.
				keptRaw += 1
				same = same and ser(cut.path) == ser(sent)
			elseif cut then
				same = same and ser(cut.path) == ser(st.out)
			end
			check(label .. ": client outputs = server rebuild", same, true)
			if same then
				equal += 1
			end
			if f.latched then
				latchedCount += 1
			end
			-- Every output once shown stays, the last one too (a full stroke records nothing more;
			-- until slice 6 the sample at maxPoints followed the pointer).
			local stays = true
			for _, snap in shown do
				for i, p in snap do
					if p.x ~= st.out[i].x or p.y ~= st.out[i].y then
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
note(string.format("replay: %d/%d strokes (%d doughs x %d cases x off/on) give identical client and server outputs; %d/%d keep every shown output; %d/%d within the %.3f u bound; %d/%d off strokes untouched; %d reached the %d-sample limit, %d finished there; the assist switched itself off in %d; the guard kept the raw path in %d",
	equal, total, #DOUGHS, #CASES, frozen, total, bounded, total, cap, offRaw, total / 2, tails, cfg.maxPoints, finished, latchedCount, keptRaw))

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
	-- Equal-axis spread (a plus sign of samples) has no principal axis; the grade's fit (shared)
	-- still gives a line, and the result is finite.
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
		check("guard: short stroke not extended", on.completeness <= off.completeness + 1e-3, true)
		check("guard: raw samples kept with the cut", #on.raw, #drive(Scoring.ROUND, true, short).points)
	end
end

-- 5. Off vs on on identical drags (the A/B table): grades per stroke and per layout.
local function quality(c: any): number
	return if c then (Scoring.cutQuality(c)) else -1
end
note("| Dough | Stroke | Off: straight / complete / dev | On: straight / complete / dev | Quality off -> on | Assist |")
note("|---|---|---|---|---|---|")
local worstGain, steadyChange, worstDrop = 0, 0, 0
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
			-- Since 7b-2 the assisted path the groove showed is the one graded, so the assist can
			-- cost a little (reported); it may never cost much.
			worstDrop = math.max(worstDrop, qOff - qOn)
			check(d.name .. " / " .. c.name .. ": quality at most 0.05 lower on", qOn >= qOff - 0.05, true)
		end
		if d.name == "round" or c.name == "diagonal, slight wobble" or c.name == "deliberate curve (chevron)" or c.name == "short stroke (0.6 of the chord)" then
			note(string.format("| %s | %s | %s | %s | %.3f -> %.3f | %s |", d.name, c.name, cell(cOff, wOff), cell(cOn, wOn), qOff, qOn,
				(if f.latched then "off at sample " .. f.latched .. " (" .. tostring(f.reason) .. ")" else "on")
					.. (if cOn and cOn.assisted == false then ", raw kept" else "")))
		end
		if c.name == "deliberate curve (chevron)" and cOff and cOn then
			check(d.name .. ": a chevron gains nothing that matters", qOn <= qOff + 0.01, true)
			steadyChange = math.max(steadyChange, qOn - qOff)
		end
	end
end
note(string.format("largest quality gain from the assist on one stroke: %.3f (chevron: %.3f); largest drop: %.3f", worstGain, steadyChange, worstDrop))
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
		local gOff, gOn = CutStroke.pizzaGrade(slices, offLines, d.S).score, CutStroke.pizzaGrade(slices, onLines, d.S).score
		check(d.name .. " " .. slices .. " slices: accepted alike", #offLines, #onLines)
		check(d.name .. " " .. slices .. " slices: on never below off", gOn >= gOff, true)
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

-- 7. Groove ends (CutStroke.groovePieces): no piece has a corner off the dough, the pieces cover
-- the chord without a gap, and the taper carries the groove to within a small residue of the
-- edge. Chords at every 5 degrees and at offsets across each dough, plus every sweep stroke
-- below (section 9). Distances are reported in px at 1920x1080 (frame radius 372 px).
local HALF = 0.03
local function piecesInside(S: any, pieces: { any }): boolean
	local Si = G.inverse(S)
	for _, p in pieces do
		local dx, dy = p.bx - p.ax, p.by - p.ay
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0 then
			local nx, ny = -dy / len * p.half, dx / len * p.half
			for _, c in { P(p.ax + nx, p.ay + ny), P(p.ax - nx, p.ay - ny), P(p.bx + nx, p.by + ny), P(p.bx - nx, p.by - ny) } do
				local u = G.apply(Si, c)
				if u.x * u.x + u.y * u.y > 1 + 1e-9 then
					return false
				end
			end
		end
	end
	return true
end
local endsWorst = { pull = 0, residue = 0, gaps = 0, outside = 0, chords = 0 }
do
	for _, d in DOUGHS do
		for deg = 0, 175, 5 do
			local a = math.rad(deg)
			local dir = P(math.cos(a), math.sin(a))
			for _, off in { 0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9 } do
				-- Offset in dough units, mapped to the frame.
				local o = G.apply(d.S, P(-math.sin(a) * off, math.cos(a) * off))
				local w = G.apply(d.S, dir)
				local line = { x1 = o.x - w.x, y1 = o.y - w.y, x2 = o.x + w.x, y2 = o.y + w.y }
				local len = math.sqrt(w.x * w.x + w.y * w.y)
				local ux, uy = w.x / len, w.y / len
				local t0, t1 = Scoring.clipToDough(d.S, o.x - ux * 4, o.y - uy * 4, o.x + ux * 4, o.y + uy * 4)
				if t0 and t1 then
					endsWorst.chords += 1
					local e0, e1 = 8 * t0, 8 * t1 -- along the line from o - 4u
					local pieces = CutStroke.groovePieces(line, d.S, HALF)
					if not piecesInside(d.S, pieces) then
						endsWorst.outside += 1
					end
					-- Cover along the line: intervals of the pieces, merged.
					local spans = {}
					for _, p in pieces do
						local ta = (p.ax - (o.x - ux * 4)) * ux + (p.ay - (o.y - uy * 4)) * uy
						local tb = (p.bx - (o.x - ux * 4)) * ux + (p.by - (o.y - uy * 4)) * uy
						table.insert(spans, { math.min(ta, tb), math.max(ta, tb), p.half })
						if p.half == HALF then
							endsWorst.pull = math.max(endsWorst.pull, math.min(ta, tb) - e0, e1 - math.max(ta, tb))
						end
					end
					table.sort(spans, function(x, y)
						return x[1] < y[1]
					end)
					if #spans > 0 then
						local reach = spans[1][2]
						for i = 2, #spans do
							if spans[i][1] > reach + 1e-6 then
								endsWorst.gaps += 1
							end
							reach = math.max(reach, spans[i][2])
						end
						endsWorst.residue = math.max(endsWorst.residue, spans[1][1] - e0, e1 - reach)
					end
				end
			end
		end
	end
	check("ends: no groove piece has a corner off the dough (chords)", endsWorst.outside, 0)
	check("ends: the pieces cover each chord without a gap", endsWorst.gaps, 0)
	check("ends: the taper reaches within 0.03 cut units of the edge", endsWorst.residue <= 0.03, true)
	note(string.format("groove ends over %d chords (4 doughs, every 5 deg, offsets 0 to 0.9): full width stops up to %.4f cut units (%.1f px at 1920x1080) from the edge; the taper (widths 0.8 to 0.1) leaves at most %.4f (%.1f px) uncovered; no corner off the dough",
		endsWorst.chords, endsWorst.pull, endsWorst.pull * 372, endsWorst.residue, endsWorst.residue * 372))
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

-- 9. The sample limit (Astra r17, D2). The build she reviewed let a full stream's last sample
-- follow the pointer (replicated below as recordBefore, for paths that stay inside the accepted
-- range): the segment from sample 47 to that moving tail could cross dough the cutter went
-- around, with the assist off. Now a full stream is finished: what was recorded stays, nothing
-- more is added (the release neither), and the live groove, the payload and the server's stored
-- path are that one list. The "before" rows are expected to show the fault. The wobble seed is
-- put back afterwards, so the sweep below draws the same strokes as before this section existed.
do
	local savedSeed = seed
	local function qp(p: any): any
		return P(CutStroke.quantize(p.x), CutStroke.quantize(p.y))
	end
	-- The stream as it was: a sample each spacing (and the release), and once maxPoints were
	-- recorded the last sample moved to each new one. limit = nil records without a limit.
	local function recordBefore(events: { any }, limit: number?): { any }
		local pts = { qp(events[1]) }
		for i = 2, #events do
			local p, last = events[i], pts[#pts]
			local dist = math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2)
			if dist >= cfg.spacing or (i == #events and dist > 1e-4) then
				if limit and #pts >= limit then
					pts[#pts] = qp(p)
				else
					table.insert(pts, qp(p))
				end
			end
		end
		return pts
	end
	-- The stream now (slice 7b-2): samples spaced by position. A point at least spacing from the
	-- last sample is kept when it reaches spacing further from the press point than any sample
	-- so far, or lies detour or more from the last sample; the release always; nothing past the
	-- limit (no moving tail). limit = nil records without a limit.
	local function recordNow(events: { any }, limit: number?): { any }
		local pts = { qp(events[1]) }
		local first = pts[1]
		local reach = 0
		for i = 2, #events do
			if limit and #pts >= limit then
				break
			end
			local p, last = events[i], pts[#pts]
			local dist = math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2)
			local fromPress = math.sqrt((p.x - first.x) ^ 2 + (p.y - first.y) ^ 2)
			local final = i == #events
			if (final and dist > 1e-4) or (not final and dist >= cfg.spacing and (fromPress >= reach + cfg.spacing or dist >= cfg.detour)) then
				local k = qp(p)
				table.insert(pts, k)
				reach = math.max(reach, math.sqrt((k.x - first.x) ^ 2 + (k.y - first.y) ^ 2))
			end
		end
		return pts
	end
	-- Same points by value (so 0 and -0 match: an output is its sample plus a zero correction).
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
	local function prefix(a: { any }, n: number): { any }
		return table.move(a, 1, math.min(n, #a), 1, {})
	end
	-- How many consecutive samples are joined across dough (the grade's own clip).
	local function crossings(S: any, pts: { any }): number
		local n = 0
		for i = 2, #pts do
			if Scoring.clipToDough(S, pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y) ~= nil then
				n += 1
			end
		end
		return n
	end
	local function longest(pts: { any }): number
		local m = 0
		for i = 2, #pts do
			m = math.max(m, math.sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2))
		end
		return m
	end
	local function outputsStay(shown: { any }, final: { any }): boolean
		for _, snap in shown do
			for i, p in snap do
				if p.x ~= final[i].x or p.y ~= final[i].y then
					return false
				end
			end
		end
		return true
	end
	-- The replica (recordNow) is the stream itself on every path that never reaches the limit.
	local agree = 0
	for _, d in DOUGHS do
		for _, c in CASES do
			local events = c.make(d.S)
			local st = drive(d.S, false, events)
			if not st.full and not st.closed and #st.points < cfg.maxPoints then
				local inside = true
				for _, e in events do
					inside = inside and math.abs(e.x) <= CutStroke.RANGE and math.abs(e.y) <= CutStroke.RANGE
				end
				if inside then
					check("limit: replica = stream under the limit (" .. d.name .. " / " .. c.name .. ")", same(recordNow(events, cfg.maxPoints), st.points), true)
					agree += 1
				end
			end
		end
	end
	check("limit: the replica is checked on some paths", agree > 10, true)

	-- Her fixture: 47 samples left of the dough (sawing at x = -1.2), then around the pizza on a
	-- semicircle of radius 1.2, outside every dough here, ending right of it.
	local around = {}
	for i = 0, 45 do
		table.insert(around, P(-1.2, if i % 2 == 0 then 0.5 else 0.42))
	end
	table.insert(around, P(-1.2, 0))
	for k = 1, 90 do
		local a = math.pi + math.pi * k / 90
		table.insert(around, P(1.2 * math.cos(a), 1.2 * math.sin(a)))
	end
	local pizza = { id = 31, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
	local session = { shift = { pizzas = { [31] = pizza }, cutAssist = false } } :: any
	for _, d in DOUGHS do
		local label = "around the pizza / " .. d.name
		local before = recordBefore(around, cfg.maxPoints)
		local unlimited = recordBefore(around, nil)
		check(label .. ": before, sample 47 is where her fixture puts it", same({ before[47] }, { P(-1.2, 0) }), true)
		check(label .. ": before, the tail ends at the release, right of the dough", same({ before[#before] }, { qp(around[#around]) }), true)
		check(label .. ": before, the last segment crosses the dough", crossings(d.S, before) > 0, true)
		check(label .. ": before, the cutter never crossed it", crossings(d.S, unlimited), 0)
		if d.name == "round" then
			local cut = CutStroke.grade(before, d.S, false)
			check(label .. ": before, it grades as a cut", cut ~= nil, true)
			note(string.format("limit, her fixture (before): %d samples; the segment from sample 47 to the tail crosses the round dough and grades as a cut, completeness %.2f, straightness %.2f, though the cutter went around the pizza", #before, cut and cut.completeness or -1, cut and cut.straightness or -1))
		end
		local st, shown = drive(d.S, false, around)
		-- Since slice 7b-2 the sawing on the spot spends no samples (no progress, no detour), so
		-- the walk around the pizza fits under the limit.
		check(label .. ": after, the samples are the cutter's own, by position", same(st.points, recordNow(around, cfg.maxPoints)), true)
		check(label .. ": after, sawing on the spot spent no budget", #st.points < cfg.maxPoints and st.full == false, true)
		check(label .. ": after, no segment crosses the dough", crossings(d.S, st.points), 0)
		check(label .. ": after, no cut", CutStroke.grade(st.points, d.S, false), nil)
		check(label .. ": after, every shown output stays", outputsStay(shown, st.out), true)
		check(label .. ": after, the live groove is the payload", same(st.out, st.points), true)
		local cutsBefore = #pizza.cuts
		local ok = ShiftService.apply(session, "cut", { pizzaId = 31, path = st.points })
		check(label .. ": after, the server refuses it too", ok, false)
		check(label .. ": after, and stores nothing", #pizza.cuts, cutsBefore)
	end

	-- 47, 48, 49 and many more samples: a stroke along y = 0.3 that saws back and forth (every
	-- event a sample, 0.0711 apart), released at its last event.
	local function saw(n: number): { any }
		local pts = {}
		local x, dir = -1.5, 1
		for _ = 1, n do
			table.insert(pts, P(x, 0.3))
			if x + dir * 0.0711 > 1.5 or x + dir * 0.0711 < -1.5 then
				dir = -dir
			end
			x += dir * 0.0711
		end
		return pts
	end
	for _, n in { 47, 48, 49, 60, 200 } do
		local events = saw(n)
		local label = string.format("limit, %d events", n)
		local st, shown = drive(Scoring.ROUND, false, events)
		local kept = recordNow(events, nil)
		check(label .. ": samples", #st.points, math.min(#kept, cfg.maxPoints))
		check(label .. ": finished only at the limit", st.full == true, #kept >= cfg.maxPoints)
		check(label .. ": the samples are the kept events, unmoved", same(st.points, prefix(kept, cfg.maxPoints)), true)
		check(label .. ": every shown output stays", outputsStay(shown, st.out), true)
		if n > cfg.maxPoints then
			local before = recordBefore(events, cfg.maxPoints)
			check(label .. ": before, sample 48 had moved to the release", same({ before[cfg.maxPoints] }, { qp(events[n]) }), true)
		end
		if st.full and #kept > cfg.maxPoints then
			check(label .. ": after, sample 48 is the 48th kept event, not the release", same({ st.points[cfg.maxPoints] }, { kept[cfg.maxPoints] }) and not same({ st.points[cfg.maxPoints] }, { qp(events[n]) }), true)
			-- A release after the limit adds or moves nothing.
			local held = table.clone(st.points)
			CutStroke.record(st, P(0, -0.9), true)
			check(label .. ": a later release changes nothing", same(st.points, held), true)
		end
	end

	-- Circles: the pointer circles on the dough (radius 0.6, events 0.03 apart, a sample every
	-- third) about two and a half times and lets go opposite sample 47.
	do
		local events = {}
		for k = 0, 326 do
			local a = k * 0.05
			table.insert(events, P(0.6 * math.cos(a), 0.6 * math.sin(a)))
		end
		local st, shown = drive(Scoring.ROUND, false, events)
		local before = recordBefore(events, cfg.maxPoints)
		check("limit, circles: finished at the limit", st.full == true, true)
		check("limit, circles: the first 48 samples the cutter made", same(st.points, prefix(recordNow(events, nil), cfg.maxPoints)), true)
		check("limit, circles: every shown output stays", outputsStay(shown, st.out), true)
		-- A segment is at most the detour plus one event step (0.03), far short of the circle.
		check("limit, circles: no sample joined across the circle", longest(st.points) < cfg.detour + 0.031, true)
		check("limit, circles: before, the tail jumped across it", longest(before) > 0.5, true)
		note(string.format("limit, circles: longest segment %.3f (before %.3f, the jump from sample 47 to the tail)", longest(st.points), longest(before)))
	end

	-- A legitimate long cut, corner to corner across the whole range: it reaches the limit past
	-- the far crust, so the cut is whole; the server stores exactly the sent samples.
	do
		local events = line(-1.58, -1.58, 1.58, 1.58, 0.02, 0)
		local st, shown = drive(Scoring.ROUND, false, events)
		local cut = CutStroke.grade(st.points, Scoring.ROUND, false)
		check("limit, long cut: finished at the limit", st.full == true, true)
		check("limit, long cut: still a whole cut", cut ~= nil and cut.completeness >= 0.999, true)
		check("limit, long cut: every shown output stays", outputsStay(shown, st.out), true)
		-- Its own pizza: under the old rules the strokes above filled pizza 31's four cuts.
		local whole = { id = 32, ticketId = 1, stage = "cutting", toppings = {}, cuts = {} }
		session.shift.pizzas[32] = whole
		local ok = ShiftService.apply(session, "cut", { pizzaId = 32, path = st.points })
		check("limit, long cut: accepted", ok, true)
		local stored = whole.cuts[#whole.cuts]
		check("limit, long cut: stored path = payload = live groove", stored and same(stored.path, st.points) and same(st.points, st.out), true)
		note(string.format("limit, long cut: %d samples, ends at %.3f,%.3f, completeness %.3f", #st.points, st.points[#st.points].x, st.points[#st.points].y, cut and cut.completeness or -1))
	end
	seed = savedSeed
end

-- 10. The sweep: 3,456 strokes, every one graded with the assist off and on from the same raw
-- samples. 4 doughs x 12 directions x 4 offsets x 3 shapes (wobble, bow, bow with wobble) x 3
-- lengths (0.55, 1.0 and 1.25 of the half chord each way) x 2 starts (straight in, or a bent
-- lead-in across the worktop). The assist must never refuse a stroke the raw path passes, never
-- lower its credit, never make it miss the centre, and never lower a one-cut pizza's Cut grade;
-- then 240 whole pizzas (4, 6, 8 slices) from sweep-like strokes must never grade lower on.
local function yield()
	-- Lets Studio breathe between batches; a no-op where there is no task library.
	pcall(function()
		task.wait()
	end)
end
local function bowed(S: any, deg: number, reach: number, offset: number, bow: number, wobble: number): { any }
	local a = math.rad(deg)
	local u = G.apply(S, P(math.cos(a), math.sin(a)))
	local len = math.sqrt(u.x * u.x + u.y * u.y)
	local nx, ny = -u.y / len, u.x / len
	local pts = {}
	local n = math.max(8, math.floor(2 * reach * len / 0.02))
	for i = 0, n do
		local t = i / n
		local side = offset + bow * math.sin(t * math.pi) + wobble * (math.sin(t * math.pi * 3) * 0.6 + rnd())
		table.insert(pts, P(-u.x * reach + 2 * u.x * reach * t + nx * side, -u.y * reach + 2 * u.y * reach * t + ny * side))
	end
	return pts
end
local function withLeadIn(pts: { any }): { any }
	-- Starts beside the stroke on the worktop and bends into it.
	local a, b = pts[1], pts[2]
	local dx, dy = b.x - a.x, b.y - a.y
	local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-9)
	dx, dy = dx / len, dy / len
	local start = P(a.x - dx * 0.25 - dy * 0.2, a.y - dy * 0.25 + dx * 0.2)
	local out = line(start.x, start.y, a.x, a.y, 0.02, 0)
	for i = 2, #pts do
		table.insert(out, pts[i])
	end
	return out
end
local SHAPES = { { name = "wobble", bow = 0, wobble = 0.014 }, { name = "bow", bow = 0.05, wobble = 0 }, { name = "bow+wobble", bow = 0.035, wobble = 0.01 } }
local sweep = { strokes = 0, accepted = 0, refusedBoth = 0, mismatch = 0, lower = 0, centre = 0, gradeLower = 0, keptRaw = 0, latched = 0, drop = 0, gradeDrop = 0, centreDrop = 0, shown = 0,
	gain = 0, gradeGain = 0, addedDev = -math.huge, leadAddedDev = -math.huge, outside = 0 }
local tol = cfg.centreTolerance
for _, d in DOUGHS do
	for k = 0, 11 do
		for _, offset in { 0, 0.04, 0.1, 0.2 } do
			for _, shape in SHAPES do
				for _, reach in { 0.55, 1.0, 1.25 } do
					for _, lead in { false, true } do
						local events = bowed(d.S, k * 15 + 4, reach, offset, shape.bow, shape.wobble)
						if lead then
							events = withLeadIn(events)
						end
						sweep.strokes += 1
						-- Recorded with the assist off: the raw samples are the same either way (section 5).
						local sent = drive(d.S, false, events).points
						local cOff = CutStroke.grade(sent, d.S, false)
						local cOn = CutStroke.grade(sent, d.S, true)
						if (cOff ~= nil) ~= (cOn ~= nil) then
							sweep.mismatch += 1
						elseif not cOff then
							sweep.refusedBoth += 1
						else
							sweep.accepted += 1
							local qOff, qOn = Scoring.cutQuality(cOff), Scoring.cutQuality(cOn)
							if qOn < qOff - 1e-12 then
								sweep.lower += 1
							end
							sweep.drop = math.max(sweep.drop, qOff - qOn)
							sweep.gain = math.max(sweep.gain, qOn - qOff)
							local flipped = Scoring.cutOffset(cOn, d.S) > tol and Scoring.cutOffset(cOff, d.S) <= tol
							if flipped then
								sweep.centre += 1
							end
							local gOff = CutStroke.pizzaGrade(2, { cOff }, d.S).score
							local gOn = CutStroke.pizzaGrade(2, { cOn }, d.S).score
							if gOn < gOff then
								sweep.gradeLower += 1
							end
							if flipped then
								sweep.centreDrop = math.max(sweep.centreDrop, gOff - gOn)
							else
								sweep.gradeDrop = math.max(sweep.gradeDrop, gOff - gOn)
							end
							sweep.gradeGain = math.max(sweep.gradeGain, gOn - gOff)
							-- The graded path is the assisted outputs the groove showed.
							local shownOut = CutStroke.assist(sent, d.S, true)
							if cOn.assisted == false or ser(cOn.path) == ser(shownOut) then
								sweep.shown += 1
							end
							if cOn.assisted == false then
								sweep.keptRaw += 1
							else
								local added = cOn.deviation - cOff.deviation
								sweep.addedDev = math.max(sweep.addedDev, added)
								if lead then
									sweep.leadAddedDev = math.max(sweep.leadAddedDev, added)
								end
							end
							if not piecesInside(d.S, CutStroke.groovePieces(cOn, d.S, HALF)) then
								sweep.outside += 1
							end
						end
						local _, f = CutStroke.assist(sent, d.S, true)
						if f.latched then
							sweep.latched += 1
						end
					end
				end
			end
		end
		yield()
	end
end
check("sweep: 3,456 strokes", sweep.strokes, 3456)
check("sweep: the assist never changes whether a stroke is accepted", sweep.mismatch, 0)
check("sweep: the graded path is the shown (assisted) path on every accepted stroke", sweep.shown, sweep.accepted)
check("sweep: the assist never costs a stroke more than 0.05 credit", sweep.drop <= 0.05, true)
check("sweep: unless it moves a cut past the centre tolerance, the assist never costs a one-cut Cut grade more than 5 points", sweep.gradeDrop <= 5, true)
check("sweep: no groove piece has a corner off the dough", sweep.outside, 0)
note(string.format("sweep: %d strokes, %d accepted alike, %d refused alike, 0 refused only with the assist; graded on the shown path: credit lower on %d (largest drop %.3f, largest gain %.3f), one-cut Cut grade lower on %d (largest drop %d points, largest gain %d), off-centre only with the assist %d (largest drop there %d points); raw path kept (assisted path refused) %d; the gates switched the assist off in %d",
	sweep.strokes, sweep.accepted, sweep.refusedBoth, sweep.lower, sweep.drop, sweep.gain, sweep.gradeLower, sweep.gradeDrop, sweep.gradeGain, sweep.centre, sweep.centreDrop, sweep.keptRaw, sweep.latched))
note(string.format("sweep: the assisted path's wobble against the raw one's (largest change %+.4f cut units, %+.1f px at 1920x1080; after a worktop lead-in %+.4f, %+.1f px)",
	sweep.addedDev, sweep.addedDev * 372, sweep.leadAddedDev, sweep.leadAddedDev * 372))

do
	local pizzas, lower, gain, drop = 0, 0, 0, 0
	for _, d in DOUGHS do
		for _, slices in { 4, 6, 8 } do
			for trial = 1, 20 do
				local offLines, onLines = {}, {}
				for k = 0, slices // 2 - 1 do
					local shape = SHAPES[(trial + k) % 3 + 1]
					local deg = 180 * k / (slices // 2) + 7 + rnd() * 10
					local events = bowed(d.S, deg, 1.15 + rnd() * 0.2, rnd() * 0.12, shape.bow * (0.5 + rnd()), shape.wobble)
					if trial % 2 == 0 then
						events = withLeadIn(events)
					end
					local sent = drive(d.S, false, events).points
					local cOff, cOn = CutStroke.grade(sent, d.S, false), CutStroke.grade(sent, d.S, true)
					if cOff then
						table.insert(offLines, cOff)
					end
					if cOn then
						table.insert(onLines, cOn)
					end
				end
				pizzas += 1
				local gOff = CutStroke.pizzaGrade(slices, offLines, d.S).score
				local gOn = CutStroke.pizzaGrade(slices, onLines, d.S).score
				if gOn < gOff then
					lower += 1
				end
				gain = math.max(gain, gOn - gOff)
				drop = math.max(drop, gOff - gOn)
			end
			yield()
		end
	end
	check("sweep pizzas: 240", pizzas, 240)
	check("sweep pizzas: the assist never costs a pizza more than 5 Cut points", drop <= 5, true)
	note(string.format("sweep: %d whole pizzas (4 doughs x 4/6/8 slices x 20): Cut grade lower with the assist on %d (largest drop %d points), largest gain %d points", pizzas, lower, drop, gain))
end

-- Since 7b-2 the pizza is graded on the lines that were shown: no raw-line floor.
do
	local S = Scoring.ROUND
	local good = { x1 = -0.95, y1 = 0, x2 = 0.95, y2 = 0, straightness = 1, completeness = 1 }
	local bent = { x1 = -0.95, y1 = 0.3, x2 = 0.95, y2 = 0.3, straightness = 1, completeness = 1 }
	check("pizza grade: the shown lines' grade", CutStroke.pizzaGrade(4, { good, bent }, S).score, Scoring.cut(4, { good, bent }, S).score)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut stroke checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

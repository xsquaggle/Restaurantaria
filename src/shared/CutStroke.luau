--!strict
-- One cut stroke's sample contract (slice 3, 2026-10-27), shared by the Cut station, the server
-- and the offline checks, so the live groove, the cutter, the committed groove and the grade all
-- come from one sample list:
--
-- 1. The stream. The drag is recorded as one append-only list of raw samples in cut units (the
--    pizza frame, edge 1), each rounded to 1/10000 when recorded: the press point, then a point
--    each time the pointer has moved at least Config.Cut.spacing from the last one, the points
--    where the drag leaves and re-enters the accepted range (+-RANGE), and the release point.
--    A recorded sample is never moved, thinned or resampled. Since slice 7b-2 the budget is spent
--    by position along the cut (Astra r19/r20: wobble and dense events used it up before the
--    cutter crossed the pizza): a point the pointer reaches at least `spacing` from the last
--    sample is recorded only when it carries the cut forward, at least `spacing` further from the
--    press point than any sample so far, or when it is Config.Cut.detour or more from the last
--    sample (a turn or a way back, so no recorded segment cuts a corner by much). Wobble around
--    the line and going back over the cut record nothing new. At Config.Cut.maxPoints samples
--    the stream is full: the stroke is finished there and nothing more is recorded until the
--    next press (the Cut station lifts the cutter so the stop shows). It used to let its last
--    sample follow the pointer instead, which could draw and grade a chord across dough the
--    cutter never crossed (Astra r17, D2). This exact list is what the client sends and the
--    server grades.
-- 2. The assist (Config.Cut.assist; off unless the shift has it on). Each sample's output is a
--    function of the raw samples up to it and nothing later, computed once and kept, so the
--    output for a raw prefix never changes as the stroke grows, and the server rebuilds the same
--    output from the same raw list. See CutStroke.filter for the rule.
-- 3. The grade. CutStroke.grade grades the raw list, then the assisted list, with
--    Scoring.cutPath, and keeps the assisted cut only when it does at least as well as the raw
--    one (see there); otherwise the raw cut. So the assist never refuses a stroke, never makes a
--    cut out of a miss, never makes a short stroke longer and never lowers a grade.
-- 4. The drawing. CutStroke.runs merges nearly straight samples into groove runs with a rule
--    that only looks forward from the last closed run, so runs already drawn never change as
--    the stroke grows, and the committed groove is the live one, except when the guard keeps
--    the raw path: then the committed groove is the raw samples' (at most 0.015 dough units
--    from the live one).

local Config = require(script.Parent.Config)
local PrepGeometry = require(script.Parent.PrepGeometry)
local Scoring = require(script.Parent.Scoring)

type Point = { x: number, y: number }
type Mat2 = PrepGeometry.Mat2

local CutStroke = {}

-- Just inside the server's accepted range (+-1.6), so a clipped sample never rounds past it.
CutStroke.RANGE = 1.599

function CutStroke.quantize(v: number): number
	return math.round(v * 10000) / 10000
end

local function q(p: Point): Point
	return { x = CutStroke.quantize(p.x), y = CutStroke.quantize(p.y) }
end

------------------------------------------------------------------------------------------
-- The assist filter.
--
-- Coordinates: samples and corrections are in cut units (frame units, the units the server
-- grades the path in); the gates are measured in the dough's unit disc u = S^-1 p (edge 1), as
-- Astra asked (r15), on RAW samples only. For sample k with raw prefix r1..rk:
-- * Raw output (no correction) while k < 3 or the raw travel so far (sum of |u(i) - u(i-1)|) is
--   under assist.travel.
-- * Line: the grade's own best-fit line (Scoring.cutFit, the function Scoring.cutPath uses) of
--   r1..rk: the principal axis, in frame units, of the part of the samples on the dough, pointing
--   from r1 towards rk. No correction until that fit exists (it needs three samples' worth on
--   the dough), so a stroke started on the worktop is not bent by its off-pizza lead-in.
-- * Gates, on the raw sample: its distance from the line in u over assist.deviation, or the
--   raw progress along the line falling more than assist.backtrack (u) behind its furthest
--   point so far, switches the assist off for the rest of the stroke (it never comes back on, so
--   it can't flicker). The correction already shown is never taken back: from then on each
--   sample gets the last correction times assist.decay per sample (0.5: a short fade instead of
--   a kink), then nothing.
-- * Correction, a vector normal to the line (so progress along the line never changes):
--   strength x the sample's offset TOWARD the line, plus, when the line passes within
--   assist.centre (u) of the dough's centre, strength x the line's miss TOWARD the centre. It
--   never aims at a ticket's angle. The sum is capped at strength x assist.deviation in u, so
--   the two parts together never exceed that one bound.
------------------------------------------------------------------------------------------

export type Filter = {
	S: Mat2,
	Si: Mat2,
	on: boolean,
	raw: { Point },
	out: { Point },
	travel: number, -- raw travel in u up to the last sample
	latched: number?, -- sample index where the assist switched off
	last: Point, -- correction given to the last sample
	reason: string?, -- why the assist switched off (traces and checks)
}

function CutStroke.filter(S: Mat2, on: boolean): Filter
	return {
		S = S,
		Si = PrepGeometry.inverse(S),
		on = on,
		raw = {},
		out = {},
		travel = 0,
		latched = nil,
		last = { x = 0, y = 0 },
		reason = nil,
	}
end

local function toU(Si: Mat2, x: number, y: number): (number, number)
	return Si.a * x + Si.b * y, Si.c * x + Si.d * y
end

-- The correction for the newest raw sample (frame units), and whether the gates switch the
-- assist off at it.
local function correction(f: Filter): (number, number, string?)
	local cfg = Config.Cut.assist
	local raw, Si = f.raw, f.Si
	local k = #raw
	if k < 3 or f.travel < cfg.travel then
		return 0, 0, nil
	end
	-- The grade's own fit (Scoring.cutFit) of the raw samples so far: the principal axis of the
	-- part on the dough, pointing from the first sample towards the newest. Nothing to correct
	-- until it has a line (fewer than three samples' worth on the dough).
	local fit = Scoring.cutFit(raw, f.S)
	if not fit then
		return 0, 0, nil
	end
	local first, newest = raw[1], raw[k]
	local mx, my, dx, dy = fit.mx, fit.my, fit.ux, fit.uy
	-- Gates in u, on the raw samples: the line mapped by S^-1.
	local mu, mv = toU(Si, mx, my)
	local du, dv = toU(Si, dx, dy)
	local dlen = math.sqrt(du * du + dv * dv)
	du, dv = du / dlen, dv / dlen
	local nu, nv = toU(Si, newest.x, newest.y)
	if math.abs((nu - mu) * dv - (nv - mv) * du) > cfg.deviation then
		return 0, 0, "deviation"
	end
	local fu, fv = toU(Si, first.x, first.y)
	local furthest = -math.huge
	for i = 1, k do
		local u, v = toU(Si, raw[i].x, raw[i].y)
		furthest = math.max(furthest, (u - fu) * du + (v - fv) * dv)
	end
	if furthest - ((nu - fu) * du + (nv - fv) * dv) > cfg.backtrack then
		return 0, 0, "backtrack"
	end
	-- The correction, normal to the line (frame units).
	local nx, ny = -dy, dx
	local offset = (newest.x - mx) * nx + (newest.y - my) * ny -- sample's signed offset from the line
	local amount = -cfg.strength * offset -- toward the line
	local miss = math.abs(mu * dv - mv * du) -- the line's distance from the centre, in u
	if miss < cfg.centre then
		amount += cfg.strength * -(mx * nx + my * ny) -- toward the centre
	end
	local cx, cy = nx * amount, ny * amount
	local cu, cv = toU(Si, cx, cy)
	local size = math.sqrt(cu * cu + cv * cv)
	local cap = cfg.strength * cfg.deviation
	if size > cap then
		cx, cy = cx * cap / size, cy * cap / size
	end
	return cx, cy, nil
end

-- Adds one raw sample (already recorded and rounded) and returns its output, which is kept.
function CutStroke.push(f: Filter, p: Point): Point
	local cfg = Config.Cut.assist
	local prev = f.raw[#f.raw]
	table.insert(f.raw, p)
	if prev then
		local au, av = toU(f.Si, prev.x, prev.y)
		local bu, bv = toU(f.Si, p.x, p.y)
		f.travel += math.sqrt((bu - au) ^ 2 + (bv - av) ^ 2)
	end
	local cx, cy = 0, 0
	if f.on then
		if f.latched then
			cx, cy = f.last.x * cfg.decay, f.last.y * cfg.decay
			if math.abs(cx) + math.abs(cy) < 1e-5 then
				cx, cy = 0, 0
			end
		else
			local why
			cx, cy, why = correction(f)
			if why then
				f.latched, f.reason = #f.raw, why
				cx, cy = f.last.x * cfg.decay, f.last.y * cfg.decay
			end
		end
	end
	f.last = { x = cx, y = cy }
	local out = { x = p.x + cx, y = p.y + cy }
	table.insert(f.out, out)
	return out
end

-- The assisted path for a whole raw list: the server's rebuild, and the replay of a recorded
-- stroke. The same pushes the live stroke made, so the same output.
function CutStroke.assist(raw: { Point }, S: Mat2, on: boolean): ({ Point }, Filter)
	local f = CutStroke.filter(S, on)
	for _, p in raw do
		CutStroke.push(f, p)
	end
	return f.out, f
end

-- Grades a sent raw list on the dough S. Assist off: Scoring.cutPath of the raw list. Assist on:
-- the raw list is graded first and refused exactly when assist off would refuse it; then the
-- assisted path is graded, the very path the live groove showed (Lawson, 2026-10-29: the assist
-- applies alike to the visible cut and the graded path). Only if the assisted path were refused
-- where the raw one is not does the raw cut stand (assisted = false), so the assist never
-- refuses a stroke. The assisted path's grade stands even where it is lower than the raw one's.
function CutStroke.grade(raw: any, S: Mat2, on: boolean): (any?, string?)
	local rawCut, reason = Scoring.cutPath(raw, S)
	if not rawCut then
		return nil, reason
	end
	if not on then
		return rawCut, nil
	end
	local r = rawCut :: any
	-- cutPath has checked the list: plain, at most maxPoints numeric points in range.
	local assisted = CutStroke.assist(r.path, S, true)
	local cut = Scoring.cutPath(assisted, S)
	if cut then
		local c = cut :: any
		c.raw = r.path
		c.assisted = true
		return c, nil
	end
	r.assisted = false
	return r, nil
end

-- The pizza's Cut grade from its stored cuts: Scoring.cut on the lines and paths that were
-- shown, assisted or not.
function CutStroke.pizzaGrade(slices: number, cuts: { any }, S: Mat2?): Scoring.Grade
	return Scoring.cut(slices, cuts, S)
end

------------------------------------------------------------------------------------------
-- The stream: records the drag into raw samples and runs them through the filter as they come.
------------------------------------------------------------------------------------------

export type Stream = {
	S: Mat2,
	reach: number, -- furthest any sample lies from the press point (cut units)
	filter: Filter,
	points: { Point }, -- raw samples
	out: { Point }, -- their outputs (assisted, or the raw samples when off)
	outside: Point?, -- where the path left the accepted range, while it is outside
	closed: boolean, -- the path came back in across the dough; nothing more is recorded
	full: boolean, -- maxPoints samples recorded; nothing more is recorded
	dirty: boolean, -- samples added since the groove was last drawn
}

local function inRange(p: Point): boolean
	return math.abs(p.x) <= CutStroke.RANGE and math.abs(p.y) <= CutStroke.RANGE
end

-- Where the segment from a (inside the range) towards b leaves the range; clipping each axis on
-- its own would bend the path.
local function rangeExit(a: Point, b: Point): Point
	local dx, dy = b.x - a.x, b.y - a.y
	local t = 1
	for _, pair in { { dx, a.x }, { dy, a.y } } do
		local dv, av = pair[1], pair[2]
		if dv > 1e-9 then
			t = math.min(t, (CutStroke.RANGE - av) / dv)
		elseif dv < -1e-9 then
			t = math.min(t, (-CutStroke.RANGE - av) / dv)
		end
	end
	t = math.max(t, 0)
	return { x = a.x + dx * t, y = a.y + dy * t }
end

local function add(st: Stream, p: Point)
	if st.full then
		return
	end
	p = q(p)
	table.insert(st.points, p)
	local first = st.points[1]
	st.reach = math.max(st.reach, math.sqrt((p.x - first.x) ^ 2 + (p.y - first.y) ^ 2))
	table.insert(st.out, CutStroke.push(st.filter, p))
	st.full = #st.points >= Config.Cut.maxPoints
	st.dirty = true
end

-- A stroke starting at the pizza-local press point (clamped into the range).
function CutStroke.stream(S: Mat2, on: boolean, start: Point): Stream
	local st: Stream = {
		S = S,
		reach = 0,
		filter = CutStroke.filter(S, on),
		points = {},
		out = {},
		outside = nil,
		closed = false,
		full = false,
		dirty = false,
	}
	add(st, { x = math.clamp(start.x, -CutStroke.RANGE, CutStroke.RANGE), y = math.clamp(start.y, -CutStroke.RANGE, CutStroke.RANGE) })
	return st
end

-- Records the pointer's pizza-local position (not clamped). `final` is the release.
function CutStroke.record(st: Stream, raw: Point, final: boolean?)
	if CutStroke.stopped(st) then
		return
	end
	local last = st.points[#st.points]
	if st.outside then
		if not inRange(raw) then
			return
		end
		-- Back in range: where it re-entered, unless the jump from where it left would run
		-- across the dough, which the wheel never rolled over. Then the path ends where it left.
		local entry = rangeExit(raw, st.outside :: Point)
		local out = st.outside :: Point
		if Scoring.clipToDough(st.S, out.x, out.y, entry.x, entry.y) ~= nil then
			st.closed = true
			return
		end
		add(st, entry)
		st.outside = nil
		last = st.points[#st.points]
	end
	local dist = math.sqrt((raw.x - last.x) ^ 2 + (raw.y - last.y) ^ 2)
	if not inRange(raw) then
		local exit = rangeExit(last, raw)
		if math.sqrt((exit.x - last.x) ^ 2 + (exit.y - last.y) ^ 2) > 1e-4 then
			add(st, exit)
		end
		st.outside = st.points[#st.points]
		return
	end
	if final then
		if dist > 1e-4 then
			add(st, raw)
		end
		return
	end
	if dist < Config.Cut.spacing then
		return
	end
	-- The budget goes by position: forward along the cut, or a real turn (see the header).
	local first = st.points[1]
	local fromPress = math.sqrt((raw.x - first.x) ^ 2 + (raw.y - first.y) ^ 2)
	if fromPress >= st.reach + Config.Cut.spacing or dist >= Config.Cut.detour then
		add(st, raw)
	end
end

-- True once the stroke records nothing more: full (maxPoints samples), or closed by a jump back
-- across the dough. The path stays as recorded and is what the release sends.
function CutStroke.stopped(st: Stream): boolean
	return st.closed or st.full
end

-- The correction the newest sample got (frame units), for the cutter's contact point.
function CutStroke.lastCorrection(st: Stream): Point
	local n = #st.points
	if n == 0 then
		return { x = 0, y = 0 }
	end
	return { x = st.out[n].x - st.points[n].x, y = st.out[n].y - st.points[n].y }
end

------------------------------------------------------------------------------------------
-- Drawing helpers.
------------------------------------------------------------------------------------------

-- The groove's runs: indices into `path` where one straight groove piece ends and the next
-- starts. A run from i grows while every sample between i and its far end stays within `tol` of
-- the line between them; the first sample that breaks it closes the run at the sample before.
-- Closed runs depend only on the samples up to the one that closed them, so adding samples
-- never changes them (only the last, open run grows).
function CutStroke.runs(path: { Point }, tol: number?): { number }
	local tolerance = tol or 0.008
	local n = #path
	if n == 0 then
		return {}
	end
	local keys = { 1 }
	local i = 1
	local j = i + 1
	while j <= n do
		-- Can the run i..j hold?
		local a, b = path[i], path[j]
		local dx, dy = b.x - a.x, b.y - a.y
		local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-9)
		local fits = true
		for k = i + 1, j - 1 do
			local p = path[k]
			if math.abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len > tolerance then
				fits = false
				break
			end
		end
		if fits then
			j += 1
		else
			i = j - 1
			table.insert(keys, i)
			j = i + 1
		end
	end
	if keys[#keys] ~= n then
		table.insert(keys, n)
	end
	return keys
end

-- How far along the groove (from point e, heading inward along unit d) a groove of half-width
-- `half` (cut units) must start so both its corners lie on the dough. 0 when the corners are
-- already inside. maxInset caps it and must not pass the point where the run could leave the
-- dough again (half the run when both its ends are on the edge).
function CutStroke.endInset(S: Mat2, ex: number, ey: number, dx: number, dy: number, half: number, maxInset: number): number
	local Si = PrepGeometry.inverse(S)
	local nx, ny = -dy * half, dx * half
	local function inside(s: number): boolean
		local px, py = ex + dx * s, ey + dy * s
		local au, av = toU(Si, px + nx, py + ny)
		local bu, bv = toU(Si, px - nx, py - ny)
		return au * au + av * av <= 1 and bu * bu + bv * bv <= 1
	end
	if inside(0) then
		return 0
	end
	if not inside(maxInset) then
		return maxInset
	end
	local lo, hi = 0, maxInset
	for _ = 1, 24 do
		local mid = (lo + hi) / 2
		if inside(mid) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

-- The groove's end taper: the widths (shares of the full half-width) of the steps that carry the
-- groove from where its full width fits on the dough out to the crust's edge. Each narrower step
-- starts where its own corners fit, so the visible groove narrows into the crust instead of
-- stopping short of it or crossing it, the way a mask cut to the crust would show it. The gap
-- left between the narrowest step and the edge is the residue the checks measure.
CutStroke.TAPER = { 1, 0.8, 0.6, 0.45, 0.3, 0.2, 0.1 }
-- Pieces along one run overlap this far (cut units) at a join or a taper step, so no gap opens.
CutStroke.JOIN = 0.008

export type Piece = { ax: number, ay: number, bx: number, by: number, half: number, whole: boolean }

-- Whether both corners of a groove of half-width `half` at point (px, py), heading along unit
-- (dx, dy), lie on the dough.
local function cornersIn(Si: Mat2, px: number, py: number, dx: number, dy: number, half: number): boolean
	local nx, ny = -dy * half, dx * half
	local au, av = toU(Si, px + nx, py + ny)
	local bu, bv = toU(Si, px - nx, py - ny)
	return au * au + av * av <= 1 and bu * bu + bv * bv <= 1
end

-- One end of a groove piece from e heading inward along d (span: the piece's length). `edge` is
-- true when e is on the dough's edge; otherwise e is a join or the path's own end, where the
-- piece reaches `reach` past e (a join's overlap) when its corners stay on the dough there. Gives
-- the inset of the full-width piece's end and the taper steps (narrower pieces) beyond it.
local function grooveEnd(S: Mat2, Si: Mat2, ex: number, ey: number, dx: number, dy: number, half: number, span: number, maxInset: number, edge: boolean, reach: number, out: { Piece })
	if not edge and cornersIn(Si, ex - dx * reach, ey - dy * reach, dx, dy, half) then
		return -reach
	end
	local steps = CutStroke.TAPER
	local full = CutStroke.endInset(S, ex, ey, dx, dy, half, maxInset)
	local outer = full -- where the last (wider) step begins
	for i = 2, #steps do
		local w = half * steps[i]
		local s = CutStroke.endInset(S, ex, ey, dx, dy, w, maxInset)
		if s < outer and cornersIn(Si, ex + dx * s, ey + dy * s, dx, dy, w) then
			local stop = math.min(outer + CutStroke.JOIN, span / 2)
			if stop > s and cornersIn(Si, ex + dx * stop, ey + dy * stop, dx, dy, w) then
				table.insert(out, { ax = ex + dx * s, ay = ey + dy * s, bx = ex + dx * stop, by = ey + dy * stop, half = w, whole = false })
			end
			outer = s
		end
	end
	return full
end

-- The groove pieces for a cut (the committed path or the live stroke, or a plain line) on the
-- dough S, half-width `half` (cut units). A path is drawn along its runs (CutStroke.runs), each
-- clipped to the dough with the grade's own clip (Scoring.clipToDough); a plain line (x1..y2, no
-- path) as the chord of its infinite line across the dough, with the art's own tapered ends
-- (whole). Wherever a full-width end would put a corner past the crust (at the dough's edge, or
-- at a join near the rim), the full-width piece stops where its corners fit and the taper steps
-- carry the groove on toward the edge. No piece has a corner off the dough.
function CutStroke.groovePieces(line: any, S: Mat2, half: number): { Piece }
	local Si = PrepGeometry.inverse(S)
	local pieces: { Piece } = {}
	local function piece(ax: number, ay: number, bx: number, by: number, startEdge: boolean, endEdge: boolean, startReach: number, endReach: number, whole: boolean)
		local dx, dy = bx - ax, by - ay
		local span = math.sqrt(dx * dx + dy * dy)
		if span < 1e-4 then
			return
		end
		local ux, uy = dx / span, dy / span
		local maxInset = if startEdge and endEdge then span / 2 else span
		local tapers: { Piece } = {}
		local s0 = grooveEnd(S, Si, ax, ay, ux, uy, half, span, maxInset, startEdge, startReach, tapers)
		local s1 = grooveEnd(S, Si, bx, by, -ux, -uy, half, span, maxInset, endEdge, endReach, tapers)
		-- endInset gives up at maxInset on a run too short or too close to the rim for the full
		-- width: then only the taper steps that fit are drawn.
		if s0 + s1 < span and cornersIn(Si, ax + ux * s0, ay + uy * s0, ux, uy, half) and cornersIn(Si, bx - ux * s1, by - uy * s1, ux, uy, half) then
			table.insert(pieces, { ax = ax + ux * s0, ay = ay + uy * s0, bx = bx - ux * s1, by = by - uy * s1, half = half, whole = whole })
		end
		for _, t in tapers do
			table.insert(pieces, t)
		end
	end
	local path = line.path
	if path then
		local keys = CutStroke.runs(path)
		for i = 2, #keys do
			local a, b = path[keys[i - 1]], path[keys[i]]
			local t0, t1 = Scoring.clipToDough(S, a.x, a.y, b.x, b.y)
			if t0 and t1 then
				local dx, dy = b.x - a.x, b.y - a.y
				piece(a.x + dx * t0, a.y + dy * t0, a.x + dx * t1, a.y + dy * t1, t0 > 0, t1 < 1, if i > 2 then CutStroke.JOIN else 0, if i < #keys then CutStroke.JOIN else 0, false)
			end
		end
		return pieces
	end
	local dx, dy = line.x2 - line.x1, line.y2 - line.y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1e-4 then
		return pieces
	end
	-- The infinite line, long enough to cross any dough (semi-axes stop at 1.1), clipped to it.
	local ux, uy = dx / len, dy / len
	local ax, ay, bx, by = line.x1 - ux * 4, line.y1 - uy * 4, line.x2 + ux * 4, line.y2 + uy * 4
	local t0, t1 = Scoring.clipToDough(S, ax, ay, bx, by)
	if t0 and t1 then
		local ex, ey = bx - ax, by - ay
		piece(ax + ex * t0, ay + ey * t0, ax + ex * t1, ay + ey * t1, true, true, 0, 0, true)
	end
	return pieces
end

return CutStroke

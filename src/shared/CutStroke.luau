--!strict
-- One cut stroke's sample contract (slice 3, 2026-10-27), shared by the Cut station, the server
-- and the offline checks, so the live groove, the cutter, the committed groove and the grade all
-- come from one sample list:
--
-- 1. The stream. The drag is recorded as one append-only list of raw samples in cut units (the
--    pizza frame, edge 1), each rounded to 1/10000 when recorded: the press point, then a point
--    each time the pointer has moved at least Config.Cut.spacing from the last one, the points
--    where the drag leaves and re-enters the accepted range (+-RANGE), and the release point.
--    A recorded sample is never moved, thinned or resampled. At Config.Cut.maxPoints samples
--    the stream is full and its last sample becomes the open tail: it follows the pointer until
--    release, and only its own output changes. This exact list is what the client sends and the
--    server grades.
-- 2. The assist (Config.Cut.assist; off unless the shift has it on). Each sample's output is a
--    function of the raw samples up to it and nothing later, computed once and kept, so the
--    output for a raw prefix never changes as the stroke grows, and the server rebuilds the same
--    output from the same raw list. See CutStroke.filter for the rule.
-- 3. The grade. CutStroke.grade grades the assisted list with Scoring.cutPath, and only when the
--    raw list is accepted too; the cut keeps the raw list's completeness when that is lower, so
--    the assist never makes a cut out of a miss or makes a short stroke longer.
-- 4. The drawing. CutStroke.runs merges nearly straight samples into groove runs with a rule
--    that only looks forward from the last closed run, so runs already drawn never change as
--    the stroke grows, and the committed groove is the live one.

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
-- * Line: the principal axis of r1..rk in frame units (unweighted mean and covariance, the same
--   method as Scoring.cutPath), pointing from r1 towards rk. Degenerate cases: all samples at
--   one point gives no correction; equal-axis covariance (no clear axis) uses the direction
--   r1 -> rk, and no correction when that is zero too.
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

function CutStroke.clone(f: Filter): Filter
	return {
		S = f.S,
		Si = f.Si,
		on = f.on,
		raw = table.clone(f.raw),
		out = table.clone(f.out),
		travel = f.travel,
		latched = f.latched,
		last = f.last,
		reason = f.reason,
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
	local mx, my = 0, 0
	for i = 1, k do
		mx += raw[i].x
		my += raw[i].y
	end
	mx /= k
	my /= k
	local sxx, syy, sxy = 0, 0, 0
	for i = 1, k do
		local dx, dy = raw[i].x - mx, raw[i].y - my
		sxx += dx * dx
		syy += dy * dy
		sxy += dx * dy
	end
	if sxx + syy < 1e-12 then
		return 0, 0, nil
	end
	local first, newest = raw[1], raw[k]
	local tx, ty = newest.x - first.x, newest.y - first.y
	local dx, dy
	if math.sqrt((sxx - syy) ^ 2 + 4 * sxy * sxy) < 1e-9 * (sxx + syy) then
		local len = math.sqrt(tx * tx + ty * ty)
		if len < 1e-9 then
			return 0, 0, nil
		end
		dx, dy = tx / len, ty / len
	else
		local theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
		dx, dy = math.cos(theta), math.sin(theta)
		if dx * tx + dy * ty < 0 then
			dx, dy = -dx, -dy
		end
	end
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

-- Grades a sent raw list on the dough S: the assisted path (when on) graded by Scoring.cutPath,
-- accepted only when the raw list is accepted too, with the raw list's completeness when that
-- is lower. The cut keeps the assisted path (drawn) and the raw samples.
function CutStroke.grade(raw: any, S: Mat2, on: boolean): (any?, string?)
	local rawCut, reason = Scoring.cutPath(raw, S)
	if not rawCut then
		return nil, reason
	end
	if not on then
		return rawCut, nil
	end
	-- cutPath has checked the list: plain, at most maxPoints numeric points in range.
	local assisted = CutStroke.assist(rawCut.path, S, true)
	local cut, why = Scoring.cutPath(assisted, S)
	if not cut then
		return nil, why
	end
	local c = cut :: any
	c.completeness = math.min(c.completeness, (rawCut :: any).completeness)
	c.raw = rawCut.path
	c.assisted = true
	return c, nil
end

------------------------------------------------------------------------------------------
-- The stream: records the drag into raw samples and runs them through the filter as they come.
------------------------------------------------------------------------------------------

export type Stream = {
	S: Mat2,
	filter: Filter,
	before: Filter?, -- the filter before the open tail was pushed (full stream)
	points: { Point }, -- raw samples
	out: { Point }, -- their outputs (assisted, or the raw samples when off)
	outside: Point?, -- where the path left the accepted range, while it is outside
	closed: boolean, -- the path came back in across the dough; nothing more is recorded
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
	p = q(p)
	local n = #st.points
	if n >= Config.Cut.maxPoints then
		-- Full: the last sample is the open tail and follows the pointer; earlier outputs stay.
		local f = CutStroke.clone(st.before :: Filter)
		st.points[n] = p
		st.out[n] = CutStroke.push(f, p)
		st.filter = f
	else
		if n + 1 == Config.Cut.maxPoints then
			st.before = CutStroke.clone(st.filter)
		end
		table.insert(st.points, p)
		table.insert(st.out, CutStroke.push(st.filter, p))
	end
	st.dirty = true
end

-- A stroke starting at the pizza-local press point (clamped into the range).
function CutStroke.stream(S: Mat2, on: boolean, start: Point): Stream
	local st: Stream = {
		S = S,
		filter = CutStroke.filter(S, on),
		before = nil,
		points = {},
		out = {},
		outside = nil,
		closed = false,
		dirty = false,
	}
	add(st, { x = math.clamp(start.x, -CutStroke.RANGE, CutStroke.RANGE), y = math.clamp(start.y, -CutStroke.RANGE, CutStroke.RANGE) })
	return st
end

-- Records the pointer's pizza-local position (not clamped). `final` is the release.
function CutStroke.record(st: Stream, raw: Point, final: boolean?)
	if st.closed then
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
	if dist >= Config.Cut.spacing or (final and dist > 1e-4) then
		add(st, raw)
	end
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

-- How far to pull the groove's end at the dough's edge (point e, the run heading inward along
-- unit d) so both corners of a groove of half-width `half` (cut units) lie on the dough. The
-- visible stroke ends inside the crust; the geometry and the grade are unchanged. 0 when the
-- corners are already inside. maxInset caps it and must not pass the point where the run could
-- leave the dough again (half the run when both its ends are on the edge).
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

return CutStroke

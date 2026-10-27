--!strict
-- The Make tab's sauce step (Lawson, 2026-10-26): pour ladles of marinara onto the rolled dough
-- and spread them with the back of the ladle. Pure functions shared by the server
-- (authoritative), the client (drawing and the live spread preview) and the tests. Constants are
-- Config.Sauce's proposals.
--
-- Positions are dough-local (PrepGeometry: q = 0.95 S^-1 p, so radius 0.95 is the dough's edge
-- whatever its shape, and the sauce follows the oval the player rolled).
--
-- The sauce is a thickness field on a fine square grid of cells (Config.Sauce.cell apart, out to
-- Config.Sauce.extent, past the dough's edge so spilled sauce lies on the board). A pour lays one
-- ladle (one unit of sauce) evenly over the cells within pourRadius of its point. A spread walks
-- the dragged path in exact spreadStep marks; at each mark the ladle's back, a disc of
-- ladleRadius, takes pick of the sauce under it into its load and lays lay of its load back over
-- the same cells, so sauce is dragged along and evened out. What is left in the ladle at the end
-- is laid where it last touched. Sauce is never created or lost: the field always holds exactly
-- one unit per pour.
--
-- The grade reads the same field the client draws (so what looks bare is graded bare): coverage
-- is the plan's (rev 6, 3.2) fractional credit, min(1, thickness / half an even 3-ladle layer),
-- averaged over the edible area (dough-local 0.84); amount compares the pours with 3; clean is
-- the share of sauce on the edible area (sauce off the dough counts twice).
--
-- Stored on a pizza as make.sauce = { actions }, in order:
--   { kind = "pour", x, y }               one ladle at dough-local (x, y)
--   { kind = "spread", points = { {x, y} } }  one spread stroke's dragged path
-- The field is replayed from the actions, so Undo just removes the last one. Replays are
-- memoised (MakeSauce.replay): a record whose actions extend or cut back a recent one replays
-- only from the nearest saved snapshot, so per-frame reads and the server's per-spread check do
-- not redo the whole record.

local Config = require(script.Parent.Config)

local MakeSauce = {}

export type Vec = { x: number, y: number }
export type Action = { kind: string, x: number?, y: number?, points: { Vec }? }
export type Sauce = { actions: { Action } }
export type Field = { number }
export type Grade = { score: number, notes: { string }, detail: any? }

local CRUST = 0.95 -- the dough's edge, dough-local
local EDGE = 0.84 -- the edible area's edge (sauce, cheese and topping limit)

-- The grid, built once: cell i sits at (xs[i], ys[i]), rs[i] from the centre. index[gx][gy] maps
-- grid coordinates to cells (nil past the extent).
local H = Config.Sauce.cell
local N = math.floor(Config.Sauce.extent / H + 0.5)
local xs: { number }, ys: { number }, rs: { number } = {}, {}, {}
local index: { [number]: { [number]: number } } = {}
for gx = -N, N do
	index[gx] = {}
	for gy = -N, N do
		local x, y = gx * H, gy * H
		local r = math.sqrt(x * x + y * y)
		if r <= Config.Sauce.extent + 1e-9 then
			table.insert(xs, x)
			table.insert(ys, y)
			table.insert(rs, r)
			index[gx][gy] = #xs
		end
	end
end
MakeSauce.CELL = H
MakeSauce.GRID = N
-- The cell at grid coordinates (gx, gy), or nil past the extent.
function MakeSauce.cellAt(gx: number, gy: number): number?
	local column = index[gx]
	return column and column[gy]
end
MakeSauce.xs, MakeSauce.ys, MakeSauce.rs = xs, ys, rs
MakeSauce.COUNT = #xs
local CELL_AREA = H * H

-- Edible cells (centre within 0.84) and the full-credit thickness: half an even layer of the
-- target pours over the edible disc (the plan's "half an even share").
local edible = 0
for i = 1, #rs do
	if rs[i] <= EDGE then
		edible += 1
	end
end
MakeSauce.EDIBLE_CELLS = edible
MakeSauce.EVEN = Config.Sauce.targetPours / (math.pi * EDGE * EDGE)
MakeSauce.HALF = MakeSauce.EVEN / 2

local function finite(v: any, limit: number): boolean
	return type(v) == "number" and v == v and v >= -limit and v <= limit
end

-- The cells whose centres lie within radius R of (x, y).
function MakeSauce.cellsNear(x: number, y: number, R: number): { number }
	local out = {}
	local r2 = R * R + 1e-12
	for gx = math.floor((x - R) / H), math.ceil((x + R) / H) do
		local column = index[gx]
		if column then
			for gy = math.floor((y - R) / H), math.ceil((y + R) / H) do
				local i = column[gy]
				if i and (xs[i] - x) ^ 2 + (ys[i] - y) ^ 2 <= r2 then
					table.insert(out, i)
				end
			end
		end
	end
	return out
end

function MakeSauce.empty(): Field
	return table.create(#xs, 0)
end

-- One ladle at q. Returns false (and changes nothing) when no cell is in reach.
function MakeSauce.pour(field: Field, q: Vec): boolean
	local cells = MakeSauce.cellsNear(q.x, q.y, Config.Sauce.pourRadius)
	if #cells == 0 then
		return false
	end
	local add = 1 / (#cells * CELL_AREA)
	for _, i in cells do
		field[i] += add
	end
	return true
end

-- The exact spreadStep marks along a path (its first point, then every spreadStep of travel
-- along the straight segments between points), so equal paths spread equally whatever the
-- pointer's event rate.
function MakeSauce.marks(points: { Vec }): { Vec }
	local step = Config.Sauce.spreadStep
	local out = { { x = points[1].x, y = points[1].y } }
	local carried = 0
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local dx, dy = b.x - a.x, b.y - a.y
		local len = math.sqrt(dx * dx + dy * dy)
		local t = step - carried
		while t <= len + 1e-12 do
			table.insert(out, { x = a.x + dx * t / len, y = a.y + dy * t / len })
			t += step
		end
		carried = len - (t - step)
	end
	return out
end

-- One spread stroke along points. Returns crossed (the ladle touched sauce at least occupied
-- thick somewhere along the way) and moved (sauce it picked up in all).
function MakeSauce.spread(field: Field, points: { Vec }): (boolean, number)
	local cfg = Config.Sauce
	local load, moved, crossed = 0, 0, false
	local last: { number }? = nil
	for _, m in MakeSauce.marks(points) do
		local cells = MakeSauce.cellsNear(m.x, m.y, cfg.ladleRadius)
		if #cells > 0 then
			local mass = 0
			for _, i in cells do
				mass += field[i]
				-- Only sauce on the dough counts (plan rev 6, 3.2 clips to the dough): a stroke
				-- beside the pizza over sauce spilled on the board does not.
				if field[i] >= cfg.occupied and rs[i] <= CRUST then
					crossed = true
				end
			end
			mass *= CELL_AREA
			local take = cfg.pick * mass
			moved += take
			load += take
			local lay = cfg.lay * load
			load -= lay
			local add = lay / (#cells * CELL_AREA)
			for _, i in cells do
				field[i] = field[i] * (1 - cfg.pick) + add
			end
			last = cells
		end
	end
	if last and load > 0 then
		local add = load / (#last * CELL_AREA)
		for _, i in last do
			field[i] += add
		end
	end
	return crossed, moved
end

-- Applies one stored action: the pours and spread-met state after it.
local function apply(field: Field, a: Action, pours: number, spreadMet: boolean): (number, boolean)
	if a.kind == "pour" then
		if MakeSauce.pour(field, { x = a.x :: number, y = a.y :: number }) then
			pours += 1
		end
	else
		local crossed, moved = MakeSauce.spread(field, a.points :: { Vec })
		if crossed and moved > 0 then
			spreadMet = true
		end
	end
	return pours, spreadMet
end

-- Two stored actions with the same values (a record copied to the client is new tables with the
-- same contents, so the memo compares values, every point of a spread).
local function sameAction(a: Action, b: Action): boolean
	if rawequal(a, b) then
		return true
	end
	if a.kind ~= b.kind or a.x ~= b.x or a.y ~= b.y then
		return false
	end
	local pa, pb = a.points, b.points
	if pa == nil or pb == nil then
		return pa == pb
	end
	if #pa ~= #pb then
		return false
	end
	for i = 1, #pa do
		if pa[i].x ~= pb[i].x or pa[i].y ~= pb[i].y then
			return false
		end
	end
	return true
end

-- The replay memo: up to MEMO recent histories, each the actions it replayed and snapshots of
-- the state after every SNAP-th action and after its last (snapshot fields are never changed).
type Snap = { field: Field, pours: number, met: boolean }
type Memo = { actions: { Action }, snaps: { [number]: Snap } }
local MEMO, SNAP = 16, 4
local memos: { Memo } = {}
local EMPTY: Snap = { field = MakeSauce.empty(), pours = 0, met = false }

-- Replays stored actions: the field (shared: read it, never change it), the pour count, and
-- whether a spread moved sauce (the step's minimum, D7).
function MakeSauce.replay(sauce: Sauce): (Field, number, boolean)
	local actions = sauce.actions
	local n = #actions
	if n == 0 then
		return EMPTY.field, 0, false
	end
	-- The recent history sharing the longest prefix with this record.
	local best, bestAt, shared = nil :: Memo?, 0, 0
	for at, memo in memos do
		local k, limit = 0, math.min(n, #memo.actions)
		while k < limit and sameAction(memo.actions[k + 1], actions[k + 1]) do
			k += 1
		end
		if best == nil or k > shared then
			best, bestAt, shared = memo, at, k
		end
	end
	if best and shared == n and best.snaps[n] then
		local s = best.snaps[n]
		table.remove(memos, bestAt)
		table.insert(memos, 1, best)
		return s.field, s.pours, s.met
	end
	-- Start from the latest snapshot inside the shared prefix; a history that shares nothing
	-- gets a memo of its own, one that diverged (Undo, then something new) replaces its old one.
	local memo: Memo
	local base, start = EMPTY, 0
	if best and shared > 0 then
		memo = best
		table.remove(memos, bestAt)
		for j = shared, 1, -1 do
			if memo.snaps[j] then
				base, start = memo.snaps[j], j
				break
			end
		end
		for j in memo.snaps do
			if j > shared then
				memo.snaps[j] = nil
			end
		end
	else
		memo = { actions = {}, snaps = {} }
	end
	memo.actions = table.move(actions, 1, n, 1, table.create(n))
	local field = table.clone(base.field)
	local pours, met = base.pours, base.met
	for i = start + 1, n do
		pours, met = apply(field, actions[i], pours, met)
		if i == n then
			memo.snaps[i] = { field = field, pours = pours, met = met }
		elseif i % SNAP == 0 then
			memo.snaps[i] = { field = table.clone(field), pours = pours, met = met }
		end
	end
	table.insert(memos, 1, memo)
	if #memos > MEMO then
		table.remove(memos)
	end
	return field, pours, met
end

-- As replay, but the caller's own copy of the field (free to change).
function MakeSauce.field(sauce: Sauce): (Field, number, boolean)
	local field, pours, spreadMet = MakeSauce.replay(sauce)
	return table.clone(field), pours, spreadMet
end

-- The same replay without the memo (the tests' reference).
function MakeSauce.replayUncached(sauce: Sauce): (Field, number, boolean)
	local field = MakeSauce.empty()
	local pours, met = 0, false
	for _, a in sauce.actions do
		pours, met = apply(field, a, pours, met)
	end
	return field, pours, met
end

function MakeSauce.counts(sauce: Sauce): (number, number)
	local pours, spreads = 0, 0
	for _, a in sauce.actions do
		if a.kind == "pour" then
			pours += 1
		else
			spreads += 1
		end
	end
	return pours, spreads
end

------------------------------------------------------------------------------------------
-- Checks (server), each before anything is stored. Each returns the clean action to store.

function MakeSauce.validatePour(sauce: Sauce, args: any): (Action?, string?)
	local cfg = Config.Sauce
	if not finite(args.x, CRUST) or not finite(args.y, CRUST) then
		return nil, "pour off the dough"
	end
	if args.x * args.x + args.y * args.y > CRUST * CRUST then
		return nil, "pour off the dough"
	end
	if (MakeSauce.counts(sauce)) >= cfg.maxPours then
		return nil, "too many ladles"
	end
	return { kind = "pour", x = args.x, y = args.y }, nil
end

-- A true array of 2..maxPoints points: exactly #points keys, so a list stuffed with extra keys is
-- refused, and counting stops one past the length (bounded work whatever was sent).
local function pointList(points: any, max: number): ({ Vec }?, string?)
	if type(points) ~= "table" then
		return nil, "bad spread"
	end
	local n = #points
	if n < 2 then
		return nil, "spread too short"
	elseif n > max then
		return nil, "spread too long"
	end
	local keys = 0
	for _ in next, points do
		keys += 1
		if keys > n then
			return nil, "bad spread"
		end
	end
	local reach = Config.Sauce.strokeReach
	local clean = table.create(n)
	for i = 1, n do
		local p = points[i]
		if type(p) ~= "table" or not finite(p.x, reach) or not finite(p.y, reach) then
			return nil, "spread out of range"
		end
		clean[i] = { x = p.x, y = p.y }
	end
	return clean, nil
end
MakeSauce.pointList = pointList

function MakeSauce.validateSpread(sauce: Sauce, args: any): (Action?, string?)
	local cfg = Config.Sauce
	local pours, spreads = MakeSauce.counts(sauce)
	if pours == 0 then
		return nil, "pour some sauce first"
	end
	if spreads >= cfg.maxSpreads then
		return nil, "too many spreads"
	end
	local points, reason = pointList(args.points, cfg.maxPoints)
	if not points then
		return nil, reason
	end
	local length = 0
	for i = 2, #points do
		length += math.sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].y - points[i - 1].y) ^ 2)
	end
	if length < cfg.minSpread then
		return nil, "spread too short"
	elseif length > cfg.maxSpread then
		return nil, "spread too long"
	end
	-- It must cross sauce on the dough (rev 6): a stroke over bare dough or the board alone is
	-- refused. The record's field comes from the memo, so this replays one spread, not the record.
	local field = MakeSauce.field(sauce)
	local crossed = MakeSauce.spread(field, points)
	if not crossed then
		return nil, "spread missed the sauce"
	end
	return { kind = "spread", points = points }, nil
end

-- The step's minimum (D7): a pour and a spread that moved sauce.
function MakeSauce.canFinish(sauce: Sauce): boolean
	local _, pours, spreadMet = MakeSauce.replay(sauce)
	return pours > 0 and spreadMet
end

------------------------------------------------------------------------------------------
-- Grade

-- The coverage ceiling's ramp (plan rev 6, 5.3d): 35 at e <= 0.25, none from 0.75.
function MakeSauce.ceiling(e: number): number
	local cfg = Config.Sauce
	local t = math.clamp((e - cfg.ceilingFrom) / (cfg.ceilingTo - cfg.ceilingFrom), 0, 1)
	return math.floor(cfg.ceilingFloor + (100 - cfg.ceilingFloor) * t + 0.5 + 1e-9)
end

-- Coverage of the edible area, and the sauce on the crust band and off the dough (shares of
-- the total).
function MakeSauce.measure(field: Field): (number, number, number, number)
	local coverage, total, crust, off = 0, 0, 0, 0
	for i = 1, #rs do
		local t = field[i]
		total += t
		if rs[i] <= EDGE then
			coverage += math.min(1, t / MakeSauce.HALF)
		elseif rs[i] <= CRUST then
			crust += t
		else
			off += t
		end
	end
	coverage /= edible
	if total <= 0 then
		return coverage, 0, 0, 0
	end
	return coverage, crust / total, off / total, total * CELL_AREA
end

function MakeSauce.grade(sauce: Sauce): Grade
	local cfg = Config.Sauce
	local field, pours = MakeSauce.replay(sauce)
	local coverage, crust, off = MakeSauce.measure(field)
	local amount = math.clamp(1 - math.abs(pours - cfg.targetPours) / cfg.targetPours, 0, 1)
	-- No sauce earns no clean credit either: an empty step scores 0.
	local clean = if pours == 0 then 0 else math.clamp(1 - crust - cfg.offWeight * off, 0, 1)
	local score = math.floor(100 * (cfg.amountWeight * amount + cfg.coverWeight * coverage + cfg.cleanWeight * clean) + 0.5 + 1e-9)
	local notes = {}
	if pours == 0 then
		table.insert(notes, "No sauce")
	elseif pours < cfg.targetPours then
		table.insert(notes, "Not enough sauce")
	elseif pours > cfg.targetPours then
		table.insert(notes, "Too much sauce")
	end
	if pours > 0 and coverage < cfg.bareBelow then
		table.insert(notes, "Bare spots in the sauce")
	end
	if off > cfg.spillAbove then
		table.insert(notes, "Sauce spilled off the dough")
	end
	if crust > cfg.crustAbove then
		table.insert(notes, "Sauce on the crust")
	end
	return {
		score = score,
		notes = notes,
		detail = {
			pours = pours,
			amount = amount,
			coverage = coverage,
			clean = clean,
			crust = crust,
			off = off,
			ceiling = MakeSauce.ceiling(coverage),
		},
	}
end

return MakeSauce

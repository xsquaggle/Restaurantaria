--!strict
-- Prep food models on dough-local coordinates (PrepGeometry): sauce cells, pours and spreads,
-- and cheese pinches with their frozen footprint sample. Pure functions shared by server,
-- client and tests. Quantities and weights are the cooking plan's proposals (rev 6, 3.2/3.3);
-- the corrections from Astra's response 9 are marked.

local PrepFood = {}

local CRUST = 0.95
local SAUCE_EDGE = 0.84
-- Three equal-area sauce rings inside 0.84, then the crust ring to 0.95.
PrepFood.RINGS = { SAUCE_EDGE * math.sqrt(1 / 3), SAUCE_EDGE * math.sqrt(2 / 3), SAUCE_EDGE, CRUST }
PrepFood.SECTORS = 8
PrepFood.SAUCE_CELLS = 24 -- cells 1..24 hold sauce; 25..32 are the crust ring
PrepFood.CELLS = 32
PrepFood.POUR_REACH = 0.35 -- a pour splits over cells whose centres are this close (proposal)
PrepFood.PICKUP = 0.5 -- a spread picks up this share of its pickup cell (proposal)
PrepFood.OCCUPIED = 0.01 -- a cell holding at least this much sauce counts as food (proposal)
PrepFood.STROKE_SAMPLES = 512 -- fixed samples along a spread stroke (frozen)
PrepFood.TARGET_POURS = 3
PrepFood.HALF_SHARE = 3 / 24 / 2 -- 0.0625

PrepFood.PINCH_STEP = 0.25 -- one pinch per 0.25 of travel (proposal)
PrepFood.PINCH_RADIUS = 0.17 -- footprint disc (plan rev 6)
PrepFood.TARGET_PINCHES = 24
PrepFood.MAX_PINCHES = 48
PrepFood.PINCH_REACH = 1.5 -- dough-local radius past which a pinch is refused (proposal)

export type Vec = { x: number, y: number }

-- Cell of a dough-local point: 1..24 sauce, 25..32 crust, nil past the outline.
function PrepFood.cellOf(q: Vec): number?
	local r = math.sqrt(q.x * q.x + q.y * q.y)
	if r > CRUST then
		return nil
	end
	local ring = 4
	for i, edge in PrepFood.RINGS do
		if r <= edge then
			ring = i
			break
		end
	end
	local a = math.atan2(q.y, q.x) % (2 * math.pi)
	local sector = math.min(math.floor(a / (2 * math.pi / PrepFood.SECTORS)), PrepFood.SECTORS - 1) + 1
	return (ring - 1) * PrepFood.SECTORS + sector
end

-- Area centroid of each cell (annular sector), computed once.
PrepFood.centroids = {} :: { Vec }
do
	local half = math.pi / PrepFood.SECTORS
	local inner = 0
	for ring, outer in PrepFood.RINGS do
		local rc = (2 / 3) * (outer ^ 3 - inner ^ 3) / (outer ^ 2 - inner ^ 2) * math.sin(half) / half
		for sector = 1, PrepFood.SECTORS do
			local a = (sector - 0.5) * 2 * half
			PrepFood.centroids[(ring - 1) * PrepFood.SECTORS + sector] = { x = rc * math.cos(a), y = rc * math.sin(a) }
		end
		inner = outer
	end
end

function PrepFood.emptyCells(): { number }
	local cells = table.create(PrepFood.CELLS, 0)
	return cells
end

-- One ladleful at q, split equally over the cells whose centres lie within POUR_REACH (always
-- including the cell it lands in). Returns false when q is off the dough.
function PrepFood.pour(cells: { number }, q: Vec): boolean
	local landed = PrepFood.cellOf(q)
	if not landed then
		return false
	end
	local targets = { [landed] = true }
	local n = 1
	for i, c in PrepFood.centroids do
		if i ~= landed and (c.x - q.x) ^ 2 + (c.y - q.y) ^ 2 <= PrepFood.POUR_REACH ^ 2 then
			targets[i] = true
			n += 1
		end
	end
	for i in targets do
		cells[i] += 1 / n
	end
	return true
end

-- The cells a straight dough-local stroke crosses, in order, from fixed samples. Samples past
-- the outline add nothing: sauce carried past 0.95 stays in the crust cell where it left.
function PrepFood.cellsCrossed(q1: Vec, q2: Vec): { number }
	local out = {}
	local last: number? = nil
	for i = 0, PrepFood.STROKE_SAMPLES do
		local t = i / PrepFood.STROKE_SAMPLES
		local cell = PrepFood.cellOf({ x = q1.x + (q2.x - q1.x) * t, y = q1.y + (q2.y - q1.y) * t })
		if cell and cell ~= last then
			table.insert(out, cell)
			last = cell
		end
	end
	return out
end

-- One spread stroke. Rev 6 picked up from the start cell only, so a stroke admitted because it
-- crossed sauce could move nothing. Corrected (Astra r9): it picks up from the FIRST cell along
-- the stroke that holds sauce (OCCUPIED or more), then lays that sauce evenly over every cell it
-- crosses from there on, the pickup cell included. Returns accepted (the stroke crossed food)
-- and transfer, the sauce that left the pickup cell. Only an accepted stroke with transfer > 0
-- meets the step's spread minimum (D7); an accepted stroke with no transfer is still graded.
function PrepFood.spread(cells: { number }, q1: Vec, q2: Vec): (boolean, number)
	local crossed = PrepFood.cellsCrossed(q1, q2)
	local start: number? = nil
	for i, cell in crossed do
		if cells[cell] >= PrepFood.OCCUPIED then
			start = i
			break
		end
	end
	if not start then
		return false, 0
	end
	local lay: { number } = {}
	local seen: { [number]: boolean } = {}
	for i = start, #crossed do
		local cell = crossed[i]
		if not seen[cell] then
			seen[cell] = true
			table.insert(lay, cell)
		end
	end
	local pickup = crossed[start]
	local picked = cells[pickup] * PrepFood.PICKUP
	cells[pickup] -= picked
	for _, cell in lay do
		cells[cell] += picked / #lay
	end
	return true, picked * (#lay - 1) / #lay
end

export type SauceAction = { kind: string, x: number, y: number, x2: number?, y2: number? }

-- Replays stored actions in order. Returns the cells, the pour count and whether the spread
-- minimum is met (an accepted spread with positive transfer).
function PrepFood.sauce(actions: { SauceAction }): ({ number }, number, boolean)
	local cells = PrepFood.emptyCells()
	local pours, spreadMet = 0, false
	for _, a in actions do
		if a.kind == "pour" then
			if PrepFood.pour(cells, { x = a.x, y = a.y }) then
				pours += 1
			end
		else
			local ok, moved = PrepFood.spread(cells, { x = a.x, y = a.y }, { x = a.x2 :: number, y = a.y2 :: number })
			if ok and moved > 0 then
				spreadMet = true
			end
		end
	end
	return cells, pours, spreadMet
end

-- Sauce score parts (plan 3.2): amount, fractional coverage over the 24 sauce cells, clean crust.
function PrepFood.sauceScore(cells: { number }, pours: number): (number, number, number, number)
	local amount = math.clamp(1 - math.abs(pours - PrepFood.TARGET_POURS) / PrepFood.TARGET_POURS, 0, 1)
	local coverage, total, crust = 0, 0, 0
	for i = 1, PrepFood.CELLS do
		total += cells[i]
		if i <= PrepFood.SAUCE_CELLS then
			coverage += math.min(1, cells[i] / PrepFood.HALF_SHARE)
		else
			crust += cells[i]
		end
	end
	coverage /= PrepFood.SAUCE_CELLS
	local clean = if total > 0 then 1 - crust / total else 1
	return math.floor(100 * (0.3 * amount + 0.5 * coverage + 0.2 * clean) + 0.5), amount, coverage, clean
end

-- Cheese pinches along a held path. A pinch lands at the press point and then at every exact
-- PINCH_STEP of travel along the straight segments between pointer samples (interpolated), so
-- equal physical paths give equal pinches whatever the event rate. Travel counts both ways, so
-- a reversal keeps sprinkling. Returns a sampler: feed(q) takes the next pointer sample and
-- returns the pinches it placed.
export type Sampler = { feed: (q: Vec) -> { Vec } }

function PrepFood.sampler(): Sampler
	local last: Vec? = nil
	local carried = 0 -- travel since the last pinch
	local function feed(q: Vec): { Vec }
		local placed = {}
		if not last then
			last = q
			table.insert(placed, { x = q.x, y = q.y })
			return placed
		end
		local from = last :: Vec
		local dx, dy = q.x - from.x, q.y - from.y
		local len = math.sqrt(dx * dx + dy * dy)
		local t = PrepFood.PINCH_STEP - carried
		while t <= len + 1e-12 do
			table.insert(placed, { x = from.x + dx * t / len, y = from.y + dy * t / len })
			t += PrepFood.PINCH_STEP
		end
		carried = len - (t - PrepFood.PINCH_STEP)
		last = q
		return placed
	end
	return { feed = feed }
end

-- Server check for one stroke's consecutive points (replaces rev 6's "at least 0.2 apart",
-- which refuses legitimate reversals): a chord is never longer than its arc, so consecutive
-- pinches of one stroke are at most PINCH_STEP apart.
function PrepFood.strokeSpacingOk(points: { Vec }): boolean
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 > (PrepFood.PINCH_STEP + 1e-6) ^ 2 then
			return false
		end
	end
	return true
end

-- Validates one batch of cheese pinches against a pizza's committed strokes WITHOUT changing
-- them (Astra r13 item 3): the whole candidate is checked first and the caller commits only on
-- success, so a refused batch leaves points, counts and sequencing exactly as they were. The
-- server's cheese handler must call this before it touches state. Checks: a non-empty list of
-- finite points within PINCH_REACH (spill past the outline lands on the board and scores as
-- crust or nothing), the pizza's pinch cap, and the spacing rule across the
-- join with the held stroke's last pinch. The chord rule is necessary for reversals, not proof
-- of travelled distance; ownership, step, sequence and rate are the handler's own checks.
function PrepFood.validateCheeseBatch(strokes: { { Vec } }, points: { Vec }, newStroke: boolean): (boolean, string?)
	if type(points) ~= "table" or #points == 0 then
		return false, "empty"
	end
	local held = 0
	for _, st in strokes do
		held += #st
	end
	if held + #points > PrepFood.MAX_PINCHES then
		return false, "cap"
	end
	for _, pt in points do
		if type(pt) ~= "table" or type(pt.x) ~= "number" or type(pt.y) ~= "number" then
			return false, "type"
		end
		if pt.x ~= pt.x or pt.y ~= pt.y or math.abs(pt.x) == math.huge or math.abs(pt.y) == math.huge then
			return false, "finite"
		end
		if pt.x * pt.x + pt.y * pt.y > PrepFood.PINCH_REACH * PrepFood.PINCH_REACH then
			return false, "bounds"
		end
	end
	local candidate = {}
	local current = strokes[#strokes]
	if not newStroke and current and #current > 0 then
		table.insert(candidate, current[#current])
	end
	for _, pt in points do
		table.insert(candidate, pt)
	end
	if not PrepFood.strokeSpacingOk(candidate) then
		return false, "spacing"
	end
	return true, nil
end

-- Frozen 37-point footprint sample of a pinch disc: the centre, then rings of 6, 12 and 18 at
-- the radii that give every point an equal share of the disc's area (sqrt((before + n / 2) /
-- 37) of the radius), turned 0, 15 and 10 degrees. Each point stands for area pi R^2 / 37.
PrepFood.FOOTPRINT = {} :: { Vec }
do
	table.insert(PrepFood.FOOTPRINT, { x = 0, y = 0 })
	local before = 1
	for _, ring in { { 6, 0 }, { 12, 15 }, { 18, 10 } } do
		local n, turn = ring[1], ring[2]
		local r = math.sqrt((before + n / 2) / 37)
		for i = 0, n - 1 do
			local a = math.rad(turn + i * 360 / n)
			table.insert(PrepFood.FOOTPRINT, { x = r * math.cos(a), y = r * math.sin(a) })
		end
		before += n
	end
end
PrepFood.PINCH_AREA = math.pi * PrepFood.PINCH_RADIUS ^ 2

-- Footprint area of the pinches in each sauce cell. Overlap adds (two pinches over one spot
-- count twice); the per-cell credit cap below stops that from paying more than full credit.
function PrepFood.footprint(pinches: { Vec }): { number }
	local area = table.create(PrepFood.SAUCE_CELLS, 0)
	local share = PrepFood.PINCH_AREA / #PrepFood.FOOTPRINT
	for _, p in pinches do
		for _, o in PrepFood.FOOTPRINT do
			local cell = PrepFood.cellOf({ x = p.x + o.x * PrepFood.PINCH_RADIUS, y = p.y + o.y * PrepFood.PINCH_RADIUS })
			if cell and cell <= PrepFood.SAUCE_CELLS then
				area[cell] += share
			end
		end
	end
	return area
end

-- Cheese score (plan 3.3): count of pinch centres inside the sauce area, spread from footprint
-- credit (min(1, area / a quarter pinch) averaged over the 24 cells), crust pinches penalised.
function PrepFood.cheeseScore(pinches: { Vec }): (number, number, number, number)
	local inside, crust = 0, 0
	for _, p in pinches do
		local r = math.sqrt(p.x * p.x + p.y * p.y)
		if r <= SAUCE_EDGE then
			inside += 1
		elseif r <= CRUST then
			crust += 1
		end
	end
	local spread = 0
	for _, a in PrepFood.footprint(pinches) do
		spread += math.min(1, a / (PrepFood.PINCH_AREA / 4))
	end
	spread /= PrepFood.SAUCE_CELLS
	local count = math.clamp(1 - math.abs(inside - PrepFood.TARGET_PINCHES) / PrepFood.TARGET_PINCHES, 0, 1)
	local score = math.floor(100 * math.clamp(0.6 * count + 0.4 * spread - 0.5 * crust / PrepFood.TARGET_PINCHES, 0, 1) + 0.5)
	return score, inside, spread, crust
end

return PrepFood

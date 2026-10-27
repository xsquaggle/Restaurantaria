--!strict
-- What the sauce looks like, read from the same thickness field the grade reads (MakeSauce):
-- pure functions shared by the client renderer (MakeLayers) and the tests. Presentation only:
-- nothing here changes the field, the pours or the grade.
--
-- Astra r14 (art-integration.md): one thick marinara material drawn through the coverage the
-- field already holds, never a translucent stamp. Each field cell on the dough that carries
-- sauce shows one disc of the material map, sampled at the disc's own dough-local place, so
-- neighbouring discs show one continuous material. Amount is never drawn as transparency:
--  * "full": a covered cell (at least SOLID credit) whose four neighbours are covered too is a
--    disc a little larger than the cell (FULL), so a covered patch closes up with no gaps;
--  * "edge": any other cell next to a covered cell is a FULL disc pushed back toward the patch
--    (against the way the credit falls, read from its four neighbours) so that it reaches out
--    just as far as the cell's credit (its outer point at credit - 1/2 cells from the cell's
--    centre): the drawn edge sits where the scored edge is, and neighbouring edge discs overlap
--    into one rim with shallow scallops, not a row of beads or a staircase;
--  * "speck": a cell with no covered neighbour is a disc whose area is its credit (AREA), a
--    little off the grid (JITTER), so a thin trace reads as scattered specks, not a dot grid.
-- No disc reaches more than EDGE_TOL (2 reference HD px) onto a cell drawn bare, so the drawn
-- edge never invents coverage or fills a hole; a disc that would is narrowed.
--
-- Material span (decided in slice 2, recorded in the hand-off): the 1024 px material maps cover
-- the dough-local square -1..1 (radius 1.0) in every view; the dough's edge is 0.95 and no disc
-- reaches past it. Sauce off the dough (radius past 0.95, out to the field's 1.2) is not drawn as
-- material: the board shows it only through the spill smear (sauce_board_spill_v2), placed from
-- the recorded spill.

local Config = require(script.Parent.Config)
local MakeSauce = require(script.Parent.MakeSauce)

local SauceCover = {}

local CELL = MakeSauce.CELL
local xs, ys, rs = MakeSauce.xs, MakeSauce.ys, MakeSauce.rs

SauceCover.SPAN = 1.0 -- the material maps' half width, dough-local
SauceCover.DOUGH = 0.95 -- cells out to here are drawn as material
-- Proposals (looks, not grading): a cell under BARE credit is drawn bare; one at SOLID credit
-- or more counts as covered (a patch of cells at half credit or more reads as covered sauce,
-- thinner sauce as specks); disc diameters as multiples of the cell: AREA keeps a speck's area
-- equal to its credit (2 / sqrt(pi)), FULL closes a covered patch (at least sqrt 2, so four
-- neighbours leave no hole) and is the edge discs' size (their scallops are 0.18 cells deep);
-- the deep-red tint of a thick layer (its 5x5 mean) starts at DEEP_FROM even layers and is full
-- DEEP_SPAN later.
SauceCover.BARE = 0.03
SauceCover.SOLID = 0.5
SauceCover.AREA = 2 / math.sqrt(math.pi)
SauceCover.FULL = 1.6
SauceCover.DEEP_FROM = 1.3
SauceCover.DEEP_SPAN = 1.7
-- Sizes are rounded to this share of a cell (fewer resizes).
SauceCover.STEP = 0.05
-- A speck sits off its cell centre by a fixed amount up to JITTER cells each way (from the
-- cell's index); it still samples the map at its own drawn place.
SauceCover.JITTER = 0.35
-- How far drawn sauce may reach onto a cell drawn bare (under BARE credit), in cells: Astra's
-- edge rule allows at most 2 reference HD px, and a cell is 16.5 px at the HD Make size
-- (F = 661), so 0.12 cell = 1.98 px. Holds for every disc at every size (a disc's size is
-- dough-local); MakeLayers' pinhole guard keeps to it too.
SauceCover.EDGE_TOL = 0.12

-- The material cells (drawn on the dough), each one's four grid neighbours (0 past the field's
-- extent or off the dough, which count as bare) and its 5x5 block (for the deep-red tint, read
-- from the block's mean so the tint changes smoothly instead of cell by cell).
local cells: { number } = {}
local neighbours: { [number]: { number } } = {}
local blocks: { [number]: { number } } = {}
do
	local N = MakeSauce.GRID
	for gx = -N, N do
		for gy = -N, N do
			local i = MakeSauce.cellAt(gx, gy)
			if i and rs[i] <= SauceCover.DOUGH + 1e-9 then
				table.insert(cells, i)
				local list = {}
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local j = MakeSauce.cellAt(gx + d[1], gy + d[2])
					table.insert(list, if j and rs[j] <= SauceCover.DOUGH + 1e-9 then j else 0)
				end
				neighbours[i] = list
				local block = {}
				for dx = -2, 2 do
					for dy = -2, 2 do
						local j = MakeSauce.cellAt(gx + dx, gy + dy)
						if j then
							table.insert(block, j)
						end
					end
				end
				blocks[i] = block
			end
		end
	end
end
SauceCover.cells = cells

-- A cell's coverage credit, as MakeSauce.measure counts it.
function SauceCover.credit(t: number): number
	return math.min(1, math.max(t, 0) / MakeSauce.HALF)
end

export type Disc = {
	cell: number,
	kind: string,
	x: number,
	y: number,
	w: number,
	h: number,
	credit: number,
	deep: number,
	-- The widest radius this disc may be drawn at from its centre (EDGE_TOL onto the nearest
	-- bare cell), and whether it was narrowed to it.
	limit: number,
	clamped: boolean,
}

-- The widest radius a disc centred at (x, y) for material cell i may have: the distance to the
-- nearest cell of its 5x5 block drawn bare (under BARE credit), plus EDGE_TOL.
local function reachLimit(field: { number }, i: number, x: number, y: number): number
	local most = math.huge
	local half = CELL / 2
	for _, j in blocks[i] do
		if SauceCover.credit(field[j]) < SauceCover.BARE then
			local dx = math.max(math.abs(x - xs[j]) - half, 0)
			local dy = math.max(math.abs(y - ys[j]) - half, 0)
			most = math.min(most, math.sqrt(dx * dx + dy * dy) + SauceCover.EDGE_TOL * CELL)
		end
	end
	return most
end
SauceCover.reachLimit = reachLimit

local function round(scale: number): number
	return math.max(SauceCover.STEP, math.floor(scale / SauceCover.STEP + 0.5) * SauceCover.STEP)
end

-- The disc drawn for material cell i (nil: bare): its kind ("full", "edge" or "speck"), centre
-- and diameter (w = h, dough-local), its credit and its deep-red share (0..1, in 0.05 steps).
function SauceCover.disc(field: { number }, i: number): Disc?
	local c = SauceCover.credit(field[i])
	if c < SauceCover.BARE then
		return nil
	end
	local around = neighbours[i]
	local n = table.create(4, 0)
	local covered = 0
	for k, j in around do
		n[k] = if j == 0 then 0 else SauceCover.credit(field[j])
		if n[k] >= SauceCover.SOLID then
			covered += 1
		end
	end
	local mean = 0
	for _, j in blocks[i] do
		mean += field[j]
	end
	mean /= #blocks[i]
	local deep = math.clamp((mean / MakeSauce.EVEN - SauceCover.DEEP_FROM) / SauceCover.DEEP_SPAN, 0, 1)
	deep = math.floor(deep * 20 + 0.5) / 20
	local x, y = xs[i], ys[i]
	local kind, w, h
	if c >= SauceCover.SOLID and covered == 4 then
		kind, w, h = "full", SauceCover.FULL * CELL, SauceCover.FULL * CELL
	elseif covered > 0 and (n[1] ~= n[2] or n[3] ~= n[4]) then
		-- The way out of the patch: against the credit's rise across the four neighbours
		-- (+x, -x, +y, -y).
		kind = "edge"
		local gx, gy = n[1] - n[2], n[3] - n[4]
		local g = math.sqrt(gx * gx + gy * gy)
		local d = SauceCover.FULL * CELL
		local back = d / 2 - (c - 0.5) * CELL
		x += gx / g * back
		y += gy / g * back
		w, h = d, d
	else
		kind = "speck"
		local d = round(SauceCover.AREA * math.sqrt(c)) * CELL
		w, h = d, d
		local a = SauceCover.JITTER * CELL * 2
		x += (((i * 0.6180339887) % 1) - 0.5) * a
		y += (((i * 0.7548776662) % 1) - 0.5) * a
	end
	-- Never past the dough's edge (sauce off the dough shows only as the smear).
	local function inDough()
		local r = math.sqrt(x * x + y * y)
		local limit = SauceCover.DOUGH - w / 2
		if r > limit then
			x, y = x * limit / r, y * limit / r
		end
	end
	inDough()
	-- Never more than EDGE_TOL onto a cell drawn bare: a speck that would goes back to its
	-- cell's centre first; any disc still too wide is made narrower (it may then show less
	-- than its credit, never more).
	local most = reachLimit(field, i, x, y)
	if w / 2 > most and kind == "speck" then
		x, y = xs[i], ys[i]
		inDough()
		most = reachLimit(field, i, x, y)
	end
	local clamped = false
	if w / 2 > most then
		w, h = 2 * most, 2 * most
		clamped = true
	end
	return { cell = i, kind = kind, x = x, y = y, w = w, h = h, credit = c, deep = deep, limit = most, clamped = clamped }
end

-- Every disc of a field, in the fixed cell order.
function SauceCover.discs(field: { number }): { Disc }
	local out = {}
	for _, i in cells do
		local disc = SauceCover.disc(field, i)
		if disc then
			table.insert(out, disc)
		end
	end
	return out
end

-- Where a disc samples the material map: the top-left corner and size of its rectangle in the
-- map's 0..1 UV (the map's -SPAN..SPAN square, y down as on screen).
function SauceCover.uv(disc: Disc): (number, number, number, number)
	local span = 2 * SauceCover.SPAN
	return (disc.x - disc.w / 2 + SauceCover.SPAN) / span, (disc.y - disc.h / 2 + SauceCover.SPAN) / span, disc.w / span, disc.h / span
end

------------------------------------------------------------------------------------------
-- Spill on the board

-- Proposals: the off-dough sauce is grouped by SECTORS equal angles around the dough; a sector
-- with at least SPILL_MIN ladles past the dough's edge shows one smear at that sauce's mass
-- centre, along the edge, its width growing with the square root of the amount from SPILL_W[1]
-- (a trace) to SPILL_W[2] (SPILL_FULL ladles or more), dough-local (about 36 to 60 px at the HD
-- Make size, Astra's trial range).
SauceCover.SECTORS = 12
SauceCover.SPILL_MIN = 0.01
SauceCover.SPILL_FULL = 0.15
SauceCover.SPILL_W = { 0.105, 0.172 }

export type Spill = { x: number, y: number, along: number, width: number, mass: number }

-- One smear per sector of recorded spill: centre (dough-local), the edge's direction there
-- (radians, dough-local), width (dough-local) and the ladles it stands for. Nothing for a clean
-- board.
function SauceCover.spills(field: { number }): { Spill }
	local n = SauceCover.SECTORS
	local mass, sx, sy = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local area = CELL * CELL
	for i = 1, #rs do
		local t = field[i]
		if rs[i] > SauceCover.DOUGH + 1e-9 and t > 0 then
			local k = math.floor(((math.atan2(ys[i], xs[i]) / (2 * math.pi)) % 1) * n) % n + 1
			local m = t * area
			mass[k] += m
			sx[k] += xs[i] * m
			sy[k] += ys[i] * m
		end
	end
	local out = {}
	for k = 1, n do
		if mass[k] >= SauceCover.SPILL_MIN then
			local x, y = sx[k] / mass[k], sy[k] / mass[k]
			local share = math.clamp(math.sqrt(mass[k] / SauceCover.SPILL_FULL), 0, 1)
			table.insert(out, {
				x = x,
				y = y,
				along = math.atan2(y, x) + math.pi / 2,
				width = SauceCover.SPILL_W[1] + (SauceCover.SPILL_W[2] - SauceCover.SPILL_W[1]) * share,
				mass = mass[k],
			})
		end
	end
	return out
end

------------------------------------------------------------------------------------------
-- Cooking

-- How far the sauce has cooked (0 raw .. 1 cooked) after `seconds` in the oven: the food's own
-- state (Config.Oven: raw up to rawUntil, cooked from cookedFrom), never the ticket's doneness.
function SauceCover.cooked(seconds: number?): number
	if not seconds then
		return 0
	end
	local cfg = Config.Oven
	return math.clamp((seconds - cfg.rawUntil) / (cfg.cookedFrom - cfg.rawUntil), 0, 1)
end

-- How far toward scorched (0 .. 1): from the end of the cooked span (scorchFrom) to burntAt.
function SauceCover.scorched(seconds: number?): number
	if not seconds then
		return 0
	end
	local cfg = Config.Oven
	return math.clamp((seconds - cfg.scorchFrom) / (cfg.burntAt - cfg.scorchFrom), 0, 1)
end

return SauceCover

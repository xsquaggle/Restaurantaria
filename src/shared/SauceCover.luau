--!strict
-- What the sauce looks like, read from the same thickness field the grade reads (MakeSauce):
-- pure functions shared by the client renderer (MakeLayers) and the tests. Presentation only:
-- nothing here changes the field, the pours or the grade.
--
-- Astra r14 (art-integration.md): one thick marinara material drawn through the coverage the
-- field already holds, never a translucent stamp. Each field cell on the dough that carries
-- sauce shows a disc of the material map, sampled at the disc's own dough-local place, so
-- neighbouring discs show one continuous material. The disc's area is the cell's coverage
-- credit (MakeSauce.measure: min(1, thickness / half an even layer)), so a thin trace shows as
-- sparse specks with the board or dough between them and a covered patch reads solid: amount is
-- never drawn as transparency. A fully credited cell inside a covered patch is drawn a little
-- larger (FULL) so the discs close up with no gaps; at a boundary every disc keeps the area of
-- its credit (AREA), which keeps the drawn edge on the scored edge (within a third of a cell).
--
-- Material span (decided in slice 2, recorded in the hand-off): the 1024 px material maps cover
-- the dough-local square -1..1 (radius 1.0) in every view; the dough's edge is 0.95. Sauce off
-- the dough (radius past 0.95, out to the field's 1.2) is not drawn as material: the board shows
-- it only through the spill smear (sauce_board_spill_v2), placed from the recorded spill.

local Config = require(script.Parent.Config)
local MakeSauce = require(script.Parent.MakeSauce)

local SauceCover = {}

local CELL = MakeSauce.CELL
local xs, ys, rs = MakeSauce.xs, MakeSauce.ys, MakeSauce.rs

SauceCover.SPAN = 1.0 -- the material maps' half width, dough-local
SauceCover.DOUGH = 0.95 -- cells out to here are drawn as material
-- Proposals (looks, not grading): a cell under BARE credit is drawn bare; disc diameters as
-- multiples of the cell: AREA keeps a disc's area equal to its credit (2 / sqrt(pi)), FULL closes
-- a fully covered patch (at least sqrt 2, so four neighbours leave no hole); the deep-red tint of
-- a thick layer starts at DEEP_FROM even layers and is full DEEP_SPAN later.
SauceCover.BARE = 0.03
SauceCover.AREA = 2 / math.sqrt(math.pi)
SauceCover.FULL = 1.5
SauceCover.DEEP_FROM = 1.3
SauceCover.DEEP_SPAN = 1.7
-- Diameters are rounded to this share of a cell (fewer resizes).
SauceCover.STEP = 0.05
-- A boundary disc sits off its cell centre by a fixed amount up to JITTER cells each way (from
-- the cell's index), so a thin edge does not print as a regular dot grid; it still samples the
-- map at its own drawn place.
SauceCover.JITTER = 0.35

-- The material cells (drawn on the dough), each one's four grid neighbours (0 past the field's
-- extent or off the dough, which count as bare) and its 3x3 block (for the deep-red tint, read
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
				for dx = -1, 1 do
					for dy = -1, 1 do
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

export type Disc = { cell: number, x: number, y: number, d: number, credit: number, deep: number }

-- The disc drawn for material cell i (nil: bare): centre (dough-local), diameter d (dough-local),
-- its credit and its deep-red share (0..1, in 0.05 steps).
function SauceCover.disc(field: { number }, i: number): Disc?
	local c = SauceCover.credit(field[i])
	if c < SauceCover.BARE then
		return nil
	end
	local scale = SauceCover.AREA * math.sqrt(c)
	if c >= 1 then
		local inside = true
		for _, j in neighbours[i] do
			if j == 0 or SauceCover.credit(field[j]) < 1 then
				inside = false
				break
			end
		end
		if inside then
			scale = SauceCover.FULL
		end
	end
	scale = math.max(SauceCover.STEP, math.floor(scale / SauceCover.STEP + 0.5) * SauceCover.STEP)
	local mean = 0
	for _, j in blocks[i] do
		mean += field[j]
	end
	mean /= #blocks[i]
	local deep = math.clamp((mean / MakeSauce.EVEN - SauceCover.DEEP_FROM) / SauceCover.DEEP_SPAN, 0, 1)
	deep = math.floor(deep * 20 + 0.5) / 20
	local x, y = xs[i], ys[i]
	if scale < SauceCover.FULL then
		local a = SauceCover.JITTER * CELL * 2
		x += (((i * 0.6180339887) % 1) - 0.5) * a
		y += (((i * 0.7548776662) % 1) - 0.5) * a
		-- Never past the material's span.
		local r = math.sqrt(x * x + y * y)
		local limit = SauceCover.SPAN - scale * CELL / 2
		if r > limit then
			x, y = x * limit / r, y * limit / r
		end
	end
	return { cell = i, x = x, y = y, d = scale * CELL, credit = c, deep = deep }
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

-- Where a disc samples the material map: the top-left corner and size of its square in the
-- map's 0..1 UV (the map's -SPAN..SPAN square, y down as on screen).
function SauceCover.uv(disc: Disc): (number, number, number)
	local span = 2 * SauceCover.SPAN
	return (disc.x - disc.d / 2 + SauceCover.SPAN) / span, (disc.y - disc.d / 2 + SauceCover.SPAN) / span, disc.d / span
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

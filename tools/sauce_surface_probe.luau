-- Sauce surface diagnosis (slice 7b-2, Astra r20 R20-08: "scalloped edges, a small polygonal
-- centre gap and broad stripe-like highlights"). Not a check: it measures the drawn sauce mask
-- (SauceCover.discs, as MakeLayers draws them, pinhole guard included) against the graded field,
-- rasterized at a given screen scale, and prints what it finds. Run offline:
--   python3 -I tests/offline/run.py tools/sauce_surface_probe.luau
-- Measures, inside the drawn material area (dough radius 0.95):
--  * invented: painted pixels more than EDGE_TOL inside a cell the field holds bare (a mask bug);
--  * holes: unpainted pixels inside a covered cell whose eight neighbours are covered (a bug);
--  * edge offset: pixels where the disc mask and a smooth edge (the field's credit interpolated
--    between cell centres, cut at SOLID) disagree, divided by the smooth edge's length in pixels:
--    the mean width of the scallops/steps along the edge;
--  * bare islands: groups of edible cells under BARE credit with no bare path to the crust (a
--    gap inside the sauce), in the field and in the drawing.

local Shared = game:GetService("ReplicatedStorage").Shared
local MakeSauce = require(Shared.MakeSauce)
local SauceCover = require(Shared.SauceCover)

local CELL = MakeSauce.CELL
local xs, ys, rs = MakeSauce.xs, MakeSauce.ys, MakeSauce.rs
local N = MakeSauce.GRID

local function P(x: number, y: number)
	return { x = x, y = y }
end
local function circle(cx: number, cy: number, r: number, n: number): { any }
	local pts = {}
	for k = 0, n do
		local a = k / n * 2 * math.pi
		table.insert(pts, P(cx + r * math.cos(a), cy + r * math.sin(a)))
	end
	return pts
end
local function line(ax: number, ay: number, bx: number, by: number, n: number): { any }
	local pts = {}
	for k = 0, n do
		table.insert(pts, P(ax + (bx - ax) * k / n, ay + (by - ay) * k / n))
	end
	return pts
end

-- Astra's phone run (r20 LIVE-RUNTIME-NOTES), converted at 111 px per dough unit around her
-- circle centre: pours at (0, 0.36), (-0.32, -0.18), (0.32, -0.18); circles 0.25 / 0.42 / 0.59.
local CASES = {
	{ name = "Astra phone pattern (3 pours, 3 circles)", actions = {
		{ kind = "pour", x = 0, y = 0.36 }, { kind = "pour", x = -0.32, y = -0.18 }, { kind = "pour", x = 0.32, y = -0.18 },
		{ kind = "spread", points = circle(0, 0, 0.25, 24) }, { kind = "spread", points = circle(0, 0, 0.42, 36) }, { kind = "spread", points = circle(0, 0, 0.59, 48) },
	} },
	{ name = "even (3 pours apart, cross spreads)", actions = {
		{ kind = "pour", x = 0.4, y = 0 }, { kind = "pour", x = -0.2, y = 0.35 }, { kind = "pour", x = -0.2, y = -0.35 },
		{ kind = "spread", points = line(-0.7, 0, 0.7, 0, 30) }, { kind = "spread", points = line(0, -0.7, 0, 0.7, 30) },
		{ kind = "spread", points = line(-0.5, -0.5, 0.5, 0.5, 30) }, { kind = "spread", points = line(-0.5, 0.5, 0.5, -0.5, 30) },
		{ kind = "spread", points = circle(0, 0, 0.6, 48) },
	} },
	{ name = "sparse (1 pour, one short spread)", actions = {
		{ kind = "pour", x = 0, y = 0 }, { kind = "spread", points = line(-0.3, 0, 0.3, 0, 12) },
	} },
	{ name = "crust-heavy (3 pours near the rim)", actions = {
		{ kind = "pour", x = 0.8, y = 0 }, { kind = "pour", x = -0.4, y = 0.69 }, { kind = "pour", x = -0.4, y = -0.69 },
		{ kind = "spread", points = circle(0, 0, 0.8, 48) },
	} },
	{ name = "spill (pours at the rim, spread outward)", actions = {
		{ kind = "pour", x = 0.3, y = 0 }, { kind = "pour", x = -0.2, y = 0.3 }, { kind = "pour", x = 0.9, y = 0.1 },
		{ kind = "spread", points = line(0, 0, 1.1, 0.1, 24) }, { kind = "spread", points = circle(0, 0, 0.45, 36) },
	} },
}

local function credit(field: { number }, i: number?): number
	return if i then SauceCover.credit(field[i]) else 0
end
local function cellOf(x: number, y: number): number?
	return MakeSauce.cellAt(math.floor(x / CELL + 0.5), math.floor(y / CELL + 0.5))
end
-- Bilinear credit between cell centres.
local function smooth(field: { number }, x: number, y: number): number
	local gx, gy = x / CELL, y / CELL
	local x0, y0 = math.floor(gx), math.floor(gy)
	local fx, fy = gx - x0, gy - y0
	local function c(a: number, b: number): number
		local i = MakeSauce.cellAt(a, b)
		if not i or rs[i] > SauceCover.DOUGH + 1e-9 then
			return 0
		end
		return credit(field, i)
	end
	return c(x0, y0) * (1 - fx) * (1 - fy) + c(x0 + 1, y0) * fx * (1 - fy) + c(x0, y0 + 1) * (1 - fx) * fy + c(x0 + 1, y0 + 1) * fx * fy
end

-- Bare islands among edible cells (credit under BARE, or unpainted for the drawing): groups not
-- joined to the outside of the edible disc through 4-neighbour bare cells.
local function islands(isBare: (number) -> boolean): (number, number)
	local seen = {}
	local count, cells = 0, 0
	for gx = -N, N do
		for gy = -N, N do
			local i = MakeSauce.cellAt(gx, gy)
			if i and rs[i] <= 0.84 and isBare(i) and not seen[i] then
				local stack, group, open = { { gx, gy } }, 0, false
				seen[i] = true
				while #stack > 0 do
					local c = table.remove(stack)
					group += 1
					for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local j = MakeSauce.cellAt(c[1] + d[1], c[2] + d[2])
						if not j or rs[j] > 0.84 then
							open = true
						elseif isBare(j) and not seen[j] then
							seen[j] = true
							table.insert(stack, { c[1] + d[1], c[2] + d[2] })
						end
					end
				end
				if not open then
					count += 1
					cells += group
				end
			end
		end
	end
	return count, cells
end

local function probe(name: string, field: { number }, pxPerUnit: number, label: string)
	local discs = SauceCover.discs(field)
	-- MakeLayers' pinhole guard on full discs (CLOSE_PX 1.5 along the shorter axis; round view).
	local CLOSE_PX = 1.5
	for k, d in discs do
		if d.kind == "full" then
			local least = math.min(CELL * math.sqrt(2) + 2 * CLOSE_PX / pxPerUnit, 2 * d.limit)
			if d.w < least then
				d = table.clone(d)
				d.w, d.h = least, least
				discs[k] = d
			end
		end
	end
	-- Bucket the discs for lookup.
	local buckets = {}
	for _, d in discs do
		local r = d.w / 2
		for bx = math.floor((d.x - r) / CELL), math.floor((d.x + r) / CELL) do
			for by = math.floor((d.y - r) / CELL), math.floor((d.y + r) / CELL) do
				local key = bx * 1000 + by
				buckets[key] = buckets[key] or {}
				table.insert(buckets[key], d)
			end
		end
	end
	local function painted(x: number, y: number): boolean
		local list = buckets[math.floor(x / CELL) * 1000 + math.floor(y / CELL)]
		if list then
			for _, d in list do
				local r = d.w / 2
				if (x - d.x) ^ 2 + (y - d.y) ^ 2 <= r * r then
					return true
				end
			end
		end
		return false
	end
	local step = 1 / pxPerUnit
	local half = SauceCover.DOUGH
	local invented, holes, disagree, edgePx, paintedPx = 0, 0, 0, 0, 0
	local paintedCell = {}
	local smoothRow: { [number]: boolean } = {}
	local y = -half
	local prevRow: { boolean }? = nil
	while y <= half do
		local row: { boolean } = {}
		local x = -half
		local col = 0
		while x <= half do
			col += 1
			if x * x + y * y <= half * half then
				local p = painted(x, y)
				local s = smooth(field, x, y) >= SauceCover.SOLID
				row[col] = s
				local i = cellOf(x, y)
				local c = credit(field, i)
				if p then
					paintedPx += 1
					if i then
						paintedCell[i] = true
					end
				end
				if p and c < SauceCover.BARE and i then
					-- How far inside the bare cell (from its nearest edge).
					local inside = CELL / 2 - math.max(math.abs(x - xs[i]), math.abs(y - ys[i]))
					if inside > SauceCover.EDGE_TOL * CELL + step then
						invented += 1
					end
				end
				if not p and i and c >= SauceCover.SOLID then
					local all = true
					local gx, gy = math.floor(xs[i] / CELL + 0.5), math.floor(ys[i] / CELL + 0.5)
					for dx = -1, 1 do
						for dy = -1, 1 do
							local j = MakeSauce.cellAt(gx + dx, gy + dy)
							if not j or credit(field, j) < SauceCover.SOLID or rs[j] > SauceCover.DOUGH then
								all = false
							end
						end
					end
					if all then
						holes += 1
					end
				end
				if p ~= s then
					disagree += 1
				end
				-- Smooth edge length: a pixel whose left or upper neighbour differs.
				if (row[col - 1] ~= nil and row[col - 1] ~= s) or (prevRow and prevRow[col] ~= nil and prevRow[col] ~= s) then
					edgePx += 1
				end
			end
			x += step
		end
		prevRow = row
		y += step
	end
	local coverage = MakeSauce.measure(field)
	local fIsl, fCells = islands(function(i)
		return credit(field, i) < SauceCover.BARE
	end)
	local fSolidIsl, fSolidCells = islands(function(i)
		return credit(field, i) < SauceCover.SOLID
	end)
	print(string.format("  | %s | %s | %.3f | %d | %d | %d | %.2f px | %d (%d cells) | %d (%d cells) |", name, label, coverage, #discs, invented, holes,
		if edgePx > 0 then disagree / edgePx else 0, fIsl, fCells, fSolidIsl, fSolidCells))
end

print("  | Case | Scale | Coverage (graded) | Discs | Invented px | Hole px | Mean edge offset | Bare islands in the field (< BARE) | Thin islands (< SOLID, drawn as specks or bare) |")
print("  |---|---|---|---|---|---|---|---|---|")
for _, c in CASES do
	local field = MakeSauce.replayUncached({ actions = c.actions })
	for _, scale in { { 330.5, "HD Make (F 661)" }, { 100, "phone Make (F 200, measured live)" } } do
		probe(c.name, field, scale[1], scale[2])
	end
end
return "sauce surface probe done"

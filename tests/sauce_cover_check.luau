-- Checks for how the sauce is drawn (SauceCover, slice 2, Astra r14): presentation only. For
-- every record of the comparison set the grade, mass, pours and coverage are the same before and
-- after the renderer reads the field, the field itself is unchanged, and the drawn tiles keep the
-- material contract: only on the dough, inside the material's -1..1 span, sampled at their own
-- place, no tile on a bare cell, an edge band as deep as its credit, a speck's area equal to its
-- credit, a covered patch closed up. The board smear appears only for recorded spill, at that spill. Cooking follows the food's
-- own state. The comparison records here are the ones the Studio A/B captures draw
-- (tools/food_ab.luau builds the same actions). Run offline with tests/offline/run.py, or in
-- Studio Edit after a sync. Arithmetic only: how it looks is checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local MakeSauce = require(Shared.MakeSauce)
local SauceCover = require(Shared.SauceCover)

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
local function near(name: string, got: number?, want: number, tol: number?)
	if type(got) == "number" and math.abs(got - want) <= (tol or 1e-6) then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %.6f (+-%g)", name, tostring(got), want, tol or 1e-6))
	end
end
local function P(x: number, y: number)
	return { x = x, y = y }
end
local function circle(r: number): { any }
	local out = {}
	for i = 0, 40 do
		local a = 2 * math.pi * i / 40
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function arc(r: number, from: number, to: number): { any }
	local out = {}
	for i = 0, 32 do
		local a = math.rad(from + (to - from) * i / 32)
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function slice(list: { any }, a: number, b: number): { any }
	local out = {}
	for i = a, b do
		table.insert(out, list[i])
	end
	return out
end
local function sauceOf(pours: { any }, spreads: { { any } }): any
	local actions = {}
	for _, p in pours do
		table.insert(actions, { kind = "pour", x = p.x, y = p.y })
	end
	for _, s in spreads do
		table.insert(actions, { kind = "spread", points = s })
	end
	return { actions = actions }
end
local function mass(field: { number }): number
	local t = 0
	for _, v in field do
		t += v
	end
	return t * MakeSauce.CELL * MakeSauce.CELL
end
local function fingerprint(field: { number }): string
	local h = 0
	for i, v in field do
		h = (h * 31 + math.floor(v * 1e9) + i) % 2147483647
	end
	return tostring(h)
end

-- The proposals these checks assume.
check("proposal: span", SauceCover.SPAN, 1.0)
check("proposal: dough edge", SauceCover.DOUGH, 0.95)
check("proposal: bare", SauceCover.BARE, 0.03)
check("proposal: solid", SauceCover.SOLID, 0.5)
near("proposal: area disc", SauceCover.AREA, 2 / math.sqrt(math.pi), 1e-12)
check("proposal: full disc", SauceCover.FULL, 1.6)
check("proposal: full disc closes a patch (>= sqrt 2)", SauceCover.FULL >= math.sqrt(2), true)
check("proposal: edge band inset", SauceCover.INSET, 0.1)
check("proposal: spill sectors / min / full", string.format("%d/%g/%g", SauceCover.SECTORS, SauceCover.SPILL_MIN, SauceCover.SPILL_FULL), "12/0.01/0.15")
check("default renderer", Config.FoodArt.sauce, "material")
check("default cheese family", Config.FoodArt.cheese, "v2")

-- 1. The material cells: every field cell within the dough's edge (counted independently: grid
-- points (gx, gy) with gx^2 + gy^2 <= 19^2 = 361, since 0.95 / 0.05 = 19).
do
	local n = 0
	for gx = -19, 19 do
		for gy = -19, 19 do
			if gx * gx + gy * gy <= 361 then
				n += 1
			end
		end
	end
	check("material cells", #SauceCover.cells, n)
end

-- 2. The comparison set (Astra r14): the same actions the Studio A/B draws.
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local wide = circle(1.1)
local even = sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) })
local records = {
	{ "small pour", sauceOf({ P(0.2, -0.1) }, {}) },
	{ "thin trace", sauceOf({ P(-0.5, 0.1) }, { { P(-0.6, 0.1), P(0.75, 0.1) }, { P(0.75, 0.15), P(-0.2, 0.15) } }) },
	{ "half spread", sauceOf({ P(0.3, 0), P(0.45, 0.4), P(0.45, -0.4) }, { arc(0.2, -80, 80), arc(0.4, -80, 80), arc(0.6, -80, 80), arc(0.75, -80, 80) }) },
	{ "even adequate", even },
	{ "excess mound", sauceOf({ P(0, 0), P(0.06, 0), P(-0.06, 0), P(0, 0.06), P(0, -0.06), P(0.04, 0.04) }, { { P(-0.15, 0), P(0.15, 0) } }) },
	{ "rim spill", sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7), circle(0.88) }) },
	{ "board spill", sauceOf(tri, { circle(0.3), circle(0.6), circle(0.9), slice(wide, 1, 21), slice(wide, 21, 41) }) },
	{ "undo (even, last spread taken back)", sauceOf(tri, { circle(0.3), circle(0.5) }) },
	{ "unmoved dollops", sauceOf(tri, {}) },
}
local area = MakeSauce.CELL * MakeSauce.CELL
table.insert(report, "record                               pours  mass   coverage  grade  tiles (full/edge/speck)  drawn/edible  deepest  spills (ladles)")
for _, rec in records do
	local name, sauce = rec[1], rec[2]
	local before = MakeSauce.grade(sauce)
	local field = MakeSauce.replay(sauce)
	local print0 = fingerprint(field)
	local mass0 = mass(field)
	local discs = SauceCover.discs(field)
	local spills = SauceCover.spills(field)
	-- The renderer read the field and changed nothing the grade reads.
	check(name .. ": field unchanged", fingerprint(field), print0)
	near(name .. ": mass unchanged", mass(field), mass0, 1e-12)
	local after = MakeSauce.grade(sauce)
	check(name .. ": grade unchanged", after.score, before.score)
	near(name .. ": coverage unchanged", after.detail.coverage, before.detail.coverage, 0)
	check(name .. ": pours unchanged", after.detail.pours, before.detail.pours)
	check(name .. ": same discs again", #SauceCover.discs(field), #discs)
	-- Every disc keeps the contract.
	local drawn, offDough, outside, badUv, onBare, badArea, badKind, maxDeep = 0, 0, 0, 0, 0, 0, 0, 0
	local kinds = { full = 0, edge = 0, speck = 0 }
	for _, d in discs do
		local r = math.sqrt(d.x * d.x + d.y * d.y)
		local home = math.sqrt((d.x - MakeSauce.xs[d.cell]) ^ 2 + (d.y - MakeSauce.ys[d.cell]) ^ 2)
		if home > (0.5 + SauceCover.INSET) * MakeSauce.CELL + 1e-9 then
			offDough += 1
		end
		if MakeSauce.rs[d.cell] > SauceCover.DOUGH + 1e-9 then
			offDough += 1
		end
		if r + math.sqrt(d.w * d.w + d.h * d.h) / 2 > SauceCover.SPAN + 1e-9 then
			outside += 1
		end
		local u, v, uw, vh = SauceCover.uv(d)
		if u < -1e-9 or v < -1e-9 or u + uw > 1 + 1e-9 or v + vh > 1 + 1e-9
			or math.abs(u + uw / 2 - (d.x + 1) / 2) > 1e-9 or math.abs(v + vh / 2 - (d.y + 1) / 2) > 1e-9
			or math.abs(uw - d.w / 2) > 1e-9 or math.abs(vh - d.h / 2) > 1e-9 then
			badUv += 1
		end
		if SauceCover.credit(field[d.cell]) < SauceCover.BARE then
			onBare += 1
		end
		kinds[d.kind] += 1
		local area1 = MakeSauce.CELL * MakeSauce.CELL
		if d.kind == "full" then
			-- A covered cell inside a covered patch.
			if d.credit < SauceCover.SOLID or math.abs(d.w - SauceCover.FULL * MakeSauce.CELL) > 1e-9 or d.w ~= d.h then
				badKind += 1
			end
			drawn += area1
		elseif d.kind == "edge" then
			-- A band along the patch: FULL cells long, its depth past the patch side the credit.
			local long, depth = math.max(d.w, d.h) / MakeSauce.CELL, math.min(d.w, d.h) / MakeSauce.CELL
			if math.abs(long - SauceCover.FULL) > 1e-9 then
				badKind += 1
			end
			if math.abs(depth - (d.credit + SauceCover.INSET)) > SauceCover.STEP / 2 + 1e-9 then
				badArea += 1
			end
			drawn += d.credit * area1
		else
			-- A speck: its area is its credit (to the rounding).
			local scale = d.w / MakeSauce.CELL
			local want = SauceCover.AREA * math.sqrt(d.credit)
			if d.w ~= d.h or (math.abs(scale - want) > SauceCover.STEP / 2 + 1e-9 and scale > SauceCover.STEP + 1e-9) then
				badArea += 1
			end
			drawn += math.pi * (scale / 2) ^ 2 * area1
		end
		maxDeep = math.max(maxDeep, d.deep)
	end
	check(name .. ": every disc on a dough cell, near its centre", offDough, 0)
	check(name .. ": no disc past the material span", outside, 0)
	check(name .. ": every disc samples its own place", badUv, 0)
	check(name .. ": no disc on a bare cell", onBare, 0)
	check(name .. ": edge depth and speck area = credit", badArea, 0)
	check(name .. ": full discs and edge bands keep their sizes", badKind, 0)
	-- Every material cell with credit is drawn, and only those.
	local credited = 0
	for _, i in SauceCover.cells do
		if SauceCover.credit(field[i]) >= SauceCover.BARE then
			credited += 1
		end
	end
	check(name .. ": one disc per credited cell", #discs, credited)
	-- The smear: only for sauce past the dough's edge, at that sauce.
	local off = 0
	for i = 1, MakeSauce.COUNT do
		if MakeSauce.rs[i] > SauceCover.DOUGH + 1e-9 then
			off += field[i] * area
		end
	end
	local shown = 0
	for _, sp in spills do
		shown += sp.mass
		check(name .. ": smear past the dough's edge", math.sqrt(sp.x * sp.x + sp.y * sp.y) > SauceCover.DOUGH, true)
		check(name .. ": smear width in range", sp.width >= SauceCover.SPILL_W[1] - 1e-9 and sp.width <= SauceCover.SPILL_W[2] + 1e-9, true)
	end
	if off < SauceCover.SPILL_MIN then
		check(name .. ": clean board, no smear", #spills, 0)
	end
	check(name .. ": smear never stands for more than the spill", shown <= off + 1e-9, true)
	table.insert(report, string.format("%-36s %5d  %.3f  %.4f    %3d    %4d (%d/%d/%d)  %.3f   %.2f     %d (%.3f of %.3f off)", name, before.detail.pours, mass0, before.detail.coverage, before.score, #discs, kinds.full, kinds.edge, kinds.speck, drawn / (MakeSauce.EDIBLE_CELLS * area), maxDeep, #spills, shown, off))
	if name == "excess mound" then
		check("excess mound: thick sauce drawn deeper", maxDeep > 0, true)
	elseif name == "even adequate" then
		check("even adequate: clean board, no smear", #spills, 0)
	elseif name == "board spill" then
		check("board spill: smeared", #spills > 0, true)
	end
end

-- 3. A covered patch closes up: in the even record, every cell at SOLID credit or more whose
-- four neighbours are too is drawn FULL (no hole between four discs), and only those.
do
	local field = MakeSauce.replay(even)
	local full, closed = 0, 0
	for _, d in SauceCover.discs(field) do
		if d.kind == "full" then
			closed += 1
		end
		if d.credit >= SauceCover.SOLID then
			full += 1
		end
	end
	check("even: some patch closed up", closed > 0, true)
	check("even: closed discs are covered cells", closed <= full, true)
end

-- 4. Undo: the before/after pair are two records; the renderer draws each from its own field.
do
	local after = MakeSauce.replay(records[8][2])
	local before = MakeSauce.replay(even)
	check("undo: fewer covered cells after taking the spread back", #SauceCover.discs(after) ~= #SauceCover.discs(before), true)
end

-- 5. Cooking follows the food's own state (Config.Oven: raw to 8 s, cooked from 12 s, scorching
-- from 32 s, burnt at 36 s), never the ticket.
check("cooked: not baked", SauceCover.cooked(nil), 0)
check("cooked: 8 s raw", SauceCover.cooked(8), 0)
near("cooked: 10 s half", SauceCover.cooked(10), 0.5, 1e-12)
check("cooked: 12 s cooked", SauceCover.cooked(12), 1)
check("cooked: 30 s cooked", SauceCover.cooked(30), 1)
check("scorched: 32 s none", SauceCover.scorched(32), 0)
near("scorched: 34 s half", SauceCover.scorched(34), 0.5, 1e-12)
check("scorched: 36 s full", SauceCover.scorched(36), 1)
do
	local last, monotonic = -1, true
	for s = 0, 40, 0.25 do
		local k = SauceCover.cooked(s)
		if k < last then
			monotonic = false
		end
		last = k
	end
	check("cooked: monotonic", monotonic, true)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("sauce cover checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

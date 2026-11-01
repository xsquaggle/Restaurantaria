-- Checks for the continuous sauce surface (slice 8a, Astra r21: one thick opaque material over
-- the sauced area, not a disc per cell): presentation only. For every record of the slice 2
-- comparison set the grade and the field are unchanged after the surface is built; the surface
-- never reaches past the dough's edge; it draws about the area the grade credits (surface plus
-- the specks of thin sauce beside it); a bare hole stays bare; thin sauce stays specks, never a
-- wash; the specks sit off the surface; a small pizza's coarser grid keeps the shape; a thick
-- layer is keyed deep red. Arithmetic only: how it looks is checked in Studio and by Lawson.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local MakeSauce = require(Shared.MakeSauce)
local SauceCover = require(Shared.SauceCover)
local SurfaceTiles = require(Shared.SurfaceTiles)

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
local function fingerprint(field: { number }): string
	local h = 0
	for i, v in field do
		h = (h * 31 + math.floor(v * 1e9) + i) % 2147483647
	end
	return tostring(h)
end
-- Points of the drawn surface: a 5x5 sample of every tile, kept where the tile draws.
local function insidePoints(tiles: { SurfaceTiles.Tile }): { { number } }
	local out = {}
	for _, t in tiles do
		for sx = 0, 4 do
			for sy = 0, 4 do
				local x = t.x0 + (t.x1 - t.x0) * sx / 4
				local y = t.y0 + (t.y1 - t.y0) * sy / 4
				local inside = true
				if t.kind == "cut" then
					local cx, cy = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2
					inside = (t.nx :: number) * (x - cx) + (t.ny :: number) * (y - cy) <= (t.d :: number) + 1e-9
				end
				if inside then
					table.insert(out, { x, y })
				end
			end
		end
	end
	return out
end
local function covers(tiles: { SurfaceTiles.Tile }, x: number, y: number): boolean
	for _, t in tiles do
		if x >= t.x0 and x <= t.x1 and y >= t.y0 and y <= t.y1 then
			if t.kind == "full" then
				return true
			end
			local cx, cy = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2
			if (t.nx :: number) * (x - cx) + (t.ny :: number) * (y - cy) <= (t.d :: number) then
				return true
			end
		end
	end
	return false
end
local CELL = MakeSauce.CELL
-- The area the grade credits on the dough: each material cell's credit times its area.
local function credited(field: { number }): number
	local a = 0
	for _, i in SauceCover.cells do
		a += SauceCover.credit(field[i]) * CELL * CELL
	end
	return a
end
local function speckArea(specks: { SauceCover.Disc }): number
	local a = 0
	for _, d in specks do
		a += math.pi * d.w * d.w / 4
	end
	return a
end

check("default renderer", Config.FoodArt.sauce, "surface")
check("surface level: SOLID", SauceCover.SOLID, 0.5)

-- 1. The slice 2 comparison set (tests/sauce_cover_check.luau has the same records).
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
-- Drawn against credited, for the records with a real layer (the small pour and the thin trace
-- are mostly specks and partial credit, reported only). The surface is opaque: a cell at half
-- credit or more is drawn whole, so sauce thinned along the rim draws a little more than it is
-- credited (rim spill, about 8.5%); never transparency for amount (Astra r14).
local GATED = { ["half spread"] = true, ["even adequate"] = true, ["rim spill"] = true, ["board spill"] = true, ["undo (even, last spread taken back)"] = true, ["unmoved dollops"] = true, ["excess mound"] = true }
local DRAWN_TOL = 0.1
table.insert(report, "record                               coverage  grade  credited  surface + specks = drawn   drawn/credited  tiles (stride 1 / 2)  specks  deepest key")
for _, rec in records do
	local name, sauce = rec[1], rec[2]
	local before = MakeSauce.grade(sauce)
	local field = MakeSauce.replay(sauce)
	local print0 = fingerprint(field)
	local tiles = SauceCover.surface(field)
	local tiles2 = SauceCover.surface(field, 2)
	local specks = SauceCover.specks(field)
	check(name .. ": field unchanged", fingerprint(field), print0)
	check(name .. ": grade unchanged", MakeSauce.grade(sauce).score, before.score)
	-- Never past the dough's edge (sauce off the dough shows only as the smear).
	local worst = 0
	for _, list in { tiles, tiles2 } do
		for _, p in insidePoints(list) do
			worst = math.max(worst, math.sqrt(p[1] * p[1] + p[2] * p[2]) - SauceCover.DOUGH)
		end
	end
	check(name .. ": nothing drawn past the dough's edge", worst <= 1e-9, true)
	-- The specks sit off the surface: no speck's centre is under it.
	local under = 0
	for _, d in specks do
		if covers(tiles, d.x, d.y) then
			under += 1
		end
	end
	check(name .. ": no speck under the surface", under, 0)
	local surf = SurfaceTiles.area(tiles)
	local surf2 = SurfaceTiles.area(tiles2)
	local sp = speckArea(specks)
	local cred = credited(field)
	local ratio = if cred > 0 then (surf + sp) / cred else 0
	if GATED[name] then
		check(string.format("%s: drawn within %d%% of credited", name, DRAWN_TOL * 100), math.abs(ratio - 1) <= DRAWN_TOL, true)
		check(name .. ": every second node, the surface within 8% of its fine drawing", math.abs(surf2 - surf) / surf <= 0.08, true)
	end
	local deepest = 0
	for _, t in tiles do
		deepest = math.max(deepest, t.key or 0)
	end
	table.insert(report, string.format("%-36s %8.3f  %5d  %8.3f  %7.3f + %6.3f = %7.3f  %14.3f  %9d / %-9d  %6d  %11.2f", name, before.detail.coverage, before.score, cred, surf, sp, surf + sp, ratio, #tiles, #tiles2, #specks, deepest))
	if name == "excess mound" then
		check("excess mound: the mound is keyed deep red", deepest > 0, true)
	end
	-- The keys are the discs' deep shares (one rule): every key is the mean of corner cells'.
	local discDeep = 0
	for _, d in SauceCover.discs(field) do
		discDeep = math.max(discDeep, d.deep)
	end
	check(name .. ": no key deeper than the deepest disc", deepest <= discDeep + 1e-9, true)
end

-- 2. A bare hole stays bare: an even layer out to 0.8 with a hole of radius 0.15 at (0.3, 0).
do
	local field = MakeSauce.empty()
	for i = 1, MakeSauce.COUNT do
		local x, y = MakeSauce.xs[i], MakeSauce.ys[i]
		if MakeSauce.rs[i] <= 0.8 and (x - 0.3) ^ 2 + y ^ 2 > 0.15 ^ 2 then
			field[i] = MakeSauce.EVEN
		end
	end
	local tiles = SauceCover.surface(field)
	check("hole: its middle is bare", covers(tiles, 0.3, 0), false)
	check("hole: the layer opposite is drawn", covers(tiles, -0.3, 0), true)
	check("hole: nothing drawn far past the layer's edge", covers(tiles, 0.86, 0), false)
	-- The drawn hole against the true one (pi 0.15^2), within 25% (the grid is 0.05).
	local bare = 0
	local step = 0.005
	for x = 0.1, 0.5, step do
		for y = -0.2, 0.2, step do
			if not covers(tiles, x, y) then
				bare += step * step
			end
		end
	end
	local truth = math.pi * 0.15 ^ 2
	check("hole: drawn bare area within 25% of the hole", math.abs(bare - truth) / truth <= 0.25, true)
	table.insert(report, string.format("hole of radius 0.15: drawn bare %.4f against %.4f", bare, truth))
end

-- 3. Thin sauce stays specks, never a wash: a layer at 0.3 credit everywhere out to 0.6.
do
	local field = MakeSauce.empty()
	for i = 1, MakeSauce.COUNT do
		if MakeSauce.rs[i] <= 0.6 then
			field[i] = 0.3 * MakeSauce.HALF
		end
	end
	check("thin layer: no surface", #SauceCover.surface(field), 0)
	check("thin layer: shown as specks", #SauceCover.specks(field) > 0, true)
end

-- 4. An empty field draws nothing.
check("empty: no surface", #SauceCover.surface(MakeSauce.empty()), 0)
check("empty: no specks", #SauceCover.specks(MakeSauce.empty()), 0)

for _, l in report do
	print("  " .. l)
end
local summary = string.format("sauce surface checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

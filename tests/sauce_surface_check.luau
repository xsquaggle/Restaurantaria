-- Checks for the continuous sauce surface (slice 8a, Astra r21: one thick opaque material over
-- the sauced area, not a disc per cell): presentation only. For every record of the slice 2
-- comparison set the grade and the field are unchanged after the surface is built; the surface
-- never reaches past the dough's edge; it draws about the area the grade credits (surface plus
-- the specks of thin sauce beside it); a bare hole stays bare; a round layer draws round (no
-- octagon); thin sauce stays specks, never a wash; the specks sit off the surface; a small
-- pizza's coarser grid keeps the shape; a thick layer's deep red is nested bands inside it. Arithmetic only: how it looks is checked in Studio and by Lawson.

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
table.insert(report, "record                               coverage  grade  credited  surface + specks = drawn   drawn/credited  tiles (stride 1 / 2)  specks  deep-red band areas")
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
	-- The deep-red bands: nested (each inside the one below, the first inside the surface),
	-- the same rule as the discs' tint (the deepest band reached is at most the deepest disc's
	-- share, rounded).
	local drawnLayers = SauceCover.layers(field, 1, true)
	check(name .. ": layers' surface is the surface", SurfaceTiles.area(drawnLayers.surface), surf)
	local deepest, outside, below = 0, 0, drawnLayers.surface
	local bandAreas = {}
	for j, band in drawnLayers.bands do
		check(string.format("%s: band %d is level %.2f", name, j, SauceCover.DEEP_LEVELS[j]), band.level, SauceCover.DEEP_LEVELS[j])
		if #band.tiles > 0 then
			deepest = band.level
		end
		for _, p in insidePoints(band.tiles) do
			if not covers(below, p[1], p[2]) then
				outside += 1
			end
		end
		below = band.tiles
		table.insert(bandAreas, string.format("%.3f", SurfaceTiles.area(band.tiles)))
	end
	check(name .. ": every band inside the one below it (and the first inside the surface)", outside, 0)
	local discDeep = 0
	for _, d in SauceCover.discs(field) do
		discDeep = math.max(discDeep, d.deep)
	end
	check(name .. ": no band deeper than the deepest disc's share", deepest <= discDeep + 0.025 + 1e-9, true)
	table.insert(report, string.format("%-36s %8.3f  %5d  %8.3f  %7.3f + %6.3f = %7.3f  %14.3f  %9d / %-9d  %6d  %s", name, before.detail.coverage, before.score, cred, surf, sp, surf + sp, ratio, #tiles, #tiles2, #specks, if #bandAreas > 0 then table.concat(bandAreas, " ") else "-"))
	if name == "excess mound" then
		check("excess mound: the mound reaches the top deep-red band", deepest, SauceCover.DEEP_LEVELS[#SauceCover.DEEP_LEVELS])
	end
	if name == "even adequate" then
		check("even adequate: an even layer is mostly free of deep red", #drawnLayers.bands == 0 or SurfaceTiles.area(drawnLayers.bands[1].tiles) < 0.25 * surf, true)
	end
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

-- 4. A round layer draws round: an even layer out to 0.61 (the cells out to 0.6, past rounding).
-- On the raw cell grid every crossing
-- of a sharp edge fell half way between two cells and the patch drew as an octagon (Studio,
-- 2026-11-01); smoothed on the finer grid its outline's radius stays within a few percent.
do
	local field = MakeSauce.empty()
	for i = 1, MakeSauce.COUNT do
		if MakeSauce.rs[i] <= 0.61 then
			field[i] = MakeSauce.EVEN
		end
	end
	for _, stride in { 1, 2 } do
		local tiles = SauceCover.surface(field, stride)
		local lo, hi, sum, n = math.huge, 0, 0, 0
		for a = 0, 359, 5 do
			local c, sn = math.cos(math.rad(a)), math.sin(math.rad(a))
			local r0, r1 = 0.3, 0.9
			for _ = 1, 30 do
				local m = (r0 + r1) / 2
				if covers(tiles, m * c, m * sn) then
					r0 = m
				else
					r1 = m
				end
			end
			lo, hi, sum, n = math.min(lo, r0), math.max(hi, r0), sum + r0, n + 1
		end
		local mean = sum / n
		-- The outline's directions, in 5 degree bins: an octagon has 8, a round outline many.
		local bins, dirs = {}, 0
		for _, t in tiles do
			if t.kind == "cut" then
				local b = math.floor(math.deg(math.atan2(t.ny :: number, t.nx :: number)) / 5 + 0.5) % 72
				if not bins[b] then
					bins[b] = true
					dirs += 1
				end
			end
		end
		check(string.format("round layer (stride %d): outline turns through at least 36 of 72 directions", stride), dirs >= 36, true)
		check(string.format("round layer (stride %d): outline radius within 6%% of its mean", stride), (hi - lo) / mean <= 0.06, true)
		check(string.format("round layer (stride %d): outline at the scored edge (0.6 to 0.65)", stride), mean >= 0.6 and mean <= 0.65, true)
		table.insert(report, string.format("round layer to 0.6, stride %d: outline radius %.3f to %.3f (mean %.3f, spread %.1f%%), %d of 72 directions", stride, lo, hi, mean, (hi - lo) / mean * 100, dirs))
	end
end

-- 5. SurfaceTiles: an inside corner exactly at the level lies on the outline and gives no side.
-- One such corner alone draws nothing; on a staircase's diagonal (two corners at the level, one
-- above, one below) the square's inside half is the one with the corner above.
do
	local function at(values: { [string]: number })
		return function(gx: number, gy: number): number
			return values[gx .. "," .. gy] or -1
		end
	end
	local lone = SurfaceTiles.build(1, 1, at({ ["0,0"] = 0 }), 0)
	check("tiles: a lone corner at the level draws nothing", SurfaceTiles.area(lone), 0)
	-- Square (0,0)-(1,1): (0,0) and (1,1) at the level, (0,1) above, (1,0) below.
	local stair = SurfaceTiles.build(1, 1, at({ ["0,0"] = 0, ["1,1"] = 0, ["0,1"] = 1, ["1,0"] = -1 }), 0)
	local half, onAbove, onBelow = 0, false, false
	for _, t in stair do
		if t.x0 == 0 and t.y0 == 0 then
			half += SurfaceTiles.area({ t })
		end
	end
	onAbove = covers(stair, 0.2, 0.8)
	onBelow = covers(stair, 0.8, 0.2)
	check("tiles: a diagonal at the level draws half the square", math.abs(half - 0.5) < 1e-9, true)
	check("tiles: that half is the side above the level", onAbove and not onBelow, true)
	-- Both outside corners a rounding error under the level: the outline runs along the
	-- square's edge and the whole square is inside (Studio, 2026-11-01: such squares drew bare,
	-- small notches along the sauce's outline).
	local edgeOn = SurfaceTiles.build(1, 1, at({ ["0,0"] = 1, ["0,1"] = 1, ["1,0"] = -1e-18, ["1,1"] = -1e-18 }), 0)
	local whole = 0
	for _, t in edgeOn do
		if t.x0 == 0 and t.y0 == 0 then
			whole += SurfaceTiles.area({ t })
		end
	end
	check("tiles: outside corners a rounding error under the level leave the square whole", math.abs(whole - 1) < 1e-6, true)
	-- Random fields with many values at, or a rounding error from, the level: the drawn surface
	-- agrees with the field read between its nodes (bilinear) wherever that is clearly in or
	-- out (a quarter of the square's largest corner value: the straight cut is a chord of the
	-- curved outline). A saddle whose middle is inside is drawn whole by design (header of
	-- SurfaceTiles), so those squares are left out.
	local seed = 12345
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local G = 6
	local bad, samples, saddles = 0, 0, 0
	for _ = 1, 40 do
		local values: { [string]: number } = {}
		for gx = -G, G do
			for gy = -G, G do
				local r = rand()
				values[gx .. "," .. gy] = if r < 0.2 then 0 elseif r < 0.35 then -1e-17 elseif r < 0.45 then 1e-17 else (rand() * 2 - 1)
			end
		end
		local value = at(values)
		local tiles = SurfaceTiles.build(G, 1, value, 0)
		for gx = -G, G - 1 do
			for gy = -G, G - 1 do
				local a, b, c, e = value(gx, gy), value(gx + 1, gy), value(gx + 1, gy + 1), value(gx, gy + 1)
				local big = math.max(math.abs(a), math.abs(b), math.abs(c), math.abs(e))
				local ia, ib, ic, ie = a >= 0, b >= 0, c >= 0, e >= 0
				if ia == ic and ib == ie and ia ~= ib and (a + b + c + e) / 4 >= 0 then
					saddles += 1
					continue
				end
				for sx = 1, 3 do
					for sy = 1, 3 do
						local u, w = sx / 4, sy / 4
						local bil = a * (1 - u) * (1 - w) + b * u * (1 - w) + c * u * w + e * (1 - u) * w
						if math.abs(bil) > 0.25 * big then
							samples += 1
							if (bil > 0) ~= covers(tiles, gx + u, gy + w) then
								bad += 1
							end
						end
					end
				end
			end
		end
	end
	check("tiles: random fields near the level draw what the field says", bad, 0)
	table.insert(report, string.format("tiles: %d clear samples of 40 random fields near the level (%d whole saddles left out), %d drawn wrong", samples, saddles, bad))
end

-- 5b. An oval rolled at an angle (a view that stretches the dough along turned axes): the
-- surfaces are drawn on their grid turned (SurfaceTiles.fit and build's turn), so every tile is
-- an exact turned rectangle (Studio, 2026-11-02: on the field's own grid such a view drew rows
-- of tiles splitting into stripes and steps). The fit rebuilds the view exactly, keeps the turn
-- within a quarter turn and leaves round and upright views on the field's own grid; the turned
-- surface covers what the field's own does (points clear of the outline) and draws the same area.
do
	local G = require(Shared.PrepGeometry)
	local function rot(t: number)
		return { a = math.cos(t), b = -math.sin(t), c = math.sin(t), d = math.cos(t) }
	end
	local function mul(A: any, B: any)
		return { a = A.a * B.a + A.b * B.c, b = A.a * B.b + A.b * B.d, c = A.c * B.a + A.d * B.c, d = A.c * B.b + A.d * B.d }
	end
	local worst, worstTurn, flips = 0, 0, 0
	local seed = 777
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for _ = 1, 400 do
		local J = { a = rnd() * 400 - 50, b = rnd() * 200 - 100, c = rnd() * 200 - 100, d = rnd() * 400 - 50 }
		if J.a * J.d - J.b * J.c > 1 then
			local phi, a, b, turn = SurfaceTiles.fit(J)
			local back = mul(mul(rot(math.rad(phi)), { a = a, b = 0, c = 0, d = b }), rot(turn))
			local scale = math.max(math.abs(J.a), math.abs(J.b), math.abs(J.c), math.abs(J.d))
			for _, k in { "a", "b", "c", "d" } do
				worst = math.max(worst, math.abs(back[k] - J[k]) / scale)
			end
			worstTurn = math.max(worstTurn, math.abs(turn))
			if a <= 0 or b <= 0 then
				flips += 1
			end
		end
	end
	check("turned fit: rebuilds the view (400 random views)", worst < 1e-9, true)
	check("turned fit: turn within a quarter turn", worstTurn <= math.pi / 4 + 1e-9, true)
	check("turned fit: positive stretches", flips, 0)
	-- Round and upright views keep the field's own grid, with no turn on screen.
	for _, case in { { "round", G.shape(0.95, 0.95, 0), 1 }, { "round in the oven", G.shape(0.95, 0.95, 0), 0.6 }, { "upright oval", G.shape(1.0, 0.8, 0), 1 }, { "tall oval", G.shape(0.8, 1.0, 0), 1 }, { "tall oval in the oven", G.shape(0.8, 1.0, 0), 0.6 } } do
		local J = G.localStretch(case[2], 300, case[3])
		local phi, a, b, turn = SurfaceTiles.fit(J)
		check("turned fit: " .. case[1] .. " keeps the grid", turn, 0)
		check("turned fit: " .. case[1] .. " is upright", phi, 0)
		check("turned fit: " .. case[1] .. " stretches as drawn", math.abs(a - J.a) + math.abs(b - J.d) < 1e-9, true)
	end
	-- A turned oval: a real turn, and the turned surface covers what the field's own does.
	local J = G.localStretch(G.shape(1.0, 0.72, math.rad(35)), 300, 1)
	local _, _, _, turn = SurfaceTiles.fit(J)
	check("turned fit: an oval turned 35 degrees turns the grid", math.abs(turn) > 0.3, true)
	local field = MakeSauce.replay(even)
	local own = SauceCover.layers(field, 2, true)
	local turned = SauceCover.layers(field, 2, true, turn)
	local h = 2 * CELL / SauceCover.FINE
	local samples, bad = 0, 0
	-- Compare where the field's own surface is clear: the point and its neighbours 1.5 squares
	-- away agree on it.
	for ix = -40, 40 do
		for iy = -40, 40 do
			local x, y = ix / 40, iy / 40
			local inOwn = covers(own.surface, x, y)
			local clear = true
			for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
				if covers(own.surface, x + 1.5 * h * o[1], y + 1.5 * h * o[2]) ~= inOwn then
					clear = false
					break
				end
			end
			if clear then
				samples += 1
				-- u = R(turn) p
				local ux, uy = math.cos(turn) * x - math.sin(turn) * y, math.sin(turn) * x + math.cos(turn) * y
				if covers(turned.surface, ux, uy) ~= inOwn then
					bad += 1
				end
				local bx, by = SurfaceTiles.unturn(turn, ux, uy)
				if math.abs(bx - x) + math.abs(by - y) > 1e-12 then
					bad += 1
				end
			end
		end
	end
	check("turned surface: covers what the field's own surface covers (clear of the outline)", bad, 0)
	local aOwn, aTurned = SurfaceTiles.area(own.surface), SurfaceTiles.area(turned.surface)
	check("turned surface: same area within 1%", math.abs(aTurned - aOwn) / aOwn <= 0.01, true)
	check("turned surface: as many deep-red bands", #turned.bands, #own.bands)
	-- Each turned band lies inside the turned surface and inside the band below it.
	local outside = 0
	for ix = -40, 40 do
		for iy = -40, 40 do
			local x, y = ix / 40, iy / 40
			local below = covers(turned.surface, x, y)
			for _, b in turned.bands do
				local here = covers(b.tiles, x, y)
				if here and not below then
					-- Allow the outline's own width: a neighbour of the point is under it.
					local near = false
					for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						if covers(turned.surface, x + h * o[1], y + h * o[2]) then
							near = true
						end
					end
					if not near then
						outside += 1
					end
				end
				below = here
			end
		end
	end
	check("turned surface: bands nested inside the surface", outside, 0)
	table.insert(report, string.format("turned grid: fit rebuilds 400 random views (worst %.1e), oval at 35 degrees turns the grid %.3f rad; %d clear points agree, area %.4f turned vs %.4f own", worst, turn, samples, aTurned, aOwn))
end

-- 6. An empty field draws nothing.
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

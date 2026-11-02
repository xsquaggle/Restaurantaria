--!strict
-- A food surface from a field on a square grid of nodes (marching squares), as tiles a GUI can
-- draw without masks or canvas groups (slice 8a; Astra r21: continuous surfaces, not per-cell
-- disc stamps). The surface is where the field is at or above `level`, between nodes taken as
-- linear, so its outline is a chain of straight pieces, one per grid square it crosses:
--  * "full" tiles: runs of whole squares along x inside the surface (one tile per run, so a large
--    patch is a few long tiles, not hundreds of squares);
--  * "cut" tiles: one square the outline crosses, drawn whole with a hard straight edge where
--    the outline runs (inside: n . (p - centre) <= d, n the outline's unit normal pointing out),
--    which the client draws with a UIGradient. A square whose four corners alternate (a saddle)
--    is two cut tiles when its middle is outside, or a full square when its middle is inside.
-- Pure: shared by the client renderer (FoodSurface) and the checks. Positions are in the grid's
-- own units (dough-local for the food).

local SurfaceTiles = {}

export type Tile = {
	kind: string, -- "full" or "cut"
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	nx: number?,
	ny: number?,
	d: number?,
	key: any?,
}

-- G: nodes run -G..G on each axis, h apart. value(gx, gy) is the field at a node. key(gx, gy),
-- if given, labels each square (a full run only joins squares with equal keys, e.g. a tint).
-- turn (radians, optional): build on the field's grid turned by it, so a view that stretches
-- the food along turned axes (an oval rolled at an angle: a shear the GUI cannot draw on
-- upright squares) draws exact turned rectangles. The tiles are then in turned coordinates
-- u = R(turn) p (SurfaceTiles.unturn maps them back), and each turned node takes the field
-- bilinearly between the field's own nodes (nodes past the grid take its nearest edge).
function SurfaceTiles.build(G: number, h: number, value: (number, number) -> number, level: number, key: ((number, number) -> any)?, turn: number?): { Tile }
	local tiles: { Tile } = {}
	local side = 2 * G + 1
	local vals = table.create(side * side, 0)
	for gx = -G, G do
		for gy = -G, G do
			vals[(gx + G) * side + (gy + G) + 1] = value(gx, gy)
		end
	end
	if turn and turn ~= 0 then
		assert(key == nil, "a turned surface has no square keys")
		local own = vals
		vals = table.create(side * side, 0)
		local c, s = math.cos(turn), math.sin(turn)
		local function at(ix: number, iy: number): number
			ix = math.clamp(ix, -G, G)
			iy = math.clamp(iy, -G, G)
			return own[(ix + G) * side + (iy + G) + 1]
		end
		for ux = -G, G do
			for uy = -G, G do
				-- p = R(-turn) u, in node units.
				local px, py = c * ux + s * uy, -s * ux + c * uy
				local fx, fy = math.floor(px), math.floor(py)
				local tx, ty = px - fx, py - fy
				local v00, v10, v01, v11 = at(fx, fy), at(fx + 1, fy), at(fx, fy + 1), at(fx + 1, fy + 1)
				vals[(ux + G) * side + (uy + G) + 1] = (v00 * (1 - tx) + v10 * tx) * (1 - ty) + (v01 * (1 - tx) + v11 * tx) * ty
			end
		end
	end
	local function v(gx: number, gy: number): number
		return vals[(gx + G) * side + (gy + G) + 1]
	end
	-- Where the outline crosses the edge from node a (value va, position pa) to node b.
	local function cross(ax: number, ay: number, va: number, bx: number, by: number, vb: number): (number, number)
		local t = (level - va) / (vb - va)
		return ax + (bx - ax) * t, ay + (by - ay) * t
	end
	-- A cut tile for square (gx, gy) from the outline piece P-Q, given the corners that bound
	-- the piece ({x, y, inside}). The normal is turned by the corner farthest from the line: a
	-- corner at the level, or within rounding of it, lies on the outline and gives no side (a
	-- smoothed staircase puts corners exactly at the level along its diagonal, and both outside
	-- corners of a square can sit a rounding error under it, the outline then running along
	-- the square's edge).
	local function cut(gx: number, gy: number, px: number, py: number, qx: number, qy: number, corners: { { any } }, k: any)
		local cx, cy = (gx + 0.5) * h, (gy + 0.5) * h
		local tx, ty = qx - px, qy - py
		local len = math.sqrt(tx * tx + ty * ty)
		if len < 1e-9 * h then
			-- Both crossings at one corner, which is at the level. An outside corner there: the
			-- inside is the whole square but that point. An inside one: that point alone.
			for _, o in corners do
				if not o[3] and math.abs(o[1] - px) + math.abs(o[2] - py) < 1e-9 * h then
					table.insert(tiles, { kind = "full", x0 = gx * h, y0 = gy * h, x1 = (gx + 1) * h, y1 = (gy + 1) * h, key = k })
					return
				end
			end
			return
		end
		local nx, ny = -ty / len, tx / len
		-- Point it out: the farthest corner is on the outside of the line if it is outside, on
		-- the inside if it is inside.
		local best, bestInside = 0, false
		for _, o in corners do
			local s = nx * (o[1] - px) + ny * (o[2] - py)
			if math.abs(s) > math.abs(best) then
				best, bestInside = s, o[3]
			end
		end
		if (best < 0) ~= bestInside then
			nx, ny = -nx, -ny
		end
		local d = nx * (px - cx) + ny * (py - cy)
		table.insert(tiles, { kind = "cut", x0 = gx * h, y0 = gy * h, x1 = (gx + 1) * h, y1 = (gy + 1) * h, nx = nx, ny = ny, d = d, key = k })
	end
	for gy = -G, G - 1 do
		local run: number? = nil
		local runKey: any = nil
		local function flush(endX: number)
			if run then
				table.insert(tiles, { kind = "full", x0 = run * h, y0 = gy * h, x1 = endX * h, y1 = (gy + 1) * h, key = runKey })
				run = nil
			end
		end
		for gx = -G, G - 1 do
			local a, b, c, e = v(gx, gy), v(gx + 1, gy), v(gx + 1, gy + 1), v(gx, gy + 1)
			local ia, ib, ic, ie = a >= level, b >= level, c >= level, e >= level
			local k = if key then key(gx, gy) else nil
			local full = ia and ib and ic and ie
			local empty = not (ia or ib or ic or ie)
			if not full and not empty and ia == ic and ib == ie and ia ~= ib then
				-- Saddle: decide by the middle.
				if (a + b + c + e) / 4 >= level then
					full = true
				end
			end
			if full then
				if run and runKey ~= k then
					flush(gx)
				end
				if not run then
					run, runKey = gx, k
				end
			else
				flush(gx)
				if not empty then
					local x0, y0, x1, y1 = gx * h, gy * h, (gx + 1) * h, (gy + 1) * h
					-- Corners in order around the square: (x0,y0) a, (x1,y0) b, (x1,y1) c, (x0,y1) e.
					local cx = { x0, x1, x1, x0 }
					local cy = { y0, y0, y1, y1 }
					local cv = { a, b, c, e }
					local inside = { ia, ib, ic, ie }
					local points = {}
					for i = 1, 4 do
						local j = i % 4 + 1
						if inside[i] ~= inside[j] then
							local px, py = cross(cx[i], cy[i], cv[i], cx[j], cy[j], cv[j])
							table.insert(points, { px, py, i, j })
						end
					end
					if #points == 2 then
						local corners = {}
						for i = 1, 4 do
							corners[i] = { cx[i], cy[i], inside[i] }
						end
						cut(gx, gy, points[1][1], points[1][2], points[2][1], points[2][2], corners, k)
					elseif #points == 4 then
						-- Saddle with its middle outside: each inside corner gets its own piece,
						-- between the crossings on its two edges.
						for i = 1, 4 do
							if inside[i] then
								local before = (i + 2) % 4 + 1 -- the edge ending at corner i
								local p1, p2
								for _, p in points do
									if p[3] == i then
										p1 = p
									elseif p[3] == before then
										p2 = p
									end
								end
								if p1 and p2 then
									-- The corner and its two neighbours, which are outside (a saddle
									-- alternates); the opposite corner is inside but past the line.
									local o1, o2 = i % 4 + 1, (i + 2) % 4 + 1
									cut(gx, gy, p1[1], p1[2], p2[1], p2[2], { { cx[i], cy[i], true }, { cx[o1], cy[o1], false }, { cx[o2], cy[o2], false } }, k)
								end
							end
						end
					end
				end
			end
		end
		flush(G)
	end
	return tiles
end

-- A point of a turned surface's tiles (u, built with `turn`) back in the field's own
-- coordinates: p = R(-turn) u.
function SurfaceTiles.unturn(turn: number, x: number, y: number): (number, number)
	local c, s = math.cos(turn), math.sin(turn)
	return c * x + s * y, -s * x + c * y
end

-- A surface's exact draw: J = R(phi) diag(a, b) R(turn), a view's local stretch (screen px per
-- unit, screen = J p, R(t) turning +x towards +y)
-- split into a turn of the food's own grid, a stretch along the turned axes and a turn on
-- screen (2 x 2 singular values). A surface built on its field's grid turned by `turn`
-- (SurfaceTiles.build) is drawn by tiles that are exact turned rectangles, so neighbours meet
-- on any oval; on the field's own grid a sheared oval (rolled at an angle) cannot be drawn by
-- rectangles, and Studio showed the tiles' rows splitting into stripes and steps. The turn is
-- kept within a quarter turn, and is 0 for every round dough and the oven's upright views (the
-- tiles are then the field's own squares, as before). Returns phi (degrees), a and b (px per
-- unit along the drawn axes) and turn (radians). The material maps are sampled in the turned
-- grid's coordinates, so on a turned oval the sauce material is turned with it (one consistent
-- orientation for every tile of the view).
function SurfaceTiles.fit(J: { a: number, b: number, c: number, d: number }): (number, number, number, number)
	local E, Fd = (J.a + J.d) / 2, (J.a - J.d) / 2
	local Gs, H = (J.b + J.c) / 2, (J.c - J.b) / 2
	local Q, R = math.sqrt(E * E + H * H), math.sqrt(Fd * Fd + Gs * Gs)
	local a2 = math.atan2(H, E)
	if R <= 1e-9 * Q then
		-- The same stretch both ways: a turn and a scale, no grid turn.
		return math.deg(a2), Q, Q, 0
	end
	local a1 = math.atan2(Gs, Fd)
	local phi, turn = (a2 + a1) / 2, (a2 - a1) / 2
	local sa, sb = Q + R, Q - R
	-- Keep the grid's turn within a quarter turn: R(phi) diag(a, b) R(turn) equals
	-- R(phi - k pi/2) diag'(.) R(turn + k pi/2), the axes swapped for odd k.
	local k = math.floor(-turn / (math.pi / 2) + 0.5)
	if k ~= 0 then
		turn += k * math.pi / 2
		phi -= k * math.pi / 2
		if k % 2 ~= 0 then
			sa, sb = sb, sa
		end
	end
	if math.abs(turn) < 1e-7 then
		turn = 0
	end
	if math.abs(phi) < 1e-9 then
		phi = 0
	end
	return math.deg(phi), sa, sb, turn
end

-- The area of the surface the tiles draw (full tiles plus each cut tile's inside part), for the
-- proofs' drawn-against-scored figures. Exact for the half-plane inside a square.
function SurfaceTiles.area(tiles: { Tile }): number
	local total = 0
	for _, t in tiles do
		local w, hh = t.x1 - t.x0, t.y1 - t.y0
		if t.kind == "full" then
			total += w * hh
		else
			-- Clip the square by n . (p - c) <= d (Sutherland-Hodgman on four corners).
			local cx, cy = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2
			local nx, ny, d = t.nx :: number, t.ny :: number, t.d :: number
			local poly = { { t.x0, t.y0 }, { t.x1, t.y0 }, { t.x1, t.y1 }, { t.x0, t.y1 } }
			local out = {}
			for i = 1, 4 do
				local p, q = poly[i], poly[i % 4 + 1]
				local fp = nx * (p[1] - cx) + ny * (p[2] - cy) - d
				local fq = nx * (q[1] - cx) + ny * (q[2] - cy) - d
				if fp <= 0 then
					table.insert(out, p)
				end
				if (fp < 0 and fq > 0) or (fp > 0 and fq < 0) then
					local s = fp / (fp - fq)
					table.insert(out, { p[1] + (q[1] - p[1]) * s, p[2] + (q[2] - p[2]) * s })
				end
			end
			local a = 0
			for i = 1, #out do
				local p, q = out[i], out[i % #out + 1]
				a += p[1] * q[2] - q[1] * p[2]
			end
			total += math.abs(a) / 2
		end
	end
	return total
end

return SurfaceTiles

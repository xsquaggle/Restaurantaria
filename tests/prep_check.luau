-- Checks for the Prep contract's pure code: the one coordinate map (PrepGeometry), the view and
-- body transforms, the roll preview, the layout envelope, sauce cells and the corrected spread
-- pickup, cheese pinch sampling and footprint (PrepFood), and the ordered cheese outbox
-- (PrepOutbox) against a model of the server's cheese actions. Run offline with
-- tests/offline/run.py, or in Studio Edit after a sync. Arithmetic and logic only: the drawn
-- sizes, clipping and registration are measured in Studio (tests/studio/prep_proof.luau).

local Shared = game:GetService("ReplicatedStorage").Shared
local G = require(Shared.PrepGeometry)
local F = require(Shared.PrepFood)
local PrepOutbox = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.PrepOutbox)

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
-- One check either way: a miss is one failure, with both values.
local function near(name: string, got: number, want: number, tol: number?)
	if math.abs(got - want) <= (tol or 1e-9) then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %.9f, want %.9f (+-%g)", name, got, want, tol or 1e-9))
	end
end
local function note(line: string)
	table.insert(report, line)
end

local R45 = math.rad(45)

-- 1. One map. A full round dough: dough-local = pizza-local.
local full = G.shape(0.95, 0.95, 0)
local q = G.toDough(full, { x = 0.3, y = -0.7 })
near("full round: q.x = p.x", q.x, 0.3)
near("full round: q.y = p.y", q.y, -0.7)

-- Astra's example: a = 1.1, b = 0.35 at 45 degrees, p = (0.1, 0.35) -> q ~ (-0.145, 0.534).
local worst = G.shape(1.1, 0.35, R45)
q = G.toDough(worst, { x = 0.1, y = 0.35 })
near("worst oval: q.x", q.x, -0.145, 0.0006)
near("worst oval: q.y", q.y, 0.534, 0.0006)
local back = G.toPizza(worst, q)
near("worst oval: round trip x", back.x, 0.1, 1e-12)
near("worst oval: round trip y", back.y, 0.35, 1e-12)
check("worst oval: visible half from physical x", G.visibleHalf(worst, q), "right")
check("worst oval: q.x alone would say left", q.x < 0, true)
-- Astra's counterexample in geometry-check.json: physical (0.05, 0.3).
q = G.toDough(worst, { x = 0.05, y = 0.3 })
check("counterexample: visible right", G.visibleHalf(worst, q), "right")
check("counterexample: local x negative", q.x < 0, true)

-- The outline is dough-local radius 0.95 for every shape and turn.
for _, shape in { { 0.95, 0.95 }, { 1.1, 0.35 }, { 0.35, 0.35 }, { 0.7, 0.5 } } do
	for _, turn in { 0, 45, 90 } do
		local S = G.shape(shape[1], shape[2], math.rad(turn))
		local worstErr = 0
		for k = 0, 35 do
			local a = math.rad(k * 10)
			local p = G.apply(S, { x = math.cos(a), y = math.sin(a) })
			local d = G.toDough(S, p)
			worstErr = math.max(worstErr, math.abs(math.sqrt(d.x * d.x + d.y * d.y) - 0.95))
		end
		near(string.format("outline at 0.95: %.2fx%.2f turned %d", shape[1], shape[2], turn), worstErr, 0, 1e-12)
	end
end
-- The mixed convention Astra found: S applied to a 0.95 radius lands at 0.9025, 5 % short.
near("mixed map shortfall (documented, not used)", G.apply(full, { x = 0.95, y = 0 }).x, 0.9025, 1e-12)
near("one map: dough-local 0.95 is the outline", G.toPizza(full, { x = 0.95, y = 0 }).x, 0.95, 1e-12)

-- 2. Displayed ellipse from the full composed transform, against brute force.
local function brute(K)
	local best, worst2, angle = 0, math.huge, 0
	for k = 0, 35999 do
		local a = math.rad(k / 100)
		local v = G.apply(K, { x = math.cos(a), y = math.sin(a) })
		local r = math.sqrt(v.x * v.x + v.y * v.y)
		if r > best then
			best, angle = r, math.atan2(v.y, v.x)
		end
		worst2 = math.min(worst2, r)
	end
	return best, worst2, angle
end
-- 0.58 here is a fixed geometric case (the oven flatten before slice 4), not the live oven,
-- which is PrepGeometry.BAKE_FLATTEN (0.7).
for _, case in { { 190, 1 }, { 190, 0.58 }, { 663, 0.58 } } do
	for _, turn in { 0, 45, 90 } do
		local K = G.viewMatrix(G.shape(1.1, 0.35, math.rad(turn)), case[1], case[2])
		local e = G.ellipseOf(K)
		local A, B, ang = brute(K)
		local label = string.format("view F=%d flatten %.2f turn %d", case[1], case[2], turn)
		near(label .. ": major", e.major, A, 1e-4 * A)
		near(label .. ": minor", e.minor, B, 1e-3)
		local da = math.abs(((e.angle - ang + math.pi / 2) % math.pi) - math.pi / 2)
		near(label .. ": angle", da, 0, 0.0002)
		note(string.format("%s: displayed %.2f x %.2f px at %.2f deg", label, 2 * e.major, 2 * e.minor, math.deg(e.angle)))
	end
end
-- Bake's flatten is not "vertical radius x 0.58 at the original angle" for a turned oval.
do
	local e = G.ellipseOf(G.viewMatrix(G.shape(1.1, 0.35, R45), 190, 0.58))
	check("bake 45: angle moves off 45", math.abs(math.deg(e.angle) - 45) > 5, true)
	note(string.format("bake 45 deg oval: drawn angle %.2f deg, not 45", math.deg(e.angle)))
end

-- 2b. Food transform (Astra r13 item 2). Expected offsets are worked by hand from
-- screen = (F / 2) D S (q / 0.95), never from the helpers under test. The doubled map Astra found
-- gave (114.95, 0) and (0, 11.6375) for the first two.
do
	local function at(label, S, flatten, q, wx, wy)
		local o = G.screenOf(S, 190, flatten, q)
		near(label .. " x", o.x, wx, 1e-9)
		near(label .. " y", o.y, wy, 1e-9)
	end
	local oval = G.mat(1.1, 0, 0, 0.35)
	at("diag(1.1, .35) Prep q=(.95,0)", oval, 1, { x = 0.95, y = 0 }, 104.5, 0)
	at("diag(1.1, .35) Prep q=(0,.95)", oval, 1, { x = 0, y = 0.95 }, 0, 33.25)
	at("diag(1.1, .35) Bake q=(0,.95)", oval, 0.58, { x = 0, y = 0.95 }, 0, 19.285)
	-- Turned 45 degrees: S = [.725 .375; .375 .725] (mean .725, half-difference .375).
	local turned = G.mat(0.725, 0.375, 0.375, 0.725)
	local fromShape = G.shape(1.1, 0.35, R45)
	near("shape(1.1, .35, 45) = [.725 .375; .375 .725]", math.abs(fromShape.a - 0.725) + math.abs(fromShape.b - 0.375) + math.abs(fromShape.d - 0.725), 0, 1e-12)
	at("turned Prep q=(.95,0)", turned, 1, { x = 0.95, y = 0 }, 68.875, 35.625)
	at("turned Prep q=(0,.95)", turned, 1, { x = 0, y = 0.95 }, 35.625, 68.875)
	at("turned Prep q=(.3,-.5)", turned, 1, { x = 0.3, y = -0.5 }, 3, -25)
	at("turned Bake q=(.95,0)", turned, 0.58, { x = 0.95, y = 0 }, 68.875, 20.6625)
	at("turned Bake q=(.3,-.5)", turned, 0.58, { x = 0.3, y = -0.5 }, 3, -14.5)
	-- Food on the outline sits on the drawn body: dough-local radius 0.95 lands on K's ellipse.
	local e = G.ellipseOf(G.viewMatrix(turned, 190, 0.58))
	local worst = 0
	for k = 0, 71 do
		local a = math.rad(k * 5)
		local o = G.screenOf(turned, 190, 0.58, { x = 0.95 * math.cos(a), y = 0.95 * math.sin(a) })
		local c, sn = math.cos(-e.angle), math.sin(-e.angle)
		local u, v = c * o.x - sn * o.y, sn * o.x + c * o.y
		worst = math.max(worst, math.abs((u / e.major) ^ 2 + (v / e.minor) ^ 2 - 1))
	end
	near("turned Bake: food at q-radius .95 lies on the drawn outline", worst, 0, 1e-9)
	-- Local stretch is the derivative of screenOf: a small step in q moves J times that step.
	local J = G.localStretch(turned, 190, 0.58)
	local o0 = G.screenOf(turned, 190, 0.58, { x = 0.1, y = 0.2 })
	local o1 = G.screenOf(turned, 190, 0.58, { x = 0.1 + 1e-3, y = 0.2 })
	near("localStretch matches screenOf (x step, x)", (o1.x - o0.x) / 1e-3, J.a, 1e-6)
	near("localStretch matches screenOf (x step, y)", (o1.y - o0.y) / 1e-3, J.c, 1e-6)
	near("turned Bake J.a = 95 x .725 / .95", J.a, 72.5, 1e-9)
	-- Fully rolled S = .95 I: a radius-.17 pinch is 2 x .17 x 95 = 32.3 px ACROSS (diameter).
	local fit = G.spriteFit(G.localStretch(G.shape(0.95, 0.95, 0), 190, 1), 2 * F.PINCH_RADIUS, 2 * F.PINCH_RADIUS, 0)
	near("pinch diameter at F=190, full round", fit.width, 32.3, 1e-9)
	near("pinch round on a round dough", fit.height, 32.3, 1e-9)
end

-- 3. Registered bodies. P3 and P4 state 1 on the same 0.35 ball show the same body, and a
-- measured centre offset is moved back onto the pivot.
for _, frame in { 663, 190 } do
	local e = G.ballEllipse(frame)
	local ballBody = { alphaX = 0.35, alphaY = 0.35, centreX = 0, centreY = 0 }
	local stateBody = { alphaX = 0.95, alphaY = 0.95, centreX = 0, centreY = 0 }
	local b3 = G.bodyPlacement(e, ballBody)
	local b4 = G.bodyPlacement(e, stateBody)
	near(frame .. ": P3 body", b3.width * 0.35, 0.35 * frame, 1e-9)
	near(frame .. ": P4 state 1 body = P3 body", b4.width * 0.95, b3.width * 0.35, 1e-9)
	-- Off-centre body (0.5 % of the canvas each way, Astra's per-image allowance) on a turned
	-- oval: after placement the body centre is on the pivot.
	local turned = G.ellipseOf(G.viewMatrix(G.shape(1.1, 0.35, R45), frame, 0.58))
	local off = { alphaX = 0.95, alphaY = 0.95, centreX = 0.005, centreY = -0.005 }
	local pl = G.bodyPlacement(turned, off)
	local c, s = math.cos(math.rad(pl.rotation)), math.sin(math.rad(pl.rotation))
	local bx, by = off.centreX * pl.width, off.centreY * pl.height
	near(frame .. ": registered body centre x", pl.offset.x + c * bx - s * by, 0, 1e-9)
	near(frame .. ": registered body centre y", pl.offset.y + s * bx + c * by, 0, 1e-9)
	-- Without registration that offset would drift by 0.5 % of the drawn canvas.
	local full95 = G.bodyPlacement(G.ellipseOf(G.viewMatrix(full, frame)), { alphaX = 0.95, alphaY = 0.95, centreX = 0.005, centreY = 0 })
	note(string.format("F=%d: an unregistered 0.5 %% centroid offset drifts %.3f px at full size (Astra: HD 3.315, phone 0.95); registered: 0", frame, 0.005 * full95.width))
end

-- 4. Roll preview: equal strokes, continuous growth, the cap.
do
	local S = G.ball()
	check("stroke beside the dough refused", G.roll(S, { x = 0.8, y = -1 }, { x = 0.8, y = 1 }), nil)
	-- A held stroke previewed at 60 points never jumps and ends equal to the committed stroke.
	local p1, p2 = { x = -1, y = 0 }, { x = 1, y = 0 }
	local prev = G.meanRadius(S)
	local biggest = 0
	for i = 1, 60 do
		local t = i / 60
		local P = G.roll(S, p1, { x = p1.x + (p2.x - p1.x) * t, y = 0 }) or S
		local r = G.meanRadius(P)
		check("preview never shrinks " .. i, r >= prev - 1e-12, true)
		biggest = math.max(biggest, r - prev)
		prev = r
	end
	local committed = G.meanRadius(G.roll(S, p1, p2) :: any)
	near("preview end = committed", prev, committed, 1e-12)
	note(string.format("one full stroke on the ball: mean radius 0.350 -> %.4f, largest preview step %.4f", committed, biggest))
	-- Alternating full passes: how many reach a round full-size base (Lawson 2026-10-28: three).
	local strokes = {}
	local n = 0
	repeat
		n += 1
		local a = (n % 2) * math.pi / 2
		table.insert(strokes, { x1 = -1.5 * math.cos(a), y1 = -1.5 * math.sin(a), x2 = 1.5 * math.cos(a), y2 = 1.5 * math.sin(a) })
	until G.meanRadius(G.doughShape(strokes)) >= 0.95 or n >= 30
	local ax = G.axes(G.doughShape(strokes))
	note(string.format("alternating full passes to mean radius 0.95: %d (round %.3f x %.3f)", n, ax.major, ax.minor))
	check("full size takes three passes", n, 3)
	for _ = 1, 30 do
		table.insert(strokes, { x1 = -1.5, y1 = 0, x2 = 1.5, y2 = 0 })
	end
	check("semi-axis capped at 1.1", G.axes(G.doughShape(strokes)).major <= 1.1 + 1e-12, true)
	local i1, i2, w = G.stateBlend(0.65)
	check("state blend picks 3 and 4", i1 * 10 + i2, 34)
	near("state blend weight", w, 0.5, 1e-12)
end

-- 5. Envelope: the mat is allocated outward from 211.111.
do
	local phone = G.envelope(190, 212)
	near("phone crust", phone.crust, 180.5, 1e-9)
	near("phone over-roll", phone.overRoll, 209, 1e-9)
	near("phone mat exact", phone.matExact, 211.11111111, 1e-6)
	check("phone mat rounded outward", phone.mat, 212)
	check("phone fits at 212", phone.fits, true)
	check("phone short at 211", G.envelope(190, 211).shortfall, 1)
	near("phone ball", phone.ball, 66.5, 1e-9)
	local hd = G.envelope(663, 900)
	check("HD mat", hd.mat, 737)
	near("HD crust", hd.crust, 629.85, 1e-9)
	note(string.format("phone: frame 190, crust 180.5, over-roll 209, mat %.3f -> %d (%.1f px each side of the over-roll); P4 canvas at full over-roll %.1f px", phone.matExact, phone.mat, (phone.mat - phone.overRoll) / 2, 209 / 0.95))
end

-- 6. Unsheared sprites: where the GUI cannot show the exact shape (reported, a visual gate).
do
	for _, view in { { "Prep", 1 }, { "Bake", 0.58 } } do
		for _, shape in { { 0.95, 0.95 }, { 1.1, 0.35 } } do
			for _, turn in { 0, 45, 90 } do
				local J = G.localStretch(G.shape(shape[1], shape[2], math.rad(turn)), 190, view[2])
				local worstShear = 0
				for k = 0, 7 do
					worstShear = math.max(worstShear, G.spriteFit(J, 76, 40, math.rad(k * 22.5)).shear)
				end
				if shape[1] == shape[2] and view[2] == 1 then
					near("round Prep: no shear " .. turn, worstShear, 0, 1e-9)
				end
				note(string.format("%s %.2fx%.2f turned %d: worst shear of an angular 76x40 sprite %.1f deg (round sprites map exactly)", view[1], shape[1], shape[2], turn, worstShear))
			end
		end
	end
end

-- 7. Sauce cells.
near("inner centroid radius", math.sqrt(F.centroids[1].x ^ 2 + F.centroids[1].y ^ 2), 0.315, 0.001)
near("middle centroid radius", math.sqrt(F.centroids[9].x ^ 2 + F.centroids[9].y ^ 2), 0.576, 0.001)
near("outer centroid radius", math.sqrt(F.centroids[17].x ^ 2 + F.centroids[17].y ^ 2), 0.746, 0.001)
near("crust centroid radius", math.sqrt(F.centroids[25].x ^ 2 + F.centroids[25].y ^ 2), 0.873, 0.001)
check("past the outline: no cell", F.cellOf({ x = 0.96, y = 0 }), nil)
do
	local cells = F.emptyCells()
	F.pour(cells, { x = 0, y = 0 })
	local inner = 0
	for i = 1, 8 do
		inner += cells[i]
	end
	near("centre pour fills the 8 inner cells", inner, 1, 1e-12)
	near("centre pour: one eighth each", cells[3], 1 / 8, 1e-12)
end

-- 8. Spread pickup (Astra r9): a stroke starting on bare dough that crosses sauce moves it.
local function total(cells)
	local t = 0
	for _, v in cells do
		t += v
	end
	return t
end
do
	local cells = F.emptyCells()
	F.pour(cells, { x = 0.3, y = 0.05 }) -- sauce right of centre
	local startCell = F.cellOf({ x = -0.6, y = 0.05 }) :: number
	check("stroke starts on bare dough", cells[startCell], 0)
	-- Rev 6's rule picked up from the start cell only: half of nothing.
	local oldMoved = cells[startCell] * F.PICKUP
	check("rev 6 rule would move nothing", oldMoved, 0)
	local before = total(cells)
	local ok, moved = F.spread(cells, { x = -0.6, y = 0.05 }, { x = 0.8, y = 0.05 })
	check("corrected: accepted", ok, true)
	check("corrected: positive transfer", moved > 0, true)
	near("sauce conserved", total(cells), before, 1e-12)
	note(string.format("bare-start spread across sauce: transfer %.4f units (rev 6 rule: 0)", moved))
	-- Over bare dough only: refused.
	local bare = F.emptyCells()
	F.pour(bare, { x = 0.3, y = 0.05 })
	local ok2 = F.spread(bare, { x = -0.8, y = -0.5 }, { x = -0.3, y = -0.8 })
	check("bare-only stroke refused", ok2, false)
	-- Crossing sauce only in its last cell: accepted but no transfer, so D7 is not met.
	local last = F.emptyCells()
	last[F.cellOf({ x = 0.75, y = 0.02 }) :: number] = 0.5
	local ok3, moved3 = F.spread(last, { x = -0.7, y = 0.02 }, { x = 0.75, y = 0.02 })
	check("ends in sauce: accepted", ok3, true)
	near("ends in sauce: no transfer", moved3, 0, 1e-12)
	local _, _, met = F.sauce({ { kind = "pour", x = 0.75, y = 0.02 }, { kind = "spread", x = 0.75, y = 0.02, x2 = 0.751, y2 = 0.021 } })
	check("D7: zero-transfer spread does not meet the minimum", met, false)
	local _, _, met2 = F.sauce({ { kind = "pour", x = 0, y = 0 }, { kind = "spread", x = -0.6, y = 0, x2 = 0.6, y2 = 0 } })
	check("D7: a moving spread meets it", met2, true)
	-- Carried past the outline: stays in the crust cell where it left; total kept.
	local edge = F.emptyCells()
	F.pour(edge, { x = 0.8, y = 0 })
	local t0 = total(edge)
	F.spread(edge, { x = 0.5, y = 0 }, { x = 1.4, y = 0 })
	near("past the outline: total kept", total(edge), t0, 1e-12)
end

-- 9. Cheese sampling: equal paths, equal pinches; reversals.
local function run(points)
	local s = F.sampler()
	local out = {}
	for _, p in points do
		for _, placed in s.feed(p) do
			table.insert(out, placed)
		end
	end
	return out
end
do
	local coarse = run({ { x = -0.5, y = 0 }, { x = 0.5, y = 0 } })
	local fine = {}
	for i = 0, 97 do
		table.insert(fine, { x = -0.5 + i / 97, y = 0 })
	end
	local fineOut = run(fine)
	check("straight 1.0: 5 pinches", #coarse, 5)
	check("event rate: same count", #fineOut, #coarse)
	local worstD = 0
	for i = 1, math.min(#coarse, #fineOut) do
		worstD = math.max(worstD, math.abs(coarse[i].x - fineOut[i].x) + math.abs(coarse[i].y - fineOut[i].y))
	end
	near("event rate: same positions", worstD, 0, 1e-9)
	-- A reversal 0.125 after a pinch: the next pinch lands on the first one's spot.
	local rev = run({ { x = 0, y = 0 }, { x = 0.125, y = 0 }, { x = -0.5, y = 0 } })
	check("reversal: pinches", #rev, 4)
	near("reversal: second pinch back at the start", rev[2].x, 0, 1e-12)
	local oldRule = true
	for i = 2, #rev do
		if (rev[i].x - rev[i - 1].x) ^ 2 + (rev[i].y - rev[i - 1].y) ^ 2 < 0.2 ^ 2 then
			oldRule = false
		end
	end
	check("rev 6 spacing rule would refuse the reversal", oldRule, false)
	check("corrected spacing rule accepts it", F.strokeSpacingOk(rev), true)
	check("spacing rule refuses a 0.3 jump", F.strokeSpacingOk({ { x = 0, y = 0 }, { x = 0.3, y = 0 } }), false)
end

-- 10. Footprint: frozen sample, overlap, caps.
check("footprint points", #F.FOOTPRINT, 37)
do
	-- Equal-area rings: the squared radii sum to (6 x 4 + 12 x 13 + 18 x 28) / 37 = 684 / 37,
	-- and the turns 0 / 15 / 10 degrees fix the first point of each ring.
	local r2 = 0
	for _, o in F.FOOTPRINT do
		r2 += o.x * o.x + o.y * o.y
	end
	near("footprint frozen: ring radii", r2, 684 / 37, 1e-12)
	near("footprint frozen: ring 2 turn", math.deg(math.atan2(F.FOOTPRINT[8].y, F.FOOTPRINT[8].x)), 15, 1e-9)
	near("footprint frozen: ring 3 turn", math.deg(math.atan2(F.FOOTPRINT[20].y, F.FOOTPRINT[20].x)), 10, 1e-9)
	local area = F.footprint({ { x = 0.2, y = 0.2 } })
	near("one inside pinch: whole area", total(area), F.PINCH_AREA, 1e-12)
	local twice = F.footprint({ { x = 0.2, y = 0.2 }, { x = 0.2, y = 0.2 } })
	near("overlap adds", total(twice), 2 * F.PINCH_AREA, 1e-12)
	local s1, _, spread1 = F.cheeseScore({ { x = 0.2, y = 0.2 } })
	local s2, _, spread2 = F.cheeseScore({ { x = 0.2, y = 0.2 }, { x = 0.2, y = 0.2 } })
	check("overlap credit capped per cell", spread2 <= spread1 * 2 + 1e-12 and spread2 >= spread1, true)
	-- Units: the cheese COMPONENT SCORE is out of 100; occupied cells are a count. One pinch at
	-- (0.2, 0.2) touches two cells and scores 6/100 (it does not cover six cells; Astra r13).
	local touched = 0
	for _, a in area do
		if a > 0 then
			touched += 1
		end
	end
	check("one pinch at (0.2, 0.2) touches two cells", touched, 2)
	check("one pinch at (0.2, 0.2): cheese score 6/100", s1, 6)
	near("one pinch at (0.2, 0.2): spread credit 1/12", spread1, 1 / 12, 1e-9)
	note(string.format("one pinch at (0.2, 0.2): touches %d cells, cheese score %d/100, spread %.4f (= 1/12); the same pinch twice: %d/100", touched, s1, spread1, s2))
	local edgeArea = total(F.footprint({ { x = 0.84, y = 0 } }))
	note(string.format("pinch centred on the 0.84 sauce edge: %.0f %% of its footprint counts in sauce cells", 100 * edgeArea / F.PINCH_AREA))
	check("edge pinch counts in part", edgeArea > 0 and edgeArea < F.PINCH_AREA, true)
end

-- 11. Outbox against a model of the server's cheese actions.
local function server()
	local self = { pizzas = {}, log = {}, biggest = 0, refusals = {} }
	function self.receive(m)
		local id = m.args.pizzaId
		-- A pizza's record is kept only once an action on it is accepted: a refused first batch
		-- leaves no record behind.
		local p = self.pizzas[id] or { strokes = {}, step = "cheese" }
		table.insert(self.log, m.action .. ":" .. id)
		if p.step ~= "cheese" then
			return false
		end
		if m.action == "addCheese" then
			-- Validate the whole candidate first; commit only if it passes (Astra r13 item 3).
			local newStroke = m.args.newStroke or #p.strokes == 0
			local ok, why = F.validateCheeseBatch(p.strokes, m.args.points, newStroke)
			if not ok then
				table.insert(self.refusals, why)
				return false
			end
			self.pizzas[id] = p
			if newStroke then
				table.insert(p.strokes, {})
			end
			local s = p.strokes[#p.strokes]
			self.biggest = math.max(self.biggest, #m.args.points)
			for _, pt in m.args.points do
				table.insert(s, pt)
			end
			p.batches = (p.batches or 0) + 1
		elseif m.action == "undoCheese" then
			self.pizzas[id] = p
			table.remove(p.strokes)
		elseif m.action == "advancePrep" then
			self.pizzas[id] = p
			p.step = "done"
		end
		return true
	end
	function self.count(id)
		local n = 0
		for _, s in (self.pizzas[id] or { strokes = {} }).strokes do
			n += #s
		end
		return n
	end
	return self
end
local function harness()
	local srv = server()
	local box
	box = PrepOutbox.new(function(m)
		if not srv.receive(m) then
			box.refused(m.args.pizzaId)
		end
	end)
	local clock = 0
	local function flush(seconds)
		local stop = clock + seconds
		while clock < stop do
			box.tick(clock)
			clock += 1 / 60
		end
		box.tick(clock)
	end
	return srv, box, flush
end
local function line(n, y)
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, { x = -0.6 + i * 0.05, y = y or 0 })
	end
	return out
end
do
	-- a. Hold, release and Next at once: every pinch arrives before Next.
	local srv, box, flush = harness()
	box.begin(1)
	for _, p in line(20) do
		box.place(p)
	end
	box.advance(1, "cheese")
	flush(1)
	check("a: server pinches", srv.count(1), 20)
	check("a: visible pinches", #box.visible(1), 20)
	check("a: Next sent last", srv.log[#srv.log], "advancePrep:1")
	check("a: three batches then Next", #srv.log, 4)
	check("a: no cheese after Next", box.begin(1), false)
	check("a: no Undo after Next", box.undo(1), false)

	-- b. Ticket switching keeps every batch on its own pizza.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(10) do
		box.place(p)
	end
	box.focus(2)
	box.begin(2)
	for _, p in line(5, 0.2) do
		box.place(p)
	end
	flush(1)
	check("b: pizza 1", srv.count(1), 10)
	check("b: pizza 2", srv.count(2), 5)
	check("b: pizza 2 points are its own", srv.pizzas[2].strokes[1][1].y, 0.2)

	-- c. Undo before anything is sent: nothing goes out.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(6) do
		box.place(p)
	end
	box.release()
	box.undo(1)
	flush(1)
	check("c: nothing sent", #srv.log, 0)
	check("c: nothing visible", #box.visible(1), 0)

	-- d. Undo after a partial send: the rest never reappears; a later stroke is kept.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(12) do
		box.place(p)
	end
	box.tick(0) -- 8 sent, 4 queued
	box.undo(1)
	flush(1)
	check("d: server empty after undo", srv.count(1), 0)
	check("d: visible empty", #box.visible(1), 0)
	box.begin(1)
	for _, p in line(3) do
		box.place(p)
	end
	flush(1)
	check("d: later stroke kept", srv.count(1), 3)
	check("d: client and server agree", #box.visible(1), srv.count(1))

	-- e. Undo of an unsent stroke, then Next: only the earlier stroke is graded.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(5) do
		box.place(p)
	end
	flush(0.2)
	box.begin(1)
	for _, p in line(5, 0.3) do
		box.place(p)
	end
	box.undo(1)
	box.advance(1, "cheese")
	flush(1)
	check("e: server keeps stroke 1", srv.count(1), 5)
	check("e: visible stroke 1", #box.visible(1), 5)
	check("e: step advanced", srv.pizzas[1].step, "done")

	-- f. Next while still holding, with a batch unsent.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(9) do
		box.place(p)
	end
	box.advance(1, "cheese")
	flush(1)
	check("f: all 9 reached the server", srv.count(1), 9)
	check("f: Next last", srv.log[#srv.log], "advancePrep:1")

	-- g. A reversal through the outbox passes the server's spacing check.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in run({ { x = 0, y = 0 }, { x = 0.125, y = 0 }, { x = -0.5, y = 0 }, { x = 0.4, y = 0.1 } }) do
		box.place(p)
	end
	box.release()
	flush(1)
	check("g: reversal accepted", srv.count(1), #box.visible(1))

	-- h. A refusal drops that pizza's queue only.
	srv, box, flush = harness()
	srv.pizzas[1] = { strokes = {}, step = "sauce" }
	box.begin(1)
	for _, p in line(10) do
		box.place(p)
	end
	box.focus(2)
	box.begin(2)
	for _, p in line(4) do
		box.place(p)
	end
	flush(1)
	check("h: refused pizza dropped locally", #box.visible(1), 0)
	check("h: nothing reached the refused pizza", srv.count(1), 0)
	check("h: other pizza kept", srv.count(2), 4)

	-- i. Undo on another ticket never touches the queued pizza; the cap holds.
	srv, box, flush = harness()
	box.begin(1)
	for _, p in line(10) do
		box.place(p)
	end
	box.focus(2)
	check("i: undo on an empty pizza", box.undo(2), false)
	flush(1)
	check("i: pizza 1 intact", srv.count(1), 10)
	box.begin(1)
	local placed = 0
	for i = 1, 60 do
		if box.place({ x = 0, y = 0 }) then
			placed += 1
		end
	end
	check("i: cap 48 in all", #box.visible(1), 48)
	check("i: batches never exceed 8", srv.biggest <= 8, true)
end

-- 12. A refused cheese batch changes nothing (Astra r13 item 3).
do
	local srv = server()
	local function send(points, newStroke)
		return srv.receive({ action = "addCheese", args = { pizzaId = 1, points = points, newStroke = newStroke } })
	end
	check("j: first batch accepted", send({ { x = 0, y = 0 }, { x = 0.2, y = 0 } }, true), true)
	local function snapshot()
		local p = srv.pizzas[1]
		local flat = {}
		for si, st in p.strokes do
			for _, pt in st do
				table.insert(flat, string.format("%d:%.6f,%.6f", si, pt.x, pt.y))
			end
		end
		return table.concat(flat, ";") .. "|strokes=" .. #p.strokes .. "|batches=" .. tostring(p.batches)
	end
	local before = snapshot()
	-- A batch whose own points are fine but whose join with the held stroke jumps 0.4.
	check("j: join jump refused", send({ { x = 0.6, y = 0 }, { x = 0.7, y = 0 } }, false), false)
	check("j: join jump: state unchanged", snapshot(), before)
	-- A batch that would pass the old append-then-check fixture's first points then fails late.
	check("j: late spacing failure refused", send({ { x = 0.3, y = 0 }, { x = 0.4, y = 0 }, { x = 0.9, y = 0 } }, false), false)
	check("j: late failure: state unchanged", snapshot(), before)
	check("j: NaN refused", send({ { x = 0 / 0, y = 0 } }, false), false)
	check("j: infinite refused", send({ { x = math.huge, y = 0 } }, true), false)
	check("j: out of reach refused", send({ { x = 2, y = 0 } }, true), false)
	check("j: empty refused", send({}, false), false)
	check("j: all refusals left state unchanged", snapshot(), before)
	check("j: refusal reasons", table.concat(srv.refusals, ","), "spacing,spacing,finite,finite,bounds,empty")
	-- A refused first batch on a pizza the server has not seen leaves no record of it.
	check("j: refused first batch refused", srv.receive({ action = "addCheese", args = { pizzaId = 9, points = { { x = 2, y = 0 } }, newStroke = true } }), false)
	check("j: refused first batch: no pizza record", srv.pizzas[9], nil)
	-- A refused batch at the cap leaves the count where it was.
	local cap = {}
	for i = 1, F.MAX_PINCHES do
		table.insert(cap, { x = 0, y = 0 })
	end
	check("j: over the cap refused", send(cap, true), false)
	check("j: cap refusal: state unchanged", snapshot(), before)
	-- The next good batch continues the same stroke in sequence.
	check("j: good batch after refusals accepted", send({ { x = 0.3, y = 0 } }, false), true)
	check("j: appended in order", srv.pizzas[1].strokes[1][3].x, 0.3)
	check("j: batches counted once", srv.pizzas[1].batches, 2)
	-- Simulates the old order (append, then check) on a plain list; it does not run the old fixture.
	local old = { { x = 0, y = 0 }, { x = 0.2, y = 0 } }
	for _, pt in { { x = 0.6, y = 0 } } do
		table.insert(old, pt)
	end
	check("j: append-then-check order keeps a refused point (simulated, not the old code)", F.strokeSpacingOk(old) == false and #old == 3, true)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("prep checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

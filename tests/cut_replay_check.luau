-- Replays the cut strokes recorded in Studio play on 2026-10-27 (slice 1 hand-off, play-event-log
-- .txt): the exact 48-or-fewer points the client sent, on three oval pizzas whose dough outlines
-- are rebuilt here from the same rolls the test hooks made. Each stroke is graded the way the
-- server grades it (Scoring.cutPath on the pizza's own footprint), and each pizza's layout the
-- way serve does (Scoring.cut on that footprint); the round-crust rule (S omitted) is shown beside
-- it for comparison. The points came from Studio MCP injected mouse drags, not Lawson's real
-- mouse. Run offline with tests/offline/run.py, or in Studio Edit after a sync.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local G = require(Shared.PrepGeometry)

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

-- The 2026-10-27 roll model (PrepGeometry.roll until 2026-10-28: one stroke stretched the dough
-- along itself only, by up to 35 %, tapered from 0.85 to the 1.1 cap in 16 parts). The pizzas
-- below were rolled under it in play, so their outlines are rebuilt with it, not the current one.
local function rollBefore(S: G.Mat2, p1: G.Vec, p2: G.Vec): G.Mat2?
	local dx, dy = p2.x - p1.x, p2.y - p1.y
	local len = math.sqrt(dx * dx + dy * dy)
	local chord = G.chordInside(S, p1, p2)
	if len < 1e-9 or chord <= 0 then
		return nil
	end
	local u = { x = dx / len, y = dy / len }
	local cover = math.clamp(chord / (2 * G.radiusAlong(S, u)), 0, 1)
	local part = (1 + 0.35 * cover) ^ (1 / 16) - 1
	for _ = 1, 16 do
		local k = part * math.clamp((1.1 - G.radiusAlong(S, u)) / (1.1 - 0.85), 0, 1)
		local AS = G.mul(G.mat(1 + k * u.x * u.x, k * u.x * u.y, k * u.x * u.y, 1 + k * u.y * u.y), S)
		local e = G.ellipseOf(AS)
		S = G.shape(math.min(e.major, 1.1), math.min(e.minor, 1.1), e.angle)
	end
	return S
end

-- The dough each pizza was rolled to in play (the debug hook rolled full-width strokes at these
-- angles, through the server's own validateRoll).
local ROLLS = {
	[3] = { 30, 30, 30, 120, 30, 30, 120, 30 }, -- ticket 1, pepperoni, 8 slices: oval turned 30 degrees
	[4] = { 0, 0, 0, 0, 90, 0, 0, 0 }, -- ticket 2, garden, 6 slices: long oval
	[6] = { 140, 140, 140, 50, 140, 140, 50, 140 }, -- ticket 5, half & half, 4 slices: oval turned -40 degrees
}
local SLICES = { [3] = 8, [4] = 6, [6] = 4 }
local footprint = {}
for id, rolls in ROLLS do
	local S = G.ball()
	for _, deg in rolls do
		local a = math.rad(deg)
		S = assert(rollBefore(S, { x = -1.2 * math.cos(a), y = -1.2 * math.sin(a) }, { x = 1.2 * math.cos(a), y = 1.2 * math.sin(a) }), "roll missed")
	end
	footprint[id] = S
end
-- The outlines match what the play snapshot reported (to the 4 decimals it printed).
local function near4(S: G.Mat2, a: number, b: number, d: number): boolean
	return math.abs(S.a - a) < 1e-4 and math.abs(S.b - b) < 1e-4 and math.abs(S.d - d) < 1e-4
end
check("pizza 3 outline", near4(footprint[3], 0.9809, 0.1980, 0.7522), true)
check("pizza 4 outline", near4(footprint[4], 1.0988, 0.0000, 0.4725), true)
check("pizza 6 outline", near4(footprint[6], 0.9063, -0.2252, 0.8268), true)

-- The sent paths, in the order they were cut (angle = the trace's fitted frame angle).
local SENT = {
	{ pizza = 4, angle = 90.0, path = { P(0.0000, -0.7500), P(0.0000, -0.7088), P(0.0000, -0.6743), P(0.0000, -0.6331), P(0.0000, -0.5976), P(0.0000, -0.5618), P(0.0000, -0.5205), P(0.0000, -0.4865), P(0.0000, -0.4453), P(0.0000, -0.4094), P(0.0000, -0.3737), P(0.0000, -0.3323), P(0.0000, -0.2981), P(0.0000, -0.2570), P(0.0000, -0.2224), P(0.0000, -0.1882), P(0.0000, -0.1470), P(0.0000, -0.1120), P(0.0000, -0.0690), P(0.0000, -0.0345), P(0.0000, 0.0000), P(0.0000, 0.0413), P(0.0000, 0.0764), P(0.0000, 0.1191), P(0.0000, 0.1539), P(0.0000, 0.1882), P(0.0000, 0.2293), P(0.0000, 0.2638), P(0.0000, 0.3048), P(0.0000, 0.3394), P(0.0000, 0.3737), P(0.0000, 0.4166), P(0.0000, 0.4521), P(0.0000, 0.4931), P(0.0000, 0.5275), P(0.0000, 0.5618), P(0.0000, 0.6048), P(0.0000, 0.6401), P(0.0000, 0.6814), P(0.0000, 0.7157), P(0.0000, 0.7500) } },
	{ pizza = 4, angle = -166.0, path = { P(1.2124, 0.3011), P(1.1606, 0.2888), P(1.1090, 0.2763), P(1.0576, 0.2627), P(1.0062, 0.2489), P(0.9545, 0.2367), P(0.9028, 0.2244), P(0.8511, 0.2118), P(0.7995, 0.1991), P(0.7481, 0.1856), P(0.6966, 0.1724), P(0.6449, 0.1600), P(0.5932, 0.1477), P(0.5415, 0.1351), P(0.4900, 0.1222), P(0.4385, 0.1088), P(0.3871, 0.0955), P(0.3354, 0.0830), P(0.2837, 0.0705), P(0.2320, 0.0583), P(0.1804, 0.0454), P(0.1291, 0.0315), P(0.0776, 0.0184), P(0.0259, 0.0061), P(-0.0259, -0.0061), P(-0.0776, -0.0184), P(-0.1291, -0.0315), P(-0.1804, -0.0454), P(-0.2320, -0.0583), P(-0.2837, -0.0705), P(-0.3354, -0.0830), P(-0.3871, -0.0955), P(-0.4385, -0.1088), P(-0.4900, -0.1223), P(-0.5415, -0.1351), P(-0.5932, -0.1477), P(-0.6449, -0.1600), P(-0.6966, -0.1723), P(-0.7481, -0.1856), P(-0.7995, -0.1991), P(-0.8511, -0.2118), P(-0.9028, -0.2244), P(-0.9545, -0.2367), P(-1.0062, -0.2489), P(-1.0576, -0.2627), P(-1.1090, -0.2763), P(-1.1606, -0.2888), P(-1.2124, -0.3011) } },
	{ pizza = 4, angle = -14.0, path = { P(-1.2124, 0.3011), P(-1.1606, 0.2888), P(-1.1090, 0.2763), P(-1.0576, 0.2627), P(-1.0062, 0.2489), P(-0.9545, 0.2367), P(-0.9028, 0.2244), P(-0.8511, 0.2118), P(-0.7995, 0.1991), P(-0.7481, 0.1856), P(-0.6966, 0.1724), P(-0.6449, 0.1600), P(-0.5932, 0.1477), P(-0.5415, 0.1351), P(-0.4900, 0.1222), P(-0.4385, 0.1088), P(-0.3871, 0.0955), P(-0.3354, 0.0830), P(-0.2837, 0.0705), P(-0.2320, 0.0583), P(-0.1804, 0.0454), P(-0.1291, 0.0315), P(-0.0776, 0.0184), P(-0.0259, 0.0061), P(0.0259, -0.0061), P(0.0776, -0.0184), P(0.1291, -0.0315), P(0.1804, -0.0454), P(0.2320, -0.0583), P(0.2837, -0.0705), P(0.3354, -0.0830), P(0.3871, -0.0955), P(0.4385, -0.1088), P(0.4900, -0.1223), P(0.5415, -0.1351), P(0.5932, -0.1477), P(0.6449, -0.1600), P(0.6966, -0.1723), P(0.7481, -0.1856), P(0.7995, -0.1991), P(0.8511, -0.2118), P(0.9028, -0.2244), P(0.9545, -0.2367), P(1.0062, -0.2489), P(1.0576, -0.2627), P(1.1090, -0.2763), P(1.1606, -0.2888), P(1.2124, -0.3011) } },
	{ pizza = 3, angle = 11.4, path = { P(-1.2742, -0.2581), P(-1.2200, -0.2469), P(-1.1658, -0.2359), P(-1.1116, -0.2250), P(-1.0573, -0.2141), P(-1.0031, -0.2030), P(-0.9489, -0.1920), P(-0.8947, -0.1811), P(-0.8404, -0.1702), P(-0.7862, -0.1591), P(-0.7320, -0.1480), P(-0.6778, -0.1372), P(-0.6235, -0.1263), P(-0.5694, -0.1151), P(-0.5151, -0.1041), P(-0.4609, -0.0933), P(-0.4067, -0.0823), P(-0.3525, -0.0712), P(-0.2983, -0.0602), P(-0.2440, -0.0493), P(-0.1898, -0.0384), P(-0.1356, -0.0273), P(-0.0814, -0.0163), P(-0.0271, -0.0054), P(0.0271, 0.0054), P(0.0814, 0.0163), P(0.1356, 0.0273), P(0.1898, 0.0384), P(0.2440, 0.0493), P(0.2983, 0.0602), P(0.3525, 0.0712), P(0.4067, 0.0823), P(0.4609, 0.0933), P(0.5151, 0.1041), P(0.5694, 0.1151), P(0.6235, 0.1263), P(0.6778, 0.1372), P(0.7320, 0.1480), P(0.7862, 0.1591), P(0.8404, 0.1702), P(0.8947, 0.1811), P(0.9489, 0.1919), P(1.0031, 0.2030), P(1.0573, 0.2141), P(1.1116, 0.2250), P(1.1658, 0.2359), P(1.2200, 0.2469), P(1.2742, 0.2581) } },
	{ pizza = 3, angle = -141.1, path = { P(1.0134, 0.8172), P(0.9704, 0.7823), P(0.9274, 0.7474), P(0.8843, 0.7126), P(0.8412, 0.6778), P(0.7981, 0.6430), P(0.7550, 0.6082), P(0.7120, 0.5733), P(0.6690, 0.5383), P(0.6258, 0.5036), P(0.5826, 0.4690), P(0.5389, 0.4348), P(0.4954, 0.4006), P(0.4523, 0.3658), P(0.4094, 0.3307), P(0.3669, 0.2952), P(0.3241, 0.2601), P(0.2804, 0.2259), P(0.2369, 0.1916), P(0.1938, 0.1568), P(0.1507, 0.1220), P(0.1077, 0.0870), P(0.0647, 0.0522), P(0.0216, 0.0174), P(-0.0216, -0.0174), P(-0.0647, -0.0522), P(-0.1077, -0.0870), P(-0.1507, -0.1220), P(-0.1938, -0.1568), P(-0.2369, -0.1916), P(-0.2804, -0.2259), P(-0.3241, -0.2601), P(-0.3669, -0.2952), P(-0.4094, -0.3308), P(-0.4523, -0.3658), P(-0.4954, -0.4006), P(-0.5389, -0.4348), P(-0.5826, -0.4689), P(-0.6258, -0.5036), P(-0.6690, -0.5383), P(-0.7120, -0.5733), P(-0.7550, -0.6082), P(-0.7981, -0.6430), P(-0.8412, -0.6778), P(-0.8843, -0.7126), P(-0.9274, -0.7474), P(-0.9704, -0.7823), P(-1.0134, -0.8172) } },
	{ pizza = 3, angle = 75.3, path = { P(-0.2742, -1.0403), P(-0.2618, -0.9962), P(-0.2497, -0.9521), P(-0.2387, -0.9077), P(-0.2275, -0.8632), P(-0.2154, -0.8191), P(-0.2034, -0.7749), P(-0.1920, -0.7306), P(-0.1806, -0.6862), P(-0.1683, -0.6421), P(-0.1565, -0.5979), P(-0.1455, -0.5535), P(-0.1342, -0.5091), P(-0.1220, -0.4650), P(-0.1100, -0.4208), P(-0.0988, -0.3764), P(-0.0872, -0.3321), P(-0.0749, -0.2880), P(-0.0631, -0.2437), P(-0.0523, -0.1993), P(-0.0409, -0.1549), P(-0.0285, -0.1109), P(-0.0168, -0.0666), P(-0.0056, -0.0222), P(0.0056, 0.0222), P(0.0167, 0.0666), P(0.0286, 0.1108), P(0.0409, 0.1549), P(0.0522, 0.1993), P(0.0631, 0.2438), P(0.0750, 0.2880), P(0.0873, 0.3321), P(0.0988, 0.3764), P(0.1099, 0.4208), P(0.1220, 0.4650), P(0.1344, 0.5091), P(0.1455, 0.5535), P(0.1563, 0.5980), P(0.1683, 0.6421), P(0.1807, 0.6862), P(0.1921, 0.7306), P(0.2034, 0.7749), P(0.2154, 0.8191), P(0.2274, 0.8633), P(0.2387, 0.9077), P(0.2495, 0.9522), P(0.2618, 0.9962), P(0.2742, 1.0403) } },
	{ pizza = 3, angle = -35.3, path = { P(-0.9866, 0.6989), P(-0.9451, 0.6685), P(-0.9034, 0.6384), P(-0.8609, 0.6093), P(-0.8184, 0.5803), P(-0.7764, 0.5506), P(-0.7346, 0.5206), P(-0.6930, 0.4903), P(-0.6513, 0.4601), P(-0.6087, 0.4313), P(-0.5664, 0.4020), P(-0.5249, 0.3716), P(-0.4833, 0.3414), P(-0.4413, 0.3116), P(-0.3991, 0.2821), P(-0.3566, 0.2532), P(-0.3143, 0.2239), P(-0.2728, 0.1934), P(-0.2311, 0.1633), P(-0.1892, 0.1335), P(-0.1472, 0.1038), P(-0.1050, 0.0743), P(-0.0629, 0.0447), P(-0.0210, 0.0149), P(0.0210, -0.0149), P(0.0629, -0.0447), P(0.1050, -0.0743), P(0.1472, -0.1038), P(0.1892, -0.1335), P(0.2312, -0.1633), P(0.2728, -0.1934), P(0.3143, -0.2239), P(0.3566, -0.2532), P(0.3992, -0.2821), P(0.4413, -0.3116), P(0.4833, -0.3414), P(0.5249, -0.3716), P(0.5664, -0.4021), P(0.6087, -0.4313), P(0.6513, -0.4601), P(0.6930, -0.4903), P(0.7345, -0.5207), P(0.7764, -0.5506), P(0.8184, -0.5803), P(0.8609, -0.6093), P(0.9034, -0.6383), P(0.9451, -0.6685), P(0.9866, -0.6989) } },
	{ pizza = 6, angle = 5.3, path = { P(-1.2849, -0.1183), P(-1.2303, -0.1128), P(-1.1756, -0.1076), P(-1.1209, -0.1033), P(-1.0661, -0.0991), P(-1.0115, -0.0936), P(-0.9569, -0.0881), P(-0.9022, -0.0825), P(-0.8476, -0.0772), P(-0.7928, -0.0731), P(-0.7381, -0.0686), P(-0.6835, -0.0632), P(-0.6288, -0.0578), P(-0.5742, -0.0523), P(-0.5195, -0.0473), P(-0.4647, -0.0431), P(-0.4100, -0.0386), P(-0.3554, -0.0331), P(-0.3007, -0.0276), P(-0.2461, -0.0220), P(-0.1914, -0.0170), P(-0.1367, -0.0129), P(-0.0820, -0.0082), P(-0.0273, -0.0027), P(0.0273, 0.0027), P(0.0820, 0.0082), P(0.1367, 0.0129), P(0.1914, 0.0170), P(0.2461, 0.0220), P(0.3007, 0.0276), P(0.3554, 0.0331), P(0.4100, 0.0386), P(0.4647, 0.0431), P(0.5195, 0.0472), P(0.5742, 0.0523), P(0.6288, 0.0578), P(0.6835, 0.0632), P(0.7381, 0.0687), P(0.7928, 0.0731), P(0.8476, 0.0772), P(0.9022, 0.0825), P(0.9569, 0.0881), P(1.0115, 0.0936), P(1.0661, 0.0991), P(1.1209, 0.1033), P(1.1756, 0.1076), P(1.2303, 0.1128), P(1.2849, 0.1183) } },
	{ pizza = 6, angle = -58.6, path = { P(-0.5887, 0.9624), P(-0.5634, 0.9216), P(-0.5380, 0.8808), P(-0.5124, 0.8402), P(-0.4868, 0.7996), P(-0.4621, 0.7585), P(-0.4374, 0.7173), P(-0.4127, 0.6761), P(-0.3880, 0.6350), P(-0.3633, 0.5938), P(-0.3383, 0.5528), P(-0.3127, 0.5122), P(-0.2872, 0.4715), P(-0.2625, 0.4303), P(-0.2378, 0.3892), P(-0.2131, 0.3480), P(-0.1882, 0.3069), P(-0.1629, 0.2662), P(-0.1374, 0.2255), P(-0.1117, 0.1849), P(-0.0865, 0.1441), P(-0.0618, 0.1029), P(-0.0371, 0.0618), P(-0.0124, 0.0206), P(0.0124, -0.0206), P(0.0371, -0.0618), P(0.0618, -0.1029), P(0.0865, -0.1441), P(0.1117, -0.1849), P(0.1374, -0.2255), P(0.1629, -0.2662), P(0.1882, -0.3069), P(0.2131, -0.3480), P(0.2378, -0.3892), P(0.2625, -0.4303), P(0.2872, -0.4715), P(0.3127, -0.5122), P(0.3383, -0.5528), P(0.3633, -0.5938), P(0.3880, -0.6350), P(0.4127, -0.6761), P(0.4374, -0.7173), P(0.4621, -0.7585), P(0.4868, -0.7996), P(0.5124, -0.8402), P(0.5380, -0.8808), P(0.5634, -0.9216), P(0.5887, -0.9624) } },
}

-- Two strokes the client refused before sending (their paths were not logged; rebuilt here as the
-- straight scripted drags from the logged start points).
local bare = { P(-0.901, 0.750), P(0.901, 0.750) } -- pizza 4, across the board below the oval
local short = { P(-0.148, -0.024), P(0.121, 0.030) } -- pizza 3, a short tap-drag near the middle

local _, bareWhy = Scoring.cutPath(bare, footprint[4])
check("bare-board drag on pizza 4 refused", bareWhy, "cut missed the pizza")
local _, shortWhy = Scoring.cutPath(short, footprint[3])
check("short drag on pizza 3 refused", shortWhy, "cut too short")
local roundBare = Scoring.cutPath(bare)

local lines = { [3] = {}, [4] = {}, [6] = {} }
local roundLines = { [3] = {}, [4] = {}, [6] = {} }
for i, s in SENT do
	local cut, why = Scoring.cutPath(s.path, footprint[s.pizza])
	check(string.format("stroke %d (pizza %d) accepted", i, s.pizza), cut ~= nil, true)
	if cut then
		-- The trace printed 1.000; resampling leaves the ends a hair inside on some strokes.
		check(string.format("stroke %d complete", i), cut.completeness > 0.999, true)
		check(string.format("stroke %d fitted angle matches the trace", i), math.abs(math.deg(math.atan2(cut.y2 - cut.y1, cut.x2 - cut.x1)) - s.angle) < 0.05, true)
		-- The stored chord ends on the dough's own edge: 0.95 S^-1 of each end has length 0.95.
		local q1 = G.toDough(footprint[s.pizza], { x = cut.x1, y = cut.y1 })
		local q2 = G.toDough(footprint[s.pizza], { x = cut.x2, y = cut.y2 })
		check(string.format("stroke %d ends on the dough edge", i), math.abs(math.sqrt(q1.x ^ 2 + q1.y ^ 2) - 0.95) < 1e-6 and math.abs(math.sqrt(q2.x ^ 2 + q2.y ^ 2) - 0.95) < 1e-6, true)
		table.insert(lines[s.pizza], cut)
	else
		table.insert(failures, string.format("stroke %d refused: %s", i, tostring(why)))
	end
	local rc = Scoring.cutPath(s.path)
	if rc then
		table.insert(roundLines[s.pizza], rc)
	end
end

-- The served Cut grades seen on the result cards: 100 on each pizza.
local played = { [3] = 100, [4] = 100, [6] = 100 }
table.insert(report, "| Pizza | Slices | Strokes sent | Cut (own dough) | Cut (round-crust rule, S omitted) | Bare-board drag, round rule |")
table.insert(report, "|---|---|---|---|---|---|")
for _, id in { 4, 3, 6 } do
	local g = Scoring.cut(SLICES[id], lines[id], footprint[id])
	local r = Scoring.cut(SLICES[id], roundLines[id])
	check(string.format("pizza %d Cut grade matches the result card", id), g.score, played[id])
	table.insert(report, string.format("| %d | %d | %d | %d | %d (%s) | %s |", id, SLICES[id], #lines[id], g.score, r.score, table.concat(r.notes, "; "),
		if id == 4 then (if roundBare then "accepted, complete " .. string.format("%.2f", roundBare.completeness) else "refused") else "-"))
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cut replay checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

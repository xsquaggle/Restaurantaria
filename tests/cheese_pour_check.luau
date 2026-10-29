-- Cheese: choosing the shaker is separate from pouring (Lawson 2026-10-28, real mouse: the
-- cheese poured all over the table as soon as the drag left the bowl; Astra r19 R19-03). The
-- Make station now picks the shaker up with a tap or drag on the bowl, which pours nothing, and
-- pours only during a fresh press on the board (MakeCheese.pour). Deterministic pointer paths
-- on a full round dough (dough-local = pizza-local), sent through the server's own batch check
-- (MakeCheese.validate / add). The "before" rows replay the slice 6 rule (a press on the bowl
-- sprinkled along the whole drag, PrepFood.sampler, kept within PINCH_REACH) and are checked as
-- showing the fault. The three proofs of Astra's shaker rule (even, large miss, heavy pile) are
-- recorded with the current grade, which slice 7a leaves alone (its count and spread terms let a
-- pile or a ring score high: Lawson's call, see the hand-off).

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local PrepFood = require(Shared.PrepFood)
local MakeCheese = require(Shared.MakeCheese)
local MakeDough = require(Shared.MakeDough)

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
local function note(line: string)
	table.insert(report, line)
end

local has = type(MakeCheese.pour) == "function"
check("the pour is shared logic (MakeCheese.pour)", has, true)
check("proposal: flow time", Config.Cheese.flowTime, 0.15)

local EDGE = MakeDough.BOARD_EDGE
local DT = 1 / 60
local function P(x: number, y: number)
	return { x = x, y = y }
end
local function walk(path: { any }, to: any, step: number)
	local from = path[#path]
	local dx, dy = to.x - from.x, to.y - from.y
	local n = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / step))
	for i = 1, n do
		table.insert(path, P(from.x + dx * i / n, from.y + dy * i / n))
	end
end
local function onBoard(q: any): boolean
	return q.x * q.x + q.y * q.y <= EDGE * EDGE
end

-- One held pour after the shaker was chosen: the pointer visits `path` one sample a frame, then
-- stays still for `still` seconds; returns the pinches, in order.
local function pourAlong(path: { any }, still: number?): { any }
	local out = {}
	if not has then
		return out
	end
	local pour = MakeCheese.pour()
	local now = 0
	local function add(list: { any })
		for _, p in list do
			table.insert(out, p)
		end
	end
	add(pour.press(path[1], onBoard(path[1]), now))
	for i = 2, #path do
		now += DT
		add(pour.move(path[i], onBoard(path[i]), now))
		add(pour.tick(now))
	end
	local stop = now + (still or 0)
	while now < stop - 1e-9 do
		now += DT
		add(pour.tick(now))
	end
	return out
end

-- Stores pinches as the station sends them: batches of batchSize through the server's check.
local function store(strokes: { { any } }): (any, number)
	local cheese = { strokes = {} }
	local refused = 0
	for _, stroke in strokes do
		local first = true
		local i = 1
		while i <= #stroke do
			local batch = {}
			while #batch < Config.Cheese.batchSize and i <= #stroke do
				table.insert(batch, stroke[i])
				i += 1
			end
			local clean, newStroke = MakeCheese.validate(cheese, { newStroke = first, points = batch })
			if clean then
				MakeCheese.add(cheese, clean, newStroke)
				first = false
			else
				refused += 1
			end
		end
	end
	return cheese, refused
end

------------------------------------------------------------------------------------------
-- 1. Choosing and carrying the shaker pours nothing. The bowl sits left of the board (pizza-local
-- x = -2.4); the drag carries it across the table onto the pizza and sweeps it.

local carryPath = { P(-2.4, 0.2) }
walk(carryPath, P(-0.9, 0), 0.05)
walk(carryPath, P(0.6, 0.3), 0.05)
-- Before (slice 6): the press on the bowl started the sprinkle, so it poured along the way.
local before = {}
do
	local sampler = PrepFood.sampler()
	for _, q in carryPath do
		for _, p in sampler.feed(q) do
			if p.x * p.x + p.y * p.y <= PrepFood.PINCH_REACH ^ 2 then
				table.insert(before, p)
			end
		end
	end
end
local beforeOff = 0
for _, p in before do
	if p.x * p.x + p.y * p.y > 0.95 * 0.95 then
		beforeOff += 1
	end
end
check("before (slice 6): the carry poured on the table", beforeOff > 0, true)
-- After: the carry is not a pour at all (the station never makes one for it); a pour whose press
-- lands off the board pours nothing, and dragging it onto the pizza does not start it.
local fromBowl = pourAlong(carryPath)
check("after: a press off the board pours nothing, even dragged onto the pizza", #fromBowl, 0)
note(string.format("carry from the bowl across the table: before %d pinches (%d off the dough); after 0", #before, beforeOff))

------------------------------------------------------------------------------------------
-- 2. Held still, it keeps pouring by time: one pinch at the press, then one every flowTime.

local still = pourAlong({ P(0.2, -0.1) }, 2.0)
check("held still 2 s: one pinch at the press plus one every 0.15 s", #still, 1 + math.floor(2.0 / Config.Cheese.flowTime + 1e-9))
local samePlace = true
for _, p in still do
	if p.x ~= 0.2 or p.y ~= -0.1 then
		samePlace = false
	end
end
check("held still: every pinch lands under the shaker", samePlace, true)

-- A stalled frame adds one pinch, never a catch-up burst.
if has then
	local pour = MakeCheese.pour()
	local n = #pour.press(P(0, 0), true, 0)
	n += #pour.tick(1.0)
	check("a one-second stall adds one pinch, not six", n, 2)
end

------------------------------------------------------------------------------------------
-- 3. Leaving the board ends the pour; coming back needs a fresh press.

local out = { P(0, 0) }
walk(out, P(1.3, 0), 0.05)
walk(out, P(0.2, 0.2), 0.05)
local leaving = pourAlong(out)
local afterLeave = 0
for _, p in leaving do
	if p.x * p.x + p.y * p.y > EDGE * EDGE then
		afterLeave += 1
	end
end
check("leaving the board: nothing lands past its edge", afterLeave, 0)
check("leaving the board: the pour stopped (only the way out poured)", #leaving <= math.ceil(EDGE / PrepFood.PINCH_STEP) + 2, true)
note(string.format("press at the centre, out past the board and back: %d pinches, all on the way out", #leaving))

------------------------------------------------------------------------------------------
-- 4. Every pour the server would accept: 200 seeded sweeps with pauses, stored through the
-- server's batch check, none refused.

local seed = 777
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local refusedTotal, pinchTotal = 0, 0
for _ = 1, 200 do
	local path = { P((rand() - 0.5) * 1.2, (rand() - 0.5) * 1.2) }
	for _ = 1, 1 + math.floor(rand() * 4) do
		walk(path, P((rand() - 0.5) * 1.6, (rand() - 0.5) * 1.6), 0.01 + rand() * 0.08)
		for _ = 1, math.floor(rand() * 20) do
			table.insert(path, path[#path]) -- a pause, held still
		end
	end
	local pinches = pourAlong(path)
	local cheese, refused = store({ pinches })
	refusedTotal += refused
	pinchTotal += MakeCheese.count(cheese)
	check("random pour: spacing as the server checks", PrepFood.strokeSpacingOk(pinches), true)
end
check("random pours: no batch refused by the server", refusedTotal, 0)
note(string.format("200 random held pours: %d pinches stored, %d batches refused", pinchTotal, refusedTotal))

------------------------------------------------------------------------------------------
-- 5. Astra's shaker-rule proofs (10-28 17:05): even, a large miss, a heavy pile. Recorded with
-- the current grade and an independent footprint coverage: the share of a fine grid over the
-- edible area (radius 0.84) within PINCH_RADIUS of a pinch.

local function coverage(pinches: { any }): number
	local hit, total = 0, 0
	for y = -0.84, 0.84, 0.03 do
		for x = -0.84, 0.84, 0.03 do
			if x * x + y * y <= 0.84 * 0.84 then
				total += 1
				for _, p in pinches do
					if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= PrepFood.PINCH_RADIUS ^ 2 then
						hit += 1
						break
					end
				end
			end
		end
	end
	return hit / total
end
-- Even: a held spiral sweep from the middle out to the sauce edge.
local spiral = { P(0, 0) }
for i = 1, 300 do
	local t = i / 300
	local r = 0.08 + 0.72 * t
	local a = t * 2 * math.pi * 3.2
	table.insert(spiral, P(r * math.cos(a), r * math.sin(a)))
end
-- Large miss: the same kind of sweep over the left half only.
local half = { P(-0.1, -0.7) }
for i = 1, 6 do
	walk(half, P(if i % 2 == 1 then -0.75 else -0.15, -0.7 + 0.25 * i), 0.02)
end
-- Heavy pile: a short sweep, then held still for 3 s in one spot.
local pile = { P(0.3, 0.1) }
walk(pile, P(0.4, 0.15), 0.02)
local proofs = {
	{ "even", pourAlong(spiral) },
	{ "large miss (left half)", pourAlong(half) },
	{ "heavy pile (3 s still)", pourAlong(pile, 3.0) },
}
note("proof                      pinches  inside  spread  footprint coverage  Cheese grade  notes")
local grades = {}
for _, proof in proofs do
	local cheese, refused = store({ proof[2] })
	check(proof[1] .. ": stored without refusals", refused, 0)
	local g = MakeCheese.grade(cheese)
	local cov = coverage(MakeCheese.pinches(cheese))
	grades[proof[1]] = { g = g, cov = cov }
	note(string.format("%-26s %7d  %6d  %6.3f  %18.3f  %12d  %s", proof[1], g.detail.pinches, g.detail.inside, g.detail.spread, cov, g.score, table.concat(g.notes, " / ")))
end
if has then
	check("proofs: the miss covers less than the even pour", grades["large miss (left half)"].cov < grades["even"].cov, true)
	check("proofs: the pile covers less than the even pour", grades["heavy pile (3 s still)"].cov < grades["even"].cov, true)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("cheese pour checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

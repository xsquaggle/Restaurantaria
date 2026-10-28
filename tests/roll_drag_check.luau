-- Rolling with a held pointer (Lawson, 2026-10-28, real mouse in Play: "it spins around,
-- alternates oval and round, the roller spins too"; he wants three smooth, consistent swipes to
-- roll it out). Deterministic pointer paths, sampled the way the client samples them, are played
-- through the drag logic of the build Lawson tried (replicated below from the Make station as it
-- was: one press-to-release stroke whose direction came from the press point, the pin turned to
-- that direction, the dough art turned to the oval's long axis, the old roll model) and through
-- the shared logic the station uses now (MakeDough.rollDrag, MakeDough.pinTurn,
-- PrepGeometry.steadyEllipse, the three-pass roll model). The "before" rows are expected to show
-- the reported faults and are checked as such; the "after" rows must not. Synthetic paths, not
-- Lawson's mouse: a real-mouse try is still owed. Run offline with tests/offline/run.py, or in
-- Studio Edit after a sync.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local G = require(Shared.PrepGeometry)
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
local function near(name: string, got: number?, want: number, tol: number?)
	if type(got) == "number" and math.abs(got - want) <= (tol or 1e-6) then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %.6f (+-%g)", name, tostring(got), want, tol or 1e-6))
	end
end
local function note(line: string)
	table.insert(report, line)
end

local cfg = Config.Make
check("proposal: roll lock", cfg.rollLock, 0.12)
check("proposal: roll turn", cfg.rollTurn, 0.1)

-- Shortest turn between two drawn rotations (degrees): an image turned a full turn looks the same.
local function turnGap(a: number, b: number): number
	local d = (b - a) % 360
	return math.min(d, 360 - d)
end

------------------------------------------------------------------------------------------
-- The build Lawson played (before 2026-10-28), replicated.

-- PrepGeometry.roll as it was: along the stroke only, up to 35 %, tapered from 0.85 to 1.1.
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
local function shapeBefore(strokes: { any }): G.Mat2
	local S = G.ball()
	for _, l in strokes do
		S = rollBefore(S, { x = l.x1, y = l.y1 }, { x = l.x2, y = l.y2 }) or S
	end
	return S
end

export type Run = {
	strokes: number,
	mean: number,
	round: number,
	shrinks: number, -- samples where the drawn dough got smaller than the sample before
	pinJump: number, -- largest pin turn between two samples (degrees)
	pinFlips: number, -- pin turns of 90 degrees or more between two samples
	artJump: number, -- largest dough-art turn between two samples (degrees)
	artTravel: number, -- total dough-art turning over the whole run (degrees)
	artError: number, -- largest drawn-outline error (px) against the scored dough
}

local FRAME = 400 -- a desktop pizza frame (px); the phone's is 190

-- holds: a list of pointer paths, one per press-to-release (pizza-local samples).
local function playBefore(holds: { { G.Vec } }): Run
	local strokes = {}
	local run = { strokes = 0, mean = 0, round = 0, shrinks = 0, pinJump = 0, pinFlips = 0, artJump = 0, artTravel = 0, artError = 0 }
	local lastMean, lastPin, lastArt = nil, nil, nil
	for _, path in holds do
		local from = path[1]
		local to = from
		local moved = false
		for i = 1, #path do
			to = path[i]
			local dx, dy = to.x - from.x, to.y - from.y
			local S = shapeBefore(strokes)
			if math.sqrt(dx * dx + dy * dy) > 0.02 then
				moved = true
				local pin = math.deg(math.atan2(dy, dx)) + 90
				if lastPin then
					local gap = turnGap(lastPin, pin)
					run.pinJump = math.max(run.pinJump, gap)
					if gap >= 90 then
						run.pinFlips += 1
					end
				end
				lastPin = pin
			end
			if moved then
				S = rollBefore(S, from, to) or S
			end
			local e = G.ellipseOf(G.viewMatrix(S, FRAME))
			local mean = (e.major + e.minor) / 2
			if lastMean and mean < lastMean - 1e-9 then
				run.shrinks += 1
			end
			lastMean = mean
			local art = math.deg(e.angle)
			if lastArt then
				local gap = turnGap(lastArt, art)
				run.artJump = math.max(run.artJump, gap)
				run.artTravel += gap
			end
			lastArt = art
		end
		local dx, dy = to.x - from.x, to.y - from.y
		if moved and dx * dx + dy * dy >= cfg.minStroke ^ 2 and rollBefore(shapeBefore(strokes), from, to) then
			table.insert(strokes, { x1 = from.x, y1 = from.y, x2 = to.x, y2 = to.y })
		end
	end
	local e = G.axes(shapeBefore(strokes))
	run.strokes, run.mean, run.round = #strokes, (e.major + e.minor) / 2, e.minor / e.major
	return run
end

------------------------------------------------------------------------------------------
-- The station now: the same steps the Make station takes per pointer sample.

local function playAfter(holds: { { G.Vec } }, frame: number?): Run
	local F = frame or FRAME
	local make = MakeDough.new()
	make.placed = true
	local run = { strokes = 0, mean = 0, round = 0, shrinks = 0, pinJump = 0, pinFlips = 0, artJump = 0, artTravel = 0, artError = 0 }
	local lastMean, lastPin, lastArt = nil, nil, nil
	local artTurn = 0
	local pin = -12 -- the pin's rest turn
	local function commit(l: any)
		if l and (l.x2 - l.x1) ^ 2 + (l.y2 - l.y1) ^ 2 >= cfg.minStroke ^ 2 and MakeDough.validateRoll(make, l) then
			table.insert(make.strokes, l)
		end
	end
	local function draw(drag: any)
		local S = MakeDough.shape(make)
		local open = drag and drag.line()
		if open then
			S = G.roll(S, { x = open.x1, y = open.y1 }, { x = open.x2, y = open.y2 }) or S
		end
		local exact = G.ellipseOf(G.viewMatrix(S, F))
		local drawn, err = G.steadyEllipse(exact, artTurn, 1)
		artTurn = drawn.angle
		run.artError = math.max(run.artError, err)
		local mean = (exact.major + exact.minor) / 2
		if lastMean and mean < lastMean - 1e-9 then
			run.shrinks += 1
		end
		lastMean = mean
		local art = math.deg(drawn.angle)
		if lastArt then
			local gap = turnGap(lastArt, art)
			run.artJump = math.max(run.artJump, gap)
			run.artTravel += gap
		end
		lastArt = art
	end
	for _, path in holds do
		local drag = MakeDough.rollDrag(path[1])
		for i = 1, #path do
			commit(drag.move(path[i]))
			if drag.axis then
				local target = MakeDough.pinTurn(drag.axis, pin)
				local gap = turnGap(pin, target)
				run.pinJump = math.max(run.pinJump, gap)
				if gap >= 90 then
					run.pinFlips += 1
				end
				pin = target
			end
			draw(drag)
		end
		commit(drag.close())
		draw(nil)
	end
	local e = G.axes(MakeDough.shape(make))
	run.strokes, run.mean, run.round = #make.strokes, (e.major + e.minor) / 2, e.minor / e.major
	return run
end

------------------------------------------------------------------------------------------
-- Pointer paths. A real mouse at 60 Hz moving a swipe of about a third of a second gives a
-- sample every 0.03 to 0.06 pizza-local units; hands wobble sideways and tremble at the press.
-- Deterministic: the wobble is a fixed sine mix, the press tremor a fixed list.

local TREMOR = { { x = 0.006, y = -0.004 }, { x = -0.009, y = 0.007 }, { x = 0.004, y = 0.012 }, { x = -0.012, y = -0.006 } }

local function swipe(path: { G.Vec }, from: G.Vec, to: G.Vec, step: number, wobble: number, phase: number)
	local dx, dy = to.x - from.x, to.y - from.y
	local len = math.sqrt(dx * dx + dy * dy)
	local nx, ny = -dy / len, dx / len
	local n = math.max(1, math.ceil(len / step))
	for i = 1, n do
		local t = i / n
		local w = wobble * (0.6 * math.sin(phase + 9.1 * t) + 0.4 * math.sin(phase * 1.7 + 23.3 * t))
		table.insert(path, { x = from.x + dx * t + nx * w, y = from.y + dy * t + ny * w })
	end
end
local function pressAt(p: G.Vec): { G.Vec }
	local path = { { x = p.x, y = p.y } }
	for _, t in TREMOR do
		table.insert(path, { x = p.x + t.x, y = p.y + t.y })
	end
	return path
end

-- A: Lawson's report, read literally: one hold pressed on the dough, the pin pushed up, pulled
-- down past where it was pressed, pushed up again.
local function backAndForth(step: number, wobble: number): { { G.Vec } }
	local top, bottom, press = { x = 0.03, y = -0.9 }, { x = -0.02, y = 0.9 }, { x = 0.04, y = 0.12 }
	local path = pressAt(press)
	swipe(path, press, top, step, wobble, 0.3)
	swipe(path, top, bottom, step, wobble, 1.9)
	swipe(path, bottom, top, step, wobble, 3.7)
	return { path }
end
-- A2: the same from the board's edge, so the press point is never crossed.
local function backAndForthFromEdge(step: number, wobble: number): { { G.Vec } }
	local top, bottom = { x = 0.03, y = -0.9 }, { x = -0.02, y = 0.9 }
	local path = pressAt(bottom)
	swipe(path, bottom, top, step, wobble, 0.3)
	swipe(path, top, bottom, step, wobble, 1.9)
	swipe(path, bottom, top, step, wobble, 3.7)
	return { path }
end
-- B: three separate swipes, each its own press and release, all the same way.
local function threeSwipes(step: number, wobble: number): { { G.Vec } }
	local holds = {}
	for k = 1, 3 do
		local from, to = { x = -0.05 + 0.03 * k, y = 0.92 }, { x = 0.04 - 0.02 * k, y = -0.92 }
		local path = pressAt(from)
		swipe(path, from, to, step, wobble, k * 1.3)
		table.insert(holds, path)
	end
	return holds
end
-- C: a sloppier hand: one hold, diagonal swipes that curve and overshoot the board side.
local function sloppy(step: number, wobble: number): { { G.Vec } }
	local a, b, c = { x = -0.85, y = 0.7 }, { x = 0.8, y = -0.75 }, { x = -0.7, y = 0.85 }
	local path = pressAt(a)
	swipe(path, a, b, step, wobble, 0.8)
	swipe(path, b, c, step, wobble, 2.4)
	swipe(path, c, { x = 0.85, y = -0.6 }, step, wobble, 4.1)
	return { path }
end

local function row(name: string, r: Run)
	note(string.format("%-34s rolls %d, mean %.3f, short/long %.3f, shrinks %d, pin jump %.1f deg (%d flips), art jump %.1f deg, art travel %.0f deg, outline error %.2f px",
		name, r.strokes, r.mean, r.round, r.shrinks, r.pinJump, r.pinFlips, r.artJump, r.artTravel, r.artError))
end

for _, case in {
	{ name = "A back and forth, one hold", holds = backAndForth },
	{ name = "A2 back and forth from the edge", holds = backAndForthFromEdge },
	{ name = "B three separate swipes", holds = threeSwipes },
	{ name = "C sloppy diagonals, one hold", holds = sloppy },
} do
	for _, sampling in { { step = 0.03, wobble = 0.012, label = "fine" }, { step = 0.06, wobble = 0.03, label = "coarse" } } do
		local holds = case.holds(sampling.step, sampling.wobble)
		local label = case.name .. " (" .. sampling.label .. ")"
		local before = playBefore(holds)
		local after = playAfter(holds)
		row("before: " .. label, before)
		row("after:  " .. label, after)
		-- Before: the faults Lawson reported show up on the replica (A is the hold he described).
		if case.name:sub(1, 2) == "A " then
			check("before " .. label .. ": the pin flips round", before.pinFlips > 0, true)
			check("before " .. label .. ": the dough art spins", before.artJump >= 90, true)
		end
		if case.name:sub(1, 1) == "A" then
			check("before " .. label .. ": the dough shrinks back while held", before.shrinks > 0, true)
			check("before " .. label .. ": one roll at most is kept", before.strokes <= 1, true)
		end
		check("before " .. label .. ": three swipes leave it short of full size", before.mean < cfg.sizeFullLow, true)
		-- After: three passes kept, full size and round enough, nothing shrinks or flips.
		check("after " .. label .. ": three rolls kept", after.strokes, 3)
		check("after " .. label .. ": full size", after.mean >= cfg.sizeFullLow and after.mean <= cfg.sizeFullHigh, true)
		check("after " .. label .. ": round enough", after.round >= cfg.roundFull, true)
		check("after " .. label .. ": the dough never shrinks back", after.shrinks, 0)
		check("after " .. label .. ": the pin never flips", after.pinFlips, 0)
		check("after " .. label .. ": the outline stays within 1 px", after.artError <= 1 + 1e-9, true)
	end
end

-- The back-and-forth hold on the phone's frame (190 px): same rolls, art steadier still.
local phone = playAfter(backAndForth(0.03, 0.012), 190)
row("after:  A on the phone frame", phone)
check("after A phone: three rolls kept", phone.strokes, 3)
check("after A phone: the outline stays within 1 px", phone.artError <= 1 + 1e-9, true)

------------------------------------------------------------------------------------------
-- The drag's own rules.

do
	-- No direction until the pointer has gone rollLock from the press; then it points along.
	local d = MakeDough.rollDrag({ x = 0, y = 0.8 })
	check("drag: no pass before the lock", d.move({ x = 0, y = 0.8 - 0.11 }), nil)
	check("drag: no line before the lock", d.line(), nil)
	d.move({ x = 0, y = 0.8 - 0.13 })
	near("drag: locked upwards", d.axis and d.axis.y or 0, -1, 1e-9)
	-- Going further moves the far end (along the fixed direction); jitter back under rollTurn
	-- ends nothing.
	d.move({ x = 0, y = -0.5 })
	check("drag: back 0.09 keeps the pass", d.move({ x = 0, y = -0.41 }), nil)
	local l = d.line() :: any
	near("drag: the open pass reaches its farthest point", l.y2, -0.5, 1e-9)
	-- Back 0.1 or more: the pass ends at its farthest point and the next starts there.
	local ended = d.move({ x = 0, y = -0.39 }) :: any
	check("drag: back 0.11 ends the pass", ended ~= nil, true)
	near("drag: the ended pass runs press to turn (start)", ended.y1, 0.8, 1e-9)
	near("drag: the ended pass runs press to turn (end)", ended.y2, -0.5, 1e-9)
	check("drag: the next pass has no direction yet", d.axis, nil)
	d.move({ x = 0, y = 0.6 })
	local back = d.close() :: any
	near("drag: the next pass starts at the turn", back.y1, -0.5, 1e-9)
	near("drag: and runs back down", back.y2, 0.6, 1e-9)
	check("drag: closed", d.line(), nil)
	-- Off to the side without going further also ends a pass (an L-shaped drag is two passes).
	local s = MakeDough.rollDrag({ x = 0, y = 0.6 })
	s.move({ x = 0, y = -0.4 })
	local side = s.move({ x = 0.12, y = -0.4 })
	check("drag: a sideways turn ends the pass", side ~= nil, true)
end

do
	-- The pin lies across the pass: level for an upward pass, kept when the pass reverses, and
	-- never turned past 135 degrees from level (its light stays on top).
	near("pin: upward pass from rest", MakeDough.pinTurn({ x = 0, y = -1 }, -12), 0, 1e-9)
	near("pin: the pass back down keeps it", MakeDough.pinTurn({ x = 0, y = 1 }, 0), 0, 1e-9)
	near("pin: a sideways pass stands it up", math.abs(MakeDough.pinTurn({ x = 1, y = 0 }, 0)), 90, 1e-9)
	local worst = 0
	local turn = -12
	for k = 0, 720 do
		local a = math.rad(k * 7.3)
		turn = MakeDough.pinTurn({ x = math.cos(a), y = math.sin(a) }, turn)
		worst = math.max(worst, math.abs(turn))
	end
	check("pin: never past 135 degrees from level", worst <= MakeDough.PIN_LIMIT + 1e-9, true)
end

do
	-- steadyEllipse: the drawn outline is the scored one within the tolerance, for any turn
	-- asked for. Checked on the radial distance (at least the distance between the outlines).
	local function radius(e: G.Ellipse, psi: number): number
		local c, s = math.cos(psi - e.angle), math.sin(psi - e.angle)
		return 1 / math.sqrt(c * c / (e.major * e.major) + s * s / (e.minor * e.minor))
	end
	local worst, cases = 0, 0
	for i = 1, 60 do
		local b = 40 + (i * 37) % 160
		local a = b + ({ 0.2, 0.8, 1.5, 4, 12, 40 })[(i % 6) + 1]
		local exact = { major = a, minor = b, angle = math.rad((i * 53) % 180) }
		for j = 0, 11 do
			local turn = math.rad(j * 31 - 170)
			local drawn, err = G.steadyEllipse(exact, turn, 1)
			local gap = 0
			for k = 0, 359 do
				local psi = math.rad(k)
				gap = math.max(gap, math.abs(radius(drawn, psi) - radius(exact, psi)))
			end
			worst = math.max(worst, gap - err)
			check("steady: within 1 px " .. i .. "/" .. j, gap <= 1 + 1e-6, true)
			cases += 1
		end
	end
	note(string.format("steadyEllipse: %d cases, the measured gap never exceeds its stated bound by more than %.2g px", cases, worst))
	check("steady: the stated bound holds", worst <= 1e-6, true)
	-- Nearly round: the art keeps its turn exactly.
	local round, _ = G.steadyEllipse({ major = 100.5, minor = 100, angle = math.rad(70) }, math.rad(5), 1)
	near("steady: a nearly round dough keeps the art's turn", round.angle, math.rad(5), 1e-12)
	-- A clear oval at 88 degrees asked for turn 0: the nearest drawing is the 90-degree
	-- equivalent at -2 degrees (axes swapped), turned back towards 0 by no more than the 1 px
	-- allows: asin(1 / (60 x 160 / 100)) = 0.597 degrees.
	local oval, _ = G.steadyEllipse({ major = 160, minor = 100, angle = math.rad(88) }, 0, 1)
	near("steady: a clear oval is drawn on its axes", math.deg(oval.angle), -2 + math.deg(math.asin(1 / 96)), 1e-9)
	near("steady: drawn along the short side there", oval.major, 100, 1e-12)
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("roll drag checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

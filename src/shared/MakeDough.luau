--!strict
-- The Make tab's dough steps (Lawson, 2026-10-26): flour the board, pull the dough onto it and
-- roll it. Pure functions shared by the server (authoritative), the client (the live preview
-- while a stroke is held) and the tests. Constants are Config.Make's proposals.
--
-- Stored on a pizza as make = { step, flour, placed, strokes }:
--   step     "dough" while flouring, placing and rolling; "toppings" once the dough is done
--   flour    the committed flour strokes, each a list of pizza-local dust stamps
--   placed   the dough ball is on the board (it always lands in the centre)
--   strokes  the committed rolls, { x1, y1, x2, y2 } pizza-local press and release points
-- The dough's shape comes from the strokes alone (PrepGeometry.doughShape), so the grade and
-- every drawing of the dough read the same oval.

local Config = require(script.Parent.Config)
local G = require(script.Parent.PrepGeometry)

local MakeDough = {}

export type Vec = { x: number, y: number }
export type Line = { x1: number, y1: number, x2: number, y2: number }
export type Make = { step: string, flour: { { Vec } }, placed: boolean, strokes: { Line } }
export type Grade = { score: number, notes: { string }, detail: any? }

local function finite(v: any, limit: number): boolean
	return type(v) == "number" and v == v and v >= -limit and v <= limit
end

function MakeDough.new(): Make
	return { step = "dough", flour = {}, placed = false, strokes = {} }
end

function MakeDough.stampCount(make: Make): number
	local n = 0
	for _, stroke in make.flour do
		n += #stroke
	end
	return n
end

-- The dough's current outline matrix (the ball until a roll lands).
function MakeDough.shape(make: Make): G.Mat2
	return G.doughShape(make.strokes)
end

-- Which part of the dough step the player is on: "flour" (nothing on the board yet), "dough"
-- (floured, the ball not pulled yet), "roll" (the ball is on the board) or "done".
function MakeDough.phase(make: Make): string
	if make.step ~= "dough" then
		return "done"
	elseif make.placed then
		return "roll"
	elseif #make.flour > 0 then
		return "dough"
	end
	return "flour"
end

------------------------------------------------------------------------------------------
-- Flour

-- Dust stamps along a held drag: one at the press point, then one at every exact flourStep of
-- travel along the straight segments between pointer samples, so equal physical drags give
-- equal stamps whatever the event rate. feed(p) takes the next pointer sample (pizza-local)
-- and returns the stamps it placed.
export type Sampler = { feed: (Vec) -> { Vec } }

function MakeDough.flourSampler(): Sampler
	local step = Config.Make.flourStep
	local last: Vec? = nil
	local carried = 0 -- travel since the last stamp
	local function feed(p: Vec): { Vec }
		local out = {}
		local from = last
		if not from then
			last = { x = p.x, y = p.y }
			table.insert(out, { x = p.x, y = p.y })
			return out
		end
		local dx, dy = p.x - from.x, p.y - from.y
		local len = math.sqrt(dx * dx + dy * dy)
		local walked = 0
		while carried + (len - walked) >= step - 1e-9 do
			walked += step - carried
			carried = 0
			local t = walked / len
			table.insert(out, { x = from.x + dx * t, y = from.y + dy * t })
		end
		carried += len - walked
		last = { x = p.x, y = p.y }
		return out
	end
	return { feed = feed }
end

-- Checks one flour stroke before anything is stored: 1 to flourMaxPerStroke finite stamps on
-- the board, consecutive stamps at most flourStep apart (a chord is never longer than the arc
-- the sampler walked), and the pizza's stamp cap. Returns the clean copy to store.
function MakeDough.validateFlour(make: Make, points: any): ({ Vec }?, string?)
	local cfg = Config.Make
	if make.step ~= "dough" then
		return nil, "dough is done"
	end
	if make.placed then
		return nil, "the dough is already on the board"
	end
	if type(points) ~= "table" or #points < 1 or #points > cfg.flourMaxPerStroke then
		return nil, "bad flour stroke"
	end
	local clean = {}
	for i = 1, #points do
		local p = points[i]
		if type(p) ~= "table" or not finite(p.x, cfg.flourReach) or not finite(p.y, cfg.flourReach) then
			return nil, "flour off the board"
		end
		if p.x * p.x + p.y * p.y > cfg.flourReach * cfg.flourReach then
			return nil, "flour off the board"
		end
		local prev = clean[#clean]
		if prev and (p.x - prev.x) ^ 2 + (p.y - prev.y) ^ 2 > (cfg.flourStep + 1e-6) ^ 2 then
			return nil, "flour stamps too far apart"
		end
		table.insert(clean, { x = p.x, y = p.y })
	end
	if MakeDough.stampCount(make) + #clean > cfg.flourMaxStamps then
		return nil, "too much flour"
	end
	return clean, nil
end

-- Frozen sample of the unit disc: the centre and rings of 6, 12, 18 and 24 points at the radii
-- that give each point an equal share of the area (sqrt((before + n / 2) / 61)), each ring
-- turned half a step from the last. 61 points.
MakeDough.SAMPLE = {} :: { Vec }
do
	table.insert(MakeDough.SAMPLE, { x = 0, y = 0 })
	local before = 1
	for ring, n in { 6, 12, 18, 24 } do
		local r = math.sqrt((before + n / 2) / 61)
		local turn = (ring % 2) * math.pi / n
		for k = 0, n - 1 do
			local a = turn + k * 2 * math.pi / n
			table.insert(MakeDough.SAMPLE, { x = r * math.cos(a), y = r * math.sin(a) })
		end
		before += n
	end
end

-- Share of the dough's area (shape S) that lies on flour: each sample point of the unit disc,
-- mapped onto the dough's outline, counts when a stamp's disc covers it.
function MakeDough.flourCoverage(make: Make, S: G.Mat2): number
	local r2 = Config.Make.flourRadius ^ 2
	local covered = 0
	for _, u in MakeDough.SAMPLE do
		local p = G.apply(S, u)
		local hit = false
		for _, stroke in make.flour do
			for _, s in stroke do
				if (p.x - s.x) ^ 2 + (p.y - s.y) ^ 2 <= r2 then
					hit = true
					break
				end
			end
			if hit then
				break
			end
		end
		if hit then
			covered += 1
		end
	end
	return covered / #MakeDough.SAMPLE
end

------------------------------------------------------------------------------------------
-- Dough

function MakeDough.validateRoll(make: Make, args: any): (Line?, string?)
	local cfg = Config.Make
	if make.step ~= "dough" then
		return nil, "dough is done"
	end
	if not make.placed then
		return nil, "no dough on the board"
	end
	if #make.strokes >= cfg.maxStrokes then
		return nil, "too many rolls"
	end
	for _, k in { "x1", "y1", "x2", "y2" } do
		if not finite(args[k], cfg.strokeReach) then
			return nil, "roll out of range"
		end
	end
	local line = { x1 = args.x1, y1 = args.y1, x2 = args.x2, y2 = args.y2 }
	if (line.x2 - line.x1) ^ 2 + (line.y2 - line.y1) ^ 2 < cfg.minStroke ^ 2 then
		return nil, "roll too short"
	end
	if not G.roll(MakeDough.shape(make), { x = line.x1, y = line.y1 }, { x = line.x2, y = line.y2 }) then
		return nil, "roll missed the dough"
	end
	return line, nil
end

-- Ready for the next step: the dough is on the board and rolled at least once. A minimum only;
-- it says nothing about quality.
function MakeDough.canFinish(make: Make): boolean
	return make.step == "dough" and make.placed and #make.strokes > 0
end

local function ramp(v: number, zero: number, full: number): number
	return math.clamp((v - zero) / (full - zero), 0, 1)
end

-- The Dough score: roll (half size, half roundness) and flour under the finished dough, weighed
-- by flourWeight. detail keeps every part for feedback.
function MakeDough.grade(make: Make): Grade
	local cfg = Config.Make
	local notes = {}
	if not make.placed then
		return { score = 0, notes = { "No dough on the board" }, detail = { roll = 0, flour = 0 } }
	end
	local S = MakeDough.shape(make)
	local e = G.axes(S)
	local mean = (e.major + e.minor) / 2
	local size = if mean < cfg.sizeFullLow then ramp(mean, cfg.sizeZeroLow, cfg.sizeFullLow)
		elseif mean > cfg.sizeFullHigh then 1 - ramp(mean, cfg.sizeFullHigh, cfg.sizeZeroHigh)
		else 1
	local roundness = e.minor / e.major
	local round = ramp(roundness, cfg.roundZero, cfg.roundFull)
	local roll = 100 * (0.5 * size + 0.5 * round)
	local coverage = MakeDough.flourCoverage(make, S)
	local flour = 100 * ramp(coverage, cfg.flourCoverZero, cfg.flourCoverFull)
	local score = math.floor((1 - cfg.flourWeight) * roll + cfg.flourWeight * flour + 0.5 + 1e-9)
	if mean < cfg.sizeFullLow then
		table.insert(notes, "Dough too small")
	elseif mean > cfg.sizeFullHigh then
		table.insert(notes, "Dough too big and thin")
	end
	if roundness < cfg.roundFull then
		table.insert(notes, "Dough uneven")
	end
	if coverage < cfg.flourCoverFull then
		table.insert(notes, "Flour the whole board first")
	end
	return {
		score = score,
		notes = notes,
		detail = {
			roll = roll,
			flour = flour,
			size = size,
			round = round,
			coverage = coverage,
			stamps = MakeDough.stampCount(make),
			strokes = #make.strokes,
			major = e.major,
			minor = e.minor,
			meanRadius = mean,
			-- The oval's area over the full-size circle's (plan rev 6, 5.3c), kept for the final
			-- grade step; no ceiling is applied here.
			completeness = e.major * e.minor / (G.CRUST * G.CRUST),
		},
	}
end

return MakeDough

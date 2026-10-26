--!strict
-- Pure grading functions shared by server (authoritative) and client (previews, tests).
-- Pizza-local coordinates are normalized: centre (0, 0), crust edge radius 1, x right, y down.

local Config = require(script.Parent.Config)
local MakeDough = require(script.Parent.MakeDough)
local Recipes = require(script.Parent.Recipes)

export type Piece = { ingredient: string, x: number, y: number }
export type Line = { x1: number, y1: number, x2: number, y2: number }
export type Point = { x: number, y: number }
-- A committed cut: its best-fit chord (x1..y2, across the crust), the dragged path it came from
-- and that path's grades (0..1). Lines without grades (test hooks) count as straight and full.
export type Cut = Line & { path: { Point }?, straightness: number?, completeness: number? }
export type Grade = { score: number, notes: { string }, detail: any? }

local Scoring = {}

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

local function inRegion(region: string, x: number): boolean
	if region == "left" then
		return x < 0
	elseif region == "right" then
		return x >= 0
	end
	return true
end

-- Sector index used to judge spread: quadrants for a whole pizza, top/bottom for a half.
local function sectorOf(region: string, x: number, y: number): number
	if region == "whole" then
		return (if x < 0 then 0 else 1) + (if y < 0 then 0 else 2) + 1
	end
	return if y < 0 then 1 else 2
end

local REGION_WORDS = { left = "the left half", right = "the right half", whole = "the whole pizza" }

function Scoring.toppings(recipe: Recipes.Recipe, pieces: { Piece }): Grade
	local notes = {}
	local required: { [string]: boolean } = {}
	local total, weight = 0, 0

	for _, req in recipe.toppings do
		required[req.ingredient] = true
		local info = Recipes.Ingredients[req.ingredient]
		local inside, outside = 0, 0
		local sectors = if req.region == "whole" then 4 else 2
		local perSector = table.create(sectors, 0)
		for _, piece in pieces do
			if piece.ingredient == req.ingredient then
				if inRegion(req.region, piece.x) then
					inside += 1
					local s = sectorOf(req.region, piece.x, piece.y)
					perSector[s] += 1
				else
					outside += 1
				end
			end
		end

		local countScore = clamp01(1 - math.abs(inside - req.count) / req.count)
		-- Spread judges only the pieces placed: 1 for the most even split those pieces allow,
		-- 0 for all in one sector. An empty pizza has no spread to credit.
		local spreadScore = 0
		if inside > 0 then
			local expected = inside / sectors
			local spreadError = 0
			for s = 1, sectors do
				spreadError += math.abs(perSector[s] - expected)
			end
			local r = inside % sectors
			local best = 2 * r * (sectors - r) / sectors
			local worst = 2 * inside * (1 - 1 / sectors)
			spreadScore = if worst > best then clamp01(1 - (spreadError - best) / (worst - best)) else 1
		end
		local outsidePenalty = outside / req.count
		total += clamp01(countScore * 0.6 + spreadScore * 0.4 - outsidePenalty * 0.5)
		weight += 1

		if inside ~= req.count then
			table.insert(notes, string.format("Needed %d %s on %s, placed %d", req.count, info.plural, REGION_WORDS[req.region], inside))
		end
		if outside > 0 then
			table.insert(notes, string.format("%d %s landed outside %s", outside, info.plural, REGION_WORDS[req.region]))
		end
		if inside >= 2 and spreadScore < 0.7 then
			local plural = info.plural:sub(1, 1):upper() .. info.plural:sub(2)
			table.insert(notes, string.format("%s were bunched instead of spread evenly", plural))
		end
	end

	local base = if weight > 0 then total / weight else 1
	local wrong = 0
	for _, piece in pieces do
		if not required[piece.ingredient] then
			wrong += 1
		end
	end
	if wrong > 0 then
		table.insert(notes, string.format("%d topping%s not on the order", wrong, if wrong == 1 then " was" else "s were"))
	end

	local score = math.clamp(base * 100 - wrong * Config.Topping.wrongIngredientPenalty, 0, 100)
	return { score = math.floor(score + 0.5), notes = notes }
end

-- The Make part of the order grade (proposal, 2026-10-26): the Dough score (flour inside it) and,
-- only when the ticket asks for toppings, the Toppings score, averaged. A cheese order is its
-- Dough score alone: no free topping score. Sauce and cheese are not graded until they are
-- hands-on. The order grade stays the four-part average with Make in Topping's place.
function Scoring.make(recipe: Recipes.Recipe, make: MakeDough.Make, pieces: { Piece }): Grade
	local dough = MakeDough.grade(make)
	local notes = table.clone(dough.notes)
	if #recipe.toppings == 0 then
		return { score = dough.score, notes = notes, detail = { dough = dough } }
	end
	local toppings = Scoring.toppings(recipe, pieces)
	for _, n in toppings.notes do
		table.insert(notes, n)
	end
	return { score = math.floor((dough.score + toppings.score) / 2 + 0.5), notes = notes, detail = { dough = dough, toppings = toppings } }
end

function Scoring.bakeState(target: number, seconds: number): string
	local cfg = Config.Oven
	local delta = seconds - target
	if seconds > cfg.burntAt then
		return "burnt"
	elseif math.abs(delta) <= cfg.perfectWindow then
		return "perfect"
	elseif delta < 0 then
		return "under"
	end
	return "over"
end

function Scoring.bake(bakeId: string, seconds: number): Grade
	local cfg = Config.Oven
	local target = cfg.targets[bakeId]
	local state = Scoring.bakeState(target, seconds)
	local delta = seconds - target
	local score
	if state == "burnt" then
		score = 0
	elseif state == "perfect" then
		score = 100
	else
		local over = math.abs(delta) - cfg.perfectWindow
		score = 100 * clamp01(1 - over / (cfg.zeroAt - cfg.perfectWindow))
	end
	local notes = {}
	if state == "burnt" then
		table.insert(notes, "Burnt")
	elseif state ~= "perfect" then
		table.insert(notes, string.format("Baked %.0fs %s %s", math.abs(delta), if delta < 0 then "short of" else "past", bakeId))
	end
	return { score = math.floor(score + 0.5), notes = notes }
end

local function lineAngleAndOffset(line: Line): (number, number)
	local dx, dy = line.x2 - line.x1, line.y2 - line.y1
	local len = math.sqrt(dx * dx + dy * dy)
	local offset = math.abs(dx * -line.y1 - dy * -line.x1) / math.max(len, 1e-6)
	local angle = math.deg(math.atan2(dy, dx)) % 180
	return angle, offset
end

-- Grades one freehand cut from its dragged path (cut coordinates: the pizza frame, frame edge
-- 1, crust at Config.Cut.crustRadius). Returns the cut to store, or nil and a refusal reason.
-- The server runs this on every cut it accepts; the client runs it to explain a refusal first.
-- Only the part of the path inside the crust is graded, since the wheel cuts nothing off the
-- pizza: the best-fit line (principal axis) of that part gives the chord, the widest distance
-- from it gives straightness, and the share of the chord the path spans gives completeness.
function Scoring.cutPath(points: any): (Cut?, string?)
	local cfg = Config.Cut
	if type(points) ~= "table" then
		return nil, "cut path missing"
	end
	local n = #points
	if n > cfg.maxPoints then
		return nil, "cut path too long"
	end
	-- A plain list only. Counting stops one past the length, so a table stuffed with extra keys
	-- costs at most maxPoints + 1 steps.
	local count = 0
	for _ in points do
		count += 1
		if count > n then
			break
		end
	end
	if n < 2 or count ~= n then
		return nil, "cut path missing"
	end
	local path: { Point } = table.create(n)
	for i = 1, n do
		local p = points[i]
		local x, y = if type(p) == "table" then p.x else nil, if type(p) == "table" then p.y else nil
		if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or math.abs(x) > 1.6 or math.abs(y) > 1.6 then
			return nil, "cut out of range"
		end
		path[i] = { x = x, y = y }
	end
	local total = 0
	for i = 2, n do
		total += math.sqrt((path[i].x - path[i - 1].x) ^ 2 + (path[i].y - path[i - 1].y) ^ 2)
	end
	if total < cfg.minDragLength then
		return nil, "cut too short"
	end

	-- Even samples along the path (at most about 2,000), keeping those inside the crust, plus
	-- the exact points where the path crosses the crust so a cut that reaches it spans fully.
	local R = cfg.crustRadius
	local step = math.max(0.01, total / 2000)
	-- Crust crossings count for span and distance but carry no weight in the fit, so they do
	-- not bias it towards the path's ends.
	local xs, ys, ws = {}, {}, {}
	local function keep(x: number, y: number, w: number)
		table.insert(xs, x)
		table.insert(ys, y)
		table.insert(ws, w)
	end
	local px, py = path[1].x, path[1].y
	local wasIn = px * px + py * py <= R * R
	if wasIn then
		keep(px, py, 1)
	end
	for i = 2, n do
		local a, b = path[i - 1], path[i]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		local k = math.max(1, math.ceil(len / step))
		for j = 1, k do
			local t = j / k
			local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
			local isIn = x * x + y * y <= R * R
			if isIn ~= wasIn then
				-- Where the short step from (px, py) to (x, y) meets the crust.
				local dx, dy = x - px, y - py
				local A, B, C = dx * dx + dy * dy, 2 * (px * dx + py * dy), px * px + py * py - R * R
				local root = math.sqrt(math.max(0, B * B - 4 * A * C))
				local u = if wasIn then (-B + root) / (2 * A) else (-B - root) / (2 * A)
				u = math.clamp(u, 0, 1)
				keep(px + dx * u, py + dy * u, 0)
			end
			if isIn then
				keep(x, y, 1)
			end
			px, py, wasIn = x, y, isIn
		end
	end
	if #xs < 3 then
		return nil, "cut missed the pizza"
	end

	-- Principal axis of the inside samples.
	local mx, my, wsum = 0, 0, 0
	for i = 1, #xs do
		mx += xs[i] * ws[i]
		my += ys[i] * ws[i]
		wsum += ws[i]
	end
	if wsum < 3 then
		return nil, "cut missed the pizza"
	end
	mx /= wsum
	my /= wsum
	local sxx, syy, sxy = 0, 0, 0
	for i = 1, #xs do
		local dx, dy = xs[i] - mx, ys[i] - my
		sxx += dx * dx * ws[i]
		syy += dy * dy * ws[i]
		sxy += dx * dy * ws[i]
	end
	local theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
	local ux, uy = math.cos(theta), math.sin(theta)
	-- Point the line the way the cutter travelled.
	if ux * (path[n].x - path[1].x) + uy * (path[n].y - path[1].y) < 0 then
		ux, uy = -ux, -uy
	end
	-- Closest point of the line to the centre, and the chord's half length across the crust.
	local along = mx * ux + my * uy
	local cx, cy = mx - ux * along, my - uy * along
	local d2 = cx * cx + cy * cy
	if d2 >= R * R then
		return nil, "cut missed the pizza"
	end
	local half = math.sqrt(R * R - d2)
	local lo, hi, dev = math.huge, -math.huge, 0
	for i = 1, #xs do
		local px, py = xs[i] - cx, ys[i] - cy
		local t = px * ux + py * uy
		lo = math.min(lo, t)
		hi = math.max(hi, t)
		dev = math.max(dev, math.abs(px * uy - py * ux))
	end
	local completeness = (math.clamp(hi, -half, half) - math.clamp(lo, -half, half)) / (2 * half)
	if completeness < cfg.minComplete then
		return nil, "cut doesn't cross the pizza"
	end
	local straightness = clamp01(1 - (dev - cfg.straightPerfect) / (cfg.straightZero - cfg.straightPerfect))
	return {
		x1 = cx - ux * half,
		y1 = cy - uy * half,
		x2 = cx + ux * half,
		y2 = cy + uy * half,
		path = path,
		straightness = straightness,
		completeness = completeness,
		deviation = dev,
	} :: any, nil
end

-- A dragged path with at most `max` points, evenly spaced along it (both ends kept). Paths
-- already within `max` points come back unchanged (copied).
function Scoring.resamplePath(points: { Point }, max: number): { Point }
	local out = {}
	if #points <= max then
		for _, p in points do
			table.insert(out, { x = p.x, y = p.y })
		end
		return out
	end
	local lens = { 0 }
	for i = 2, #points do
		lens[i] = lens[i - 1] + math.sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].y - points[i - 1].y) ^ 2)
	end
	local length = lens[#points]
	local seg = 1
	for k = 0, max - 1 do
		local target = if k == max - 1 then length else length * k / (max - 1)
		while seg < #points - 1 and lens[seg + 1] < target do
			seg += 1
		end
		local a, b = points[seg], points[seg + 1]
		local segLen = lens[seg + 1] - lens[seg]
		local t = if segLen < 1e-12 then 0 else math.clamp((target - lens[seg]) / segLen, 0, 1)
		table.insert(out, { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t })
	end
	return out
end

-- Credit for a cut's path: straightness times completeness credit (none at completeZero, full
-- from completeFull).
function Scoring.cutQuality(cut: Cut): (number, number, number)
	local cfg = Config.Cut
	local straight = cut.straightness or 1
	local complete = clamp01(((cut.completeness or 1) - cfg.completeZero) / (cfg.completeFull - cfg.completeZero))
	return straight * complete, straight, complete
end

function Scoring.cut(slices: number, lines: { Cut }): Grade
	local cfg = Config.Cut
	local notes = {}
	local needed = slices // 2
	if #lines == 0 then
		return { score = 0, notes = { "The pizza wasn't cut" } }
	end

	local angles = {}
	local offCentre = 0
	for _, line in lines do
		local angle, offset = lineAngleAndOffset(line)
		table.insert(angles, angle)
		if offset > cfg.centreTolerance then
			offCentre += 1
		end
	end
	table.sort(angles)

	local ideal = 180 / #angles
	local gapError = 0
	for i = 1, #angles do
		local nextAngle = if i < #angles then angles[i + 1] else angles[1] + 180
		gapError += math.abs((nextAngle - angles[i]) - ideal)
	end
	local meanError = gapError / #angles
	local evenScore = if #angles == 1
		then 1
		else clamp01(1 - (meanError - cfg.perfectDegrees) / (cfg.zeroDegrees - cfg.perfectDegrees))

	local countScore = clamp01(1 - math.abs(#lines - needed) / needed)
	local layout = clamp01(countScore * 0.5 + evenScore * 0.5 - offCentre * 0.25)
	-- Freehand: the layout score is scaled by the cuts' mean path credit, so crooked or
	-- partial cuts lower the grade. Each cut's parts are kept for feedback.
	local quality, crooked, short = 0, 0, 0
	local perCut = {}
	for _, line in lines do
		local q, straight, complete = Scoring.cutQuality(line)
		quality += q
		if straight < 0.75 then
			crooked += 1
		end
		if (line.completeness or 1) < 0.9 then
			short += 1
		end
		table.insert(perCut, {
			straight = math.floor(straight * 100 + 0.5),
			complete = math.floor((line.completeness or 1) * 100 + 0.5),
			credit = math.floor(q * 100 + 0.5),
		})
	end
	quality /= #lines
	local score = 100 * layout * quality
	if #lines ~= needed then
		score = math.min(score, 60)
		table.insert(notes, string.format("Cut into %d slices instead of %d", #lines * 2, slices))
	end
	if offCentre > 0 then
		table.insert(notes, string.format("%d cut%s missed the centre", offCentre, if offCentre == 1 then "" else "s"))
	end
	if #angles > 1 and meanError > cfg.perfectDegrees + 3 then
		table.insert(notes, "Slices were uneven sizes")
	end
	if crooked > 0 then
		table.insert(notes, string.format("%d cut%s wobbled off a straight line", crooked, if crooked == 1 then "" else "s"))
	end
	if short > 0 then
		table.insert(notes, string.format("%d cut%s stopped short of the crust", short, if short == 1 then "" else "s"))
	end
	return {
		score = math.floor(score + 0.5),
		notes = notes,
		detail = { layout = math.floor(layout * 100 + 0.5), path = math.floor(quality * 100 + 0.5), cuts = perCut },
	}
end

function Scoring.patienceFraction(arrivedAt: number, now: number): number
	return clamp01(1 - (now - arrivedAt) / Config.Patience.seconds)
end

function Scoring.patienceBand(fraction: number): string
	local cfg = Config.Patience
	if fraction > cfg.happy then
		return "happy"
	elseif fraction > cfg.neutral then
		return "neutral"
	elseif fraction > cfg.impatient then
		return "impatient"
	end
	return "grumpy"
end

function Scoring.wait(fraction: number): Grade
	local cfg = Config.Wait
	local score = if fraction >= cfg.fullScoreAbove
		then 100
		else cfg.floorScore + (100 - cfg.floorScore) * (fraction / cfg.fullScoreAbove)
	local notes = {}
	if score < 100 then
		table.insert(notes, "Waited longer than they liked")
	end
	return { score = math.floor(score + 0.5), notes = notes }
end

return Scoring

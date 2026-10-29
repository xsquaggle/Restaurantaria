--!strict
-- Pure grading functions shared by server (authoritative) and client (previews, tests).
-- Pizza-local coordinates are normalized: centre (0, 0), crust edge radius 1, x right, y down.

local Config = require(script.Parent.Config)
local MakeCheese = require(script.Parent.MakeCheese)
local MakeDough = require(script.Parent.MakeDough)
local MakeSauce = require(script.Parent.MakeSauce)
local PrepGeometry = require(script.Parent.PrepGeometry)
local Recipes = require(script.Parent.Recipes)

export type Piece = { ingredient: string, x: number, y: number }
export type Line = { x1: number, y1: number, x2: number, y2: number }
export type Point = { x: number, y: number }
-- A committed cut: its best-fit chord (x1..y2, across the crust), the dragged path it came from
-- and that path's grades (0..1). Lines without grades (test hooks) count as straight and full.
-- With the cutting assist on (CutStroke.grade), `path` is the assisted path and `raw` the samples
-- the client sent.
export type Cut = Line & { path: { Point }?, straightness: number?, completeness: number?, raw: { Point }?, assisted: boolean?, rawLine: Line?, rawStraightness: number?, rawCompleteness: number? }
export type Grade = { score: number, notes: { string }, detail: any? }

local Scoring = {}

local function clamp01(v: number): number
	return math.clamp(v, 0, 1)
end

-- The made pizza's footprint for cutting and toppings: its rolled dough outline S (pizza-local;
-- the outline is S applied to the unit circle, PrepGeometry), from the made dough record only,
-- never from the client. A pizza with no dough on the board (old fixtures, test lines) counts as
-- the full round crust, S = 0.95 I, so its grades are what they were before the footprint.
Scoring.ROUND = PrepGeometry.shape(PrepGeometry.CRUST, PrepGeometry.CRUST)

function Scoring.footprint(make: any?): PrepGeometry.Mat2
	if make and make.placed and type(make.strokes) == "table" then
		return MakeDough.shape(make)
	end
	return Scoring.ROUND
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

-- Pieces are dough-local (slice 1, 2026-10-27): S is the made pizza's dough (Scoring.footprint;
-- the full round crust when omitted, where dough-local and pizza-local agree). Halves and spread
-- sectors are what the player sees: each piece is judged by its physical place, toPizza(S, q)
-- (PrepGeometry: never by q.x, which a rotated oval can flip). A half split by a line through the
-- dough's centre is half its area on any oval.
-- detail.completeness is the lowest share, over the ticket's ingredients, of the right pieces
-- inside the asked region against the count (capped at 1; wrong and extra pieces never count);
-- detail.short names that ingredient (Scoring.makeCeilings turns it into a ceiling).
function Scoring.toppings(recipe: Recipes.Recipe, pieces: { Piece }, S: PrepGeometry.Mat2?): Grade
	local dough = S or Scoring.ROUND
	local notes = {}
	local required: { [string]: boolean } = {}
	local total, weight = 0, 0
	local completeness, short = 1, nil
	local seen: { [Piece]: Point } = {}
	for _, piece in pieces do
		seen[piece] = PrepGeometry.toPizza(dough, piece)
	end

	for _, req in recipe.toppings do
		required[req.ingredient] = true
		local info = Recipes.Ingredients[req.ingredient]
		local inside, outside = 0, 0
		local sectors = if req.region == "whole" then 4 else 2
		local perSector = table.create(sectors, 0)
		for _, piece in pieces do
			if piece.ingredient == req.ingredient then
				local p = seen[piece]
				if inRegion(req.region, p.x) then
					inside += 1
					local s = sectorOf(req.region, p.x, p.y)
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
		local share = math.min(1, inside / req.count)
		if share < completeness then
			completeness = share
			short = { ingredient = req.ingredient, count = req.count, inside = inside, region = req.region }
		end

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
	return { score = math.floor(score + 0.5), notes = notes, detail = { completeness = completeness, short = short } }
end

-- The Make part of the order grade (proposal, 2026-10-27): the mean of its graded steps, Dough
-- (flour inside it), Sauce, Cheese and, only when the ticket asks for toppings, Toppings. A
-- cheese order has no Toppings part: no free score. The step scores themselves are never changed.
-- Make also gathers the safeguard ceilings of its steps (plan rev 6, 5.3c and 5.3d): coverage of
-- the edible area for sauce and cheese, and, when Config.Grade.completeness is on, how much of
-- each was put on (pours / 3, pinches on the dough / 24, and the dough's area / the full round's
-- with doughCompleteness). Each is 35 at a quarter or less, none from three quarters. Where the
-- lowest one holds is Config.Grade.ceilingsOn: "order" the whole grade (Scoring.order), "make"
-- only this Make score (slice 2). detail.ceilings lists every ceiling under 100, lowest first.
export type Ceiling = { name: string, value: number, note: string }

local CEILING_WORDS = {
	sauceCover = "Most of the pizza has no sauce",
	cheeseCover = "Cheese bunched or missing",
	sauceAmount = "Not enough sauce poured",
	cheeseAmount = "Not enough cheese on the dough",
	dough = "Dough covers too little of the pan",
	toppings = "Toppings missing",
}
-- The order of the ceilings on a tie: the defect a player sees first.
local CEILING_ORDER = { "toppings", "sauceCover", "cheeseCover", "sauceAmount", "cheeseAmount", "dough" }

-- toppings (optional) is Scoring.toppings's grade for a ticket with toppings: with
-- Config.Grade.toppingCompleteness on, its detail.completeness sets the toppings ceiling, whose
-- note names the food first ("Needed 8 pepperoni on the whole pizza, placed 1").
function Scoring.makeCeilings(make: MakeDough.Make, dough: Grade, sauce: Grade, cheese: Grade, toppings: Grade?): { Ceiling }
	local cfg = Config.Grade
	local values: { [string]: number } = {
		sauceCover = sauce.detail.ceiling,
		cheeseCover = cheese.detail.ceiling,
	}
	local words = table.clone(CEILING_WORDS)
	if cfg.toppingCompleteness and toppings and toppings.detail then
		values.toppings = MakeSauce.ceiling(toppings.detail.completeness)
		local short = toppings.detail.short
		if short then
			words.toppings = string.format("Needed %d %s on %s, placed %d", short.count, Recipes.Ingredients[short.ingredient].plural, REGION_WORDS[short.region], short.inside)
		end
	end
	if cfg.completeness then
		-- Pours whose point is on the dough (dough-local radius 0.95), against the target.
		local pours = 0
		for _, a in (make.sauce or { actions = {} }).actions do
			if a.kind == "pour" and a.x * a.x + a.y * a.y <= 0.95 * 0.95 + 1e-9 then
				pours += 1
			end
		end
		values.sauceAmount = MakeSauce.ceiling(math.min(1, pours / Config.Sauce.targetPours))
		-- Pinches on the dough: on the sauce area and on the crust band together.
		values.cheeseAmount = MakeSauce.ceiling(math.min(1, (cheese.detail.inside + cheese.detail.crust) / 24))
		if cfg.doughCompleteness and dough.detail.completeness then
			values.dough = MakeSauce.ceiling(math.min(1, dough.detail.completeness))
		end
	end
	local list: { Ceiling } = {}
	for _, name in CEILING_ORDER do
		local v = values[name]
		if v and v < 100 then
			table.insert(list, { name = name, value = v, note = words[name] })
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		local ia, ib = table.find(CEILING_ORDER, a.name) :: number, table.find(CEILING_ORDER, b.name) :: number
		return ia < ib
	end)
	return list
end

function Scoring.make(recipe: Recipes.Recipe, make: MakeDough.Make, pieces: { Piece }): Grade
	local dough = MakeDough.grade(make)
	local sauce = MakeSauce.grade(make.sauce or { actions = {} })
	local cheese = MakeCheese.grade(make.cheese or { strokes = {} })
	local parts = { dough.score, sauce.score, cheese.score }
	local notes = {}
	local detail: any = { dough = dough, sauce = sauce, cheese = cheese }
	local toppings = nil
	if #recipe.toppings > 0 then
		toppings = Scoring.toppings(recipe, pieces, Scoring.footprint(make))
		table.insert(parts, toppings.score)
		detail.toppings = toppings
	end
	local sum = 0
	for _, v in parts do
		sum += v
	end
	local mean = math.floor(sum / #parts + 0.5 + 1e-9)
	local score = mean
	local ceilings = Scoring.makeCeilings(make, dough, sauce, cheese, toppings)
	-- "make": the lowest ceiling holds this score and its note goes first, naming the defect.
	-- "order": the score stays the mean; Scoring.order applies the ceiling to the grade.
	local low = ceilings[1]
	if Config.Grade.ceilingsOn == "make" and low and low.value < score then
		score = low.value
		table.insert(notes, string.format("%s: Make held to %d", low.note, low.value))
	end
	-- Then only the weakest step's notes (plan rev 6, 5): the lowest-scoring step that has any,
	-- the earlier step on a tie, so Make does not crowd Bake and Cut out of the result.
	local weakest: Grade? = nil
	for _, step in { dough, sauce, cheese, toppings } do
		if step and #step.notes > 0 and (weakest == nil or step.score < weakest.score) then
			weakest = step
		end
	end
	for _, n in if weakest then weakest.notes else {} do
		table.insert(notes, n)
	end
	detail.mean = mean
	detail.ceilings = ceilings
	return { score = score, notes = notes, detail = detail }
end

-- The order grade and its rewards (proposal, 2026-10-27; plan rev 6, 5.1 to 5.3 with the rev 7
-- amendment). Config.Grade.join:
--   "split":   Weighted = 0.5 Make + 0.3 Bake + 0.2 Cut (Lawson's provisional playtest weights);
--              Grade = Weighted held by the lowest Make ceiling (ceilingsOn "order") and by the
--              food's raw/burnt hold (Bake's detail.cap); Service (the wait score) is not in the
--              grade and not in XP: it is a 0.85-1.00 pay modifier before integer rounding,
--              Paid = round(Grade x (0.75 + 0.25 x Service / 100)); coins = round(12 x Paid / 100);
--              XP = round(10 x Grade / 100). With both roundings the final coin cut can exceed
--              15 % on small payouts. Still a proposal pending Lawson.
--   "average": Grade = the mean of Wait, Make, Bake and Cut (the earlier join), held the same
--              way; coins 12 x Grade / 100 and XP 10 x Grade / 100, as before.
-- Every part's score and notes are kept; `held` is the ceiling or hold that set the grade (nil
-- when none; name "food" for the raw/burnt hold) and its note leads the result's notes.
export type Order = { join: string, weighted: number, grade: number, paid: number, coins: number, xp: number, held: Ceiling?, service: number }

local function whole(x: number): number
	return math.floor(x + 0.5 + 1e-9)
end

function Scoring.order(wait: Grade, make: Grade, bake: Grade, cut: Grade): Order
	local cfg = Config.Grade
	local split = cfg.join == "split"
	local weighted = if split
		then whole(cfg.weights.make * make.score + cfg.weights.bake * bake.score + cfg.weights.cut * cut.score)
		else whole((wait.score + make.score + bake.score + cut.score) / 4)
	local grade = weighted
	local held: Ceiling? = nil
	local low = make.detail and make.detail.ceilings and make.detail.ceilings[1]
	if cfg.ceilingsOn == "order" and low and low.value < grade then
		grade = low.value
		held = low
	end
	-- Raw or burnt food (Scoring.bake's detail.cap, slice 1): holds the whole grade the same way.
	local food = bake.detail and bake.detail.cap
	if food and food < grade then
		grade = food
		held = { name = "food", value = food, note = bake.notes[1] or "Burnt" }
	end
	local paid = if split then whole(grade * (1 - cfg.serviceShare + cfg.serviceShare * wait.score / 100)) else grade
	return {
		join = cfg.join,
		weighted = weighted,
		grade = grade,
		paid = paid,
		coins = whole(Config.Rewards.baseTip * paid / 100),
		xp = whole(Config.Rewards.xpPerOrder * grade / 100),
		held = held,
		service = wait.score,
	}
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

-- The food's own state by bake time, whatever doneness was asked (Config.Oven, slice 1): "raw"
-- (up to rawUntil), "undercooked" (on the way to cooked), "cooked", "scorching" (past the latest
-- perfect window, on the way to burnt) or "burnt" (past burntAt).
function Scoring.foodState(seconds: number): string
	local cfg = Config.Oven
	if seconds > cfg.burntAt then
		return "burnt"
	elseif seconds > cfg.scorchFrom then
		return "scorching"
	elseif seconds >= cfg.cookedFrom then
		return "cooked"
	elseif seconds > cfg.rawUntil then
		return "undercooked"
	end
	return "raw"
end

-- The hold raw or burnt food puts on the order grade: 100 (none) while cooked, falling evenly to
-- foodCap at rawUntil and at burntAt, foodCap beyond. Continuous and monotonic on each side, so
-- the grade never jumps at a state boundary. Not rounded here (Scoring.order rounds the grade).
function Scoring.foodCap(seconds: number): number
	local cfg = Config.Oven
	local floor = cfg.foodCap
	if seconds <= cfg.rawUntil or seconds >= cfg.burntAt then
		return floor
	elseif seconds < cfg.cookedFrom then
		return floor + (100 - floor) * (seconds - cfg.rawUntil) / (cfg.cookedFrom - cfg.rawUntil)
	elseif seconds > cfg.scorchFrom then
		return floor + (100 - floor) * (cfg.burntAt - seconds) / (cfg.burntAt - cfg.scorchFrom)
	end
	return 100
end

local FOOD_WORDS = { raw = "Still raw", undercooked = "Undercooked", scorching = "Nearly burnt", burnt = "Burnt" }

-- The Bake score: how close the bake came to the ticket's doneness (100 inside the perfect
-- window, none at zeroAt away). With Config.Oven.foodCapOn (slice 1) that is all it measures;
-- the food's own state is detail.food and its hold is detail.cap (Scoring.foodCap, rounded),
-- which Scoring.order applies to the whole grade. With foodCapOn false it is today's rule:
-- burnt (past burntAt) scores 0 and nothing is held.
function Scoring.bake(bakeId: string, seconds: number): Grade
	local cfg = Config.Oven
	local target = cfg.targets[bakeId]
	local state = Scoring.bakeState(target, seconds)
	local delta = seconds - target
	local score
	if state == "burnt" and not cfg.foodCapOn then
		score = 0
	elseif state == "perfect" then
		score = 100
	else
		local over = math.abs(delta) - cfg.perfectWindow
		score = 100 * clamp01(1 - over / (cfg.zeroAt - cfg.perfectWindow))
	end
	local notes = {}
	local food = Scoring.foodState(seconds)
	local detail: any = { food = food, cap = 100 }
	if cfg.foodCapOn then
		local cap = math.floor(Scoring.foodCap(seconds) + 0.5 + 1e-9)
		detail.cap = cap
		-- The food first ("Burnt", "Still raw"), then how far from the asked doneness.
		if cap < 100 then
			table.insert(notes, FOOD_WORDS[food])
		end
		if food ~= "burnt" and food ~= "raw" and state ~= "perfect" then
			table.insert(notes, string.format("Baked %.0fs %s %s", math.abs(delta), if delta < 0 then "short of" else "past", bakeId))
		end
	elseif state == "burnt" then
		table.insert(notes, "Burnt")
	elseif state ~= "perfect" then
		table.insert(notes, string.format("Baked %.0fs %s %s", math.abs(delta), if delta < 0 then "short of" else "past", bakeId))
	end
	return { score = math.floor(score + 0.5), notes = notes, detail = detail }
end

local function lineAngleAndOffset(line: Line): (number, number)
	local dx, dy = line.x2 - line.x1, line.y2 - line.y1
	local len = math.sqrt(dx * dx + dy * dy)
	local offset = math.abs(dx * -line.y1 - dy * -line.x1) / math.max(len, 1e-6)
	local angle = math.deg(math.atan2(dy, dx)) % 180
	return angle, offset
end

-- A cut line's distance from the dough's centre in dough-local units (PrepGeometry.toDough), the
-- measure Scoring.cut holds against centreTolerance.
function Scoring.cutOffset(line: Line, S: PrepGeometry.Mat2?): number
	local dough = S or Scoring.ROUND
	local a = PrepGeometry.toDough(dough, { x = line.x1, y = line.y1 })
	local b = PrepGeometry.toDough(dough, { x = line.x2, y = line.y2 })
	local _, offset = lineAngleAndOffset({ x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y })
	return offset
end

-- The part of segment a-b on the dough S, as parameters along it (nil when none). A linear map
-- keeps the parameters, so it is the unit-circle clip of the segment mapped by S^-1. The one
-- clip shared by the grade (Scoring.cutPath), the live groove and the committed groove (Widgets).
function Scoring.clipToDough(S: PrepGeometry.Mat2, ax: number, ay: number, bx: number, by: number): (number?, number?)
	local Si = PrepGeometry.inverse(S)
	local a, b = PrepGeometry.apply(Si, { x = ax, y = ay }), PrepGeometry.apply(Si, { x = bx, y = by })
	local dx, dy = b.x - a.x, b.y - a.y
	local A = dx * dx + dy * dy
	if A < 1e-12 then
		return nil, nil
	end
	local B = 2 * (a.x * dx + a.y * dy)
	local C = a.x * a.x + a.y * a.y - 1
	local disc = B * B - 4 * A * C
	if disc <= 0 then
		return nil, nil
	end
	local r = math.sqrt(disc)
	local t0, t1 = math.max(0, (-B - r) / (2 * A)), math.min(1, (-B + r) / (2 * A))
	if t1 - t0 < 1e-6 then
		return nil, nil
	end
	return t0, t1
end

-- The best-fit line of a checked path (plain list, at least 2 points in range) on the dough S:
-- the principal axis, in frame units, of even samples along the path that lie on the dough,
-- pointing the way the cutter travelled. The one fit shared by the grade (Scoring.cutPath) and
-- the cutting assist (CutStroke), so the assist straightens toward the very line the grade
-- measures. Nil and a refusal reason when the path is too short or misses the dough.
export type CutFit = { xs: { number }, ys: { number }, ws: { number }, mx: number, my: number, ux: number, uy: number, total: number }
function Scoring.cutFit(path: { Point }, dough: PrepGeometry.Mat2): (CutFit?, string?)
	local n = #path
	local total = 0
	for i = 2, n do
		total += math.sqrt((path[i].x - path[i - 1].x) ^ 2 + (path[i].y - path[i - 1].y) ^ 2)
	end
	if total < 1e-6 then
		return nil, "cut too short"
	end

	-- Even samples along the path (at most about 2,000), keeping those on the dough, plus the
	-- exact points where the path crosses the dough's edge so a cut that reaches it spans fully.
	-- In the dough's unit-circle frame (S^-1 p) the edge is the unit circle.
	local Si = PrepGeometry.inverse(dough)
	local function mapped(x: number, y: number): (number, number)
		return Si.a * x + Si.b * y, Si.c * x + Si.d * y
	end
	local function onDough(x: number, y: number): boolean
		local u, v = mapped(x, y)
		return u * u + v * v <= 1
	end
	local step = math.max(0.01, total / 2000)
	-- Edge crossings count for span and distance but carry no weight in the fit, so they do not
	-- bias it towards the path's ends.
	local xs, ys, ws = {}, {}, {}
	local function keep(x: number, y: number, w: number)
		table.insert(xs, x)
		table.insert(ys, y)
		table.insert(ws, w)
	end
	local px, py = path[1].x, path[1].y
	local wasIn = onDough(px, py)
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
			local isIn = onDough(x, y)
			if isIn ~= wasIn then
				-- Where the short step from (px, py) to (x, y) meets the dough's edge.
				local au, av = mapped(px, py)
				local bu, bv = mapped(x, y)
				local du, dv = bu - au, bv - av
				local A, B, C = du * du + dv * dv, 2 * (au * du + av * dv), au * au + av * av - 1
				local root = math.sqrt(math.max(0, B * B - 4 * A * C))
				local u = if wasIn then (-B + root) / (2 * A) else (-B - root) / (2 * A)
				u = math.clamp(u, 0, 1)
				keep(px + (x - px) * u, py + (y - py) * u, 0)
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

	-- Principal axis of the samples on the dough, in frame units.
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
	return { xs = xs, ys = ys, ws = ws, mx = mx, my = my, ux = ux, uy = uy, total = total }, nil
end

-- Grades one freehand cut from its dragged path (cut coordinates: the pizza frame, frame edge
-- 1) against the made pizza's dough footprint S (Scoring.footprint; the full round crust when
-- omitted). Returns the cut to store, or nil and a refusal reason. The server runs this on every
-- cut it accepts with the pizza's own S; the client runs it with the same S to explain a refusal
-- first and to show whether the live stroke would cut. Only the part of the path on the dough is
-- graded, since the wheel cuts nothing off the food: the best-fit line (principal axis) of that
-- part gives the chord across the dough, the widest distance from it gives straightness and the
-- share of the chord the path spans gives completeness. The fit and the wobble are measured in
-- frame units (the hand's own scale), so a thin oval does not magnify jitter; the chord and the
-- span are measured on the dough, so a cut across bare board never counts. Shares along one line
-- are the same in frame and dough units (the map is linear).
function Scoring.cutPath(points: any, S: PrepGeometry.Mat2?): (Cut?, string?)
	local cfg = Config.Cut
	local dough = S or Scoring.ROUND
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
	local fit, why = Scoring.cutFit(path, dough)
	if not fit then
		return nil, why
	end
	local xs, ys, mx, my, ux, uy, total = fit.xs, fit.ys, fit.mx, fit.my, fit.ux, fit.uy, fit.total
	local Si = PrepGeometry.inverse(dough)
	local function mapped(x: number, y: number): (number, number)
		return Si.a * x + Si.b * y, Si.c * x + Si.d * y
	end
	-- Where the line (mx, my) + t (ux, uy) meets the dough's edge: |S^-1 (m + t u)| = 1.
	local au, av = mapped(mx, my)
	local eu, ev = mapped(ux, uy)
	local ee, ae, aa = eu * eu + ev * ev, au * eu + av * ev, au * au + av * av
	local disc = ae * ae - ee * (aa - 1)
	if disc <= 1e-12 then
		return nil, "cut missed the pizza"
	end
	local root = math.sqrt(disc)
	local tlo, thi = (-ae - root) / ee, (-ae + root) / ee
	local chord = thi - tlo
	-- The drag must be at least minDragShare of the chord it crosses, so a short stroke across
	-- a thin oval's narrow way counts like a long one across a round pizza.
	if total < cfg.minDragShare * chord then
		return nil, "cut too short"
	end
	local lo, hi, widest = math.huge, -math.huge, 0
	-- Straightness forgives hand tremor and input noise (Lawson, 2026-10-29): the wobble is
	-- measured on the path averaged over a short stretch along it (Config.Cut.tremor), so small
	-- quick shakes cancel out while a drift or a bend that lasts longer than the stretch counts
	-- in full. The widest raw distance is kept for the trace (rawDeviation).
	local ws = fit.ws
	local offs, along = {}, {}
	local run, px, py = 0, nil :: number?, nil :: number?
	for i = 1, #xs do
		local qx, qy = xs[i] - mx, ys[i] - my
		local t = qx * ux + qy * uy
		lo = math.min(lo, t)
		hi = math.max(hi, t)
		if ws[i] > 0 then
			local d = qx * uy - qy * ux
			widest = math.max(widest, math.abs(d))
			if px and py then
				run += math.sqrt((xs[i] - px) ^ 2 + (ys[i] - py) ^ 2)
			end
			px, py = xs[i], ys[i]
			table.insert(offs, d)
			table.insert(along, run)
		end
	end
	local dev = 0
	local half = cfg.tremor / 2
	local a, b, sum = 1, 0, 0
	for i = 1, #offs do
		while b < #offs and along[b + 1] <= along[i] + half do
			b += 1
			sum += offs[b]
		end
		while along[a] < along[i] - half do
			sum -= offs[a]
			a += 1
		end
		dev = math.max(dev, math.abs(sum / (b - a + 1)))
	end
	local completeness = (math.clamp(hi, tlo, thi) - math.clamp(lo, tlo, thi)) / chord
	if completeness < cfg.minComplete then
		return nil, "cut doesn't cross the pizza"
	end
	local straightness = clamp01(1 - (dev - cfg.straightPerfect) / (cfg.straightZero - cfg.straightPerfect))
	return {
		x1 = mx + ux * tlo,
		y1 = my + uy * tlo,
		x2 = mx + ux * thi,
		y2 = my + uy * thi,
		path = path,
		straightness = straightness,
		completeness = completeness,
		deviation = dev,
		rawDeviation = widest,
	} :: any, nil
end

-- A dragged path with at most `max` points, evenly spaced along it (both ends kept). Paths
-- already within `max` points come back unchanged (copied). Since slice 3 the Cut station no
-- longer resamples (it records at most maxPoints samples, CutStroke); kept for the checks.
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

-- The cut grade against the made pizza's dough S (the full round crust when omitted). Evenness
-- and the centre are judged in dough-local units (PrepGeometry.toDough): on an oval, equal angles
-- there are equal-area slices, so a fair layout on a rotated or sheared oval scores like the same
-- layout on a round pizza.
function Scoring.cut(slices: number, lines: { Cut }, S: PrepGeometry.Mat2?): Grade
	local cfg = Config.Cut
	local dough = S or Scoring.ROUND
	local notes = {}
	local needed = slices // 2
	if #lines == 0 then
		return { score = 0, notes = { "The pizza wasn't cut" } }
	end

	local angles = {}
	local offCentre = 0
	for _, line in lines do
		local a = PrepGeometry.toDough(dough, { x = line.x1, y = line.y1 })
		local b = PrepGeometry.toDough(dough, { x = line.x2, y = line.y2 })
		local angle, offset = lineAngleAndOffset({ x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y })
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
	-- The same mean with every cut straight, and with every cut complete: what the wobble and
	-- the short cuts cost, so their notes only appear when they cost points (below).
	local qualityStraight, qualityComplete = 0, 0
	local perCut = {}
	for _, line in lines do
		local q, straight, complete = Scoring.cutQuality(line)
		quality += q
		qualityStraight += complete
		qualityComplete += straight
		if straight < 0.9 then
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
	qualityStraight /= #lines
	qualityComplete /= #lines
	local function scoreOf(l: number, q: number): number
		local v = 100 * l * q
		return if #lines ~= needed then math.min(v, 60) else v
	end
	local score = scoreOf(layout, quality)
	-- A note names a problem only when it cost at least noteMinPoints of this Cut score
	-- (Lawson, 2026-10-29: no criticism of tiny deviations); each problem has one note.
	local evenLayout = clamp01(countScore * 0.5 + 0.5 - offCentre * 0.25)
	local unevenCost = scoreOf(evenLayout, quality) - score
	local wobbleCost = scoreOf(layout, qualityStraight) - score
	local shortCost = scoreOf(layout, qualityComplete) - score
	if #lines ~= needed then
		-- Cuts made against cuts needed: a freehand path need not make exactly 2 x cuts slices.
		table.insert(notes, string.format("Made %d cut%s, the order needed %d", #lines, if #lines == 1 then "" else "s", needed))
	end
	if offCentre > 0 then
		table.insert(notes, string.format("%d cut%s missed the centre", offCentre, if offCentre == 1 then "" else "s"))
	end
	if #angles > 1 and unevenCost >= cfg.noteMinPoints then
		table.insert(notes, "Slices were uneven sizes")
	end
	if crooked > 0 and wobbleCost >= cfg.noteMinPoints then
		table.insert(notes, string.format("%d cut%s wobbled off a straight line", crooked, if crooked == 1 then "" else "s"))
	end
	if short > 0 and shortCost >= cfg.noteMinPoints then
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

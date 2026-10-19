--!strict
-- Pure grading functions shared by server (authoritative) and client (previews, tests).
-- Pizza-local coordinates are normalized: centre (0, 0), crust edge radius 1, x right, y down.

local Config = require(script.Parent.Config)
local Recipes = require(script.Parent.Recipes)

export type Piece = { ingredient: string, x: number, y: number }
export type Line = { x1: number, y1: number, x2: number, y2: number }
export type Grade = { score: number, notes: { string } }

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

function Scoring.bakeState(target: number, seconds: number): string
	local cfg = Config.Oven
	local delta = seconds - target
	if delta > cfg.burntAfter then
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

function Scoring.cut(slices: number, lines: { Line }): Grade
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
	local score = 100 * clamp01(countScore * 0.5 + evenScore * 0.5 - offCentre * 0.25)
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
	return { score = math.floor(score + 0.5), notes = notes }
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

--!strict
-- The Make tab's cheese step (Lawson, 2026-10-26): hold and drag over the sauce to sprinkle
-- shredded cheese, one pinch every PrepFood.PINCH_STEP of travel (PrepFood.sampler). The pinch
-- model, its footprint and its score are PrepFood's (cooking plan rev 6, 3.3); this module adds
-- the server's batch check and the step's grade. Positions are dough-local, so the cheese
-- follows the dough the player rolled.
--
-- Stored on a pizza as make.cheese = { strokes }: each held sprinkle is one stroke, a list of
-- pinches in placement order. A stroke arrives in batches (Config.Cheese.batchSize at most);
-- `newStroke` on a batch starts the next stroke. Undo removes the whole last stroke.

local Config = require(script.Parent.Config)
local PrepFood = require(script.Parent.PrepFood)
local MakeSauce = require(script.Parent.MakeSauce)

local MakeCheese = {}

export type Vec = { x: number, y: number }
export type Cheese = { strokes: { { Vec } } }
export type Grade = { score: number, notes: { string }, detail: any? }

local CRUST = 0.95

function MakeCheese.count(cheese: Cheese): number
	local n = 0
	for _, s in cheese.strokes do
		n += #s
	end
	return n
end

function MakeCheese.pinches(cheese: Cheese): { Vec }
	local out = {}
	for _, s in cheese.strokes do
		for _, p in s do
			table.insert(out, p)
		end
	end
	return out
end

-- Checks one batch before anything is stored. points must be a true array of 1..batchSize
-- points (exactly #points keys, counted no further than one past the length, so a list stuffed
-- with extra keys costs nothing and is refused); then PrepFood.validateCheeseBatch (finite, in
-- reach, the pizza's cap, the spacing within the stroke, across the join with the stroke's last
-- pinch). A first batch always starts a stroke. Returns the clean copy to store and whether it
-- starts a stroke.
function MakeCheese.validate(cheese: Cheese, args: any): ({ Vec }?, boolean, string?)
	local points = args.points
	if type(points) ~= "table" then
		return nil, false, "bad cheese"
	end
	local n = #points
	if n < 1 then
		return nil, false, "no cheese"
	elseif n > Config.Cheese.batchSize then
		return nil, false, "too many pinches at once"
	end
	local keys = 0
	for _ in next, points do
		keys += 1
		if keys > n then
			return nil, false, "bad cheese"
		end
	end
	local clean = table.create(n)
	for i = 1, n do
		local p = points[i]
		if type(p) ~= "table" then
			return nil, false, "bad cheese"
		end
		clean[i] = { x = p.x, y = p.y }
	end
	if args.newStroke ~= nil and type(args.newStroke) ~= "boolean" then
		return nil, false, "bad cheese"
	end
	local newStroke = args.newStroke == true or #cheese.strokes == 0
	local ok, why = PrepFood.validateCheeseBatch(cheese.strokes, clean, newStroke)
	if not ok then
		local words = { cap = "too much cheese", spacing = "pinches too far apart", bounds = "cheese out of reach", finite = "bad cheese", type = "bad cheese", empty = "no cheese" }
		return nil, false, words[why :: string] or "bad cheese"
	end
	return clean, newStroke, nil
end

-- Commits a batch that validate() accepted.
function MakeCheese.add(cheese: Cheese, points: { Vec }, newStroke: boolean)
	if newStroke then
		table.insert(cheese.strokes, {})
	end
	local stroke = cheese.strokes[#cheese.strokes]
	for _, p in points do
		table.insert(stroke, p)
	end
end

-- One held pour of the shaker (Lawson 2026-10-28: the cheese poured over the table as soon as
-- the drag left the bowl; Astra r19 R19-03). Choosing the shaker pours nothing; the client calls
-- press() only for a fresh press made with the shaker already chosen. The flow then follows the
-- pointer's travel (PrepFood.sampler, one pinch every PINCH_STEP) and, held still, time (one
-- pinch every Config.Cheese.flowTime, so a deliberate still hold builds a pile), and only while
-- the pointer is over the board: a press off it pours nothing, and leaving it ends the pour, so
-- coming back needs a fresh press. tick() adds at most one pinch however long a frame stalled
-- (no catch-up burst). Every call returns the pinches it placed (dough-local); consecutive
-- pinches are at most PINCH_STEP apart, as the server checks.
export type Pour = {
	stopped: boolean,
	press: (q: Vec, onBoard: boolean, now: number) -> { Vec },
	move: (q: Vec, onBoard: boolean, now: number) -> { Vec },
	tick: (now: number) -> { Vec },
}

function MakeCheese.pour(): Pour
	local sampler = PrepFood.sampler()
	local last: Vec? = nil
	local lastPinch = 0
	local pour = {} :: Pour
	pour.stopped = false
	function pour.press(q: Vec, onBoard: boolean, now: number): { Vec }
		if pour.stopped or last then
			return {}
		end
		if not onBoard then
			pour.stopped = true
			return {}
		end
		last, lastPinch = { x = q.x, y = q.y }, now
		return sampler.feed(q)
	end
	function pour.move(q: Vec, onBoard: boolean, now: number): { Vec }
		if pour.stopped or not last then
			return {}
		end
		if not onBoard then
			pour.stopped = true
			return {}
		end
		local placed = sampler.feed(q)
		last = { x = q.x, y = q.y }
		if #placed > 0 then
			lastPinch = now
		end
		return placed
	end
	function pour.tick(now: number): { Vec }
		local at = last
		if pour.stopped or not at or now - lastPinch < Config.Cheese.flowTime then
			return {}
		end
		lastPinch = now
		return { { x = at.x, y = at.y } }
	end
	return pour
end

-- The step's minimum: at least one pinch.
function MakeCheese.canFinish(cheese: Cheese): boolean
	return MakeCheese.count(cheese) > 0
end

-- The Cheese score (PrepFood.cheeseScore: count on the edible area against 24, footprint spread
-- over the 24 sauce cells, a penalty for pinches on the crust band) with the plan's notes and the
-- severe-coverage ceiling on the spread (the same ramp as the sauce's).
function MakeCheese.grade(cheese: Cheese): Grade
	local cfg = Config.Cheese
	local pinches = MakeCheese.pinches(cheese)
	local score, inside, spread, crust = PrepFood.cheeseScore(pinches)
	local off = 0
	for _, p in pinches do
		if p.x * p.x + p.y * p.y > CRUST * CRUST then
			off += 1
		end
	end
	local notes = {}
	if #pinches == 0 then
		table.insert(notes, "No cheese")
	elseif inside < cfg.fewBelow then
		table.insert(notes, "Not enough cheese")
	elseif inside > cfg.manyAbove then
		table.insert(notes, "Too much cheese")
	end
	if #pinches > 0 and spread < cfg.bunchedBelow then
		table.insert(notes, "Cheese patchy, with bare parts")
	end
	if crust > 0 then
		table.insert(notes, "Cheese on the crust")
	end
	if off > 0 then
		table.insert(notes, "Cheese fell off the dough")
	end
	return {
		score = score,
		notes = notes,
		detail = { pinches = #pinches, inside = inside, spread = spread, crust = crust, off = off, ceiling = MakeSauce.ceiling(spread) },
	}
end

return MakeCheese

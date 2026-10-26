--!strict
-- Every pacing and tolerance value lives here so tuning is an edit, not a code change.

local Config = {}

Config.Shift = {
	-- Customers served in one shift after the tutorial (separate from the character roster
	-- size). Three, provisionally (Lawson, 2026-10-21), until arrival spacing and ticket
	-- pressure are tuned against the full preparation cycle.
	customerCount = 3,
	-- Customers on a save's first shift, the tutorial (Lawson, 2026-10-21). Later shifts use
	-- customerCount.
	tutorialCustomers = 1,
	-- Seconds after shift start when each customer arrives.
	arrivals = { 1, 10, 24, 50, 64, 90 },
	maxActiveTickets = 3,
}

Config.Patience = {
	-- Seconds from arrival until patience reaches zero. Zero patience lowers the wait
	-- grade; early ranks never walk out.
	seconds = 150,
	-- Display bands for the four faces (fraction of patience remaining).
	happy = 0.70,
	neutral = 0.40,
	impatient = 0.15,
}

Config.Oven = {
	slots = 2,
	-- Target bake seconds per doneness.
	targets = { light = 18, regular = 24, well = 30 },
	perfectWindow = 2, -- within +/- this many seconds scores 100
	zeroAt = 12, -- this far from target scores 0
	-- Burnt is one absolute time for every order, so the gauge's red zone means the same
	-- thing on every ticket: past it the pizza is burnt whatever bake was asked for.
	burntAt = 36,
}

-- The Make tab's first steps (Lawson, 2026-10-26): flour the board, pull the dough onto it and
-- roll it. Flour is graded inside the Dough score: no new grade weight, no flour stock. Every
-- value below is a proposal, not a balance decision. Coordinates are pizza-local (radius 1 at
-- the pizza frame's edge, the drawn crust at 0.95; the board's edge at 1 / 0.9).
Config.Make = {
	-- Flour: dragging the scoop drops one dust stamp at the press point and then one every
	-- flourStep of travel; each stamp floors a disc of flourRadius.
	flourStep = 0.15,
	flourRadius = 0.35,
	flourReach = 1.11, -- stamps past the board's edge are refused
	flourMaxPerStroke = 40,
	flourMaxStamps = 96,
	-- Past this many stamps the extra flour shows as clumps (looks only; not a penalty).
	flourPlenty = 64,
	-- Share of the finished dough's area that sits on flour: full flour credit from
	-- flourCoverFull, none at flourCoverZero.
	flourCoverFull = 0.8,
	flourCoverZero = 0.2,
	-- Flour's share of the Dough score; the roll (size and roundness) is the rest.
	flourWeight = 0.2,
	-- Rolling: a stroke runs press to release, is judged on its two end points
	-- (PrepGeometry.roll) and must cross the dough.
	strokeReach = 1.6,
	minStroke = 0.3,
	maxStrokes = 24,
	-- Size (mean semi-axis): full marks from sizeFullLow to sizeFullHigh, none at sizeZeroLow
	-- and at sizeZeroHigh (the 1.1 cap). Roundness (short / long axis): full at roundFull, none
	-- at roundZero. The roll part is half size, half roundness (cooking plan rev 6, 3.1).
	sizeFullLow = 0.95,
	sizeFullHigh = 1.05,
	sizeZeroLow = 0.6,
	sizeZeroHigh = 1.1,
	roundFull = 0.9,
	roundZero = 0.5,
}

Config.Topping = {
	maxPieces = 48,
	-- Normalized pizza-local radius inside which a piece's centre may sit (1 = crust edge).
	placeRadius = 0.84,
	wrongIngredientPenalty = 8,
}

Config.Cut = {
	maxLines = 4,
	-- A cut line must pass this close to the centre (normalized radius) to count.
	centreTolerance = 0.16,
	-- Angular error (degrees) that still scores full marks, and where it reaches zero.
	perfectDegrees = 5,
	zeroDegrees = 30,
	minDragLength = 0.9, -- normalized; shorter drags are ignored
	-- Freehand cuts (Lawson, 2026-10-26): the server keeps the dragged path and grades how
	-- straight and how complete each cut is. The values below are proposals, not balance
	-- decisions. Cut coordinates are the pizza frame's (frame edge 1), so the drawn crust edge
	-- is at 0.95.
	crustRadius = 0.95,
	-- Most points one cut's path may carry. The client resamples the drag to this many.
	maxPoints = 48,
	-- Widest distance (cut units) of the path inside the crust from its best-fit line that
	-- still counts as straight, and where straightness reaches zero. At 1920x1080 the pizza's
	-- radius is about 400 px (0.04 = 16 px, 0.2 = 80 px); on a 667x375 phone about 150 px.
	straightPerfect = 0.04,
	straightZero = 0.2,
	-- Share of the fitted line's chord across the crust the path covers: full credit from
	-- completeFull, none at completeZero; below minComplete the cut is refused.
	completeFull = 0.95,
	completeZero = 0.5,
	minComplete = 0.25,
}

Config.Wait = {
	fullScoreAbove = 0.70, -- patience fraction
	floorScore = 40,
}

Config.Rewards = {
	baseTip = 12, -- tip at a 100% grade, scaled by grade
	xpPerOrder = 10,
	xpPerRank = 100,
	-- One-time tutorial bonus (Lawson 2026-10-21): the first completed tutorial order is topped
	-- up to this many coins, paid as its own labelled amount, never folded into the tip or grade.
	tutorialGuarantee = 4,
}

Config.Dev = {
	-- Development and test only: orders draw on every recipe, as in the mixed proof shift,
	-- instead of the save's unlocked recipes. Off for real play, where a new save gets cheese
	-- orders only.
	mixedOrders = false,
}

Config.Net = {
	maxActionsPerSecond = 20,
}

return Config

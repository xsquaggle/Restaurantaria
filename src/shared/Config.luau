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
	-- thing on every ticket: past it the pizza is burnt whatever bake was asked for. 36 s is a
	-- proposal pending Lawson.
	burntAt = 36,
	-- The food's own state, apart from the doneness the ticket asked for (slice 1, 2026-10-27;
	-- Astra r14): raw up to rawUntil, cooked from cookedFrom to scorchFrom, burnt past burntAt.
	-- Raw or burnt food holds the order grade to foodCap; the hold's approach is continuous, so
	-- no state boundary makes the grade jump: none from cookedFrom to scorchFrom, falling evenly to
	-- foodCap at rawUntil and at burntAt, foodCap beyond. scorchFrom is the latest perfect
	-- window's end (well 30 + 2), so no pizza baked inside its window is ever held. The Bake score
	-- itself is only the distance from the asked doneness (it no longer drops to 0 past burntAt).
	-- Every value is a proposal, NOT approved (the 35 cap and the 36 s burn time are Lawson's).
	-- foodCapOn = false is today's rule (Bake 0 past burntAt, no hold), kept for comparison.
	foodCapOn = true,
	foodCap = 35,
	rawUntil = 8,
	cookedFrom = 12,
	scorchFrom = 32,
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
	-- Stamp centres stay this close to the middle (the board's edge, 1 / 0.9, less one stamp
	-- radius) so no dust lands off the board; the client pulls a drag past it back inside.
	flourReach = 0.76,
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
	-- Rolling: a held drag is split into passes (MakeDough.rollDrag): a pass fixes its direction
	-- once the pointer is rollLock from where it began, and ends once the pointer, going no
	-- further along it, is rollTurn from where it went furthest (a turn), or at the release.
	-- Each pass is a stroke, judged on its two end points (PrepGeometry.roll); it must cross the
	-- dough and be minStroke long.
	strokeReach = 1.6,
	minStroke = 0.3,
	maxStrokes = 24,
	rollLock = 0.12,
	rollTurn = 0.1,
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

-- The Make tab's sauce step (MakeSauce): tap the dough to pour a ladle, drag across the sauce to
-- spread it. Every value is a proposal, not a balance decision. Units are dough-local (radius 0.95
-- is the dough's edge, 0.84 the edible area's).
Config.Sauce = {
	-- The thickness field's grid: cells this far apart, out to this radius (past the dough's
	-- edge, so spilled sauce lies on the board).
	cell = 0.05,
	extent = 1.2,
	-- A pour spreads one ladle evenly over the cells within pourRadius of its point.
	pourRadius = 0.3,
	-- Spreading: the ladle's back is a disc of ladleRadius; every spreadStep of the path it
	-- takes pick of the sauce under it and lays lay of its load back.
	ladleRadius = 0.18,
	spreadStep = 0.04,
	pick = 0.5,
	lay = 0.5,
	-- A cell at least this thick counts as sauce for "the spread must cross sauce".
	occupied = 0.05,
	-- A press that moves this many pixels before release is a spread, otherwise a pour (plan
	-- rev 6, D8).
	tapPixels = 8,
	targetPours = 3,
	maxPours = 6,
	maxSpreads = 30,
	-- One spread's path: at most maxPoints points within strokeReach, at least minSpread and at
	-- most maxSpread long (a bound on the server's replay work; a longer drag goes out as more
	-- than one spread).
	maxPoints = 64,
	strokeReach = 1.6,
	minSpread = 0.2,
	maxSpread = 6,
	-- The score: amount (pours against targetPours), coverage of the edible area, clean (sauce
	-- on the crust band counts once, off the dough offWeight times).
	amountWeight = 0.3,
	coverWeight = 0.5,
	cleanWeight = 0.2,
	offWeight = 2,
	-- Notes: coverage under bareBelow; more than crustAbove of the sauce on the crust band; more
	-- than spillAbove off the dough.
	bareBelow = 0.9,
	crustAbove = 0.05,
	spillAbove = 0.02,
	-- Severe-coverage safeguard (plan rev 6, 5.3d): the Make score is held to ceilingFloor at
	-- coverage ceilingFrom or less, not held at all from ceilingTo, evenly between.
	ceilingFloor = 35,
	ceilingFrom = 0.25,
	ceilingTo = 0.75,
}

-- The Make tab's cheese step (PrepFood's pinch model, plan rev 6, 3.3): hold and drag to sprinkle,
-- one pinch every PrepFood.PINCH_STEP of travel. Proposals.
Config.Cheese = {
	-- A batch the client sends: at most batchSize pinches, at most one batch every batchGap s
	-- while a sprinkle is held (the rest go out on release).
	batchSize = 8,
	batchGap = 0.1,
	-- A held pour (MakeCheese.pour) drops a pinch every PrepFood.PINCH_STEP of travel and, held
	-- still, one every flowTime s (slice 7a, a proposal: about 24 pinches in 3.6 s of holding).
	flowTime = 0.15,
	-- Notes: fewer than fewBelow or more than manyAbove pinches on the edible area; spread under
	-- bunchedBelow.
	fewBelow = 20,
	manyAbove = 28,
	bunchedBelow = 0.7,
}

Config.Topping = {
	maxPieces = 48,
	-- Dough-local radius inside which a piece's centre may sit (slice 1, 2026-10-27: pieces are
	-- stored dough-local, PrepGeometry.toDough, so 0.95 is the made dough's own edge and 0.84 the
	-- sauce edge on any oval).
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
	-- A drag shorter than this share of the chord its fitted line crosses on the dough is ignored
	-- (slice 1, 2026-10-27: 0.9 of the full round's 1.9 chord, as the earlier fixed 0.9 length,
	-- now relative so a stroke across a thin oval's narrow way counts). Proposal.
	minDragShare = 0.47,
	-- Freehand cuts (Lawson, 2026-10-26): the server keeps the dragged path and grades how
	-- straight and how complete each cut is. The values below are proposals, not balance
	-- decisions. Cut coordinates are the pizza frame's (frame edge 1), so the full round crust
	-- is at 0.95. Since slice 1 (2026-10-27) cuts are clipped and graded against the made
	-- pizza's own dough outline (Scoring.footprint); crustRadius is the full round's, kept for
	-- pizzas with no dough record. centreTolerance is in dough-local units (dough edge 0.95).
	crustRadius = 0.95,
	-- Most points one cut's path may carry. Since slice 3 (2026-10-27) the client records the
	-- drag as at most this many samples, one each `spacing` cut units (CutStroke), and sends
	-- exactly those; nothing is resampled. 0.07 lets a straight drag cross the whole accepted
	-- range (3.2 units) in 47 steps; at maxPoints the stroke is finished and records nothing
	-- more until the next press.
	-- Proposal: 0.07 = 26 px at 1920x1080 and 6 px on a 667x375 phone.
	maxPoints = 48,
	spacing = 0.07,
	-- Cutting assist (slice 3; Lawson's request, Astra's 0.10 starting value). Test proposals,
	-- not balance decisions, and OFF by default: a shift turns it on only through the Studio
	-- test hook (RestaurantariaDebug "cutAssist") until Lawson accepts it. The rule is in
	-- CutStroke.filter. travel, deviation, backtrack and centre are in the dough's unit disc
	-- (u = S^-1 p, edge 1); strength is the share of the measured offset corrected; the
	-- correction is capped at strength x deviation (u); decay fades the last correction per
	-- sample once the gates switch the assist off.
	assist = {
		on = false,
		strength = 0.10,
		travel = 0.10,
		deviation = 0.15,
		backtrack = 0.05,
		centre = 0.10,
		decay = 0.5,
	},
	-- Widest distance (cut units) of the path inside the crust from its best-fit line that
	-- still counts as straight, and where straightness reaches zero. One cut unit is the pizza
	-- frame's radius, measured in Studio: 372 px at 1920x1080 (0.04 = 15 px, 0.2 = 74 px) and
	-- 86.5 px on a 667x375 phone (0.04 = 3.5 px, 0.2 = 17 px).
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

-- How the parts join the order grade (grade split, 2026-10-27). Every value and switch is a
-- proposal, not a balance decision: Lawson's 50 / 30 / 20 are his provisional playtest weights
-- (2026-10-21); the rest follows cooking plan rev 6, 5.1 to 5.3 (rev 7 amendment).
Config.Grade = {
	-- "split": Grade = Make 50 / Bake 30 / Cut 20 and Service joins the pay once (plan 5.2);
	-- "average": the earlier join, the plain mean of Wait, Make, Bake and Cut.
	join = "split",
	weights = { make = 0.5, bake = 0.3, cut = 0.2 },
	-- Where the Make ceilings (coverage, and completeness when on) hold: "order" the whole grade
	-- (plan 5.3), "make" only the Make part (as slice 2 built it).
	ceilingsOn = "order",
	-- Completeness ceilings (plan 5.3c): sauce pours on the dough / Config.Sauce.targetPours,
	-- cheese pinches on the dough / 24, dough area a x b / 0.95^2. Same ramp as coverage.
	completeness = true,
	doughCompleteness = true,
	-- Topping completeness ceiling (slice 1, 2026-10-27; Astra r14 P1): for each ingredient the
	-- ticket asks for, the right pieces inside the asked region against the count; the lowest
	-- share sets a ceiling on the same ramp (35 at a quarter or less, none from three quarters).
	-- Wrong or extra pieces never count toward it. Proposal; false turns it off for comparison.
	toppingCompleteness = true,
	-- Split join only: Service is a 0.85-1.00 pay modifier before integer rounding (Service runs
	-- 40 to 100, so 1 - 0.25 + 0.25 x Service / 100 runs 0.85 to 1.00): Paid = round(Grade x that
	-- modifier), coins = round(12 x Paid / 100). Service is not in the grade and not in XP (XP from
	-- the Grade). Because both steps round, the final coin cut can exceed 15 % on small payouts
	-- (grade 100: 12 -> 10 coins; grade 13: 2 -> 1). Still a proposal pending Lawson, as is
	-- dropping the intermediate rounding (that would change payouts). The tutorial top-up is
	-- separate (Config.Rewards.tutorialGuarantee).
	serviceShare = 0.25,
}

Config.Rewards = {
	baseTip = 12, -- tip at a 100% grade, scaled by grade
	xpPerOrder = 10,
	xpPerRank = 100,
	-- One-time tutorial bonus (Lawson 2026-10-21): the first completed tutorial order is topped
	-- up to this many coins, paid as its own labelled amount, never folded into the tip or grade.
	tutorialGuarantee = 4,
}

-- How the player's own sauce and cheese are drawn (slice 2, Astra r14). "material": one thick
-- marinara material through the scored coverage (SauceCover), raw and cooked maps blended under
-- one mask; "stamps": the r13 soft translucent stamps, kept only for the same-input A/B. The
-- cooked cheese family: "v2" Astra's r14 denser exports on the shared alpha, "v1" the r13 ones.
-- MakeLayers.new can override both for a comparison view.
Config.FoodArt = {
	sauce = "material",
	cheese = "v2",
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

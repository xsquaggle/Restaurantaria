--!strict
-- Every pacing and tolerance value lives here so tuning is an edit, not a code change.

local Config = {}

Config.Shift = {
	-- Customers served in one shift (separate from the character roster size).
	customerCount = 6,
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
	burntAfter = 14, -- seconds past target when the pizza is burnt
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
}

Config.Wait = {
	fullScoreAbove = 0.70, -- patience fraction
	floorScore = 40,
}

Config.Rewards = {
	baseTip = 12, -- tip at a 100% grade, scaled by grade
	xpPerOrder = 10,
	xpPerRank = 100,
}

Config.Net = {
	maxActionsPerSecond = 20,
}

return Config

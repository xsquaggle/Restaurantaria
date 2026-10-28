--!strict
-- The game-wide motion language as numbers and curves (Astra r15 motion-and-reward-spec):
-- press, pop (one restrained overshoot), settle, the slowing count-up, the rate-limited count
-- ticks, the XP fill across rank thresholds, the shift reward timeline and the curves its
-- light effects follow (twinkle, coin spin, ring, sweep). Pure: no services, no instances, so
-- the timing and the values a presentation ends on can be checked offline. Motion and Shine
-- (the Roblox side) play these. The starting settings are Astra's; the end-of-shift sequence
-- is retuned here for Lawson's 2026-10-28 direction (a richer, more rewarding card), not from
-- measured Papa's timings.

local MotionPlan = {}

-- Seconds and scales. One table so a business or a re-skin can retune the feel in one place.
MotionPlan.T = {
	-- Buttons: visual scale 1 -> 0.97 in about 70 ms, back in 110 ms (spec 2).
	pressScale = 0.97,
	pressIn = 0.07,
	pressOut = 0.11,
	-- End-of-shift panel. Astra's start was 0.96 -> 1.01 -> 1.00 in 220 ms; Lawson asked for
	-- a fluid, much more rewarding card (2026-10-28), so it lands from further, with a fuller
	-- overshoot, a short fade and a longer upward settle.
	panelFrom = 0.9,
	panelPeak = 1.03,
	panelEnter = 0.36,
	panelRise = 18, -- px the panel settles up from
	panelFade = 0.14,
	-- Heading: begins after the panel starts to land, fades and rises.
	headingDelay = 0.12,
	headingIn = 0.24,
	headingRise = 10,
	-- The completion emblem stamps in: small and tilted, one overshoot, upright.
	emblemFrom = 0.35,
	emblemPeak = 1.18,
	emblemTilt = -16, -- degrees
	emblemStamp = 0.46,
	-- Coin impact: the row lands from above with one overshoot.
	impactFrom = 0.86,
	impactPeak = 1.06,
	impact = 0.2,
	impactDrop = 12,
	-- The coin spins in as it lands: turns about its upright axis, slowing to face-on.
	coinSpin = 0.75,
	coinTurns = 2,
	-- Coin count: 1,200 ms baseline, 900 to 1,500 ms by size of the award. The row swells
	-- slightly while it counts, then releases in the payoff.
	coinCountMin = 0.9,
	coinCount = 1.2,
	coinCountMax = 1.5,
	countSwell = 1.04,
	-- Payoff when the count lands: the row pops, a ring of light and sparkles leave the coin.
	coinFlourish = 0.55,
	flourishPeak = 1.1,
	flourishPop = 0.42,
	-- XP arrival rises 4 to 8 phone px and settles; the star spins in. Count/fill 900 ms
	-- (700 to 1,200).
	xpArrive = 0.24,
	xpRise = 8,
	starFrom = 0.3,
	starPeak = 1.22,
	starTilt = -140, -- degrees
	starSpin = 0.5,
	xpCountMin = 0.7,
	xpCount = 0.9,
	xpCountMax = 1.2,
	-- After the bar settles: a flash along it, a ring and sparkles from the star.
	xpFinale = 0.6,
	finalePeak = 1.04,
	finalePop = 0.4,
	-- A short pause between the coin and XP phases (the coin payoff overlaps it).
	gap = 0.14,
	-- Light: the sweep across the whole card, a glint across a coin, bar or button, one
	-- twinkle's life, and motes shed by the moving fill.
	cardSheenDelay = 0.22,
	cardSheen = 0.9,
	glint = 0.6,
	twinkle = 0.5,
	moteEvery = 0.04,
	mote = 0.45,
	-- Resting state: the continuation button's call to action once it can be pressed, then a
	-- glint on the button and the coin now and then while the card stays up.
	buttonPeak = 1.06,
	buttonPop = 0.34,
	buttonGlint = 3.4,
	coinGlint = 4.8,
	-- The save accepts an award shown as a projection: the gain locks in (nothing counts
	-- again); a real rank-up is celebrated only now.
	lockIn = 0.45,
	rankPeak = 1.25,
	rankPop = 0.42,
	-- Per-order result card: a modest accent, not the shift sequence.
	cardEnter = 0.2,
	cardFrom = 0.96,
	cardPeak = 1.012,
	cardRise = 6,
	cardExit = 0.16,
	-- The pay row's coin lands after the card: its icon is small (18 to 20 px), so it pops
	-- from further than the summary's coin group for the same readable weight.
	payDelay = 0.12,
	payFrom = 0.6,
	payPeak = 1.15,
	payPop = 0.22,
	-- Reduced motion: a short fade only.
	reducedFade = 0.12,
	-- Count ticks: at most 10 a second, never queued (spec 5).
	tickRate = 10,
}

-- Share of a pop spent rising to the peak; the rest settles back to 1.
MotionPlan.POP_SPLIT = 0.45

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

-- Ease-out cubic: fast first, progressively slower (the count-up curve of spec 4).
function MotionPlan.easeOut(p: number): number
	local q = 1 - clamp01(p)
	return 1 - q * q * q
end

-- Ease-in-out sine: a light sweep accelerates in and decelerates out.
local function easeInOut(p: number): number
	p = clamp01(p)
	return 0.5 - math.cos(math.pi * p) / 2
end
MotionPlan.easeInOut = easeInOut

-- Scale at progress p of a pop from `from` through one overshoot to `peak`, ending on 1.
function MotionPlan.pop(p: number, from: number, peak: number): number
	p = clamp01(p)
	local split = MotionPlan.POP_SPLIT
	if p < split then
		return from + (peak - from) * MotionPlan.easeOut(p / split)
	end
	return peak + (1 - peak) * easeInOut((p - split) / (1 - split))
end

-- Rotation (degrees) at progress p of a turn-in from `tilt` to upright, passing upright once
-- and coming back (the same overshoot as a pop), ending on exactly 0.
function MotionPlan.tilt(p: number, tilt: number): number
	return tilt * (1 - MotionPlan.pop(p, 0, 1.12))
end

-- A twinkle at q (0..1 of its life): it flares past full size quickly, then shrinks away
-- while its light fades. Returns scale and transparency; ends at 0 and 1.
local TWINKLE_FLARE = 0.22
function MotionPlan.twinkle(q: number): (number, number)
	q = clamp01(q)
	local scale: number
	if q < TWINKLE_FLARE then
		scale = 1.12 * MotionPlan.easeOut(q / TWINKLE_FLARE)
	else
		local d = (q - TWINKLE_FLARE) / (1 - TWINKLE_FLARE)
		scale = 1.12 * (1 - d * d)
	end
	local transparency = if q < 0.5 then 0 else ((q - 0.5) / 0.5) ^ 1.5
	return scale, transparency
end

-- A coin spinning `turns` times about its upright axis and slowing to face-on: its shown
-- width (0.08..1) and how far it shades toward its edge colour (0..0.6), at progress p.
function MotionPlan.flip(p: number, turns: number): (number, number)
	local c = math.abs(math.cos(2 * math.pi * turns * MotionPlan.easeOut(p)))
	return math.max(c, 0.08), (1 - c) * 0.6
end

-- A ring of light: transparency at q, from `peak` (bright) to gone, holding early.
function MotionPlan.ringFade(q: number, peak: number): number
	q = clamp01(q)
	return peak + (1 - peak) * q ^ 1.6
end

-- Where a light band is (gradient offset) at progress p of a sweep: off one side to off
-- the other, easing in and out.
MotionPlan.SWEEP = 0.95
function MotionPlan.sweep(p: number): number
	return -MotionPlan.SWEEP + 2 * MotionPlan.SWEEP * easeInOut(p)
end

-- Integer shown at `elapsed` of a count from 0 to `final` over `duration`: floor(final * p),
-- monotonic, and exactly `final` once the time is up (or the duration is not positive).
function MotionPlan.countValue(final: number, elapsed: number, duration: number): number
	if duration <= 0 or elapsed >= duration then
		return final
	end
	return math.floor(final * MotionPlan.easeOut(elapsed / duration))
end

-- Count duration for an award: small awards count briefly, large ones stay bounded.
function MotionPlan.countDuration(amount: number, base: number, lo: number, hi: number): number
	if amount <= 0 then
		return 0
	end
	-- About 30 integer steps are readable at the baseline; fewer shorten, more lengthen gently.
	local d = base * (0.75 + 0.25 * math.log(amount + 1) / math.log(31))
	return math.clamp(d, lo, hi)
end

-- Rate limiter for count ticks: at most `rate` a second, a missed tick is dropped, never
-- queued. tick(now, changed) says whether to sound/vibrate one tick for this frame.
export type Ticker = { rate: number, last: number, count: number }

function MotionPlan.ticker(rate: number?): Ticker
	return { rate = rate or MotionPlan.T.tickRate, last = -math.huge, count = 0 }
end

function MotionPlan.tick(t: Ticker, now: number, changed: boolean): boolean
	if not changed or now - t.last < 1 / t.rate then
		return false
	end
	t.last = now
	t.count += 1
	return true
end

-- The XP bar from `fromXp` to `toXp` (both totals), split at each rank threshold so the bar
-- fills to the boundary, the rank advances and the overflow carries (spec 4). Each segment
-- is one rank's part: rank, fraction at its start and at its end, and its share of the fill.
export type Segment = { rank: number, from: number, to: number, share: number }

function MotionPlan.xpSegments(fromXp: number, toXp: number, perRank: number): { Segment }
	local segments: { Segment } = {}
	if perRank <= 0 then
		return segments
	end
	toXp = math.max(toXp, fromXp)
	local total = toXp - fromXp
	local at = fromXp
	while true do
		local rank = 1 + at // perRank
		local base = (rank - 1) * perRank
		local stop = math.min(toXp, base + perRank)
		table.insert(segments, {
			rank = rank,
			from = (at - base) / perRank,
			to = (stop - base) / perRank,
			share = if total > 0 then (stop - at) / total else 1,
		})
		at = stop
		if at >= toXp then
			-- A total that ends exactly on a threshold rests on the new rank at zero.
			if total > 0 and at == base + perRank then
				table.insert(segments, { rank = rank + 1, from = 0, to = 0, share = 0 })
			end
			break
		end
	end
	return segments
end

-- The bar at fill progress p (0..1 over all segments): rank and fraction inside it.
function MotionPlan.xpAt(segments: { Segment }, p: number): (number, number)
	p = clamp01(p)
	local last = segments[#segments]
	if not last then
		return 1, 0
	end
	if p >= 1 then
		return last.rank, last.to
	end
	local acc = 0
	for i, s in segments do
		if p <= acc + s.share or i == #segments then
			local q = if s.share > 0 then clamp01((p - acc) / s.share) else 1
			return s.rank, s.from + (s.to - s.from) * q
		end
		acc += s.share
	end
	return 1, 0
end

-- The shift reward timeline (spec 4), as named phases with start and duration in seconds.
-- It plays once, on the first showing of a shift (`reveal`); a later showing (a save result,
-- a resize, a repeated notification) never replays it. `fill`: the XP bar moves with the XP
-- count, from the real pre-shift progress to the earned endpoint, whether the save has
-- accepted the award yet or not (a pending one is shown as a labelled projection, Astra r17
-- R17-06). `reduced`: reduced motion (a short fade, final values).
export type Phase = { name: string, start: number, duration: number }

function MotionPlan.rewardTimeline(coins: number, bonus: number, xp: number, reveal: boolean, fill: boolean, reduced: boolean): { Phase }
	local T = MotionPlan.T
	local phases: { Phase } = {}
	if not reveal then
		return phases
	end
	if reduced then
		table.insert(phases, { name = "fade", start = 0, duration = T.reducedFade })
		return phases
	end
	table.insert(phases, { name = "panel", start = 0, duration = T.panelEnter })
	table.insert(phases, { name = "heading", start = T.headingDelay, duration = T.headingIn })
	local t = T.headingDelay + T.headingIn
	table.insert(phases, { name = "impact", start = t, duration = T.impact })
	t += T.impact
	local count = MotionPlan.countDuration(coins, T.coinCount, T.coinCountMin, T.coinCountMax)
	if count > 0 then
		table.insert(phases, { name = "coins", start = t, duration = count })
		t += count
		-- The payoff runs on into the XP arrival (overlapping action).
		table.insert(phases, { name = "coinsDone", start = t, duration = T.coinFlourish })
	end
	if bonus > 0 then
		-- With the coin result: a brief reveal of its own row, never added to the coins.
		table.insert(phases, { name = "bonus", start = t - math.min(count, T.impact), duration = T.impact })
	end
	t += T.gap
	-- XP arrives after the coins and its award label counts up from zero; the bar moves along
	-- the same progress.
	local xpCount = MotionPlan.countDuration(xp, T.xpCount, T.xpCountMin, T.xpCountMax)
	table.insert(phases, { name = "xpArrive", start = t, duration = T.xpArrive })
	t += T.xpArrive
	if xpCount > 0 then
		table.insert(phases, { name = "xpCount", start = t, duration = xpCount })
		if fill then
			table.insert(phases, { name = "xpFill", start = t, duration = xpCount })
			table.insert(phases, { name = "xpDone", start = t + xpCount, duration = T.xpFinale })
		end
	end
	return phases
end

-- When the whole timeline has finished.
function MotionPlan.total(phases: { Phase }): number
	local e = 0
	for _, p in phases do
		e = math.max(e, p.start + p.duration)
	end
	return e
end

function MotionPlan.find(phases: { Phase }, name: string): Phase?
	for _, p in phases do
		if p.name == name then
			return p
		end
	end
	return nil
end

return MotionPlan

--!strict
-- The game-wide motion language as numbers and curves (Astra r15 motion-and-reward-spec):
-- press, pop (one restrained overshoot), settle, the slowing count-up, the rate-limited count
-- ticks, the XP fill across rank thresholds and the shift reward timeline. Pure: no services,
-- no instances, so the timing and the values a presentation ends on can be checked offline.
-- Motion (the Roblox side) plays these; the starting settings are Astra's, not measured
-- Papa's timings, and are tuned here only.

local MotionPlan = {}

-- Seconds and scales. One table so a business or a re-skin can retune the feel in one place.
MotionPlan.T = {
	-- Buttons: visual scale 1 -> 0.97 in about 70 ms, back in 110 ms (spec 2).
	pressScale = 0.97,
	pressIn = 0.07,
	pressOut = 0.11,
	-- Panel enter: 0.96 -> 1.01 -> 1.00 with a small upward settle, 220 ms (spec 4).
	panelFrom = 0.96,
	panelPeak = 1.01,
	panelEnter = 0.22,
	panelRise = 8, -- px the panel settles up from
	-- Heading: begins about 100 ms after the panel, 140 ms fade/slide.
	headingDelay = 0.10,
	headingIn = 0.14,
	headingRise = 6,
	-- Coin impact: lands from a few px above, 0.94 -> 1.035 -> 1.00, about 140 ms.
	impactFrom = 0.94,
	impactPeak = 1.035,
	impact = 0.14,
	impactDrop = 6,
	-- Coin count: 1,200 ms baseline, 900 to 1,500 ms by size of the award.
	coinCountMin = 0.9,
	coinCount = 1.2,
	coinCountMax = 1.5,
	-- XP arrival rises 4 to 8 phone px and settles, 180 ms; count/fill 900 ms (700 to 1,200).
	xpArrive = 0.18,
	xpRise = 6,
	xpCountMin = 0.7,
	xpCount = 0.9,
	xpCountMax = 1.2,
	-- A short pause between phases so each lands before the next asks for attention.
	gap = 0.08,
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

local function easeInOut(p: number): number
	p = clamp01(p)
	return 0.5 - math.cos(math.pi * p) / 2
end

-- Scale at progress p of a pop from `from` through one overshoot to `peak`, ending on 1.
function MotionPlan.pop(p: number, from: number, peak: number): number
	p = clamp01(p)
	local split = MotionPlan.POP_SPLIT
	if p < split then
		return from + (peak - from) * MotionPlan.easeOut(p / split)
	end
	return peak + (1 - peak) * easeInOut((p - split) / (1 - split))
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
-- `reveal`: this is the first showing of the shift (coins may count); `advance`: the XP is
-- accepted and may fill the bar; `reduced`: reduced motion (a short fade, final values).
export type Phase = { name: string, start: number, duration: number }

function MotionPlan.rewardTimeline(coins: number, bonus: number, xp: number, reveal: boolean, advance: boolean, reduced: boolean): { Phase }
	local T = MotionPlan.T
	local phases: { Phase } = {}
	if reduced then
		if reveal then
			table.insert(phases, { name = "fade", start = 0, duration = T.reducedFade })
		end
		return phases
	end
	local t = 0
	if reveal then
		table.insert(phases, { name = "panel", start = 0, duration = T.panelEnter })
		table.insert(phases, { name = "heading", start = T.headingDelay, duration = T.headingIn })
		t = T.headingDelay + T.headingIn
		table.insert(phases, { name = "impact", start = t, duration = T.impact })
		t += T.impact
		local count = MotionPlan.countDuration(coins, T.coinCount, T.coinCountMin, T.coinCountMax)
		if count > 0 then
			table.insert(phases, { name = "coins", start = t, duration = count })
			t += count
		end
		if bonus > 0 then
			-- With the coin result: a brief reveal of its own row, never added to the coins.
			table.insert(phases, { name = "bonus", start = t - math.min(count, T.impact), duration = T.impact })
		end
		t += T.gap
	end
	-- XP arrives with the first showing and its award label counts up from zero; the bar
	-- moves along the same progress only once the award is accepted (advance). A save that
	-- confirms later fills the bar alone: the label is not counted again.
	local count = MotionPlan.countDuration(xp, T.xpCount, T.xpCountMin, T.xpCountMax)
	if reveal then
		table.insert(phases, { name = "xpArrive", start = t, duration = T.xpArrive })
		t += T.xpArrive
		if count > 0 then
			table.insert(phases, { name = "xpCount", start = t, duration = count })
		end
	end
	if advance and count > 0 then
		table.insert(phases, { name = "xpFill", start = t, duration = count })
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

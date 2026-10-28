--!strict
-- The game-wide motion language as numbers and curves (Astra r15 motion-and-reward-spec):
-- press, pop (one restrained overshoot), settle, the slowing count-up, the rate-limited count
-- ticks, the XP fill across rank thresholds, the shift reward timeline and the curves its
-- light effects follow (twinkle, coin spin, ring, sweep, the rays' turn, tossed coins' arcs,
-- confetti), and the save line's wave, spinner, check and hop.
-- Pure: no services, no instances, so the timing and the values a presentation ends on can
-- be checked offline. Motion and Shine (the Roblox side) play these. The starting settings
-- are Astra's; the end-of-shift sequence is retuned here for Lawson's 2026-10-28 direction (a
-- richer, more rewarding card), not from measured Papa's timings.

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
	-- The backdrop (Astra's ui_scrim) settles at this transparency: deeper than its earlier
	-- 0.55, so the card and its light stand out (Lawson 2026-10-28).
	scrim = 0.4,
	-- The card's glory: slow light rays behind it and a warm glow round its edge. Their light
	-- (1 = full) comes up as the panel lands, surges with each payoff and eases to a resting
	-- level when the sequence ends; the rays turn slowly, with a faster whirl at the start.
	gloryIn = 0.6,
	gloryRest = 0.55,
	glorySurge = 1.4,
	glorySurgeTime = 0.7,
	gloryRestIn = 0.9,
	raysSpin = 6, -- degrees a second
	raysWhirl = 40, -- degrees added while the panel lands
	raysWhirlTime = 1.4,
	-- Glows behind the coin and the star: up as each arrives, the coin's brighter as it counts;
	-- a payoff blooms a larger glow out (a flare); both keep a soft glow at rest.
	glowIn = 0.35,
	coinGlowCount = 0.3, -- transparency the coin's glow reaches as its count ends
	coinGlowRest = 0.62,
	starGlowRest = 0.68,
	flare = 0.7,
	-- Small coins tossed out of the coin at its payoff, more for a larger award (bounded).
	toss = 0.9,
	tossMin = 5,
	tossMax = 12,
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
	-- Confetti as the end-of-shift card lands (Lawson 2026-10-28): a little burst from behind
	-- the card's top edge, thrown up and out, slowed by the air and fluttering down. Speeds
	-- and sizes are for the desktop card (560 px wide) and scale with the card.
	confettiAt = 0.06, -- seconds after the panel starts to land
	confetti = 46, -- pieces (the phone card throws fewer)
	confettiCompact = 30,
	confettiSpeed = 1040, -- px a second they leave at, at most
	confettiDrag = 3.1, -- how fast the air slows them (1/s)
	confettiFall = 250, -- px a second they flutter down at, at most
	confettiSize = 20, -- px: the length of an average piece
	confettiLife = 2.5,
	confettiFront = 0.35, -- share of pieces in front of the card; the rest fly behind it
	-- The save line (Lawson 2026-10-28). While the save runs, "Saving..." waves letter by
	-- letter (each letter hops in turn, then the line rests) beside a spinner whose arc
	-- breathes as it turns. When the save lands the spinner whirls and closes into a ring, the
	-- ring fills into a green disc with one overshoot, the check draws on, and the words hop
	-- once (one small bounce) into "Saved!", which fades out after a couple of seconds.
	saveWaveStep = 0.07, -- seconds between one letter's hop and the next
	saveWaveHop = 0.44, -- seconds one letter's hop lasts
	saveWaveRest = 0.36, -- seconds the line rests between waves
	saveWaveLift = 0.24, -- how high a letter hops, in text heights
	saveTurn = 0.9, -- seconds per turn of the spinner
	saveArcMin = 0.25, -- the spinner's arc, as a share of its ring, breathing between these
	saveArcMax = 0.72,
	saveBreath = 1.6, -- seconds per breath of the arc
	saveWhirl = 0.34, -- seconds the spinner whirls and closes into a ring as the save lands
	saveWhirlTurns = 1.25, -- extra turns while it whirls
	saveDiscAt = 0.2, -- seconds into the landing the ring starts to fill into the disc
	saveDisc = 0.32,
	saveDiscFrom = 0.4,
	saveDiscPeak = 1.18,
	saveCheckAt = 0.34, -- seconds into the landing the check starts to draw
	saveCheck = 0.3,
	saveWordAt = 0.3, -- seconds into the landing the words change and hop
	saveHop = 0.46,
	saveHopLift = 0.42, -- in text heights
	saveSlide = 0.4, -- share of the hop the line takes to re-centre on the shorter word
	saveHold = 2, -- seconds "Saved!" stays after it has landed
	saveFade = 0.45,
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

-- The rays' turn (degrees) at `clock` seconds of the motion clock, `since` seconds after the
-- panel began to land: a steady slow turn on the clock itself (so rays built again carry on
-- at the same angle), plus a whirl that eases out while the panel lands.
function MotionPlan.raysTurn(clock: number, since: number): number
	local T = MotionPlan.T
	return T.raysSpin * clock + T.raysWhirl * MotionPlan.easeOut(math.max(since, 0) / T.raysWhirlTime)
end

-- Where a tossed object is `t` seconds after leaving with velocity (vx, vy) px a second under
-- `gravity` px a second squared (screen y grows downward).
function MotionPlan.arc(t: number, vx: number, vy: number, gravity: number): (number, number)
	return vx * t, vy * t + 0.5 * gravity * t * t
end

-- How many small coins a payoff tosses: a few more for each doubling of the award, bounded.
function MotionPlan.tossCount(coins: number): number
	local T = MotionPlan.T
	if coins <= 0 then
		return 0
	end
	return math.clamp(T.tossMin + math.floor(math.log(coins + 1, 2)), T.tossMin, T.tossMax)
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

------------------------------------------------------------------------------------------
-- Confetti and the save line

-- Where a piece of confetti is `t` seconds after leaving with velocity (vx, vy) px a second,
-- slowed by air drag `drag` (1/s) and falling under `gravity` px a second squared (screen y
-- grows downward): it slows quickly and never falls faster than gravity / drag.
function MotionPlan.confetti(t: number, vx: number, vy: number, drag: number, gravity: number): (number, number)
	local e = 1 - math.exp(-drag * t)
	return vx / drag * e, vy / drag * e + gravity / drag * (t - e / drag)
end

-- Letter i (from 1) of an n-letter waiting word at `t` seconds: how far it has hopped (0 at
-- rest, 1 at the top). Each letter hops in turn, easing up and down; the line then rests
-- before the next wave.
function MotionPlan.saveWaveCycle(n: number): number
	local T = MotionPlan.T
	return math.max(n - 1, 0) * T.saveWaveStep + T.saveWaveHop + T.saveWaveRest
end

function MotionPlan.saveWave(t: number, i: number, n: number): number
	local T = MotionPlan.T
	local u = (t % MotionPlan.saveWaveCycle(n) - (i - 1) * T.saveWaveStep) / T.saveWaveHop
	if u <= 0 or u >= 1 then
		return 0
	end
	local s = math.sin(math.pi * u)
	return s * s
end

-- The spinner `t` seconds into a wait: its turn (degrees, 0..360) and its arc (share of the
-- ring), breathing between T.saveArcMin and T.saveArcMax.
function MotionPlan.spinner(t: number): (number, number)
	local T = MotionPlan.T
	local breath = 0.5 - 0.5 * math.cos(2 * math.pi * t / T.saveBreath)
	return (360 * t / T.saveTurn) % 360, T.saveArcMin + (T.saveArcMax - T.saveArcMin) * breath
end

-- A ring drawn as a stroke cut by a linear gradient shows the arc of `share` of the ring
-- (centred on the gradient's direction) when the gradient goes from hidden to shown at this
-- point along it: 1 shows nothing, 0 the whole ring.
function MotionPlan.arcCut(share: number): number
	return (1 + math.cos(math.pi * clamp01(share))) / 2
end

-- The check drawing on at progress p, like a pen: how much of its short stroke and of its
-- long stroke shows (0..1 each). `split` is the short stroke's share of the whole length.
function MotionPlan.checkDraw(p: number, split: number): (number, number)
	local s = easeInOut(p)
	if s <= split then
		return if split > 0 then s / split else 1, 0
	end
	return 1, if split < 1 then (s - split) / (1 - split) else 1
end

-- The new words' hop at progress p: how high they are (in hop heights: up fast, down under
-- gravity, one small bounce, at rest at the end) and their scale (one overshoot, ending on 1).
local HOP_UP, HOP_DOWN = 0.34, 0.7
function MotionPlan.hop(p: number): (number, number)
	p = clamp01(p)
	local lift: number
	if p < HOP_UP then
		lift = MotionPlan.easeOut(p / HOP_UP)
	elseif p < HOP_DOWN then
		local d = (p - HOP_UP) / (HOP_DOWN - HOP_UP)
		lift = 1 - d * d
	else
		lift = 0.18 * math.sin(math.pi * (p - HOP_DOWN) / (1 - HOP_DOWN))
	end
	return lift, MotionPlan.pop(p, 0.86, 1.12)
end

-- How long after a save lands its "Saved!" line starts to fade, and how faded it is
-- (0 shown .. 1 gone) `since` seconds after it landed.
function MotionPlan.savedFadeStart(): number
	local T = MotionPlan.T
	return T.saveWordAt + T.saveHop + T.saveHold
end

function MotionPlan.savedFade(since: number): number
	local T = MotionPlan.T
	return easeInOut((since - MotionPlan.savedFadeStart()) / T.saveFade)
end

return MotionPlan

-- Checks for the shared motion language (MotionPlan, slice 5): the count-up ends exactly on
-- its value and never goes back, ticks stay under the rate limit and are never queued, a pop
-- ends on 1 after one overshoot, the XP bar carries overflow across rank thresholds, the light
-- curves (twinkle, coin spin, ring, sweep, turn-in, the rays' turn, tossed coins' arcs) start
-- and end where they must, and the shift reward timeline keeps Astra's order (panel, heading,
-- coin impact, coin count and its payoff, then XP and its payoff) inside its bounded length.
-- It plays on the first showing only. Numbers and order only: smoothness, feel and real-time
-- frame rate need Lawson's eyes on the running game, not this file.

local MotionPlan = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.MotionPlan)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local T = MotionPlan.T

-- Starting settings as Astra wrote them (spec 2 and 4), and the end-of-shift panel as
-- retuned for Lawson's richer card (2026-10-28).
check("press scale", T.pressScale, 0.97)
check("press in 70 ms", T.pressIn, 0.07)
check("press out 110 ms", T.pressOut, 0.11)
check("panel 360 ms", T.panelEnter, 0.36)
check("panel lands from 0.9", T.panelFrom, 0.9)
check("panel overshoot 1.03", T.panelPeak, 1.03)
check("coin count baseline 1.2 s", T.coinCount, 1.2)
check("xp count baseline 0.9 s", T.xpCount, 0.9)
check("tick rate 10/s", T.tickRate, 10)
check("xp rise within 4-8 px", T.xpRise >= 4 and T.xpRise <= 8, true)
check("count swell is slight", T.countSwell > 1 and T.countSwell <= 1.05, true)
check("payoff peaks above the swell", T.flourishPeak > T.countSwell, true)

-- Ease-out curve: 0 at 0, 1 at 1, rising, slower at the end than at the start.
check("ease 0", MotionPlan.easeOut(0), 0)
check("ease 1", MotionPlan.easeOut(1), 1)
check("ease clamps below", MotionPlan.easeOut(-1), 0)
check("ease clamps above", MotionPlan.easeOut(2), 1)
check("ease fast start", MotionPlan.easeOut(0.1) - MotionPlan.easeOut(0) > MotionPlan.easeOut(1) - MotionPlan.easeOut(0.9), true)

-- Count-up: monotonic integers, exact final at and after the duration, sampled at 60, 30
-- and 7 frames a second (a slow device skips values, it never shows a wrong one).
for _, final in { 0, 1, 2, 7, 30, 123, 4567, 99999 } do
	for _, fps in { 60, 30, 7 } do
		local duration = 1.2
		local last, monotonic, integers, inRange = -1, true, true, true
		local t = 0
		while t < duration do
			local n = MotionPlan.countValue(final, t, duration)
			monotonic = monotonic and n >= last
			integers = integers and n == math.floor(n)
			inRange = inRange and n >= 0 and n <= final
			last = n
			t += 1 / fps
		end
		local name = string.format("count %d at %d fps", final, fps)
		check(name .. ": monotonic", monotonic, true)
		check(name .. ": integers", integers, true)
		check(name .. ": within 0..final", inRange, true)
		check(name .. ": exact at end", MotionPlan.countValue(final, duration, duration), final)
		check(name .. ": exact after end", MotionPlan.countValue(final, duration + 5, duration), final)
	end
	check(string.format("count %d starts at 0", final), MotionPlan.countValue(final, 0, 1.2), 0)
	check(string.format("count %d zero duration is final", final), MotionPlan.countValue(final, 0, 0), final)
end
-- The last few values are perceptible: the final 10 % of time covers under 1 % of a large count.
do
	local final = 1000
	local at90 = MotionPlan.countValue(final, 0.9 * 1.2, 1.2)
	check("count slows at the end", final - at90 <= 10 and final - at90 >= 1, true)
end

-- Count durations: zero for nothing, bounded for small and large awards.
check("coin duration 0", MotionPlan.countDuration(0, T.coinCount, T.coinCountMin, T.coinCountMax), 0)
for _, amount in { 1, 3, 30, 300, 1e6 } do
	local d = MotionPlan.countDuration(amount, T.coinCount, T.coinCountMin, T.coinCountMax)
	check(string.format("coin duration %g bounded", amount), d >= T.coinCountMin and d <= T.coinCountMax, true)
	local x = MotionPlan.countDuration(amount, T.xpCount, T.xpCountMin, T.xpCountMax)
	check(string.format("xp duration %g bounded", amount), x >= T.xpCountMin and x <= T.xpCountMax, true)
end
check("coin duration 30 is the baseline", near(MotionPlan.countDuration(30, T.coinCount, T.coinCountMin, T.coinCountMax), 1.2), true)
check("small award counts shorter", MotionPlan.countDuration(3, 1.2, 0.9, 1.5) < MotionPlan.countDuration(300, 1.2, 0.9, 1.5), true)

-- Ticks: at most 10 a second at any frame rate, none for unchanged frames, none queued (a
-- burst after a long frame gives one tick, not the missed ones).
for _, fps in { 240, 60, 30 } do
	local ticker = MotionPlan.ticker()
	local ticks, t = 0, 0
	while t < 1.2 do
		if MotionPlan.tick(ticker, t, true) then
			ticks += 1
		end
		t += 1 / fps
	end
	check(string.format("ticks at %d fps <= 13 in 1.2 s", fps), ticks <= 13, true)
	check(string.format("ticks at %d fps >= 8 in 1.2 s", fps), ticks >= 8, true)
end
do
	local ticker = MotionPlan.ticker()
	check("no tick when unchanged", MotionPlan.tick(ticker, 0, false), false)
	check("first change ticks", MotionPlan.tick(ticker, 0, true), true)
	check("too soon: dropped", MotionPlan.tick(ticker, 0.05, true), false)
	check("after a 2 s stall: one tick", MotionPlan.tick(ticker, 2.05, true), true)
	check("after a 2 s stall: not a second", MotionPlan.tick(ticker, 2.06, true), false)
	check("tick count", ticker.count, 2)
end

-- Pop: starts at `from`, one overshoot no higher than `peak`, ends on exactly 1.
for _, case in { { 0.96, 1.01 }, { 0.94, 1.035 }, { 0.6, 1.15 }, { 1.18, 0.98 } } do
	local from, peak = case[1], case[2]
	local name = string.format("pop %.3f->%.3f", from, peak)
	check(name .. ": start", near(MotionPlan.pop(0, from, peak), from), true)
	check(name .. ": end", MotionPlan.pop(1, from, peak), 1)
	check(name .. ": peak at split", near(MotionPlan.pop(MotionPlan.POP_SPLIT, from, peak), peak), true)
	local lo, hi = math.min(from, peak, 1), math.max(from, peak, 1)
	local bounded = true
	for i = 0, 100 do
		local v = MotionPlan.pop(i / 100, from, peak)
		bounded = bounded and v >= lo - 1e-9 and v <= hi + 1e-9
	end
	check(name .. ": never beyond from/peak", bounded, true)
end

-- Light curves (Shine plays these).
check("ease in-out 0", MotionPlan.easeInOut(0), 0)
check("ease in-out 1", near(MotionPlan.easeInOut(1), 1), true)
check("ease in-out half", near(MotionPlan.easeInOut(0.5), 0.5), true)
do
	-- Turn-in: from the tilt, past upright once, ending exactly upright.
	check("tilt starts tilted", near(MotionPlan.tilt(0, -16), -16), true)
	check("tilt ends upright", MotionPlan.tilt(1, -16), 0)
	local over, back = 0, false
	for i = 0, 100 do
		local r = MotionPlan.tilt(i / 100, -16)
		if r > 0 then
			back = true
			over = math.max(over, r)
		end
	end
	check("tilt passes upright once", back, true)
	check("tilt overshoot small", over <= 16 * 0.12 + 1e-9, true)
	-- Twinkle: from nothing, flares to at most 1.12, fades out, ends gone.
	local s0, t0 = MotionPlan.twinkle(0)
	local s1, t1 = MotionPlan.twinkle(1)
	check("twinkle starts at zero size", s0, 0)
	check("twinkle starts lit", t0, 0)
	check("twinkle ends at zero size", near(s1, 0), true)
	check("twinkle ends gone", t1, 1)
	local maxScale, lastT, fades = 0, 0, true
	for i = 0, 100 do
		local sc, tr = MotionPlan.twinkle(i / 100)
		maxScale = math.max(maxScale, sc)
		fades = fades and tr >= lastT - 1e-9
		lastT = tr
	end
	check("twinkle flare bounded", maxScale <= 1.12 + 1e-9 and maxScale >= 1.1, true)
	check("twinkle only fades out", fades, true)
	-- Coin spin: face-on at both ends, edge-on in between, never thinner than 8 %.
	local w0, sh0 = MotionPlan.flip(0, T.coinTurns)
	local w1, sh1 = MotionPlan.flip(1, T.coinTurns)
	check("spin starts face-on", near(w0, 1) and near(sh0, 0), true)
	check("spin ends face-on", near(w1, 1) and near(sh1, 0), true)
	local thinnest, shadeOk = 1, true
	for i = 0, 400 do
		local w, sh = MotionPlan.flip(i / 400, T.coinTurns)
		thinnest = math.min(thinnest, w)
		shadeOk = shadeOk and sh >= 0 and sh <= 0.6 + 1e-9
	end
	check("spin passes edge-on", near(thinnest, 0.08), true)
	check("spin shade bounded", shadeOk, true)
	-- Ring: bright at the start, gone at the end, never brighter again.
	check("ring starts at its peak", near(MotionPlan.ringFade(0, 0.05), 0.05), true)
	check("ring ends gone", MotionPlan.ringFade(1, 0.05), 1)
	local last, monotonic = 0, true
	for i = 0, 100 do
		local v = MotionPlan.ringFade(i / 100, 0.05)
		monotonic = monotonic and v >= last - 1e-9
		last = v
	end
	check("ring only fades", monotonic, true)
	-- Sweep: off one side to off the other, never turning back.
	check("sweep starts off the left", near(MotionPlan.sweep(0), -MotionPlan.SWEEP), true)
	check("sweep ends off the right", near(MotionPlan.sweep(1), MotionPlan.SWEEP), true)
	last, monotonic = -math.huge, true
	for i = 0, 100 do
		local v = MotionPlan.sweep(i / 100)
		monotonic = monotonic and v >= last
		last = v
	end
	check("sweep one way", monotonic, true)
	-- Rays: a steady turn on the clock plus a landing whirl that ends; a card built again
	-- (no whirl) shows the same angle as one whose whirl has ended.
	check("rays whirl starts at nothing", near(MotionPlan.raysTurn(0, 0), 0), true)
	check("rays whirl ends", near(MotionPlan.raysTurn(10, 5) - MotionPlan.raysTurn(10, 4), 0), true)
	check("rays rebuilt carry on", near(MotionPlan.raysTurn(12.5, math.huge), MotionPlan.raysTurn(12.5, T.raysWhirlTime)), true)
	check("rays turn slowly at rest", near(MotionPlan.raysTurn(11, math.huge) - MotionPlan.raysTurn(10, math.huge), T.raysSpin), true)
	last, monotonic = -math.huge, true
	for i = 0, 200 do
		local v = MotionPlan.raysTurn(i / 100, i / 100)
		monotonic = monotonic and v >= last
		last = v
	end
	check("rays never turn back", monotonic, true)
	-- Tossed coins: leave from the centre, rise, then fall under gravity.
	local x0, y0 = MotionPlan.arc(0, 50, -300, 1200)
	check("toss starts at the centre", x0 == 0 and y0 == 0, true)
	local _, yTop = MotionPlan.arc(0.25, 50, -300, 1200)
	local _, yEnd = MotionPlan.arc(0.9, 50, -300, 1200)
	check("toss rises to its top", near(yTop, -37.5), true)
	check("toss falls back past its start", yEnd > 0, true)
	-- How many: none for nothing, a few more per doubling of the award, bounded.
	check("toss none for nothing", MotionPlan.tossCount(0), 0)
	check("toss one coin", MotionPlan.tossCount(1), T.tossMin + 1)
	check("toss grows", MotionPlan.tossCount(100) > MotionPlan.tossCount(5), true)
	check("toss bounded", MotionPlan.tossCount(1e9), T.tossMax)
	-- The card's light: up with the panel, a surge above full, a lower resting level; the
	-- backdrop deepened from 0.55 but still lets the game show through.
	check("glory rests lower than full", T.gloryRest > 0 and T.gloryRest < 1, true)
	check("glory surges above full", T.glorySurge > 1, true)
	check("backdrop deeper than before", T.scrim < 0.55 and T.scrim >= 0.3, true)
	check("coin glow brightens as it counts", T.coinGlowCount < T.coinGlowRest, true)
end

-- XP bar across thresholds (100 XP a rank).
local function seg(fromXp: number, toXp: number): { MotionPlan.Segment }
	return MotionPlan.xpSegments(fromXp, toXp, 100)
end
local function at(fromXp: number, toXp: number, p: number): (number, number)
	return MotionPlan.xpAt(seg(fromXp, toXp), p)
end
do
	-- Partial rank: 40 -> 70 stays in rank 1.
	local s = seg(40, 70)
	check("partial: one segment", #s, 1)
	check("partial: from .4", near(s[1].from, 0.4), true)
	check("partial: to .7", near(s[1].to, 0.7), true)
	local r, f = at(40, 70, 0)
	check("partial: starts at real progress", r == 1 and near(f, 0.4), true)
	r, f = at(40, 70, 1)
	check("partial: ends at 70", r == 1 and near(f, 0.7), true)
	-- One rank-up: 80 -> 130 fills to the boundary, then carries 30.
	s = seg(80, 130)
	check("rank-up: two segments", #s, 2)
	check("rank-up: first fills to 1", near(s[1].to, 1), true)
	check("rank-up: second from 0", s[2].rank == 2 and near(s[2].from, 0), true)
	check("rank-up: overflow .3", near(s[2].to, 0.3), true)
	check("rank-up: shares by XP", near(s[1].share, 0.4) and near(s[2].share, 0.6), true)
	r, f = at(80, 130, 1)
	check("rank-up: ends rank 2 at .3", r == 2 and near(f, 0.3), true)
	r, f = at(80, 130, 0.2)
	check("rank-up: mid first segment", r == 1 and near(f, 0.9), true)
	-- Several rank-ups: 50 -> 420 passes ranks 1..4 and ends in rank 5 at .2.
	s = seg(50, 420)
	check("multi: five segments", #s, 5)
	local total = 0
	for _, x in s do
		total += x.share
	end
	check("multi: shares sum to 1", near(total, 1), true)
	r, f = at(50, 420, 1)
	check("multi: ends rank 5 at .2", r == 5 and near(f, 0.2), true)
	local lastRank, ranksMonotonic = 0, true
	for i = 0, 50 do
		local rr = at(50, 420, i / 50)
		ranksMonotonic = ranksMonotonic and rr >= lastRank
		lastRank = rr
	end
	check("multi: rank never goes back", ranksMonotonic, true)
	-- Exactly on a threshold: 70 -> 100 rests on rank 2 at zero.
	r, f = at(70, 100, 1)
	check("exact threshold: rank 2 at 0", r == 2 and near(f, 0), true)
	-- Nothing earned: the bar holds its real progress.
	s = seg(55, 55)
	check("zero: one segment", #s, 1)
	r, f = at(55, 55, 1)
	check("zero: holds .55", r == 1 and near(f, 0.55), true)
	check("bad threshold: no segments", #MotionPlan.xpSegments(10, 20, 0), 0)
end

-- Reward timeline.
local function names(phases: { MotionPlan.Phase }): string
	local out = {}
	for _, p in phases do
		table.insert(out, p.name)
	end
	return table.concat(out, ",")
end
do
	local tl = MotionPlan.rewardTimeline(30, 0, 30, true, true, false)
	check("ordinary: phases", names(tl), "panel,heading,impact,coins,coinsDone,xpArrive,xpCount,xpFill,xpDone")
	local total = MotionPlan.total(tl)
	check("ordinary: 3.2-3.8 s", total >= 3.2 and total <= 3.8, true)
	local panel = MotionPlan.find(tl, "panel") :: MotionPlan.Phase
	local heading = MotionPlan.find(tl, "heading") :: MotionPlan.Phase
	local impact = MotionPlan.find(tl, "impact") :: MotionPlan.Phase
	local coins = MotionPlan.find(tl, "coins") :: MotionPlan.Phase
	local payoff = MotionPlan.find(tl, "coinsDone") :: MotionPlan.Phase
	local arrive = MotionPlan.find(tl, "xpArrive") :: MotionPlan.Phase
	local xpCount = MotionPlan.find(tl, "xpCount") :: MotionPlan.Phase
	local xpFill = MotionPlan.find(tl, "xpFill") :: MotionPlan.Phase
	local xpDone = MotionPlan.find(tl, "xpDone") :: MotionPlan.Phase
	check("heading while the panel lands", heading.start > 0 and heading.start < panel.duration, true)
	check("heading ends before impact", heading.start + heading.duration <= impact.start + 1e-9, true)
	check("count after impact", coins.start >= impact.start + impact.duration - 1e-9, true)
	check("payoff when the count lands", near(payoff.start, coins.start + coins.duration), true)
	check("XP after coins settle", arrive.start >= coins.start + coins.duration, true)
	check("XP arrives as the payoff plays out", arrive.start < payoff.start + payoff.duration, true)
	check("XP count after arrival", near(xpCount.start, arrive.start + arrive.duration), true)
	check("fill with the XP count", near(xpFill.start, xpCount.start) and near(xpFill.duration, xpCount.duration), true)
	check("XP payoff when the bar settles", near(xpDone.start, xpFill.start + xpFill.duration), true)
	check("XP payoff ends the sequence", near(total, xpDone.start + xpDone.duration), true)

	-- A pending award fills too (as a projection): the timeline is the same whatever the
	-- save state. Without a bar the XP counts and nothing fills.
	tl = MotionPlan.rewardTimeline(30, 0, 30, true, false, false)
	check("no bar: XP counts, nothing fills", names(tl), "panel,heading,impact,coins,coinsDone,xpArrive,xpCount")
	tl = MotionPlan.rewardTimeline(30, 25, 30, true, true, false)
	check("bonus: own reveal", names(tl), "panel,heading,impact,coins,coinsDone,bonus,xpArrive,xpCount,xpFill,xpDone")
	local bonus = MotionPlan.find(tl, "bonus") :: MotionPlan.Phase
	local c2 = MotionPlan.find(tl, "coins") :: MotionPlan.Phase
	check("bonus: with the coin result", bonus.start < c2.start + c2.duration and bonus.start + bonus.duration <= c2.start + c2.duration + 1e-9, true)
	tl = MotionPlan.rewardTimeline(0, 0, 0, true, true, false)
	check("zero: quiet reveal, no counts", names(tl), "panel,heading,impact,xpArrive")
	check("zero: short", MotionPlan.total(tl) < 1, true)
	tl = MotionPlan.rewardTimeline(1e6, 500, 1e6, true, true, false)
	check("large: bounded", MotionPlan.total(tl) <= 4.4, true)
	-- A later showing (the save's acceptance, a resize, a correction) never replays.
	tl = MotionPlan.rewardTimeline(30, 0, 30, false, true, false)
	check("later showing: nothing replays", #tl, 0)
	tl = MotionPlan.rewardTimeline(30, 0, 30, false, false, false)
	check("rebuild: nothing plays", #tl, 0)
	tl = MotionPlan.rewardTimeline(30, 25, 30, true, true, true)
	check("reduced: fade only", names(tl), "fade")
	check("reduced: short", MotionPlan.total(tl) <= 0.2, true)
	tl = MotionPlan.rewardTimeline(30, 0, 30, false, true, true)
	check("reduced later showing: nothing plays", #tl, 0)
end

local report = string.format("motion checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

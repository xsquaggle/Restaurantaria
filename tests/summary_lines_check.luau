-- Checks for the shift summary's save wording (SummaryLines): the lifetime shift count only
-- appears once the shift is settled, and a failed save asks for a retry instead of claiming
-- the rewards are kept. Run from the Studio command bar after a sync, or offline with
-- tests/offline/run.py. Text only: this does not check layout, wrapping or the button.

local SummaryLines = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.SummaryLines)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local function lines(settlement: string?, shifts: number): { string }
	return SummaryLines.build({ xp = 3, settlement = settlement, profile = { rank = 1, shiftsCompleted = shifts } })
end

local l = lines("pending", 0)
check("pending: experience", l[1], "Experience: +3")
check("pending: no count", l[2], "Rank 1")
check("pending: saving", l[3], "Saving...")
check("pending: not settled", SummaryLines.settled({ settlement = "pending" }), false)

l = lines("retry", 0)
check("retry: no count", l[2], "Rank 1")
check("retry: wording", l[3], "Save not confirmed. Please retry.")
check("retry: not settled", SummaryLines.settled({ settlement = "retry" }), false)

l = lines("saved", 1)
check("saved: count", l[2], "Rank 1 · 1 shift completed")
check("saved: wording", l[3], "Progress saved")
check("saved: settled", SummaryLines.settled({ settlement = "saved" }), true)

l = lines("saved", 2)
check("saved: plural", l[2], "Rank 1 · 2 shifts completed")

l = lines("session", 1)
check("session: count", l[2], "Rank 1 · 1 shift completed")
check("session: wording", l[3], "Progress not saved")
check("session: settled", SummaryLines.settled({ settlement = "session" }), true)

for _, settlement in { "pending", "retry", "saved", "session" } do
	for _, line in lines(settlement, 0) do
		check(settlement .. ": never 'Rewards kept'", string.find(line, "Rewards kept", 1, true), nil)
	end
end

-- The summary model (SummaryLines.model): the XP bar runs on the real per-rank threshold;
-- before the save has the shift it shows the award as a labelled projection from the profile
-- as it stands (Astra r17 R17-06); the completed day comes from the receipt.
local function snap(settlement: string?, recorded: boolean, profileXp: number?, earned: number): any
	return {
		xp = earned,
		tips = 7,
		tutorialBonus = 0,
		settlement = settlement,
		recorded = recorded,
		day = 3,
		completedShiftDay = 3,
		customers = { { status = "served" }, { status = "served" }, { status = "waiting" } },
		profile = { rank = 1, shiftsCompleted = if recorded then 3 else 2, xp = profileXp },
	}
end

local m = SummaryLines.model(snap("pending", false, 40, 30), 100)
check("model pending: day from receipt", m.day, 3)
check("model pending: served", m.served, 2)
check("model pending: coins", m.coins, 7)
check("model pending: xp earned", m.xpEarned, 30)
check("model pending: bar not counted", m.bar and m.bar.counted, false)
check("model pending: bar projected", m.bar and m.bar.projected, true)
check("model pending: from saved xp", m.bar and m.bar.fromXp, 40)
check("model pending: to saved + earned", m.bar and m.bar.toXp, 70)
check("model pending: shows the projection", m.bar and m.bar.into, 70)
check("model pending: confirmed part solid", m.bar and m.bar.solidFraction, 0.4)
check("model pending: need = xpPerRank", m.bar and m.bar.need, 100)
check("model pending: caption says projected", m.xpCaption, "Projected: 70 / 100 XP to Rank 2")
check("model pending: standby", m.action.mode, "standby")
check("model pending: standby says wait", m.action.label, "Please wait")
check("model pending: xp label pending", m.xpLabel, "+30 XP · save pending")
check("model pending: one status", m.status, "Saving...")
check("model pending: tone", m.tone, "pending")

m = SummaryLines.model(snap("saved", true, 70, 30), 100)
check("model saved: bar counted", m.bar and m.bar.counted, true)
check("model saved: not a projection", m.bar and m.bar.projected, false)
check("model saved: all solid", m.bar and m.bar.solidFraction, 0.7)
check("model saved: into", m.bar and m.bar.into, 70)
check("model saved: fraction", m.bar and m.bar.fraction, 0.7)
check("model saved: from", m.bar and m.bar.fromXp, 40)
check("model saved: to", m.bar and m.bar.toXp, 70)
check("model saved: no rank up", m.bar and m.bar.rankUp, false)
check("model saved: caption", m.xpCaption, "70 / 100 XP to Rank 2")
check("model saved: ready", m.action.mode, "ready")
check("model saved: label", m.action.label, "Next shift")
check("model saved: xp label plain", m.xpLabel, "+30 XP")
check("model saved: tone", m.tone, "saved")

m = SummaryLines.model(snap("saved", true, 120, 30), 100)
check("model rank up: rank", m.rank, 2)
check("model rank up: flag", m.bar and m.bar.rankUp, true)
check("model rank up: into", m.bar and m.bar.into, 20)
check("model rank up: caption", m.xpCaption, "20 / 100 XP to Rank 3")

m = SummaryLines.model(snap("saved", true, 70, 30), 50)
check("model threshold follows config: rank", m.rank, 2)
check("model threshold follows config: need", m.bar and m.bar.need, 50)

m = SummaryLines.model(snap("retry", false, 40, 30), 100)
check("model retry: action", m.action.mode, "retry")
check("model retry: label", m.action.label, "Retry save")
check("model retry: not counted", m.bar and m.bar.counted, false)
check("model retry: tone", m.tone, "warn")
check("model retry: xp label pending", m.xpLabel, "+30 XP · save pending")
check("model retry: still a projection", m.bar and m.bar.projected, true)

m = SummaryLines.model(snap("session", true, 70, 30), 100)
check("model session: ready", m.action.mode, "ready")
check("model session: tone", m.tone, "warn")
check("model session: status", m.status, "Progress not saved")
check("model session counted: xp label plain", m.xpLabel, "+30 XP")
m = SummaryLines.model(snap("session", false, 40, 30), 100)
check("model session uncounted: xp label", m.xpLabel, "+30 XP · not saved")

m = SummaryLines.model(snap("saved", true, 0, 0), 100)
check("model zero: fraction", m.bar and m.bar.fraction, 0)
check("model zero: caption", m.xpCaption, "0 / 100 XP to Rank 2")

-- No profile XP or no threshold: text only, no bar and no invented denominator.
m = SummaryLines.model(snap("saved", true, nil, 30), 100)
check("model no xp: no bar", m.bar, nil)
check("model no xp: no caption", m.xpCaption, nil)
check("model no xp: rank from profile", m.rank, 1)
m = SummaryLines.model(snap("saved", true, 70, 30), nil)
check("model no threshold: no bar", m.bar, nil)

-- Older snapshots without a day: the save's count, which holds the shift once recorded.
local old = snap("pending", false, 40, 30)
old.day, old.completedShiftDay = nil, nil
check("model day fallback pending", SummaryLines.model(old, 100).day, 3)
old = snap("saved", true, 70, 30)
old.day, old.completedShiftDay = nil, nil
check("model day fallback saved", SummaryLines.model(old, 100).day, 3)

-- Zero XP earned: no qualifier while pending, nothing projected.
m = SummaryLines.model(snap("pending", false, 40, 0), 100)
check("model pending zero: xp label", m.xpLabel, "+0 XP")
check("model pending zero: no projection", m.bar and m.bar.projected, false)
check("model pending zero: plain caption", m.xpCaption, "40 / 100 XP to Rank 2")

-- A pending award across a threshold: the projected rank is labelled, the confirmed part
-- belongs to the old rank (none of the new rank is confirmed), no "Rank up!" before the save.
m = SummaryLines.model(snap("pending", false, 80, 50), 100)
check("projected rank-up: rank", m.bar and m.bar.rank, 2)
check("projected rank-up: base rank", m.bar and m.bar.baseRank, 1)
check("projected rank-up: flagged", m.bar and m.bar.rankUp, true)
check("projected rank-up: nothing solid in the new rank", m.bar and m.bar.solidFraction, 0)
check("projected rank-up: caption", m.xpCaption, "Projected: 30 / 100 XP to Rank 3")
do
	local bar = m.bar :: any
	local text, small = SummaryLines.rankText(bar, 2, true, false)
	check("projected rank-up: rank words", text, "Projected Rank 2")
	check("projected rank-up: qualifier style", small, true)
	text = SummaryLines.rankText(bar, 1, false, false)
	check("projected rank-up: before the threshold", text, "Rank 1")
	text = SummaryLines.rankText(bar, 1, false, true)
	check("projected, tight layout: qualifier kept without a caption", text, "Projected Rank 1")
	check("projected rank-up: never 'Rank up!'", string.find(SummaryLines.rankText(bar, 2, true, true), "Rank up", 1, true), nil)
end
m = SummaryLines.model(snap("saved", true, 130, 50), 100)
do
	local bar = m.bar :: any
	check("accepted rank-up: rank words final", (SummaryLines.rankText(bar, 2, true, false)), "Rank 2 · Rank up!")
	check("accepted rank-up: while filling", (SummaryLines.rankText(bar, 2, false, false)), "Rank 2")
	check("accepted rank-up: tight unchanged", (SummaryLines.rankText(bar, 2, true, true)), "Rank 2 · Rank up!")
	check("caption at any point", SummaryLines.caption(bar, 1, 0.905), "90 / 100 XP to Rank 2")
end

-- The refresh key: any shown amount changes it, even with the same save wording.
do
	local a = snap("pending", false, 40, 30)
	a.shiftId = "K"
	a.tutorialBonus = 25
	local b = table.clone(a)
	check("receipt key: same snapshot, same key", SummaryLines.receiptKey(a), SummaryLines.receiptKey(b))
	b.tutorialBonus = 0
	check("receipt key: corrected bonus, same status", SummaryLines.receiptKey(a) ~= SummaryLines.receiptKey(b), true)
	b = table.clone(a)
	b.xp = 25
	check("receipt key: corrected award", SummaryLines.receiptKey(a) ~= SummaryLines.receiptKey(b), true)
	b = table.clone(a)
	b.tips = 9
	check("receipt key: corrected coins", SummaryLines.receiptKey(a) ~= SummaryLines.receiptKey(b), true)
	b = table.clone(a)
	b.settlement = "saved"
	check("receipt key: save result", SummaryLines.receiptKey(a) ~= SummaryLines.receiptKey(b), true)
end

-- Play-once presentation cues (motion brief rule 1): keyed by shift, outside the UI.
local state = {}
local function cue(settlement: string, recorded: boolean, id: string): any
	local sn = snap(settlement, recorded, if recorded then 70 else 40, 30)
	sn.shiftId = id
	return SummaryLines.presentation(state, sn, 100)
end
local c = cue("pending", false, "A")
check("cue first: reason", c.reason, "first")
check("cue first: reveal", c.revealEarnings, true)
check("cue first pending: xp moves as a projection", c.advanceXp, true)
check("cue first pending: nothing to confirm", c.confirmXp, false)
c = cue("pending", false, "A")
check("cue repeat pending: rebuild", c.reason, "rebuild")
check("cue repeat pending: no reveal", c.revealEarnings, false)
check("cue repeat pending: no fill", c.advanceXp, false)
c = cue("retry", false, "A")
check("cue retry: rebuild", c.reason, "rebuild")
c = cue("saved", true, "A")
check("cue saved: settled", c.reason, "settled")
check("cue saved: locks in once", c.confirmXp, true)
check("cue saved: no replayed fill", c.advanceXp, false)
check("cue saved: no second reveal", c.revealEarnings, false)
c = cue("saved", true, "A")
check("cue duplicate saved: rebuild", c.reason, "rebuild")
check("cue duplicate saved: no second lock-in", c.confirmXp, false)
c = cue("saved", true, "B")
check("cue new shift saved at once: first", c.reason, "first")
check("cue new shift saved at once: reveal", c.revealEarnings, true)
check("cue new shift saved at once: advance", c.advanceXp, true)
check("cue new shift saved at once: nothing to confirm later", c.confirmXp, false)
c = cue("saved", true, "B")
check("cue resize after: rebuild", c.reason, "rebuild")
check("cue resize after: no advance", c.advanceXp, false)

local report = string.format("summary lines checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

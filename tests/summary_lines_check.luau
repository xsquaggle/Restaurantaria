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

-- The summary model (SummaryLines.model): the XP bar runs on the real per-rank threshold and
-- only counts the shift once the save has it; the completed day comes from the receipt.
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
check("model pending: bar at saved xp", m.bar and m.bar.into, 40)
check("model pending: need = xpPerRank", m.bar and m.bar.need, 100)
check("model pending: caption", m.xpCaption, "Before this shift: 40 / 100 XP to Rank 2")
check("model pending: standby", m.action.mode, "standby")
check("model pending: standby says wait", m.action.label, "Please wait")
check("model pending: xp label pending", m.xpLabel, "+30 XP · save pending")
check("model pending: one status", m.status, "Saving...")
check("model pending: tone", m.tone, "pending")

m = SummaryLines.model(snap("saved", true, 70, 30), 100)
check("model saved: bar counted", m.bar and m.bar.counted, true)
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

-- Zero XP earned: no qualifier while pending.
m = SummaryLines.model(snap("pending", false, 40, 0), 100)
check("model pending zero: xp label", m.xpLabel, "+0 XP")

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
check("cue first pending: no xp advance", c.advanceXp, false)
c = cue("pending", false, "A")
check("cue repeat pending: rebuild", c.reason, "rebuild")
check("cue repeat pending: no reveal", c.revealEarnings, false)
c = cue("retry", false, "A")
check("cue retry: rebuild", c.reason, "rebuild")
c = cue("saved", true, "A")
check("cue saved: settled", c.reason, "settled")
check("cue saved: advance xp once", c.advanceXp, true)
check("cue saved: no second reveal", c.revealEarnings, false)
c = cue("saved", true, "A")
check("cue duplicate saved: rebuild", c.reason, "rebuild")
check("cue duplicate saved: no advance", c.advanceXp, false)
c = cue("saved", true, "B")
check("cue new shift saved at once: first", c.reason, "first")
check("cue new shift saved at once: reveal", c.revealEarnings, true)
check("cue new shift saved at once: advance", c.advanceXp, true)
c = cue("saved", true, "B")
check("cue resize after: rebuild", c.reason, "rebuild")
check("cue resize after: no advance", c.advanceXp, false)

local report = string.format("summary lines checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

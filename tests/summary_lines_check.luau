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

local report = string.format("summary lines checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

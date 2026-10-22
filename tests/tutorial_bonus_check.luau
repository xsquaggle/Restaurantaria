-- Checks for the one-time tutorial bonus: the top-up amount and the once-per-save flag in
-- SaveService.commitShift. Run from the Studio command bar (or the Studio MCP in Edit mode)
-- after a sync. Uses only the in-memory (failed-load) path, so nothing is written to a save.

local ServerScriptService = game:GetService("ServerScriptService")
local SaveService = require(ServerScriptService.Server.SaveService)
local ShiftService = require(ServerScriptService.Server.ShiftService)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

-- Top-up amounts, max(0, 4 - coins).
for _, case in { { 0, 4 }, { 1, 3 }, { 2, 2 }, { 3, 1 }, { 4, 0 }, { 5, 0 }, { 12, 0 } } do
	check("bonus for " .. case[1] .. " coins", ShiftService.tutorialBonusFor(case[1]), case[2])
end

-- A stand-in player key and a failed-load profile, so commitShift stays in memory.
local fake = {} :: any
local function freshProfile(data: any?)
	SaveService.profiles[fake] = {
		status = "failed",
		message = "test",
		data = data or { tips = 0, xp = 0, shiftsCompleted = 0, recentShiftIds = {}, unlockedRecipes = {}, tutorialBonusPaid = false },
	}
	return SaveService.profiles[fake]
end

-- Fresh save: a tutorial shift earning 1 coin gets 3, balance 4, flag set.
local p = freshProfile()
local function commit(id: string, tips: number, xp: number, bonus: number?): number?
	return SaveService.commitShift(fake, { shiftId = id, tips = tips, xp = xp, tutorialBonus = bonus }).bonusPaid
end
local paid = commit("t1", 1, 3, 3)
check("fresh: paid", paid, 3)
check("fresh: balance", p.data.tips, 4)
check("fresh: flag", p.data.tutorialBonusPaid, true)
-- The same shift id again pays nothing more; it reports what that shift was paid.
paid = commit("t1", 1, 3, 3)
check("same shift: reported", paid, 3)
check("same shift: balance", p.data.tips, 4)
-- A replayed tutorial (new shift id, same save) pays its coins but no second bonus.
paid = commit("t2", 1, 3, 3)
check("replay: paid", paid, 0)
check("replay: balance", p.data.tips, 5)

-- A zero bonus still uses the guarantee.
p = freshProfile()
paid = commit("z1", 6, 6, 0)
check("zero: paid", paid, 0)
check("zero: flag", p.data.tutorialBonusPaid, true)
check("zero: balance", p.data.tips, 6)

-- A later (non-tutorial) shift never touches the flag or pays a bonus.
p = freshProfile()
paid = commit("n1", 2, 2, nil)
check("later: paid", paid, 0)
check("later: flag", p.data.tutorialBonusPaid, false)
check("later: balance", p.data.tips, 2)

SaveService.profiles[fake] = nil
local report = string.format("tutorial bonus checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

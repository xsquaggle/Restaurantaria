-- Checks for shift save settlement: the next shift waits for the save, a failed save keeps
-- the shift's receipt for a retry, and no retry, lost reply or second session pays twice.
-- Run from the Studio command bar (or the Studio MCP in Edit mode) after a sync. Every save
-- goes to an in-memory FakeStore; the real DataStore is never read or written, and the test
-- refuses to run if the fake store is not in place.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local FakeStore = require(Server.FakeStore)
local SaveService = require(Server.SaveService)
local ShiftService = require(Server.ShiftService)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local KEY = "p_-4242"
local players = {} :: { any }
local store: any

-- A stand-in player on a fresh fake store (or the given one), loaded through SaveService.
local function newPlayer(onStore: any?, raw: any?): any
	if not onStore then
		store = FakeStore.new()
		store.data[KEY] = raw
	end
	SaveService.store = store
	assert(SaveService.store ~= SaveService.realStore, "fake store not in place")
	local player = { UserId = -4242, Name = "SettlementTest" }
	table.insert(players, player)
	SaveService.load(player :: any)
	return player
end

-- Ends the player's shift with the given coins and XP (the tutorial bonus as serve sets it).
local function finish(player: any, tips: number, xp: number): any
	local session = ShiftService.sessions[player] or ShiftService.start(player)
	local shift = session.shift
	shift.nextArrival = shift.customerCount + 1
	shift.tips, shift.xp = tips, xp
	if shift.tutorial then
		shift.tutorialBonus = ShiftService.tutorialBonusFor(tips)
	end
	ShiftService.finishIfDone(session)
	return session
end

local function settled(session: any): string?
	local t = os.clock()
	while session.shift.settlement == "pending" and os.clock() - t < 10 do
		task.wait(0.05)
	end
	return session.shift.settlement
end

local function act(session: any, action: string): (boolean, string?)
	return ShiftService.apply(session, action, {})
end

local function run()
	SaveService.simulateLoadFailure = false
	SaveService.retryWait = function() end

	-- 1. Delayed successful save: Next shift waits; the shift pays once; the next is not the tutorial.
	local p = newPlayer()
	store.delay = 0.3
	local s = finish(p, 1, 3)
	local firstId = s.shift.id
	check("delayed: tutorial shift", s.shift.tutorial, true)
	check("delayed: pending", s.shift.settlement, "pending")
	for i = 1, 3 do
		local ok, why = act(s, "newShift")
		check("delayed: next shift refused " .. i, ok, false)
		check("delayed: reason " .. i, why, "progress still saving")
	end
	check("delayed: retry refused while saving", (act(s, "retrySave")), false)
	check("delayed: same shift", s.shift.id, firstId)
	check("delayed: settles saved", settled(s), "saved")
	check("delayed: bonus shown", s.shift.tutorialBonus, 3)
	check("delayed: stored coins", store.data[KEY].tips, 4)
	check("delayed: stored shifts", store.data[KEY].shiftsCompleted, 1)
	check("delayed: one write", store.writes, 1)
	check("delayed: recorded", ShiftService.snapshot(p).recorded, true)
	check("delayed: next shift accepted", (act(s, "newShift")), true)
	check("delayed: next not tutorial", s.shift.tutorial, false)
	check("delayed: next full quota", s.shift.customerCount, Config.Shift.customerCount)

	-- 2. Three definite pre-write failures, then Retry: rewards and receipt survive, pay once.
	p = newPlayer()
	store.failNext = 3
	s = finish(p, 1, 3)
	local receipt = s.shift.receipt
	check("fail: retry needed", settled(s), "retry")
	check("fail: bonus kept", s.shift.tutorialBonus, 3)
	check("fail: receipt kept", s.shift.receipt, receipt)
	check("fail: receipt bonus", receipt.tutorialBonus, 3)
	check("fail: nothing stored", store.data[KEY], nil)
	check("fail: profile unchanged", SaveService.profiles[p].data.tips, 0)
	local snap = ShiftService.snapshot(p)
	check("fail: not recorded", snap.recorded, false)
	check("fail: HUD keeps 4", snap.profile.tips + snap.tips + snap.tutorialBonus, 4)
	local ok, why = act(s, "newShift")
	check("fail: next shift refused", ok, false)
	check("fail: reason", why, "progress not saved yet")
	check("fail: retry accepted", (act(s, "retrySave")), true)
	check("fail: retry saved", settled(s), "saved")
	check("fail: same shift id", s.shift.id, receipt.shiftId)
	check("fail: stored coins", store.data[KEY].tips, 4)
	check("fail: stored shifts", store.data[KEY].shiftsCompleted, 1)
	check("fail: bonus after retry", s.shift.tutorialBonus, 3)
	check("fail: one write", store.writes, 1)
	check("fail: second retry refused", (act(s, "retrySave")), false)
	check("fail: next shift accepted", (act(s, "newShift")), true)
	check("fail: next not tutorial", s.shift.tutorial, false)

	-- 3a. Write succeeded but its reply was lost: the next attempt finds the receipt.
	p = newPlayer()
	store.loseAckNext = 1
	s = finish(p, 1, 3)
	check("lost reply: saved", settled(s), "saved")
	check("lost reply: bonus reported", s.shift.tutorialBonus, 3)
	check("lost reply: stored coins", store.data[KEY].tips, 4)
	check("lost reply: stored shifts", store.data[KEY].shiftsCompleted, 1)
	check("lost reply: one write", store.writes, 1)
	check("lost reply: profile coins", SaveService.profiles[p].data.tips, 4)

	-- 3b. Every reply lost: retry needed, then Retry reconciles the same receipt.
	p = newPlayer()
	store.loseAckNext = 3
	s = finish(p, 1, 3)
	check("all lost: retry needed", settled(s), "retry")
	check("all lost: bonus kept", s.shift.tutorialBonus, 3)
	check("all lost: written once", store.writes, 1)
	act(s, "retrySave")
	check("all lost: retry saved", settled(s), "saved")
	check("all lost: bonus reported", s.shift.tutorialBonus, 3)
	check("all lost: stored coins", store.data[KEY].tips, 4)
	check("all lost: stored shifts", store.data[KEY].shiftsCompleted, 1)
	check("all lost: still one write", store.writes, 1)

	-- 4. Transform re-run after another server took the bonus: attribution follows the kept call.
	p = newPlayer()
	store.interleave = function(d: any)
		return { tips = 7, xp = 2, shiftsCompleted = 1, recentShiftIds = { "other" }, tutorialBonusPaid = true, tutorialBonusReceipt = { shiftId = "other", coins = 3 } }
	end
	s = finish(p, 1, 3)
	check("re-run: saved", settled(s), "saved")
	check("re-run: transform ran twice", store.transforms, 2)
	check("re-run: no second bonus", s.shift.tutorialBonus, 0)
	check("re-run: stored coins", store.data[KEY].tips, 8)
	check("re-run: stored shifts", store.data[KEY].shiftsCompleted, 2)

	-- 5. Duplicate shift id: in-session and against the store with a stale profile.
	p = newPlayer()
	local r = { shiftId = "dup", tips = 1, xp = 3, tutorialBonus = 3 }
	local o = SaveService.commitShift(p, r)
	check("dup: first saved", o.state, "saved")
	check("dup: first paid", o.bonusPaid, 3)
	o = SaveService.commitShift(p, r)
	check("dup: again saved", o.state, "saved")
	check("dup: again reports", o.bonusPaid, 3)
	check("dup: no new store call", store.calls, 1)
	SaveService.profiles[p].data = { tips = 0, xp = 0, shiftsCompleted = 0, recentShiftIds = {}, unlockedRecipes = {}, tutorialBonusPaid = false }
	o = SaveService.commitShift(p, r)
	check("dup stale: saved", o.state, "saved")
	check("dup stale: reports", o.bonusPaid, 3)
	check("dup stale: stored coins", store.data[KEY].tips, 4)
	check("dup stale: one write", store.writes, 1)
	check("dup stale: profile refreshed", SaveService.profiles[p].data.tips, 4)

	-- 6. Deliberate no-save session: continues in memory, never claims a durable save.
	store = FakeStore.new()
	SaveService.store = store
	SaveService.simulateLoadFailure = true
	p = { UserId = -4242, Name = "SettlementTest" }
	table.insert(players, p)
	SaveService.load(p)
	SaveService.simulateLoadFailure = false
	check("no-save: profile failed", SaveService.profiles[p].status, "failed")
	s = finish(p, 1, 3)
	check("no-save: session only", settled(s), "session")
	check("no-save: bonus", s.shift.tutorialBonus, 3)
	check("no-save: memory coins", SaveService.profiles[p].data.tips, 4)
	check("no-save: store untouched", store.calls, 0)
	o = SaveService.commitShift(p, s.shift.receipt)
	check("no-save: duplicate stays session", o.state, "session")
	check("no-save: duplicate reports", o.bonusPaid, 3)
	check("no-save: memory coins once", SaveService.profiles[p].data.tips, 4)
	check("no-save: next shift accepted", (act(s, "newShift")), true)
	check("no-save: next not tutorial", s.shift.tutorial, false)

	-- 7. Legacy saves without tutorialBonusPaid.
	p = newPlayer(nil, { tips = 10, xp = 5, shiftsCompleted = 2, recentShiftIds = { "a", "b" } })
	check("legacy played: flag counts as used", SaveService.profiles[p].data.tutorialBonusPaid, true)
	s = ShiftService.start(p)
	check("legacy played: not tutorial", s.shift.tutorial, false)
	s = finish(p, 2, 2)
	check("legacy played: saved", settled(s), "saved")
	check("legacy played: no bonus", s.shift.tutorialBonus, nil)
	check("legacy played: stored coins", store.data[KEY].tips, 12)
	p = newPlayer(nil, { tips = 0, xp = 0, shiftsCompleted = 0, recentShiftIds = {} })
	check("legacy fresh: eligible", SaveService.profiles[p].data.tutorialBonusPaid, false)
	s = finish(p, 1, 3)
	check("legacy fresh: tutorial", s.shift.tutorial, true)
	check("legacy fresh: saved", settled(s), "saved")
	check("legacy fresh: bonus", s.shift.tutorialBonus, 3)
	check("legacy fresh: stored coins", store.data[KEY].tips, 4)
	check("legacy fresh: flag stored", store.data[KEY].tutorialBonusPaid, true)
	-- A later poor order pays under 4 with no bonus.
	act(s, "newShift")
	s = finish(p, 1, 1)
	check("later poor: saved", settled(s), "saved")
	check("later poor: no bonus", s.shift.tutorialBonus, nil)
	check("later poor: stored coins", store.data[KEY].tips, 5)

	-- 8. Two sessions of one save (two servers), both loaded fresh: one bonus between them.
	local a = newPlayer()
	local b = newPlayer(store)
	local sa = finish(a, 1, 3)
	check("two sessions: A saved", settled(sa), "saved")
	local sb = finish(b, 1, 3)
	check("two sessions: B tutorial by its stale load", sb.shift.tutorial, true)
	check("two sessions: B saved", settled(sb), "saved")
	check("two sessions: A bonus", sa.shift.tutorialBonus, 3)
	check("two sessions: B no bonus", sb.shift.tutorialBonus, 0)
	check("two sessions: stored coins", store.data[KEY].tips, 5)
	check("two sessions: stored shifts", store.data[KEY].shiftsCompleted, 2)
	check("two sessions: receipt names A", store.data[KEY].tutorialBonusReceipt.shiftId, sa.shift.id)

	-- 9. Leaving with a failed save: one last attempt with the same receipt.
	p = newPlayer()
	store.failNext = 3
	s = finish(p, 1, 3)
	check("leave: retry needed", settled(s), "retry")
	ShiftService.stop(p)
	check("leave: stored on the way out", store.data[KEY] and store.data[KEY].tips, 4)
	check("leave: one write", store.writes, 1)
end

local ok, err = pcall(run)
-- Always put the real store back and drop the stand-in players.
SaveService.store = SaveService.realStore
SaveService.retryWait = task.wait
SaveService.simulateLoadFailure = false
for _, player in players do
	ShiftService.sessions[player] = nil
	SaveService.profiles[player] = nil
end
if not ok then
	error("save settlement checks stopped: " .. tostring(err))
end
local report = string.format("save settlement checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

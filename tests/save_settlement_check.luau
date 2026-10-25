-- Checks for shift save settlement: the next shift waits for the save, a failed save keeps
-- the shift's receipt for a retry, no retry, lost reply or second session pays twice, leaving
-- or a server shutdown settles the save before the profile goes, and nothing earned on a test
-- store reaches the real one.
-- Run from the Studio command bar (or the Studio MCP in Edit mode) after a sync, or offline
-- with tests/offline/run.py. Every save goes to an in-memory FakeStore. For the whole run
-- SaveService.productionStore is replaced by a FakeStore stand-in, so even a broken isolation rule
-- could only reach the stand-in: the real DataStore is never read or written. These are mock
-- results: they say nothing about the real DataStore, a real rejoin or overlapping servers.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local FakeStore = require(Server.FakeStore)
local SaveService = require(Server.SaveService)
local ShiftService = require(Server.ShiftService)
local TestStore = require(Server.TestStore)

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
local trueProductionStore = SaveService.productionStore
local realStandIn = FakeStore.new()

-- A stand-in player on a fresh fake store (or the given one), loaded through SaveService.
local function newPlayer(onStore: any?, raw: any?): any
	if not onStore then
		store = FakeStore.new()
		store.data[KEY] = raw
	end
	SaveService.store = store
	assert(SaveService.store ~= SaveService.productionStore, "fake store not in place")
	assert(SaveService.productionStore == realStandIn, "real store stand-in not in place")
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

-- A second stand-in player with its own key, on its own fresh fake store.
local function playerOn(onStore: any, userId: number): any
	SaveService.store = onStore
	local player = { UserId = userId, Name = "SettlementTest" .. -userId }
	table.insert(players, player)
	SaveService.load(player :: any)
	return player
end

local function waitFor(done: () -> boolean, seconds: number)
	local t = os.clock()
	while not done() and os.clock() - t < seconds do
		task.wait(0.05)
	end
end

local function run()
	SaveService.simulateLoadFailure = false
	SaveService.retryWait = function() end
	SaveService.productionStore = realStandIn

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
	local r = { shiftId = "dup", tips = 1, xp = 3, tutorialBonus = 3, store = store }
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
	check("leave: settles saved", ShiftService.leave(p), "saved")
	check("leave: stored on the way out", store.data[KEY] and store.data[KEY].tips, 4)
	check("leave: one write", store.writes, 1)
	check("leave: profile released", SaveService.profiles[p], nil)

	-- 10. Leaving while the save is still running and it succeeds: wait for it, no second attempt.
	p = newPlayer()
	store.delay = 0.3
	s = finish(p, 1, 3)
	check("pending leave: pending", s.shift.settlement, "pending")
	check("pending leave: saved", ShiftService.leave(p), "saved")
	check("pending leave: one call", store.calls, 1)
	check("pending leave: stored coins", store.data[KEY] and store.data[KEY].tips, 4)
	check("pending leave: session gone", ShiftService.sessions[p], nil)
	check("pending leave: profile released", SaveService.profiles[p], nil)

	-- 11. Leaving while the save is running and all its attempts fail: one more attempt
	-- after it, never alongside it.
	p = newPlayer()
	store.delay = 0.3
	store.failNext = 3
	s = finish(p, 1, 3)
	check("pending fail leave: pending", s.shift.settlement, "pending")
	check("pending fail leave: saved", ShiftService.leave(p), "saved")
	check("pending fail leave: calls", store.calls, 4)
	check("pending fail leave: never two at once", store.maxInFlight, 1)
	check("pending fail leave: one write", store.writes, 1)
	check("pending fail leave: stored coins", store.data[KEY] and store.data[KEY].tips, 4)
	check("pending fail leave: bonus once", s.shift.tutorialBonus, 3)

	-- 12. Leaving while every attempt fails: reported as not saved, nothing written.
	p = newPlayer()
	store.delay = 0.3
	store.failNext = 6
	s = finish(p, 1, 3)
	check("all fail leave: not saved", ShiftService.leave(p), "retry")
	check("all fail leave: calls", store.calls, 6)
	check("all fail leave: never two at once", store.maxInFlight, 1)
	check("all fail leave: nothing stored", store.data[KEY], nil)
	check("all fail leave: profile released", SaveService.profiles[p], nil)

	-- 13. Two leaves at once (PlayerRemoving and BindToClose) while every attempt fails: one
	-- settlement with one last attempt, no race, and no client intent accepted meanwhile.
	p = newPlayer()
	store.delay = 0.3
	store.failNext = 6
	s = finish(p, 1, 3)
	local results = {}
	task.spawn(function()
		results[1] = ShiftService.leave(p)
	end)
	task.spawn(function()
		results[2] = ShiftService.leave(p)
	end)
	local ok, why = ShiftService.handle(p, s.lastSeq + 1, "retrySave", {})
	check("double leave: intents refused", ok, false)
	check("double leave: reason", why, "leaving")
	waitFor(function()
		return results[1] ~= nil and results[2] ~= nil
	end, 15)
	check("double leave: first not saved", results[1], "retry")
	check("double leave: second not saved", results[2], "retry")
	check("double leave: one last attempt only", store.calls, 6)
	check("double leave: never two at once", store.maxInFlight, 1)
	check("double leave: nothing stored", store.data[KEY], nil)
	check("double leave: profile released", SaveService.profiles[p], nil)

	-- 14. A leave past its deadline returns without waiting longer; the attempt in flight still
	-- finishes on its own store (persistence is not guaranteed past the deadline).
	p = newPlayer()
	store.delay = 2
	s = finish(p, 1, 3)
	local t0 = os.clock()
	check("deadline: still pending", ShiftService.leave(p, os.clock() + 0.5), "pending")
	check("deadline: returned in time", os.clock() - t0 < 1.5, true)
	check("deadline: session gone", ShiftService.sessions[p], nil)
	waitFor(function()
		return store.writes > 0
	end, 10)
	check("deadline: late attempt stored", store.data[KEY] and store.data[KEY] and store.data[KEY].tips, 4)

	-- 15. Server shutdown (BindToClose): every player settles together, then is released.
	for _, player in players do
		ShiftService.sessions[player] = nil
	end
	local storeA, storeB, storeC = FakeStore.new(), FakeStore.new(), FakeStore.new()
	local a = playerOn(storeA, -4301)
	local b = playerOn(storeB, -4302)
	local c = playerOn(storeC, -4303)
	storeA.delay = 0.3
	storeB.delay = 0.3
	storeB.failNext = 3
	finish(a, 1, 3)
	finish(b, 2, 3)
	ShiftService.start(c) -- mid-shift when the server closes
	ShiftService.closeAll(25)
	check("shutdown: A stored", storeA.data["p_-4301"] and storeA.data["p_-4301"].tips, 4)
	check("shutdown: B stored", storeB.data["p_-4302"] and storeB.data["p_-4302"].tips, 4)
	check("shutdown: B never two at once", storeB.maxInFlight, 1)
	check("shutdown: B calls", storeB.calls, 4)
	check("shutdown: C abandoned, nothing written", storeC.calls, 0)
	check("shutdown: no sessions left", next(ShiftService.sessions), nil)
	check("shutdown: profiles released", SaveService.profiles[a] == nil and SaveService.profiles[b] == nil and SaveService.profiles[c] == nil, true)

	-- 16. Fake-to-real isolation. 16a: a shift on a fake store, then the global store pointed
	-- back at the real one (what the old fakeStore(false) did): Retry and leaving still write
	-- only to the fake.
	p = newPlayer()
	local fake = store
	fake.failNext = 3
	s = finish(p, 1, 3)
	check("isolation: retry needed", settled(s), "retry")
	SaveService.store = SaveService.productionStore
	act(s, "retrySave")
	check("isolation: saved to its own store", settled(s), "saved")
	check("isolation: fake stored", fake.data[KEY] and fake.data[KEY].tips, 4)
	ShiftService.leave(p)
	check("isolation: real untouched", realStandIn.calls, 0)

	-- 16b: the profile reloaded from the real store while a fake receipt waits: the receipt is
	-- refused, never written, and leaving does not write it either.
	p = newPlayer()
	fake = store
	fake.failNext = 3
	s = finish(p, 1, 3)
	check("reload: retry needed", settled(s), "retry")
	SaveService.store = SaveService.productionStore
	SaveService.load(p)
	check("reload: profile on real", SaveService.profiles[p].store, realStandIn)
	act(s, "retrySave")
	check("reload: refused", settled(s), "retry")
	check("reload: next shift still refused", (act(s, "newShift")), false)
	check("reload: leaving refused too", ShiftService.leave(p), "retry")
	check("reload: real never written", realStandIn.calls, 0)
	check("reload: fake not written", fake.writes, 0)

	-- 16c: the Studio fakeStore command (TestStore). No way back to the real store; no switch
	-- while a real receipt is unsettled; after a switch everything is bound to the fake.
	realStandIn.data[KEY] = nil
	SaveService.store = SaveService.productionStore
	p = { UserId = -4242, Name = "SettlementTest" }
	table.insert(players, p)
	SaveService.load(p)
	s = ShiftService.start(p)
	check("command: shift on real", s.shift.store, realStandIn)
	realStandIn.failNext = 3
	s = finish(p, 1, 3)
	check("command: real retry", settled(s), "retry")
	local realCalls = realStandIn.calls
	check("command: false refused", string.sub(TestStore.command(p, false), 1, 7), "refused")
	check("command: switch refused while real unsettled", string.sub(TestStore.command(p, { failNext = 3 }), 1, 7), "refused")
	check("command: still real", SaveService.store, realStandIn)
	act(s, "retrySave")
	check("command: real retry saved", settled(s), "saved")
	realCalls = realStandIn.calls
	check("command: switch", string.sub(TestStore.command(p, { failNext = 3 }), 1, 10), "fake store")
	local fakeNow = SaveService.store
	check("command: fake in place", fakeNow ~= realStandIn, true)
	check("command: profile on fake", SaveService.profiles[p].store, fakeNow)
	check("command: new shift on fake", s.shift.store, fakeNow)
	s = finish(p, 2, 2)
	check("command: fake retry", settled(s), "retry")
	check("command: false still refused", string.sub(TestStore.command(p, false), 1, 7), "refused")
	check("command: store still fake", SaveService.store, fakeNow)
	act(s, "retrySave")
	check("command: fake saved", settled(s), "saved")
	check("command: fake stored (2 coins + 2 tutorial bonus)", fakeNow.data[KEY] and fakeNow.data[KEY].tips, 4)
	act(s, "newShift")
	fakeNow.failNext = 3
	s = finish(p, 3, 3)
	check("command: fake retry again", settled(s), "retry")
	check("command: fresh allowed over a fake receipt", string.sub(TestStore.command(p, { fresh = true }), 1, 10), "fake store")
	check("command: fresh store", SaveService.store ~= fakeNow and SaveService.store ~= realStandIn, true)
	ShiftService.leave(p)
	check("command: real never written after the switch", realStandIn.calls, realCalls)

	-- 16d: two players (Astra's 2026-10-24 review). A and B both load real profiles; A switches
	-- to a fake store and leaves; B, still on the real store, must get no fake faults, no test
	-- mutation and no forced coins, and its own fakeStore call must switch it (not "faults set").
	-- A player who joins after a switch loads from the fake store.
	realStandIn.data["p_-5001"] = nil
	realStandIn.data["p_-5002"] = nil
	realStandIn.failNext, realStandIn.loseAckNext, realStandIn.delay = 0, 0, 0
	local realBefore = realStandIn.writes
	local a = playerOn(realStandIn, -5001)
	local sa = ShiftService.start(a)
	local b = playerOn(realStandIn, -5002)
	local sb = ShiftService.start(b)
	check("two: A on real", TestStore.productionBound(a), true)
	check("two: B on real", TestStore.productionBound(b), true)
	check("two: mutator refused on real A", TestStore.guard(a) ~= nil, true)
	check("two: forced coins refused on real A", string.sub(TestStore.forceTip(a, 9), 1, 7), "refused")
	check("two: A switches", string.sub(TestStore.command(a, { failNext = 3, delay = 0.2 }), 1, 10), "fake store")
	local fakeA = SaveService.profiles[a].store
	check("two: A on its fake", fakeA ~= realStandIn and sa.shift.store == fakeA, true)
	check("two: A mutators allowed", TestStore.guard(a), nil)
	check("two: forced coins on fake A", TestStore.forceTip(a, 77), "ok")
	check("two: B still on real", SaveService.profiles[b].store, realStandIn)
	check("two: B shift still on real", sb.shift.store, realStandIn)
	check("two: real store got no faults", realStandIn.failNext + realStandIn.loseAckNext + realStandIn.delay, 0)
	check("two: B mutator refused", TestStore.guard(b) ~= nil, true)
	check("two: B forced coins refused", string.sub(TestStore.forceTip(b, 9), 1, 7), "refused")
	check("two: B has no forced coins", sb.devForcedTip, nil)
	check("two: no server-wide forced coins", (ShiftService :: any).devForcedTip, nil)
	-- A served order on B's real shift scores normally even while A forces 77 coins.
	sb.shift.customers = { { id = 901, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = workspace:GetServerTimeNow() } }
	sb.shift.pizzas = { [902] = { id = 902, ticketId = 901, stage = "cutting", toppings = {}, cuts = {}, bakeSeconds = Config.Oven.targets.regular } }
	sb.shift.nextArrival = sb.shift.customerCount + 2
	check("two: B serve", (ShiftService.apply(sb, "serve", { pizzaId = 902 })), true)
	check("two: B coins not forced", sb.shift.customers[1].result.tip ~= 77, true)
	sa.shift.customers = { { id = 903, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = workspace:GetServerTimeNow() } }
	sa.shift.pizzas = { [904] = { id = 904, ticketId = 903, stage = "cutting", toppings = {}, cuts = {}, bakeSeconds = Config.Oven.targets.regular } }
	sa.shift.nextArrival = sa.shift.customerCount + 2
	check("two: A serve", (ShiftService.apply(sa, "serve", { pizzaId = 904 })), true)
	check("two: A coins forced", sa.shift.customers[1].result.tip, 77)
	check("two: A fake save fails as set", settled(sa), "retry")
	ShiftService.leave(a)
	check("two: A gone", ShiftService.sessions[a] == nil and SaveService.profiles[a] == nil, true)
	-- B finished its real shift: it saves to the real store, B's own coins only.
	check("two: B saved to real", settled(sb), "saved")
	check("two: real got B's write", realStandIn.writes, realBefore + 1)
	check("two: B real coins", realStandIn.data["p_-5002"].tips, sb.shift.tips + (sb.shift.tutorialBonus or 0))
	check("two: fake A never reached real", realStandIn.data["p_-5001"], nil)
	-- B's real receipt unsettled: B's switch is refused and the receipt kept.
	act(sb, "newShift")
	realStandIn.failNext = 3
	local tipsBefore = realStandIn.data["p_-5002"].tips
	sb.shift.customers = { { id = 905, status = "ordered", order = { recipe = "cheese", bake = "regular", slices = 8 }, arrivedAt = workspace:GetServerTimeNow() } }
	sb.shift.pizzas = { [906] = { id = 906, ticketId = 905, stage = "cutting", toppings = {}, cuts = {}, bakeSeconds = Config.Oven.targets.regular } }
	sb.shift.nextArrival = sb.shift.customerCount + 2
	ShiftService.apply(sb, "serve", { pizzaId = 906 })
	check("two: B real retry", settled(sb), "retry")
	local receiptB = sb.shift.receipt
	check("two: B switch refused while real unsettled", string.sub(TestStore.command(b, {}), 1, 7), "refused")
	check("two: B receipt kept", sb.shift.receipt, receiptB)
	check("two: B still real after refusal", SaveService.profiles[b].store, realStandIn)
	act(sb, "retrySave")
	check("two: B retry saved to real", settled(sb), "saved")
	check("two: B real coins once", realStandIn.data["p_-5002"].tips, tipsBefore + receiptB.tips)
	-- Settled: B's own call switches B (a new fake, never A's faults or "faults set").
	local line = TestStore.command(b, {})
	check("two: B switches, not faults set", string.sub(line, 1, 10), "fake store")
	local fakeB = SaveService.profiles[b].store
	check("two: B on its own fake", fakeB ~= realStandIn and fakeB ~= fakeA and sb.shift.store == fakeB, true)
	check("two: B fake clean", fakeB.failNext + fakeB.delay, 0)
	-- A later join loads from the selected test store, not the real one.
	local c = { UserId = -5003, Name = "SettlementTest5003" }
	table.insert(players, c)
	SaveService.load(c :: any)
	check("two: later join on test store", SaveService.profiles[c].store ~= realStandIn, true)
	check("two: later join not production-bound", TestStore.productionBound(c :: any), false)
	-- reloadProfile-style reload keeps each player on its own store.
	SaveService.load(b, SaveService.profiles[b].store)
	check("two: reload keeps B on its fake", SaveService.profiles[b].store, fakeB)
	ShiftService.leave(b)
	SaveService.release(c :: any)
	check("two: real writes are B's two only", realStandIn.writes, realBefore + 2)

	-- 17. Retry through the live client path (handle: sequence and rate checks). A rate-limited
	-- Retry leaves the receipt waiting; it is not lost.
	p = newPlayer()
	store.failNext = 3
	s = finish(p, 1, 3)
	check("live: retry needed", settled(s), "retry")
	local receiptBefore = s.shift.receipt
	local seq = s.lastSeq
	local function send(action: string): (boolean, string?)
		seq += 1
		return ShiftService.handle(p, seq, action, {})
	end
	ok, why = send("newShift")
	check("live: next refused", why, "progress not saved yet")
	local limited = 0
	for _ = 1, Config.Net.maxActionsPerSecond + 2 do
		local _, reason = send("newShift")
		if reason == "too many requests" then
			limited += 1
		end
	end
	check("live: burst rate-limited", limited > 0, true)
	ok, why = send("retrySave")
	check("live: limited retry refused", why, "too many requests")
	check("live: still retry", s.shift.settlement, "retry")
	check("live: same receipt", s.shift.receipt, receiptBefore)
	store.delay = 0.3
	task.wait(1.1)
	ok, why = send("retrySave")
	check("live: retry accepted", ok, true)
	check("live: pending", s.shift.settlement, "pending")
	ok, why = ShiftService.handle(p, seq, "retrySave", {})
	check("live: replay refused", why, "replayed request")
	ok, why = ShiftService.handle(p, "x", "retrySave", {})
	check("live: bad sequence refused", why, "bad sequence")
	check("live: saved", settled(s), "saved")
	check("live: one write", store.writes, 1)
	check("live: stored coins", store.data[KEY] and store.data[KEY].tips, 4)
	ok, why = send("retrySave")
	check("live: nothing to retry", why, "nothing to retry")
	ok, why = send("placeTopping")
	check("live: shift over", why, "shift is over")
	check("live: rejections counted", s.rejected > 0, true)
	ok = send("newShift")
	check("live: next shift accepted", ok, true)
	check("live: next not tutorial", s.shift.tutorial, false)

	-- The only writes the stand-in ever saw are 16c's and 16d's own real-store receipts.
	check("real store stand-in: three writes, their own", realStandIn.writes, 3)
end

local ok, err = pcall(run)
-- Always put the real store back and drop the stand-in players.
SaveService.productionStore = trueProductionStore
SaveService.store = trueProductionStore
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

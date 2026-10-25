-- Checks for save backend isolation: which DataStore each backend opens (never production in a
-- test or memory runtime), the test-only fault adapter, store kinds, the guards on server-wide
-- test settings, and same-account overlap (two sessions on one key: every receipt paid once, a
-- delayed old session never overwrites newer progress).
-- Run offline with tests/offline/run.py, or in Studio Edit after a sync. Every store here is a
-- FakeStore or the adapter over one; the real DataStore is never read or written. Mock results:
-- the Studio persistence run (tests/studio/persistence_check.luau) is the real-store evidence.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local FakeStore = require(Server.FakeStore)
local SaveBackend = require(Server.SaveBackend)
local SaveService = require(Server.SaveService)
local ShiftService = require(Server.ShiftService)
local TestDataStore = require(Server.TestDataStore)
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

local players = {} :: { any }
local trueProductionStore = SaveService.productionStore
local trueStore = SaveService.store
local productionStandIn = FakeStore.new()

local function load(userId: number, onStore: any): any
	local player = { UserId = userId, Name = "BackendTest" .. -userId }
	table.insert(players, player)
	SaveService.load(player :: any, onStore)
	return player
end

local function receipt(id: string, tips: number, xp: number, onStore: any, bonus: number?): any
	return table.freeze({ shiftId = id, tips = tips, xp = xp, tutorialBonus = bonus, store = onStore })
end

local function run()
	SaveService.retryWait = function() end
	SaveService.simulateLoadFailure = false
	SaveService.productionStore = productionStandIn

	-- 1. Backend choice. `open` records every DataStore name asked for.
	local opened = {}
	local function choose(studio: boolean, backend: any, testName: any): any
		table.clear(opened)
		return SaveBackend.choose({
			studio = studio,
			backend = backend,
			testName = testName,
			open = function(name: string): any
				table.insert(opened, name)
				return FakeStore.new()
			end,
		})
	end
	local prod = SaveBackend.PRODUCTION_NAME
	local sel = choose(true, nil, nil)
	check("default: production", sel.kind, "production")
	check("default: opens production once", table.concat(opened, ","), prod)
	sel = choose(false, "test", "Restaurantaria_TEST_x")
	check("live server ignores selector", sel.kind, "production")
	check("live server opens production", table.concat(opened, ","), prod)
	sel = choose(true, "test", prod)
	check("test with production name: kind", sel.kind, "test")
	check("test with production name: no store", sel.store, nil)
	check("test with production name: nothing opened", #opened, 0)
	check("test with production name: refused", sel.error ~= nil and string.find(sel.error, "refused", 1, true) ~= nil, true)
	sel = choose(true, "test", "Restaurantaria_Progress_v1_test")
	check("test without prefix: nothing opened", #opened, 0)
	check("test without prefix: no store", sel.store, nil)
	sel = choose(true, "test", nil)
	check("test without name: nothing opened", #opened, 0)
	check("test without name: no store", sel.store, nil)
	sel = choose(true, "prod", nil)
	check("unknown backend: nothing opened", #opened, 0)
	check("unknown backend: no store", sel.store, nil)
	sel = choose(true, "memory", nil)
	check("memory: nothing opened", #opened, 0)
	check("memory: kind", SaveService.kindOf(sel.store), "memory")
	sel = choose(true, "test", "Restaurantaria_TEST_run1")
	check("test: opens only the test name", table.concat(opened, ","), "Restaurantaria_TEST_run1")
	check("test: adapter kind", SaveService.kindOf(sel.store), "test")
	check("test: adapter name", sel.store.name, "Restaurantaria_TEST_run1")

	-- 2. Store kinds.
	check("kind: production", SaveService.kindOf(productionStandIn), "production")
	check("kind: none", SaveService.kindOf(nil), "none")
	check("kind: unknown fails closed", SaveService.kindOf({}), "production")

	-- 3. A test-DataStore profile through the adapter: faults stay in the adapter.
	local inner = FakeStore.new()
	local adapter = TestDataStore.wrap(inner, "Restaurantaria_TEST_mock")
	local a = load(-501, adapter)
	check("test profile ok", SaveService.profiles[a].status, "ok")
	adapter.failNext = 3
	local out = SaveService.commitShift(a, receipt("r-fail", 5, 10, adapter))
	check("failNext: retry", out.state, "retry")
	check("failNext: nothing written", inner.data["p_-501"], nil)
	check("failNext: inner fields untouched", inner.failNext, 0)
	out = SaveService.commitShift(a, receipt("r-fail", 5, 10, adapter))
	check("failNext retry: saved", out.state, "saved")
	check("failNext retry: tips once", inner.data["p_-501"].tips, 5)
	adapter.loseAckNext = 1
	out = SaveService.commitShift(a, receipt("r-lost", 7, 10, adapter))
	-- The first attempt wrote and lost its reply; the second sees the receipt and cancels.
	check("loseAck: saved within the retries", out.state, "saved")
	check("loseAck: inner fields untouched", inner.loseAckNext, 0)
	check("loseAck: paid once", inner.data["p_-501"].tips, 12)
	check("loseAck: two shifts", inner.data["p_-501"].shiftsCompleted, 2)

	-- 4. Guards. A production-bound player blocks server-wide settings; mixed orders and the
	-- load-failure hook never reach a production profile.
	SaveService.store = productionStandIn
	local p = load(-502, productionStandIn)
	ShiftService.start(p :: any)
	check("production player bound", TestStore.productionBound(p :: any), true)
	check("server settings refused", TestStore.guardServer() ~= nil, true)
	Config.Dev.mixedOrders = true
	check("mixed orders ignored on production", table.concat(ShiftService.newShift(p :: any).menu, ","), "cheese")
	SaveService.simulateLoadFailure = true
	check("load failure ignored on production", SaveService.load(p :: any, productionStandIn).status, "ok")
	ShiftService.sessions[p] = nil
	SaveService.profiles[p] = nil
	check("nobody on production: allowed", TestStore.guardServer(), nil)
	check("load failure applies on test", SaveService.load(a :: any, adapter).status, "failed")
	SaveService.simulateLoadFailure = false
	SaveService.load(a :: any, adapter)
	local session = ShiftService.start(a :: any)
	check("mixed orders apply on test", #session.shift.menu > 1, true)
	Config.Dev.mixedOrders = false
	check("test player not production-bound", TestStore.productionBound(a :: any), false)
	check("fakeStore on test sets adapter faults", TestStore.command(a :: any, { failNext = 2 }), "test store faults set")
	check("adapter failNext set", adapter.failNext, 2)
	check("inner untouched by fakeStore", inner.failNext, 0)
	adapter.failNext = 0
	-- An unsettled test-DataStore receipt is never dropped by a switch to memory.
	session.shift.finished = true
	session.shift.receipt = receipt(session.shift.id, 1, 1, adapter)
	session.shift.settlement = "retry"
	check("switch refused while test save unsettled", TestStore.command(a :: any, { fresh = true }), "refused: this shift's save is not settled yet")
	session.shift.settlement = "saved"
	check("switch to memory once settled", TestStore.command(a :: any, { fresh = true }), "fake store, profile ok, new shift")
	check("now on memory", SaveService.kindOf(SaveService.profiles[a].store), "memory")
	ShiftService.sessions[a] = nil

	-- 5. Same-account overlap: an old session (slow server) and a new one on one key.
	local shared = FakeStore.new()
	local slow = TestDataStore.wrap(shared, "Restaurantaria_TEST_mock")
	local fast = TestDataStore.wrap(shared, "Restaurantaria_TEST_mock")
	shared.data["p_-503"] = { tips = 100, xp = 50, shiftsCompleted = 3, recentShiftIds = { "s1", "s2", "s3" }, unlockedRecipes = { "cheese" }, tutorialBonusPaid = true }
	local old = load(-503, slow)
	slow.delay = 2
	local oldOut
	task.spawn(function()
		oldOut = SaveService.commitShift(old, receipt("r-old", 9, 20, slow))
	end)
	local new = load(-503, fast)
	check("overlap: new session sees old data", SaveService.profiles[new].data.tips, 100)
	out = SaveService.commitShift(new, receipt("r-new", 11, 30, fast))
	check("overlap: new saved first", out.state, "saved")
	check("overlap: old still in flight", oldOut, nil)
	task.wait(3)
	check("overlap: old saved late", oldOut and oldOut.state, "saved")
	local d = shared.data["p_-503"]
	check("overlap: both paid", d.tips, 120)
	check("overlap: xp both", d.xp, 100)
	check("overlap: shifts", d.shiftsCompleted, 5)
	check("overlap: old profile now holds the newer write", SaveService.profiles[old].data.tips, 120)
	slow.delay = 0
	out = SaveService.commitShift(old, receipt("r-old", 9, 20, slow))
	check("overlap: old retry saved", out.state, "saved")
	out = SaveService.commitShift(new, receipt("r-new", 11, 30, fast))
	check("overlap: new retry saved", out.state, "saved")
	fast.loseAckNext = 1
	out = SaveService.commitShift(new, receipt("r-new2", 4, 5, fast))
	check("overlap: lost reply saved", out.state, "saved")
	d = shared.data["p_-503"]
	check("overlap: retries paid nothing more", d.tips, 124)
	check("overlap: shifts after retries", d.shiftsCompleted, 6)

	-- Two tutorial sessions on one fresh key: the one-time bonus is paid once.
	local t1 = load(-504, slow)
	local t2 = load(-504, fast)
	local b1 = SaveService.commitShift(t1, receipt("t-1", 2, 5, slow, 48))
	local b2 = SaveService.commitShift(t2, receipt("t-2", 3, 5, fast, 47))
	check("tutorial overlap: first pays bonus", b1.bonusPaid, 48)
	check("tutorial overlap: second pays none", b2.bonusPaid, 0)
	check("tutorial overlap: total", shared.data["p_-504"].tips, 53)

	check("production stand-in never written", productionStandIn.writes, 0)
end

local ok, err = pcall(run)
SaveService.productionStore = trueProductionStore
SaveService.store = trueStore
SaveService.retryWait = task.wait
SaveService.simulateLoadFailure = false
Config.Dev.mixedOrders = false
for _, player in players do
	ShiftService.sessions[player] = nil
	SaveService.profiles[player] = nil
end
if not ok then
	error("save backend checks stopped: " .. tostring(err))
end
local report = string.format("save backend checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

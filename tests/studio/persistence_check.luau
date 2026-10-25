-- Real-persistence check against the isolated test DataStore, at the SaveService level. Run it
-- in Studio during Play (Server datamodel) with the test backend selected before Play (see
-- SaveBackend): it refuses to run on any other backend, so it can only write to the test
-- DataStore. Players are stand-ins with negative user ids (keys p_-9100xx), one key per
-- scenario. Each scenario records its starting data, stable receipt ids, the expected totals,
-- each commit's outcome and an uncached readback (UseCache = false).
-- Scenarios: durable save and readback, reload as a rejoin, failed write then retry, lost
-- reply then retry (paid once), same-account overlap (a delayed old session lands after a
-- newer one: both paid once, nothing overwritten), and the tutorial bonus across two sessions.
-- Not covered here: two live servers (a Studio selector cannot isolate them) and the real
-- player lifecycle (rejoin, leave and shutdown are run through the game itself).
-- Returns a log; any failed expectation is marked FAIL.

local Server = game:GetService("ServerScriptService").Server
local SaveService = require(Server.SaveService)
local TestDataStore = require(Server.TestDataStore)

return function(): string
	local log = {}
	local failed = 0
	local function line(text: string)
		table.insert(log, text)
	end
	local function expect(name: string, got: any, want: any)
		local ok = got == want
		if not ok then
			failed += 1
		end
		line(string.format("  %s %s: %s%s", if ok then "ok  " else "FAIL", name, tostring(got), if ok then "" else " (want " .. tostring(want) .. ")"))
	end

	if SaveService.backend.kind ~= "test" or SaveService.productionStore ~= nil or SaveService.kindOf(SaveService.store) ~= "test" then
		return "refused: the test backend is not selected (backend=" .. SaveService.backend.kind .. ")"
	end
	local adapter = SaveService.store
	local inner = adapter.inner
	line("backend=test store=" .. tostring(SaveService.backend.name) .. " productionOpen=false")

	local function read(key: string): any
		local options = Instance.new("DataStoreGetOptions")
		options.UseCache = false
		return (inner:GetAsync(key, options))
	end
	local function summary(d: any): string
		if d == nil then
			return "empty"
		end
		return string.format("tips=%d xp=%d shifts=%d ids=%s bonusPaid=%s", d.tips, d.xp, d.shiftsCompleted, table.concat(d.recentShiftIds, "|"), tostring(d.tutorialBonusPaid))
	end
	local function stub(userId: number): any
		return { UserId = userId, Name = "PersistTest" .. -userId }
	end
	local function receipt(id: string, tips: number, xp: number, onStore: any, bonus: number?): any
		return table.freeze({ shiftId = id, tips = tips, xp = xp, tutorialBonus = bonus, store = onStore })
	end
	local function commit(player: any, r: any): any
		local t = os.clock()
		local out = SaveService.commitShift(player, r)
		line(string.format("  commit %s -> %s bonusPaid=%s (%.1f s)%s", r.shiftId, out.state, tostring(out.bonusPaid), os.clock() - t, if out.message then " " .. out.message else ""))
		return out
	end
	local stubs = {}
	local function load(userId: number, onStore: any): any
		local player = stub(userId)
		table.insert(stubs, player)
		local profile = SaveService.load(player, onStore)
		line(string.format("  load p_%d -> %s %s", userId, profile.status, summary(profile.data)))
		return player
	end

	local ok, err = pcall(function()
		-- S1: durable save and readback, then a reload (rejoin) from the store.
		line("S1 durable save + reload")
		local k1 = "p_-910001"
		line("  start " .. summary(read(k1)))
		local a = load(-910001, adapter)
		local out = commit(a, receipt("persist-S1-a", 12, 30, adapter, 38))
		expect("outcome", out.state, "saved")
		expect("bonus paid", out.bonusPaid, 38)
		local d = read(k1)
		line("  readback " .. summary(d))
		expect("tips 12+38", d and d.tips, 50)
		expect("shifts", d and d.shiftsCompleted, 1)
		SaveService.release(a)
		local again = load(-910001, adapter)
		expect("reload tips", SaveService.profiles[again].data.tips, 50)
		expect("reload not tutorial", SaveService.profiles[again].data.shiftsCompleted, 1)

		-- S2: a failed write (all three attempts) reports retry and writes nothing; the retry
		-- pays once.
		line("S2 failed write, then retry")
		local k2 = "p_-910002"
		local b = load(-910002, adapter)
		adapter.failNext = 3
		out = commit(b, receipt("persist-S2-b", 9, 20, adapter))
		expect("outcome", out.state, "retry")
		line("  readback " .. summary(read(k2)))
		expect("nothing written", read(k2), nil)
		out = commit(b, receipt("persist-S2-b", 9, 20, adapter))
		expect("retry outcome", out.state, "saved")
		d = read(k2)
		line("  readback " .. summary(d))
		expect("tips once", d and d.tips, 9)

		-- S3: lost replies. Every attempt's reply is lost (the first one wrote), so the caller
		-- sees retry; the later retry finds the receipt and pays nothing more.
		line("S3 lost reply, then retry")
		local k3 = "p_-910003"
		local c = load(-910003, adapter)
		adapter.loseAckNext = 3
		out = commit(c, receipt("persist-S3-c", 15, 40, adapter, 33))
		expect("outcome", out.state, "retry")
		d = read(k3)
		line("  readback " .. summary(d))
		expect("written once despite lost reply", d and d.tips, 48)
		out = commit(c, receipt("persist-S3-c", 15, 40, adapter, 33))
		expect("retry outcome", out.state, "saved")
		expect("retry reports the recorded bonus", out.bonusPaid, 33)
		d = read(k3)
		line("  readback " .. summary(d))
		expect("paid once", d and d.tips, 48)
		expect("one shift", d and d.shiftsCompleted, 1)

		-- S4: same-account overlap. The old session's save is slow (5 s, as a server that is
		-- still closing); the new session loads, saves its own shift first, then the old one
		-- lands. Both are paid once and the old one adds to the newer data.
		line("S4 same-account overlap")
		local k4 = "p_-910004"
		local seed = load(-910004, adapter)
		out = commit(seed, receipt("persist-S4-seed", 100, 50, adapter, 0))
		expect("seed saved", out.state, "saved")
		SaveService.release(seed)
		line("  start " .. summary(read(k4)))
		local slow = TestDataStore.wrap(inner, adapter.name)
		local old = load(-910004, slow)
		slow.delay = 5
		local oldOut = nil
		task.spawn(function()
			oldOut = SaveService.commitShift(old, receipt("persist-S4-old", 9, 20, slow))
		end)
		local new = load(-910004, adapter)
		out = commit(new, receipt("persist-S4-new", 11, 30, adapter))
		expect("new saved", out.state, "saved")
		expect("old still in flight", oldOut, nil)
		local t = os.clock()
		while oldOut == nil and os.clock() - t < 40 do
			task.wait(0.2)
		end
		line(string.format("  commit persist-S4-old (late) -> %s", tostring(oldOut and oldOut.state)))
		expect("old saved late", oldOut and oldOut.state, "saved")
		d = read(k4)
		line("  readback " .. summary(d))
		expect("both paid: 100+11+9", d and d.tips, 120)
		expect("xp 50+30+20", d and d.xp, 100)
		expect("shifts 1+2", d and d.shiftsCompleted, 3)
		slow.delay = 0
		out = commit(old, receipt("persist-S4-old", 9, 20, slow))
		expect("old retry", out.state, "saved")
		out = commit(new, receipt("persist-S4-new", 11, 30, adapter))
		expect("new retry", out.state, "saved")
		d = read(k4)
		line("  readback " .. summary(d))
		expect("retries paid nothing more", d and d.tips, 120)
		expect("shifts still 3", d and d.shiftsCompleted, 3)

		-- S5: two sessions on a fresh key both finish a tutorial shift: the bonus is paid once.
		line("S5 tutorial bonus across two sessions")
		local k5 = "p_-910005"
		local t1 = load(-910005, adapter)
		local t2 = load(-910005, slow)
		local o1 = commit(t1, receipt("persist-S5-1", 2, 5, adapter, 48))
		local o2 = commit(t2, receipt("persist-S5-2", 3, 5, slow, 47))
		expect("first pays bonus", o1.bonusPaid, 48)
		expect("second pays none", o2.bonusPaid, 0)
		d = read(k5)
		line("  readback " .. summary(d))
		expect("total 2+48+3", d and d.tips, 53)
	end)
	for _, player in stubs do
		SaveService.release(player)
	end
	if not ok then
		failed += 1
		line("STOPPED: " .. tostring(err))
	end
	line(string.format("adapter calls=%d writes=%d gets=%d", adapter.calls, adapter.writes, adapter.gets))
	line(if failed == 0 then "persistence check: ALL PASSED (test DataStore " .. tostring(SaveService.backend.name) .. ")" else string.format("persistence check: %d FAILED", failed))
	return table.concat(log, "\n")
end

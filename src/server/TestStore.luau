--!strict
-- Studio test hook behind Main's fakeStore command and its test mutators. Store kinds come
-- from SaveService.kindOf: production (the real save), test (an isolated test DataStore
-- behind the TestDataStore adapter) and memory (a FakeStore). Everything is decided by the
-- selected player's own loaded store, never by the server-wide one. A player still bound to
-- the production store gets no test faults and no test mutations (forced coins, scripted
-- play, clock edits, mixed orders, load failures). fakeStore moves a player off production
-- onto a new FakeStore, one way only: production comes back only with a new play session.
-- On a test or memory store it sets that store's faults; on the test DataStore the faults
-- live in the adapter, never on the DataStore object itself. Every profile, shift and
-- receipt keeps the store it began on (SaveService, ShiftService), so nothing made on a test
-- or memory store can reach production.

local FakeStore = require(script.Parent.FakeStore)
local SaveService = require(script.Parent.SaveService)
local ShiftService = require(script.Parent.ShiftService)

local TestStore = {}

local function unsettled(settlement: string?): boolean
	return settlement == "pending" or settlement == "retry"
end

-- A store test faults may be set on: the isolated test DataStore's adapter or a FakeStore.
local function isTestKind(store: any): boolean
	local kind = SaveService.kindOf(store)
	return kind == "test" or kind == "memory"
end

-- True while the player's loaded profile or current shift is bound to the production store (a
-- shift begun there can still commit there after a reload).
function TestStore.productionBound(player: Player): boolean
	local profile = SaveService.profiles[player]
	local session = ShiftService.sessions[player]
	return (profile ~= nil and SaveService.kindOf(profile.store) == "production")
		or (session ~= nil and SaveService.kindOf(session.shift.store) == "production")
end

-- True while anyone on this server is bound to production: server-wide test settings
-- (mixedOrders, simulateLoadFailure) are refused then.
function TestStore.anyProductionBound(): boolean
	for player in SaveService.profiles do
		if TestStore.productionBound(player) then
			return true
		end
	end
	for player in ShiftService.sessions do
		if TestStore.productionBound(player) then
			return true
		end
	end
	return false
end

-- Refusal line for a test mutator (a command that edits rewards, timing or play), or nil when
-- the player is on a test store.
function TestStore.guard(player: Player): string?
	if TestStore.productionBound(player) then
		return "refused: this player is on the real save; run fakeStore first"
	end
	return nil
end

-- Refusal line for a server-wide test setting, or nil when nobody is on production.
function TestStore.guardServer(): string?
	if TestStore.anyProductionBound() then
		return "refused: a player on this server is on the real save; run fakeStore first"
	end
	return nil
end

-- value = { failNext, loseAckNext, delay, fresh }. When the player is bound to production, has
-- no store, or with fresh = true, this selects a new empty FakeStore first, then reloads the
-- player's profile from it and starts a new shift (the current one is abandoned: no reward).
-- A receipt for a persistent store (production or test) that is not settled yet is never
-- abandoned: the switch is refused. When the player is already on a test or memory store,
-- without fresh, it only sets that store's faults (the adapter's, for the test DataStore).
-- Anything else (false included) is refused. Returns a line for the caller.
function TestStore.command(player: Player, value: any): string
	if type(value) ~= "table" then
		return "refused: the real store comes back only with a new play session"
	end
	local session = ShiftService.sessions[player]
	local profile = SaveService.profiles[player]
	local current = profile and profile.store
	local switching = TestStore.productionBound(player) or value.fresh == true or not isTestKind(current)
	if switching and session and SaveService.kindOf(session.shift.store) ~= "memory" and unsettled(session.shift.settlement) then
		-- Its receipt belongs to a persistent save; abandoning it would lose its rewards.
		return "refused: this shift's save is not settled yet"
	end
	local target = if switching then FakeStore.new() else current
	target.failNext = value.failNext or 0
	target.loseAckNext = value.loseAckNext or 0
	target.delay = value.delay or 0
	if not switching then
		return SaveService.kindOf(target) .. " store faults set"
	end
	-- The isolated store is chosen before the profile loads; later joins load from it too.
	SaveService.store = target
	SaveService.simulateLoadFailure = false
	local loaded = SaveService.load(player, target)
	if session then
		session.devForcedTip = nil
		session.shift = ShiftService.newShift(player)
	end
	return "fake store, profile " .. loaded.status .. ", new shift"
end

-- value = coins every served order earns for this player, or nil to score normally. Only on a
-- test store; never server-wide.
function TestStore.forceTip(player: Player, value: any): string
	local refusal = TestStore.guard(player)
	if refusal then
		return refusal
	end
	local session = ShiftService.sessions[player]
	if not session then
		return "no session"
	end
	session.devForcedTip = if type(value) == "number" then value else nil
	return "ok"
end

return TestStore

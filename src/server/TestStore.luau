--!strict
-- Studio test hook behind Main's fakeStore command and its test mutators: puts a player's
-- saving on an in-memory FakeStore so the pending and retry states can be seen without
-- touching the real save. Everything is decided by the selected player's own loaded store,
-- never by the server-wide one: with two players, one switching to a fake store changes
-- nothing for the other. A player still bound to the real store gets no test faults and no
-- test mutations (forced coins, scripted play, clock edits). One way only: once a player is on
-- a fake store, the real store comes back only with a new play session. Every profile, shift
-- and receipt also keeps the store it began on (SaveService, ShiftService), so nothing made on
-- a fake store can reach the real one.

local FakeStore = require(script.Parent.FakeStore)
local SaveService = require(script.Parent.SaveService)
local ShiftService = require(script.Parent.ShiftService)

local TestStore = {}

local function unsettled(settlement: string?): boolean
	return settlement == "pending" or settlement == "retry"
end

local function isFake(store: any): boolean
	return store ~= nil and store ~= SaveService.realStore
end

-- True while the player's loaded profile or current shift is bound to the real store (a shift
-- begun there can still commit there after a reload). With no real store at all, nothing is.
function TestStore.productionBound(player: Player): boolean
	local real = SaveService.realStore
	if real == nil then
		return false
	end
	local profile = SaveService.profiles[player]
	local session = ShiftService.sessions[player]
	return (profile ~= nil and profile.store == real) or (session ~= nil and session.shift.store == real)
end

-- Refusal line for a test mutator (a command that edits rewards, timing or play), or nil when
-- the player is on a test store.
function TestStore.guard(player: Player): string?
	if TestStore.productionBound(player) then
		return "refused: this player is on the real save; run fakeStore first"
	end
	return nil
end

-- value = { failNext, loseAckNext, delay, fresh }. When the player is bound to the real store,
-- or with fresh = true, this selects a new empty fake store first, then reloads the player's
-- profile from it and starts a new shift (the current one is abandoned: no reward). A real
-- receipt that is not settled yet is never abandoned: the switch is refused. When the player
-- is already on a fake store, without fresh, it only changes that store's faults. Anything
-- else (false included) is refused. Returns a line for the caller.
function TestStore.command(player: Player, value: any): string
	if type(value) ~= "table" then
		return "refused: the real store comes back only with a new play session"
	end
	local session = ShiftService.sessions[player]
	local profile = SaveService.profiles[player]
	local switching = TestStore.productionBound(player) or value.fresh == true or not (profile and isFake(profile.store))
	if switching and session and not isFake(session.shift.store) and unsettled(session.shift.settlement) then
		-- Its receipt belongs to the real save; abandoning it would lose real rewards.
		return "refused: this shift's real save is not settled yet"
	end
	local fake = if switching then FakeStore.new() else (profile :: SaveService.Profile).store
	fake.failNext = value.failNext or 0
	fake.loseAckNext = value.loseAckNext or 0
	fake.delay = value.delay or 0
	if not switching then
		return "fake store faults set"
	end
	-- The isolated store is chosen before the profile loads; later joins load from it too.
	SaveService.store = fake
	SaveService.simulateLoadFailure = false
	local loaded = SaveService.load(player, fake)
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

--!strict
-- Studio test hook behind Main's fakeStore command: puts this server's saving on an in-memory
-- FakeStore so the pending and retry states can be seen without touching the real save.
-- One way only: once a fake store is in use, the real store comes back only with a new play
-- session. Every profile, shift and receipt also keeps the store it began on (SaveService,
-- ShiftService), so nothing made on a fake store can reach the real one.

local FakeStore = require(script.Parent.FakeStore)
local SaveService = require(script.Parent.SaveService)
local ShiftService = require(script.Parent.ShiftService)

local TestStore = {}

local function unsettled(settlement: string?): boolean
	return settlement == "pending" or settlement == "retry"
end

-- value = { failNext, loseAckNext, delay, fresh }. On the real store, or with fresh = true,
-- this swaps in a new empty fake store, reloads the profile from it and starts a new shift
-- (the current one is abandoned: no reward). On a fake store without fresh it only changes
-- the faults. Anything else (false included) is refused. Returns a line for the caller.
function TestStore.command(player: Player, value: any): string
	if type(value) ~= "table" then
		return "refused: the real store comes back only with a new play session"
	end
	local session = ShiftService.sessions[player]
	local switching = SaveService.store == SaveService.realStore or value.fresh == true
	if switching and session and session.shift.store == SaveService.realStore and unsettled(session.shift.settlement) then
		-- Its receipt belongs to the real save; abandoning it would lose real rewards.
		return "refused: this shift's real save is not settled yet"
	end
	if switching then
		SaveService.store = FakeStore.new()
	end
	local fake = SaveService.store
	fake.failNext = value.failNext or 0
	fake.loseAckNext = value.loseAckNext or 0
	fake.delay = value.delay or 0
	if not switching then
		return "fake store faults set"
	end
	SaveService.simulateLoadFailure = false
	local profile = SaveService.load(player)
	if session then
		session.shift = ShiftService.newShift(player)
	end
	return "fake store, profile " .. profile.status .. ", new shift"
end

return TestStore

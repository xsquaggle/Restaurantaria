--!strict
-- Player progress persistence.
-- Rules: a failed or unavailable load never writes (so it can't overwrite real data);
-- rewards are committed once per shift id inside UpdateAsync, so retries and parallel
-- sessions cannot pay a shift twice. A shift's commit settles as "saved" (in the DataStore),
-- "session" (kept for this session only, by design: the load failed or saving is
-- unavailable) or "retry" (the write failed, or its reply was lost; the caller keeps the
-- receipt to commit again). A profile keeps the store it was loaded from and a receipt the
-- store its shift began on; a receipt is only ever written to that same store, so nothing
-- earned on a test store can reach the real save.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)
local SaveBackend = require(script.Parent.SaveBackend)

local RECENT_SHIFT_LIMIT = 30
local RETRIES = 3

-- tutorialBonusReceipt records which shift the one-time bonus was paid to and how much, so a
-- retry after a lost reply reports the same payment instead of guessing.
export type Data = {
	tips: number,
	xp: number,
	shiftsCompleted: number,
	recentShiftIds: { string },
	unlockedRecipes: { string },
	tutorialBonusPaid: boolean,
	tutorialBonusReceipt: { shiftId: string, coins: number }?,
}
-- store: where this profile was loaded from; every write for it goes there (nil: no store).
export type Profile = { status: string, data: Data, message: string?, store: any? }
-- One finished shift's rewards, fixed when it ends and committed unchanged on every attempt.
-- store: the store of the profile the shift began on.
export type Receipt = { shiftId: string, tips: number, xp: number, tutorialBonus: number?, store: any?, completedShiftDay: number? }
-- bonusPaid is what the save paid this shift as its tutorial bonus; nil when unknown (retry).
export type Outcome = { state: string, bonusPaid: number?, message: string? }

local SaveService = {}
SaveService.profiles = {} :: { [Player]: Profile }

-- Test hook: when true, loads fail as if the DataStore were down (test and memory stores only).
SaveService.simulateLoadFailure = false

-- Where saves go, chosen once before any store is opened (SaveBackend): kind is "production",
-- "test" (an isolated test DataStore) or "memory" (a FakeStore).
local selected = SaveBackend.select()
SaveService.backend = table.freeze({ kind = selected.kind, name = selected.name })
-- The production DataStore, only in a production runtime; nil in a test or memory one, which
-- never opens it.
SaveService.productionStore = if selected.kind == "production" then selected.store else nil :: any
local storeError: string? = selected.error
-- The store new loads use. The Studio save-flow hook (TestStore) and tests swap in a FakeStore;
-- profiles already loaded keep their own.
SaveService.store = selected.store :: any
-- Waits between attempts; tests make it instant.
SaveService.retryWait = task.wait

-- What kind of store this is: "production", "test", "memory" or "none". Anything else counts
-- as production, so test-only commands fail closed.
function SaveService.kindOf(store: any): string
	if store == nil then
		return "none"
	elseif store == SaveService.productionStore then
		return "production"
	elseif type(store) == "table" and (store.kind == "test" or store.kind == "memory") then
		return store.kind
	end
	return "production"
end

local function defaultData(): Data
	return { tips = 0, xp = 0, shiftsCompleted = 0, recentShiftIds = {}, unlockedRecipes = table.clone(Recipes.Starting), tutorialBonusPaid = false }
end

local function sanitize(raw: any): Data
	local data = defaultData()
	if type(raw) == "table" then
		data.tips = if type(raw.tips) == "number" then raw.tips else 0
		data.xp = if type(raw.xp) == "number" then raw.xp else 0
		data.shiftsCompleted = if type(raw.shiftsCompleted) == "number" then raw.shiftsCompleted else 0
		-- Saves from before the flag existed count as used once they are past the tutorial.
		data.tutorialBonusPaid = if type(raw.tutorialBonusPaid) == "boolean" then raw.tutorialBonusPaid else data.shiftsCompleted > 0
		local receipt = raw.tutorialBonusReceipt
		if type(receipt) == "table" and type(receipt.shiftId) == "string" and type(receipt.coins) == "number" then
			data.tutorialBonusReceipt = { shiftId = receipt.shiftId, coins = receipt.coins }
		end
		if type(raw.recentShiftIds) == "table" then
			for _, id in raw.recentShiftIds do
				if type(id) == "string" then
					table.insert(data.recentShiftIds, id)
				end
			end
		end
		-- Saves from before unlocks existed, or with nothing known left, start from the
		-- starting recipes.
		if type(raw.unlockedRecipes) == "table" then
			local known = Recipes.known(raw.unlockedRecipes)
			if #known > 0 then
				data.unlockedRecipes = known
			end
		end
	end
	return data
end

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function withRetries<T>(fn: () -> T): (boolean, any)
	local lastErr
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < RETRIES then
			SaveService.retryWait(2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

-- onStore: load from this store instead of SaveService.store (the Studio test hook names its
-- fake store, so a test profile can never fall back to the real one).
function SaveService.load(player: Player, onStore: any?): Profile
	local profile: Profile
	local store = onStore or SaveService.store
	-- The load-failure test hook never applies to a production load.
	if SaveService.simulateLoadFailure and SaveService.kindOf(store) ~= "production" then
		profile = { status = "failed", data = defaultData(), message = "Couldn't load your progress. Playing without saving so nothing gets overwritten." }
	elseif not store then
		profile = { status = "unavailable", data = defaultData(), message = "Saving is unavailable in this session (" .. tostring(storeError) .. ")" }
	else
		local ok, result = withRetries(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			profile = { status = "ok", data = sanitize(result) }
		else
			local text = tostring(result)
			local unpublished = string.find(text, "publish", 1, true) ~= nil or string.find(text, "API", 1, true) ~= nil
			profile = {
				status = if unpublished then "unavailable" else "failed",
				data = defaultData(),
				message = if unpublished
					then "Saving is unavailable here: publish the place and enable Studio access to API services"
					else "Couldn't load your progress. Playing without saving so nothing gets overwritten.",
			}
		end
	end
	profile.store = store
	SaveService.profiles[player] = profile
	return profile
end

function SaveService.rank(xp: number): number
	return 1 + xp // Config.Rewards.xpPerRank
end

-- The tutorial bonus this save paid to a shift, from its durable receipt (0 if none).
local function bonusRecorded(data: Data, shiftId: string): number
	local r = data.tutorialBonusReceipt
	return if r and r.shiftId == shiftId then r.coins else 0
end

-- Adds a receipt to data. tutorialBonus is set only for a tutorial shift; it is paid at most
-- once per save, guarded by the saved flag inside the same write as the shift's coins.
-- Returns the bonus paid by this write.
local function apply(data: Data, receipt: Receipt): number
	local paid = 0
	if receipt.tutorialBonus and not data.tutorialBonusPaid then
		paid = receipt.tutorialBonus
		data.tutorialBonusPaid = true -- set even for a 0 bonus: the guarantee is used once
		data.tutorialBonusReceipt = { shiftId = receipt.shiftId, coins = paid }
	end
	data.tips += receipt.tips + paid
	data.xp += receipt.xp
	data.shiftsCompleted += 1
	table.insert(data.recentShiftIds, receipt.shiftId)
	while #data.recentShiftIds > RECENT_SHIFT_LIMIT do
		table.remove(data.recentShiftIds, 1)
	end
	return paid
end

-- Adds one shift's rewards exactly once. Committing the same receipt again (a retry, or a
-- reply that was lost after the write) reports what was recorded and never pays twice.
function SaveService.commitShift(player: Player, receipt: Receipt): Outcome
	local profile = SaveService.profiles[player]
	if not profile then
		return { state = "retry", message = "No profile" }
	end
	if receipt.store ~= profile.store then
		-- Earned on another store (a Studio test store, or before a reload from another one):
		-- never written here.
		return { state = "retry", message = "This shift belongs to a different save store; nothing was written." }
	end
	local sessionOnly = profile.status ~= "ok"
	if table.find(profile.data.recentShiftIds, receipt.shiftId) then
		-- For a loaded save, profile.data only holds what a write returned, so this is durable.
		return {
			state = if sessionOnly then "session" else "saved",
			bonusPaid = bonusRecorded(profile.data, receipt.shiftId),
			message = if sessionOnly then profile.message else nil,
		}
	end

	if sessionOnly then
		-- Keep the session's totals visible, but never write over data we failed to read.
		local paid = apply(profile.data, receipt)
		return { state = "session", bonusPaid = paid, message = profile.message }
	end

	-- Decided inside the transform on every call, so the last call (the one UpdateAsync kept)
	-- sets it; nothing carries over from an earlier attempt.
	local paid: number? = nil
	local latest: Data? = nil
	local ok, result = withRetries(function()
		paid = nil
		return (profile.store :: any):UpdateAsync(key(player), function(old)
			local data = sanitize(old)
			latest = data
			if table.find(data.recentShiftIds, receipt.shiftId) then
				-- Recorded by an earlier attempt whose reply was lost; cancel the write.
				paid = bonusRecorded(data, receipt.shiftId)
				return nil
			end
			paid = apply(data, receipt)
			return data
		end)
	end)
	if ok and paid ~= nil then
		profile.data = if result ~= nil then sanitize(result) else (latest :: Data)
		return { state = "saved", bonusPaid = paid }
	end
	return { state = "retry", message = "Couldn't save this shift: " .. tostring(result) }
end

function SaveService.release(player: Player)
	SaveService.profiles[player] = nil
end

return SaveService

--!strict
-- Player progress persistence.
-- Rules: a failed or unavailable load never writes (so it can't overwrite real data);
-- rewards are committed once per shift id inside UpdateAsync, so retries and parallel
-- sessions cannot pay a shift twice. A shift's commit settles as "saved" (in the DataStore),
-- "session" (kept for this session only, by design: the load failed or saving is
-- unavailable) or "retry" (the write failed; nothing was recorded and the caller keeps the
-- receipt to commit again).

local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Recipes = require(Shared.Recipes)

local STORE_NAME = "Restaurantaria_Progress_v1"
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
export type Profile = { status: string, data: Data, message: string? }
-- One finished shift's rewards, fixed when it ends and committed unchanged on every attempt.
export type Receipt = { shiftId: string, tips: number, xp: number, tutorialBonus: number? }
-- bonusPaid is what the save paid this shift as its tutorial bonus; nil when unknown (retry).
export type Outcome = { state: string, bonusPaid: number?, message: string? }

local SaveService = {}
SaveService.profiles = {} :: { [Player]: Profile }

-- Test hook: when true, loads fail as if the DataStore were down.
SaveService.simulateLoadFailure = false

SaveService.realStore = nil :: DataStore?
local storeError: string? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		SaveService.realStore = result
	else
		storeError = tostring(result)
	end
end
-- The store in use. Tests and the Studio save-flow hook swap in a FakeStore.
SaveService.store = SaveService.realStore :: any
-- Waits between attempts; tests make it instant.
SaveService.retryWait = task.wait

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

function SaveService.load(player: Player): Profile
	local profile: Profile
	if SaveService.simulateLoadFailure then
		profile = { status = "failed", data = defaultData(), message = "Couldn't load your progress. Playing without saving so nothing gets overwritten." }
	elseif not SaveService.store then
		profile = { status = "unavailable", data = defaultData(), message = "Saving is unavailable in this session (" .. tostring(storeError) .. ")" }
	else
		local ok, result = withRetries(function()
			return SaveService.store:GetAsync(key(player))
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
		return SaveService.store:UpdateAsync(key(player), function(old)
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

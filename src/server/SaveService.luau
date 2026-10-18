--!strict
-- Player progress persistence.
-- Rules: a failed or unavailable load never writes (so it can't overwrite real data);
-- rewards are committed once per shift id inside UpdateAsync, so retries and parallel
-- sessions cannot pay a shift twice.

local DataStoreService = game:GetService("DataStoreService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local STORE_NAME = "Restaurantaria_Progress_v1"
local RECENT_SHIFT_LIMIT = 30
local RETRIES = 3

export type Data = { tips: number, xp: number, shiftsCompleted: number, recentShiftIds: { string } }
export type Profile = { status: string, data: Data, message: string? }

local SaveService = {}
SaveService.profiles = {} :: { [Player]: Profile }

-- Test hook: when true, loads fail as if the DataStore were down.
SaveService.simulateLoadFailure = false

local store: DataStore? = nil
local storeError: string? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
	end
end

local function defaultData(): Data
	return { tips = 0, xp = 0, shiftsCompleted = 0, recentShiftIds = {} }
end

local function sanitize(raw: any): Data
	local data = defaultData()
	if type(raw) == "table" then
		data.tips = if type(raw.tips) == "number" then raw.tips else 0
		data.xp = if type(raw.xp) == "number" then raw.xp else 0
		data.shiftsCompleted = if type(raw.shiftsCompleted) == "number" then raw.shiftsCompleted else 0
		if type(raw.recentShiftIds) == "table" then
			for _, id in raw.recentShiftIds do
				if type(id) == "string" then
					table.insert(data.recentShiftIds, id)
				end
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
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

function SaveService.load(player: Player): Profile
	local profile: Profile
	if not store then
		profile = { status = "unavailable", data = defaultData(), message = "Saving is unavailable in this session (" .. tostring(storeError) .. ")" }
	elseif SaveService.simulateLoadFailure then
		profile = { status = "failed", data = defaultData(), message = "Couldn't load your progress. Playing without saving so nothing gets overwritten." }
	else
		local ok, result = withRetries(function()
			return (store :: DataStore):GetAsync(key(player))
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

-- Adds one shift's rewards exactly once. Returns (saved, message).
function SaveService.commitShift(player: Player, shiftId: string, tips: number, xp: number): (boolean, string?)
	local profile = SaveService.profiles[player]
	if not profile then
		return false, "No profile"
	end
	if table.find(profile.data.recentShiftIds, shiftId) then
		return true, "Already recorded"
	end
	local function apply(data: Data)
		data.tips += tips
		data.xp += xp
		data.shiftsCompleted += 1
		table.insert(data.recentShiftIds, shiftId)
		while #data.recentShiftIds > RECENT_SHIFT_LIMIT do
			table.remove(data.recentShiftIds, 1)
		end
	end

	if profile.status ~= "ok" then
		-- Keep the session's totals visible, but never write over data we failed to read.
		apply(profile.data)
		return false, profile.message
	end

	local latest: Data? = nil
	local ok, result = withRetries(function()
		return (store :: DataStore):UpdateAsync(key(player), function(old)
			local data = sanitize(old)
			latest = data
			if table.find(data.recentShiftIds, shiftId) then
				return nil -- already paid by an earlier attempt; cancel the write
			end
			apply(data)
			return data
		end)
	end)
	if ok then
		profile.data = if result ~= nil then sanitize(result) else (latest :: Data)
		return true, nil
	end
	return false, "Couldn't save this shift: " .. tostring(result)
end

function SaveService.release(player: Player)
	SaveService.profiles[player] = nil
end

return SaveService

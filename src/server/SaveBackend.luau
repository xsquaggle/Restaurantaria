--!strict
-- Chooses where player progress is saved. Runs once, when SaveService is first required: before
-- any DataStore is opened and before any profile loads. Three explicit kinds:
--   production  the real save, DataStore "Restaurantaria_Progress_v1"
--   test        an isolated test DataStore whose name starts with "Restaurantaria_TEST_",
--               behind a test-only adapter (TestDataStore) that can inject faults
--   memory      an in-memory FakeStore; nothing is persisted
-- Selection (Studio only): ServerStorage attributes RestaurantariaSaveBackend = "test" or
-- "memory", and RestaurantariaTestStore = the test DataStore name. Set them in Edit before
-- pressing Play. A test or memory runtime never opens the production DataStore: a missing or
-- refused test name, or an unknown backend, gives no store at all (progress kept for the
-- session only), never production. Live servers ignore the attributes and always use
-- production, so this selector cannot isolate a live server; that needs a separate experience.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FakeStore = require(script.Parent.FakeStore)
local TestDataStore = require(script.Parent.TestDataStore)

local SaveBackend = {}

SaveBackend.PRODUCTION_NAME = "Restaurantaria_Progress_v1"
SaveBackend.TEST_PREFIX = "Restaurantaria_TEST_"
SaveBackend.BACKEND_ATTRIBUTE = "RestaurantariaSaveBackend"
SaveBackend.TEST_NAME_ATTRIBUTE = "RestaurantariaTestStore"

export type Selected = {
	kind: string, -- "production" | "test" | "memory"
	name: string?, -- the DataStore name (nil for memory)
	store: any?, -- nil when no store could be opened
	error: string?,
}

-- nil when name may be used as a test DataStore, otherwise why not.
function SaveBackend.refuseTestName(name: any): string?
	if type(name) ~= "string" or name == "" then
		return "no test DataStore name set (" .. SaveBackend.TEST_NAME_ATTRIBUTE .. ")"
	end
	if name == SaveBackend.PRODUCTION_NAME or string.sub(name, 1, #SaveBackend.TEST_PREFIX) ~= SaveBackend.TEST_PREFIX then
		return "test DataStore name refused: it must start with " .. SaveBackend.TEST_PREFIX
	end
	return nil
end

-- The decision itself. options.open opens a DataStore by name; it is called at most once,
-- with the production name only when the backend is production.
function SaveBackend.choose(options: { studio: boolean, backend: any, testName: any, open: (string) -> any }): Selected
	local backend = if options.studio then options.backend else nil
	local function open(kind: string, name: string): Selected
		local ok, result = pcall(options.open, name)
		if ok then
			return { kind = kind, name = name, store = result }
		end
		return { kind = kind, name = name, error = tostring(result) }
	end
	if backend == nil or backend == "" or backend == "production" then
		return open("production", SaveBackend.PRODUCTION_NAME)
	elseif backend == "memory" then
		return { kind = "memory", store = FakeStore.new() }
	elseif backend == "test" then
		local refusal = SaveBackend.refuseTestName(options.testName)
		if refusal then
			return { kind = "test", error = refusal }
		end
		local selected = open("test", options.testName)
		if selected.store then
			selected.store = TestDataStore.wrap(selected.store, options.testName)
		end
		return selected
	end
	-- An unknown backend in Studio is a mistake in a test set-up: no store, never production.
	return { kind = "test", error = "unknown save backend " .. tostring(backend) }
end

-- Reads the selection from the place and opens the chosen store.
function SaveBackend.select(): Selected
	local studio = RunService:IsStudio()
	local backend = ServerStorage:GetAttribute(SaveBackend.BACKEND_ATTRIBUTE)
	local selected = SaveBackend.choose({
		studio = studio,
		backend = backend,
		testName = ServerStorage:GetAttribute(SaveBackend.TEST_NAME_ATTRIBUTE),
		open = function(name: string): any
			return DataStoreService:GetDataStore(name)
		end,
	})
	if not studio and backend ~= nil then
		warn("[Save] " .. SaveBackend.BACKEND_ATTRIBUTE .. " is ignored outside Studio; using production")
	end
	if studio then
		print(string.format("[Save] backend=%s store=%s%s", selected.kind, tostring(selected.name),
			if selected.error then " error=" .. selected.error else ""))
	end
	return selected
end

return SaveBackend

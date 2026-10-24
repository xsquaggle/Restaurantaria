-- Offline runner body (run.py prepends SOURCES and TESTS and runs the result with the Luau
-- CLI). A mock of the few Roblox APIs the server modules and checks use: an instance tree
-- built from default.project.json's layout, require, task on a virtual clock (os.clock and
-- workspace:GetServerTimeNow follow it, so waits take no real time), and a DataStoreService
-- whose stores fail any call. MOCK EVIDENCE ONLY: no Roblox engine, DataStore, network,
-- player or Studio is involved, and timing is simulated.

local REAL_G = getfenv()

------------------------------------------------------------------------------------------
-- Scheduler

local clock = 0
local queue = {}
local order = 0
local threadErrors = {}
local warnings = {}

local function resume(co: thread, ...: any)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(threadErrors, debug.traceback(co, tostring(err)))
	end
end

local function schedule(at: number, co: thread, ...: any)
	order += 1
	table.insert(queue, { at = at, order = order, co = co, args = table.pack(...) })
end

local task = {}
function task.spawn(f: any, ...: any): thread
	local co = if type(f) == "thread" then f else coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f: any, ...: any): thread
	local co = if type(f) == "thread" then f else coroutine.create(f)
	schedule(clock, co, ...)
	return co
end
function task.delay(t: number?, f: any, ...: any): thread
	local co = if type(f) == "thread" then f else coroutine.create(f)
	schedule(clock + (t or 0), co, ...)
	return co
end
function task.wait(t: number?): number
	local co = coroutine.running()
	local start = clock
	schedule(clock + math.max(t or 0, 1 / 60), co)
	coroutine.yield()
	return clock - start
end

local function drain()
	while #queue > 0 do
		table.sort(queue, function(a, b)
			if a.at ~= b.at then
				return a.at < b.at
			end
			return a.order < b.order
		end)
		local item = table.remove(queue, 1)
		clock = math.max(clock, item.at)
		if clock > 3600 then
			error("virtual clock passed an hour; something never settles")
		end
		resume(item.co, table.unpack(item.args, 1, item.args.n))
	end
end

------------------------------------------------------------------------------------------
-- Instances

local Methods = {}
local Inst = {}
Inst.__index = function(self: any, k: string): any
	local m = Methods[k]
	if m then
		return m
	end
	local v = rawget(self, "_props")[k]
	if v ~= nil then
		return v
	end
	for _, c in rawget(self, "_children") do
		if c.Name == k then
			return c
		end
	end
	return nil
end
Inst.__newindex = function(self: any, k: string, v: any)
	local props = rawget(self, "_props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "_children")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		if v then
			table.insert(rawget(v, "_children"), self)
		end
	end
	props[k] = v
end
Inst.__tostring = function(self: any): string
	return self.Name
end

local function newInstance(className: string, name: string?, parent: any?): any
	local self = setmetatable({ _props = { ClassName = className, Name = name or className }, _children = {}, _attrs = {} }, Inst)
	if parent then
		self.Parent = parent
	end
	return self
end

function Methods.FindFirstChild(self: any, name: string, recursive: boolean?): any
	for _, c in rawget(self, "_children") do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_children") do
			local found = c:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function Methods.WaitForChild(self: any, name: string): any
	return assert(self:FindFirstChild(name), "mock: no child " .. name)
end
function Methods.GetChildren(self: any): { any }
	return table.clone(rawget(self, "_children"))
end
function Methods.GetDescendants(self: any): { any }
	local out = {}
	for _, c in rawget(self, "_children") do
		table.insert(out, c)
		for _, d in c:GetDescendants() do
			table.insert(out, d)
		end
	end
	return out
end
function Methods.IsA(self: any, className: string): boolean
	return self.ClassName == className
end
function Methods.GetFullName(self: any): string
	local parent = self.Parent
	return if parent and parent.ClassName ~= "DataModel" then parent:GetFullName() .. "." .. self.Name else self.Name
end
function Methods.GetAttribute(self: any, name: string): any
	return rawget(self, "_attrs")[name]
end
function Methods.SetAttribute(self: any, name: string, value: any)
	rawget(self, "_attrs")[name] = value
end
function Methods.Destroy(self: any)
	self.Parent = nil
end

------------------------------------------------------------------------------------------
-- Services and globals

-- Any call on a store from DataStoreService counts here and fails: the checks swap in
-- FakeStores, so a real-store call is always a test failure.
local realStoreCalls = {}
local function realStore(name: string): any
	local store = {}
	for _, method in { "GetAsync", "SetAsync", "UpdateAsync", "RemoveAsync", "IncrementAsync" } do
		store[method] = function()
			table.insert(realStoreCalls, name .. ":" .. method)
			error("mock: the real DataStore must never be used")
		end
	end
	return store
end

local game = newInstance("DataModel", "game")
local services = {}
local guid = 0
local function service(name: string): any
	local s = services[name]
	if s then
		return s
	end
	s = newInstance(name, name, game)
	if name == "DataStoreService" then
		function s.GetDataStore(_self: any, storeName: string): any
			return realStore(storeName)
		end
	elseif name == "HttpService" then
		function s.GenerateGUID(_self: any, _wrap: boolean?): string
			guid += 1
			return string.format("00000000-0000-0000-0000-%012d", guid)
		end
	elseif name == "RunService" then
		function s.IsStudio(): boolean
			return true
		end
		function s.IsServer(): boolean
			return true
		end
		function s.IsClient(): boolean
			return false
		end
	elseif name == "Players" then
		function s.GetPlayers(): { any }
			return {}
		end
	elseif name == "StarterPlayer" then
		newInstance("StarterPlayerScripts", "StarterPlayerScripts", s)
	end
	services[name] = s
	return s
end
function Methods.GetService(_self: any, name: string): any
	return service(name)
end

local workspace = service("Workspace")
function workspace.GetServerTimeNow(): number
	return 1.8e9 + clock
end

local function enumProxy(path: string): any
	return setmetatable({}, {
		__index = function(_, k)
			return enumProxy(path .. "." .. k)
		end,
		__tostring = function()
			return path
		end,
	})
end

local mockOs = setmetatable({
	clock = function(): number
		return clock
	end,
}, { __index = os })

local GLOBALS: any = setmetatable({
	game = game,
	workspace = workspace,
	task = task,
	os = mockOs,
	Enum = enumProxy("Enum"),
	Instance = {
		new = function(className: string): any
			return newInstance(className)
		end,
	},
	Color3 = {
		fromRGB = function(r, g, b)
			return { R = r / 255, G = g / 255, B = b / 255 }
		end,
		new = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
	},
	typeof = function(v: any): string
		return if getmetatable(v) == Inst then "Instance" else type(v)
	end,
	warn = function(...: any)
		local parts = table.pack(...)
		for i = 1, parts.n do
			parts[i] = tostring(parts[i])
		end
		table.insert(warnings, table.concat(parts, " ", 1, parts.n))
	end,
}, { __index = REAL_G })

------------------------------------------------------------------------------------------
-- Modules from default.project.json's layout

local ROOTS = {
	{ dir = "src/shared/", parent = service("ReplicatedStorage"), name = "Shared" },
	{ dir = "src/server/", parent = service("ServerScriptService"), name = "Server" },
	{ dir = "src/client/", parent = service("StarterPlayer"):FindFirstChild("StarterPlayerScripts"), name = "Client" },
}
local sourceOf = {}
for _, root in ROOTS do
	local folder = newInstance("Folder", root.name, root.parent)
	for path, source in SOURCES do
		if string.sub(path, 1, #root.dir) == root.dir then
			local parts = string.split(string.sub(path, #root.dir + 1), "/")
			local parent = folder
			for i = 1, #parts - 1 do
				parent = parent:FindFirstChild(parts[i]) or newInstance("Folder", parts[i], parent)
			end
			local file = parts[#parts]
			local name, class = file, "ModuleScript"
			if string.match(file, "%.server%.luau$") then
				name, class = string.gsub(file, "%.server%.luau$", ""), "Script"
			elseif string.match(file, "%.client%.luau$") then
				name, class = string.gsub(file, "%.client%.luau$", ""), "LocalScript"
			else
				name = string.gsub(file, "%.luau$", "")
			end
			local inst = newInstance(class, name, parent)
			sourceOf[inst] = { path = path, source = source }
		end
	end
end

local loaded = {}
local function run(source: string, chunk: string, script: any): any
	local fn, err = loadstring(source, "=" .. chunk)
	if not fn then
		error("mock: " .. tostring(err), 0)
	end
	setfenv(fn, setmetatable({ script = script }, { __index = GLOBALS }))
	return fn()
end
GLOBALS.require = function(inst: any): any
	if loaded[inst] ~= nil then
		return loaded[inst]
	end
	local entry = sourceOf[inst]
	if not entry or inst.ClassName ~= "ModuleScript" then
		error("mock: cannot require " .. tostring(inst), 2)
	end
	local result = run(entry.source, entry.path, inst)
	loaded[inst] = result
	return result
end

------------------------------------------------------------------------------------------
-- Run each check

local failed = 0
for _, test in TESTS do
	local done, ok, result = false, false, nil
	task.spawn(function()
		ok, result = pcall(run, test.source, test.path, nil)
		done = true
	end)
	drain()
	if not done then
		ok, result = false, "never finished (a thread waits forever)"
	end
	print(string.format("[%s] %s", if ok then "PASS" else "FAIL", test.path))
	print("  " .. string.gsub(tostring(result), "\n", "\n  "))
	if not ok then
		failed += 1
	end
end
print(string.format("virtual time %.1f s; %d warning(s) from the code under test", clock, #warnings))
for _, w in warnings do
	print("  warn: " .. w)
end
if #threadErrors > 0 then
	failed += 1
	print("errors in spawned threads:")
	for _, e in threadErrors do
		print("  " .. e)
	end
end
if #realStoreCalls > 0 then
	failed += 1
	print("REAL DATASTORE CALLED (mock): " .. table.concat(realStoreCalls, ", "))
else
	print("real DataStore calls (mock DataStoreService): 0")
end
print(if failed == 0 then "ALL PASSED (mock environment)" else string.format("%d FAILED", failed))
if failed > 0 then
	error("offline checks failed", 0)
end

-- The CustomerLooks container (Astra r18, QA18-01: customers invisible while "Marta is
-- waiting"). The saved place held three empty ReplicatedStorage.CustomerLooks folders; the
-- server made a fourth and built the looks into it, and the client watched the first, empty
-- one. Each case builds a stand-in for ReplicatedStorage (a private folder, never the place's
-- own) in a state a saved place can be in, then plays the old rules (replicated below from the
-- build Astra tested: the server module made a new folder whenever it loaded, and the client
-- took the first folder of the name) and the new ones (LooksFolder.claim on the server,
-- LooksFolder.binder on the client, CustomerLooks.start). The "before" rows are expected to
-- show the fault and are checked as such; the "after" rows must not. Mock only: run it with
-- tests/offline/run.py (last in the list, since starting CustomerLooks lets later arrivals find
-- looks) or with the same mock inside Studio; against the place's own modules it would build
-- real avatars.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local LooksFolder = require(Shared.LooksFolder)
local Recipes = require(Shared.Recipes)
local Server = game:GetService("ServerScriptService").Server
-- Loaded the way the game loads them: ShiftService requires CustomerLooks.
local ShiftService = require(Server.ShiftService)
local CustomerLooks = require(Server.CustomerLooks)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local NAME = LooksFolder.NAME
local LOOKS = { "fallback:marta", "fallback:bo", "fallback:ines" }

-- A stand-in for ReplicatedStorage as saved: `stale` lists the saved folders of the name in
-- child order, each "empty", "populated" (an old look inside) or "old token" (populated and
-- stamped by an earlier server).
local function savedPlace(stale: { string }): any
	local place = Instance.new("Folder")
	place.Name = "ReplicatedStorage stand-in"
	for _, kind in stale do
		local folder = Instance.new("Folder")
		folder.Name = NAME
		if kind ~= "empty" then
			local old = Instance.new("Model")
			old.Name = "fallback:marta"
			old:SetAttribute("Stale", true)
			old.Parent = folder
		end
		if kind == "old token" then
			folder:SetAttribute(LooksFolder.TOKEN, "token of an earlier server")
		end
		folder.Parent = place
	end
	return place
end

local function named(place: any): { any }
	local out = {}
	for _, c in place:GetChildren() do
		if c.Name == NAME then
			table.insert(out, c)
		end
	end
	return out
end

-- Fills a container the way the server's fallbacks do.
local function build(folder: any)
	for _, key in LOOKS do
		local m = Instance.new("Model")
		m.Name = key
		m.Parent = folder
	end
end

-- The build Astra tested, replicated: the server module made a folder whenever it loaded and
-- built the looks into it; the client bound the first folder of the name (WaitForChild).
local function serverBefore(place: any): any
	local folder = Instance.new("Folder")
	folder.Name = NAME
	folder.Parent = place
	build(folder)
	return folder
end
local function clientBefore(place: any): any
	return place:FindFirstChild(NAME)
end

-- Who a client shows for the first customer from the folder it bound: Marta's look (or, after
-- LOOK_WAIT, any look there), "stale" when that look is an old saved one, or "nobody".
local function shown(folder: any): string
	if not folder then
		return "nobody"
	end
	local look = folder:FindFirstChild("fallback:marta") or folder:FindFirstChildOfClass("Model")
	if not look then
		return "nobody"
	end
	return if look:GetAttribute("Stale") then "stale" else look.Name
end

-- 1. The saved place as found in the main place and the QA copy: three empty folders.
do
	local before = savedPlace({ "empty", "empty", "empty" })
	local live = serverBefore(before)
	local bound = clientBefore(before)
	check("before, three empty: the server's folder is the fourth of the name", #named(before), 4)
	check("before, three empty: the client binds a folder that is not the server's", bound ~= live, true)
	check("before, three empty: so Marta is not shown (QA18-01)", shown(bound), "nobody")

	local after = savedPlace({ "empty", "empty", "empty" })
	local container = LooksFolder.binder(after)
	local folder, removed, kept = LooksFolder.claim(after, "token A")
	build(folder)
	check("after, three empty: the three are removed", removed, 3)
	check("after, three empty: none kept", kept, 0)
	check("after, three empty: one folder of the name left", #named(after), 1)
	check("after, three empty: the client binds the server's", container() == folder, true)
	check("after, three empty: Marta is shown", shown(container()), "fallback:marta")
end

-- 2. A saved folder with something in it, first, then an empty one.
do
	local before = savedPlace({ "populated", "empty" })
	local live = serverBefore(before)
	check("before, populated first: the client binds the saved folder, not the server's", clientBefore(before) ~= live, true)
	check("before, populated first: so it shows the old saved look", shown(clientBefore(before)), "stale")

	local after = savedPlace({ "populated", "empty" })
	local saved = named(after)[1]
	local container = LooksFolder.binder(after)
	local folder, removed, kept = LooksFolder.claim(after, "token B")
	build(folder)
	check("after, populated first: the empty one is removed", removed, 1)
	check("after, populated first: the populated one is kept", kept, 1)
	check("after, populated first: and still holds its model", saved.Parent == after and #saved:GetChildren() == 1, true)
	check("after, populated first: it is never live", LooksFolder.isLive(after, saved), false)
	check("after, populated first: the client binds the server's", container() == folder, true)
	check("after, populated first: and shows the new Marta", shown(container()), "fallback:marta")
end

-- 3. A folder and token saved from an earlier server (pasted back from a Play session).
do
	local place = savedPlace({ "old token" })
	place:SetAttribute(LooksFolder.TOKEN, "token of an earlier server")
	local saved = named(place)[1]
	local container = LooksFolder.binder(place)
	check("old token: until the server stamps its own, the saved pair matches", container() == saved, true)
	local folder, removed, kept = LooksFolder.claim(place, "token C")
	build(folder)
	check("old token: kept (it holds a model)", kept, 1)
	check("old token: nothing removed", removed, 0)
	check("old token: the saved folder is no longer live", LooksFolder.isLive(place, saved), false)
	check("old token: the client moves to the server's folder", container() == folder, true)
	check("old token: and shows the new Marta", shown(container()), "fallback:marta")
end

-- 4. Arrival order on a client: the folder and the token replicate separately.
do
	local place = savedPlace({ "empty", "empty", "empty" })
	local container = LooksFolder.binder(place)
	check("arrival: saved folders only, no token: nothing bound", container(), nil)
	place:SetAttribute(LooksFolder.TOKEN, "token D")
	check("arrival: the token without its folder: nothing bound", container(), nil)
	local folder = Instance.new("Folder")
	folder.Name = NAME
	folder:SetAttribute(LooksFolder.TOKEN, "token D")
	folder.Parent = place
	check("arrival: then the folder: bound", container() == folder, true)

	local place2 = savedPlace({ "empty" })
	local container2 = LooksFolder.binder(place2)
	local folder2 = Instance.new("Folder")
	folder2.Name = NAME
	folder2:SetAttribute(LooksFolder.TOKEN, "token E")
	folder2.Parent = place2
	check("arrival: the folder without the token: nothing bound", container2(), nil)
	place2:SetAttribute(LooksFolder.TOKEN, "token E")
	check("arrival: then the token: bound", container2() == folder2, true)
	folder2:Destroy()
	check("arrival: a bound folder that goes away is let go", container2(), nil)
end

-- 5. The server module as the game runs it.
do
	check("server: requiring CustomerLooks (and ShiftService) adds no folder to ReplicatedStorage", #named(ReplicatedStorage), 0)
	check("server: ShiftService loaded", type(ShiftService.apply), "function")
	local player = { UserId = 1 } :: any
	check("server: before start, no look is ready, so arrivals wait", CustomerLooks.pick(player, {}, {}, {}, 1), nil)
	check("server: before start, nothing to describe", #CustomerLooks.describe(), 0)

	local place = savedPlace({ "empty", "populated", "empty", "empty" })
	local saved = named(place)[2]
	local live = CustomerLooks.start(place)
	task.wait()
	check("server: start leaves the live folder and the populated saved one", #named(place), 2)
	check("server: the populated saved one keeps its model", saved.Parent == place and #saved:GetChildren() == 1, true)
	check("server: the live folder is the one clients bind", LooksFolder.binder(place)() == live, true)
	local built = #live:GetChildren()
	check("server: the three fallback looks are built into it", built, 3)
	check("server: a second start returns the same folder", CustomerLooks.start(place) == live, true)
	task.wait()
	check("server: and makes no second folder", #named(place), 2)
	check("server: and builds nothing more", #live:GetChildren(), built)
	local look = CustomerLooks.pick(player, {}, {}, {}, 1)
	check("server: the first arrival gets Marta's look from the live folder", look and look.key, "fallback:marta")
	check("server: named from the cast", look and look.name, Recipes.Cast[1].name)
	check("server: the look is in the folder the client binds", LooksFolder.binder(place)():FindFirstChild("fallback:marta") ~= nil, true)
end

local summary = string.format("looks folder checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

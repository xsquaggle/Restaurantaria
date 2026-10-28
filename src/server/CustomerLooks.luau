--!strict
-- Customer appearances (QA-002). Every customer is a native Roblox avatar: an R15 model built
-- offstage from a HumanoidDescription and kept in the server's CustomerLooks folder in
-- ReplicatedStorage (LooksFolder), which each client clones into its own Order room.
-- Friends' avatars are one source; the curated fallbacks are the other, and they are built as
-- soon as the server starts, so a customer is only admitted once their look exists and nothing
-- ever waits on loading.
--
-- Appearance, personality and visit stay separate (dialogue-plan, "Who gets which pool"):
-- the look key (`friend:<userId>` or `fallback:<id>`) is the appearance, `pool` indexes
-- Recipes.Cast, and the customer record in ShiftService is the visit.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LooksFolder = require(ReplicatedStorage.Shared.LooksFolder)
local Recipes = require(ReplicatedStorage.Shared.Recipes)

local CustomerLooks = {}

export type Look = { key: string, name: string, username: string?, pool: number }

-- One curated fallback per enabled pool; the fallback named Marta is always P01, and so on.
-- Short, normal and tall bodies, one with a large accessory (the sun hat). All catalog
-- items are Roblox-made. top and bottom colour the body if the clothes fail to load. A
-- proposal until Lawson approves the cast's looks.
local FALLBACKS = {
	{ id = "marta", pool = 1, height = 1.0, width = 0.8, skin = Color3.fromRGB(234, 184, 146), hair = "7193448258", hat = "", shirt = 398634295, pants = 398634487, top = Color3.fromRGB(196, 196, 204), bottom = Color3.fromRGB(70, 72, 84) },
	{ id = "bo", pool = 2, height = 1.05, width = 0.85, skin = Color3.fromRGB(124, 92, 70), hair = "7193401217", hat = "607702162", shirt = 4047884939, pants = 382538503, top = Color3.fromRGB(78, 120, 170), bottom = Color3.fromRGB(52, 56, 66) },
	{ id = "ines", pool = 3, height = 0.9, width = 0.75, skin = Color3.fromRGB(255, 220, 190), hair = "7193442167", hat = "116076110", shirt = 398635081, pants = 382537569, top = Color3.fromRGB(46, 70, 170), bottom = Color3.fromRGB(60, 60, 72) },
}
-- Friends tried per player; a shift has six customers, so a dozen gives plenty of variety.
local MAX_FRIENDS = 12

-- The live container, made by start() (QA18-01). Requiring this module creates nothing, so a
-- require in Studio's Edit mode can no longer leave a folder behind in the saved place.
local folder: Folder? = nil

type Friend = { key: string, name: string, username: string, id: number }
local friends: { [Player]: { Friend } } = {}

-- Studio only: workspace attribute DebugLookFailure = "friends" makes the friend list fail
-- to load, "assets" makes every full avatar fail so the plain stand-ins are used.
local function failing(what: string): boolean
	return RunService:IsStudio() and workspace:GetAttribute("DebugLookFailure") == what
end

-- Builds one look and stores it in into. A description whose items fail to load is retried
-- with its body only (skin, proportions, no clothes or accessories), so a look is never a
-- broken rig; dress, when given, colours that body's torso and legs so it still reads as dressed.
local function store(into: Folder, key: string, description: HumanoidDescription, dress: { top: Color3, bottom: Color3 }?)
	local ok, model = pcall(function()
		if failing("assets") then
			error("simulated asset failure")
		end
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	local plain = false
	if not ok then
		warn(string.format("[CustomerLooks] %s: %s; using its plain body", key, tostring(model)))
		local body = Instance.new("HumanoidDescription")
		for _, p in { "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale", "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
			(body :: any)[p] = (description :: any)[p]
		end
		if dress then
			body.TorsoColor = dress.top
			body.LeftLegColor = dress.bottom
			body.RightLegColor = dress.bottom
		end
		ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, body, Enum.HumanoidRigType.R15)
		plain = true
	end
	if not ok then
		warn(string.format("[CustomerLooks] %s: no look (%s)", key, tostring(model)))
		return
	end
	-- A figure for clients to clone: no scripts, no physics, no Roblox name tag.
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	model.Name = key
	model:SetAttribute("Plain", plain)
	model.Parent = into
end

-- Makes the one live container, once per server: a second call returns the same folder and
-- builds nothing more. Stale CustomerLooks folders saved in the place are handled by
-- LooksFolder.claim (empty ones removed, others left alone and never bound). parent is
-- ReplicatedStorage unless a check passes its own. Then the fallbacks are built into it.
function CustomerLooks.start(parent: Instance?): Folder
	local existing = folder
	if existing then
		return existing
	end
	local into, removed, kept = LooksFolder.claim(parent or ReplicatedStorage, HttpService:GenerateGUID(false))
	folder = into
	if removed > 0 then
		print(string.format("[CustomerLooks] removed %d stale empty CustomerLooks folder(s) saved in the place", removed))
	end
	if kept > 0 then
		warn(string.format("[CustomerLooks] left %d saved CustomerLooks folder(s) with contents alone; customers use this server's own", kept))
	end
	for _, f in FALLBACKS do
		task.spawn(function()
			local d = Instance.new("HumanoidDescription")
			d.HeightScale = f.height
			d.WidthScale = f.width
			d.DepthScale = f.width
			d.HeadColor = f.skin
			d.TorsoColor = f.skin
			d.LeftArmColor = f.skin
			d.RightArmColor = f.skin
			d.LeftLegColor = f.skin
			d.RightLegColor = f.skin
			d.HairAccessory = f.hair
			d.HatAccessory = f.hat
			d.Shirt = f.shirt
			d.Pants = f.pants
			store(into, "fallback:" .. f.id, d, { top = f.top, bottom = f.bottom })
		end)
	end
	return into
end

-- Loads the player's friends in the background: the list first (every page until
-- MAX_FRIENDS), then each avatar in turn. Shifts carry on with fallbacks meanwhile.
function CustomerLooks.loadFriends(player: Player)
	local list: { Friend } = {}
	friends[player] = list
	local ok, err = pcall(function()
		if failing("friends") then
			error("simulated friend list failure")
		end
		local pages = Players:GetFriendsAsync(player.UserId)
		while #list < MAX_FRIENDS do
			for _, item in pages:GetCurrentPage() do
				if #list >= MAX_FRIENDS then
					break
				end
				table.insert(list, { key = "friend:" .. item.Id, name = item.DisplayName, username = item.Username, id = item.Id })
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn(string.format("[CustomerLooks] friends of %d: %s; fallbacks only", player.UserId, tostring(err)))
	end
	for _, f in list do
		local into = folder
		if friends[player] ~= list or not into then
			return
		end
		if into:FindFirstChild(f.key) then
			continue
		end
		local got, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, f.id)
		if got then
			store(into, f.key, description)
		else
			warn(string.format("[CustomerLooks] %s: %s", f.key, tostring(description)))
		end
	end
end

function CustomerLooks.forget(player: Player)
	friends[player] = nil
end

-- A friend's pool comes from a hash of the shop owner and the appearance, so it is the same
-- every session while the enabled pools are (the saved assignment comes with saving).
local function poolFor(owner: number, key: string): number
	local h = owner % 2147483647
	for i = 1, #key do
		h = (h * 31 + string.byte(key, i)) % 2147483647
	end
	return h % #Recipes.Cast + 1
end

-- The look for the next customer of a shift, or nil while none is ready.
-- present: look keys of customers in the shop now (nobody is there twice); visits: how many
-- times each look has come this shift; names: friends' display names in this shift, which a
-- fallback's fictional name must not repeat. Friends come first, the least-seen first;
-- fallbacks rotate with the arrival number.
function CustomerLooks.pick(player: Player, present: { [string]: boolean }, visits: { [string]: number }, names: { [string]: boolean }, arrival: number): Look?
	local into = folder
	if not into then
		return nil
	end
	local best: Friend? = nil
	for _, f in friends[player] or {} do
		if present[f.key] or not into:FindFirstChild(f.key) then
			continue
		end
		if best == nil or (visits[f.key] or 0) < (visits[best.key] or 0) then
			best = f
		end
	end
	if best then
		return { key = best.key, name = best.name, username = best.username, pool = poolFor(player.UserId, best.key) }
	end
	for k = 0, #FALLBACKS - 1 do
		local f = FALLBACKS[((arrival - 1 + k) % #FALLBACKS) + 1]
		local key = "fallback:" .. f.id
		local name = Recipes.Cast[f.pool].name
		if not present[key] and not names[name:lower()] and into:FindFirstChild(key) then
			return { key = key, name = name, pool = f.pool }
		end
	end
	return nil
end

-- What exists right now (Studio debug and evidence).
function CustomerLooks.describe(): { string }
	local rows = {}
	local into = folder
	if not into then
		return rows
	end
	for _, m in into:GetChildren() do
		local head = m:FindFirstChild("Head") :: BasePart?
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		local accessories = {}
		for _, a in m:GetChildren() do
			if a:IsA("Accessory") then
				table.insert(accessories, a.Name)
			end
		end
		table.insert(rows, string.format("%s plain=%s hip=%.2f headTop=%.2f accessories=%s", m.Name, tostring(m:GetAttribute("Plain")), humanoid and humanoid.HipHeight or 0, if head and root then head.Position.Y + head.Size.Y / 2 - (root.Position.Y - root.Size.Y / 2) + (humanoid and humanoid.HipHeight or 0) else 0, table.concat(accessories, ",")))
	end
	table.sort(rows)
	return rows
end

return CustomerLooks

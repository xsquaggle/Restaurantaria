--!strict
-- Resolves an art name to something an ImageLabel can show.
--
-- 1. An uploaded image asset id from Assets (the only path that works in a published game).
-- 2. In Studio only: sprite data cut by tools/ArtPipeline.luau into ReplicatedStorage.DevArt,
--    shown through an EditableImage, so supplied art can be judged in the real layout before
--    it is uploaded.
-- 3. Nothing. Missing art is reported once and the image stays empty: code never draws a
--    stand-in.

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(script.Parent.Assets)

local Art = {}

local editables: { [string]: EditableImage } = {}
local sizes: { [string]: Vector2 } = {}
local reported: { [string]: boolean } = {}
-- Which art each label shows, so images no label shows any more can be freed when Studio's
-- EditableImage memory budget runs out.
-- (Strong keys: Roblox can collect an Instance's weak-table key while the Instance still lives.)
local shown: { [Instance]: string } = {}
-- Labels whose image was freed while they were hidden; Art.restore re-applies them when
-- their station is shown again.
local stale: { [Instance]: boolean } = {}

-- A label counts as showing only when it is in the game and no ancestor hides it, so the
-- art of the three hidden stations can be freed when the budget runs out.
local function isShowing(inst: Instance): boolean
	if not inst:IsDescendantOf(game) then
		return false
	end
	local p: Instance? = inst
	while p and not p:IsA("ScreenGui") do
		if p:IsA("GuiObject") and not p.Visible then
			return false
		end
		p = p.Parent
	end
	return true
end

local function devFolder(name: string): Instance?
	name = Assets.Alias[name] or name
	if not RunService:IsStudio() then
		return nil
	end
	local root = ReplicatedStorage:FindFirstChild("DevArt")
	return root and root:FindFirstChild(name)
end

local function devImage(name: string): EditableImage?
	if editables[name] then
		return editables[name]
	end
	local folder = devFolder(name)
	if not folder then
		return nil
	end
	local parts = {}
	for i = 1, folder:GetAttribute("Parts") :: number do
		table.insert(parts, require(folder:FindFirstChild(tostring(i)) :: ModuleScript) :: any)
	end
	local packed = EncodingService:Base64Decode(buffer.fromstring(table.concat(parts)))
	local pixels = EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
	local size = Vector2.new(folder:GetAttribute("Width") :: number, folder:GetAttribute("Height") :: number)
	local function create(): EditableImage?
		local ok, image = pcall(function()
			return AssetService:CreateEditableImage({ Size = size })
		end)
		return if ok then image else nil
	end
	local image = create()
	if not image then
		-- Free every image no live label still shows, then try once more.
		local inUse = {}
		for label, shownName in shown do
			if not label:IsDescendantOf(game) then
				shown[label] = nil
			elseif isShowing(label) then
				inUse[shownName] = true
			end
		end
		for other, editable in editables do
			if not inUse[other] then
				editable:Destroy()
				editables[other] = nil
				for label, shownName in shown do
					if shownName == other then
						stale[label] = true
					end
				end
			end
		end
		image = create()
	end
	if not image then
		warn("[Art] no memory budget left for " .. name)
		return nil
	end
	image:WritePixelsBuffer(Vector2.zero, size, pixels)
	editables[name] = image
	return image
end

-- True when the art exists through either path.
function Art.has(name: string): boolean
	return Assets.get(name) ~= nil or devFolder(name) ~= nil
end

-- Pixel size of the art when known (DevArt records it; uploaded ids rely on Assets.Meta).
function Art.size(name: string): Vector2?
	if sizes[name] then
		return sizes[name]
	end
	local folder = devFolder(name)
	if folder then
		sizes[name] = Vector2.new(folder:GetAttribute("Width") :: number, folder:GetAttribute("Height") :: number)
		return sizes[name]
	end
	return nil
end

function Art.aspect(name: string, fallback: number?): number
	local s = Art.size(name)
	return if s then s.X / s.Y else fallback or 1
end

-- Point an ImageLabel/ImageButton at the art. Returns false (and leaves it empty) if missing.
function Art.apply(label: ImageLabel | ImageButton, name: string): boolean
	local id = Assets.get(name)
	if id then
		label.Image = id
		return true
	end
	if shown[label] == name and not stale[label] and editables[name] then
		return true
	end
	shown[label] = nil
	stale[label] = nil
	local image = devImage(name)
	if image then
		shown[label] = name
		label.ImageContent = Content.fromObject(image)
		return true
	end
	label.Image = ""
	if not reported[name] then
		reported[name] = true
		warn("[Art] missing art: " .. name)
	end
	return false
end

-- Clear a label so the image it showed can be freed (Studio dev art only holds memory while
-- some live label shows it).
-- Re-apply the art of labels under `root` whose image was freed while they were hidden.
function Art.restore(root: Instance)
	for label, name in shown do
		if stale[label] and label:IsDescendantOf(root) then
			Art.apply(label :: ImageLabel, name)
		end
	end
end

function Art.release(label: ImageLabel | ImageButton)
	shown[label] = nil
	stale[label] = nil
	label.ImageContent = Content.none
end

-- Load art ahead of first use (e.g. every state of a button) so a state change never shows
-- an empty frame while the image arrives. Never yields.
function Art.preload(names: { string })
	local ids = {}
	for _, name in names do
		local id = Assets.get(name)
		if id then
			table.insert(ids, id)
		else
			devImage(name)
		end
	end
	if #ids > 0 then
		task.spawn(function()
			ContentProvider:PreloadAsync(ids)
		end)
	end
end

-- Names that were asked for but do not exist yet; the art request list should cover these.
function Art.missing(): { string }
	local list = {}
	for name in reported do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

return Art

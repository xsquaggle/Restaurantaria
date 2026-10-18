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
local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(script.Parent.Assets)

local Art = {}

local editables: { [string]: EditableImage } = {}
local sizes: { [string]: Vector2 } = {}
local reported: { [string]: boolean } = {}

local function devFolder(name: string): Instance?
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
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = size })
	end)
	if not ok or not image then
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
	local image = devImage(name)
	if image then
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

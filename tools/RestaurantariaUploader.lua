-- Restaurantaria image uploader: a local Studio plugin (install this file in the Roblox
-- Plugins folder). Roblox only lets locally loaded plugins call AssetService:CreateAssetAsync,
-- so this is the step that turns repo PNGs into image asset ids.
--
-- Protocol (Edit mode only):
--   1. Tooling creates ServerStorage.RestaurantariaUpload (a Folder) holding one ModuleScript
--      per image, named after the asset (letters, digits, underscores), whose Source is the
--      PNG file encoded as Base64. Not code: the plugin only reads the text.
--   2. Tooling sets the folder's "Status" attribute to "requested".
--   3. The plugin uploads each image and writes "id_<name>" (the asset id) or "err_<name>"
--      attributes on the folder, then sets "Status" to "done".
-- Identical files (same SHA-256) reuse the id from an earlier upload instead of uploading again.

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if RunService:IsRunning() then
	return
end

local FOLDER = "RestaurantariaUpload"
local MAX_SIDE = 1024

local function log(...)
	print("[RestaurantariaUploader]", ...)
end

local function hex(s: string): string
	return (s:gsub(".", function(c)
		return string.format("%02x", string.byte(c))
	end))
end

local function uploadOne(Png, name: string, base64: string): (number?, string?)
	local cache = plugin:GetSetting("uploads") or {}
	local bytes = buffer.tostring(EncodingService:Base64Decode(buffer.fromstring(base64)))
	local hash = hex(EncodingService:ComputeStringHash(bytes, Enum.HashAlgorithm.Sha256))
	if cache[hash] then
		return cache[hash], "reused"
	end
	local image = Png.decode(bytes)
	if image.width > MAX_SIDE or image.height > MAX_SIDE then
		return nil, string.format("%dx%d is larger than %d px", image.width, image.height, MAX_SIDE)
	end
	local size = Vector2.new(image.width, image.height)
	local editable = AssetService:CreateEditableImage({ Size = size })
	editable:WritePixelsBuffer(Vector2.zero, size, image.pixels)
	local result, idOrError = AssetService:CreateAssetAsync(editable, Enum.AssetType.Image, {
		Name = name,
		Description = "Restaurantaria art: " .. name,
	})
	editable:Destroy()
	if result ~= Enum.CreateAssetResult.Success then
		return nil, tostring(result) .. " " .. tostring(idOrError)
	end
	cache[hash] = idOrError
	plugin:SetSetting("uploads", cache)
	return idOrError, nil
end

local busy = false
local function process(folder: Instance)
	if busy or folder:GetAttribute("Status") ~= "requested" then
		return
	end
	busy = true
	folder:SetAttribute("Status", "working")
	local ok, err = pcall(function()
		local Png = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Png") :: ModuleScript)
		for _, child in folder:GetChildren() do
			local name = child.Name
			if child:IsA("ModuleScript") and name:match("^[%w_]+$") then
				local callOk, id, note = pcall(uploadOne, Png, name, (child :: ModuleScript).Source)
				if callOk and id then
					folder:SetAttribute("id_" .. name, id)
					log(name, "->", id, note or "uploaded")
				else
					local message = if callOk then tostring(note) else tostring(id)
					folder:SetAttribute("err_" .. name, message)
					log(name, "failed:", message)
				end
				task.wait(0.5)
			end
		end
	end)
	if not ok then
		folder:SetAttribute("err", tostring(err))
		log("request failed:", err)
	end
	folder:SetAttribute("Status", "done")
	busy = false
end

local function watch(folder: Instance)
	if folder.Name ~= FOLDER then
		return
	end
	folder:GetAttributeChangedSignal("Status"):Connect(function()
		process(folder)
	end)
	process(folder)
end

ServerStorage.ChildAdded:Connect(watch)
for _, child in ServerStorage:GetChildren() do
	watch(child)
end
log("ready")

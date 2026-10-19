--!strict
-- Generated 3D models (Higgsfield output, refined in Blender) for the 3D parts of the game.
--
-- Imported models (Studio's 3D importer, uploaded) live as MeshParts in
-- ReplicatedStorage.Models3D. Until a model is imported, Studio can hold each one as packed geometry in
-- ReplicatedStorage.DevModels.<name> (written by tools/GlbImport.luau) with its colour map in
-- DevArt as <name>_base. build() turns that into a MeshPart through an EditableMesh. Code
-- never shapes a model: vertices, UVs and textures come from the file as generated.

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Art = require(script.Parent.Art)

local Model3D = {}

local function folder(name: string): Instance?
	if not RunService:IsStudio() then
		return nil
	end
	local root = ReplicatedStorage:FindFirstChild("DevModels")
	return root and root:FindFirstChild(name)
end

-- A model brought in through Studio's 3D importer (uploaded mesh and textures), kept as a
-- MeshPart in ReplicatedStorage.Models3D. Works on every client, unlike the dev path.
local function imported(name: string): MeshPart?
	local root = ReplicatedStorage:FindFirstChild("Models3D")
	local m = root and root:FindFirstChild(name)
	return if m and m:IsA("MeshPart") then m else nil
end

function Model3D.has(name: string): boolean
	return imported(name) ~= nil or folder(name) ~= nil
end

-- Size in studs the model was stored at (its bounding box).
function Model3D.size(name: string): Vector3?
	local m = imported(name)
	if m then
		return m.Size
	end
	local f = folder(name)
	return f and f:GetAttribute("Size") :: Vector3
end

-- Geometry layout: u32 vertex count, u32 triangle count, then per vertex 8 f32
-- (position xyz, normal xyz, uv), then 3 u32 per triangle.
function Model3D.build(name: string): MeshPart?
	local m = imported(name)
	if m then
		local copy = m:Clone()
		copy.Anchored = true
		copy.CanCollide = false
		return copy
	end
	local f = folder(name)
	if not f then
		warn("[Model3D] missing model: " .. name)
		return nil
	end
	local parts = {}
	for i = 1, f:GetAttribute("Parts") :: number do
		table.insert(parts, require(f:FindFirstChild(tostring(i)) :: ModuleScript) :: any)
	end
	local packed = EncodingService:Base64Decode(buffer.fromstring(table.concat(parts)))
	local b = EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
	local nv, nt = buffer.readu32(b, 0), buffer.readu32(b, 4)
	local ok, em = pcall(function()
		return AssetService:CreateEditableMesh({})
	end)
	if not ok or em == nil then
		warn("[Model3D] no memory budget for " .. name)
		return nil
	end
	local vids, nids, uids = table.create(nv), table.create(nv), table.create(nv)
	for i = 0, nv - 1 do
		local o = 8 + i * 32
		local r = function(k: number): number
			return buffer.readf32(b, o + k * 4)
		end
		vids[i + 1] = em:AddVertex(Vector3.new(r(0), r(1), r(2)))
		nids[i + 1] = em:AddNormal(Vector3.new(r(3), r(4), r(5)))
		uids[i + 1] = em:AddUV(Vector2.new(r(6), r(7)))
	end
	local base = 8 + nv * 32
	for t = 0, nt - 1 do
		local o = base + t * 12
		local a, c, d = buffer.readu32(b, o) + 1, buffer.readu32(b, o + 4) + 1, buffer.readu32(b, o + 8) + 1
		local face = em:AddTriangle(vids[a], vids[c], vids[d])
		em:SetFaceNormals(face, { nids[a], nids[c], nids[d] })
		em:SetFaceUVs(face, { uids[a], uids[c], uids[d] })
	end
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = true
	part.Material = Enum.Material.SmoothPlastic
	local texture = Art.editable(name .. "_base")
	if texture then
		part.TextureContent = Content.fromObject(texture)
	end
	return part
end

return Model3D

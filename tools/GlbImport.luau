--!strict
-- Studio-only importer for generated 3D models (Higgsfield GLB output, or a Blender re-export).
-- Reads a binary glTF, turns each triangle primitive into an EditableMesh and its PNG maps into
-- EditableImages, and returns MeshParts. It only imports: geometry and textures come from the
-- file unchanged, apart from scaling, an optional texture downsize to the 1024 px EditableImage
-- limit, and normals that the file already carries.
--
-- Install as ServerStorage.GlbImport (ModuleScript). Usage in the Edit command bar:
--   local G = require(game.ServerStorage.GlbImport)
--   local model = G.import(G.fetch(url), { name = "Counter", width = 18 })
--   model.Parent = workspace

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Png = require(Shared:WaitForChild("Png") :: ModuleScript)
local Jpeg = require((Shared:FindFirstChild("Jpeg") or game:GetService("ServerStorage"):FindFirstChild("Jpeg")) :: ModuleScript)

local GlbImport = {}

local MAX_TEXTURE = 1024

function GlbImport.fetch(url: string): buffer
	local was = HttpService.HttpEnabled
	HttpService.HttpEnabled = true
	local ok, body = pcall(function()
		return HttpService:GetAsync(url)
	end)
	HttpService.HttpEnabled = was
	if not ok then
		error("fetch failed: " .. tostring(body))
	end
	return buffer.fromstring(body)
end

type Glb = { json: any, bin: buffer?, binOffset: number }

function GlbImport.parse(data: buffer): Glb
	assert(buffer.readu32(data, 0) == 0x46546C67, "not a GLB file")
	local length = buffer.readu32(data, 8)
	local at = 12
	local json, bin, binOffset = nil, nil, 0
	while at < length do
		local chunkLen = buffer.readu32(data, at)
		local chunkType = buffer.readu32(data, at + 4)
		if chunkType == 0x4E4F534A then
			json = HttpService:JSONDecode(buffer.readstring(data, at + 8, chunkLen))
		elseif chunkType == 0x004E4942 then
			bin = data
			binOffset = at + 8
		end
		at += 8 + chunkLen
	end
	return { json = json, bin = bin, binOffset = binOffset }
end

local COMPONENTS = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4 }

-- Returns a reader for element i (0-based), component c (0-based).
local function accessor(glb: Glb, index: number): (number, (number, number) -> number)
	local acc = glb.json.accessors[index + 1]
	local view = glb.json.bufferViews[acc.bufferView + 1]
	local comps = COMPONENTS[acc.type]
	local ct = acc.componentType
	local size = if ct == 5126 or ct == 5125 then 4 elseif ct == 5123 or ct == 5122 then 2 else 1
	local stride = view.byteStride or comps * size
	local base = glb.binOffset + (view.byteOffset or 0) + (acc.byteOffset or 0)
	local b = glb.bin :: buffer
	local read: (number, number) -> number
	if ct == 5126 then
		read = function(i, c) return buffer.readf32(b, base + i * stride + c * 4) end
	elseif ct == 5125 then
		read = function(i, c) return buffer.readu32(b, base + i * stride + c * 4) end
	elseif ct == 5123 then
		read = function(i, c) return buffer.readu16(b, base + i * stride + c * 2) end
	elseif ct == 5121 then
		read = function(i, c) return buffer.readu8(b, base + i * stride + c) end
	else
		error("unsupported component type " .. tostring(ct))
	end
	return acc.count, read
end

local function imageBytes(glb: Glb, imageIndex: number): (string, buffer)
	local img = glb.json.images[imageIndex + 1]
	local view = glb.json.bufferViews[img.bufferView + 1]
	local start = glb.binOffset + (view.byteOffset or 0)
	local out = buffer.create(view.byteLength)
	buffer.copy(out, 0, glb.bin :: buffer, start, view.byteLength)
	return img.mimeType or "?", out
end

-- Box-filter downsize of an RGBA8 image so its longer side is at most MAX_TEXTURE.
local function shrink(img: Png.Image): Png.Image
	local f = math.ceil(math.max(img.width, img.height) / MAX_TEXTURE)
	if f <= 1 then
		return img
	end
	local w, h = img.width // f, img.height // f
	local out = buffer.create(w * h * 4)
	local src = img.pixels
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, bl, a = 0, 0, 0, 0
			for dy = 0, f - 1 do
				local row = ((y * f + dy) * img.width + x * f) * 4
				for dx = 0, f - 1 do
					local p = row + dx * 4
					r += buffer.readu8(src, p)
					g += buffer.readu8(src, p + 1)
					bl += buffer.readu8(src, p + 2)
					a += buffer.readu8(src, p + 3)
				end
			end
			local n = f * f
			local o = (y * w + x) * 4
			buffer.writeu8(out, o, r // n)
			buffer.writeu8(out, o + 1, g // n)
			buffer.writeu8(out, o + 2, bl // n)
			buffer.writeu8(out, o + 3, a // n)
		end
		if y % 64 == 0 then
			task.wait()
		end
	end
	return { width = w, height = h, pixels = out }
end

local function editableFromTexture(glb: Glb, texIndex: number?): (EditableImage?, string)
	if texIndex == nil then
		return nil, "none"
	end
	local tex = glb.json.textures[texIndex + 1]
	local mime, bytes = imageBytes(glb, tex.source)
	local img
	if mime == "image/png" then
		img = shrink(Png.decode(bytes))
	elseif mime == "image/jpeg" then
		-- Decoded at quarter size (see Jpeg.luau).
		img = shrink(Jpeg.decode(bytes))
	else
		return nil, mime
	end
	local e = AssetService:CreateEditableImage({ Size = Vector2.new(img.width, img.height) })
	e:WritePixelsBuffer(Vector2.zero, Vector2.new(img.width, img.height), img.pixels)
	return e, string.format("%s %dx%d", mime, img.width, img.height)
end

-- Lists what a GLB holds without building anything.
function GlbImport.describe(glb: Glb): { [string]: any }
	local j = glb.json
	local out = { meshes = {}, images = {}, materials = {} }
	for _, m in j.meshes or {} do
		for _, p in m.primitives do
			local count = 0
			if p.indices then
				count = j.accessors[p.indices + 1].count // 3
			end
			table.insert(out.meshes, string.format("%s tris=%d verts=%d mat=%s", m.name or "?", count, j.accessors[p.attributes.POSITION + 1].count, tostring(p.material)))
		end
	end
	for _, im in j.images or {} do
		table.insert(out.images, (im.mimeType or "?") .. " " .. tostring(j.bufferViews[im.bufferView + 1].byteLength))
	end
	for _, m in j.materials or {} do
		local pbr = m.pbrMetallicRoughness or {}
		table.insert(out.materials, string.format("%s base=%s mr=%s normal=%s", m.name or "?", tostring(pbr.baseColorTexture and pbr.baseColorTexture.index), tostring(pbr.metallicRoughnessTexture and pbr.metallicRoughnessTexture.index), tostring(m.normalTexture and m.normalTexture.index)))
	end
	return out
end

-- Builds one MeshPart per primitive inside a Model. opts.width scales the whole model so its
-- longest horizontal extent equals that many studs. Returns the model and a report.
function GlbImport.import(data: buffer, opts: { name: string?, width: number? }?): (Model, { string })
	local o = opts or {}
	local glb = GlbImport.parse(data)
	local j = glb.json
	local report = {}
	local model = Instance.new("Model")
	model.Name = o.name or "Imported"
	-- First pass: bounds, for the scale factor.
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, m in j.meshes do
		for _, p in m.primitives do
			local acc = j.accessors[p.attributes.POSITION + 1]
			if acc.min and acc.max then
				minV = minV:Min(Vector3.new(acc.min[1], acc.min[2], acc.min[3]))
				maxV = maxV:Max(Vector3.new(acc.max[1], acc.max[2], acc.max[3]))
			end
		end
	end
	local extent = maxV - minV
	local scale = if o.width then o.width / math.max(extent.X, extent.Z) else 1
	table.insert(report, string.format("source extent %.3f x %.3f x %.3f, scale %.3f", extent.X, extent.Y, extent.Z, scale))
	-- Centre on X/Z, feet on Y = 0.
	local centre = Vector3.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2)
	for mi, m in j.meshes do
		for pi, p in m.primitives do
			if (p.mode or 4) ~= 4 then
				table.insert(report, "skipped non-triangle primitive")
				continue
			end
			local em = AssetService:CreateEditableMesh({})
			local nPos, pos = accessor(glb, p.attributes.POSITION)
			local nrm = p.attributes.NORMAL and select(2, accessor(glb, p.attributes.NORMAL))
			local uvr = p.attributes.TEXCOORD_0 and select(2, accessor(glb, p.attributes.TEXCOORD_0))
			local vids, nids, uids = table.create(nPos), table.create(nPos), table.create(nPos)
			for i = 0, nPos - 1 do
				local v = (Vector3.new(pos(i, 0), pos(i, 1), pos(i, 2)) - centre) * scale
				vids[i + 1] = em:AddVertex(v)
				if nrm then
					nids[i + 1] = em:AddNormal(Vector3.new(nrm(i, 0), nrm(i, 1), nrm(i, 2)).Unit)
				end
				if uvr then
					-- glTF UV origin is top-left, the same as Roblox.
					uids[i + 1] = em:AddUV(Vector2.new(uvr(i, 0), uvr(i, 1)))
				end
				if i % 4000 == 0 then
					task.wait()
				end
			end
			local nIdx, idx
			if p.indices then
				nIdx, idx = accessor(glb, p.indices)
			else
				nIdx, idx = nPos, function(i: number, _c: number): number return i end
			end
			for t = 0, nIdx // 3 - 1 do
				local a, b, c = idx(t * 3, 0) + 1, idx(t * 3 + 1, 0) + 1, idx(t * 3 + 2, 0) + 1
				local f = em:AddTriangle(vids[a], vids[b], vids[c])
				if nrm then
					em:SetFaceNormals(f, { nids[a], nids[b], nids[c] })
				end
				if uvr then
					em:SetFaceUVs(f, { uids[a], uids[b], uids[c] })
				end
				if t % 4000 == 0 then
					task.wait()
				end
			end
			local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
			part.Name = string.format("%s_%d_%d", m.name or "Mesh", mi, pi)
			part.Anchored = true
			part.Material = Enum.Material.SmoothPlastic
			-- CreateMeshPartAsync recentres the mesh; put it back where the file placed it.
			local pmin, pmax = Vector3.one * math.huge, -Vector3.one * math.huge
			local acc = j.accessors[p.attributes.POSITION + 1]
			if acc.min then
				pmin = (Vector3.new(acc.min[1], acc.min[2], acc.min[3]) - centre) * scale
				pmax = (Vector3.new(acc.max[1], acc.max[2], acc.max[3]) - centre) * scale
				part.Position = (pmin + pmax) / 2
			end
			local mat = p.material and j.materials[p.material + 1]
			local pbr = mat and mat.pbrMetallicRoughness or {}
			local colour, how = editableFromTexture(glb, pbr.baseColorTexture and pbr.baseColorTexture.index)
			if colour then
				part.TextureContent = Content.fromObject(colour)
			elseif pbr.baseColorFactor then
				local f = pbr.baseColorFactor
				part.Color = Color3.new(f[1], f[2], f[3])
			end
			table.insert(report, string.format("%s: %d verts, %d tris, base colour %s", part.Name, nPos, nIdx // 3, how))
			part.Parent = model
		end
	end
	return model, report
end

return GlbImport

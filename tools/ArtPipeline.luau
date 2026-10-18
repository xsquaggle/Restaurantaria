--!strict
-- Turns generated source images into runtime sprites inside the open Studio place.
--
-- Sources are PNGs from Higgsfield (see art/manifest.json). This module only crops, trims,
-- resizes and stores them: it never paints pixels of its own. Run it from the Studio command
-- bar or the Studio MCP in Edit mode, e.g.
--   local P = require(game.ServerStorage.ArtPipeline)
--   P.run(P.manifest)  -- manifest = the decoded art/manifest.json
--
-- Output: ReplicatedStorage.DevArt.<name>, a Folder with Width/Height attributes holding
-- ModuleScripts "1", "2", ... whose concatenated return values are Base64(Zstd(RGBA8)).
-- The client shows these through EditableImage in Studio only (src/shared/Art.luau); the
-- uploader plugin turns the same data into image assets.

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Png = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Png") :: ModuleScript)

type Image = { width: number, height: number, pixels: buffer }
type Box = { x: number, y: number, w: number, h: number }

local Pipeline = {}

local CHUNK = 199000 -- Script.Source is capped at 200,000 characters
local cache: { [string]: Image } = {}

function Pipeline.load(url: string): Image
	if cache[url] then
		return cache[url]
	end
	local was = HttpService.HttpEnabled
	HttpService.HttpEnabled = true
	local ok, body = pcall(function()
		return HttpService:GetAsync(url)
	end)
	HttpService.HttpEnabled = was
	if not ok then
		error("fetch failed: " .. tostring(body))
	end
	local decoded = Png.decode(body)
	local image = { width = decoded.width, height = decoded.height, pixels = decoded.pixels }
	cache[url] = image
	return image
end

function Pipeline.forget()
	table.clear(cache)
end

function Pipeline.crop(src: Image, box: Box): Image
	local out = buffer.create(box.w * box.h * 4)
	for y = 0, box.h - 1 do
		buffer.copy(out, y * box.w * 4, src.pixels, ((box.y + y) * src.width + box.x) * 4, box.w * 4)
	end
	return { width = box.w, height = box.h, pixels = out }
end

-- Smallest box holding every pixel whose alpha exceeds the threshold.
function Pipeline.trimBox(src: Image, threshold: number?): Box
	local t = threshold or 8
	local W, H, px = src.width, src.height, src.pixels
	local x0, y0, x1, y1 = W, H, -1, -1
	for y = 0, H - 1 do
		local row = y * W * 4
		for x = 0, W - 1 do
			if buffer.readu8(px, row + x * 4 + 3) > t then
				if x < x0 then x0 = x end
				if x > x1 then x1 = x end
				if y < y0 then y0 = y end
				y1 = y
			end
		end
		if y % 256 == 0 then
			task.wait()
		end
	end
	if x1 < 0 then
		return { x = 0, y = 0, w = W, h = H }
	end
	return { x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }
end

-- Separate sprites on a transparent sheet: flood fill over a coarse alpha grid, then trim each.
function Pipeline.components(src: Image, cell: number?, minCells: number?): { Box }
	local c = cell or 8
	local gw, gh = math.ceil(src.width / c), math.ceil(src.height / c)
	local grid = buffer.create(gw * gh)
	local px, W = src.pixels, src.width
	for y = 0, src.height - 1, 2 do
		local row = y * W * 4
		for x = 0, W - 1, 2 do
			if buffer.readu8(px, row + x * 4 + 3) > 24 then
				buffer.writeu8(grid, (y // c) * gw + x // c, 1)
			end
		end
		if y % 256 == 0 then
			task.wait()
		end
	end
	local boxes: { Box } = {}
	local stack = {}
	for start = 0, gw * gh - 1 do
		if buffer.readu8(grid, start) == 1 then
			buffer.writeu8(grid, start, 2)
			table.clear(stack)
			table.insert(stack, start)
			local gx0, gy0, gx1, gy1, n = gw, gh, -1, -1, 0
			while #stack > 0 do
				local i = table.remove(stack) :: number
				local gx, gy = i % gw, i // gw
				n += 1
				gx0, gy0, gx1, gy1 = math.min(gx0, gx), math.min(gy0, gy), math.max(gx1, gx), math.max(gy1, gy)
				for dy = -1, 1 do
					for dx = -1, 1 do
						local nx, ny = gx + dx, gy + dy
						if nx >= 0 and ny >= 0 and nx < gw and ny < gh then
							local j = ny * gw + nx
							if buffer.readu8(grid, j) == 1 then
								buffer.writeu8(grid, j, 2)
								table.insert(stack, j)
							end
						end
					end
				end
			end
			if n >= (minCells or 12) then
				local x = math.max(0, (gx0 - 1) * c)
				local y = math.max(0, (gy0 - 1) * c)
				local box = { x = x, y = y, w = math.min(src.width, (gx1 + 2) * c) - x, h = math.min(src.height, (gy1 + 2) * c) - y }
				local piece = Pipeline.crop(src, box)
				local t = Pipeline.trimBox(piece)
				table.insert(boxes, { x = box.x + t.x, y = box.y + t.y, w = t.w, h = t.h })
			end
		end
	end
	return boxes
end

-- Order boxes in reading order: rows by centre height (within half a box), then left to right.
function Pipeline.readingOrder(boxes: { Box }): { Box }
	local sorted = table.clone(boxes)
	table.sort(sorted, function(a, b)
		local ay, by = a.y + a.h / 2, b.y + b.h / 2
		if math.abs(ay - by) > math.min(a.h, b.h) / 2 then
			return ay < by
		end
		return a.x < b.x
	end)
	return sorted
end

-- Area-average resize with alpha weighting, separable (horizontal then vertical).
function Pipeline.resize(src: Image, w: number, h: number): Image
	local function pass(s: Image, ow: number, oh: number, horizontal: boolean): Image
		local out = buffer.create(ow * oh * 4)
		local sw, sh, sp = s.width, s.height, s.pixels
		local srcLen = if horizontal then sw else sh
		local dstLen = if horizontal then ow else oh
		local lines = if horizontal then oh else ow
		local scale = srcLen / dstLen
		for line = 0, lines - 1 do
			for d = 0, dstLen - 1 do
				local a0, a1 = d * scale, (d + 1) * scale
				local r, g, b, a, wsum = 0, 0, 0, 0, 0
				local i = math.floor(a0)
				while i < a1 and i < srcLen do
					local wgt = math.min(i + 1, a1) - math.max(i, a0)
					local o = if horizontal then (line * sw + i) * 4 else (i * sw + line) * 4
					local al = buffer.readu8(sp, o + 3) * wgt
					r += buffer.readu8(sp, o) * al
					g += buffer.readu8(sp, o + 1) * al
					b += buffer.readu8(sp, o + 2) * al
					a += al
					wsum += wgt
					i += 1
				end
				local o = if horizontal then (line * ow + d) * 4 else (d * ow + line) * 4
				if a > 0 then
					buffer.writeu8(out, o, math.clamp(math.round(r / a), 0, 255))
					buffer.writeu8(out, o + 1, math.clamp(math.round(g / a), 0, 255))
					buffer.writeu8(out, o + 2, math.clamp(math.round(b / a), 0, 255))
				end
				buffer.writeu8(out, o + 3, math.clamp(math.round(a / wsum), 0, 255))
			end
			if line % 64 == 0 then
				task.wait()
			end
		end
		return { width = ow, height = oh, pixels = out }
	end
	local mid = pass(src, w, src.height, true)
	return pass(mid, w, h, false)
end

-- Copy colour into fully transparent pixels next to visible ones so filtering at sprite edges
-- does not pull in black. Alpha is unchanged, so nothing new becomes visible.
function Pipeline.bleed(src: Image, passes: number?)
	local W, H, px = src.width, src.height, src.pixels
	for o = 0, W * H * 4 - 4, 4 do
		if buffer.readu8(px, o + 3) == 0 then
			buffer.writeu32(px, o, 0)
		end
	end
	for _ = 1, passes or 3 do
		local fill = {}
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local o = (y * W + x) * 4
				if buffer.readu8(px, o + 3) == 0 and buffer.readu8(px, o) == 0 and buffer.readu8(px, o + 1) == 0 and buffer.readu8(px, o + 2) == 0 then
					local r, g, b, n = 0, 0, 0, 0
					for dy = -1, 1 do
						for dx = -1, 1 do
							local nx, ny = x + dx, y + dy
							if nx >= 0 and ny >= 0 and nx < W and ny < H then
								local q = (ny * W + nx) * 4
								local nr, ng, nb = buffer.readu8(px, q), buffer.readu8(px, q + 1), buffer.readu8(px, q + 2)
								if buffer.readu8(px, q + 3) > 0 or nr + ng + nb > 0 then
									r += nr
									g += ng
									b += nb
									n += 1
								end
							end
						end
					end
					if n > 0 then
						table.insert(fill, { o, r // n, g // n, b // n })
					end
				end
			end
			if y % 128 == 0 then
				task.wait()
			end
		end
		for _, f in fill do
			buffer.writeu8(px, f[1], math.max(f[2], 1))
			buffer.writeu8(px, f[1] + 1, f[3])
			buffer.writeu8(px, f[1] + 2, f[4])
		end
	end
end

-- Place a trimmed sprite centred on a transparent square canvas, scaled to fit inside the padding.
function Pipeline.fitSquare(src: Image, side: number, pad: number): Image
	local inner = side - pad * 2
	local k = inner / math.max(src.width, src.height)
	local w, h = math.max(1, math.round(src.width * k)), math.max(1, math.round(src.height * k))
	local scaled = Pipeline.resize(src, w, h)
	local out = buffer.create(side * side * 4)
	local ox, oy = (side - w) // 2, (side - h) // 2
	for y = 0, h - 1 do
		buffer.copy(out, ((oy + y) * side + ox) * 4, scaled.pixels, y * w * 4, w * 4)
	end
	return { width = side, height = side, pixels = out }
end

function Pipeline.store(name: string, image: Image, meta: { [string]: any }?)
	local root = ReplicatedStorage:FindFirstChild("DevArt")
	if not root then
		root = Instance.new("Folder")
		root.Name = "DevArt"
		root.Parent = ReplicatedStorage
	end
	local old = (root :: Instance):FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local packed = EncodingService:CompressBuffer(image.pixels, Enum.CompressionAlgorithm.Zstd, 9)
	local text = buffer.tostring(EncodingService:Base64Encode(packed))
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("Width", image.width)
	folder:SetAttribute("Height", image.height)
	for k, v in meta or {} do
		folder:SetAttribute(k, v)
	end
	local part = 0
	for i = 1, #text, CHUNK do
		part += 1
		local m = Instance.new("ModuleScript")
		m.Name = tostring(part)
		m.Source = 'return "' .. text:sub(i, i + CHUNK - 1) .. '"'
		m.Parent = folder
	end
	folder:SetAttribute("Parts", part)
	folder.Parent = root
	return #text
end

-- Show stored or in-memory images in the Edit viewport for review (removed by Pipeline.hide).
function Pipeline.preview(images: { Image }, background: Color3?)
	Pipeline.hide()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArtPreview"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BorderSizePixel = 0
	back.BackgroundColor3 = background or Color3.fromRGB(70, 70, 80)
	back.Parent = gui
	local editables = {}
	for k, img in images do
		local e = AssetService:CreateEditableImage({ Size = Vector2.new(img.width, img.height) })
		e:WritePixelsBuffer(Vector2.zero, Vector2.new(img.width, img.height), img.pixels)
		table.insert(editables, e)
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.ScaleType = Enum.ScaleType.Fit
		label.Size = UDim2.fromScale(1 / #images, 1)
		label.Position = UDim2.fromScale((k - 1) / #images, 0)
		label.ImageContent = Content.fromObject(e)
		label.Parent = back
	end
	gui.Parent = game:GetService("StarterGui")
	Pipeline._previewEditables = editables
end

function Pipeline.hide()
	local old = game:GetService("StarterGui"):FindFirstChild("ArtPreview")
	if old then
		old:Destroy()
	end
	for _, e in (Pipeline :: any)._previewEditables or {} do
		e:Destroy()
	end
	Pipeline._previewEditables = nil
end

-- Process every output in a manifest (see art/manifest.json for the schema).
function Pipeline.run(manifest: any, only: { [string]: boolean }?): { string }
	local log = {}
	for _, source in manifest.sources do
		local wanted = false
		for _, out in source.outputs do
			if not only or only[out.name] or (out.names and only[out.names[1]]) then
				wanted = true
			end
		end
		if wanted then
			local src = Pipeline.load(source.url)
			if source.kind == "sheet" then
				local boxes = Pipeline.readingOrder(Pipeline.components(src))
				local names = source.outputs[1].names
				if #boxes ~= #names then
					table.insert(log, string.format("%s: expected %d sprites, found %d", source.id, #names, #boxes))
				else
					for i, box in boxes do
						local o = source.outputs[1]
						local img = Pipeline.fitSquare(Pipeline.crop(src, box), o.side, o.pad or 0)
						Pipeline.bleed(img)
						Pipeline.store(names[i], img)
						table.insert(log, string.format("%s <- %s box %d,%d %dx%d", names[i], source.id, box.x, box.y, box.w, box.h))
						task.wait()
					end
				end
			elseif source.kind == "sprite" then
				local o = source.outputs[1]
				local box = Pipeline.trimBox(src)
				local img = Pipeline.fitSquare(Pipeline.crop(src, box), o.side, o.pad or 0)
				Pipeline.bleed(img)
				Pipeline.store(o.name, img)
				table.insert(log, string.format("%s <- %s trimmed %dx%d", o.name, source.id, box.w, box.h))
			elseif source.kind == "tiles" then
				-- Crop to the target aspect (centred), then cut a cols x rows grid of tiles.
				local o = source.outputs[1]
				local aspect = o.width / o.height
				local cw, ch = src.width, src.height
				if cw / ch > aspect then
					cw = math.floor(ch * aspect)
				else
					ch = math.floor(cw / aspect)
				end
				local x0, y0 = (src.width - cw) // 2, (src.height - ch) // 2
				local tw, th = o.width // o.cols, o.height // o.rows
				for r = 0, o.rows - 1 do
					for c = 0, o.cols - 1 do
						local sx0, sx1 = x0 + math.floor(c * cw / o.cols), x0 + math.floor((c + 1) * cw / o.cols)
						local sy0, sy1 = y0 + math.floor(r * ch / o.rows), y0 + math.floor((r + 1) * ch / o.rows)
						local tile = Pipeline.resize(Pipeline.crop(src, { x = sx0, y = sy0, w = sx1 - sx0, h = sy1 - sy0 }), tw, th)
						local name = string.format("%s_%d", o.name, r * o.cols + c + 1)
						Pipeline.store(name, tile, { Col = c, Row = r, Cols = o.cols, Rows = o.rows })
						table.insert(log, name .. " <- " .. source.id)
						task.wait()
					end
				end
			end
		end
	end
	return log
end

return Pipeline

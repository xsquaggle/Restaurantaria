--!strict
-- Minimal PNG decoder: non-interlaced images (grey, RGB, palette, with or without alpha, 1-16
-- bit) to an RGBA8 buffer. Studio tooling only (art preview before upload, the upload plugin);
-- the game itself shows uploaded asset ids and never decodes images.

local Png = {}

export type Image = { width: number, height: number, pixels: buffer }

local band, bor, lshift, rshift = bit32.band, bit32.bor, bit32.lshift, bit32.rshift
local readu8, writeu8 = buffer.readu8, buffer.writeu8

------------------------------------------------------------------------------------------
-- Inflate (RFC 1950 zlib wrapper around RFC 1951 deflate), canonical Huffman decoding as in
-- zlib's puff.c.

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

type Huffman = { count: { [number]: number }, symbol: { [number]: number } }

-- lengths is 0-indexed by symbol.
local function huffman(lengths: { [number]: number }, n: number): Huffman
	local count: { [number]: number } = {}
	for len = 0, 15 do
		count[len] = 0
	end
	for sym = 0, n - 1 do
		local len = lengths[sym]
		count[len] += 1
	end
	local offs: { [number]: number } = { [1] = 0 }
	for len = 1, 14 do
		offs[len + 1] = offs[len] + count[len]
	end
	local symbol: { [number]: number } = {}
	for sym = 0, n - 1 do
		local len = lengths[sym]
		if len ~= 0 then
			symbol[offs[len]] = sym
			offs[len] += 1
		end
	end
	return { count = count, symbol = symbol }
end

local FIXED_LIT: Huffman, FIXED_DIST: Huffman
do
	local lengths: { [number]: number } = {}
	for sym = 0, 287 do
		lengths[sym] = if sym < 144 then 8 elseif sym < 256 then 9 elseif sym < 280 then 7 else 8
	end
	FIXED_LIT = huffman(lengths, 288)
	local dist: { [number]: number } = {}
	for sym = 0, 29 do
		dist[sym] = 5
	end
	FIXED_DIST = huffman(dist, 30)
end

-- Inflates zlib data from src starting at byte `start`, into a buffer of exactly `expected` bytes.
function Png.inflate(src: buffer, start: number, expected: number): buffer
	local srcLen = buffer.len(src)
	local cmf, flg = readu8(src, start), readu8(src, start + 1)
	if band(cmf, 15) ~= 8 or (cmf * 256 + flg) % 31 ~= 0 then
		error("not zlib/deflate data")
	end
	if band(flg, 32) ~= 0 then
		error("preset dictionaries are not supported")
	end
	local pos = start + 2
	local bitbuf, bitcnt = 0, 0
	local out = buffer.create(expected)
	local outPos = 0

	local function bits(need: number): number
		local val = bitbuf
		while bitcnt < need do
			if pos >= srcLen then
				error("compressed data ended early")
			end
			val = bor(val, lshift(readu8(src, pos), bitcnt))
			pos += 1
			bitcnt += 8
		end
		bitbuf = rshift(val, need)
		bitcnt -= need
		return band(val, lshift(1, need) - 1)
	end

	local function decode(h: Huffman): number
		local count, symbol = h.count, h.symbol
		local code, first, index = 0, 0, 0
		for len = 1, 15 do
			if bitcnt == 0 then
				if pos >= srcLen then
					error("compressed data ended early")
				end
				bitbuf = readu8(src, pos)
				pos += 1
				bitcnt = 8
			end
			code = bor(code, band(bitbuf, 1))
			bitbuf = rshift(bitbuf, 1)
			bitcnt -= 1
			local c = count[len]
			if code - c < first then
				return symbol[index + (code - first)]
			end
			index += c
			first = (first + c) * 2
			code *= 2
		end
		error("invalid Huffman code")
	end

	local function codes(lit: Huffman, dist: Huffman)
		while true do
			local sym = decode(lit)
			if sym < 256 then
				if outPos >= expected then
					error("inflated data is larger than expected")
				end
				writeu8(out, outPos, sym)
				outPos += 1
			elseif sym == 256 then
				return
			else
				sym -= 257
				if sym >= 29 then
					error("invalid length code")
				end
				local len = LEN_BASE[sym + 1] + bits(LEN_EXTRA[sym + 1])
				local d = decode(dist)
				if d >= 30 then
					error("invalid distance code")
				end
				local distance = DIST_BASE[d + 1] + bits(DIST_EXTRA[d + 1])
				if distance > outPos then
					error("distance too far back")
				end
				if outPos + len > expected then
					error("inflated data is larger than expected")
				end
				if distance >= len then
					buffer.copy(out, outPos, out, outPos - distance, len)
					outPos += len
				else
					-- Overlapping copy repeats the last `distance` bytes.
					for _ = 1, len do
						writeu8(out, outPos, readu8(out, outPos - distance))
						outPos += 1
					end
				end
			end
		end
	end

	repeat
		local last = bits(1)
		local kind = bits(2)
		if kind == 0 then
			bitbuf, bitcnt = 0, 0
			if pos + 4 > srcLen then
				error("compressed data ended early")
			end
			local len = readu8(src, pos) + readu8(src, pos + 1) * 256
			pos += 4
			if pos + len > srcLen or outPos + len > expected then
				error("stored block out of range")
			end
			buffer.copy(out, outPos, src, pos, len)
			pos += len
			outPos += len
		elseif kind == 1 then
			codes(FIXED_LIT, FIXED_DIST)
		elseif kind == 2 then
			local nlen = bits(5) + 257
			local ndist = bits(5) + 1
			local ncode = bits(4) + 4
			local lengths: { [number]: number } = {}
			for i = 0, 18 do
				lengths[i] = 0
			end
			for i = 1, ncode do
				lengths[CODE_LENGTH_ORDER[i]] = bits(3)
			end
			local lencode = huffman(lengths, 19)
			local all: { [number]: number } = {}
			local index = 0
			while index < nlen + ndist do
				local sym = decode(lencode)
				if sym < 16 then
					all[index] = sym
					index += 1
				else
					local value, rep = 0, 0
					if sym == 16 then
						if index == 0 then
							error("repeat with no previous length")
						end
						value = all[index - 1]
						rep = 3 + bits(2)
					elseif sym == 17 then
						rep = 3 + bits(3)
					else
						rep = 11 + bits(7)
					end
					if index + rep > nlen + ndist then
						error("too many code lengths")
					end
					for _ = 1, rep do
						all[index] = value
						index += 1
					end
				end
			end
			local litLengths: { [number]: number } = {}
			for i = 0, nlen - 1 do
				litLengths[i] = all[i]
			end
			local distLengths: { [number]: number } = {}
			for i = 0, ndist - 1 do
				distLengths[i] = all[nlen + i]
			end
			codes(huffman(litLengths, nlen), huffman(distLengths, ndist))
		else
			error("invalid block type")
		end
	until last == 1
	if outPos ~= expected then
		error(string.format("inflated %d bytes, expected %d", outPos, expected))
	end
	return out
end

------------------------------------------------------------------------------------------
-- PNG

local SIGNATURE = "\137PNG\r\n\26\n"
local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }

local function u32(b: buffer, at: number): number
	return readu8(b, at) * 16777216 + readu8(b, at + 1) * 65536 + readu8(b, at + 2) * 256 + readu8(b, at + 3)
end

local function paeth(a: number, b: number, c: number): number
	local p = a + b - c
	local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
	if pa <= pb and pa <= pc then
		return a
	elseif pb <= pc then
		return b
	end
	return c
end

function Png.decode(data: string | buffer): Image
	local src: buffer = if type(data) == "string" then buffer.fromstring(data) else data :: buffer
	local n = buffer.len(src)
	if n < 8 or buffer.readstring(src, 0, 8) ~= SIGNATURE then
		error("not a PNG file")
	end
	local width, height, depth, colour = 0, 0, 0, 0
	local palette: buffer? = nil
	local alpha: buffer? = nil
	local idat: { string } = {}
	local at = 8
	while at + 8 <= n do
		local len = u32(src, at)
		local kind = buffer.readstring(src, at + 4, 4)
		local body = at + 8
		if body + len > n then
			error("truncated chunk " .. kind)
		end
		if kind == "IHDR" then
			width, height = u32(src, body), u32(src, body + 4)
			depth, colour = readu8(src, body + 8), readu8(src, body + 9)
			if readu8(src, body + 12) ~= 0 then
				error("interlaced PNGs are not supported")
			end
			if not CHANNELS[colour] then
				error("unsupported colour type " .. colour)
			end
		elseif kind == "PLTE" then
			palette = buffer.create(len)
			buffer.copy(palette :: buffer, 0, src, body, len)
		elseif kind == "tRNS" then
			alpha = buffer.create(len)
			buffer.copy(alpha :: buffer, 0, src, body, len)
		elseif kind == "IDAT" then
			table.insert(idat, buffer.readstring(src, body, len))
		elseif kind == "IEND" then
			break
		end
		at = body + len + 4
	end
	if width == 0 or height == 0 then
		error("missing IHDR")
	end

	local channels = CHANNELS[colour]
	local bitsPerPixel = channels * depth
	local stride = math.ceil(width * bitsPerPixel / 8)
	local bpp = math.max(1, bitsPerPixel // 8)
	local raw = Png.inflate(buffer.fromstring(table.concat(idat)), 0, height * (stride + 1))

	-- Undo the per-row filters in place.
	for y = 0, height - 1 do
		local row = y * (stride + 1)
		local filter = readu8(raw, row)
		local cur = row + 1
		local prev = cur - (stride + 1)
		if filter == 1 then
			for x = bpp, stride - 1 do
				writeu8(raw, cur + x, (readu8(raw, cur + x) + readu8(raw, cur + x - bpp)) % 256)
			end
		elseif filter == 2 and y > 0 then
			for x = 0, stride - 1 do
				writeu8(raw, cur + x, (readu8(raw, cur + x) + readu8(raw, prev + x)) % 256)
			end
		elseif filter == 3 then
			for x = 0, stride - 1 do
				local a = if x >= bpp then readu8(raw, cur + x - bpp) else 0
				local b = if y > 0 then readu8(raw, prev + x) else 0
				writeu8(raw, cur + x, (readu8(raw, cur + x) + (a + b) // 2) % 256)
			end
		elseif filter == 4 then
			for x = 0, stride - 1 do
				local a = if x >= bpp then readu8(raw, cur + x - bpp) else 0
				local b = if y > 0 then readu8(raw, prev + x) else 0
				local c = if x >= bpp and y > 0 then readu8(raw, prev + x - bpp) else 0
				writeu8(raw, cur + x, (readu8(raw, cur + x) + paeth(a, b, c)) % 256)
			end
		elseif filter > 4 then
			error("invalid filter type " .. filter)
		end
	end

	local pixels = buffer.create(width * height * 4)
	if colour == 6 and depth == 8 then
		for y = 0, height - 1 do
			buffer.copy(pixels, y * width * 4, raw, y * (stride + 1) + 1, width * 4)
		end
		return { width = width, height = height, pixels = pixels }
	end

	local maxValue = lshift(1, depth) - 1
	local step = if depth == 16 then 2 else 1
	local function sample(row: number, index: number): number
		-- index counts samples along the row; returns an 8-bit value.
		if depth >= 8 then
			return readu8(raw, row + index * step)
		end
		local bitPos = index * depth
		local byte = readu8(raw, row + bitPos // 8)
		local value = band(rshift(byte, 8 - depth - bitPos % 8), maxValue)
		return if colour == 3 then value else value * 255 // maxValue
	end
	for y = 0, height - 1 do
		local row = y * (stride + 1) + 1
		for x = 0, width - 1 do
			local o = (y * width + x) * 4
			local r, g, b, a = 0, 0, 0, 255
			if colour == 0 then
				r = sample(row, x)
				g, b = r, r
			elseif colour == 2 then
				r, g, b = sample(row, x * 3), sample(row, x * 3 + 1), sample(row, x * 3 + 2)
			elseif colour == 3 then
				local i = sample(row, x)
				local p = palette :: buffer
				r, g, b = readu8(p, i * 3), readu8(p, i * 3 + 1), readu8(p, i * 3 + 2)
				if alpha and i < buffer.len(alpha) then
					a = readu8(alpha, i)
				end
			elseif colour == 4 then
				r = sample(row, x * 2)
				g, b = r, r
				a = sample(row, x * 2 + 1)
			else
				r, g, b, a = sample(row, x * 4), sample(row, x * 4 + 1), sample(row, x * 4 + 2), sample(row, x * 4 + 3)
			end
			writeu8(pixels, o, r)
			writeu8(pixels, o + 1, g)
			writeu8(pixels, o + 2, b)
			writeu8(pixels, o + 3, a)
		end
	end
	return { width = width, height = height, pixels = pixels }
end

return Png

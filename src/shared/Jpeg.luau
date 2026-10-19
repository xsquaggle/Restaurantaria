--!strict
-- Minimal baseline JPEG decoder for Studio tooling (generated 3D models carry JPEG texture
-- maps). Decodes at a quarter of the stored size: each 8x8 block becomes 2x2 pixels, the mean
-- of its four 4x4 quadrants, so a 4096 px map arrives at 1024 px, the EditableImage limit,
-- without a full inverse DCT. Baseline Huffman only (SOF0/SOF1), any chroma subsampling,
-- restart intervals supported; progressive files are rejected.

local Jpeg = {}

export type Image = { width: number, height: number, pixels: buffer }

local ZIGZAG = {
	0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
	28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61,
	54, 47, 55, 62, 63,
}

-- Q[q*8+u]: mean over the 4 samples of half q of the 1-D IDCT basis u, so a quadrant's mean is
-- sum_u sum_v Q[qy][v] Q[qx][u] F[v][u].
local Q = table.create(16, 0)
for q = 0, 1 do
	for u = 0, 7 do
		local cu = if u == 0 then 1 / math.sqrt(2) else 1
		local s = 0
		for x = q * 4, q * 4 + 3 do
			s += cu / 2 * math.cos((2 * x + 1) * u * math.pi / 16)
		end
		Q[q * 8 + u + 1] = s / 4
	end
end

type Huff = { lookup: { [number]: number }, maxLen: number }

local function buildHuff(counts: { number }, symbols: { number }): Huff
	-- Map (length << 16 | code) to symbol.
	local lookup = {}
	local code, k = 0, 1
	local maxLen = 0
	for len = 1, 16 do
		for _ = 1, counts[len] do
			lookup[bit32.bor(bit32.lshift(len, 16), code)] = symbols[k]
			k += 1
			code += 1
			maxLen = len
		end
		code = bit32.lshift(code, 1)
	end
	return { lookup = lookup, maxLen = maxLen }
end

function Jpeg.decode(data: string | buffer): Image
	local b: buffer = if type(data) == "string" then buffer.fromstring(data) else data
	local n = buffer.len(b)
	local function u8(i: number): number
		return buffer.readu8(b, i)
	end
	local function u16(i: number): number
		return u8(i) * 256 + u8(i + 1)
	end
	assert(u16(0) == 0xFFD8, "not a JPEG")
	local qt: { [number]: { number } } = {}
	local dcT: { [number]: Huff } = {}
	local acT: { [number]: Huff } = {}
	local comps: { any } = {}
	local width, height = 0, 0
	local restart = 0
	local p = 2
	local scanStart = 0
	while p < n do
		assert(u8(p) == 0xFF, "bad marker")
		local m = u8(p + 1)
		local len = u16(p + 2)
		local s = p + 4
		if m == 0xDB then
			local q = s
			while q < p + 2 + len do
				local pq, tq = bit32.rshift(u8(q), 4), bit32.band(u8(q), 15)
				local t = table.create(64, 0)
				for i = 1, 64 do
					t[ZIGZAG[i] + 1] = if pq == 0 then u8(q + i) else u16(q + 1 + (i - 1) * 2)
				end
				qt[tq] = t
				q += 1 + (if pq == 0 then 64 else 128)
			end
		elseif m == 0xC4 then
			local q = s
			while q < p + 2 + len do
				local tc, th = bit32.rshift(u8(q), 4), bit32.band(u8(q), 15)
				local counts, total = {}, 0
				for i = 1, 16 do
					counts[i] = u8(q + i)
					total += counts[i]
				end
				local symbols = {}
				for i = 1, total do
					symbols[i] = u8(q + 16 + i)
				end
				local h = buildHuff(counts, symbols)
				if tc == 0 then
					dcT[th] = h
				else
					acT[th] = h
				end
				q += 17 + total
			end
		elseif m == 0xC0 or m == 0xC1 then
			height, width = u16(s + 1), u16(s + 3)
			for c = 0, u8(s + 5) - 1 do
				local o = s + 6 + c * 3
				table.insert(comps, { id = u8(o), h = bit32.rshift(u8(o + 1), 4), v = bit32.band(u8(o + 1), 15), tq = u8(o + 2) })
			end
		elseif m == 0xC2 then
			error("progressive JPEG not supported")
		elseif m == 0xDD then
			restart = u16(s)
		elseif m == 0xDA then
			local ns = u8(s)
			for i = 0, ns - 1 do
				local id, t = u8(s + 1 + i * 2), u8(s + 2 + i * 2)
				for _, c in comps do
					if c.id == id then
						c.dc, c.ac = bit32.rshift(t, 4), bit32.band(t, 15)
					end
				end
			end
			scanStart = p + 2 + len
			break
		end
		p += 2 + len
	end
	local hmax, vmax = 1, 1
	for _, c in comps do
		hmax, vmax = math.max(hmax, c.h), math.max(vmax, c.v)
	end
	local mcuW, mcuH = 8 * hmax, 8 * vmax
	local mcusX, mcusY = math.ceil(width / mcuW), math.ceil(height / mcuH)
	-- Each component plane at quarter scale: 2 samples per block side.
	for _, c in comps do
		c.pw = mcusX * c.h * 2
		c.ph = mcusY * c.v * 2
		c.plane = buffer.create(c.pw * c.ph * 4)
		c.pred = 0
		c.q = qt[c.tq]
	end

	-- Bit reader with byte unstuffing.
	local pos = scanStart
	local bitBuf, bitCnt = 0, 0
	local function fill()
		while bitCnt <= 24 do
			local byte = 0
			if pos < n then
				byte = u8(pos)
				if byte == 0xFF then
					local nxt = u8(pos + 1)
					if nxt == 0 then
						pos += 2
					elseif nxt >= 0xD0 and nxt <= 0xD7 then
						byte = 0 -- marker: feed zeros until reset
					else
						byte = 0
					end
				else
					pos += 1
				end
			end
			bitBuf = bit32.bor(bit32.lshift(bitBuf, 8), byte)
			bitCnt += 8
		end
	end
	local function bits(k: number): number
		if k == 0 then
			return 0
		end
		if bitCnt < k then
			fill()
		end
		bitCnt -= k
		return bit32.band(bit32.rshift(bitBuf, bitCnt), bit32.lshift(1, k) - 1)
	end
	local function decodeHuff(h: Huff): number
		local code = 0
		for len = 1, h.maxLen do
			code = bit32.bor(bit32.lshift(code, 1), bits(1))
			local sym = h.lookup[bit32.bor(bit32.lshift(len, 16), code)]
			if sym ~= nil then
				return sym
			end
		end
		error("bad Huffman code")
	end
	local function extend(v: number, t: number): number
		if t == 0 then
			return 0
		end
		if v < bit32.lshift(1, t - 1) then
			return v - bit32.lshift(1, t) + 1
		end
		return v
	end
	local function resetBits()
		bitBuf, bitCnt = 0, 0
		-- Skip to just after the RSTn marker.
		while pos < n - 1 and not (u8(pos) == 0xFF and u8(pos + 1) >= 0xD0 and u8(pos + 1) <= 0xD7) do
			pos += 1
		end
		pos += 2
		for _, c in comps do
			c.pred = 0
		end
	end

	local F = table.create(64, 0)
	local function block(c: any, bx: number, by: number)
		table.clear(F)
		for i = 1, 64 do
			F[i] = 0
		end
		local t = decodeHuff(dcT[c.dc])
		c.pred += extend(bits(t), t)
		local q = c.q
		F[1] = c.pred * q[1]
		local k = 2
		local ac = acT[c.ac]
		while k <= 64 do
			local rs = decodeHuff(ac)
			local r, sz = bit32.rshift(rs, 4), bit32.band(rs, 15)
			if sz == 0 then
				if r == 15 then
					k += 16
				else
					break
				end
			else
				k += r
				local z = ZIGZAG[k] + 1
				F[z] = extend(bits(sz), sz) * q[z]
				k += 1
			end
		end
		-- 2x2 quadrant means.
		for qy = 0, 1 do
			for qx = 0, 1 do
				local sum = 0
				for v = 0, 7 do
					local wy = Q[qy * 8 + v + 1]
					if wy ~= 0 then
						local row = v * 8
						local rs2 = 0
						for u = 0, 7 do
							local f = F[row + u + 1]
							if f ~= 0 then
								rs2 += Q[qx * 8 + u + 1] * f
							end
						end
						sum += wy * rs2
					end
				end
				buffer.writef32(c.plane, ((by * 2 + qy) * c.pw + bx * 2 + qx) * 4, sum + 128)
			end
		end
	end

	local mcuCount = 0
	for my = 0, mcusY - 1 do
		for mx = 0, mcusX - 1 do
			if restart > 0 and mcuCount > 0 and mcuCount % restart == 0 then
				resetBits()
			end
			for _, c in comps do
				for v = 0, c.v - 1 do
					for h = 0, c.h - 1 do
						block(c, mx * c.h + h, my * c.v + v)
					end
				end
			end
			mcuCount += 1
		end
		if my % 8 == 0 then
			task.wait()
		end
	end

	-- Colour conversion at quarter size.
	local ow, oh = math.ceil(width / 4), math.ceil(height / 4)
	local out = buffer.create(ow * oh * 4)
	local function sample(c: any, x: number, y: number): number
		local sx = x * c.h // hmax
		local sy = y * c.v // vmax
		return buffer.readf32(c.plane, (sy * c.pw + sx) * 4)
	end
	local function clamp(v: number): number
		return if v < 0 then 0 elseif v > 255 then 255 else math.floor(v + 0.5)
	end
	for y = 0, oh - 1 do
		for x = 0, ow - 1 do
			local o = (y * ow + x) * 4
			if #comps >= 3 then
				local Y = sample(comps[1], x, y)
				local cb = sample(comps[2], x, y) - 128
				local cr = sample(comps[3], x, y) - 128
				buffer.writeu8(out, o, clamp(Y + 1.402 * cr))
				buffer.writeu8(out, o + 1, clamp(Y - 0.344136 * cb - 0.714136 * cr))
				buffer.writeu8(out, o + 2, clamp(Y + 1.772 * cb))
			else
				local g = clamp(sample(comps[1], x, y))
				buffer.writeu8(out, o, g)
				buffer.writeu8(out, o + 1, g)
				buffer.writeu8(out, o + 2, g)
			end
			buffer.writeu8(out, o + 3, 255)
		end
		if y % 128 == 0 then
			task.wait()
		end
	end
	return { width = ow, height = oh, pixels = out }
end

return Jpeg

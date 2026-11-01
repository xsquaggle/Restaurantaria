--!strict
-- Draws a SurfaceTiles surface on screen (slice 8a): one GUI element per tile, pooled. A "full"
-- tile is a plain rectangle; a "cut" tile is a rectangle with a hard straight edge drawn by a
-- UIGradient, so the outline is a continuous chain of straight pieces with no scallops, beads or
-- staircase, and nothing relies on CanvasGroup (which falls back to plain frames on low-memory
-- devices, and in Studio's captures).
--
-- Geometry: the view maps dough-local p to screen J p (PrepGeometry.localStretch). Every tile is
-- drawn as the unsheared R(phi) diag(a, b) nearest J (MakeLayers' tileFit), centred on the true
-- screen place of its centre, so neighbouring tiles meet. A UIGradient's 0..1 runs across the
-- element through its centre along its direction: measured in Studio (2026-11-01), its length is
-- min(W / |cos t|, H / |sin t|) for a W x H element and gradient Rotation t, in the element's own
-- (turned) frame, with t growing along (cos t, sin t), y down.
--
-- Looks: `color` gives flat-colour tiles (a declared placeholder until authored material
-- arrives); `image` gives material tiles sampling a map that covers the dough-local square
-- -span..span (ImageRect), so neighbouring tiles show one continuous material. Tints and
-- transparency are set on every tile (no group).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Art = require(Shared.Art)
local SurfaceTiles = require(Shared.SurfaceTiles)

local FoodSurface = {}

local PAD = 0.5 -- px each tile reaches past its square, so rounding never opens a seam
local SOFT = 1.0 -- px over which a cut edge goes from opaque to clear (anti-aliasing)

export type Options = {
	color: Color3?,
	image: string?,
	imagePx: number?, -- the material map's size in px
	span: number?, -- the material map's half width, dough-local
}

export type Surface = {
	place: (Surface, origin: Vector2, screen: (any) -> Vector2, phi: number, a: number, b: number) -> (),
	draw: (Surface, tiles: { SurfaceTiles.Tile }, tint: ((any) -> Color3)?) -> (),
	look: (Surface, color: Color3, transparency: number) -> (),
	clear: (Surface) -> (),
	count: (Surface) -> number,
	folder: Frame,
}

function FoodSurface.new(parent: GuiObject, zIndex: number, name: string, options: Options): Surface
	local folder = Instance.new("Frame")
	folder.Name = name
	folder.BackgroundTransparency = 1
	folder.Size = UDim2.fromScale(1, 1)
	folder.ZIndex = zIndex
	folder.Parent = parent
	local useImage = options.image ~= nil
	local imagePx = options.imagePx or 1024
	local span = options.span or 1
	local pool: { GuiObject } = {}
	local tints: { Color3 } = {}
	local shown = 0
	local origin = Vector2.zero
	local screen: (any) -> Vector2 = function(_)
		return Vector2.zero
	end
	local phi, sa, sb = 0, 1, 1
	local lookColor = options.color or Color3.new(1, 1, 1)
	local lookTransparency = 0

	local function make(): GuiObject
		local el: GuiObject
		if useImage then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			Art.apply(img, options.image :: string)
			el = img
		else
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			el = f
		end
		el.AnchorPoint = Vector2.new(0.5, 0.5)
		el.ZIndex = zIndex
		local g = Instance.new("UIGradient")
		g.Enabled = false
		g.Parent = el
		el.Parent = folder
		return el
	end

	local function paint(el: GuiObject, tint: Color3)
		local c = Color3.new(tint.R * lookColor.R, tint.G * lookColor.G, tint.B * lookColor.B)
		if useImage then
			local img = el :: ImageLabel
			img.ImageColor3 = c
			img.ImageTransparency = lookTransparency
		else
			el.BackgroundColor3 = c
			el.BackgroundTransparency = lookTransparency
		end
	end

	local surface = {} :: Surface
	surface.folder = folder

	function surface.place(_self: Surface, o: Vector2, f: (any) -> Vector2, p: number, a: number, b: number)
		origin, screen, phi, sa, sb = o, f, p, a, b
	end

	function surface.draw(_self: Surface, tiles: { SurfaceTiles.Tile }, tint: ((any) -> Color3)?)
		local n = 0
		for _, t in tiles do
			n += 1
			local el = pool[n]
			if not el then
				el = make()
				pool[n] = el
			end
			local cx, cy = (t.x0 + t.x1) / 2, (t.y0 + t.y1) / 2
			local s = screen({ x = cx, y = cy }) - origin
			local W = sa * (t.x1 - t.x0) + 2 * PAD
			local H = sb * (t.y1 - t.y0) + 2 * PAD
			el.Position = UDim2.fromOffset(s.X, s.Y)
			el.Size = UDim2.fromOffset(W, H)
			el.Rotation = phi
			if useImage then
				local img = el :: ImageLabel
				local scale = imagePx / (2 * span)
				img.ImageRectOffset = Vector2.new((t.x0 + span) * scale, (t.y0 + span) * scale)
				img.ImageRectSize = Vector2.new((t.x1 - t.x0) * scale, (t.y1 - t.y0) * scale)
			end
			local tc = if tint then tint(t.key) else Color3.new(1, 1, 1)
			tints[n] = tc
			local g = el:FindFirstChildOfClass("UIGradient") :: UIGradient
			if t.kind == "cut" then
				-- The edge in the tile's own frame: local u = diag(a, b) (p - c), so the inside
				-- n . (p - c) <= d is m . u <= d with m = (nx / a, ny / b).
				local mx, my = (t.nx :: number) / sa, (t.ny :: number) / sb
				local ml = math.sqrt(mx * mx + my * my)
				local dist = (t.d :: number) / ml
				local th = math.atan2(my, mx)
				local c, sn = math.abs(math.cos(th)), math.abs(math.sin(th))
				local L = math.min(if c > 1e-6 then W / c else math.huge, if sn > 1e-6 then H / sn else math.huge)
				local t0 = 0.5 + dist / L
				local soft = SOFT / L
				local lo, hi = t0 - soft / 2, t0 + soft / 2
				if hi <= 0 then
					el.Visible = false
					g.Enabled = false
					continue
				end
				g.Rotation = math.deg(th)
				if lo >= 1 then
					g.Enabled = false
				else
					lo = math.clamp(lo, 0.0005, 0.998)
					hi = math.clamp(hi, lo + 0.0005, 0.9995)
					g.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(lo, 0),
						NumberSequenceKeypoint.new(hi, 1),
						NumberSequenceKeypoint.new(1, 1),
					})
					g.Enabled = true
				end
			else
				g.Enabled = false
			end
			paint(el, tc)
			el.Visible = true
		end
		for i = n + 1, shown do
			pool[i].Visible = false
		end
		for i = n + 1, #pool do
			pool[i].Visible = false
		end
		shown = n
	end

	-- The look of every tile: a colour (multiplied with each tile's tint) and a transparency.
	function surface.look(_self: Surface, color: Color3, transparency: number)
		if color == lookColor and transparency == lookTransparency then
			return
		end
		lookColor, lookTransparency = color, transparency
		folder.Visible = transparency < 1
		for i = 1, shown do
			paint(pool[i], tints[i])
		end
	end

	function surface.clear(_self: Surface)
		for i = 1, #pool do
			pool[i].Visible = false
		end
		shown = 0
	end

	function surface.count(_self: Surface): number
		return shown
	end

	return surface
end

return FoodSurface

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
-- Render budget (measured in Studio 2026-11-01): the engine keeps one texture per distinct
-- gradient sequence, and past about a thousand distinct sequences on screen the newest
-- gradients stop drawing (their tiles show as plain squares, a staircase edge). 2,560 gradients
-- sharing one sequence drew correctly. So every cut tile uses one of a few shared sequences (an
-- edge at the middle, softened over a quantised width) and its edge is moved with the
-- gradient's Offset, which shifts the gradient by (Offset.X * W, Offset.Y * H) px in the
-- element's own frame (measured the same day).
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

-- A turned view (an oval rolled at an angle): each tile reaches PAD px past its square, so
-- rounding never opens a seam. An upright view (every round dough, and the oven's flattened
-- view of it): tiles are snapped to whole pixels instead, so neighbours share their edges
-- exactly and never overlap (an overlap shows as a darker line while a surface fades).
local PAD = 0.5
local SOFT = 1.0 -- px over which a cut edge goes from opaque to clear (anti-aliasing)
local SOFT_STEP = 1 / 256 -- the soft width's quantum along the gradient: few shared sequences

-- The shared edge sequences, by quantised soft width (see "Render budget" above).
local edges: { [number]: NumberSequence } = {}
local function edge(steps: number): NumberSequence
	local seq = edges[steps]
	if not seq then
		local half = steps * SOFT_STEP / 2
		seq = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5 - half, 0),
			NumberSequenceKeypoint.new(0.5 + half, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		edges[steps] = seq
	end
	return seq
end

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
	local upright = true
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
		-- Upright: dough-local x and y run straight across and down the screen (no turn, no
		-- shear), so every tile's corners land on one pixel grid.
		local c0, cx1, cy1 = f({ x = 0, y = 0 }), f({ x = 1, y = 0 }), f({ x = 0, y = 1 })
		upright = math.abs(p) < 1e-6 and math.abs(cx1.Y - c0.Y) < 0.01 and math.abs(cy1.X - c0.X) < 0.01
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
			local W, H
			-- The drawn rectangle in dough-local units (for the material) and the shift of its
			-- centre from the square's (for the cut edge).
			local lx0, ly0, lx1, ly1 = t.x0, t.y0, t.x1, t.y1
			local shiftX, shiftY = 0, 0
			if upright then
				local p0 = screen({ x = t.x0, y = t.y0 }) - origin
				local p1 = screen({ x = t.x1, y = t.y1 }) - origin
				local X0, Y0 = math.floor(p0.X + 0.5), math.floor(p0.Y + 0.5)
				local X1, Y1 = math.floor(p1.X + 0.5), math.floor(p1.Y + 0.5)
				W, H = X1 - X0, Y1 - Y0
				if W <= 0 or H <= 0 then
					-- Covers no whole pixel: its neighbours meet across it.
					tints[n] = Color3.new(1, 1, 1)
					el.Visible = false
					local g0 = el:FindFirstChildOfClass("UIGradient") :: UIGradient
					g0.Enabled = false
					continue
				end
				lx0, ly0 = t.x0 + (X0 - p0.X) / sa, t.y0 + (Y0 - p0.Y) / sb
				lx1, ly1 = t.x1 + (X1 - p1.X) / sa, t.y1 + (Y1 - p1.Y) / sb
				local px, py = (X0 + X1) / 2, (Y0 + Y1) / 2
				shiftX, shiftY = (px - s.X) / sa, (py - s.Y) / sb
				el.Position = UDim2.fromOffset(px, py)
			else
				W = sa * (t.x1 - t.x0) + 2 * PAD
				H = sb * (t.y1 - t.y0) + 2 * PAD
				lx0, ly0, lx1, ly1 = t.x0 - PAD / sa, t.y0 - PAD / sb, t.x1 + PAD / sa, t.y1 + PAD / sb
				el.Position = UDim2.fromOffset(s.X, s.Y)
			end
			el.Size = UDim2.fromOffset(W, H)
			el.Rotation = phi
			if useImage then
				local img = el :: ImageLabel
				local scale = imagePx / (2 * span)
				img.ImageRectOffset = Vector2.new((lx0 + span) * scale, (ly0 + span) * scale)
				img.ImageRectSize = Vector2.new((lx1 - lx0) * scale, (ly1 - ly0) * scale)
			end
			local tc = if tint then tint(t.key) else Color3.new(1, 1, 1)
			tints[n] = tc
			local g = el:FindFirstChildOfClass("UIGradient") :: UIGradient
			if t.kind == "cut" then
				-- The edge in the tile's own frame: local u = diag(a, b) (p - c), so the inside
				-- n . (p - c) <= d is m . u <= d with m = (nx / a, ny / b).
				local mx, my = (t.nx :: number) / sa, (t.ny :: number) / sb
				local ml = math.sqrt(mx * mx + my * my)
				-- Measured from the drawn centre: n . (p - c') <= d - n . (c' - c).
				local d = (t.d :: number) - ((t.nx :: number) * shiftX + (t.ny :: number) * shiftY)
				local dist = d / ml
				local th = math.atan2(my, mx)
				local c, sn = math.abs(math.cos(th)), math.abs(math.sin(th))
				local L = math.min(if c > 1e-6 then W / c else math.huge, if sn > 1e-6 then H / sn else math.huge)
				local steps = math.clamp(math.floor(SOFT / L / SOFT_STEP + 0.5), 1, 64)
				local half = steps * SOFT_STEP / 2
				local t0 = 0.5 + dist / L
				if t0 + half <= 0 then
					el.Visible = false
					g.Enabled = false
					continue
				end
				if t0 - half >= 1 then
					g.Enabled = false
				else
					-- One shared sequence with its edge at the middle, moved to the cut by the
					-- Offset: the shift (dist cos th / W, dist sin th / H) of the element's size
					-- moves the gradient's middle dist px along its direction.
					g.Rotation = math.deg(th)
					g.Transparency = edge(steps)
					g.Offset = Vector2.new(dist * math.cos(th) / W, dist * math.sin(th) / H)
					g.Enabled = true
				end
			else
				g.Enabled = false
			end
			paint(el, tc)
			el.Visible = true
		end
		for i = n + 1, #pool do
			pool[i].Visible = false
			local g = pool[i]:FindFirstChildOfClass("UIGradient") :: UIGradient
			g.Enabled = false
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

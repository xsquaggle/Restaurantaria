--!strict
-- Light for reward moments (slice 5; Lawson 2026-10-28 asked for glimmer and shine on the
-- end-of-shift card, its coins and its XP meter): sweeps of light across a surface or a
-- label, twinkles and bursts of them, rings, glows and flares, light rays, a glow round a
-- panel's edge, drifting motes, a flash, a coin's spin, small coins tossed out of one and a
-- burst of confetti. Curves and timings come from MotionPlan.
--
-- Every effect plays on the Motion driver, so the Studio test clock holds it and a skip is
-- exact: given a presentation, the presentation owns the effect and its finish removes it at
-- once; without one (an idle glint) the effect removes itself when it ends. Lasting light
-- (rays, an edge glow, a glow behind an icon) is a shape the caller keeps and sets. Effects
-- only add instances over or under the layout: they never move a row, change a value or
-- take input.
--
-- Stand-ins (declared, not supplied art): no sparkle, ray or cool glow art has been
-- supplied, so a twinkle is drawn here from four soft light streaks, a bright core and a soft
-- halo; a cool glow from stacked soft discs; light rays from soft beams; a panel's edge glow
-- from stacked rounded outlines; a sweep of light is a band in a UIGradient; confetti pieces
-- (paper, pepperoni, basil) are drawn shapes. Shine.skin.sparkle names supplied art to use
-- for twinkles instead (one image, tinted per use). Supplied art used as it is:
-- fx_select_ring (rings), fx_oven_glow (warm glows and flares) and icon_coin (tossed coins).

local Art = require(game:GetService("ReplicatedStorage").Shared.Art)
local Motion = require(script.Parent.Motion)
local MotionPlan = require(script.Parent.MotionPlan)
local Ui = require(script.Parent.Ui)

local Shine = {}

local WHITE = Color3.new(1, 1, 1)
-- Light on dark ground (over the backdrop) and on saturated art (the coin, the star).
Shine.WARM = Color3.fromRGB(255, 249, 232)
-- Light that still reads on the cream card: a saturated gold and a deep mint.
Shine.GOLD = Color3.fromRGB(255, 196, 64)
Shine.TEAL = Color3.fromRGB(40, 200, 172)
-- Mint light on the bar's fill and on the star.
Shine.MINT = Color3.fromRGB(150, 255, 224)

-- Re-skin slot: an art name for the twinkle image (nil: the drawn stand-in).
Shine.skin = { sparkle = nil :: string? }

type Owner = Motion.Presentation?

local function kp(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

local function ck(t: number, c: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(t, c)
end

local function round(): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- Plays one effect instance: hidden() until `delay` has passed, then step(q) for q from 0 to
-- 1 over `life`, then the instance is removed. An owning presentation removes it on finish.
-- An effect whose host has gone (the card rebuilt or closed under it) stops at once instead of
-- running its timer out on a removed instance (Astra r18 M18-03).
local function play(pr: Owner, inst: Instance, delay: number, life: number, step: (number) -> (), hidden: (() -> ())?)
	local function remove()
		inst:Destroy()
	end
	local key = {}
	if pr then
		if not pr.alive then
			remove()
			return
		end
		pr:own(key, remove)
	end
	local total = delay + life
	Motion.run(key, total, function(p)
		if inst.Parent == nil then
			Motion.stop(key, false)
			remove()
			return
		end
		local t = p * total - delay
		if t < 0 then
			if hidden then
				hidden()
			end
		else
			step(if life > 0 then math.min(t / life, 1) else 1)
		end
	end, remove)
end

------------------------------------------------------------------------------------------
-- Twinkles

export type Twinkle = { root: Frame, set: (scale: number, transparency: number, spin: number) -> () }

type Part = { inst: GuiObject, prop: string, rest: number, angle: number? }

-- Two long streaks and two short, dimmer diagonals, each fading toward its ends.
local STREAKS = {
	{ length = 1, thickness = 0.13, angle = 0, rest = 0 },
	{ length = 1, thickness = 0.13, angle = 90, rest = 0 },
	{ length = 0.52, thickness = 0.09, angle = 45, rest = 0.3 },
	{ length = 0.52, thickness = 0.09, angle = 135, rest = 0.3 },
}
local STREAK_FADE = NumberSequence.new({ kp(0, 1), kp(0.5, 0), kp(1, 1) })
-- The halo: two soft discs behind the streaks, so a twinkle reads on light ground too.
local HALO = { { size = 0.72, rest = 0.84 }, { size = 0.42, rest = 0.66 } }

-- One twinkle, `px` across, centred on its Position; set() places its moment of life. With
-- `halo`, a soft disc of that colour glows behind it.
function Shine.twinkleShape(parent: Instance, px: number, colour: Color3, z: number, halo: Color3?): Twinkle
	local root = Ui.new("Frame", {
		Name = "Twinkle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
		ZIndex = z,
		Parent = parent,
	})
	local scale = Ui.new("UIScale", { Scale = 0.001, Parent = root })
	local parts: { Part } = {}
	if halo then
		for _, h in HALO do
			local disc = Ui.new("Frame", {
				BackgroundColor3 = halo,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(h.size, h.size),
				ZIndex = z,
				Parent = root,
			}, { round() })
			table.insert(parts, { inst = disc, prop = "BackgroundTransparency", rest = h.rest })
		end
	end
	local skin = Shine.skin.sparkle
	if skin then
		local image = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			ImageColor3 = colour,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = root,
		})
		Art.apply(image, skin)
		table.insert(parts, { inst = image, prop = "ImageTransparency", rest = 0, angle = 0 })
	else
		for _, s in STREAKS do
			local streak = Ui.new("Frame", {
				BackgroundColor3 = colour,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(s.length, s.thickness),
				Rotation = s.angle,
				ZIndex = z,
				Parent = root,
			}, {
				round(),
				Ui.new("UIGradient", { Transparency = STREAK_FADE }),
			})
			table.insert(parts, { inst = streak, prop = "BackgroundTransparency", rest = s.rest, angle = s.angle })
		end
		local core = Ui.new("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.24, 0.24),
			ZIndex = z,
			Parent = root,
		}, { round() })
		table.insert(parts, { inst = core, prop = "BackgroundTransparency", rest = 0.05 })
	end
	return {
		root = root,
		set = function(s: number, transparency: number, spin: number)
			scale.Scale = math.max(s, 0.001)
			for _, part in parts do
				(part.inst :: any)[part.prop] = part.rest + (1 - part.rest) * transparency
				if part.angle then
					part.inst.Rotation = part.angle + spin
				end
			end
		end,
	}
end

export type TwinkleOptions = {
	at: UDim2,
	size: number,
	colour: Color3?,
	halo: Color3?,
	z: number,
	delay: number?,
	life: number?,
	spin: number?,
}

-- One twinkle in place: flares, turns a little and fades.
function Shine.twinkle(pr: Owner, host: Instance, o: TwinkleOptions)
	local tw = Shine.twinkleShape(host, math.max(2, math.round(o.size)), o.colour or Shine.WARM, o.z, o.halo)
	tw.root.Position = o.at
	local spin = o.spin or 45
	play(pr, tw.root, o.delay or 0, o.life or MotionPlan.T.twinkle, function(q)
		local s, t = MotionPlan.twinkle(q)
		tw.set(s, t, spin * q)
	end)
end

export type BurstOptions = {
	at: UDim2, -- the centre the twinkles leave from
	count: number,
	from: number, -- px from the centre where they appear
	to: number, -- px from the centre they travel to (each varies a little)
	size: number,
	colours: { Color3 },
	halo: Color3?,
	z: number,
	seed: number, -- the same burst every time (deterministic, so stills can be compared)
	life: number?,
	delay: number?,
	stagger: number?, -- each twinkle starts up to this much later
	angle: number?, -- degrees of the first twinkle's direction
}

-- Twinkles thrown outward from a centre, evenly round it with a little jitter.
function Shine.burst(pr: Owner, host: Instance, o: BurstOptions)
	local rng = Random.new(o.seed)
	local life = o.life or MotionPlan.T.twinkle
	for i = 1, o.count do
		local a = math.rad(o.angle or -90) + (i - 1) / o.count * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local dir = Vector2.new(math.cos(a), math.sin(a))
		local reach = o.to * rng:NextNumber(0.8, 1.1)
		local px = math.max(2, math.round(o.size * rng:NextNumber(0.7, 1.2)))
		local tw = Shine.twinkleShape(host, px, o.colours[(i - 1) % #o.colours + 1], o.z, o.halo)
		local spin = rng:NextNumber(40, 110) * (if rng:NextNumber() < 0.5 then -1 else 1)
		local function place(r: number)
			tw.root.Position = o.at + UDim2.fromOffset(dir.X * r, dir.Y * r)
		end
		place(o.from)
		local delay = (o.delay or 0) + (o.stagger or 0) * rng:NextNumber()
		play(pr, tw.root, delay, life * rng:NextNumber(0.85, 1), function(q)
			place(o.from + (reach - o.from) * MotionPlan.easeOut(q))
			local s, t = MotionPlan.twinkle(q)
			tw.set(s, t, spin * q)
		end)
	end
end

------------------------------------------------------------------------------------------
-- Glows, flares, rays and a panel's edge glow

export type Glow = { root: GuiObject, set: (scale: number, transparency: number) -> () }

-- Stacked soft discs for a cool glow: most of them small, so the light gathers in the middle
-- and thins out toward a soft fringe (evenly spread discs read as a flat disc).
local DISCS = 9
local DISC_ALPHA = 0.12

-- A soft round glow `px` across, centred on its Position, set to a scale and a transparency.
-- With `art` (fx_oven_glow: a yellow core in an orange halo, tinted by `colour`) it is that
-- image; without, a disc glow of `colour` is drawn (the art's orange cannot take a cool tint).
function Shine.glowShape(parent: Instance, px: number, colour: Color3, z: number, art: string?): Glow
	if art then
		local image = Ui.new("ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(px, px),
			ImageColor3 = colour,
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = z,
			Parent = parent,
		})
		Art.apply(image, art)
		local scale = Ui.new("UIScale", { Scale = 1, Parent = image })
		return {
			root = image,
			set = function(s: number, transparency: number)
				scale.Scale = math.max(s, 0.001)
				image.ImageTransparency = math.clamp(transparency, 0, 1)
			end,
		}
	end
	local root = Ui.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
		ZIndex = z,
		Parent = parent,
	})
	local scale = Ui.new("UIScale", { Scale = 1, Parent = root })
	local discs: { Frame } = {}
	for k = 1, DISCS do
		local f = (k / DISCS) ^ 1.6
		table.insert(
			discs,
			Ui.new("Frame", {
				BackgroundColor3 = colour,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(f, f),
				ZIndex = z,
				Parent = root,
			}, { round() })
		)
	end
	return {
		root = root,
		set = function(s: number, transparency: number)
			scale.Scale = math.max(s, 0.001)
			local t = 1 - DISC_ALPHA * (1 - math.clamp(transparency, 0, 1))
			for _, disc in discs do
				disc.BackgroundTransparency = t
			end
		end,
	}
end

export type FlareOptions = {
	at: UDim2,
	size: number, -- px across at scale 1
	from: number, -- scale it blooms from
	to: number, -- and to
	life: number,
	colour: Color3?,
	art: string?,
	peak: number?, -- transparency at its brightest
	z: number,
	delay: number?,
}

-- A glow that blooms outward and fades: the light of a payoff.
function Shine.flare(pr: Owner, host: Instance, o: FlareOptions)
	local glow = Shine.glowShape(host, math.round(o.size), o.colour or WHITE, o.z, o.art)
	glow.root.Position = o.at
	glow.set(o.from, 1)
	local peak = o.peak or 0
	play(pr, glow.root, o.delay or 0, o.life, function(q)
		glow.set(o.from + (o.to - o.from) * MotionPlan.easeOut(q), MotionPlan.ringFade(q, peak))
	end)
end

export type Rays = {
	root: Frame,
	setLevel: (number) -> (), -- 0 dark, 1 their full light (o.opacity), above 1 a surge
	setTurn: (number) -> (), -- degrees
	setScale: (number) -> (),
	setRadius: (number) -> (),
}

export type RaysOptions = {
	at: UDim2,
	radius: number, -- px from the centre to a long ray's tip
	count: number, -- an even number: long and short rays alternate
	colour: Color3,
	opacity: number, -- a ray's light at its brightest, at level 1
	width: number?, -- a long ray's width as a share of the radius
	z: number,
}

-- Each ray is brightest near the centre and fades out along its length. A ray is a bright
-- narrow beam inside a fainter wide one, so its sides fall off softly.
local RAY_FADE = NumberSequence.new({ kp(0, 0), kp(0.45, 0.05), kp(1, 1) })
local RAY_LAYERS = { { width = 1, light = 0.45 }, { width = 0.38, light = 0.75 } }

-- Soft light rays round a centre, turning as a whole.
function Shine.rays(parent: Instance, o: RaysOptions): Rays
	local root = Ui.new("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.at,
		Size = UDim2.fromOffset(o.radius * 2, o.radius * 2),
		ZIndex = o.z,
		Parent = parent,
	})
	local scale = Ui.new("UIScale", { Scale = 1, Parent = root })
	local width = (o.width or 0.1) / 2 -- of the root's height (two radii)
	local beams: { { frame: Frame, light: number } } = {}
	for i = 1, o.count do
		local long = i % 2 == 1
		-- Each arm turns one ray about the centre; the ray runs from the centre outward.
		local arm = Ui.new("Frame", {
			Name = "Arm",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = (i - 1) * 360 / o.count,
			ZIndex = o.z,
			Parent = root,
		})
		for _, layer in RAY_LAYERS do
			table.insert(beams, {
				light = layer.light,
				frame = Ui.new("Frame", {
					Name = "Ray",
					BackgroundColor3 = o.colour,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(if long then 0.5 else 0.36, (if long then width else width * 0.7) * layer.width),
					ZIndex = o.z,
					Parent = arm,
				}, {
					round(),
					Ui.new("UIGradient", { Transparency = RAY_FADE }),
				}),
			})
		end
	end
	return {
		root = root,
		setLevel = function(level: number)
			for _, beam in beams do
				beam.frame.BackgroundTransparency = math.clamp(1 - o.opacity * beam.light * level, 0, 1)
			end
		end,
		setTurn = function(degrees: number)
			root.Rotation = degrees
		end,
		setScale = function(s: number)
			scale.Scale = s
		end,
		setRadius = function(r: number)
			root.Size = UDim2.fromOffset(r * 2, r * 2)
		end,
	}
end

export type EdgeGlow = {
	root: Frame, -- the panel's own rectangle: the caller sizes and places it
	setLevel: (number) -> (), -- 0 dark, 1 full (o.opacity at the edge), above 1 a surge
	setCorner: (number) -> (), -- the panel's corner radius, px
}

export type EdgeGlowOptions = { colour: Color3, opacity: number, layers: number, step: number, z: number }

-- A soft glow round a rounded panel: rounded shapes each `step` px larger than the last,
-- stacked so the light is strongest at the panel's edge and fades outward.
function Shine.edgeGlow(parent: Instance, o: EdgeGlowOptions): EdgeGlow
	local root = Ui.new("Frame", {
		Name = "EdgeGlow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = o.z,
		Parent = parent,
	})
	-- Each layer's light, so all of them together reach o.opacity at the edge.
	local alpha = 1 - (1 - o.opacity) ^ (1 / o.layers)
	local shapes: { Frame } = {}
	local corners: { UICorner } = {}
	for k = 1, o.layers do
		local d = k * o.step
		local corner = Ui.new("UICorner", { CornerRadius = UDim.new(0, d) })
		table.insert(corners, corner)
		table.insert(
			shapes,
			Ui.new("Frame", {
				BackgroundColor3 = o.colour,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, d * 2, 1, d * 2),
				ZIndex = o.z,
				Parent = root,
			}, { corner })
		)
	end
	return {
		root = root,
		setLevel = function(level: number)
			local t = 1 - math.clamp(alpha * level, 0, 1)
			for _, shape in shapes do
				shape.BackgroundTransparency = t
			end
		end,
		setCorner = function(r: number)
			for k, corner in corners do
				corner.CornerRadius = UDim.new(0, math.round(r + k * o.step))
			end
		end,
	}
end

------------------------------------------------------------------------------------------
-- Rings, sweeps, flashes, motes and tossed coins

export type RingOptions = { at: UDim2, from: number, to: number, life: number, colour: Color3?, peak: number?, z: number, delay: number? }

-- A ring of light (fx_select_ring) that expands from `from` to `to` px and fades.
function Shine.ring(pr: Owner, host: Instance, o: RingOptions)
	local ring = Ui.new("ImageLabel", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.at,
		Size = UDim2.fromOffset(o.from, o.from),
		ImageColor3 = o.colour or WHITE,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = o.z,
		Parent = host,
	})
	Art.apply(ring, "fx_select_ring")
	local peak = o.peak or 0
	play(pr, ring, o.delay or 0, o.life, function(q)
		local d = o.from + (o.to - o.from) * MotionPlan.easeOut(q)
		ring.Size = UDim2.fromOffset(d, d)
		ring.ImageTransparency = MotionPlan.ringFade(q, peak)
	end)
end

export type SheenOptions = {
	life: number,
	z: number,
	delay: number?,
	peak: number?, -- transparency at the brightest point of the band
	inset: Vector2?, -- px kept clear inside the host's edge on each side
	corner: UDim?, -- the lit area's corner radius, matching the art underneath
	colour: Color3?,
	angle: number?, -- degrees the band leans
}

-- A broad soft band with a thin one trailing it: the classic glint.
local function band(peak: number): NumberSequence
	local thin = peak + (1 - peak) * 0.4
	return NumberSequence.new({
		kp(0, 1),
		kp(0.3, 1),
		kp(0.345, thin),
		kp(0.39, 1),
		kp(0.43, 1),
		kp(0.55, peak),
		kp(0.67, 1),
		kp(1, 1),
	})
end

-- A sweep of light across the host, clipped to its rounded shape, once.
function Shine.sheen(pr: Owner, host: Instance, o: SheenOptions)
	local inset = o.inset or Vector2.zero
	local lit = Ui.new("Frame", {
		Name = "Sheen",
		BackgroundColor3 = o.colour or WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(inset.X, inset.Y),
		Size = UDim2.new(1, -2 * inset.X, 1, -2 * inset.Y),
		ZIndex = o.z,
		Parent = host,
	}, {
		Ui.new("UICorner", { CornerRadius = o.corner or UDim.new(0, 0) }),
	})
	local gradient = Ui.new("UIGradient", {
		Rotation = o.angle or 22,
		Transparency = band(o.peak or 0.3),
		Offset = Vector2.new(-1, 0),
		Parent = lit,
	})
	play(pr, lit, o.delay or 0, o.life, function(q)
		gradient.Offset = Vector2.new(MotionPlan.sweep(q), 0)
	end, function()
		gradient.Offset = Vector2.new(-1, 0)
	end)
end

export type FlashOptions = { life: number, z: number, peak: number?, colour: Color3?, corner: UDim?, delay: number? }

-- Light over the whole host that fades out (a bar locking in, a threshold reached).
function Shine.flash(pr: Owner, host: Instance, o: FlashOptions)
	local peak = o.peak or 0.3
	local lit = Ui.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = o.colour or WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = o.z,
		Parent = host,
	}, {
		Ui.new("UICorner", { CornerRadius = o.corner or UDim.new(0, 0) }),
	})
	play(pr, lit, o.delay or 0, o.life, function(q)
		lit.BackgroundTransparency = peak + (1 - peak) * MotionPlan.easeOut(q)
	end)
end

export type MoteOptions = { at: UDim2, drift: Vector2, size: number, life: number, colour: Color3, z: number, peak: number? }

-- A small round mote of light that drifts, shrinks and fades.
function Shine.mote(pr: Owner, host: Instance, o: MoteOptions)
	local peak = o.peak or 0
	local dot = Ui.new("Frame", {
		Name = "Mote",
		BackgroundColor3 = o.colour,
		BackgroundTransparency = peak,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = o.at,
		Size = UDim2.fromOffset(o.size, o.size),
		ZIndex = o.z,
		Parent = host,
	}, { round() })
	play(pr, dot, 0, o.life, function(q)
		local e = MotionPlan.easeOut(q)
		dot.Position = o.at + UDim2.fromOffset(o.drift.X * e, o.drift.Y * e)
		local d = o.size * (1 - 0.6 * q)
		dot.Size = UDim2.fromOffset(d, d)
		dot.BackgroundTransparency = peak + (1 - peak) * q * q
	end)
end

export type TossOptions = {
	at: UDim2, -- where the coins leave from
	count: number,
	size: number, -- px across
	speed: number, -- px a second they leave at (each varies a little)
	gravity: number, -- px a second squared
	spread: number?, -- degrees of the upward fan they leave in
	edge: Color3, -- the coin's colour edge-on as it spins
	z: number,
	seed: number, -- the same toss every time
	life: number?,
	delay: number?,
}

-- Small coins (icon_coin) tossed up out of a centre: each flies its own arc under gravity,
-- spinning about its upright axis, and fades as it falls.
function Shine.toss(pr: Owner, host: Instance, o: TossOptions)
	local rng = Random.new(o.seed)
	local spread = math.rad(o.spread or 150)
	local px = math.max(4, math.round(o.size))
	for i = 1, o.count do
		local holder = Ui.new("Frame", {
			Name = "Toss",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = o.at,
			Size = UDim2.fromOffset(px, px),
			ZIndex = o.z,
			Parent = host,
		})
		local image = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = o.z,
			Parent = holder,
		})
		Art.apply(image, "icon_coin")
		local scale = Ui.new("UIScale", { Scale = 0.001, Parent = holder })
		-- Evenly across the fan, centred straight up, with a little jitter.
		local a = -math.pi / 2 - spread / 2 + spread * (i - 0.5) / o.count + rng:NextNumber(-0.12, 0.12)
		local v = o.speed * rng:NextNumber(0.75, 1.1)
		local vx, vy = math.cos(a) * v, math.sin(a) * v
		local turns = rng:NextNumber(1.2, 2.4)
		local phase = rng:NextNumber()
		local life = (o.life or MotionPlan.T.toss) * rng:NextNumber(0.85, 1)
		local delay = (o.delay or 0) + rng:NextNumber(0, 0.06)
		play(pr, holder, delay, life, function(q)
			local x, y = MotionPlan.arc(q * life, vx, vy, o.gravity)
			holder.Position = o.at + UDim2.fromOffset(x, y)
			scale.Scale = 0.35 + 0.65 * MotionPlan.easeOut(math.min(q / 0.15, 1))
			local w = math.abs(math.cos(2 * math.pi * (turns * q + phase)))
			image.Size = UDim2.fromScale(math.max(w, 0.1), 1)
			image.ImageColor3 = WHITE:Lerp(o.edge, (1 - w) * 0.55)
			image.ImageTransparency = if q < 0.6 then 0 else ((q - 0.6) / 0.4) ^ 1.3
		end, function()
			image.ImageTransparency = 1
		end)
	end
end

------------------------------------------------------------------------------------------
-- Confetti

export type ConfettiOptions = {
	at: UDim2, -- the middle of the line the pieces leave from
	width: number, -- px: how wide that line is
	count: number,
	speed: number, -- px a second they leave at, at most
	drag: number, -- how fast the air slows them (1/s)
	fall: number, -- px a second they flutter down at, at most
	size: number, -- px: the length of an average piece
	life: number,
	back: number, -- ZIndex of the pieces behind the card
	front: number, -- ZIndex of the pieces in front of it
	frontShare: number, -- share of the pieces in front
	seed: number, -- the same burst every time
	delay: number?,
	room: number?, -- px of screen above the line: a burst that would rise higher is squashed to it
}

-- Paper in the pizzeria's colours (tomato, cheese, the XP teal, cream, oven orange, basil),
-- with pepperoni slices and basil leaves among it.
local PAPER = {
	Color3.fromRGB(226, 91, 69),
	Color3.fromRGB(255, 200, 68),
	Color3.fromRGB(44, 196, 168),
	Color3.fromRGB(255, 245, 224),
	Color3.fromRGB(240, 160, 64),
	Color3.fromRGB(127, 179, 94),
}
local PEPPERONI = Color3.fromRGB(205, 74, 56)
local PEPPERONI_SPOT = Color3.fromRGB(150, 44, 34)
local LEAF = Color3.fromRGB(96, 156, 72)
local SHADE = Color3.fromRGB(70, 44, 36)
-- Shapes: width and height as shares of the piece's length, corner radius, how often.
local PIECES = {
	{ kind = "strip", w = 0.42, h = 1, corner = 0.12, weight = 40 },
	{ kind = "square", w = 0.62, h = 0.62, corner = 0.1, weight = 20 },
	{ kind = "dot", w = 0.52, h = 0.52, corner = 0.5, weight = 12 },
	{ kind = "pepperoni", w = 0.7, h = 0.7, corner = 0.5, weight = 14 },
	{ kind = "leaf", w = 0.44, h = 0.95, corner = 0.5, weight = 14 },
}

local function pickPiece(rng: Random): any
	local total = 0
	for _, p in PIECES do
		total += p.weight
	end
	local r = rng:NextNumber(0, total)
	for _, p in PIECES do
		r -= p.weight
		if r <= 0 then
			return p
		end
	end
	return PIECES[1]
end

-- A burst of confetti: pieces thrown up and outward from along a line, slowed by the air,
-- fluttering down (each sways, turns and tumbles end over end, darkening edge-on) and
-- fading out. Some fly behind the card and some in front; the front ones leave from the
-- outer parts of the line and lean outward, so few cross the card's middle. Stand-in: the
-- pieces are drawn shapes (no confetti art has been supplied).
function Shine.confetti(pr: Owner, host: Instance, o: ConfettiOptions)
	local rng = Random.new(o.seed)
	local T = MotionPlan.T
	-- Only the upward speed is squashed, so a short screen keeps the burst's sideways spread.
	local lift = if o.room then MotionPlan.confettiLift(o.room, o.speed, o.drag * T.confettiDragLow, o.fall) else 1
	for _ = 1, o.count do
		local piece = pickPiece(rng)
		local front = rng:NextNumber() < o.frontShare
		local depth = if front then 1.12 else 0.86
		local len = o.size * depth * rng:NextNumber(0.8, 1.15)
		local w, h = math.max(3, math.round(len * piece.w)), math.max(3, math.round(len * piece.h))
		local colour = if piece.kind == "pepperoni" then PEPPERONI
			elseif piece.kind == "leaf" then LEAF
			else PAPER[rng:NextInteger(1, #PAPER)]
		if not front then
			-- Further away: a little smaller and a little dimmer.
			colour = colour:Lerp(SHADE, 0.12)
		end
		local holder = Ui.new("Frame", {
			Name = "Confetti",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = o.at,
			Size = UDim2.fromOffset(w, h),
			ZIndex = if front then o.front else o.back,
			Parent = host,
		})
		local paper = Ui.new("Frame", {
			Name = "Paper",
			BackgroundColor3 = colour,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = holder.ZIndex,
			Parent = holder,
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(piece.corner, 0) }),
		})
		local spots: { Frame } = {}
		if piece.kind == "pepperoni" then
			for _, s in { { 0.32, 0.36, 0.22 }, { 0.64, 0.6, 0.18 }, { 0.36, 0.7, 0.13 } } do
				table.insert(spots, Ui.new("Frame", {
					BackgroundColor3 = PEPPERONI_SPOT,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(s[1], s[2]),
					Size = UDim2.fromScale(s[3], s[3]),
					ZIndex = holder.ZIndex,
					Parent = paper,
				}, { round() }))
			end
		end
		local scale = Ui.new("UIScale", { Scale = 0.3, Parent = holder })
		-- Front pieces leave from the outer thirds of the line and lean further out.
		local u = if front
			then (if rng:NextNumber() < 0.5 then rng:NextNumber(0, 0.3) else rng:NextNumber(0.7, 1))
			else rng:NextNumber()
		local x0 = (u - 0.5) * o.width
		local fan = math.rad(if front then 64 else 46)
		local a = -math.pi / 2 + (u - 0.5) * 2 * fan + math.rad(rng:NextNumber(-14, 14))
		local speed = o.speed * rng:NextNumber(0.5, 1)
		local vx, vy = math.cos(a) * speed, math.sin(a) * speed * lift
		local drag = o.drag * rng:NextNumber(T.confettiDragLow, T.confettiDragHigh)
		local gravity = o.fall * drag
		local sway = len * rng:NextNumber(0.6, 1.6)
		local swayRate = rng:NextNumber(3.5, 6.5)
		local swayPhase = rng:NextNumber(0, math.pi * 2)
		local spin = rng:NextNumber(150, 520) * (if rng:NextNumber() < 0.5 then -1 else 1)
		local turn0 = rng:NextNumber(0, 360)
		local tumble = rng:NextNumber(4, 11)
		local tumblePhase = rng:NextNumber(0, math.pi * 2)
		local life = o.life * rng:NextNumber(0.8, 1.05)
		local delay = (o.delay or 0) + rng:NextNumber(0, 0.05)
		play(pr, holder, delay, life, function(q)
			local t = q * life
			local slow = math.exp(-drag * t)
			local x, y = MotionPlan.confetti(t, vx, vy, drag, gravity)
			x += x0 + sway * math.sin(swayRate * t + swayPhase) * (1 - slow)
			holder.Position = o.at + UDim2.fromOffset(x, y)
			holder.Rotation = turn0 + spin * (0.4 * t + 0.6 * (1 - slow) / drag)
			scale.Scale = 0.3 + 0.7 * MotionPlan.easeOut(math.min(t / 0.1, 1))
			-- Tumbling end over end: it narrows and darkens edge-on.
			local c = math.abs(math.cos(tumble * t + tumblePhase))
			paper.Size = UDim2.fromScale(math.max(c, 0.12), 1)
			paper.BackgroundColor3 = colour:Lerp(SHADE, (1 - c) * 0.35)
			local fade = if q < 0.72 then 0 else ((q - 0.72) / 0.28) ^ 1.2
			paper.BackgroundTransparency = fade
			for _, spot in spots do
				spot.BackgroundTransparency = fade
			end
		end, function()
			paper.BackgroundTransparency = 1
			for _, spot in spots do
				spot.BackgroundTransparency = 1
			end
		end)
	end
end

------------------------------------------------------------------------------------------
-- Effects on existing objects: each owns one property group of the object (Motion.keyOf),
-- so a new one replaces the old and the object always ends on its resting look.

-- A sweep of light through a label's text: the text takes the gradient's colours (its own
-- colour with a bright band) for the sweep, then its own colour again.
export type TextShineOptions = { colour: Color3, life: number, delay: number?, width: number? }

function Shine.text(pr: Owner, label: TextLabel, o: TextShineOptions)
	local key = Motion.keyOf(label, "shine")
	key.rest = key.rest or label.TextColor3
	local base: Color3 = key.rest
	local old = label:FindFirstChild("Shine")
	if old then
		old:Destroy()
	end
	local w = o.width or 0.16
	local gradient = Ui.new("UIGradient", {
		Name = "Shine",
		Rotation = 14,
		Color = ColorSequence.new({ ck(0, base), ck(0.5 - w, base), ck(0.5, o.colour), ck(0.5 + w, base), ck(1, base) }),
		Offset = Vector2.new(-1, 0),
	})
	local function rest()
		gradient:Destroy()
		label.TextColor3 = base
	end
	if pr then
		pr:own(key, rest)
	end
	local delay = o.delay or 0
	local total = delay + o.life
	Motion.run(key, total, function(p)
		local t = p * total - delay
		if t < 0 then
			return
		end
		if gradient.Parent ~= label then
			gradient.Parent = label
			label.TextColor3 = WHITE
		end
		gradient.Offset = Vector2.new(MotionPlan.sweep(math.min(t / o.life, 1)), 0)
	end, rest)
end

export type SpinOptions = { turns: number, life: number, edge: Color3, delay: number? }

-- A coin image spins about its upright axis and slows to face-on: it narrows and darkens
-- toward its edge colour as it turns. The image must be centred in its holder.
function Shine.spin(pr: Owner, image: ImageLabel, o: SpinOptions)
	local key = Motion.keyOf(image, "spin")
	local function rest()
		image.Size = UDim2.fromScale(1, 1)
		image.ImageColor3 = WHITE
	end
	if pr then
		pr:own(key, rest)
	end
	local delay = o.delay or 0
	local total = delay + o.life
	Motion.run(key, total, function(p)
		local t = p * total - delay
		if t < 0 then
			return
		end
		local width, shade = MotionPlan.flip(math.min(t / o.life, 1), o.turns)
		image.Size = UDim2.fromScale(width, 1)
		image.ImageColor3 = WHITE:Lerp(o.edge, shade)
	end, rest)
end

return Shine

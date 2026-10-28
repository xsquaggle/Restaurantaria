--!strict
-- Light for reward moments (slice 5; Lawson 2026-10-28 asked for glimmer and shine on the
-- end-of-shift card, its coins and its XP meter): a sweep of light across a surface or a
-- label, twinkles, bursts of twinkles, a ring of light, drifting motes, a flash and a coin's
-- spin. Curves and timings come from MotionPlan.
--
-- Every effect plays on the Motion driver, so the Studio test clock holds it and a skip is
-- exact: given a presentation, the presentation owns the effect and its finish removes it at
-- once; without one (an idle glint) the effect removes itself when it ends. Effects only add
-- instances over or under the layout: they never move a row, change a value or take input.
--
-- Stand-ins (declared, not supplied art): no sparkle art has been supplied, so a twinkle is
-- drawn here from four soft light streaks and a bright core, and a sweep of light is a white
-- band in a UIGradient. Shine.skin.sparkle names supplied art to use for twinkles instead (one
-- image, tinted per use). The ring of light is Astra's fx_select_ring, tinted.

local Art = require(game:GetService("ReplicatedStorage").Shared.Art)
local Motion = require(script.Parent.Motion)
local MotionPlan = require(script.Parent.MotionPlan)
local Ui = require(script.Parent.Ui)

local Shine = {}

local WHITE = Color3.new(1, 1, 1)
Shine.WARM = Color3.fromRGB(255, 249, 232)
Shine.GOLD = Color3.fromRGB(255, 208, 96)
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

-- Plays one effect instance: hidden() until `delay` has passed, then step(q) for q from 0 to
-- 1 over `life`, then the instance is removed. An owning presentation removes it on finish.
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

-- One twinkle, `px` across, centred on its Position; set() places its moment of life.
function Shine.twinkleShape(parent: Instance, px: number, colour: Color3, z: number): Twinkle
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
				Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
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
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		})
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

export type TwinkleOptions = { at: UDim2, size: number, colour: Color3?, z: number, delay: number?, life: number?, spin: number? }

-- One twinkle in place: flares, turns a little and fades.
function Shine.twinkle(pr: Owner, host: Instance, o: TwinkleOptions)
	local tw = Shine.twinkleShape(host, math.max(2, math.round(o.size)), o.colour or Shine.WARM, o.z)
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
		local tw = Shine.twinkleShape(host, px, o.colours[(i - 1) % #o.colours + 1], o.z)
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
-- Rings, sweeps, flashes and motes

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
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	play(pr, dot, 0, o.life, function(q)
		local e = MotionPlan.easeOut(q)
		dot.Position = o.at + UDim2.fromOffset(o.drift.X * e, o.drift.Y * e)
		local d = o.size * (1 - 0.6 * q)
		dot.Size = UDim2.fromOffset(d, d)
		dot.BackgroundTransparency = peak + (1 - peak) * q * q
	end)
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

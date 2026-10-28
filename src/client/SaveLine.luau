--!strict
-- The end-of-shift card's save line (Lawson 2026-10-28). While the save runs, "Saving..."
-- waves letter by letter beside a spinner whose arc breathes as it turns. When the save
-- lands, the spinner whirls and closes into a ring, the ring fills into a green disc as a
-- check draws on and a ring of light leaves it, and the words hop once into "Saved!", which
-- fades away after a couple of seconds. The row stays, so nothing below it moves. A failed
-- or session-only save shows plain words in the warning colour, never animated or faded.
--
-- It only shows the save state it is given: it never decides, delays or retries anything.
-- Reduced motion: plain words while saving; the check and "Saved!" come and go with a short
-- fade.
--
-- Stand-ins (declared, not supplied art): the spinner is an arc drawn with a UIStroke cut by
-- a UIGradient over a faint ring, and the check a disc with two rounded white strokes.

local Players = game:GetService("Players")

local Motion = require(script.Parent.Motion)
local MotionPlan = require(script.Parent.MotionPlan)
local Shine = require(script.Parent.Shine)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local C = Theme.Colour
local WHITE = Color3.new(1, 1, 1)
-- The spinner is oven-warm while it waits (a deeper oven orange, so a thin arc reads on the
-- cream card) and turns basil green as it lands. A faint full ring is its track.
local SPIN = Color3.fromRGB(226, 128, 44)
local DONE = C.basil
local TRACK = 0.2
-- The light that leaves the check: a fresh basil green.
local DONE_LIGHT = Color3.fromRGB(122, 196, 98)
local CENTRE = UDim2.fromScale(0.5, 0.5)

local SaveLine = {}

-- The check's three points, in disc diameters from its centre (y down), and its stroke.
local CHECK = { Vector2.new(-0.24, 0.02), Vector2.new(-0.07, 0.19), Vector2.new(0.25, -0.15) }
local CHECK_WIDTH = 0.13
local CHECK_SPLIT = (CHECK[2] - CHECK[1]).Magnitude / ((CHECK[2] - CHECK[1]).Magnitude + (CHECK[3] - CHECK[2]).Magnitude)
-- How soft the ends of the spinner's arc are, along its gradient.
local ARC_SOFT = 0.07

export type Cue = {
	fresh: boolean, -- the save has just landed: its landing plays (once)
	age: number, -- seconds since it landed (math.huge: long ago)
	delay: number?, -- seconds before a fresh landing plays (the card is still arriving)
}

type Values = {
	appear: number, -- 0..1: the line arriving with its card
	shown: number, -- 0..1: the landed line fading away
	turn: number, -- the spinner: its turn (degrees), its arc, its tint (warm 0 .. green 1)
	arc: number,
	tint: number,
	spin: number, -- 0..1: how much of the spinner shows
	disc: number, -- the check's disc: its scale and how much of it shows
	discAlpha: number,
	short: number, -- how much of each of the check's strokes is drawn
	long: number,
	letters: number, -- 0..1: how much of the waiting word shows
	lifts: { number }, -- each letter's hop (0..1)
	drop: number, -- 0..1: the waiting word sinking away as the save lands
	word: number, -- 0..1: how much of the landed word shows
	wordLift: number,
	wordScale: number,
	width: number, -- the width of the word the line is centred on
}

export type Line = {
	label: TextLabel, -- the row itself; its own text shows only as plain words
	size: number,
	rowH: number,
	state: string, -- "plain" | "pending" | "saved"
	text: string,
	closed: boolean,
	root: Frame,
	icon: Frame,
	spinner: Frame,
	stroke: UIStroke,
	gradient: UIGradient,
	track: UIStroke,
	disc: Frame,
	discScale: UIScale,
	arms: { Frame },
	letters: { TextLabel },
	advances: { number },
	word: TextLabel,
	wordScale: UIScale,
	waitW: number,
	wordW: number,
	iconPx: number,
	gap: number,
	v: Values,
	loopKey: any,
	landKey: any,
	fadeKey: any,
	appearKey: any,
}

------------------------------------------------------------------------------------------
-- Drawing

local measurer: TextLabel? = nil

-- Text widths in layout pixels, measured on a label outside every scaled frame, so a card's
-- pop never changes them. A word's letters measured one by one add up to the word.
local function measure(text: string, font: Font, size: number): number
	local label = measurer
	if label == nil or label.Parent == nil then
		local gui = Ui.new("ScreenGui", {
			Name = "RestaurantariaMeasure",
			ResetOnSpawn = false,
			Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"),
		})
		label = Ui.new("TextLabel", {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			Size = UDim2.fromOffset(2000, 200),
			Parent = gui,
		})
		measurer = label
	end
	local m = label :: TextLabel
	m.FontFace = font
	m.TextSize = size
	m.Text = text
	return m.TextBounds.X
end

-- The spinner's arc: the stroke shows only past the cut along its gradient, with soft ends.
local function arcSequence(share: number): NumberSequence
	if share >= 0.999 then
		return NumberSequence.new(0)
	end
	local cut = MotionPlan.arcCut(share)
	local lo = math.clamp(cut - ARC_SOFT / 2, 0.001, 0.997)
	local hi = math.clamp(cut + ARC_SOFT / 2, lo + 0.001, 0.999)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(lo, 1),
		NumberSequenceKeypoint.new(hi, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

-- One stroke of the check, drawn `amount` (0..1) of the way from `from` to `to`, with round
-- ends; positions in disc diameters from the disc's centre.
local function setArm(arm: Frame, from: Vector2, to: Vector2, amount: number, px: number, width: number)
	if amount <= 0 then
		arm.Visible = false
		return
	end
	arm.Visible = true
	local a, d = from * px, (to - from) * px
	local length = d.Magnitude * math.min(amount, 1)
	local mid = a + d.Unit * (length / 2)
	arm.Position = UDim2.new(0.5, mid.X, 0.5, mid.Y)
	arm.Size = UDim2.fromOffset(length + width, width)
	arm.Rotation = math.deg(math.atan2(d.Y, d.X))
end

local function draw(line: Line)
	local v = line.v
	local T = Motion.T
	line.label.TextTransparency = if line.state == "plain" then 1 - v.appear else 1
	if not line.root.Visible then
		return
	end
	local alpha = v.appear * v.shown
	local px, gap = line.iconPx, line.gap
	-- The icon and the word are centred together; the line re-centres as the word changes.
	local left = -(px + gap + v.width) / 2
	line.icon.Position = UDim2.new(0.5, left + px / 2, 0.5, 0)

	local spinA = v.spin * alpha
	line.spinner.Visible = spinA > 0.002
	if line.spinner.Visible then
		local colour = SPIN:Lerp(DONE, v.tint)
		line.stroke.Transparency = 1 - spinA
		line.stroke.Color = colour
		line.gradient.Rotation = v.turn
		line.gradient.Transparency = arcSequence(v.arc)
		line.track.Transparency = 1 - spinA * TRACK
		line.track.Color = colour
	end

	local discA = v.discAlpha * alpha
	line.disc.Visible = discA > 0.002
	if line.disc.Visible then
		line.disc.BackgroundTransparency = 1 - discA
		line.discScale.Scale = math.max(v.disc, 0.01)
		local width = math.max(2, math.round(px * CHECK_WIDTH))
		setArm(line.arms[1], CHECK[1], CHECK[2], v.short, px, width)
		setArm(line.arms[2], CHECK[2], CHECK[3], v.long, px, width)
		for _, arm in line.arms do
			arm.BackgroundTransparency = 1 - discA
		end
	end

	local x = left + px + gap
	local letterA = v.letters * alpha
	for i, letter in line.letters do
		letter.Visible = letterA > 0.002
		letter.Position = UDim2.new(0.5, x, 0.5, (v.drop * 0.3 - (v.lifts[i] or 0) * T.saveWaveLift) * line.size)
		letter.TextTransparency = 1 - letterA
		x += line.advances[i]
	end

	local wordA = v.word * alpha
	line.word.Visible = wordA > 0.002
	line.word.Position = UDim2.new(0.5, left + px + gap + line.wordW / 2, 0.5, -v.wordLift * line.size * T.saveHopLift)
	line.word.TextTransparency = 1 - wordA
	line.wordScale.Scale = v.wordScale
end

------------------------------------------------------------------------------------------
-- Building

-- The save line over a status label (the footer's row; its height comes from its text).
-- `size` is the label's text size.
function SaveLine.new(label: TextLabel, size: number): Line
	local z = label.ZIndex
	local px = math.round(size * 1.15)
	local stroke = math.max(2, math.round(px * 0.14))
	local root = Ui.new("Frame", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Visible = false,
		Parent = label,
	})
	local icon = Ui.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTRE,
		Size = UDim2.fromOffset(px, px),
		ZIndex = z + 1,
		Parent = root,
	})
	-- A stroke is drawn outside its frame: the ring's outer edge is the icon's. The track is
	-- the same ring, faint and whole, under the spinner's arc.
	local track = Ui.new("UIStroke", { Thickness = stroke, Color = SPIN, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local spinner = Ui.new("Frame", {
		Name = "Spinner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTRE,
		Size = UDim2.fromOffset(px - stroke * 2, px - stroke * 2),
		ZIndex = z + 1,
		Visible = false,
		Parent = icon,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	-- One frame can hold one stroke: the arc's frame sits on the track's.
	local arc = Ui.new("Frame", {
		Name = "Arc",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = spinner,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	track.Parent = spinner
	local ring = Ui.new("UIStroke", {
		Thickness = stroke,
		Color = SPIN,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = arc,
	})
	local gradient = Ui.new("UIGradient", { Parent = ring })
	local disc = Ui.new("Frame", {
		Name = "Check",
		BackgroundColor3 = DONE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = CENTRE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
		Visible = false,
		Parent = icon,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	local arms: { Frame } = {}
	for i, name in { "Short", "Long" } do
		arms[i] = Ui.new("Frame", {
			Name = name,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = z + 3,
			Visible = false,
			Parent = disc,
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		})
	end
	local rowH = math.round(size * 1.4)
	local word = Ui.new("TextLabel", {
		Name = "Word",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = label.FontFace,
		TextSize = size,
		TextColor3 = DONE,
		TextTransparency = 1,
		Size = UDim2.fromOffset(0, rowH),
		ZIndex = z + 1,
		Visible = false,
		Parent = root,
	})
	return {
		label = label,
		size = size,
		rowH = rowH,
		state = "plain",
		text = "",
		closed = false,
		root = root,
		icon = icon,
		spinner = spinner,
		stroke = ring,
		gradient = gradient,
		track = track,
		disc = disc,
		discScale = Ui.new("UIScale", { Parent = disc }),
		arms = arms,
		letters = {},
		advances = {},
		word = word,
		wordScale = Ui.new("UIScale", { Parent = word }),
		waitW = 0,
		wordW = 0,
		iconPx = px,
		gap = math.round(size * 0.4),
		v = {
			appear = 1,
			shown = 1,
			turn = 0,
			arc = MotionPlan.T.saveArcMin,
			tint = 0,
			spin = 0,
			disc = 1,
			discAlpha = 0,
			short = 0,
			long = 0,
			letters = 0,
			lifts = {},
			drop = 0,
			word = 0,
			wordLift = 0,
			wordScale = 1,
			width = 0,
		},
		loopKey = {},
		landKey = {},
		fadeKey = {},
		appearKey = {},
	}
end

-- The waiting word as one label per letter, placed by measured advances.
local function setLetters(line: Line, text: string, colour: Color3)
	for _, letter in line.letters do
		letter:Destroy()
	end
	line.letters, line.advances = {}, {}
	local font = line.label.FontFace
	local total = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		local w = measure(ch, font, line.size)
		table.insert(line.letters, Ui.new("TextLabel", {
			Name = "Letter",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			FontFace = font,
			TextSize = line.size,
			TextColor3 = colour,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = ch,
			Size = UDim2.fromOffset(math.ceil(w) + 1, line.rowH),
			ZIndex = line.label.ZIndex + 1,
			Visible = false,
			Parent = line.root,
		}))
		table.insert(line.advances, w)
		total += w
	end
	line.waitW = total
	line.v.lifts = table.create(#line.letters, 0)
end

------------------------------------------------------------------------------------------
-- Motion

local function stopAll(line: Line)
	Motion.stop(line.loopKey, false)
	Motion.stop(line.landKey, false)
	Motion.stop(line.fadeKey, false)
end

-- While the save runs: the spinner turns and breathes, the letters hop in waves.
local function waiting(line: Line)
	local v = line.v
	local started = Motion.now()
	local n = #line.letters
	local function lap()
		if line.closed then
			return
		end
		Motion.run(line.loopKey, 30, function()
			local t = Motion.now() - started
			v.turn, v.arc = MotionPlan.spinner(t)
			for i = 1, n do
				v.lifts[i] = MotionPlan.saveWave(t, i, n)
			end
			draw(line)
		end, lap)
	end
	lap()
end

-- "Saved!" stays, then fades away. `since`: seconds since the save landed.
local function hold(line: Line, since: number)
	local T = Motion.T
	local v = line.v
	local start = MotionPlan.savedFadeStart()
	if since >= start + T.saveFade then
		v.shown = 0
		draw(line)
		return
	end
	local from = math.max(since - start, 0) / T.saveFade
	local function fade()
		Motion.run(line.fadeKey, T.saveFade * (1 - from), function(p)
			v.shown = 1 - MotionPlan.easeInOut(from + (1 - from) * p)
			draw(line)
		end)
	end
	if since >= start then
		fade()
	else
		v.shown = 1
		draw(line)
		Motion.after(line.fadeKey, start - since, fade)
	end
end

-- The landed check and word at rest.
local function landed(line: Line)
	local v = line.v
	v.spin = 0
	v.tint = 1
	v.disc = 1
	v.discAlpha = 1
	v.short = 1
	v.long = 1
	v.letters = 0
	v.word = 1
	v.wordLift = 0
	v.wordScale = 1
	v.width = line.wordW
end

-- Light as the check lands: a green ring leaves it and a few sparkles fly off.
local function light(line: Line)
	local px = line.iconPx
	local z = line.icon.ZIndex
	Shine.ring(nil, line.icon, { at = CENTRE, from = px * 0.9, to = px * 2.6, life = 0.5, colour = DONE_LIGHT, peak = 0.1, z = z })
	Shine.burst(nil, line.icon, {
		at = CENTRE,
		count = 6,
		from = px * 0.4,
		to = px * 1.5,
		size = px * 0.75,
		colours = { Shine.GOLD, DONE_LIGHT },
		halo = Shine.GOLD,
		z = z + 3,
		seed = 61,
		life = 0.45,
		stagger = 0.03,
	})
end

-- The save lands: from the spinner (it was waiting on this card) or straight in (it landed
-- before the card showed), after `delay` seconds.
local function land(line: Line, fromSpinner: boolean, delay: number)
	local T = Motion.T
	local v = line.v
	Motion.stop(line.loopKey, false)
	local turn0, arc0 = v.turn, v.arc
	-- Straight in, the disc, check and words come in at once (no ring to close first).
	local shift = if fromSpinner then 0 else T.saveDiscAt
	local total = T.saveWordAt + T.saveHop - shift
	if not fromSpinner then
		v.spin = 0
		v.letters = 0
		v.width = line.wordW
	end
	local lit = false
	Motion.run(line.landKey, delay + total, function(p)
		local s = p * (delay + total) - delay
		if s < 0 then
			return
		end
		if fromSpinner then
			local w = MotionPlan.easeInOut(s / T.saveWhirl)
			v.turn = (turn0 + 360 * s / T.saveTurn + 360 * T.saveWhirlTurns * w) % 360
			v.arc = arc0 + (1 - arc0) * w
			v.tint = w
		end
		local at = s + shift
		local q = (at - T.saveDiscAt) / T.saveDisc
		if q >= 0 then
			v.disc = MotionPlan.pop(q, T.saveDiscFrom, T.saveDiscPeak)
			v.discAlpha = MotionPlan.easeOut(math.min(q / 0.35, 1))
			if fromSpinner then
				v.spin = 1 - MotionPlan.easeOut(math.min(q / 0.5, 1))
			end
		end
		v.short, v.long = MotionPlan.checkDraw((at - T.saveCheckAt) / T.saveCheck, CHECK_SPLIT)
		local h = (at - T.saveWordAt) / T.saveHop
		if h >= 0 then
			-- The waiting word sinks and fades first; the new word comes in as it rises, so
			-- the two never sit on top of each other.
			if fromSpinner then
				local out = math.min(h / 0.16, 1)
				v.letters = 1 - out
				v.drop = MotionPlan.easeOut(out)
				v.width = line.waitW + (line.wordW - line.waitW) * MotionPlan.easeInOut(h / T.saveSlide)
			end
			v.word = MotionPlan.easeOut(math.clamp((h - 0.12) / 0.2, 0, 1))
			v.wordLift, v.wordScale = MotionPlan.hop(h)
		end
		if not lit and at >= T.saveCheckAt + 0.1 then
			lit = true
			light(line)
		end
		draw(line)
	end, function()
		landed(line)
		draw(line)
		hold(line, T.saveWordAt + T.saveHop)
	end)
end

-- Reduced motion: the check and the word fade in, nothing else moves.
local function fadeIn(line: Line, delay: number)
	local T = Motion.T
	local v = line.v
	Motion.stop(line.loopKey, false)
	landed(line)
	v.discAlpha = 0
	v.word = 0
	Motion.run(line.landKey, delay + T.reducedFade, function(p)
		local s = p * (delay + T.reducedFade) - delay
		local k = math.clamp(s / T.reducedFade, 0, 1)
		v.discAlpha = k
		v.word = k
		draw(line)
	end, function()
		hold(line, T.saveWordAt + T.saveHop)
	end)
end

------------------------------------------------------------------------------------------
-- State

-- Shows a save state: `tone` "pending" (waiting), "saved" or anything else (plain words in
-- `colour`). The same state again changes nothing, so a refresh never replays the landing.
-- `cue` says whether a "saved" has just landed (it plays once) or how long ago it did.
function SaveLine.set(line: Line, tone: string, text: string, colour: Color3, cue: Cue?)
	local label = line.label
	label.Text = text
	label.TextColor3 = colour
	local reduced = Motion.reduced()
	local v = line.v
	if tone == "pending" and not reduced then
		if line.state == "pending" and line.text == text then
			return
		end
		stopAll(line)
		line.state = "pending"
		line.text = text
		setLetters(line, text, colour)
		v.shown = 1
		v.spin = 1
		v.tint = 0
		v.discAlpha = 0
		v.short = 0
		v.long = 0
		v.letters = 1
		v.drop = 0
		v.word = 0
		v.wordLift = 0
		v.wordScale = 1
		v.width = line.waitW
		line.root.Visible = true
		waiting(line)
		draw(line)
		return
	end
	if tone == "saved" then
		if line.state == "saved" then
			return
		end
		local from = line.state
		stopAll(line)
		line.state = "saved"
		line.text = text
		line.word.Text = text
		line.wordW = measure(text, label.FontFace, line.size)
		line.word.Size = UDim2.fromOffset(math.ceil(line.wordW) + 2, line.rowH)
		line.root.Visible = true
		if cue ~= nil and cue.fresh then
			if reduced then
				fadeIn(line, cue.delay or 0)
			else
				land(line, from == "pending", cue.delay or 0)
			end
		else
			landed(line)
			hold(line, if cue then cue.age else math.huge)
		end
		draw(line)
		return
	end
	if line.state == "plain" and line.text == text then
		draw(line)
		return
	end
	stopAll(line)
	line.state = "plain"
	line.text = text
	line.root.Visible = false
	v.shown = 1
	draw(line)
end

-- The line arrives with its card: a fade over `duration` seconds (0: at once).
function SaveLine.appear(line: Line, duration: number)
	local v = line.v
	if duration <= 0 then
		Motion.stop(line.appearKey, false)
		v.appear = 1
		draw(line)
		return
	end
	v.appear = 0
	draw(line)
	Motion.run(line.appearKey, duration, function(p)
		v.appear = MotionPlan.easeOut(p)
		draw(line)
	end)
end

-- The card is going away: every motion of the line stops for good.
function SaveLine.close(line: Line)
	line.closed = true
	stopAll(line)
	Motion.stop(line.appearKey, false)
end

return SaveLine

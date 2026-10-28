--!strict
-- Shared presentation primitives (Astra r15 motion-and-reward-spec, section 1): press and
-- release, pop (one restrained overshoot), rise/settle, group fade and the slowing count-up
-- with rate-limited ticks. Timings and curves come from MotionPlan; this module only plays
-- them. Every animated property has one owner: starting a motion on a key cancels the one
-- already running there and continues from the visible value, so repeated taps never stack.
--
-- Re-skinnable: Motion.hooks are the sound and haptic slots (coin tick, XP tick, impact,
-- completion, press). None is filled: no audio or haptic asset has been supplied, and the
-- visual language must carry the feel on its own (spec 1a). A business or theme fills them
-- without touching the callers.
--
-- Reduced motion (GuiService.ReducedMotionEnabled, or the Studio-only LocalPlayer attribute
-- RestaurantariaReducedMotion for tests): callers show final values, at most a short fade.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MotionPlan = require(script.Parent.MotionPlan)

local Motion = {}

Motion.T = MotionPlan.T

export type Hooks = {
	coinTick: ((n: number) -> ())?,
	xpTick: ((n: number) -> ())?,
	impact: ((name: string) -> ())?,
	complete: ((name: string) -> ())?,
	press: (() -> ())?,
}
Motion.hooks = {} :: Hooks

local function hook(name: string, ...: any)
	local f = (Motion.hooks :: any)[name]
	if f then
		-- A broken sound or haptic hook must never stop the presentation or its values.
		pcall(f, ...)
	end
end
Motion.hook = hook

function Motion.reduced(): boolean
	local player = Players.LocalPlayer
	if player and RunService:IsStudio() then
		local forced = player:GetAttribute("RestaurantariaReducedMotion")
		if type(forced) == "boolean" then
			return forced
		end
	end
	return GuiService.ReducedMotionEnabled
end

------------------------------------------------------------------------------------------
-- The driver: one Heartbeat connection plays every running motion by elapsed time.

type Running = { start: number, duration: number, step: (number) -> (), done: (() -> ())? }
local running: { [any]: Running } = {}
local connection: RBXScriptConnection? = nil

local function frame()
	local now = os.clock()
	for key, r in running do
		local p = if r.duration > 0 then (now - r.start) / r.duration else 1
		if p >= 1 then
			running[key] = nil
			r.step(1)
			if r.done then
				r.done()
			end
		else
			r.step(p)
		end
	end
	if next(running) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Plays step(p) for p from 0 to 1 over `duration` seconds under `key`, replacing whatever
-- ran there (that one neither finishes nor calls its done). step(0) runs at once.
function Motion.run(key: any, duration: number, step: (number) -> (), done: (() -> ())?)
	running[key] = { start = os.clock(), duration = duration, step = step, done = done }
	step(0)
	if duration <= 0 then
		frame()
		return
	end
	if not connection then
		connection = RunService.Heartbeat:Connect(frame)
	end
end

-- Stops the motion under `key`; with `finish`, jumps it to its end and calls its done.
function Motion.stop(key: any, finish: boolean?)
	local r = running[key]
	if not r then
		return
	end
	running[key] = nil
	if finish then
		r.step(1)
		if r.done then
			r.done()
		end
	end
end

function Motion.isRunning(key: any): boolean
	return running[key] ~= nil
end

------------------------------------------------------------------------------------------
-- Primitives. Each owns one property group of one object.

-- The object's own presentation scale (a UIScale named MotionScale), made on first use.
function Motion.scale(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("MotionScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local made = Instance.new("UIScale")
	made.Name = "MotionScale"
	made.Parent = gui
	return made
end

-- One stable key per object and property group, so a new motion replaces the old one.
local groupKeys: { [Instance]: { [string]: { rest: any? } } } = setmetatable({}, { __mode = "k" }) :: any

local function keyOf(gui: Instance, group: string): { rest: any? }
	local byGroup = groupKeys[gui]
	if not byGroup then
		byGroup = {}
		groupKeys[gui] = byGroup
	end
	local key = byGroup[group]
	if not key then
		key = {}
		byGroup[group] = key
	end
	return key
end
Motion.keyOf = keyOf

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Press: the visual dips to T.pressScale at once; release returns it. The hit target is a
-- separate object and never moves. `scale` is the button visual's own UIScale.
function Motion.press(scale: UIScale)
	local from = scale.Scale
	hook("press")
	Motion.run(scale, Motion.T.pressIn, function(p)
		scale.Scale = lerp(from, Motion.T.pressScale, MotionPlan.easeOut(p))
	end)
end

function Motion.release(scale: UIScale)
	local from = scale.Scale
	Motion.run(scale, Motion.T.pressOut, function(p)
		scale.Scale = lerp(from, 1, MotionPlan.easeOut(p))
	end)
end

-- Pop: from `from` through one overshoot to `peak`, settling on exactly 1.
function Motion.pop(scale: UIScale, from: number, peak: number, duration: number, done: (() -> ())?)
	Motion.run(scale, duration, function(p)
		scale.Scale = MotionPlan.pop(p, from, peak)
	end, done)
end

-- Rise/settle: the object travels from `dy` px below (negative: above) its resting position
-- to rest. Only for objects a layout does not place.
-- The resting position is the one seen on the object's first settle.
function Motion.settle(gui: GuiObject, dy: number, duration: number, done: (() -> ())?)
	local key = keyOf(gui, "settle")
	key.rest = key.rest or gui.Position
	local rest: UDim2 = key.rest
	Motion.run(key, duration, function(p)
		gui.Position = rest + UDim2.fromOffset(0, dy * (1 - MotionPlan.easeOut(p)))
	end, done)
end

-- Puts an object back on its resting position (the one its first settle saw) and stops
-- any settle still running there.
function Motion.rest(gui: GuiObject)
	local key = keyOf(gui, "settle")
	Motion.stop(key, false)
	if key.rest then
		gui.Position = key.rest
	end
end

-- Group fade. A fader reads the resting transparency of every image, text and stroke under
-- `root` (and root itself) once, when it is made: hide() makes them all transparent at once,
-- show() fades them back to rest, rest() puts them back at once.
export type Fader = {
	hide: (Fader) -> (),
	show: (Fader, number, (() -> ())?) -> (),
	out: (Fader, number, (() -> ())?) -> (),
	rest: (Fader) -> (),
	key: any,
}

function Motion.fader(root: GuiObject): Fader
	local parts: { { inst: Instance, prop: string, rest: number } } = {}
	local function collect(inst: Instance)
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			table.insert(parts, { inst = inst, prop = "ImageTransparency", rest = inst.ImageTransparency })
		end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			table.insert(parts, { inst = inst, prop = "TextTransparency", rest = inst.TextTransparency })
			table.insert(parts, { inst = inst, prop = "TextStrokeTransparency", rest = inst.TextStrokeTransparency })
		end
		if inst:IsA("UIStroke") then
			table.insert(parts, { inst = inst, prop = "Transparency", rest = inst.Transparency })
		end
	end
	collect(root)
	for _, d in root:GetDescendants() do
		collect(d)
	end
	local key = keyOf(root, "fade")
	local function set(e: number)
		for _, part in parts do
			(part.inst :: any)[part.prop] = lerp(1, part.rest, e)
		end
	end
	return {
		key = key,
		hide = function(_f: Fader)
			Motion.stop(key, false)
			set(0)
		end,
		show = function(_f: Fader, duration: number, done: (() -> ())?)
			Motion.run(key, duration, function(p)
				set(MotionPlan.easeOut(p))
			end, done)
		end,
		-- Fades from fully shown to transparent (an exit).
		out = function(_f: Fader, duration: number, done: (() -> ())?)
			Motion.run(key, duration, function(p)
				set(1 - MotionPlan.easeOut(p))
			end, done)
		end,
		rest = function(_f: Fader)
			Motion.stop(key, false)
			set(1)
		end,
	}
end

-- Count-up: render(n) with n rising from 0 to `final` on the slowing curve, by elapsed time
-- (never one step per frame or per coin), ending on exactly `final`. `tick` (a hook name)
-- sounds at most T.tickRate times a second and is never queued.
function Motion.count(key: any, final: number, duration: number, render: (number) -> (), tick: string?, done: (() -> ())?)
	local shown = -1
	local ticker = MotionPlan.ticker()
	Motion.run(key, duration, function(p)
		local n = if p >= 1 then final else MotionPlan.countValue(final, p * duration, duration)
		if n ~= shown then
			local changed = shown >= 0
			shown = n
			render(n)
			if tick and MotionPlan.tick(ticker, os.clock(), changed) then
				hook(tick, n)
			end
		end
	end, done)
end

------------------------------------------------------------------------------------------
-- A presentation: named phases on one clock (MotionPlan timeline), one version token, and
-- one finish that every path (natural end, skip, cancel, rebuild) runs exactly once.

export type Presentation = {
	alive: boolean,
	keys: { any },
	finals: { () -> () },
	-- Starts `f` at `at` seconds unless the presentation has ended by then.
	at: (Presentation, number, () -> ()) -> (),
	-- Registers a motion key this presentation owns and the final state it must end on.
	own: (Presentation, any, () -> ()) -> (),
	-- Stops every owned motion and puts each owned property on its final value.
	finish: (Presentation) -> (),
	onFinished: (() -> ())?,
}

function Motion.presentation(): Presentation
	local self: Presentation
	self = {
		alive = true,
		keys = {},
		finals = {},
		at = function(pr: Presentation, t: number, f: () -> ())
			if t <= 0 then
				f()
				return
			end
			task.delay(t, function()
				if pr.alive then
					f()
				end
			end)
		end,
		own = function(pr: Presentation, key: any, final: () -> ())
			table.insert(pr.keys, key)
			table.insert(pr.finals, final)
		end,
		finish = function(pr: Presentation)
			if not pr.alive then
				return
			end
			pr.alive = false
			for _, key in pr.keys do
				Motion.stop(key, false)
			end
			for _, final in pr.finals do
				final()
			end
			if pr.onFinished then
				pr.onFinished()
			end
		end,
		onFinished = nil,
	}
	return self
end

return Motion

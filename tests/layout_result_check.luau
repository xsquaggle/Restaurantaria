-- Checks for slice 4's layout numbers (StationLayout) and result-card wording (ResultLines):
-- the phone Make frame and mat, tool contact points under rotation, the common oven framing,
-- and the result's grade parts, pay row and note order. Run offline with tests/offline/run.py
-- or from the Studio command bar after a sync. Numbers and text only: no layout engine,
-- rendering or input is exercised here (Studio captures cover those).

local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local StationLayout = require(Client.StationLayout)
local ResultLines = require(Client.ResultLines)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local failures = {}
local passed = 0
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end
local function near(name: string, got: number, want: number, tol: number?)
	check(name, math.abs(got - want) <= (tol or 1e-6), true)
	if math.abs(got - want) > (tol or 1e-6) then
		table.insert(failures, string.format("  (%s: %.6f vs %.6f)", name, got, want))
	end
end

------------------------------------------------------------------------------------------
-- Make frame on a 667x375 phone (landscape, Roblox top bar 58 px: root 667x317). Main's
-- numbers: nav 74 px, rail 180 px, strip from StationLayout.

local rootX, rootY = 667, 317
local strip = StationLayout.hintStripHeight(true, rootY)
check("phone strip", strip, 31)
local stationH = rootY - 74 - strip
check("phone station height", stationH, 212)
local L = StationLayout.make(rootX - 180, stationH, true)
check("phone frame F = 190 (agreed)", L.F, 190)
check("phone mat >= 211", L.mat >= 211, true)
check("phone mat", L.mat, 212)
-- A dough at the smallest full size (mean semi-axis sizeFullLow) is drawn F * 0.95 wide:
-- 180.5 px, so at least 180 (measured from the alpha bounds in Studio too).
check("phone crust >= 180 at full size", L.F * Config.Make.sizeFullLow >= 180, true)
check("phone board fits the station", L.mat <= stationH, true)
check("phone board clear of the tool column", L.cx - L.mat / 2 >= L.margin + L.gridW, true)
check("phone board inside the station width", L.cx + L.mat / 2 <= rootX - 180, true)

-- The same at 1920x1080 (top bar 58: root 1920x1022; nav round(1022 * 0.11) = 112, strip 51).
local hdStrip = StationLayout.hintStripHeight(false, 1022)
check("hd strip unchanged", hdStrip, 51)
local hdRail = math.clamp(math.round(1920 * 0.24), 280, 460)
local hdL = StationLayout.make(1920 - hdRail, 1022 - 112 - hdStrip, false)
-- The width decides at HD: F 661 px, as measured since Make slice 1.
check("hd frame unchanged by slice 4", hdL.F, 661)
check("hd mat = ceil(F / 0.9)", hdL.mat, math.ceil(hdL.F / 0.9 - 1e-9))

-- Before slice 4 the phone strip was 34 px: 209 px station, F 188, mat 209 (Astra's 188/209).
local old = StationLayout.make(rootX - 180, rootY - 74 - 34, true)
check("phone before: F 188", old.F, 188)
check("phone before: mat 209", old.mat, 209)

------------------------------------------------------------------------------------------
-- Tool contact: the contact anchor lands on the pointer at any tilt and size.

for _, case in {
	{ "ladle pour", StationLayout.LADLE_CONTACT, StationLayout.LADLE_POUR, 110 },
	{ "ladle spread", StationLayout.LADLE_CONTACT, StationLayout.LADLE_SPREAD, 110 },
	{ "scoop", StationLayout.SCOOP_CONTACT, StationLayout.SCOOP_TILT, 69 },
	{ "ladle hd", StationLayout.LADLE_CONTACT, StationLayout.LADLE_POUR, 384 },
	{ "flat", StationLayout.SCOOP_CONTACT, 0, 100 },
	{ "upside down", StationLayout.LADLE_CONTACT, 180, 100 },
} do
	local name, a, deg, size = case[1], case[2], case[3], case[4]
	local px, py = 300.5, 120.25
	local cx, cy = StationLayout.toolCentre(px, py, size, size, a.x, a.y, deg)
	-- Where Roblox draws the anchor: the centre plus the anchor's offset turned clockwise.
	local dx, dy = (a.x - 0.5) * size, (a.y - 0.5) * size
	local r = math.rad(deg)
	near(name .. ": contact on pointer x", cx + dx * math.cos(r) - dy * math.sin(r), px)
	near(name .. ": contact on pointer y", cy + dx * math.sin(r) + dy * math.cos(r), py)
end
local cx, cy = StationLayout.toolCentre(0, 0, 100, 100, 0.5, 0.35, 0)
near("scoop flat: centre below the bowl", cy, 15)
near("scoop flat: centred", cx, 0)
check("ladle pivot unchanged", StationLayout.LADLE_CONTACT.x == 0.49963 and StationLayout.LADLE_CONTACT.y == 0.74373, true)
check("ladle tilts are Astra's provisional", StationLayout.LADLE_POUR == 25 and StationLayout.LADLE_SPREAD == -10, true)

------------------------------------------------------------------------------------------
-- Oven framing: one rule for every pizza, whole inside the window, flatter than round.

for _, win in { { 180, 96 }, { 590, 330 }, { 600, 200 }, { 100, 100 } } do
	local w, h = StationLayout.ovenPizza(win[1], win[2])
	local o = StationLayout.OVEN
	check(string.format("oven %dx%d: inside width", win[1], win[2]), w <= win[1] + 1e-9, true)
	check(string.format("oven %dx%d: inside height", win[1], win[2]), h / 2 <= math.min(o.centreY, 1 - o.centreY) * win[2] + 1e-9, true)
	near(string.format("oven %dx%d: flatten", win[1], win[2]), h / w, o.flatten)
end
check("oven flatten eased from 0.58", StationLayout.OVEN.flatten > 0.58 and StationLayout.OVEN.flatten < 1, true)

------------------------------------------------------------------------------------------
-- Result card wording.

local function part(score: number, notes: { string }?, detail: any?): any
	return { score = score, notes = notes or {}, detail = detail }
end
local function result(over: { [string]: any }): any
	local r = {
		join = "split",
		overall = 100,
		tip = 12,
		wait = part(100),
		make = part(99),
		bake = part(100),
		cut = part(100),
	}
	for k, v in over do
		r[k] = v
	end
	return r
end

local m = ResultLines.model(result({}), "Bo")
check("title", m.title, "Bo · 100%")
check("split: three grade parts", #m.parts, 3)
check("split: parts order", m.parts[1].name .. m.parts[2].name .. m.parts[3].name, "MakeBakeCut")
check("split: service not a grade part", m.parts[4], nil)
check("split: pay row", m.pay, "+12 coins · Service 100")
check("perfect: no notes", #m.notes, 0)

m = ResultLines.model(result({ tip = 1, wait = part(62, { "Waited longer than they liked" }) }), "Ana")
check("pay singular", m.pay, "+1 coin · Service 62")
check("wait note kept", m.notes[1], "Waited longer than they liked")

m = ResultLines.model(result({ join = "average", wait = part(80) }), "Cy")
check("average: wait is a grade part", m.parts[1].name, "Wait")
check("average: four parts", #m.parts, 4)
check("average: pay coins only", m.pay, "+12 coins")

-- A held grade: the food problem first, the hold after it, whatever part held it.
m = ResultLines.model(result({
	overall = 35,
	make = part(89, { "Cheese piled in one spot: grade held to 35", "Cheese was bunched" }),
}), "Di")
check("held: problem first", m.notes[1], "Cheese piled in one spot")
check("held: hold second", m.notes[2], "That held the grade to 35")
check("held: other notes after", m.notes[3], "Cheese was bunched")

m = ResultLines.model(result({
	overall = 35,
	make = part(70, { "Dough too small" }),
	bake = part(0, { "Burnt: grade held to 35" }),
}), "Ed")
check("held in bake: problem first", m.notes[1], "Burnt")
check("held in bake: hold second", m.notes[2], "That held the grade to 35")
check("held in bake: make note after", m.notes[3], "Dough too small")

local p, h = ResultLines.splitHeld("Too little sauce: Make held to 60")
check("split make hold: problem", p, "Too little sauce")
check("split make hold: hold", h, "That held Make to 60")
p, h = ResultLines.splitHeld("Slices were uneven sizes")
check("plain note unchanged", p, "Slices were uneven sizes")
check("plain note: no hold", h, nil)

-- Crust spill gets a text reason even when the sauce is not the weakest step.
local sauceDetail = { sauce = { score = 80, notes = { "Sauce on the crust" } } }
m = ResultLines.model(result({ make = part(85, { "Dough too small" }, sauceDetail) }), "Fi")
check("crust: named", table.find(m.notes, "Sauce on the crust") ~= nil, true)
check("crust: after the first note", m.notes[2], "Sauce on the crust")
m = ResultLines.model(result({ make = part(85, { "Sauce on the crust" }, sauceDetail) }), "Fi")
check("crust: not twice", #m.notes, 1)
m = ResultLines.model(result({
	overall = 35,
	make = part(60, { "Too little cheese: grade held to 35" }, sauceDetail),
}), "Gu")
check("crust after hold pair", m.notes[3], "Sauce on the crust")

-- Never more than three notes.
m = ResultLines.model(result({
	make = part(60, { "a", "b" }),
	bake = part(60, { "c" }),
	cut = part(60, { "d", "e" }),
}), "Ha")
check("notes capped", #m.notes, ResultLines.MAX_NOTES)
check("notes take turns", table.concat(m.notes, ""), "acd")

local report = string.format("layout and result checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(report .. "\n" .. table.concat(failures, "\n"))
end
return report

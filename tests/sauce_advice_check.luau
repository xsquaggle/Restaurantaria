-- Sauce off the edible area is advice, never a stop (Lawson 2026-10-28, real mouse: "Sauce on
-- the board, tap Undo" and "sauce on the crust" were way too strict). Slice 7a replaces the
-- first shift's "tap Undo" pointers with one plain line (MakeSauce.advice, Astra r19's copy) on
-- every shift, keeps Next available, and leaves the cost to the grade's clean part, unchanged
-- (Config.Sauce cleanWeight 0.2, offWeight 2). Records as in sauce_cover_check.

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local MakeSauce = require(Shared.MakeSauce)

local failures = {}
local passed = 0
local report = {}
local function check(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		table.insert(failures, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

local cfg = Config.Sauce
check("weights unchanged: amount", cfg.amountWeight, 0.3)
check("weights unchanged: cover", cfg.coverWeight, 0.5)
check("weights unchanged: clean", cfg.cleanWeight, 0.2)
check("weights unchanged: off the dough counts twice", cfg.offWeight, 2)
local has = type(MakeSauce.advice) == "function"
check("the advice is shared logic (MakeSauce.advice)", has, true)

local function P(x: number, y: number)
	return { x = x, y = y }
end
local function circle(r: number): { any }
	local out = {}
	for i = 0, 40 do
		local a = 2 * math.pi * i / 40
		out[i + 1] = P(r * math.cos(a), r * math.sin(a))
	end
	return out
end
local function slice(list: { any }, a: number, b: number): { any }
	local out = {}
	for i = a, b do
		table.insert(out, list[i])
	end
	return out
end
local function sauceOf(pours: { any }, spreads: { { any } }): any
	local actions = {}
	for _, p in pours do
		table.insert(actions, { kind = "pour", x = p.x, y = p.y })
	end
	for _, s in spreads do
		table.insert(actions, { kind = "spread", points = s })
	end
	return { actions = actions }
end
local tri = {}
for i, deg in { 90, 210, 330 } do
	tri[i] = P(0.4 * math.cos(math.rad(deg)), 0.4 * math.sin(math.rad(deg)))
end
local six = {}
for k = 0, 5 do
	six[k + 1] = P(0.45 * math.cos(math.rad(60 * k)), 0.45 * math.sin(math.rad(60 * k)))
end
local wide = circle(1.1)

local records = {
	{ "even adequate", sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7) }), nil },
	{ "rim spill", sauceOf(tri, { circle(0.3), circle(0.5), circle(0.7), circle(0.88) }), "any" },
	{ "board spill", sauceOf(tri, { circle(0.3), circle(0.6), circle(0.9), slice(wide, 1, 21), slice(wide, 21, 41) }), "spill" },
	-- sauce_cheese_check's heavy record: sauce on the crust, none off the dough.
	{ "crust, no spill", sauceOf(six, { circle(0.2), circle(0.4), circle(0.6), circle(0.75) }), "crust" },
	{ "one pour, not spread", sauceOf({ P(0.2, 0) }, {}), nil },
}
table.insert(report, "record          Next   advice                                          sauce  clean  crust   off    clean part costs")
for _, rec in records do
	local name, sauce, want = rec[1], rec[2], rec[3]
	local g = MakeSauce.grade(sauce)
	local advice = if has then MakeSauce.advice(sauce) else nil
	local cost = 100 * cfg.cleanWeight * (1 - g.detail.clean)
	if name == "one pour, not spread" then
		check(name .. ": Next not yet (the step's minimum)", MakeSauce.canFinish(sauce), false)
		check(name .. ": no advice before the minimum", advice, nil)
	else
		check(name .. ": Next available", MakeSauce.canFinish(sauce), true)
		if want == nil then
			check(name .. ": no advice", advice, nil)
		elseif want == "crust" then
			check(name .. ": crust advice", advice, "A little sauce on the crust. You can continue.")
			check(name .. ": crust note in the grade", table.find(g.notes, "Sauce on the crust") ~= nil, true)
			check(name .. ": nothing off the dough", g.detail.off, 0)
		elseif want == "spill" then
			check(name .. ": spill advice", advice, "Some sauce spilled. You can continue or undo.")
			check(name .. ": spill note in the grade", table.find(g.notes, "Sauce spilled off the dough") ~= nil, true)
		else
			check(name .. ": some advice", advice ~= nil, true)
		end
		-- The grade is the stated weights, nothing subtracted twice.
		local amount = math.clamp(1 - math.abs(g.detail.pours - cfg.targetPours) / cfg.targetPours, 0, 1)
		local expect = math.floor(100 * (cfg.amountWeight * amount + cfg.coverWeight * g.detail.coverage + cfg.cleanWeight * g.detail.clean) + 0.5 + 1e-9)
		check(name .. ": grade = the stated weights", g.score, expect)
	end
	table.insert(report, string.format("%-15s %-6s %-47s %5d  %.3f  %.3f  %.3f  %.1f sauce points", name, tostring(MakeSauce.canFinish(sauce)), tostring(advice), g.score, g.detail.clean, g.detail.crust, g.detail.off, cost))
end

for _, l in report do
	print("  " .. l)
end
local summary = string.format("sauce advice checks: %d passed, %d failed", passed, #failures)
if #failures > 0 then
	error(summary .. "\n" .. table.concat(failures, "\n"))
end
return summary

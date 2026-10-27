-- Table-driven checks for the pure grading functions in ReplicatedStorage.Shared.Scoring.
-- Run from the Studio command bar (or the Studio MCP in Edit mode) after a sync; returns a
-- report and errors if any case fails.

local Shared = game:GetService("ReplicatedStorage").Shared
local Scoring = require(Shared.Scoring)
local Recipes = require(Shared.Recipes)
local Config = require(Shared.Config)

-- n pieces of one ingredient evenly round a ring, optionally limited to one half.
local function ring(ingredient: string, n: number, radius: number, half: string?)
	local out = {}
	for i = 1, n do
		local a
		if half then
			-- Spread over the half's arc, top to bottom.
			local t = (i - 0.5) / n
			a = math.rad(if half == "left" then 90 + t * 180 else -90 + t * 180)
		else
			a = math.rad(22.5 + (i - 1) * 360 / n)
		end
		table.insert(out, { ingredient = ingredient, x = math.cos(a) * radius, y = -math.sin(a) * radius })
	end
	return out
end

local function join(...)
	local out = {}
	for _, list in { ... } do
		for _, p in list do
			table.insert(out, p)
		end
	end
	return out
end

local function cluster(ingredient: string, n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { ingredient = ingredient, x = 0.3 + i * 0.02, y = 0.3 })
	end
	return out
end

local R = Recipes.ById
local cases = {
	{ "pepperoni: 8 even", R.pepperoni, ring("pepperoni", 8, 0.55), 100, 100 },
	{ "pepperoni: empty", R.pepperoni, {}, 0, 0 },
	{ "pepperoni: 8 in one quadrant", R.pepperoni, cluster("pepperoni", 8), 60, 60 },
	{ "pepperoni: 4 even", R.pepperoni, ring("pepperoni", 4, 0.55), 70, 70 },
	{ "garden: 6+6 even", R.garden, join(ring("mushroom", 6, 0.4), ring("pepper", 6, 0.65)), 100, 100 },
	{ "halfolive: 6 left + 4 right", R.halfolive, join(ring("olive", 6, 0.5, "left"), ring("pepperoni", 4, 0.5, "right")), 100, 100 },
	{ "halfolive: sides swapped", R.halfolive, join(ring("olive", 6, 0.5, "right"), ring("pepperoni", 4, 0.5, "left")), 0, 0 },
	{ "cheese: plain", R.cheese, {}, 100, 100 },
	{ "cheese: 1 stray pepperoni", R.cheese, ring("pepperoni", 1, 0.5), 92, 92 },
}

local lines, failed = {}, 0
for _, c in cases do
	local name, recipe, pieces, lo, hi = c[1], c[2], c[3], c[4], c[5]
	local g = Scoring.toppings(recipe, pieces)
	local pass = g.score >= lo and g.score <= hi
	if not pass then
		failed += 1
	end
	table.insert(lines, string.format("%s %-30s %3d  (want %d-%d)  %s", if pass then "ok  " else "FAIL", name, g.score, lo, hi, table.concat(g.notes, "; ")))
end

-- Bake boundary sweep: each bake's grade and state just inside and outside its perfect
-- window, at the gauge's band edges, and either side of the absolute burnt line.
local bakeCases = {
	{ "light", 15.9, "under" }, { "light", 16, "perfect" }, { "light", 20, "perfect" }, { "light", 20.1, "over" },
	{ "regular", 21.9, "under" }, { "regular", 22, "perfect" }, { "regular", 26, "perfect" }, { "regular", 26.1, "over" },
	{ "well", 27.9, "under" }, { "well", 28, "perfect" }, { "well", 32, "perfect" }, { "well", 32.1, "over" },
	{ "light", 36, "over" }, { "light", 36.1, "burnt" }, { "well", 36, "over" }, { "well", 36.1, "burnt" },
}
for _, c in bakeCases do
	local bake, seconds, want = c[1], c[2], c[3]
	local state = Scoring.bakeState(Config.Oven.targets[bake], seconds)
	local g = Scoring.bake(bake, seconds)
	-- Burnt: today's rule scores Bake 0; with the food-state hold (Config.Oven.foodCapOn, slice 1)
	-- the Bake score stays the distance from the asked doneness and the grade is held to foodCap.
	local burntOk = if Config.Oven.foodCapOn then g.detail.cap == Config.Oven.foodCap else g.score == 0
	local pass = state == want and (want ~= "perfect" or g.score == 100) and (want ~= "burnt" or burntOk)
	if not pass then
		failed += 1
	end
	table.insert(lines, string.format("%s bake %-8s %5.1fs %-8s %3d  (want %s)", if pass then "ok  " else "FAIL", bake, seconds, state, g.score, want))
end
local report = table.concat(lines, "\n")
if failed > 0 then
	error(string.format("%d scoring check(s) failed\n%s", failed, report))
end
return report

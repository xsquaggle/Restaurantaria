-- Checks for the unlocked-recipe menu in ReplicatedStorage.Shared.Recipes (orders and trays
-- follow a save's unlocked recipes). Run from the Studio command bar (or the Studio MCP in
-- Edit mode) after a sync; returns a report and errors if any case fails.

local Shared = game:GetService("ReplicatedStorage").Shared
local Recipes = require(Shared.Recipes)
local Config = require(Shared.Config)

local failures, lines = 0, {}
local function check(name: string, ok: boolean, detail: string?)
	if not ok then
		failures += 1
	end
	table.insert(lines, (if ok then "ok   " else "FAIL ") .. name .. (if detail then "  " .. detail else ""))
end

check("starting recipes are cheese only", #Recipes.Starting == 1 and Recipes.Starting[1] == "cheese")
check("mixed orders off by default", Config.Dev.mixedOrders == false)

-- A cheese-only menu: every order is cheese and keeps ShiftOrders' doneness and slices.
local all = true
local seen = {}
for i = 1, #Recipes.ShiftOrders * 2 do
	local o = Recipes.menuOrder(Recipes.Starting, i)
	local def = Recipes.ShiftOrders[((i - 1) % #Recipes.ShiftOrders) + 1]
	all = all and o.recipe == "cheese" and o.bake == def.bake and o.slices == def.slices
	table.insert(seen, string.format("%s/%s/%d", o.recipe, o.bake, o.slices))
end
check("cheese menu: cheese orders with the scripted doneness and slices", all, table.concat(seen, " ", 1, #Recipes.ShiftOrders))
check("cheese menu needs no trays", #Recipes.ingredientsFor(Recipes.Starting) == 0)

-- The full menu reproduces the scripted mixed shift exactly.
local same = true
for i, def in Recipes.ShiftOrders do
	local o = Recipes.menuOrder(Recipes.all(), i)
	same = same and o.recipe == def.recipe and o.bake == def.bake and o.slices == def.slices
end
check("full menu = scripted mixed orders", same)
check("full menu uses every tray", #Recipes.ingredientsFor(Recipes.all()) == #Recipes.IngredientOrder)

-- A later menu: locked recipes are replaced in turn by unlocked ones, nothing locked appears.
local menu = { "cheese", "pepperoni" }
local onlyMenu = true
for i = 1, 12 do
	onlyMenu = onlyMenu and table.find(menu, Recipes.menuOrder(menu, i).recipe) ~= nil
end
check("cheese + pepperoni menu stays on the menu", onlyMenu)
local trays = Recipes.ingredientsFor(menu)
check("cheese + pepperoni needs the pepperoni tray only", #trays == 1 and trays[1] == "pepperoni", table.concat(trays, ","))

check("known() drops unknown ids and repeats, keeps list order", table.concat(Recipes.known({ "garden", "nope", "cheese", "garden" }), ",") == "cheese,garden")

local report = string.format("%d checks, %d failed\n%s", #lines, failures, table.concat(lines, "\n"))
if failures > 0 then
	error(report)
end
return report

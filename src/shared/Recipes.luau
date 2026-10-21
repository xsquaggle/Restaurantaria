--!strict
-- Ingredients, recipes and the starter cast. `art` names the sprite set (art/manifest.json:
-- topping_<art>_1..3 on the pizza, tray_<art> in the bin) and `size` is a piece's on-pizza
-- width as a fraction of the pizza's diameter. colour/shape remain for the bake and cut
-- stations' greybox pizza until their art exists.

export type Requirement = { ingredient: string, count: number, region: string }
export type Recipe = { id: string, name: string, toppings: { Requirement } }

local Recipes = {}

Recipes.Ingredients = {
	pepperoni = { name = "Pepperoni", plural = "pepperoni", art = "pepperoni", size = 0.16, colour = Color3.fromRGB(184, 58, 42), shape = "disc" },
	mushroom = { name = "Mushroom", plural = "mushrooms", art = "mushroom", size = 0.15, colour = Color3.fromRGB(222, 205, 176), shape = "cap" },
	basil = { name = "Basil", plural = "basil leaves", art = "basil", size = 0.14, colour = Color3.fromRGB(78, 150, 58), shape = "disc" },
	olive = { name = "Olive", plural = "olives", art = "olive", size = 0.095, colour = Color3.fromRGB(52, 44, 48), shape = "ring" },
	-- One ingredient with green and red looks; colour never affects counts or grading.
	pepper = {
		name = "Bell pepper",
		short = "Pepper",
		plural = "bell peppers",
		art = "pepper",
		tray = "tray_pepper_mixed",
		variants = { "topping_pepper_1", "topping_pepper_2", "topping_pepper_3", "topping_pepper_red_1", "topping_pepper_red_2", "topping_pepper_red_3" },
		size = 0.14,
		colour = Color3.fromRGB(78, 140, 62),
		shape = "ring",
	},
}

-- Tray order on the topping counter, left to right (matches the approved reference).
Recipes.IngredientOrder = { "pepperoni", "mushroom", "basil", "olive", "pepper" }

-- Requested doneness as players read it on a ticket (Astra, 2026-10-19). Each has a live
-- label and its own icon from Astra's oven/pizza icon family, which pairs a colour with a
-- visible progression: light teal, regular green, well-done amber. Red is kept for burnt or
-- error and never marks a request. Extra well-done (orange) is pending: it has no oven target
-- or grading yet (Config.Oven.targets), so it is never offered.
Recipes.Doneness = {
	light = { label = "Light bake", short = "Light", tone = "teal", icon = "icon_bake_light" },
	regular = { label = "Regular bake", short = "Regular", tone = "green", icon = "icon_bake_regular" },
	well = { label = "Well done", short = "Well done", tone = "amber", icon = "icon_bake_well_done" },
}
Recipes.DonenessOrder = { "light", "regular", "well" }

-- Regions: "whole", "left", "right". Left/right are halves split by the vertical axis.
Recipes.List = {
	{ id = "cheese", name = "Cheese", toppings = {} },
	{ id = "pepperoni", name = "Pepperoni", toppings = { { ingredient = "pepperoni", count = 8, region = "whole" } } },
	{ id = "garden", name = "Garden", toppings = {
		{ ingredient = "mushroom", count = 6, region = "whole" },
		{ ingredient = "pepper", count = 6, region = "whole" },
	} },
	{ id = "halfolive", name = "Half & Half", toppings = {
		{ ingredient = "olive", count = 6, region = "left" },
		{ ingredient = "pepperoni", count = 4, region = "right" },
	} },
	{ id = "pepbasil", name = "Pepperoni Basil", toppings = {
		{ ingredient = "pepperoni", count = 6, region = "whole" },
		{ ingredient = "basil", count = 4, region = "whole" },
	} },
} :: { Recipe }

Recipes.ById = {} :: { [string]: Recipe }
for _, recipe in Recipes.List do
	Recipes.ById[recipe.id] = recipe
end

-- The scripted order list for this scene: recipe, doneness, slice count. An order keeps its
-- doneness and slices on every save; its recipe is used only while it is unlocked
-- (Recipes.menuOrder).
Recipes.ShiftOrders = {
	{ recipe = "pepperoni", bake = "regular", slices = 8 },
	{ recipe = "garden", bake = "light", slices = 6 },
	{ recipe = "halfolive", bake = "well", slices = 4 },
	{ recipe = "cheese", bake = "regular", slices = 8 },
	{ recipe = "pepbasil", bake = "regular", slices = 6 },
	{ recipe = "pepperoni", bake = "well", slices = 4 },
}

-- Recipes a new save starts with (Lawson, 2026-10-21: new players begin with cheese pizza).
-- Each save keeps its own unlocked list (SaveService); the progression system adds to it.
-- Orders and the topping trays follow that list, so nothing is asked for before it is
-- unlocked.
Recipes.Starting = { "cheese" }

-- Known recipe ids from a list, in Recipes.List order and without repeats.
function Recipes.known(ids: { any }): { string }
	local out = {}
	for _, recipe in Recipes.List do
		if table.find(ids, recipe.id) then
			table.insert(out, recipe.id)
		end
	end
	return out
end

-- Every recipe id, for the development setting that mixes all recipes into the orders.
function Recipes.all(): { string }
	local out = {}
	for _, recipe in Recipes.List do
		table.insert(out, recipe.id)
	end
	return out
end

-- The ingredients a set of recipes uses, in tray order.
function Recipes.ingredientsFor(recipeIds: { string }): { string }
	local used = {}
	for _, id in recipeIds do
		local recipe = Recipes.ById[id]
		if recipe then
			for _, req in recipe.toppings do
				used[req.ingredient] = true
			end
		end
	end
	local out = {}
	for _, ingredient in Recipes.IngredientOrder do
		if used[ingredient] then
			table.insert(out, ingredient)
		end
	end
	return out
end

-- The i-th order of a shift whose menu is `menu` (recipe ids). The order keeps its doneness
-- and slices from ShiftOrders, and its recipe while that is on the menu; otherwise the menu's
-- recipes take turns.
function Recipes.menuOrder(menu: { string }, i: number): { recipe: string, bake: string, slices: number }
	local def = Recipes.ShiftOrders[((i - 1) % #Recipes.ShiftOrders) + 1]
	local recipe = if table.find(menu, def.recipe) then def.recipe else menu[((i - 1) % #menu) + 1]
	return { recipe = recipe, bake = def.bake, slices = def.slices }
end

Recipes.Cast = {
	{ name = "Marta", colour = Color3.fromRGB(214, 120, 96) },
	{ name = "Bo", colour = Color3.fromRGB(96, 148, 186) },
	{ name = "Ines", colour = Color3.fromRGB(150, 118, 186) },
}

return Recipes

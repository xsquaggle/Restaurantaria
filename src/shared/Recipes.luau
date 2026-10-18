--!strict
-- Ingredients, recipes and the starter cast. Placeholder visuals are described here so the
-- client can draw greybox food until illustrated sprites exist.

export type Requirement = { ingredient: string, count: number, region: string }
export type Recipe = { id: string, name: string, toppings: { Requirement } }

local Recipes = {}

Recipes.Ingredients = {
	pepperoni = { name = "Pepperoni", plural = "pepperoni", colour = Color3.fromRGB(184, 58, 42), size = 0.13, shape = "disc" },
	mushroom = { name = "Mushroom", plural = "mushrooms", colour = Color3.fromRGB(222, 205, 176), size = 0.11, shape = "cap" },
	olive = { name = "Olive", plural = "olives", colour = Color3.fromRGB(52, 44, 48), size = 0.08, shape = "ring" },
	pepper = { name = "Green pepper", short = "Pepper", plural = "green peppers", colour = Color3.fromRGB(78, 140, 62), size = 0.10, shape = "ring" },
	onion = { name = "Onion", plural = "onions", colour = Color3.fromRGB(205, 170, 205), size = 0.10, shape = "ring" },
}

Recipes.IngredientOrder = { "pepperoni", "mushroom", "olive", "pepper", "onion" }

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
	{ id = "onionpep", name = "Onion Pepperoni", toppings = {
		{ ingredient = "pepperoni", count = 6, region = "whole" },
		{ ingredient = "onion", count = 6, region = "whole" },
	} },
} :: { Recipe }

Recipes.ById = {} :: { [string]: Recipe }
for _, recipe in Recipes.List do
	Recipes.ById[recipe.id] = recipe
end

-- The scripted order list for this scene: recipe, doneness, slice count.
Recipes.ShiftOrders = {
	{ recipe = "pepperoni", bake = "regular", slices = 8 },
	{ recipe = "garden", bake = "light", slices = 6 },
	{ recipe = "halfolive", bake = "well", slices = 4 },
	{ recipe = "cheese", bake = "regular", slices = 8 },
	{ recipe = "onionpep", bake = "regular", slices = 6 },
	{ recipe = "pepperoni", bake = "well", slices = 4 },
}

Recipes.Cast = {
	{ name = "Marta", colour = Color3.fromRGB(214, 120, 96) },
	{ name = "Bo", colour = Color3.fromRGB(96, 148, 186) },
	{ name = "Ines", colour = Color3.fromRGB(150, 118, 186) },
}

return Recipes

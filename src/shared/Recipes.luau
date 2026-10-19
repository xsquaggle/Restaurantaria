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

-- The scripted order list for this scene: recipe, doneness, slice count.
Recipes.ShiftOrders = {
	{ recipe = "pepperoni", bake = "regular", slices = 8 },
	{ recipe = "garden", bake = "light", slices = 6 },
	{ recipe = "halfolive", bake = "well", slices = 4 },
	{ recipe = "cheese", bake = "regular", slices = 8 },
	{ recipe = "pepbasil", bake = "regular", slices = 6 },
	{ recipe = "pepperoni", bake = "well", slices = 4 },
}

Recipes.Cast = {
	{ name = "Marta", colour = Color3.fromRGB(214, 120, 96) },
	{ name = "Bo", colour = Color3.fromRGB(96, 148, 186) },
	{ name = "Ines", colour = Color3.fromRGB(150, 118, 186) },
}

return Recipes

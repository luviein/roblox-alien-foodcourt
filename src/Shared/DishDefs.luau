--!strict
-- Data-driven dish definitions. Adding a dish is a table entry, never new code.
--
-- KEY CONVENTION (shared across every assembly dish, so muscle memory carries):
--   Q = base       (bun / tortilla / shell)
--   A = protein    (patty / sausage / beef)
--   S D F = toppings
--   W = lid        (top bun, if the dish has one)
--
-- Tags and workload are unused in P0 -- they are the hooks the environment
-- system in P2 plugs into. They live here now so dishes never need rewriting.

export type Component = {
	key: string,
	id: string,
	required: boolean,
}

export type Dish = {
	id: string,
	displayName: string,
	alienName: string,
	archetype: string,
	baseValue: number,
	orderStrict: boolean,
	components: { Component },
	timing: { perfect: number, good: number, sloppy: number },
	tags: { string },
	workload: { [string]: number },
}

local DishDefs = {}

-- Display metadata only -- colour is used for the grey-box UI chips.
DishDefs.Ingredients = {
	bun_bottom = { name = "Bottom Bun", color = Color3.fromRGB(206, 162, 96) },
	bun_top    = { name = "Top Bun",    color = Color3.fromRGB(224, 180, 110) },
	patty      = { name = "Patty",      color = Color3.fromRGB(102, 66, 46) },
	cheese     = { name = "Cheese",     color = Color3.fromRGB(240, 190, 60) },
	lettuce    = { name = "Lettuce",    color = Color3.fromRGB(120, 190, 90) },
	pickle     = { name = "Pickle",     color = Color3.fromRGB(96, 150, 70) },

	hotdog_bun = { name = "Split Bun",  color = Color3.fromRGB(214, 170, 104) },
	sausage    = { name = "Sausage",    color = Color3.fromRGB(170, 84, 66) },
	onion      = { name = "Onion",      color = Color3.fromRGB(226, 214, 196) },
	ketchup    = { name = "Ketchup",    color = Color3.fromRGB(198, 52, 48) },
	mustard    = { name = "Mustard",    color = Color3.fromRGB(226, 186, 48) },

	tortilla   = { name = "Tortilla",   color = Color3.fromRGB(228, 206, 158) },
	beef       = { name = "Beef",       color = Color3.fromRGB(122, 74, 50) },
	salsa      = { name = "Salsa",      color = Color3.fromRGB(186, 60, 46) },
}

DishDefs.Dishes = {
	burger = {
		id = "burger",
		displayName = "Cheeseburger",
		alienName = "the layered brown disc",
		archetype = "Assembly",
		baseValue = 45,
		orderStrict = true,
		components = {
			{ key = "Q", id = "bun_bottom", required = true },
			{ key = "A", id = "patty",      required = true },
			{ key = "S", id = "cheese",     required = false },
			{ key = "D", id = "lettuce",    required = false },
			{ key = "F", id = "pickle",     required = false },
			{ key = "W", id = "bun_top",    required = true },
		},
		timing = { perfect = 7, good = 11, sloppy = 16 },
		tags = { "Hot", "Savory", "Greasy" },
		workload = { dishLoad = 1, trashLoad = 2, greaseLoad = 2, messRisk = 1, prepTime = 2 },
	},

	hotdog = {
		id = "hotdog",
		displayName = "Hot Dog",
		alienName = "the tube in the trench",
		archetype = "Assembly",
		baseValue = 32,
		orderStrict = true,
		components = {
			{ key = "Q", id = "hotdog_bun", required = true },
			{ key = "A", id = "sausage",    required = true },
			{ key = "S", id = "onion",      required = false },
			{ key = "D", id = "ketchup",    required = false },
			{ key = "F", id = "mustard",    required = false },
		},
		timing = { perfect = 5, good = 8, sloppy = 12 },
		tags = { "Hot", "Savory", "Greasy" },
		workload = { dishLoad = 1, trashLoad = 3, greaseLoad = 1, messRisk = 2, prepTime = 1 },
	},

	taco = {
		id = "taco",
		displayName = "Taco",
		alienName = "the folded field rations",
		archetype = "Assembly",
		baseValue = 38,
		orderStrict = true,
		components = {
			{ key = "Q", id = "tortilla", required = true },
			{ key = "A", id = "beef",     required = true },
			{ key = "S", id = "cheese",   required = false },
			{ key = "D", id = "lettuce",  required = false },
			{ key = "F", id = "salsa",    required = false },
		},
		timing = { perfect = 6, good = 9, sloppy = 14 },
		tags = { "Hot", "Fresh", "Savory" },
		workload = { dishLoad = 1, trashLoad = 2, greaseLoad = 1, messRisk = 2, prepTime = 2 },
	},
}

-- What can show up on tickets in P0. Later this becomes the player's drafted menu.
DishDefs.ActiveMenu = { "burger", "hotdog", "taco" }

function DishDefs.get(dishId: string): Dish?
	return DishDefs.Dishes[dishId]
end

function DishDefs.ingredientName(id: string): string
	local ing = DishDefs.Ingredients[id]
	return ing and ing.name or id
end

function DishDefs.ingredientColor(id: string): Color3
	local ing = DishDefs.Ingredients[id]
	return ing and ing.color or Color3.fromRGB(140, 140, 140)
end

return DishDefs

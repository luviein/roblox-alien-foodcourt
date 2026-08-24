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
--
-- `visual` describes how the ingredient is built in 3D on the plate:
--   shape : "cylinder" | "block" | "dome" | "rod"
--   size  : stud dimensions (x,z = footprint, y = thickness)
--   rise  : how far the stack grows after adding this layer
--   tilt  : degrees of random tilt, for a draped/hand-made look
-- Swapping any of these for a MeshPart later is a one-line change in FoodStack.

local DishDefs = {}

DishDefs.Ingredients = {
	bun_bottom = {
		name = "Bottom Bun", color = Color3.fromRGB(206, 162, 96),
		visual = { shape = "cylinder", size = Vector3.new(2.4, 0.45, 2.4), rise = 0.45, tilt = 0 },
	},
	bun_top = {
		name = "Top Bun", color = Color3.fromRGB(224, 180, 110),
		visual = { shape = "dome", size = Vector3.new(2.4, 1.1, 2.4), rise = 0.7, tilt = 0 },
	},
	patty = {
		name = "Patty", color = Color3.fromRGB(102, 66, 46),
		visual = { shape = "cylinder", size = Vector3.new(2.2, 0.42, 2.2), rise = 0.42, tilt = 3 },
	},
	cheese = {
		name = "Cheese", color = Color3.fromRGB(240, 190, 60),
		visual = { shape = "block", size = Vector3.new(2.3, 0.12, 2.3), rise = 0.14, tilt = 7 },
	},
	lettuce = {
		name = "Lettuce", color = Color3.fromRGB(120, 190, 90),
		visual = { shape = "cylinder", size = Vector3.new(2.6, 0.2, 2.6), rise = 0.2, tilt = 5 },
	},
	pickle = {
		name = "Pickle", color = Color3.fromRGB(96, 150, 70),
		visual = { shape = "cylinder", size = Vector3.new(1.1, 0.14, 1.1), rise = 0.14, tilt = 10 },
	},

	hotdog_bun = {
		name = "Split Bun", color = Color3.fromRGB(214, 170, 104),
		visual = { shape = "block", size = Vector3.new(3.0, 0.5, 1.3), rise = 0.5, tilt = 0 },
	},
	sausage = {
		name = "Sausage", color = Color3.fromRGB(170, 84, 66),
		visual = { shape = "rod", size = Vector3.new(0.55, 2.8, 0.55), rise = 0.5, tilt = 0 },
	},
	onion = {
		name = "Onion", color = Color3.fromRGB(226, 214, 196),
		visual = { shape = "block", size = Vector3.new(2.4, 0.12, 0.85), rise = 0.14, tilt = 6 },
	},
	ketchup = {
		name = "Ketchup", color = Color3.fromRGB(198, 52, 48),
		visual = { shape = "block", size = Vector3.new(2.2, 0.1, 0.28), rise = 0.11, tilt = 4 },
	},
	mustard = {
		name = "Mustard", color = Color3.fromRGB(226, 186, 48),
		visual = { shape = "block", size = Vector3.new(2.2, 0.1, 0.28), rise = 0.11, tilt = 4 },
	},

	-- Fryer steps. No `visual`, so nothing is stacked on the plate for these --
	-- they are actions, not ingredients, and FoodStack skips anything without
	-- a visual. Reusing the ingredient system means the fryer needs no separate
	-- input handling: it is a key sequence like any other dish.
	basket_load  = { name = "Load Basket",  color = Color3.fromRGB(196, 200, 214) },
	basket_shake = { name = "Shake Basket", color = Color3.fromRGB(168, 174, 192) },
	basket_lower = { name = "Lower Basket", color = Color3.fromRGB(232, 148, 62) },

	steak_raw = {
		name = "Raw Steak", color = Color3.fromRGB(150, 72, 72),
		visual = { shape = "cylinder", size = Vector3.new(2.5, 0.5, 2.0), rise = 0.5, tilt = 4 },
	},
	pancake_batter = {
		name = "Batter", color = Color3.fromRGB(232, 214, 172),
		visual = { shape = "cylinder", size = Vector3.new(2.6, 0.3, 2.6), rise = 0.3, tilt = 2 },
	},

	tortilla = {
		name = "Tortilla", color = Color3.fromRGB(228, 206, 158),
		visual = { shape = "cylinder", size = Vector3.new(2.7, 0.14, 2.7), rise = 0.14, tilt = 0 },
	},
	beef = {
		name = "Beef", color = Color3.fromRGB(122, 74, 50),
		visual = { shape = "cylinder", size = Vector3.new(2.1, 0.32, 2.1), rise = 0.32, tilt = 4 },
	},
	salsa = {
		name = "Salsa", color = Color3.fromRGB(186, 60, 46),
		visual = { shape = "cylinder", size = Vector3.new(1.9, 0.16, 1.9), rise = 0.16, tilt = 8 },
	},
}

DishDefs.Dishes = {
	burger = {
		id = "burger",
		displayName = "Cheeseburger",
		alienName = "the layered brown disc",
		station = "Prep",
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
		station = "Prep",
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
		station = "Prep",
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

	-- Fryer dishes. The components are the prep steps -- load, shake, lower --
	-- so the fryer reuses the assembly input rather than needing its own.
	-- Completing the sequence lowers the basket and cooking starts.
	--
	--   cookTime  : seconds until the basket is ready
	--   perfect   : seconds after ready that still counts as Perfect
	--   good      : ... as Good. Past that and up to `burn` is Sloppy.
	--   burn      : seconds after ready before it is ruined outright
	fries = {
		id = "fries",
		displayName = "Fries",
		alienName = "the salted golden splinters",
		station = "Fryer",
		archetype = "Fry",
		baseValue = 28,
		orderStrict = true,
		components = {
			{ key = "Q", id = "basket_load",  required = true },
			{ key = "W", id = "basket_lower", required = true },
		},
		fry = { cookTime = 3, perfect = 1.5, good = 3, burn = 6 },
		tags = { "Hot", "Fried", "Greasy" },
		workload = { dishLoad = 0, trashLoad = 2, greaseLoad = 3, messRisk = 1, prepTime = 1 },
	},

	onion_rings = {
		id = "onion_rings",
		displayName = "Onion Rings",
		alienName = "the crunchy orbits",
		station = "Fryer",
		archetype = "Fry",
		baseValue = 36,
		orderStrict = true,
		components = {
			{ key = "Q", id = "basket_load",  required = true },
			{ key = "W", id = "basket_lower", required = true },
		},
		fry = { cookTime = 4, perfect = 1.2, good = 2.5, burn = 5 },
		tags = { "Hot", "Fried", "Greasy" },
		workload = { dishLoad = 0, trashLoad = 2, greaseLoad = 3, messRisk = 1, prepTime = 1 },
	},

	-- Grill dishes. Prep steps get it onto the grill, then you HOLD the sear
	-- key and let go inside the band. The opposite pressure to the fryer: the
	-- fryer punishes you for not coming back, the grill punishes you for
	-- looking away at all.
	--
	--   duration    : seconds of holding to reach fully cooked (1.0)
	--   perfectFrom/To, goodFrom/To : fractions of duration
	--   Holding past 1.0 burns it outright.
	steak = {
		id = "steak",
		displayName = "Steak",
		alienName = "the seared slab",
		station = "Grill",
		archetype = "Sear",
		baseValue = 58,
		orderStrict = true,
		components = {
			{ key = "Q", id = "steak_raw", required = true },
		},
		sear = {
			key = "W",
			label = "SEAR (hold)",
			duration = 3.2,
			perfectFrom = 0.62, perfectTo = 0.86,
			goodFrom = 0.42, goodTo = 0.96,
		},
		tags = { "Hot", "Savory" },
		workload = { dishLoad = 2, trashLoad = 1, greaseLoad = 2, messRisk = 1, prepTime = 2 },
	},

	pancakes = {
		id = "pancakes",
		displayName = "Pancakes",
		alienName = "the stacked sun discs",
		station = "Grill",
		archetype = "Sear",
		baseValue = 42,
		orderStrict = true,
		components = {
			{ key = "Q", id = "pancake_batter", required = true },
		},
		sear = {
			key = "W",
			label = "GRIDDLE (hold)",
			duration = 2.4,
			-- A narrower band than steak: batter goes from pale to burnt fast.
			perfectFrom = 0.68, perfectTo = 0.84,
			goodFrom = 0.50, goodTo = 0.94,
		},
		tags = { "Hot", "Sweet" },
		workload = { dishLoad = 2, trashLoad = 1, greaseLoad = 1, messRisk = 1, prepTime = 2 },
	},
}

-- What can show up on tickets. Later this becomes the player's drafted menu.
DishDefs.ActiveMenu = {
	"burger", "hotdog", "taco",
	"fries", "onion_rings",
	"steak", "pancakes",
}

function DishDefs.stationOf(dishId: string): string?
	local dish = DishDefs.Dishes[dishId]
	return dish and dish.station or nil
end

function DishDefs.get(dishId: string)
	return DishDefs.Dishes[dishId]
end

function DishDefs.ingredient(id: string)
	return DishDefs.Ingredients[id]
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

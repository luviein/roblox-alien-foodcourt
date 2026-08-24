--!strict
-- What cash can be spent on: dishes, and permanent upgrades.
--
-- The rule every upgrade here follows: RAISE THE CEILING, DO NOT LOWER THE
-- FLOOR. An extra order slot is a good upgrade because it makes you busier and
-- richer at once. "+20% patience" would be a bad one -- it makes the game
-- permanently slower and easier, takes away the pressure people are playing
-- for, and can never be walked back once it is sold.
--
-- Same reason pets pay cash rather than cook faster: score stays pure skill,
-- and everything bought or rolled multiplies what that score is worth.

local ShopDefs = {}

-- Dish unlocks, in the order they are meant to be bought.
--
-- New VERBS come early: fries introduce the fryer and steak the grill, both
-- ahead of the cheaper assembly dishes. The first half of the curve should pay
-- out in new things to do, not in more of the same thing.
ShopDefs.DishOrder = {
	"fries", "hotdog", "steak", "grilled_cheese", "taco",
	"onion_rings", "pancakes", "club_sandwich", "breakfast_burrito",
	"tempura_veg", "ramen", "gloom_spuds", "quivvern_flank",
	"six_yolk_omelette",
}

ShopDefs.DishCost = {
	fries             = 400,     -- unlocks the fryer
	hotdog            = 900,
	steak             = 1500,    -- unlocks the grill
	grilled_cheese    = 2600,
	taco              = 4000,
	onion_rings       = 6000,
	pancakes          = 8500,
	club_sandwich     = 11000,
	breakfast_burrito = 14000,
	tempura_veg       = 18000,

	-- Cooked with what the station has rather than what Earth sent. These are
	-- harder as well as dearer: a reward that is only a bigger number stops
	-- being interesting the moment you own it.
	ramen             = 23000,
	gloom_spuds       = 29000,
	quivvern_flank    = 37000,
	six_yolk_omelette = 47000,
}

-- Permanent upgrades. `levels` is a list of costs; buying level N costs
-- levels[N]. `apply` describes what each level is worth.
ShopDefs.Upgrades = {
	slots = {
		id = "slots",
		name = "Counter Space",
		blurb = "One more customer can queue at a time.",
		-- Deliberately harder AND more lucrative: more tickets on screen is
		-- more to juggle, not less.
		levels = { 1200, 5000 },
		baseValue = 3,
		perLevel = 1,
	},

	tips = {
		id = "tips",
		name = "Reputation",
		blurb = "Every order pays a little more.",
		levels = { 800, 2000, 4500, 9000, 18000 },
		baseValue = 0,
		perLevel = 0.04,   -- +4% cash per level
	},

	shift = {
		id = "shift",
		name = "Longer Licence",
		blurb = "Eight more seconds of service per shift.",
		levels = { 1500, 3800, 8000 },
		baseValue = 0,
		-- Scaled down with the shift: +15s on a ninety second day was a 17%
		-- swing from one purchase.
		perLevel = 8,
	},
}

ShopDefs.UpgradeOrder = { "slots", "tips", "shift" }

-- ------------------------------------------------------------------ query --

function ShopDefs.dishCost(dishId: string): number?
	return ShopDefs.DishCost[dishId]
end

-- Cost of the NEXT level, or nil when maxed.
function ShopDefs.upgradeCost(upgradeId: string, ownedLevels: number): number?
	local upgrade = ShopDefs.Upgrades[upgradeId]
	if not upgrade then
		return nil
	end
	return upgrade.levels[ownedLevels + 1]
end

function ShopDefs.maxLevel(upgradeId: string): number
	local upgrade = ShopDefs.Upgrades[upgradeId]
	return if upgrade then #upgrade.levels else 0
end

-- Total value of an upgrade at a given level.
function ShopDefs.valueOf(upgradeId: string, level: number): number
	local upgrade = ShopDefs.Upgrades[upgradeId]
	if not upgrade then
		return 0
	end
	return upgrade.baseValue + upgrade.perLevel * level
end

return ShopDefs

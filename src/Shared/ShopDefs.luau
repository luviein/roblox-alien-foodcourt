--!strict
-- What cash can be spent on: dishes, and permanent upgrades.
--
-- The rule most upgrades here follow: RAISE THE CEILING, DO NOT LOWER THE
-- FLOOR. An extra order slot is a good upgrade because it makes you busier and
-- richer at once, rather than making the game permanently easier.
--
-- Counter Service is the deliberate exception, and it is worth being honest
-- about why. Buying patience DOES lower the floor. It only works because the
-- base was cut from 22s to 15s first: at 22s every order graded Perfect and
-- there was no pressure to sell relief from. At 15s there is, and the upgrade
-- buys back room a new player never had rather than removing difficulty an
-- experienced one was already handling.
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

-- Roughly halved when Word of Mouth was removed. Dishes are now the ONLY thing
-- that raises customer flow before a rebirth -- a dish with the right tag is
-- worth +5% hype in the phase or weather it suits -- so the curve has to be
-- something a player climbs steadily rather than saves up for. The old curve
-- topped out at 47,000, which was priced for a player who also had five levels
-- of Word of Mouth pushing their earnings up. Nobody has that now.
--
-- The shape is unchanged: new VERBS come early. Fries introduce the fryer and
-- steak the grill, both ahead of the cheaper assembly dishes, because the first
-- half of the curve should pay out in new things to do rather than more of the
-- same thing.
ShopDefs.DishCost = {
	fries             = 250,     -- unlocks the fryer
	hotdog            = 500,
	steak             = 850,     -- unlocks the grill
	grilled_cheese    = 1400,
	taco              = 2100,
	onion_rings       = 3000,
	pancakes          = 4200,
	club_sandwich     = 5600,
	breakfast_burrito = 7200,
	tempura_veg       = 9000,

	-- Cooked with what the station has rather than what Earth sent. These are
	-- harder as well as dearer: a reward that is only a bigger number stops
	-- being interesting the moment you own it.
	ramen             = 11500,
	gloom_spuds       = 14500,
	quivvern_flank    = 18000,
	six_yolk_omelette = 23000,
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

	-- Word of Mouth used to live here: five levels of permanently higher base
	-- hype. It was removed, and the reason is worth keeping.
	--
	-- Hype only controls how fast customers ARRIVE. It cannot make you cook
	-- faster, and one measured shift put that ceiling at roughly one order
	-- every eight seconds -- about eleven in a ninety second day. Word of Mouth
	-- sold arrivals well past that point, so its last levels bought nothing but
	-- customers who walked out. An upgrade whose top half is dead is worse than
	-- no upgrade at all, because it reads as progress.
	--
	-- Customer flow is now sourced entirely from hype the player EARNS: dish
	-- tags that pay off in the right phase and the right weather, and base hype
	-- from rebirths. That makes unlocking dishes the growth lever, and drafting
	-- them well the skill -- which is the point of the dish system.
	--
	-- Flyers (a per-day, randomly rolled +10-30%, bought fresh each morning and
	-- unlocked at rebirth 1) are the planned replacement. See PLAN-flyers.md.

	patience = {
		id = "patience",
		name = "Counter Service",
		blurb = "Customers wait two seconds longer before giving up.",
		-- The one upgrade that does lower the floor rather than raise the
		-- ceiling, which is why the base was cut to fifteen seconds first. It
		-- buys back room a new player does not have, instead of removing
		-- pressure they were already handling.
		levels = { 1000, 2600, 6000 },
		baseValue = 0,
		perLevel = 2,
	},

	cell = {
		id = "cell",
		name = "Continuity Cell",
		blurb = "The understudy keeps the counter open four hours longer while you are away.",
		-- Buys HOURS, never rate. The understudy earns a fraction of what the
		-- player earns, so raising its rate would make not-playing better;
		-- raising its cap only ever helps someone who was already away. The
		-- station's own excuse is that it will not sell fidelity, because a
		-- perfect copy of a worker raises questions nobody here wants asked.
		levels = { 2500, 6000, 13000 },
		baseValue = 0,
		perLevel = 4,   -- +4 hours of cell per level
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

ShopDefs.UpgradeOrder = { "slots", "patience", "tips", "shift", "cell" }

-- Upgrades that no longer exist. Any levels a player already bought are
-- refunded at full price on their next load, because taking away something
-- someone paid for and saying nothing is the one thing a shop must never do.
ShopDefs.RetiredUpgrades = {
	word = { 700, 1800, 4000, 8500, 17000 },
}

-- What a retired upgrade's owned levels are worth back.
function ShopDefs.refundValue(upgradeId: string, ownedLevels: number): number
	local levels = ShopDefs.RetiredUpgrades[upgradeId]
	if not levels then
		return 0
	end

	local total = 0
	for index = 1, math.min(ownedLevels, #levels) do
		total += levels[index]
	end
	return total
end

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

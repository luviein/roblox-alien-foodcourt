--!strict
-- The shop, the unlock curve, and refunds for retired upgrades.
--
-- Half of this file is consistency checks over the tables themselves rather
-- than tests of logic. Those are the ones that earn their keep here: a dish
-- added to the order list without a price, or a retired upgrade left in the
-- shop, is a nil at runtime rather than a wrong number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DishDefs = require(Shared.DishDefs)
local ShopDefs = require(Shared.ShopDefs)

local Runner = require(script.Parent.Runner)

return function()
	local t = Runner.new("shop")

	-- ------------------------------------------------------------- upgrades --

	t:equal("no levels means base value",
		ShopDefs.valueOf("slots", 0), ShopDefs.Upgrades.slots.baseValue)
	t:equal("levels add perLevel each",
		ShopDefs.valueOf("slots", 2),
		ShopDefs.Upgrades.slots.baseValue + 2 * ShopDefs.Upgrades.slots.perLevel)
	t:equal("an unknown upgrade is worth nothing", ShopDefs.valueOf("nonsense", 3), 0)

	t:equal("the first level costs levels[1]",
		ShopDefs.upgradeCost("slots", 0), ShopDefs.Upgrades.slots.levels[1])
	t:equal("a maxed upgrade has no next cost",
		ShopDefs.upgradeCost("slots", ShopDefs.maxLevel("slots")), nil)
	t:equal("an unknown upgrade has no cost", ShopDefs.upgradeCost("nonsense", 0), nil)

	-- Every upgrade in the order list must exist, and vice versa, or the shop
	-- renders a row for nothing or silently hides one.
	local orderAllReal = true
	for _, upgradeId in ShopDefs.UpgradeOrder do
		if not ShopDefs.Upgrades[upgradeId] then
			orderAllReal = false
		end
	end
	t:check("every ordered upgrade exists", orderAllReal)

	local allListed = true
	for upgradeId in ShopDefs.Upgrades do
		if not table.find(ShopDefs.UpgradeOrder, upgradeId) then
			allListed = false
		end
	end
	t:check("every upgrade is listed in the order", allListed)

	local costsClimb = true
	for upgradeId, upgrade in ShopDefs.Upgrades do
		for index = 2, #upgrade.levels do
			if upgrade.levels[index] <= upgrade.levels[index - 1] then
				costsClimb = false
			end
		end
	end
	t:check("upgrade costs increase with level", costsClimb)

	-- ---------------------------------------------------- the unlock curve --

	local everyDishPriced = true
	for _, dishId in ShopDefs.DishOrder do
		if not ShopDefs.dishCost(dishId) then
			everyDishPriced = false
		end
	end
	t:check("every unlockable dish has a price", everyDishPriced)

	local everyDishReal = true
	for _, dishId in ShopDefs.DishOrder do
		if not DishDefs.get(dishId) then
			everyDishReal = false
		end
	end
	t:check("every unlockable dish is a real dish", everyDishReal)

	local everyPriceOrdered = true
	for dishId in ShopDefs.DishCost do
		if not table.find(ShopDefs.DishOrder, dishId) then
			everyPriceOrdered = false
		end
	end
	t:check("every price belongs to an ordered dish", everyPriceOrdered)

	-- The curve is meant to be climbed in order, so it has to be monotonic.
	local curveClimbs = true
	local previous = 0
	for _, dishId in ShopDefs.DishOrder do
		local cost = ShopDefs.dishCost(dishId) or 0
		if cost <= previous then
			curveClimbs = false
		end
		previous = cost
	end
	t:check("the unlock curve only goes up", curveClimbs)

	-- ------------------------------------------------------------- refunds --

	-- Word of Mouth was removed. It must be gone from the shop AND still
	-- refundable, or anyone who bought it silently loses the cash.
	t:equal("a retired upgrade is out of the shop", ShopDefs.Upgrades.word, nil)
	t:equal("and out of the order", table.find(ShopDefs.UpgradeOrder, "word"), nil)
	t:truthy("but still refundable", ShopDefs.RetiredUpgrades.word)

	local levels = ShopDefs.RetiredUpgrades.word
	t:equal("nothing owned refunds nothing", ShopDefs.refundValue("word", 0), 0)
	t:equal("one level refunds its price", ShopDefs.refundValue("word", 1), levels[1])
	t:equal("two levels refund both", ShopDefs.refundValue("word", 2), levels[1] + levels[2])

	local everything = 0
	for _, cost in levels do
		everything += cost
	end
	t:equal("all levels refund the lot", ShopDefs.refundValue("word", #levels), everything)

	-- A save claiming more levels than ever existed must not pay for the
	-- extras -- refundValue clamps rather than indexing off the end.
	t:equal("an impossible level count is clamped",
		ShopDefs.refundValue("word", #levels + 5), everything)
	t:equal("an unknown upgrade refunds nothing", ShopDefs.refundValue("nonsense", 3), 0)

	return t
end

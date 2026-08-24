--!strict
-- Order generation. Uses a bag (deck) randomiser rather than raw math.random
-- so players never get five identical tickets in a row, and never get a
-- drought of one dish either. This genuinely feels better than uniform RNG.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DishDefs = require(Shared.DishDefs)

local OPTIONAL_CHANCE = 0.55

local OrderService = {}

export type Order = {
	id: number,
	dishId: string,
	required: { string },  -- ingredient ids, in the order they must be added
	keys: { string },      -- parallel array of keyboard keys
	createdAt: number,
	expiresAt: number,
	baseValue: number,
	timing: { perfect: number, good: number, sloppy: number },
}

-- Fisher-Yates.
local function shuffle<T>(list: { T }, rng: Random): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

export type Bag = {
	contents: { string },
	rng: Random,
	lastDrawn: string?,
}

function OrderService.newBag(seed: number?): Bag
	return {
		contents = {},
		rng = if seed then Random.new(seed) else Random.new(),
		lastDrawn = nil,
	}
end

local function refill(bag: Bag)
	local fresh = table.clone(DishDefs.ActiveMenu)
	shuffle(fresh, bag.rng)

	-- Avoid a repeat straddling the bag boundary.
	if #fresh > 1 and fresh[1] == bag.lastDrawn then
		fresh[1], fresh[#fresh] = fresh[#fresh], fresh[1]
	end

	bag.contents = fresh
end

function OrderService.draw(bag: Bag): string
	if #bag.contents == 0 then
		refill(bag)
	end
	local dishId = table.remove(bag.contents, 1) :: string
	bag.lastDrawn = dishId
	return dishId
end

-- Builds a concrete ticket: rolls which optional components this customer wants.
function OrderService.create(bag: Bag, orderId: number, now: number): Order
	local dishId = OrderService.draw(bag)
	local dish = DishDefs.get(dishId)
	assert(dish, `unknown dish "{dishId}" in ActiveMenu`)

	local required: { string } = {}
	local keys: { string } = {}

	-- Fryer dishes have no components: nothing is assembled, so the ticket
	-- lists nothing and both arrays stay empty.
	for _, component in (dish.components or {}) do
		local include = component.required or bag.rng:NextNumber() < OPTIONAL_CHANCE
		if include then
			table.insert(required, component.id)
			table.insert(keys, component.key)
		end
	end

	return {
		id = orderId,
		dishId = dishId,
		station = dish.station,
		required = required,
		keys = keys,
		createdAt = now,
		expiresAt = now + Config.ORDER_PATIENCE,
		baseValue = dish.baseValue,
		timing = dish.timing,
	}
end

return OrderService

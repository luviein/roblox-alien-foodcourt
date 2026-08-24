--!strict
-- A Kitchen is one running station with a list of participants. In P0 that
-- list always has exactly one player -- but the shape is deliberate: co-op
-- later means pushing more players into participants and giving stations an
-- owner field, not rewriting this file.
--
-- The server owns every timer. The client only renders and sends intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DishDefs = require(Shared.DishDefs)
local StationDefs = require(Shared.StationDefs)

local OrderService = require(script.Parent.OrderService)
local ScoreService = require(script.Parent.ScoreService)

local Kitchen = {}
Kitchen.__index = Kitchen

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Reads a {progress, value} curve from Config and returns the value for the
-- current shift progress.
local function curveValue(curve, progress: number): number
	local result = curve[1][2]
	for _, entry in curve do
		if progress >= entry[1] then
			result = entry[2]
		end
	end
	return result
end

function Kitchen.new(participants: { Player })
	local self = setmetatable({}, Kitchen)

	self.participants = participants
	self.state = "Idle"

	self.orders = {}
	self.bag = OrderService.newBag()
	self.nextOrderId = 1

	-- Which station the player is standing at. 1-4 moves between them.
	self.activeStation = StationDefs.Order[1]

	-- Prep counter working state. These predate the station system; renaming
	-- them into a nested table would buy nothing.
	self.activeOrderId = nil
	self.build = {}

	-- Fryer baskets. Each is either empty or cooking one specific order, and it
	-- keeps cooking whether or not the player is standing there -- which is the
	-- entire point of the station.
	self.baskets = {}
	local fryer = StationDefs.get("Fryer")
	for index = 1, (fryer and fryer.baskets or 0) do
		self.baskets[index] = {
			state = "empty",   -- empty | cooking | ready | burnt
			orderId = nil,
			readyAt = 0,
			burnAt = 0,
		}
	end

	self.score = 0
	self.combo = 0
	self.bestCombo = 0
	self.stats = {
		served = 0, perfect = 0, good = 0, sloppy = 0, failed = 0, expired = 0,
	}

	self.shiftStartedAt = 0
	self.shiftEndsAt = 0
	self.nextSpawnAt = 0
	self.fumbleUntil = 0

	self.events = {}  -- drained by ShiftService each tick

	return self
end

function Kitchen:emit(event)
	table.insert(self.events, event)
end

function Kitchen:drainEvents()
	local drained = self.events
	self.events = {}
	return drained
end

-- ------------------------------------------------------------ lifecycle ----

function Kitchen:startShift()
	if self.state == "Service" then
		return
	end

	local t = now()

	self.state = "Service"
	self.orders = {}
	self.bag = OrderService.newBag()
	self.nextOrderId = 1
	self.activeOrderId = nil
	self.build = {}
	self.score = 0
	self.combo = 0
	self.bestCombo = 0
	self.stats = {
		served = 0, perfect = 0, good = 0, sloppy = 0, failed = 0, expired = 0,
	}
	self.activeStation = StationDefs.Order[1]
	for _, basket in self.baskets do
		basket.state = "empty"
		basket.orderId = nil
	end
	self.shiftStartedAt = t
	self.shiftEndsAt = t + Config.SHIFT_DURATION
	self.nextSpawnAt = t + 1.0   -- brief beat before the first ticket
	self.fumbleUntil = 0

	self:emit({ type = "shiftStarted" })
end

function Kitchen:closeResults()
	if self.state == "Results" then
		self.state = "Idle"
	end
end

function Kitchen:progress(): number
	if self.state ~= "Service" then
		return 0
	end
	local elapsed = now() - self.shiftStartedAt
	return math.clamp(elapsed / Config.SHIFT_DURATION, 0, 1)
end

-- --------------------------------------------------------------- orders ----

function Kitchen:findOrder(orderId: number)
	for index, order in self.orders do
		if order.id == orderId then
			return order, index
		end
	end
	return nil, nil
end

function Kitchen:activeOrder()
	if not self.activeOrderId then
		return nil
	end
	local order = self:findOrder(self.activeOrderId)
	return order
end

-- The Prep counter always works its oldest waiting order. Choosing a ticket is
-- no longer a thing the player does -- choosing a STATION is.
function Kitchen:ensureSelection()
	if self.activeOrderId then
		local current = self:findOrder(self.activeOrderId)
		if current and current.station == "Prep" then
			return
		end
	end

	self.activeOrderId = nil
	self.build = {}

	for _, order in self.orders do
		if order.station == "Prep" then
			self.activeOrderId = order.id
			return
		end
	end
end

-- Oldest fryer order that no basket has claimed yet.
function Kitchen:nextFryerOrder()
	local claimed = {}
	for _, basket in self.baskets do
		if basket.orderId then
			claimed[basket.orderId] = true
		end
	end

	for _, order in self.orders do
		if order.station == "Fryer" and not claimed[order.id] then
			return order
		end
	end
	return nil
end

function Kitchen:spawnOrder()
	local order = OrderService.create(self.bag, self.nextOrderId, now())
	self.nextOrderId += 1
	table.insert(self.orders, order)
	self:emit({ type = "orderArrived", orderId = order.id, dishId = order.dishId })
	self:ensureSelection()
end

function Kitchen:removeOrder(orderId: number)
	local _, index = self:findOrder(orderId)
	if index then
		table.remove(self.orders, index)
	end
	if self.activeOrderId == orderId then
		self.activeOrderId = nil
		self.build = {}
	end
	self:ensureSelection()
end

-- ------------------------------------------------------------ selection ----

-- Walking to another station. Deliberately does NOT abandon the half-built
-- plate at Prep: leaving something on the counter, dealing with the fryer, and
-- coming back to finish it is the whole point of having stations.
function Kitchen:selectStation(index: number)
	local stationId = StationDefs.byKeyIndex(index)
	if not stationId or stationId == self.activeStation then
		return
	end
	self.activeStation = stationId
	self:emit({ type = "stationChanged", stationId = stationId })
end

-- ---------------------------------------------------------------- build ----

-- Which ingredient does this key mean, for the dish currently selected?
local function keyToIngredient(dishId: string, key: string): string?
	local dish = DishDefs.get(dishId)
	if not dish then
		return nil
	end
	for _, component in dish.components do
		if component.key == key then
			return component.id
		end
	end
	return nil
end

function Kitchen:addIngredient(key: string)
	if self.state ~= "Service" or self.activeStation ~= "Prep" then
		return
	end

	local t = now()
	if t < self.fumbleUntil then
		return
	end

	local order = self:activeOrder()
	if not order then
		return
	end

	local ingredientId = keyToIngredient(order.dishId, key)
	local expected = order.required[#self.build + 1]
	local correct = ingredientId ~= nil and ingredientId == expected

	if correct then
		table.insert(self.build, ingredientId)
		self:emit({
			type = "ingredientAdded",
			orderId = order.id,
			key = key,
			ingredientId = ingredientId,
			step = #self.build,
			total = #order.required,
			complete = #self.build == #order.required,
		})
		return
	end

	-- Wrong key.
	self.fumbleUntil = t + Config.FUMBLE_LOCKOUT

	if Config.WRONG_KEY_MODE == "corrupt" and ingredientId then
		-- It lands on the plate and ruins the build; the player must SCRAP.
		table.insert(self.build, ingredientId)
	end

	self:emit({
		type = "fumble",
		orderId = order.id,
		key = key,
		mode = Config.WRONG_KEY_MODE,
	})
end

function Kitchen:scrap()
	if self.state ~= "Service" or self.activeStation ~= "Prep" or #self.build == 0 then
		return
	end
	self.build = {}
	self:emit({ type = "scrapped" })
end

local function buildMatches(build, required): boolean
	if #build ~= #required then
		return false
	end
	for index, id in required do
		if build[index] ~= id then
			return false
		end
	end
	return true
end

function Kitchen:serve()
	if self.state ~= "Service" or self.activeStation ~= "Prep" then
		return
	end

	local order = self:activeOrder()
	if not order or #self.build == 0 then
		return
	end

	local t = now()
	local correct = buildMatches(self.build, order.required)
	self:award(order, ScoreService.grade(order, t, correct))
end

-- Scoring, combo, stats and the graded event, shared by every station: a dish
-- pulled from the fryer pays out exactly like a plate handed over at Prep.
function Kitchen:award(order, grade: string, basketIndex: number?)
	local value, comboMult = ScoreService.payout(order, grade, self.combo)

	self.score += value
	self.combo = ScoreService.nextCombo(self.combo, grade)
	self.bestCombo = math.max(self.bestCombo, self.combo)

	if grade == "Fail" then
		self.stats.failed += 1
	else
		self.stats.served += 1
		self.stats[string.lower(grade)] += 1
	end

	self:emit({
		type = "graded",
		orderId = order.id,
		dishId = order.dishId,
		station = order.station,
		basket = basketIndex,
		grade = grade,
		value = value,
		comboMult = comboMult,
		combo = self.combo,
	})

	self:removeOrder(order.id)
end

-- ---------------------------------------------------------------- fryer ----

-- One key per basket, and the key means whatever the basket needs next: drop
-- when empty, pull when cooking or ready, clear when burnt. Two keys run the
-- whole station no matter how busy it gets.
function Kitchen:basketAction(index: number)
	if self.state ~= "Service" or self.activeStation ~= "Fryer" then
		return
	end

	local basket = self.baskets[index]
	if not basket then
		return
	end

	local t = now()

	if basket.state == "empty" then
		local order = self:nextFryerOrder()
		if not order then
			return
		end

		local dish = DishDefs.get(order.dishId)
		local fry = dish and dish.fry
		if not fry then
			return
		end

		basket.state = "cooking"
		basket.orderId = order.id
		basket.readyAt = t + fry.cookTime
		basket.burnAt = basket.readyAt + fry.burn

		self:emit({
			type = "basketDropped",
			basket = index,
			orderId = order.id,
			dishId = order.dishId,
			readyAt = basket.readyAt,
			burnAt = basket.burnAt,
		})

	elseif basket.state == "cooking" then
		-- Pulled early. Raw food is a wrong order, not a slow one.
		self:finishBasket(index, "Fail")

	elseif basket.state == "ready" then
		self:finishBasket(index, nil)

	elseif basket.state == "burnt" then
		-- The order already failed when it burned; this just empties the basket
		-- so it can be used again.
		basket.state = "empty"
		basket.orderId = nil
		self:emit({ type = "basketCleared", basket = index })
	end
end

-- Grades and pays out whatever is in the basket, then empties it. A nil
-- `forcedGrade` means work it out from how late the pull was.
function Kitchen:finishBasket(index: number, forcedGrade: string?)
	local basket = self.baskets[index]
	if not basket or not basket.orderId then
		return
	end

	local order = self:findOrder(basket.orderId)
	local t = now()

	if order then
		local grade = forcedGrade

		if not grade then
			local dish = DishDefs.get(order.dishId)
			local fry = dish and dish.fry
			local overshoot = t - basket.readyAt

			-- Two clocks apply to a fried order: how precisely it came out of
			-- the oil, and how long the customer has been waiting. Take the
			-- worse of the two, so you cannot rescue a forgotten ticket with a
			-- flawless pull, or vice versa.
			local fryGrade = ScoreService.fryGrade(overshoot, fry)
			local patienceGrade = ScoreService.grade(order, t, true)
			grade = ScoreService.worst(fryGrade, patienceGrade)
		end

		self:award(order, grade, index)
	end

	basket.state = "empty"
	basket.orderId = nil
end

-- ----------------------------------------------------------------- tick ----

function Kitchen:tick()
	if self.state ~= "Service" then
		return
	end

	local t = now()

	-- The fryer runs whether or not anyone is watching it. This loop is the
	-- reason the station exists.
	for index, basket in self.baskets do
		if basket.state == "cooking" and t >= basket.readyAt then
			basket.state = "ready"
			self:emit({ type = "basketReady", basket = index, orderId = basket.orderId })

		elseif basket.state == "ready" and t >= basket.burnAt then
			-- Left too long. The order fails on its own -- ignoring the fryer
			-- has to cost something, or there is no tension in walking away.
			basket.state = "burnt"
			local order = if basket.orderId then self:findOrder(basket.orderId) else nil
			self:emit({ type = "basketBurnt", basket = index, orderId = basket.orderId })
			if order then
				self:award(order, "Fail", index)
			end
			basket.orderId = nil
		end
	end

	-- Walk-outs.
	local index = 1
	while index <= #self.orders do
		local order = self.orders[index]
		if t >= order.expiresAt then
			self.stats.expired += 1
			self.combo = 0
			self:emit({ type = "expired", orderId = order.id, dishId = order.dishId })
			self:removeOrder(order.id)
		else
			index += 1
		end
	end

	-- New tickets, on the difficulty curve.
	local progress = self:progress()
	local maxActive = curveValue(Config.MAX_ACTIVE_ORDERS, progress)
	local interval = curveValue(Config.SPAWN_INTERVAL, progress)

	if t >= self.nextSpawnAt and #self.orders < math.min(maxActive, Config.MAX_ORDER_SLOTS) then
		self:spawnOrder()
		self.nextSpawnAt = t + interval
	end

	-- End of service.
	if t >= self.shiftEndsAt then
		self.state = "Results"
		self.orders = {}
		self.activeOrderId = nil
		self.build = {}
		self:emit({ type = "shiftEnded", score = self.score, stats = self.stats })
	end
end

-- ------------------------------------------------------------- snapshot ----

-- Sent at Config.TICK_RATE. Deliberately compact: the client already has
-- DishDefs, so tickets carry ids and timestamps, not display strings.
function Kitchen:snapshot()
	local orders = table.create(#self.orders)
	for _, order in self.orders do
		table.insert(orders, {
			id = order.id,
			dishId = order.dishId,
			station = order.station,
			required = order.required,
			keys = order.keys,
			createdAt = order.createdAt,
			expiresAt = order.expiresAt,
		})
	end

	-- Baskets are sent every tick: their countdowns are the one thing the
	-- player must be able to read from another station.
	local baskets = {}
	for index, basket in self.baskets do
		baskets[index] = {
			state = basket.state,
			orderId = basket.orderId,
			readyAt = basket.readyAt,
			burnAt = basket.burnAt,
		}
	end

	return {
		state = self.state,
		serverTime = now(),
		shiftEndsAt = self.shiftEndsAt,
		shiftDuration = Config.SHIFT_DURATION,
		score = self.score,
		combo = self.combo,
		comboMult = ScoreService.comboMultiplier(self.combo),
		bestCombo = self.bestCombo,
		activeStation = self.activeStation,
		baskets = baskets,
		activeOrderId = self.activeOrderId,
		build = self.build,
		fumbleUntil = self.fumbleUntil,
		orders = orders,
		stats = self.stats,
	}
end

return Kitchen

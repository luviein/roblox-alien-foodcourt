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

	self.activeOrderId = nil
	self.build = {}

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

-- Keeps the selection sensible: if nothing is selected (or the selected
-- ticket just left), fall to the oldest ticket on the rail.
function Kitchen:ensureSelection()
	if self.activeOrderId and self:findOrder(self.activeOrderId) then
		return
	end
	self.activeOrderId = if self.orders[1] then self.orders[1].id else nil
	self.build = {}
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

function Kitchen:selectSlot(slot: number)
	local order = self.orders[slot]
	if not order or order.id == self.activeOrderId then
		return
	end
	self.activeOrderId = order.id
	self.build = {}   -- switching tickets abandons the current build
	self:emit({ type = "selected", orderId = order.id })
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
	if self.state ~= "Service" then
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
	if self.state ~= "Service" or #self.build == 0 then
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
	if self.state ~= "Service" then
		return
	end

	local order = self:activeOrder()
	if not order or #self.build == 0 then
		return
	end

	local t = now()
	local correct = buildMatches(self.build, order.required)
	local grade = ScoreService.grade(order, t, correct)
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
		grade = grade,
		value = value,
		comboMult = comboMult,
		combo = self.combo,
	})

	self:removeOrder(order.id)
end

-- ----------------------------------------------------------------- tick ----

function Kitchen:tick()
	if self.state ~= "Service" then
		return
	end

	local t = now()

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
			required = order.required,
			keys = order.keys,
			createdAt = order.createdAt,
			expiresAt = order.expiresAt,
		})
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
		activeOrderId = self.activeOrderId,
		build = self.build,
		fumbleUntil = self.fumbleUntil,
		orders = orders,
		stats = self.stats,
	}
end

return Kitchen

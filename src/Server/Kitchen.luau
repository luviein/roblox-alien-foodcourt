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
local ChoreDefs = require(Shared.ChoreDefs)
local HypeDefs = require(Shared.HypeDefs)
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

-- Seconds until the next interruption. Randomised so chores never become
-- something you can count down to and pre-empt.
local function choreGap(rng: Random): number
	return rng:NextNumber(Config.CHORE_GAP[1], Config.CHORE_GAP[2])
end

function Kitchen.new(participants: { Player })
	local self = setmetatable({}, Kitchen)

	self.participants = participants
	self.state = "Idle"

	self.orders = {}
	self.bag = OrderService.newBag()
	self.nextOrderId = 1

	-- The ticket being worked on, and the plate being built for it.
	self.activeOrderId = nil
	self.build = {}

	self.score = 0
	self.tips = 0
	self.combo = 0
	self.bestCombo = 0
	self.stats = {
		served = 0, perfect = 0, good = 0, sloppy = 0, failed = 0, expired = 0,
		chores = 0,
	}

	self.shiftStartedAt = 0
	self.shiftEndsAt = 0
	self.nextSpawnAt = 0
	self.fumbleUntil = 0
	self.chore = nil
	self.nextChoreAt = 0
	self.phase = ""
	self.hype = 1

	self.events = {}  -- drained by ShiftService each tick

	-- Replaced on every startShift; these are only the resting defaults so a
	-- snapshot taken before the first shift is not full of nils.
	self.loadout = {
		menu = { "burger" },
		orderSlots = Config.MAX_ORDER_SLOTS,
		shiftDuration = Config.SHIFT_DURATION,
		cashMultiplier = 1,
	}

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

-- `loadout` is what the player brings to this shift: the dishes they have
-- unlocked and whatever their upgrades are worth. Kitchen never reads a profile
-- itself -- it is handed the numbers.
function Kitchen:startShift(loadout)
	if self.state == "Service" then
		return
	end

	local t = now()

	self.loadout = loadout
	self.state = "Service"
	self.orders = {}
	self.bag = OrderService.newBag(loadout.menu, loadout.seed)
	self.nextOrderId = 1
	self.activeOrderId = nil
	self.build = {}
	self.score = 0
	self.tips = 0
	self.combo = 0
	self.bestCombo = 0
	self.stats = {
		served = 0, perfect = 0, good = 0, sloppy = 0, failed = 0, expired = 0,
		chores = 0,
	}
	self.shiftStartedAt = t
	self.shiftEndsAt = t + loadout.shiftDuration
	self.nextSpawnAt = t + 1.0   -- brief beat before the first ticket
	-- Nothing interrupts in the opening moments; let them get going first.
	self.chore = nil
	self.nextChoreAt = t + choreGap(self.bag.rng) * 0.6
	self.phase = ""
	self.hype = (loadout.hypeByPhase and loadout.hypeByPhase.morning) or 1
	self.fumbleUntil = 0

	self:emit({ type = "shiftStarted" })
end

function Kitchen:closeResults()
	if self.state == "Results" then
		self.state = "Idle"
	end
end

-- Fills in the result of a shift nobody actually cooked, and stops. A testing
-- convenience, gated behind Config.DEBUG_COMMANDS by its caller.
--
-- The numbers are a competent-but-not-perfect day, and they matter: ending a
-- real shift early scores zero, and a zero shift poisons everything measured
-- against recent earnings -- the understudy included, which then pays nothing
-- and looks broken. This produces a shift worth having on the books.
--
-- Deliberately identical every time. Testing wants a repeatable number far
-- more than it wants a realistic spread.
function Kitchen:debugFinishShift()
	if self.state ~= "Service" then
		return
	end

	local served = 8
	local perfect = 6

	self.stats = {
		served = served,
		perfect = perfect,
		good = served - perfect,
		sloppy = 0,
		failed = 0,
		expired = 0,
		chores = 2,
	}
	self.bestCombo = served
	self.tips = served * (self.loadout.tipPerOrder or 0)

	-- Roughly what eight orders at a decent grade and a climbing combo pay,
	-- which lands near the 900 a real good early shift scores.
	self.score = 900

	self.orders = {}
	self.activeOrderId = nil
	self.build = {}
	self.chore = nil
	self.state = "Results"

	self:emit({ type = "shiftEnded", score = self.score, stats = self.stats })
end

-- Brings the closing bell forward to right now. A testing convenience, gated
-- behind Config.DEBUG_COMMANDS by its caller.
--
-- It moves the CLOCK rather than setting the state directly, so the next tick
-- ends the shift down exactly the same path a shift that ran its full length
-- takes: results, payout, daily task progress, save. A second way to finish a
-- shift is a second thing to keep in step, and this way there isn't one.
function Kitchen:endShiftNow()
	if self.state ~= "Service" then
		return
	end
	self.shiftEndsAt = now()

	-- Also sends everyone still waiting home. Without this the shift would sit
	-- in last orders for up to a full patience after the command, which is the
	-- opposite of what a "end this now" command is for. They are dropped
	-- rather than counted as walkouts: this is a testing exit, and it should
	-- not quietly stain the stats it exists to let you look at.
	self.orders = {}
end

function Kitchen:progress(): number
	if self.state ~= "Service" then
		return 0
	end
	local elapsed = now() - self.shiftStartedAt
	return math.clamp(elapsed / math.max(self.loadout.shiftDuration, 1), 0, 1)
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

-- Only clears a selection that is no longer valid. Deliberately never picks
-- one: an order is something you choose to pick up, so nothing lands in your
-- hands on its own and the prep panel never opens by itself.
function Kitchen:validateSelection()
	if self.activeOrderId and self:findOrder(self.activeOrderId) then
		return
	end
	self.activeOrderId = nil
	self.build = {}
end

function Kitchen:spawnOrder()
	local order = OrderService.create(
		self.bag, self.nextOrderId, now(), self.loadout.orderPatience)
	self.nextOrderId += 1
	table.insert(self.orders, order)
	self:emit({ type = "orderArrived", orderId = order.id, dishId = order.dishId })
	self:validateSelection()
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
	self:validateSelection()
end

-- ------------------------------------------------------------ selection ----

-- Picking up a different ticket. Abandons whatever was on the plate: you
-- cannot half-build two dishes at once.
function Kitchen:selectSlot(slot: number)
	local order = self.orders[slot]
	if not order or order.id == self.activeOrderId then
		return
	end
	self.activeOrderId = order.id
	self.build = {}
	self:emit({ type = "selected", orderId = order.id })
end

function Kitchen:selectOrder(orderId: number)
	for slot, order in self.orders do
		if order.id == orderId then
			self:selectSlot(slot)
			return
		end
	end
end

-- ---------------------------------------------------------------- build ----

-- Which ingredient does this key mean, for the dish currently selected?
local function keyToIngredient(dishId: string, key: string): string?
	local dish = DishDefs.get(dishId)
	if not dish then
		return nil
	end
	for _, component in (dish.components or {}) do
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

	-- Once it is in the oil the keys do nothing: the only thing left is to come
	-- back for it.
	if order.cookState and order.cookState ~= "raw" then
		return
	end

	local ingredientId = keyToIngredient(order.dishId, key)
	local expected = order.required[#self.build + 1]
	local correct = ingredientId ~= nil and ingredientId == expected

	if correct then
		table.insert(self.build, ingredientId)
		local complete = #self.build == #order.required

		self:emit({
			type = "ingredientAdded",
			orderId = order.id,
			key = key,
			ingredientId = ingredientId,
			step = #self.build,
			total = #order.required,
			complete = complete,
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
	if not order then
		return
	end

	-- Fried orders have no plate to check. SPACE starts them cooking, then
	-- collects them once they are ready.
	if order.cookState then
		self:handleFryOrder(order)
		return
	end

	-- Grilled orders: the sear has to be finished before it can be handed over,
	-- and the grade is the worse of the sear and the customer's patience.
	if order.searState then
		if order.searState ~= "done" then
			return
		end
		local patienceGrade = ScoreService.grade(order, now(), true)
		self:award(order, ScoreService.worst(order.searGrade or "Sloppy", patienceGrade))
		return
	end

	if #self.build == 0 then
		return
	end

	local t = now()
	local correct = buildMatches(self.build, order.required)
	self:award(order, ScoreService.grade(order, t, correct))
end

-- Scoring, combo, stats and the graded event, shared by every station: a dish
-- pulled from the fryer pays out exactly like a plate handed over at Prep.
function Kitchen:award(order, grade: string)
	local value, comboMult = ScoreService.payout(order, grade, self.combo)

	self.score += value
	self.combo = ScoreService.nextCombo(self.combo, grade)
	self.bestCombo = math.max(self.bestCombo, self.combo)

	if grade == "Fail" then
		self.stats.failed += 1
	else
		self.stats.served += 1
		self.stats[string.lower(grade)] += 1

		-- A tip boost pays flat cash per order, banked here and added to the
		-- payout at the end. It deliberately never touches self.score: score
		-- is the skill number and has to stay comparable between a boosted
		-- shift and an unboosted one.
		self.tips += self.loadout.tipPerOrder or 0
	end

	self:emit({
		type = "graded",
		orderId = order.id,
		dishId = order.dishId,
		station = order.station,
		grade = grade,
		value = value,
		comboMult = comboMult,
		combo = self.combo,
	})

	self:removeOrder(order.id)
end

-- ---------------------------------------------------------------- fryer ----

-- Every fried order cooks on its own clock, rather than competing for a fixed
-- shared pool of fryer baskets. Four customers can all have fries going at
-- once, which is how Cook Serve Delicious does it and what a fixed set of
-- baskets could not express.
--
-- Because starting a fry is therefore nearly free, the pressure lives in
-- COLLECTING it: an order sits ready for a few seconds and then burns. Walking
-- away is still a decision, it is just a decision about coming back.
function Kitchen:startCook(order): boolean
	local dish = DishDefs.get(order.dishId)
	local fry = dish and dish.fry
	if not fry or order.cookState ~= "raw" then
		return false
	end

	local t = now()

	-- Some things do not cook the same way twice. Jitter means there is no
	-- rhythm to memorise, so you have to watch the ticket rather than count.
	local cookTime = fry.cookTime
	if fry.jitter then
		cookTime += self.bag.rng:NextNumber(-fry.jitter, fry.jitter)
	end

	order.cookState = "cooking"
	order.readyAt = t + cookTime
	order.burnAt = order.readyAt + fry.burn

	self:emit({
		type = "cookStarted",
		orderId = order.id,
		dishId = order.dishId,
		readyAt = order.readyAt,
		burnAt = order.burnAt,
	})
	return true
end

-- SPACE on a fried order means whatever it needs next: start it if it is raw,
-- collect it if it is ready. One key, no mode to remember.
function Kitchen:handleFryOrder(order): boolean
	local t = now()

	if order.cookState == "raw" then
		-- SPACE is the commit for every dish. Here it drops the basket in --
		-- but only once the prep steps are done, so it cannot skip them.
		if #self.build == #order.required and buildMatches(self.build, order.required) then
			self:startCook(order)
			self.build = {}
			-- Out of your hands: the panel closes and the countdown carries on
			-- over the customer's head while you do something else.
			self.activeOrderId = nil
		end
		return true

	elseif order.cookState == "cooking" then
		-- Nothing to collect yet. Deliberately a no-op rather than a raw
		-- collection: failing an order that is merely still cooking punishes a
		-- stray keypress, and a stray keypress aimed at one ticket should never
		-- ruin another.
		return true

	elseif order.cookState == "ready" then
		local dish = DishDefs.get(order.dishId)
		-- Two clocks apply: how precisely it was collected, and how long the
		-- customer has been waiting. The worse one wins, so a flawless pull
		-- cannot rescue a ticket left sitting.
		local fryGrade = ScoreService.fryGrade(t - order.readyAt, dish and dish.fry)
		local patienceGrade = ScoreService.grade(order, t, true)
		self:award(order, ScoreService.worst(fryGrade, patienceGrade))

	elseif order.cookState == "burnt" then
		self:award(order, "Fail")
	end

	return true
end

-- ----------------------------------------------------------------- grill ---

-- Holding the sear key. The meter starts the moment the key goes down and the
-- grade is decided by where it is when you let go, so the whole interaction is
-- one press held for the right length of time.
function Kitchen:searStart()
	if self.state ~= "Service" then
		return
	end

	local order = self:activeOrder()
	if not order or not order.searState or order.searState ~= "waiting" then
		return
	end

	-- The prep steps have to be done first: you cannot sear an empty grill.
	if not buildMatches(self.build, order.required) then
		return
	end

	order.searState = "searing"
	order.searStartedAt = now()
	self:emit({ type = "searStarted", orderId = order.id, startedAt = order.searStartedAt })
end

function Kitchen:searEnd()
	if self.state ~= "Service" then
		return
	end

	local order = self:activeOrder()
	if not order or order.searState ~= "searing" then
		return
	end

	local dish = DishDefs.get(order.dishId)
	local sear = dish and dish.sear
	local elapsed = now() - order.searStartedAt
	local fraction = elapsed / (sear and sear.duration or 1)

	order.searState = "done"
	order.searGrade = ScoreService.searGrade(fraction, sear)

	self:emit({
		type = "searFinished",
		orderId = order.id,
		grade = order.searGrade,
		fraction = fraction,
	})
end

-- ---------------------------------------------------------------- chores ---

function Kitchen:spawnChore()
	local chore = ChoreDefs.roll(self.bag.rng, self.loadout.tagCounts)
	local t = now()

	self.chore = {
		id = chore.id,
		startedAt = t,
		expiresAt = t + chore.duration,
	}

	self:emit({ type = "choreStarted", choreId = chore.id, expiresAt = self.chore.expiresAt })
end

-- One key clears whatever is up. Deliberately not per-chore: every letter key
-- may be an ingredient for the dish in your hands.
function Kitchen:clearChore()
	if self.state ~= "Service" or not self.chore then
		return
	end

	local choreId = self.chore.id
	self.chore = nil
	self.nextChoreAt = now() + choreGap(self.bag.rng)
	self.stats.chores += 1

	self:emit({ type = "choreCleared", choreId = choreId })
end

-- ----------------------------------------------------------------- tick ----

function Kitchen:tick()
	if self.state ~= "Service" then
		return
	end

	local t = now()

	-- Chores. One at a time: two competing five second timers is not pressure,
	-- it is a mess.
	if self.chore then
		if t >= self.chore.expiresAt then
			local choreId = self.chore.id
			self.chore = nil
			self.nextChoreAt = t + choreGap(self.bag.rng)

			-- Halved, not reset. A missed five second window should hurt without
			-- erasing a minute of clean work.
			local before = self.combo
			self.combo = math.floor(self.combo * Config.CHORE_COMBO_PENALTY)
			self:emit({
				type = "choreFailed",
				choreId = choreId,
				comboBefore = before,
				combo = self.combo,
			})
		end
	elseif t >= self.nextChoreAt then
		self:spawnChore()
	end

	-- Anything left on the grill burns. Unlike the fryer this cannot be left
	-- and returned to: it is ruined a couple of seconds after it is done.
	for _, order in self.orders do
		if order.searState == "searing" then
			local dish = DishDefs.get(order.dishId)
			local sear = dish and dish.sear
			if sear and (t - order.searStartedAt) > sear.duration * 1.25 then
				order.searState = "done"
				order.searGrade = "Fail"
				self:emit({ type = "searBurnt", orderId = order.id })
			end
		end
	end

	-- Fried orders cook whether or not anyone is looking at them. This loop is
	-- the reason walking away costs something.
	for _, order in self.orders do
		if order.cookState == "cooking" and t >= order.readyAt then
			order.cookState = "ready"
			self:emit({ type = "cookReady", orderId = order.id, dishId = order.dishId })

		elseif order.cookState == "ready" and t >= order.burnAt then
			-- Left too long. Still collectable, but it is a Fail now: ignoring
			-- it has to cost something or there is no tension in leaving.
			order.cookState = "burnt"
			self:emit({ type = "cookBurnt", orderId = order.id, dishId = order.dishId })
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

	-- Hype IS the spawn rate. A well-drafted menu fills the queue; a bad one
	-- leaves you idle, which is why the draft matters more than any single
	-- dish on it. Recomputed per phase, so a breakfast dish stops earning its
	-- place the moment the morning ends.
	local phase = HypeDefs.phaseAt(t - self.shiftStartedAt, self.loadout.shiftDuration)
	if phase ~= self.phase then
		self.phase = phase
		self.hype = (self.loadout.hypeByPhase and self.loadout.hypeByPhase[phase]) or 1
		self:emit({ type = "phaseChanged", phase = phase, hype = self.hype })
	end

	interval /= math.max(self.hype, 0.01)

	-- Last orders. Nobody new comes in once the clock runs out -- but see the
	-- end-of-service note below for what happens to whoever is already here.
	if t < self.shiftEndsAt
		and t >= self.nextSpawnAt
		and #self.orders < math.min(maxActive, self.loadout.orderSlots)
	then
		self:spawnOrder()
		self.nextSpawnAt = t + interval
	end

	-- End of service, once the counter is actually clear.
	--
	-- The clock running out used to end the shift on the spot and discard
	-- every ticket still standing there, so a customer who walked in on the
	-- last second vanished -- not served, not even counted as a walkout, just
	-- gone. Anyone already at the counter now gets their full patience to be
	-- served, exactly like any other customer.
	--
	-- This cannot run long: patience ticks down through overtime the same as
	-- ever and the walk-out loop above removes them when it expires, so the
	-- most this can add is one order's patience, and only if the player stops
	-- serving entirely.
	if t >= self.shiftEndsAt and #self.orders == 0 then
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
			cookState = order.cookState,
			readyAt = order.readyAt,
			burnAt = order.burnAt,
			searState = order.searState,
			searStartedAt = order.searStartedAt,
			searGrade = order.searGrade,
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
		shiftDuration = self.loadout.shiftDuration,
		score = self.score,
		combo = self.combo,
		comboMult = ScoreService.comboMultiplier(self.combo),
		bestCombo = self.bestCombo,
		activeOrderId = self.activeOrderId,
		build = self.build,
		fumbleUntil = self.fumbleUntil,
		chore = self.chore,
		phase = self.phase,
		hype = self.hype,
		orders = orders,
		stats = self.stats,
	}
end

return Kitchen

--!strict
-- Daily tasks: three things to go and do, rolled fresh every day.
--
-- These are NOT a separate game mode. They are goals you complete by playing
-- ordinary shifts -- serve this many dishes, clear this many chores, get
-- through a day without anyone walking out -- so the daily gives a reason to
-- come back without asking anyone to play something different.
--
-- Everyone gets the same three tasks on the same day, because they are rolled
-- from the UTC day number. The PRIZE is not: that rolls per claim, per player,
-- or every player on the station would win the same thing and opening it would
-- stop being worth anything.
--
-- Shared rather than server-only so the panel can render targets and prize odds
-- from the same table the server pays out from.


local Config = require(script.Parent.Config)

local DailyDefs = {}

local SECONDS_PER_DAY = 86400

-- How many tasks are set each day.
DailyDefs.TASK_COUNT = 3

-- ------------------------------------------------------------------ time --

-- Which UTC day it is, as an integer. The same number for everyone on the
-- planet at the same moment, which is the entire point of it.
function DailyDefs.dayNumber(atSeconds: number?): number
	return math.floor((atSeconds or os.time()) / SECONDS_PER_DAY)
end

-- The same day as a stamp to store against a record. UTC, hence the "!".
function DailyDefs.dateString(atSeconds: number?): string
	return os.date("!%Y-%m-%d", atSeconds or os.time()) :: string
end

-- Today's stamp, memoised for a second.
--
-- The tick loop compares against this to spot midnight, which meant formatting
-- a date string ten times a second for every player to answer a question whose
-- answer changes once a day. A one second cache cannot miss a rollover by more
-- than a second, and nothing here is that fussy.
local cachedDate = ""
local cachedSecond = -1

function DailyDefs.todayString(): string
	local second = os.clock() // 1
	if second ~= cachedSecond then
		cachedSecond = second
		cachedDate = DailyDefs.dateString()
	end
	return cachedDate
end

-- ------------------------------------------------------------------ tasks --

-- `mode` is how progress accumulates:
--   "sum" -- added up across every shift played today
--   "max" -- the best single shift today, so one great run counts and a
--            hundred bad ones do not add up to it
--
-- Targets are a range, rolled per day, so the same task is not identical every
-- time it comes round. They are sized against a shift of roughly eight to
-- eleven customers: the cumulative ones want two or three shifts, and the
-- single-shift ones want one good one.
DailyDefs.Tasks = {
	serve = {
		id = "serve",
		mode = "sum",
		range = { 18, 30 },
		text = "Serve %d dishes",
		blurb = "Any dish, any grade, across as many shifts as you like.",
	},

	perfect = {
		id = "perfect",
		mode = "sum",
		range = { 10, 18 },
		text = "Serve %d orders at Perfect",
		blurb = "Hand them over while the patience bar is still green.",
	},

	chores = {
		id = "chores",
		mode = "sum",
		range = { 5, 10 },
		text = "Clear %d chores",
		blurb = "The interruptions. Clear them before they time out.",
	},

	clean = {
		id = "clean",
		mode = "sum",
		range = { 1, 2 },
		text = "Finish %d shifts with nobody walking out",
		blurb = "Every customer served. One walkout and the shift does not count.",
	},

	combo = {
		id = "combo",
		mode = "max",
		range = { 8, 14 },
		text = "Reach a combo of %d",
		blurb = "In a single shift. Dropping it means starting the climb again.",
	},

	score = {
		id = "score",
		mode = "max",
		range = { 800, 1600 },
		text = "Score %d in one shift",
		blurb = "Your best shift today counts, so it is worth another go.",
	},
}

-- Fixed order, because iterating a Luau table is not deterministic and the
-- daily roll has to land on the same three tasks for everybody.
DailyDefs.TaskOrder = { "serve", "perfect", "chores", "clean", "combo", "score" }

local function shuffled<T>(list: { T }, rng: Random): { T }
	local copy = table.clone(list)
	for index = #copy, 2, -1 do
		local swap = rng:NextInteger(1, index)
		copy[index], copy[swap] = copy[swap], copy[index]
	end
	return copy
end

-- Today's three tasks, derived entirely from the day number.
function DailyDefs.rollTasks(day: number)
	local rng = Random.new(day)
	local picks = shuffled(DailyDefs.TaskOrder, rng)
	local tasks = {}

	for index = 1, math.min(DailyDefs.TASK_COUNT, #picks) do
		local def = DailyDefs.Tasks[picks[index]]
		local target = rng:NextInteger(def.range[1], def.range[2])

		-- Score targets are rounded so the panel does not read "Score 1327 in
		-- one shift", which looks like a bug rather than a goal.
		if def.id == "score" then
			target = math.floor(target / 100 + 0.5) * 100
		end

		table.insert(tasks, {
			id = def.id,
			target = target,
			progress = 0,
			claimed = false,
		})
	end

	return tasks
end

-- The line the panel shows for a task.
function DailyDefs.describe(task): (string, string)
	local def = DailyDefs.Tasks[task.id]
	if not def then
		return task.id, ""
	end
	return string.format(def.text, task.target), def.blurb
end

function DailyDefs.isComplete(task): boolean
	return (task.progress or 0) >= task.target
end

-- ------------------------------------------------------------------ prize --

-- What claiming a finished task pays. Weighted, and rolled per claim rather
-- than per day: a prize everyone can look up is not a prize.
--
-- Two kinds. `cash` pays out once. `boost` starts a timer instead, which is
-- the more interesting prize: cash is a number that goes up, a boost is a
-- reason to go and play another shift right now.
--
-- Pets drop in later as a third kind. The panel reads `name` whatever it is.
DailyDefs.PrizePool = {
	{ id = "credits_small", weight = 30, kind = "cash", amount = 150,  name = "A handful of credits" },
	{ id = "credits_mid",   weight = 24, kind = "cash", amount = 350,  name = "A decent tip jar" },
	{ id = "credits_large", weight = 14, kind = "cash", amount = 750,  name = "A very good day" },
	{ id = "credits_huge",  weight = 6,  kind = "cash", amount = 1800, name = "Someone tipped in bullion" },

	{
		id = "boost_earnings",
		weight = 16,
		kind = "boost",
		effect = "earnings",
		name = "Station-wide write-up",
	},
	{
		id = "boost_tips",
		weight = 10,
		kind = "boost",
		effect = "tips",
		name = "The locals are feeling generous",
	},
}

-- Rolls a prize, and settles anything about it that varies.
--
-- An earnings boost picks its own strength here rather than carrying a fixed
-- one, so two players who win the same prize do not walk away with the same
-- number. The result is a fresh table, never the pool entry itself: handing
-- back the definition would let a caller mutate the pool for everyone.
function DailyDefs.rollPrize(rng: Random?)
	local roll = rng or Random.new()

	local total = 0
	for _, entry in DailyDefs.PrizePool do
		total += entry.weight
	end

	local chosen = DailyDefs.PrizePool[1]
	local pick = roll:NextNumber() * total
	for _, entry in DailyDefs.PrizePool do
		pick -= entry.weight
		if pick <= 0 then
			chosen = entry
			break
		end
	end

	local prize = {
		id = chosen.id,
		kind = chosen.kind,
		name = chosen.name,
		effect = chosen.effect,
		amount = chosen.amount,
		seconds = if chosen.kind == "boost" then Config.BOOST_SECONDS else nil,
		value = nil :: number?,
	}

	if chosen.effect == "earnings" then
		local range = Config.BOOST_EARNINGS_RANGE
		-- Rounded to whole percent so the panel reads "+23%" rather than
		-- "+23.4712%".
		prize.value = math.floor(roll:NextNumber(range[1], range[2]) * 100 + 0.5) / 100
	end

	return prize
end

-- ------------------------------------------------------------------ boosts --

-- What a boost is worth right now. Reads a profile's boost record and answers
-- in the terms a shift actually needs, so callers never poke at `remaining`
-- themselves.
function DailyDefs.boostValues(boosts)
	local earnings = 0
	local tips = false

	if typeof(boosts) == "table" then
		local e = boosts.earnings
		if typeof(e) == "table" and (e.remaining or 0) > 0 then
			earnings = e.value or 0
		end

		local t = boosts.tips
		if typeof(t) == "table" and (t.remaining or 0) > 0 then
			tips = true
		end
	end

	return earnings, tips
end

-- Starts or extends a boost. Winning one you already have adds its time on
-- rather than replacing it, and keeps the BETTER strength -- being handed a
-- worse write-up should never downgrade the one already running.
function DailyDefs.grantBoost(boosts, prize)
	if typeof(boosts) ~= "table" or prize.kind ~= "boost" then
		return
	end

	local slot = boosts[prize.effect]
	if typeof(slot) ~= "table" then
		slot = { remaining = 0, value = 0 }
		boosts[prize.effect] = slot
	end

	slot.remaining = (slot.remaining or 0) + (prize.seconds or 0)
	if prize.value then
		slot.value = math.max(slot.value or 0, prize.value)
	end
end

-- Runs the clock down. Called from the server tick, so boosts only burn while
-- the player is actually in the game. Returns true if anything expired, so the
-- caller knows the shift loadout may be stale.
function DailyDefs.tickBoosts(boosts, dt: number): boolean
	if typeof(boosts) ~= "table" then
		return false
	end

	local expired = false
	for _, slot in boosts do
		if typeof(slot) == "table" and (slot.remaining or 0) > 0 then
			slot.remaining = math.max(0, slot.remaining - dt)
			if slot.remaining == 0 then
				expired = true
			end
		end
	end
	return expired
end

-- ----------------------------------------------------------------- record --

-- Rolls a fresh set of tasks when the stored record is from another day.
-- Mutates in place and reports whether it changed anything, so the caller
-- knows to save. `streak` counts consecutive days with at least one claim.
function DailyDefs.ensureToday(record, day: number?): boolean
	local dayNumber = day or DailyDefs.dayNumber()
	local today = DailyDefs.dateString(dayNumber * SECONDS_PER_DAY)

	if record.date == today and typeof(record.tasks) == "table" and #record.tasks > 0 then
		return false
	end

	local yesterday = DailyDefs.dateString((dayNumber - 1) * SECONDS_PER_DAY)

	-- A streak counts days you actually CLAIMED something, not days the game
	-- happened to roll you tasks. It is checked here, on the way out of
	-- yesterday, because this is the last moment yesterday's record exists.
	if record.date == yesterday and (record.claimedToday or 0) > 0 then
		record.streak = (record.streak or 0) + 1
	else
		record.streak = 0
	end

	record.date = today
	record.tasks = DailyDefs.rollTasks(dayNumber)
	record.claimedToday = 0
	return true
end

-- Applies one finished shift to today's tasks. Returns true if anything moved,
-- so the caller can skip a save when nothing did.
--
-- `stats` is the Kitchen's shift stats; `score` and `bestCombo` are its
-- headline numbers. Kept here rather than in ShiftService so the rules for
-- what counts live next to the tasks themselves.
function DailyDefs.applyShift(record, stats, score: number, bestCombo: number): boolean
	if typeof(record.tasks) ~= "table" then
		return false
	end

	local contribution = {
		serve = stats.served or 0,
		perfect = stats.perfect or 0,
		chores = stats.chores or 0,
		-- Served at least one customer and lost nobody. The served check stops
		-- an empty shift from quietly counting as a flawless one.
		clean = if (stats.expired or 0) == 0 and (stats.served or 0) > 0 then 1 else 0,
		combo = bestCombo,
		score = score,
	}

	local moved = false
	for _, task in record.tasks do
		local def = DailyDefs.Tasks[task.id]
		local gained = contribution[task.id]
		if def and gained and gained > 0 then
			local before = task.progress or 0
			if def.mode == "max" then
				task.progress = math.max(before, gained)
			else
				task.progress = before + gained
			end
			if task.progress ~= before then
				moved = true
			end
		end
	end

	return moved
end

-- What the client needs to draw the panel and the badge.
--
-- `day` rides along on purpose: the client renders from this rather than
-- calling dayNumber() itself, because os.time() on the client is the player's
-- own machine clock and a clock a day out would show the wrong tasks.
function DailyDefs.statusOf(record, day: number?)
	local dayNumber = day or DailyDefs.dayNumber()

	local tasks = {}
	local claimable = 0

	if typeof(record) == "table" and typeof(record.tasks) == "table" then
		for _, task in record.tasks do
			local complete = DailyDefs.isComplete(task)
			if complete and not task.claimed then
				claimable += 1
			end
			table.insert(tasks, {
				id = task.id,
				target = task.target,
				progress = math.min(task.progress or 0, task.target),
				claimed = task.claimed == true,
				complete = complete,
			})
		end
	end

	return {
		day = dayNumber,
		tasks = tasks,
		claimable = claimable,
		streak = (typeof(record) == "table" and record.streak) or 0,
	}
end

return DailyDefs

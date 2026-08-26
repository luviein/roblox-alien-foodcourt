--!strict
-- Daily tasks, prizes and boosts.
--
-- The boost tests are the ones that matter most: a bug in there is a live
-- exploit rather than a wrong number on a screen, and this file exists partly
-- because one shipped -- boosts ticked down in memory without marking the
-- profile dirty, so relogging handed the prize back at full length.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyDefs = require(Shared.DailyDefs)

local Runner = require(script.Parent.Runner)

local DAY = 20000   -- an arbitrary fixed day, so results never move with time

return function()
	local t = Runner.new("daily")

	-- ------------------------------------------------------------- rolling --

	local a = DailyDefs.rollTasks(DAY)
	local b = DailyDefs.rollTasks(DAY)

	t:equal("rolls TASK_COUNT tasks", #a, DailyDefs.TASK_COUNT)

	-- The whole premise of a daily is that everyone gets the same one.
	local sameIds, sameTargets = true, true
	for index, task in a do
		if task.id ~= b[index].id then
			sameIds = false
		end
		if task.target ~= b[index].target then
			sameTargets = false
		end
	end
	t:check("same day rolls the same task ids", sameIds)
	t:check("same day rolls the same targets", sameTargets)

	local seen = {}
	local duplicates = false
	for _, task in a do
		if seen[task.id] then
			duplicates = true
		end
		seen[task.id] = true
	end
	t:check("no duplicate tasks in a day", not duplicates)

	local inRange, known = true, true
	for _, task in a do
		local def = DailyDefs.Tasks[task.id]
		if not def then
			known = false
		elseif task.target < def.range[1] or task.target > def.range[2] then
			inRange = false
		end
	end
	t:check("every rolled task is a known task", known)
	t:check("targets sit inside their range", inRange)

	-- Different days should not all land on the same three. Ten days is plenty
	-- to catch a seed that is being ignored entirely.
	local signatures = {}
	local distinct = 0
	for offset = 0, 9 do
		local tasks = DailyDefs.rollTasks(DAY + offset)
		local parts = {}
		for _, task in tasks do
			table.insert(parts, task.id .. ":" .. tostring(task.target))
		end
		local signature = table.concat(parts, ",")
		if not signatures[signature] then
			signatures[signature] = true
			distinct += 1
		end
	end
	t:check("different days differ", distinct > 1, distinct .. " distinct over 10 days")

	-- ---------------------------------------------------------- completion --

	t:check("progress below target is incomplete",
		not DailyDefs.isComplete({ target = 10, progress = 9 }))
	t:check("progress at target is complete",
		DailyDefs.isComplete({ target = 10, progress = 10 }))
	t:check("progress past target is complete",
		DailyDefs.isComplete({ target = 10, progress = 11 }))

	-- ------------------------------------------------------------- applying --

	local function recordWith(id: string, target: number, progress: number)
		return { tasks = { { id = id, target = target, progress = progress, claimed = false } } }
	end

	local function shift(served, perfect, chores, expired)
		return {
			served = served, perfect = perfect, chores = chores, expired = expired,
			good = 0, sloppy = 0, failed = 0,
		}
	end

	local sum = recordWith("serve", 30, 4)
	DailyDefs.applyShift(sum, shift(6, 3, 2, 0), 500, 5)
	t:equal("sum tasks accumulate", sum.tasks[1].progress, 10)

	local best = recordWith("combo", 20, 12)
	DailyDefs.applyShift(best, shift(6, 3, 2, 0), 500, 8)
	t:equal("max tasks keep the better run", best.tasks[1].progress, 12)
	DailyDefs.applyShift(best, shift(6, 3, 2, 0), 500, 15)
	t:equal("max tasks take a new best", best.tasks[1].progress, 15)

	local clean = recordWith("clean", 3, 0)
	DailyDefs.applyShift(clean, shift(6, 3, 2, 0), 500, 5)
	t:equal("a flawless shift counts", clean.tasks[1].progress, 1)
	DailyDefs.applyShift(clean, shift(6, 3, 2, 1), 500, 5)
	t:equal("a shift with a walkout does not", clean.tasks[1].progress, 1)
	DailyDefs.applyShift(clean, shift(0, 0, 0, 0), 0, 0)
	t:equal("an empty shift is not flawless", clean.tasks[1].progress, 1)

	-- --------------------------------------------------------------- record --

	local record = { date = "", tasks = {}, claimedToday = 0, streak = 0 }

	t:check("a blank record rerolls", DailyDefs.ensureToday(record, DAY))
	t:equal("and is stamped with the day",
		record.date, DailyDefs.dateString(DAY * 86400))
	t:check("a current record does not reroll", not DailyDefs.ensureToday(record, DAY))

	-- Played yesterday AND claimed: the streak survives.
	record.claimedToday = 1
	DailyDefs.ensureToday(record, DAY + 1)
	t:equal("claiming yesterday continues the streak", record.streak, 1)
	t:equal("claim count resets with the new day", record.claimedToday, 0)

	-- Skipped a day: back to nothing.
	record.claimedToday = 1
	DailyDefs.ensureToday(record, DAY + 5)
	t:equal("a missed day breaks the streak", record.streak, 0)

	-- Turned up but claimed nothing: also nothing.
	record.claimedToday = 0
	record.streak = 4
	DailyDefs.ensureToday(record, DAY + 6)
	t:equal("a day without a claim breaks the streak", record.streak, 0)

	-- --------------------------------------------------------------- status --

	local status = DailyDefs.statusOf({
		streak = 3,
		tasks = {
			{ id = "serve", target = 10, progress = 10, claimed = false },
			{ id = "chores", target = 5, progress = 5, claimed = true },
			{ id = "combo", target = 9, progress = 2, claimed = false },
		},
	}, DAY)

	t:equal("counts only unclaimed finished tasks", status.claimable, 1)
	t:equal("carries the streak", status.streak, 3)
	t:equal("carries the day", status.day, DAY)
	t:equal("clamps progress to the target", status.tasks[1].progress, 10)

	-- --------------------------------------------------------------- prizes --

	local validKinds, valuesInRange = true, true
	for _ = 1, 200 do
		local prize = DailyDefs.rollPrize()
		if prize.kind ~= "cash" and prize.kind ~= "boost" then
			validKinds = false
		end
		if prize.effect == "earnings" then
			local range = Config.BOOST_EARNINGS_RANGE
			-- Rounded to whole percent on the way out, so allow a percent of
			-- slack at each end rather than testing the raw draw.
			if not prize.value
				or prize.value < range[1] - 0.011
				or prize.value > range[2] + 0.011
			then
				valuesInRange = false
			end
		end
		if prize.kind == "boost" and prize.seconds ~= Config.BOOST_SECONDS then
			validKinds = false
		end
	end
	t:check("every prize has a known kind", validKinds)
	t:check("earnings rolls inside its range", valuesInRange)

	-- --------------------------------------------------------------- boosts --

	local boosts = {
		earnings = { remaining = 0, value = 0 },
		tips = { remaining = 0 },
	}

	local earnings, tips = DailyDefs.boostValues(boosts)
	t:equal("no earnings boost when expired", earnings, 0)
	t:equal("no tip boost when expired", tips, false)

	DailyDefs.grantBoost(boosts, {
		kind = "boost", effect = "earnings", seconds = 600, value = 0.20,
	})
	earnings = DailyDefs.boostValues(boosts)
	t:near("a granted boost is worth its roll", earnings, 0.20)
	t:equal("and carries its time", boosts.earnings.remaining, 600)

	-- Winning it again adds time and keeps the better rate.
	DailyDefs.grantBoost(boosts, {
		kind = "boost", effect = "earnings", seconds = 600, value = 0.10,
	})
	t:equal("a second win extends the clock", boosts.earnings.remaining, 1200)
	t:near("and never downgrades the rate", boosts.earnings.value, 0.20)

	DailyDefs.grantBoost(boosts, {
		kind = "boost", effect = "earnings", seconds = 600, value = 0.30,
	})
	t:near("but a better rate wins", boosts.earnings.value, 0.30)

	-- A cash prize must not start a timer.
	local untouched = { earnings = { remaining = 0, value = 0 }, tips = { remaining = 0 } }
	DailyDefs.grantBoost(untouched, { kind = "cash", amount = 500 })
	t:equal("cash prizes start no boost", untouched.earnings.remaining, 0)

	-- Ticking down, and stopping at zero rather than going negative.
	DailyDefs.grantBoost(boosts, { kind = "boost", effect = "tips", seconds = 10 })
	DailyDefs.tickBoosts(boosts, 4)
	t:equal("tips burn down", boosts.tips.remaining, 6)
	DailyDefs.tickBoosts(boosts, 100)
	t:equal("and floor at zero", boosts.tips.remaining, 0)

	local _, tipsActive = DailyDefs.boostValues(boosts)
	t:equal("an expired tip boost is inactive", tipsActive, false)

	-- ----------------------------------------------------------------- time --

	t:equal("a day number round trips",
		DailyDefs.dayNumber(DAY * 86400), DAY)
	t:check("consecutive days give different stamps",
		DailyDefs.dateString(DAY * 86400) ~= DailyDefs.dateString((DAY + 1) * 86400))

	return t
end

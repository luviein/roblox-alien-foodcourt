--!strict
-- The Understudy.
--
-- The assertion that matters most is the last one in this file: an hour away
-- must never approach an hour of cooking. Everything else here is arithmetic;
-- that one is the design rule, and it is the one a future tuning change could
-- quietly break.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local OfflineDefs = require(Shared.OfflineDefs)

local Runner = require(script.Parent.Runner)

local HOUR = 3600

-- A profile that has finished ten shifts averaging 200 c each.
local function player(overrides)
	local profile = {
		recentEarnings = { 200, 200, 200, 200, 200 },
		stats = { shifts = 10, served = 90, bestScore = 0, bestCombo = 0 },
		upgrades = {},
	}
	for key, value in (overrides or {}) do
		profile[key] = value
	end
	return profile
end

return function()
	local t = Runner.new("offline")

	-- ------------------------------------------------------------- the rate --

	t:equal("no history means no rate", OfflineDefs.perShift({}), 0)
	t:equal("nil history means no rate", OfflineDefs.perShift(nil), 0)
	t:equal("the rate is the average", OfflineDefs.perShift({ 100, 200, 300 }), 200)

	-- The whole point: a better cook is worth more while away.
	local weak = OfflineDefs.accrue(player({ recentEarnings = { 50 } }), 4 * HOUR)
	local strong = OfflineDefs.accrue(player({ recentEarnings = { 400 } }), 4 * HOUR)
	t:check("offline pay scales with skill", strong.amount > weak.amount * 3,
		string.format("%d vs %d", strong.amount, weak.amount))

	-- --------------------------------------------------------------- the cap --

	t:equal("the base cap is the config value",
		OfflineDefs.capHours(player()), Config.OFFLINE_CAP_HOURS)
	t:equal("a cell adds hours",
		OfflineDefs.capHours(player({ upgrades = { cell = 2 } })),
		Config.OFFLINE_CAP_HOURS + 2 * 4)

	local capped = OfflineDefs.accrue(player(), 40 * HOUR)
	local atCap = OfflineDefs.accrue(player(), Config.OFFLINE_CAP_HOURS * HOUR)
	t:equal("time past the cap is not counted",
		capped.seconds, Config.OFFLINE_CAP_HOURS * HOUR)
	t:equal("and pays exactly the cap", capped.amount, atCap.amount)
	t:check("being over the cap is reported", capped.capped)
	t:check("being under it is not", not atCap.capped)

	-- The real absence is kept alongside the part that was paid for, or the
	-- collect screen tells someone away for days that they were away for hours.
	t:equal("the true absence is remembered", capped.elapsed, 40 * HOUR)
	t:check("and is longer than what the cell held", capped.elapsed > capped.seconds)
	t:equal("an uncapped absence has them equal", atCap.elapsed, atCap.seconds)

	local bigger = OfflineDefs.accrue(player({ upgrades = { cell = 3 } }), 40 * HOUR)
	t:check("a bigger cell earns more from the same absence",
		bigger.amount > capped.amount)

	-- --------------------------------------------------------- nothing owed --

	t:equal("a player who has never cooked earns nothing",
		OfflineDefs.accrue(player({ recentEarnings = {} }), 4 * HOUR).amount, 0)
	t:equal("and neither does one with no finished shifts",
		OfflineDefs.accrue(
			player({ stats = { shifts = 0, served = 0 } }), 4 * HOUR).amount, 0)
	t:equal("no time away pays nothing", OfflineDefs.accrue(player(), 0).amount, 0)

	-- The threshold is one run of the impression, and there must be no gap
	-- between "too short to report" and "long enough to pay". A separate
	-- minimum used to sit below it, so everything in between silently paid
	-- nothing and read as a broken feature.
	local oneRun = OfflineDefs.secondsPerShift()
	t:equal("under one run pays nothing",
		OfflineDefs.accrue(player(), oneRun - 1).amount, 0)
	t:check("exactly one run pays something",
		OfflineDefs.accrue(player(), oneRun).amount > 0)

	-- Partial time above the threshold is credited rather than discarded.
	local half = OfflineDefs.accrue(player(), oneRun * 1.5)
	local full = OfflineDefs.accrue(player(), oneRun)
	local double = OfflineDefs.accrue(player(), oneRun * 2)
	t:check("an extra half run pays more than a whole one", half.amount > full.amount)
	t:check("and less than two", half.amount < double.amount)
	t:check("time scales the payout linearly",
		math.abs(double.amount - full.amount * 2) <= 1,
		string.format("%d vs %d", double.amount, full.amount * 2))

	-- --------------------------------------------------------- every field --

	-- Structural, and it earns its place: a refactor removed the local `hours`
	-- while one line still read it, so accrue threw on nil arithmetic at the
	-- very last statement -- after all the early returns, meaning it broke
	-- exactly when it was about to pay out and never when it was not.
	--
	-- Checking the whole shape catches the next one of those without anyone
	-- having to guess which field it will be.
	local shape = OfflineDefs.accrue(player(), 3 * HOUR)
	for _, field in { "seconds", "elapsed", "amount", "ran", "served", "left", "asked" } do
		t:equal("report." .. field .. " is a number", typeof(shape[field]), "number")
	end
	t:equal("report.capped is a boolean", typeof(shape.capped), "boolean")

	-- ------------------------------------------------------------ the story --

	-- The collect screen has to be describing the payout, not decorating it.
	local report = OfflineDefs.accrue(player(), 6 * HOUR)
	t:equal("it ran a shift per half hour",
		report.ran, math.floor(6 * Config.OFFLINE_SHIFTS_PER_HOUR))
	t:check("somebody was served", report.served > 0)
	t:check("and somebody left", report.left > 0)
	t:check("more were served than left", report.served > report.left)
	t:check("somebody asked", report.asked >= 1)
	t:check("a note is chosen", OfflineDefs.noteFor(report) ~= "")

	-- The same report must read the same way twice; a note that reshuffles
	-- under the player on the next snapshot looks like a glitch.
	t:equal("the note is stable",
		OfflineDefs.noteFor(report), OfflineDefs.noteFor(report))

	-- ------------------------------------------------------------- pending --

	local pending = { amount = 0, seconds = 0, ran = 0, served = 0, left = 0, asked = 0 }
	OfflineDefs.addPending(pending, report)
	t:equal("collecting later keeps the first lot", pending.amount, report.amount)

	OfflineDefs.addPending(pending, report)
	t:equal("and adds the second", pending.amount, report.amount * 2)
	t:equal("along with its time", pending.seconds, report.seconds * 2)

	-- A capped absence folded into the pot has to stay flagged, or the overflow
	-- goes unmentioned the moment two returns are collected together.
	local mixed = { amount = 0, seconds = 0, elapsed = 0, ran = 0, served = 0, left = 0, asked = 0, capped = false }
	OfflineDefs.addPending(mixed, OfflineDefs.accrue(player(), 2 * HOUR))
	t:check("an uncapped return leaves the pot uncapped", not mixed.capped)
	OfflineDefs.addPending(mixed, OfflineDefs.accrue(player(), 40 * HOUR))
	t:check("a capped one flags the whole pot", mixed.capped)

	OfflineDefs.clearPending(pending)
	t:equal("collecting empties the pot", pending.amount, 0)
	t:equal("and its story", pending.ran, 0)
	t:equal("and its overflow flag", pending.capped, false)

	local ignored = { amount = 5, seconds = 0, ran = 0, served = 0, left = 0, asked = 0 }
	OfflineDefs.addPending(ignored, OfflineDefs.accrue(player(), 0))
	t:equal("an empty report adds nothing", ignored.amount, 5)

	-- -------------------------------------------------------------- format --

	t:equal("hours and minutes", OfflineDefs.formatSpan(8 * HOUR), "8h 00m")
	t:equal("minutes alone under an hour", OfflineDefs.formatSpan(14 * 60), "14m")
	t:equal("a part hour", OfflineDefs.formatSpan(HOUR + 5 * 60), "1h 05m")

	-- ----------------------------------------------------- THE DESIGN RULE --

	-- An hour away must never approach an hour of cooking. A shift cycle is
	-- roughly two minutes of real time counting the draft and the results
	-- screen, so an hour of play is about thirty shifts.
	local SHIFTS_PER_ACTIVE_HOUR = 30
	local oneHour = OfflineDefs.accrue(player(), HOUR)
	local activeHour = 200 * SHIFTS_PER_ACTIVE_HOUR

	t:check("an hour offline is under a tenth of an hour played",
		oneHour.amount < activeHour * 0.1,
		string.format("%d offline vs %d played", oneHour.amount, activeHour))

	-- And the same must hold with every cell level bought, since that is the
	-- upgrade most likely to be raised later without thinking about this.
	local maxedCell = OfflineDefs.accrue(
		player({ upgrades = { cell = 3 } }), HOUR)
	t:equal("the cell buys time, never rate", maxedCell.amount, oneHour.amount)

	return t
end

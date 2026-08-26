--!strict
-- The Understudy: what the counter earns while you are not standing at it.
--
-- Sector 7 licenses a counter on one condition -- it is never unstaffed. When
-- you leave you are in breach, so rather than pull the licence the station
-- runs a Continuity Impression: a recording of your last few shifts, played
-- back through a service unit that stands where you stand and does what you
-- did. It plates the burger perfectly and hands it to the wrong customer.
--
-- That premise is not decoration. It is doing the mechanical work, and every
-- rule below falls out of it:
--
--   pay scales with the player   it is a recording OF THEM. A better cook
--                                makes a better recording.
--   it can never beat playing    a copy is lossy. It cannot exceed its source.
--   it is capped in hours        the cell holds only so many hours before the
--                                recording degrades into noise.
--   upgrades buy TIME, not rate  the station sells a bigger cell. It will not
--                                sell fidelity, because a perfect copy of a
--                                worker raises questions nobody at Sector 7
--                                wants answered.
--
-- That last one is the load-bearing joke: it is why the upgrade cannot break
-- the economy. Raising the rate would make not-playing better. Raising the cap
-- only ever helps someone who was already away.

local Config = require(script.Parent.Config)
local ShopDefs = require(script.Parent.ShopDefs)

local OfflineDefs = {}

-- ------------------------------------------------------------------- rate --

-- What one shift is currently worth to this player, averaged over their last
-- few. This is the number the whole feature scales from: cash stays what skill
-- is worth, and the understudy simply hands back a slice of it.
--
-- A flat rate was the alternative and it is the wrong one -- it pays a player
-- who cannot cook the same as one who can, which breaks the rule the rest of
-- the game is built on.
function OfflineDefs.perShift(recentEarnings): number
	if typeof(recentEarnings) ~= "table" or #recentEarnings == 0 then
		return 0
	end

	local total = 0
	for _, amount in recentEarnings do
		total += amount
	end
	return total / #recentEarnings
end

-- How many hours the cell holds before the recording degrades.
function OfflineDefs.capHours(profile): number
	local upgrades = (profile and profile.upgrades) or {}
	return Config.OFFLINE_CAP_HOURS + ShopDefs.valueOf("cell", upgrades.cell or 0)
end

-- How long one run of the impression takes, and so the shortest absence worth
-- reporting: below this it never finished a shift, and there is nothing to
-- tell you about.
--
-- DERIVED rather than configured. It was a separate number once and the two
-- disagreed: the config claimed a two minute floor while the arithmetic threw
-- away anything under thirty, so everything in between silently paid nothing
-- and looked like a broken feature.
function OfflineDefs.secondsPerShift(): number
	return 3600 / math.max(Config.OFFLINE_SHIFTS_PER_HOUR, 0.0001)
end

-- ---------------------------------------------------------------- accrual --

-- What the understudy earned over `seconds` away, plus the numbers the collect
-- screen reports. Pure: hand it a profile and a duration, get a report.
--
-- `served` and `left` are derived from the player's own average headcount
-- rather than invented, so the story on the collect screen is describing the
-- payout rather than decorating it.
function OfflineDefs.accrue(profile, seconds: number)
	local capSeconds = OfflineDefs.capHours(profile) * 3600
	local counted = math.clamp(seconds, 0, capSeconds)

	local stats = (profile and profile.stats) or {}
	local perShift = OfflineDefs.perShift(profile and profile.recentEarnings)

	local report = {
		-- `seconds` is what the cell actually held and paid for. `elapsed` is
		-- how long they were really gone. They differ once the cell fills, and
		-- the collect screen has to show both -- reporting only the capped
		-- figure told someone away for three days that they had been away for
		-- eight hours.
		seconds = counted,
		elapsed = math.max(seconds, 0),
		capped = seconds > capSeconds,
		amount = 0,
		ran = 0,
		served = 0,
		left = 0,
		asked = 0,
	}

	-- Nothing to copy yet. A profile that has never finished a shift has no
	-- recording to play back, which is also why a brand new player cannot
	-- collect anything on their very first join.
	if perShift <= 0 or (stats.shifts or 0) <= 0 then
		return report
	end

	-- Away for less than one run of the impression: it never finished a shift,
	-- so there is nothing to report and no reason to interrupt anyone with a
	-- full screen panel over a handful of credits.
	if counted < OfflineDefs.secondsPerShift() then
		return report
	end

	-- FRACTIONAL on purpose. Flooring this first threw away up to one whole
	-- shift of time every return, so being away an hour and a half paid the
	-- same as an hour. `ran` is rounded for the report; the money is not.
	local shifts = (counted / 3600) * Config.OFFLINE_SHIFTS_PER_HOUR
	report.ran = math.max(1, math.floor(shifts + 0.5))

	-- The impression is worth a fraction of the real thing, and the walkouts
	-- ARE that fraction: what it loses at the counter is what it loses on the
	-- till. One number, so the story cannot drift from the payout.
	local keeps = 1 - Config.OFFLINE_WALKOUT_RATE
	report.amount = math.floor(shifts * perShift * keeps + 0.5)

	local perShiftServed = (stats.served or 0) / math.max(stats.shifts or 1, 1)
	local attempted = shifts * perShiftServed
	report.left = math.floor(attempted * Config.OFFLINE_WALKOUT_RATE + 0.5)
	report.served = math.max(0, math.floor(attempted + 0.5) - report.left)

	-- Someone always asks. Slowly more of them the longer you are gone.
	report.asked = math.clamp(1 + math.floor(hours / 3), 1, 6)

	return report
end

-- Folds a fresh report into whatever is already waiting. Someone who leaves
-- without collecting must not lose the last lot.
function OfflineDefs.addPending(pending, report)
	if typeof(pending) ~= "table" or report.amount <= 0 then
		return pending
	end

	pending.amount = (pending.amount or 0) + report.amount
	pending.seconds = (pending.seconds or 0) + report.seconds
	pending.elapsed = (pending.elapsed or 0) + (report.elapsed or report.seconds)
	pending.ran = (pending.ran or 0) + report.ran
	pending.served = (pending.served or 0) + report.served
	pending.left = (pending.left or 0) + report.left
	pending.asked = math.max(pending.asked or 0, report.asked)

	-- Sticky. If any absence folded in here overflowed the cell, the collect
	-- screen still has to admit it.
	pending.capped = (pending.capped == true) or (report.capped == true)
	return pending
end

function OfflineDefs.clearPending(pending)
	pending.amount = 0
	pending.seconds = 0
	pending.elapsed = 0
	pending.ran = 0
	pending.served = 0
	pending.left = 0
	pending.asked = 0
	pending.capped = false
end

-- ------------------------------------------------------------------ report --

-- "8h 00m", or "14m" under an hour. Its own helper because the collect screen
-- and the shift clock want different things -- this one never shows seconds.
function OfflineDefs.formatSpan(seconds: number): string
	local totalMinutes = math.floor(seconds / 60)
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60

	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm", minutes)
end

-- The lines Zorb leaves on the counter. Kept here rather than in the UI so the
-- wording lives next to the numbers it is describing.
--
-- The paperwork calls it a Continuity Impression. Everyone calls it the
-- understudy, and that gap is the joke.
OfflineDefs.NOTES = {
	"It did the thing with the bun again. I moved the bun. It found a new bun.",
	"It served the queue in the order they arrived yesterday.",
	"It wiped a counter that was already clean for two hours.",
	"Someone complimented it. It did not respond. They left happy.",
	"It has learned to reach for the fryer. The fryer is not there.",
	"I told it you were coming back. It did not stop.",
}

function OfflineDefs.noteFor(report): string
	if report.ran <= 0 then
		return ""
	end
	-- Chosen from the numbers rather than at random, so re-reading the same
	-- collect screen does not reshuffle the note under the player.
	local index = (report.ran + report.left) % #OfflineDefs.NOTES + 1
	return OfflineDefs.NOTES[index]
end

return OfflineDefs

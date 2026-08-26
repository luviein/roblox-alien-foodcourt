--!strict
-- The daily challenge: one fixed shift a day, the same one for every player.
--
-- The whole value of a daily is that two scores are comparable, which means
-- everything that could differ between two players has to be nailed down:
--
--   the menu      - drafted from the seed, not from what you have unlocked
--   the weather   - rolled from the seed
--   the tickets   - the order bag takes the seed, so the sequence matches
--   the chores    - they draw from that same bag rng, so they match too
--   base hype     - Config.BASE_HYPE flat, ignoring rebirths
--   patience,     - the unupgraded values, ignoring everything in the shop
--   slots, length
--
-- If any one of those leaked through, a rebirthed player with a maxed shop
-- would post a bigger number for the same cooking, and the leaderboard this is
-- eventually for would measure progress rather than skill.
--
-- Shared rather than server-only so the client can render today's challenge
-- from the same maths instead of needing a remote to ask what it is.

local Config = require(script.Parent.Config)
local DishDefs = require(script.Parent.DishDefs)
local HypeDefs = require(script.Parent.HypeDefs)

local DailyDefs = {}

local SECONDS_PER_DAY = 86400

-- How many dishes are on a daily menu. Fixed rather than following the
-- player's menuSlots, for the same reason as everything else here.
DailyDefs.MENU_SIZE = 3

-- ------------------------------------------------------------------ time --

-- Which UTC day it is, as an integer. The same number for everyone on the
-- planet at the same moment, which is the entire point of it.
function DailyDefs.dayNumber(atSeconds: number?): number
	return math.floor((atSeconds or os.time()) / SECONDS_PER_DAY)
end

-- The same day as a stamp to store against a score. UTC, hence the "!".
function DailyDefs.dateString(atSeconds: number?): string
	return os.date("!%Y-%m-%d", atSeconds or os.time()) :: string
end

-- ------------------------------------------------------------- challenge --

-- Today's challenge, derived entirely from the day number.
--
-- The menu takes one dish from each third of the catalog, which is ordered by
-- difficulty. That is deliberate: three dishes drawn at random could hand a
-- first-day player three of the hardest dishes in the game and nothing they
-- have ever cooked, and could equally hand out three trivial ones. A dish from
-- each third guarantees both a foothold and something to actually struggle
-- with, every single day.
--
-- Everything is drawn from ONE rng in a fixed order. Separate rngs seeded off
-- the same day would correlate the menu with the weather in ways that are hard
-- to see and impossible to debug.
function DailyDefs.challengeFor(day: number)
	local rng = Random.new(day)
	local catalog = DishDefs.ActiveMenu
	local menu = {}

	local tiers = DailyDefs.MENU_SIZE
	local perTier = math.max(1, math.floor(#catalog / tiers))

	for tier = 0, tiers - 1 do
		local lo = tier * perTier + 1
		-- The last tier absorbs the remainder when the catalog does not divide
		-- evenly, so no dish is ever unreachable.
		local hi = if tier == tiers - 1 then #catalog else (tier + 1) * perTier
		if lo <= #catalog then
			table.insert(menu, catalog[rng:NextInteger(lo, math.max(lo, hi))])
		end
	end

	local weather = HypeDefs.rollWeather(rng)

	return {
		day = day,
		date = DailyDefs.dateString(day * SECONDS_PER_DAY),
		menu = menu,
		seed = day,
		weather = weather.id,
		weatherName = weather.name,
		weatherBlurb = weather.blurb,
	}
end

function DailyDefs.today()
	return DailyDefs.challengeFor(DailyDefs.dayNumber())
end

-- ----------------------------------------------------------------- reward --

-- Paid once per day, on the first run. Later runs still record a better score
-- but pay nothing, so replaying is about the number rather than the money --
-- otherwise the daily becomes the most efficient way to farm cash and the
-- restaurant stops being the game.
function DailyDefs.reward(score: number): number
	return math.floor(
		Config.DAILY_REWARD_BASE + score * Config.DAILY_REWARD_PER_POINT + 0.5)
end

-- ---------------------------------------------------------------- status --

-- What the player's saved `daily` record means for today. Pure, so the client
-- can render the panel and the server can decide the payout from one place.
-- `day` rides along in the result on purpose. The client renders the panel from
-- this number rather than calling dayNumber() itself, because os.time() on the
-- client is the player's own machine clock: someone whose clock is a day out
-- would otherwise be shown a menu the server is not going to run.
function DailyDefs.statusOf(record, day: number?)
	local dayNumber = day or DailyDefs.dayNumber()
	local today = DailyDefs.dateString(dayNumber * SECONDS_PER_DAY)

	if typeof(record) ~= "table" or record.date ~= today then
		return {
			day = dayNumber,
			played = false,
			score = 0,
			streak = (record and record.streak) or 0,
		}
	end

	return {
		day = dayNumber,
		played = true,
		score = record.score or 0,
		streak = record.streak or 0,
	}
end

return DailyDefs

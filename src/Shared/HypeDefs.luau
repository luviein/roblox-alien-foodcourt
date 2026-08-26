--!strict
-- The day: its phases, its weather, and how a menu turns into hype.
--
-- Hype drives how fast customers arrive. A well-drafted menu fills the queue;
-- a badly drafted one leaves you standing around earning nothing. It is the
-- only system in the game where the decision happens BEFORE the shift, and it
-- is deliberately visible up front -- a rule you cannot see is not strategy,
-- it is a guess.
--
-- Hype is recomputed per phase rather than once per shift, which is what makes
-- the draft interesting: a breakfast dish earns its place for thirty seconds
-- and then stops, so the question is what shape your menu has across the whole
-- day rather than what its average is.

local Config = require(script.Parent.Config)

local HypeDefs = {}

-- One shift is one day, in three equal parts.
HypeDefs.Phases = { "morning", "afternoon", "night" }

HypeDefs.PhaseName = {
	morning = "Morning",
	afternoon = "Afternoon",
	night = "Night",
}

-- Weather is usually nothing. That keeps it a bonus you sometimes catch rather
-- than a fourth axis you have to plan around every single day.
HypeDefs.WeatherDeck = {
	{ id = "clear",  name = "Clear Skies",       weight = 5, blurb = "Nothing doing." },
	{ id = "sunny",  name = "Triple-Sun Glare",  weight = 2, blurb = "They want it fast and cold." },
	{ id = "rain",   name = "Methane Rain",      weight = 2, blurb = "Comfort food weather." },
	{ id = "cold",   name = "Nebula Frost",      weight = 2, blurb = "Anything hot, please." },
}

-- Every bonus and penalty is the same size on purpose. It keeps the maths
-- legible to a player counting in their head, and it means no single tag can
-- run away with a draft.
HypeDefs.STEP = 0.05

-- Tags scale hype rather than adding to it. This matters: base hype is 0.15 for
-- a new player, so a flat "+0.05" would be a third of their whole counter,
-- while being trivial to someone rebirthed. As a multiplier, +5% means the same
-- thing to everyone.
--
-- These cap how far one menu can swing you either side of your own base. Below
-- the floor there is nothing to do; above the ceiling more customers arrive
-- than anyone can physically serve, which is not difficulty, just loss.
HypeDefs.SWING_DOWN = 0.60   -- worst menu: 60% of base
HypeDefs.SWING_UP = 1.35     -- best menu: 135% of base

-- Absolute floor and ceiling, whatever the base. 1.00 is a full house.
HypeDefs.MIN = 0.05
HypeDefs.MAX = 1.00

HypeDefs.HEALTHY_PAIR = 2   -- this many healthy dishes gives the bonus
HypeDefs.FATTY_LIMIT = 3    -- this many fatty dishes starts costing you

function HypeDefs.rollWeather(rng: Random)
	local total = 0
	for _, entry in HypeDefs.WeatherDeck do
		total += entry.weight
	end

	local pick = rng:NextNumber() * total
	for _, entry in HypeDefs.WeatherDeck do
		pick -= entry.weight
		if pick <= 0 then
			return entry
		end
	end
	return HypeDefs.WeatherDeck[1]
end

function HypeDefs.weather(id: string)
	for _, entry in HypeDefs.WeatherDeck do
		if entry.id == id then
			return entry
		end
	end
	return HypeDefs.WeatherDeck[1]
end

-- Which third of the shift a given elapsed time falls in.
function HypeDefs.phaseAt(elapsed: number, shiftDuration: number): string
	local slice = shiftDuration / #HypeDefs.Phases
	local index = math.clamp(math.floor(elapsed / slice) + 1, 1, #HypeDefs.Phases)
	return HypeDefs.Phases[index]
end

-- Works out hype for one phase, and returns the reasons alongside it so the
-- draft screen can show its working rather than just a number.
--
-- `menu` is dish definitions, `stale` a set of dish ids served in the last few
-- days (see HypeDefs.staleSet).
-- `base` is where a neutral menu sits: Config.BASE_HYPE plus whatever rebirths
-- have added. Tags move hype relative to it.
function HypeDefs.evaluate(menu, phase: string, weatherId: string, stale, base: number?): (number, { string })
	local origin = base or Config.BASE_HYPE

	-- Accumulated as a multiplier around 1.0, then applied to the base at the
	-- end, so every tag is worth the same PROPORTION to every player.
	local modifier = 1.0
	local reasons = {}

	local healthy, fatty = 0, 0

	for _, dish in menu do
		local tags = dish.hype or {}

		if tags.healthy then
			healthy += 1
		end
		if tags.fatty then
			fatty += 1
		end

		if tags.weather and tags.weather == weatherId then
			modifier += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s suits the weather")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "morning" and tags.breakfast then
			modifier += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s is a breakfast dish")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "night" and tags.lateNight then
			modifier += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s sells late")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if tags.alwaysHyped then
			modifier += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s is always wanted")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "morning" and tags.smelly then
			modifier -= HypeDefs.STEP
			table.insert(reasons, ("-%d%% %s is too much this early")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		-- Anything served in the last MENU_STALE_DAYS days. Two rather than one
		-- on purpose: with a one day memory you could alternate between two
		-- menus forever and never once pay a repeat penalty, which is exactly
		-- the habit this is meant to discourage.
		if stale and stale[dish.id] then
			modifier -= HypeDefs.STEP
			table.insert(reasons, ("-%d%% %s again so soon")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end
	end

	if healthy >= HypeDefs.HEALTHY_PAIR then
		modifier += HypeDefs.STEP
		table.insert(reasons, ("+%d%% a balanced menu"):format(HypeDefs.STEP * 100))
	end

	if fatty >= HypeDefs.FATTY_LIMIT then
		modifier -= HypeDefs.STEP
		table.insert(reasons, ("-%d%% too much fried food"):format(HypeDefs.STEP * 100))
	end

	return math.clamp(
		origin * modifier,
		math.max(origin * HypeDefs.SWING_DOWN, HypeDefs.MIN),
		math.min(origin * HypeDefs.SWING_UP, HypeDefs.MAX)
	), reasons
end

-- Flattens the last few days of menus into one set of "served too recently"
-- dish ids. Shared so the draft preview and the shift itself cannot disagree
-- about what counts as stale.
-- Which dishes were served recently enough to cost hype if drafted again.
--
-- `unlockedCount` and `slots` are optional, and when both are given they cap
-- how much of the menu can be stale at once. That cap is the important part:
-- with five dishes unlocked and three slots, a plain history lookup marks
-- almost everything TOO SOON and there is no draft that avoids it. A penalty
-- you cannot play around is not a decision, it is a tax on being new.
--
-- The cap leaves at least `slots` dishes fresh, so a clean menu always exists.
-- It stops mattering as the catalogue grows: at fifteen dishes it never binds,
-- and the full history applies again.
function HypeDefs.staleSet(recentMenus, unlockedCount: number?, slots: number?): { [string]: boolean }
	local set = {}
	local count = 0

	local cap = math.huge
	if unlockedCount and slots then
		cap = math.max(0, unlockedCount - slots)
	end

	-- recentMenus is newest first, so trimming at the cap keeps the dishes
	-- served most recently stale and quietly lets the oldest go fresh again.
	for _, menu in (recentMenus or {}) do
		for _, dishId in menu do
			if not set[dishId] then
				if count >= cap then
					return set
				end
				set[dishId] = true
				count += 1
			end
		end
	end
	return set
end

-- How many menu dishes carry each chore-provoking tag, for ChoreDefs.roll.
function HypeDefs.tagCounts(menu): { [string]: number }
	local counts = { trash = 0, dishes = 0 }
	for _, dish in menu do
		local tags = dish.hype or {}
		if tags.trash then
			counts.trash += 1
		end
		if tags.dishes then
			counts.dishes += 1
		end
	end
	return counts
end

return HypeDefs

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

-- Below the floor there is nothing to do; above the ceiling more customers
-- arrive than anyone can physically serve, which is not difficulty, just loss.
HypeDefs.MIN = 0.60
HypeDefs.MAX = 1.50

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
-- `menu` is dish definitions, `yesterday` a set of dish ids served last shift.
function HypeDefs.evaluate(menu, phase: string, weatherId: string, yesterday): (number, { string })
	local hype = 1.0
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
			hype += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s suits the weather")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "morning" and tags.breakfast then
			hype += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s is a breakfast dish")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "night" and tags.lateNight then
			hype += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s sells late")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if tags.alwaysHyped then
			hype += HypeDefs.STEP
			table.insert(reasons, ("+%d%% %s is always wanted")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		if phase == "morning" and tags.smelly then
			hype -= HypeDefs.STEP
			table.insert(reasons, ("-%d%% %s is too much this early")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end

		-- Serving the same thing two days running. One day off clears it,
		-- because yesterday's menu is simply whatever you last ran.
		if yesterday and yesterday[dish.id] then
			hype -= HypeDefs.STEP
			table.insert(reasons, ("-%d%% %s again so soon")
				:format(HypeDefs.STEP * 100, dish.displayName))
		end
	end

	if healthy >= HypeDefs.HEALTHY_PAIR then
		hype += HypeDefs.STEP
		table.insert(reasons, ("+%d%% a balanced menu"):format(HypeDefs.STEP * 100))
	end

	if fatty >= HypeDefs.FATTY_LIMIT then
		hype -= HypeDefs.STEP
		table.insert(reasons, ("-%d%% too much fried food"):format(HypeDefs.STEP * 100))
	end

	return math.clamp(hype, HypeDefs.MIN, HypeDefs.MAX), reasons
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

--!strict
-- Chores: the things that interrupt you.
--
-- Everything else in the game is a queue you work through at your own pace.
-- Chores are the only thing that demands attention on their own schedule, and
-- that is the whole point of them -- without something like this the game is
-- busy but never actually pressured.
--
-- Each one is cleared by a GESTURE rather than a key. Every letter key is
-- potentially an ingredient for whatever dish is in your hands, so a chore key
-- collides with prep at exactly the worst moment -- and a chore that costs one
-- keypress is an interruption you barely notice rather than one you have to
-- stop and deal with.
--
-- Two gestures, because two chores that feel the same are one chore:
--
--   fling  a decisive drag in any direction, past a threshold. Throwing
--          something out. `work` counts HOW MANY -- five bags is five throws.
--   scrub  keep the pointer moving. `work` is SECONDS of actual scrubbing,
--          not elapsed time, so resting the hand pauses it.
--
-- Counting throws and timing scrubs rather than forcing both into one unit is
-- deliberate: a bag is a discrete thing you get rid of, and cleaning is not.
--
-- Both are one pointer moving, so mouse and touch are the same code path and
-- neither needed a separate control scheme.
--
-- `work` is the LABOUR, and it is the number power-ups will reduce -- fewer
-- bags, less scrubbing. Which is why the server computes the real requirement
-- per chore and sends it with the chore, rather than the client reading the
-- base value out of this table and deciding for itself.

local ChoreDefs = {}

ChoreDefs.Gesture = {
	FLING = "fling",
	SCRUB = "scrub",
}

ChoreDefs.List = {
	trash = {
		id = "trash",
		name = "Airlock the Trash",
		blurb = "It is starting to hum.",
		duration = 9,
		gesture = ChoreDefs.Gesture.FLING,
		-- Five bags out of the airlock, one throw each.
		work = 5,
		verb = "Throw every bag out",
		-- Base likelihood before menu tags push it around. Dishes carrying the
		-- `trash` tag raise this one; `dishes` raises the wash.
		weight = 1.0,
		tag = "trash",
	},

	dishes = {
		id = "dishes",
		name = "Run the Sonic Wash",
		blurb = "The pile is listing.",
		duration = 7,
		gesture = ChoreDefs.Gesture.SCRUB,
		-- Three seconds of actual scrubbing. Bad, but not the worst job here.
		work = 3,
		verb = "Scrub until it stops",
		weight = 1.0,
		tag = "dishes",
	},

	toilet = {
		id = "toilet",
		name = "Clean the Toilet",
		blurb = "Do not ask what happened.",
		duration = 9,
		gesture = ChoreDefs.Gesture.SCRUB,
		-- Four seconds. The worst job on the station, priced accordingly.
		work = 4,
		verb = "Scrub. Keep scrubbing.",
		-- Nothing on the menu makes this more or less likely. It is simply the
		-- universe deciding it is your problem.
		weight = 0.45,
		tag = nil,
	},
}

ChoreDefs.Order = { "trash", "dishes", "toilet" }

function ChoreDefs.get(choreId: string)
	return ChoreDefs.List[choreId]
end

-- How much labour this chore actually costs, after whatever reduces it.
--
-- `reduction` is a fraction: 0.25 takes a quarter off. This is the seam the
-- planned power-ups plug into -- fewer bags to throw, less scrubbing -- and it
-- exists now, returning the base, so those never have to reach into the chore
-- system and change how work is counted.
--
-- Never returns less than one. A chore reduced to nothing is not a reward, it
-- is a chore that flickers on screen and vanishes, and the player is left
-- wondering what they missed.
--
-- Flings round to whole bags because half a bag is not a thing you can throw.
-- Scrub seconds do not, because two and a half seconds of scrubbing is.
function ChoreDefs.workFor(def, reduction: number?): number
	if not def then
		return 1
	end

	local remaining = (def.work or 1) * (1 - math.clamp(reduction or 0, 0, 0.9))

	if def.gesture == ChoreDefs.Gesture.FLING then
		return math.max(1, math.floor(remaining + 0.5))
	end
	return math.max(1, remaining)
end

-- Picks a chore, weighted, with menu tags nudging the odds. `tagCounts` is how
-- many dishes on the menu carry each tag.
function ChoreDefs.roll(rng: Random, tagCounts: { [string]: number }?)
	local counts = tagCounts or {}

	local total = 0
	local weights = {}
	for _, id in ChoreDefs.Order do
		local chore = ChoreDefs.List[id]
		local weight = chore.weight
		if chore.tag then
			-- Each dish carrying the tag adds 40% of the base weight, so a menu
			-- full of greasy wrappers really does bury you in trash.
			weight += chore.weight * 0.4 * (counts[chore.tag] or 0)
		end
		weights[id] = weight
		total += weight
	end

	local pick = rng:NextNumber() * total
	for _, id in ChoreDefs.Order do
		pick -= weights[id]
		if pick <= 0 then
			return ChoreDefs.List[id]
		end
	end
	return ChoreDefs.List.trash
end

return ChoreDefs

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
--   fling  one decisive drag in any direction, past a threshold. Throwing
--          something. Quick, but it wants commitment -- a timid drag does
--          nothing.
--   scrub  drag back and forth. Each reversal counts a stroke, and it takes
--          several. Slower and more annoying on purpose: it is cleaning.
--
-- Both are one pointer moving, so mouse and touch are the same code path and
-- neither needed a separate control scheme.

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
		duration = 5,
		gesture = ChoreDefs.Gesture.FLING,
		verb = "Fling it at the airlock",
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
		verb = "Scrub back and forth",
		weight = 1.0,
		tag = "dishes",
	},

	toilet = {
		id = "toilet",
		name = "Clean the Toilet",
		blurb = "Do not ask what happened.",
		duration = 8,
		gesture = ChoreDefs.Gesture.SCRUB,
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

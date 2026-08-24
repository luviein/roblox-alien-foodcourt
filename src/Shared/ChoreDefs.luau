--!strict
-- Chores: the things that interrupt you.
--
-- Everything else in the game is a queue you work through at your own pace.
-- Chores are the only thing that demands attention on their own schedule, and
-- that is the whole point of them -- without something like this the game is
-- busy but never actually pressured.
--
-- One key clears whichever chore is up, rather than a key per chore. Every
-- letter key is potentially an ingredient for whatever dish is in your hands,
-- so per-chore keys would collide with prep at exactly the worst moment.

local ChoreDefs = {}

ChoreDefs.KEY = "C"

ChoreDefs.List = {
	trash = {
		id = "trash",
		name = "Airlock the Trash",
		blurb = "It is starting to hum.",
		duration = 5,
		-- Base likelihood before menu tags push it around. Dishes carrying the
		-- `trash` tag raise this one; `dishes` raises the wash.
		weight = 1.0,
		tag = "trash",
	},

	dishes = {
		id = "dishes",
		name = "Run the Sonic Wash",
		blurb = "The pile is listing.",
		duration = 5,
		weight = 1.0,
		tag = "dishes",
	},

	toilet = {
		id = "toilet",
		name = "Clean the Toilet",
		blurb = "Do not ask what happened.",
		duration = 6,
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

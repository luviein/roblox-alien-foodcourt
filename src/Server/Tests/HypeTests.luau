--!strict
-- Hype: the maths behind how fast customers arrive.
--
-- The case worth guarding is that tags are MULTIPLIERS of the player's own
-- base, not offsets. A previous bug read SWING_DOWN and SWING_UP as offsets on
-- the draft screen, which drew the bar as 5%-100% whatever the menu did, so a
-- good draft looked like it had achieved nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DishDefs = require(Shared.DishDefs)
local HypeDefs = require(Shared.HypeDefs)

local Runner = require(script.Parent.Runner)

-- A dish with exactly the tags asked for, so a test can isolate one rule
-- rather than depending on what the real catalogue happens to carry.
local function fakeDish(id: string, tags): any
	return { id = id, displayName = id, hype = tags or {} }
end

return function()
	local t = Runner.new("hype")
	local base = Config.BASE_HYPE

	-- ------------------------------------------------------------- neutral --

	local neutral = HypeDefs.evaluate({ fakeDish("plain") }, "afternoon", "clear", nil, base)
	t:near("a menu with no tags sits on base", neutral, base)

	local empty = HypeDefs.evaluate({}, "afternoon", "clear", nil, base)
	t:near("an empty menu sits on base", empty, base)

	-- ------------------------------------------------------ multiplicative --

	local oneTag = HypeDefs.evaluate(
		{ fakeDish("hyped", { alwaysHyped = true }) }, "afternoon", "clear", nil, base)
	t:near("one tag is base x 1.05", oneTag, base * (1 + HypeDefs.STEP))

	-- The point of multiplying: the same tag is worth the same PROPORTION to
	-- a new player and a rebirthed one, not the same number of points.
	local higherBase = base * 2
	local scaled = HypeDefs.evaluate(
		{ fakeDish("hyped", { alwaysHyped = true }) }, "afternoon", "clear", nil, higherBase)
	t:near("the same tag scales with base", scaled, higherBase * (1 + HypeDefs.STEP))
	t:check("which is a bigger absolute step", scaled - higherBase > oneTag - base)

	local twoTags = HypeDefs.evaluate(
		{ fakeDish("both", { alwaysHyped = true, weather = "rain" }) },
		"afternoon", "rain", nil, base)
	t:near("two tags stack", twoTags, base * (1 + 2 * HypeDefs.STEP))

	-- --------------------------------------------------------------- rules --

	local breakfast = fakeDish("pancakes", { breakfast = true })
	t:near("a breakfast dish pays in the morning",
		HypeDefs.evaluate({ breakfast }, "morning", "clear", nil, base),
		base * (1 + HypeDefs.STEP))
	t:near("and not at night",
		HypeDefs.evaluate({ breakfast }, "night", "clear", nil, base),
		base)

	local lateNight = fakeDish("ramen", { lateNight = true })
	t:near("a late dish pays at night",
		HypeDefs.evaluate({ lateNight }, "night", "clear", nil, base),
		base * (1 + HypeDefs.STEP))

	local smelly = fakeDish("kipper", { smelly = true })
	t:near("something smelly costs you in the morning",
		HypeDefs.evaluate({ smelly }, "morning", "clear", nil, base),
		base * (1 - HypeDefs.STEP))
	t:near("but is fine at night",
		HypeDefs.evaluate({ smelly }, "night", "clear", nil, base),
		base)

	local suits = fakeDish("stew", { weather = "cold" })
	t:near("a dish suits the weather",
		HypeDefs.evaluate({ suits }, "afternoon", "cold", nil, base),
		base * (1 + HypeDefs.STEP))
	t:near("and does nothing in other weather",
		HypeDefs.evaluate({ suits }, "afternoon", "clear", nil, base),
		base)

	-- Staleness: served recently, so it costs.
	t:near("a repeat costs hype",
		HypeDefs.evaluate({ fakeDish("burger") }, "afternoon", "clear", { burger = true }, base),
		base * (1 - HypeDefs.STEP))

	-- Balance bonus and the fried-food penalty.
	local healthy = { fakeDish("salad", { healthy = true }), fakeDish("greens", { healthy = true }) }
	t:near("two healthy dishes is a balanced menu",
		HypeDefs.evaluate(healthy, "afternoon", "clear", nil, base),
		base * (1 + HypeDefs.STEP))

	local fatty = {
		fakeDish("f1", { fatty = true }),
		fakeDish("f2", { fatty = true }),
		fakeDish("f3", { fatty = true }),
	}
	t:near("three fried dishes costs you",
		HypeDefs.evaluate(fatty, "afternoon", "clear", nil, base),
		base * (1 - HypeDefs.STEP))

	-- -------------------------------------------------------------- clamps --

	local stacked = {}
	for index = 1, 12 do
		table.insert(stacked, fakeDish("hyped" .. index, { alwaysHyped = true }))
	end
	local ceiling = HypeDefs.evaluate(stacked, "afternoon", "clear", nil, base)
	t:near("a huge menu is capped at SWING_UP", ceiling, base * HypeDefs.SWING_UP)
	t:check("and never exceeds MAX", ceiling <= HypeDefs.MAX)

	local awful = {}
	local staleSet = {}
	for index = 1, 12 do
		local id = "smelly" .. index
		table.insert(awful, fakeDish(id, { smelly = true, fatty = true }))
		staleSet[id] = true
	end
	local floor = HypeDefs.evaluate(awful, "morning", "clear", staleSet, base)
	t:near("an awful menu bottoms out at SWING_DOWN", floor, base * HypeDefs.SWING_DOWN)
	t:check("and never drops below MIN", floor >= HypeDefs.MIN)

	-- A very high base must still respect the absolute ceiling.
	local nearFull = HypeDefs.evaluate(stacked, "afternoon", "clear", nil, 0.95)
	t:check("MAX wins over the swing at a high base", nearFull <= HypeDefs.MAX)

	-- -------------------------------------------------------------- phases --

	t:equal("the shift opens in the morning", HypeDefs.phaseAt(0, 90), "morning")
	t:equal("29s in is still morning", HypeDefs.phaseAt(29, 90), "morning")
	t:equal("30s in is afternoon", HypeDefs.phaseAt(30, 90), "afternoon")
	t:equal("60s in is night", HypeDefs.phaseAt(60, 90), "night")
	t:equal("the last second is night", HypeDefs.phaseAt(89.9, 90), "night")
	-- Overtime: last orders runs past the clock, and must not fall off the end.
	t:equal("overtime stays in the last phase", HypeDefs.phaseAt(120, 90), "night")

	-- ------------------------------------------------------------ staleness --

	local stale = HypeDefs.staleSet({ { "burger", "fries" }, { "taco" } })
	t:check("recent menus become a set", stale.burger == true and stale.taco == true)
	t:check("anything else is absent", stale.ramen == nil)
	t:equal("nil is handled", next(HypeDefs.staleSet(nil)), nil)

	-- ------------------------------------------------------------- weather --

	local rolled = HypeDefs.rollWeather(Random.new(1))
	t:truthy("weather rolls something", rolled and rolled.id)
	t:equal("a weather id round trips", HypeDefs.weather(rolled.id).id, rolled.id)
	t:equal("an unknown id falls back", HypeDefs.weather("nonsense").id, HypeDefs.WeatherDeck[1].id)

	-- ------------------------------------------------- the real catalogue --

	-- Every dish the game can actually serve must be a real definition. A
	-- typo here is a nil dish at runtime, mid-shift.
	local allReal = true
	for _, dishId in DishDefs.ActiveMenu do
		if not DishDefs.get(dishId) then
			allReal = false
		end
	end
	t:check("every dish on the active menu exists", allReal)

	return t
end

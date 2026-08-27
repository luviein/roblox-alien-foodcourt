--!strict
-- Chore workloads.
--
-- `workFor` is the seam the planned power-ups plug into, so it is worth pinning
-- down before anything reduces it: the floor, the rounding, and the fact that
-- flings count whole bags while scrubs do not have to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChoreDefs = require(Shared.ChoreDefs)

local Runner = require(script.Parent.Runner)

return function()
	local t = Runner.new("chores")

	local trash = ChoreDefs.get("trash")
	local toilet = ChoreDefs.get("toilet")

	-- --------------------------------------------------------------- bases --

	t:equal("the airlock is five bags", trash.work, 5)
	t:equal("and is thrown", trash.gesture, ChoreDefs.Gesture.FLING)
	t:equal("the toilet is four seconds", toilet.work, 4)
	t:equal("and is scrubbed", toilet.gesture, ChoreDefs.Gesture.SCRUB)

	local everyOneDefined = true
	for _, id in ChoreDefs.Order do
		local def = ChoreDefs.get(id)
		if not def or not def.work or not def.gesture or not def.verb then
			everyOneDefined = false
		end
	end
	t:check("every chore has work, a gesture and a verb", everyOneDefined)

	-- Timers have to leave room for the labour, or a chore is unfinishable
	-- however well it is played.
	local everyOneFinishable = true
	for _, id in ChoreDefs.Order do
		local def = ChoreDefs.get(id)
		if def.gesture == ChoreDefs.Gesture.SCRUB and def.duration <= def.work then
			everyOneFinishable = false
		end
	end
	t:check("scrub timers exceed the scrubbing they ask for", everyOneFinishable)

	-- ----------------------------------------------------------- reductions --

	t:equal("no reduction is the base", ChoreDefs.workFor(trash), trash.work)
	t:equal("nil reduction is the base", ChoreDefs.workFor(trash, nil), trash.work)
	t:equal("a fifth off five bags is four", ChoreDefs.workFor(trash, 0.2), 4)
	t:equal("half off five bags is three", ChoreDefs.workFor(trash, 0.5), 3)

	-- Scrub seconds keep their fraction; bags do not, because half a bag is not
	-- a thing anyone can throw.
	t:near("half off four seconds is two", ChoreDefs.workFor(toilet, 0.5), 2)
	t:near("a quarter off four seconds is three", ChoreDefs.workFor(toilet, 0.25), 3)

	-- ---------------------------------------------------------- the floor ---

	-- A chore reduced to nothing is not a reward, it is a chore that flickers
	-- on screen and vanishes while the player wonders what they missed.
	t:equal("a total reduction still leaves one bag",
		ChoreDefs.workFor(trash, 1), 1)
	t:equal("and one second of scrubbing",
		ChoreDefs.workFor(toilet, 1), 1)
	t:equal("an absurd reduction is clamped, not inverted",
		ChoreDefs.workFor(trash, 99), 1)
	t:equal("a negative reduction does not ADD work",
		ChoreDefs.workFor(trash, -5), trash.work)

	t:equal("an unknown chore still asks for something",
		ChoreDefs.workFor(nil), 1)

	-- ------------------------------------------------------------- rolling --

	local rng = Random.new(7)
	local rolledReal = true
	for _ = 1, 50 do
		local picked = ChoreDefs.roll(rng, {})
		if not picked or not ChoreDefs.get(picked.id) then
			rolledReal = false
		end
	end
	t:check("every roll returns a real chore", rolledReal)

	-- A menu heavy in one tag should bury the player in that chore.
	local plain = 0
	local greasy = 0
	local plainRng = Random.new(11)
	local greasyRng = Random.new(11)
	for _ = 1, 300 do
		if ChoreDefs.roll(plainRng, {}).id == "trash" then
			plain += 1
		end
		if ChoreDefs.roll(greasyRng, { trash = 3 }).id == "trash" then
			greasy += 1
		end
	end
	t:check("trashy menus roll more trash", greasy > plain,
		string.format("%d vs %d over 300", greasy, plain))

	return t
end

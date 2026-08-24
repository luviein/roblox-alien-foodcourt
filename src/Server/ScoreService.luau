--!strict
-- Grading and payout. Kept deliberately small and pure so the numbers stay
-- easy to reason about when we tune the economy against real playtest data.
--
-- Design rule: grading depends ONLY on build correctness and elapsed time.
-- Environment modifiers (P2) will move demand, price and workload -- never
-- what counts as a Perfect. Skill must stay readable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ScoreService = {}

export type Grade = "Perfect" | "Good" | "Sloppy" | "Fail"

-- Graded on how much of the customer's patience is left, not on absolute
-- seconds since the ticket appeared.
--
-- The absolute version was unplayable: with four tickets on screen and a 22s
-- patience, the third and fourth were already past every threshold by the time
-- you could physically reach them, so almost everything came out Sloppy no
-- matter how well it was played.
--
-- Grading on the remaining fraction fixes that and pays off twice: it scales
-- automatically with ORDER_PATIENCE, and it makes the patience bar above each
-- customer *be* the grade meter. Serve while it is green and that is a
-- Perfect. No hidden numbers.
function ScoreService.grade(order, now: number, buildCorrect: boolean): Grade
	if not buildCorrect then
		return "Fail"
	end

	local span = math.max(order.expiresAt - order.createdAt, 0.001)
	local remaining = math.clamp((order.expiresAt - now) / span, 0, 1)

	if remaining >= Config.GRADE_PATIENCE.perfect then
		return "Perfect"
	elseif remaining >= Config.GRADE_PATIENCE.good then
		return "Good"
	end
	return "Sloppy"
end

-- How precisely the basket came out of the oil. `overshoot` is seconds past
-- the moment it was ready; negative means it was pulled raw.
function ScoreService.fryGrade(overshoot: number, fry): Grade
	if not fry then
		return "Sloppy"
	end
	if overshoot < 0 then
		return "Fail"          -- raw
	elseif overshoot <= fry.perfect then
		return "Perfect"
	elseif overshoot <= fry.good then
		return "Good"
	end
	return "Sloppy"
end

local GRADE_RANK = { Perfect = 4, Good = 3, Sloppy = 2, Fail = 1 }

-- The lower of two grades. A fried order is judged on both the pull and the
-- customer's patience, and the worse one wins -- a flawless pull cannot
-- rescue a ticket you left sitting.
function ScoreService.worst(a: Grade, b: Grade): Grade
	return if (GRADE_RANK[a] or 0) <= (GRADE_RANK[b] or 0) then a else b
end

function ScoreService.comboMultiplier(combo: number): number
	return math.min(1 + combo * Config.COMBO_STEP, Config.COMBO_MAX)
end

function ScoreService.payout(order, grade: Grade, combo: number): (number, number)
	local gradeMult = Config.GRADE_MULT[grade] or 0
	local comboMult = ScoreService.comboMultiplier(combo)
	local value = math.floor(order.baseValue * gradeMult * comboMult + 0.5)
	return value, comboMult
end

-- Perfect/Good extend the combo, Sloppy holds it, anything worse breaks it.
function ScoreService.nextCombo(combo: number, grade: Grade): number
	if grade == "Perfect" or grade == "Good" then
		return combo + 1
	elseif grade == "Sloppy" then
		return combo
	end
	return 0
end

return ScoreService

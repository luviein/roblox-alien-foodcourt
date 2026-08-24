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

-- Elapsed time is measured from when the TICKET APPEARED, not from when the
-- player started building it. That makes the grade reflect the whole juggle,
-- which is the actual skill being tested.
function ScoreService.grade(order, now: number, buildCorrect: boolean): Grade
	if not buildCorrect then
		return "Fail"
	end

	local elapsed = now - order.createdAt
	if elapsed <= order.timing.perfect then
		return "Perfect"
	elseif elapsed <= order.timing.good then
		return "Good"
	end
	return "Sloppy"
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

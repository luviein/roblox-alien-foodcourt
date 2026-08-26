--!strict
-- A very small test harness.
--
-- Deliberately not TestEZ: pulling that in needs Wally, a manifest and a
-- package folder, which is a lot of machinery around what this project
-- actually needs -- a few dozen assertions over the pure logic in Shared.
--
-- It runs inside Studio, in the real Luau runtime, so `Random`, `os.time`,
-- `typeof` and `table.clone` are the genuine articles rather than stubs. What
-- it CANNOT reach is anything made of Instances: rendering, input, clicks,
-- ZIndex. Most of the bugs this project has shipped were exactly that, so
-- passing tests here are worth something but they are not a green light.

local Runner = {}
Runner.__index = Runner

function Runner.new(label: string): any
	return setmetatable({
		label = label,
		passed = 0,
		failures = {},
	}, Runner)
end

function Runner:check(name: string, condition: boolean, detail: string?)
	if condition then
		self.passed += 1
	else
		table.insert(
			self.failures,
			if detail then string.format("%s  (%s)", name, detail) else name)
	end
end

function Runner:equal(name: string, actual: any, expected: any)
	self:check(
		name,
		actual == expected,
		string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

-- Floating point needs a tolerance. Hype is all products of fractions, so
-- exact equality would fail on arithmetic that is perfectly correct.
function Runner:near(name: string, actual: number, expected: number, tolerance: number?)
	local slack = tolerance or 1e-6
	self:check(
		name,
		math.abs(actual - expected) <= slack,
		string.format("expected %.6f +/- %.6f, got %.6f", expected, slack, actual))
end

function Runner:truthy(name: string, value: any)
	self:check(name, value ~= nil and value ~= false, "value was " .. tostring(value))
end

-- Prints one block per suite. warn() rather than print() for failures, so they
-- come out orange and cannot be missed in a busy Output window.
function Runner.report(suites: { any }): boolean
	local totalPassed, totalFailed = 0, 0

	for _, suite in suites do
		local failed = #suite.failures
		totalPassed += suite.passed
		totalFailed += failed

		if failed == 0 then
			print(string.format("[tests]   ok  %-14s %d passed", suite.label, suite.passed))
		else
			warn(string.format("[tests] FAIL  %-14s %d passed, %d failed",
				suite.label, suite.passed, failed))
			for _, failure in suite.failures do
				warn("           . " .. failure)
			end
		end
	end

	if totalFailed == 0 then
		print(string.format("[tests] all %d assertions passed", totalPassed))
	else
		warn(string.format("[tests] %d of %d assertions FAILED",
			totalFailed, totalPassed + totalFailed))
	end

	return totalFailed == 0
end

return Runner

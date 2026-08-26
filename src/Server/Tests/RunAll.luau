--!strict
-- Runs every suite and prints one summary.
--
-- Called from Main.server only when Config.DEBUG_COMMANDS is on, so a release
-- build neither runs them nor pays to require them.

local Runner = require(script.Parent.Runner)

local SUITES = {
	require(script.Parent.DailyTests),
	require(script.Parent.HypeTests),
	require(script.Parent.OfflineTests),
	require(script.Parent.ShopTests),
}

return function(): boolean
	local results = {}

	for _, suite in SUITES do
		-- One suite throwing must not hide the others: a crash here is itself
		-- a failure worth seeing, reported next to whatever else went wrong.
		local ok, result = pcall(suite)
		if ok then
			table.insert(results, result)
		else
			local broken = Runner.new("crashed")
			broken:check("suite ran without error", false, tostring(result))
			table.insert(results, broken)
		end
	end

	return Runner.report(results)
end

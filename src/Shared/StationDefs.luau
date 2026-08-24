--!strict
-- The stations behind the counter, and which number key reaches each one.
--
-- 1-4 used to select a TICKET. It now selects a STATION, and each station
-- works its own oldest waiting order automatically. That is the whole shape of
-- the game changing: the decision stops being "which of these four dishes do I
-- build next" and becomes "which of these four places needs me most right
-- now", which is the thing that actually creates pressure.

local StationDefs = {}

-- Display order, which is also the number-key order.
StationDefs.Order = { "Prep", "Fryer" }

StationDefs.Stations = {
	Prep = {
		id = "Prep",
		displayName = "Prep Counter",
		key = "1",
		archetype = "Assembly",
	},

	Fryer = {
		id = "Fryer",
		displayName = "Fryer",
		key = "2",
		archetype = "Fry",

		-- Two baskets, each driven by one key: Q and W. The same key drops and
		-- pulls depending on what the basket is doing, so the fryer never needs
		-- more than two keys no matter how busy it gets.
		baskets = 2,
		basketKeys = { "Q", "W" },
	},
}

function StationDefs.get(stationId: string)
	return StationDefs.Stations[stationId]
end

-- Station a number key maps to, or nil.
function StationDefs.byKeyIndex(index: number): string?
	return StationDefs.Order[index]
end

function StationDefs.indexOf(stationId: string): number?
	for index, id in StationDefs.Order do
		if id == stationId then
			return index
		end
	end
	return nil
end

return StationDefs

--!strict
-- Server entry point.

local CustomerRigs = require(script.Parent.CustomerRigs)
local ShiftService = require(script.Parent.ShiftService)

-- Pre-builds the customer avatar pool into ReplicatedStorage. Yields on web
-- calls internally, so it does not hold up the shift service.
CustomerRigs.build()

ShiftService.start()

print("[AlienFoodCourt] server ready")

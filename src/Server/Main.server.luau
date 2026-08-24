--!strict
-- Server entry point.

local CustomerRigs = require(script.Parent.CustomerRigs)
local DataService = require(script.Parent.DataService)
local ShiftService = require(script.Parent.ShiftService)

-- Profiles first: a player can join before anything else is ready, and their
-- save has to be loaded before a shift can pay into it.
DataService.start()

-- Pre-builds the customer avatar pool into ReplicatedStorage. Yields on web
-- calls internally, so it does not hold up the shift service.
CustomerRigs.build()

ShiftService.start()

print("[AlienFoodCourt] server ready")

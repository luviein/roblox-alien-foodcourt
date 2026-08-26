--!strict
-- Server entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CustomerRigs = require(script.Parent.CustomerRigs)
local DataService = require(script.Parent.DataService)
local ShiftService = require(script.Parent.ShiftService)

-- Tests run first, before anything can touch a profile, and only when debug
-- logging is on -- they are Output noise rather than a cheat, so they stay on
-- through a realistic playtest.
--
-- They cover the pure logic in Shared: hype maths, daily tasks, boosts, the
-- shop tables. Nothing made of Instances, so a green run says the numbers are
-- right, not that the game looks right.
if Config.DEBUG_LOGGING then
	require(script.Parent.Tests.RunAll)()
end

-- Profiles first: a player can join before anything else is ready, and their
-- save has to be loaded before a shift can pay into it.
DataService.start()

-- Pre-builds the customer avatar pool into ReplicatedStorage. Yields on web
-- calls internally, so it does not hold up the shift service.
CustomerRigs.build()

ShiftService.start()

print("[AlienFoodCourt] server ready")

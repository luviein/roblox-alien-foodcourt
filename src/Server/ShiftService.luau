--!strict
-- Owns the player -> Kitchen registry, the authoritative tick loop, and all
-- remote wiring. Nothing the client sends is trusted: every action is
-- validated, rate limited, and applied to server-side state only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Kitchen = require(script.Parent.Kitchen)

-- The only keys the station will ever accept. Anything else is dropped
-- before it reaches gameplay code.
local VALID_KEYS = {
	Q = true, W = true, E = true, R = true, T = true,
	A = true, S = true, D = true, F = true, G = true,
}

local ShiftService = {}

local kitchens: { [Player]: any } = {}
local actionBudget: { [Player]: { count: number, windowStart: number } } = {}

-- ----------------------------------------------------------- rate limit ----

local function allowAction(player: Player): boolean
	local budget = actionBudget[player]
	if not budget then
		return false
	end

	local nowClock = os.clock()
	if nowClock - budget.windowStart >= 1 then
		budget.windowStart = nowClock
		budget.count = 0
	end

	budget.count += 1
	return budget.count <= Config.ACTION_RATE_LIMIT
end

-- -------------------------------------------------------------- push -------

local function pushSnapshot(player: Player)
	local kitchen = kitchens[player]
	if not kitchen then
		return
	end
	local snapshot = kitchen:snapshot()
	snapshot.events = kitchen:drainEvents()
	Remotes.ShiftUpdate:FireClient(player, snapshot)
end

-- ------------------------------------------------------------ lifecycle ----

local function onPlayerAdded(player: Player)
	-- One Kitchen per player, with a single participant. Co-op later means
	-- several players sharing one Kitchen -- this registry is the only thing
	-- that has to change.
	kitchens[player] = Kitchen.new({ player })
	actionBudget[player] = { count = 0, windowStart = os.clock() }
	pushSnapshot(player)
end

local function onPlayerRemoving(player: Player)
	kitchens[player] = nil
	actionBudget[player] = nil
end

-- --------------------------------------------------------------- remotes ---

local function onStartShift(player: Player)
	local kitchen = kitchens[player]
	if not kitchen then
		return
	end

	if kitchen.state == "Results" then
		kitchen:closeResults()
	elseif kitchen.state == "Idle" then
		kitchen:startShift()
	end

	pushSnapshot(player)
end

local function onStationAction(player: Player, payload: any)
	local kitchen = kitchens[player]
	if not kitchen then
		return
	end
	if typeof(payload) ~= "table" or typeof(payload.action) ~= "string" then
		return
	end
	if not allowAction(player) then
		return
	end

	local action = payload.action

	if action == "sync" then
		-- Client just started up and wants current state. The server fires a
		-- snapshot on PlayerAdded, but that can land before the client has
		-- connected its handler, so the client asks once on boot.
		pushSnapshot(player)
		return
	elseif action == "ingredient" then
		local key = payload.key
		if typeof(key) ~= "string" or not VALID_KEYS[key] then
			return
		end
		kitchen:addIngredient(key)
	elseif action == "serve" then
		kitchen:serve()
	elseif action == "scrap" then
		kitchen:scrap()
	elseif action == "select" then
		local slot = payload.slot
		if typeof(slot) ~= "number" then
			return
		end
		slot = math.floor(slot)
		if slot < 1 or slot > Config.MAX_ORDER_SLOTS then
			return
		end
		kitchen:selectSlot(slot)
	else
		return
	end

	-- Answer immediately rather than waiting for the next tick, so input
	-- feels instant instead of up to 100ms late.
	pushSnapshot(player)
end

-- ------------------------------------------------------------------ tick ---

local function startTickLoop()
	task.spawn(function()
		local interval = 1 / Config.TICK_RATE
		while true do
			task.wait(interval)
			for player, kitchen in kitchens do
				local before = kitchen.state
				kitchen:tick()
				-- Idle kitchens have nothing moving; skip the traffic unless
				-- the state just changed.
				if kitchen.state ~= "Idle" or before ~= "Idle" then
					pushSnapshot(player)
				end
			end
		end
	end)
end

function ShiftService.start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Remotes.StartShift.OnServerEvent:Connect(onStartShift)
	Remotes.StationAction.OnServerEvent:Connect(onStationAction)

	startTickLoop()
end

return ShiftService

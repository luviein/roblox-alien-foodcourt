--!strict
-- Owns the player -> Kitchen registry, the authoritative tick loop, and all
-- remote wiring. Nothing the client sends is trusted: every action is
-- validated, rate limited, and applied to server-side state only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Kitchen = require(script.Parent.Kitchen)
local ShopDefs = require(Shared.ShopDefs)

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

	-- The profile rides along so the HUD can show cash without another remote.
	local profile = DataService.get(player)
	if profile then
		snapshot.profile = {
			cash = profile.cash,
			debtPaid = profile.debtPaid,
			settings = profile.settings,
			unlocked = profile.unlocked,
			upgrades = profile.upgrades,
			lastEarned = kitchen.lastEarned,
			temporary = DataService.isTemporary(player),
		}
	end
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

-- Turns a saved profile into the numbers a shift runs on. The only place that
-- knows how upgrades translate into gameplay.
local function loadoutFor(player: Player)
	local profile = DataService.get(player)

	local menu = {}
	if profile then
		-- Order matters for the bag; walk the canonical list rather than the
		-- profile table, whose iteration order is arbitrary.
		if profile.unlocked.burger then
			table.insert(menu, "burger")
		end
		for _, dishId in ShopDefs.DishOrder do
			if profile.unlocked[dishId] then
				table.insert(menu, dishId)
			end
		end
	end
	if #menu == 0 then
		menu = { "burger" }
	end

	local upgrades = (profile and profile.upgrades) or {}

	return {
		menu = menu,
		orderSlots = math.min(
			ShopDefs.valueOf("slots", upgrades.slots or 0),
			Config.MAX_ORDER_SLOTS
		),
		shiftDuration = Config.SHIFT_DURATION + ShopDefs.valueOf("shift", upgrades.shift or 0),
		-- Applied to CASH at payout, never to score. Score stays comparable
		-- between players; what it is worth does not.
		cashMultiplier = 1 + ShopDefs.valueOf("tips", upgrades.tips or 0),

		-- How many menu dishes carry each chore-provoking tag. Empty until the
		-- menu draft exists; ChoreDefs falls back to flat odds.
		tagCounts = {},
	}
end

local function onStartShift(player: Player)
	local kitchen = kitchens[player]
	if not kitchen then
		return
	end

	if kitchen.state == "Results" then
		kitchen:closeResults()
	elseif kitchen.state == "Idle" then
		kitchen:startShift(loadoutFor(player))
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

	elseif action == "settings" then
		-- Client owns its own preferences; the server only stores them.
		local values = payload.values
		if typeof(values) ~= "table" then
			return
		end
		DataService.update(player, function(data)
			for key, value in values do
				if data.settings[key] ~= nil and typeof(data.settings[key]) == typeof(value) then
					data.settings[key] = value
				end
			end
		end)
		return

	elseif action == "buy" then
		-- Purchases are entirely server-side: the client asks for a thing by
		-- id and the server decides whether it is affordable, buyable, and not
		-- already owned. Nothing about price or ownership is trusted from the
		-- message.
		if kitchen.state ~= "Idle" then
			return   -- no shopping mid-shift
		end

		local kind, id = payload.kind, payload.id
		if typeof(kind) ~= "string" or typeof(id) ~= "string" then
			return
		end

		DataService.update(player, function(data)
			if kind == "dish" then
				local cost = ShopDefs.dishCost(id)
				if not cost or data.unlocked[id] or data.cash < cost then
					return
				end
				data.cash -= cost
				data.unlocked[id] = true

			elseif kind == "upgrade" then
				local owned = data.upgrades[id] or 0
				local cost = ShopDefs.upgradeCost(id, owned)
				if not cost or owned >= ShopDefs.maxLevel(id) or data.cash < cost then
					return
				end
				data.cash -= cost
				data.upgrades[id] = owned + 1
			end
		end)

		DataService.save(player)

	elseif action == "chore" then
		kitchen:clearChore()

	elseif action == "searStart" then
		kitchen:searStart()

	elseif action == "searEnd" then
		kitchen:searEnd()

	elseif action == "selectOrder" then
		local orderId = payload.orderId
		if typeof(orderId) ~= "number" then
			return
		end
		kitchen:selectOrder(math.floor(orderId))

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

				-- A shift that just ended pays into the profile. Doing it here
				-- rather than inside Kitchen keeps the gameplay state machine
				-- unaware of saving.
				if before == "Service" and kitchen.state == "Results" then
					local earned = math.floor(kitchen.score * kitchen.loadout.cashMultiplier + 0.5)
					kitchen.lastEarned = earned
					DataService.update(player, function(data)
						data.cash += earned
						data.stats.shifts += 1
						data.stats.served += kitchen.stats.served
						data.stats.bestScore = math.max(data.stats.bestScore, kitchen.score)
						data.stats.bestCombo = math.max(data.stats.bestCombo, kitchen.bestCombo)
					end)
					DataService.save(player)
				end
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

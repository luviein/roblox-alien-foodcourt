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
local HypeDefs = require(Shared.HypeDefs)
local DishDefs = require(Shared.DishDefs)
local DailyDefs = require(Shared.DailyDefs)

-- The only keys the station will ever accept. Anything else is dropped
-- before it reaches gameplay code.
local VALID_KEYS = {
	Q = true, W = true, E = true, R = true, T = true,
	A = true, S = true, D = true, F = true, G = true,
}

local ShiftService = {}

local kitchens: { [Player]: any } = {}
local actionBudget: { [Player]: { count: number, windowStart: number } } = {}

-- When each idle player was last sent a snapshot to keep a boost clock moving.
local lastIdlePush: { [Player]: number } = {}

-- Whether anything is currently counting down for this player.
local function boostRunning(player: Player): boolean
	local profile = DataService.get(player)
	local earnings, tips = DailyDefs.boostValues(profile and profile.boosts)
	return earnings > 0 or tips
end

-- Forward declared: pushSnapshot sends the day-s conditions along with every
-- snapshot, and is defined above the roll that produces them.
local conditionsFor

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

	-- Reroll the moment the date turns over, so someone who leaves the game
	-- open across midnight gets the new list without relogging. The cheap date
	-- comparison guards the write: this runs at the tick rate, and marking the
	-- profile dirty ten times a second for nothing would be silly.
	if profile and profile.daily and profile.daily.date ~= DailyDefs.dateString() then
		DataService.update(player, function(data)
			DailyDefs.ensureToday(data.daily)
		end)
	end

	if profile then
		snapshot.profile = {
			cash = profile.cash,
			debtPaid = profile.debtPaid,
			settings = profile.settings,
			unlocked = profile.unlocked,
			upgrades = profile.upgrades,
			lastEarned = kitchen.lastEarned,
			day = profile.day,
			recentMenus = profile.recentMenus,
			menuSlots = profile.menuSlots,
			rebirths = profile.rebirths,
			conditions = conditionsFor(player),
			temporary = DataService.isTemporary(player),

			-- Today's tasks and how far along they are. Rolled here if the
			-- stored list is from another day, so a player who leaves the
			-- game open across midnight gets the new list without relogging.
			daily = DailyDefs.statusOf(profile.daily),

			-- The last prize won, so the panel can announce it. The serial on
			-- it is what stops the announcement repeating every snapshot.
			lastPrize = kitchen.lastPrize,

			-- Running boosts, so the HUD can show what is active and how long
			-- is left on it.
			boosts = profile.boosts,
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
	lastIdlePush[player] = nil
end

-- --------------------------------------------------------------- remotes ---

-- Turns a saved profile into the numbers a shift runs on. The only place that
-- knows how upgrades translate into gameplay.
-- Today's conditions, rolled once and held until the shift is played. Rolling
-- them fresh on every draft screen redraw would let a player reroll the
-- weather by closing and reopening it.
local dayConditions: { [Player]: any } = {}

function conditionsFor(player: Player)
	local existing = dayConditions[player]
	if existing then
		return existing
	end

	local profile = DataService.get(player)
	local rng = Random.new()
	local weather = HypeDefs.rollWeather(rng)

	local conditions = {
		day = (profile and profile.day) or 1,
		weather = weather.id,
		weatherName = weather.name,
		weatherBlurb = weather.blurb,
	}
	dayConditions[player] = conditions
	return conditions
end

-- Which dishes the player may draft from.
local function unlockedMenu(profile): { string }
	local menu = {}
	if not profile then
		return { "burger" }
	end
	if profile.unlocked.burger then
		table.insert(menu, "burger")
	end
	for _, dishId in ShopDefs.DishOrder do
		if profile.unlocked[dishId] then
			table.insert(menu, dishId)
		end
	end
	if #menu == 0 then
		menu = { "burger" }
	end
	return menu
end

-- `chosen` is the drafted menu. Anything not unlocked, or over the slot limit,
-- is dropped here rather than trusted.
local function loadoutFor(player: Player, chosen: { string }?)
	local profile = DataService.get(player)
	local allowed = {}
	for _, dishId in unlockedMenu(profile) do
		allowed[dishId] = true
	end

	local slots = (profile and profile.menuSlots) or 3
	local menu = {}
	local seen = {}

	for _, dishId in (chosen or {}) do
		if allowed[dishId] and not seen[dishId] and #menu < slots then
			seen[dishId] = true
			table.insert(menu, dishId)
		end
	end

	-- Nothing draftable came through: fall back to whatever they own so a
	-- malformed request cannot produce a shift with no dishes at all.
	if #menu == 0 then
		for _, dishId in unlockedMenu(profile) do
			if #menu < slots then
				table.insert(menu, dishId)
			end
		end
	end

	local defs = {}
	for _, dishId in menu do
		table.insert(defs, DishDefs.get(dishId))
	end

	local conditions = conditionsFor(player)
	local stale = HypeDefs.staleSet(profile and profile.recentMenus)
	local upgrades = (profile and profile.upgrades) or {}
	local earningsBoost, tipBoost = DailyDefs.boostValues(profile and profile.boosts)

	-- Where a neutral menu sits. Nothing in the shop moves this any more -- the
	-- only permanent lift is rebirths, which are earned. Everything else about
	-- how busy the counter gets comes out of the DRAFT: dish tags paying off in
	-- the phase and weather that suit them.
	local baseHype = Config.BASE_HYPE
		+ Config.REBIRTH_HYPE_STEP * ((profile and profile.rebirths) or 0)

	local hypeByPhase = {}
	for _, phase in HypeDefs.Phases do
		hypeByPhase[phase] =
			HypeDefs.evaluate(defs, phase, conditions.weather, stale, baseHype)
	end

	return {
		menu = menu,
		orderSlots = math.min(
			ShopDefs.valueOf("slots", upgrades.slots or 0),
			Config.MAX_ORDER_SLOTS
		),
		shiftDuration = Config.SHIFT_DURATION + ShopDefs.valueOf("shift", upgrades.shift or 0),
		orderPatience = Config.ORDER_PATIENCE
			+ ShopDefs.valueOf("patience", upgrades.patience or 0),
		-- Applied to CASH at payout, never to score. Score stays comparable
		-- between players; what it is worth does not.
		--
		-- Boosts are read HERE, at the start of the shift, rather than at
		-- payout: a boost that runs out with ten seconds of cooking left
		-- should still pay for the shift it was there for. A ninety second
		-- shift cannot be stretched far enough for that to be worth gaming.
		cashMultiplier = 1 + ShopDefs.valueOf("tips", upgrades.tips or 0) + earningsBoost,

		-- Flat cash per order served, on top of the score payout. Zero unless
		-- a tip boost is running.
		tipPerOrder = if tipBoost then Config.TIP_BOOST_PER_ORDER else 0,

		hypeByPhase = hypeByPhase,
		weather = conditions.weather,

		-- A menu full of greasy wrappers really does bury you in trash.
		tagCounts = HypeDefs.tagCounts(defs),
	}
end

local function onStartShift(player: Player, chosenMenu: any)
	local kitchen = kitchens[player]
	if not kitchen then
		return
	end

	if kitchen.state == "Results" then
		kitchen:closeResults()
	elseif kitchen.state == "Idle" then
		local loadout = loadoutFor(player, if typeof(chosenMenu) == "table" then chosenMenu else nil)
		kitchen:startShift(loadout)

		-- Today's menu becomes tomorrow's repeat penalty. Recorded at the
		-- START of the shift so quitting halfway does not dodge it.
		DataService.update(player, function(data)
			-- Newest first, trimmed to the staleness window.
			table.insert(data.recentMenus, 1, table.clone(loadout.menu))
			while #data.recentMenus > Config.MENU_STALE_DAYS do
				table.remove(data.recentMenus)
			end
		end)
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

	elseif action == "claimDaily" then
		-- Claiming a finished daily task. The index is the only thing the
		-- client sends; everything about whether it is claimable, and what it
		-- pays, is decided here.
		local index = payload.index
		if typeof(index) ~= "number" then
			return
		end
		index = math.floor(index)

		-- Annotated because --!strict would otherwise infer `nil` from the
		-- initialiser and object to the assignment inside the closure.
		local prize: any = nil
		DataService.update(player, function(data)
			DailyDefs.ensureToday(data.daily)

			local task = data.daily.tasks[index]
			if not task or task.claimed or not DailyDefs.isComplete(task) then
				return
			end

			-- Marked claimed BEFORE the payout is recorded, so two clicks
			-- arriving together cannot both pass the check above.
			task.claimed = true
			data.daily.claimedToday = (data.daily.claimedToday or 0) + 1

			prize = DailyDefs.rollPrize()
			if prize.kind == "cash" then
				data.cash += prize.amount
			elseif prize.kind == "boost" then
				DailyDefs.grantBoost(data.boosts, prize)
			end
		end)

		if prize then
			-- The serial is what lets the client tell a NEW win from the same
			-- win arriving in the next ten snapshots. Without it the prize
			-- popup would either flicker forever or need its own remote.
			kitchen.prizeSerial = (kitchen.prizeSerial or 0) + 1
			kitchen.lastPrize = {
				serial = kitchen.prizeSerial,
				name = prize.name,
				kind = prize.kind,
				effect = prize.effect,
				amount = prize.amount,
				value = prize.value,
				seconds = prize.seconds,
			}
			DataService.save(player)
		end
		pushSnapshot(player)
		return

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

				-- Boost timers run here rather than off wall-clock stamps, so
				-- they only burn while the player is actually in the game.
				--
				-- Routed through DataService.update so the profile is marked
				-- dirty as it burns down. Mutating it directly would leave the
				-- last SAVED value at the full duration, and relogging would
				-- hand the boost back at full length, over and over.
				if boostRunning(player) then
					DataService.update(player, function(data)
						DailyDefs.tickBoosts(data.boosts, interval)
					end)
				end

				-- A shift that just ended pays into the profile. Doing it here
				-- rather than inside Kitchen keeps the gameplay state machine
				-- unaware of saving.
				if before == "Service" and kitchen.state == "Results" then
					-- Score is the skill number and stays big; cash is what
					-- that skill is worth, and is deliberately a fraction.
					--
					-- Tips are added AFTER the multiplier rather than inside
					-- it. They are already a flat per-order bonus, and running
					-- them through an earnings boost as well would make two
					-- prizes that stack quietly worth far more than either
					-- reads.
					local earned = math.floor(
						kitchen.score
							* kitchen.loadout.cashMultiplier
							* Config.CASH_PER_POINT
						+ 0.5) + (kitchen.tips or 0)
					kitchen.lastEarned = earned

					DataService.update(player, function(data)
						data.cash += earned
						data.stats.shifts += 1
						data.stats.served += kitchen.stats.served
						data.stats.bestScore = math.max(data.stats.bestScore, kitchen.score)
						data.day += 1

						-- Every ordinary shift counts towards the daily tasks.
						-- ensureToday first, so a shift finished just after
						-- midnight lands on the new day's list rather than
						-- topping up a list that is about to be thrown away.
						DailyDefs.ensureToday(data.daily)
						DailyDefs.applyShift(
							data.daily, kitchen.stats, kitchen.score, kitchen.bestCombo)
					end)

					-- A finished day gets fresh weather tomorrow.
					dayConditions[player] = nil
					DataService.save(player)
				end
				-- Idle kitchens have nothing moving; skip the traffic unless
				-- the state just changed.
				--
				-- A running boost is the exception. Its clock keeps ticking
				-- between shifts, which is exactly when someone is most likely
				-- watching it, and with no snapshot the countdown would sit
				-- frozen on screen while the server quietly burned it down.
				-- Once a second is enough for a mm:ss readout.
				if kitchen.state ~= "Idle" or before ~= "Idle" then
					pushSnapshot(player)
				elseif boostRunning(player) then
					local last = lastIdlePush[player] or 0
					if os.clock() - last >= 1 then
						lastIdlePush[player] = os.clock()
						pushSnapshot(player)
					end
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

	-- Profiles load asynchronously. An idle kitchen never pushes on its own,
	-- so without this the client would sit on a profile-less snapshot.
	DataService.onLoaded = pushSnapshot

	Remotes.StartShift.OnServerEvent:Connect(onStartShift)
	Remotes.StationAction.OnServerEvent:Connect(onStationAction)

	startTickLoop()
end

return ShiftService

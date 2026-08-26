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
local OfflineDefs = require(Shared.OfflineDefs)

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

-- Each player's conditions for today, rolled once and held until the shift is
-- played. Declared up here with the other registries because settleShift
-- clears it and is defined long before conditionsFor fills it.
local dayConditions: { [Player]: any } = {}

-- Whether anything is currently counting down for this player.
local function boostRunning(player: Player): boolean
	local profile = DataService.get(player)
	local earnings, tips = DailyDefs.boostValues(profile and profile.boosts)
	return earnings > 0 or tips
end

-- Everything a finished shift does to a profile: pay it, count it, advance the
-- day, feed the daily tasks.
--
-- Lifted out of the tick loop so the skip command can finish a shift down this
-- exact path. A second copy of it would be a second thing to keep in step, and
-- the one most likely to drift is the one only used in testing.
local function settleShift(player: Player, kitchen)
	-- Score is the skill number and stays big; cash is what that skill is
	-- worth, and is deliberately a fraction.
	--
	-- Tips are added AFTER the multiplier rather than inside it. They are
	-- already a flat per-order bonus, and running them through an earnings
	-- boost as well would make two prizes that stack quietly worth far more
	-- than either one reads.
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

		-- Newest first, trimmed. This average is what the understudy is paid a
		-- fraction of, so it has to be recorded here, on the way out of a real
		-- shift.
		table.insert(data.recentEarnings, 1, earned)
		while #data.recentEarnings > Config.OFFLINE_RECENT_SHIFTS do
			table.remove(data.recentEarnings)
		end

		-- Every ordinary shift counts towards the daily tasks. ensureToday
		-- first, so a shift finished just after midnight lands on the new day's
		-- list rather than topping up a list about to be thrown away.
		DailyDefs.ensureToday(data.daily)
		DailyDefs.applyShift(
			data.daily, kitchen.stats, kitchen.score, kitchen.bestCombo)
	end)

	-- A finished day gets fresh weather tomorrow.
	dayConditions[player] = nil
	DataService.save(player)
end

-- What the understudy earned while the player was away, banked for collection.
--
-- Normally runs once, from onLoaded: that is the first moment the saved
-- lastSeen can be read and the last moment before the next save overwrites it.
-- The `away` debug command rewinds lastSeen and calls it again, so testing goes
-- down this same path rather than a shortcut that could drift from it.
--
-- `force` is only ever passed by that command. It waives the temporary-profile
-- guard, because Studio without API access is precisely where this needs
-- testing and is also the one place every profile is temporary.
local function settleOffline(player: Player, force: boolean?): boolean
	-- Every way this can decline says so out loud while debug LOGGING is on --
	-- which is deliberately a separate flag from the cheats, so the reasons
	-- survive a playtest run the way a player would run it. It used to return
	-- silently from five different places, which made "no report appeared"
	-- indistinguishable from "the feature is broken", and the commonest causes
	-- are environmental rather than bugs.
	local function decline(reason: string): boolean
		if Config.DEBUG_LOGGING then
			warn(("[offline] nothing for %s: %s"):format(player.Name, reason))
		end
		return false
	end

	local profile = DataService.get(player)
	if not profile then
		return decline("profile is not loaded yet")
	end

	local lastSeen = profile.lastSeen or 0
	if lastSeen <= 0 then
		return decline(
			"this profile has never been saved, so there is no stamp to measure "
				.. "from. Expected once, on the first return after the feature "
				.. "shipped -- it will work on the return after this one.")
	end

	-- A temporary profile is skipped for a sharper reason than the rest: its
	-- real save could not be loaded, so paying it out would invent cash against
	-- a profile we already know not to trust. It is also why the debug command
	-- can waive this and nothing else can.
	if not force and DataService.isTemporary(player) then
		return decline(
			"profile is TEMPORARY -- the real save could not be loaded, so "
				.. "nothing here is trusted and lastSeen is never written. Turn on "
				.. "Experience Settings > Security > Enable Studio Access to API "
				.. "Services, and open the PUBLISHED place.")
	end

	local away = os.time() - lastSeen
	if away <= 0 then
		return decline("no time has passed since the last save")
	end

	local report = OfflineDefs.accrue(profile, away)
	if report.amount <= 0 then
		local perShift = OfflineDefs.perShift(profile.recentEarnings)
		local detail = if perShift <= 0
			then "no finished shifts on record, so there is no recording to play "
				.. "back. Play a shift through to the results screen first."
			else ("under the %s minimum for one run."):format(
				OfflineDefs.formatSpan(OfflineDefs.secondsPerShift()))

		return decline(("away %s, average shift %d c -- %s"):format(
			OfflineDefs.formatSpan(away), math.floor(perShift), detail))
	end

	DataService.update(player, function(data)
		OfflineDefs.addPending(data.pendingOffline, report)
	end)

	if Config.DEBUG_LOGGING then
		print(("[offline] %s was away %s: %d c banked"):format(
			player.Name, OfflineDefs.formatSpan(report.seconds), report.amount))
	end
	return true
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

			-- What the understudy banked while they were away, waiting to be
			-- collected. Zero means the collect screen stays shut.
			pendingOffline = profile.pendingOffline,
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

-- Rolled once and held until the shift is played. Rolling fresh on every draft
-- screen redraw would let a player reroll the weather by closing and reopening
-- it until they liked what they saw.
function conditionsFor(player: Player)
	local profile = DataService.get(player)

	local existing = dayConditions[player]
	if existing then
		-- Only the WEATHER has to be frozen -- that is what stops a player
		-- rerolling it by closing and reopening the draft. The day is just a
		-- label and is read live, so it corrects itself the moment the profile
		-- arrives rather than staying wrong for the session.
		existing.day = (profile and profile.day) or existing.day
		return existing
	end

	local rng = Random.new()
	local weather = HypeDefs.rollWeather(rng)

	local conditions = {
		day = (profile and profile.day) or 1,
		weather = weather.id,
		weatherName = weather.name,
		weatherBlurb = weather.blurb,
	}

	-- Not remembered until there IS a profile. The first snapshot goes out on
	-- join, before the save has loaded, and caching then froze "DAY 1" over a
	-- returning player's real day for the whole session -- along with a weather
	-- roll made before anyone could see it.
	if profile then
		dayConditions[player] = conditions
	end
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

	-- The unlocked count and slot count go in so staleness can cap itself and
	-- always leave a draftable fresh menu. `allowed` was built from the same
	-- list above, so #unlocked is what the player can actually choose from.
	local unlocked = unlockedMenu(profile)
	local stale = HypeDefs.staleSet(
		profile and profile.recentMenus, #unlocked, slots)
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

	elseif action == "endShift" then
		-- Testing only. Ends the running shift immediately, paying out exactly
		-- as if the clock had run down -- which is the point: it is for
		-- reaching the results screen and the daily task progress quickly,
		-- not for skipping either.
		if not Config.DEBUG_COMMANDS then
			return
		end
		kitchen:endShiftNow()
		pushSnapshot(player)
		return

	elseif action == "grantBoost" then
		-- Testing only. Starts a boost without waiting on a daily task and a
		-- lucky roll, which is otherwise the only way to see one.
		if not Config.DEBUG_COMMANDS then
			return
		end

		local effect = if payload.effect == "tips" then "tips" else "earnings"
		local seconds = if typeof(payload.seconds) == "number"
			then math.clamp(payload.seconds, 5, 3600)
			else Config.BOOST_SECONDS

		DataService.update(player, function(data)
			DailyDefs.grantBoost(data.boosts, {
				kind = "boost",
				effect = effect,
				seconds = seconds,
				-- Mid-range rather than random, so a test run is repeatable.
				value = if effect == "earnings" then 0.20 else nil,
			})
		end)

		DataService.save(player)
		pushSnapshot(player)
		return

	elseif action == "skipShift" then
		-- Testing. Puts a finished shift on the books without cooking one, so
		-- everything downstream of "has played" can be reached quickly: the
		-- day counter, staleness, daily task progress, and the earnings
		-- average the understudy is paid a fraction of.
		--
		-- Backspace was the alternative and it is the wrong tool: it ends a
		-- shift where it stands, which for an untouched one means a score of
		-- zero, and a run of zeroes drags that average to nothing.
		if not Config.DEBUG_COMMANDS then
			return
		end

		local count = if typeof(payload.count) == "number"
			then math.clamp(math.floor(payload.count), 1, 20)
			else 1

		for _ = 1, count do
			if kitchen.state == "Results" then
				kitchen:closeResults()
			end
			if kitchen.state ~= "Idle" then
				-- Mid-shift: settle what is really there rather than
				-- overwriting it, so this never destroys a run in progress.
				kitchen:endShiftNow()
				kitchen:tick()
				if kitchen.state == "Results" then
					settleShift(player, kitchen)
					kitchen:closeResults()
				end
			end

			local loadout = loadoutFor(player, nil)
			kitchen:startShift(loadout)

			-- Same record onStartShift keeps, so skipped days age the menu
			-- exactly as played ones do. Without this, skipping forward would
			-- never make anything stale and staleness could not be tested by
			-- the one command built for skipping forward.
			DataService.update(player, function(data)
				table.insert(data.recentMenus, 1, table.clone(loadout.menu))
				while #data.recentMenus > Config.MENU_STALE_DAYS do
					table.remove(data.recentMenus)
				end
			end)

			kitchen:debugFinishShift()
			settleShift(player, kitchen)
			kitchen:closeResults()
		end

		kitchen:drainEvents()
		pushSnapshot(player)
		return

	elseif action == "offlineStatus" then
		-- Read-only. Prints every input the understudy reads, so a return that
		-- paid nothing can be diagnosed without leaving and coming back to
		-- reproduce it.
		--
		-- Gated on LOGGING rather than COMMANDS, so it survives a realistic
		-- playtest with the cheats switched off -- which is exactly the run
		-- where a silent failure is most expensive and least reproducible.
		if not Config.DEBUG_LOGGING then
			return
		end

		local profile = DataService.get(player)
		if not profile then
			warn("[offline] no profile loaded")
			return
		end

		local lastSeen = profile.lastSeen or 0
		local away = if lastSeen > 0 then os.time() - lastSeen else -1
		local perShift = OfflineDefs.perShift(profile.recentEarnings)
		local pending = profile.pendingOffline or {}

		print(("[offline] ---- %s ----"):format(player.Name))
		print(("  profile        %s"):format(
			if DataService.isTemporary(player)
				then "TEMPORARY (will never pay out or save lastSeen)"
				else "saving normally"))
		print(("  lastSeen       %s"):format(
			if lastSeen > 0
				then ("%d, %s ago"):format(lastSeen, OfflineDefs.formatSpan(math.max(away, 0)))
				else "never written -- nothing to measure from yet"))
		print(("  recent shifts  %s  (average %d c)"):format(
			table.concat(profile.recentEarnings or {}, ", "), math.floor(perShift)))
		print(("  one run needs  %s"):format(
			OfflineDefs.formatSpan(OfflineDefs.secondsPerShift())))
		print(("  cell holds     %d hours"):format(OfflineDefs.capHours(profile)))
		print(("  waiting now    %d c"):format(pending.amount or 0))

		if away > 0 then
			local would = OfflineDefs.accrue(profile, away)
			print(("  that gap pays  %d c"):format(would.amount))
		end
		return

	elseif action == "away" then
		-- Testing. Rewinds the clock on this profile and settles the gap
		-- exactly as a real return would, rather than fabricating a payout --
		-- so what this produces is what a genuine absence produces.
		if not Config.DEBUG_COMMANDS then
			return
		end

		local hours = if typeof(payload.hours) == "number"
			then math.clamp(payload.hours, 0.05, 48)
			else 8

		DataService.update(player, function(data)
			data.lastSeen = os.time() - math.floor(hours * 3600)
		end)

		if not settleOffline(player, true) then
			-- Silence here would look like a broken command, when it usually
			-- means the profile simply has no recording to play back yet.
			warn(("[AFC] /away earned %s nothing: the understudy copies your "
				.. "last shifts, so finish one first (Backspace ends a shift).")
				:format(player.Name))
		end

		pushSnapshot(player)
		return

	elseif action == "collectOffline" then
		-- The amount was decided on load and has been sitting in the profile
		-- since. Nothing about it is taken from the client here.
		local collected = 0
		DataService.update(player, function(data)
			local pending = data.pendingOffline
			collected = pending.amount or 0
			if collected > 0 then
				data.cash += collected
				OfflineDefs.clearPending(pending)
			end
		end)

		if collected > 0 then
			DataService.save(player)
		end
		pushSnapshot(player)
		return

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
					settleShift(player, kitchen)
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
	--
	-- It is also the first moment the saved lastSeen exists, which makes it the
	-- only place the time away can be measured.
	DataService.onLoaded = function(player: Player)
		-- The snapshot goes out whatever happens to the settling.
		--
		-- These ran in sequence, unprotected, and an error inside settleOffline
		-- took the push down with it -- so the client sat on the profile-less
		-- snapshot it got on join: no cash, no daily tasks, and no collect
		-- screen even for earnings already banked and waiting. A bug in one
		-- feature should not blank the rest of them.
		local ok, err = pcall(settleOffline, player)
		if not ok then
			warn("[offline] settling failed for " .. player.Name .. ": " .. tostring(err))
		end
		pushSnapshot(player)
	end

	Remotes.StartShift.OnServerEvent:Connect(onStartShift)
	Remotes.StationAction.OnServerEvent:Connect(onStationAction)

	startTickLoop()
end

return ShiftService

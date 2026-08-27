--!strict
-- Client entry point: input in, snapshots out to the scene and the HUD.
--
-- The client is deliberately dumb. It never decides whether a key was correct,
-- never grades a dish, never runs a timer that matters. It sends intents and
-- draws whatever the server last told it.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DishDefs = require(Shared.DishDefs)
local Remotes = require(Shared.Remotes)

local Audio = require(script.Parent.Audio)
local Scene = require(script.Parent.Scene)
local Customers = require(script.Parent.Customers)
local FoodStack = require(script.Parent.FoodStack)
local Loading = require(script.Parent.Loading)
local Settings = require(script.Parent.Settings)
local SettingsUI = require(script.Parent.SettingsUI)
local ShopUI = require(script.Parent.ShopUI)
local DraftUI = require(script.Parent.DraftUI)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local snapshot: any = nil

-- Nothing accepts input until the avatar pool is built and preloaded.
local ready = false

-- Ceiling on how long we will wait for the server. If the pool never
-- finishes, the game opens anyway with the procedural fallback rather than
-- stranding the player on a loading screen.
local BOOT_TIMEOUT = 30

-- Tracks whether the combo has already topped out this streak, so the max-combo
-- sting fires on the way up and not on every serve afterwards.
local comboWasMaxed = false

-- The menu drafted for the next shift. Empty means "whatever I own", which is
-- what a player who has not opened the draft screen gets.
local draftMenu: { string } = {}

-- Declared up here so every callback below closes over these locals rather
-- than over globals that do not exist yet. All three are assigned further
-- down, after the UI they depend on has been built.
--
-- `refs` in particular: onStart is defined above UI.build but has to ask
-- whether the daily panel is open, and a local declared after its reader
-- resolves to a nil global at runtime rather than failing to compile.
local shop
local draft
local refs

-- ----------------------------------------------------------------- scene ---

Scene.applyLighting()
local scene = Scene.build()
Scene.lockCamera()
Scene.parkCharacter()

FoodStack.init(scene)
Audio.init()

-- --------------------------------------------------------------- intents ---

local function sendAction(payload)
	Remotes.StationAction:FireServer(payload)
end

local function onKey(key: string)
	if not snapshot or snapshot.state ~= "Service" then
		return
	end
	sendAction({ action = "ingredient", key = key })
end

local function onSelect(slot: number)
	sendAction({ action = "select", slot = slot })
end

-- Clicking a customer's ticket picks up that order, which is how you reach one
-- that is not simply next in line.
local function onSelectOrder(orderId: number)
	sendAction({ action = "selectOrder", orderId = orderId })
end

-- Initialised here rather than with the other subsystems: it needs the click
-- handler above, which needs sendAction.
Customers.init(scene, onSelectOrder)

local function onServe()
	sendAction({ action = "serve" })
end

local function onScrap()
	sendAction({ action = "scrap" })
end

-- Testing: end the running shift immediately. The server decides whether to
-- honour it -- see Config.DEBUG_COMMANDS -- so leaving this bound in a release
-- build does nothing.
--
-- Declared above handleInput because that is what calls it, and a local
-- declared after its caller resolves to a nil global at runtime.
local function endShiftNow()
	sendAction({ action = "endShift" })
end

-- Testing: start a boost without waiting on a lucky prize roll. Server-gated
-- on Config.DEBUG_COMMANDS like the rest.
local function grantBoost(effect: string, seconds: number?)
	sendAction({ action = "grantBoost", effect = effect, seconds = seconds })
end

-- Testing: pretend the last few hours happened without you. The server rewinds
-- this profile and settles the gap down the real return path, so the collect
-- screen shows what a genuine absence would have shown.
local function simulateAway(hours: number?)
	sendAction({ action = "away", hours = hours })
end

-- Testing: bank a finished shift without cooking one. Unlike ending a shift
-- early, this scores a competent day rather than a zero, so it can be used to
-- reach anything that reads recent earnings.
local function skipShift(count: number?)
	sendAction({ action = "skipShift", count = count })
end

-- Testing: dump every input the understudy reads, to Output. Read-only, so it
-- can be run mid-diagnosis without changing what is being diagnosed.
local function offlineStatus()
	sendAction({ action = "offlineStatus" })
end

-- Outside a shift, E opens the draft rather than starting immediately: the
-- menu is the first decision of the day, not a detail to skip past. From the
-- results screen it still just means "continue".
local function onStart()
	if not ready then
		return
	end

	-- Any open panel eats the key, closing itself and nothing else.
	--
	-- Each of these absorbs MOUSE clicks on its own, but a panel teaches the
	-- keyboard nothing, and outside a shift E means "start the day" -- so
	-- without this it fires straight through and starts a shift under the
	-- panel the player is still reading. Anything modal added later belongs in
	-- this list.
	-- The offline report is the exception: it has no dismiss, only a COLLECT
	-- button, so E must do nothing at all rather than closing it.
	if UI.isOfflineOpen(refs) then
		return
	end
	if UI.isDailyOpen(refs) then
		UI.setDailyOpen(refs, false)
		return
	end
	if ShopUI.isOpen(shop) then
		ShopUI.setOpen(shop, false)
		return
	end

	if snapshot and snapshot.state == "Idle" then
		if DraftUI.isOpen(draft) then
			DraftUI.setOpen(draft, false)
		else
			DraftUI.seed(draft, snapshot.profile)
			DraftUI.render(draft, snapshot.profile)
			DraftUI.setOpen(draft, true)
		end
		return
	end
	Remotes.StartShift:FireServer(draftMenu)
end

refs = UI.build(playerGui, {
	onKey = onKey,
	onServe = onServe,
	onScrap = onScrap,
	onSelect = onSelect,
	onStart = onStart,
	onChore = function()
		sendAction({ action = "chore" })
	end,
	onOpenShop = function()
		-- Rendered on the way open, since it is no longer redrawn while shut.
		ShopUI.render(shop, snapshot and snapshot.profile)
		ShopUI.setOpen(shop, true)
	end,
	onClaimDaily = function(index)
		sendAction({ action = "claimDaily", index = index })
	end,
	onCollectOffline = function()
		sendAction({ action = "collectOffline" })
	end,
})

SettingsUI.build(playerGui)

shop = ShopUI.build(playerGui, function(kind, id)
	sendAction({ action = "buy", kind = kind, id = id })
end)

draft = DraftUI.build(playerGui, function(menu)
	draftMenu = menu
	DraftUI.setOpen(draft, false)
	Remotes.StartShift:FireServer(menu)
end)

-- Push preference changes to the profile. Debounced by the fact that the panel
-- only fires on an actual change.
Settings.onChanged = function()
	sendAction({ action = "settings", values = Settings.values })
end

-- ----------------------------------------------------------------- input ---

local INGREDIENT_KEYS = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.G] = "G",
}

-- 1-4 picks up the ticket in that slot.
local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

-- The sear key for whatever is currently in hand, or nil. Only live once the
-- prep steps are done and the grill has not been used yet.
local function searKeyFor(snap): string?
	if not snap or not snap.activeOrderId then
		return nil
	end
	for _, order in snap.orders do
		if order.id == snap.activeOrderId then
			if order.searState ~= "waiting" and order.searState ~= "searing" then
				return nil
			end
			if #snap.build < #order.required then
				return nil   -- still prepping
			end
			local dish = DishDefs.get(order.dishId)
			return dish and dish.sear and dish.sear.key or nil
		end
	end
	return nil
end

local function handleInput(_actionName: string, inputState: Enum.UserInputState, input: InputObject)
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	if not ready then
		return Enum.ContextActionResult.Sink
	end

	local keyCode = input.KeyCode
	local inService = snapshot ~= nil and snapshot.state == "Service"

	-- Searing is the one action that cares about the key coming back UP: the
	-- meter runs while it is held and the grade is decided by where it is when
	-- you let go.
	if inService and INGREDIENT_KEYS[keyCode] and searKeyFor(snapshot) == INGREDIENT_KEYS[keyCode] then
		if inputState == Enum.UserInputState.Begin then
			sendAction({ action = "searStart" })
		elseif inputState == Enum.UserInputState.End then
			sendAction({ action = "searEnd" })
		end
		return Enum.ContextActionResult.Sink
	end

	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	-- Testing: F7 and F8 start a boost. Function keys because they collide with
	-- nothing, in or out of a shift, so they work on either screen. The server
	-- ignores both unless Config.DEBUG_COMMANDS is on.
	-- Testing keys. Checked client-side as well as server-side so that a
	-- playtest run with the cheats off is genuinely untouched by them, rather
	-- than quietly firing remotes the server throws away.
	if Config.DEBUG_COMMANDS then
		if keyCode == Enum.KeyCode.F7 then
			grantBoost("earnings")
			return Enum.ContextActionResult.Sink
		elseif keyCode == Enum.KeyCode.F8 then
			grantBoost("tips")
			return Enum.ContextActionResult.Sink
		elseif keyCode == Enum.KeyCode.F6 then
			-- A full night away. F6 rather than F9, which Studio takes for the
			-- developer console.
			simulateAway(8)
			return Enum.ContextActionResult.Sink
		elseif keyCode == Enum.KeyCode.F5 then
			skipShift(1)
			return Enum.ContextActionResult.Sink
		end
	end

	-- E doubles as an ingredient key during service and as the start/continue
	-- key outside it. Gating on state keeps both bindings clean.
	if not inService then
		if keyCode == Enum.KeyCode.E then
			onStart()
		end
		return Enum.ContextActionResult.Sink
	end

	if keyCode == Enum.KeyCode.Backspace then
		-- Testing: end the shift now. Backspace because nothing else uses it
		-- and it is nowhere near the cooking keys, so it cannot be hit by
		-- accident mid-order. Gated server-side on Config.DEBUG_COMMANDS.
		endShiftNow()
	elseif keyCode == Enum.KeyCode.C then
		-- Clears whatever chore is up. Its own key so it never collides with an
		-- ingredient on whatever dish happens to be in hand.
		sendAction({ action = "chore" })
	elseif keyCode == Enum.KeyCode.Space then
		onServe()
	elseif keyCode == Enum.KeyCode.X then
		onScrap()
	elseif SLOT_KEYS[keyCode] then
		onSelect(SLOT_KEYS[keyCode])
	elseif INGREDIENT_KEYS[keyCode] then
		onKey(INGREDIENT_KEYS[keyCode])
	end

	return Enum.ContextActionResult.Sink
end

local BOUND_KEYS = {
	Enum.KeyCode.Q, Enum.KeyCode.W, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.T,
	Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.F, Enum.KeyCode.G,
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Space, Enum.KeyCode.X, Enum.KeyCode.C,
	Enum.KeyCode.Backspace,
	Enum.KeyCode.F5, Enum.KeyCode.F6, Enum.KeyCode.F7, Enum.KeyCode.F8,
}

-- Sinking Space also stops the character jumping under the UI, which is what
-- we want -- this is a fixed-camera screen, not a platformer.
ContextActionService:BindAction("AFC_Input", handleInput, false, table.unpack(BOUND_KEYS))

-- The same testing command in the chat box, for when a key is awkward -- on a
-- phone, or with the panel focus somewhere unhelpful.
--
-- Registered inside a pcall because TextChatCommand only exists under the
-- current TextChatService. A place still on the legacy chat would throw here,
-- and a debug convenience must never be the thing that stops the client
-- booting. Backspace still works either way.
if Config.DEBUG_COMMANDS or Config.DEBUG_LOGGING then
	task.spawn(function()
		local ok, err = pcall(function()
			local TextChatService = game:GetService("TextChatService")

			local function register(name: string, alias: string, short: string?, run)
				local command = Instance.new("TextChatCommand")
				command.Name = name
				command.PrimaryAlias = alias
				if short then
					command.SecondaryAlias = short
				end
				command.Triggered:Connect(run)
				command.Parent = TextChatService
			end

			-- Read-only, so it belongs with the logging rather than the cheats
			-- and survives a playtest run with the cheats switched off.
			if Config.DEBUG_LOGGING then
				register("OfflineStatusCommand", "/offline", nil, offlineStatus)
			end

			if not Config.DEBUG_COMMANDS then
				return
			end

			register("EndShiftCommand", "/endshift", "/es", endShiftNow)

			-- Triggered passes (textSource, message), where message is the whole
			-- line including the alias. Everything after it is the argument, so
			-- "/boost tips 60" is a tip boost for a minute.
			-- "/away 8" is eight hours. Fractions work, so "/away 0.5" is half
			-- an hour, which is the quickest way to see a small report.
			register("AwayCommand", "/away", "/a", function(_source, message)
				local words = string.split(message or "", " ")
				simulateAway(tonumber(words[2]))
			end)

			-- "/skip 5" banks five finished shifts, which is five days of the
			-- staleness history and five contributions to the daily tasks.
			register("SkipCommand", "/skip", "/s", function(_source, message)
				local words = string.split(message or "", " ")
				skipShift(tonumber(words[2]))
			end)

			register("BoostCommand", "/boost", "/b", function(_source, message)
				local words = string.split(message or "", " ")
				local effect = words[2]
				local seconds = tonumber(words[3])
				grantBoost(
					if effect == "tips" or effect == "tip" then "tips" else "earnings",
					seconds)
			end)
		end)
		if not ok then
			warn("[AFC] chat commands unavailable, use Backspace / F7 / F8: " .. tostring(err))
		end
	end)
end

-- ---------------------------------------------------------------- events ---

-- Events ride inside the snapshot, so they are guaranteed to be handled before
-- the state they describe is drawn. Order matters: the plate has to know it
-- was SERVED before it sees an empty build list, or it plays the wrong exit.
local function handleEvent(event)
	local kind = event.type

	if kind == "ingredientAdded" then
		UI.pulseKey(refs, event.key, true)
		Audio.play("click")

	elseif kind == "fumble" then
		UI.pulseKey(refs, event.key, false)
		Scene.shake(0.12, 0.18)
		Audio.play("fumble")

	elseif kind == "graded" then
		UI.flashGrade(refs, event)
		-- The grade goes straight through: the customer picks their own
		-- reaction face from it, so Perfect and Sloppy do not look identical.
		Customers.markExit(event.orderId, event.grade)

		if event.grade == "Fail" then
			FoodStack.dump()
			Audio.play("wrongOrder")
		else
			FoodStack.serve()
			Audio.play("serveSuccess")
			if event.grade == "Perfect" then
				Scene.shake(0.35, 0.22)
			end
		end

		-- Only when the streak actually tops out, and only on the way up --
		-- otherwise it retriggers on every serve for the rest of the round.
		local atMax = event.comboMult >= Config.COMBO_MAX
		if atMax and not comboWasMaxed then
			Audio.play("maxCombo")
		end
		comboWasMaxed = atMax

	elseif kind == "expired" then
		UI.flash(refs, "WALKED OUT", UI.COLOR.bad)
		Customers.markExit(event.orderId, "Expired")
		Audio.play("wrongOrder")
		comboWasMaxed = false

	elseif kind == "scrapped" then
		-- Switching tickets abandons the plate, same as scrapping it. Showing
		-- the food hit the floor makes that cost legible instead of silent.
		FoodStack.dump()

	elseif kind == "cookStarted" then
		-- The moment the basket goes in, not the whole cook.
		Audio.play("frying")

	elseif kind == "searStarted" then
		Audio.play("sizzle")

	elseif kind == "choreFailed" then
		UI.flash(refs, "CHORE MISSED", UI.COLOR.bad)
		Audio.play("wrongOrder")
		Scene.shake(0.2, 0.2)
		comboWasMaxed = false

	elseif kind == "orderArrived" then
		Audio.play("ticketArrive")

	elseif kind == "shiftStarted" then
		Customers.clear()
		FoodStack.clear()
		comboWasMaxed = false
		Audio.startMusic()

	elseif kind == "shiftEnded" then
		Customers.clear()
		FoodStack.clear()
		comboWasMaxed = false
		Audio.play("roundComplete")
	end
end

Remotes.ShiftUpdate.OnClientEvent:Connect(function(newSnapshot)
	if newSnapshot.events then
		for _, event in newSnapshot.events do
			handleEvent(event)
		end
	end

	snapshot = newSnapshot

	if newSnapshot.profile then
		Settings.apply(newSnapshot.profile.settings)
	end

	-- Panels are only redrawn while they are actually on screen.
	--
	-- Both of these ran on every snapshot, ten times a second, whether open or
	-- not. The shop walks nineteen rows setting text and colours; the draft
	-- screen is worse -- it evaluates the whole menu once PER PHASE and builds
	-- the reason strings -- and all of it was being thrown away unseen. Each
	-- opens by rendering itself first, so nothing is ever shown stale.
	if ShopUI.isOpen(shop) then
		ShopUI.render(shop, newSnapshot.profile)
	end

	if newSnapshot.state == "Idle" then
		if DraftUI.isOpen(draft) then
			DraftUI.render(draft, newSnapshot.profile)
		end
	else
		DraftUI.setOpen(draft, false)
	end

	UI.render(refs, snapshot)
	Customers.sync(snapshot)
	FoodStack.sync(snapshot.build)
end)

RunService.RenderStepped:Connect(function(dt)
	UI.renderTimers(refs, snapshot)
	Customers.update(dt, snapshot)
end)

-- Full-screen game: get the default Roblox chrome out of the way.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Ask for current state now that the handlers above are connected.
sendAction({ action = "sync" })

-- ------------------------------------------------------------------ boot ---

-- Holds the game shut until the customer rigs exist AND their meshes and
-- textures are resident. Skipping either half is what made the first
-- customers of a session show up as fallback blobs.
local function boot()
	local loading = Loading.show(playerGui)

	Loading.setStatus(loading, "contacting the station", 0.05)

	local folder = ReplicatedStorage:WaitForChild("CustomerRigs", 15)

	if folder then
		local deadline = os.clock() + BOOT_TIMEOUT

		while not folder:GetAttribute("Ready") and os.clock() < deadline do
			local built = folder:GetAttribute("Built") or 0
			local total = math.max(folder:GetAttribute("Total") or 1, 1)
			Loading.setStatus(
				loading,
				("processing arrivals   %d"):format(built),
				0.1 + 0.55 * math.min(built / math.max(total, 1), 1)
			)
			task.wait(0.1)
		end

		-- PreloadAsync is the part that actually matters: without it the rigs
		-- exist but stream in grey and untextured on first sight.
		local rigs = folder:GetChildren()
		if #rigs > 0 then
			Loading.setStatus(loading, "loading appearances", 0.7)
			pcall(function()
				ContentProvider:PreloadAsync(rigs)
			end)
		else
			warn("[AlienFoodCourt] no rigs available at boot -- using procedural fallback")
		end
	else
		warn("[AlienFoodCourt] CustomerRigs never appeared -- using procedural fallback")
	end

	Loading.setStatus(loading, "opening the shutters", 1)
	task.wait(0.35)

	ready = true
	Loading.finish(loading)

	-- Music from the menu onward, not just during a shift.
	Audio.startMusic()

	print("[AlienFoodCourt] client ready")
end

task.spawn(boot)
